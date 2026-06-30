#!/usr/bin/env bash
# scripts/task-dag.sh — Task DAG with DFS cycle detection + auto-unblock
# Ported from ClawTeam clawteam/store/file.py:316-344 (cycle), :362-375 (auto-unblock)
# TaskItem schema: team/models.py:124-143
#
# Uses 3-colour DFS (WHITE/GRAY/BLACK) backed by temp files + awk,
# compatible with macOS bash 3.2 (no associative arrays).
# Cycle detection uses python3 (macOS default, alios-8u CI default) for O(V+E) iterative DFS.
# Pure bash 3.2 implementation was O(n²) due to awk subprocess per node visit (R4 review).
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
TASKS_FILE="${SWARM_HOME}/.swarm/tasks.json"
LOCK_FILE="${SWARM_HOME}/.swarm/tasks.json.lock"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ensure_tasks_file() {
  if [ ! -f "$TASKS_FILE" ]; then
    mkdir -p "$(dirname "$TASKS_FILE")"
    printf '{"tasks":{}}\n' > "$TASKS_FILE"
  fi
}

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

_atomic_write() {
  local tmp="$1"
  mv "$tmp" "$TASKS_FILE"
}

# Acquire an exclusive lock before running the wrapped command, so that
# concurrent processes cannot clobber each other's read-modify-write cycles
# on tasks.json.  Uses flock when available (Linux); falls back to a
# mkdir-based lock on macOS where flock is not installed by default.
with_lock() {
  ensure_tasks_file

  if command -v flock >/dev/null 2>&1; then
    exec 200>"$LOCK_FILE"
    if ! flock -w 10 200; then
      echo "task-dag: could not acquire lock within 10s" >&2
      return 1
    fi
    local rc=0
    "$@" || rc=$?
    flock -u 200
    return $rc
  else
    local lockdir="${SWARM_HOME}/.swarm/.tasks.json.lockdir"
    local waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
      if [ "$waited" -ge 100 ]; then
        echo "task-dag: could not acquire mkdir-lock within 10s" >&2
        return 1
      fi
    done
    local rc=0
    "$@" || rc=$?
    rmdir "$lockdir"
    return $rc
  fi
}

# ---------------------------------------------------------------------------
# 3-colour DFS cycle detection
#   WHITE (0) unvisited | GRAY (1) in current path | BLACK (2) fully processed
#
# Given a *proposed* task id + its comma-separated deps, determine whether
# following the blocked_by chain from the proposed node leads back to a
# GRAY node (back edge = cycle).
#
# Implementation: single python3 invocation (O(V+E) iterative DFS).
# Bash 3.2 + awk-per-node was O(n²) subprocess overhead — 50 chained tasks
# took 26s on macOS.  Python is available on macOS 12.3+ and alios-8u CI.
# ---------------------------------------------------------------------------

detect_cycle() {
  local proposed_id="$1"
  local proposed_deps_csv="${2:-}"
  ensure_tasks_file

  # Prefer python3 (cleaner code, slightly faster for huge graphs).
  # SWARM_FORCE_JQ=1 forces the jq fallback path (used by tests).
  if [ "${SWARM_FORCE_JQ:-}" != "1" ] && command -v python3 >/dev/null 2>&1; then
    _detect_cycle_python3 "$proposed_id" "$proposed_deps_csv"
    return $?
  fi

  # Fallback: pure jq (jq is already a hard dep for this script).
  _detect_cycle_jq "$proposed_id" "$proposed_deps_csv"
  return $?
}

