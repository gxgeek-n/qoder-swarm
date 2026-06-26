<p align="center">
  <h1 align="center">qoder-swarm</h1>
  <p align="center"><strong>Multi-agent orchestration kit for Qoder CLI</strong></p>
  <p align="center">Ported from <a href="https://github.com/code-yeongyu/lazycodex">LazyCodex/OmO</a> + <a href="https://github.com/readysteadyscience/codex-threaddeck">ThreadDeck</a></p>
</p>

## What It Does

Turn a single Qoder session into a multi-agent control room with model-tiered cost optimization.

| Feature | Origin | Description |
|---------|--------|-------------|
| **`swarm` Skill** (primary) | Original | One auto-triggered skill routes natural-language requests to 10 orchestration patterns |
| 5 custom subagents | LazyCodex/OmO | `swarm-explorer/librarian/planner/reviewer/worker` with per-role model tiers |
| Dispatch protocol | ThreadDeck | Multi-terminal collaboration via file system |
| Comment-checker hook | LazyCodex | Post-edit AI-slop reminder |
| Stop-continuation hook | LazyCodex | Pending-work alert on session end |
| Model tiering | Original | Free Qwen for search, GLM for code — save 60%+ credits |
| 10 Workflow scripts (optional) | LazyCodex/OmO | Reference `.mjs` runtime implementations; require Qoder Workflow tool feature flag |

## Install

```bash
# Replace the URL below with your fork's URL after publishing
git clone <YOUR_REPO_URL> qoder-swarm
cd qoder-swarm
bash install.sh
```

Or let Qoder do it:
```
Clone qoder-swarm and run its install.sh
```

## Orchestration Patterns

The `swarm` Skill auto-activates from natural-language triggers (works on all Qoder accounts). Each pattern lives in `~/.qoder/skills/swarm/references/<name>.md` after install.

| Pattern | Trigger (EN / 中文) | Agents | Cost |
|---------|---------------------|--------|------|
| `plan-and-review` | "plan this" / "规划" | 4 | ~1.80x |
| `five-agent-review` | "review work" / "审查代码" | 6 | ~2.40x |
| `start-work` | "start work" / "开始干活" | N+2 | varies |
| `remove-ai-slops` | "clean AI code" / "清理AI代码" | N/5+2 | varies |
| `init-deep` | "project memory" / "项目记忆" | 4-12 | ~1.20x |
| `ultraresearch` | "deep research" / "深度研究" | 3-15 | varies |
| `debugging` | "debug this" / "调试" | 5 | ~2.40x |
| `visual-qa-strict` | "visual QA" / "视觉验证" | 4 | ~2.40x |
| `teammode` | "team mode" / "团队模式" | 4+ | varies |
| `ulw-loop` | "keep going" / "一直跑到完成" | 1-20 | varies |

**Advanced**: power users with the Qoder Workflow tool feature flag enabled can also invoke patterns directly:
```
Workflow({ name: "plan-and-review", args: { task: "..." } })
```
The `workflows/*.mjs` scripts ship as reference implementations of the same patterns.

## Model Configuration

Each workflow has 3 tiers at the top of the file:

```javascript
const CHEAP = 'Qwen3.7-Max-DogFooding'  // 0.00x - FREE
const MID   = 'GLM-5.2'                 // 0.60x - code
const HEAVY = 'GLM-5.2'                 // 0.60x - reasoning
```

Change these to any model from `/model`:
- `Qwen3.7-Max-DogFooding` (0.00x) — free dogfooding
- `Qwen3.7-Plus` (0.10x) — cheap reasoning
- `DeepSeek-V4-Flash` (0.10x) — cheap general
- `MiniMax-M3` (0.20x) — multimodal
- `Kimi-K2.7-Code` (0.30x) — code specialist
- `DeepSeek-V4-Pro` (0.50x) — strong reasoning
- `Qwen3.7-Max` (0.50x/0.25x) — top tier, half price regular hours
- `GLM-5.2` (0.60x) — engineering-grade

## Multi-Terminal Dispatch

For persistent cross-session collaboration:

```
# In any Qoder session:
"帮我初始化 dispatch 协议"

# Or manually:
bash ~/.qoder/dispatch-kit/init-dispatch.sh /path/to/project
```

Then open multiple terminals, each Qoder session reads its role's inbox.

## Architecture

```
qoder-swarm/
├── skills/swarm/        # The 'swarm' Skill — primary entry point
│   ├── SKILL.md         #   router with trigger words → reference dispatch
│   └── references/      #   10 orchestration pattern playbooks
├── agents/              # 5 custom subagents with per-role model tiers
│   ├── swarm-explorer.md   # efficient/low — read-only codebase search
│   ├── swarm-librarian.md  # efficient/low — external docs/OSS
│   ├── swarm-planner.md    # performance/high — strategic planning
│   ├── swarm-reviewer.md   # performance/high — adversarial review
│   └── swarm-worker.md     # performance/medium — implementation (worktree-isolated)
├── workflows/           # 10 Workflow .mjs (optional, feature-gated)
│   ├── plan-and-review.mjs
│   ├── five-agent-review.mjs
│   ├── start-work.mjs
│   ├── remove-ai-slops.mjs
│   ├── init-deep.mjs
│   ├── ultraresearch.mjs
│   ├── debugging.mjs
│   ├── teammode.mjs
│   ├── ulw-loop.mjs
│   └── visual-qa-strict.mjs
├── hooks/               # Post-tool and stop hooks
│   ├── swarm-comment-checker.sh
│   └── swarm-stop-continuation.sh
├── dispatch-kit/        # Multi-session protocol
│   ├── registry.yml
│   ├── init-dispatch.sh
│   └── templates/
├── install.sh           # One-command installer
└── package.json
```

