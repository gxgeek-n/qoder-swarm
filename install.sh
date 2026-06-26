#!/bin/bash
# qoder-swarm installer
# Usage: bash install.sh [QODER_HOME]
#   QODER_HOME defaults to $HOME/.qoder
#
# Installs workflows, hooks, dispatch-kit, scripts, skills, and custom
# subagents into Qoder's config directory, then registers hooks in
# settings.json.

set -euo pipefail
shopt -s nullglob

usage() {
  cat <<'EOF'
qoder-swarm installer

Usage:
  bash install.sh [QODER_HOME]

Positional arg:
  QODER_HOME    Target Qoder config dir (default: $HOME/.qoder)

Other commands:
  bash install.sh --help, -h           Show this message
  bash install.sh --version, -V        Show version
  bash install.sh --doctor             Check runtime prerequisites
  python3 install-settings.py --uninstall   Remove the registered hooks
EOF
}

doctor() {
  echo "qoder-swarm doctor"
  echo ""
  printf "  python3:    "
  if command -v python3 >/dev/null 2>&1; then
    python3 --version
  else
    echo "MISSING — required for hook registration and image-diff.py"
  fi

  printf "  Pillow:     "
  if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
    python3 -c "import PIL; print(PIL.__version__)"
  else
    echo "MISSING — required for visual-qa-strict workflow (pip install Pillow)"
  fi

  printf "  git:        "
  if command -v git >/dev/null 2>&1; then
    git --version | head -1
  else
    echo "MISSING — required for swarm-worker worktree isolation"
  fi

  printf "  qodercli:   "
  if command -v qodercli >/dev/null 2>&1; then
    qodercli --version 2>/dev/null || echo "installed (version unknown)"
  else
    echo "MISSING — qoder-swarm is for Qoder CLI; install via https://qoder.com/install"
  fi
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -V|--version) echo "qoder-swarm 0.1.0"; exit 0 ;;
  --doctor) doctor; exit 0 ;;
  -*)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac

QODER_HOME="${1:-$HOME/.qoder}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Marker file written into every directory we create so future re-installs
# can safely clean up without touching user content with the same name.
SWARM_MARKER=".swarm-installed"

echo "Installing qoder-swarm into: $QODER_HOME"

# 1. Workflows
mkdir -p "$QODER_HOME/workflows"
for f in "$SCRIPT_DIR/workflows/"*.mjs; do
  cp "$f" "$QODER_HOME/workflows/"
done
[ -f "$SCRIPT_DIR/workflows/README.md" ] && cp "$SCRIPT_DIR/workflows/README.md" "$QODER_HOME/workflows/"
WF_COUNT=0
for _ in "$SCRIPT_DIR/workflows/"*.mjs; do WF_COUNT=$((WF_COUNT+1)); done
echo "  ✓ Workflows installed ($WF_COUNT files)"

# 2. Hooks
mkdir -p "$QODER_HOME/hooks"
HOOK_COUNT=0
for f in "$SCRIPT_DIR/hooks/swarm-"*.sh; do
  cp "$f" "$QODER_HOME/hooks/"
  chmod +x "$QODER_HOME/hooks/$(basename "$f")"
  HOOK_COUNT=$((HOOK_COUNT+1))
done
echo "  ✓ Hooks installed ($HOOK_COUNT files)"

# 3. Dispatch kit
mkdir -p "$QODER_HOME/dispatch-kit/templates"
cp "$SCRIPT_DIR/dispatch-kit/registry.yml" "$QODER_HOME/dispatch-kit/"
cp "$SCRIPT_DIR/dispatch-kit/README.md" "$QODER_HOME/dispatch-kit/"
cp "$SCRIPT_DIR/dispatch-kit/init-dispatch.sh" "$QODER_HOME/dispatch-kit/"
for f in "$SCRIPT_DIR/dispatch-kit/templates/"*; do
  cp "$f" "$QODER_HOME/dispatch-kit/templates/"
done
chmod +x "$QODER_HOME/dispatch-kit/init-dispatch.sh"
echo "  ✓ Dispatch kit installed"

