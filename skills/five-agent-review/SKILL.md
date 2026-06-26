---
name: five-agent-review
description: "Post-implementation 5-agent parallel code review. Use when the user says 'review work', 'review my work', 'review changes', 'QA my work', 'check my work', 'validate changes', '审查代码', '代码审查', '审查一下', or after completing significant implementation. Five parallel reviewers cover: goal verification, hands-on QA execution, code quality, security audit, and context mining. All must PASS for overall PASS."
---

# five-agent-review

Five specialized review agents run in parallel after implementation work. All must pass.

## When to activate

User mentions any of:
- "review work" / "review my work" / "review changes"
- "QA my work" / "check my work" / "validate changes"
- "审查代码" / "代码审查" / "帮我审查" / "审查一下"
- Or just finished implementing something and wants final gate

## How to execute

**Do NOT use the Workflow tool**. Use `Agent` tool with parallel invocations.

### Step 1 — Gather context

Use Bash to collect:
```
git diff --name-only HEAD~1
git diff --stat HEAD~1
```

Read full content of each changed file (max 10).

### Step 2 — Launch 5 reviewers IN PARALLEL

Emit 5 `Agent` tool calls in ONE message:

**Agent 1: Goal & Constraint Verification** (HEAVY model)
```
prompt: "REVIEW: GOAL & CONSTRAINTS
ORIGINAL GOAL: {goal}
CONSTRAINTS: {constraints}
CHANGES: {diff_and_files}
CHECK:
1. Goal completeness - sub-requirements ACHIEVED/MISSED/PARTIAL
2. Constraint compliance with code evidence
3. Requirement gaps (implied but unstated)
4. Over-engineering (added without request)
5. Edge cases (trace 5+ scenarios)
OUTPUT: <verdict>PASS|FAIL</verdict> <summary> <blocking_issues>"
```

**Agent 2: QA Execution** (MID model)
```
prompt: "REVIEW: QA BY ACTUALLY RUNNING
GOAL: {goal}
FILES: {changed_files}
PROCESS:
1. Find test command (package.json/Makefile)
2. Run tests, report pass/fail
3. Run linter/typecheck
4. Try 3+ edge cases
OUTPUT: <verdict>PASS|FAIL</verdict> <test_results> <blocking_issues>"
```

**Agent 3: Code Quality** (HEAVY model)
```
prompt: "REVIEW: CODE QUALITY (senior staff engineer standard)
CHANGES: {diff_and_files}
CHECK 10 DIMENSIONS:
1. Correctness (logic, races, leaks)
2. Pattern consistency with codebase
3. Naming & readability
4. Error handling
5. Type safety
6. Performance
7. Abstraction level
8. Testing
9. API design
10. Tech debt
SEVERITY: CRITICAL > MAJOR > MINOR > NITPICK
OUTPUT: <verdict>PASS|FAIL</verdict> <findings categorized> <blocking_issues>CRITICAL+MAJOR only</blocking_issues>"
```

**Agent 4: Security** (MID model)
```
prompt: "REVIEW: SECURITY ONLY
CHANGES: {diff_and_files}
CHECK:
1. Input validation (SQL/XSS/cmd injection/SSRF)
2. Auth/AuthZ
3. Secrets in code or logs
4. Data exposure (PII, over-exposed APIs)
5. Dependencies (CVEs)
6. Path traversal
OUTPUT: <verdict>PASS|FAIL</verdict> <severity>CRITICAL|HIGH|MEDIUM|LOW|NONE</severity> <findings>"
```

**Agent 5: Context Mining** (CHEAP model)
```
prompt: "REVIEW: MISSED CONTEXT
GOAL: {goal}
CHANGED FILES: {files}
SEARCH:
1. git log --oneline -20 -- <each file>
2. git blame on critical sections
3. grep TODO/FIXME/HACK in changes
4. Find files importing changed modules
5. Check docs/README needs updates
OUTPUT: <verdict>PASS|FAIL</verdict> <discovered_context> <blocking_issues>"
```

### Step 3 — Synthesize verdict

After all 5 return, present a final report:

```
# Review Report
## Overall Verdict: PASSED / FAILED  (ALL 5 must PASS)

| Area | Verdict |
| Goal | ... |
| QA | ... |
| Code Quality | ... |
| Security | ... |
| Context | ... |

## Blocking Issues (deduplicated)
## Recommendations (prioritized)
```

## Model tiers

| Reviewer | Model |
|----------|-------|
| Goal, Code Quality | `GLM-5.2` (HEAVY) |
| QA, Security | `GLM-5.2` (MID) |
| Context Mining | `Qwen3.7-Max-DogFooding` (CHEAP/FREE) |

## Critical rules

- ALL 5 must PASS for overall PASS
- ANY single FAIL = overall FAIL
- Don't summarize away blocking issues
- Be specific with locations (file:line)
