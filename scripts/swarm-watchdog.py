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

Detection is read-only by default. With --auto-soft, a confirmed stall gets
ONE SIGINT delivered to the hosting CLI — the equivalent of pressing Esc in
that window: the TUI survives, only the hung model call is interrupted. A
per-session cooldown (--soft-cooldown-min, default 120min) prevents repeat
interrupts; a session still hung after its SIGINT is escalated in the flag
message instead of being signalled again. SIGTERM / `qodercli -p --resume`
hard recovery is deliberately NOT wired in: killing a TUI host destroys the
user's window. State lives in <qoder-home>/cache/swarm-watchdog-state.json.

Usage:
  swarm-watchdog.py [--threshold MIN] [--qoder-home DIR] [--notify] [--json]
                    [--write-flag PATH] [--no-process-check]
                    [--auto-soft] [--soft-cooldown-min MIN] [--proc-regex RE]

Cron pair for the UserPromptSubmit alert hook (hooks/swarm-hang-notifier.sh):
  */10 * * * * python3 ~/.qoder/scripts/swarm-watchdog.py \
      --write-flag /tmp/qoder-swarm-hang-alert.flag --auto-soft

Exit code: number of stalled sessions (0 = none, 2 = usage error).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import signal
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


def find_host_pid(sess_file: str, proc_regex: str) -> tuple[str, int, bool]:
    """Locate the CLI hosting this session. Returns (status, pid, is_print):
      ("ok", pid, is_print)  — uniquely bound
      ("ambiguous", n, _)    — n > 1 same-project candidates, none decisive
      ("none", 0, _)         — no live CLI matches the project dir

    Binding chain (decisive first):
      1. cmdline carries `--resume/-r <session-id>` → direct hit
      2. exactly one candidate after pruning those started AFTER the
         session file was created (st_birthtime) → unique host
      3. otherwise ambiguous — fail safe, never signal a guess

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
        return ("none", 0, False)
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
        cmd = subprocess.run(["ps", "-o", "command=", "-p", pid_s],
                             capture_output=True, text=True).stdout.strip()
        et = subprocess.run(["ps", "-o", "etimes=", "-p", pid_s],
                            capture_output=True, text=True).stdout.strip()
        start = time.time() - (int(et) if et.isdigit() else 0)
        candidates.append({"pid": int(pid_s), "cmd": cmd, "start": start})
    if not candidates:
        return ("none", 0, False)
    direct = [c for c in candidates
              if re.search(r"(?:--resume[=\s]|-r\s)" + re.escape(sid) + r"(?![\w-])",
                           c["cmd"])]
    pool = direct or candidates
    if not direct and born is not None:
        viable = [c for c in pool if c["start"] <= born + 5]
        if viable:
            pool = viable
    if len(pool) > 1:
        return ("ambiguous", len(pool), False)
    c = pool[0]
    is_print = " -p " in f" {c['cmd']} " or "--print" in c["cmd"]
    return ("ok", c["pid"], is_print)


def apply_auto_soft(stalled: list[dict], qoder_home: str, proc_regex: str,
                    cooldown_min: float) -> None:
    """Annotate each stalled session with an `action`, sending at most one
    SIGINT (≈ Esc) per session per cooldown window. Never SIGTERMs."""
    now = time.time()
    spath = os.path.join(qoder_home, "cache", "swarm-watchdog-state.json")
    try:
        with open(spath) as f:
            state = json.load(f)
    except (OSError, json.JSONDecodeError):
        state = {}
    for s in stalled:
        sid = s["session"]
        last = state.get(sid, {}).get("sigint_at", 0)
        if now - last < cooldown_min * 60:
            s["action"] = "escalate(auto-Esc已发仍卡住)"
            continue
        status, val, is_print = find_host_pid(s["file"], proc_regex)
        if status == "none":
            s["action"] = "host-not-found"
            continue
        if status == "ambiguous":
            s["action"] = f"host-ambiguous({val}个同项目窗口)"
            continue
        pid = val
        try:
            os.kill(pid, signal.SIGINT)
        except OSError as exc:
            s["action"] = f"sigint-failed({exc.strerror or exc})"
            continue
        state[sid] = {"sigint_at": now}
        s["action"] = f"sigint-sent(pid={pid},mode={'print' if is_print else 'tui'})"
    live = {s["session"] for s in stalled}
    state = {k: v for k, v in state.items()
             if k in live or now - v.get("sigint_at", 0) < 86400}
    try:
        os.makedirs(os.path.dirname(spath), exist_ok=True)
        with open(spath, "w") as f:
            json.dump(state, f)
    except OSError:
        pass


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
        if s.get("action"):
            line += f" action={s['action']}"
        lines.append(line)
    actions = {s.get("action", "") for s in stalled}
    if any(a.startswith("sigint-sent") for a in actions):
        lines.append("已自动按 Esc (SIGINT): 切到该会话输入「继续」或重新派发任务即可, TUI 未受影响。")
    if any(a.startswith("escalate") for a in actions):
        lines.append("自动 Esc 后仍卡住: 需手动处理 (到该会话按 Esc 后重开窗口/重派任务)。")
    if any(a.startswith("host-ambiguous") for a in actions):
        lines.append("同项目开了多个 qodercli 窗口, 无法确定挂死宿主, 未自动中断: "
                     "请按 file= 路径找到对应会话窗口手动按 Esc。")
    if any(a == "host-not-found" or a.startswith("sigint-failed") for a in actions):
        lines.append("未能自动中断 (宿主进程未找到/信号失败): 请手动检查该会话窗口。")
    if all(not a for a in actions):
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
    p.add_argument("--auto-soft", action="store_true",
                   help="send ONE SIGINT (≈ Esc) to the stalled session's host CLI; "
                        "cooldown-guarded, escalates instead of repeating. Never SIGTERMs")
    p.add_argument("--soft-cooldown-min", type=float, default=120,
                   help="minutes before a session may be SIGINTed again (default: 120)")
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

    if args.auto_soft and stalled:
        apply_auto_soft(stalled, args.qoder_home, args.proc_regex,
                        args.soft_cooldown_min)

    if args.write_flag:
        write_flag(args.write_flag, stalled)

    if args.json:
        print(json.dumps(stalled, indent=2))
    else:
        for s in stalled:
            subs = ", ".join(f"{a['agent']}({a['silent_min']}m)" for a in s["subagents"]) or "n/a"
            action = f" action={s['action']}" if s.get("action") else ""
            print(f"STALLED session={s['session']} silent={s['silent_min']}m "
                  f"pending={','.join(s['pending_tools'])} subagents: {subs}{action}")
        if stalled:
            print("Hint: a hung stream does not recover. Interrupt the session, "
                  "then re-dispatch the task as a fresh agent.", file=sys.stderr)

    if stalled and args.notify:
        notify(stalled)
    return len(stalled)


if __name__ == "__main__":
    sys.exit(main())
