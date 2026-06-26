---
name: start-work
description: "Execute a plan with pure orchestration - main agent never writes code, all implementation delegated to parallel workers with evidence verification. Use when the user says 'start work', 'execute plan', 'implement this plan', '开始干活', '执行计划', '按计划实现'. Requires a plan file or task list. Uses worktree isolation for parallel safety."
---

# start-work

Pure orchestration: main agent NEVER implements, delegates everything to workers.

## When to activate

User mentions:
- "start work" / "execute plan" / "implement this plan"
- "开始干活" / "执行计划" / "按计划实现"
- After plan-and-review completed, user wants to do the work

## Hard rule

**The main agent NEVER writes product code, NEVER edits files, NEVER runs implementation commands.** Every code edit, test write, and QA execution is delegated to a spawned worker.

If you catch yourself about to use Edit/Write/Bash for implementation, STOP. Spawn a worker instead.

## How to execute

### Step 1 — Parse plan into waves

Read the plan file (or task list). Use one `Agent` call:

```
prompt: "Parse this plan into parallel execution waves.
PLAN: {plan}
DELIVERABLE: JSON structure:
{
  waves: [
    { wave: 1, tasks: [{id, title, description, files, acceptance, depends_on: []}] },
    { wave: 2, tasks: [...] }
  ]
}
RULES:
- Tasks with no deps go in Wave 1
- Tasks depending on Wave 1 go in Wave 2
- Maximize parallelism within waves
- Each task: id, title, description, files, acceptance criterion"
```

### Step 2 — Execute each wave

For each wave, spawn ALL tasks IN PARALLEL via multiple `Agent` calls in one message:

```
For each task in wave:
  Agent({
    subagent_type: "general-purpose",
    description: "Worker-{id}: {title}",
    prompt: "TASK: Implement this task completely.
TITLE: {title}
DESCRIPTION: {description}
FILES: {files}
ACCEPTANCE: {acceptance}
RULES:
- Smallest correct change
- Write tests if criterion requires verification
- Do not touch files outside assignment
DELIVERABLE: list modified files + verification command + expected output"
  })
```

Wait for all wave tasks to complete before moving to next wave.

### Step 3 — Adversarial verification

After all waves complete, ONE final `Agent` call:

```
prompt: "Act as adversarial verifier. Check work actually accomplished the plan.
PLAN: {plan}
VERIFY:
1. Run test suite
2. Run typecheck/lint
3. Check each acceptance criterion passes
4. Look for regressions
For each plan item: [confirmed | false-positive | needs-fix] + evidence
Overall: DONE or NEEDS-WORK + items to fix"
```

## Critical patterns

- **Worktree isolation**: When workers must touch overlapping files, instruct them to work in `git worktree add` branches. Main agent merges after.
- **Evidence per task**: Each worker reports exact command + observed output, not "should work".
- **Adversarial verify**: Worker that did the work cannot verify own work. Use independent agent.
- **No silent skips**: If criterion can't be verified, say so explicitly.

## Model tiers

| Role | Model |
|------|-------|
| Plan parser | `Qwen3.7-Max-DogFooding` (CHEAP/FREE) |
| Workers | `GLM-5.2` (MID) |
| Adversarial verifier | `GLM-5.2` (HEAVY) |
