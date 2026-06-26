# Worker Result Template
# Worker writes this to .dispatch/outbox/{role}.md after completing a task

From: {{ROLE}}
Time: {{TIMESTAMP}}
Status: done | blocked | rejected
Task: {{ORIGINAL TASK GOAL}}

## Result
{{WHAT WAS DONE}}

## Changed Files
- {{FILE_1}}
- {{FILE_2}}

## Verification
Command: {{EXACT COMMAND RUN}}
Output: {{PASS/FAIL + KEY OUTPUT}}

## Evidence
Path: {{ARTIFACT PATH IF ANY}}

## Next
{{WHAT THE CONTROLLER SHOULD DO NEXT, OR "none"}}
