#!/usr/bin/env bash
# hooks/agent-dispatch-log.sh — PostToolUse hook logging Agent dispatches.
# Install via settings.json PostToolUse matcher "Agent".
# Logs to .swarm/audit/dispatches.jsonl for cost analysis.
set -euo pipefail

# Only care about Agent tool invocations.
# Qoder provides QODER_TOOL_NAME; support TOOL_NAME as fallback for testing.
TOOL_NAME="${QODER_TOOL_NAME:-${TOOL_NAME:-}}"
if [ "$TOOL_NAME" != "Agent" ]; then
  exit 0
fi

# Determine project root (where agents/ and .swarm/ live).
SWARM_HOME="${SWARM_HOME:-$PWD}"
LOG_DIR="${SWARM_HOME}/.swarm/audit"
LOG_FILE="${LOG_DIR}/dispatches.jsonl"
mkdir -p "$LOG_DIR"

# Parse agent info from tool input JSON.
# Qoder provides QODER_TOOL_INPUT; support TOOL_INPUT as fallback.
# NOTE: Cannot use ${TOOL_INPUT:-{}} because } in the default {} closes
# the expansion prematurely and appends a literal }. Use explicit check.
TOOL_INPUT="${QODER_TOOL_INPUT:-${TOOL_INPUT:-}}"
if [ -z "$TOOL_INPUT" ]; then
  TOOL_INPUT='{}'
fi
AGENT_TYPE=$(printf '%s' "$TOOL_INPUT" | jq -r '.subagent_type // "general-purpose"' 2>/dev/null || echo "general-purpose")
DESCRIPTION=$(printf '%s' "$TOOL_INPUT" | jq -r '.description // "unknown"' 2>/dev/null || echo "unknown")

# Sanitize for safe JSON string embedding (strip quotes and backslashes).
sanitize() {
  printf '%s' "$1" | tr -d '"' | tr '\\' '/' | tr '\n' ' ' | cut -c1-200
}
AGENT_TYPE=$(sanitize "$AGENT_TYPE")
DESCRIPTION=$(sanitize "$DESCRIPTION")

# Look up model + effort from agent frontmatter.
AGENT_FILE="${SWARM_HOME}/agents/${AGENT_TYPE}.md"
if [ -f "$AGENT_FILE" ]; then
  MODEL=$(grep -m1 '^model:' "$AGENT_FILE" | awk '{print $2}')
  EFFORT=$(grep -m1 '^effort:' "$AGENT_FILE" | awk '{print $2}')
fi
MODEL="${MODEL:-inherit}"
EFFORT="${EFFORT:-default}"

# Timestamp (UTC ISO 8601).
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write log line (single append, atomic for small writes).
printf '{"ts":"%s","agent":"%s","model":"%s","effort":"%s","desc":"%s"}\n' \
  "$TS" "$AGENT_TYPE" "$MODEL" "$EFFORT" "$DESCRIPTION" >> "$LOG_FILE"

exit 0
