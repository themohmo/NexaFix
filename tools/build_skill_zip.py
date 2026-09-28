#!/usr/bin/env python3
"""Package the nexa-costing skill as a zip for upload to Claude.ai
(Settings > Capabilities > Skills > Upload skill).

    python tools/build_skill_zip.py            # -> dist/nexa-costing.zip

The zip holds the current rates.toml, so rebuild and re-upload after
changing prices if you use the skill on Claude.ai.
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "nexa-costing"
OUT = ROOT / "dist" / "nexa-costing.zip"
SKIP_DIRS = {"__pycache__", ".pytest_cache", "out"}
SKIP_SUFFIXES = {".pyc", ".png"}


def main() -> int:
    if not (SKILL / "SKILL.md").exists():
        print(f"SKILL.md not found in {SKILL}", file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(SKILL.rglob("*")):
            rel = p.relative_to(SKILL)
            if p.is_dir() or any(part in SKIP_DIRS for part in rel.parts) or p.suffix in SKIP_SUFFIXES:
                continue
            z.write(p, Path("nexa-costing") / rel)
            n += 1
    print(f"{OUT} ({n} files, {OUT.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
