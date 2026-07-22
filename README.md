<p align="center">
  <h1 align="center">qoder-swarm</h1>
  <p align="center"><strong>Multi-agent orchestration kit for Qoder CLI</strong></p>
  <p align="center">Ported from <a href="https://github.com/code-yeongyu/lazycodex">LazyCodex/OmO</a> + <a href="https://github.com/readysteadyscience/codex-threaddeck">ThreadDeck</a></p>
</p>

## What It Does

Turn a single Qoder session into a multi-agent control room with model-tiered cost optimization.

| Feature | Origin | Description |
|---------|--------|-------------|
| **`swarm` Skill** (primary) | Original | One auto-triggered skill routes natural-language requests to 16 orchestration patterns |
| 9 custom subagents | LazyCodex/OmO | `swarm-explorer/librarian/planner/reviewer/worker/worker-glm/worker-qwen/context-manager/error-coordinator` with per-role model tiers |
| 10 hooks | Original + LazyCodex | Pre/post-tool, session-start, stop, and prompt-submit hooks for quality, memory, and audit |
| Dispatch protocol | ThreadDeck | Multi-terminal collaboration via file system |
| Model tiering | Original | Free Qwen for search, GLM for code, Kimi-K3 for planning — save 60%+ credits |
| Wiki integration | obsidian-wiki | Auto-ingest swarm outputs into an Obsidian vault (Karpathy LLM Wiki architecture) |
| 10 Workflow scripts (optional) | LazyCodex/OmO | Reference `.mjs` runtime implementations; require Qoder Workflow tool feature flag |

## Install

### Option A: Plugin install (recommended)

```bash
qodercli plugin install https://github.com/gxgeek/qoder-swarm.git
```

Or from local clone:
```bash
git clone https://github.com/gxgeek/qoder-swarm.git
cd qoder-swarm
qodercli plugin install .
```

### Option B: Manual install

```bash
git clone https://github.com/gxgeek/qoder-swarm.git
cd qoder-swarm
bash install.sh
```

After install, reload in your session: `/agents reload` + `/skills reload`.

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
| `autopilot` | "full auto" / "全自动" / "hands off" | 4+ | varies |
| `ralph` | "persistence loop" / "不停直到完成" | 1-20 | varies |
| `magentic-loop` | "group conversation" / "对辩收敛" | 3-8 | varies |
| `self-improve` | "evolutionary" / "自进化" / "tournament" | 3+ | varies |
| `cancel` | "cancel" / "stop swarm" / "取消" | 0 | free |
| `skillify` | "make this a skill" / "提取技能" | 2 | ~1.20x |

**Advanced**: power users with the Qoder Workflow tool feature flag enabled can also invoke patterns directly:
```
Workflow({ name: "plan-and-review", args: { task: "..." } })
```
The `workflows/*.mjs` scripts ship as reference implementations of the same patterns.

## Model Configuration

Each workflow has 3 tiers at the top of the file:

```javascript
const CHEAP = 'Peach-07-17-DogFooding'  // 0.00x - FREE
const MID   = 'GLM-5.2'                 // 0.60x - code
const HEAVY = 'GLM-5.2'                 // 0.60x - reasoning
```

Change these to any model from `/model`:
- `Peach-07-17-DogFooding` (0.00x) — free dogfooding
- `Qwen3.7-Plus` (0.10x) — cheap reasoning
- `DeepSeek-V4-Flash` (0.10x) — cheap general
- `MiniMax-M3` (0.20x) — multimodal
- `Kimi-K2.7-Code` (0.30x) — code specialist
- `DeepSeek-V4-Pro` (0.50x) — strong reasoning
- `Qwen3.7-Max` (0.50x/0.25x) — top tier, half price regular hours
- `GLM-5.2` (0.60x) — engineering-grade
- `Kimi-K3` (0.80x) — deep reasoning, used for planner + reviewer

## Hooks System

