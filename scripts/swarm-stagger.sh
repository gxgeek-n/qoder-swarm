#!/usr/bin/env bash
# scripts/swarm-stagger.sh — Random micro-sleep to stagger dispatch bursts.
# Usage:
#   scripts/swarm-stagger.sh                # sleeps random 200-400ms
#   scripts/swarm-stagger.sh 100 500        # sleeps random 100-500ms
#   scripts/swarm-stagger.sh --off          # no sleep (env override)
#
# Env:
#   SWARM_STAGGER_OFF=1     Disable staggering entirely
#   SWARM_STAGGER_MIN_MS    Min sleep (default 200)
#   SWARM_STAGGER_MAX_MS    Max sleep (default 400)
set -euo pipefail

if [ "${SWARM_STAGGER_OFF:-0}" = "1" ] || [ "${1:-}" = "--off" ]; then
  exit 0
fi

MIN_MS="${1:-${SWARM_STAGGER_MIN_MS:-200}}"
MAX_MS="${2:-${SWARM_STAGGER_MAX_MS:-400}}"

if [ "$MIN_MS" -gt "$MAX_MS" ]; then
  echo "swarm-stagger: MIN_MS ($MIN_MS) > MAX_MS ($MAX_MS)" >&2
  exit 1
fi

# Random ms in [MIN, MAX]
RANGE=$((MAX_MS - MIN_MS + 1))
DELAY_MS=$((MIN_MS + RANDOM % RANGE))

# Convert to sleep argument (bash sleep supports floats on macOS/Linux)
DELAY_SEC=$(awk -v ms="$DELAY_MS" 'BEGIN{printf "%.3f", ms/1000}')

sleep "$DELAY_SEC"
