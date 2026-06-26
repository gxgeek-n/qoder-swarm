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

# 5. Hook registration reminder
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  qoder-swarm installed successfully!"
echo ""
echo "  To enable hooks, add to ~/.qoder/settings.json:"
echo ""
echo '  "PostToolUse": [{'
echo '    "matcher": "Edit|Write",'
echo '    "hooks": [{"type":"command","command":"~/.qoder/hooks/swarm-comment-checker.sh","timeout":5}]'
echo '  }]'
echo ""
echo '  "Stop": [{'
echo '    "matcher": "*",'
echo '    "hooks": [{"type":"command","command":"~/.qoder/hooks/swarm-stop-continuation.sh","timeout":10}]'
echo '  }]'
echo ""
echo "  Available workflows:"
echo "    plan-and-review, five-agent-review, start-work,"
echo "    remove-ai-slops, init-deep, ultraresearch,"
echo "    debugging, teammode, ulw-loop"
echo ""
echo "  Usage in Qoder:"
echo '    Workflow({ name: "plan-and-review", args: { task: "..." } })'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
