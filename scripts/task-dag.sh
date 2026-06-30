#!/usr/bin/env bash
# scripts/task-dag.sh — Task DAG with DFS cycle detection + auto-unblock
# Ported from ClawTeam clawteam/store/file.py:316-344 (cycle), :362-375 (auto-unblock)
# TaskItem schema: team/models.py:124-143
#
# Uses 3-colour DFS (WHITE/GRAY/BLACK) backed by temp files + awk,
# compatible with macOS bash 3.2 (no associative arrays).
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
TASKS_FILE="${SWARM_HOME}/.swarm/tasks.json"
LOCK_FILE="${SWARM_HOME}/.swarm/tasks.json.lock"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ensure_tasks_file() {
  mkdir -p "$(dirname "$TASKS_FILE")"
  if [ ! -f "$TASKS_FILE" ]; then
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
# Implementation: temp files + awk (bash 3.2 has no associative arrays).
# ---------------------------------------------------------------------------

detect_cycle() {
  local proposed_id="$1"
  local proposed_deps_csv="${2:-}"
  ensure_tasks_file

  local color_file deps_file
  color_file=$(mktemp)
  deps_file=$(mktemp)

  # Build adjacency list: "id<TAB>dep1 dep2 ..." (including proposed node)
  local proposed_deps_spaced="${proposed_deps_csv//,/ }"
  jq -r --arg pid "$proposed_id" --arg pdeps "$proposed_deps_spaced" '
    .tasks | to_entries[] | "\(.key)\t\(.value.blocked_by // [] | join(" "))",
    "\($pid)\t\($pdeps)"
  ' "$TASKS_FILE" > "$deps_file" 2>/dev/null || true

  # Initialise colours: all WHITE (0)
  while IFS=$'\t' read -r cid _; do
    [ -z "$cid" ] && continue
    printf '%s\t0\n' "$cid"
  done < "$deps_file" > "$color_file"

  # --- helper functions (global, but reference locals via dynamic scope) ---

  _dc_get_deps() {
    awk -F'\t' -v n="$1" '$1==n{print $2; exit}' "$deps_file"
  }

  _dc_get_color() {
    awk -F'\t' -v n="$1" '$1==n{print $2; exit}' "$color_file"
  }

  _dc_set_color() {
    local node="$1" color="$2"
    awk -F'\t' -v n="$node" '$1!=n' "$color_file" > "${color_file}.tmp" 2>/dev/null || true
    printf '%s\t%s\n' "$node" "$color" >> "${color_file}.tmp"
    mv "${color_file}.tmp" "$color_file"
  }

  # Recursive 3-colour DFS
  _dc_dfs() {
    local node="$1"
    _dc_set_color "$node" 1            # GRAY
    local parents parent c
    parents=$(_dc_get_deps "$node")
    for parent in $parents; do
      [ -z "$parent" ] && continue
      c=$(_dc_get_color "$parent")
      [ -z "$c" ] && continue          # parent not in graph → skip
      if [ "$c" = "1" ]; then
        return 1                       # back edge → cycle
      fi
      if [ "$c" = "0" ]; then
        _dc_dfs "$parent" || return 1
      fi
    done
    _dc_set_color "$node" 2            # BLACK
    return 0
  }

  local result=0
  _dc_dfs "$proposed_id" || result=1

  rm -f "$color_file" "$deps_file" "${color_file}.tmp" 2>/dev/null || true
  return $result
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

  ensure_tasks_file

  # Duplicate check
  if jq -e --arg id "$id" '.tasks[$id]' "$TASKS_FILE" > /dev/null 2>&1; then
    echo "task-dag: task $id already exists" >&2
    return 1
  fi

  # Parent existence check
  if [ -n "$depends" ]; then
    local OLD_IFS="$IFS"
    IFS=','
    for dep in $depends; do
      if ! jq -e --arg d "$dep" '.tasks[$d]' "$TASKS_FILE" > /dev/null 2>&1; then
        echo "task-dag: parent task $dep does not exist" >&2
        IFS="$OLD_IFS"
        return 1
      fi
    done
    IFS="$OLD_IFS"
  fi

  # Cycle check
  if ! detect_cycle "$id" "$depends"; then
    echo "task-dag: cycle detected — adding $id with depends=[$depends] would create a cycle" >&2
    return 1
  fi

  local now status blocked_by_json
  now=$(_now)

  if [ -n "$depends" ]; then
    status="blocked"
    blocked_by_json=$(printf '%s' "$depends" | tr ',' '\n' | jq -R . | jq -s .)
  else
    status="pending"
    blocked_by_json="[]"
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg id "$id" \
     --arg title "$title" \
     --arg owner "$owner" \
     --arg status "$status" \
     --arg now "$now" \
     --argjson blocked_by "$blocked_by_json" \
     '.tasks[$id] = {
        id: $id,
        title: $title,
        status: $status,
        blocked_by: $blocked_by,
        blocks: [],
        owner: $owner,
        created: $now,
        updated: $now
     }' \
     "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"

  # Update parent .blocks arrays
  if [ -n "$depends" ]; then
    local OLD_IFS="$IFS"
    IFS=','
    for dep in $depends; do
      tmp=$(mktemp)
      jq --arg id "$id" --arg dep "$dep" \
         '.tasks[$dep].blocks += [$id] | .tasks[$dep].blocks |= unique' \
         "$TASKS_FILE" > "$tmp" && _atomic_write "$tmp"
    done
    IFS="$OLD_IFS"
  fi

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
