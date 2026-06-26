# Multi-Agent Workflows

本目录包含从 LazyCodex/OmO + ThreadDeck 移植的多 agent 编排 workflow。

## 可用 Workflows

| Workflow | 触发词 | 功能 | Agent 数 | Credit/次 |
|----------|--------|------|---------|-----------|
| `plan-and-review` | "plan this", "规划" | 探索→规划→找漏洞→审批 | 4 | ~1.80x |
| `five-agent-review` | "review work", "审查代码" | 5路并行审查 | 6 | ~2.40x |
| `start-work` | "start work", "执行计划" | 并行执行+对抗验证 | N+2 | 按任务数 |
| `remove-ai-slops` | "remove slop", "清理AI代码" | 行为锁定→并行清理→质检 | N/5+2 | 按文件数 |
| `init-deep` | "init-deep", "项目记忆" | 动态探索→评分→生成AGENTS.md | 4-12 | ~1.20x |
| `ultraresearch` | "ultraresearch", "深度研究" | 轴分解→蜂群搜索→递归展开 | 3-15 | 按复杂度 |
| `debugging` | "debug this", "为什么报错" | 3+假设并行→最小修复→验证 | 5 | ~2.40x |

## 模型搭配（当前配置）

```javascript
const CHEAP = 'Qwen3.7-Max-DogFooding'  // 0.00x - 搜索、只读、解析
const MID   = 'GLM-5.2'                 // 0.60x - 代码实现、QA
const HEAVY = 'GLM-5.2'                 // 0.60x - 深度推理、审查
```

修改任意 workflow 文件顶部的 3 个常量即可切换模型。

## 使用方式

在 Qoder 对话中直接说触发词，或显式调用：

```
Workflow({ name: 'plan-and-review', args: { task: '重构认证模块' } })
Workflow({ name: 'five-agent-review', args: { goal: '添加了 OAuth 支持' } })
Workflow({ name: 'start-work', args: { tasks: ['实现登录页', '写集成测试'] } })
Workflow({ name: 'remove-ai-slops', args: {} })
Workflow({ name: 'init-deep', args: {} })
Workflow({ name: 'ultraresearch', args: { question: 'React Server Components 原理' } })
Workflow({ name: 'debugging', args: { symptom: 'TypeError: Cannot read property x of null' } })
```

## Dispatch 协议（多终端协作）

见 `dispatch-kit/README.md`。在 Qoder 中说"帮我初始化 dispatch 协议"即可。

## 设计原则（来自 LazyCodex）

1. **编排不实现** — 主 agent 只做决策/验证/分发，不碰产品代码
2. **证据驱动** — 每一步要求可验证的交付物，不接受"should work"
3. **模型分级** — 搜索用免费模型，推理用付费模型，省 66% credit
4. **对抗验证** — 实现者和验证者必须是不同 agent
5. **并行最大化** — 独立任务同一 wave 并行，只有依赖才串行
