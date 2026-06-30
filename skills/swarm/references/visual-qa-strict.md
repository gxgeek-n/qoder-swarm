# visual-qa-strict

Strict visual verification: design-system real + CJK correct + no image-fakery.

## Prereqs

- `python3` + `Pillow` (`pip install Pillow`)
- Screenshot tool: Playwright / alijk-agent-browser / web-ux-screenshot skill
- Script at `<qoder-home>/scripts/image-diff.py` (installed alongside qoder-swarm; locate with `find ~/.qoder /opt -name image-diff.py 2>/dev/null`)

## Step 1 — Capture actual screenshot

If user gave URL but no actual screenshot: use available browser tooling, save to `/tmp/visual-qa-actual.png`.

## Step 2 — Pixel diff (Bash)

If reference image provided:
```bash
python3 <qoder-home>/scripts/image-diff.py {reference.png} {actual.png}
```
If qoder-swarm was installed to a non-default location, adjust the path. Run `find ~/.qoder /opt -name image-diff.py 2>/dev/null` to locate.

Capture JSON: `dimensionsMatch`, `diffRatio`, `similarityScore`, `alphaChannelIntact`, `hotspots[]`.

## Step 3 — Dual Oracle review IN PARALLEL (HEAVY × 2)

Emit TWO Agent calls in ONE message:

```
Agent[swarm-reviewer] HEAVY:
TASK: PASS A — design-system + functional integrity (read-only)
ASSUMPTION: Surface MAY BE FAKED until source proves otherwise
INTENT: {what user wanted}
SCREENSHOT: {actual_path}
REFERENCE: {reference_path or 'none'}
DIFF JSON: {script_output}
CHECK (BLOCKING if failed):
  1. Real design system vs ad-hoc/mock — read UI source, styles via design tokens or one-off hardcoded?
  2. Faked-with-image — real DOM/component tree, or pasted raster?
  3. Alpha — alphaChannelIntact, unexpected opaque/black fills?
  4. Code style / implementation quality
  5. Responsive across viewport sizes
  6. User-intended features actually work — trace code paths
DELIVERABLE:
  VERDICT: PASS | REVISE | FAIL
  CONFIDENCE: HIGH | MEDIUM | LOW
  FINDINGS: [dimension] [severity] what, where (file:line/region), concrete fix
  WHAT IS GOOD: must not regress
  BLOCKING: must fix (empty if PASS)

Agent[swarm-reviewer] HEAVY:
TASK: PASS B — visual fidelity + CJK precision (read-only)
INTENT: {what user wanted}
SCREENSHOT: {actual_path}
REFERENCE: {reference_path}
DIFF JSON: {script_output}
USE EVIDENCE:
  - diffRatio + similarityScore baseline
  - For each hotspot (gridX, gridY, x, y, w, h, diffRatio): inspect that region
  - Explain visual cause from pixels + source
CHECK:
  1. Match user intent: layout, spacing, color, type, alignment
  2. CJK precision:
     - Natural line breaking
     - Oversized headings with orphaned 1-char lines → FLAG
     - Split phrases ('오케스트 / 레이션' broken mid-word) → FLAG
     - Detached labels '[Image #1]' separated from content → FLAG
     - Clipped descenders / baselines → FLAG
     - Tofu (□ dropped glyphs) → FLAG
     - Font metric mismatch → FLAG
  3. Per-hotspot: what visually changed? intentional or regression?
DELIVERABLE:
  VERDICT: PASS | REVISE | FAIL
  EVIDENCE TRACE: each hotspot → visual cause
  FINDINGS: [severity] what, where, concrete fix
  BLOCKING: empty if PASS
```

## Step 4 — Synthesize (MID × 1)

```
Agent[swarm-planner]:
TASK: Merge Pass A + Pass B into ONE verdict
PASS A: {pass_a}
PASS B: {pass_b}
DIFF JSON: {diff_json}
RULES:
  - Either FAIL → overall FAIL
  - Both PASS → overall PASS
  - Else → REVISE
  - Deduplicate findings across passes
  - For each bad item: where + concrete fix
  - Call out what's good
DELIVERABLE:
  # Visual QA Report
  ## Overall Verdict: PASS | REVISE | FAIL
  ## Pass Summary (table)
  ## Key Diff Evidence (similarity, hotspots)
  ## Blocking Issues (deduplicated, located, with fix)
  ## What's Good (do not regress)
  ## Recommendations (prioritized)
```
