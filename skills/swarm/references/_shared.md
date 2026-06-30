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
  subagent_type: "<role-specific subagent>",
  description: "<3-5 word label>",
  prompt: "<TASK header + body>"
})
```

## subagent_type → real model routing

Qoder's `Agent` tool **does not accept a `model` parameter at call time**. Model selection happens **inside the subagent's frontmatter** (the `model:` field in its `.md` definition). qoder-swarm ships 7 specialized subagents installed at `~/.qoder/agents/`:

| Role | subagent_type | Model | Effort | Tools | When to use |
|------|--------------|-------|--------|-------|-------------|
| Read-only codebase search | `swarm-explorer` | `Qwen3.7-Max-DogFooding` | `low` | Read/Grep/Glob/Bash/WebFetch | Exploration in plan-and-review, init-deep, debugging |
| External docs/OSS research | `swarm-librarian` | `Qwen3.7-Max-DogFooding` | `low` | WebFetch/WebSearch/Bash | Research in plan-and-review, ultraresearch |
| Strategic planning | `swarm-planner` | `ultimate` | `high` | Read/Write plan files only | Plan drafting in plan-and-review |
| Adversarial review | `swarm-reviewer` | `ultimate` | `high` | Read-only inspection | Gap analysis, code review, plan review |
| Implementation worker | `swarm-worker` | `GLM-5.2` | `medium` | Read/Edit/Write/Bash | Worker dispatch in start-work, remove-ai-slops |
| Context compression | `swarm-context-manager` | `DeepSeek-V4-Flash (0.10x)` | `low` | Read/Bash | Long-running loops, context overflow |
| Error triage & recovery | `swarm-error-coordinator` | `DeepSeek-V4-Flash (0.10x)` | `medium` | Read/Bash | Worker failure classification, recovery routing |

These are the shipped defaults. Edit the `model:` field in the agent `.md` file or use `settings.json` overrides to customize.

If `swarm-*` subagents aren't installed (kit not installed yet), **fall back** to Qoder built-ins:
- `swarm-explorer` → `Explore`
- `swarm-librarian` → `general-purpose`
- `swarm-planner` → `Plan`
- `swarm-reviewer` → `Plan` or `general-purpose`
- `swarm-worker` → `general-purpose`
- `swarm-context-manager` → `general-purpose` (if not installed)
- `swarm-error-coordinator` → `general-purpose` (if not installed)

To check installed subagents: ask the user to run `/agents` in TUI or `qodercli agents list`.

## How to control credit cost

The models above range from cost-effective options (Qwen3.7-Max-DogFooding for explorer/librarian, GLM-5.2 for workers) to the premium ultimate model (planner/reviewer). To force different specific models, the user must:

Option A — edit the agent file's `model:` field to a specific model name:
```yaml
# ~/.qoder/agents/swarm-explorer.md
model: Qwen3.7-Max-DogFooding
```

Option B — use `settings.json` overrides:
```json
{
  "agents": {
    "overrides": {
      "swarm-explorer": { "modelConfig": { "model": "Qwen3.7-Max-DogFooding" } },
      "swarm-planner":  { "modelConfig": { "model": "GLM-5.2" } }
    }
  }
}
```

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

## Inter-stage handoff template

When one stage completes and hands off to the next (e.g., plan-and-review → start-work, or start-work → five-agent-review), write a handoff brief to `.swarm/<current-pattern>/handoff.md` using this format:

```
## Handoff: <current_stage> → <next_stage>
- Decided: [choices made, with brief rationale]
- Rejected: [discarded options, with reason for rejection]
- Risks: [identified risks that the next stage should watch for]
- Files: [modified or created file list with absolute paths]
- Remaining: [items intentionally left for later stages]
```

The next stage reads `.swarm/<previous-pattern>/handoff.md` first before executing. This `Handoff:` brief format keeps inter-stage context compact (avoids re-reading 1000+ lines of plan/report) while preserving decisions that matter.

Borrowed from oh-my-claudecode (MIT, https://github.com/Yeachan-Heo/oh-my-claudecode).
