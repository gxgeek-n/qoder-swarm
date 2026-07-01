#!/usr/bin/env python3
"""SessionStart hook: restore active swarm pattern context.

Scans .swarm/*/state.json for running/cancelled patterns, counts memory
files, and checks audit freshness. If no .swarm/ dir exists, exits silently.
"""
import json, os, sys, glob, time

SWARM_HOME = os.environ.get("SWARM_HOME", os.getcwd())
SWARM_DIR = os.path.join(SWARM_HOME, ".swarm")

if not os.path.isdir(SWARM_DIR):
    sys.exit(0)

messages = []

# --- Scan active/cancelled patterns ---
for state_file in glob.glob(os.path.join(SWARM_DIR, "*/state.json")):
    pattern = os.path.basename(os.path.dirname(state_file))
    try:
        with open(state_file) as f:
            state = json.load(f)
    except (json.JSONDecodeError, OSError):
        continue
    status = state.get("status", "")
    stage = state.get("stage", "?")
    if status == "running":
        messages.append(f"⚡ Active swarm pattern: {pattern} at {stage}. Resume with 'continue' or cancel with '/cancel'.")
    elif status == "cancelled":
        messages.append(f"⏸️ Paused pattern: {pattern} (cancelled at stage {stage}). Say 'resume' to continue from checkpoint.")

# --- Memory count ---
mem_count = len(glob.glob(os.path.join(SWARM_DIR, "memory", "*.md")))
if mem_count:
    messages.append(f"swarm: {mem_count} memory file(s) stored.")

# --- Audit freshness ---
audit_file = os.path.join(SWARM_DIR, "audit", "empty-dones.jsonl")
if os.path.isfile(audit_file):
    mtime = os.path.getmtime(audit_file)
    age_h = (time.time() - mtime) / 3600
    if age_h < 24:
        messages.append(f"swarm: last audit activity {age_h:.1f}h ago.")

for msg in messages:
    print(msg)
