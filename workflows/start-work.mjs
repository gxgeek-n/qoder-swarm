export const meta = {
  name: 'start-work',
  description: 'Execute a plan with pure orchestration - main agent never writes code, all implementation delegated to parallel workers with evidence verification.',
  whenToUse: 'When user says "start work", "execute plan", "implement this plan". Requires a plan file or task list.',
  phases: [
    { title: 'Parse', detail: 'Read plan and identify tasks' },
    { title: 'Execute', detail: 'Dispatch parallel workers per wave' },
    { title: 'Verify', detail: 'Adversarial verification of results' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      plan: { type: 'string', description: 'Plan content or path to plan file' },
      tasks: { type: 'array', description: 'Task list if no plan file', items: { type: 'string' } },
    },
  },
}

const planContent = args.plan || (args.tasks ? args.tasks.join('\n') : null)
if (!planContent) {
  log('ERROR: No plan or tasks provided. Pass plan content or a tasks array.')
  return
}

// Model tiers - adjust to your preference / credit budget
const CHEAP = 'Qwen3.7-Max-DogFooding'  // 0.00x - FREE! parsing, read-only
const MID   = 'GLM-5.2'                 // 0.60x - implementation workers
const HEAVY = 'GLM-5.2'                 // 0.60x - adversarial verification

// Phase 1: Parse plan into executable units
phase('Parse')
log('Parsing plan into execution waves...')

const parsed = await agent(`TASK: Parse this plan into parallel execution waves.

PLAN:
${planContent}

DELIVERABLE: A JSON structure (output as plain text, not code block):
{
  "waves": [
    {
      "wave": 1,
      "tasks": [
        {"id": "1", "title": "...", "description": "...", "files": ["..."], "acceptance": "...", "depends_on": []}
      ]
    }
  ]
}

RULES:
- Tasks with no dependencies go in Wave 1
- Tasks depending on Wave 1 go in Wave 2, etc.
- Each task must have: id, title, description, files (to touch), acceptance (verifiable criterion)
- Maximize parallelism: independent tasks in the same wave

SCOPE: Analysis only. Do not edit any files.`, {
  label: 'plan-parser',
  phase: 'Parse',
  model: CHEAP,
  schema: {
    type: 'object',
    properties: {
      waves: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            wave: { type: 'number' },
            tasks: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  id: { type: 'string' },
                  title: { type: 'string' },
                  description: { type: 'string' },
                  files: { type: 'array', items: { type: 'string' } },
                  acceptance: { type: 'string' },
                },
                required: ['id', 'title', 'description', 'acceptance'],
              },
            },
          },
          required: ['wave', 'tasks'],
        },
      },
    },
    required: ['waves'],
  },
})

if (!parsed || !parsed.waves) {
  log('ERROR: Could not parse plan into waves.')
  return
}

// Phase 2: Execute waves sequentially, tasks within each wave in parallel
phase('Execute')

for (const wave of parsed.waves) {
  log(`Wave ${wave.wave}: dispatching ${wave.tasks.length} tasks in parallel...`)

  const waveResults = await parallel(
    wave.tasks.map(task => () => agent(`TASK: Implement this task completely.

TITLE: ${task.title}
DESCRIPTION: ${task.description}
FILES TO TOUCH: ${(task.files || []).join(', ') || 'Determine from context'}
ACCEPTANCE CRITERION: ${task.acceptance}

RULES:
- Make the smallest correct change
- Write tests if the criterion requires verification
- Do not touch files outside your assignment
- Report exactly what you changed

DELIVERABLE:
1. What files were modified/created
2. What the change does
3. How to verify: exact command + expected output

VERIFY: Run the acceptance criterion command and confirm it passes.`, {
      label: `worker-${task.id}`,
      phase: 'Execute',
      model: MID,
      isolation: 'worktree',
    }))
  )

  log(`Wave ${wave.wave} complete: ${waveResults.filter(Boolean).length}/${wave.tasks.length} succeeded`)
}

// Phase 3: Adversarial verification
phase('Verify')
log('Running adversarial verification...')

const verification = await agent(`TASK: Act as an adversarial verifier. Check that the work actually accomplished the plan.

ORIGINAL PLAN:
${planContent}

Verify:
1. Run tests (find and execute the test command)
2. Run typecheck/lint if available
3. Check that each acceptance criterion from the plan is met
4. Look for regressions: did anything that worked before break?

For each task, report:
- confirmed: the criterion passes with evidence
- false-positive: claimed done but actually broken
- needs-fix: partial completion

OUTPUT:
For each plan item: [confirmed | false-positive | needs-fix] + evidence
Overall: DONE or NEEDS-WORK + specific items to fix`, {
  label: 'adversarial-verifier',
  phase: 'Verify',
  model: HEAVY,
})

log('Execution and verification complete.')
