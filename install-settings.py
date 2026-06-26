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

# Marker that identifies hooks added by this installer
SWARM_MARKER = "swarm-"

# Hooks we want to install. The 'script' field is the basename in <qoder_home>/hooks/;
# the actual command path is built at install time from --qoder-home so non-default
# install locations work correctly.
SWARM_HOOKS = {
    "PostToolUse": {
        "matcher": "Edit|Write|NotebookEdit",
        "script": "swarm-comment-checker.sh",
        "timeout": 5,
    },
    "Stop": {
        "matcher": "*",
        "script": "swarm-stop-continuation.sh",
        "timeout": 10,
    },
}


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


def hook_entry_for(event_name, command):
    """Build a single hook block in the schema Qoder expects."""
    cfg = SWARM_HOOKS[event_name]
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


def already_installed(hooks_section, event_name):
    """Check if any swarm hook is already in this event."""
    entries = hooks_section.get(event_name, [])
    for entry in entries:
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            if SWARM_MARKER in cmd:
                return True
    return False


def install(settings, event_name, qoder_home):
    """Append swarm hook block to the event. Returns True if changed."""
    cfg = SWARM_HOOKS[event_name]
    settings.setdefault("hooks", {})
    section = settings["hooks"]

    if already_installed(section, event_name):
        return False

    command = hook_command_path(qoder_home, cfg["script"])
    section.setdefault(event_name, [])
    section[event_name].append(hook_entry_for(event_name, command))
    return True


def uninstall(settings, event_name):
    """Remove all swarm hooks from this event. Returns True if changed."""
    section = settings.get("hooks", {})
    if event_name not in section:
        return False

    changed = False
    new_entries = []
    for entry in section[event_name]:
        kept_hooks = [h for h in entry.get("hooks", []) if SWARM_MARKER not in h.get("command", "")]
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
