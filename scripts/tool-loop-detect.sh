#!/usr/bin/env bash
# scripts/tool-loop-detect.sh — Detect tool-call loops in dispatch log.
# Ported from OmO packages/omo-opencode/src/features/background-agent/loop-detector.ts
# Usage: scripts/tool-loop-detect.sh [--threshold N] [--log <path>]
#   --threshold N: how many consecutive same-signature calls trigger warning (default 5)
#   --log <path>: dispatch log path (default $SWARM_HOME/.swarm/audit/dispatches.jsonl)
# Exit: 0 = no loop, 1 = loop detected, 2 = error
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
THRESHOLD=5
LOG_FILE="${SWARM_HOME}/.swarm/audit/dispatches.jsonl"

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --log)       LOG_FILE="$2"; shift 2 ;;
    --help|-h)
      grep -E "^# " "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$LOG_FILE" ]; then
  echo "tool-loop-detect: no dispatch log at $LOG_FILE (nothing to check)"
  exit 0
fi

# The dispatch log records Agent dispatches, but loop detection at that level
# is per-worker-invocation. Real value is detecting same-signature (agent,
# description) pairs — a proxy for "same subagent doing same task repeatedly".
# Note: full tool-call loop detection would need per-tool logging, which is
# a Qoder platform feature. This is the best we can do with dispatch-log alone.

# Group consecutive lines by (agent, description) and count runs.
LOOP=$(jq -sr '
  # Reduce over lines building runs: each element is {sig, count}
  reduce .[] as $entry (
    [];
    . as $acc |
    (($entry.agent // "unknown") + "::" + ($entry.desc // "unknown")) as $sig |
    if ($acc | length) > 0 and $acc[-1].sig == $sig then
      $acc[0:-1] + [{sig: $sig, count: ($acc[-1].count + 1)}]
    else
      $acc + [{sig: $sig, count: 1}]
    end
  )
  | map(select(.count >= '"$THRESHOLD"'))
  | if length == 0 then empty else .[0] end
' "$LOG_FILE" 2>/dev/null || true)

if [ -n "$LOOP" ]; then
  echo "WARNING: Tool-call loop detected!" >&2
  echo "   Signature: $(echo "$LOOP" | jq -r '.sig')" >&2
  echo "   Consecutive count: $(echo "$LOOP" | jq -r '.count') (threshold: $THRESHOLD)" >&2
  echo "" >&2
  echo "Suggestion: The orchestrator should kill this dispatch and retry with a different approach." >&2
  exit 1
fi

echo "OK: No tool-call loop detected in $(wc -l < "$LOG_FILE" | tr -d ' ') dispatches (threshold: $THRESHOLD)."
exit 0
