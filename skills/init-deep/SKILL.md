---
name: init-deep
description: "Generate hierarchical AGENTS.md project memory with dynamic agent scaling. Use when user says 'init-deep', 'generate project memory', 'create AGENTS.md', '生成项目记忆', '初始化项目', or opens a new large codebase. Scales explorer count by project size (file count, depth, languages). Scores directories for AGENTS.md placement."
---

# init-deep

Hierarchical project memory generator. Spawns explorers proportional to project size.

## When to activate

User mentions: "init-deep" / "generate project memory" / "create AGENTS.md" / "项目记忆" / "初始化项目"

## How to execute

### Step 1 — Measure project scale

Run via Bash:
```bash
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' | wc -l
find . -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \) -not -path '*/node_modules/*' -exec wc -l {} + 2>/dev/null | tail -1
find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | awk -F/ '{print NF}' | sort -rn | head -1
find . -type f \( -name "AGENTS.md" -o -name "CLAUDE.md" \) -not -path '*/node_modules/*'
ls package.json Cargo.toml go.mod pyproject.toml requirements.txt pom.xml 2>/dev/null
```

Get: totalFiles, totalLines, maxDepth, languages, existingAgentsMd, packageManager.

### Step 2 — Compute dynamic agent count

```
base = 4
extras = (totalFiles / 100) + (maxDepth >= 4 ? 2 : 0) + max(0, languages.length - 1)
agentCount = min(base + extras, 12)
```

### Step 3 — Launch explorers IN PARALLEL

Emit `agentCount` `Agent` calls in ONE message. Each tackles one dimension:

Base 4 (always):
1. "Project structure: map layout, find non-standard patterns"
2. "Entry points: find main files, trace execution flow"
3. "Conventions: find config files (.eslintrc, pyproject.toml), report rules"
4. "Anti-patterns: find DO NOT/NEVER/ALWAYS/DEPRECATED comments"

Extra (added based on scale):
5. "Build/CI: workflows, Makefile, deployment configs"
6. "Test patterns: test configs and structure"
7. "Large files >500 lines: complexity hotspots"
8. "Cross-cutting concerns: shared utilities"
9. "API surface: exported functions/classes"
10. "Dependencies: heavy/unusual imports"
11. "Security patterns: auth, validation"
12. "Data layer: DB schemas, migrations, ORMs"

Each agent uses `CHEAP` model (FREE Qwen), read-only.

### Step 4 — Score directories

ONE `Agent` call:
```
prompt: "Based on these exploration findings, decide which directories need AGENTS.md.

FINDINGS: {merged_explorer_output}

SCORING:
- File count (3x): >20 = high
- Subdir count (2x): >5 = high
- Code ratio (2x): >70% = high
- Unique patterns (1x): own config = high
- Module boundary (2x): index.ts/__init__.py = high

DECISION:
- Score >15: CREATE
- 8-15: CREATE if distinct domain
- <8: SKIP
- Root (.): ALWAYS create

DELIVERABLE: List paths + score + reason"
```

### Step 5 — Generate AGENTS.md files

ONE `Agent` call (or one per file if many):
```
prompt: "Generate AGENTS.md for these locations: {scoring}

Use exploration data: {findings}

ROOT TEMPLATE (50-150 lines):
# PROJECT KNOWLEDGE BASE
## OVERVIEW (1-2 sentences)
## STRUCTURE (non-obvious only)
## WHERE TO LOOK (task→location)
## CONVENTIONS (deviations from standard only)
## ANTI-PATTERNS (forbidden in this project)
## COMMANDS (dev/test/build)

SUBDIR TEMPLATE (30-80 lines):
## OVERVIEW (1 line)
## WHERE TO LOOK
## CONVENTIONS (if different from parent)

RULES:
- No generic advice
- No obvious info
- Child never repeats parent
- Telegraphic style
- Every claim grounded in exploration data"
```

## Anti-patterns

- Static agent count (must scale by size)
- Sequential execution (must parallel)
- Ignoring existing AGENTS.md
- Over-documenting (not every dir needs one)
- Generic content
