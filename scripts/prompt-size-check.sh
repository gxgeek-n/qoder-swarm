#!/usr/bin/env bash
# scripts/prompt-size-check.sh — Validate a proposed Agent prompt fits the char budget.
# Enforces the ≤2500 char HARD RULE from _shared.md "Sub-agent PROMPT size contract".
# Usage:
#   echo "prompt text" | scripts/prompt-size-check.sh
#   scripts/prompt-size-check.sh --file path/to/prompt.txt
#   scripts/prompt-size-check.sh --budget 3000 --quiet < prompt.txt
# Exit: 0 = within budget, 1 = over budget, 2 = error
set -euo pipefail

BUDGET=2500
QUIET=false
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --budget)  BUDGET="$2"; shift 2 ;;
    --quiet)   QUIET=true; shift ;;
    --file)    FILE="$2"; shift 2 ;;
    --help|-h)
      grep -E "^# " "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Read prompt: from --file if given, otherwise stdin
if [ -n "$FILE" ]; then
  if [ ! -f "$FILE" ]; then
    echo "error: file not found: $FILE" >&2
    exit 2
  fi
  PROMPT="$(cat "$FILE")"
else
  PROMPT="$(cat)"
fi

CHARS=${#PROMPT}
WORDS=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
LINES=$(printf '%s' "$PROMPT" | wc -l | tr -d ' ')

if [ "$QUIET" = true ]; then
  if [ "$CHARS" -le "$BUDGET" ]; then
    exit 0
  else
    exit 1
  fi
fi

echo "chars:   $CHARS"
echo "words:   $WORDS"
echo "lines:   $LINES"
echo "budget:  $BUDGET"

if [ "$CHARS" -le "$BUDGET" ]; then
  echo "status:  OK (within budget)"
  exit 0
fi

OVER=$((CHARS - BUDGET))
echo "status:  OVER BUDGET by $OVER chars"
echo ""

# --- Offender detection ---

# 1. Detect heredoc/code fence blocks totaling >500 chars
HEREDOC_CHARS=0
IN_FENCE=false
FENCE_BUF=""
while IFS= read -r line; do
  case "$line" in
    \`\`\`*)
      if [ "$IN_FENCE" = false ]; then
        IN_FENCE=true
        FENCE_BUF=""
      else
        IN_FENCE=false
        FENCE_LEN=${#FENCE_BUF}
        if [ "$FENCE_LEN" -gt 0 ]; then
          echo "  - code fence block: ${FENCE_LEN} chars"
        fi
        HEREDOC_CHARS=$((HEREDOC_CHARS + FENCE_LEN))
        FENCE_BUF=""
      fi
      ;;
    *)
      if [ "$IN_FENCE" = true ]; then
        FENCE_BUF="${FENCE_BUF}${line}"$'\n'
      fi
      ;;
  esac
done <<< "$PROMPT"

if [ "$HEREDOC_CHARS" -gt 500 ]; then
  echo "offender: code fence blocks total ${HEREDOC_CHARS} chars (>500)"
  echo "  suggest: extract to reference file (worker Reads it via path)"
fi

# 2. Detect >5 acceptance criteria (lines starting with - or * under ACCEPTANCE)
ACCEPT_COUNT=$(printf '%s\n' "$PROMPT" | sed -n '/ACCEPTANCE/,/^$/p' | grep -cE '^\s*[-*]\s' || true)
if [ "$ACCEPT_COUNT" -gt 5 ]; then
  echo "offender: $ACCEPT_COUNT acceptance criteria (>5)"
  echo "  suggest: use recipe from worker-verify-recipes.md"
fi

# 3. Generic suggestion if no specific offenders found
if [ "$HEREDOC_CHARS" -le 500 ] && [ "$ACCEPT_COUNT" -le 5 ]; then
  echo "offender: general verbosity"
  echo "  suggest: trim redundant explanation, remove example outputs, use recipe name"
fi

exit 1
