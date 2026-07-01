#!/usr/bin/env bash
# scripts/swarm-concurrency.sh — Per-model concurrency slot manager.
# Ported from OmO packages/omo-opencode/src/features/background-agent/concurrency.ts
#
# Commands:
#   status                                 Show all model slot state
#   acquire <model> <task-id>              Try to acquire a slot; exit 0 if got, exit 1 if full
#   release <model> <task-id> [opts]       Release a slot (must have acquired first)
#     --status <STATUS>                    completed|error|timeout|cancelled|empty-done
#     --error <ERROR_CLASS>                429|5xx|timeout|refusal|empty-done|unknown
#     --duration-ms <N>                    numeric ms (default 0)
#     --agent <NAME>                       subagent type (default unknown)
#   config <model> <limit>                 Set concurrency limit for a model (persisted)
#   reset                                  Clear all slots (dangerous)
#
# Env:
#   SWARM_CONCURRENCY_DEFAULT              Default per-model limit (default 5)
#   SWARM_HOME                             Root dir (default $PWD)
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
STATE_DIR="${SWARM_HOME}/.swarm/concurrency"
STATE_FILE="${STATE_DIR}/slots.json"
LOCK_DIR="${STATE_DIR}/.lockdir"
AUDIT_DIR="${SWARM_HOME}/.swarm/audit"
AUDIT_FILE="${AUDIT_DIR}/attempts.jsonl"
DEFAULT_LIMIT="${SWARM_CONCURRENCY_DEFAULT:-5}"

ensure_state() {
  mkdir -p "$STATE_DIR"
  if [ ! -f "$STATE_FILE" ]; then
    echo '{}' > "$STATE_FILE"
  fi
}

with_lock() {
  ensure_state
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    sleep 0.05
    waited=$((waited + 1))
    if [ "$waited" -ge 200 ]; then
      echo "swarm-concurrency: lock timeout (10s)" >&2
      return 1
    fi
  done
  local rc=0
  "$@" || rc=$?
  rmdir "$LOCK_DIR"
  return $rc
}

