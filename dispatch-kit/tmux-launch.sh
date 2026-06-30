#!/bin/bash
# dispatch-kit tmux launcher
# Starts N+1 tmux panes in one window: 1 controller + N workers.
# Each pane runs `qodercli` with a role hint.
#
# Usage:
#   bash dispatch-kit/tmux-launch.sh [project-root] [session-name]
#
# Defaults:
#   project-root: current directory
#   session-name: swarm
#
# This does NOT install or configure anything. It assumes:
#   1. .dispatch/registry.yml exists (run `bash init-dispatch.sh` first)
#   2. `qodercli` is on PATH
#   3. `tmux` is installed
# QODER_HOME is configurable (defaults to $HOME/.qoder).
# After launch: you type in the first pane (controller) and work
# happens across all panes. Close the session with: tmux kill-session -t <name>

QODER_HOME="${QODER_HOME:-$HOME/.qoder}"

set -euo pipefail

PROJECT="${1:-.}"
SESSION="${2:-swarm}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed. Install with: brew install tmux" >&2
  exit 1
fi

if ! command -v qodercli >/dev/null 2>&1; then
  echo "Error: qodercli is not on PATH." >&2
  exit 1
fi

REGISTRY="$PROJECT/.dispatch/registry.yml"
if [ ! -f "$REGISTRY" ]; then
  echo "Error: $REGISTRY not found." >&2
  echo "Run: bash \"$QODER_HOME/dispatch-kit/init-dispatch.sh\" $PROJECT" >&2
  exit 1
fi

# Parse worker roles from registry.yml (simple grep — handles the basic format)
ROLES=()
while IFS= read -r line; do
  role=$(echo "$line" | grep -oP '(?<=role: ).*' 2>/dev/null || echo "$line" | sed -n 's/.*role: *//p')
  [ -n "$role" ] && [ "$role" != "controller" ] && ROLES+=("$role")
done < <(grep "role:" "$REGISTRY")

if [ ${#ROLES[@]} -eq 0 ]; then
  echo "No worker roles found in $REGISTRY. Using defaults: impl test docs"
  ROLES=(impl test docs)
fi

echo "Launching tmux session '$SESSION' with 1 controller + ${#ROLES[@]} workers"
echo "  Project: $PROJECT"
echo "  Workers: ${ROLES[*]}"
echo ""

# Create tmux session with controller pane
tmux new-session -d -s "$SESSION" -c "$PROJECT" \
  "echo '=== CONTROLLER === (orchestrate, read outbox, write inbox)' && qodercli"

# Add one pane per worker
for role in "${ROLES[@]}"; do
  tmux split-window -t "$SESSION" -c "$PROJECT" \
    "echo '=== WORKER: $role === (monitor .dispatch/inbox/$role.md)' && qodercli"
done

# Tile all panes evenly
tmux select-layout -t "$SESSION" tiled

echo "Session '$SESSION' ready. Attach with:"
echo "  tmux attach -t $SESSION"
echo ""
echo "Kill with:"
echo "  tmux kill-session -t $SESSION"
echo ""
echo "Tip: in each worker pane, tell Qoder:"
echo "  '你是 $role worker。/loop 1m 检查 .dispatch/inbox/$role.md'"

# Optionally attach automatically
if [ -t 0 ]; then
  tmux attach -t "$SESSION"
fi
