# self-improve — evolutionary tournament optimization

Source: chickenlj/oh-my-qoder `skills/self-improve/SKILL.md` (Apache-2.0).
Adapted for qoder-swarm: uses our scripts (task-dag.sh, swarm-concurrency.sh, eval-bootstrap.sh, swarm-cost-qoder.py) and `.swarm/` state convention.

## When to use

- You want to **iteratively improve** a metric (test score, performance number, cost/credit)
- You have a **benchmark command** that outputs a numeric score
- The improvement requires multiple attempts with different strategies
- Triggers: "self-improve" / "evolutionary" / "tournament" / "自进化" / "持续优化" / "benchmark loop"

## Core concept

```
Setup → [Research → N Plans → N Executors → Benchmark each → Keep best → Merge winner] × iterations
         ↑                                                                              ↓
         └──────────────── stop if plateau (3 rounds no improvement) ────────────────────┘
```

Tournament selection: spawn N workers each implementing a different plan. Benchmark all. Best score wins. Losers discarded. Winner merges into `improve/` branch. Repeat.

## State

```
.swarm/self-improve/{topic}/
├── config/
│   ├── settings.json     # benchmark_command, max_iterations, plateau_threshold, n_agents
│   ├── goal.md           # what to improve + target metric
│   └── sealed_files      # files benchmark uses (cannot be modified by workers)
├── state/
│   ├── progress.json     # {iteration, best_score, plateau_count, status}
│   ├── history/          # one JSON per iteration {round, plans[], scores[], winner}
│   └── research/         # briefs from each round's research phase
└── branches/             # tracking: which git branches are active experiments
```

## Setup (once, interactive)

1. User provides: target repo path + benchmark command + goal description
2. Orchestrator validates benchmark runs 3x with consistent score (baseline)
3. Creates `improve/{goal_slug}` branch from current HEAD
4. Writes `config/settings.json` + `config/goal.md` + `state/progress.json`
5. **Trust gate**: user explicitly confirms "this will run benchmark repeatedly"

## Improvement loop (autonomous after setup)

### Step 1 — Research (swarm-explorer, CHEAP)

```
Agent[swarm-explorer]:
TASK: Analyze codebase for improvement opportunities targeting {goal}
DELIVERABLE: 3-5 hypotheses, each: what to change + expected impact + files involved
OUTPUT: .swarm/self-improve/{topic}/state/research/round_{n}.md
```

### Step 2 — Planning (swarm-planner, HEAVY, × N)

For each hypothesis (or top 3 if >3):
```
Agent[swarm-planner]:
TASK: Write an implementation plan for hypothesis: {hypothesis}
CONSTRAINT: changes must not touch sealed_files
DELIVERABLE: .swarm/self-improve/{topic}/plans/round_{n}_plan_{i}.md
```

### Step 3 — Execution (swarm-worker, × N, parallel via worktrees)

Each plan gets its own git worktree branch:
```bash
git worktree add .swarm/self-improve/{topic}/worktrees/round_{n}_exec_{i} -b experiment/round_{n}_exec_{i} improve/{goal_slug}
```

```
Agent[swarm-worker]:  (cwd = worktree path)
TASK: Implement plan_{i}
ACCEPTANCE: benchmark command exits 0
```

### Step 4 — Tournament (orchestrator evaluates)

```bash
for each executor branch:
  cd worktree_{i}
  score_{i} = $(eval $BENCHMARK_COMMAND)
end

winner = argmax(score_{i})
```

### Step 5 — Merge winner + record history

```bash
git merge --no-ff experiment/round_{n}_exec_{winner} -m "Iteration {n}: {hypothesis} (score: {baseline} → {winner_score})"
```

Write `state/history/round_{n}.json`:
```json
{"round": N, "hypotheses": [...], "scores": [...], "winner_idx": K, "improvement": delta}
```

Update `state/progress.json`:
```json
{"iteration": N, "best_score": X, "plateau_count": P, "status": "running"}
```

### Step 6 — Stop conditions

| Condition | Action |
|---|---|
| `iteration >= max_iterations` (default 10) | Stop, report final score |
| `plateau_count >= plateau_threshold` (default 3) — no improvement for 3 rounds | Stop, report "converged" |
| `best_score >= target_value` (if set) | Stop, report "target achieved" |
| All N executors fail benchmark | Log, continue next round (new research) |
| User sends `/cancel` | Save state, stop gracefully |

### Step 7 — Cleanup losers

Archive losing branches as tags, delete worktrees:
```bash
git tag archive/round_{n}_exec_{i} experiment/round_{n}_exec_{i}
git worktree remove .swarm/self-improve/{topic}/worktrees/round_{n}_exec_{i}
git branch -D experiment/round_{n}_exec_{i}
```

## Hard rules

- NEVER modify sealed_files (benchmark integrity)
- NEVER run without user trust confirmation
- autonomous: no stops/questions during the loop (only stop conditions halt it)
- Each iteration is atomic: either winner merges or nothing changes on improve/ branch
- State on disk: crash at any point → resume from last completed step

## Example: optimize swarm credit consumption

```
Goal: reduce per-bootstrap credit from 155 to <80
Benchmark: python3 scripts/swarm-cost-qoder.py --date today | grep TOTAL | awk '{print $NF}'
Sealed: scripts/swarm-cost-qoder.py (can't cheat by modifying the meter)
N_agents: 3
Max_iterations: 5
```

Round 1 research → hypotheses: "shorter prompts", "fewer dispatches", "Qwen for doc tasks"
Round 1 execution → 3 workers each try one approach → benchmark → "fewer dispatches" wins (120 → 95)
Round 2 research → "combine remaining" → benchmark → 95 → 78 → target achieved → STOP

## Cost model

Per iteration: 1 explorer (free) + N planners (Ultimate) + N workers (GLM) + 1 merge
For N=3, 5 iterations: ~5 × (0 + 3×1 + 3×0.6 + 0) × 15K tokens/call = moderate

## Relationship to other patterns

- plan-and-review: runs ONCE; self-improve loops plan-and-review N× with tournament
- ulw-loop: loops execution with a checklist; self-improve loops with a BENCHMARK score
- five-agent-review: validates code quality; self-improve's Step 4 validates metric improvement
