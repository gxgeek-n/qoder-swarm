# magentic-loop — group conversation with LLM speaker selection

**Source**: Microsoft Semantic Kernel `Magentic One` (`magentic.py:596-657` inner loop, `:681-714` limits)
**License**: MIT (Microsoft)
**Pattern type**: Iterative multi-agent conversation with LLM-driven speaker selection.

## When to use

- Multiple sub-agents need **iterative convergence** (not parallel-then-aggregate)
- The "who should speak next" decision is dynamic, not predetermined
- Concrete cases:
  - Architecture decisions where security + perf + UX viewpoints must converge
  - Complex debugging where hypothesis tree needs progressive narrowing
  - Cross-cutting refactors where the right specialist changes by sub-task

**NOT for**: simple parallel review (use `five-agent-review`), independent worker dispatch (use `start-work`), or single-agent execution (just call the agent directly).

## Configuration

Default limits (override per dispatch):
- `max_round_count`: 20  — terminate if no convergence
- `max_reset_count`: 3   — max replans before giving up
- `max_stall_count`: 3   — consecutive stall rounds before triggering replan

Saved to `.swarm/magentic/{session}/state.json` on init; mutated each round.

## Stage 0 — Memory check (optional)

`Glob .swarm/memory/*.md`. If any filename matches the current task topic, `Read` it before Stage 1. See `docs/memory-protocol.md`.

## Stage 1 — Task ledger (preflight)

Goal: build a shared understanding of facts + plan that all participants see.

### Step 1.1 — Gather facts

Make an LLM call using `prompts/task-ledger-facts.md` with `{task}` filled in. Save the 4-section response to `.swarm/magentic/{session}/facts.md`.

### Step 1.2 — Draft plan

Make an LLM call using `prompts/task-ledger-plan.md` with `{team}` (bullet list of available sub-agents) filled in. Save the bullet-point plan to `.swarm/magentic/{session}/plan.md`.

### Step 1.3 — Initialize state

Write `.swarm/magentic/{session}/state.json`:
```json
{
  "task": "<user request>",
  "team": ["agent-1", "agent-2", "..."],
  "round_count": 0,
  "stall_count": 0,
  "reset_count": 0,
  "max_round": 20,
  "max_reset": 3,
  "max_stall": 3,
  "chat_history": []
}
```

### Step 1.4 — Seed chat history

Compose the initial system message combining facts + plan + task. This is `chat_history[0]`. All participants see it.

## Stage 2 — Inner loop

Repeat until terminated:

### Step 2.1 — Read state

Read `state.json`. If `round_count >= max_round` → break (limit hit; go to Stage 3).

### Step 2.2 — Build context for ledger call

Construct the ProgressLedger prompt (from `prompts/progress-ledger.md`):
- `{task}` = state.task
- `{team_descriptions}` = bullet list of agent name + role
- `{participant_names}` = comma-separated agent names
- Append full chat_history as conversation context

### Step 2.3 — LLM call → ProgressLedger

Call the orchestrator's LLM with the ProgressLedger prompt. **Parse the output as JSON.** Expected schema (5 keys, each with `reason` + `answer`):

```json
{
  "is_request_satisfied": {"reason": "...", "answer": false},
  "is_in_loop": {"reason": "...", "answer": false},
  "is_progress_being_made": {"reason": "...", "answer": true},
  "next_speaker": {"reason": "...", "answer": "swarm-worker"},
  "instruction_or_question": {"reason": "...", "answer": "Implement T1 ..."}
}
```

**Parse failure handling** (3-strikes):
- Attempt 1: parse output as JSON.
- Attempt 2 (if 1 fails): strip markdown fences (```json ... ```), retry parse.
- Attempt 3 (if 2 fails): retry the LLM call with prompt suffix "OUTPUT ONLY VALID JSON. NO MARKDOWN."
- After 3 fails: log to `.swarm/magentic/{session}/anomalies.log`, fall back to **round-robin** (see Hard rules below).

### Step 2.4 — Check termination conditions

- `ledger.is_request_satisfied.answer == true` → success, go to Stage 3.
- `ledger.next_speaker.answer NOT in state.team` → retry LLM call once with stricter prompt; if still invalid, fall back to round-robin.

### Step 2.5 — Stall detection

If `ledger.is_in_loop.answer == true` OR `!ledger.is_progress_being_made.answer`:
- `state.stall_count += 1`
- If `state.stall_count >= state.max_stall`:
  - If `state.reset_count < state.max_reset`: **trigger replan** (Step 2.6)
  - Else: terminate (cannot recover); go to Stage 3.
