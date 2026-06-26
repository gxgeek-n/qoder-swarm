# init-deep

Hierarchical AGENTS.md generator with dynamic explorer scaling.

## Step 1 — Measure project scale

Bash:
```bash
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' | wc -l
find . -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \) -not -path '*/node_modules/*' -exec wc -l {} + 2>/dev/null | tail -1
find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | awk -F/ '{print NF}' | sort -rn | head -1
find . -type f \( -name "AGENTS.md" -o -name "CLAUDE.md" \) -not -path '*/node_modules/*'
ls package.json Cargo.toml go.mod pyproject.toml requirements.txt pom.xml 2>/dev/null
```

Compute: `agentCount = min(4 + totalFiles/100 + (maxDepth>=4 ? 2 : 0) + max(0, languages.length-1), 12)`

## Step 2 — Parallel exploration (CHEAP × N)

Emit `agentCount` Agent calls in ONE message. Base 4 always:

```
Agent[structure]: "Map repo layout. Find non-standard patterns. Report deviations."
Agent[entry-points]: "Find main entry files. Trace execution flow."
Agent[conventions]: "Find config files (.eslintrc, pyproject.toml, .editorconfig). Report rules."
Agent[anti-patterns]: "Find DO NOT / NEVER / ALWAYS / DEPRECATED comments. List forbidden patterns."
```

Add more if agentCount > 4:
```
Agent[build-ci]: "Find .github/workflows, Makefile, deployment configs"
Agent[test-patterns]: "Find test infra, configs, structure"
Agent[hot-files]: "Files >500 lines — complexity hotspots"
Agent[shared-utils]: "Cross-cutting shared utilities"
Agent[api-surface]: "Exported functions/classes, public interface"
Agent[deps]: "Heavy/unusual imports, package deps"
Agent[security]: "Auth, validation, sanitization patterns"
Agent[data-layer]: "DB schemas, migrations, ORM models"
```

Each: `SCOPE: Read-only. DELIVERABLE: structured findings with file paths + one-line descriptions.`

## Step 3 — Score directories (CHEAP × 1)

```
Agent[scorer]:
TASK: Decide which directories need AGENTS.md
FINDINGS: {merged_exploration}
SCORING (weight × threshold):
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
DELIVERABLE: list of paths + score + reason
```

## Step 4 — Generate AGENTS.md (MID × 1)

```
Agent[generator]:
TASK: Write AGENTS.md for these locations
LOCATIONS: {scored_list}
EXPLORATION: {findings}

ROOT TEMPLATE (50-150 lines):
  # PROJECT KNOWLEDGE BASE
  ## OVERVIEW (1-2 sentences)
  ## STRUCTURE (non-obvious only)
  ## WHERE TO LOOK (task → location)
  ## CONVENTIONS (deviations from standard only)
  ## ANTI-PATTERNS (forbidden in THIS project)
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
  - Every claim grounded in exploration data
```

## Anti-patterns

- Static agent count (must scale)
- Sequential exploration (must parallel)
- Generic content
- Child repeating parent
