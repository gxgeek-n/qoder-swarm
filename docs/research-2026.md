# 4 个参考项目对比 + qoder-swarm 定位

研究时间：2026-06-26
研究方法：clone 全部源码到 /tmp/research/，扫文件结构、读核心 skill prompt、分析架构文档。

---

## 速览表

| 项目 | 规模 | 哲学 | 与 qoder-swarm 关系 |
|------|------|------|---------------------|
| **wshobson/agents** | 13MB, 1074 文件, 85 plugins, 194 agents | **Marketplace + 多 harness 自动转译** | 上层产品形态 |
| **obra/superpowers** | 2.4MB, 173 文件, 14 skill | **强制 TDD/review 流水线 + 跨平台原生 plugin** | 同行者，方法论更硬核 |
| **VoltAgent/awesome-claude-code-subagents** | 2.0MB, 189 文件, 100+ subagent | **职责分类的 subagent 目录** | 素材库 |
| **am-will/swarms** | 232KB, 13 文件, 2 核心 skill | **Wave-based 并行调度，极简** | 同思路、更早期版本 |

---

## 1️⃣ wshobson/agents — Plugin Marketplace

### 规模
- 85 plugins，194 agents，158 skills，106 commands
- 跨 5 个 harness 自动生成（Codex / Cursor / OpenCode / Gemini / Copilot / 已支持 Claude）
- 13 MB / 1074 个文件 / 386 个 pytest

### 核心设计（来自 ARCHITECTURE.md）
**单一事实源 → 自动转译为 N 个 harness**

```
plugins/<name>/                ← 唯一作者层
├── agents/*.md
├── commands/*.md
└── skills/<n>/{SKILL.md, references/, assets/}

tools/adapters/                ← 自动转译层
├── base.py
├── codex.py   → .codex/skills/*.toml + 8KB body cap
├── cursor.py  → .cursor-plugin/ + .cursor/rules/*.mdc
├── opencode.py → .opencode/agents/  (tools→permission block)
├── gemini.py  → skills/ at extension root
└── copilot.py → .copilot/agents/ + model alias mapping
```

### 5 个 invariants（直接复用）
1. **Single source of truth** — 生成物 gitignored
2. **One canonical context file** — `AGENTS.md` 是真相，其他都是 symlink
3. **Adapters own per-harness mechanics** — 作者写"Claude-Code 质量的 markdown"，adapter 处理格式差异
4. **Mechanical enforcement with remediation hints** — 每个 lint 输出"how to fix"
5. **Progressive disclosure** — context 文件 ≤150 行，skill body ≤8KB，detail 放 `references/`

### 三道质检 gate（make targets）
- `make validate` — 结构校验（错误阻塞 CI）
- `make garden` — drift detection（死链、孤儿 marketplace、过大 skill）
- `make test` — 386 个 pytest

### 我们能学的
- ✅ **多 harness 转译模式** — 解锁让 qoder-swarm 也能跑在 Claude Code / Cursor
- ✅ **doc_gardener** — 自动检测 skill 漂移（文档说有但实际无、过期链接）
- ✅ **Makefile 入口** — `make help` 一目了然
- ❌ 不学：85 plugins 规模（我们 1 个就够，别扩散）

---

## 2️⃣ obra/superpowers — 强制流水线 + 多 harness

### 14 个 skill 列表
```
brainstorming                       # Socratic 需求澄清
dispatching-parallel-agents         # 并行 dispatch ← 跟我们 plan-and-review 重合
executing-plans                     # 跨 session 执行 plan
finishing-a-development-branch      # 完成分支（push, MR）
receiving-code-review               # 收到 review 的处理流程
requesting-code-review              # 主动请 review
subagent-driven-development         # 每 task 一个 fresh subagent ← 核心
systematic-debugging                # 根因→测试→修复
test-driven-development             # 强制 RED-GREEN-REFACTOR
using-git-worktrees                 # worktree 隔离
using-superpowers                   # meta: 如何用这个框架
verification-before-completion      # 完成前强制验证
writing-plans                       # 写 plan 的方法论
writing-skills                      # meta: 怎么写 skill
```

### 多 harness 支持
```
.claude-plugin/
.codex-plugin/      ← 多个目录并存
.cursor-plugin/
.kimi-plugin/       ← 包含 Kimi！
.opencode/
.pi/                ← 未知，可能新 harness
```

