---
name: plan-and-review
description: "Explore-first planning with adversarial review. Use when the user says 'plan this', 'ulw-plan', '规划', 'break this down', 'plan-and-review', or work has 5+ steps, ambiguous scope, multiple modules, architecture decisions. Spawns explorer + librarian in parallel for research, then planner drafts, metis finds gaps, momus approves or iterates. Saves cost via model tiering (free Qwen for search, GLM for reasoning)."
---

# plan-and-review

Multi-agent adversarial planning. Replaces a single-agent plan with a 4-stage parallel + adversarial flow.

## When to activate

User mentions any of:
- "plan this" / "规划一下" / "做个计划"
- "ulw-plan" / "plan-and-review"
- "break this down" / "拆解"
- Work has ≥5 steps, ambiguous scope, multiple modules, architecture decisions

## How to execute

**Do NOT use the Workflow tool** (the feature gate may be disabled). Instead, spawn agents directly using the `Agent` tool with `subagent_type: "general-purpose"`. Run independent agents **in parallel** by emitting multiple Agent tool calls in a SINGLE message.

### Stage 1 — Parallel Research (CHEAP model)

Send TWO `Agent` calls in one message:

```
Agent 1 (explorer):
prompt: "TASK: Act as a codebase explorer. Find all files, patterns, conventions relevant to: {USER_TASK}
DELIVERABLE: Structured report with relevant absolute paths, existing patterns to follow, anti-patterns to avoid, entry points.
SCOPE: Read-only. Never edit.
VERIFY: Every path exists. Every claim cites a file."

Agent 2 (librarian):
prompt: "TASK: Act as a librarian. Research external docs, OSS examples, best practices for: {USER_TASK}
DELIVERABLE: Cited findings with official doc refs, real-world examples, known pitfalls.
SCOPE: External sources only. Don't inspect local code.
VERIFY: Every claim has URL/source citation."
```

### Stage 2 — Plan (HEAVY model)

ONE `Agent` call after Stage 1 returns:

```
prompt: "TASK: Strategic planner. Produce ONE executable work plan.
USER REQUEST: {USER_TASK}
CODEBASE CONTEXT: {explorer_output}
EXTERNAL RESEARCH: {librarian_output}
DELIVERABLE: Markdown plan with:
## TL;DR
## Scope (Must have / Must NOT have)
## Execution waves (parallel grouping + dependency matrix)
## Todos (each: What to do / References / Acceptance criteria / QA scenarios)
CONSTRAINTS:
- Every task atomic and agent-executable
- Every acceptance criterion verifiable by command
- No 'verify it works' - name exact tool + invocation
- Decision-complete: zero further interview needed"
```

### Stage 3 — Gap Analysis (HEAVY model)

ONE `Agent` call after Stage 2:

```
prompt: "TASK: Metis - pre-planning analyst. Find contradictions, ambiguity, missing constraints, execution risks.
PLAN: {plan_output}
CHECK:
1. Contradictions: two requirements that cannot both be true
2. Ambiguity: terms executor would guess
3. Missing constraints: auth, error handling, concurrency, rollback, tests
4. Execution risks: missing file refs, unreachable criteria, vague QA
DELIVERABLE: Structured gap report + verdict: CLEAR or GAPS FOUND"
```

### Stage 4 — Review (HEAVY model)

ONE `Agent` call after Stage 3:

```
prompt: "TASK: Momus - plan reviewer. Answer: 'Can a capable developer execute this plan without getting stuck?'
PLAN: {plan_output}
GAPS: {gaps_output}
DECISION:
- OKAY (default): 80% clear is good. Approve.
- ITERATE: max 3 fixable gaps planner can patch alone
- REJECT: impossible or needs user decision
DELIVERABLE: **[OKAY]** or **[ITERATE]** or **[REJECT]** + summary + max 3 issues"
```

## Model tiers (default)

| Stage | Model | Reason |
|-------|-------|--------|
| explorer/librarian | `Qwen3.7-Max-DogFooding` (FREE) | Read-only search |
| planner/metis/momus | `GLM-5.2` | Deep reasoning |

If your account doesn't have these models, fall back to whatever's available via `/model`.

## Output

Final user-facing message: summarize the plan, the gap analysis verdict, and the reviewer verdict. Save the plan to `.swarm/plans/{slug}.md`.
