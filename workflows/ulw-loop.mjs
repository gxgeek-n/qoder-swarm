export const meta = {
  name: 'ulw-loop',
  description: 'Self-referential execution loop with durable ledger. Runs until all success criteria have captured evidence. Survives context loss via file state. Max iterations configurable.',
  whenToUse: 'When user says "ulw-loop", "ulw", "keep going until done", "run until verified", or needs a long-running task with evidence checkpoints.',
  phases: [
    { title: 'Bootstrap', detail: 'Create goal + success criteria + ledger' },
    { title: 'Loop', detail: 'Execute → verify → record, repeat' },
    { title: 'Complete', detail: 'All criteria met with evidence' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      task: { type: 'string', description: 'What to accomplish' },
      maxIterations: { type: 'number', description: 'Max loop iterations (default 20)' },
      criteria: { type: 'array', items: { type: 'string' }, description: 'Explicit success criteria (optional, auto-generated if missing)' },
    },
    required: ['task'],
  },
}

const CHEAP = 'Qwen3.7-Max-DogFooding'
const MID   = 'GLM-5.2'
const task = args.task
const maxIterations = args.maxIterations || 20
const explicitCriteria = args.criteria || null

// Phase 1: Bootstrap - create goal state
phase('Bootstrap')
log(`ULW Loop: ${task}`)

const bootstrap = await agent(`TASK: Create a durable goal state for this work.

WORK: ${task}
${explicitCriteria ? `USER-PROVIDED CRITERIA:\n${explicitCriteria.join('\n')}` : ''}

CREATE: .swarm/ulw-loop/state.json with:
{
  "task": "${task}",
  "status": "active",
  "iteration": 0,
  "max_iterations": ${maxIterations},
  "criteria": [
    {
      "id": "C1",
      "description": "<verifiable condition>",
      "verification": "<exact command that proves it>",
      "status": "pending",
      "evidence": null
    }
  ]
}

CREATE: .swarm/ulw-loop/ledger.jsonl (empty, will be appended)

RULES for criteria:
- ${explicitCriteria ? 'Use the user-provided criteria, make each verifiable' : 'Generate 2-5 criteria from the task'}
- Each must have an exact verification command
- "verify it works" is NOT a criterion - name the tool + expected output
- Include at least: happy path + one edge case

DELIVERABLE: Created state.json with criteria list. Report the criteria.`, {
  label: 'bootstrapper',
  phase: 'Bootstrap',
  model: CHEAP,
  schema: {
    type: 'object',
    properties: {
      criteria: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' },
            description: { type: 'string' },
            verification: { type: 'string' },
          },
          required: ['id', 'description', 'verification'],
        },
      },
    },
    required: ['criteria'],
  },
})

if (!bootstrap || !bootstrap.criteria || bootstrap.criteria.length === 0) {
  log('ERROR: Could not establish success criteria.')
  return
}

const totalCriteria = bootstrap.criteria.length
log(`Established ${totalCriteria} criteria. Starting execution loop...`)

// Phase 2: Execution loop
phase('Loop')

let completedCount = 0
let iteration = 0

while (completedCount < totalCriteria && iteration < maxIterations) {
  iteration++
  log(`Iteration ${iteration}/${maxIterations} — ${completedCount}/${totalCriteria} criteria met`)

  if (budget.total && budget.remaining() < budget.total * 0.1) {
    log(`Budget low (${budget.remaining()} remaining). Stopping loop.`)
    break
  }

  const stepResult = await agent(`TASK: Execute one step toward completing the remaining criteria.

READ .swarm/ulw-loop/state.json to see which criteria are still pending.
READ .swarm/ulw-loop/ledger.jsonl to see what has been done so far.

CURRENT ITERATION: ${iteration}
COMPLETED SO FAR: ${completedCount}/${totalCriteria}

RULES:
1. Pick the FIRST pending criterion
2. Do the work needed to satisfy it
3. Run the verification command
4. If it passes: update state.json (status→"done", evidence→output), append to ledger.jsonl
5. If it fails: append failure to ledger.jsonl, try a different approach next iteration
6. Do NOT skip criteria. Do NOT mark as done without running verification.

LEDGER ENTRY FORMAT (append one line to ledger.jsonl):
{"iteration":${iteration},"criterion":"<id>","action":"<what was done>","result":"pass|fail","evidence":"<verification output>","timestamp":"2026-06-26T12:00:00Z"}

DELIVERABLE: Report what was done, which criterion was attempted, pass or fail.`, {
    label: `loop-${iteration}`,
    phase: 'Loop',
    model: MID,
  })

  // Check if a criterion was completed
  if (stepResult && (stepResult.includes('"result":"pass"') || stepResult.includes('pass') || stepResult.includes('PASS'))) {
    completedCount++
  }
}

// Phase 3: Completion
phase('Complete')

if (completedCount >= totalCriteria) {
  log(`ALL ${totalCriteria} criteria met in ${iteration} iterations.`)
} else {
  log(`Stopped at ${iteration} iterations. ${completedCount}/${totalCriteria} criteria met.`)
}

await agent(`TASK: Generate final ULW loop report.

READ .swarm/ulw-loop/state.json and .swarm/ulw-loop/ledger.jsonl

REPORT:
- Task: ${task}
- Iterations used: ${iteration}/${maxIterations}
- Criteria met: ${completedCount}/${totalCriteria}
- For each criterion: status + evidence summary
- If incomplete: what remains and suggested next steps

Update state.json status to "${completedCount >= totalCriteria ? 'completed' : 'paused'}"

DELIVERABLE: Final status report.`, {
  label: 'reporter',
  phase: 'Complete',
  model: CHEAP,
})
