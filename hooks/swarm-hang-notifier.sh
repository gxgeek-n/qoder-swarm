#!/bin/bash
# swarm-hang-notifier.sh — UserPromptSubmit hook.
# If the watchdog (cron: swarm-watchdog.py --write-flag) has flagged stalled
# sessions, surface the alert in the user's UI via systemMessage — user-only
# channel, never enters model context, never blocks the prompt (always exit 0).
# One-shot: the flag is deleted on display.
#
# This hook NEVER kills or resumes anything. Recovery is a human decision:
# interrupt the hung call in that session (Esc), then re-dispatch the task
# as a fresh agent.
FLAG_FILE="${SWARM_HANG_FLAG:-/tmp/qoder-swarm-hang-alert.flag}"

if [ -f "$FLAG_FILE" ]; then
  python3 - "$FLAG_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    msg = f.read().strip()
print(json.dumps({
    "systemMessage": "⚠️ [swarm-watchdog] 检测到挂死会话:\n" + msg +
        "\n   处理: 到对应会话按 Esc 中断挂起的调用, 然后把任务重新派发给新 agent (不要等旧的)。",
}, ensure_ascii=False))
PYEOF
  rm -f "$FLAG_FILE"
fi
exit 0
