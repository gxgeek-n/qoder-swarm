#!/usr/bin/env python3
"""
scripts/swarm-empty-done.py — Detect empty-done sub-agent dispatches from Qoder audit.

Scans ~/.qoder/audit/audit.jsonl for Agent PostToolUse events on a given date,
walks each sub-agent transcript at ~/.qoder/projects/*/*/subagents/agent-<id>.jsonl,
and classifies a dispatch as "empty-done" if:
  - transcript file is missing (reason: no-transcript), OR
  - assistant produced < 50 chars of text (reason: empty-content)

Prints a summary table to stdout and writes per-empty-done records to
.swarm/audit/empty-dones.jsonl for orchestrator consumption.

Usage:
    scripts/swarm-empty-done.py [--date YYYY-MM-DD] [--consecutive]

    --date        Date filter (default: today)
    --consecutive  Only show subagent_types with 2+ consecutive empty-dones
                   (actionable signal for orchestrator — single empty-dones are noise)

Exit code: 0 on success (even if no empty-dones found).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

QODER_HOME = Path.home() / ".qoder"
AUDIT_LOG = QODER_HOME / "audit" / "audit.jsonl"
SUBAGENTS_GLOB = str(QODER_HOME / "projects" / "*" / "*" / "subagents" / "agent-*.jsonl")

OUTPUT_DIR = Path.cwd() / ".swarm" / "audit"
OUTPUT_FILE = OUTPUT_DIR / "empty-dones.jsonl"

# Threshold: assistant chars below this = empty-done
EMPTY_THRESHOLD = 50


def parse_ts(s: str) -> datetime | None:
    try:
        return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return None


def find_agent_dispatches(date_filter: str) -> dict:
    """Read audit.jsonl. Return: agent_id -> {sub, ts, session_id, duration_s}."""
    if not AUDIT_LOG.exists():
        print(f"ERROR: Qoder audit log not found: {AUDIT_LOG}", file=sys.stderr)
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
                sid = j.get("session_id", "")
                pre_dt = parse_ts(pre_ts)
                post_dt = parse_ts(ts)
                dur_s = (post_dt - pre_dt).total_seconds() if pre_dt and post_dt else 0.0
                dispatches[aid] = {
                    "sub": atype,
                    "ts": ts,
                    "session_id": sid,
                    "duration_s": dur_s,
                }

    return dispatches


def count_assistant_chars(path: str) -> int:
    """Count assistant text chars in a sub-agent transcript. Returns -1 if file missing."""
    if not os.path.exists(path):
        return -1
    assistant_chars = 0
    with open(path) as f:
        for line in f:
            try:
                j = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = j.get("message", {})
            if not isinstance(msg, dict):
                continue
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content", "")
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        assistant_chars += len(c.get("text", ""))
            elif isinstance(content, str):
                assistant_chars += len(content)
    return assistant_chars


def find_transcript(agent_id: str) -> str | None:
    """Search all sessions' subagents dirs for agent-<id>.jsonl."""
    target = f"agent-{agent_id}.jsonl"
    for match in glob.glob(SUBAGENTS_GLOB):
        if os.path.basename(match) == target:
            return match
    return None


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--date",
        default=datetime.now().strftime("%Y-%m-%d"),
        help="Date filter YYYY-MM-DD (default: today)",
    )
    ap.add_argument(
        "--consecutive",
        action="store_true",
        help="Only show subagent_types with 2+ consecutive empty-dones",
    )
    args = ap.parse_args()

    dispatches = find_agent_dispatches(args.date)
    print(f"=== Empty-Done Audit — {args.date} ===")
    print(f"Total Agent dispatches: {len(dispatches)}\n")

    if not dispatches:
        print("No Agent dispatches found.")
        return 0

    # Per-dispatch classification
    empty_records: list[dict] = []
    by_sub: dict[str, dict] = defaultdict(
        lambda: {"count": 0, "empty_dones": 0, "duration_s": 0.0, "ts_list": []}
    )

    for aid, info in dispatches.items():
        sub = info["sub"]
        tp = find_transcript(aid)
        achars = count_assistant_chars(tp) if tp else -1

        is_empty = False
        reason = None
        if achars < 0:
            is_empty = True
            reason = "no-transcript"
        elif achars < EMPTY_THRESHOLD:
            is_empty = True
            reason = "empty-content"

        s = by_sub[sub]
        s["count"] += 1
        s["duration_s"] += info["duration_s"]
        s["ts_list"].append(info["ts"])

        if is_empty:
            s["empty_dones"] += 1
            rec = {
                "ts": info["ts"],
                "agent_id": aid,
                "subagent_type": sub,
                "reason": reason,
                "duration_s": round(info["duration_s"], 1),
            }
            empty_records.append(rec)

    # Consecutive detection: sort each subagent's timestamps, find runs of 2+ empty
    consecutive_subs: set[str] = set()
    if args.consecutive:
        # Need to track which specific dispatches were empty, in time order
        sub_empty_ts: dict[str, list[str]] = defaultdict(list)
        for rec in empty_records:
            sub_empty_ts[rec["subagent_type"]].append(rec["ts"])
        for sub, ts_list in sub_empty_ts.items():
            ts_list.sort()
            # Simple consecutive check: if any two empty-dones share the same
            # subagent_type and both happened (we treat 2+ empties for same sub
            # within the day as consecutive signal)
            if len(ts_list) >= 2:
                consecutive_subs.add(sub)

    # Write JSONL output
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w") as f:
        for rec in empty_records:
            # Filter by consecutive mode
            if args.consecutive and rec["subagent_type"] not in consecutive_subs:
                continue
            f.write(json.dumps(rec) + "\n")

    # Print table
    header = (
        f'{"Subagent":<26} {"Count":>5} {"Empty":>5} {"Rate%":>6} '
        f'{"WallMin":>8} {"WastedMin":>10}'
    )
    print(header)
    print("-" * len(header))

    total_count = 0
    total_empty = 0
    total_dur = 0.0
    total_wasted = 0.0

    rows = []
    for sub, s in by_sub.items():
        if args.consecutive and sub not in consecutive_subs:
            continue
        rate = (s["empty_dones"] / s["count"] * 100) if s["count"] > 0 else 0.0
        # Wasted wall time: only count time spent on empty-done dispatches
        # Approximate: (empty_dones / count) * total_duration
        wasted = (s["empty_dones"] / s["count"] * s["duration_s"]) if s["count"] > 0 else 0.0
        rows.append((sub, s, rate, wasted))
        total_count += s["count"]
        total_empty += s["empty_dones"]
        total_dur += s["duration_s"]
        total_wasted += wasted

    for sub, s, rate, wasted in sorted(rows, key=lambda r: -r[1]["empty_dones"]):
        print(
            f'{sub:<26} {s["count"]:>5} {s["empty_dones"]:>5} {rate:>5.0f}% '
            f'{s["duration_s"]/60:>8.1f} {wasted/60:>10.1f}'
        )

    print("-" * len(header))
    overall_rate = (total_empty / total_count * 100) if total_count > 0 else 0.0
    print(
        f'{"TOTAL":<26} {total_count:>5} {total_empty:>5} {overall_rate:>5.0f}% '
        f'{total_dur/60:>8.1f} {total_wasted/60:>10.1f}'
    )

    # Summary
    print()
    if total_empty == 0:
        print("No empty-done dispatches detected.")
    else:
        print(f"Detected {total_empty} empty-done dispatches.")
        if args.consecutive:
            if consecutive_subs:
                print(
                    f"Consecutive offenders (2+ empty-dones): "
                    f"{', '.join(sorted(consecutive_subs))}"
                )
            else:
                print("No subagent_types with 2+ consecutive empty-dones.")

    print(f"\nDetailed records: {OUTPUT_FILE}")
    print(f"  ({len(empty_records)} records written)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
