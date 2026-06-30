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

### Worker subtype routing (cost optimization)

When dispatching a worker, pick model based on task content:

| Task type | Detected by | Model | Why |
|-----------|------------|-------|-----|
| doc-only | Files all match `*.md` AND description has no "implement"/"refactor" | `Qwen3.7-Max-DogFooding` (0.00x) | Free model, plenty good for grep+sed edits |
| shell/yaml | Files include `.sh`/`.yaml`/`.yml` AND description involves <50 LOC | `Qwen3.7-Max-DogFooding` (0.00x) | Same — config edits don't need GLM |
| code-edit | Files include `.py`/`.ts`/`.java`/`.go` OR description has "implement"/"refactor"/"new feature" | `GLM-5.2` (0.60x) | Default — code reasoning needs mid-tier |
| complex-refactor | description has "breaking change" OR multi-file (>5 files) | `ultimate` (1.00x) | Heavy reasoning |

How to apply: model is bound to the subagent's frontmatter (`model:` field). To use a different model for a doc-only task:

**Option A (recommended)**: dispatch via `general-purpose` agent (default session model — typically a CHEAP-tier model in dogfooding configs) with `subagent_type: "general-purpose"`. This works for any text-edit task without needing a swarm-* worker.

**Option B**: maintain a second worker definition (e.g., `agents/swarm-worker-doc.md` with `model: Qwen3.7-Max-DogFooding`) and dispatch with `subagent_type: "swarm-worker-doc"`.

**Option C**: configure user session to use a cheap model by default (settings.json model routing), so even `swarm-worker` runs cheap until explicit `effort: high` is requested.

The Agent tool does NOT accept a runtime `model:` parameter (per ARCHITECTURE.md I2). Earlier drafts of this table suggested `MODEL: ...` in the prompt body — that was incorrect and has been removed.

This pattern shaves ~50-70% of worker costs in a typical 10-task plan where 5-6 tasks are doc-only.

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

## Sub-agent return value contract (HARD RULE)

Every dispatched sub-agent must return ≤200 tokens inline. Detailed output goes to disk.

Why: A wave of 7 parallel workers × 2000-token inline returns = 14k tokens dumped into the orchestrator's main context, blowing the budget before the next decision. 7 × 200 = 1400, fine.

Borrowed from: smolagents (managed_agent report+truncate), openai-agents-python (as_tool fresh context).

> Use `scripts/truncate.sh <max-chars>` to bound tool output before pasting into return value (e.g., `tail -100 big.log | scripts/truncate.sh 1000`).

### Required format

Every Agent prompt's DELIVERABLE section must specify:

- Detailed output → write to `.swarm/{pattern}/{task-id}/output.md` (no size limit)
- Inline response → 3-5 lines following this exact template:

```
<TASK-ID> STATUS: DONE | FAIL
file: <absolute path to output.md, or "n/a" if no artifact>
verification: <one-line evidence — actual command output, not "should work">
next: <one-line handoff hint, or "none">
```

### Anti-patterns (auto-reject)
- "Successfully completed XYZ. Here's a summary: <500 lines>"
- "I made the following changes: 1. ... 2. ... 3. ... <pasted file content>"
- Verbatim quoting tool output that already lives on disk

Orchestrator reads files when needed via Read tool, doesn't trust inline summaries.

## Summary mode for sub-agent returns (smolagents pattern)

When a sub-agent finishes a long task and writes a report to `.swarm/`, the inline return should use **summary mode** (smolagents `write_memory_to_messages(summary_mode=True)` in `memory.py:92`):

**STRIP:**
- System prompt repetition ("As a swarm-worker...")
- Planning/reasoning narration ("I first considered X, then realized Y...")
- Verbatim tool output (already on disk in `.swarm/`)

**KEEP:**
- Concrete observations ("File foo.md now has 7 instead of 5")
- Verification command + actual output ("grep ... | wc -l → 0")
- One-line handoff hint to the next stage

This is the smolagents `ActionStep.to_messages(summary_mode=True)` pattern: only the final observations cross the agent boundary. Planning steps return empty list when in summary mode.

Combined with the 200-token rule above, this is how a 5000-token sub-agent execution becomes a 3-line inline return.

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

## Memory protocol (on-demand learning)

Before starting any pattern (plan-and-review / start-work / debugging / etc), the orchestrator should:

1. `Glob .swarm/memory/*.md` — cheap file-list check
2. If a filename obviously matches the current task topic, Read it first
3. Apply the lesson; continue with the pattern's normal Stage 1

See `docs/memory-protocol.md` for the write/read format. Cost is 1 Glob per pattern start (free); Read only when topic obviously matches.

Borrowed from: navigator.ai (on-demand context loading) + anthropics/skills (lazy skill activation).
