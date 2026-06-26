# Task Handoff Template
# Controller writes this to .dispatch/inbox/{role}.md

From: controller
To: {{ROLE}}
Time: {{TIMESTAMP}}
Type: task_handoff
Risk: low | medium | high

## Goal
{{ONE CONCRETE OBJECTIVE}}

## Scope
- Touch: {{WHAT TO MODIFY}}
- Do NOT touch: {{FORBIDDEN SCOPE}}

## Context
{{MINIMAL NECESSARY CONTEXT FROM CONTROLLER}}

## Worker Instructions
1. Read your existing context and project entry files.
2. Decide if this task belongs to your role.
3. If yes: execute, then write result to your outbox.
4. If no or conflicts: write REJECTED + reason to outbox.

## Acceptance Criteria
{{EXACT COMMAND + EXPECTED OUTPUT}}
