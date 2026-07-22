export const meta = {
  name: 'five-agent-review',
  description: 'Post-implementation 5-agent parallel review: Goal verification, QA execution, Code quality, Security audit, Context mining. All must PASS.',
  whenToUse: 'After completing implementation work. When user says "review work", "review changes", "QA my work", "check my work", "validate changes".',
  phases: [
    { title: 'Gather', detail: 'Collect diff, files, context' },
    { title: 'Review', detail: '5 parallel review agents' },
    { title: 'Verdict', detail: 'Synthesize final report' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      goal: { type: 'string', description: 'Original objective' },
      constraints: { type: 'string', description: 'Rules and limitations' },
      base: { type: 'string', description: 'Git base ref (default: HEAD~1)' },
    },
    required: ['goal'],
  },
}

const goal = args.goal
const constraints = args.constraints || 'None specified'
const base = args.base || 'HEAD~1'

// Model tiers - adjust to your preference / credit budget
const CHEAP = 'Peach-07-17-DogFooding'  // 0.00x - FREE! search, read-only
const MID   = 'GLM-5.2'                 // 0.60x - code, QA execution
const HEAVY = 'GLM-5.2'                 // 0.60x - deep reasoning

// Phase 1: Gather context (cheap - just reading)
phase('Gather')
log('Collecting review context...')

const context = await agent(`TASK: Gather review context for a code review.

Run these commands and return their output:
1. git diff --name-only ${base} (changed files)
2. git diff --stat ${base} (change summary)
3. For each changed file (max 10): read the full file content

DELIVERABLE: JSON-like structured output:
- changed_files: [list of paths]
- diff_stat: summary
- file_contents: {path: content} for each file

SCOPE: Read-only git commands and file reads only.
VERIFY: All paths exist, all content is current.`, {
  label: 'context-gatherer',
  phase: 'Gather',
  model: CHEAP,
})

// Phase 2: 5 parallel review agents
phase('Review')
log('Launching 5 review agents in parallel...')