_ensure_model_entry() {
  local model="$1"
  local tmp; tmp=$(mktemp)
  jq --arg m "$model" --argjson d "$DEFAULT_LIMIT" '
    if .[$m] == null then
      .[$m] = {count: 0, limit: $d, queue: []}
    else . end
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

cmd_status() {
  ensure_state
  echo "=== Concurrency slots ==="
  if [ "$(jq 'length' "$STATE_FILE")" = "0" ]; then
    echo "  (no models tracked yet)"
    return 0
  fi
  jq -r '
    to_entries[] |
    "  \(.key): \(.value.count)/\(.value.limit) running, \(.value.queue | length) queued"
  ' "$STATE_FILE"
}

_do_acquire() {
  local model="$1"
  local task_id="$2"
  _ensure_model_entry "$model"
  local count limit
  count=$(jq -r --arg m "$model" '.[$m].count' "$STATE_FILE")
  limit=$(jq -r --arg m "$model" '.[$m].limit' "$STATE_FILE")

  if [ "$count" -lt "$limit" ]; then
    local tmp; tmp=$(mktemp)
    jq --arg m "$model" --arg t "$task_id" '
      .[$m].count += 1
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "acquired: $model slot $((count+1))/$limit (task=$task_id)"
    return 0
  else
    local tmp; tmp=$(mktemp)
    jq --arg m "$model" --arg t "$task_id" '
      .[$m].queue += [$t] | .[$m].queue |= unique
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "queued: $model at capacity $count/$limit (task=$task_id)" >&2
    return 1
  fi
}

cmd_acquire() {
  local model="${1:?usage: acquire <model> <task-id>}"
  local task_id="${2:?usage: acquire <model> <task-id>}"
  with_lock _do_acquire "$model" "$task_id"
}

_do_release() {
  local model="$1"
  local task_id="$2"
  local status="${3:-completed}"
  local error_class="${4:-}"
  local duration_ms="${5:-0}"
  local agent="${6:-unknown}"

  _ensure_model_entry "$model"
  local tmp; tmp=$(mktemp)
  jq --arg m "$model" --arg t "$task_id" '
    .[$m].count = (if .[$m].count > 0 then .[$m].count - 1 else 0 end)
    | .[$m].queue -= [$t]
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  local count limit
  count=$(jq -r --arg m "$model" '.[$m].count' "$STATE_FILE")
  limit=$(jq -r --arg m "$model" '.[$m].limit' "$STATE_FILE")
  echo "released: $model now $count/$limit (task=$task_id)"

  # Append audit record to attempts.jsonl
  _append_audit "$model" "$task_id" "$status" "$error_class" "$duration_ms" "$agent"
}

_append_audit() {
  local model="$1"
  local task_id="$2"
  local status="$3"
  local error_class="$4"
  local duration_ms="$5"
  local agent="$6"

  # Validate duration_ms is numeric, default to 0 if not
  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]]; then
    duration_ms=0
  fi

  mkdir -p "$AUDIT_DIR"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if [ -n "$error_class" ]; then
    jq -nc \
      --arg ts "$ts" \
      --arg tid "$task_id" \
      --arg ag "$agent" \
      --arg mo "$model" \
      --arg st "$status" \
      --argjson dm "$duration_ms" \
      --arg ec "$error_class" \
      '{ts:$ts,task_id:$tid,agent:$ag,model:$mo,status:$st,duration_ms:$dm,error_class:$ec}' \
      >> "$AUDIT_FILE"
  else
    jq -nc \
      --arg ts "$ts" \
      --arg tid "$task_id" \
      --arg ag "$agent" \
      --arg mo "$model" \
      --arg st "$status" \
      --argjson dm "$duration_ms" \
      '{ts:$ts,task_id:$tid,agent:$ag,model:$mo,status:$st,duration_ms:$dm}' \
      >> "$AUDIT_FILE"
  fi
}

cmd_release() {
  local model="${1:?usage: release <model> <task-id> [--status <STATUS>] [--error <ERROR_CLASS>] [--duration-ms <N>] [--agent <NAME>]}"
  local task_id="${2:?usage: release <model> <task-id>}"
  shift 2 || true

  local status="completed"
  local error_class=""
  local duration_ms="0"
  local agent="unknown"

  while [ $# -gt 0 ]; do
    case "$1" in
      --status)      status="$2"; shift 2 ;;
      --error)       error_class="$2"; shift 2 ;;
      --duration-ms) duration_ms="$2"; shift 2 ;;
      --agent)       agent="$2"; shift 2 ;;
      *)             echo "unknown flag: $1" >&2; shift ;;
    esac
  done

  with_lock _do_release "$model" "$task_id" "$status" "$error_class" "$duration_ms" "$agent"
}

cmd_config() {
  local model="${1:?usage: config <model> <limit>}"
  local limit="${2:?usage: config <model> <limit>}"
  ensure_state
  local tmp; tmp=$(mktemp)
  jq --arg m "$model" --argjson l "$limit" --argjson d "$DEFAULT_LIMIT" '
    if .[$m] == null then
      .[$m] = {count: 0, limit: $l, queue: []}
    else
      .[$m].limit = $l
    end
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  echo "config: $model limit=$limit"
}

cmd_reset() {
  ensure_state
  echo '{}' > "$STATE_FILE"
  echo "all slots reset"
}

cmd_help() {
  grep -E "^#" "$0" | head -20 | sed 's/^# //; s/^#//'
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    status)  cmd_status ;;
    acquire) cmd_acquire "$@" ;;
    release) cmd_release "$@" ;;
    config)  cmd_config "$@" ;;
    reset)   cmd_reset ;;
    help|-h|--help) cmd_help ;;
    *) echo "unknown command: $cmd" >&2; cmd_help; exit 1 ;;
  esac
}

main "$@"