每个 harness 一个独立目录，**手动维护**（不是自动转译，跟 wshobson/agents 不同方向）。

### 核心机制：`subagent-driven-development`
强制流程（来自 SKILL.md）：

```
1. 读 plan + 创建 todos
2. 每个 task:
   a. 派 implementer subagent（用 implementer-prompt.md）
   b. 写 diff → 派 task reviewer subagent（spec 合规 + 代码质量）
   c. 如有 Critical/Important → 派 fix subagent → 重审
   d. 标记 done
3. 全部 task 完成后 → 派最终 code reviewer
4. 调用 finishing-a-development-branch
```

**两个关键约束**：
- "Fresh subagent per task" — 不让 subagent 继承 session 历史
- "Continuous execution" — task 之间**不停下来问人**，全部跑完为止

### 我们能学的
- ✅ **subagent-driven-development 流水线**（implementer → task reviewer → fix subagent → final reviewer）— 我们的 start-work 只到"派 worker"，缺中间 review-fix 循环
- ✅ **graphviz `digraph` 决策图** — SKILL.md 里直接画 DOT 图说明"什么时候用"，可读性高于纯文字
- ✅ **Continuous execution** — 我们的 ulw-loop 应该明确写"don't pause for confirmation between tasks"
- ❌ 不学：14 个 skill 平铺（我们用 1 router + references 已经更紧凑）

---

## 3️⃣ VoltAgent/awesome-claude-code-subagents — 素材库

### 10 个分类
```
01-core-development      # 通用开发
02-language-specialists  # 语言专家
03-infrastructure        # IaC/DevOps
04-quality-security      # 质量+安全
05-data-ai               # 数据/AI
06-developer-experience  # DX 工具
07-specialized-domains   # 垂直
08-business-product      # 业务/产品
09-meta-orchestration    # 编排元 ← 跟我们 swarm 同位
10-research-analysis     # 研究
```

### 09-meta-orchestration 里的 11 个 subagent
```
agent-installer.md
agent-organizer.md
codebase-orchestrator.md
context-manager.md           ← 上下文剪枝（值得偷）
error-coordinator.md         ← 错误恢复路由
it-ops-orchestrator.md
knowledge-synthesizer.md
multi-agent-coordinator.md
performance-monitor.md
（README + 1 个 installer）
```

每个都是 1 个 `.md` 文件 + frontmatter，跟我们 `agents/swarm-*.md` 格式完全一样。

### 我们能学的
- ✅ **`context-manager` subagent** — 专职上下文剪枝，避免长 session 爆炸
- ✅ **`error-coordinator` subagent** — 专职错误恢复路由（之前 swarm 没这个角色）
- ✅ **10 类 taxonomy** — 给 qoder-swarm 加一个 `agents/` 目录的"想扩 N 个 swarm-X 怎么命名"分类
- ❌ 不学：100+ subagent 平铺，对我们太重

---

## 4️⃣ am-will/swarms — Wave-based 并行（最像我们）

### 规模
**只有 232 KB，13 个文件**。极简。

### 2 个核心 skill
```
swarm-planner/                 # 写带 depends_on 字段的 plan
parallel-task/                 # 按依赖图 wave 派发并行 subagent

variant:
  parallel-task-spark/         # 集成 Spark
  parallel-task-tmux/          # tmux 多窗口
  super-swarm/
  super-swarm-spark/
  co-design/
```

### 核心机制：**显式 `depends_on`**
plan 格式（来自 swarm-planner/SKILL.md）：
```markdown
### T1: Initialize project
- **depends_on**: []
- **location**: src/index.ts
- **acceptance**: project compiles

### T2: Add auth module
- **depends_on**: [T1]
- **location**: src/auth/
- **acceptance**: tests pass
```

`parallel-task` 解析 `depends_on`，自动计算 wave：所有依赖已完成 = 同 wave 并行。

### parallel-task 派 subagent 的 prompt template（直接借用）
```
You are implementing a specific task from a development plan.

## Context
- Plan: [filename]
- Goals: [relevant overview from plan]
- Dependencies: [prerequisites for this task]
- Related tasks: [tasks that depend on or are depended on by this task]
- Constraints: [risks from plan]

## Your Task
**Task [ID]: [Name]**

Location: [File paths]
Description: [Full description]
Acceptance Criteria: [...]
Validation: [...]
```

