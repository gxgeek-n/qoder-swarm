# ulw-loop

Self-correcting execution loop with evidence-bound completion. Survives context loss.

## Step 1 — Bootstrap goal state (CHEAP × 1)

```
Agent[swarm-explorer]:
TASK: Create durable goal state for: {task}
CREATE .swarm/ulw-loop/state.json:
  {
    task: '{task}',
    status: 'active',
    iteration: 0,
    max_iterations: {max},
    criteria: [
      {
        id: 'C1',
        description: '<verifiable condition>',
        verification: '<exact command that proves it>',
        status: 'pending',
        evidence: null
      }
    ]
  }
CREATE .swarm/ulw-loop/ledger.jsonl (empty)
RULES for criteria:
  - 2-5 criteria
  - Each has exact verification command
  - NOT "verify it works" — name the tool + expected output
  - Include happy path + ≥1 edge case
```

## Step 2 — Execution loop

Repeat until all criteria done OR max_iterations reached:

For each iteration:
1. Read `state.json`, find first pending criterion
2. ONE Agent call (MID):

```
Agent[loop-iter-{N}]:
TASK: Execute one step toward this criterion
CRITERION: {criterion.description}
VERIFICATION: {criterion.verification}
LEDGER (prior attempts): {ledger}
STEPS:
  1. Do work needed to satisfy criterion
  2. Run verification command EXACTLY as stated
  3. If passes: update state.json status='done', evidence={output}
  4. If fails: append failure to ledger.jsonl, try different approach next iteration
LEDGER ENTRY (append one line):
  { iteration, criterion_id, action, result: 'pass'|'fail', evidence }
DELIVERABLE: what was done, which criterion attempted, pass or fail
```

3. If criterion marked done → increment completed count
4. Repeat

## Step 3 — Final report (CHEAP × 1)

```
Agent[swarm-explorer]:
TASK: Generate final ULW loop report
INPUT: .swarm/ulw-loop/state.json + ledger.jsonl
REPORT:
  - Task: {task}
  - Iterations: {used}/{max}
  - Criteria met: {completed}/{total}
  - Per criterion: status + evidence summary
  - If incomplete: what remains + next steps
Update state.json status → 'completed' or 'paused'
```

## Resumption (KEY FEATURE)

If session is interrupted (Ctrl+C, context loss, restart):
- All state is in `.swarm/ulw-loop/state.json` + `ledger.jsonl`
- New session reads these and resumes from last incomplete criterion
- Don't restart from scratch

Stop-continuation hook (if installed) alerts when this state exists.

## Budget awareness

Before each iteration, check remaining token budget. If <10%, stop and report partial completion rather than dying mid-loop.
