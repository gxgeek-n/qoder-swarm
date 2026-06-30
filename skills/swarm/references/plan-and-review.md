# plan-and-review

4-stage adversarial planning. Total cost ~1.80x credit.

### Stage 0 — Check memory (on-demand)

Before launching Stage 1 research, `Glob .swarm/memory/*.md` and `Read` any file whose name obviously matches the task topic. See `docs/memory-protocol.md`. Skip if no obvious match.

## Stage 0.5 — Interview mode (when ambiguous)

**Source**: OmO Prometheus interview mode. Front-loads clarity to prevent plan-reject-replan cycles.

Before launching Stage 1 research, the orchestrator checks if the user's request is ambiguous (see `prompts/interview.md` for detection signals).

**If ambiguous:**
1. Make ONE LLM call using `prompts/interview.md` with `{task}` and detected `{ambiguity_signals}`
2. Present the questions to the user (via normal chat response — NOT a tool call)
3. Wait for user answers
4. Incorporate answers into `{task}` — append "Clarifications: ..." to the task description
5. Proceed to Stage 1 with the enriched task

**If not ambiguous** (common case):
- Skip directly to Stage 1. No LLM call, no delay.

**After receiving answers:**
- Do NOT ask follow-up questions. One round only.
- If user says "你决定" or equivalent → use question defaults → proceed.

**Cost**: 0-1 LLM calls (only when ambiguous). Most concrete tasks skip this entirely.

**Why this matters**: In v1-v4 iterations, the gap analysis found 3+ "ambiguity" issues in every plan. Each ambiguity = one potential replan cycle = 2+ LLM calls wasted. A single interview call saves multiple replan calls.

## Stage 1 — Parallel research (CHEAP × 2)

Emit TWO Agent calls in ONE message:

```
Agent[swarm-explorer]:
TASK: Codebase explorer. Find files, patterns, conventions relevant to: {task}
DELIVERABLE: Structured report — absolute paths, existing patterns, anti-patterns, entry points
SCOPE: Read-only. Never edit.
VERIFY: Every path exists. Every claim cites a file.

Agent[swarm-librarian]:
TASK: Librarian. Research external docs, OSS examples, best practices for: {task}
DELIVERABLE: Cited findings — official refs, real examples, pitfalls
SCOPE: External only. Don't touch local code.
VERIFY: Every claim has URL/source citation.
```

## Stage 2 — Plan draft (HEAVY × 1)

```
Agent[swarm-planner]:
TASK: Strategic planner. Produce ONE executable work plan for: {task}
CONTEXT: {explorer_output}
RESEARCH: {librarian_output}
DELIVERABLE: Markdown plan with TL;DR / Scope (Must have, Must NOT have) / Execution waves (dependency matrix) / Todos (each: What/References/Acceptance/QA)
SCOPE: Write plan text only. Never edit product code.
VERIFY:
  - Every task atomic and agent-executable
  - Every task has machine-readable `depends_on: [T-id, ...]` field (empty array if no deps)
  - Every acceptance criterion has exact command + expected output
  - Zero further interview needed by executor
```

### Required task schema in the plan

Every task in `## Todos` must follow this shape so `start-work` can parse dependencies automatically:

```markdown
### T1: <Title>
- **depends_on**: []          # empty array = Wave 1
- **files**: src/foo.ts, src/foo.test.ts
- **acceptance**: `pnpm test foo` exits 0 with all assertions green
- **description**: <what to do, exhaustive>

### T2: <Title>
- **depends_on**: [T1]         # blocks until T1 done
- **files**: ...
- **acceptance**: ...
- **description**: ...
```

This is **not** a workflow gate — the planner still decides scope, ordering, granularity. The `depends_on` field exists so the executor can compute the dependency graph mechanically instead of re-deriving it from prose.

Save plan to `.swarm/plan-and-review/{slug}.md`.

## Stage 3 — Gap analysis (HEAVY × 1)

