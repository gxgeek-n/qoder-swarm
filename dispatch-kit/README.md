# Qoder Dispatch Kit

多 session 协作的文件协议。在项目里初始化 `.dispatch/` 目录，多个 Qoder 终端各负责一个角色，通过文件系统通信。

## 使用方法

在任何 Qoder session 中说：

```
帮我在当前项目初始化 dispatch 协议，我要多终端协作
```

Qoder 会自动：
1. 创建 `.dispatch/` 目录结构
2. 根据项目特点推荐 worker 角色
3. 生成 `registry.yml`

## 目录结构

```
.dispatch/
├── registry.yml        # 角色注册（谁负责什么）
├── inbox/              # Controller → Worker 的任务
│   ├── impl.md
│   ├── test.md
│   └── docs.md
├── outbox/             # Worker → Controller 的结果
│   ├── impl.md
│   ├── test.md
│   └── docs.md
└── log.jsonl           # 调度审计日志
```

## 操作模式

```
Terminal 1 (controller): qoder  →  编排，读 outbox，写 inbox
Terminal 2 (impl):       qoder  →  读 inbox/impl.md，执行，写 outbox/impl.md
Terminal 3 (test):       qoder  →  读 inbox/test.md，跑测试，写 outbox/test.md
```

## 安全规则

- 默认允许：status_query, task_handoff, evidence_handoff
- 需要确认：publish, deploy, delete, force_push, credentials
- 拒绝：跨 session 传密钥、无检查批量派发

## 模板

见 `templates/` 目录：
- `task-handoff.md` — 派发任务给 worker
- `evidence-handoff.md` — worker 间传递证据
- `worker-result.md` — worker 回报结果

## Integration with swarm-coord-protocol

dispatch-kit and swarm-coord-protocol serve the same purpose at different scales:

| | dispatch-kit (multi-terminal) | swarm-coord-protocol (single-session parallel) |
|---|---|---|
| **Communication** | File inbox/outbox per terminal | Agent tool parallel dispatch |
| **State** | `.dispatch/registry.yml` | `.swarm/tasks.json` via task-dag.sh |
| **Coordination** | Human reads outbox, writes inbox | Orchestrator reads inline returns |
| **Use case** | Long-running parallel sessions (hours/days) | Single orchestration pass (minutes) |

**When to use which:**
- **Single session, short tasks** → swarm-coord-protocol (start-work pattern dispatches parallel workers within one orchestrator session)
- **Multi-session, long-running** → dispatch-kit (each terminal is an independent Qoder session, communicating via filesystem)
- **Hybrid** → Use both: the controller terminal runs swarm patterns internally, while other terminals watch their inbox for cross-session tasks

**Shared concepts (templates ↔ protocol mapping):**
- `templates/task-handoff.md` ↔ plan.md task schema (Goal = description, Scope = files, Acceptance = acceptance)
- `templates/worker-result.md` ↔ 200-token return contract (Status + Changed Files + Verification + Next)
- `templates/evidence-handoff.md` ↔ handoff.md inter-stage template (Decided / Rejected / Risks / Files / Remaining)

**Upgrade path (v5+):**
dispatch-kit's inbox will migrate from single-file markdown to per-message JSON (ported from OmO team-core). See `dispatch-kit/schema/message.json` for the message schema.
