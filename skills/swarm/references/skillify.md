# skillify — Turn a Session Into a Reusable Skill

Use this pattern after a successful multi-step session, when the user says "make this a skill" / "skillify" / "提取技能" / "做成skill".

## Goal

Capture a repeatable workflow from the current session as a concrete skill draft, so future sessions can follow the same steps without rediscovering them.

## Quality Gate

Before extracting a skill, all three must be true. If any answer is "No", tell the user this does not warrant a skill and stop.

1. **Non-Googleable?** — "Could someone Google this in 5 minutes and get a complete answer?" → No.
2. **Project-specific?** — "Is this specific to this codebase, project, or team workflow?" → Yes.
3. **Real effort?** — "Did this take genuine debugging, design, or operational effort to discover?" → Yes.

Prefer skills that encode decision-making heuristics, constraints, pitfalls, and verification steps. Reject generic snippets, boilerplate, or library usage examples — those belong in normal documentation.

## Workflow

### 1. Identify the repeatable task

Scan the session for the core accomplishment. Ask: "What did we actually do that was hard?" The answer is the candidate skill.

### 2. Extract the essential elements

- **Inputs**: What information, files, or context does the skill need to start?
- **Ordered steps**: What did we do, in order? Each step should be actionable, not vague.
- **Success criteria**: How do we know the skill worked? Must be verifiable (test passes, file exists, command exits 0).
- **Constraints / pitfalls**: What constraints did we hit? What mistakes did we make that future runs should avoid?
- **Verification**: What command or check proves the task is complete?

### 3. Decide placement

- Repo built-in skill → `skills/<name>/SKILL.md` (shipped with the repo, version-controlled)
- User/project learned skill → `.qoder/skills/learned/<skill-name>/SKILL.md` (local, not shipped unless committed)
- Documentation only → if the workflow is too ad-hoc to encode, write it as a note and skip the skill file

### 4. Draft the skill file

Output a **complete** SKILL.md with YAML frontmatter. Never emit plain markdown without frontmatter.

Minimum frontmatter:

```yaml
---
name: <skill-name>
description: <one-line description>
triggers:
  - <trigger-phrase-1>
  - <trigger-phrase-2>
---
```

The body should contain:
- **Goal**: one sentence
- **Inputs**: what the skill needs
- **Steps**: ordered, actionable
- **Success criteria**: verifiable
- **Constraints / pitfalls**: what to watch out for
- **Verification**: the exact command or check

### 5. Flag unresolved issues

If the workflow still has fuzzy branching decisions, unresolved edge cases, or steps that depend on external state, note them explicitly before finalizing. Do not silently paper over gaps.

## Routing triggers

This pattern activates when the user says any of:
- "make this a skill" / "skillify" / "做成skill" / "提取技能"
- "save this workflow" / "保存这个流程"
- "turn this into a reusable pattern"

## Rules

- Only capture workflows that are actually repeatable — one-off debugging sessions do not qualify.
- Keep the skill practical and scoped. If it needs 200 lines, it is probably two skills.
- Prefer explicit success criteria over vague prose. "Test passes" beats "should work".
- If the workflow has unresolved branching decisions, note them before drafting — do not guess.
- Learned skills go to `.qoder/skills/learned/<skill-name>/SKILL.md`. Repo skills go to `skills/<name>/SKILL.md`.
- Uncommitted skills are worktree-local until committed or copied to a user-level directory.

## Output

- Proposed skill name
- Target location (repo skill vs learned skill vs docs-only)
- Complete SKILL.md draft with frontmatter
- Quality-gate verdict (which of the 3 questions passed/failed)
- Open questions, if any
