#!/usr/bin/env python3
"""PostToolUse hook: auto-ingest swarm outputs into obsidian-wiki vault.

Triggers when an Agent completes with "STATUS: DONE" mentioning .swarm/ paths.
Scans those paths for .md reports and writes distilled wiki pages with frontmatter.
"""
import json, os, re, sys
from datetime import datetime
from pathlib import Path


def _vault_path():
    vp = os.environ.get("OBSIDIAN_VAULT_PATH")
    if not vp:
        cfg = Path.home() / ".obsidian-wiki" / "config"
        if cfg.is_file():
            for line in cfg.read_text().splitlines():
                if line.startswith("OBSIDIAN_VAULT_PATH="):
                    vp = line.split("=", 1)[1].strip()
                    break
    return Path(vp) if vp else None


def _category(path, body):
    p, c = str(path).lower(), body.lower()[:200]
    if "review" in p or "review" in c: return "synthesis"
    if "research" in p: return "references"
    if "plan" in p: return "projects"
    return "references"


def _first_line(body, prefix):
    for s in (l.strip() for l in body.splitlines()):
        if s.startswith(prefix) and ":" in s:
            return s.split(":", 1)[1].strip()
    return ""


def main():
    if os.environ.get("QODER_TOOL_NAME", "") not in ("", "Agent"):
        return
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    if payload.get("tool_name") != "Agent":
        return
    resp = payload.get("tool_response", {})
    content = resp.get("content", "") if isinstance(resp, dict) else ""
    if not isinstance(content, str):
        content = str(content) if content else ""
    if "STATUS: DONE" not in content:
        return
    swarm_paths = re.findall(r"\.swarm/[^\s\)\]\"']+", content)
    if not swarm_paths:
        return
    vault = _vault_path()
    if not vault or not vault.is_dir():
        return
    today = datetime.now().strftime("%Y-%m-%d")
    base = Path(os.environ.get("SWARM_HOME", os.getcwd()))
    ingested = 0
    for sp in swarm_paths:
        src = base / sp
        mds = [src] if src.is_file() and src.suffix == ".md" else \
              sorted(src.glob("*.md")) if src.is_dir() else []
        for mf in mds:
            body = mf.read_text(errors="replace")
            cat = _category(mf, body)
            title = next((l.strip().lstrip("#").strip()[:120]
                          for l in body.splitlines() if l.strip()), "Untitled")
            pat = (_first_line(body, "PATTERN:") or "unknown").lower()
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:60] or "untitled"
            dest = vault / cat / f"{today}-{slug}.md"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(
                f"---\ntitle: {title}\ndate: {today}\nsource: {mf}\n"
                f"confidence: HIGH\nlast_confirmed: {today}\n"
                f"tags: [swarm, auto-ingested, {pat}]\n---\n\n{body}")
            with (vault / "index.md").open("a") as f:
                f.write(f"- [{title}]({cat}/{dest.name})\n")
            with (vault / "log.md").open("a") as f:
                f.write(f"## [{today}] ingest | {title}\n- source: {mf}\n- category: {cat}\n")
            ingested += 1
    if ingested:
        print(f"[swarm:wiki-ingest] {ingested} page(s) ingested into vault.")


if __name__ == "__main__":
    main()
