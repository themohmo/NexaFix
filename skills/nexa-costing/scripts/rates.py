#!/usr/bin/env python3
"""View and update the NexaFix rate book (rates.toml) without opening it.

    python rates.py show                     # every material & trade with cost / sell / status
    python rates.py show spc                 # filter by key, name or category
    python rates.py get materials.spc_plank  # one entry in full
    python rates.py set materials.spc_plank.cost 38
    python rates.py set materials.spc_plank.sell 115
    python rates.py set trades.carpenter.cost_per_hour 24
    python rates.py set pricing.contingency_pct 7
    python rates.py add spc_oak_plank --name "SPC oak plank 1220 x 180" --unit plank \\
          --category flooring --cost 30 --sell 95 --length-mm 1220 --width-mm 180 --like spc_plank
    python rates.py placeholders            # what still needs your real prices
    python rates.py confirm materials.tile_60x60   # keep the price, mark it as yours

Setting a cost / sell / hourly rate marks the entry status="owner" so it is
no longer flagged as a placeholder in quotes.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nexa_costing.ratebook import Ratebook, coerce, rates_path, set_dotted, set_values  # noqa: E402
from nexa_costing.util import SpecError  # noqa: E402


def _fmt(v) -> str:
    if v is None or v == "":
        return "-"
    if isinstance(v, float):
        return f"{v:,.2f}".rstrip("0").rstrip(".")
    return str(v)


def cmd_show(rb: Ratebook, flt: str | None):
    f = (flt or "").lower()
    rows = []
    for k, m in rb.materials.items():
        hay = f"{k} {m.get('name', '')} {m.get('category', '')}".lower()
        if f and f not in hay:
            continue
        sell = m.get("sell")
        sell_txt = _fmt(sell) if sell else f"{rb.unit_sell(m):,.2f} (+{rb.markup_pct(m):g}%)"
        rows.append((m.get("category", ""), k, m.get("name", ""), m.get("unit", ""), _fmt(m.get("cost")), sell_txt,
                     "PLACEHOLDER" if rb.is_placeholder(m) else m.get("status", "")))
    rows.sort()
    if rows:
        print(f"{'category':<17} {'key':<24} {'unit':<6} {'cost':>9} {'sell':>18}  status  name")
        for cat, k, name, unit, cost, sell, st in rows:
            print(f"{cat:<17} {k:<24} {unit:<6} {cost:>9} {sell:>18}  {st:<11} {name}")
    trows = [(k, t) for k, t in rb.trades.items() if not f or f in f"{k} {t.get('label', '')} labour trade".lower()]
    if trows:
        print(f"\n{'trade':<14} {'where':<9} {'cost/h':>7} {'sell/h':>7}  status       label")
        for k, t in trows:
            st = "PLACEHOLDER" if rb.is_placeholder(t) else t.get("status", "")
            print(f"{k:<14} {t.get('where', ''):<9} {_fmt(t.get('cost_per_hour')):>7} {_fmt(t.get('sell_per_hour')):>7}  {st:<12} {t.get('label', '')}")


def cmd_get(rb: Ratebook, dotted: str):
    node = rb.data
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            raise SpecError(f"{dotted} not found")
        node = node[part]
    if isinstance(node, dict):
        for k, v in node.items():
            print(f"{k} = {v!r}")
    else:
        print(repr(node))


def cmd_placeholders(rb: Ratebook):
    mats = rb.placeholder_materials()
    trades = rb.placeholder_trades()
    if not mats and not trades:
        print("All rates are confirmed. Nothing is running on placeholder prices.")
        return
    print(f"{len(mats)} materials and {len(trades)} trades still use researched market defaults.\n"
          "Send Claude your supplier prices (or run `rates.py set ...`) to replace them.\n")
    by_cat: dict[str, list] = {}
    for k in mats:
        by_cat.setdefault(rb.materials[k].get("category", "other"), []).append(k)
    for cat, keys in sorted(by_cat.items()):
        print(f"[{cat}]")
        for k in keys:
            m = rb.materials[k]
            print(f"  {k:<24} {_fmt(m.get('cost')):>8} / {m.get('unit', '')}   {m.get('name', '')}")
    if trades:
        print("[labour]")
        for k in trades:
            t = rb.trades[k]
            print(f"  {k:<24} {_fmt(t.get('cost_per_hour')):>8} / h cost, {_fmt(t.get('sell_per_hour'))} / h sell   {t.get('label', '')}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="NexaFix rate book")
    ap.add_argument("--rates", help="rate book path (default rates.toml in the skill)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show")
    s.add_argument("filter", nargs="?")
    g = sub.add_parser("get")
    g.add_argument("key")
    st = sub.add_parser("set")
    st.add_argument("key", help="e.g. materials.spc_plank.cost")
    st.add_argument("value")
    st.add_argument("--keep-status", action="store_true", help="don't mark as owner-confirmed")
    c = sub.add_parser("confirm")
    c.add_argument("keys", nargs="+", help="e.g. materials.tile_60x60 trades.helper")
    sub.add_parser("placeholders")
    a = sub.add_parser("add", help="add a new material")
    a.add_argument("key")
    a.add_argument("--name", required=True)
    a.add_argument("--unit", required=True)
    a.add_argument("--cost", type=float, required=True)
    a.add_argument("--sell", type=float)
    a.add_argument("--category", default="sundries")
    a.add_argument("--length-mm", type=float)
    a.add_argument("--width-mm", type=float)
    a.add_argument("--pack-size", type=float)
    a.add_argument("--waste-pct", type=float)
    a.add_argument("--like", help="copy other fields (install hours, trims, layout...) from this material")
    args = ap.parse_args(argv)

    path = rates_path(args.rates)
    try:
        rb = Ratebook.load(path)
        if args.cmd == "show":
            cmd_show(rb, args.filter)
        elif args.cmd == "get":
            cmd_get(rb, args.key)
        elif args.cmd == "placeholders":
            cmd_placeholders(rb)
        elif args.cmd == "set":
            for ch in set_dotted(path, args.key, coerce(args.value), mark_owner=not args.keep_status):
                print(ch)
        elif args.cmd == "confirm":
            for k in args.keys:
                for ch in set_values(path, k, {"status": "owner"}):
                    print(ch)
        elif args.cmd == "add":
            if args.key in rb.materials:
                raise SpecError(f"materials.{args.key} already exists — use `set` to change it")
            vals = {}
            if args.like:
                base = rb.material(args.like)
                vals.update({k: v for k, v in base.items() if k not in ("key", "name", "short", "client_name", "status")})
            vals.update({"name": args.name, "unit": args.unit, "category": args.category, "cost": args.cost})
            for k, v in (("sell", args.sell), ("length_mm", args.length_mm), ("width_mm", args.width_mm),
                         ("pack_size", args.pack_size), ("waste_pct", args.waste_pct)):
                if v is not None:
                    vals[k] = v
            if args.sell is None:
                vals.pop("sell", None)
            vals["status"] = "owner"
            for ch in set_values(path, f"materials.{args.key}", vals):
                print(ch)
    except SpecError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
