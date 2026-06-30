#!/usr/bin/env bash
# Middle-truncate stdin or file. Keeps head+tail, drops middle.
# Ported from smolagents/utils.py:257 (truncate_content).
# Usage: cat big.log | scripts/truncate.sh 5000   # keep first+last 2500 chars
#        scripts/truncate.sh 5000 big.log         # file form
set -euo pipefail
MAX="${1:-4000}"
if [ -n "${2:-}" ]; then
  exec < "$2"
fi
content="$(cat)"
len=${#content}
if [ "$len" -le "$MAX" ]; then
  printf '%s' "$content"
  exit 0
fi
half=$((MAX / 2))
printf '%s' "${content:0:$half}"
printf '\n...[truncated %d chars]...\n' "$((len - MAX))"
printf '%s' "${content: -$half}"