```
Agent[swarm-reviewer]:
TASK: Pre-planning analyst. Find contradictions, ambiguity, missing constraints, execution risks
PLAN: {plan_output}
DELIVERABLE: Gap report —
  ## Contradictions (two reqs that can't both be true)
  ## Ambiguity (terms executor would guess + clarifying question)
  ## Missing Constraints (auth, errors, concurrency, rollback, tests)
  ## Execution Risks (missing refs, unreachable criteria, vague QA)
  ## Verdict: CLEAR or GAPS FOUND
SCOPE: Read-only analysis.
VERIFY: Every finding is specific enough to act on.
```

## Stage 3.5 — Hyperplan hostile critics (adversarial stress-test)

**Source**: OmO hyperplan workflow. Deploys hostile critics to try to BREAK the plan before any worker touches code.

After Stage 3 (gap analysis) and BEFORE Stage 4 (reviewer verdict), run one hostile critic pass:

```
Agent[swarm-reviewer]:
TASK: Hostile critic — try to break this plan
PLAN: {plan_output}
GAPS: {gaps_output}
PROMPT: prompts/hyperplan-critic.md
DELIVERABLE: JSON with attacks[] + verdict + top_fatal_flaw
SCOPE: Read-only adversarial analysis. Do not fix — only expose.
```

**Processing the result:**
- `verdict: "ROBUST"` → proceed to Stage 4 (reviewer verdict) normally
- `verdict: "VULNERABLE"` with severity HIGH attacks:
  - If top_fatal_flaw is addressable without replanning → patch the plan inline (add a task or fix an acceptance criterion)
  - If top_fatal_flaw requires fundamental redesign → feed attacks back to Stage 2 planner as additional context, re-run Stage 2 (max 1 replan from hyperplan)
- LOW/MEDIUM attacks → document in gaps, don't replan

**Cost**: 1 additional LLM call (using swarm-reviewer, which is Ultimate model — appropriate for adversarial depth). Total plan-and-review cost goes from ~1.80x → ~2.80x, but saves 1-2 replan cycles downstream.

**Why this matters**: In v1 self-bootstrap, the 5-agent review found 12 blockers AFTER implementation. In v3, it found 3 MAJORs. Moving adversarial critique to planning stage catches these pre-implementation = 10-20x cheaper (no worker credit spent on doomed code).

## Stage 4 — Review (HEAVY × 1)

```
Agent[swarm-reviewer]:
TASK: Plan reviewer. Answer: "Can a capable developer execute this plan without getting stuck?"
PLAN: {plan_output}
GAPS: {gaps_output}
DELIVERABLE: [OKAY] | [ITERATE] | [REJECT] + 1-2 sentence summary + max 3 issues
SCOPE: Read-only.
VERIFY: Approval bias — when in doubt, APPROVE. 80% clear is good enough.
```

If `[ITERATE]`: re-run Stage 2 with the issues as additional context. Max 2 iterations.

## Final output

Surface to user:
1. Plan path: `.swarm/plan-and-review/{slug}.md`
2. Gap verdict (CLEAR or N issues)
3. Reviewer verdict (OKAY / ITERATE / REJECT)
4. One-line next step: "Run `swarm:start-work` to execute" (if approved)
5. **MANDATORY** — Write `.swarm/plan-and-review/handoff.md` per the Inter-stage handoff template in `_shared.md`. The next stage (start-work) reads ONLY this handoff, not the full plan.md or gaps.md. This is how we keep context lean across stages.

## Why handoff.md matters (token budget)

`plan.md` + `gaps.md` + `verdict.md` easily run 1500+ lines combined. If `start-work` reads all three every time, the orchestrator's context spikes 10-15k tokens before dispatching any worker.

The `handoff.md` template (≤30 lines) captures: what was decided, what was rejected, what files are touched, what risks remain. `start-work` reads `handoff.md` and only opens `plan.md` when it needs the exact acceptance command for a specific task.

This pattern is borrowed from openai-agents-python `nest_handoff_history` (`src/agents/handoffs/history.py:71-112`) — compress prior transcript into one summary message instead of forwarding full history.
