#!/bin/bash
# comment-checker hook: after any Edit/Write tool call, remind to check for AI slop comments
# Install: add to PostToolUse hooks in settings.json with matcher "Edit|Write"

TOOL_NAME="${QODER_TOOL_NAME:-}"

# Only trigger on file-editing tools
case "$TOOL_NAME" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

# Output a gentle reminder as hook feedback
cat << 'EOF'
[swarm:comment-checker] File modified. Quick self-check:
- No "obvious" comments restating code?
- No TODO/FIXME without ticket reference?
- No commented-out dead code?
- No AI-style section dividers (// ===== Section =====)?
EOF

exit 0
