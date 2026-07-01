#!/usr/bin/env python3
"""
qoder-swarm settings installer.
Idempotently merges swarm hooks into ~/.qoder/settings.json.

Usage:
  python3 install-settings.py [--qoder-home DIR] [--uninstall] [--dry-run]
"""

import argparse
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

# Hooks we want to install. The 'script' field is the basename in <qoder_home>/hooks/;
# the actual command path is built at install time from --qoder-home so non-default
# install locations work correctly.
# Each event maps to a LIST of hook configs so multiple hooks can share one event.
SWARM_HOOKS = {
    "PreToolUse": [
        {
            "matcher": "Agent",
            "script": "subagent-tracker.py",
            "timeout": 5,
        },
        {
            "matcher": "Agent",
            "script": "pre-tool-enforcer.py",
            "timeout": 5,
        },
    ],
    "PostToolUse": [
        {
            "matcher": "Edit|Write|NotebookEdit",
            "script": "swarm-comment-checker.sh",
            "timeout": 5,
        },
        {
            "matcher": "Agent",
            "script": "post-tool-verifier.py",
            "timeout": 5,
        },
        {
            "matcher": "Agent",
            "script": "memory-learner.py",
            "timeout": 5,
        },
        {
            "matcher": "Agent",
            "script": "subagent-tracker.py",
            "timeout": 5,
        },
        {
            "matcher": "Agent",
            "script": "swarm-wiki-ingest.py",
            "timeout": 10,
        },
    ],
    "Stop": [
        {
            "matcher": "*",
            "script": "swarm-stop-continuation.sh",
            "timeout": 10,
        },
    ],
    "UserPromptSubmit": [
        {
            "matcher": "*",
            "script": "keyword-detector.py",
            "timeout": 5,
        },
    ],
    "SessionStart": [
        {
            "matcher": "*",
            "script": "session-start.py",
            "timeout": 5,
        },
    ],
}


def _all_scripts():
    """Return set of all swarm hook script basenames."""
    names = set()
    for cfgs in SWARM_HOOKS.values():
        for c in cfgs:
            names.add(c["script"])
    return names


def hook_command_path(qoder_home, script_name):
    """Build the command path for a hook script under qoder_home.

    Uses '~/.qoder/...' tilde form only when qoder_home resolves to the user's
    default home so settings.json stays portable. Otherwise uses the resolved
    absolute path.
    """
    qoder_home = Path(qoder_home).expanduser()
    default_home = (Path.home() / ".qoder").resolve()
    if qoder_home.resolve() == default_home:
        return f"~/.qoder/hooks/{script_name}"
    return str(qoder_home / "hooks" / script_name)


def load_settings(path):
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def backup_settings(path):
    if not path.exists():
        return None
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = path.with_suffix(f".json.swarm-backup-{ts}")
    shutil.copy2(path, backup)
    return backup


def hook_entry_for(cfg, command):
    """Build a single hook block in the schema Qoder expects."""
    return {
        "matcher": cfg["matcher"],
        "hooks": [
            {
                "type": "command",
                "command": command,
                "timeout": cfg["timeout"],
            }
        ],
    }


def script_installed(hooks_section, event_name, script_name):
    """Check if a specific swarm hook script is already installed in this event."""
    for entry in hooks_section.get(event_name, []):
        for h in entry.get("hooks", []):
            if script_name in h.get("command", ""):
                return True
    return False


def install(settings, event_name, qoder_home):
    """Append swarm hook block(s) to the event. Returns True if changed."""
    settings.setdefault("hooks", {})
    section = settings["hooks"]
    section.setdefault(event_name, [])
    changed = False
    for cfg in SWARM_HOOKS[event_name]:
        if script_installed(section, event_name, cfg["script"]):
            continue
        command = hook_command_path(qoder_home, cfg["script"])
        section[event_name].append(hook_entry_for(cfg, command))
        changed = True
    return changed


def uninstall(settings, event_name):
    """Remove all swarm hooks from this event. Returns True if changed."""
    section = settings.get("hooks", {})
    if event_name not in section:
        return False

    scripts = _all_scripts()
    changed = False
    new_entries = []
    for entry in section[event_name]:
        kept_hooks = [h for h in entry.get("hooks", [])
                      if not any(s in h.get("command", "") for s in scripts)]
        if len(kept_hooks) != len(entry.get("hooks", [])):
            changed = True
        if kept_hooks:
            entry["hooks"] = kept_hooks
            new_entries.append(entry)
        # if all hooks in this entry were swarm hooks, drop the entry entirely

    if changed:
        if new_entries:
            section[event_name] = new_entries
        else:
            del section[event_name]
    return changed


def write_settings(path, settings, dry_run=False):
    body = json.dumps(settings, indent=2, ensure_ascii=False) + "\n"
    if dry_run:
        print("--- DRY RUN: would write the following ---")
        print(body)
        return
    with open(path, "w") as f:
        f.write(body)


def main():
    parser = argparse.ArgumentParser(description="Install/uninstall qoder-swarm hooks in settings.json")
    parser.add_argument("--qoder-home", default=str(Path.home() / ".qoder"), help="Qoder config dir (default: ~/.qoder)")
    parser.add_argument("--uninstall", action="store_true", help="Remove swarm hooks instead of installing")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change, don't write")
    args = parser.parse_args()

    qoder_home = Path(args.qoder_home).expanduser()
    settings_path = qoder_home / "settings.json"

    if not qoder_home.exists():
        print(f"ERROR: Qoder home does not exist: {qoder_home}", file=sys.stderr)
        sys.exit(1)

    settings = load_settings(settings_path)
    action = "uninstall" if args.uninstall else "install"

    changes = []
    for event_name in SWARM_HOOKS:
        if args.uninstall:
            if uninstall(settings, event_name):
                changes.append(f"removed swarm hook from {event_name}")
        else:
            if install(settings, event_name, qoder_home):
                changes.append(f"added swarm hook to {event_name}")

    if not changes:
        print(f"Nothing to do — swarm hooks already {'absent' if args.uninstall else 'present'}.")
        return

    print(f"Changes ({action}):")
    for c in changes:
        print(f"  • {c}")

    if not args.dry_run:
        backup = backup_settings(settings_path)
        if backup:
            print(f"  ✓ Backed up to: {backup}")

    write_settings(settings_path, settings, dry_run=args.dry_run)

    if not args.dry_run:
        print(f"  ✓ Updated: {settings_path}")
        print()
        print("Restart Qoder CLI for hooks to take effect.")


if __name__ == "__main__":
    main()
