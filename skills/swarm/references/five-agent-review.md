# five-agent-review

5 parallel reviewers. ALL must PASS for overall PASS. Cost ~2.40x.

## Step 1 — Gather context (CHEAP × 1, or direct Bash)

```bash
git diff --name-only HEAD~1
git diff --stat HEAD~1
```

Read full content of each changed file (max 10). Bind as `{diff_and_files}`.

## Step 2 — Launch 5 reviewers IN PARALLEL

Emit FIVE Agent calls in ONE message:

```
Agent[goal-verifier] HEAVY:
TASK: Verify implementation against goal & constraints
GOAL: {goal}
CONSTRAINTS: {constraints}
CHANGES: {diff_and_files}
CHECK:
  1. Goal completeness — sub-requirements ACHIEVED/MISSED/PARTIAL
  2. Constraint compliance with code evidence
  3. Requirement gaps (implied but unstated)
  4. Over-engineering
  5. Edge cases (trace 5+ scenarios)
DELIVERABLE: <verdict>PASS|FAIL</verdict> <summary> <blocking_issues>

Agent[qa-executor] MID:
TASK: QA by ACTUALLY RUNNING the code
GOAL: {goal}
FILES: {changed_files}
PROCESS:
  1. Find test command (package.json / Makefile)
  2. Run tests, report pass/fail
  3. Run linter/typecheck
  4. Try 3+ edge cases
DELIVERABLE: <verdict>PASS|FAIL</verdict> <test_results> <blocking_issues>

Agent[code-reviewer] HEAVY:
TASK: Code quality (senior staff engineer standard)
CHANGES: {diff_and_files}
CHECK 10 dimensions: correctness, pattern consistency, naming, error handling, type safety, performance, abstraction, testing, API design, tech debt
SEVERITY: CRITICAL > MAJOR > MINOR > NITPICK
DELIVERABLE: <verdict>PASS|FAIL</verdict> <findings categorized> <blocking_issues>CRITICAL+MAJOR only</blocking_issues>

Agent[security-auditor] MID:
TASK: Security only (ignore style)
CHANGES: {diff_and_files}
CHECK: input validation (SQL/XSS/cmd/SSRF), auth/authz, secrets, data exposure, deps with CVEs, path traversal
DELIVERABLE: <verdict>PASS|FAIL</verdict> <severity>CRITICAL|HIGH|MEDIUM|LOW|NONE</severity> <findings>

Agent[context-miner] CHEAP:
TASK: Find missed context
GOAL: {goal}
CHANGED FILES: {changed_files}
SEARCH:
  1. git log --oneline -20 -- <each file>
  2. git blame on critical sections
  3. grep TODO/FIXME/HACK in changes
  4. files importing changed modules
  5. docs/README needing updates
DELIVERABLE: <verdict>PASS|FAIL</verdict> <discovered_context> <blocking_issues>
```

## Step 3 — Synthesize verdict

```
# Review Report
## Overall Verdict: PASSED / FAILED  (ALL 5 must PASS)

| Area | Verdict |
| Goal | ... |
| QA | ... |
| Code Quality | ... |
| Security | ... |
| Context | ... |

## Blocking Issues (deduplicated, with file:line)
## Recommendations (prioritized fix order)
```

## Hard rules

- Don't summarize away any FAIL
- Be specific with locations (file:line)
- INCONCLUSIVE counts as FAIL (no silent passes)
