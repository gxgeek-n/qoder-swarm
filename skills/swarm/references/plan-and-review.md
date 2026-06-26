# plan-and-review

4-stage adversarial planning. Total cost ~1.80x credit.

## Stage 1 — Parallel research (CHEAP × 2)

Emit TWO Agent calls in ONE message:

```
Agent[explorer]:
TASK: Codebase explorer. Find files, patterns, conventions relevant to: {task}
DELIVERABLE: Structured report — absolute paths, existing patterns, anti-patterns, entry points
SCOPE: Read-only. Never edit.
VERIFY: Every path exists. Every claim cites a file.

Agent[librarian]:
TASK: Librarian. Research external docs, OSS examples, best practices for: {task}
DELIVERABLE: Cited findings — official refs, real examples, pitfalls
SCOPE: External only. Don't touch local code.
VERIFY: Every claim has URL/source citation.
```

## Stage 2 — Plan draft (HEAVY × 1)

```
Agent[planner]:
TASK: Strategic planner. Produce ONE executable work plan for: {task}
CONTEXT: {explorer_output}
RESEARCH: {librarian_output}
DELIVERABLE: Markdown plan with TL;DR / Scope (Must have, Must NOT have) / Execution waves (dependency matrix) / Todos (each: What/References/Acceptance/QA)
SCOPE: Write plan text only. Never edit product code.
VERIFY:
  - Every task atomic and agent-executable
  - Every acceptance criterion has exact command + expected output
  - Zero further interview needed by executor
```

Save plan to `.swarm/plan-and-review/{slug}.md`.

## Stage 3 — Gap analysis (HEAVY × 1)

```
Agent[metis]:
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

## Stage 4 — Review (HEAVY × 1)

```
Agent[momus]:
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
