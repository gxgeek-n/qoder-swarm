# teammode

Persistent multi-session team coordination via filesystem state.

## When NOT to use

- Single isolated task → use plain Agent
- Goal still ambiguous → run `plan-and-review` first
- Doesn't need cross-session persistence → just parallel Agent calls

## Step 1 — Initialize workspace (CHEAP × 1)

```
Agent[swarm-explorer]:
TASK: Create persistent team workspace at .swarm/teams/{name}/
CREATE:
  - team.json: { name, goal, status: 'active', members: [...], log: [] }
  - guide.md: auto-generated field manual for members
  - inbox/{role}.md (one per member, initially empty)
  - outbox/{role}.md (one per member)
  - artifacts/ (shared exchange)
MEMBER COMPOSITION RULES:
  - Each member owns ONE concrete slice (codebase part / ownership area / perspective)
  - NO vague roles like "backend dev". Use "app-server-lifecycle" or similar.
  - 2-4 members typical
  - If user didn't specify, suggest based on goal
DELIVERABLE: directory created, team.json written, member list
```

## Step 2 — Dispatch initial tasks (MID × 1)

```
Agent[swarm-planner]:
TASK: Write initial task assignments to inbox/{role}.md for each member
TEAM: read .swarm/teams/{name}/team.json
GOAL: {goal}
For each member, write inbox/{role}.md:
  ---
  From: leader
  To: {role}
  Type: task_handoff

  ## Goal
  {task scoped to member's focus}

  ## Scope
  - Touch: {their territory}
  - Do NOT touch: {others' territory}

  ## Deliverable
  {expected output}

  ## Coordination
  - Need from another member? Write to artifacts/ + note in outbox
  - Blocked? Write BLOCKED + reason to outbox immediately
  ---
RULES:
  - Self-contained tasks (member has no leader context)
  - Tasks don't overlap (exclusive scope)
```

## Step 3 — Monitor progress

Read `.swarm/teams/{name}/outbox/*.md` periodically. Report:
```
| Member | Status | Summary |
| A | done/working/blocked/awaiting | ... |
```

## Step 4 — Integrate (MID × 1)

When all members done:

```
Agent[swarm-worker]:
TASK: Integrate all team member results
INPUT: .swarm/teams/{name}/outbox/*.md + artifacts/*
CHECK:
  1. All deliverables present?
  2. Conflicts between changes?
  3. Pieces work together? (run tests)
  4. Team goal fully achieved?
If success:
  - Update team.json status → 'completed'
  - Write artifacts/integration-report.md
If issues:
  - List what to fix
  - Suggest which member fixes
  - DON'T close team
```

## Cross-session use

Filesystem-based state means any Qoder session that opens this project sees the team. Stop-continuation hook (if installed) alerts about active teams. Members can be separate Qoder sessions monitoring their inbox.

## OmO-style team inbox (v5 upgrade path)

The dispatch-kit `templates/*.md` approach works for human-in-the-loop multi-terminal. For automated team coordination (where the leader is also an LLM), OmO uses per-message JSON files:

```
.dispatch/inbox/{role}/{timestamp}-{uuid}.json
```

Each message conforms to `dispatch-kit/schema/message.json`. Benefits over single-file markdown:
- **Atomic writes**: one message per file = no partial-read risk
- **Ordering**: filename contains timestamp, `ls | sort` gives chronological order
- **Schema validation**: consumer can validate JSON before processing
- **Malformed tolerance**: bad messages get logged and skipped, don't break the queue
- **Concurrent safety**: multiple writers create different files, no collision

The leader writes to `inbox/{role}/`, the worker reads all files in its inbox dir sorted by timestamp, processes each, and moves processed files to `inbox/{role}/.consumed/` (or deletes).

This is the same pattern as `swarm-coord-protocol.md`'s claim-based consumption (which uses `.consumed` rename + dead-letter quarantine), applied to the multi-terminal case.

Source: OmO `packages/team-core/src/team-mailbox/inbox.ts` (MIT).
