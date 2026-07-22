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
expect "hooks/ has 3 swarm-*.sh"       "[ \$(ls $TMP_HOME/hooks/swarm-*.sh 2>/dev/null | wc -l) -eq 3 ]"
expect "hooks are executable"          "[ -x $TMP_HOME/hooks/swarm-comment-checker.sh ] && [ -x $TMP_HOME/hooks/swarm-stop-continuation.sh ] && [ -x $TMP_HOME/hooks/swarm-hang-notifier.sh ]"
expect "scripts/image-diff.py present" "[ -f $TMP_HOME/scripts/image-diff.py ]"
expect "scripts/image-diff.py exec"    "[ -x $TMP_HOME/scripts/image-diff.py ]"
expect "scripts/truncate.sh present"      "[ -f $TMP_HOME/scripts/truncate.sh ]"
expect "scripts/truncate.sh exec"         "[ -x $TMP_HOME/scripts/truncate.sh ]"
expect "scripts/task-dag.sh present"       "[ -f $TMP_HOME/scripts/task-dag.sh ]"
expect "scripts/task-dag.sh exec"          "[ -x $TMP_HOME/scripts/task-dag.sh ]"
expect "scripts/file-overlap.sh present"   "[ -f $TMP_HOME/scripts/file-overlap.sh ]"
expect "scripts/file-overlap.sh exec"      "[ -x $TMP_HOME/scripts/file-overlap.sh ]"
expect "scripts/swarm-state.sh present"    "[ -f $TMP_HOME/scripts/swarm-state.sh ]"
expect "scripts/swarm-state.sh exec"       "[ -x $TMP_HOME/scripts/swarm-state.sh ]"
expect "scripts/swarm-watchdog.py present" "[ -f $TMP_HOME/scripts/swarm-watchdog.py ]"
expect "scripts/swarm-watchdog.py exec"    "[ -x $TMP_HOME/scripts/swarm-watchdog.py ]"
expect "skills/swarm/SKILL.md"         "[ -f $TMP_HOME/skills/swarm/SKILL.md ]"
expect "skills/swarm/references/ ≥ 10" "[ \$(ls $TMP_HOME/skills/swarm/references/*.md 2>/dev/null | wc -l) -ge 10 ]"
expect "skills marker file present"    "[ -f $TMP_HOME/skills/swarm/.swarm-installed ]"
expect "agents/ has ≥5 swarm-*.md"     "[ \$(ls $TMP_HOME/agents/swarm-*.md 2>/dev/null | wc -l) -ge 5 ]"
expect "dispatch-kit registry.yml"     "[ -f $TMP_HOME/dispatch-kit/registry.yml ]"
expect "dispatch-kit templates/"       "[ \$(ls $TMP_HOME/dispatch-kit/templates/*.md 2>/dev/null | wc -l) -ge 3 ]"
expect "settings.json created"         "[ -f $TMP_HOME/settings.json ]"

# ─── v3 functional tests ─────────────────────────────────────────
# Test task-dag.sh: add, list, done, auto-unblock
DAG_TMP="${TMP_HOME}/dag-test"
mkdir -p "$DAG_TMP/.swarm"
(
  cd "$DAG_TMP"
  SWARM_HOME="$DAG_TMP" "$TMP_HOME/scripts/task-dag.sh" add A "task A" --owner test >/dev/null 2>&1
  SWARM_HOME="$DAG_TMP" "$TMP_HOME/scripts/task-dag.sh" add B "task B" --depends A --owner test >/dev/null 2>&1
)
expect "task-dag.sh basic add creates 2 tasks" \
  "[ \"\$(SWARM_HOME=$DAG_TMP \"$TMP_HOME/scripts/task-dag.sh\" list 2>/dev/null | grep -c '^[AB]')\" = \"2\" ]"
