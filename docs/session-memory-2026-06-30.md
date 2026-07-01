# Session Memory — 2026-06-30

> 这份记忆给压缩后或新 session 接手用。读完这一份就能继续干活。

## 项目是什么

`qoder-swarm` — Qoder CLI 的多 agent 编排套件，从 LazyCodex/OmO + ThreadDeck 移植。Repo: `git@github.com/gxgeek/qoder-swarm.git`

核心是 **1 个 swarm skill + 7 个 swarm-* subagent + 10 个 reference pattern**。

## 当前架构（已稳定）

```
qoder-swarm/
├── ARCHITECTURE.md        ← 5 条不变式 I1-I5
├── Makefile               ← make help/install/test/doctor/status/lint/clean
├── README.md              ← 含 Testing / Security Notes / Customizing 章节
├── LICENSE                ← MIT
├── package.json           ← repository: github.com/gxgeek/qoder-swarm
├── .aoneci/smoke.yaml     ← Aone CI 每 push 跑 smoke (alios-8u + pip Pillow + tests/smoke-test.sh)
├── .claude-plugin/README.md  ← 指向 .qoder-plugin
├── .qoder-plugin/plugin.json
├── agents/                ← 7 个 swarm-* subagent
├── skills/swarm/          ← 1 router SKILL.md + 11 references
├── hooks/                 ← swarm-comment-checker.sh + swarm-stop-continuation.sh
├── scripts/image-diff.py  ← numpy 像素 diff
├── dispatch-kit/          ← 多 session 文件协议 + tmux-launch.sh
├── workflows/*.mjs        ← 10 个可选 .mjs 引擎实现
├── tests/smoke-test.sh    ← 43 项断言 ~5 秒
└── docs/research-2026.md  ← 4 个参考项目分析
```

## 7 个 swarm-* subagent 当前配置

| Agent | Model | Effort | Temp | 角色 |
|-------|-------|--------|------|------|
| swarm-explorer | **Qwen3.7-Max-DogFooding** (0.00x 免费) | low | 0 | 代码搜索 |
| swarm-librarian | **Qwen3.7-Max-DogFooding** (0.00x 免费) | low | — | 外部文档/OSS |
| swarm-context-manager | DeepSeek-V4-Flash (0.10x) | low | — | 长 session 上下文压缩 |
| swarm-error-coordinator | DeepSeek-V4-Flash (0.10x) | medium | — | 多 worker 失败时的恢复路由 |
| **swarm-planner** | **Ultimate** (1.0x) | high | 0.2 | 规划（杠杆点不打折） |
| **swarm-reviewer** | **Ultimate** (1.0x) | high | 0 | 审查（最后一道门） |
| swarm-worker | GLM-5.2 (0.60x) | medium | — | 实现（worktree 隔离） |

**说明**：maxTurns 全部已删（用 Qoder 默认 200）。worker 保留 `timeoutMins: 20` + `isolation: worktree`。所有 agent `tools: ["*"]` + `disallowedTools: [...]` 黑名单。

## 10 个 reference pattern（在 skills/swarm/references/）

```
_shared.md, plan-and-review.md, five-agent-review.md, start-work.md,
remove-ai-slops.md, init-deep.md, ultraresearch.md, debugging.md,
visual-qa-strict.md, teammode.md, ulw-loop.md
```

## 重要历史决策

1. **不强制流水线** — 用户明确否决了 superpowers 风格的 mandatory TDD/review 强制流水线
2. **模型分级关键决策** — planner/reviewer 用 ultimate（杠杆点），explorer/librarian 用免费 Qwen，worker 用 GLM-5.2
3. **删了 maxTurns** — 之前抄 LazyCodex 限制太死（4-15），Qoder 内置默认 200，删后撞 MAX_TURNS 问题消失
4. **没做多 harness adapter** — Qoder 内部用就够，不扩散到 Claude/Cursor
5. **保持 1 skill router + N references** — 反 superpowers/voltagent 的 100+ flat skill 扩散
6. **抄了 Qoder 内置 Explore 的 prompt 模式** — temperature: 0, 速度指令, 逐工具使用指南, Bash NEVER 列表, "concise report for caller"

## 当前最棘手的问题：触发率

ai-prd session 扫了 277 prompts，**31 个该触发 swarm 没触发**：
- 12 个多 agent 信号
- 6 个 review / 对抗审查
- 12 个 debug / 排查
- 1 个端到端

**根因**：原 description 漏了用户真实说的短语。已加入：
```
对抗审查下 / 你确定可行 / 代码review了么 / 仔细排查 / 顶层设计
端到端模拟测试 / parallel tool_use / 并发 tool_use
```
还加了规则 (f)：任何「你确定？」「严格 review 下」语气 → swarm:five-agent-review。

## Aone CI 状态