const results = await parallel([
  // Agent 1: Goal & Constraint Verification (needs deep reasoning)
  () => agent(`TASK: GOAL & CONSTRAINT VERIFICATION.

ORIGINAL GOAL: ${goal}
CONSTRAINTS: ${constraints}
CHANGES: ${context}

Review whether this implementation correctly achieves the stated goal within constraints.

CHECK:
1. Goal Completeness: break into sub-requirements, mark ACHIEVED/MISSED/PARTIAL
2. Constraint Compliance: verify each with code evidence
3. Requirement Gaps: implied requirements a thoughtful engineer would include
4. Over-Engineering: anything added that wasn't requested
5. Edge Cases: trace 5+ scenarios mentally

OUTPUT:
<verdict>PASS or FAIL</verdict>
<summary>1-3 sentences</summary>
<blocking_issues>Must-fix items or empty</blocking_issues>`, {
    label: 'goal-verifier',
    phase: 'Review',
    model: HEAVY,
  }),

  // Agent 2: QA Execution (needs tool access, moderate reasoning)
  () => agent(`TASK: QA BY ACTUALLY RUNNING THE CODE.

GOAL: ${goal}
CHANGED FILES: ${context}

You are a QA engineer. Run the code and verify it works.

PROCESS:
1. Find the test command (package.json scripts, Makefile, etc.)
2. Run tests - report pass/fail
3. If it's a web app, check build succeeds
4. Run linter/typecheck if configured
5. Try 3+ edge cases relevant to the goal

OUTPUT:
<verdict>PASS or FAIL</verdict>
<summary>1-3 sentences</summary>
<test_results>What passed/failed</test_results>
<blocking_issues>P0/P1 failures or empty</blocking_issues>`, {
    label: 'qa-executor',
    phase: 'Review',
    model: MID,
  }),

  // Agent 3: Code Quality (needs deep reasoning)
  () => agent(`TASK: CODE QUALITY REVIEW.

CHANGES: ${context}

You are a senior staff engineer. Standard: "Would I approve this PR without comments?"

REVIEW:
1. Correctness: logic errors, race conditions, resource leaks
2. Pattern Consistency: follows codebase conventions?
3. Naming & Readability: self-documenting?
4. Error Handling: proper catch, log, propagate?
5. Type Safety: no any/ts-ignore/unsafe casts?
6. Performance: N+1? unnecessary re-renders? memory leaks?
7. Abstraction Level: right level? no premature over-abstraction?
8. Testing: new behaviors covered?

Severity: CRITICAL > MAJOR > MINOR > NITPICK

OUTPUT:
<verdict>PASS or FAIL</verdict>
<summary>1-3 sentences</summary>
<findings>Categorized list</findings>
<blocking_issues>CRITICAL and MAJOR only, or empty</blocking_issues>`, {
    label: 'code-reviewer',
    phase: 'Review',
    model: HEAVY,
  }),

  // Agent 4: Security (moderate reasoning, focused scope)
  () => agent(`TASK: SECURITY REVIEW.

CHANGES: ${context}

Review exclusively for security vulnerabilities. Ignore code style.

CHECK:
1. Input Validation: SQL injection, XSS, command injection, SSRF?
2. Auth & AuthZ: checks where needed? privilege escalation?
3. Secrets: hardcoded keys/tokens? secrets in logs?
4. Data Exposure: PII in errors? over-exposed APIs?
5. Dependencies: new deps with known CVEs?
6. Path Traversal: unsafe file ops?

OUTPUT:
<verdict>PASS or FAIL</verdict>
<severity>CRITICAL/HIGH/MEDIUM/LOW/NONE</severity>
<findings>Risk + remediation for each</findings>
<blocking_issues>CRITICAL and HIGH only, or empty</blocking_issues>`, {
    label: 'security-auditor',
    phase: 'Review',
    model: MID,
  }),

  // Agent 5: Context Mining (cheap - search and read)
  () => agent(`TASK: CONTEXT MINING - find missed requirements.

GOAL: ${goal}
CHANGED FILES: ${context}

Search every accessible source for context that should have informed this work.

SEARCH:
1. git log --oneline -20 -- <each changed file>
2. git blame on critical sections
3. grep for TODO/FIXME/HACK in changed files
4. Find files that import/reference changed modules
5. Check if docs/README need updates

LOOK FOR:
- Past decisions explaining WHY code was written a certain way
- Related features affected by these changes
- Warnings from previous developers
- Missing documentation updates

OUTPUT:
<verdict>PASS or FAIL</verdict>
<summary>1-3 sentences</summary>
<discovered_context>Source + finding + relevance</discovered_context>
<blocking_issues>BLOCKING items or empty</blocking_issues>`, {
    label: 'context-miner',
    phase: 'Review',
    model: CHEAP,
  }),
])

// Phase 3: Synthesize verdict
phase('Verdict')

const labels = ['Goal Verification', 'QA Execution', 'Code Quality', 'Security', 'Context Mining']
const verdicts = results.map((r, i) => `${labels[i]}: ${r}`)

log(`All 5 reviews complete. Synthesizing verdict...`)

const finalReport = await agent(`TASK: Synthesize a final review report from 5 parallel review agents.

RESULTS:
${verdicts.join('\n\n---\n\n')}

RULES:
- ALL 5 must PASS for overall PASS
- ANY FAIL = overall FAIL
- Deduplicate blocking issues across agents
- Prioritize fixes if FAILED

OUTPUT FORMAT:
# Review Report
## Overall Verdict: PASSED / FAILED
| # | Area | Verdict |
| 1 | Goal Verification | ... |
| 2 | QA Execution | ... |
| 3 | Code Quality | ... |
| 4 | Security | ... |
| 5 | Context Mining | ... |

## Blocking Issues (if any)
## Recommendations`, {
  label: 'synthesizer',
  phase: 'Verdict',
})

log('Review complete.')