expect "task-dag.sh B is blocked while A pending" \
  "SWARM_HOME=$DAG_TMP \"$TMP_HOME/scripts/task-dag.sh\" list --status blocked 2>/dev/null | grep -q '^B'"
(
  cd "$DAG_TMP"
  SWARM_HOME="$DAG_TMP" "$TMP_HOME/scripts/task-dag.sh" done A >/dev/null 2>&1
)
expect "task-dag.sh auto-unblock: B becomes pending after A done" \
  "SWARM_HOME=$DAG_TMP \"$TMP_HOME/scripts/task-dag.sh\" list --status pending 2>/dev/null | grep -q '^B'"
rm -rf "$DAG_TMP"

# Test file-overlap.sh: no-op case (HEAD vs HEAD)
expect "file-overlap.sh HEAD vs HEAD returns 'No overlap'" \
  "(cd \"$REPO_ROOT\" 2>/dev/null && \"$TMP_HOME/scripts/file-overlap.sh\" check HEAD HEAD 2>/dev/null | grep -q 'No overlap')"

# Test swarm-state.sh: wrapper forwards correctly
expect "swarm-state.sh --help shows Usage" \
  "\"$TMP_HOME/scripts/swarm-state.sh\" --help 2>/dev/null | grep -q 'Usage'"
expect "swarm-state.sh status runs without error on fresh dir" \
  "(cd /tmp && SWARM_HOME=/tmp/empty-swarm-test-\$\$ \"$TMP_HOME/scripts/swarm-state.sh\" status 2>/dev/null | grep -E 'Tasks|Memory' >/dev/null)"

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

# Exact JSON membership check — grep '"Agent"' would false-positive on hook
# matchers (PreToolUse Agent hooks).
expect "permissions.allow contains Agent rule" \
  "python3 -c 'import json,sys; sys.exit(0 if \"Agent\" in json.load(open(\"$TMP_HOME/settings.json\")).get(\"permissions\",{}).get(\"allow\",[]) else 1)'"
expect "UserPromptSubmit registers swarm-hang-notifier.sh" \
  "grep -q 'swarm-hang-notifier.sh' $TMP_HOME/settings.json"

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

# ─── v3 perf regression test ─────────────────────────────────
# Bug fixed: detect_cycle was O(n²) via awk-per-node, 50-task insert took 26s.
# After python3 DFS rewrite: ~3-4s. 10s threshold gives CI slack.
PERF_TMP="${TMP_HOME}/perf-test"
mkdir -p "$PERF_TMP/.swarm"
PERF_START=$(date +%s)
(
  cd "$PERF_TMP"
  for i in $(seq 0 49); do
    if [ "$i" -eq 0 ]; then
      SWARM_HOME="$PERF_TMP" "$TMP_HOME/scripts/task-dag.sh" add "t$i" "task$i" >/dev/null 2>&1
    else
      SWARM_HOME="$PERF_TMP" "$TMP_HOME/scripts/task-dag.sh" add "t$i" "task$i" --depends "t$((i-1))" >/dev/null 2>&1
    fi
  done
)
PERF_END=$(date +%s)
PERF_DUR=$((PERF_END - PERF_START))
expect "task-dag.sh: insert 50 chained tasks within 10s (perf regression)" "[ $PERF_DUR -le 10 ]"
echo "  (insert 50 tasks took ${PERF_DUR}s)"
rm -rf "$PERF_TMP"

# ─── v3 jq-fallback test (when python3 is missing) ─────────────────
# detect_cycle prefers python3 but falls back to pure jq.
# SWARM_FORCE_JQ=1 forces the jq path even when python3 is available.
JQ_TMP="${TMP_HOME}/jq-fallback-test"
mkdir -p "$JQ_TMP/.swarm"
# Basic add chain via jq path
SWARM_HOME="$JQ_TMP" SWARM_FORCE_JQ=1 "$TMP_HOME/scripts/task-dag.sh" add JA "alpha" >/dev/null 2>&1
SWARM_HOME="$JQ_TMP" SWARM_FORCE_JQ=1 "$TMP_HOME/scripts/task-dag.sh" add JB "beta" --depends JA >/dev/null 2>&1
expect "task-dag.sh jq fallback: add+depend chain works" \
  "[ \"\$(SWARM_HOME=$JQ_TMP $TMP_HOME/scripts/task-dag.sh list 2>/dev/null | grep -c '^J[AB]')\" = '2' ]"