- 仓库: https://github.com/gxgeek/qoder-swarm
- Pipeline: `.aoneci/smoke.yaml`，每 push 跑 ~20s
- 默认 GREEN，已验证 RED→GREEN 失败模式
- 用 alios-8u image + mirrors.aliyun.com/pypi (装 pyyaml + Pillow)

## settings.json 当前重要配置

```json
{
  "agents": {
    "overrides": {
      "Plan": { "modelConfig": { "model": "performance" }, "enabled": true },
      "general-purpose": { "modelConfig": { "model": "gm51model" } }
    }
  },
  "hooks": {
    "PostToolUse": [..., { "matcher": "Edit|Write|NotebookEdit",
                            "command": "~/.qoder/hooks/swarm-comment-checker.sh" }],
    "Stop":        [..., { "command": "~/.qoder/hooks/swarm-stop-continuation.sh" }]
  }
}
```

## 安装 / 验证 / 维护命令

```bash
# 安装到 ~/.qoder
cd /Users/gx/qoder-swarm && bash install.sh

# 体检
bash install.sh --doctor       # python3 / Pillow / git / qodercli

# 跑 smoke test
make test                       # 43 项 ~5 秒

# 看安装状态
make status                     # 列出实际安装的文件

# 模型分级调整：直接改 agents/swarm-*.md 的 model: 字段

# 同步到 ~/.qoder/agents/ 立即生效
cp agents/swarm-*.md ~/.qoder/agents/

# 当前 session reload (热加载 agent 定义)
# 在 Qoder 输入框打: /agents reload

# 推送
git push origin main           # 触发 Aone CI
```

## Git 提交规律

- 不加 `Co-Authored-By` 行
- 不用 `git add -A`（按文件名 stage）
- 使用 `-c commit.gpgsign=false`（项目里有 git hook）
- Commit message 中文/英文都 OK，按 Conventional Commits 前缀

## 最近 commit 历史

```
5ea6336 fix(skill): add 8 real user phrases mined from ai-prd session
9f6e925 fix(agents): restore closing --- in planner+reviewer frontmatter
4670bfe feat(agents): adopt Qoder built-in prompt patterns (temperature, NEVER lists, concise report)
71f3d9f fix(routing): swarm-* agents beat built-in Explore/Plan/general-purpose
5046791 fix(skill): strengthen swarm description to win against general-purpose
aba8c26 perf(models): planner+reviewer back to ultimate
8ee38a8 perf(models): apply specific model names for cost optimization
e6d3606 feat: add context-manager + error-coordinator + tmux launcher
8ee2ef8 feat: 4 borrowed enhancements (non-restrictive)
ee5cc5f docs: research notes on 4 reference projects (2026-06)
69de8ee ci(aoneci): add smoke-test pipeline (#28226186)
```

## 接下来可能要做的事

按优先级：

1. **观察新 description 是否提高触发率** — 在 ai-prd session 用一段时间，扫 prompt 数据再决策
2. **如果触发率还不够** — 考虑给 description 加更激进的规则（如"任何质疑语气都用 swarm"）
3. **可选：写 ATA 介绍文章** — 集团内部分享
4. **可选：tmux launcher 真实演示** — 录屏多 session 协作

## 不要做的事（已决策）

- ❌ multi-harness adapter
- ❌ doc-gardener  
- ❌ mandatory TDD/review 流水线
- ❌ npm publish / marketplace 化
- ❌ 100+ subagent 平铺扩散
- ❌ 给所有 agent 都用 ultimate（破坏成本结构）

## 踩过的坑 / 避免重复

### 1. `isolation: worktree` 要求 session cwd 是 git repo
**症状**: `swarm-worker` 派发时报 `Failed to resolve base branch "HEAD": git rev-parse failed`，整波 7 个 worker 全挂。
**根因**: 主 session 在 `/Users/gx`（非 repo），Qoder 试图在 cwd 建 worktree → HEAD 解析失败。即便 task 指向 `/Users/gx/qoder-swarm`（是 repo），worktree 创建发生在 dispatch 阶段，看的是 session cwd 不是 task cwd。
**修复（已在 agents/swarm-worker.md 落地）**: `isolation: worktree` → `isolation: default`。worktree 改为按需 opt-in：orchestrator 知道目标是 repo 时，通过 Agent 工具的 `isolation: "worktree"` 参数显式启用。
**铁律**: subagent frontmatter 里不要硬编码 `isolation: worktree`。worktree 是"运行期决策"，由调度方根据 cwd 是否 git repo 决定。

