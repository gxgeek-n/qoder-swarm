---
name: teammode
description: "Persistent multi-session team orchestration with durable file state. Use when user says 'team mode', 'make a team', 'run as a team', 'coordinate threads', 'parallel sessions', '团队模式', '多人协作'. Leader orchestrates, members own concrete slices. State lives in .swarm/teams/ so any Qoder session can resume."
---

# teammode

Persistent team coordination across sessions via filesystem state.

## When to activate

User mentions:
- "team mode" / "make a team" / "run as a team"
- "coordinate threads" / "parallel sessions"
- "团队模式" / "多人协作" / "组个团队"

## When NOT to use

- Single isolated task → use plain Agent
- Goal still ambiguous → use plan-and-review first
- Doesn't need cross-session persistence → use parallel Agent calls directly

## How to execute

### Step 1 — Initialize team workspace

ONE `Agent` call (CHEAP model) to set up files:
```
prompt: "Initialize a persistent team workspace at .swarm/teams/{name}/

CREATE:
- team.json: { name, goal, status: 'active', members: [...], log: [] }
- guide.md: auto-generated field manual for members
- inbox/{role}.md (one per member, initially empty)
- outbox/{role}.md (one per member)
- artifacts/ (shared exchange)

MEMBER COMPOSITION:
- Each member owns ONE concrete slice (codebase part, ownership area, perspective)
- NO vague roles like 'backend dev'. Use 'app-server-lifecycle' instead.
- 2-4 members typical
- If user didn't specify, suggest based on the goal

DELIVERABLE: directory created, team.json written, members listed"
```

### Step 2 — Dispatch initial tasks

ONE `Agent` call (MID model):
```
prompt: "Write initial task assignments to inbox/{role}.md for each member.

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
- Tasks don't overlap (exclusive scope per member)"
```

### Step 3 — Monitor progress

Use Read tool periodically (or instruct user to call you to check):
```
Read .swarm/teams/{name}/outbox/*.md
Report status table:
| Member | Status | Summary |
| A | done/working/blocked/awaiting | ... |
```

### Step 4 — Integrate

When all members report done:
```
ONE Agent call (MID model):
prompt: "Integrate all team member results.
Read .swarm/teams/{name}/outbox/*.md and artifacts/*

CHECK:
1. All deliverables present?
2. Any conflicts between changes?
3. Pieces work together? (run tests)
4. Team goal fully achieved?

If success:
- Update team.json status → 'completed'
- Write artifacts/integration-report.md

If issues:
- List what to fix
- Suggest which member fixes it
- DON'T close team"
```

## Multi-session use

The team workspace is filesystem-based, so:
- Any Qoder session that opens this project sees the team
- Stop-continuation hook (if installed) alerts about active teams
- Members can be different Qoder sessions checking their inbox

## Model tiers

| Stage | Model |
|-------|-------|
| Init / monitor | `Qwen3.7-Max-DogFooding` (FREE) |
| Dispatch / integrate | `GLM-5.2` (MID, judgment) |