# Cycle detection via jq path: craft cyclic state and verify add is rejected
cat > "$JQ_TMP/.swarm/tasks.json" <<'EOJ'
{"tasks":{
  "JX":{"id":"JX","title":"x","status":"pending","blocked_by":["JY"],"blocks":["JY"],"owner":"","created":"","updated":""},
  "JY":{"id":"JY","title":"y","status":"pending","blocked_by":["JX"],"blocks":["JX"],"owner":"","created":"","updated":""}
}}
EOJ
# task-dag.sh exits 1 when a cycle is detected; pipefail (set above) would
# make the pipeline fail even when grep succeeds. Swallow the exit with || true.
expect "task-dag.sh jq fallback: cycle reachable through existing X<->Y rejected" \
  "{ SWARM_HOME=$JQ_TMP SWARM_FORCE_JQ=1 $TMP_HOME/scripts/task-dag.sh add JZ z --depends JX 2>&1 || true; } | grep -q cycle"
rm -rf "$JQ_TMP"

# ─── v4 model-name validity check ─────────────────────────────────
# Each agent's frontmatter `model:` must match qodercli --list-models
# case-sensitively. Otherwise Qoder silently falls back to Auto routing
# and the deliberate model tiering is lost.
# verify-models.sh exits 0 only when all 7 agents pass Layer 1.
expect "verify-models.sh: all swarm-* model names valid in Qoder catalog" \
  "REPO_ROOT=$REPO_ROOT bash $TMP_HOME/scripts/verify-models.sh >/dev/null 2>&1"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[7.6/8] swarm-watchdog.py stall detection"
# ─────────────────────────────────────────────────────────────────────
# Fixtures: "stalled" dir holds one hung Agent dispatch (assistant tool_use,
# silent 2h, sub-agent also silent 2h). "clean" dir holds the states that
# must NOT be flagged: idle session, human-wait (AskUserQuestion), fresh
# dispatch under threshold, and a healthy long worker (parent pending 2h
# but sub-agent transcript still being written).
WD_FIX="$TMP_HOME/wd-fixtures"
mkdir -p "$WD_FIX/stalled/projects/p" "$WD_FIX/clean/projects/p"
python3 - "$WD_FIX" <<'EOF'
import json, os, sys, time
base = sys.argv[1]
def put(d, name, rec, age_min):
    p = os.path.join(base, d, "projects", "p", name)
    open(p, "w").write(json.dumps(rec) + "\n")
    t = time.time() - age_min * 60
    os.utime(p, (t, t))
def put_sub(d, sess, name, age_min):
    p = os.path.join(base, d, "projects", "p", sess[:-len(".jsonl")], "subagents", name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "working"}]}}) + "\n")
    t = time.time() - age_min * 60
    os.utime(p, (t, t))
agent_call = {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Agent", "input": {}}]}}
ask_call = {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "AskUserQuestion", "input": {}}]}}
idle = {"type": "assistant", "message": {"content": [{"type": "text", "text": "done"}]}}
put("stalled", "s1.jsonl", agent_call, 120)
put_sub("stalled", "s1.jsonl", "agent-dead.jsonl", 120)
put("clean", "c1.jsonl", idle, 120)
put("clean", "c2.jsonl", ask_call, 120)
put("clean", "c3.jsonl", agent_call, 1)
put("clean", "c4.jsonl", agent_call, 120)
put_sub("clean", "c4.jsonl", "agent-live.jsonl", 0)
EOF
WD="$TMP_HOME/scripts/swarm-watchdog.py"
expect "watchdog: stalled Agent dispatch flagged (exit 1)" \
  "python3 $WD --qoder-home $WD_FIX/stalled --threshold 30 --no-process-check >/dev/null 2>&1; [ \$? -eq 1 ]"