# 4. Scripts (image-diff, etc.)
mkdir -p "$QODER_HOME/scripts"
SCRIPT_COUNT=0
for f in "$SCRIPT_DIR/scripts/"*.py; do
  cp "$f" "$QODER_HOME/scripts/"
  chmod +x "$QODER_HOME/scripts/$(basename "$f")"
  SCRIPT_COUNT=$((SCRIPT_COUNT+1))
done
echo "  ✓ Scripts installed ($SCRIPT_COUNT files)"

# 5. Skill — primary entry mechanism (auto-triggered by description matching)
mkdir -p "$QODER_HOME/skills/swarm"

# Clean any stale per-pattern skill directories from PRE-934a74e installs.
# Only remove a directory if it carries the swarm marker we wrote during a
# previous install — this protects user-created skills that happen to share
# a name with one of our legacy patterns.
LEGACY_SKILLS="plan-and-review five-agent-review start-work remove-ai-slops init-deep ultraresearch debugging teammode ulw-loop visual-qa-strict"
for old in $LEGACY_SKILLS; do
  old_dir="$QODER_HOME/skills/$old"
  if [ -d "$old_dir" ] && [ -f "$old_dir/$SWARM_MARKER" ]; then
    rm -rf "$old_dir"
  elif [ -d "$old_dir" ]; then
    echo "  ⚠ Found $old_dir without swarm marker — leaving alone (likely user-owned)"
  fi
done

cp -r "$SCRIPT_DIR/skills/swarm/"* "$QODER_HOME/skills/swarm/"
touch "$QODER_HOME/skills/swarm/$SWARM_MARKER"
REF_COUNT=0
for _ in "$SCRIPT_DIR/skills/swarm/references/"*.md; do REF_COUNT=$((REF_COUNT+1)); done
echo "  ✓ Skill installed: swarm (1 router + $REF_COUNT reference docs)"

# 6. Custom subagents — real per-role model tiering via frontmatter
mkdir -p "$QODER_HOME/agents"
AGENT_COUNT=0
for agent_file in "$SCRIPT_DIR/agents/"swarm-*.md; do
  cp "$agent_file" "$QODER_HOME/agents/"
  AGENT_COUNT=$((AGENT_COUNT+1))
done
echo "  ✓ Subagents installed: $AGENT_COUNT swarm-* (explorer/librarian/planner/reviewer/worker)"

# 7. Auto-register hooks into settings.json (idempotent, with backup)
echo ""
if command -v python3 >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/install-settings.py" --qoder-home "$QODER_HOME"
else
  echo "  ⚠ python3 not found — skipping automatic hook registration."
  echo "    Manually add hooks to $QODER_HOME/settings.json (see README)."
fi

# 8. Soft-check optional Python deps
echo ""
if command -v python3 >/dev/null 2>&1 && ! python3 -c "import PIL" 2>/dev/null; then
  echo "  ⚠ Pillow not installed — the visual-qa-strict workflow will fail."
  echo "    Install with: pip3 install Pillow"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  qoder-swarm installed successfully!"
echo ""
echo "  Primary entry — the 'swarm' Skill (works on all accounts):"
echo "    Just talk naturally in Qoder. Triggers like '规划/审查/调试/"
echo "    深度研究/清理AI代码/视觉验证/团队模式' auto-activate swarm."
echo ""
echo "  10 orchestration patterns inside swarm:"
echo "    plan-and-review, five-agent-review, start-work,"
echo "    remove-ai-slops, init-deep, ultraresearch,"
echo "    debugging, teammode, ulw-loop, visual-qa-strict"
echo ""
echo "  Advanced — direct Workflow() calls (only if your account has"
echo "  the Workflow tool feature flag enabled):"
echo '    Workflow({ name: "plan-and-review", args: { task: "..." } })'
echo ""
echo "  Run 'bash install.sh --doctor' anytime to check prerequisites."
echo "  To uninstall hooks: python3 $SCRIPT_DIR/install-settings.py --uninstall"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
