---
name: remove-ai-slops
description: "Clean AI-generated code smells from branch changes. Use when user says 'remove slop', 'clean AI code', 'deslop', 'cleanup AI generated', '清理AI代码', '去掉AI味道', '清理代码'. Locks behavior with regression tests FIRST, then parallel cleanup in batches of 5, then verifies with quality gates. Covers 10 slop categories: obvious comments, over-defensive code, excessive complexity, needless abstraction, boundary violations, dead code, duplication, performance equivalences, missing tests, oversized modules."
---

# remove-ai-slops

Behavior-preserving cleanup of AI-generated code patterns.

## When to activate

User mentions: "remove slop" / "clean AI code" / "deslop" / "清理AI代码" / "去掉AI味道"

## Hard safety invariant

**Behavior is locked by GREEN regression tests BEFORE a single line is removed.** No tests = no cleanup.

## How to execute

### Step 1 — Determine scope

```
git diff $(git merge-base main HEAD)..HEAD --name-only
```

Filter: deleted/binary/generated files (node_modules, dist, lockfiles).

### Step 2 — Lock behavior with regression tests

ONE `Agent` call:
```
prompt: "For each file, check existing test coverage. Write MINIMAL regression tests only for UNCOVERED public behavior. Pin current behavior (inputs/outputs), not implementation. Run test suite - must be GREEN before cleanup."
```

If baseline can't go green, STOP. Report.

### Step 3 — Parallel cleanup in batches of 5

For each batch of 5 files, emit 5 `Agent` calls in ONE message:

```
For each file in batch:
  Agent({
    subagent_type: "general-purpose",
    description: "Clean: {filename}",
    prompt: "Remove AI slops from: {file_path}

CATEGORIES (apply in order safest→riskiest):
1. Obvious comments restating code
2. Over-defensive code (null checks for guaranteed values, broad catch)
3. Excessive complexity (nesting >3, god functions >50 lines)
4. Needless abstraction (pass-through wrappers, single-use helpers)
5. Dead code (unused imports, unreachable branches)
6. Duplication (copy-paste with trivial differences)
7. Performance equivalences (O(n²)→O(n), hoist invariants)

HARD CONSTRAINTS:
- Behavior MUST be preserved (regression tests green)
- Do NOT change public API signatures
- Do NOT remove type hints
- If equivalence not obvious, SKIP

DELIVERABLE: changes by category, before/after, why-slop, why-safe
Skipped issues: reason"
  })
```

### Step 4 — Quality gates

ONE `Agent` call:
```
prompt: "Run all quality gates:
1. Test suite (pass/fail count)
2. Linter
3. Typecheck (tsc/pyright/etc on changed files)
4. Critical review checklist:
   - No functional logic removed?
   - All error handling preserved?
   - Type hints intact?
   - Imports valid?
   - No breaking API changes?
Overall: CLEAN or NEEDS-ATTENTION + what to fix"
```

## Model tiers

| Role | Model |
|------|-------|
| Scope finder | `Qwen3.7-Max-DogFooding` (FREE) |
| Cleanup workers | `GLM-5.2` (MID) |
| Quality gates | `GLM-5.2` (MID) |

## Anti-patterns

- Skipping Phase 2 (regression tests) — behavior change time bomb
- Bundling unrelated refactors with slop removal
- Algorithm changes disguised as "performance optimization"
- Silent skips of failing gates
- Removing WHY comments (only remove WHAT-restating comments)
- Touching files outside scope