expect "watchdog: stalled output prints STALLED" \
  "{ python3 $WD --qoder-home $WD_FIX/stalled --threshold 30 --no-process-check 2>/dev/null || true; } | grep -q STALLED"
expect "watchdog: idle/human-wait/fresh/healthy-worker sessions not flagged" \
  "python3 $WD --qoder-home $WD_FIX/clean --threshold 30 --no-process-check >/dev/null 2>&1"

# --write-flag: alert flag for the UserPromptSubmit notifier hook.
WFLAG="$TMP_HOME/test-hang.flag"
expect "watchdog --write-flag: stalled writes flag with session id" \
  "python3 $WD --qoder-home $WD_FIX/stalled --threshold 30 --no-process-check --write-flag $WFLAG >/dev/null 2>&1; grep -q 'session=s1' $WFLAG"
echo "stale content" > "$WFLAG"
expect "watchdog --write-flag: clean removes stale flag" \
  "python3 $WD --qoder-home $WD_FIX/clean --threshold 30 --no-process-check --write-flag $WFLAG >/dev/null 2>&1 && [ ! -f $WFLAG ]"
rm -rf "$WD_FIX" "$WFLAG"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[7.7/8] swarm-hang-notifier.sh UserPromptSubmit hook"
# ─────────────────────────────────────────────────────────────────────
NOTIFIER="$TMP_HOME/hooks/swarm-hang-notifier.sh"
NFLAG="$TMP_HOME/test-notify.flag"
# Flag present → systemMessage on stdout, flag deleted, exit 0.
echo "session=abc silent=45m pending=Agent" > "$NFLAG"
expect "notifier: flag present → systemMessage emitted" \
  "echo '{}' | SWARM_HANG_FLAG=$NFLAG bash $NOTIFIER 2>/dev/null | grep -q systemMessage"
expect "notifier: flag deleted after display (one-shot)" \
  "[ ! -f $NFLAG ]"
# Flag absent → silent, exit 0.
expect "notifier: no flag → silent pass-through" \
  "[ -z \"\$(echo '{}' | SWARM_HANG_FLAG=$NFLAG bash $NOTIFIER 2>/dev/null)\" ]"
rm -f "$NFLAG"

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "[8/8] Uninstall round-trip"
# ─────────────────────────────────────────────────────────────────────
python3 "$REPO_ROOT/install-settings.py" --qoder-home "$TMP_HOME" --uninstall >/dev/null 2>&1
expect "swarm-comment-checker hook removed" \
  "! grep -q 'swarm-comment-checker.sh' $TMP_HOME/settings.json"
expect "swarm-stop-continuation hook removed" \
  "! grep -q 'swarm-stop-continuation.sh' $TMP_HOME/settings.json"
expect "swarm-hang-notifier hook removed" \
  "! grep -q 'swarm-hang-notifier.sh' $TMP_HOME/settings.json"
expect "user-hook still present after uninstall" \
  "grep -q 'user-hook' $TMP_HOME/settings.json"
expect "user customField still present after uninstall" \
  "grep -q 'must-survive-reinstall' $TMP_HOME/settings.json"
# Deliberate: the Agent allow-rule survives uninstall (we can't tell whether
# we added it, and other tools may rely on it).
expect "Agent allow-rule survives uninstall (deliberate)" \
  "python3 -c 'import json,sys; sys.exit(0 if \"Agent\" in json.load(open(\"$TMP_HOME/settings.json\")).get(\"permissions\",{}).get(\"allow\",[]) else 1)'"

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
