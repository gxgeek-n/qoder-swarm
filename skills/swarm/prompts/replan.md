# Replan — Update facts + plan (triggered on stall)

**Source**: `semantic-kernel/python/semantic_kernel/agents/orchestration/prompts/_magentic_prompts.py:113-138` (FACTS_UPDATE + PLAN_UPDATE prompts)
**Used by**: `references/magentic-loop.md` Stage 2 step 5 (when stall_count >= max_stall AND reset_count < max_reset)
**License**: MIT (Microsoft)

## Variables
- `{task}`: original user request
- `{team}`: bullet list of team members
- `{current_facts}`: contents of `.swarm/magentic/{session}/facts.md`
- `{current_plan}`: contents of `.swarm/magentic/{session}/plan.md`

## Output destination
Two outputs written to `.swarm/magentic/{session}/facts.md` (overwrite) and `.swarm/magentic/{session}/plan.md` (overwrite). The orchestrator makes TWO LLM calls — one for facts, one for plan — using the prompts below.

## Prompt 1: Update facts

```
As a reminder, we are working to solve the following task:

{task}

It's clear we aren't making as much progress as we would like, but we may have learned something new. Please rewrite the following fact sheet, updating it to include anything new we have learned that may be helpful.

Example edits can include (but are not limited to) adding new guesses, moving educated guesses to verified facts, removing incorrect facts, adding new information learned from chat history, etc.

Current fact sheet:

{current_facts}

Output the updated fact sheet using the same 4-heading structure as the original:

  1. GIVEN OR VERIFIED FACTS
  2. FACTS TO LOOK UP
  3. FACTS TO DERIVE
  4. EDUCATED GUESSES
```

## Prompt 2: Update plan

```
Now please devise a new short bullet-point plan, taking into account the updated facts and what we've learned about why the previous plan stalled.

Team:

{team}

Previous plan (what didn't work):

{current_plan}

Output the new plan as a short bullet-point list. Be specific about what's different from the previous plan.
```

## Operational notes

- The orchestrator should reset chat history after replan (per Magentic semantics) so the team sees the new facts+plan fresh.
- `reset_count` increments AFTER successful replan.
- If replan itself fails (LLM error), do NOT increment reset_count and log to `.swarm/magentic/{session}/anomalies.log`.
