#!/usr/bin/env python3
"""Wiki confidence lifecycle: report, decay, and reinforce page frontmatter."""
import sys, os, re, datetime, glob

DECAY_DAYS = 30
LEVELS = ["LOW", "MEDIUM", "HIGH"]
FM_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
KV_RE = re.compile(r"^(\w+):\s*(.+)$", re.MULTILINE)

def read_fm(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = FM_RE.match(text)
    if not m: return None, text, None
    kvs = {k: v.strip().strip('"\'') for k, v in KV_RE.findall(m.group(1))}
    return kvs, text[m.end():], m.group(1)

def write_fm(path, kvs, body):
    lines = ["---"] + [f"{k}: {v}" for k, v in kvs.items()] + ["---"]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n" + body)

def age_days(date_str):
    if not date_str: return None
    try: return (datetime.date.today() - datetime.date.fromisoformat(date_str)).days
    except ValueError: return None

def fmt_age(d): return "?" if d is None else f"{d}d" if d < 365 else f"{d//365}y{d%365}d"

def all_pages(vault): return sorted(glob.glob(os.path.join(vault, "**/*.md"), recursive=True))

def cmd_report(vault):
    for p in all_pages(vault):
        kvs, _, _ = read_fm(p)
        if kvs is None: continue
        conf = kvs.get("confidence", "-")
        lc = kvs.get("last_confirmed", "-")
        print(f"{conf:8} {fmt_age(age_days(lc) if lc != '-' else None):>8} {lc:12} {os.path.relpath(p, vault)}")

def cmd_decay(vault):
    for p in all_pages(vault):
        kvs, body, _ = read_fm(p)
        if kvs is None: continue
        if "confidence" not in kvs:
            kvs["confidence"] = "MEDIUM"
            kvs["last_confirmed"] = datetime.date.fromtimestamp(os.path.getmtime(p)).isoformat()
            write_fm(p, kvs, body); continue
        age = age_days(kvs.get("last_confirmed", ""))
        if age is not None and age > DECAY_DAYS:
            idx = LEVELS.index(kvs["confidence"]) if kvs["confidence"] in LEVELS else 1
            if idx > 0:
                kvs["confidence"] = LEVELS[idx - 1]
                write_fm(p, kvs, body)
                print(f"DECAY {os.path.relpath(p, vault)} -> {kvs['confidence']}")

def cmd_reinforce(page):
    kvs, body, _ = read_fm(page)
    if kvs is None: print(f"SKIP {page} (no frontmatter)"); sys.exit(1)
    kvs["confidence"] = "HIGH"
    kvs["last_confirmed"] = datetime.date.today().isoformat()
    write_fm(page, kvs, body)
    print(f"REINFORCED {page}: confidence=HIGH, last_confirmed={kvs['last_confirmed']}")

def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(f"Usage: {sys.argv[0]} <vault> [--decay] [--reinforce <page>] [--report]"); sys.exit(0)
    vault = args[0]
    if "--decay" in args: cmd_decay(vault)
    elif "--reinforce" in args: cmd_reinforce(args[args.index("--reinforce") + 1])
    else: cmd_report(vault)

if __name__ == "__main__":
    main()
