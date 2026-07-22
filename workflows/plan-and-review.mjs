export const meta = {
  name: 'plan-and-review',
  description: 'Explore-first planning with adversarial review. Explorer+Librarian research in parallel, then Planner drafts, Metis finds gaps, Momus approves or iterates.',
  whenToUse: 'When the user says "plan this", "ulw-plan", "break this down", or work has 5+ steps, ambiguous scope, multiple modules.',
  phases: [
    { title: 'Research', detail: 'Parallel explore + librarian research' },
    { title: 'Plan', detail: 'Draft execution plan' },
    { title: 'Gap Analysis', detail: 'Metis finds contradictions and risks' },
    { title: 'Review', detail: 'Momus approves or iterates' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      task: { type: 'string', description: 'What to plan' },
      cwd: { type: 'string', description: 'Project root path' },
    },
    required: ['task'],
  },
}

// Model tiers - adjust to your preference / credit budget
const CHEAP = 'Peach-07-17-DogFooding'  // 0.00x - FREE! search, read-only
const MID   = 'GLM-5.2'                 // 0.60x - code implementation
const HEAVY = 'GLM-5.2'                 // 0.60x - deep reasoning + code
// Total cost for plan-and-review: ~1.80x (vs 5x all-ultimate)

const task = args.task
const cwd = args.cwd || '.'

// Phase 1: Parallel research (cheap models - explorer/librarian are read-only)
phase('Research')
log(`Researching: ${task}`)

const [codeInsight, docsInsight] = await parallel([
  () => agent(`TASK: Act as a codebase explorer. Find all files, patterns, and conventions relevant to: ${task}

DELIVERABLE: A structured report with:
- Relevant file paths (absolute)
- Existing patterns to follow
- Anti-patterns to avoid
- Entry points and dependencies

SCOPE: Read-only. Never edit files.
VERIFY: Every path exists. Every claim cites a file.`, {
    label: 'explorer',
    phase: 'Research',
    model: CHEAP,
  }),

  () => agent(`TASK: Act as a librarian. Research external docs, OSS examples, and best practices for: ${task}

DELIVERABLE: Cited findings with:
- Official doc references
- Real-world implementation examples
- Known pitfalls and gotchas
- Recommended approach with evidence

SCOPE: External sources only. Do not inspect the local codebase.
VERIFY: Every claim has a URL or source citation.`, {
    label: 'librarian',
    phase: 'Research',
    model: CHEAP,
  }),
])

// Phase 2: Plan (high reasoning - this is the core intellectual work)
phase('Plan')
log('Drafting execution plan...')

const plan = await agent(`TASK: Act as a strategic planner. Produce ONE executable work plan.

USER REQUEST: ${task}

CODEBASE CONTEXT (from explorer):
${codeInsight}

EXTERNAL RESEARCH (from librarian):
${docsInsight}

DELIVERABLE: A complete plan in markdown with:
## TL;DR
## Scope (Must have / Must NOT have)
## Execution waves (parallel grouping + dependency matrix)
## Todos (each with: What to do / References / Acceptance criteria / QA scenarios)

CONSTRAINTS:
- Every task must be atomic and agent-executable
- Every acceptance criterion must be verifiable by command
- No "verify it works" - name the exact tool + invocation
- Decision-complete: executor needs zero further interview
- Include parallel execution waves with dependency matrix

SCOPE: Write plan text only. Never edit product code.
VERIFY: Every referenced file exists. Every task has acceptance criteria.`, {
  label: 'planner',
  phase: 'Plan',
  model: HEAVY,
})

// Phase 3: Gap analysis (high reasoning - finding subtle issues)
phase('Gap Analysis')
log('Analyzing plan for gaps...')

const gaps = await agent(`TASK: Act as a pre-planning analyst (Metis). Examine this plan and surface contradictions, ambiguity, missing constraints, and execution risks.

PLAN TO ANALYZE:
${plan}

ORIGINAL REQUEST: ${task}

CHECK THESE DIMENSIONS:
1. Contradictions: two requirements that cannot both be true
2. Ambiguity: terms the executor would need to guess
3. Missing constraints: auth, error handling, concurrency, rollback, test strategy
4. Execution risks: missing file refs, unreachable criteria, vague QA
5. Topology gaps: components lacking goal clarity

DELIVERABLE: Structured gap report with:
## Contradictions (or "None found")
## Ambiguity (term + clarifying question)
## Missing Constraints (constraint + why it matters)
## Execution Risks (risk + suggested fix)
## Verdict: CLEAR or GAPS FOUND

SCOPE: Read-only analysis. Never write plans or code.
VERIFY: Every finding is specific enough for the planner to act on.`, {
  label: 'metis',
  phase: 'Gap Analysis',
  model: HEAVY,
})

// Phase 4: Review (high reasoning - final gate)
phase('Review')
log('Momus reviewing plan...')

const review = await agent(`TASK: Act as a plan reviewer (Momus). Verify this plan is executable.

PLAN:
${plan}

GAP ANALYSIS:
${gaps}

ANSWER ONE QUESTION: "Can a capable developer execute this plan without getting stuck?"

CHECK ONLY:
1. Reference verification: do cited files/patterns exist?
2. Executability: can a developer START each task?
3. Critical blockers: missing info that would COMPLETELY STOP work?
4. QA executability: does each task have concrete tool + steps + expected?

DECISION FRAMEWORK:
- OKAY (default): 80% clear is good enough. Approve.
- ITERATE: max 3 fixable gaps the planner can patch alone.
- REJECT: impossible requirements or user decision needed.

DELIVERABLE:
**[OKAY]** or **[ITERATE]** or **[REJECT]**
**Summary**: 1-2 sentences.
**Issues** (max 3, if ITERATE/REJECT): specific + actionable.

SCOPE: Read-only. Never write plans or code.
VERIFY: Approval bias - when in doubt, APPROVE.`, {
  label: 'momus',
  phase: 'Review',
  model: HEAVY,
})

log(`Plan complete. Review verdict delivered.`)
