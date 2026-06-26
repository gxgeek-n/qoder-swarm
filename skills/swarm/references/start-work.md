# start-work

Pure orchestration. **Main agent NEVER writes code.**

## Pre-flight

If no plan exists in `.swarm/plan-and-review/` or user didn't supply a plan:
→ Run `plan-and-review.md` flow first, then continue.

## Step 1 — Parse plan into dependency-graph waves (CHEAP × 1)

```
Agent[swarm-explorer]:
TASK: Parse the plan into a dependency-graph wave schedule.
PLAN: {plan_content}

INPUT FORMAT (each task in the plan must have):
  ### T<n>: <Title>
  - **depends_on**: [T-id, ...]    # empty array if no deps
  - **files**: <paths>
  - **acceptance**: <verifiable criterion>
  - **description**: <details>

OUTPUT (JSON, deterministic):
  {
    "waves": [
      { "wave": 1, "tasks": [{"id": "T1", "title": ..., ...}] },   # tasks with depends_on == []
      { "wave": 2, "tasks": [...] },                                # tasks all of whose deps are in Wave 1
      ...
    ],
    "skipped": []   # any task with unresolved deps (cite the missing dep)
  }

ALGORITHM (apply mechanically, do not improvise):
  1. Parse every task block, extract id + depends_on + files + acceptance + description
  2. Build directed graph: edge from each dep → this task
  3. Detect cycles → list in "skipped" with reason, abort
  4. Topological sort by Kahn's algorithm:
     - Wave 1 = all nodes with in-degree 0
     - For each next wave: nodes whose deps all landed in earlier waves
  5. Maximize parallelism within each wave (no further reordering)

SCOPE: Analysis only. Do not edit anything.
DELIVERABLE: The JSON above, nothing else.
```

This is **not** a flow constraint — the planner already wrote the deps; the parser just turns them into a schedule. If the plan was written without `depends_on` fields, fall back to "one wave per task in plan order" and warn the user.

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
Agent[swarm-reviewer]:
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
