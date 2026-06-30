#!/usr/bin/env bash
# scripts/swarm-state.sh — Unified CLI for swarm state queries.
# Wraps task-dag.sh, file-overlap.sh, and memory listing.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SWARM_HOME="${SWARM_HOME:-$PWD}"

cmd_help() {
  cat <<EOF
Usage: swarm-state.sh <command> [args]

Commands:
  status [--terse]                   Overall state (task counts, agents, memory)
  task <add|list|done|...>           Forward to task-dag.sh
  overlap check <ref1> <ref2> ...    Forward to file-overlap.sh
  memory list                        List .swarm/memory/*.md files
  help                               This message

Environment:
  SWARM_HOME    Base path for .swarm/ (default: PWD)
EOF
}

cmd_status() {
  local terse=0
  if [ "${1:-}" = "--terse" ]; then terse=1; fi
  local tasks_file="${SWARM_HOME}/.swarm/tasks.json"
  if [ -f "$tasks_file" ]; then
    if [ "$terse" = "1" ]; then
      jq -r '.tasks | to_entries[] | "\(.key): status=\(.value.status) owner=\(.value.owner)"' "$tasks_file" 2>/dev/null
    else
      echo "## Tasks"
      jq -r '
        .tasks | group_by(.status) | map({status: .[0].status, count: length}) | .[] |
        "  \(.status): \(.count)"
      ' "$tasks_file" 2>/dev/null || echo "  (no tasks)"
      echo ""
      echo "## Active owners"
      jq -r '.tasks | to_entries[] | select(.value.status == "in_progress") | .value.owner' "$tasks_file" 2>/dev/null | sort -u | sed 's/^/  /' || echo "  (none)"
    fi
  else
    [ "$terse" = "1" ] || echo "## Tasks"
    [ "$terse" = "1" ] || echo "  (no .swarm/tasks.json yet)"
  fi
  if [ "$terse" = "0" ]; then
    echo ""
    echo "## Memory"
    if [ -d "${SWARM_HOME}/.swarm/memory" ]; then
      local memcount; memcount=$(ls "${SWARM_HOME}/.swarm/memory/"*.md 2>/dev/null | wc -l | tr -d ' ')
      echo "  $memcount file(s)"
      ls "${SWARM_HOME}/.swarm/memory/"*.md 2>/dev/null | sed "s|${SWARM_HOME}/||" | sed 's/^/    /' || true
    else
      echo "  (no memory yet)"
    fi
  fi
}

cmd_task() {
  exec "${SCRIPT_DIR}/task-dag.sh" "$@"
}

cmd_overlap() {
  exec "${SCRIPT_DIR}/file-overlap.sh" "$@"
}

cmd_memory() {
  case "${1:-list}" in
    list)
      if [ -d "${SWARM_HOME}/.swarm/memory" ]; then
        ls "${SWARM_HOME}/.swarm/memory/"*.md 2>/dev/null || echo "(empty)"
      else
        echo "(empty)"
      fi
      ;;
    *) echo "unknown memory subcommand: $1" >&2; return 1;;
  esac
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    status) cmd_status "$@";;
    task) cmd_task "$@";;
    overlap) cmd_overlap "$@";;
    memory) cmd_memory "$@";;
    help|-h|--help) cmd_help;;
    *) echo "unknown command: $cmd" >&2; cmd_help; exit 1;;
  esac
}

main "$@"
