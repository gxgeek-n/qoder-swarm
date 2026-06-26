#!/bin/bash
# qoder-swarm installer
# Usage: bash install.sh [qoder-home]
#
# Installs workflows, hooks, and dispatch-kit into Qoder's config directory.

set -e

QODER_HOME="${1:-$HOME/.qoder}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing qoder-swarm into: $QODER_HOME"

# 1. Workflows
mkdir -p "$QODER_HOME/workflows"
cp "$SCRIPT_DIR/workflows/"*.mjs "$QODER_HOME/workflows/"
cp "$SCRIPT_DIR/workflows/README.md" "$QODER_HOME/workflows/"
echo "  ✓ Workflows installed ($(ls "$SCRIPT_DIR/workflows/"*.mjs | wc -l | tr -d ' ') files)"

# 2. Hooks
mkdir -p "$QODER_HOME/hooks"
cp "$SCRIPT_DIR/hooks/"*.sh "$QODER_HOME/hooks/"
chmod +x "$QODER_HOME/hooks/swarm-"*.sh
echo "  ✓ Hooks installed"

# 3. Dispatch kit
mkdir -p "$QODER_HOME/dispatch-kit/templates"
cp "$SCRIPT_DIR/dispatch-kit/registry.yml" "$QODER_HOME/dispatch-kit/"
cp "$SCRIPT_DIR/dispatch-kit/README.md" "$QODER_HOME/dispatch-kit/"
cp "$SCRIPT_DIR/dispatch-kit/init-dispatch.sh" "$QODER_HOME/dispatch-kit/"
cp "$SCRIPT_DIR/dispatch-kit/templates/"* "$QODER_HOME/dispatch-kit/templates/"
chmod +x "$QODER_HOME/dispatch-kit/init-dispatch.sh"
echo "  ✓ Dispatch kit installed"

# 4. Scripts (image-diff, etc.)
mkdir -p "$QODER_HOME/scripts"
cp "$SCRIPT_DIR/scripts/"*.py "$QODER_HOME/scripts/" 2>/dev/null || true
chmod +x "$QODER_HOME/scripts/"*.py 2>/dev/null || true
echo "  ✓ Scripts installed"

# 5. Skills (auto-triggered by description matching - PRIMARY mechanism)
mkdir -p "$QODER_HOME/skills/swarm"
# Clean any stale per-pattern skills from older installs
for old in plan-and-review five-agent-review start-work remove-ai-slops init-deep ultraresearch debugging teammode ulw-loop visual-qa-strict; do
  rm -rf "$QODER_HOME/skills/$old" 2>/dev/null
done
cp -r "$SCRIPT_DIR/skills/swarm/"* "$QODER_HOME/skills/swarm/"
echo "  ✓ Skill installed: swarm (1 router + $(ls "$SCRIPT_DIR/skills/swarm/references/" | wc -l | tr -d ' ') reference docs)"

# 6. Custom subagents (real model tiering via each agent's frontmatter model: field)
mkdir -p "$QODER_HOME/agents"
AGENT_COUNT=0
for agent_file in "$SCRIPT_DIR/agents/"swarm-*.md; do
  [ -f "$agent_file" ] || continue
  cp "$agent_file" "$QODER_HOME/agents/"
  AGENT_COUNT=$((AGENT_COUNT + 1))
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
echo "  To uninstall hooks later:"
echo "    python3 $SCRIPT_DIR/install-settings.py --uninstall"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
