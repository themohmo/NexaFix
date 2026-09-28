#!/usr/bin/env python3
"""NexaFix costing engine — project spec in, full costing + NexaFix quotation out.

    python estimate.py project.yaml                 # writes to ./out/<ref>/
    python estimate.py project.json --out ~/quotes  # choose output folder
    python estimate.py project.yaml --no-pdf        # JSON + summary only
    python estimate.py project.yaml --rates my_rates.toml

Prints a markdown summary (totals, margin, shopping list, warnings) and writes:
    <ref>_Quotation.pdf   client quotation in the NexaFix template
    <ref>_Cost_Sheet.pdf  internal cost sheet (never send to clients)
    estimate.json         everything the engine computed
    summary.md            the printed summary
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nexa_costing.engine import run_estimate  # noqa: E402
from nexa_costing.ratebook import Ratebook  # noqa: E402
from nexa_costing.spec import load_spec_file  # noqa: E402
from nexa_costing.summary import markdown  # noqa: E402
from nexa_costing.util import SpecError  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="NexaFix project costing")
    ap.add_argument("spec", help="project spec (.yaml / .yml / .json)")
    ap.add_argument("--rates", help="rate book (default: rates.toml in the skill, or $NEXA_RATES)")
    ap.add_argument("--out", default="out", help="output folder (default ./out)")
    ap.add_argument("--no-pdf", action="store_true", help="skip PDF rendering")
    ap.add_argument("--date", help="issue date dd/mm/yyyy (default today)")
    args = ap.parse_args(argv)

    try:
        rates = Ratebook.load(args.rates)
        spec = load_spec_file(args.spec)
        today = dt.datetime.strptime(args.date, "%d/%m/%Y").date() if args.date else None
        if args.date:
            spec.setdefault("project", {}).setdefault("date", args.date)
        est = run_estimate(spec, rates, base_dir=Path(args.spec).resolve().parent, today=today)
    except SpecError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    ref = est["meta"]["ref"]
    out_dir = Path(args.out).expanduser() / ref
    out_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    (out_dir / "estimate.json").write_text(json.dumps(est, indent=2, ensure_ascii=False), encoding="utf-8")
    files["data"] = str(out_dir / "estimate.json")

    if not args.no_pdf:
        try:
            from nexa_costing.quote_pdf import render_quote
            from nexa_costing.costsheet_pdf import render_costsheet
        except ModuleNotFoundError as exc:  # reportlab missing
            print(f"(PDFs skipped: {exc}. Install with `pip install reportlab`.)", file=sys.stderr)
        else:
            q = render_quote(est, str(out_dir / f"{ref}_Quotation.pdf"))
            c = render_costsheet(est, str(out_dir / f"{ref}_Cost_Sheet.pdf"))
            files["quotation"] = q
            files["cost sheet"] = c

    md = markdown(est, files)
    (out_dir / "summary.md").write_text(md, encoding="utf-8")
    print(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
