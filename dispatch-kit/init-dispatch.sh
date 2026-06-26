#!/bin/bash
# Initialize .dispatch/ directory in the current project
# Usage: bash init-dispatch.sh [project-root]

ROOT="${1:-.}"

mkdir -p "$ROOT/.dispatch/inbox"
mkdir -p "$ROOT/.dispatch/outbox"
mkdir -p "$ROOT/.dispatch/log"

# Copy registry template
if [ ! -f "$ROOT/.dispatch/registry.yml" ]; then
  cat > "$ROOT/.dispatch/registry.yml" << 'EOF'
project:
  name: "my-project"
  root: "."

controller:
  role: controller
  session_hint: "Terminal 1 - orchestration only"

workers:
  - role: impl
    inbox: .dispatch/inbox/impl.md
    outbox: .dispatch/outbox/impl.md
    allowed_tasks: [feature, bugfix, refactor]

  - role: test
    inbox: .dispatch/inbox/test.md
    outbox: .dispatch/outbox/test.md
    allowed_tasks: [unit_test, integration_test, e2e]

  - role: docs
    inbox: .dispatch/inbox/docs.md
    outbox: .dispatch/outbox/docs.md
    allowed_tasks: [readme, api_docs, changelog]

safety:
  auto_dispatch: [status_query, task_handoff, evidence_handoff]
  require_confirmation: [publish, deploy, delete, force_push]
EOF
  echo "Created $ROOT/.dispatch/registry.yml"
fi

# Create .gitignore for dispatch state
cat > "$ROOT/.dispatch/.gitignore" << 'EOF'
inbox/
outbox/
log/
EOF

echo "Dispatch protocol initialized at $ROOT/.dispatch/"
echo ""
echo "Usage:"
echo "  Terminal 1 (controller): qoder  # orchestrate, read outbox, write inbox"
echo "  Terminal 2 (impl):       qoder  # read inbox/impl.md, write outbox/impl.md"
echo "  Terminal 3 (test):       qoder  # read inbox/test.md, write outbox/test.md"
