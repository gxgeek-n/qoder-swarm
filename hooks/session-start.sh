#!/usr/bin/env bash
# hooks/session-start.sh — SessionStart hook: print swarm status summary.
# Shows quick .swarm/ health on session open — memory count, last dispatch age, empty-dones.
# Source: oh-my-qoder hooks session-start.mjs + project-memory-session.mjs pattern.
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
SWARM_DIR="${SWARM_HOME}/.swarm"

# Only output if .swarm/ exists (this project uses swarm)
if [ ! -d "$SWARM_DIR" ]; then
  exit 0
fi

# Gather stats
MEMORY_COUNT=$(ls "$SWARM_DIR/memory/"*.md 2>/dev/null | wc -l | tr -d ' ')
AUDIT_FILE="$HOME/.qoder/audit/audit.jsonl"
LAST_DISPATCH="never"
EMPTY_DONES="?"

if [ -f "$AUDIT_FILE" ]; then
  LAST_TS=$(tail -500 "$AUDIT_FILE" | grep '"Agent"' | tail -1 | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        j = json.loads(line)
        if j.get('tool_name') == 'Agent' and j.get('_event') == 'PostToolUse':
            print(j.get('_timestamp', 'unknown'))
    except: pass
" 2>/dev/null | tail -1)
  if [ -n "$LAST_TS" ]; then
    LAST_DISPATCH="$LAST_TS"
  fi
fi

if [ -f "$SWARM_DIR/audit/empty-dones.jsonl" ]; then
  TODAY=$(date +%Y-%m-%d)
  EMPTY_DONES=$(grep -c "$TODAY" "$SWARM_DIR/audit/empty-dones.jsonl" 2>/dev/null || echo "0")
fi

echo "swarm: ${MEMORY_COUNT} memory files | last dispatch: ${LAST_DISPATCH} | empty-dones today: ${EMPTY_DONES}"
