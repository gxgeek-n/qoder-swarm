# Context Recovery Prompt (5-Layer)

**Source**: `ClawTeam/clawteam/harness/context_recovery.py:11-161`
**Used by**: orchestrator when re-spawning a sub-agent (after crash, abort, context overflow).
**Goal**: give the re-spawned agent enough context to resume intelligently, not start from scratch.

## When to use
- A sub-agent died mid-task (timeout, crash, manual abort)
- A sub-agent's context overflowed and was compacted
- A sub-agent reports it's "lost" and needs grounding

## Variables (placeholders for orchestrator to fill)
- `{agent_name}`: the re-spawned agent's role (e.g., `swarm-worker`)
- `{role_class}`: `executor` (does work) or `evaluator` (reviews work)
- `{iteration_count}`: how many times this agent has been spawned in this session
- `{prior_summary}`: 1-3 lines summarizing what previous iterations did
- `{own_tasks_table}`: output of `scripts/swarm-state.sh task list --owner {agent_name}` formatted as table
- `{all_tasks_table}`: only included if role_class is evaluator; else empty
- `{git_log_self}`: output of `git log --oneline --author={agent_name} -10`
- `{artifact_list}`: output of `find .swarm/{pattern}/{agent_name}/ -name '*.md' -mtime -1` formatted as bullet list
- `{teammate_oneliners}`: list of `{name}: last_action={...} status={...}` from `scripts/swarm-state.sh status --terse`

## Prompt template

```
You are {agent_name} ({role_class}). You were re-spawned because your previous run did not complete.
This is iteration #{iteration_count}.

## Layer 1 — What you did before (prior summary)
{prior_summary}

## Layer 2 — Your tasks
{own_tasks_table}

{# only if evaluator: #}
### All tasks (evaluator scope)
{all_tasks_table}

## Layer 3 — Your recent commits
{git_log_self}

## Layer 4 — Your artifacts (last 24h)
{artifact_list}

## Layer 5 — What your teammates are doing
{teammate_oneliners}

## What to do next

1. Pick the most recent in_progress or pending task from Layer 2 — that's where to resume.
2. Re-read your latest artifact in Layer 4 to recall mid-state.
3. If a teammate's status (Layer 5) shows they're blocked on you, prioritize that task.
4. After completing each task: `scripts/swarm-state.sh task done <id>` (this auto-unblocks dependents).
5. If you cannot determine where to resume, write your confusion to `.swarm/{pattern}/{agent_name}/recovery-confusion.md` and ask the orchestrator.

Begin by reading your most recent artifact and reporting your understanding of the resume point.
```

## Concrete fill example

For `swarm-worker` re-spawned after crash on T3 of magentic-loop:

```
You are swarm-worker (executor). You were re-spawned because your previous run did not complete.
This is iteration #2.

## Layer 1 — What you did before (prior summary)
Iteration 1 implemented T1 (added prompt file) and started T3 (writing reference doc) but crashed mid-edit.

## Layer 2 — Your tasks
ID    STATUS         OWNER          TITLE
T1    done           swarm-worker   ProgressLedger prompt
T3    in_progress    swarm-worker   Magentic loop reference

## Layer 3 — Your recent commits
0c43edc swarm v2: token-optimization
d4bf42d swarm self-bootstrap: 11 plan tasks

## Layer 4 — Your artifacts (last 24h)
- .swarm/plan-v3/swarm-worker/T1-output.md
- .swarm/plan-v3/swarm-worker/T3-draft.md (incomplete)

## Layer 5 — What your teammates are doing
swarm-reviewer: last_action=reviewed T1 status=idle
swarm-planner: last_action=plan-v3 written status=idle
```

## Hard rules

1. **Always start from Layer 2** — the task DAG is truth. Don't trust memory of "what I was doing".
2. **Prefer in_progress over pending** — finish what you started before claiming new work.
3. **If Layer 5 shows a teammate blocked on you** — that's your top priority.
4. **If recovery prompt is incomplete** (some layer is empty), proceed but flag in recovery-confusion.md.
