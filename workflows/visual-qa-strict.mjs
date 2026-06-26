export const meta = {
  name: 'visual-qa-strict',
  description: 'Strict visual QA with pixel diff + dual oracle review. Detects fake UIs (image stand-ins, hardcoded styles), CJK precision issues (broken line wrapping, glyph drops, tofu), alpha channel violations. Ported from LazyCodex visual-qa.',
  whenToUse: 'When user says "visual QA", "screenshot diff", "pixel diff", "is this a real design system or an image", "CJK text wrapping", "alpha breakage", or wants strict UI verification beyond generic UX review.',
  phases: [
    { title: 'Capture', detail: 'Take actual screenshot + locate reference' },
    { title: 'Diff', detail: 'Run pixel-level diff script' },
    { title: 'Review', detail: 'Dual oracle parallel pass A + B' },
    { title: 'Synthesize', detail: 'Merge verdicts into one report' },
  ],
  inputSchema: {
    type: 'object',
    properties: {
      url: { type: 'string', description: 'URL to capture (web mode)' },
      reference: { type: 'string', description: 'Path to reference/baseline PNG' },
      actual: { type: 'string', description: 'Path to actual screenshot PNG (optional, will capture from url)' },
      intent: { type: 'string', description: 'What the user wanted the UI to be' },
      viewport: { type: 'string', description: 'Viewport size like 1280x800 (default 1280x800)' },
    },
    required: ['intent'],
  },
}

const CHEAP = 'Qwen3.7-Max-DogFooding'
const MID   = 'GLM-5.2'
const HEAVY = 'GLM-5.2'

const url = args.url || null
const referencePath = args.reference || null
const actualPath = args.actual || null
const intent = args.intent
const viewport = args.viewport || '1280x800'

// Phase 1: Capture screenshot if needed
phase('Capture')

let screenshotPath = actualPath
if (!screenshotPath && url) {
  log(`Capturing ${url} at ${viewport}...`)
  const captureResult = await agent(`TASK: Capture a screenshot of ${url} at viewport ${viewport}.

Use Playwright via the available browser tooling (web-ux-screenshot skill, alijk-agent-browser, or playwright-cli).

DELIVERABLE:
- Save the screenshot to /tmp/visual-qa-actual.png
- Confirm the file exists and report its path

SCOPE: Just capture. Do not analyze yet.`, {
    label: 'screenshot-capturer',
    phase: 'Capture',
    model: CHEAP,
  })
  screenshotPath = '/tmp/visual-qa-actual.png'
}

if (!screenshotPath) {
  log('ERROR: No actual screenshot. Provide either "url" or "actual" arg.')
  return
}

if (!referencePath) {
  log('WARN: No reference image. Diff phase will be skipped, only structural review will run.')
}

// Phase 2: Run pixel diff
phase('Diff')

let diffJson = null
if (referencePath) {
  log(`Running pixel diff: ${referencePath} vs ${screenshotPath}...`)
  const diffResult = await agent(`TASK: Run the image-diff script and capture its JSON output.

COMMAND TO RUN:
python3 ~/.qoder/scripts/image-diff.py "${referencePath}" "${screenshotPath}"

DELIVERABLE: The full JSON output from stdout. Do not interpret it, just return it verbatim.
SCOPE: Run one command and report output.`, {
    label: 'diff-runner',
    phase: 'Diff',
    model: CHEAP,
  })
  diffJson = diffResult
} else {
  diffJson = '{ "note": "no reference provided, diff skipped" }'
}

// Phase 3: Dual oracle parallel review
phase('Review')
log('Dispatching dual oracle review (Pass A + Pass B)...')

