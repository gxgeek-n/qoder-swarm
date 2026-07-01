# autopilot

Full autonomous pipeline: idea → planned → implemented → reviewed → committed. Chains all existing patterns into one continuous flow. Survives interruption via `.swarm/autopilot/state.json`.

## When to use

User says "autopilot" / "全自动" / "一键完成" / "full auto" / "hands off" / "build it end to end" / "走完整流程". Task is multi-phase (plan + code + review + commit), not a single-file fix.

## Execution policy

- Each phase must complete before the next begins.
- Bounded loops: QA cycles max 5; if the same error persists 3 times, stop and report.
- Cancel at any phase → write partials + state for resume.
- State lives in `.swarm/autopilot/state.json`.
- Orchestrator emits one-line progress per phase transition (per SKILL.md HUD contract).

## Phase 0 — Interview (when ambiguous)

Before launching Phase 1, check if the user's request is ambiguous (no file paths, function names, or concrete anchors).

**If ambiguous:**
1. Read `prompts/interview.md`, make ONE LLM call with `{task}` and detected ambiguity signals.
2. Present questions to the user via normal chat (NOT a tool call).
3. Wait for answers. Append "Clarifications: ..." to the task description.
4. One round only — no follow-up questions.

**If concrete:** skip directly to Phase 1.

Update `state.json`: `{"phase": "interview-done", "task": "{enriched_task}"}`.

## Phase 1 — Plan and review

Read `references/plan-and-review.md` and execute the full 4-stage flow:
- Stage 0.5 interview (already done if Phase 0 ran)
- Stage 1 parallel research (explorer + librarian)
- Stage 2 plan draft (planner)
- Stage 3 gap analysis (reviewer)
- Stage 3.5 hyperplan hostile critic (reviewer)
- Stage 4 reviewer verdict

If verdict is `[REJECT]`: stop, surface to user.
If verdict is `[OKAY]`: write `.swarm/plan-and-review/handoff.md`, proceed to Phase 2.

Update `state.json`: `{"phase": "planned", "plan_path": ".swarm/plan-and-review/{slug}.md", "verdict": "OKAY"}`.

## Phase 2 — Start work

Read `references/start-work.md` and execute the wave-dispatch flow:
- Parse plan into dependency-graph waves (explorer).
- Dispatch each wave as parallel `swarm-worker` agents (MID tier).
- Wait for all tasks in a wave before next wave.
- Step 3 adversarial verification (reviewer) after final wave.

If verification returns `needs-fix`: route through error-coordinator, re-dispatch failed tasks.

Update `state.json`: `{"phase": "executed", "waves_completed": N, "verification": "DONE|NEEDS-WORK"}`.

## Phase 3 — QA loop (five-agent-review, max 5 cycles)

Read `references/five-agent-review.md` and run the 5-reviewer parallel review.

**Loop:**
```
cycle = 0
while cycle < 5:
    cycle += 1
    dispatch 5 reviewers in parallel
    aggregate verdict
    if 5/5 PASS or 4/5 PASS:
        → proceed to Phase 4
    if 3/5 PASS (NEEDS-FIX):
        dispatch swarm-worker to fix blocking issues
        re-run five-agent-review
    if same error repeats 3 times:
        stop, report fundamental issue to user
    if 2/5 PASS or worse (REJECT):
        → back to Phase 1 (replan), max 1 replan
```

Update `state.json` per cycle: `{"phase": "qa", "cycle": N, "verdict": "k/5 PASS"}`.

## Phase 4 — Validation (multi-perspective)

Dispatch 3 `swarm-reviewer` agents in parallel for final gate:

```
Agent[swarm-reviewer] HEAVY:
TASK: Architecture validation — does the implementation match the plan's design?
PLAN: {plan_path}
CHANGES: {all_modified_files}
DELIVERABLE: <verdict>APPROVED|REJECTED</verdict> + rationale

Agent[swarm-reviewer] HEAVY:
TASK: Security review — input validation, auth, secrets, data exposure
CHANGES: {all_modified_files}
DELIVERABLE: <verdict>APPROVED|REJECTED</verdict> + findings

Agent[swarm-reviewer] HEAVY:
TASK: Code quality — correctness, patterns, error handling, tests
CHANGES: {all_modified_files}
DELIVERABLE: <verdict>APPROVED|REJECTED</verdict> + findings
```

All 3 must APPROVE. Any REJECT → fix via `swarm-worker` + re-validate that perspective only. Max 2 re-validation rounds.

Update `state.json`: `{"phase": "validated", "architecture": "APPROVED", "security": "APPROVED", "quality": "APPROVED"}`.

## Phase 5 — Cleanup

1. Run `make test` (smoke test) — must pass.
2. `git add` only files declared in the plan's `files:` fields (precision staging per git hygiene).
3. `git commit` with structured trailers (see `_shared.md` § Structured commit trailers).
4. `git push` to current branch remote (per auto-execution boundary — reversible).
5. Clear `.swarm/autopilot/`, `.swarm/plan-and-review/`, `.swarm/start-work/` state dirs.
6. Write final summary: phases completed, files changed, commit SHA, push status.

Update `state.json`: `{"phase": "completed", "commit": "{sha}", "pushed": true}`.

## Cancel and resume

**Cancel at any phase:**
- Write current partials to `.swarm/autopilot/partials/`.
- Update `state.json` with `{"phase": "<current>", "status": "cancelled", "resume_hint": "..."}`.
- Stop. Do NOT auto-advance.

**Resume:**
- Read `.swarm/autopilot/state.json`.
- Jump to the phase where `status` was `cancelled`.
- Re-read handoff files from prior phases (plan.md, handoff.md) to rebuild context.
- Continue from that phase.

## State file shape

```json
{
  "task": "<user's original request>",
  "phase": "interview-done|planned|executed|qa|validated|completed",
  "status": "active|cancelled|completed",
  "cycle": 0,
  "plan_path": ".swarm/plan-and-review/{slug}.md",
  "verdict": "OKAY",
  "commit": null,
  "pushed": false,
  "started_at": "<ISO-8601>",
  "updated_at": "<ISO-8601>"
}
```

## Cost estimate

| Phase | Agents | Model tier | Est. credit |
|-------|--------|------------|-------------|
| Phase 0 | 1 LLM call | CHEAP | ~0.1x |
| Phase 1 | 5 agents (research×2, planner, gap, hyperplan, reviewer) | HEAVY | ~2.8x |
| Phase 2 | N workers (waves) | MID | ~1.5x per wave |
| Phase 3 | 5 reviewers × up to 5 cycles | HEAVY | ~2.4x per cycle |
| Phase 4 | 3 reviewers | HEAVY | ~1.5x |
| Phase 5 | 1 commit | — | ~0x |

Total baseline: ~8-12x credit for a typical 5-task plan with 1 QA cycle. Scales with task count and QA iterations.

## Hard rules

- Never skip phases. Phase 0 may be skipped only when the task is concrete.
- Never claim DONE while `state.json` status is not `completed`.
- Never push to main without explicit user confirmation (auto-execution boundary).
- If any phase fails 3 times with the same error, stop and report — do not retry indefinitely.
- Orchestrator NEVER writes code directly. Always dispatch via `swarm-worker`.
