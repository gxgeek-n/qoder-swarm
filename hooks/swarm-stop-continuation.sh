#!/bin/bash
# stop-continuation hook: if .swarm/ state shows incomplete work, emit a
# brief continuation hint so the next Qoder session can resume.
#
# SECURITY: Parse JSON via python3 (regex on JSON is fragile against
# pretty-printed input) and sanitize ALL state-file content before
# echoing — those files can be checked in by anyone with write access
# to the repo and become a prompt-injection vector into the LLM context.
#
# Install: add to Stop hooks in settings.json (handled by install-settings.py).

set -euo pipefail

# Truncate + strip control chars + newlines from any string we forward to
# the LLM. Length cap is conservative; LLM-context attacks usually need
# more than 80 chars of room to be useful.
sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | cut -c1-80
}

# Read one JSON field as a string. Empty string if missing / not a string /
# file unparseable. Never raises on bad input — silent failure is safer here
# than spilling tracebacks into the hook stream.
read_json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY' 2>/dev/null || printf ''
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    val = data.get(sys.argv[2], "")
    print(val if isinstance(val, str) else "")
except Exception:
    pass
PY
}

# Check ulw-loop state
ULW_STATE=".swarm/ulw-loop/state.json"
if [ -f "$ULW_STATE" ]; then
  STATUS=$(read_json_field "$ULW_STATE" status)
  if [ "$STATUS" = "active" ]; then
    TASK=$(sanitize "$(read_json_field "$ULW_STATE" task)")
    echo "[swarm:continuation] ULW loop is still active."
    if [ -n "$TASK" ]; then
      echo "  Task hint (sanitized): $TASK"
    fi
    echo "  Resume by telling Qoder: continue the ulw-loop in this project"
    echo "  Authoritative state: $ULW_STATE"
    exit 0
  fi
fi

# Check team state
if [ -d ".swarm/teams" ]; then
  for TEAM_JSON in .swarm/teams/*/team.json; do
    [ -f "$TEAM_JSON" ] || continue
    STATUS=$(read_json_field "$TEAM_JSON" status)
    if [ "$STATUS" = "active" ]; then
      NAME=$(sanitize "$(read_json_field "$TEAM_JSON" name)")
      DIR=$(dirname "$TEAM_JSON")
      echo "[swarm:continuation] Team has active work."
      if [ -n "$NAME" ]; then
        echo "  Team name (sanitized): $NAME"
      fi
      echo "  Authoritative state: $TEAM_JSON"
      echo "  Inbox/outbox: $DIR/outbox/"
      exit 0
    fi
  done
fi

exit 0
