export const meta = {
  name: 'debugging',
  description: 'Hypothesis-driven debugging: form 3+ hypotheses, investigate in parallel, confirm root cause with runtime evidence, fix minimally, verify.',
  whenToUse: 'When user says "debug this", "why is X broken", "trace this bug", "reproduce and fix", "silent failure", or hits a runtime issue.',
  phases: [
    { title: 'Hypothesize', detail: 'Form 3+ competing hypotheses' },
    { title: 'Investigate', detail: 'Parallel evidence gathering' },
    { title: 'Fix', detail: 'Minimal targeted fix + failing test' },
    { title: 'Verify', detail: 'Confirm fix and no regression' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      symptom: { type: 'string', description: 'What is broken / the error message / unexpected behavior' },
      context: { type: 'string', description: 'Any additional context (file, URL, recent change)' },
    },
    required: ['symptom'],
  },
}

const CHEAP = 'Qwen3.7-Max-DogFooding'
const MID   = 'GLM-5.2'
const symptom = args.symptom
const context = args.context || ''

// Phase 1: Form hypotheses
phase('Hypothesize')
log(`Symptom: ${symptom}`)

const hypotheses = await agent(`TASK: Form at least 3 competing hypotheses for this bug.

SYMPTOM: ${symptom}
CONTEXT: ${context}

RULES:
- Runtime truth beats code reading. Do NOT just guess from code.
- Look at error messages, stack traces, logs, git blame for recent changes.
- Each hypothesis must be FALSIFIABLE: name the exact check that would confirm or rule it out.
- Order by likelihood (most likely first).
- Include at least one "weird" hypothesis (race condition, stale cache, env mismatch).

DELIVERABLE:
For each hypothesis:
- H1: [statement]
  Check: [exact command/action to confirm or refute]
  If confirmed: [what the fix would be]
  If refuted: [what to try next]

- H2: ...
- H3: ...

SCOPE: Read code, run diagnostic commands, check logs. Do not fix anything yet.`, {
  label: 'hypothesis-former',
  phase: 'Hypothesize',
  model: MID,
  schema: {
    type: 'object',
    properties: {
      hypotheses: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' },
            statement: { type: 'string' },
            check: { type: 'string' },
            if_confirmed: { type: 'string' },
            if_refuted: { type: 'string' },
          },
          required: ['id', 'statement', 'check'],
        },
      },
    },
    required: ['hypotheses'],
  },
})

if (!hypotheses || !hypotheses.hypotheses || hypotheses.hypotheses.length < 2) {
  log('ERROR: Could not form sufficient hypotheses.')
  return
}

log(`Formed ${hypotheses.hypotheses.length} hypotheses. Investigating in parallel...`)

// Phase 2: Parallel investigation - one agent per hypothesis
phase('Investigate')

const investigations = await parallel(
  hypotheses.hypotheses.map(h => () => agent(`TASK: Investigate hypothesis "${h.statement}"

CHECK TO RUN: ${h.check}

RULES:
- Run the check command/action EXACTLY as stated
- Report the ACTUAL output (do not summarize or interpret prematurely)
- Based on the output, declare: CONFIRMED | REFUTED | INCONCLUSIVE
- If CONFIRMED: describe the root cause precisely
- If REFUTED: state what the evidence actually showed
- If INCONCLUSIVE: state what additional check would disambiguate

DELIVERABLE:
Hypothesis: ${h.statement}
Verdict: CONFIRMED | REFUTED | INCONCLUSIVE
Evidence: [actual command output or observation]
Root cause (if confirmed): [precise description]`, {
    label: `investigate-${h.id}`,
    phase: 'Investigate',
    model: CHEAP,
  }))
)

// Find confirmed hypothesis
const confirmedIdx = investigations.findIndex(r => r && r.includes('CONFIRMED'))
const rootCause = confirmedIdx >= 0
  ? investigations[confirmedIdx]
  : investigations.filter(Boolean).join('\n')

if (confirmedIdx < 0) {
  log('No hypothesis confirmed in first round. Using strongest evidence to guide fix.')
}

// Phase 3: Minimal fix
phase('Fix')
log('Applying minimal fix...')

const fix = await agent(`TASK: Fix this bug with the MINIMAL correct change.

SYMPTOM: ${symptom}
ROOT CAUSE EVIDENCE:
${rootCause}

RULES:
1. Write a FAILING TEST FIRST that reproduces the bug
2. Run it - confirm it fails for the right reason
3. Apply the smallest fix that makes the test pass
4. Do NOT refactor surrounding code
5. Do NOT add unrelated improvements

DELIVERABLE:
- Test file + test name that reproduces the bug
- The fix (which files, what changed)
- The test now passes`, {
  label: 'fixer',
  phase: 'Fix',
  model: MID,
})

// Phase 4: Verify no regression
phase('Verify')
log('Verifying fix and checking for regressions...')

const verify = await agent(`TASK: Verify the bug fix is correct and introduces no regressions.

SYMPTOM: ${symptom}
FIX APPLIED: ${fix}

RUN:
1. Run the full test suite (not just the new test)
2. Run typecheck/lint
3. If it's a runtime bug, reproduce the original symptom and confirm it's gone
4. Check git diff - is the change minimal? No unrelated modifications?

DELIVERABLE:
- Regression test: PASS/FAIL
- Full suite: PASS/FAIL (count)
- Original symptom: GONE / STILL PRESENT
- Change scope: MINIMAL / OVER-BROAD
- Overall: FIXED | NEEDS-MORE-WORK + what`, {
  label: 'verifier',
  phase: 'Verify',
  model: MID,
})

log('Debugging complete.')
