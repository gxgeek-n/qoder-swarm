#!/usr/bin/env python3
"""Pre+PostToolUse hook: track active sub-agents in .swarm/audit/active-agents.json."""
import json, os, sys, uuid
from datetime import datetime, timezone


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def recompute_summary(data):
    r = c = fl = 0
    for k, v in data.items():
        if k == "_summary" or not isinstance(v, dict):
            continue
        s = v.get("status")
        if s == "running":
            r += 1
        elif s == "completed":
            c += 1
        elif s == "failed":
            fl += 1
    data["_summary"] = {"running": r, "completed": c, "failed": fl}


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    if payload.get("tool_name") != "Agent":
        sys.exit(0)

    event = os.environ.get("QODER_HOOK_EVENT", "") or payload.get("_event", "")
    tool_input = payload.get("tool_input", {})
    subagent_type = tool_input.get("subagent_type", "unknown")

    path = os.path.join(os.environ.get("SWARM_HOME", os.getcwd()),
                        ".swarm", "audit", "active-agents.json")
    data = load(path)

    if "Pre" in event:
        aid = f"{subagent_type}-{uuid.uuid4().hex[:8]}"
        data[aid] = {"type": subagent_type, "started": now(), "status": "running"}
    elif "Post" in event:
        resp = payload.get("tool_response", {})
        aid = resp.get("agentId", "") if isinstance(resp, dict) else ""
        entry = data.get(aid) if aid else None
        if not entry:
            for k, v in data.items():
                if k != "_summary" and isinstance(v, dict) \
                   and v.get("status") == "running" and v.get("type") == subagent_type:
                    entry = v
                    aid = k
                    break
        if entry:
            entry["status"] = "failed" if (isinstance(resp, dict) and "error" in resp) else "completed"
            entry["ended"] = now()
    else:
        sys.exit(0)

    recompute_summary(data)
    save(path, data)


if __name__ == "__main__":
    main()
