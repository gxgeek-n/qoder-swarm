#!/bin/bash
# swarm-hang-notifier.sh — UserPromptSubmit hook.
# If the watchdog (cron: swarm-watchdog.py --write-flag) has flagged stalled
# sessions, surface the alert in the user's UI via systemMessage — user-only
# channel, never enters model context, never blocks the prompt (always exit 0).
# One-shot: the flag is deleted on display.
#
# The flag content — per-session host window (tty) when uniquely resolved,
# plus recovery guidance — is authored by swarm-watchdog.py; this hook only
# relays it verbatim. Recovery is a human decision (Esc in the named
# window): the watchdog and this hook never kill, signal, or resume
# anything (verified 2026-07-23: external SIGINT kills the qodercli TUI).
FLAG_FILE="${SWARM_HANG_FLAG:-/tmp/qoder-swarm-hang-alert.flag}"

if [ -f "$FLAG_FILE" ]; then
  python3 - "$FLAG_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    msg = f.read().strip()
print(json.dumps({
    "systemMessage": "⚠️ [swarm-watchdog] 检测到挂死会话:\n" + msg,
}, ensure_ascii=False))
PYEOF
  rm -f "$FLAG_FILE"
fi
exit 0
