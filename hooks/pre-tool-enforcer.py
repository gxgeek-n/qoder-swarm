#!/usr/bin/env python3
"""PreToolUse hook: enforce swarm rules before Agent dispatch.

Checks prompt size budget, subagent_type validity, and cancel signals.
Outputs warnings to stdout (injected as system reminders). stdlib only.
"""
import json, os, sys
from pathlib import Path

_PROMPT_BUDGET = 2500
_SWARM_HOME = Path(os.environ.get("SWARM_HOME", os.getcwd()))
_AGENTS_DIR = _SWARM_HOME / "agents"
_CANCEL_SIGNAL = _SWARM_HOME / ".swarm" / "cancel-signal.json"


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return
    if payload.get("tool_name") != "Agent":
        return
    ti = payload.get("tool_input", {})
    prompt = ti.get("prompt", "") or ""
    subagent_type = ti.get("subagent_type", "") or ""

    # a. Prompt size check (warning only, don't block)
    n = len(prompt)
    if n > _PROMPT_BUDGET:
        print(f"⚠️ Prompt exceeds {_PROMPT_BUDGET} char budget ({n} chars). "
              f"Consider extracting heredocs to reference files.")

    # b. Model validity: swarm-* subagent_type must have a matching agent file
    if subagent_type.startswith("swarm-"):
        agent_file = _AGENTS_DIR / f"{subagent_type}.md"
        if not agent_file.is_file():
            available = sorted(p.stem for p in _AGENTS_DIR.glob("swarm-*.md")) \
                if _AGENTS_DIR.is_dir() else []
            print(f"⚠️ Unknown swarm agent: {subagent_type}. "
                  f"Available: {', '.join(available)}")

    # c. Cancel signal active
    if _CANCEL_SIGNAL.is_file():
        print("⚠️ Cancel signal active. This dispatch may be wasted. Check cancel status.")


if __name__ == "__main__":
    main()
