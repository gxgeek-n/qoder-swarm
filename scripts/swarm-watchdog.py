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

Co-silence rule for Agent dispatches: when the pending tool is Agent and
open sub-agent transcripts exist, at least one sub-agent must ALSO be
silent past the threshold. A sub-agent still writing is a live worker —
the main session is merely blocked on the join, and a healthy 40-min
worker must not be flagged.

Why not scan sub-agent transcripts directly: their terminal state is
unreliable — final answers often lack stop_reason and `last-prompt` is only
written when the parent session closes. The parent transcript's
"tool_use dispatched, no tool_result" signature is precise.

Auto-recovery is deliberately ABSENT. Every remote-interrupt mechanism
was tested on 2026-07-23 against a live throwaway qodercli TUI:
  * SIGINT to the host pid      → TUI process DIES. In raw-mode stdin,
    Ctrl-C/Esc reach the app as input BYTES, not signals, so no SIGINT
    handler is installed and the default disposition kills the process.
  * write ESC to /dev/ttysNNN   → lands on the OUTPUT path (toward the
    pty master); the TUI's stdin never sees it. Harmless, useless.
  * TIOCSTI ioctl (fake input)  → EPERM on macOS for other sessions.
Instead, a confirmed stall is RESOLVED to its hosting window and the
alert names the tty: --resume/-r <sid> cmdline → st_birthtime pruning
→ fail-safe refusal when ≥2 same-project windows remain. Manual Esc in
the named window is then a 10-second action.

Usage:
  swarm-watchdog.py [--threshold MIN] [--qoder-home DIR] [--notify] [--json]
                    [--write-flag PATH] [--no-process-check] [--proc-regex RE]

Cron pair for the UserPromptSubmit alert hook (hooks/swarm-hang-notifier.sh):
  */10 * * * * python3 ~/.qoder/scripts/swarm-watchdog.py \
      --write-flag /tmp/qoder-swarm-hang-alert.flag

