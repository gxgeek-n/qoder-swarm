# debugging

Hypothesis-driven debug loop. Runtime truth > code reading.

## Step 1 — Form 3+ hypotheses (HEAVY × 1)

```
Agent[swarm-planner]:
TASK: Form ≥3 competing hypotheses for this bug
SYMPTOM: {symptom}
CONTEXT: {context}
RULES:
  - Runtime truth beats code reading — don't guess from code alone
  - Each FALSIFIABLE: name exact check that confirms/refutes
  - Order by likelihood (most likely first)
  - Include ≥1 "weird" hypothesis (race / stale cache / env mismatch)
DELIVERABLE for each:
  H{N}: [statement]
    Check: [exact command/action]
    If confirmed: [fix description]
    If refuted: [next thing to try]
```

## Step 2 — Investigate IN PARALLEL (CHEAP × N)

Emit ONE Agent call per hypothesis in ONE message:

```
Agent[investigate-H{N}]:
TASK: Investigate hypothesis: {statement}
CHECK: {check_command}
RULES:
  - Run check EXACTLY as stated
  - Report ACTUAL output (no premature summary)
  - Verdict: CONFIRMED | REFUTED | INCONCLUSIVE
  - If CONFIRMED: precise root cause
  - If REFUTED: what evidence actually showed
  - If INCONCLUSIVE: what additional check disambiguates
```

## Step 3 — Minimal fix (MID × 1)

Find the CONFIRMED hypothesis. If none confirmed but strong evidence in one, treat as confirmed.

```
Agent[swarm-worker]:
TASK: Fix bug with MINIMAL correct change
SYMPTOM: {symptom}
ROOT CAUSE: {confirmed_evidence}
PROCESS:
  1. Write FAILING TEST FIRST that reproduces the bug
  2. Run it — confirm fails for right reason (not import error)
  3. Apply smallest fix
  4. Test now passes
CONSTRAINTS:
  - Do NOT refactor surrounding code
  - Do NOT add unrelated improvements
  - Test mirrors real conditions, not implementation
```

## Step 4 — Verify (MID × 1)

```
Agent[swarm-reviewer]:
TASK: Verify fix + no regression
SYMPTOM: {symptom}
FIX: {fix_summary}
RUN:
  1. Full test suite (not just new test)
  2. Typecheck/lint
  3. Reproduce original symptom — gone?
  4. git diff — change minimal?
DELIVERABLE:
  - Regression test: PASS/FAIL
  - Full suite: PASS/FAIL (count)
  - Original symptom: GONE / STILL PRESENT
  - Change scope: MINIMAL / OVER-BROAD
  - Overall: FIXED | NEEDS-MORE-WORK
```

## Hard rules

- Hypotheses must be falsifiable (name exact check)
- Run checks, don't read code to "decide"
- One CONFIRMED is enough — stop investigating
- Failing test FIRST, then fix
- Minimal fix — no refactoring while debugging
