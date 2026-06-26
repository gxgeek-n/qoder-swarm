export const meta = {
  name: 'remove-ai-slops',
  description: 'Clean AI-generated code smells: lock behavior with regression tests FIRST, then parallel cleanup in batches of 5, then verify with quality gates.',
  whenToUse: 'When user says "remove slop", "clean AI code", "deslop", "cleanup AI generated", "strip slop".',
  phases: [
    { title: 'Scope', detail: 'Identify changed files' },
    { title: 'Lock', detail: 'Write regression tests to pin behavior' },
    { title: 'Clean', detail: 'Parallel slop removal in batches of 5' },
    { title: 'Verify', detail: 'Quality gates + critical review' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      files: { type: 'array', items: { type: 'string' }, description: 'Explicit file list (optional, defaults to branch diff)' },
      base: { type: 'string', description: 'Git base ref (default: main)' },
    },
  },
}

const CHEAP = 'Qwen3.7-Max-DogFooding'
const MID   = 'GLM-5.2'

const base = args.base || 'main'
const explicitFiles = args.files || null

// Phase 1: Determine scope
phase('Scope')
log('Determining cleanup scope...')

const scope = await agent(`TASK: Determine which files need AI slop cleanup.

${explicitFiles ? `EXPLICIT FILE LIST:\n${explicitFiles.join('\n')}` : `Run: git diff $(git merge-base ${base} HEAD)..HEAD --name-only`}

Filter out: deleted files, binary files, generated/vendored (node_modules, dist, target, lockfiles).

DELIVERABLE: A clean list of source files to process, one per line.
SCOPE: Read-only. Do not edit anything.`, {
  label: 'scope-finder',
  phase: 'Scope',
  model: CHEAP,
})

const files = scope.trim().split('\n').filter(f => f.trim().length > 0)
if (files.length === 0) {
  log('No files in scope. Nothing to clean.')
  return
}
log(`Found ${files.length} files to clean.`)

// Phase 2: Lock behavior with regression tests
phase('Lock')
log('Locking behavior with regression tests...')

const lockResult = await agent(`TASK: For each file, verify existing test coverage. Write MINIMAL regression tests only for uncovered public behavior.

FILES:
${files.join('\n')}

RULES:
- Check if existing tests cover the public API of each file
- Only write tests for UNCOVERED behavior (do not duplicate existing tests)
- Tests pin CURRENT behavior (inputs + outputs), not implementation details
- Run the test suite after. All must be GREEN before we proceed.
- If tests cannot be written (no test infra), report which files are uncovered.

DELIVERABLE: Test status per file: [covered | new-test-added | uncoverable]
Run the test suite and confirm GREEN baseline.`, {
  label: 'behavior-locker',
  phase: 'Lock',
  model: MID,
})

// Phase 3: Parallel slop removal in batches of 5
phase('Clean')

const BATCH_SIZE = 5
const batches = []
for (let i = 0; i < files.length; i += BATCH_SIZE) {
  batches.push(files.slice(i, i + BATCH_SIZE))
}

log(`Processing ${files.length} files in ${batches.length} batches of ${BATCH_SIZE}...`)

for (let b = 0; b < batches.length; b++) {
  const batch = batches[b]
  log(`Batch ${b + 1}/${batches.length}: ${batch.join(', ')}`)

  await parallel(
    batch.map(file => () => agent(`TASK: Remove AI slops from: ${file}

CATEGORIES (check all, apply in order safest→riskiest):
1. Obvious comments - restating code, trivial docstrings, section dividers
2. Over-defensive code - null checks for guaranteed values, broad catch blocks
3. Excessive complexity - deep nesting >3, nested ternaries, god functions >50 lines
4. Needless abstraction - pass-through wrappers, single-use helpers
5. Dead code - unused imports/functions, unreachable branches, debug leftovers
6. Duplication - copy-paste branches with trivial differences
7. Performance equivalences - O(n²)→O(n) via set, hoist computation out of loops

HARD CONSTRAINTS:
- Behavior MUST be preserved (regression tests are green)
- Do NOT change public API signatures
- Do NOT remove type hints
- Do NOT introduce new abstractions
- If equivalence is not obvious, SKIP
- Apply order: comments → dead code → defensive → duplication → complexity → abstraction → performance

DELIVERABLE: List changes by category. For each: before/after, why-slop, why-safe.
For skipped issues: reason.`, {
      label: `clean-${file.split('/').pop()}`,
      phase: 'Clean',
      model: MID,
    }))
  )
}

// Phase 4: Verify
phase('Verify')
log('Running quality gates...')

const verification = await agent(`TASK: Run all quality gates after slop removal.

1. Run the project test suite - report pass/fail count
2. Run linter if configured - report errors (not warnings)
3. Run typecheck (tsc / pyright / etc) - report new errors on changed files
4. Critical review checklist:
   - No functional logic removed?
   - All error handling preserved?
   - Type hints intact?
   - Imports valid?
   - No breaking API changes?
   - Return values unchanged?

DELIVERABLE:
- Test suite: PASS/FAIL (N tests, M failed)
- Lint: PASS/FAIL
- Typecheck: PASS/FAIL
- Critical review: PASS/FAIL per item
- Overall: CLEAN or NEEDS-ATTENTION + what to fix`, {
  label: 'quality-gates',
  phase: 'Verify',
  model: MID,
})

log('Slop removal complete.')
