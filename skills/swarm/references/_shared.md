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

**Option B**: maintain a second worker definition (e.g., `agents/swarm-worker-<variant>.md` with `model: Qwen3.7-Max-DogFooding`) and dispatch with `subagent_type: "swarm-worker-doc"`.

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

## Sub-agent PROMPT size contract (HARD RULE — from token cost analysis)

Every dispatched sub-agent prompt MUST be <=2500 chars. Bigger prompts cost more tokens (both input tokens billed AND response tokens tend to bloat proportionally).

Real data from 2026-07-01 analysis (scripts/swarm-cost-qoder.py):
- 11 swarm-worker dispatches average 12K tokens each
- Longest single prompt: 8734 chars (contained full source code heredoc)
- Prompt-size correlates strongly with response-size and total cost

### What to include

- Task ID + one-line goal
- File paths (absolute or CWD-relative)
- 3-5 bullet WHAT TO DO
- Reference paths (worker Reads them, don't paste)
- Verify recipe name OR <=80-char inline check
- SCOPE limits

### What to EXCLUDE

- Full source code of files being ported (paste path instead, worker Reads it)
- Multi-heredoc test scripts (use recipe)
- 5-line explanation of "why we're doing this" (worker reads plan.md if unclear)
- Example outputs (worker infers from spec)
- Boilerplate template blocks (reference worker-template.md)

### Enforcement

Before Agent dispatch, orchestrator MUST self-check: `[ ${#prompt} -le 2500 ]`. If longer, refactor: extract heredocs to referenced files, remove redundant explanation, use recipe name.

See `references/worker-template.md` for the target shape.
See `references/worker-verify-recipes.md` for named verify recipes.

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

### Auto-execution (no human trigger needed)

The following wiki/memory operations happen AUTOMATICALLY as part of pattern execution. The orchestrator does NOT wait for user to say "wiki ingest" or "remember this":

| When | What happens | Who does it |
|---|---|---|
| Pattern completes (any) | .swarm/{pattern}/*.md → wiki vault (references/ or synthesis/) | orchestrator, after final output step |
| Stage 0 reads wiki pages | Those pages get `--reinforce` (confidence=HIGH, last_confirmed=today) | orchestrator, during Stage 0 |
| Session start | session-start.py scans vault + prints active patterns + memory count | hook, automatic |
| Agent output contains insight keywords | memory-learner.py writes to .swarm/memory/ | hook, automatic |
| Agent completes with "STATUS: DONE" + .swarm/ path | swarm-wiki-ingest.py writes to vault | hook, automatic |
| Weekly (or user runs) | wiki-confidence.py --decay | manual for now (suggest: cron) |

The ONLY manual wiki operation is `wiki-lint` (health check) and `wiki-query` (user asking a question). Everything else is automatic.

**Anti-pattern**: Orchestrator says "I'll wiki-ingest this later" or "you can run wiki-ingest manually" — NO. If it's ingest-worthy, ingest it NOW as part of the current step.

## ProgressLedger 协议（来自 magentic-loop）

**Source**: SK Magentic One (`semantic-kernel/python/semantic_kernel/agents/orchestration/prompts/_magentic_prompts.py:63-111`)
**Detailed pattern**: `references/magentic-loop.md`

When using the `magentic-loop` pattern, the orchestrator makes 1 LLM call per round using the ProgressLedger schema:

### Schema (5 fields, each with reason + answer)

```json
{
  "is_request_satisfied": {"reason": "...", "answer": boolean},
  "is_in_loop": {"reason": "...", "answer": boolean},
  "is_progress_being_made": {"reason": "...", "answer": boolean},
  "next_speaker": {"reason": "...", "answer": "<one of participant_names>"},
  "instruction_or_question": {"reason": "...", "answer": "<concrete instruction>"}
}
```

### JSON parse failure (3-strikes)

1. Direct parse fails → strip markdown fences (` ```json ... ``` `), retry parse
2. Still fails → re-call LLM with suffix "OUTPUT ONLY VALID JSON. NO MARKDOWN."
3. Still fails → fall back to **round-robin** speaker selection (see below), log `.swarm/magentic/{session}/anomalies.log`

### Stall detection rules

- `is_in_loop.answer == true` OR `!is_progress_being_made.answer` → `stall_count += 1`
- `stall_count >= max_stall` (default 3) AND `reset_count < max_reset` (default 3) → trigger replan via `prompts/replan.md`
- After 3 stalls + 3 replans exhausted → terminate with partial result (last assistant message from chat_history)

### Round-robin fallback definition

See `references/magentic-loop.md` § "Round-robin fallback" for the canonical algorithm. In short: modular index into `state.team` using `state.round_count`, skipping any agent the orchestrator marked unavailable. Never re-implement this in another file — link here.

### Hard rules

- `next_speaker.answer` MUST be in `participant_names` (else 1 retry, then round-robin)
- ledger.jsonl record format: `{"round": <int>, "timestamp": <ISO-8601>, "ledger": <full ProgressLedger JSON>}`
- partial result on limits hit: last assistant message; if none, return `{"status": "INCOMPLETE", "reason": "<limit-name> exhausted", "rounds_used": N}`
- Never make multiple speaker selections per round — one ProgressLedger → one dispatch

## Fallback chain (from OmO fallback-retry-handler)

Source: `packages/omo-opencode/src/features/background-agent/fallback-retry-handler.ts` + `attempt-lifecycle.ts` (MIT).

Every swarm-* agent has a `fallback_models:` field in its frontmatter — an ordered list of alternate models to try when the primary fails.

### When to trigger fallback

The orchestrator should catch Agent dispatch failures and inspect the error:

| Signal | Action |
|---|---|
| Provider 429 (rate limit) | Wait backoff (5s, 10s, 20s) then retry same model; after 2 backoff fails, switch to fallback |
| Provider 5xx | Immediate fallback |
| Empty Done (agent returned but no output file) | Retry same model 1x, then fallback |
| Timeout > 2× expected | Fallback |
| Explicit content-policy refusal | Fallback (different model may not refuse) |

### Attempt tracking

Log each attempt to `.swarm/audit/attempts.jsonl`:
```json
{"task_id":"T5","attempt":1,"model":"Ultimate","status":"error","error":"429","started":"...","completed":"..."}
{"task_id":"T5","attempt":2,"model":"GLM-5.2","status":"completed","started":"..."}
```

Report to user shows the whole chain:
```
T5: COMPLETED (via fallback to GLM-5.2, primary Ultimate 429'd)
```

### Orchestrator pseudocode

```
def dispatch_with_fallback(agent_type, prompt):
    agent_config = read_frontmatter(agent_type)
    chain = [agent_config.model] + agent_config.fallback_models
    for attempt_num, model in enumerate(chain, 1):
        try:
            result = Agent(subagent_type=agent_type, prompt=prompt, model_override=model)
            log_attempt(task_id, attempt_num, model, "completed")
            return result
        except (RateLimitError, ProviderError, EmptyDone) as e:
            log_attempt(task_id, attempt_num, model, "error", str(e))
            if attempt_num == len(chain):
                raise  # exhausted all fallbacks
            # else: try next
    raise Exception("all fallback models exhausted")
```

**Note**: Qoder's Agent tool doesn't accept a runtime `model` parameter (per ARCHITECTURE.md I2). The `model_override` above is aspirational. Real implementation options:
1. Maintain per-model shadow agents (e.g., `agents/swarm-worker-glm.md`, `agents/swarm-worker-qwen.md`) and dispatch by different `subagent_type`
2. Use `general-purpose` as the ultimate fallback (inherits session default model)
3. Wait for Qoder to expose runtime model override

Currently the `fallback_models` field is a **contract/spec**, orchestrator implements it via option 1 or 2.

## Loop detection (from OmO background-agent)

Source: `packages/omo-opencode/src/features/background-agent/loop-detector.ts` (MIT).

When the orchestrator dispatches workers in a loop (e.g., ulw-loop pattern), same-agent-same-task
repeated calls indicate the LLM is stuck. Check periodically:

```bash
scripts/tool-loop-detect.sh --threshold 5
```

Exit codes:
- `0` — no loop detected
- `1` — loop detected (orchestrator should kill + retry with different strategy)
- `2` — usage error

Threshold default is 5 consecutive same-signature dispatches (agent × description).
This mirrors OmO's `DEFAULT_CIRCUIT_BREAKER_CONSECUTIVE_THRESHOLD` = 5.

**Integration with ulw-loop**: after each iteration, run `tool-loop-detect.sh`. If exit 1,
force switch to a different swarm-* agent for the next iteration OR terminate with partial
result.

## Structured commit trailers (from oh-my-qoder)

Source: chickenlj/oh-my-qoder commit protocol.

When the orchestrator commits after a successful swarm iteration, use these git trailers (appended after the commit body, blank-line-separated):

```
Confidence: HIGH | MEDIUM | LOW
  - HIGH: all acceptance criteria met + smoke passes + review PASS
  - MEDIUM: acceptance met but no adversarial review OR partial test coverage
  - LOW: changes are speculative / aspirational / not yet validated

Scope-risk: CONTAINED | MODERATE | BROAD
  - CONTAINED: only files declared in plan.md's `files:` field were touched
  - MODERATE: 1-2 undeclared files touched (e.g., docs update not in plan)
  - BROAD: touched shared infrastructure (hooks/settings/CI) or >10 files

Not-tested: <comma-separated list of scenarios not verified>
  - e.g., "macOS bash 3.2 compat, concurrent 10+ tasks, non-git-repo cwd"
  - If everything was tested: "none"

Constraint: <comma-separated invariants respected>
  - e.g., "I1 single-skill router, I3 file-as-truth, I5 reversible cleanup"

Rejected: <alternatives considered and why rejected>
  - e.g., "full Rate Governor (no empirical data), jq-native DFS (BFS simpler)"
```

### Example commit with trailers:

```
swarm v6 rate-governor lite — observability-first counter-proposal

[body text here]

Confidence: HIGH
Scope-risk: CONTAINED
Not-tested: windows, non-jq systems
Constraint: I1, I2, I3, I4, I5
Rejected: D.1 jitter (no 429 evidence), D.4 donation pool (single-user)
```

### When to apply

- ALWAYS on swarm auto-commits (commits made by the orchestrator per auto-execution boundary).
- OPTIONAL on user-directed commits (when user says "commit this").
- The orchestrator self-evaluates: was this reviewed? what wasn't tested? what was the scope?

## Wiki confidence lifecycle

Wiki pages carry `confidence` and `last_confirmed` frontmatter fields. Confidence
decays over time and strengthens with reinforcement (LLM Wiki v2 pattern).

**Levels**: `HIGH` > `MEDIUM` > `LOW`

**Tool**: `scripts/wiki-confidence.py <vault> [--report] [--decay] [--reinforce <page>]`

| Command | Action |
|---------|--------|
| `--report` (default) | Print per-page confidence, age, and last_confirmed |
| `--decay` | Pages with `last_confirmed` > 30 days: drop one level (HIGH→MEDIUM→LOW). Pages without confidence field: add `MEDIUM` + `last_confirmed` from file mtime |
| `--reinforce <page>` | Set `confidence=HIGH` + `last_confirmed=today` for one page |

Pages without frontmatter are skipped (raw files never modified). stdlib only,
no PyYAML dependency.

## CWD must be a git repo when dispatching swarm-worker (HARD RULE)

**Bug**: `swarm-worker · Error: Failed to resolve base branch "HEAD": git rev-parse failed`

**Root cause**: Qoder CLI internally runs `git rev-parse` even when `isolation: default`. If the session's cwd is not a git repo (e.g., `/Users/gx/`), this fails.

**Fix**: Every Agent call with `subagent_type: "swarm-worker*"` MUST include `cwd: "/path/to/git/repo"`:
```
Agent(subagent_type="swarm-worker", cwd="/Users/gx/qoder-swarm", prompt="...")
```

**Orchestrator self-check**: Before dispatching any swarm-* worker, verify:
1. Is there a known git repo path? (from the user's task context or `git rev-parse --show-toplevel`)
2. If yes → pass as `cwd`
3. If no → use `subagent_type: "general-purpose"` instead (it doesn't hit the git path)

This is documented in `docs/session-memory-2026-06-30.md` "踩坑 #1" and is a Qoder platform behavior we cannot fix — only work around.
