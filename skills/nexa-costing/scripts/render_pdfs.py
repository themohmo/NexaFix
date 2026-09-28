#!/usr/bin/env python3
"""Render the client quotation and the internal cost sheet from an estimate JSON.

    python render_pdfs.py estimate.json --out DIR

Writes <ref>_Quotation.pdf and <ref>_Cost_Sheet.pdf into DIR (default: the
folder of the JSON file). Relative image paths in the estimate
(meta.cover_images, scope[].image) are resolved against the JSON's folder.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from nexa_costing.costsheet_pdf import render_costsheet  # noqa: E402
from nexa_costing.quote_pdf import render_quote  # noqa: E402


def _resolve(path, base: str):
    if not path or not isinstance(path, str) or os.path.isabs(path):
        return path
    candidate = os.path.join(base, path)
    return candidate if os.path.exists(candidate) else path


def _with_resolved_images(estimate: dict, base: str) -> dict:
    est = copy.deepcopy(estimate)
    meta = est.get("meta") or {}
    if isinstance(meta.get("cover_images"), list):
        meta["cover_images"] = [_resolve(p, base) for p in meta["cover_images"]]
    for item in est.get("scope") or []:
        if isinstance(item, dict) and item.get("image"):
            item["image"] = _resolve(item["image"], base)
    return est


def safe_ref(ref) -> str:
    ref = re.sub(r"[^A-Za-z0-9._-]+", "_", str(ref or "").strip()).strip("._")
    return ref or "Estimate"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Render NexaFix quotation + internal cost sheet PDFs")
    ap.add_argument("estimate", help="path to estimate.json")
    ap.add_argument("--out", default=None, help="output folder (default: next to the JSON)")
    ap.add_argument("--only", choices=["quote", "costsheet"], default=None,
                    help="render just one of the two PDFs")
    args = ap.parse_args(argv)

    src = os.path.abspath(args.estimate)
    with open(src, encoding="utf-8") as fh:
        estimate = json.load(fh)
    base = os.path.dirname(src)
    estimate = _with_resolved_images(estimate, base)
    out_dir = os.path.abspath(args.out or base)
    os.makedirs(out_dir, exist_ok=True)
    ref = safe_ref((estimate.get("meta") or {}).get("ref"))

    if args.only in (None, "quote"):
        print(render_quote(estimate, os.path.join(out_dir, f"{ref}_Quotation.pdf")))
    if args.only in (None, "costsheet"):
        print(render_costsheet(estimate, os.path.join(out_dir, f"{ref}_Cost_Sheet.pdf")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