Else:
- `state.stall_count = 0` (reset on progress)

### Step 2.6 — Replan (when stalled)

Run the 2-step replan flow from `prompts/replan.md`:
1. LLM call 1: update facts.md based on chat history
2. LLM call 2: produce new plan.md based on updated facts + what didn't work
3. Reset `chat_history` to the new seed message (facts + plan + task)
4. `state.reset_count += 1`; `state.stall_count = 0`
5. Continue inner loop.

### Step 2.7 — Dispatch the selected speaker

Append the orchestrator's instruction as an assistant message to `chat_history`:

```
Orchestrator → {next_speaker}: {instruction_or_question}
```

Then dispatch to the selected sub-agent:

```
Agent[{next_speaker}]:
TASK: {instruction_or_question}
CONTEXT: You are participating in a group conversation. Here is the conversation so far:
{chat_history}

Your role: {role_description}

DELIVERABLE: Your response to the instruction/question. Be specific and actionable.
SCOPE: Address only what was asked. Do not take over other agents' work.
VERIFY: Your response must add new information or advance the task — not repeat prior messages.
```

Wait for the sub-agent's response. When it returns:

1. Append the response to `chat_history` as a user message:
   ```
   {next_speaker}: {response}
   ```
2. Append the response to `.swarm/magentic/{session}/ledger.jsonl`:
   ```json
   {"round": N, "speaker": "next_speaker", "instruction": "...", "response": "...", "timestamp": "..."}
   ```
3. `state.round_count += 1`
4. Write updated `state.json` back to disk.
5. Loop back to Step 2.1.

### Round-robin fallback

When ProgressLedger parse fails 3 times OR `next_speaker.answer` is not in `participant_names` after retry:

1. Compute `next_index = state.round_count % len(state.team)`
2. Select `state.team[next_index]` as the next speaker
3. Reuse the previous `instruction_or_question` (or a default "continue with your task" if none)
4. Log to `.swarm/magentic/{session}/anomalies.log`: `round={N} fallback=round-robin selected={agent}`
5. Continue inner loop normally

If the selected agent's previous response (in chat_history) shows it cannot proceed, increment `next_index` and try the next agent. If all agents exhaust without progress, terminate with `NO_AVAILABLE_AGENT`.

## Stage 3 — Termination

Three exit paths from the inner loop:

### Path A — Task satisfied (success)

Triggered when `ledger.is_request_satisfied.answer == true` (Step 2.4).

1. Make a final LLM call to synthesize the answer from `chat_history`. Use the final-answer prompt (inline below, adapted from `magentic.py:465-495` ORCHESTRATOR_FINAL_ANSWER_PROMPT):
   ```
   We have been working on the following task:

   {task}

   The conversation so far is:

   {chat_history}

   Please provide the final answer to the task based on the conversation above.
   ```
2. Write the final answer to `.swarm/magentic/{session}/result.md`.
3. Update `state.json` with `"status": "completed"`.
4. Surface to user: result summary + path to `result.md`.

### Path B — Limit hit (round or reset)

Triggered when `round_count >= max_round` OR `reset_count >= max_reset` (Step 2.1 or Step 2.5).

1. Retrieve the latest assistant content from `chat_history` as the partial result.
2. If no assistant content exists, write `"Stopped because the maximum {limit_type} limit was reached. No partial result available."` to `result.md`.
3. Update `state.json` with `"status": "limit_reached"` and `"limit_type": "round" | "reset"`.
4. Surface to user: partial result + explanation of which limit was hit + recommendations (e.g., "increase max_round", "narrow the task scope", "add more specialized agents").

### Path C — Unrecoverable stall (all replans exhausted)

Triggered when `stall_count >= max_stall` AND `reset_count >= max_reset` (Step 2.5).

1. Same as Path B but with `"status": "stalled"` and `"limit_type": "stall"`.
2. Append stall analysis to `result.md`:
   - Last 3 ledger entries (from `ledger.jsonl`)
   - Which agents spoke in the stalled rounds
   - Suggested next steps (different team composition, different task decomposition)
3. Surface to user with the stall analysis.

### Final state write

Regardless of exit path, write the final `state.json`:
```json
{
  "task": "...",
  "team": [...],
  "round_count": N,
  "stall_count": N,
  "reset_count": N,
  "status": "completed | limit_reached | stalled",
  "limit_type": "round | reset | stall | null",
  "final_result_path": ".swarm/magentic/{session}/result.md"
}
```

