#!/usr/bin/env bash
# scripts/verify-models.sh — Confirm swarm-* agent model dispatch is working.
#
# Three-layer verification:
#   L1: Each frontmatter `model:` name exists in `qodercli --list-models`
#       (case-sensitive — Qoder rejects unknown names by silently falling
#       back to Auto routing, defeating the model tiering).
#   L2: When a swarm-* agent is dispatched, its child process sees
#       QODER_MODEL=<expected> env var. We can't probe this from outside —
#       L2 is documented as "run the probe prompts in references/verify-models.md".
#   L3: Behavioral signature — Ultimate-tier agents (planner/reviewer)
#       refuse env probes due to Model Confidentiality; cheaper tiers
#       (worker/explorer/etc.) comply. Refusal == positive signal.
#
# Exits 0 if L1 passes, non-zero otherwise. L2/L3 require manual dispatch.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
QODER_CLI="${QODER_CLI_BIN:-$HOME/.qoder/bin/qodercli/qodercli-1.0.32}"

if [ ! -x "$QODER_CLI" ]; then
  # Try to find any qodercli-*.* binary in the same dir
  QODER_CLI=$(ls "$HOME/.qoder/bin/qodercli/qodercli-"* 2>/dev/null | head -1)
fi

if [ ! -x "$QODER_CLI" ]; then
  echo "ERROR: qodercli binary not found. Set QODER_CLI_BIN env var." >&2
  exit 2
fi

echo "=== Layer 1: model name validity (case-sensitive against --list-models) ==="
echo ""

MODELS=$("$QODER_CLI" --list-models 2>&1)
FAIL=0

for f in "$REPO_ROOT/agents/swarm-"*.md; do
  name=$(grep -m1 '^name:' "$f" | awk '{print $2}')
  model=$(grep -m1 '^model:' "$f" | awk '{print $2}')

  if echo "$MODELS" | grep -qE "^${model}\$"; then
    printf "  %-26s model=%-26s ✓ valid\n" "$name" "$model"
  else
    printf "  %-26s model=%-26s ✗ NOT in catalog\n" "$name" "$model"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== Layer 2: dispatch propagation (manual probe) ==="
echo ""
echo "  To verify a sub-agent actually receives QODER_MODEL=<expected> env,"
echo "  dispatch each agent with a prompt that runs:"
echo ""
echo "    env | grep -E '^QODER_MODEL' > /tmp/swarm-model-probe/<agent>.txt"
echo ""
echo "  Then compare with frontmatter. Ultimate-tier agents may refuse on"
echo "  Model Confidentiality grounds — that refusal itself is a positive"
echo "  signal that the model is correctly Ultimate."
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Layer 1 FAIL: $FAIL agent(s) have invalid model names."
  echo ""
  echo "Available models:"
  echo "$MODELS" | sed 's/^/  /'
  exit 1
fi

echo "✅ Layer 1 PASS: all $(ls "$REPO_ROOT/agents/swarm-"*.md | wc -l | tr -d ' ') swarm-* agents have valid model names."
