"""Turns a project spec + the rate book into a full estimate (see references/estimate-json.md)."""
from __future__ import annotations

import datetime as _dt
import math
from pathlib import Path

from .calculators import CATEGORY, REGISTRY
from .lines import Builder, Line
from .ratebook import Ratebook
from .spec import Package, build_packages, build_room, rooms_from_typology
import re

from .util import SpecError, area as parse_area, as_bool, ceil_int, ceil_to, count_phrase, dim, num, r2

_COUNT_RE = re.compile(r"\b([a-z]+) \((\d+)\) (points?|units?|pieces?)\b")

# item types that measure floors/walls of rooms and default to a room set
DEFAULT_ROOMS = {
    "flooring": "dry", "floor": "dry", "spc": "dry", "spc_flooring": "dry", "laminate": "dry", "parquet": "dry",
    "vinyl": "dry", "tiles": "wet", "floor_tiles": "wet", "tiling": "wet",
    "painting": "all", "paint": "all", "gypsum_ceiling": "all", "false_ceiling": "all", "ceiling": "all",
}


class Context:
    def __init__(self, rates: Ratebook, spec: dict):
        self.rates = rates
        self.spec = spec
        self.project: dict = spec.get("project") or {}
        self.assumptions: list[str] = []
        self.flags: set[str] = set()
        self.demolition_m2 = 0.0
        defaults = rates.data.get("defaults", {})
        h = dim(self.project.get("ceiling_height"), "ceiling height", self.assumptions)
        if h is None:
            h = float(defaults.get("ceiling_height", 2.8))
            self.assumptions.append(f"Ceiling height {h:g} m (default — not given)")
        self.default_height = h
        raw_rooms = spec.get("rooms") or []
        if not raw_rooms and self.project.get("typology"):
            raw_rooms = rooms_from_typology(rates, self.project["typology"],
                                            parse_area(self.project.get("total_area"), "total_area"),
                                            self.assumptions)
        self.rooms = [build_room(r, h, self.assumptions) for r in raw_rooms]

    @property
    def total_floor_area(self) -> float:
        a = parse_area(self.project.get("total_area"), "total_area")
        if a:
            return a
        return sum(r.area for r in self.rooms)

    def select_rooms(self, selector) -> list:
        if selector is None:
            return []
        sels = selector if isinstance(selector, (list, tuple)) else [selector]
        out = []
        for s in sels:
            hit = [r for r in self.rooms if r.matches(str(s))]
            if not hit:
                names = ", ".join(r.name for r in self.rooms) or "no rooms defined"
                raise SpecError(f"No room matches '{s}'. Rooms: {names}")
            for r in hit:
                if r not in out:
                    out.append(r)
        return out

    def rooms_for(self, item: dict, pkg: Package) -> list:
        for sel in (item.get("rooms"), item.get("room"), pkg.rooms, pkg.room):
            if sel is not None:
                return self.select_rooms(sel)
        dflt = DEFAULT_ROOMS.get(item.get("type"))
        explicit_size = any(item.get(k) is not None for k in ("area", "width", "length"))
        if dflt and self.rooms and not explicit_size:
            rooms = self.select_rooms(dflt) if any(r.matches(dflt) for r in self.rooms) else []
            if rooms:
                self.assumptions.append(f"{item['type']}: applied to {dflt} rooms ({', '.join(r.name for r in rooms)})")
            return rooms
        return []


def _canon(t) -> str:
    """Canonical calculator name for an item type alias (first name registered)."""
    fn = REGISTRY.get(t)
    for name, f in REGISTRY.items():
        if f is fn:
            return name
    return str(t)


# ---------------------------------------------------------------- text helpers
def _short_tile(title: str) -> str:
    t = title.upper()
    if len(t) <= 18:
        return t
    out = ""
    for w in t.split():
        if len(out) + len(w) + 1 > 18:
            break
        out = f"{out} {w}".strip()
    return out or t[:18]


def _auto_title(categories: list[str]) -> str:
    seen = []
    for c in categories:
        if c and c not in seen:
            seen.append(c)
    if not seen:
        return "Fit-Out Package"
    if len(seen) == 1:
        return f"{seen[0]} Package"
    if len(seen) > 3:
        seen = seen[:3]
    return ", ".join(seen[:-1]) + f" & {seen[-1]} Package"