The installer registers 10 hooks across 5 Qoder lifecycle events. All scripts are copied to `~/.qoder/hooks/` and auto-registered in `settings.json` via `install-settings.py`.

| Hook | Event | Matcher | What it does |
|------|-------|---------|-------------|
| `swarm-comment-checker.sh` | PostToolUse | `Edit\|Write\|NotebookEdit` | Post-edit AI-slop reminder |
| `swarm-stop-continuation.sh` | Stop | `*` | Pending-work alert on session end |
| `pre-tool-enforcer.py` | PreToolUse | `Agent` | Prompt-size budget, subagent_type validity, cancel signals |
| `post-tool-verifier.py` | PostToolUse | `Agent` | Catch empty-done (<50 chars) and oversized output (>50KB) |
| `session-start.py` | SessionStart | `*` | Restore active swarm pattern context from `.swarm/` state |
| `keyword-detector.py` | UserPromptSubmit | `*` | Detect swarm trigger keywords, inject routing hints |
| `memory-learner.py` | PostToolUse | `Agent` | Auto-extract learnings into `.swarm/memory/` |
| `subagent-tracker.py` | Pre+PostToolUse | `Agent` | Track active sub-agents in `.swarm/audit/active-agents.json` |
| `swarm-wiki-ingest.py` | PostToolUse | `Agent` | Auto-ingest completed swarm outputs into Obsidian wiki vault |
| `agent-dispatch-log.sh` | PostToolUse | `Agent` | Log Agent dispatches to `.swarm/audit/dispatches.jsonl` for cost analysis |

Hooks are idempotent: re-running `bash install.sh` never duplicates entries. Uninstall removes only swarm hooks, preserving user hooks.

## Wiki Integration

qoder-swarm integrates with [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) (MIT) for persistent knowledge management — no need to build a wiki system from scratch.

**Architecture** (Karpathy LLM Wiki three-layer model):
1. **Raw sources** — qoder-swarm code, `.swarm/` state files, agent outputs
2. **Wiki layer** — LLM-maintained structured Markdown in `~/Documents/qoder-swarm-wiki/`
3. **Schema layer** — conventions encoded in `AGENTS.md`

**Triggers**: `"wiki ingest"` / `"wiki query"` / `"wiki lint"` / `"记住这个"` / `"wiki this"`

The `swarm-wiki-ingest.py` hook auto-distills completed swarm outputs (reports, plans, reviews) into wiki pages with frontmatter. Open the vault in Obsidian to see the knowledge graph via `[[wiki-links]]`.

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
├── skills/swarm/            # The 'swarm' Skill — primary entry point
│   ├── SKILL.md             #   router with trigger words → reference dispatch
│   ├── references/          #   20 files (16 routable patterns + 4 utility)
│   └── prompts/             #   7 prompt templates (context-recovery, replan, etc.)
├── agents/                  # 9 custom subagents (per-role models: agents/models.yml)
│   ├── models.yml                    # single source of truth for model bindings
│   ├── swarm-explorer.md            # read-only codebase search
│   ├── swarm-librarian.md           # external docs/OSS
│   ├── swarm-planner.md             # strategic planning
│   ├── swarm-reviewer.md            # adversarial review
│   ├── swarm-worker.md              # implementation (default)
│   ├── swarm-worker-glm.md           # GLM-pinned worker variant
│   ├── swarm-worker-qwen.md          # free-tier worker variant
│   ├── swarm-context-manager.md     # context window management
│   └── swarm-error-coordinator.md   # error recovery
├── workflows/               # 10 Workflow .mjs (optional, feature-gated)
├── hooks/                   # 10 hook scripts (2 .sh + 8 .py/.sh)
├── scripts/                 # 17 utility scripts (DAG, cost, state, wiki, etc.)
├── dispatch-kit/            # Multi-session protocol
│   ├── registry.yml
│   ├── init-dispatch.sh
│   ├── tmux-launch.sh
│   ├── schema/message.json
│   └── templates/            # 3 handoff templates
├── tests/smoke-test.sh      # Automated assertion suite
├── docs/                    # Articles, memory protocol, research notes
│   ├── articles/
│   ├── memory-protocol.md
│   └── research-2026.md
├── .swarm/                  # Runtime state (DAG, memory, audit logs)
├── ARCHITECTURE.md          # 5 design invariants (I1-I5)
├── Makefile                 # make help/install/test/doctor/status/lint/clean
├── install.sh               # One-command installer
├── install-settings.py      # Hook registration + uninstall
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

