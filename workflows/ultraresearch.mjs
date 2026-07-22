export const meta = {
  name: 'ultraresearch',
  description: 'Maximum-saturation research: parallel explorer+librarian swarms, recursive EXPAND loop chasing leads until convergence, empirical verification, cited synthesis.',
  whenToUse: 'When user explicitly says "ultraresearch", "deep research", "research this thoroughly", or needs exhaustive multi-source investigation.',
  phases: [
    { title: 'Axes', detail: 'Decompose question into research axes' },
    { title: 'Swarm', detail: 'Parallel research per axis' },
    { title: 'Expand', detail: 'Chase new leads recursively' },
    { title: 'Synthesize', detail: 'Cited report with verified claims' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      question: { type: 'string', description: 'Research question' },
      maxWaves: { type: 'number', description: 'Max expansion waves (default 3)' },
    },
    required: ['question'],
  },
}

const CHEAP = 'Peach-07-17-DogFooding'
const MID   = 'GLM-5.2'
const question = args.question
const maxWaves = args.maxWaves || 3

// Phase 1: Decompose into research axes
phase('Axes')
log(`Decomposing: ${question}`)

const axes = await agent(`TASK: Decompose this research question into independent research axes.

QUESTION: ${question}

An axis is one angle of investigation that can be pursued independently.
Example: "How does React Server Components work?" →
- Axis 1: Official React docs and RFC
- Axis 2: Implementation in Next.js source code
- Axis 3: Community adoption patterns and gotchas
- Axis 4: Performance benchmarks vs traditional SSR

DELIVERABLE: 3-6 axes, each with:
- title: one-line description
- source_type: "codebase" | "docs" | "oss" | "web" | "hybrid"
- key_queries: 2-3 specific search queries to start with`, {
  label: 'axis-planner',
  phase: 'Axes',
  model: CHEAP,
  schema: {
    type: 'object',
    properties: {
      axes: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            title: { type: 'string' },
            source_type: { type: 'string' },
            key_queries: { type: 'array', items: { type: 'string' } },
          },
          required: ['title', 'source_type', 'key_queries'],
        },
      },
    },
    required: ['axes'],
  },
})

if (!axes || !axes.axes || axes.axes.length === 0) {
  log('ERROR: Could not decompose question into axes.')
  return
}

log(`Identified ${axes.axes.length} research axes.`)

// Phase 2: Parallel swarm - one agent per axis
phase('Swarm')
log(`Launching ${axes.axes.length} researchers in parallel...`)

let allFindings = await parallel(
  axes.axes.map((axis, i) => () => agent(`TASK: Research this axis exhaustively.

AXIS: ${axis.title}
SOURCE TYPE: ${axis.source_type}
STARTING QUERIES: ${axis.key_queries.join(', ')}

RULES:
- Search multiple angles (not the same query twice)
- For codebase: use grep, glob, read files
- For docs/web: use web search
- For OSS: clone shallow and read source
- Every claim must cite a source (URL, file path, or commit SHA)
- When sources disagree, surface the disagreement explicitly

DELIVERABLE:
## Findings (${axis.title})
- Finding 1: [claim] — Source: [citation]
- Finding 2: [claim] — Source: [citation]
...
## New Leads (things found that warrant further investigation)
- Lead: [what to investigate next]
## Open Questions
- [what remains unknown]`, {
    label: `researcher-${i}`,
    phase: 'Swarm',
    model: axis.source_type === 'codebase' ? MID : CHEAP,
  }))
)

// Phase 3: Recursive EXPAND loop - chase new leads
phase('Expand')

for (let wave = 0; wave < maxWaves; wave++) {
  const leadsText = allFindings.filter(Boolean).join('\n')
  const leadMatches = leadsText.match(/Lead:.*$/gm)

  if (!leadMatches || leadMatches.length === 0) {
    log(`Wave ${wave + 1}: no new leads. Converged.`)
    break
  }

  const uniqueLeads = [...new Set(leadMatches)].slice(0, 4)
  log(`Wave ${wave + 1}: chasing ${uniqueLeads.length} leads...`)

  const expandResults = await parallel(
    uniqueLeads.map((lead, i) => () => agent(`TASK: Investigate this lead from prior research.

LEAD: ${lead}
PRIOR CONTEXT: This emerged during research on: ${question}

Search for evidence. Confirm or refute. Cite sources.
Report NEW leads if you find more threads to pull.

DELIVERABLE:
- Confirmed/Refuted/Inconclusive: [verdict]
- Evidence: [citation]
- New Leads: [or "none"]`, {
      label: `expand-${wave}-${i}`,
      phase: 'Expand',
      model: CHEAP,
    }))
  )

  allFindings = allFindings.concat(expandResults)
}

// Phase 4: Synthesize cited report
phase('Synthesize')
log('Synthesizing final report...')

const report = await agent(`TASK: Synthesize a comprehensive research report from all findings.

ORIGINAL QUESTION: ${question}

ALL FINDINGS (${allFindings.filter(Boolean).length} sources):
${allFindings.filter(Boolean).join('\n\n---\n\n')}

RULES:
- Every claim must have a citation (URL, file path, or commit)
- Group by theme, not by source
- Mark confidence: HIGH (multiple sources agree), MEDIUM (single credible source), LOW (uncertain)
- Surface contradictions between sources explicitly
- End with "Open Questions" for anything unresolved

FORMAT:
# Research Report: ${question}
## Key Findings
## Detailed Analysis (by theme)
## Contradictions & Disagreements
## Open Questions
## Sources (complete citation list)`, {
  label: 'synthesizer',
  phase: 'Synthesize',
  model: MID,
})

log('Research complete.')