def _auto_summary(categories: list[str]) -> str:
    words = {"Bespoke Joinery": "bespoke joinery", "Wall Cladding": "wall cladding", "Flooring": "flooring",
             "Gypsum Works": "gypsum works", "Lighting": "architectural lighting", "Electrical": "electrical points",
             "Painting": "painting", "Mirrors": "mirrors", "Soft Furnishings": "curtains and blinds",
             "Furniture & Decor": "furniture and décor", "Countertops": "countertops", "Wall Finishes": "wall finishes",
             "Preparation": "preparation works", "Works": "associated works"}
    seen = []
    for c in categories:
        w = words.get(c, c.lower())
        if w and w not in seen:
            seen.append(w)
    if len(seen) > 5:
        seen = seen[:4] + ["associated works"]
    body = seen[0] if len(seen) == 1 else ", ".join(seen[:-1]) + f", and {seen[-1]}"
    return (f"A premium proposal for the supply, fabrication, and installation of {body}, executed in approved "
            "materials and finishes to an exacting standard of craftsmanship.")


_SINGULAR = {"pcs": "pc", "Units": "Unit", "pts": "pt", "windows": "window"}


def _qty_display(q: float, unit: str) -> str:
    qs = f"{q:,.0f}" if float(q).is_integer() else f"{q:,.1f}"
    if q == 1:
        unit = _SINGULAR.get(unit, unit)
        if unit == "Unit":
            return "1"
    return f"{qs} {unit}"


