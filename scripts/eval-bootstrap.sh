#!/usr/bin/env bash
# scripts/eval-bootstrap.sh — End-to-end swarm pipeline evaluation (no LLM required).
# Exercises: task-dag lifecycle + file-overlap + swarm-state + truncate.
# Collects: wall time, task count, files touched, assertion results.
# Output: .swarm/eval/runs/<timestamp>.json
set -euo pipefail

SWARM_HOME="${SWARM_HOME:-$PWD}"
EVAL_DIR="${SWARM_HOME}/.swarm/eval"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="${EVAL_DIR}/runs"
RESULT_FILE="${RUN_DIR}/${TIMESTAMP}.json"

mkdir -p "$RUN_DIR"

PASS=0
FAIL=0
START_SEC=$(date +%s)

check() {
  local desc="$1"
  shift
  if eval "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
  fi
}

echo "=== qoder-swarm eval-bootstrap ($TIMESTAMP) ==="
echo ""

# --- Phase 1: Task DAG lifecycle ---
echo "[1/4] Task DAG lifecycle..."
EVAL_TMP=$(mktemp -d)
export SWARM_HOME="$EVAL_TMP"
mkdir -p "$EVAL_TMP/.swarm"

# Add tasks
scripts/task-dag.sh add EVAL-1 "setup" >/dev/null 2>&1
scripts/task-dag.sh add EVAL-2 "implement" --depends EVAL-1 >/dev/null 2>&1
scripts/task-dag.sh add EVAL-3 "review" --depends EVAL-2 >/dev/null 2>&1

check "3 tasks created" "[ \$(scripts/task-dag.sh list | grep -c '^EVAL') -eq 3 ]"
check "EVAL-2 is blocked" "scripts/task-dag.sh list --status blocked | grep -q EVAL-2"
check "EVAL-3 is blocked" "scripts/task-dag.sh list --status blocked | grep -q EVAL-3"

# Complete EVAL-1 → auto-unblock EVAL-2
scripts/task-dag.sh done EVAL-1 >/dev/null 2>&1
check "EVAL-2 unblocked after EVAL-1 done" "scripts/task-dag.sh list --status pending | grep -q EVAL-2"
check "EVAL-3 still blocked" "scripts/task-dag.sh list --status blocked | grep -q EVAL-3"

# Complete EVAL-2 → auto-unblock EVAL-3
scripts/task-dag.sh done EVAL-2 >/dev/null 2>&1
check "EVAL-3 unblocked after EVAL-2 done" "scripts/task-dag.sh list --status pending | grep -q EVAL-3"

# Complete EVAL-3 → all done
scripts/task-dag.sh done EVAL-3 >/dev/null 2>&1
check "all 3 tasks done" "[ \$(scripts/task-dag.sh list --status done | grep -c '^EVAL') -eq 3 ]"

# Cycle detection (jq fallback)
SWARM_FORCE_JQ=1 scripts/task-dag.sh add CYC-A "a" >/dev/null 2>&1
SWARM_FORCE_JQ=1 scripts/task-dag.sh add CYC-B "b" --depends CYC-A >/dev/null 2>&1
cat > "$EVAL_TMP/.swarm/tasks.json" <<'EOJ'
{"tasks":{
  "CYC-X":{"id":"CYC-X","title":"x","status":"pending","blocked_by":["CYC-Y"],"blocks":["CYC-Y"],"owner":"","created":"","updated":""},
  "CYC-Y":{"id":"CYC-Y","title":"y","status":"pending","blocked_by":["CYC-X"],"blocks":["CYC-X"],"owner":"","created":"","updated":""}
}}
EOJ
check "cycle detection (jq fallback)" "! SWARM_FORCE_JQ=1 scripts/task-dag.sh add CYC-Z z --depends CYC-X 2>/dev/null"

# --- Phase 2: File overlap ---
echo "[2/4] File overlap check..."
export SWARM_HOME="$PWD"  # need git repo
check "file-overlap HEAD vs HEAD = no overlap" "scripts/file-overlap.sh check HEAD HEAD 2>&1 | grep -q 'No overlap'"

# --- Phase 3: swarm-state wrapper ---
echo "[3/4] swarm-state wrapper..."
export SWARM_HOME="$EVAL_TMP"
check "swarm-state --help works" "scripts/swarm-state.sh --help 2>&1 | grep -q Usage"
check "swarm-state status runs clean" "[ \$(scripts/swarm-state.sh status 2>&1 | grep -cE 'Tasks|Memory') -gt 0 ]"
check "swarm-state memory list works" "scripts/swarm-state.sh memory list 2>&1"

# --- Phase 4: Truncate utility ---
echo "[4/4] Truncate utility..."
check "truncate passthrough on short input" "[ \"\$(printf 'hi' | scripts/truncate.sh 100)\" = 'hi' ]"
check "truncate actually truncates long input" "[ \$(seq 1 1000 | tr '\\n' 'X' | scripts/truncate.sh 200 | wc -c) -lt 300 ]"

# --- Cleanup & Report ---
rm -rf "$EVAL_TMP"
END_SEC=$(date +%s)
DURATION=$((END_SEC - START_SEC))

echo ""
echo "─────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo "  duration: ${DURATION}s"
echo "─────────────────────────────────────────"

# Write JSON result
export SWARM_HOME="$PWD"
mkdir -p "$RUN_DIR"
cat > "$RESULT_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "duration_sec": $DURATION,
  "passed": $PASS,
  "failed": $FAIL,
  "total": $((PASS + FAIL)),
  "phases": ["task-dag-lifecycle", "file-overlap", "swarm-state", "truncate"],
  "version": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}
EOF

echo ""
echo "Result: $RESULT_FILE"

if [ "$FAIL" -gt 0 ]; then
  echo "❌ EVAL FAILED"
  exit 1
fi
echo "✅ EVAL PASSED"