const [passA, passB] = await parallel([
  // Pass A: Design system integrity + anti-fake-UI
  () => agent(`TASK: VISUAL QA PASS A — DESIGN-SYSTEM AND FUNCTIONAL INTEGRITY (read-only)

Treat this as the deeper, stricter pass. Assume a plausible-looking surface MAY BE FAKED OR MOCK-ONLY until the source proves otherwise.

INTENT (what the user wanted):
${intent}

SCREENSHOT PATH: ${screenshotPath}
REFERENCE PATH: ${referencePath || 'none'}

DIFF SCRIPT EVIDENCE (reference, not verdict):
${diffJson}

CHECK EACH (BLOCKING if failed):

1. Real design system vs ad-hoc/mock-only
   - Read the UI source code (HTML/CSS/components)
   - Are styles driven by coherent design tokens and reused primitives?
   - Or one-off hardcoded values scattered per element?
   - If user wanted a throwaway mock, this is OK. Otherwise BLOCKING.

2. Faked-with-an-image anti-pattern
   - Is the UI a real DOM/component tree?
   - Or pasted raster/screenshot/background-image standing in for live elements?
   - Check: does it have interactive elements? semantic HTML? component boundaries?

3. Alpha and transparency
   - Cross-check alphaChannelIntact from the diff JSON
   - Look for unexpected opaque/black fills where transparency was intended
   - Check PNG/CSS alpha is handled correctly

4. Code style and implementation quality
   - Component structure
   - CSS organization
   - Naming conventions

5. Responsive behavior
   - Read CSS / inspect viewport behavior
   - Look for fixed widths that would break on resize

6. Do user-intended FEATURES actually work?
   - Trace the code paths
   - Interactions, states, navigation

OUTPUT FORMAT:
VERDICT: PASS | REVISE | FAIL
CONFIDENCE: HIGH | MEDIUM | LOW
SUMMARY: 1-3 sentences

FINDINGS (for each):
[dimension] [severity] what is wrong
- Location: file/line or screenshot region
- Fix: concrete action

WHAT IS GOOD: correct aspects that must not regress
BLOCKING: items that must be fixed; empty if PASS`, {
    label: 'oracle-pass-A',
    phase: 'Review',
    model: HEAVY,
  }),

  // Pass B: Visual fidelity + CJK precision
  () => agent(`TASK: VISUAL QA PASS B — VISUAL FIDELITY AND CJK PRECISION (read-only)

Treat this as the focused visual pass. Open the screenshot directly and inspect every hotspot.

INTENT (what the user wanted):
${intent}

SCREENSHOT PATH: ${screenshotPath}
REFERENCE PATH: ${referencePath || 'none'}

DIFF SCRIPT EVIDENCE (REQUIRED — consume every field):
${diffJson}

USE THE EVIDENCE:
- Start from diffRatio and similarityScore
- For EACH hotspot in hotspots[]: open the screenshot, look at that grid region
  (gridX, gridY map to the 8x8 grid; x/y/width/height are pixel coords)
- Explain the visual cause of each flagged region from pixels + source

CHECK:

1. Does the rendered output match what the user requested?
   - Layout, spacing, color, type, alignment
   - Cross-check with reference if provided

2. CJK precision (中日韩)
   - Natural CJK line breaking — display text and body text
   - Flag oversized headings that create orphaned one-character lines
   - Flag split semantic phrases (e.g. "오케스트 / 레이션" broken mid-word)
   - Flag detached labels like "[Image #1]" separated from their content
   - Flag clipped baselines/descenders
   - Flag dropped glyphs (tofu □ squares)
   - Flag font metric mismatch
   - Example BAD wrapping: "에이전트 오케스트 / 레이션 현황 및 미 / 래" → REVISE or FAIL

3. Per-hotspot analysis
   - For each hotspot in diff JSON, describe what visually changed there
   - Is it intentional or a regression?

OUTPUT FORMAT:
VERDICT: PASS | REVISE | FAIL
CONFIDENCE: HIGH | MEDIUM | LOW
SUMMARY: 1-3 sentences

EVIDENCE TRACE: each hotspot mapped to its visual cause
- Hotspot (gridX, gridY): [visual description] — cause: [source reason]

FINDINGS (for each):
[severity] what is wrong
- Location: hotspot grid or screenshot region
- Fix: concrete action

BLOCKING: items that must be fixed; empty if PASS`, {
    label: 'oracle-pass-B',
    phase: 'Review',
    model: HEAVY,
  }),
])

// Phase 4: Synthesize one verdict
phase('Synthesize')

const finalReport = await agent(`TASK: Synthesize Pass A and Pass B into ONE visual QA verdict.

INTENT: ${intent}

PASS A (design system + functional integrity):
${passA}

PASS B (visual fidelity + CJK):
${passB}

DIFF JSON:
${diffJson}

RULES:
- If EITHER pass returned FAIL → overall FAIL
- If both PASS → overall PASS
- Otherwise → REVISE
- Per dimension: mark good or bad with evidence
- For each bad item: state what is wrong, WHERE (file/line, hotspot grid), and the CONCRETE FIX
- Call out what is genuinely good so it does not regress later
- Deduplicate findings that both passes raised

OUTPUT:
# Visual QA Report

## Overall Verdict: PASS | REVISE | FAIL

## Pass Summary
| Pass | Verdict | Confidence |
| Pass A (design system) | ... | ... |
| Pass B (visual + CJK) | ... | ... |

## Key Diff Evidence
- Similarity: X/100
- Hotspots: N regions
- Top hotspot: (gridX, gridY) at (x, y) — diffRatio=X

## Blocking Issues
[Aggregated, deduplicated, with location + fix]

## What's Good (do not regress)
[Aggregated]

## Recommendations
[Prioritized fix order if not PASS]`, {
  label: 'synthesizer',
  phase: 'Synthesize',
  model: MID,
})

log('Visual QA complete.')
