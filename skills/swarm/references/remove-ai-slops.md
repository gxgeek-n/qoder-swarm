# remove-ai-slops

Behavior-locked AI-code-smell cleanup.

## Hard safety invariant

**Behavior is locked by GREEN regression tests BEFORE any line is removed.** No tests = no cleanup.

## Step 1 — Scope

```bash
git diff $(git merge-base main HEAD)..HEAD --name-only
```

Filter: deleted/binary/generated (node_modules, dist, lockfiles).

## Step 2 — Lock behavior (MID × 1)

```
Agent[swarm-worker]:
TASK: Verify regression coverage. Write tests for UNCOVERED public behavior. Run suite to GREEN baseline.
FILES: {scope}
RULES:
  - Only write tests for UNCOVERED behavior
  - Pin current inputs/outputs, not implementation
  - Run test suite — must be GREEN before cleanup
DELIVERABLE: status per file [covered | new-test-added | uncoverable] + GREEN suite proof
```

If baseline can't go GREEN, STOP and report.

## Step 3 — Parallel cleanup, batches of 5 (MID × N)

For each batch of 5 files, emit 5 Agent calls in ONE message:

```
Agent[clean-{file}]:
TASK: Remove AI slops from {file_path}
CATEGORIES (apply safest → riskiest):
  1. Obvious comments restating code
  2. Over-defensive code (null check for guaranteed values, broad catch)
  3. Excessive complexity (nesting >3, god functions >50 lines)
  4. Needless abstraction (pass-through wrappers, single-use helpers)
  5. Dead code (unused imports, unreachable branches)
  6. Duplication (copy-paste with trivial differences)
  7. Performance equivalences (O(n²)→O(n), hoist invariants)
SCOPE: Only {file_path}. Behavior MUST be preserved (tests are GREEN).
  - No public API changes
  - No removed type hints
  - If equivalence not obvious, SKIP
DELIVERABLE: changes by category, before/after, why-slop, why-safe. Skipped: reason.
VERIFY: Re-run regression tests — still GREEN.
```

## Step 4 — Quality gates (MID × 1)

```
Agent[swarm-reviewer]:
TASK: Run all quality gates
PROCESS:
  1. Full test suite (pass/fail count)
  2. Linter (errors only, not warnings)
  3. Typecheck (tsc / pyright on changed files)
  4. Critical review:
     - No functional logic removed?
     - All error handling preserved?
     - Type hints intact?
     - Imports valid?
     - No breaking API?
DELIVERABLE: gate-by-gate status + overall CLEAN or NEEDS-ATTENTION
```

## Anti-patterns

- Skipping Step 2 (regression lock) = behavior bomb
- Bundling unrelated refactors with cleanup
- Algorithm changes disguised as "performance"
- Silent failed-gate skips
- Removing WHY comments (only remove WHAT-restating)
