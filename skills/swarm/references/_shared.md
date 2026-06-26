# Shared Conventions

All patterns inherit these. The pattern reference adds specifics on top.

## Agent prompt template

Every `Agent` call uses this 4-line header:

```
TASK: <imperative, self-contained instruction>
DELIVERABLE: <exact output shape>
SCOPE: <what to touch / what NOT to touch>
VERIFY: <how to check the deliverable is correct>
```

Then add pattern-specific body.

## Parallel emission

To run N agents in parallel: emit N `Agent` tool calls in **one assistant message**. Don't wait between them.

## Tool

```
Agent({
  subagent_type: "general-purpose",
  description: "<3-5 word label>",
  prompt: "<TASK header + body>"
})
```

## Model tiers

Bind these at top of every pattern execution:
- `CHEAP` = `Qwen3.7-Max-DogFooding` (0.00x, FREE — search, parsing, monitoring)
- `MID` = `GLM-5.2` (0.60x — code, QA, integration)
- `HEAVY` = `GLM-5.2` (0.60x — reasoning, planning, review)

If Qoder's Agent tool doesn't accept a `model` field, prepend the prompt with `Use model: <model_name>.`.

## Error handling

- Agent returns null → treat as inconclusive, don't claim success.
- Agent returns empty → re-spawn with smaller scope ONCE, then surface.
- Verification fails → record in ledger, try next iteration. Don't silently skip.
- Same error 3x → stop, escalate to user with: what tried, what failed, hypothesis.

## State location

Every pattern writes to `.swarm/<pattern>/`:
- `state.json` — current status, criteria, iteration
- `ledger.jsonl` — append-only audit log

These survive context loss. New session reads them to resume.

## When skill calls skill

If a reference says "run plan-and-review first", read `plan-and-review.md` and execute it inline. Don't recurse past 2 levels.
