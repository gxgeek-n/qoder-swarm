---
name: debugging
description: "Hypothesis-driven debugging with parallel investigation. Use when user says 'debug this', 'why is X broken', 'trace this bug', 'reproduce and fix', 'silent failure', '调试', '为什么报错', '排查问题', or hits a runtime issue. Forms 3+ competing hypotheses, investigates them in parallel, confirms root cause with runtime evidence, applies minimal fix, verifies."
---

# debugging

Hypothesis-driven debug loop. Runtime truth beats code reading.

## When to activate

User mentions:
- "debug this" / "why is X broken" / "trace this bug"
- "silent failure" / "HTTP 200 but empty"
- "调试" / "为什么报错" / "排查问题" / "为啥不工作"

## How to execute

### Step 1 — Form 3+ hypotheses

ONE `Agent` call (HEAVY model — needs reasoning):
```
prompt: "Form at least 3 competing hypotheses for this bug.
SYMPTOM: {symptom}
CONTEXT: {context}

RULES:
- Runtime truth beats code reading - don't just guess from code
- Each hypothesis FALSIFIABLE: name exact check that confirms/refutes
- Order by likelihood (most likely first)
- Include one 'weird' hypothesis (race, stale cache, env mismatch)

DELIVERABLE for each:
H{N}: [statement]
  Check: [exact command/action]
  If confirmed: [fix description]
  If refuted: [next thing to try]"
```

### Step 2 — Investigate hypotheses IN PARALLEL

Emit ONE `Agent` call per hypothesis IN A SINGLE MESSAGE (CHEAP model):
```
For each hypothesis H{N}:
  Agent({
    description: "Investigate H{N}",
    prompt: "Investigate hypothesis: {statement}

CHECK: {check_command}

RULES:
- Run the check EXACTLY as stated
- Report ACTUAL output (don't summarize prematurely)
- Verdict: CONFIRMED | REFUTED | INCONCLUSIVE
- If CONFIRMED: describe root cause precisely
- If REFUTED: what evidence actually showed
- If INCONCLUSIVE: what additional check would disambiguate"
  })
```

### Step 3 — Minimal fix

Find the CONFIRMED hypothesis, then ONE `Agent` call (MID model):
```
prompt: "Fix this bug with the MINIMAL correct change.
SYMPTOM: {symptom}
ROOT CAUSE: {confirmed_evidence}

PROCESS:
1. Write FAILING TEST FIRST that reproduces the bug
2. Run it - confirm fails for right reason
3. Apply smallest fix
4. Test now passes

CONSTRAINTS:
- Do NOT refactor surrounding code
- Do NOT add unrelated improvements
- Test must mirror real conditions, not implementation"
```

### Step 4 — Verify no regression

ONE `Agent` call (MID model):
```
prompt: "Verify fix is correct and no regressions.
SYMPTOM: {symptom}
FIX: {fix_summary}

RUN:
1. Full test suite (not just new test)
2. Typecheck/lint
3. Reproduce original symptom - is it gone?
4. git diff - is change minimal?

DELIVERABLE:
- Regression test: PASS/FAIL
- Full suite: PASS/FAIL (count)
- Original symptom: GONE / STILL PRESENT
- Change scope: MINIMAL / OVER-BROAD
- Overall: FIXED | NEEDS-MORE-WORK"
```

## Critical patterns

- **Hypotheses must be falsifiable** — name the exact check
- **Run checks, don't read code** — observed output > plausible story
- **One CONFIRMED is enough** — don't keep investigating once root cause is clear
- **Failing test first** — pin bug before fixing
- **Minimal fix** — don't refactor while debugging

## Model tiers

| Stage | Model |
|-------|-------|
| Hypothesize | `GLM-5.2` (needs reasoning) |
| Investigate | `Qwen3.7-Max-DogFooding` (just runs commands) |
| Fix | `GLM-5.2` (code editing) |
| Verify | `GLM-5.2` (judgment) |
