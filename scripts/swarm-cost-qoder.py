#!/usr/bin/env python3
"""
scripts/swarm-cost-qoder.py — Analyze Qoder-internal audit.jsonl for sub-agent cost.

Unlike swarm-cost.sh which only reads .swarm/audit/dispatches.jsonl (our own hook,
often empty), this reads ~/.qoder/audit/audit.jsonl (Qoder-native audit, records
EVERY tool call including Agent dispatches) plus sub-agent transcripts under
~/.qoder/projects/*/subagents/agent-<id>.jsonl for token estimation.

Usage:
    scripts/swarm-cost-qoder.py [--date YYYY-MM-DD] [--session-uuid UUID]

Defaults: today, all sessions.

Output: per-subagent breakdown of dispatches, tokens, tool calls, and estimated credit.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────
# Model → credit multiplier (approximate — real pricing has input/output split)
# ─────────────────────────────────────────────────────────────────────
CREDIT_MULTIPLIER = {
    "Peach-07-17-DogFooding": 0.00,
    "Qwen3.7-Max": 0.50,
    "Qwen3.7-Plus": 0.10,
    "DeepSeek-V4-Flash": 0.10,
    "DeepSeek-V4-Pro": 0.50,
    "GLM-5.2": 0.60,
    "Kimi-K3": 0.80,
    "Kimi-K2.7-Code": 0.30,
    "MiniMax-M3": 0.20,
    "Ultimate": 1.60,
    "Performance": 1.10,
    "Efficient": 0.30,
    "Lite": 0.00,
    "Auto": 1.00,  # unknown, assume mid-tier
}


def _load_swarm_bindings() -> tuple[dict, dict]:
    """subagent→model and model→cost from agents/models.yml (source of truth)."""
    yml = Path(__file__).resolve().parent.parent / "agents" / "models.yml"
    try:
        import yaml
        data = yaml.safe_load(yml.read_text()) or {}
    except Exception:
        return {}, {}
    sub = {role: cfg["model"] for role, cfg in data.items() if "model" in cfg}
    mult = {cfg["model"]: float(cfg.get("cost", 0)) for cfg in data.items() if "model" in cfg}
    return sub, mult


_swarm_sub, _swarm_mult = _load_swarm_bindings()
CREDIT_MULTIPLIER.update(_swarm_mult)

# subagent_type → model (swarm roles from agents/models.yml; rest are static fallbacks)
SUBAGENT_MODEL = {
    **_swarm_sub,
    "general-purpose": "GLM-5.2",
    "Explore": "Efficient",
    "Plan": "Performance",
}

QODER_HOME = Path.home() / ".qoder"
AUDIT_LOG = QODER_HOME / "audit" / "audit.jsonl"
SUBAGENTS_GLOB = str(QODER_HOME / "projects" / "*" / "*" / "subagents" / "agent-*.jsonl")


def parse_ts(s: str) -> datetime | None:
    try:
        return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return None


def find_agent_dispatches(date_filter: str | None, session_filter: str | None) -> dict:
    """Read audit.jsonl. Return: agent_id -> {sub, ts, session_id, duration_s}."""
    if not AUDIT_LOG.exists():
        print(f"❌ Qoder audit log not found: {AUDIT_LOG}", file=sys.stderr)
        sys.exit(1)

    pre_events: dict[str, str] = {}  # tool_use_id -> pre_ts
    dispatches: dict[str, dict] = {}  # agent_id -> info

    with AUDIT_LOG.open() as f:
        for line in f:
            try:
                j = json.loads(line)
            except json.JSONDecodeError:
                continue

            ts = j.get("_timestamp", "")
            if date_filter and not ts.startswith(date_filter):
                continue
            if j.get("tool_name") != "Agent":
                continue

            sid = j.get("session_id", "")
            if session_filter and sid != session_filter:
                continue

            tid = j.get("tool_use_id", "")
            evt = j.get("_event")

            if evt == "PreToolUse":
                pre_events[tid] = ts
            elif evt == "PostToolUse":
                pre_ts = pre_events.get(tid, ts)
                tr = j.get("tool_response", {})
                if not isinstance(tr, dict):
                    continue
                aid = tr.get("agentId")
                if not aid:
                    continue
                atype = tr.get("agentType", "?")
                state = tr.get("state", "?")
                term = tr.get("terminateReason", "")
                pre_dt = parse_ts(pre_ts)
                post_dt = parse_ts(ts)
                dur_s = (post_dt - pre_dt).total_seconds() if pre_dt and post_dt else 0.0
                dispatches[aid] = {
                    "sub": atype,
                    "ts": ts,
                    "session_id": sid,
                    "state": state,
                    "terminate_reason": term,
                    "duration_s": dur_s,
                }

    return dispatches


def analyze_transcript(path: str) -> dict:
    """Count chars, assistant chars, tool calls in a sub-agent transcript."""
    total_chars = 0
    assistant_chars = 0
    tool_calls = 0
    if not os.path.exists(path):
        return {"total_chars": 0, "assistant_chars": 0, "tool_calls": 0, "found": False}
    with open(path) as f:
        for line in f:
            try:
                j = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = j.get("message", {})
            if not isinstance(msg, dict):
                continue
            role = msg.get("role", "")
            content = msg.get("content", "")
            if isinstance(content, list):
                for c in content:
                    if not isinstance(c, dict):
                        continue
                    ctype = c.get("type")
                    if ctype == "text":
                        text = c.get("text", "")
                        total_chars += len(text)
                        if role == "assistant":
                            assistant_chars += len(text)
                    elif ctype == "tool_use":
                        tool_calls += 1
            elif isinstance(content, str):
                total_chars += len(content)
    return {
        "total_chars": total_chars,
        "assistant_chars": assistant_chars,
        "tool_calls": tool_calls,
        "found": True,
    }


def find_transcript(agent_id: str) -> str | None:
    """Search all sessions' subagents dirs for agent-<id>.jsonl."""
    for match in glob.glob(SUBAGENTS_GLOB):
        if os.path.basename(match) == f"agent-{agent_id}.jsonl":
            return match
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", default=datetime.now().strftime("%Y-%m-%d"),
                    help="Date filter YYYY-MM-DD (default: today)")
    ap.add_argument("--session-uuid", default=None, help="Filter to one session UUID")
    ap.add_argument("--verbose", "-v", action="store_true", help="Show per-dispatch detail")
    ap.add_argument("--top-consumers", type=int, default=5, help="Show top N dispatches by chars (default 5)")
    args = ap.parse_args()

    print(f"=== Qoder sub-agent cost audit — {args.date} ===\n")

    dispatches = find_agent_dispatches(args.date, args.session_uuid)
    if not dispatches:
        print(f"No Agent dispatches found for date={args.date}", end="")
        if args.session_uuid:
            print(f" session={args.session_uuid}")
        else:
            print()
        return 0

    # Aggregate by subagent_type
    by_sub: dict[str, dict] = defaultdict(lambda: {
        "count": 0, "total_chars": 0, "assistant_chars": 0,
        "tool_calls": 0, "duration_s": 0.0, "empty_dones": 0,
        "dispatches": [],
    })

    for aid, info in dispatches.items():
        sub = info["sub"]
        tp = find_transcript(aid)
        stats = analyze_transcript(tp) if tp else {"total_chars": 0, "assistant_chars": 0, "tool_calls": 0, "found": False}
        s = by_sub[sub]
        s["count"] += 1
        s["total_chars"] += stats["total_chars"]
        s["assistant_chars"] += stats["assistant_chars"]
        s["tool_calls"] += stats["tool_calls"]
        s["duration_s"] += info["duration_s"]
        # Empty done: transcript missing OR assistant produced ~0 chars
        if not stats["found"] or stats["assistant_chars"] < 50:
            s["empty_dones"] += 1
        s["dispatches"].append({
            "agent_id": aid, "ts": info["ts"], "dur_s": info["duration_s"],
            "chars": stats["total_chars"], "assistant": stats["assistant_chars"],
            "tools": stats["tool_calls"], "found": stats["found"],
        })

    # Table
    header = f'{"Subagent":<26} {"Count":>5} {"Model":<25} {"Tokens*":>10} {"AssistChr":>10} {"Empty":>5} {"Tools":>5} {"WallMin":>8} {"Credit*":>8}'
    print(header)
    print("─" * len(header))

    total_credit = 0.0
    total_tokens = 0
    total_dur = 0.0
    total_dispatches = 0

    rows = []
    for sub, s in by_sub.items():
        model = SUBAGENT_MODEL.get(sub, "?")
        mul = CREDIT_MULTIPLIER.get(model, 0.6)
        # Rough token estimate: chars / 4 for English, chars * 1.5 for Chinese
        # Use chars/4 as conservative English-heavy estimate
        est_tokens = s["total_chars"] // 4
        est_credit = est_tokens * mul / 1000
        rows.append((sub, s, model, est_tokens, est_credit))
        total_credit += est_credit
        total_tokens += est_tokens
        total_dur += s["duration_s"]
        total_dispatches += s["count"]

    for sub, s, model, est_tokens, est_credit in sorted(rows, key=lambda r: -r[4]):
        print(f'{sub:<26} {s["count"]:>5} {model:<25} {est_tokens:>10,} '
              f'{s["assistant_chars"]//4:>10,} {s["empty_dones"]:>5} {s["tool_calls"]:>5} '
              f'{s["duration_s"]/60:>8.1f} {est_credit:>8.2f}')

    print("─" * len(header))
    print(f'{"TOTAL":<26} {total_dispatches:>5} {"":<25} {total_tokens:>10,} {"":<10} {"":<5} {"":<5} {total_dur/60:>8.1f} {total_credit:>8.2f}')
    print()
    print("* Tokens = chars/4 (rough; Chinese content real usage 1.5-2x higher)")
    print("* Credit = tokens/1000 * multiplier (approximate; input/output split not tracked)")
    print("* Empty = dispatches where transcript missing or assistant produced <50 chars (likely failed)")

    # Rank
    print("\n=== Credit consumption ranking ===")
    for sub, s, model, est_tokens, est_credit in sorted(rows, key=lambda r: -r[4]):
        if total_credit == 0:
            pct = 0
        else:
            pct = est_credit / total_credit * 100
        print(f"  {sub:<26} {est_credit:>6.2f} credit ({pct:>4.0f}%) via {model}")

    # Empty-Done pain
    empty_total = sum(s["empty_dones"] for _, s in by_sub.items())
    if empty_total > 0:
        print(f"\n⚠️  {empty_total} empty-done dispatches (wasted concurrency slot):")
        for sub, s in sorted(by_sub.items(), key=lambda x: -x[1]["empty_dones"]):
            if s["empty_dones"] > 0:
                wall = s["duration_s"] / 60
                print(f"  {sub:<26} {s['empty_dones']:>3} empty / {s['count']:>3} total  (wasted ~{wall:.1f}min wall)")

    if args.verbose:
        print("\n=== Top verbose per-dispatch ===")
        all_dispatches = []
        for sub, s in by_sub.items():
            for d in s["dispatches"]:
                d["sub"] = sub
                all_dispatches.append(d)
        for d in sorted(all_dispatches, key=lambda x: -x["chars"])[:args.top_consumers]:
            found_mark = "✓" if d["found"] else "✗"
            print(f'  [{found_mark}] {d["sub"]:<26} {d["ts"]} {d["dur_s"]:>5.0f}s  chars={d["chars"]:>7,}  assist={d["assistant"]:>6,}  tools={d["tools"]:>3}')

    return 0


if __name__ == "__main__":
    sys.exit(main())