## Design Principles

1. **Orchestrate, never implement** — main agent dispatches, workers execute
2. **Evidence-driven completion** — no "should work", every claim has a verification command
3. **Model tiering** — search with free models, reason with paid models
4. **Adversarial verification** — implementer and verifier are always different agents
5. **Maximum parallelism** — independent tasks run concurrently in waves
6. **Durable state** — survives context loss via `.swarm/` files
7. **Budget-aware** — workflows check `budget.remaining()` before expensive operations

## Customizing swarm-* Subagents

After installation, the 5 subagents live at `~/.qoder/agents/swarm-*.md`. Each is a Markdown file with YAML frontmatter. You can edit them to fit your environment without touching this repo.

### Switch underlying models

Each subagent's `model:` field controls which LLM it uses. Default values are Qoder model tiers (`efficient`, `performance`). To force specific models:

```yaml
# ~/.qoder/agents/swarm-explorer.md
model: Qwen3.7-Max-DogFooding   # free dogfooding model
```

```yaml
# ~/.qoder/agents/swarm-planner.md
model: GLM-5.2                  # specific provider model
```

Run `/model` inside Qoder to see what's available in your account.

### Add MCP servers

If you have MCP servers configured at the session level (`settings.json` `mcpServers`), give a specific subagent access by adding to its frontmatter:

```yaml
# Reference an already-configured MCP server by name
mcpServers:
  - code        # internal Alibaba code MCP
  - yuque       # internal docs MCP
  - github      # public github MCP
```

Or define an MCP server inline for one subagent only — see the [Qoder subagent docs](https://docs.qoder.com/en/cli/subagent.md#configure-mcp) for full syntax.

### Preload more skills

`skills:` preloads specialized skills into the subagent's context (vs. having it discovered via description matching). Defaults already include `ast-grep`, `code-reading-skill`, `security-review`, `simplify`. Add more:

```yaml
# Worker that handles AE-Trade domain code
skills:
  - simplify
  - ast-grep
  - code-reading-skill
  - tech-prd-v2                 # internal: AE trade PRD
  - ae-trade-carts-convention   # internal: AE carts convention
```

### Change permissions / runtime limits

```yaml
permissionMode: acceptEdits     # auto-approve edits (less prompting)
maxTurns: 20                    # more conversation turns
timeoutMins: 30                 # longer runtime cap
isolation: worktree             # run in separate git worktree
```

### Override without editing files

If you want to keep `~/.qoder/agents/swarm-*.md` clean (for easy upgrades), use `settings.json` overrides:

```json
{
  "agents": {
    "overrides": {
      "swarm-explorer": {
        "modelConfig": { "model": "Qwen3.7-Max-DogFooding" },
        "mcpServers": { "code": { "type": "http", "url": "..." } }
      }
    }
  }
}
```

This persists across `bash install.sh` re-runs.

## Security Notes

Read these before running `bash install.sh` from a repo you didn't write.

**What the installer does to your system:**
- Writes files into `$QODER_HOME` (default `~/.qoder/`) — workflows, hooks, scripts, skills, agents
- Modifies `$QODER_HOME/settings.json` to register two hooks (backup saved as `settings.json.swarm-backup-<timestamp>`)
- Does NOT use sudo, does NOT call out to the network, does NOT modify anything outside `$QODER_HOME`

**Auditable in advance:** `bash install.sh --doctor` checks prerequisites without writing anything. `python3 install-settings.py --dry-run` shows the proposed settings.json change.

**Trust model of the subagents:**
- `swarm-explorer` / `swarm-librarian` / `swarm-reviewer` are filesystem read-only via `disallowedTools: [Write, Edit, NotebookEdit]`
- `swarm-worker` has full write access and runs with `isolation: worktree` so changes land in a separate git worktree the orchestrator merges
- `swarm-planner` has `Edit`/`Write` but is **prompt-enforced** to only touch `.swarm/plans/*.md`. The boundary is NOT filesystem-enforced — a maliciously crafted prompt could direct it elsewhere. Treat planner output the same way you treat any other LLM-generated code: review before relying on it.

**Hostile-repo defense:**
The `swarm-stop-continuation.sh` hook reads `.swarm/ulw-loop/state.json` and `.swarm/teams/*/team.json` from the current project and echoes a snippet to the next session. State files are **untrusted input** when they ship via a repo you didn't author. The hook sanitizes the content (control chars stripped, length capped at 80 chars, JSON parsed via `python3 -c` not regex) but the threat model is "best-effort" — if you clone a repo from a source you don't trust, delete `.swarm/` before opening a Qoder session in that directory.

**Uninstall:**
```bash
python3 install-settings.py --uninstall    # removes only swarm hooks; user's other hooks preserved
rm -rf ~/.qoder/skills/swarm ~/.qoder/agents/swarm-*.md   # removes the kit's files
```

## Provenance

| Source | What was ported | License |
|--------|----------------|---------|
| [LazyCodex](https://github.com/code-yeongyu/lazycodex) | Agent roles, planning flow, review pattern, ulw-loop, remove-ai-slops, init-deep, debugging, teammode | MIT |
| [ThreadDeck](https://github.com/readysteadyscience/codex-threaddeck) | Dispatch protocol, registry, task/evidence handoff templates, safety model | MIT |

## License

MIT
