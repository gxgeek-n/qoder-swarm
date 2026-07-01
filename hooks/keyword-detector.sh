#!/usr/bin/env bash
# hooks/keyword-detector.sh — UserPromptSubmit hook: detect swarm-related keywords.
# When user types swarm triggers, injects a system reminder to activate the skill.
#
# Qoder hook env: $QODER_USER_PROMPT (if exposed). If not available, this is a no-op.
# Source: oh-my-qoder hooks/hooks.json → keyword-detector.mjs pattern (Apache-2.0).
set -euo pipefail

# Qoder may not expose the user prompt to hooks. Check env.
PROMPT="${QODER_USER_PROMPT:-${USER_PROMPT:-}}"
if [ -z "$PROMPT" ]; then
  # No prompt text available in hook env — silent exit (Qoder platform limitation)
  exit 0
fi

# Swarm trigger keywords (subset of SKILL.md triggers)
KEYWORDS="plan-and-review|start-work|five-agent|swarm|自举|自进化|self-improve|ultrawork|magentic|team mode|对抗审查|code review|hyperplan|hostile critic"

if echo "$PROMPT" | grep -qiE "$KEYWORDS"; then
  # Output goes to system-reminder injection (if Qoder supports hook stdout → prompt)
  echo "→ Swarm pattern keyword detected. Consider activating the swarm skill for this task."
fi

exit 0