# python3 path: 3-color iterative DFS, O(V+E).
_detect_cycle_python3() {
  local proposed_id="$1"
  local proposed_deps_csv="$2"
  python3 - "$proposed_id" "$proposed_deps_csv" "$TASKS_FILE" <<'PYEOF'
import json, sys

proposed_id = sys.argv[1]
deps_csv = sys.argv[2]
tasks_file = sys.argv[3]

try:
    with open(tasks_file) as f:
        data = json.load(f)
except (json.JSONDecodeError, OSError) as e:
    print(f"task-dag: cannot read tasks file: {e}", file=sys.stderr)
    sys.exit(3)
tasks = data.get("tasks", {})

# Adjacency: node -> list of parents (blocked_by)
adj = {tid: list(t.get("blocked_by") or []) for tid, t in tasks.items()}
proposed_parents = [d for d in deps_csv.split(",") if d.strip()] if deps_csv else []
adj[proposed_id] = proposed_parents

# 3-color iterative DFS from proposed
WHITE, GRAY, BLACK = 0, 1, 2
color = {n: WHITE for n in adj}

def dfs(start):
    stack = [(start, iter(adj.get(start, [])))]
    color[start] = GRAY
    while stack:
        node, it = stack[-1]
        try:
            parent = next(it)
        except StopIteration:
            color[node] = BLACK
            stack.pop()
            continue
        if parent not in color:
            # Missing parent — caller catches via parent-existence check
            continue
        if color[parent] == GRAY:
            return True  # cycle
        if color[parent] == WHITE:
            color[parent] = GRAY
            stack.append((parent, iter(adj.get(parent, []))))
    return False

sys.exit(1 if dfs(proposed_id) else 0)
PYEOF
}

# jq fallback path: iterative 3-color DFS in jq.
# Cycle exists iff the augmented graph (existing tasks + {proposed_id: proposed_parents})
# contains any cycle reachable from proposed_id by walking blocked_by edges.
# Pure jq, no new deps. Exit codes match python3 path:
#   0 = no cycle, 1 = cycle, 3 = tasks file unreadable.
_detect_cycle_jq() {
  local proposed_id="$1"
  local proposed_deps_csv="$2"

  # Validate JSON is parseable.
  if ! jq -e '.tasks' "$TASKS_FILE" >/dev/null 2>&1; then
    echo "task-dag: cannot read tasks file (not valid JSON or missing .tasks)" >&2
    return 3
  fi

  # Comma-split proposed parents into a JSON array.
  local proposed_parents_json
  if [ -z "$proposed_deps_csv" ]; then
    proposed_parents_json='[]'
  else
    proposed_parents_json=$(printf '%s' "$proposed_deps_csv" \
      | jq -R 'split(",") | map(select(length > 0))')
  fi

  # 3-color DFS in jq, iterative stack:
  #   color: 0=white (unvisited), 1=gray (on current path), 2=black (done)
  #   stack entries: {node, parents_remaining: [...]}
  # We start DFS from proposed_id with proposed_parents grafted in.
  # Cycle = walk encounters a gray node.
  jq -e \
    --arg pid "$proposed_id" \
    --argjson parents "$proposed_parents_json" \
    '
      . as $root
      # Build adjacency: existing tasks blocked_by + proposed override
      | ($root.tasks | with_entries(.value = (.value.blocked_by // []))) as $baseAdj
      | ($baseAdj + {($pid): $parents}) as $adj

      # Initial state: gray = [pid], black = [], stack = [{node: pid, rem: parents}]
      | {
          color: {($pid): "gray"},
          stack: [{node: $pid, rem: $parents}],
          found: false
        }
      | until(.found or (.stack | length) == 0;
          (.stack[-1]) as $top
          | if ($top.rem | length) == 0 then
              # done with this node; mark black, pop
              .color[$top.node] = "black"
              | .stack |= .[:-1]
            else
              # examine next parent
              ($top.rem[0]) as $p
              | .stack[-1].rem = $top.rem[1:]
              | if ($adj[$p] | not) then
                  # parent does not exist in adj (caller catches via existence check) — skip
                  .
                elif .color[$p] == "gray" then
                  .found = true
                elif .color[$p] == "black" then
                  .  # already fully explored, no cycle through here
                else
                  # white: push
                  .color[$p] = "gray"
                  | .stack += [{node: $p, rem: ($adj[$p] // [])}]
                end
            end)
      | .found | not  # true if NO cycle
    ' "$TASKS_FILE" >/dev/null 2>&1
  # jq -e: exit 0 if expression yields true (no cycle), exit 1 if false (cycle).
  return $?
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_add() {
  local id="${1:?usage: add <id> <title> [--depends ID,ID] [--owner X]}"
  shift
  local title="${1:?usage: add <id> <title> [--depends ID,ID] [--owner X]}"
  shift

  local depends=""
  local owner=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --depends) depends="${2:?}"; shift 2 ;;
      --owner)   owner="${2:?}";  shift 2 ;;
      *) echo "task-dag: unknown flag: $1" >&2; return 1 ;;
    esac
  done

  # Cycle check — single python3 invocation (O(V+E) DFS)
  detect_cycle "$id" "$depends"
  local rc=$?
  case "$rc" in
    0) ;;  # no cycle, proceed
    1) echo "task-dag: cycle detected — adding $id with depends=[$depends] would create a cycle" >&2; return 1 ;;
    2) echo "task-dag: cycle detection unavailable (python3 missing) — refusing add" >&2; return 2 ;;
    3) echo "task-dag: tasks file is corrupt or unreadable — refusing add" >&2; return 3 ;;
    *) echo "task-dag: cycle detection returned unexpected code $rc" >&2; return 1 ;;
  esac

  local status blocked_by_json

  if [ -n "$depends" ]; then
    status="blocked"
    # Build JSON array in pure bash (avoids tr+jq+jq subprocess forks)
    local deps_json=""
    local OLD_IFS="$IFS"
    IFS=','
    for dep in $depends; do
      deps_json="${deps_json}\"${dep}\","
    done
    IFS="$OLD_IFS"
    blocked_by_json="[${deps_json%,}]"
  else
    status="pending"
    blocked_by_json="[]"
  fi

  # Combined: duplicate check + parent existence check + write + blocks update.
  # Single jq call replaces 4+ separate subprocess forks (was O(n) jq calls).
  # Uses jq's now|todate for timestamp (avoids date fork).
  # error() causes exit code 5 with message on stderr.
  local tmp jq_err
  tmp=$(mktemp)

  if ! jq_err=$(jq --arg id "$id" \
          --arg title "$title" \
          --arg owner "$owner" \
          --arg status "$status" \
          --argjson blocked_by "$blocked_by_json" \
          --arg deps "$depends" '
      (now | todate) as $now
      | . as $root
      | ($deps | split(",") | map(select(length > 0))) as $dl
      | [ $dl[] | select(. as $d | $root.tasks[$d] | not) ] as $miss
      | if $root.tasks[$id] then error("DUP")
        elif ($miss | length) > 0 then error("MISS:" + ($miss | first))
        else
          .tasks[$id] = {
            id: $id,
            title: $title,
            status: $status,
            blocked_by: $blocked_by,
            blocks: [],
            owner: $owner,
            created: $now,
            updated: $now
          }
          | reduce $dl[] as $dep (.;
              .tasks[$dep].blocks += [$id]
              | .tasks[$dep].blocks |= unique)
        end
      ' "$TASKS_FILE" 2>&1 >"$tmp"); then
    # jq exited non-zero — validation error
    rm -f "$tmp"
    case "$jq_err" in
      *DUP*)
        echo "task-dag: task $id already exists" >&2 ;;
      *MISS:*)
        local missing="${jq_err##*MISS:}"
        missing="${missing%%[[:space:]]*}"
        echo "task-dag: parent task $missing does not exist" >&2 ;;
      *)
        echo "task-dag: internal error" >&2 ;;
    esac
    return 1
  fi

  _atomic_write "$tmp"
  echo "added $id (status=$status)"
}

