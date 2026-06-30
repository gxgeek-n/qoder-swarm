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

echo "=== Layer 0: qodercli's own agents list (authoritative source) ==="
echo ""
echo "  Qoder CLI's 'agents list' output tells us, in its own words, what"
echo "  model each agent is bound to after loading. This is the most"
echo "  authoritative check — bypasses any guesswork about frontmatter parsing."
echo ""

FAIL=0

# Parse `agents list` output. Format per line: "  <name> · <model>"
AGENTS_LIST=$("$QODER_CLI" agents list 2>&1 || true)

for f in "$REPO_ROOT/agents/swarm-"*.md; do
  name=$(grep -m1 '^name:' "$f" | awk '{print $2}')
  expected=$(grep -m1 '^model:' "$f" | awk '{print $2}')

  # Match line like "  swarm-worker · GLM-5.2"
  actual=$(echo "$AGENTS_LIST" | awk -v n="$name" '$1 == n && $2 == "·" { print $3 }')

  if [ -z "$actual" ]; then
    printf "  %-26s ⚠️  agent not loaded by qodercli (frontmatter=%s)\n" "$name" "$expected"
    FAIL=$((FAIL + 1))
  elif [ "$expected" = "$actual" ]; then
    printf "  %-26s frontmatter=%-26s qodercli=%-26s ✅ MATCH\n" "$name" "$expected" "$actual"
  else
    printf "  %-26s frontmatter=%-26s qodercli=%-26s ❌ MISMATCH\n" "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
done

# Surface any config-load warnings
if echo "$AGENTS_LIST" | grep -qE "error loading|errors loading"; then
  echo ""
  echo "  ⚠️  qodercli reported config-load issues:"
  echo "$AGENTS_LIST" | grep -E "error loading|errors loading" | sed 's/^/      /'
fi

echo ""
echo "=== Layer 1: model name validity (case-sensitive against --list-models) ==="
echo ""

MODELS=$("$QODER_CLI" --list-models 2>&1)

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
  echo "❌ Verification FAIL: $FAIL issue(s) across Layer 0 + Layer 1."
  echo ""
  echo "Available models from --list-models:"
  echo "$MODELS" | sed 's/^/  /'
  exit 1
fi

AGENT_COUNT=$(ls "$REPO_ROOT/agents/swarm-"*.md | wc -l | tr -d ' ')
echo "✅ Verification PASS: all $AGENT_COUNT swarm-* agents are correctly bound."
echo "   - Layer 0 (qodercli agents list): matches frontmatter"
echo "   - Layer 1 (qodercli --list-models): valid model names"
