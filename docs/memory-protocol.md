# Memory protocol (on-demand learning)

Goal: capture successful patterns + failure modes so future swarm iterations don't repeat them, WITHOUT preloading them at session start (which would burn tokens for irrelevant memories).

## Where
`.swarm/memory/<topic>.md` — one file per topic. Topics emerge organically (e.g., `worktree-isolation-bug.md`, `efficient-doc-sweep.md`).

## When to write
After a stage completes successfully OR after a stage fails with a clear root cause. Examples:
- five-agent-review found 12 blockers, all fixed → write `.swarm/memory/blocker-patterns.md` listing what the reviewers caught
- swarm-worker `isolation: worktree` broke dispatch → write `.swarm/memory/worker-isolation.md`

## When to read
Orchestrator at the START of a pattern (before Stage 1) should:
1. `Glob .swarm/memory/*.md` (cheap — file list only)
2. If any filename obviously matches the current task topic, `Read` it
3. If not, proceed without preloading

This is the navigator.ai "on-demand context" pattern + anthropics/skills "load only when triggered". Cost: 1 Glob call (free) per pattern start, 0-1 Read calls only when relevant.

## Format

Each memory file:

```
# <topic>
**When this applies:** <one-line trigger context>
**What we learned:** <1-3 bullets>
**What NOT to do:** <1-3 bullets>
**Reference:** <commit SHA or .swarm/ path that originated this>
```

## Anti-patterns
- Don't preload ALL memory files at session start (defeats on-demand purpose)
- Don't duplicate `docs/session-memory-*.md` content into `.swarm/memory/` — session-memory is session-scoped, memory is pattern-scoped
- Don't write memory for every minor success — only when there's a transferable lesson
