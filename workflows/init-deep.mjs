export const meta = {
  name: 'init-deep',
  description: 'Generate hierarchical AGENTS.md project memory. Dynamically scales agent count by project size. Scores directories for complexity and generates context files where needed.',
  whenToUse: 'When user says "init-deep", "generate project memory", "create AGENTS.md", or opens a new large codebase.',
  phases: [
    { title: 'Discover', detail: 'Parallel exploration scaled by project size' },
    { title: 'Score', detail: 'Rate directories for AGENTS.md placement' },
    { title: 'Generate', detail: 'Write AGENTS.md files' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      maxDepth: { type: 'number', description: 'Max directory depth (default 3)' },
      createNew: { type: 'boolean', description: 'Delete existing and regenerate from scratch' },
    },
  },
}

const CHEAP = 'Qwen3.7-Max-DogFooding'
const MID   = 'GLM-5.2'
const maxDepth = args.maxDepth || 3
const createNew = args.createNew || false

// Phase 1: Discovery - scale agents by project size
phase('Discover')
log('Measuring project scale...')

const projectInfo = await agent(`TASK: Measure this project's scale and report metrics.

Run these commands:
1. find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' | wc -l
2. find . -type f \\( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \\) -not -path '*/node_modules/*' -exec wc -l {} + 2>/dev/null | tail -1
3. find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | awk -F/ '{print NF}' | sort -rn | head -1
4. find . -type f -name "AGENTS.md" -o -name "CLAUDE.md" | head -10
5. ls package.json Cargo.toml go.mod pyproject.toml requirements.txt pom.xml 2>/dev/null

DELIVERABLE: JSON with: totalFiles, totalLines, maxDepth, languages[], existingAgentsMd[], packageManager
SCOPE: Read-only.`, {
  label: 'project-measurer',
  phase: 'Discover',
  model: CHEAP,
  schema: {
    type: 'object',
    properties: {
      totalFiles: { type: 'number' },
      totalLines: { type: 'number' },
      maxDepth: { type: 'number' },
      languages: { type: 'array', items: { type: 'string' } },
      existingAgentsMd: { type: 'array', items: { type: 'string' } },
    },
  },
})

// Dynamic agent count based on project scale
const baseAgents = 4
const extraByFiles = Math.floor((projectInfo.totalFiles || 0) / 100)
const extraByDepth = (projectInfo.maxDepth || 0) >= 4 ? 2 : 0
const extraByLangs = Math.max(0, (projectInfo.languages || []).length - 1)
const agentCount = Math.min(baseAgents + extraByFiles + extraByDepth + extraByLangs, 12)

log(`Project: ${projectInfo.totalFiles} files, ${projectInfo.totalLines} lines, depth ${projectInfo.maxDepth}. Spawning ${agentCount} explorers.`)

// Build explorer prompts dynamically
const explorerTasks = [
  'Project structure: map layout, find non-standard patterns, report deviations',
  'Entry points: find main files, trace execution flow, report organization',
  'Conventions: find config files (.eslintrc, pyproject.toml, .editorconfig), report rules',
  'Anti-patterns: find DO NOT / NEVER / ALWAYS / DEPRECATED comments, list forbidden patterns',
]

if (agentCount > 4) explorerTasks.push('Build/CI: find workflows, Makefile, report non-standard patterns')
if (agentCount > 5) explorerTasks.push('Test patterns: find test configs/structure, report conventions')
if (agentCount > 6) explorerTasks.push('Large files >500 lines: find complexity hotspots')
if (agentCount > 7) explorerTasks.push('Cross-cutting concerns: find shared utilities across directories')
if (agentCount > 8) explorerTasks.push('API surface: find exported functions/classes, report public interface')
if (agentCount > 9) explorerTasks.push('Dependencies: analyze package deps, find unusual or heavy imports')
if (agentCount > 10) explorerTasks.push('Security patterns: find auth, validation, sanitization code')
if (agentCount > 11) explorerTasks.push('Data layer: find DB schemas, migrations, ORM models')

const explorerResults = await parallel(
  explorerTasks.map((task, i) => () => agent(`TASK: ${task}

DELIVERABLE: Structured findings with file paths and one-line descriptions.
SCOPE: Read-only. Never edit files.`, {
    label: `explorer-${i}`,
    phase: 'Discover',
    model: CHEAP,
  }))
)

// Phase 2: Score directories
phase('Score')
log('Scoring directories for AGENTS.md placement...')

const scoring = await agent(`TASK: Based on these exploration findings, decide which directories need their own AGENTS.md.

FINDINGS:
${explorerResults.filter(Boolean).join('\n\n---\n\n')}

SCORING MATRIX (weight × threshold):
- File count (3x): >20 files = high
- Subdir count (2x): >5 subdirs = high
- Code ratio (2x): >70% code files = high
- Unique patterns (1x): has own config = high
- Module boundary (2x): has index.ts/__init__.py = high

DECISION:
- Score >15: CREATE AGENTS.md
- Score 8-15: CREATE if distinct domain
- Score <8: SKIP (parent covers it)
- Root (.): ALWAYS create

Max depth: ${maxDepth}

DELIVERABLE: List of paths that need AGENTS.md, with score and reason.
FORMAT: One per line: path | score | reason`, {
  label: 'directory-scorer',
  phase: 'Score',
  model: CHEAP,
})

// Phase 3: Generate AGENTS.md files
phase('Generate')
log('Generating AGENTS.md files...')

const locations = scoring.trim().split('\n').filter(l => l.includes('|'))

await agent(`TASK: Generate AGENTS.md files for these locations.

LOCATIONS:
${scoring}

EXPLORATION DATA:
${explorerResults.filter(Boolean).slice(0, 5).join('\n\n---\n\n')}

${createNew ? 'MODE: Delete existing AGENTS.md files first, then regenerate.' : 'MODE: Update existing, create new where warranted.'}

ROOT AGENTS.md TEMPLATE (50-150 lines):
# PROJECT KNOWLEDGE BASE
## OVERVIEW (1-2 sentences)
## STRUCTURE (tree, non-obvious purposes only)
## WHERE TO LOOK (task→location table)
## CONVENTIONS (ONLY deviations from standard)
## ANTI-PATTERNS (THIS PROJECT) (explicitly forbidden)
## COMMANDS (dev/test/build)

SUBDIRECTORY AGENTS.md (30-80 lines):
## OVERVIEW (1 line)
## WHERE TO LOOK
## CONVENTIONS (if different from parent)

RULES:
- No generic advice that applies to all projects
- No obvious information
- Child never repeats parent content
- Telegraphic style
- Every claim must be grounded in the exploration data above`, {
  label: 'generator',
  phase: 'Generate',
  model: MID,
})

log(`Generated AGENTS.md for ${locations.length} locations.`)
