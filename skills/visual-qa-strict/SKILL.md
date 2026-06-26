---
name: visual-qa-strict
description: "Strict visual QA with pixel diff + dual oracle review. Use when user says 'visual QA', 'screenshot diff', 'pixel diff', 'is this a real design system or an image', 'CJK text wrapping', 'alpha breakage', '视觉验证', '截图对比', '设计稿对比'. Detects fake UIs (image stand-ins, hardcoded styles), CJK precision issues (broken line wrapping, glyph drops, tofu), alpha channel violations."
---

# visual-qa-strict

Strict visual verification: not just "looks ok" but "is real design system + CJK correct + no fakery".

## When to activate

User mentions:
- "visual QA" / "screenshot diff" / "pixel diff"
- "is this a real design system or an image"
- "CJK text wrapping" / "alpha breakage"
- "视觉验证" / "截图对比" / "设计稿对比"

## How to execute

### Step 1 — Capture actual screenshot

If user gave a URL but no actual screenshot, use Playwright via available browser tooling (web-ux-screenshot skill, alijk-agent-browser, or playwright-cli). Save to `/tmp/visual-qa-actual.png`.

### Step 2 — Run pixel diff script

If user provided a reference image, run via Bash:
```bash
python3 ~/.qoder/scripts/image-diff.py {reference.png} {actual.png}
```

Capture JSON output: `dimensionsMatch`, `diffRatio`, `similarityScore`, `alphaChannelIntact`, `hotspots[]`.

### Step 3 — Dual Oracle parallel review

Emit TWO `Agent` calls in ONE message (both HEAVY model):

**Pass A: Design System + Functional Integrity**
```
prompt: "VISUAL QA PASS A — DESIGN-SYSTEM AND FUNCTIONAL INTEGRITY (read-only)

Treat this as the deeper, stricter pass. Assume the surface MAY BE FAKED until source proves otherwise.

INTENT: {what user wanted}
SCREENSHOT: {actual_path}
REFERENCE: {reference_path or 'none'}
DIFF JSON: {script_output}

CHECK (BLOCKING if failed):

1. Real design system vs ad-hoc/mock
   - Read UI source code
   - Styles via design tokens + reused primitives?
   - Or one-off hardcoded values scattered per element?

2. Faked-with-image anti-pattern
   - Real DOM/component tree?
   - Or pasted raster/background-image standing in for live elements?

3. Alpha and transparency
   - alphaChannelIntact from diff JSON
   - Unexpected opaque/black fills?

4. Code style / implementation quality

5. Responsive behavior across viewport sizes

6. User-intended FEATURES actually work?
   - Trace code paths
   - Interactions, states, navigation

OUTPUT:
VERDICT: PASS | REVISE | FAIL
CONFIDENCE: HIGH | MEDIUM | LOW
FINDINGS: [dimension] [severity] what is wrong, where (file:line/region), concrete fix
WHAT IS GOOD: must not regress
BLOCKING: must fix, empty if PASS"
```

**Pass B: Visual Fidelity + CJK Precision**
```
prompt: "VISUAL QA PASS B — VISUAL FIDELITY AND CJK PRECISION (read-only)

Open the screenshot directly. Inspect every hotspot.

INTENT: {what user wanted}
SCREENSHOT: {actual_path}
REFERENCE: {reference_path or 'none'}
DIFF JSON: {script_output}

USE EVIDENCE:
- diffRatio + similarityScore baseline
- For each hotspot (gridX, gridY, x, y, w, h, diffRatio): inspect that region in screenshot
- Explain visual cause from pixels + source

CHECK:

1. Match user intent: layout, spacing, color, type, alignment

2. CJK precision (中日韩)
   - Natural line breaking
   - Oversized headings with orphaned 1-char lines: FLAG
   - Split semantic phrases (e.g. '오케스트 / 레이션'): FLAG
   - Detached labels like '[Image #1]' separated from content: FLAG
   - Clipped baselines/descenders: FLAG
   - Tofu (□ dropped glyphs): FLAG
   - Font metric mismatch: FLAG

3. Per-hotspot analysis
   - What visually changed in each hotspot grid?
   - Intentional or regression?

OUTPUT:
VERDICT: PASS | REVISE | FAIL
EVIDENCE TRACE: each hotspot → visual cause
FINDINGS: [severity] what wrong, where, concrete fix
BLOCKING: empty if PASS"
```

### Step 4 — Synthesize one verdict

After both passes return, ONE `Agent` call (MID model):
```
prompt: "Synthesize Pass A and Pass B into ONE visual QA verdict.

PASS A: {pass_a}
PASS B: {pass_b}
DIFF JSON: {diff_json}

RULES:
- Either FAIL → overall FAIL
- Both PASS → overall PASS
- Else → REVISE
- Deduplicate findings across passes
- For each bad item: state where + concrete fix
- Call out what's good

OUTPUT:
# Visual QA Report
## Overall Verdict: PASS | REVISE | FAIL
## Pass Summary (table)
## Key Diff Evidence (similarity, hotspots)
## Blocking Issues (deduplicated, located, with fix)
## What's Good (do not regress)
## Recommendations (prioritized)"
```

## Required setup

- `python3` + `Pillow` (`pip install Pillow`)
- Playwright or alijk-agent-browser for screenshot capture
- `image-diff.py` script at `~/.qoder/scripts/image-diff.py`

## Model tiers

| Stage | Model |
|-------|-------|
| Capture / diff runner | `Qwen3.7-Max-DogFooding` (CHEAP) |
| Pass A / Pass B | `GLM-5.2` (HEAVY — needs visual reasoning) |
| Synthesize | `GLM-5.2` (MID) |
