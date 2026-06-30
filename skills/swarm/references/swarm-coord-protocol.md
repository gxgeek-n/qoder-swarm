# swarm-coord-protocol — sub-agent 自协调协议

**Source**: `ClawTeam/clawteam/spawn/prompt.py:27-108` (build_agent_prompt coordination block)
**Used by**: orchestrator (start-work, magentic-loop) APPENDS this protocol to each Bash-capable sub-agent's system prompt.
**License**: MIT (HKUDS/ClawTeam)

## When to use this protocol

The orchestrator injects this protocol when:
1. Multiple sub-agents are dispatched in parallel (Wave dispatch)
2. Tasks have inter-dependencies (DAG with `blocked_by`)
3. Sub-agents are likely to touch overlapping files

The protocol applies to **Bash-capable** sub-agents only (swarm-worker, swarm-explorer, swarm-context-manager, swarm-error-coordinator). For Read-only agents (swarm-reviewer, swarm-planner), the orchestrator runs these commands on the agent's behalf — see § "Orchestrator-relayed commands" below.

## Protocol (paste into Bash-capable sub-agent prompts)

You are part of a swarm. Other agents may be working on related tasks. Use these CLI tools to coordinate. Run them from the swarm root (use `${SWARM_HOME:-$PWD}` as prefix or full path).

### Check task state

```bash
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh status        # global swarm state
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh task list --owner <your-agent-name> --status pending
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh task show <task-id>
```

### Report completion

After completing each task, MUST run:

```bash
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh task done <task-id>
```

This auto-unblocks any tasks whose `blocked_by` list contained this task — saves the orchestrator a round.

### Check file conflicts before editing

When about to modify a file that other agents might also be editing:

```bash
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh overlap check HEAD <peer-branch>
```

If the report shows `severity: high` for any file you plan to edit, **STOP** and write a coordination note to `.swarm/{pattern}/conflict-<your-name>.md` describing the conflict. Then proceed with caution (smaller hunks, frequent commits) or escalate to orchestrator.

### Query memory

```bash
${SWARM_HOME:-$PWD}/scripts/swarm-state.sh memory list
```

If a memory file's name matches your task topic, `Read` it before starting work.

## Orchestrator-relayed commands (for Read-only agents)

For `swarm-reviewer` and `swarm-planner` (which lack Bash tool):

1. The agent reports completion in its inline summary using the standard format:
   ```
   T<id> STATUS: DONE | FAIL
   file: <output path>
   verification: <evidence>
   next: <handoff hint>
   ```
2. The orchestrator parses this and runs `scripts/swarm-state.sh task done <id>` on the agent's behalf.
3. Before dispatching a parallel-edit task to a Read-only agent, the orchestrator runs `scripts/swarm-state.sh overlap check` and injects any `severity: high` warnings into the agent's initial prompt.

This keeps coordination working even for least-privilege agents — the agent declares intent, the orchestrator handles side effects.

## Hard rules

1. **Always call `task done` after finishing** — otherwise dependent tasks stay blocked forever.
2. **Check overlap before editing shared files** — `severity: high` overlap = STOP + escalate.
3. **Use the unified `swarm-state.sh` wrapper** — do not call `task-dag.sh` or `file-overlap.sh` directly. The wrapper provides forward-compat for future additions.
4. **Use `${SWARM_HOME:-$PWD}`** — never hardcode `~/.qoder` or absolute paths; the orchestrator may run you from a worktree.
5. **Do not edit `.swarm/tasks.json` directly** — always go through the CLI to preserve DAG invariants (cycle freedom, atomic writes via lock).

## What the orchestrator does at dispatch

When dispatching a parallel wave:

1. For each task in the wave, the orchestrator calls `scripts/swarm-state.sh task add <id> "<title>" --owner <agent> [--depends X,Y]`. This builds the DAG.
2. Right before dispatching agent X, the orchestrator runs `scripts/swarm-state.sh task claim <id> <agent-name>`. This sets status=in_progress and assigns ownership.
3. The orchestrator appends this protocol text to the agent's initial prompt (or relies on the agent having read `references/swarm-coord-protocol.md` during pattern activation).
4. When the agent's inline return arrives, the orchestrator parses STATUS and runs `task done` if status=DONE, or `task block` with the FAIL reason if status=FAIL.

## Anti-patterns

- ❌ Calling `task-dag.sh` directly instead of going through `swarm-state.sh`
- ❌ Editing `.swarm/tasks.json` with Edit/Write tool — bypasses lock, can corrupt
- ❌ Not running `task done` after finishing — leaves dependents blocked
- ❌ Forking your own branch without first running `overlap check`
- ❌ Assuming you are the only agent (you may not be)