After installation, the 9 subagents live at `~/.qoder/agents/swarm-*.md`. Each is a Markdown file with YAML frontmatter. You can edit them to fit your environment without touching this repo.

### Switch underlying models

Each subagent's `model:` field controls which LLM it uses. Defaults are defined once in `agents/models.yml` and propagated by `scripts/sync-models.py`:

<!-- MODEL-BINDINGS:BEGIN — auto-generated by scripts/sync-models.py; edit agents/models.yml instead -->
| Agent | Default model | Cost tier |
|-------|--------------|-----------|
| swarm-explorer | Peach-07-17-DogFooding | 0.00x (free) |
| swarm-librarian | Peach-07-17-DogFooding | 0.00x (free) |
| swarm-planner | Kimi-K3 | 0.80x |
| swarm-reviewer | Kimi-K3 | 0.80x |
| swarm-worker | GLM-5.2 | 0.60x |
| swarm-worker-glm | GLM-5.2 | 0.60x |
| swarm-worker-qwen | Peach-07-17-DogFooding | 0.00x (free) |
| swarm-context-manager | DeepSeek-V4-Flash | 0.10x |
| swarm-error-coordinator | DeepSeek-V4-Flash | 0.10x |
<!-- MODEL-BINDINGS:END -->

To force a specific model:

```yaml
# ~/.qoder/agents/swarm-explorer.md
model: Peach-07-17-DogFooding   # free dogfooding model
```

Run `/model` inside Qoder to see what's available in your account.

### Updating models when the Qoder catalog changes

Model names live in exactly one place: `agents/models.yml`. When Qoder renames or retires a model:

```bash
python3 scripts/sync-models.py --auto-fix   # remap vanished models + propagate
python3 scripts/sync-models.py --check      # or just detect drift (CI mode, exit 1)
```

`sync-models.py` rewrites agent frontmatter, syncs `~/.qoder/agents/`, and regenerates the table above. Auto-fix rules: a vanished `*-DogFooding` model remaps to the current dogfooding entry; otherwise the first valid `fallback_models` entry is promoted. To hand-pick replacements instead, edit `agents/models.yml` and run without flags.

### Add MCP servers

If you have MCP servers configured at the session level (`settings.json` `mcpServers`), give a specific subagent access by adding to its frontmatter:

```yaml
mcpServers:
  - code        # internal Alibaba code MCP
  - yuque       # internal docs MCP
  - github      # public github MCP
```