### 我们能学的
- ✅ **`depends_on` 字段强约束** — 现在 swarm:start-work 写了 wave 但 task 没 depends_on，靠 orchestrator 估
- ✅ **`/parallel-task <plan>` 一句话触发** — 比我们当前的"让 LLM 自己决定怎么派"更确定
- ✅ **task prompt template** 直接抄一份到 swarm-worker reference
- ✅ **parallel-task-tmux 变种** — 多 tmux 窗口跑（我们 dispatch-kit 是文件协议，tmux 是另一种）

---

## qoder-swarm 在坐标系里的位置

```
                      项目规模
                       │
                       │
  wshobson/agents ─────┼──── 大（marketplace 形态）
       (37k★)          │
                       │
  obra/superpowers ────┼──── 中（一套方法论）
       (~3-5k★)        │
                       │
  qoder-swarm ─────────┼──── 中-小（1 skill + 5 subagent + 10 ref）
       (本项目)        │
                       │
  am-will/swarms ──────┼──── 小（2 个核心 skill）
       (~200★)         │
                       │
                       └──── 小
       质量 ←──────────┼──────────→ 重型方法论
       工具/marketplace               强制流水线
       原生集成                       TDD/review 强约束
```

### qoder-swarm 的差异化优势
| 维度 | 别人 | qoder-swarm |
|------|------|------------|
| 平台 | Claude Code 为主 | **Qoder CLI 原生**（集团内独此一份） |
| 模型 | Anthropic only | **Qwen/GLM/DeepSeek 混搭省 credit** |
| CI | GitHub Actions | **Aone CI 已通** |
| 内网集成 | 无 | **mcp__code__ / mcp__yuque__ 等内部 MCP 友好** |
| 学习成本 | 14-194 个 skill 平铺 | 1 个 swarm skill router |
| 测试 | 部分有 pytest | **smoke-test 37 项 + 真实 CI** |

### qoder-swarm 缺的
1. **多 harness 转译** — 别人能跑 Claude/Cursor/Gemini，我们只能 Qoder
2. **`depends_on` 强约束** — start-work 是 wave 但没机器可读字段
3. **fresh subagent per task** — superpowers 那个 implementer → reviewer → fix subagent 循环我们没有
4. **context-manager / error-coordinator** — 这两个职责我们没拆出来
5. **Makefile 入口** — `make help` 直接列所有命令

---

## 借鉴优先级 (基于真实代码考察)

### P0 — 直接拿来用（< 半天）

1. **从 `am-will/swarms` 偷 `depends_on` schema** — start-work reference 加 task 必须写 `depends_on: [...]`
2. **从 `obra/superpowers` 偷 graphviz `digraph` 决策图** — 给 swarm SKILL.md 加 1 个"什么时候用哪个 pattern"的 DOT 图
3. **从 `wshobson/agents` 偷 ARCHITECTURE.md 5 invariants** — 给 qoder-swarm 加一个 `ARCHITECTURE.md` 文档化我们的不变式
4. **从 `voltagent` 偷 `context-manager` + `error-coordinator`** — 加 2 个 swarm-* agent

### P1 — 投入产出比高（1-2 天）

5. **从 `wshobson/agents` 偷 `tools/adapters/` 框架** — 让 qoder-swarm 也能装到 Claude Code（adapter 模式）
6. **从 `obra/superpowers` 偷 subagent-driven-development 流水线** — 给 start-work reference 加 implementer→reviewer→fix 循环
7. **从 `am-will/swarms` 偷 parallel-task tmux 变种** — 给 dispatch-kit 加 tmux 多窗口模式

### P2 — 长期价值（半周以上）

8. **doc_gardener** — 检测 skill 漂移
9. **Makefile + make help** — 让 `make help` 列出所有命令
10. **plugin marketplace JSON** — 写一个 marketplace.json 让别人能 `/plugin marketplace add` 装我们

---

## 本地参考路径

```
/tmp/research/
├── superpowers/        ← 强制流水线方法论
├── swarms-amwill/      ← 极简 wave 调度
├── agents/             ← 工业级 marketplace
└── voltagent-subagents/ ← subagent 素材库
```

每次写新功能前，可以 `grep -r "概念" /tmp/research/` 看别人怎么处理。
