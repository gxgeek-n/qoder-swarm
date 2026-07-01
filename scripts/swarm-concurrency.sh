#!/usr/bin/env bash
# scripts/swarm-concurrency.sh — Per-model concurrency slot manager.
# Ported from OmO packages/omo-opencode/src/features/background-agent/concurrency.ts
#
# Commands:
#   status                                 Show all model slot state
#   acquire <model> <task-id>              Try to acquire a slot; exit 0 if got, exit 1 if full
#   release <model> <task-id>              Release a slot (must have acquired first)
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
}

cmd_release() {
  local model="${1:?usage: release <model> <task-id>}"
  local task_id="${2:?usage: release <model> <task-id>}"
  with_lock _do_release "$model" "$task_id"
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
