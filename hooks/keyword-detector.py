#!/usr/bin/env python3
"""UserPromptSubmit hook: detect swarm-related keywords in the user prompt.

Reads JSON from stdin (Qoder hook payload), extracts the prompt text,
and prints a system-reminder line when a swarm trigger keyword is found.
If stdin is empty or not valid JSON, exits silently.
"""
import json
import re
import sys

KEYWORDS = [
    "plan-and-review", "start-work", "five-agent", "five agent",
    "swarm", "self-improve", "ultrawork", "ulw-loop", "magentic",
    "team mode", "hyperplan", "hostile critic", "autopilot", "ralph",
    "init-deep", "ultraresearch", "remove slop", "deslop", "skillify",
    "code review", "review my work", "qa my work",
    "对抗审查", "对抗规划", "代码review", "代码审查", "审查代码",
    "自举", "自进化", "团队模式", "全自动", "一键完成",
    "深度研究", "彻底研究", "清理ai代码", "一直跑到完成",
    "不停直到完成", "走完整流程",
]
_PATTERN = re.compile("|".join(re.escape(k) for k in KEYWORDS), re.IGNORECASE)


def extract_prompt(data):
    """Extract user prompt text from various JSON payload shapes."""
    for key in ("prompt", "message", "content"):
        val = data.get(key)
        if isinstance(val, str) and val:
            return val
    # message.content nested shape
    msg = data.get("message")
    if isinstance(msg, dict):
        c = msg.get("content")
        if isinstance(c, str) and c:
            return c
    return ""


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        return
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return
    if not isinstance(data, dict):
        return
    prompt = extract_prompt(data)
    if not prompt:
        return
    match = _PATTERN.search(prompt)
    if match:
        keyword = match.group(0)
        print(f"→ Swarm pattern detected: '{keyword}'. Skill 'swarm' should activate.")


if __name__ == "__main__":
    main()
