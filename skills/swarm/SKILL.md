---
name: swarm
description: "Multi-agent orchestration kit (qoder-swarm). Activates for any multi-agent or structured workflow: planning, review, parallel execution, debugging, research, project memory, AI slop cleanup, visual QA, persistent teams, self-loops. Triggers (EN + 中文): 'plan this', 'review work', 'review my work', 'start work', 'execute plan', 'debug this', 'why is X broken', 'deep research', 'ultraresearch', 'remove slop', 'clean AI code', 'init-deep', 'project memory', 'visual QA', 'screenshot diff', 'CJK wrapping', 'team mode', 'ulw-loop', 'keep going until done', '规划', '审查代码', '开始干活', '调试', '为什么报错', '深度研究', '清理AI代码', '项目记忆', '视觉验证', '截图对比', '团队模式', '一直跑到完成'. Routes to the matching reference doc and uses Agent tool parallel calls with model tiering for credit savings."
---

# swarm — Multi-Agent Orchestration Kit

One skill, ten orchestration patterns. Routes by user intent to the matching reference.

## When to activate (any of)

| Pattern | Trigger words (EN / 中文) |
|---------|-------------------------|
| `plan-and-review` | "plan this" / "ulw-plan" / "break down" / "规划" / "拆解" + multi-step/ambiguous |
| `five-agent-review` | "review work" / "QA my work" / "审查代码" / "代码审查" |
| `start-work` | "start work" / "execute plan" / "开始干活" / "执行计划" |
| `remove-ai-slops` | "remove slop" / "clean AI code" / "deslop" / "清理AI代码" |
| `init-deep` | "init-deep" / "project memory" / "AGENTS.md" / "项目记忆" |
| `ultraresearch` | "ultraresearch" / "deep research" / "深度研究" / "彻底研究" |
| `debugging` | "debug this" / "why is X broken" / "调试" / "为什么报错" |
| `visual-qa-strict` | "visual QA" / "screenshot diff" / "视觉验证" / "截图对比" / CJK issues |
| `teammode` | "team mode" / "make a team" / "团队模式" / "多人协作" |
| `ulw-loop` | "ulw-loop" / "keep going" / "一直跑到完成" |

## How to execute (universal flow)

1. **Detect pattern** from user message → pick ONE pattern name from the table above.
2. **Read** `references/{pattern}.md` from this skill directory using the Read tool.
3. **Follow the reference** — it specifies stages, parallel groups, model tiers, and exact Agent prompts.
4. **Universal rules** (apply to every pattern):
   - Use the `Agent` tool with `subagent_type: "general-purpose"`. Do NOT use the `Workflow` tool (feature-gated on some accounts).
   - Send all independent Agent calls **in a single message** to run them in parallel.
   - Each spawned agent's prompt must be self-contained: `TASK: ... DELIVERABLE: ... SCOPE: ... VERIFY: ...`
   - Apply model tiering (see below).
   - Save state to `.swarm/{pattern}/` when the reference says so.

## Model tiers (cost optimization)

Use these constants in every Agent call. Adjust if user's `/model` list differs.

| Tier | Default model | Credit | Use for |
|------|--------------|--------|---------|
| `CHEAP` | `Qwen3.7-Max-DogFooding` | 0.00x (FREE) | search, read-only exploration, parsing, monitoring |
| `MID` | `GLM-5.2` | 0.60x | code editing, QA execution, integration |
| `HEAVY` | `GLM-5.2` | 0.60x | deep reasoning, planning, adversarial review |

Pass model via `Agent` opts when the SDK supports it; otherwise mention the model in the prompt.

## Composability — skill calls skill

A pattern's reference may instruct you to invoke another pattern. Example:
- `start-work` reference says: "If no plan exists, first run `plan-and-review`."
- Treat this as: read `references/plan-and-review.md`, execute that flow, then continue.

Don't recurse beyond 2 levels (plan → execute → review is the deepest typical chain).

## Files

```
swarm/
├── SKILL.md                          ← this file (routing only)
└── references/
    ├── plan-and-review.md            ← 4-agent planning loop
    ├── five-agent-review.md          ← 5 parallel reviewers
    ├── start-work.md                 ← orchestrate workers in waves
    ├── remove-ai-slops.md            ← lock-then-clean cycle
    ├── init-deep.md                  ← dynamic explorer fleet
    ├── ultraresearch.md              ← swarm + recursive EXPAND
    ├── debugging.md                  ← 3+ hypothesis parallel investigation
    ├── visual-qa-strict.md           ← pixel diff + dual oracle
    ├── teammode.md                   ← persistent multi-session team
    ├── ulw-loop.md                   ← self-loop with evidence ledger
    └── _shared.md                    ← TASK template, error handling, retry rules
```

## Critical: when this skill activates

After deciding which pattern applies:
1. Tell the user briefly: `"Running swarm:<pattern> (using Agent parallel calls, ~Nx credit)"`.
2. Read the reference file.
3. Execute. Don't paraphrase the reference — follow it.

When in doubt between two patterns, pick the more specific one. When user says "just plan and execute and review", chain `plan-and-review` → `start-work` → `five-agent-review`.
