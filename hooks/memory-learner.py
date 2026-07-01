#!/usr/bin/env python3
"""PostToolUse hook: auto-extract learnings from Agent outputs into .swarm/memory/."""
import sys, json, os
from datetime import datetime

KEYWORDS = ("lesson learned", "踩坑", "root cause", "discovered", "找到根因", "key insight")


def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        return
    # Fast path: skip non-Agent tools immediately
    if data.get("tool_name") != "Agent":
        return
    if data.get("_action", "").upper() != "SUCCESS":
        return
    resp = data.get("tool_response", {})
    content = resp.get("content", "") if isinstance(resp, dict) else str(resp)
    if not content:
        return
    low = content.lower()
    if not any(kw in low for kw in KEYWORDS):
        return
    # Learnable — append to memory + audit trail
    agent = resp.get("agentType", "unknown") if isinstance(resp, dict) else "unknown"
    summary = content[:100].replace("\n", " ").strip()
    date = datetime.now().strftime("%Y-%m-%d")
    cwd = data.get("cwd") or os.getcwd()
    mem_dir = os.path.join(cwd, ".swarm", "memory")
    aud_dir = os.path.join(cwd, ".swarm", "audit")
    os.makedirs(mem_dir, exist_ok=True)
    os.makedirs(aud_dir, exist_ok=True)
    with open(os.path.join(mem_dir, "auto-learned.md"), "a") as f:
        f.write(f"## [{date}] {agent}: {summary}\n\n")
    entry = {"date": date, "agent": agent, "summary": summary,
             "keywords": [kw for kw in KEYWORDS if kw in low]}
    with open(os.path.join(aud_dir, "auto-learns.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
