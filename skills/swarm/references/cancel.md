# Graceful Cancellation Pattern

When a user says "cancel", "stop", "取消", or "中止" during an active swarm pattern,
the orchestrator must shut down sub-agents cleanly, preserve partial results, and
leave enough state for a future session to resume.

## Cancel signal

The orchestrator writes a cancel signal file at the swarm root:

```json
// .swarm/cancel-signal.json
{
  "pattern": "start-work",
  "reason": "user_requested",
  "timestamp": "2025-01-15T10:30:00Z",
  "initiatedBy": "orchestrator"
}
```

This file is the single source of truth. Sub-agents poll for it; the orchestrator
creates it and then waits for in-flight agents to drain.

## Detection — when to check

Sub-agents check for the cancel signal **before each major step** in their
execution loop:

1. Before starting a new task / wave / stage.
2. Before writing results to disk.
3. Before spawning child agents.

The check is a single file-exists test:

```bash
test -f .swarm/cancel-signal.json && echo "CANCELLED"
```

If the file exists, the sub-agent must **stop immediately** — do not start the
next step, do not spawn children, do not write new output.

## On cancel — flush partial results

When a sub-agent detects the cancel signal mid-work, it flushes whatever partial
results it has to the pattern's partials directory:

```
.swarm/{pattern}/partials/
  ├── {agentRole}-{taskName}.partial.md   ← incomplete work, marked as partial
  ├── {agentRole}-{taskName}.partial.json ← structured partial state (optional)
  └── ...
```

Each partial file should include:
- What was completed before cancellation.
- What remained unfinished.
- Any intermediate artifacts (file paths, commit SHAs, test output).

This ensures no work is lost — the next session can pick up where the swarm left off.

## State preservation

The orchestrator updates the pattern's state file to reflect cancellation:

```json
// .swarm/{pattern}/state.json
{
  "pattern": "start-work",
  "status": "cancelled",
  "cancelledAt": "2025-01-15T10:30:05Z",
  "completedTasks": ["T1", "T4"],
  "inFlightTasks": ["T2", "T3"],
  "pendingTasks": ["T5", "T6"],
  "partialsDir": ".swarm/start-work/partials/",
  "lastWave": 2,
  "resumeHint": "Wave 2 was in flight (T2, T3). Re-run these tasks, then continue with Wave 3 (T5, T6)."
}
```

Key fields:
- `status`: set to `"cancelled"` (not `"failed"` — cancellation is intentional, not an error).
- `completedTasks`: tasks that finished successfully before cancel.
- `inFlightTasks`: tasks that were running when cancel hit — these may have partials.
- `pendingTasks`: tasks never started.
- `resumeHint`: human-readable guidance for the next session.

## Orchestrator shutdown sequence

When the orchestrator receives a cancel request:

1. **Write** `.swarm/cancel-signal.json` immediately.
2. **Wait** for in-flight sub-agents to drain (they will see the signal and stop).
   - Do NOT force-kill — give agents a grace window to flush partials.
   - If an agent doesn't respond within ~60 seconds, log a warning and proceed.
3. **Collect** partial results from all agents that flushed.
4. **Update** `.swarm/{pattern}/state.json` with `status: "cancelled"`.
5. **Clean up** the cancel signal file (`.swarm/cancel-signal.json`) so the next
   session starts fresh.
6. **Report** to the user: which tasks completed, which have partials, and that
   resume is available.

## Resume — next activation

When the swarm pattern activates again and `.swarm/{pattern}/state.json` exists
with `status: "cancelled"`, the orchestrator should:

1. **Read** the state file.
2. **Inform** the user: "Previous run was cancelled. Completed: X tasks. Partial: Y tasks. Pending: Z tasks."
3. **Offer** resume: "Resume from where we left off? (Y/n)"
   - If yes: re-run `inFlightTasks` first (they may have partials to build on),
     then continue with `pendingTasks`.
   - If no: archive the old state (move to `.swarm/{pattern}/.archive/`) and start fresh.
4. **Load** any partial results from `.swarm/{pattern}/partials/` as context for
   the resumed tasks.

## What NOT to do

- **Do not** delete partial results on cancel — they are the whole point.
- **Do not** mark cancelled tasks as `"failed"` — failed implies a bug; cancelled
  implies user intent.
- **Do not** leave `.swarm/cancel-signal.json` in place after shutdown — it would
  cause the next session to immediately abort.
- **Do not** force-kill sub-agents without a grace window — partials may be
  incomplete or corrupted.
