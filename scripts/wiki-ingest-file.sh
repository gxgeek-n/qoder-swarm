#!/usr/bin/env bash
# scripts/wiki-ingest-file.sh — Ingest a single .md file into obsidian-wiki vault.
# Usage: scripts/wiki-ingest-file.sh <source.md> <vault-path> [category]
# Categories: references (default), synthesis, projects, concepts
set -euo pipefail

SOURCE="${1:?usage: wiki-ingest-file.sh <source.md> <vault-path> [category]}"
VAULT="${2:?usage: wiki-ingest-file.sh <source.md> <vault-path> [category]}"
CATEGORY="${3:-references}"

[ -f "$SOURCE" ] || { echo "source not found: $SOURCE" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "vault not found: $VAULT" >&2; exit 1; }

# Extract title from first heading or filename
TITLE=$(grep -m1 "^# " "$SOURCE" | sed 's/^# //' || basename "$SOURCE" .md)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)
DATE=$(date +%Y-%m-%d)
TARGET="$VAULT/$CATEGORY/${DATE}-${SLUG}.md"

mkdir -p "$VAULT/$CATEGORY"

# Write with frontmatter
cat > "$TARGET" <<EOF
---
title: $TITLE
date: $DATE
source: $SOURCE
confidence: HIGH
last_confirmed: $DATE
tags: [swarm, auto-ingested]
---

EOF
cat "$SOURCE" >> "$TARGET"

# Update index.md
echo "- [[$CATEGORY/${DATE}-${SLUG}]] — $TITLE (auto-ingested $DATE)" >> "$VAULT/index.md"

# Update log.md
echo "## [$DATE] ingest | $TITLE" >> "$VAULT/log.md"
echo "- Source: $SOURCE" >> "$VAULT/log.md"
echo "- Target: $TARGET" >> "$VAULT/log.md"
echo "" >> "$VAULT/log.md"

echo "wiki-ingest: $SOURCE → $TARGET"
