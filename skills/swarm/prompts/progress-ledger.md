# Progress Ledger Prompt (Magentic)

**Source**: `semantic-kernel/python/semantic_kernel/agents/orchestration/prompts/_magentic_prompts.py:63-111`
**Used by**: `references/magentic-loop.md` — orchestrator's per-round LLM call.
**License**: MIT (Microsoft)

## Variables (placeholders)
- `{task}`: current user request
- `{team_descriptions}`: bullet list of sub-agents available
- `{participant_names}`: comma-separated names eligible as next_speaker

## Output destination
Orchestrator parses returned JSON, appends to `.swarm/magentic/{session}/ledger.jsonl`.

## Prompt

```
Recall we are working on the following request:

{task}

And we have assembled the following team:

{team_descriptions}

To make progress on the request, please answer the following questions, including necessary reasoning:

  - Is the request fully satisfied? (True if complete, or False if the original request has yet to be SUCCESSFULLY and FULLY addressed)
  - Are we in a loop where we are repeating the same requests and / or getting the same responses as before? Loops can span multiple turns, and can include repeated actions like scrolling up or down more than a handful of times.
  - Are we making forward progress? (True if just starting, or recent messages are adding value. False if recent messages show evidence of being stuck in a loop or if there is evidence of significant barriers to success such as the inability to read from a required file)
  - Who should speak next? (select from: {participant_names})
  - What instruction or question would you give this team member? (Phrase as if speaking directly to them, and include any specific information they may need)

Please output an answer in pure JSON format according to the following schema. The JSON object must be parsable as-is.
DO NOT OUTPUT ANYTHING OTHER THAN JSON, AND DO NOT DEVIATE FROM THIS SCHEMA:

{
    "is_request_satisfied": {
        "reason": string,
        "answer": boolean
    },
    "is_in_loop": {
        "reason": string,
        "answer": boolean
    },
    "is_progress_being_made": {
        "reason": string,
        "answer": boolean
    },
    "next_speaker": {
        "reason": string,
        "answer": string (select from: {participant_names})
    },
    "instruction_or_question": {
        "reason": string,
        "answer": string
    }
}
```

## Loop detection examples (concrete, qoder-swarm specific)

- reviewer 连续 2 轮提同一个 blocker → `is_in_loop.answer = true`
- planner 修改 plan 但 reviewer 继续否决，且否决理由相同 → `is_in_loop.answer = true`
- worker 报告同一个 verification command 失败超过 2 次 → `is_in_loop.answer = true`
- 所有 sub-agent 在等彼此（无新 tool call）→ `is_progress_being_made.answer = false`

## Schema validation hard rules
- Orchestrator MUST parse output as JSON
- 5 keys required, each with `reason` (string) + `answer` field
- `next_speaker.answer` MUST be one of `{participant_names}` — else retry once
- If parse fails 3 times → fallback to round-robin (log warning to `.swarm/magentic/{session}/parse-failures.log`)
