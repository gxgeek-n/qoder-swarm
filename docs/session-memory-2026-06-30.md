# Session Memory — 2026-06-30

> 这份记忆给压缩后或新 session 接手用。读完这一份就能继续干活。

## 项目是什么

`qoder-swarm` — Qoder CLI 的多 agent 编排套件，从 LazyCodex/OmO + ThreadDeck 移植。Repo: `git@gitlab.alibaba-inc.com:gxgeek/qoder-swarm.git`

核心是 **1 个 swarm skill + 7 个 swarm-* subagent + 10 个 reference pattern**。

## 当前架构（已稳定）

```
qoder-swarm/
├── ARCHITECTURE.md        ← 5 条不变式 I1-I5
├── Makefile               ← make help/install/test/doctor/status/lint/clean
├── README.md              ← 含 Testing / Security Notes / Customizing 章节
├── LICENSE                ← MIT
├── package.json           ← repository: gitlab.alibaba-inc.com:gxgeek/qoder-swarm
├── .aoneci/smoke.yaml     ← Aone CI 每 push 跑 smoke (alios-8u + pip Pillow + tests/smoke-test.sh)
├── .claude-plugin/README.md  ← 指向 .qoder-plugin
├── .qoder-plugin/plugin.json
├── agents/                ← 7 个 swarm-* subagent
├── skills/swarm/          ← 1 router SKILL.md + 11 references
├── hooks/                 ← swarm-comment-checker.sh + swarm-stop-continuation.sh
├── scripts/image-diff.py  ← numpy 像素 diff
├── dispatch-kit/          ← 多 session 文件协议 + tmux-launch.sh
├── workflows/*.mjs        ← 10 个可选 .mjs 引擎实现
├── tests/smoke-test.sh    ← 39 项断言 ~5 秒
└── docs/research-2026.md  ← 4 个参考项目分析
```

## 7 个 swarm-* subagent 当前配置

| Agent | Model | Effort | Temp | 角色 |
|-------|-------|--------|------|------|
| swarm-explorer | **Qwen3.7-Max-DogFooding** (0.00x 免费) | low | 0 | 代码搜索 |
| swarm-librarian | **Qwen3.7-Max-DogFooding** (0.00x 免费) | low | — | 外部文档/OSS |
| swarm-context-manager | DeepSeek-V4-Flash (0.10x) | low | — | 长 session 上下文压缩 |
| swarm-error-coordinator | DeepSeek-V4-Flash (0.10x) | medium | — | 多 worker 失败时的恢复路由 |
| **swarm-planner** | **ultimate** (1.0x) | high | 0.2 | 规划（杠杆点不打折） |
| **swarm-reviewer** | **ultimate** (1.0x) | high | 0 | 审查（最后一道门） |
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

- 仓库: https://code.alibaba-inc.com/gxgeek/qoder-swarm
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
make test                       # 39 项 ~5 秒

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
