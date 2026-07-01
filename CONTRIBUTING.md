# Contributing to qoder-swarm

## Quick start

```bash
git clone https://github.com/gxgeek/qoder-swarm.git
cd qoder-swarm
bash install.sh        # install to ~/.qoder/
bash tests/smoke-test.sh  # verify everything works
```

## How to add a new pattern

1. Create `skills/swarm/references/<your-pattern>.md` following the existing format (see `plan-and-review.md` as template)
2. Add a routing row in `skills/swarm/SKILL.md` with trigger words
3. Run `bash scripts/check-references.sh` to verify no broken cross-references
4. Run `bash tests/smoke-test.sh` to verify nothing breaks
5. Submit a PR

## How to add a new hook

1. Create `hooks/<your-hook>.py` (Python, stdlib-only, ≤80 lines, fast path <5ms for non-matching tools)
2. Register in `install-settings.py` under the appropriate lifecycle event
3. Run `bash install.sh` to install to `~/.qoder/hooks/`
4. Test manually: `echo '<json payload>' | python3 hooks/<your-hook>.py`

## How to run tests

```bash
bash tests/smoke-test.sh              # 63+ assertions, ~10s
bash scripts/eval-bootstrap.sh        # end-to-end pipeline eval, ~1s
bash scripts/verify-models.sh         # model tier validation
bash scripts/check-references.sh      # cross-reference integrity
```

## Plugin install (alternative to bash install.sh)

```bash
qodercli plugin install .             # from the repo root
qodercli plugin install https://github.com/gxgeek/qoder-swarm.git
```

## Code style

- Hooks: Python, stdlib-only, fast path for non-matching tools
- Scripts: bash or Python, `set -euo pipefail`, `chmod +x`
- References: Markdown, cite source (project + file:line + license)
- Agents: Markdown with YAML frontmatter (`model:` must match `qodercli --list-models` case-sensitive)
- Commits: use structured trailers (Confidence / Scope-risk / Not-tested / Constraint / Rejected)

## Architecture invariants (do not break)

1. **I1**: One `swarm` skill as router → N reference docs (lazy-loaded)
2. **I2**: Model names in frontmatter must exactly match `qodercli --list-models`
3. **I3**: All state on disk under `.swarm/` (survives context compaction)
4. **I4**: Hook paths built dynamically from `QODER_HOME` (no hardcoded `~/.qoder/`)
5. **I5**: Legacy skill cleanup is marker-based + reversible (archive, not delete)

## Reporting issues

- Include `bash scripts/verify-models.sh` output
- Include `bash tests/smoke-test.sh 2>&1 | tail -10`
- Include Qoder CLI version: `~/.qoder/bin/qodercli/version.txt`
