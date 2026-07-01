# ralph

PRD-driven persistence loop. Keeps working until ALL user stories pass acceptance and a reviewer signs off. Wraps `start-work` (execution) + `five-agent-review` (verification) into a single bounded loop.

## When to activate

User says: "ralph" / "persistence loop" / "不停直到完成" / "all stories pass" / "PRD-driven" / "don't stop until done" / "keep going until complete"

## State files

| File | Purpose |
|------|---------|
| `.swarm/ralph/prd.json` | User stories with `passes` flags — the source of truth |
| `.swarm/ralph/progress.json` | Iteration counter, stories passed/remaining, per-story attempt log |

## Step 0 — Scaffold PRD (CHEAP × 1, first run only)

If `.swarm/ralph/prd.json` does not exist, dispatch an explorer to create it:

```
Agent[swarm-explorer]:
TASK: Break down the user request into user stories and write prd.json
REQUEST: {original user task}
OUTPUT .swarm/ralph/prd.json:
  {
    "stories": [
      {
        "id": "S1",
        "description": "<what this story delivers>",
        "acceptance": "<verifiable criterion — name exact command or file check>",
        "passes": false
      }
    ]
  }
RULES:
  - 2-6 stories, each completable in one worker dispatch
  - acceptance MUST be a concrete check (file exists, test passes, grep finds pattern), not "implementation is complete"
  - Order by dependency (foundational stories first)
  - Every story starts with passes: false
DELIVERABLE: path to prd.json + story count
```

Initialize `.swarm/ralph/progress.json`:

```json
{
  "iteration": 0,
  "stories_passed": 0,
  "stories_remaining": 0,
  "story_attempts": {}
}
```

## Step 1 — Pick next story (orchestrator, no agent call)

1. Read `.swarm/ralph/prd.json`
2. Select the first story with `passes: false` (stories are dependency-ordered)
3. If all stories have `passes: true` → jump to Step 4 (final review)
4. Check `progress.json.story_attempts[storyId]`:
   - If attempts ≥ 5 → STOP, report fundamental issue for this story
   - If last 3 attempts have the same error → STOP, report fundamental issue

## Step 2 — Dispatch worker (MID × 1)

Delegate to `swarm-worker` using the `start-work` TASK contract:

```
Agent[swarm-worker]:
TASK: Implement story {story.id}
DESCRIPTION: {story.description}
ACCEPTANCE: {story.acceptance} — run the exact verification and paste real output
FILES: <inferred from story description + existing plan if any>
REFERENCES: skills/swarm/references/start-work.md for worker contract
DELIVERABLE: standard (changed files + verification evidence)
```

On return, read the worker's verification output. Do NOT trust "should work" — require pasted real output.

## Step 3 — Verify + QA (HEAVY × 1)

Dispatch a targeted `swarm-reviewer` on the story's changed files only (not full five-agent — that's Step 4):

```
Agent[swarm-reviewer]:
TASK: Verify story {story.id} against its acceptance criterion
ACCEPTANCE: {story.acceptance}
CHANGED FILES: {list from worker report}
VERIFY:
  1. Re-run the acceptance verification command independently
  2. Check for regressions in files touched by this story
  3. Check edge cases the worker might have missed
VERDICT: PASS | REVISE | FAIL
DELIVERABLE: verdict + list of issues (if any)
```

On verdict:
- **PASS** → set `passes: true` in prd.json for this story, increment `stories_passed`, decrement `stories_remaining` in progress.json. Go to Step 1.
- **REVISE** → increment `story_attempts[storyId]`, append the issue to the story's description as a note. Go to Step 2 with the revised task.
- **FAIL** → increment `story_attempts[storyId]`. If the same root cause appears 3× consecutively, STOP and report. Otherwise go to Step 2 with the failure as additional context.

## Step 4 — Final review (HEAVY × 5, all stories pass)

When every story has `passes: true`, run the full `five-agent-review` pattern on the complete changed-file set across all stories:

1. Read `references/five-agent-review.md`
2. Execute the 5-agent parallel review on all files touched during the loop
3. Collect verdicts

On `5/5 PASS` or `4/5 PASS`:
- Proceed to completion (Step 5)

On `3/5 PASS` or lower:
- Identify which stories' changes caused the failures
- Set those stories back to `passes: false` in prd.json
- Return to Step 1 to re-implement

## Step 5 — Done

1. Write final progress.json with `iteration`, `stories_passed`, `stories_remaining: 0`
2. Emit one-line summary: `"Ralph complete: {N}/{N} stories passed, {M} iterations, reviewer {PASS/FAIL}"`
3. Auto-execute boundary applies: commit locally if all reversible, ask user before push/deploy

## Bounded loop — hard stops

| Condition | Action |
|-----------|--------|
| Story attempts ≥ 5 | STOP, report which story and last error |
| Same error 3× consecutive | STOP, report fundamental issue |
| Total iterations ≥ (stories × 5) | STOP, report exhaustion |
| Worker returns same output twice | Force replan via `plan-and-review` before retrying |

## Composition with other patterns

- **No plan exists?** Run `plan-and-review` first, then feed the plan into Step 0's PRD scaffold.
- **Story needs research?** Delegate to `ultraresearch` mid-story, then continue the loop.
- **Context getting large?** After iteration 10, run context compression (same as `ulw-loop` Step 2 subsection).

## Resumption

All state is in `.swarm/ralph/`. If the session is interrupted:
1. Read `prd.json` — find first `passes: false` story
2. Read `progress.json` — resume iteration counter and attempt log
3. Continue from Step 1

Do not restart from scratch. The PRD is the checkpoint.
