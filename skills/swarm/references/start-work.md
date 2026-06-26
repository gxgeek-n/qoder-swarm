# start-work

Pure orchestration. **Main agent NEVER writes code.**

## Pre-flight

If no plan exists in `.swarm/plan-and-review/` or user didn't supply a plan:
→ Run `plan-and-review.md` flow first, then continue.

## Step 1 — Parse plan into waves (CHEAP × 1)

```
Agent[plan-parser]:
TASK: Parse plan into parallel execution waves
PLAN: {plan_content}
DELIVERABLE: JSON —
  { waves: [
      { wave: 1, tasks: [{id, title, description, files, acceptance, depends_on: []}] },
      { wave: 2, tasks: [...] }
  ]}
RULES:
  - No-deps tasks → Wave 1
  - Tasks depending on Wave N → Wave N+1
  - Maximize parallelism within a wave
SCOPE: Analysis only. Do not edit anything.
```

## Step 2 — Execute each wave

For EACH wave, emit ALL its tasks as parallel Agent calls in ONE message:

```
For each task in wave:
  Agent[worker-{id}] MID:
  TASK: Implement {title}
  DESCRIPTION: {description}
  FILES: {files}
  ACCEPTANCE: {acceptance}
  DELIVERABLE:
    1. Files modified
    2. Verification command + expected output
    3. The verification actually run (not "should pass")
  SCOPE: Touch only {files}. Smallest correct change.
  VERIFY: Run the acceptance command. Report actual output.
```

Wait for ALL wave tasks before moving to next wave.

## Step 3 — Adversarial verification (HEAVY × 1)

```
Agent[verifier]:
TASK: Independently verify the work
PLAN: {plan}
WAVE RESULTS: {all_worker_outputs}
PROCESS:
  1. Run full test suite
  2. Run typecheck/lint
  3. Check each acceptance criterion passes (run the commands yourself)
  4. Look for regressions
DELIVERABLE: For each plan item: [confirmed | false-positive | needs-fix] + evidence
Overall: DONE or NEEDS-WORK + items to fix
SCOPE: Verification only. Don't fix.
VERIFY: Verifier must be DIFFERENT context from workers (it is — separate Agent).
```

## Hard rules

- Main agent NEVER uses Edit/Write/Bash for implementation
- Catch yourself about to write code? → Spawn a worker instead
- If a worker's `false-positive` is found, re-spawn that worker with the failure evidence
- Don't claim DONE while any item is `needs-fix`