### 2. sub-agent 输出截断 / 空 Done
**症状**: `swarm-explorer` / `swarm-librarian` / `swarm-reviewer` 经常返回空（"Agent execution completed" 无内容）或 "fetch failed"。
**根因**: AgentRunner 异常路径未 emit Done（CLAUDE.md §9 已记录）。具体到 qoder-swarm 的影响：sub-agent prompt 太严（要求 inline 返回长报告），output buffer 满或上游异常时整段丢。
**workaround（已在 plan-and-review.md 实践）**: 所有 sub-agent prompt 强制 file-based 产出 —— "Write report to `.swarm/{stage}/report.md`. Final response = 5 lines confirming file path."。orchestrator 失败时直接读文件兜底。
**铁律**: 关键 sub-agent 任务一律 file-based。inline 返回只用来传"文件位置 + 一句摘要"。
**完美 fallback**: orchestrator 自己也要能完成 sub-agent 的工作（这次 gaps.md 就是 reviewer 截断后 orchestrator 手工跑 grep 兜底完成的）。

### 3. 内置 Explore agent 没有 Write 工具
**症状**: 派 Explore 让它把报告写盘 → "I'm operating in READ-ONLY mode and cannot create files"。
**根因**: 内置 Explore agent 的 tools 不含 Write/Edit。
**修复**: 需要写文件时用 `general-purpose` 而非 `Explore`。或 orchestrator 接收 inline 内容自己 Write 落盘（这次 librarian 用了后一种）。
**铁律**: 写文件的 sub-agent 必须有 Write/Edit 工具 —— `Explore` 只读、`swarm-*` 自定义都有、`general-purpose` 全功能。

## 工作风格备忘

用户偏好：
- **直接干活，不要长篇问询**
- **修了就跑 smoke-test 验证 + commit + push 一气呵成**
- **诚实承认错误**（之前我说 maxTurns 默认 10，二进制证明是 200，要承认）
- **不绑死工作流**（superpowers 风格强制流水线被否决）
- **保持紧凑**（拒绝 100+ skill 扩散）

## 本地参考资料路径

```
/tmp/research/superpowers/        ← Claude Code framework + multi-harness
/tmp/research/swarms-amwill/      ← depends_on wave scheduling
/tmp/research/agents/             ← 37k★ marketplace + adapter pattern
/tmp/research/voltagent-subagents/ ← 22k★ subagent taxonomy
```

`grep -r "概念" /tmp/research/` 看别人怎么处理。

## 迭代 3.1 (2026-06-30 续) — self-bootstrap

通过 `swarm:plan-and-review` → `swarm:start-work` → `swarm:five-agent-review` 自举完成。

**改动 (15 files / 170+ insertions)**:
- Wave 1: T1 doc sweep (5→7 subagents, 移除硬编码 assertion 数), T2 model tier docs (用真名替换 efficient/performance), T4 explorer 搜索约束放宽 (2→5 waves), T5 librarian 加 confidence tiers, T6 hardcoded ~/.qoder paths (visual-qa-strict + dispatch-kit), T11 smoke-test +legacy archival 测试 (22→43 assertions), T12 five-agent-review k-vote consensus (3/5 majority)
- Wave 2: T7 ulw-loop wire context-manager, T8 start-work wire error-coordinator, T9 _shared.md routing table 加 2 行
- Wave 3: T10 handoff template
- Ad-hoc: swarm-worker.md isolation worktree→default (修 dispatch HEAD bug), 此 doc 加"踩过的坑"section

**自举验证**: 5-agent review 第一轮 3 PASS / 2 FAIL (NEEDS-FIX per 新 k-vote 规则) → fixers 修 12 个 finding 后通过。

**剩余可改进 (下次迭代)**:
- dispatch-kit/tmux-launch.sh CI 覆盖
- README customization 章节示例同步
- Aone CI 验 43 assertions

## 迭代 7 (2026-07-01 续) — 知识管理集成

obsidian-wiki (MIT, github.com/Ar9av/obsidian-wiki) 直接集成：
- `pip install obsidian-wiki` 或直接 clone + symlink
- 35 个 wiki skills 已 symlink 到 `~/.qoder/skills/` (llm-wiki, wiki-ingest, wiki-query, wiki-lint, wiki-synthesize, wiki-update, cross-linker 等)
- Vault 初始化: `~/Documents/qoder-swarm-wiki/` (Karpathy LLM Wiki 三层架构)
- 架构: raw sources (qoder-swarm 代码) → wiki (LLM 维护的结构化 md) → schema (AGENTS.md 约定)
- 触发: "wiki ingest" / "wiki query" / "wiki lint" / "wiki update" / "记住这个" / "wiki this"
- Obsidian 打开 vault 看 graph view

不自己造轮子。obsidian-wiki 是最成熟的 LLM Wiki 实现 (Karpathy 推荐)，直接用。

### 什么替代了什么

| 之前 | 现在 |
|---|---|
| docs/memory-protocol.md (概念) | obsidian-wiki 35 skills (实现) |
| .swarm/memory/*.md (手工) | ~/Documents/qoder-swarm-wiki/ (LLM 自动维护) |
| 无 wiki-links | [[wiki-links]] + index.md + log.md |
| 无 lint | wiki-lint (orphan/stale/contradiction detection) |
| 无 knowledge graph | Obsidian graph view + cross-linker skill |
