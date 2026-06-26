---
name: ultraresearch
description: "Maximum-saturation research with parallel swarms and recursive lead expansion. Use when user explicitly says 'ultraresearch', 'deep research', 'research this thoroughly', '深度研究', '彻底研究'. Decomposes question into research axes, spawns parallel researchers, recursively chases new leads until convergence, synthesizes cited report. Different from built-in deep-research: this one does aggressive recursive EXPAND loops."
---

# ultraresearch

Exhaustive research orchestration. Parallel swarms + recursive lead chasing.

## When to activate

User explicitly says:
- "ultraresearch" / "deep research"
- "research this thoroughly" / "exhaustive investigation"
- "深度研究" / "彻底研究" / "详细研究"

NOT activated by ordinary questions or debugging context-gathering.

## How to execute

### Step 1 — Decompose into research axes

ONE `Agent` call (CHEAP model):
```
prompt: "Decompose this question into independent research axes.
QUESTION: {question}

An axis = one angle that can be pursued independently.
Example 'How does React Server Components work?' →
- Axis 1: Official React docs + RFC
- Axis 2: Implementation in Next.js source
- Axis 3: Community adoption patterns
- Axis 4: Performance vs traditional SSR

DELIVERABLE: 3-6 axes, each:
- title: one-line
- source_type: codebase | docs | oss | web | hybrid
- key_queries: 2-3 starting queries"
```

### Step 2 — Parallel research swarm

Emit ONE `Agent` call per axis IN A SINGLE MESSAGE:
```
For each axis:
  Agent({
    description: "Research: {axis.title}",
    prompt: "Research this axis EXHAUSTIVELY.
AXIS: {axis.title}
SOURCE TYPE: {axis.source_type}
STARTING QUERIES: {axis.key_queries}

RULES:
- Multiple angles (don't repeat same query)
- Codebase: grep, glob, read
- Web/docs: WebSearch + WebFetch
- OSS: clone shallow, read source
- Every claim cites source (URL, file path, SHA)
- Surface disagreements between sources

DELIVERABLE:
## Findings ({axis.title})
- Finding: [claim] — Source: [citation]
## New Leads (warrant further investigation)
- Lead: [what to investigate]
## Open Questions"
  })
```

### Step 3 — Recursive EXPAND loop (up to 3 waves)

For each wave:
1. Scan all findings for "Lead:" entries
2. Dedupe, take top 4 unprocessed leads
3. Spawn 4 parallel `Agent` calls to chase them
4. Each lead-chaser reports: Confirmed/Refuted/Inconclusive + evidence + new leads

Stop when no new leads or max waves reached.

### Step 4 — Synthesize cited report

ONE `Agent` call (MID model):
```
prompt: "Synthesize research report from all findings.
QUESTION: {original_question}
FINDINGS ({n} sources): {all_findings_concatenated}

RULES:
- Every claim cites source
- Group by theme, not source
- Confidence: HIGH (multiple agree) / MEDIUM (single credible) / LOW (uncertain)
- Surface contradictions explicitly

FORMAT:
# Research Report: {question}
## Key Findings
## Detailed Analysis (by theme)
## Contradictions & Disagreements
## Open Questions
## Sources (complete list)"
```

## Difference from Qoder built-in `deep-research`

| Aspect | This skill | Built-in deep-research |
|--------|-----------|------------------------|
| Lead chasing | Recursive EXPAND loop (up to 3 waves) | Single fan-out |
| Axis decomposition | Explicit upfront | Implicit |
| Convergence | Stops when no new leads | Fixed depth |
| Verification | Citation-based | Adversarial agent |

Use this one when you need EXHAUSTIVE coverage. Use built-in `deep-research` for normal research.

## Model tiers

| Stage | Model |
|-------|-------|
| Axis planner | `Qwen3.7-Max-DogFooding` (CHEAP) |
| Researchers | `Qwen3.7-Max-DogFooding` (CHEAP, parallel) |
| Synthesizer | `GLM-5.2` (MID, integration logic) |