Exit code: number of stalled sessions (0 = none, 2 = usage error).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
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
        subs = open_subagents(sess, now)
        if "Agent" in tools and subs and all(
                a["silent_min"] < threshold_min for a in subs):
            # Every open sub-agent transcript is still being written: the
            # workers are alive, the main session is just blocked on the
            # join. A healthy long worker is not a hang.
            continue
        stalled.append({
            "session": os.path.basename(sess)[: -len(".jsonl")],
            "file": sess,
            "silent_min": round(age_min, 1),
            "pending_tools": tools,
            "subagents": subs,
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


def locate_host(sess_file: str, proc_regex: str) -> tuple[str, int, str]:
    """Locate the terminal window hosting this session. Returns (status, pid, tty):
      ("ok", pid, tty)     — uniquely bound; tty = its controlling terminal
      ("ambiguous", n, "") — n > 1 same-project candidates, none decisive
      ("none", 0, "")      — no live CLI matches the project dir

    Binding chain (decisive first):
      1. cmdline carries `--resume/-r <session-id>` → direct hit
      2. exactly one candidate after pruning those started AFTER the
         session file was created (st_birthtime) → unique host
      3. otherwise ambiguous — fail safe, never name a guess

    Candidates must own a controlling terminal: pty wrappers (script(1),
    tmux) share the child's cmdline and cwd but hold no tty of their own,
    and a host without a window cannot be named anyway.

    A session's projects-dir name is the host cwd with '/' → '-'. Match in
    the cwd → slug direction: slug → cwd is ambiguous for directory names
    containing '-' ('ae-aaic-work' would wrongly become 'ae/aaic/work').
    No stronger binding exists: qodercli holds no transcript handle and
    exports no session env (verified 2026-07-23).
    """
    slug = os.path.basename(os.path.dirname(sess_file))
    sid = os.path.basename(sess_file)[: -len(".jsonl")]
    r = subprocess.run(["pgrep", "-f", proc_regex],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return ("none", 0, "")
    try:
        born = os.stat(sess_file).st_birthtime
    except (AttributeError, OSError):
        born = None
    candidates = []
    for pid_s in r.stdout.split():
        if not pid_s.isdigit() or int(pid_s) == os.getpid():
            continue
        lo = subprocess.run(["lsof", "-a", "-p", pid_s, "-d", "cwd", "-Fn"],
                            capture_output=True, text=True)
        cwd = next((l[1:] for l in lo.stdout.splitlines() if l.startswith("n")), "")
        if not cwd or cwd.rstrip("/").replace("/", "-") != slug:
            continue
        tty = subprocess.run(["ps", "-o", "tty=", "-p", pid_s],
                             capture_output=True, text=True).stdout.strip()
        if tty in ("", "?", "??"):
            continue
        cmd = subprocess.run(["ps", "-o", "command=", "-p", pid_s],
                             capture_output=True, text=True).stdout.strip()
        et = subprocess.run(["ps", "-o", "etimes=", "-p", pid_s],
                            capture_output=True, text=True).stdout.strip()
        start = time.time() - (int(et) if et.isdigit() else 0)
        candidates.append({"pid": int(pid_s), "cmd": cmd, "start": start,
                           "tty": tty})
    if not candidates:
        return ("none", 0, "")
    direct = [c for c in candidates
              if re.search(r"(?:--resume[=\s]|-r\s)" + re.escape(sid) + r"(?![\w-])",
                           c["cmd"])]
    pool = direct or candidates
    if not direct and born is not None:
        viable = [c for c in pool if c["start"] <= born + 5]
        if viable:
            pool = viable
    if len(pool) > 1:
        return ("ambiguous", len(pool), "")
    c = pool[0]
    return ("ok", c["pid"], c["tty"])


def locate_hosts(stalled: list[dict], proc_regex: str) -> None:
    """Annotate each stalled session with the window hosting it (`host`).
    Read-only: never signals, never writes to the host's tty — every
    remote-interrupt mechanism is either fatal or denied (module docstring),
    so recovery stays a manual Esc in the named window."""
    for s in stalled:
        status, val, tty = locate_host(s["file"], proc_regex)
        if status == "ok":
            s["host"] = f"{tty} pid={val}"
        elif status == "ambiguous":
            s["host"] = f"ambiguous({val}个同项目窗口)"
        else:
            s["host"] = "not-found"


def notify(stalled: list[dict]) -> None:
    agents = sum(1 for s in stalled if "Agent" in s["pending_tools"])
    script = (
        'display notification "Hung streams do not recover — interrupt, '
        'then re-dispatch a fresh agent" with title "swarm-watchdog: '
        f'{len(stalled)} stalled session(s)" subtitle "{agents} waiting on Agent"'
    )
    subprocess.run(["osascript", "-e", script], check=False)


def write_flag(path: str, stalled: list[dict]) -> None:
    """Maintain the alert flag consumed by hooks/swarm-hang-notifier.sh.

    Stalled sessions found  → (over)write one summary line per session.
    Nothing stalled         → remove a stale flag so no outdated alert shows.
    """
    if not stalled:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        return
    lines = []
    for s in stalled:
        line = (f"session={s['session']} silent={s['silent_min']}m "
                f"pending={','.join(s['pending_tools'])} file={s['file']}")
        if s.get("host"):
            line += f" host={s['host']}"
        lines.append(line)
    hosts = {s.get("host", "") for s in stalled}
    if any(h.startswith("ttys") for h in hosts):
        lines.append("窗口已定位: 到 host= 对应 tty 的窗口按 Esc 中断挂起的调用, "
                     "再输入「继续」或重派任务。")
    if any(h.startswith("ambiguous") for h in hosts):
        lines.append("同项目开了多个 qodercli 窗口, 无法确定挂死宿主: "
                     "按 file= 路径对照找到该会话的窗口, 手动按 Esc。")
    if any(h == "not-found" for h in hosts):
        lines.append("未找到宿主窗口(可能已关闭): 重开终端执行 "
                     "qodercli --resume 恢复对应会话。")
    if all(not h for h in hosts):
        lines.append("处理: 到对应会话按 Esc 中断挂起的调用, 然后把任务重新派发给新 agent (不要等旧的)。")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main() -> int:
    p = argparse.ArgumentParser(description="Detect stalled (fake-think) Qoder sessions")
    p.add_argument("--threshold", type=float, default=30, help="silence threshold in minutes (default: 30)")
    p.add_argument("--qoder-home", default=os.path.expanduser("~/.qoder"))
    p.add_argument("--notify", action="store_true", help="macOS notification when stalled sessions found")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--write-flag", metavar="PATH",
                   help="write alert flag for swarm-hang-notifier.sh (cron use); removed when clean")
    p.add_argument("--no-process-check", action="store_true",
                   help="skip the qodercli-alive check (testing, cron on remote hosts)")
    p.add_argument("--proc-regex", default=os.environ.get("SWARM_WATCHDOG_PROC_REGEX", "qodercli"),
                   help="pgrep -f pattern for host CLIs (default: qodercli; "
                        "env SWARM_WATCHDOG_PROC_REGEX, override for testing)")
    args = p.parse_args()

    process_start = None if args.no_process_check else oldest_qodercli_start()
    if not args.no_process_check and process_start is None:
        # No live CLI: silent transcripts are leftovers of closed sessions.
        stalled: list[dict] = []
    else:
        stalled = find_stalled(args.qoder_home, args.threshold, process_start)

    if stalled:
        locate_hosts(stalled, args.proc_regex)

    if args.write_flag:
        write_flag(args.write_flag, stalled)

    if args.json:
        print(json.dumps(stalled, indent=2))
    else:
        for s in stalled:
            subs = ", ".join(f"{a['agent']}({a['silent_min']}m)" for a in s["subagents"]) or "n/a"
            host = f" host={s['host']}" if s.get("host") else ""
            print(f"STALLED session={s['session']} silent={s['silent_min']}m "
                  f"pending={','.join(s['pending_tools'])} subagents: {subs}{host}")
        if stalled:
            print("Hint: a hung stream does not recover. Interrupt the session, "
                  "then re-dispatch the task as a fresh agent.", file=sys.stderr)

    if stalled and args.notify:
        notify(stalled)
    return len(stalled)


if __name__ == "__main__":
    sys.exit(main())
