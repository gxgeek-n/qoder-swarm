# ultraresearch

Exhaustive research: parallel swarms + recursive lead chasing. NOT activated by ordinary questions — only explicit "deep research" / "ultraresearch" / "彻底研究".

## Different from built-in `deep-research`

Use this when you need EXHAUSTIVE coverage (recursive EXPAND loops). Use built-in `deep-research` for normal research tasks.

## Step 1 — Axis decomposition (CHEAP × 1)

```
Agent[axis-planner]:
TASK: Decompose research question into independent axes
QUESTION: {question}
DEFINITION: An axis = one angle pursuable independently
  Example "How does React Server Components work?" →
    Axis 1: Official React docs + RFC
    Axis 2: Implementation in Next.js source
    Axis 3: Community adoption patterns
    Axis 4: Performance vs traditional SSR
DELIVERABLE: 3-6 axes, each:
  - title: one-line
  - source_type: codebase | docs | oss | web | hybrid
  - key_queries: 2-3 starting queries
```

## Step 2 — Parallel research swarm (CHEAP × N)

Emit ONE Agent call per axis in ONE message:

```
Agent[research-{i}]:
TASK: Research axis EXHAUSTIVELY: {axis.title}
SOURCE: {axis.source_type}
QUERIES: {axis.key_queries}
RULES:
  - Multiple angles (don't repeat same query)
  - Codebase: grep, glob, read
  - Web/docs: WebSearch + WebFetch
  - OSS: clone shallow, read source
  - Every claim cites source (URL / path / SHA)
DELIVERABLE:
  ## Findings ({axis.title})
  - Finding: [claim] — Source: [citation]
  ## New Leads (warrant further investigation)
  - Lead: [what to investigate]
  ## Open Questions
```

## Step 3 — Recursive EXPAND (up to 3 waves)

For each wave:
1. Scan all findings for `Lead:` lines
2. Deduplicate. Take top 4 unprocessed leads
3. Emit 4 parallel Agent calls (CHEAP):

```
Agent[expand-{wave}-{i}]:
TASK: Investigate lead: {lead_text}
CONTEXT: This emerged researching {original_question}
DELIVERABLE:
  - Confirmed/Refuted/Inconclusive: [verdict]
  - Evidence: [citation]
  - New Leads: [or "none"]
```

Stop when: no new leads, OR max 3 waves, OR budget low.

## Step 4 — Synthesize (MID × 1)

```
Agent[synthesizer]:
TASK: Synthesize cited research report
QUESTION: {original_question}
FINDINGS: {all_findings_concatenated}
RULES:
  - Every claim cites source
  - Group by theme, not source
  - Confidence: HIGH (multi-source agree) / MEDIUM (single credible) / LOW (uncertain)
  - Surface contradictions explicitly
DELIVERABLE:
  # Research Report: {question}
  ## Key Findings
  ## Detailed Analysis (by theme)
  ## Contradictions & Disagreements
  ## Open Questions
  ## Sources (complete list)
```
