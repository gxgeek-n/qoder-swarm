#!/usr/bin/env python3
"""PostToolUse hook: verify Agent tool output quality.

Checks Agent responses for empty-done (<50 chars) and oversized output (>50KB).
Empty-done records are appended to .swarm/audit/empty-dones-live.jsonl.
Reads JSON payload from stdin; uses QODER_TOOL_NAME env for fast-path skip.
"""
import json, sys, os
from datetime import datetime, timezone
from pathlib import Path

_EMPTY = 50
_LARGE = 50 * 1024
_AUDIT = Path(os.environ.get("SWARM_HOME", os.getcwd())) / ".swarm" / "audit" / "empty-dones-live.jsonl"


def main():
    env_tool = os.environ.get("QODER_TOOL_NAME", "")
    if env_tool and env_tool != "Agent":
        return
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    if payload.get("tool_name") != "Agent":
        return

    resp = payload.get("tool_response", {})
    if not isinstance(resp, dict):
        return
    content = resp.get("content", "")
    if not isinstance(content, str):
        content = str(content) if content else ""
    n = len(content)

    if n < _EMPTY:
        _AUDIT.parent.mkdir(parents=True, exist_ok=True)
        rec = {"ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "content_len": n, "preview": content[:200]}
        with _AUDIT.open("a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"[swarm:post-verifier] WARNING: Agent returned {n} chars (<{_EMPTY}). "
              f"Likely empty-done. Logged to {_AUDIT}.")

    if n > _LARGE:
        print(f"[swarm:post-verifier] WARNING: Agent returned {n:,} chars "
              f"({n // 1024}KB). Consider compaction before next dispatch.")


if __name__ == "__main__":
    main()
