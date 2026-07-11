#!/usr/bin/env python3
"""
One-way sync of an architecture-docs repo into the Obsidian vault as a
read-only mirror, so the current branch is readable from any Obsidian-linked
device for nightly review.

Copies documentation (Markdown + referenced images) from the source repo into
`<vault>/_architecture-docs/`, preserving folder structure. It is a mirror,
not a merge: files removed from the repo are pruned so the mirror always
reflects the current branch exactly.

The mirror is READ-ONLY by convention:
  - It is regenerated from the repo; edits made in the vault are overwritten.
  - Scheduled vault agents are denied write access to it.

Usage:
    python scripts/sync-docs-to-vault.py [--repo DIR] [--vault DIR] [--dry-run]

Defaults assume repo, vault, and this tooling repo are siblings, e.g.:
    <parent>/SECU_Document_Automation   (source repo)
    <parent>/lovelace                   (the vault)
    <parent>/claude-repo-tools          (this repo)
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# The dev parent that holds the sibling repos (…/dev).
PARENT = Path(__file__).resolve().parents[2]
MIRROR_NAME = "_architecture-docs"
MARKER = "_ABOUT.md"

INCLUDE_EXT = {".md", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
EXCLUDE_DIRS = {
    ".git", ".github", ".vale", ".claude", ".obsidian",
    "node_modules", "exports", "scripts", "__pycache__", ".pytest_cache",
}


def wanted_files(root: Path) -> list[Path]:
    out: list[Path] = []
    for p in root.rglob("*"):
        if p.is_dir():
            continue
        if any(part in EXCLUDE_DIRS for part in p.relative_to(root).parts):
            continue
        if p.suffix.lower() in INCLUDE_EXT:
            out.append(p)
    return out


def git(repo: Path, *args: str) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "unknown"


def marker_text(repo: Path) -> str:
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    commit = git(repo, "rev-parse", "--short", "HEAD")
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return (
        "---\n"
        "title: \"Architecture Docs — Read-Only Mirror\"\n"
        "tags: [meta, system, architecture-docs, read-only]\n"
        "---\n\n"
        "# Architecture Docs — Read-Only Mirror\n\n"
        "> **Do not edit anything in this folder.** It is an auto-generated,\n"
        "> one-way mirror of the `architecture-docs` repository, refreshed by\n"
        "> `claude-repo-tools/scripts/sync-docs-to-vault.py`. Edits here are\n"
        "> overwritten on the next sync. Make changes in the repo instead.\n\n"
        f"- **Source branch:** `{branch}`\n"
        f"- **Source commit:** `{commit}`\n"
        f"- **Last synced:** {stamp}\n"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, default=PARENT / "SECU_Document_Automation",
                    help="Source architecture-docs repo (default: sibling SECU_Document_Automation).")
    ap.add_argument("--vault", type=Path, default=PARENT / "lovelace",
                    help="Obsidian vault (default: sibling 'lovelace').")
    ap.add_argument("--dry-run", action="store_true", help="Report actions without writing.")
    args = ap.parse_args()

    repo = args.repo.resolve()
    if not (repo / ".git").exists():
        print(f"ERROR: source repo not found (no .git): {repo}", file=sys.stderr)
        return 1
    if not args.vault.is_dir():
        print(f"ERROR: vault not found: {args.vault}", file=sys.stderr)
        return 1

    mirror = (args.vault / MIRROR_NAME).resolve()
    sources = wanted_files(repo)
    expected = {(mirror / p.relative_to(repo)) for p in sources}
    expected.add(mirror / MARKER)

    copied = updated = pruned = 0
    if not args.dry_run:
        mirror.mkdir(parents=True, exist_ok=True)

    text_ext = {".md", ".svg"}
    for src in sources:
        dst = mirror / src.relative_to(repo)
        data = src.read_bytes()
        # Normalize text to LF so the mirror is stable regardless of the repo's
        # CRLF checkout and so agent re-saves (which normalize to LF) are no-ops.
        if src.suffix.lower() in text_ext:
            data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        if dst.exists() and dst.read_bytes() == data:
            continue
        is_new = not dst.exists()
        if not args.dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
        copied += is_new
        updated += (not is_new)

    if not args.dry_run:
        (mirror / MARKER).write_text(marker_text(repo), encoding="utf-8", newline="\n")

    if mirror.exists():
        for p in mirror.rglob("*"):
            if p.is_file() and p.resolve() not in expected:
                pruned += 1
                if not args.dry_run:
                    p.unlink()
        if not args.dry_run:
            for d in sorted(mirror.rglob("*"), key=lambda x: len(x.parts), reverse=True):
                if d.is_dir() and not any(d.iterdir()):
                    d.rmdir()

    prefix = "[dry-run] " if args.dry_run else ""
    print(f"{prefix}Source: {repo}")
    print(f"{prefix}Mirror: {mirror}")
    print(f"{prefix}sources={len(sources)}  new={copied}  updated={updated}  pruned={pruned}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
