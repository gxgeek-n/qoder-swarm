# Worker Prompt Template

The orchestrator MUST use this template when dispatching swarm-worker. Instead of pasting boilerplate + reference code in every dispatch, the prompt references this template and passes only the minimal delta.

## Standard prompt shape (target <=2000 chars)

```
TASK: <T-id> — <one line goal>

CWD: /Users/gx/qoder-swarm (or override)

FILES to modify:
- path/to/file1
- path/to/file2 (new)

REFERENCE (do not paste full content — worker Reads these):
- /tmp/research-origins/oh-my-openagent/packages/.../<source-file>.ts:<line-range>
- skills/swarm/prompts/<pattern>.md
- (or: "no external reference, task fully self-contained")

WHAT TO DO (3-5 bullets, no code blocks unless the code is <20 lines):
1. ...
2. ...
3. ...

ACCEPTANCE (verify recipe or shell one-liner):
- recipe: <name>   # from worker-verify-recipes.md
- OR inline: `cd /path && grep -c pattern file | test <target>`

DELIVERABLE (200-token max):
STATUS: DONE | FAIL
file(s): <paths>
verification: <one-line evidence>
next: none | <one-line hint>

SCOPE: touch only files listed; no commit.
```

## What NOT to paste in the prompt

**Don't paste**:
- Full source code of a script the worker is porting (worker uses Read tool)
- Long acceptance test scripts (use verify recipes)
- 5-line explanations of why we're doing this (worker reads plan.md)
- Multiple example outputs (worker infers)

**Do paste**:
- Concrete file paths (absolute or relative-to-cwd)
- Exact function/section names to modify
- 1-2 line examples if genuinely ambiguous
- Line ranges to Read from source

## Verify recipes (referenced by name)

See `references/worker-verify-recipes.md` for named recipes. Worker prompt says
`ACCEPTANCE: recipe smoke-then-count` and the recipe expands to a full command
locally.

## Example: BEFORE (bad, 8000+ chars)

```
TASK: T2 — Port ConcurrencyManager as scripts/swarm-concurrency.sh
[... 60 lines of source code heredoc ...]
[... 40 lines of verify test heredoc ...]
[... 30 lines of acceptance criteria heredoc ...]
```

## Example: AFTER (good, ~1200 chars)

```
TASK: T2 — Port OmO ConcurrencyManager as scripts/swarm-concurrency.sh
CWD: /Users/gx/qoder-swarm
REFERENCE:
- /tmp/research-origins/oh-my-openagent/packages/omo-opencode/src/features/background-agent/concurrency.ts:1-200

WHAT TO DO:
1. Read the reference. Port to bash + jq.
2. Commands: status, acquire, release, config, reset.
3. State: .swarm/concurrency/slots.json with {model: {count, limit, queue}}
4. mkdir-lock for concurrent safety (see task-dag.sh for pattern).
5. Add usage to references/start-work.md.

ACCEPTANCE:
- recipe: syntax-check + race-safe (5 concurrent acquires → count+queue=5)
- doc: grep -c "swarm-concurrency" references/start-work.md >= 2

DELIVERABLE: standard (see worker-template.md)
SCOPE: 1 new script + 1 doc mod, no commit.
```

Savings: 8000+ → 1200 chars = 85% shorter → ~1500 tokens saved per dispatch × 11 worker dispatches typical session = ~16K tokens = ~10 credit saved per full self-bootstrap.