Or define an MCP server inline for one subagent only — see the [Qoder subagent docs](https://docs.qoder.com/en/cli/subagent.md#configure-mcp) for full syntax.

### Preload more skills

`skills:` preloads specialized skills into the subagent's context. Defaults already include `ast-grep`, `code-reading-skill`, `security-review`, `simplify`. Add more:

```yaml
skills:
  - simplify
  - ast-grep
  - code-reading-skill
  - tech-prd-v2                 # internal: AE trade PRD
```

### Change permissions / runtime limits

```yaml
permissionMode: acceptEdits     # auto-approve edits (less prompting)
maxTurns: 20                    # more conversation turns
timeoutMins: 30                 # longer runtime cap
isolation: worktree             # run in separate git worktree
```

### Override without editing files

Use `settings.json` overrides to keep `~/.qoder/agents/swarm-*.md` clean for easy upgrades:

```json
{
  "agents": {
    "overrides": {
      "swarm-explorer": {
        "modelConfig": { "model": "Peach-07-17-DogFooding" },
        "mcpServers": { "code": { "type": "http", "url": "..." } }
      }
    }
  }
}
```

This persists across `bash install.sh` re-runs.

## Testing

Run the smoke-test against a throwaway `QODER_HOME`. It leaves no trace on your real `~/.qoder/`:

```bash
bash tests/smoke-test.sh           # ~5 seconds (assertion count printed by the test itself)
bash tests/smoke-test.sh --keep    # leave the tmpdir for inspection
bash tests/smoke-test.sh --verbose # print every command
```

The suite runs automated assertions across 8 sections:

| Section | Checks |
|---------|--------|
| Installer auxiliary commands | `--help` / `--version` / `--doctor`, rejects unknown options |
| Fresh install | exit 0, all expected dirs/files created |
| File layout | workflows, hooks, scripts, SKILL.md, references, agents, dispatch templates, settings.json |
| settings.json sanity | valid JSON, hook paths resolve under `QODER_HOME` (not hardcoded `~/.qoder/`) |
| Agent frontmatter | YAML parses for every swarm-* agent, required fields present |
| image-diff.py | output is valid JSON, similarity / diffPixels / hotspots match a known fixture |
| Idempotency | re-run produces no duplicate hooks, prints "Nothing to do", preserves unrelated user hooks |
| Uninstall round-trip | swarm hooks removed, user's other hooks intact |

Exit code = number of failed checks. Use it in CI:

```yaml
# .github/workflows/test.yml
- run: bash tests/smoke-test.sh
```

When a check fails:
1. Re-run with `--keep --verbose` to inspect the tmpdir.
2. Look at `$TMP_HOME/install-1.log` and `install-2.log` for installer output.
3. The "Failed tests" summary at the end names every check that broke.

## Security Notes

Read these before running `bash install.sh` from a repo you didn't write.

**What the installer does to your system:**
- Writes files into `$QODER_HOME` (default `~/.qoder/`) — workflows, hooks, scripts, skills, agents
- Modifies `$QODER_HOME/settings.json` to register hooks (backup saved as `settings.json.swarm-backup-<timestamp>`)
- Does NOT use sudo, does NOT call out to the network, does NOT modify anything outside `$QODER_HOME`

**Auditable in advance:** `bash install.sh --doctor` checks prerequisites without writing anything. `python3 install-settings.py --dry-run` shows the proposed settings.json change.

**Trust model of the subagents:**
- `swarm-explorer` / `swarm-librarian` / `swarm-reviewer` are filesystem read-only via `disallowedTools: [Write, Edit, NotebookEdit]`
- `swarm-worker` has full write access. The shipped default is `isolation: default` (not worktree-isolated). Orchestrators can request `isolation: worktree` at Agent call time when the cwd is a git repo.
- `swarm-planner` has `Edit`/`Write` but is **prompt-enforced** to only touch `.swarm/plans/*.md`. The boundary is NOT filesystem-enforced — a maliciously crafted prompt could direct it elsewhere. Treat planner output the same way you treat any other LLM-generated code: review before relying on it.

**Hostile-repo defense:**
The `swarm-stop-continuation.sh` hook reads `.swarm/` state files from the current project. State files are **untrusted input** when they ship via a repo you didn't author. The hook sanitizes content (control chars stripped, length capped, JSON parsed via `python3`) but the threat model is "best-effort" — if you clone a repo from a source you don't trust, delete `.swarm/` before opening a Qoder session.

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
| [oh-my-qoder](https://github.com/chickenlj/oh-my-qoder) | Self-improve pattern, structured commit trailers | Apache-2.0 |
| [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) | Wiki integration, 35 wiki skills, Karpathy LLM Wiki architecture | MIT |
| [Semantic Kernel](https://github.com/microsoft/semantic-kernel) | Magentic group conversation pattern (magentic-loop) | MIT |
| [ClawTeam](https://github.com/HKUDS/ClawTeam) | DAG self-coordination design, file-overlap detection | MIT |

## License

MIT
