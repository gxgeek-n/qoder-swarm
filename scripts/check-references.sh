#!/usr/bin/env bash
# scripts/check-references.sh — Verify all internal cross-references in swarm docs.
# Scans references/*.md and prompts/*.md for paths like:
#   prompts/foo.md, scripts/bar.sh, references/baz.md, agents/swarm-*.md
# and confirms each exists in the repo root.
# Exits 0 if all references valid; exits 1 with list of broken links.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FAIL=0

echo "=== Cross-reference integrity check ==="
echo ""

# Files to scan
FILES=$(find "$REPO_ROOT/skills/swarm/references" "$REPO_ROOT/skills/swarm/prompts" \
  -name "*.md" -type f 2>/dev/null || true)

if [ -z "$FILES" ]; then
  echo "  (no markdown files found to scan)"
  echo ""
  echo "✅ All cross-references valid."
  exit 0
fi

for f in $FILES; do
  # Extract internal cross-references: patterns like `prompts/X.md`, `scripts/Y.sh`,
  # `references/Z.md`, `agents/swarm-*.md`.
  # Use perl with negative lookbehind (?<![\w/]) to exclude matches that are
  # substrings of longer external paths (e.g. smolagents/agents.py, orchestration/prompts/foo.py).
  refs=$(perl -ne 'while (/(?<![\w\/])(prompts|scripts|references|agents)\/([a-zA-Z0-9._-]+)\.(md|sh|py)/g) { print "$1/$2.$3\n" }' "$f" 2>/dev/null | sort -u || true)
  for ref in $refs; do
    # Build candidate paths
    found=0
    # Try relative to skills/swarm/
    if [ -f "$REPO_ROOT/skills/swarm/$ref" ]; then found=1; fi
    # Try relative to repo root
    if [ -f "$REPO_ROOT/$ref" ]; then found=1; fi
    if [ "$found" -eq 0 ]; then
      rel_f="${f#$REPO_ROOT/}"
      printf "  ❌ %s → %s (NOT FOUND)\n" "$rel_f" "$ref"
      FAIL=$((FAIL + 1))
    fi
  done
done

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "❌ $FAIL broken reference(s) found."
  exit 1
fi
echo "✅ All cross-references valid."
