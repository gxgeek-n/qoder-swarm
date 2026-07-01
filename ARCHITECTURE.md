# Architecture

The 5 invariants that make qoder-swarm work. Don't break these when modifying the kit.

## I1 — One Skill, N References

There is exactly **one** registered Qoder skill: `swarm`. It lives at `skills/swarm/SKILL.md`. Everything else under `skills/swarm/references/*.md` is a routing target, not a skill of its own.

Why: Qoder's `/agents` and skill auto-trigger system gets cluttered if every pattern is a separate skill. One router + 10 references = one entry in `/agents`, 10 patterns reachable by natural-language triggers.

When to break: don't. If a new pattern is needed, add `references/<name>.md` and one row to the `## When to activate` table in SKILL.md.

## I2 — Subagent Definitions Carry the Model Tier

Every per-role subagent under `agents/swarm-*.md` has a `model:` frontmatter field. Qoder's Agent tool **does not accept a model parameter at call time** — model selection lives in the subagent definition.

Why: this is what Qoder's docs/cli/subagent.md actually supports. We tried passing `model:` as an Agent tool arg in an early version and it was silently ignored.

When to break: don't. Users override via either editing the frontmatter or `settings.json` `agents.overrides` (see README "Customizing swarm-* Subagents").

## I3 — Plans Are Files, State Is Files

Every long-running pattern writes its state to `.swarm/<pattern>/` (plan files, ledgers, team manifests). No state lives only in the LLM session. This is what survives context loss.

Why: Qoder sessions get compacted / restarted. State on disk is the source of truth; the agent's working memory is a cache of that.

When to break: don't. If a new pattern needs persistence, write to `.swarm/<pattern>/<thing>.{json,md,jsonl}` and document it in the reference.

## I4 — Hook Paths Are Built from QODER_HOME, Not Hardcoded

`install-settings.py` registers hooks with paths derived from the `--qoder-home` argument via `hook_command_path()`. Default home gets the portable `~/.qoder/...` tilde form; non-default homes get absolute paths.

Why: P0-2 from the five-agent review — `bash install.sh /opt/qoder` silently failed because hook commands were hardcoded `~/.qoder/hooks/...`. This invariant prevents that regression.

When to break: don't, ever. If a new hook is added, it goes into `SWARM_HOOKS` with a `script:` field (basename only), and `hook_command_path()` builds the full path.

## I5 — Reversible Cleanup

`install.sh` never `rm -rf`s a user-touched directory. Legacy per-pattern skill dirs from older installs only get archived (moved to `.swarm-archive/<timestamp>/`) if they carry the `.swarm-installed` marker file we wrote. Anything without the marker is left alone with a warning.

Why: P1-6 from the review — the original cleanup nuked any user-owned skill that happened to share a name with one of our legacy patterns (e.g. a user's personal `debugging` skill).

When to break: don't. New cleanup logic must follow the same marker pattern.

---

## Layout that follows from these invariants

```
qoder-swarm/
├── skills/swarm/                  # I1: one skill, one router
│   ├── SKILL.md                   #     routing only
│   └── references/                #     N pattern playbooks
├── agents/                        # I2: each .md is one subagent with model tier
│   └── swarm-*.md
├── hooks/                         # I4: hooks read from ~/.qoder/hooks/, but
│   └── swarm-*.sh                 #     install-settings.py writes the path
├── install-settings.py            # I4: hook_command_path() builds dynamic paths
├── install.sh                     # I5: marker-based archive-not-delete
├── scripts/                       # standalone tools (image-diff, etc.)
├── tests/smoke-test.sh            # automated assertions against this entire model
├── dispatch-kit/                  # multi-session protocol (file-based, I3)
└── docs/                          # research, plans, this file
```

State that gets written into user projects (I3):

```
.swarm/
├── plan-and-review/<slug>.md     # planner output
├── ulw-loop/{state.json,ledger.jsonl}
├── teams/<name>/{team.json,inbox/,outbox/,artifacts/}
└── .swarm-archive/<ts>/...        # legacy skill backups (I5)
```

## Non-invariants (things that can change freely)

- Number of `references/*.md` (currently 11)
- Number of `swarm-*` subagents (currently 7)
- Specific tool lists in agent frontmatter — adjust per evolving Qoder doc
- Reference doc structure (Stage 1 / Step 1 / etc.) — stylistic
- Model names in agent frontmatter (Qwen3.7-Max-DogFooding, Ultimate, GLM-5.2, DeepSeek-V4-Flash — case-sensitive, must match `qodercli --list-models` exactly; re-tune as Qoder model catalog evolves)
- README sections — additive
- Workflows under `workflows/*.mjs` — they're optional reference impls, not the source of truth
- Agent frontmatter `fallback_models:` field — ordered list of retry models; orchestrator honors when primary fails (see `references/_shared.md` Fallback chain section)

## How to extend safely

| Adding | Do |
|--------|---|
| A new orchestration pattern | Drop `references/<name>.md`, add one row to `## When to activate` in SKILL.md |
| A new subagent role | Drop `agents/swarm-<role>.md` with `model:` + `tools:` frontmatter |
| A new hook | Add `script:` entry to `SWARM_HOOKS` in install-settings.py; write `hooks/swarm-<name>.sh` |
| A new helper script | Drop in `scripts/`; install.sh's nullglob copy will pick it up |
| A new test | Append a `check`/`expect` to `tests/smoke-test.sh` |

| Removing | Do |
|----------|---|
| An old pattern | Delete the reference; if it shipped publicly, archive to `docs/deprecated/` first |
| An old hook | Bump SWARM_HOOKS, run `install-settings.py --uninstall` then re-install |
| An old subagent | Delete `agents/swarm-<role>.md`; check no reference points at it |

## When you must break an invariant

Document it in this file, in a `## Exceptions` section, with:
- which invariant
- why (real-world driver, not theoretical)
- escape hatch (how to detect when you've crossed back to OK)
- date + commit ref
