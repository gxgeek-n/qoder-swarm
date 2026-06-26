#!/bin/bash
# stop-continuation hook: check if ulw-loop or start-work has pending work
# If .swarm/ state shows incomplete tasks, output a continuation prompt
# Install: add to Stop hooks in settings.json

# Check ulw-loop state
ULW_STATE=".swarm/ulw-loop/state.json"
if [ -f "$ULW_STATE" ]; then
  STATUS=$(grep -o '"status":"[^"]*"' "$ULW_STATE" | head -1 | cut -d'"' -f4)
  if [ "$STATUS" = "active" ]; then
    TASK=$(grep -o '"task":"[^"]*"' "$ULW_STATE" | head -1 | cut -d'"' -f4)
    echo "[swarm:continuation] ULW loop is still active: $TASK"
    echo "Resume with: Workflow({ name: 'ulw-loop', args: { task: '$TASK' } })"
    exit 0
  fi
fi

# Check team state
if [ -d ".swarm/teams" ]; then
  for TEAM_JSON in .swarm/teams/*/team.json; do
    [ -f "$TEAM_JSON" ] || continue
    STATUS=$(grep -o '"status":"[^"]*"' "$TEAM_JSON" | head -1 | cut -d'"' -f4)
    if [ "$STATUS" = "active" ]; then
      NAME=$(grep -o '"name":"[^"]*"' "$TEAM_JSON" | head -1 | cut -d'"' -f4)
      echo "[swarm:continuation] Team '$NAME' has active work. Check .swarm/teams/$NAME/outbox/"
      exit 0
    fi
  done
fi

exit 0