## File layout

```
.swarm/magentic/{session}/
├── state.json           # mutable state, written every round
├── facts.md             # preflight facts, overwritten on replan
├── plan.md              # preflight plan, overwritten on replan
├── ledger.jsonl         # append-only round audit log
├── result.md            # final answer (written at termination)
├── anomalies.log        # parse failures, fallback events, errors
└── chat_history.json    # full conversation transcript (optional, for debugging)
```

## Hard rules

1. **Orchestrator never does implementation work** — it only selects speakers, crafts instructions, and evaluates progress. This is the same rule as `start-work.md`: the main agent dispatches, never codes.
2. **One speaker per round** — the inner loop dispatches exactly one sub-agent per round. No parallel dispatch within the magentic loop. If you need parallelism, use `start-work` instead.
3. **State is truth** — `state.json` is the single source of truth for round/stall/reset counts. Do not track these in memory. Read from disk at the start of every round.
4. **Append-only ledger** — `ledger.jsonl` is never edited or truncated. It survives crashes and context loss. New session reads it to understand prior progress.
5. **Replan resets chat history** — after replan (Step 2.6), `chat_history` is replaced with the new seed message. This is intentional (Magentic semantics): the team starts fresh with updated facts + plan. The old history is still in `ledger.jsonl`.
6. **Round-robin is a safety net, not a strategy** — it prevents deadlocks when the orchestrator LLM fails, but it produces lower-quality speaker selection. If round-robin fires more than once in a session, investigate the LLM configuration (model capability, prompt clarity).
7. **Sub-agent return value contract** — each dispatched speaker returns ≤200 tokens inline (per `_shared.md`). Detailed output goes to disk. The orchestrator reads files when needed.
8. **Context recovery** — if a sub-agent crashes mid-round, re-spawn it using `prompts/context-recovery.md`. Do NOT skip the round — the orchestrator needs a response to append to `chat_history`.

## Cost model

Each round costs 2 LLM calls:
- 1 orchestrator call (ProgressLedger) — HEAVY tier (needs structured output + reasoning)
- 1 sub-agent call (speaker) — varies by agent (see `_shared.md` routing table)

Preflight adds 2 calls (facts + plan). Replan adds 2 calls per occurrence.

Typical 10-round session with 1 replan: ~24 LLM calls.
Naive parallel dispatch of the same 10 tasks: ~10 calls but no convergence guarantee.

Use magentic-loop when the **value of convergence** exceeds the **cost of extra orchestrator calls** — typically complex, multi-stakeholder tasks where a wrong early decision is expensive.

## Anti-patterns

- Using magentic-loop for independent parallel tasks — use `start-work` (wave dispatch is cheaper and parallel)
- Using magentic-loop for single-agent review — just call the reviewer directly
- Allowing the orchestrator to do implementation work — it should only select + instruct
- Skipping the facts/plan preflight — the task ledger is what makes speaker selection intelligent; without it, the orchestrator has no context to decide who speaks next
- Not writing `state.json` to disk every round — if the session crashes, you lose progress tracking
- Increasing `max_round` above 30 — if 20 rounds isn't enough, the task is probably too broad for magentic-loop; decompose it into smaller sub-tasks and run multiple sessions
- Letting the same speaker go 3+ times in a row without explicit orchestrator reasoning — this usually means the orchestrator is stuck; trigger replan

## Relationship to other patterns

| Pattern | When to use instead |
|--------|-------------------|
| `start-work` | Tasks with clear decomposition + independent execution |
| `plan-and-review` | One-shot planning + adversarial review (no iteration needed) |
| `ulw-loop` | Single-agent self-correcting execution (no multi-agent convergence) |
| `five-agent-review` | Fixed-set parallel review (no dynamic speaker selection) |
| `debugging` | Root-cause investigation (focused, not iterative convergence) |

## Cross-references

- `prompts/progress-ledger.md` — the per-round LLM call schema (Step 2.3)
- `prompts/task-ledger-facts.md` — preflight fact-gathering prompt (Step 1.1)
- `prompts/task-ledger-plan.md` — preflight plan-drafting prompt (Step 1.2)
- `prompts/replan.md` — stall-triggered replan flow (Step 2.6)
- `prompts/context-recovery.md` — sub-agent crash recovery
- `references/swarm-coord-protocol.md` — sub-agent self-coordination (injected into Bash-capable agents)
- `references/_shared.md` — shared conventions (agent prompt template, return value contract, state location)
