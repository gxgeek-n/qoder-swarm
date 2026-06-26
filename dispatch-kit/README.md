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
