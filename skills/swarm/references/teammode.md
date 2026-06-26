# teammode

Persistent multi-session team coordination via filesystem state.

## When NOT to use

- Single isolated task → use plain Agent
- Goal still ambiguous → run `plan-and-review` first
- Doesn't need cross-session persistence → just parallel Agent calls

## Step 1 — Initialize workspace (CHEAP × 1)

```
Agent[team-init]:
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
Agent[task-dispatcher]:
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
Agent[integrator]:
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
