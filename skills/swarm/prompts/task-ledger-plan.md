# Task Ledger — Plan (preflight)

**Source**: `semantic-kernel/python/semantic_kernel/agents/orchestration/prompts/_magentic_prompts.py:33-40` (ORCHESTRATOR_TASK_LEDGER_PLAN_PROMPT)
**Used by**: `references/magentic-loop.md` Stage 1 step 2 (after fact-gathering)
**License**: MIT (Microsoft)

## Variables
- `{team}`: bullet list describing each available sub-agent (name + role)

## Output destination
LLM response saved to `.swarm/magentic/{session}/plan.md`.

## Prompt

```
Fantastic. To address this request we have assembled the following team:

{team}

Based on the team composition, and known and unknown facts (see facts.md), please devise a short bullet-point plan for addressing the original request. Remember, there is no requirement to involve all team members — a team member's particular expertise may not be needed for this task.
```

## Output schema
A short bullet-point plan (3-8 bullets typical). Each bullet should mention 1+ team member by name and 1 concrete action.