# ---------------------------------------------------------------- main entry
def run_estimate(spec: dict, rates: Ratebook, base_dir: str | Path | None = None,
                 today: _dt.date | None = None) -> dict:
    ctx = Context(rates, spec)
    pricing = rates.pricing
    project = ctx.project
    pkgs = build_packages(spec.get("scope") or [])
    if not pkgs:
        raise SpecError("`scope` is empty — list at least one item to price")
    base_dir = Path(base_dir) if base_dir else Path.cwd()
    min_charges = rates.data.get("min_charges", {})

    packages = []
    cat_value: dict[str, float] = {}
    for pkg in pkgs:
        comps = []
        for item in pkg.items:
            t = item.get("type")
            fn = REGISTRY.get(t)
            if fn is None:
                raise SpecError(f"Unknown item type '{t}'. Known types: {', '.join(sorted(REGISTRY))}")
            it = dict(item)
            if it.get("markup_pct") is None and pkg.markup_pct is not None:
                it["markup_pct"] = pkg.markup_pct
            rooms = ctx.rooms_for(it, pkg)
            b = Builder(rates, it)
            try:
                fn(b, it, ctx, rooms)
            except SpecError as exc:
                raise SpecError(f"{pkg.title or t}: {exc}") from exc
            res = b.res
            cost = sum(ln.cost for ln in res.lines)
            sell = sum(ln.sell for ln in res.lines)
            if res.sell_override is not None:
                sell = res.sell_override
            if it.get("sell_rate") is not None:
                sell = float(it["sell_rate"]) * res.measure_qty
                b.note(f"Priced at AED {float(it['sell_rate']):g} per {res.measure_unit}")
            if it.get("price") is not None:
                sell = float(it["price"])
                b.note("Lump-sum price set in the spec")
            mc = it.get("min_charge", min_charges.get(t))
            if mc and sell < float(mc):
                b.note(f"Minimum charge AED {float(mc):,.0f} applied (build-up AED {sell:,.0f})")
                sell = float(mc)
            comps.append({"item": it, "res": res, "cost": cost, "sell": sell, "hours": b.labour_hours()})
            cat_value[CATEGORY.get(t, "")] = cat_value.get(CATEGORY.get(t, ""), 0.0) + sell
        sell_build = sum(c["sell"] for c in comps)
        fixed = pkg.sell is not None
        if fixed:
            sell_build = float(pkg.sell)
        packages.append({"pkg": pkg, "comps": comps, "sell_build": sell_build, "fixed": fixed,
                         "cost": sum(c["cost"] for c in comps)})

    categories = [c for c, _ in sorted(cat_value.items(), key=lambda kv: -kv[1])]
    all_lines: list[Line] = [ln for p in packages for c in p["comps"] for ln in c["res"].lines]

    # ------------------------------------------------ purchase list (pooled across the project)
    purchase = {}
    for ln in all_lines:
        if ln.kind != "material" or not ln.purchase:
            continue
        e = purchase.setdefault(ln.ref, {"qty": 0.0})
        e["qty"] += ln.qty
    purchase_list, stock_rounding_cost, boards = [], 0.0, []
    board_m2 = {}
    for p in packages:
        for c in p["comps"]:
            for k, v in c["res"].boards.items():
                board_m2[k] = board_m2.get(k, 0.0) + v
    for ref, e in purchase.items():
        mat = rates.material(ref)
        req = e["qty"]
        pack = float(mat.get("pack_size") or 0)
        spare = int(mat.get("spare_packs", 0))
        pack_note = ""
        if pack:
            packs = ceil_int(req / pack) + spare
            buy = packs * pack
            pack_note = f"{packs} {mat.get('pack_name', 'packs')} of {pack:g}" + (f" (incl. {spare} spare)" if spare else "")
        elif rates.is_continuous(mat):
            buy = ceil_to(req, float(mat.get("buy_step", 0.1)))
        else:
            buy = ceil_int(req) + spare
        unit_cost = float(mat.get("cost", 0))
        stock_rounding_cost += (buy - req) * unit_cost
        purchase_list.append({
            "ref": ref, "description": mat.get("name", ref), "category": mat.get("category", ""),
            "qty_required": round(req, 2), "qty_to_buy": round(buy, 2), "unit": mat.get("unit", "pc"),
            "pack_note": pack_note, "unit_cost": r2(unit_cost), "cost": r2(buy * unit_cost),
            "supplier": mat.get("supplier", ""), "placeholder": rates.is_placeholder(mat)})
        if mat.get("category") == "boards":
            boards.append({"ref": ref, "description": mat.get("name", ref), "m2": round(board_m2.get(ref, 0.0), 2),
                           "sheets_exact": round(req, 2), "sheets_to_buy": round(buy, 2)})
    cat_order = ["flooring", "tiles", "cladding", "gypsum", "boards", "hardware", "lighting", "electrical",
                 "glass", "paint", "upholstery", "soft_furnishings", "stone", "sundries"]
    purchase_list.sort(key=lambda x: (cat_order.index(x["category"]) if x["category"] in cat_order else 99, x["ref"]))

    materials_cost = sum(ln.cost for ln in all_lines if ln.kind == "material")
    labour_cost = sum(ln.cost for ln in all_lines if ln.kind == "labour")
    other_cost = sum(ln.cost for ln in all_lines if ln.kind == "other")
    mat_markup = rates.price("default_material_markup_pct", 40) / 100
    consumables_cost = materials_cost * rates.price("consumables_pct", 3) / 100
    consumables_sell = consumables_cost * (1 + mat_markup)
    stock_rounding_sell = stock_rounding_cost * (1 + mat_markup)

    # ------------------------------------------------ labour & schedule
    trades = {}
    for ln in all_lines:
        if ln.kind == "labour":
            e = trades.setdefault(ln.ref, {"hours": 0.0, "cost": 0.0, "sell": 0.0})
            e["hours"] += ln.qty
            e["cost"] += ln.cost
            e["sell"] += ln.sell
    sch = rates.schedule
    hpd = float(sch.get("hours_per_day", 9))
    site_hpd = float(sch.get("site_hours_per_day", hpd))
    phase_hours = {"workshop": 0.0, "site": 0.0, "install": 0.0}
    labour_rows = []
    for tk, e in sorted(trades.items(), key=lambda kv: -kv[1]["hours"]):
        t = rates.trade(tk)
        where = t.get("where", "site")
        phase_hours[where] = phase_hours.get(where, 0.0) + e["hours"]
        labour_rows.append({"trade": tk, "label": t.get("label", tk), "hours": round(e["hours"], 1),
                            "days": round(e["hours"] / (hpd if where == "workshop" else site_hpd), 1),
                            "cost_per_hour": r2(t.get("cost_per_hour", 0)), "cost": r2(e["cost"]),
                            "sell_per_hour": r2(t.get("sell_per_hour", 0)), "sell": r2(e["sell"]), "where": where})
    ws_days = phase_hours["workshop"] / (float(sch.get("workshop_crew", 2)) * hpd)
    # site trades work in parallel, limited by how many people fit on site at once
    per_trade = [e["hours"] / (float(rates.trade(tk).get("crew", sch.get("trade_crew", 2))) * site_hpd)
                 for tk, e in trades.items() if rates.trade(tk).get("where", "site") == "site"]
    site_days = max([phase_hours["site"] / (float(sch.get("site_crew", 4)) * site_hpd)] + per_trade)
    inst_days = phase_hours["install"] / (float(sch.get("install_crew", 2)) * site_hpd)
    proc_days = float(sch.get("procurement_days", 5)) if purchase_list else 0.0
    total_days = proc_days + max(ws_days, site_days) + inst_days
    wk = float(sch.get("working_days_per_week", 6))
    schedule = {
        "procurement_days": round(proc_days, 1), "workshop_days": round(ws_days, 1),
        "site_days": round(site_days + inst_days, 1), "total_days": ceil_int(total_days) if total_days else 0,
        "weeks": round(total_days / wk, 1),
        "notes": [f"Workshop crew {sch.get('workshop_crew', 2)}, site crew {sch.get('site_crew', 2)}, "
                  f"install crew {sch.get('install_crew', 2)}; {hpd:g} h workshop / {site_hpd:g} h site days",
                  f"Longest site trade sets the pace (max {sch.get('site_crew', 4)} people on site)",
                  "Site trades (gypsum, flooring, electrical, paint) run while joinery is in the workshop; "
                  "joinery installation follows fabrication"]}

    # ------------------------------------------------ preliminaries
    pr = rates.prelims
    over = project.get("prelims", {}) or {}
    prelim_markup = float(pr.get("markup_pct", 20)) / 100
    prelims = []
    site_work = any(rates.trade(t).get("where") in ("site", "install") for t in trades)
    area = ctx.total_floor_area or sum(c["res"].floor_area for p in packages for c in p["comps"])
    site_days_all = site_days + inst_days

    def add_prelim(key, name, cost, calc, sell=None):
        o = over.get(key)
        if o is False:
            return
        if isinstance(o, (int, float)) and not isinstance(o, bool):
            cost, calc = float(o), "set in project spec"
        if cost <= 0:
            return
        prelims.append({"key": key, "name": name, "cost": r2(cost),
                        "sell": r2(cost * (1 + prelim_markup) if sell is None else sell), "calc": calc})

    if site_work or purchase_list:
        trips = int(pr.get("base_trips", 2)) + ceil_int(site_days_all / float(pr.get("site_days_per_trip", 3)))
        add_prelim("transport", "Transport & delivery", trips * float(pr.get("trip_cost", 250)),
                   f"{trips} trips x AED {pr.get('trip_cost', 250)}")
    if site_work and area:
        add_prelim("protection", "Floor & site protection",
                   max(area * float(pr.get("protection_per_m2", 5)), float(pr.get("protection_min", 250))),
                   f"{num(area)} m² x AED {pr.get('protection_per_m2', 5)} (min {pr.get('protection_min', 250)})")
        add_prelim("cleaning", "Final cleaning",
                   max(area * float(pr.get("cleaning_per_m2", 3)), float(pr.get("cleaning_min", 300))),
                   f"{num(area)} m² x AED {pr.get('cleaning_per_m2', 3)} (min {pr.get('cleaning_min', 300)})")
    if site_work:
        disp = float(pr.get("disposal_base", 300)) + (float(pr.get("skip_cost", 0)) if "demolition" in ctx.flags else 0)
        add_prelim("disposal", "Debris & packaging removal", disp,
                   "base" + (" + skip for strip-out" if "demolition" in ctx.flags else ""))
        sup_h = site_days_all * float(pr.get("supervision_hours_per_site_day", 2))
        if sup_h and "supervisor" in rates.trades:
            st = rates.trade("supervisor")
            add_prelim("supervision", "Site supervision & coordination", sup_h * float(st.get("cost_per_hour", 40)),
                       f"{num(sup_h)} h ({num(site_days_all)} site days x {pr.get('supervision_hours_per_site_day', 2)} h)",
                       sell=sup_h * float(st.get("sell_per_hour", st.get("cost_per_hour", 40))))
    fees = float(project.get("building_fees", 0) or 0)
    if fees:
        prelims.append({"key": "building_fees", "name": "Building NOC / management fees", "cost": r2(fees),
                        "sell": r2(fees), "calc": "pass-through at cost"})
    for ex in project.get("extras", []) or []:
        c = float(ex.get("cost", 0))
        prelims.append({"key": "extra", "name": ex.get("name", "Extra"), "cost": r2(c),
                        "sell": r2(float(ex["sell"]) if ex.get("sell") is not None else c * (1 + prelim_markup)),
                        "calc": ex.get("calc", "project extra")})
    prelims_cost = sum(p["cost"] for p in prelims)
    prelims_sell = sum(p["sell"] for p in prelims)
    snag_pct = rates.price("snagging_reserve_pct", 0)

    # ------------------------------------------------ sell side
    show_prelims = as_bool(project.get("show_prelims_line"), as_bool(pricing.get("show_prelims_line"), False))
    build_total = sum(p["sell_build"] for p in packages)
    extras_sell = consumables_sell + stock_rounding_sell + (0 if show_prelims else prelims_sell)
    cont_pct = float(project.get("contingency_pct", pricing.get("contingency_pct", 5)))
    contingency = cont_pct / 100 * (build_total + consumables_sell + stock_rounding_sell + prelims_sell)
    distributable = extras_sell + contingency
    flex = [p for p in packages if not p["fixed"]]
    weight_total = sum(p["sell_build"] for p in flex)
    step = float(pricing.get("round_items_to", 50))

    if show_prelims and prelims:
        pk = Package(title="Preliminaries & Site Works", items=[], subtitle="Logistics, protection & handover",
                     description="Transport, site protection, supervision, debris removal and final cleaning.",
                     includes=[p["name"] for p in prelims], summary_line="Transport, protection, supervision, cleaning")
        packages.append({"pkg": pk, "comps": [], "sell_build": prelims_sell, "fixed": False, "cost": 0.0,
                         "prelims_line": True})
        flex.append(packages[-1])
        weight_total += prelims_sell
    for p in packages:
        share = (p["sell_build"] / weight_total * distributable) if (weight_total and not p["fixed"]) else 0.0
        if not flex and distributable:
            share = 0.0
        p["pre_round"] = p["sell_build"] + share
        p["amount"] = p["pre_round"] if p["fixed"] else ceil_to(p["pre_round"], step)
    if not flex and distributable:
        ctx.assumptions.append("All scope items have fixed prices — project extras and contingency are not added")

    subtotal = sum(p["amount"] for p in packages)
    disc_pct = float(project.get("discount_pct", 0) or 0)
    disc_amt = float(project.get("discount_amount", 0) or 0) + subtotal * disc_pct / 100
    disc_label = project.get("discount_label") or (f"{disc_pct:g}%" if disc_pct else "")
    net = subtotal - disc_amt
    vat_registered = as_bool(project.get("vat"), as_bool(pricing.get("vat_registered"), True))
    vat_pct = rates.price("vat_pct", 5) if vat_registered else 0.0
    vat = net * vat_pct / 100

    # ------------------------------------------------ cost side
    snag_cost = net * snag_pct / 100
    direct = materials_cost + labour_cost + other_cost + consumables_cost + stock_rounding_cost + prelims_cost + snag_cost
    overhead_pct = rates.price("overhead_pct", 10)
    overhead = net * overhead_pct / 100
    gross = net - direct
    netp = gross - overhead
    tgt = rates.price("target_margin_pct", 35)
    mn = rates.price("min_margin_pct", 25)
    line_cost_total = sum(p["cost"] for p in packages) or 1.0
    project_costs = consumables_cost + stock_rounding_cost + prelims_cost + snag_cost

    warnings = []
    scope_out = []
    bands = rates.data.get("sanity_bands", {})
    no = 0
    for p in packages:
        pkg = p["pkg"]
        no += 1
        comps = p["comps"]
        res0 = comps[0]["res"] if comps else None
        title = pkg.title or (res0.title if len(comps) == 1 else " + ".join(c["res"].title for c in comps)) or "Works"
        subtitle = pkg.subtitle or (res0.subtitle if res0 else "")
        comp_titles = []
        for c in comps:
            r_ = c["res"]
            countable = r_.measure_unit in ("Unit", "Units", "pcs", "windows", "window")
            comp_titles.append((r_.title, r_.measure_qty if countable else 0))
        counted: dict[str, float] = {}
        for t_, q_ in comp_titles:
            counted[t_] = counted.get(t_, 0) + q_
        comp_names = [t_ + (f" x{q_:g}" if q_ > 1 else "") for t_, q_ in counted.items()]
        made = {"Bespoke Joinery", "Wall Cladding", "Mirrors", "Countertops"}
        fabricated = any(CATEGORY.get(c["item"].get("type"), "") in made for c in comps)
        if pkg.description:
            description = pkg.description
        elif len(comps) == 1:
            description = res0.description
        else:
            listed = comp_names[0] if len(comp_names) == 1 else ", ".join(comp_names[:-1]) + f" and {comp_names[-1]}"
            if fabricated:
                description = (f"{title} supplied, fabricated, and installed as per the approved reference image, "
                               f"comprising {listed}.")
            else:
                description = f"Supply and installation of {title.lower()}, comprising {listed}, as per the agreed specification."
        if pkg.includes is not None:
            includes = pkg.includes
        else:  # same line from several components: add up counted things, otherwise show once
            includes, seen_ = [], {}
            for c in comps:
                for inc in c["res"].includes:
                    m_ = _COUNT_RE.search(inc)
                    key_ = (inc[:m_.start()] + "#" + m_.group(3).rstrip("s") + inc[m_.end():]) if m_ else inc
                    if key_ not in seen_:
                        seen_[key_] = [len(includes), int(m_.group(2)) if m_ else 0]
                        includes.append(inc)
                    elif m_:
                        slot = seen_[key_]
                        slot[1] += int(m_.group(2))
                        includes[slot[0]] = inc[:m_.start()] + count_phrase(slot[1], m_.group(3).rstrip("s")) + inc[m_.end():]
        if pkg.summary_line or len(comps) == 1:
            summary_line = pkg.summary_line or (res0.summary_line if res0 else "")
        else:
            summary_line = ", ".join(comp_names)
        if pkg.qty is not None:
            qty, unit = float(pkg.qty), pkg.unit or "Set"
        elif len(comps) == 1:
            qty, unit = float(res0.measure_qty), res0.measure_unit
        elif p.get("prelims_line"):
            qty, unit = 1.0, "Lot"
        elif len({c["res"].measure_unit for c in comps}) == 1 and \
                comps[0]["res"].measure_unit in ("m²", "lm", "m", "pts", "pcs"):
            qty, unit = float(round(sum(c["res"].measure_qty for c in comps), 1)), comps[0]["res"].measure_unit
        else:
            qty, unit = 1.0, "Set"
        lines = [ln for c in comps for ln in c["res"].lines]
        c_mat = sum(ln.cost for ln in lines if ln.kind == "material")
        c_lab = sum(ln.cost for ln in lines if ln.kind == "labour")
        c_oth = sum(ln.cost for ln in lines if ln.kind == "other")
        alloc = (p["cost"] / line_cost_total * project_costs) if not p.get("prelims_line") else prelims_cost
        if p.get("prelims_line"):
            alloc = prelims_cost
        c_tot = c_mat + c_lab + c_oth + (alloc if not p.get("prelims_line") else prelims_cost)
        amount = p["amount"]
        margin = (amount - c_tot) / amount * 100 if amount else 0.0
        hours = {}
        for c in comps:
            for k, v in c["hours"].items():
                hours[k] = round(hours.get(k, 0.0) + v, 1)
        notes = [n for c in comps for n in c["res"].notes]
        warns = [w for c in comps for w in c["res"].warnings]
        if amount and margin < mn:
            warns.append(f"Margin {margin:.0f}% is below your minimum {mn:g}%")
            warnings.append(f"'{title}': margin {margin:.0f}% (below minimum {mn:g}%)")
        if len(comps) == 1 and qty and not p["fixed"]:
            band = bands.get(comps[0]["item"].get("type")) or bands.get(_canon(comps[0]["item"].get("type")))
            if band:
                per = amount / qty
                lo, hi = float(band[0]), float(band[1])
                if per < lo or per > hi:
                    w_ = (f"'{title}': AED {per:,.0f} per {unit} is outside the usual Dubai range "
                          f"{lo:,.0f}–{hi:,.0f} — check quantities and rates")
                    warns.append(w_.split(": ", 1)[1])
        zero = sorted({ln.ref for ln in lines if ln.kind == "material" and ln.unit_cost == 0})
        if zero:
            warnings.append(f"'{title}': no cost price for {', '.join(zero)}")
        warnings.extend(f"'{title}': {w}" for w in warns if not w.startswith("Margin"))
        img = pkg.image
        if img:
            ip = Path(img)
            if not ip.is_absolute():
                ip = base_dir / ip
            if ip.exists():
                img = str(ip)
            else:
                warnings.append(f"'{title}': reference image not found ({pkg.image})")
                img = None
        friendly = {"dry": "All dry areas", "all": "Whole apartment", "wet": "Wet areas",
                    "bedrooms": "Bedrooms", "everything": "Whole property"}
        rooms_sel = pkg.room or pkg.rooms or ""
        if isinstance(rooms_sel, list):
            rooms_txt = ", ".join(friendly.get(str(x).lower(), str(x)) for x in rooms_sel)
        else:
            rooms_txt = friendly.get(str(rooms_sel).lower(), str(rooms_sel))
        scope_out.append({
            "no": f"{no:02d}", "title": title, "subtitle": subtitle, "room": rooms_txt,
            "description": description, "includes": includes, "summary_line": summary_line,
            "qty": qty, "unit": unit, "qty_display": _qty_display(qty, unit),
            "unit_rate": r2(amount / qty) if qty else r2(amount), "amount": r2(amount), "image": img,
            "tile": pkg.tile or _short_tile(title),
            "internal": {
                "cost_materials": r2(c_mat), "cost_labour": r2(c_lab), "cost_other": r2(c_oth),
                "cost_project_share": r2(alloc), "cost_total": r2(c_tot),
                "sell_build_up": r2(p["sell_build"]), "amount": r2(amount), "fixed_price": p["fixed"],
                "profit": r2(amount - c_tot), "margin_pct": round(margin, 1), "labour_hours": hours,
                "lines": [ln.to_dict() for ln in lines] + ([{
                    "kind": "other", "ref": pr_["key"], "description": pr_["name"], "qty": 1, "unit": "item",
                    "unit_cost": pr_["cost"], "cost": pr_["cost"], "unit_sell": pr_["sell"], "sell": pr_["sell"],
                    "calc": pr_["calc"], "placeholder": False} for pr_ in prelims] if p.get("prelims_line") else []),
                "notes": notes, "warnings": warns}})

    gm = gross / net * 100 if net else 0.0
    if net and gm < mn:
        warnings.insert(0, f"Overall gross margin {gm:.1f}% is below your minimum {mn:g}%")
    elif net and gm < tgt:
        warnings.insert(0, f"Overall gross margin {gm:.1f}% is below your target {tgt:g}%")
    min_job = rates.price("min_job_value", 0)
    if min_job and net < min_job:
        warnings.append(f"Job value AED {net:,.0f} is below your minimum job value AED {min_job:,.0f}")
    # bare rate-book keys, matching `ref` on lines and the purchase list
    placeholders = sorted({p.split(".", 1)[1] for p in rates.used_placeholders})
    if placeholders:
        warnings.append(f"{len(placeholders)} rate(s) are still placeholders — confirm them with "
                        "`rates.py placeholders` before sending this quote")
    for r in ctx.rooms:
        if r.estimated:
            break

    # ------------------------------------------------ meta / company / terms
    co = rates.company
    today = today or _dt.date.today()
    date = project.get("date") or today.strftime("%d/%m/%Y")
    ref = project.get("ref") or f"{co.get('quote_prefix', 'NF')}-{today.year}-{today.month:02d}{today.day:02d}"
    fmt = {"company": co.get("display_name", "Nexa Fix"), "validity_days": co.get("validity_days", 15),
           "payment_terms": co.get("payment_terms", ""), "warranty": co.get("warranty", ""),
           "warranty_short": co.get("warranty_short", "")}
    quote = rates.data.get("quote", {})
    letter = [s.format(**fmt) for s in quote.get("letter", [])]
    terms = []
    fees_charged = float(project.get("building_fees", 0) or 0) > 0
    for t in rates.data.get("terms", []) or []:
        text = t.get("text_if_fees") if (fees_charged and t.get("text_if_fees")) else t.get("text", "")
        terms.append({"title": t.get("title", ""), "text": str(text).format(**fmt)})
    tiles = [s["tile"] for s in scope_out if not s["title"].startswith("Preliminaries")][:4]
    images = [s["image"] for s in scope_out if not s["title"].startswith("Preliminaries")][:4]

    estimate = {
        "meta": {
            "ref": ref, "date": date,
            "title": project.get("title") or _auto_title(categories),
            "summary": project.get("summary") or _auto_summary(categories),
            "client": project.get("client", ""), "project": project.get("name", ""),
            "location": project.get("location", ""), "currency": pricing.get("currency", "AED"),
            "salutation": project.get("salutation") or quote.get("salutation", "Dear Sir / Madam,"),
            "letter": letter, "cover_tiles": tiles, "cover_images": images,
            "show_unit_rates": as_bool(project.get("show_unit_rates"), as_bool(quote.get("show_unit_rates"), False)),
            "generated": _dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
            "rates_file": str(rates.path) if rates.path else "",
        },
        "company": {
            "name": co.get("name", "NEXA FIX"), "tagline": co.get("tagline", ""), "division": co.get("division", ""),
            "phone": co.get("phone", ""), "email": co.get("email", ""), "address": co.get("address", ""),
            "website": co.get("website", ""), "trn": co.get("trn", ""), "signatory": co.get("signatory", ""),
            "validity_days": co.get("validity_days", 15), "warranty_short": co.get("warranty_short", "2 Years"),
            "brand": dict(rates.brand),
        },
        "scope": scope_out,
        "totals": {"subtotal": r2(subtotal), "discount": r2(disc_amt), "discount_label": disc_label, "net": r2(net),
                   "vat_pct": vat_pct, "vat": r2(vat), "grand_total": r2(net + vat), "vat_registered": vat_registered},
        "terms": terms,
        "internal": {
            "materials_cost": r2(materials_cost), "labour_cost": r2(labour_cost), "other_cost": r2(other_cost),
            "consumables_cost": r2(consumables_cost), "stock_rounding_cost": r2(stock_rounding_cost),
            "prelims_cost": r2(prelims_cost), "snagging_reserve_cost": r2(snag_cost), "direct_cost": r2(direct),
            "overhead_pct": overhead_pct, "overhead_cost": r2(overhead), "total_cost": r2(direct + overhead),
            "sell_net": r2(net), "gross_profit": r2(gross), "gross_margin_pct": round(gm, 1),
            "net_profit": r2(netp), "net_margin_pct": round(netp / net * 100 if net else 0.0, 1),
            "markup_on_cost_pct": round(gross / direct * 100 if direct else 0.0, 1),
            "target_margin_pct": tgt, "min_margin_pct": mn,
            "contingency_pct": cont_pct, "contingency_amount": r2(contingency),
            "consumables_pct": rates.price("consumables_pct", 3), "snagging_reserve_pct": snag_pct,
            "prelims": [{k: v for k, v in pr_.items() if k != "key"} for pr_ in prelims],
            "purchase_list": purchase_list, "boards": boards, "labour": labour_rows, "schedule": schedule,
            "warnings": warnings, "assumptions": ctx.assumptions,
            "placeholders_used": placeholders,
            "rooms": [{"name": r.name, "area": round(r.area, 2), "perimeter": round(r.perimeter, 2),
                       "height": r.height, "wall_area": round(r.wall_area, 2), "wet": r.wet,
                       "estimated": r.estimated} for r in ctx.rooms],
        },
    }
    check = abs(sum(s["amount"] for s in scope_out) - estimate["totals"]["subtotal"])
    if check > 0.02:  # pragma: no cover - invariant
        raise AssertionError("scope amounts do not add up to subtotal")
    return estimate
