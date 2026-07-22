export const meta = {
  name: 'teammode',
  description: 'Persistent multi-session team orchestration with durable file state. Leader orchestrates, never implements. Members own concrete slices. State lives in .swarm/teams/.',
  whenToUse: 'When user says "team mode", "make a team", "run as a team", "coordinate threads", "parallel sessions", or needs cross-session persistent collaboration.',
  phases: [
    { title: 'Init', detail: 'Create team structure and assign roles' },
    { title: 'Dispatch', detail: 'Send tasks to members via inbox' },
    { title: 'Monitor', detail: 'Poll outbox for results' },
    { title: 'Integrate', detail: 'Merge results and close team' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      name: { type: 'string', description: 'Team name' },
      goal: { type: 'string', description: 'What the team should accomplish' },
      members: {
        type: 'array',
        description: 'Team members: [{role, focus, deliverable}]',
        items: {
          type: 'object',
          properties: {
            role: { type: 'string' },
            focus: { type: 'string' },
            deliverable: { type: 'string' },
          },
          required: ['role', 'focus'],
        },
      },
    },
    required: ['name', 'goal'],
  },
}

const CHEAP = 'Peach-07-17-DogFooding'
const MID   = 'GLM-5.2'
const teamName = args.name
const goal = args.goal
const members = args.members || []

// Phase 1: Initialize team state
phase('Init')
log(`Creating team "${teamName}" for: ${goal}`)

const teamSetup = await agent(`TASK: Initialize a persistent team workspace.

TEAM NAME: ${teamName}
GOAL: ${goal}
REQUESTED MEMBERS: ${JSON.stringify(members)}

CREATE THIS DIRECTORY STRUCTURE:
.swarm/teams/${teamName}/
├── team.json          # Team state (see schema below)
├── guide.md           # Auto-generated member field manual
├── inbox/             # Leader → Member task files
│   ├── {role}.md      # One per member
├── outbox/            # Member → Leader result files
│   ├── {role}.md
└── artifacts/         # Shared exchange space

TEAM.JSON SCHEMA:
{
  "name": "${teamName}",
  "goal": "${goal}",
  "status": "active",
  "created": "<ISO timestamp - use the string '2026-06-26T12:00:00Z' as placeholder>",
  "members": [
    {
      "id": "A",
      "role": "<role name>",
      "focus": "<what they own - concrete, not vague>",
      "deliverable": "<expected output>",
      "status": "active",
      "branch": "<optional git branch>"
    }
  ],
  "log": []
}

IF NO MEMBERS SPECIFIED: analyze the goal and suggest 2-4 members, each owning a distinct slice (by part, ownership, or perspective - NEVER a vague job title like "backend dev").

GUIDE.MD should contain:
- Team goal
- Each member's role, focus, deliverable
- Communication protocol (write to outbox, read from inbox)
- How to report: status, blockers, completion

DELIVERABLE: Create the directory structure and files. Report the final team composition.`, {
  label: 'team-initializer',
  phase: 'Init',
  model: CHEAP,
})

// Phase 2: Dispatch initial tasks
phase('Dispatch')
log('Writing initial task assignments to inbox...')

const dispatch = await agent(`TASK: Write initial task assignments for each team member.

TEAM STATE: Read .swarm/teams/${teamName}/team.json
GOAL: ${goal}

For each member in team.json:
1. Write a task to .swarm/teams/${teamName}/inbox/{role}.md using this format:

---
From: leader
To: {role}
Time: 2026-06-26T12:00:00Z
Type: task_handoff
Status: new

## Goal
{Specific task derived from the team goal, scoped to this member's focus}

## Scope
- Touch: {what this member owns}
- Do NOT touch: {other members' territory}

## Context
{Relevant context from the team goal}

## Deliverable
{What to write to outbox when done}

## Coordination
- If you need something from another member, write to artifacts/ and note it in your outbox
- If blocked, write BLOCKED + reason to your outbox immediately
---

2. Update team.json log with dispatch entries.

RULES:
- Each task must be self-contained (member has no access to leader context)
- Tasks must not overlap (each member's scope is exclusive)
- Include enough context for the member to start without asking questions

DELIVERABLE: Confirm all inbox files written. List each member + their assigned task summary.`, {
  label: 'task-dispatcher',
  phase: 'Dispatch',
  model: MID,
})

// Phase 3: Monitor (in a real multi-session setup, this would poll)
phase('Monitor')
log('Checking outbox for results...')

const monitor = await agent(`TASK: Check team progress by reading outbox files.

Read all files in .swarm/teams/${teamName}/outbox/

For each member:
- If outbox exists and has content → report status
- If outbox is empty or missing → report "awaiting"
- If outbox says BLOCKED → flag for leader attention

Also check .swarm/teams/${teamName}/artifacts/ for any shared evidence.

DELIVERABLE: Status table:
| Member | Role | Status | Summary |
| --- | --- | --- | --- |
| A | ... | done/working/blocked/awaiting | ... |

If all members are done → recommend moving to Integration phase.
If any are blocked → suggest unblocking action.`, {
  label: 'progress-monitor',
  phase: 'Monitor',
  model: CHEAP,
})

// Phase 4: Integrate
phase('Integrate')
log('Integrating team results...')

const integration = await agent(`TASK: Integrate all team member results into a coherent whole.

Read all outbox files from .swarm/teams/${teamName}/outbox/
Read any artifacts from .swarm/teams/${teamName}/artifacts/

INTEGRATION CHECKLIST:
1. Are all deliverables present?
2. Do any changes conflict with each other?
3. Do all pieces work together? (run tests if applicable)
4. Is the team goal fully achieved?

If integration succeeds:
- Update team.json status to "completed"
- Write a summary to .swarm/teams/${teamName}/artifacts/integration-report.md

If issues found:
- List what needs fixing
- Suggest which member should fix it
- Do NOT close the team

DELIVERABLE: Integration report + team status update.`, {
  label: 'integrator',
  phase: 'Integrate',
  model: MID,
})

log(`Team "${teamName}" workflow complete.`)
