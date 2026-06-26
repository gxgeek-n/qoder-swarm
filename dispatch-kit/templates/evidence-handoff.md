# Evidence Handoff Template
# Controller forwards evidence from one worker to another

From: controller
Source: {{SOURCE_WORKER_ROLE}}
To: {{TARGET_WORKER_ROLE}}
Time: {{TIMESTAMP}}
Type: evidence_handoff

## Evidence
- {{ARTIFACT_PATH / VERSION / CHECKSUM / TEST_RESULT}}

## Why This Matters
{{ONE SENTENCE}}

## Instructions
Use this evidence only if it belongs to your role.
If irrelevant or conflicts with current work, write REJECTED + reason to outbox.
