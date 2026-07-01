# start-work

Pure orchestration. **Main agent NEVER writes code.**

## Pre-flight

If no plan exists in `.swarm/plan-and-review/` or user didn't supply a plan:
→ Run `plan-and-review.md` flow first, then continue.
If `.swarm/plan-and-review/handoff.md` exists, read it first (per the Inter-stage handoff template in `_shared.md`) — it summarizes what the planning stage decided and what risks to watch for.

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

## Step 1.5 — Mirror to native TodoWrite (UI sync)

Right after parsing the plan into waves, call the native `TodoWrite` tool with one todo per task:
- description: `"{task-id}: {task title}"`
- status: `"pending"` initially

Update status to:
- `"in_progress"` when the wave dispatches the task's worker
- `"completed"` when its verification command passes
- `"blocked"` when its dependency is `needs-fix`

This makes wave progress visible in the user's main UI without requiring them to read .swarm/ files.

Don't batch updates — emit a `TodoWrite` call as soon as a task's status changes (per the tool's own contract).

Borrowed from: native Qoder TodoWrite + the existing dispatch pattern. Cost is near-zero (1 tool call per status change × N tasks) and unlocks visibility.

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

## Concurrency limits (per-model FIFO)

Source: OmO ConcurrencyManager (`packages/omo-opencode/src/features/background-agent/concurrency.ts`, MIT).

For each worker to dispatch, the orchestrator should first attempt to acquire a slot:

```bash
scripts/swarm-concurrency.sh acquire "$MODEL" "$TASK_ID"
```

- Exit 0 → slot acquired, dispatch immediately
- Exit 1 → at capacity, task queued; orchestrator should either wait (sleep 5s + retry) or defer to next wave

After the worker completes:
```bash
scripts/swarm-concurrency.sh release "$MODEL" "$TASK_ID"
```

Default limit: 5 concurrent workers per model (mirrors OmO's `DEFAULT_CONCURRENCY`). Override:
- Global: `SWARM_CONCURRENCY_DEFAULT=3`
- Per-model: `scripts/swarm-concurrency.sh config GLM-5.2 8`

Why: prevents cascade failure when a model provider rate-limits or degrades. Without this, a 10-worker wave all hitting Ultimate → 5 succeed, 5 fail with 429 → whole wave retried → doubles cost.

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

## Step 4 — Failure recovery (when any item is needs-fix)

If Step 3 returns any `needs-fix` items, before re-spawning workers, classify the failures so we batch correctly.

```
Agent[swarm-error-coordinator]:
TASK: Classify failures from the verification report
INPUT: Review report showing needs-fix items + the original plan
OUTPUT: For each failed item, one classification:
  - SAME_ROOT_CAUSE: likely shares an underlying issue with another fail (batch-fix)
  - INDEPENDENT: separate issue (fix individually)
  - CASCADE: caused by another failure (fix the root first, this one likely resolves)
  - FLAKY: intermittent (re-run verification before re-fix)
  Confidence: HIGH | MEDIUM | LOW per classification
DELIVERABLE: Recovery plan — which items to fix, in what order, with which workers.
SCOPE: Analysis only. Do not edit code or run fixes.
```

If error-coordinator agent is not installed (e.g., qoder-swarm not installed), fall back to manual triage: orchestrator reads the verification report and groups items by inferred root cause.

## Hard rules

- Main agent NEVER uses Edit/Write/Bash for implementation
- Catch yourself about to write code? → Spawn a worker instead
- If a worker's `false-positive` is found, re-spawn that worker with the failure evidence
- Don't claim DONE while any item is `needs-fix`
