#!/bin/bash
# qoder-swarm smoke-test
# Runs the installer against a throwaway QODER_HOME and verifies every
# component lands correctly. Idempotent — leaves no trace on your real
# ~/.qoder/ even on failure.
#
# Usage:
#   bash tests/smoke-test.sh           # full suite
#   bash tests/smoke-test.sh --keep    # leave the tmpdir for inspection
#   bash tests/smoke-test.sh --verbose # print every test command

set -uo pipefail
# Intentionally NOT set -e: we want to count failures across all checks
# rather than abort on the first one.

KEEP_TMP=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --keep)    KEEP_TMP=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d -t qoder-swarm-test.XXXXXX)"
PASS=0
FAIL=0
FAILED_TESTS=()

cleanup() {
  if [ "$KEEP_TMP" -eq 1 ]; then
    echo ""
    echo "Tmpdir kept at: $TMP_HOME"
  else
    rm -rf "$TMP_HOME"
  fi
}
trap cleanup EXIT

log() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "  [trace] $*"
  fi
}

# Test runner: name + bash expression. Pass if exit 0, fail otherwise.
check() {
  local name="$1"
  shift
  log "$*"
  if "$@" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  ✗ %s\n" "$name"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name")
  fi
}

# Like check, but for an expression. Pass means exit 0.
expect() {
  local name="$1"
  local expr="$2"
  log "$expr"
  if eval "$expr" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  ✗ %s\n" "$name"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name")
  fi
}

echo "qoder-swarm smoke-test"
echo "  repo:    $REPO_ROOT"
echo "  tmpdir:  $TMP_HOME"
echo ""

# ─────────────────────────────────────────────────────────────────────
echo "[1/8] Prereq check — installer auxiliary commands"
# ─────────────────────────────────────────────────────────────────────
check "install.sh --help works"      bash "$REPO_ROOT/install.sh" --help
check "install.sh --version works"   bash "$REPO_ROOT/install.sh" --version
check "install.sh --doctor works"    bash "$REPO_ROOT/install.sh" --doctor
check "unknown option rejected"      bash -c "! bash $REPO_ROOT/install.sh --bogus 2>/dev/null"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[2/8] Fresh install into temp QODER_HOME"
# ─────────────────────────────────────────────────────────────────────
INSTALL_LOG="$TMP_HOME/install-1.log"
if bash "$REPO_ROOT/install.sh" "$TMP_HOME" >"$INSTALL_LOG" 2>&1; then
  echo "  ✓ install.sh ran with exit 0"
  PASS=$((PASS + 1))
else
  echo "  ✗ install.sh failed (exit $?). Log:"
  sed 's/^/      /' "$INSTALL_LOG"
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("install.sh first run")
fi

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[3/8] Verify file layout"
# ─────────────────────────────────────────────────────────────────────
expect "workflows/ has 10 .mjs"        "[ \$(ls $TMP_HOME/workflows/*.mjs 2>/dev/null | wc -l) -eq 10 ]"
expect "hooks/ has 2 swarm-*.sh"       "[ \$(ls $TMP_HOME/hooks/swarm-*.sh 2>/dev/null | wc -l) -eq 2 ]"
expect "hooks are executable"          "[ -x $TMP_HOME/hooks/swarm-comment-checker.sh ] && [ -x $TMP_HOME/hooks/swarm-stop-continuation.sh ]"
expect "scripts/image-diff.py present" "[ -f $TMP_HOME/scripts/image-diff.py ]"
expect "scripts/image-diff.py exec"    "[ -x $TMP_HOME/scripts/image-diff.py ]"
expect "scripts/truncate.sh present"  "[ -f $TMP_HOME/scripts/truncate.sh ]"
expect "scripts/truncate.sh exec"     "[ -x $TMP_HOME/scripts/truncate.sh ]"
expect "skills/swarm/SKILL.md"         "[ -f $TMP_HOME/skills/swarm/SKILL.md ]"
expect "skills/swarm/references/ ≥ 10" "[ \$(ls $TMP_HOME/skills/swarm/references/*.md 2>/dev/null | wc -l) -ge 10 ]"
expect "skills marker file present"    "[ -f $TMP_HOME/skills/swarm/.swarm-installed ]"
expect "agents/ has ≥5 swarm-*.md"     "[ \$(ls $TMP_HOME/agents/swarm-*.md 2>/dev/null | wc -l) -ge 5 ]"
expect "dispatch-kit registry.yml"     "[ -f $TMP_HOME/dispatch-kit/registry.yml ]"
expect "dispatch-kit templates/"       "[ \$(ls $TMP_HOME/dispatch-kit/templates/*.md 2>/dev/null | wc -l) -ge 3 ]"
expect "settings.json created"         "[ -f $TMP_HOME/settings.json ]"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[4/8] settings.json content sanity"
# ─────────────────────────────────────────────────────────────────────
check "settings.json is valid JSON" python3 -m json.tool "$TMP_HOME/settings.json"

# Verify the hook command path points at the tmpdir, not ~/.qoder
expect "PostToolUse hook points to tmpdir" \
  "grep -q '$TMP_HOME/hooks/swarm-comment-checker.sh' $TMP_HOME/settings.json"
expect "Stop hook points to tmpdir" \
  "grep -q '$TMP_HOME/hooks/swarm-stop-continuation.sh' $TMP_HOME/settings.json"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[5/8] YAML frontmatter validity for every swarm-* agent"
# ─────────────────────────────────────────────────────────────────────
for agent in "$TMP_HOME/agents/"swarm-*.md; do
  name=$(basename "$agent" .md)
  if python3 -c "
