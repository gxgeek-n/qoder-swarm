---
name: ulw-loop
description: "Self-referential execution loop with durable ledger. Use when user says 'ulw-loop', 'ulw', 'keep going until done', 'run until verified', '一直跑到完成', '循环直到验证通过'. Runs until all success criteria have captured evidence. Survives context loss via file state in .swarm/ulw-loop/."
---

# ulw-loop

Self-correcting execution loop with evidence-bound completion.

## When to activate

User mentions:
- "ulw-loop" / "ulw"
- "keep going until done" / "run until verified" / "loop until X"
- "一直跑到完成" / "循环直到验证通过"
- Long-running task that needs checkpointed progress

## How to execute

### Step 1 — Bootstrap goal state

ONE `Agent` call (CHEAP model):
```
prompt: "Create durable goal state for: {task}

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
- NOT 'verify it works' - name the tool + expected output
- Include happy path + one edge case minimum"
```

### Step 2 — Execution loop

Repeat until all criteria done OR max_iterations reached:

For each iteration:
1. Read state.json, find first pending criterion
2. ONE `Agent` call (MID model):
```
prompt: "Execute one step toward this criterion.

CRITERION: {criterion.description}
VERIFICATION: {criterion.verification}
LEDGER (prior attempts): {ledger}

STEPS:
1. Do work needed to satisfy criterion
2. Run verification command EXACTLY as stated
3. If passes: update state.json status='done', evidence={output}
4. If fails: append failure to ledger.jsonl, try different approach next iteration

LEDGER ENTRY:
{ iteration, criterion_id, action, result: 'pass'|'fail', evidence }

DELIVERABLE: what was done, which criterion attempted, pass or fail"
```

3. Check state.json — if criterion marked done, increment completed_count
4. Repeat

### Step 3 — Final report

ONE `Agent` call (CHEAP):
```
prompt: "Generate final ULW loop report.
Read .swarm/ulw-loop/state.json and ledger.jsonl

REPORT:
- Task: {task}
- Iterations: {used}/{max}
- Criteria met: {completed}/{total}
- Per criterion: status + evidence summary
- If incomplete: what remains + next steps

Update state.json status → 'completed' or 'paused'"
```

## Resumption (key feature)

If session is interrupted (Ctrl+C, context loss, restart):
- All state is in .swarm/ulw-loop/state.json + ledger.jsonl
- New session reads these and resumes from last incomplete criterion
- Don't restart from scratch — pick up where you left off

The stop-continuation hook (if installed) reminds you when this state exists.

## Budget awareness

Before each iteration, check remaining token budget. If <10%, stop and report partial completion rather than dying mid-loop.

## Model tiers

| Stage | Model |
|-------|-------|
| Bootstrap | `Qwen3.7-Max-DogFooding` (CHEAP) |
| Each iteration | `GLM-5.2` (MID — needs real work) |
| Final report | `Qwen3.7-Max-DogFooding` (CHEAP) |
