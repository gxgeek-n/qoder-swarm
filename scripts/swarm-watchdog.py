#!/usr/bin/env python3
"""
scripts/swarm-watchdog.py — detect stalled ("fake think") sessions.

Symptom: the Qoder UI spinner is active and a sub-agent appears to be
"thinking", but nothing is being written — the managed-model streaming
request hung with no idle timeout, and the orchestrator's blocking join then
stalls the whole session (observed 6+ h on 2026-07-22, P0 filed).

A session is STALLED when all of these hold:
  1. its transcript's last record is an assistant message containing a
     tool_use block (the model called a tool and is waiting for the result)
  2. the transcript has been silent for >= --threshold minutes
  3. the transcript was last written AFTER the oldest live qodercli
     process started — otherwise it's the corpse of a crashed session,
     and crashed corpses keep the tool_use-last signature forever

Sessions waiting on user-interactive tools (AskUserQuestion, ExitPlanMode)
are excluded: pending-on-human is not a hang.

Why not scan sub-agent transcripts directly: their terminal state is
unreliable — final answers often lack stop_reason and `last-prompt` is only
written when the parent session closes. The parent transcript's
"tool_use dispatched, no tool_result" signature is precise.

Detection only — never interrupts or resumes anything. Auto-recovery via
`qodercli -p --resume <id>` is deliberately not wired in.

Usage:
  swarm-watchdog.py [--threshold MIN] [--qoder-home DIR] [--notify] [--json]
                    [--no-process-check]

Exit code: number of stalled sessions (0 = none, 2 = usage error).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
import time


# Tools that park the session waiting for HUMAN input. Pending on these is
# not a hang.
INTERACTIVE_TOOLS = {"AskUserQuestion", "ExitPlanMode"}


def last_record(path: str) -> dict | None:
    last = None
    try:
        with open(path, "rb") as f:
            for line in f:
                line = line.strip()
                if line:
                    last = line
    except OSError:
        return None
    if not last:
        return None
    try:
        return json.loads(last)
    except json.JSONDecodeError:
        return None


def pending_tools(record: dict) -> list[str]:
    """Tool names the session is waiting on (empty = idle at user prompt)."""
    if record.get("type") != "assistant":
        return []
    content = (record.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []
    return [b.get("name", "?") for b in content
            if isinstance(b, dict) and b.get("type") == "tool_use"]


def open_subagents(session_file: str, now: float) -> list[dict]:
    """Non-closed sub-agent transcripts of this session, with silence ages."""
    session_dir = session_file[: -len(".jsonl")]
    out = []
    for path in glob.glob(os.path.join(session_dir, "subagents", "agent-*.jsonl")):
        rec = last_record(path)
        if rec is None or rec.get("type") == "last-prompt":
            continue
        out.append({
            "file": path,
            "agent": os.path.basename(path)[: -len(".jsonl")],
            "silent_min": round((now - os.path.getmtime(path)) / 60, 1),
        })
    return out


def find_stalled(qoder_home: str, threshold_min: float,
                 process_start: float | None) -> list[dict]:
    now = time.time()
    stalled = []
    pattern = os.path.join(qoder_home, "projects", "*", "*.jsonl")
    for sess in glob.glob(pattern):
        mtime = os.path.getmtime(sess)
        age_min = (now - mtime) / 60
        if age_min < threshold_min:
            continue
        if process_start is not None and mtime < process_start:
            # Written before the oldest live CLI started: crashed-session
            # corpse, not a live hang.
            continue
        rec = last_record(sess)
        if rec is None or rec.get("type") == "last-prompt":
            continue
        tools = pending_tools(rec)
        if not tools or set(tools) <= INTERACTIVE_TOOLS:
            continue
        stalled.append({
            "session": os.path.basename(sess)[: -len(".jsonl")],
            "file": sess,
            "silent_min": round(age_min, 1),
            "pending_tools": tools,
            "subagents": open_subagents(sess, now),
        })
    return stalled


def oldest_qodercli_start() -> float | None:
    """Start time (epoch) of the oldest live qodercli process, None if none."""
    r = subprocess.run(["pgrep", "-f", "qodercli"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    r2 = subprocess.run(["ps", "-o", "etimes=", "-p",
                         ",".join(r.stdout.split())],
                        capture_output=True, text=True)
    ages = [int(x) for x in r2.stdout.split() if x.strip().isdigit()]
    if not ages:
        return None
    return time.time() - max(ages)


def notify(stalled: list[dict]) -> None:
    agents = sum(1 for s in stalled if "Agent" in s["pending_tools"])
    script = (
        'display notification "Hung streams do not recover — interrupt, '
        'then re-dispatch a fresh agent" with title "swarm-watchdog: '
        f'{len(stalled)} stalled session(s)" subtitle "{agents} waiting on Agent"'
    )
    subprocess.run(["osascript", "-e", script], check=False)


def main() -> int:
    p = argparse.ArgumentParser(description="Detect stalled (fake-think) Qoder sessions")
    p.add_argument("--threshold", type=float, default=30, help="silence threshold in minutes (default: 30)")
    p.add_argument("--qoder-home", default=os.path.expanduser("~/.qoder"))
    p.add_argument("--notify", action="store_true", help="macOS notification when stalled sessions found")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--no-process-check", action="store_true",
                   help="skip the qodercli-alive check (testing, cron on remote hosts)")
    args = p.parse_args()

    process_start = None if args.no_process_check else oldest_qodercli_start()
    if not args.no_process_check and process_start is None:
        # No live CLI: silent transcripts are leftovers of closed sessions.
        stalled: list[dict] = []
    else:
        stalled = find_stalled(args.qoder_home, args.threshold, process_start)

    if args.json:
        print(json.dumps(stalled, indent=2))
    else:
        for s in stalled:
            subs = ", ".join(f"{a['agent']}({a['silent_min']}m)" for a in s["subagents"]) or "n/a"
            print(f"STALLED session={s['session']} silent={s['silent_min']}m "
                  f"pending={','.join(s['pending_tools'])} subagents: {subs}")
        if stalled:
            print("Hint: a hung stream does not recover. Interrupt the session, "
                  "then re-dispatch the task as a fresh agent.", file=sys.stderr)

    if stalled and args.notify:
        notify(stalled)
    return len(stalled)


if __name__ == "__main__":
    sys.exit(main())