cmd_list() {
  local status_filter=""
  local owner_filter=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) status_filter="${2:?}"; shift 2 ;;
      --owner)  owner_filter="${2:?}";  shift 2 ;;
      *) echo "task-dag: unknown flag: $1" >&2; return 1 ;;
    esac
  done

  ensure_tasks_file

  printf 'ID\tSTATUS\tOWNER\tTITLE\n'
  jq -r --arg status "$status_filter" --arg owner "$owner_filter" '
    .tasks | to_entries[]
    | select($status == "" or .value.status == $status)
    | select($owner == "" or .value.owner == $owner)
    | [.value.id, .value.status, .value.owner, (.value.title // "")] | @tsv
  ' "$TASKS_FILE" 2>/dev/null || true
}

cmd_done() {
  local id="${1:?usage: done <id>}"
  ensure_tasks_file

  if ! jq -e --arg id "$id" '.tasks[$id]' "$TASKS_FILE" > /dev/null 2>&1; then
    echo "task-dag: task $id not found" >&2
    return 1
  fi

  local now tmp
  now=$(_now)

  # 1) Mark done
  tmp=$(mktemp)
  jq --arg id "$id" --arg now "$now" \
     '.tasks[$id].status = "done" | .tasks[$id].updated = $now' \
     "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"

  # 2) Auto-unblock: for every task that has $id in blocked_by, remove it.
  #    If blocked_by becomes [] AND status was "blocked" -> set "pending".
  local dependents
  dependents=$(jq -r --arg id "$id" \
    '.tasks | to_entries[] | select(.value.blocked_by // [] | index($id)) | .key' \
    "$TASKS_FILE" 2>/dev/null || true)

  local unblocked_count=0
  while IFS= read -r dep_id; do
    [ -z "$dep_id" ] && continue
    tmp=$(mktemp)
    jq --arg id "$id" --arg dep_id "$dep_id" --arg now "$now" \
       '.tasks[$dep_id].blocked_by -= [$id]
        | .tasks[$dep_id].updated = $now
        | if (.tasks[$dep_id].blocked_by | length) == 0 and .tasks[$dep_id].status == "blocked"
          then .tasks[$dep_id].status = "pending"
          else . end' \
       "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"
    unblocked_count=$((unblocked_count + 1))
  done <<< "$dependents"

  echo "done $id (auto-unblocked: $unblocked_count)"
}

cmd_show() {
  local id="${1:?usage: show <id>}"
  ensure_tasks_file
  jq --arg id "$id" '.tasks[$id]' "$TASKS_FILE"
}

cmd_block() {
  local id="${1:?usage: block <id> [reason]}"
  shift
  local reason="${1:-no reason}"
  ensure_tasks_file

  if ! jq -e --arg id "$id" '.tasks[$id]' "$TASKS_FILE" > /dev/null 2>&1; then
    echo "task-dag: task $id not found" >&2; return 1
  fi

  local now tmp
  now=$(_now)
  tmp=$(mktemp)
  jq --arg id "$id" --arg reason "$reason" --arg now "$now" \
     '.tasks[$id].status = "blocked"
      | .tasks[$id].block_reason = $reason
      | .tasks[$id].updated = $now' \
     "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"
  echo "blocked $id ($reason)"
}

cmd_unblock() {
  local id="${1:?usage: unblock <id>}"
  ensure_tasks_file

  if ! jq -e --arg id "$id" '.tasks[$id]' "$TASKS_FILE" > /dev/null 2>&1; then
    echo "task-dag: task $id not found" >&2; return 1
  fi

  local now tmp
  now=$(_now)
  tmp=$(mktemp)
  jq --arg id "$id" --arg now "$now" \
     '.tasks[$id].status = "pending"
      | del(.tasks[$id].block_reason)
      | .tasks[$id].updated = $now' \
     "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"
  echo "unblocked $id"
}

cmd_claim() {
  local id="${1:?usage: claim <id> <agent>}"
  local agent="${2:?usage: claim <id> <agent>}"
  ensure_tasks_file

  if ! jq -e --arg id "$id" '.tasks[$id]' "$TASKS_FILE" > /dev/null 2>&1; then
    echo "task-dag: task $id not found" >&2; return 1
  fi

  local now tmp
  now=$(_now)
  tmp=$(mktemp)
  jq --arg id "$id" --arg agent "$agent" --arg now "$now" \
     '.tasks[$id].owner = $agent
      | .tasks[$id].status = "in_progress"
      | .tasks[$id].updated = $now' \
     "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"
  echo "claimed $id by $agent"
}

cmd_help() {
  cat <<'EOF'
Usage: scripts/task-dag.sh <command> [args]

Commands:
  add <id> <title> [--depends ID1,ID2] [--owner X]   Add task (DFS cycle check)
  list [--status X] [--owner Y]                       List tasks (tabular)
  done <id>                                           Mark done + auto-unblock dependents
  show <id>                                           Show task details (JSON)
  block <id> [reason]                                 Set status=blocked
  unblock <id>                                        Set status=pending (clears block_reason)
  claim <id> <agent>                                  Set owner + status=in_progress
  help                                                This message

Environment:
  SWARM_HOME  Root directory (default: $PWD)
              Tasks file: $SWARM_HOME/.swarm/tasks.json
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    add)            with_lock cmd_add "$@" ;;
    list)           cmd_list "$@" ;;
    done)           with_lock cmd_done "$@" ;;
    show)           cmd_show "$@" ;;
    block)          with_lock cmd_block "$@" ;;
    unblock)        with_lock cmd_unblock "$@" ;;
    claim)          with_lock cmd_claim "$@" ;;
    help|-h|--help) cmd_help ;;
    *) echo "task-dag: unknown command: $cmd" >&2; cmd_help; exit 1 ;;
  esac
}

main "$@"