import re, sys, yaml
text = open('$agent').read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m: sys.exit(1)
data = yaml.safe_load(m.group(1))
required = {'name', 'description', 'tools'}
assert required.issubset(data.keys()), f'missing: {required - set(data.keys())}'
" 2>/dev/null; then
    printf "  ✓ %s frontmatter OK\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  ✗ %s frontmatter invalid\n" "$name"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name frontmatter")
  fi
done

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[6/8] image-diff.py output is valid JSON with expected fields"
# ─────────────────────────────────────────────────────────────────────
REF_PNG="$TMP_HOME/ref.png"
ACT_PNG="$TMP_HOME/act.png"
python3 -c "
from PIL import Image
ref = Image.new('RGBA', (64, 64), (255, 255, 255, 255))
act = Image.new('RGBA', (64, 64), (255, 255, 255, 255))
for y in range(0, 16):
    for x in range(48, 64):
        act.putpixel((x, y), (255, 0, 0, 255))
ref.save('$REF_PNG')
act.save('$ACT_PNG')
" 2>/dev/null
if [ -f "$REF_PNG" ] && [ -f "$ACT_PNG" ]; then
  DIFF_OUT="$TMP_HOME/diff.json"
  if python3 "$TMP_HOME/scripts/image-diff.py" "$REF_PNG" "$ACT_PNG" >"$DIFF_OUT" 2>&1; then
    check "image-diff JSON parses"         python3 -m json.tool "$DIFF_OUT"
    expect "similarity is 94"              "[ \$(python3 -c 'import json;print(json.load(open(\"$DIFF_OUT\"))[\"similarityScore\"])') -eq 94 ]"
    expect "diffPixels is 256"             "[ \$(python3 -c 'import json;print(json.load(open(\"$DIFF_OUT\"))[\"diffPixels\"])') -eq 256 ]"
    expect "hotspots is 4"                 "[ \$(python3 -c 'import json;print(len(json.load(open(\"$DIFF_OUT\"))[\"hotspots\"]))') -eq 4 ]"
  else
    printf "  ✗ image-diff.py crashed:\n"
    sed 's/^/      /' "$DIFF_OUT"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("image-diff.py runs")
  fi
else
  printf "  ⚠ skipped image-diff tests (Pillow missing or PNG synth failed)\n"
fi

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[7/8] Idempotency — re-run install and confirm no duplicate hooks"
# ─────────────────────────────────────────────────────────────────────
INSTALL_LOG2="$TMP_HOME/install-2.log"
bash "$REPO_ROOT/install.sh" "$TMP_HOME" >"$INSTALL_LOG2" 2>&1
HOOK_COUNT_PRE=$(grep -c "swarm-comment-checker.sh" "$TMP_HOME/settings.json")
expect "PostToolUse swarm hook appears exactly once after re-install" \
  "[ $HOOK_COUNT_PRE -eq 1 ]"
expect "Nothing-to-do message printed on second run" \
  "grep -q 'Nothing to do' $INSTALL_LOG2"

# Preserve unrelated user hook: inject one, re-run, verify it survived
python3 -c "
import json
with open('$TMP_HOME/settings.json') as f:
    s = json.load(f)
s['hooks'].setdefault('PreToolUse', []).append({
    'matcher': 'Bash',
    'hooks': [{'type': 'command', 'command': '/bin/echo user-hook'}],
})
s['customField'] = 'must-survive-reinstall'
with open('$TMP_HOME/settings.json', 'w') as f:
    json.dump(s, f, indent=2)
"
bash "$REPO_ROOT/install.sh" "$TMP_HOME" >/dev/null 2>&1
expect "user PreToolUse hook preserved after re-install" \
  "grep -q 'user-hook' $TMP_HOME/settings.json"
expect "user customField preserved after re-install" \
  "grep -q 'must-survive-reinstall' $TMP_HOME/settings.json"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[7.5/8] Legacy skill archival"
# ─────────────────────────────────────────────────────────────────────
# Simulate a pre-existing user-managed skill directory with the old
# .swarm-installed marker — the installer should archive it (not delete
# user content) and leave non-swarm dirs untouched.
mkdir -p "$TMP_HOME/skills/debugging"
touch "$TMP_HOME/skills/debugging/.swarm-installed"
echo "user content" > "$TMP_HOME/skills/debugging/user-note.txt"
mkdir -p "$TMP_HOME/skills/not-swarm"
echo "not ours" > "$TMP_HOME/skills/not-swarm/file.txt"

bash "$REPO_ROOT/install.sh" "$TMP_HOME" >/dev/null 2>&1

expect "archive dir created"        "[ -d $TMP_HOME/.swarm-archive ]"
expect "legacy dir archived"        "[ ! -d $TMP_HOME/skills/debugging ]"
expect "user content preserved"     "ls $TMP_HOME/.swarm-archive/*/debugging/user-note.txt"
expect "non-swarm dir untouched"    "[ -d $TMP_HOME/skills/not-swarm ]"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[8/8] Uninstall round-trip"
# ─────────────────────────────────────────────────────────────────────
python3 "$REPO_ROOT/install-settings.py" --qoder-home "$TMP_HOME" --uninstall >/dev/null 2>&1
expect "swarm-comment-checker hook removed" \
  "! grep -q 'swarm-comment-checker.sh' $TMP_HOME/settings.json"
expect "swarm-stop-continuation hook removed" \
  "! grep -q 'swarm-stop-continuation.sh' $TMP_HOME/settings.json"
expect "user-hook still present after uninstall" \
  "grep -q 'user-hook' $TMP_HOME/settings.json"
expect "user customField still present after uninstall" \
  "grep -q 'must-survive-reinstall' $TMP_HOME/settings.json"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "  Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "    - $t"
  done
fi
echo "─────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS assertions passed"
fi
exit "$FAIL"
