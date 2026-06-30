# five-agent-review

Five reviewers vote independently. 4/5 PASS or better → DONE; 3/5 → NEEDS-FIX; 2/5 or worse → REJECT. Cost ~2.40x. Full aggregation rules in the Verdict aggregation section below.

## Step 1 — Gather context (CHEAP × 1, or direct Bash)

```bash
git diff --name-only HEAD~1
git diff --stat HEAD~1
```

Read full content of each changed file (max 10). Bind as `{diff_and_files}`.

## Step 2 — Launch 5 reviewers IN PARALLEL

Emit FIVE Agent calls in ONE message:

```
Agent[swarm-reviewer] HEAVY:
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

Agent[swarm-worker] MID:
TASK: QA by ACTUALLY RUNNING the code
GOAL: {goal}
FILES: {changed_files}
PROCESS:
  1. Find test command (package.json / Makefile)
  2. Run tests, report pass/fail
  3. Run linter/typecheck
  4. Try 3+ edge cases
DELIVERABLE: <verdict>PASS|FAIL</verdict> <test_results> <blocking_issues>

Agent[swarm-reviewer] HEAVY:
TASK: Code quality (senior staff engineer standard)
CHANGES: {diff_and_files}
CHECK 10 dimensions: correctness, pattern consistency, naming, error handling, type safety, performance, abstraction, testing, API design, tech debt
SEVERITY: CRITICAL > MAJOR > MINOR > NITPICK
DELIVERABLE: <verdict>PASS|FAIL</verdict> <findings categorized> <blocking_issues>CRITICAL+MAJOR only</blocking_issues>

Agent[swarm-reviewer] MID:
TASK: Security only (ignore style)
CHANGES: {diff_and_files}
CHECK: input validation (SQL/XSS/cmd/SSRF), auth/authz, secrets, data exposure, deps with CVEs, path traversal
DELIVERABLE: <verdict>PASS|FAIL</verdict> <severity>CRITICAL|HIGH|MEDIUM|LOW|NONE</severity> <findings>

Agent[swarm-explorer] CHEAP:
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
## Overall Verdict: k-vote consensus — see Verdict aggregation section for outcome thresholds

| Area | Verdict |
| Goal | ... |
| QA | ... |
| Code Quality | ... |
| Security | ... |
| Context | ... |

## Blocking Issues (deduplicated, with file:line)
## Recommendations (prioritized fix order)
```

## Verdict aggregation

After all 5 reviewers return independently, aggregate verdicts:
(k-vote = each reviewer votes PASS/FAIL independently, then aggregate by the rules below)

- **5/5 PASS** → DONE (all clear, no action)
- **4/5 PASS** → DONE-WITH-NOTE (dissenter's concern documented, no blocker)
- **3/5 PASS** → NEEDS-FIX (majority found issues, fix and re-review)
- **2/5 PASS or fewer** → REJECT (back to plan-and-review)

Independent review requirement: reviewers MUST NOT see each other's verdicts before submitting their own. The parallel Agent call pattern in this skill already ensures isolation — do not let reviewers chat or read each other's output mid-review.

## Hard rules

- Don't summarize away any FAIL
- Be specific with locations (file:line)
- INCONCLUSIVE counts as FAIL (no silent passes)
