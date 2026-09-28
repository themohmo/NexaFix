"""Item calculators: quantity take-off + labour for every item type NexaFix quotes.

Each calculator receives a Builder (priced lines), the item dict from the
project spec, the estimate context and the rooms the item applies to. It
adds material / labour / other lines and fills in client-facing text
(title, includes...). Parameters resolve as: item value > rate-book
assembly default > hard-coded fallback.
"""
from __future__ import annotations

import math

from .joinery import build_cabinet, floating_shelf_parts, hinges_for_height
from .lines import Builder
from .util import SpecError, area as parse_area, as_bool, ceil_int, count_phrase, dim, num

REGISTRY: dict = {}
RUN_MM = 150    # run lengths (cove, LED, partitions, perimeters): numbers above this are mm
WALL_MM = 60    # wall widths / countertop runs
CATEGORY: dict = {}   # type -> category label used for quote titles


def calculator(*names, category: str = ""):
    def deco(fn):
        for n in names:
            REGISTRY[n] = fn
            CATEGORY[n] = category
        fn.category = category
        return fn
    return deco


def P(item: dict, asm: dict, key: str, default=None):
    v = item.get(key)
    if v is None:
        v = asm.get(key, default)
    return v


# ---------------------------------------------------------------- unit helpers
def linear_units(rates, mat: dict, lm: float) -> float:
    """Convert linear metres into the material's purchase unit."""
    unit = str(mat.get("unit", "m")).lower()
    if unit in ("m", "lm"):
        return lm
    if mat.get("length_mm"):
        return lm / (float(mat["length_mm"]) / 1000.0)
    raise SpecError(f"Material '{mat['key']}' needs unit 'm' or a length_mm to be used by the metre")


def area_units(rates, mat: dict, m2: float) -> float:
    unit = str(mat.get("unit", "m2")).lower()
    if unit in ("m2", "m²", "sqm"):
        return m2
    ua = rates.unit_area(mat)
    if not ua:
        raise SpecError(f"Material '{mat['key']}' needs coverage_m2 or length_mm + width_mm (or unit m2)")
    return m2 / ua


def _openings_area_perim(value, notes) -> tuple[float, float]:
    if not value:
        return 0.0, 0.0
    if isinstance(value, (int, float)):
        return float(value), 4 * math.sqrt(float(value))
    a = p = 0.0
    for o in value:
        if isinstance(o, dict):
            w, h = dim(o.get("width"), "opening", notes), dim(o.get("height"), "opening", notes)
        else:
            w, h = dim(o[0], "opening", notes), dim(o[1], "opening", notes)
        a += w * h
        p += 2 * (w + h)
    return a, p


def lc(s: str) -> str:
    """Lower-case a label for mid-sentence use without breaking '13 A' or 'LED'."""
    if len(s) > 1 and s[0].isupper() and s[1].islower():
        return s[0].lower() + s[1:]
    return s


def _sum_rooms(rooms, attr):
    return sum(getattr(r, attr) for r in rooms)


def _room_names(rooms) -> str:
    names = [r.name for r in rooms]
    return ", ".join(names) if len(names) <= 4 else f"{len(names)} rooms"


def board_sheets(b: Builder, key: str, m2: float, what: str):
    """Add a board line from m² of parts, applying the sheet yield (nesting loss)."""
    if m2 <= 1e-6:
        return
    mat = b.rates.material(key)
    sheet = b.rates.unit_area(mat)
    if not sheet:
        raise SpecError(f"Board '{key}' needs length_mm and width_mm")
    y = float(mat.get("yield_pct") or b.rates.assembly("cabinet").get("sheet_yield_pct", 82)) / 100.0
    sheets = m2 / (sheet * y)
    b.material(key, sheets, f"{what}: {num(m2)} m² of parts / ({num(sheet)} m² sheet x {y * 100:.0f}% yield)")


# ============================================================== FLOORING / TILES
@calculator("flooring", "floor", "spc", "spc_flooring", "tiles", "tiling", "floor_tiles", "laminate",
            "parquet", "wall_tiles", "vinyl", category="Flooring")
def calc_flooring(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("flooring")
    t = item["type"]
    surface = item.get("surface") or ("wall" if t == "wall_tiles" else "floor")
    defaults = {"spc": "spc_plank", "spc_flooring": "spc_plank", "laminate": "laminate_8mm",
                "parquet": "parquet_engineered", "tiles": asm.get("default_tile", "tile_60x60"),
                "floor_tiles": asm.get("default_tile", "tile_60x60"), "tiling": asm.get("default_tile", "tile_60x60"),
                "wall_tiles": asm.get("default_wall_tile", "tile_60x60")}
    key = item.get("material") or defaults.get(t) or asm.get("default_material", "spc_plank")
    mat = ctx.rates.material(key)
    is_tile = mat.get("category") == "tiles"
    notes = b.res.notes

    doors = 0
    door_w = 0.0
    if surface == "wall":
        A = parse_area(item.get("area"), "area")
        if A is None:
            W = dim(item.get("width"), "wall width", notes)
            H = dim(item.get("height"), "wall height", notes) or (rooms[0].height if rooms else ctx.default_height)
            if W is None:
                raise SpecError("wall_tiles needs `area` or `width` (+ optional height)")
            A = W * H
        oa, _ = _openings_area_perim(item.get("openings"), notes)
        A -= oa
        perim = 0.0
        where = item.get("room") or _room_names(rooms) if rooms else "wall"
    else:
        A = parse_area(item.get("area"), "area")
        if A is None:
            if not rooms:
                raise SpecError("flooring needs `area` or `rooms` (e.g. rooms: dry)")
            A = _sum_rooms(rooms, "area")
        dry_rooms = [r for r in rooms if not r.wet] or rooms
        perim = dim(item.get("perimeter"), "perimeter", notes, mm_above=RUN_MM)
        if perim is None:
            perim = _sum_rooms(dry_rooms, "perimeter") if rooms else 4 * math.sqrt(A)
        door_w = sum(r.door_width_total for r in dry_rooms) if rooms else 0.9
        doors = sum(len(r.doors) for r in rooms) if rooms else 1
        where = _room_names(rooms) if rooms else "floor area"

    pattern = str(item.get("pattern", "straight")).lower()
    pattern_extra = float(asm.get("pattern_waste_pct", {}).get(pattern, 0))
    waste = float(item.get("waste_pct", mat.get("waste_pct", asm.get("waste_pct", 8)))) + pattern_extra
    ua = ctx.rates.unit_area(mat) or (1.0 if str(mat.get("unit")).lower() in ("m2", "m²") else None)
    if not ua:
        raise SpecError(f"Flooring material '{key}' needs length_mm + width_mm or coverage_m2")
    units = A * (1 + waste / 100) / ua
    unit = mat.get("unit", "pc")
    size = (f"{mat['length_mm']:g} x {mat['width_mm']:g} mm" if mat.get("length_mm") else "")
    b.material(key, units, f"{num(A)} m² x (1 + {num(waste)}% waste) / {num(ua, 4)} m² per {unit} = {num(units, 1)}")
    b.labour_in_sell = as_bool(mat.get("sell_includes_labour"))

    # tile setting materials
    if is_tile:
        if ctx.rates.has_material(asm.get("tile_adhesive")):
            per_bag = float(asm.get("tile_adhesive_m2_per_bag_large" if ua >= 0.5 else "tile_adhesive_m2_per_bag", 4))
            b.material(asm["tile_adhesive"], A / per_bag, f"{num(A)} m² / {per_bag:g} m² per bag")
        if ctx.rates.has_material(asm.get("tile_grout")):
            gb = A / float(asm.get("tile_grout_m2_per_bag", 12))
            b.material(asm["tile_grout"], gb, f"{num(A)} m² / {asm.get('tile_grout_m2_per_bag', 12)} m² per bag")
        if ua >= 0.35 and ctx.rates.has_material(asm.get("tile_clips")):
            clips = A * float(asm.get("tile_clips_per_m2", 8))
            b.material(asm["tile_clips"], clips, f"large format: {num(A)} m² x {asm.get('tile_clips_per_m2', 8)} clips/m²")

    # underlay
    if as_bool(item.get("underlay"), as_bool(mat.get("needs_underlay"))) and surface == "floor":
        ukey = item.get("underlay_material") or asm.get("underlay_material", "spc_underlay")
        b.material(ukey, A * 1.05, f"{num(A)} m² + 5% overlap")

    # levelling
    lev = item.get("levelling")
    if lev and surface == "floor":
        mm = float(lev) if not isinstance(lev, bool) else float(asm.get("levelling_mm", 3))
        lkey = asm.get("levelling_material", "self_levelling")
        lmat = ctx.rates.material(lkey)
        kg = A * float(asm.get("levelling_kg_per_m2_per_mm", 1.6)) * mm
        bags = kg / float(lmat.get("kg_per_unit", 25))
        b.material(lkey, bags, f"{num(A)} m² x {mm:g} mm x {asm.get('levelling_kg_per_m2_per_mm', 1.6)} kg/m²/mm = {num(kg)} kg")
        b.labour(asm.get("trade", "flooring"), A * float(asm.get("levelling_hours_per_m2", 0.08)), "floor levelling",
                 in_sell=True)
        b.include(f"Floor levelling compound ({mm:g} mm)")

    # skirting
    skirting_lm = 0.0
    want_skirting = as_bool(item.get("skirting"), surface == "floor" and as_bool(asm.get("skirting"), True))
    if want_skirting and surface == "floor":
        skey = item.get("skirting_material") or mat.get("skirting_material") or asm.get("skirting_material")
        skirting_lm = max(0.0, perim - door_w)
        smat = ctx.rates.material(skey)
        sw = float(smat.get("waste_pct", 10))
        q = linear_units(ctx.rates, smat, skirting_lm * (1 + sw / 100))
        b.material(skey, q, f"perimeter {num(perim)} m - doors {num(door_w)} m = {num(skirting_lm)} lm + {sw:g}% waste")

    # thresholds
    if surface == "floor" and as_bool(item.get("thresholds"), as_bool(asm.get("thresholds"), True)) and doors:
        tkey = asm.get("threshold_material", "threshold_profile")
        n = int(item.get("threshold_count", doors))
        b.material(tkey, n, f"{n} door openings")

    # removal of existing
    if as_bool(item.get("removal")):
        rem = asm.get("removal_hours_per_m2", {})
        existing = str(item.get("existing", "tiles")).lower()
        h = A * float(rem.get(existing, rem.get("tiles", 0.3)) if isinstance(rem, dict) else rem)
        b.labour(asm.get("removal_trade", "helper"), h, f"remove existing {existing}: {num(A)} m²", in_sell=True)
        b.include("Removal and disposal of existing " + {"tiles": "floor tiles", "spc": "SPC flooring",
                                                         "laminate": "laminate flooring", "parquet": "parquet"}.get(existing, existing))
        if existing == "tiles" and not lev:
            b.warn("Tile removal usually leaves an uneven screed — consider `levelling: 3` (self-levelling compound)")
        ctx.flags.add("demolition")
        ctx.demolition_m2 += A

    # labour
    trade = mat.get("install_trade", asm.get("trade", "flooring"))
    hpm = float(mat.get("install_hours_per_m2", asm.get("hours_per_m2", 0.3)))
    factor = float(asm.get("pattern_labour_factor", {}).get(pattern, 1.0))
    if surface == "wall":
        factor *= float(asm.get("wall_labour_factor", 1.3))
    b.labour(trade, A * hpm * factor, f"{num(A)} m² x {hpm:g} h/m²" + (f" x {factor:g}" if factor != 1 else ""))
    if skirting_lm:
        b.labour(trade, skirting_lm * float(asm.get("skirting_hours_per_lm", 0.08)),
                 f"skirting {num(skirting_lm)} lm x {asm.get('skirting_hours_per_lm', 0.08)} h/lm")

    # client text
    name = mat.get("client_name") or mat.get("name", key)
    r = b.res
    r.measure_qty, r.measure_unit = round(A, 1), "m²"
    r.floor_area = A if surface == "floor" else 0.0
    r.title = item.get("title") or (f"{mat.get('short', 'Wall Tiling')}" if surface == "wall" else f"{mat.get('short', 'Flooring')}")
    r.subtitle = "Supply & installation" + (f" · {where}" if where and surface == "floor" else "")
    where_txt = f" in the {where.lower()}" if rooms and len(rooms) <= 3 and surface == "floor" else ""
    r.description = (f"Supply and installation of {lc(name)}{' (' + size + ')' if size else ''} to "
                     f"{num(A, 1)} m²{where_txt}, laid {pattern} and finished to a clean, level standard"
                     + (" with matching skirting." if skirting_lm else "."))
    b.include(f"{name}{' ' + size if size else ''}, {num(A, 1)} m²" + (f" ({pattern} lay)" if pattern != "straight" else ""))
    if is_tile:
        b.include("Tile adhesive, grout and levelling system")
    if skirting_lm:
        b.include(f"Matching skirting, {num(skirting_lm, 1)} lm")
    if surface == "floor" and doors and as_bool(item.get("thresholds"), as_bool(asm.get("thresholds"), True)):
        b.include(f"Door threshold profiles, {count_phrase(int(item.get('threshold_count', doors)), 'unit')}")
    r.summary_line = f"{name}{' ' + size if size else ''}" + (", with skirting" if skirting_lm else "")
    rate = item.get("sell_rate") or mat.get("sell_per_m2")
    if rate:
        r.sell_override = A * float(rate)
        b.note(f"Sold at AED {float(rate):g}/m² (rate book)")


# ============================================================== WALL CLADDING
def cladding_core(b: Builder, ctx, key: str, W: float, H: float, openings=None, trims=None,
                  framing=False, backing=None, notes=None) -> float:
    """Shared by wall_cladding and media-unit feature panels. Returns net m²."""
    asm = ctx.rates.assembly("wall_cladding")
    mat = ctx.rates.material(key)
    notes = notes if notes is not None else b.res.notes
    oa, op = _openings_area_perim(openings, notes)
    A_gross = W * H
    A = max(0.0, A_gross - oa)
    waste = float(mat.get("waste_pct", asm.get("waste_pct", 8)))
    width_mm = float(mat.get("cover_width_mm") or mat.get("width_mm") or 0)
    layout = mat.get("layout") or ("strips" if 0 < width_mm < 400 else "sheets")
    if layout == "strips":
        pw = width_mm / 1000.0
        pl = float(mat.get("length_mm", 2900)) / 1000.0
        cols = ceil_int(W / pw)
        full = max(1, int((H + 1e-9) // pl))
        rem = max(0.0, H - full * pl)
        topups = 0
        if rem > 0.01:
            per_panel = max(1, int((pl + 1e-9) // rem))       # top-up pieces cut from one panel
            topups = ceil_int(cols / per_panel)
            notes.append(f"Wall {num(H)} m is taller than the {num(pl)} m panel: a {num(rem * 1000, 0)} mm "
                         f"top-up piece (joint or cornice) is needed per column")
        ratio = A / A_gross if A_gross else 1
        units = ceil_int((cols * full + topups) * ratio * (1 + waste / 100))  # rounded per wall
        calc = (f"{num(W)} m / {num(pw, 3)} m = {cols} columns x {full} full pc"
                + (f" + {topups} pc for {num(rem * 1000, 0)} mm top-ups" if topups else "")
                + (f" x {num(ratio)} (openings)" if oa else "") + f" + {waste:g}% waste, rounded per wall")
    else:
        ua = ctx.rates.unit_area(mat)
        units = A * (1 + waste / 100) / ua
        if as_bool(mat.get("round_per_item"), True):
            units = ceil_int(units)
        calc = f"{num(A)} m² x (1 + {waste:g}%) / {num(ua)} m² per sheet"
    b.material(key, units, calc)

    if trims is None:
        trims = as_bool(mat.get("trims"), True)
    if trims:
        tkey = mat.get("trim_material") or asm.get("trim_material")
        if tkey:
            tmat = ctx.rates.material(tkey)
            lm = 2 * (W + H) + op
            b.material(tkey, linear_units(ctx.rates, tmat, lm * 1.1), f"perimeter {num(lm)} lm + 10%")
            b.labour(mat.get("install_trade", "installer"), lm * float(asm.get("trim_hours_per_lm", 0.08)),
                     f"trims {num(lm)} lm")
    if as_bool(mat.get("adhesive"), True) and asm.get("adhesive_material"):
        per = float(mat.get("adhesive_per_m2", asm.get("adhesive_per_m2", 0.5)))
        b.material(asm["adhesive_material"], A * per, f"{num(A)} m² x {per:g} per m²")
    if framing:
        fkey = asm.get("framing_material", "timber_batten")
        fmat = ctx.rates.material(fkey)
        lm = A_gross * float(asm.get("framing_lm_per_m2", 2.5))
        b.material(fkey, linear_units(ctx.rates, fmat, lm), f"{num(A_gross)} m² x {asm.get('framing_lm_per_m2', 2.5)} lm/m²")
        b.labour("installer", A_gross * float(asm.get("framing_hours_per_m2", 0.35)), "framing / battens")
    if backing:
        board_sheets(b, backing, A_gross * 1.05, "backing board")
    hpm = float(mat.get("install_hours_per_m2", asm.get("hours_per_m2", 1.0)))
    b.labour(mat.get("install_trade", "installer"), A * hpm, f"{num(A)} m² x {hpm:g} h/m²")
    return A


@calculator("wall_cladding", "cladding", "feature_wall", "wall_panel", "wall_panels", category="Wall Cladding")
def calc_cladding(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("wall_cladding")
    key = item.get("material") or asm.get("default_material", "wpc_fluted_panel")
    mat = ctx.rates.material(key)
    notes = b.res.notes
    H = dim(item.get("height"), "height", notes) or (rooms[0].height if rooms else ctx.default_height)
    W = dim(item.get("width"), "width", notes, mm_above=WALL_MM)
    if W is None:
        A = parse_area(item.get("area"), "area")
        if A is None:
            raise SpecError("wall_cladding needs `width` (wall length, m) or `area`")
        W = A / H
    A = cladding_core(b, ctx, key, W, H, item.get("openings"), item.get("trims"),
                      as_bool(item.get("framing")), item.get("backing"), notes)
    light = item.get("lighting") or item.get("led")
    led_lm = 0.0
    if light:
        if isinstance(light, dict):
            led_lm = dim(light.get("length"), "led length", notes, mm_above=RUN_MM) or W
            add_led(b, ctx, led_lm, runs=int(light.get("runs", 1)), strip_key=light.get("strip"),
                    profile=light.get("profile", True))
        else:
            led_lm = W if light is True else dim(light, "led length", notes, mm_above=RUN_MM)
            add_led(b, ctx, led_lm, profile=True)
    r = b.res
    r.measure_qty, r.measure_unit = round(A, 1), "m²"
    r.title = item.get("title") or "Wall Cladding"
    r.subtitle = item.get("subtitle") or "Feature wall"
    r.description = (f"Feature wall cladding in {mat.get('name', key)} to {num(W)} x {num(H)} m, supplied, fabricated "
                     "and installed strictly in accordance with the agreed specification and the approved sample.")
    b.include(f"{mat.get('client_name', mat.get('name', key))}, {num(A, 1)} m²")
    b.include("Colours and finishes as per approved sample")
    b.include("Panel design and arrangement as agreed")
    if led_lm:
        b.include(f"Integrated LED lighting within the cladding ({num(led_lm, 1)} m)")
    r.summary_line = f"{mat.get('client_name', mat.get('name', key))}" + (", with integrated lighting" if led_lm else "")
    rate = item.get("sell_rate") or mat.get("sell_per_m2")
    if rate:
        r.sell_override = A * float(rate)


# ============================================================== LED / COVE
def add_led(b: Builder, ctx, length: float, runs: int = 1, strip_key: str | None = None, profile=None,
            feeds: int | None = None) -> dict:
    """LED strip + drivers (sized at the load limit) + profile + connectors + labour."""
    asm = ctx.rates.assembly("led")
    key = strip_key or asm.get("default_strip", "led_strip_24v")
    mat = ctx.rates.material(key)
    run_m = (length or 0) * runs
    if run_m <= 1e-6:
        return {"watts": 0.0, "drivers": 0, "strip_m": 0.0, "feeds": 0}
    waste = float(asm.get("waste_pct", 5))
    strip_m = run_m * (1 + waste / 100)
    b.material(key, strip_m, f"{num(length)} m x {runs} run(s) + {waste:g}% = {num(strip_m)} m")
    wpm = float(mat.get("watts_per_m", 10))
    watts = run_m * wpm
    max_run = float(mat.get("max_run_m", asm.get("max_run_m", 10)))
    feeds = feeds or runs * max(1, ceil_int(length / max_run))
    load = float(asm.get("driver_load_pct", 80)) / 100.0
    drivers = [(k, float(ctx.rates.material(k).get("watts", 0))) for k in asm.get("drivers", [])]
    drivers = sorted([d for d in drivers if d[1] > 0], key=lambda d: d[1])
    n_drv = 0
    if drivers:
        big = drivers[-1][1]
        n_drv = max(1, ceil_int(watts / (big * load)))
        per = watts / n_drv
        choice = next((k for k, w in drivers if w * load >= per), drivers[-1][0])
        b.material(choice, n_drv, f"{num(watts)} W ({num(run_m)} m x {wpm:g} W/m) at {load * 100:.0f}% max load")
    if profile:
        pkey = profile if isinstance(profile, str) else asm.get("default_profile", "led_profile")
        pmat = ctx.rates.material(pkey)
        b.material(pkey, linear_units(ctx.rates, pmat, run_m * 1.05), f"{num(run_m)} m + 5%")
    if asm.get("connector_material"):
        b.material(asm["connector_material"], feeds, f"{feeds} feed point(s)")
    if asm.get("cable_material"):
        b.material(asm["cable_material"], feeds * float(asm.get("cable_per_feed_m", 3)),
                   f"{feeds} feeds x {asm.get('cable_per_feed_m', 3)} m")
    h = strip_m * float(asm.get("hours_per_m", 0.15)) + n_drv * float(asm.get("hours_per_driver", 0.5))
    if profile:
        h += run_m * float(asm.get("profile_hours_per_m", 0.1))
    b.labour(asm.get("trade", "electrician"), h, f"{num(strip_m)} m strip, {n_drv} driver(s)")
    return {"watts": watts, "drivers": n_drv, "strip_m": strip_m, "feeds": feeds}


def _length_or_perimeter(item, rooms, notes, key="length"):
    v = item.get(key)
    if v is None or str(v).lower() == "perimeter":
        if not rooms:
            raise SpecError(f"{item['type']} needs `{key}` (m) or rooms to take the perimeter from")
        L = _sum_rooms(rooms, "perimeter")
        notes.append(f"Length taken as room perimeter ({num(L)} m, {_room_names(rooms)})")
        return L
    return dim(v, key, notes, mm_above=RUN_MM)


def gypsum_cove(b: Builder, ctx, length: float, girth: float | None = None, kind: str = "cove"):
    asm = ctx.rates.assembly("gypsum_ceiling")
    girth = girth or float(asm.get(f"{kind}_girth_m", 0.6 if kind == "cove" else 0.9))
    bkey = asm.get("board", "gypsum_board_std")
    bmat = ctx.rates.material(bkey)
    m2 = length * girth
    b.material(bkey, m2 * 1.15 / ctx.rates.unit_area(bmat), f"{kind}: {num(length)} lm x {girth:g} m girth + 15%")
    fkey = asm.get("furring_material", "furring_channel")
    fmat = ctx.rates.material(fkey)
    b.material(fkey, linear_units(ctx.rates, fmat, length * float(asm.get(f"{kind}_framing_m_per_lm", 3.5))),
               f"{kind} framing {asm.get(f'{kind}_framing_m_per_lm', 3.5)} m per lm")
    gypsum_consumables(b, ctx, asm, m2, kind)
    b.labour(asm.get("trade", "gypsum"), length * float(asm.get(f"{kind}_hours_per_lm", 0.8)),
             f"{num(length)} lm x {asm.get(f'{kind}_hours_per_lm', 0.8)} h/lm")


@calculator("cove_lighting", "cove", "cove_light", category="Lighting")
def calc_cove(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("cove_lighting")
    runs = int(item.get("runs", 1))
    strip = item.get("strip") or asm.get("strip")
    profile = item.get("profile", asm.get("profile", False))
    if item.get("length") is None and len(rooms) > 1:
        # each room is its own circuit with its own driver(s)
        L, drivers = 0.0, 0
        for rm in rooms:
            inf = add_led(b, ctx, rm.perimeter, runs, strip, profile)
            L += rm.perimeter
            drivers += inf["drivers"]
        info = {"drivers": drivers}
        b.note(f"Cove per room perimeter ({', '.join(f'{r.name} {num(r.perimeter)} m' for r in rooms)}), one circuit each")
    else:
        L = _length_or_perimeter(item, rooms, b.res.notes)
        info = add_led(b, ctx, L, runs, strip, profile)
    if as_bool(item.get("build_cove"), as_bool(asm.get("build_cove"), False)):
        gypsum_cove(b, ctx, L, kind="cove")
        b.include(f"Gypsum cove / pelmet, {num(L, 1)} lm")
    r = b.res
    r.measure_qty, r.measure_unit = round(L, 1), "lm"
    cct = item.get("cct", asm.get("cct", "3000K warm white"))
    r.title = item.get("title") or "Cove Lighting"
    r.subtitle = f"Concealed LED · {cct}"
    r.description = f"Concealed LED cove lighting, {num(L, 1)} linear metres, complete with drivers, wiring and connection."
    b.include(f"LED strip, {num(L * runs, 1)} m, {cct}")
    b.include(f"LED drivers, {count_phrase(info['drivers'], 'unit')}, sized with 20% headroom")
    b.include("Wiring, connection and testing")
    r.summary_line = f"Concealed LED, {cct}" + (", with gypsum cove" if as_bool(item.get("build_cove"), as_bool(asm.get("build_cove"), False)) else "")
    rate = item.get("sell_rate") or asm.get("sell_rate_per_m")
    if rate:
        r.sell_override = L * float(rate)


@calculator("led_strip", "led", "led_strips", "strip_light", category="Lighting")
def calc_led(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("led")
    L = _length_or_perimeter(item, rooms, b.res.notes)
    runs = int(item.get("runs", 1))
    info = add_led(b, ctx, L, runs, item.get("strip"), item.get("profile", True))
    if item.get("sensor") and ctx.rates.has_material(asm.get("sensor_material")):
        b.material(asm["sensor_material"], int(item.get("sensor")) if not isinstance(item.get("sensor"), bool) else 1,
                   "touch / motion sensor switch")
    r = b.res
    r.measure_qty, r.measure_unit = round(L * runs, 1), "m"
    r.title = item.get("title") or "LED Strip Lighting"
    r.subtitle = f"{item.get('location', 'Accent lighting')}"
    r.description = f"LED strip lighting in aluminium profile, {num(L * runs, 1)} m, with drivers and connection."
    b.include(f"LED strip in aluminium profile with diffuser, {num(L * runs, 1)} m")
    b.include(f"LED drivers, {count_phrase(info['drivers'], 'unit')}")
    r.summary_line = f"LED strip {num(L * runs, 1)} m"
    rate = item.get("sell_rate") or asm.get("sell_rate_per_m")
    if rate:
        r.sell_override = L * runs * float(rate)


# ============================================================== GYPSUM
BOARD_ALIASES = {"std": "board", "standard": "board", "mr": "board_mr", "moisture": "board_mr",
                 "fr": "board_fr", "fire": "board_fr"}


def gypsum_board_key(ctx, asm: dict, board: str | None) -> str | None:
    """Resolve std / mr / fr shorthands to rate-book keys (partition assembly as fallback)."""
    if board is None:
        return None
    alias = BOARD_ALIASES.get(str(board).lower())
    if alias:
        return asm.get(alias) or ctx.rates.assembly("gypsum_partition").get(alias)
    return board


def gypsum_consumables(b: Builder, ctx, asm: dict, face_m2: float, what: str):
    if face_m2 <= 0:
        return
    for mkey, per_key, dflt, unit_note in (("screw_material", "screws_per_m2", 25, "screws/m²"),
                                           ("tape_material", "tape_m_per_m2", 1.4, "m/m²"),
                                           ("compound_material", "compound_kg_per_m2", 0.45, "kg/m²")):
        key = asm.get(mkey) or ctx.rates.assembly("gypsum_partition").get(mkey)
        if not key:
            continue
        per = float(asm.get(per_key, ctx.rates.assembly("gypsum_partition").get(per_key, dflt)))
        mat = ctx.rates.material(key)
        qty = face_m2 * per
        if mat.get("kg_per_unit"):
            qty /= float(mat["kg_per_unit"])
        b.material(key, qty, f"{what}: {num(face_m2)} m² x {per:g} {unit_note}")


@calculator("gypsum_partition", "partition", "gypsum_wall", "drywall", category="Gypsum Works")
def calc_partition(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("gypsum_partition")
    notes = b.res.notes
    L = dim(item.get("length"), "length", notes, mm_above=RUN_MM)
    if L is None:
        raise SpecError("gypsum_partition needs `length` (m)")
    H = dim(item.get("height"), "height", notes) or (rooms[0].height if rooms else ctx.default_height)
    sides = int(item.get("sides", 2))
    layers = int(item.get("layers", 1))
    n_doors = int(item.get("doors", 0))
    oa, _ = _openings_area_perim(item.get("openings"), notes)
    oa += n_doors * 0.9 * 2.1
    A = max(0.0, L * H - oa)
    faces = sides * layers
    board = gypsum_board_key(ctx, asm, item.get("board")) or asm.get("board", "gypsum_board_std")
    if any(r.wet for r in rooms) and "mr" not in board and item.get("board") is None:
        board = asm.get("board_mr", board)
        b.note("Wet area: moisture-resistant board used")
    bmat = ctx.rates.material(board)
    waste = float(asm.get("waste_pct", 10))
    sheets = A * faces * (1 + waste / 100) / ctx.rates.unit_area(bmat)
    b.material(board, sheets, f"{num(A)} m² x {faces} face(s) + {waste:g}%")
    spacing = float(item.get("stud_spacing", asm.get("stud_spacing_m", 0.6)))
    studs = ceil_int(L / spacing) + 1 + 2 * n_doors
    smat = ctx.rates.material(asm.get("stud_material", "stud_c"))
    stock = float(smat.get("length_mm", 3000)) / 1000
    per_stud = ceil_int(H / stock)
    b.material(smat["key"], studs * per_stud, f"{studs} studs @ {spacing:g} m (+2 per door) x {per_stud} length(s)")
    tmat = ctx.rates.material(asm.get("track_material", "track_u"))
    track_lm = 2 * L + n_doors * 1.2
    b.material(tmat["key"], linear_units(ctx.rates, tmat, track_lm * 1.05), f"top + bottom 2 x {num(L)} m + door heads")
    gypsum_consumables(b, ctx, asm, A * faces, "boards")
    if as_bool(item.get("insulation"), as_bool(asm.get("insulation"), False)):
        b.material(asm.get("insulation_material", "rockwool_50"), A * 1.05, f"{num(A)} m² + 5%")
        b.include("Rockwool acoustic insulation")
    trade = asm.get("trade", "gypsum")
    h = A * float(asm.get("framing_hours_per_m2", 0.3)) + A * faces * float(asm.get("boarding_hours_per_m2", 0.2)) \
        + A * sides * float(asm.get("finishing_hours_per_m2", 0.25))
    b.labour(trade, h, f"{num(A)} m²: framing {asm.get('framing_hours_per_m2', 0.3)} + boarding "
                       f"{asm.get('boarding_hours_per_m2', 0.2)} x {faces} + finishing {asm.get('finishing_hours_per_m2', 0.25)} x {sides} h/m²")
    r = b.res
    r.measure_qty, r.measure_unit = round(A, 1), "m²"
    r.title = item.get("title") or "Gypsum Partition Wall"
    r.subtitle = f"{num(L, 2)} m x {num(H, 2)} m"
    r.description = (f"Supply and installation of a gypsum board partition wall on galvanised metal stud framework, "
                     f"{num(L, 2)} m long x {num(H, 2)} m high, finished ready for paint.")
    b.include(f"Galvanised metal studs at {int(spacing * 1000)} mm centres with top and bottom tracks")
    b.include(f"12.5 mm {bmat.get('short', 'gypsum board')} to {'both sides' if sides == 2 else 'one side'}")
    b.include("Taping, jointing and finishing ready for paint")
    if n_doors:
        b.include(f"Door openings framed, {count_phrase(n_doors, 'unit')}")
    r.summary_line = f"Metal stud, 12.5 mm board {'both sides' if sides == 2 else 'one side'}"
    rate = item.get("sell_rate") or asm.get("sell_rate_per_m2")
    if rate:
        r.sell_override = A * float(rate)


@calculator("gypsum_ceiling", "false_ceiling", "ceiling", category="Gypsum Works")
def calc_ceiling(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("gypsum_ceiling")
    notes = b.res.notes
    A = parse_area(item.get("area"), "area")
    if A is None:
        if not rooms:
            raise SpecError("gypsum_ceiling needs `area` or `rooms`")
        A = _sum_rooms(rooms, "area")
    Pm = dim(item.get("perimeter"), "perimeter", notes, mm_above=RUN_MM) or (_sum_rooms(rooms, "perimeter") if rooms else 4 * math.sqrt(A))
    waste = float(asm.get("waste_pct", 10))
    explicit = gypsum_board_key(ctx, asm, item.get("board"))
    wet_A = sum(r.area for r in rooms if r.wet) if (explicit is None and item.get("area") is None) else 0.0
    board = explicit or asm.get("board", "gypsum_board_std")
    bmat = ctx.rates.material(board)
    if wet_A:
        mr = asm.get("board_mr", board)
        b.material(mr, wet_A * (1 + waste / 100) / ctx.rates.unit_area(ctx.rates.material(mr)),
                   f"wet rooms {num(wet_A)} m² + {waste:g}% (moisture-resistant)")
        b.note("Wet rooms use moisture-resistant board")
    if A - wet_A > 1e-6:
        b.material(board, (A - wet_A) * (1 + waste / 100) / ctx.rates.unit_area(bmat), f"{num(A - wet_A)} m² + {waste:g}%")
    for mkey, per_key, dflt in (("main_channel_material", "main_channel_m_per_m2", 0.9),
                                ("furring_material", "furring_m_per_m2", 2.5)):
        mat = ctx.rates.material(asm.get(mkey))
        lm = A * float(asm.get(per_key, dflt))
        b.material(mat["key"], linear_units(ctx.rates, mat, lm), f"{num(A)} m² x {asm.get(per_key, dflt)} m/m²")
    if asm.get("hanger_material"):
        b.material(asm["hanger_material"], A * float(asm.get("hangers_per_m2", 1.2)),
                   f"{num(A)} m² x {asm.get('hangers_per_m2', 1.2)} hangers/m²")
    wmat = ctx.rates.material(asm.get("wall_angle_material", "wall_angle"))
    b.material(wmat["key"], linear_units(ctx.rates, wmat, Pm * 1.05), f"perimeter {num(Pm)} m + 5%")
    gypsum_consumables(b, ctx, asm, A, "ceiling")
    trade = asm.get("trade", "gypsum")
    b.labour(trade, A * float(asm.get("hours_per_m2", 0.6)), f"{num(A)} m² x {asm.get('hours_per_m2', 0.6)} h/m²")
    cove = dim(item.get("cove_length"), "cove", notes, mm_above=RUN_MM) if str(item.get("cove_length", "")).lower() != "perimeter" else Pm
    bulk = dim(item.get("bulkhead_length"), "bulkhead", notes, mm_above=RUN_MM)
    if cove:
        gypsum_cove(b, ctx, cove, kind="cove")
        b.include(f"Gypsum cove / pelmet for concealed lighting, {num(cove, 1)} lm")
    if bulk:
        gypsum_cove(b, ctx, bulk, kind="bulkhead")
        b.include(f"Bulkhead drop, {num(bulk, 1)} lm")
    dl = int(item.get("downlights", 0))
    if dl:
        b.labour(trade, dl * float(asm.get("cutout_hours", 0.15)), f"{dl} downlight cut-outs")
        if item.get("supply_downlights") and ctx.rates.has_material(asm.get("downlight_material")):
            b.material(asm["downlight_material"], dl, f"{dl} downlights")
            b.labour("electrician", dl * float(asm.get("downlight_hours", 0.5)), f"{dl} downlights wired")
        b.include(f"Downlight cut-outs, {count_phrase(dl, 'point')}")
    ap = int(item.get("access_panels", 0))
    if ap:
        b.material(asm.get("access_panel_material", "access_panel"), ap, f"{ap} access panels")
        b.include(f"Access panels, {count_phrase(ap, 'unit')}")
    r = b.res
    r.measure_qty, r.measure_unit = round(A, 1), "m²"
    r.title = item.get("title") or "Gypsum False Ceiling"
    r.subtitle = _room_names(rooms) if rooms else "Suspended ceiling"
    r.description = (f"Supply and installation of a suspended gypsum board ceiling, {num(A, 1)} m², on galvanised "
                     "metal framework, jointed and finished ready for paint.")
    b.include(f"12.5 mm {bmat.get('short', 'gypsum board')} on galvanised suspension system, {num(A, 1)} m²")
    b.include("Perimeter wall angle, taping, jointing and finishing ready for paint")
    r.summary_line = f"Gypsum ceiling {num(A, 1)} m²" + (" with cove" if cove else "")
    rate = item.get("sell_rate") or asm.get("sell_rate_per_m2")
    if rate:
        r.sell_override = A * float(rate) + (cove or 0) * float(asm.get("cove_sell_rate_per_m", 0))


# ============================================================== PAINT / WALLPAPER
@calculator("painting", "paint", category="Painting")
def calc_painting(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("painting")
    surfaces = str(item.get("surfaces", asm.get("surfaces", "walls"))).lower()
    A_override = parse_area(item.get("area"), "area")
    wall_A = ceil_A = 0.0
    if A_override is not None:
        if "ceiling" in surfaces and "wall" not in surfaces:
            ceil_A = A_override
        else:
            wall_A = A_override
    else:
        if not rooms:
            raise SpecError("painting needs `area` or `rooms`")
        if "wall" in surfaces or surfaces in ("both", "all"):
            wall_A = _sum_rooms(rooms, "wall_area")
        if "ceiling" in surfaces or surfaces in ("both", "all"):
            ceil_A = _sum_rooms(rooms, "area")
    coats = int(item.get("coats", asm.get("coats", 2)))
    prep = str(item.get("prep", asm.get("prep", "light"))).lower()
    trade = asm.get("trade", "painter")
    total = wall_A + ceil_A
    for A, key_name, label, factor in ((wall_A, "paint", "walls", 1.0),
                                       (ceil_A, "ceiling_paint", "ceilings", float(asm.get("ceiling_labour_factor", 1.25)))):
        if A <= 0:
            continue
        pkey = item.get(key_name) or item.get("paint") if key_name == "paint" else (item.get("ceiling_paint") or asm.get("ceiling_paint") or asm.get("paint"))
        pkey = pkey or asm.get("paint", "paint_emulsion")
        pmat = ctx.rates.material(pkey)
        cov = float(pmat.get("coverage_m2_per_l", 10))
        litres = A * coats / cov * 1.05
        b.material(pkey, litres, f"{label} {num(A)} m² x {coats} coats / {cov:g} m²/L + 5%")
        primer = item.get("primer", asm.get("primer", "auto"))
        if (prep in ("medium", "full")) if str(primer).lower() == "auto" else as_bool(primer):
            prk = asm.get("primer_material", "primer_sealer")
            prm = ctx.rates.material(prk)
            b.material(prk, A / float(prm.get("coverage_m2_per_l", 10)) * 1.05, f"{label} {num(A)} m² primer 1 coat")
        putty = asm.get("putty_kg_per_m2", {}).get(prep, 0)
        if putty and asm.get("putty_material"):
            b.material(asm["putty_material"], A * float(putty) / float(ctx.rates.material(asm["putty_material"]).get("kg_per_unit", 1)),
                       f"{label} {num(A)} m² x {putty} kg/m² ({prep} prep)")
        hpc = float(asm.get("hours_per_m2_per_coat", 0.08))
        prep_h = float(asm.get("prep_hours_per_m2", {}).get(prep, 0.05))
        n_coats = coats + (1 if ((prep in ("medium", "full")) if str(primer).lower() == "auto" else as_bool(primer)) else 0)
        b.labour(trade, A * (hpc * n_coats + prep_h) * factor,
                 f"{label} {num(A)} m² x ({hpc:g} h x {n_coats} coats + {prep_h:g} h prep)" + (f" x {factor:g}" if factor != 1 else ""))
    r = b.res
    r.measure_qty, r.measure_unit = round(total, 1), "m²"
    colour = item.get("colour") or item.get("color")
    r.title = item.get("title") or "Painting"
    r.subtitle = (f"{colour} · " if colour else "") + ("walls & ceilings" if wall_A and ceil_A else ("ceilings" if ceil_A else "walls"))
    r.description = (f"Surface preparation and painting of {num(total, 1)} m² with {coats} finish coats"
                     f"{(' in ' + colour) if colour else ''}.")
    b.include(f"{prep.capitalize()} surface preparation, filling and sanding")
    primed = (prep in ("medium", "full")) if str(item.get("primer", asm.get("primer", "auto"))).lower() == "auto" \
        else as_bool(item.get("primer"))
    b.include((f"One coat primer / sealer and {count_phrase(coats, 'finish coat')}") if primed
              else f"{count_phrase(coats, 'finish coat').capitalize()} of premium emulsion")
    if colour:
        b.include(f"Colour: {colour}")
    r.summary_line = ("Walls & ceilings" if wall_A and ceil_A else ("Ceilings" if ceil_A else "Walls")) + f", {coats} coats" + (f", {colour}" if colour else "")
    rate = item.get("sell_rate") or asm.get("sell_rate_per_m2")
    if rate:
        r.sell_override = total * float(rate)


@calculator("wallpaper", category="Wall Finishes")
def calc_wallpaper(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("wallpaper")
    notes = b.res.notes
    key = item.get("material") or asm.get("roll_material", "wallpaper_roll")
    mat = ctx.rates.material(key)
    W = dim(item.get("width"), "width", notes, mm_above=WALL_MM)
    H = dim(item.get("height"), "height", notes) or (rooms[0].height if rooms else ctx.default_height)
    if W is None:
        raise SpecError("wallpaper needs `width` (wall length, m)")
    rw = float(mat.get("width_mm", 530)) / 1000
    rl = float(mat.get("length_mm", 10050)) / 1000
    rep = dim(item.get("pattern_repeat", 0), "repeat", notes) or 0.0
    drop = H + rep + 0.1
    per_roll = max(1, int(rl // drop))
    strips = ceil_int(W / rw)
    rolls = ceil_int(strips / per_roll)
    b.material(key, rolls, f"{strips} drops of {num(drop)} m, {per_roll} per roll")
    if asm.get("paste_material"):
        b.material(asm["paste_material"], rolls / float(asm.get("rolls_per_paste", 5)), f"{rolls} rolls")
    b.labour(asm.get("trade", "painter"), rolls * float(asm.get("hours_per_roll", 0.75)), f"{rolls} rolls")
    r = b.res
    r.measure_qty, r.measure_unit = round(W * H, 1), "m²"
    r.title = item.get("title") or "Wallpaper"
    r.subtitle = item.get("subtitle") or "Feature wall"
    r.description = f"Supply and hanging of wallpaper to {num(W)} x {num(H)} m, pattern matched."
    b.include(f"{mat.get('name', 'Wallpaper')}, {rolls} rolls")
    b.include("Wall preparation, lining and pattern-matched hanging")
    r.summary_line = f"Wallpaper {num(W * H, 1)} m²"


# ============================================================== ELECTRICAL
@calculator("electrical_point", "socket", "sockets", "power_point", "switch", "data_point", "light_point",
            "electrical", category="Electrical")
def calc_points(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("electrical_point")
    t = item["type"]
    kind = item.get("kind") or {"switch": "switch", "data_point": "data", "light_point": "light"}.get(t, "socket")
    kinds = asm.get("kinds", {})
    if kind not in kinds:
        raise SpecError(f"Unknown electrical point kind '{kind}'. Known: {', '.join(kinds)}")
    k = kinds[kind]
    n = int(item.get("count", item.get("qty", 1)))
    mode = str(item.get("mode", "new")).lower()
    if mode not in ("new", "relocate", "faceplate"):
        raise SpecError("electrical point mode must be new, relocate or faceplate")
    if mode != "relocate" or as_bool(item.get("new_faceplate")):
        b.material(k["material"], n, f"{n} x {kind}")
    if mode in ("new", "relocate"):
        if asm.get("box_material"):
            b.material(asm["box_material"], n, f"{n} back boxes")
        cable_m = float(item.get("cable_m", k.get("cable_m", 10) if mode == "new" else asm.get("relocate_cable_m", 4)))
        b.material(k.get("cable", "cable_2_5"), n * cable_m, f"{n} x {cable_m:g} m avg run")
        cmat = ctx.rates.material(asm.get("conduit_material", "conduit_20"))
        cm = n * float(k.get("conduit_m", 6) if mode == "new" else asm.get("relocate_conduit_m", 2))
        b.material(cmat["key"], linear_units(ctx.rates, cmat, cm), f"{num(cm)} m conduit")
        mg = float(asm.get("making_good_cost", 15))
        b.other("Making good (plaster patch & touch-up)", mg, mg * 1.5, f"{n} points", qty=n, unit="pt")
    hours = float(k.get("hours", {}).get(mode, asm.get("hours", {}).get(mode, 2.0))) if isinstance(k.get("hours"), dict) \
        else float(asm.get("hours", {}).get(mode, 2.0))
    b.labour(asm.get("trade", "electrician"), n * hours, f"{n} x {hours:g} h ({mode})")
    r = b.res
    label = k.get("label", kind)
    r.measure_qty, r.measure_unit = n, "pts"
    r.title = item.get("title") or ("Electrical Points" if mode == "new" else f"Electrical Points ({mode})")
    verb = {"new": "New", "relocate": "Relocated", "faceplate": "Replacement"}[mode]
    r.subtitle = f"{verb} {lc(label)}"
    r.description = {
        "new": f"Supply and installation of new {lc(label)} points including chasing, conduit, cabling from the nearest source and making good.",
        "relocate": f"Relocation of existing {lc(label)} points including chasing, extension of cabling and making good.",
        "faceplate": f"Supply and replacement of {lc(label)} faceplates on existing boxes.",
    }[mode]
    b.include(f"{label}, {count_phrase(n, 'point')}"
              + {"new": "", "relocate": " (relocated)", "faceplate": " (faceplate replacement)"}[mode])
    if mode != "faceplate":
        b.include("Chasing, conduit and cabling from nearest source")
        b.include("Making good of plaster and touch-up paint")
    if k.get("dewa_note") and mode == "new":
        b.warn(f"{label}: new circuit may need DEWA / building approval — check before quoting")
    r.summary_line = f"{label}, {n} {verb.lower()} point{'s' if n != 1 else ''}"
    rate = item.get("sell_rate") or (k.get("sell_per_point") if mode == "new" else asm.get("sell_per_point", {}).get(mode))
    if rate:
        r.sell_override = n * float(rate)


# ============================================================== MIRRORS
@calculator("mirror", "mirrors", category="Mirrors")
def calc_mirror(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("mirror")
    notes = b.res.notes
    shape = str(item.get("shape", "rectangle")).lower()
    if shape in ("round", "circle"):
        d = dim(item.get("diameter") or item.get("width"), "diameter", notes)
        if not d:
            raise SpecError("round mirror needs `diameter` (or `width`)")
        W = H = d
        perim = math.pi * d
    else:
        W = dim(item.get("width"), "width", notes)
        H = dim(item.get("height"), "height", notes)
        if not W or not H:
            raise SpecError("mirror needs `width` and `height` (or `diameter` for round)")
        perim = 2 * (W + H)
        if shape in ("arch", "arched"):
            perim = 2 * H + W + math.pi * W / 2 - W
    qty = int(item.get("qty", 1))
    key = item.get("glass") or item.get("material") or asm.get("default_glass", "mirror_clear_5mm")
    gmat = ctx.rates.material(key)
    a = W * H
    charge_a = max(a, float(asm.get("min_area_m2", 0.3)))
    waste = float(asm.get("waste_pct", 10))
    b.material(key, qty * charge_a * (1 + waste / 100),
               f"{qty} x {num(W)} x {num(H)} m" + (f" (min {asm.get('min_area_m2', 0.3)} m²)" if charge_a > a else "") + f" + {waste:g}%")
    edge = str(item.get("edge", asm.get("edge", "polished"))).lower()
    ekey = asm.get("edge_materials", {}).get(edge)
    if ekey:
        b.material(ekey, qty * perim, f"{qty} x perimeter {num(perim)} m ({edge})")
    if asm.get("adhesive_material"):
        b.material(asm["adhesive_material"], qty * max(1.0, a * float(asm.get("adhesive_per_m2", 1))), "mirror adhesive")
    frame = item.get("frame")
    if frame:
        fkey = frame if isinstance(frame, str) else asm.get("frame_material", "mirror_frame_metal")
        b.material(fkey, qty * perim * 1.1, f"{qty} x {num(perim)} m + 10%")
        b.include("Slim metal frame")
    backlit = as_bool(item.get("backlit"))
    if backlit:
        for _ in range(qty):   # each mirror is its own circuit
            add_led(b, ctx, perim * 0.9, runs=1, profile=False)
        if asm.get("sensor_material"):
            b.material(asm["sensor_material"], qty, "touch sensor switch")
        b.labour("carpenter", qty * float(asm.get("backlit_fab_hours", 1.5)), "stand-off backing frame")
        b.include("LED backlighting with touch sensor")
    trade = asm.get("trade", "installer")
    b.labour(trade, qty * (float(asm.get("install_hours_each", 0.75)) + a * float(asm.get("install_hours_per_m2", 0.5))),
             f"{qty} x ({asm.get('install_hours_each', 0.75)} h + {num(a)} m² x {asm.get('install_hours_per_m2', 0.5)} h/m²)")
    r = b.res
    r.measure_qty, r.measure_unit = qty, "pcs"
    r.title = item.get("title") or ("Feature Mirror" if qty == 1 else "Mirrors")
    r.subtitle = f"{gmat.get('short', 'Mirror')} · {edge} edge"
    size = f"{num(W * 1000, 0)} x {num(H * 1000, 0)} mm" if shape not in ("round", "circle") else f"Ø {num(W * 1000, 0)} mm"
    r.description = f"Supply and installation of {gmat.get('name', 'mirror').lower()}, {size}, {edge} edges, wall fixed."
    b.include(f"{gmat.get('name', 'Mirror')}, {size}" + (f", {count_phrase(qty, 'piece')}" if qty > 1 else ""))
    b.include(f"{edge.capitalize()} edges, fixed with mirror adhesive and safety clips")
    r.summary_line = f"{qty} x mirror {size}"


# ============================================================== JOINERY
def _preset(ctx, item):
    asm = ctx.rates.assembly("cabinet")
    presets = asm.get("presets", {})
    name = item.get("preset") or item.get("kind") or (item["type"] if item["type"] in presets else "storage")
    if name not in presets:
        raise SpecError(f"Unknown cabinet preset '{name}'. Known: {', '.join(presets)}")
    return name, presets[name], asm


def calc_cabinet_core(b: Builder, item: dict, ctx, label: str | None = None) -> dict:
    """Price one cabinet type (x qty). Returns info for client text."""
    name, pre, asm = _preset(ctx, item)
    notes = b.res.notes

    def g(k, d=None):
        v = item.get(k)
        if v is None:
            v = pre.get(k)
        if v is None:
            v = asm.get(k, d)
        return v

    W = dim(g("width"), f"{name} width", notes)
    if not W:
        raise SpecError(f"{name}: `width` is required")
    H = dim(g("height"), f"{name} height", notes)
    D = dim(g("depth"), f"{name} depth", notes)
    qty = int(item.get("qty", 1))
    sec_w = float(g("section_width", 0.9))
    sections = int(item.get("sections") or max(1, round(W / sec_w)))
    shelves = item.get("shelves")
    if shelves is None:
        shelves = int(g("shelves_per_section", 0)) * sections
    hanging_sections = int(item.get("hanging_sections", round(sections * float(g("hanging_ratio", 0)))))
    drawers = int(g("drawers", 0))
    flaps = int(g("flaps", 0))
    door_type = str(g("door_type", "hinged")).lower()
    plinth = dim(g("plinth", 0), "plinth", notes) or 0.0
    floating = as_bool(g("floating"), False)
    m = build_cabinet(W, H, D, sections=sections, shelves=int(shelves), doors=g("doors", "auto"),
                      door_type=door_type, drawers=drawers, drawer_height=dim(g("drawer_height", 0.18), "drawer", notes),
                      drawer_columns=int(g("drawer_columns", 1)), flaps=flaps, back=as_bool(g("back"), True),
                      plinth=plinth, top=as_bool(g("top"), True), hanging_sections=hanging_sections,
                      max_door_width=float(g("max_door_width", 0.6)))
    finish_req = str(item.get("finish") or "").lower()
    front_default = g("front_board", "mfc_18")
    if finish_req and not item.get("front_board"):
        swap = asm.get("finish_boards", {}).get(finish_req)
        if swap and ctx.rates.material(front_default).get("finish") != finish_req:
            front_default = swap
    boards = {"carcass": g("carcass_board", "mfc_18"), "front": front_default,
              "back": g("back_board", "mdf_06"), "drawer": g("drawer_board") or g("carcass_board", "mfc_18")}
    per_board: dict[str, float] = {}
    for role, a in m.area_by_role().items():
        key = boards.get(role)
        if key:
            per_board[key] = per_board.get(key, 0.0) + a * qty
    tag = label or name.replace("_", " ")
    for key, a in per_board.items():
        board_sheets(b, key, a, f"{tag} x{qty}")

    # edge banding (lacquered/painted fronts are sprayed, not banded)
    fmat = ctx.rates.material(boards["front"])
    finish = str(item.get("finish") or fmat.get("finish", "laminate")).lower()
    if asm.get("edge_thin_material") and m.thin_edge_m:
        b.material(asm["edge_thin_material"], m.thin_edge_m * qty * 1.1, f"{num(m.thin_edge_m * qty)} m carcass edges + 10%")
    if asm.get("edge_thick_material") and m.thick_edge_m and finish not in ("lacquer", "pu", "paint", "painted"):
        b.material(asm["edge_thick_material"], m.thick_edge_m * qty * 1.1, f"{num(m.thick_edge_m * qty)} m front edges + 10%")
    spray = 0.0
    if finish in ("lacquer", "pu", "paint", "painted", "veneer"):
        spray = m.front_area * qty * float(asm.get("spray_faces_factor", 2.1))
        skey = asm.get("clear_lacquer_material") if finish == "veneer" else asm.get("lacquer_material")
        if skey:
            b.material(skey, spray, f"fronts {num(m.front_area * qty)} m² x {asm.get('spray_faces_factor', 2.1)} (both faces + edges)")
    if m.glass_area and asm.get("glass_material"):
        b.material(asm["glass_material"], m.glass_area * qty, f"{num(m.glass_area * qty)} m² door glass")

    # hardware
    hw = asm.get("hardware", {})
    doors = m.doors * qty
    if doors and not m.sliding and hw.get("hinge"):
        hpd = hinges_for_height(m.door_height, asm.get("hinge_rule"))
        b.material(hw["hinge"], doors * hpd, f"{doors} doors x {hpd} hinges ({num(m.door_height)} m high)")
    if doors and m.sliding and hw.get("sliding_kit"):
        b.material(hw["sliding_kit"], doors, f"{doors} sliding doors")
    if m.drawers and hw.get("runner"):
        b.material(hw["runner"], m.drawers * qty, f"{m.drawers * qty} drawers")
    handles = str(g("handles", "standard")).lower()
    fronts = (m.doors + m.drawers + m.flaps) * qty
    if fronts:
        if handles in ("standard", "handle", "knob") and hw.get("handle"):
            b.material(hw["handle"], fronts, f"{fronts} fronts")
        elif handles == "profile" and hw.get("handle_profile"):
            pm = ctx.rates.material(hw["handle_profile"])
            b.material(hw["handle_profile"], linear_units(ctx.rates, pm, W * qty * max(1, m.drawers or 1)), "profile handle")
        elif handles in ("push", "push_to_open") and hw.get("push_latch"):
            b.material(hw["push_latch"], (m.doors + m.flaps) * qty, "push-to-open latches")
    if m.flaps and hw.get("gas_strut"):
        b.material(hw["gas_strut"], 2 * m.flaps * qty, f"{m.flaps * qty} flaps x 2 stays")
    if m.shelves and hw.get("shelf_pin"):
        b.material(hw["shelf_pin"], 4 * m.shelves * qty, f"{m.shelves * qty} shelves x 4 pins")
    if m.hanging_m and hw.get("hanging_rail"):
        rm = ctx.rates.material(hw["hanging_rail"])
        b.material(hw["hanging_rail"], linear_units(ctx.rates, rm, m.hanging_m * qty), f"{num(m.hanging_m * qty)} m rail")
    if floating and hw.get("wall_bracket"):
        nb = (2 + int(W // 0.6)) * qty
        b.material(hw["wall_bracket"], nb, f"floating: {nb} concealed hangers")
    elif (plinth > 0 or as_bool(g("legs"))) and hw.get("leg"):
        nl = (4 + 2 * int(max(0.0, W - 1.0) // 0.6)) * qty
        b.material(hw["leg"], nl, f"{nl} adjustable legs")

    # lighting
    led = item.get("led")
    led_m = 0.0
    if led:
        led_m = (W * max(1, sections if name == "wardrobe" else 1) if led is True else dim(led, "led", notes, mm_above=RUN_MM)) * qty
        add_led(b, ctx, led_m, profile=True)
        if as_bool(item.get("led_sensor"), True) and ctx.rates.has_material(ctx.rates.assembly("led").get("sensor_material")):
            b.material(ctx.rates.assembly("led")["sensor_material"], qty, "door / touch sensor")

    # countertop on base units
    ct = item.get("countertop")
    if ct:
        ckey = ct if isinstance(ct, str) else ctx.rates.assembly("countertop").get("default_material", "quartz_countertop")
        cmat = ctx.rates.material(ckey)
        lm = W * qty
        qty_ct = lm if str(cmat.get("unit")).lower() in ("m", "lm") else lm * D
        b.material(ckey, qty_ct, f"{num(lm)} lm countertop")

    # labour
    f = asm.get("fab_hours", {})
    board_m2_unit = sum(m.area_by_role().values())
    setup = float(g("fab_setup_hours") or f.get("setup", 1.5))
    fab = qty * (setup + board_m2_unit * float(f.get("per_m2", 0.45))
                 + m.doors * float(f.get("per_door", 0.75)) + m.drawers * float(f.get("per_drawer", 1.25))
                 + m.flaps * float(f.get("per_flap", 1.0)) + m.shelves * float(f.get("per_shelf", 0.2)))
    b.labour(asm.get("fab_trade", "carpenter"), fab,
             f"{qty} x ({setup:g} setup + {num(board_m2_unit)} m² x {f.get('per_m2', 0.45)} + {m.doors} doors x {f.get('per_door', 0.75)}"
             f" + {m.drawers} drawers x {f.get('per_drawer', 1.25)} + {m.shelves} shelves x {f.get('per_shelf', 0.2)})")
    i = asm.get("install_hours", {})
    ipu = float(g("install_per_unit") or i.get("per_unit", 1.5))
    ipm = float(g("install_per_m") or i.get("per_m_width", 1.0))
    inst = qty * (ipu + W * ipm)
    if floating:
        inst *= float(i.get("floating_factor", 1.3))
    b.labour(asm.get("install_trade", "installer"), inst, f"{qty} x ({ipu:g} + {num(W)} m x {ipm:g} h/m)"
             + (f" x {i.get('floating_factor', 1.3)} wall-hung" if floating else ""))

    return {"name": name, "W": W, "H": H, "D": D, "qty": qty, "model": m, "boards": boards, "finish": finish,
            "led_m": led_m, "floating": floating, "handles": handles, "label": pre.get("label", name.replace("_", " ").title())}


def _board_name(ctx, key):
    m = ctx.rates.material(key)
    return m.get("client_name") or m.get("name", key)


@calculator("cabinet", "joinery", "wardrobe", "kitchen_base", "kitchen_wall", "tall_unit", "vanity", "shoe_cabinet",
            "dresser", "nightstand", "bookshelf", "storage", "console", "study_desk", "tv_base", "display_unit",
            category="Bespoke Joinery")
def calc_cabinet(b: Builder, item: dict, ctx, rooms):
    info = calc_cabinet_core(b, item, ctx)
    m, qty = info["model"], info["qty"]
    r = b.res
    r.measure_qty, r.measure_unit = qty, "Unit" if qty == 1 else "Units"
    r.title = item.get("title") or info["label"]
    dims = f"{num(info['W'] * 1000, 0)} W x {num(info['H'] * 1000, 0)} H x {num(info['D'] * 1000, 0)} D mm"
    r.subtitle = dims
    r.description = (f"Bespoke {info['label'].lower()}{'' if qty == 1 else 's'} ({dims}), fabricated in our workshop in "
                     f"{_board_name(ctx, info['boards']['front'])} and installed as per the approved drawing.")
    b.include(f"{info['label']} {dims}" + (f", {count_phrase(qty, 'unit')}" if qty > 1 else ""))
    b.include(f"Carcass in {_board_name(ctx, info['boards']['carcass'])}, fronts in {_board_name(ctx, info['boards']['front'])}")
    if m.doors:
        kind = "Sliding" if m.sliding else "Hinged"
        b.include(f"{kind} doors, {count_phrase(m.doors * qty, 'unit')}" + ("" if m.sliding else " with soft-close hinges"))
    if m.drawers:
        b.include(f"Drawers, {count_phrase(m.drawers * qty, 'unit')} on soft-close runners")
    if m.flaps:
        b.include(f"Lift-up flaps, {count_phrase(m.flaps * qty, 'unit')}")
    if m.shelves:
        b.include(f"Internal shelves, {count_phrase(m.shelves * qty, 'unit')}")
    if m.hanging_m:
        b.include("Hanging rails")
    if info["floating"]:
        b.include("Wall-hung (floating) installation")
    if info["led_m"]:
        b.include(f"Integrated LED lighting ({num(info['led_m'], 1)} m)")
    r.summary_line = f"{info['label']} {dims}" + (f", x{qty}" if qty > 1 else "")


@calculator("media_unit", "tv_unit", "media_wall", category="Bespoke Joinery")
def calc_media(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("media_unit")
    notes = b.res.notes
    W = dim(item.get("width", asm.get("width", 2.4)), "width", notes)
    front = item.get("front_board") or asm.get("front_board")
    carcass = item.get("carcass_board") or asm.get("carcass_board")
    parts_txt = []
    # 1. base storage box
    base = item.get("base", True)
    if base:
        bd = base if isinstance(base, dict) else {}
        base_item = {"type": "tv_base", "preset": "tv_base", "width": bd.get("width", W),
                     "height": bd.get("height", asm.get("base_height", 0.4)),
                     "depth": bd.get("depth", asm.get("base_depth", 0.45)),
                     "drawers": bd.get("drawers", item.get("drawers", asm.get("base_drawers", 2))),
                     "flaps": bd.get("flaps", item.get("flaps", 0)),
                     "door_type": bd.get("door_type", "none"), "drawer_columns": bd.get("drawer_columns", max(1, int(bd.get("drawers", item.get("drawers", asm.get("base_drawers", 2)))))),
                     "drawer_height": bd.get("drawer_height", asm.get("base_height", 0.4) - 0.04),
                     "floating": bd.get("floating", True), "handles": item.get("handles", "push"),
                     "front_board": front, "carcass_board": carcass, "led": bd.get("led")}
        info = calc_cabinet_core(b, base_item, ctx, label="base box")
        bm = info["model"]
        desc = f"{'Floating' if info['floating'] else 'Floor-standing'} base storage box ({num(info['W'] * 1000, 0)} mm)"
        extras = []
        if bm.drawers:
            extras.append(count_phrase(bm.drawers, "drawer"))
        if bm.flaps:
            extras.append(count_phrase(bm.flaps, "flap"))
        parts_txt.append(desc + (f" with {' and '.join(extras)}" if extras else ""))
    # 2. feature back panel
    panel = item.get("panel", asm.get("panel", True))
    if panel:
        pd = panel if isinstance(panel, dict) else {}
        pw = dim(pd.get("width", W), "panel width", notes)
        ph = dim(pd.get("height"), "panel height", notes) or float(asm.get("panel_height") or (rooms[0].height if rooms else ctx.default_height))
        pkey = pd.get("material") or item.get("panel_material") or asm.get("panel_material") or front
        pmat = ctx.rates.material(pkey)
        if pmat.get("category") == "boards":
            a = pw * ph
            board_sheets(b, pkey, a * 1.05, "feature panel")
            fkey = ctx.rates.assembly("wall_cladding").get("framing_material", "timber_batten")
            fm = ctx.rates.material(fkey)
            b.material(fkey, linear_units(ctx.rates, fm, a * float(asm.get("panel_batten_lm_per_m2", 2.0))), "panel sub-frame battens")
            if ctx.rates.assembly("cabinet").get("edge_thick_material"):
                b.material(ctx.rates.assembly("cabinet")["edge_thick_material"], 2 * (pw + ph) * 1.1, "panel edges")
            b.labour("carpenter", a * float(asm.get("panel_fab_hours_per_m2", 0.5)), f"panel {num(a)} m²")
            b.labour("installer", a * float(asm.get("panel_install_hours_per_m2", 0.5)), f"panel {num(a)} m²")
        else:
            cladding_core(b, ctx, pkey, pw, ph, trims=pd.get("trims"), notes=notes)
        parts_txt.append(f"Feature back panel in {pmat.get('client_name', pmat.get('name', pkey))} ({num(pw)} x {num(ph)} m)")
        if item.get("panel_led"):
            add_led(b, ctx, 2 * (pw + ph) if item.get("panel_led") is True else dim(item["panel_led"], "panel led", notes), profile=True)
            parts_txt.append("LED backlighting to the feature panel")
    # 3. floating shelves
    n = int(item.get("shelves", asm.get("shelves", 2)))
    if n:
        L = dim(item.get("shelf_length"), "shelf length", notes) or float(asm.get("shelf_length", 1.2))
        Dp = dim(item.get("shelf_depth"), "shelf depth", notes) or float(asm.get("shelf_depth", 0.25))
        T = dim(item.get("shelf_thickness"), "shelf thickness", notes) or float(asm.get("shelf_thickness", 0.05))
        parts = floating_shelf_parts(L, Dp, T, n)
        skey = item.get("shelf_board") or front
        board_sheets(b, skey, sum(p.area for p in parts), f"{n} floating shelves")
        cab = ctx.rates.assembly("cabinet")
        if cab.get("edge_thick_material"):
            b.material(cab["edge_thick_material"], sum(p.thick_edges * p.qty for p in parts) * 1.1, "shelf edges")
        br = cab.get("hardware", {}).get("floating_bracket")
        if br:
            nb = n * max(2, ceil_int(L / 0.6))
            b.material(br, nb, f"{n} shelves x {max(2, ceil_int(L / 0.6))} concealed brackets")
        b.labour("carpenter", n * float(asm.get("shelf_fab_hours", 1.5)), f"{n} shelves")
        b.labour("installer", n * float(asm.get("shelf_install_hours", 0.75)), f"{n} shelves")
        txt = f"Floating display shelves, {count_phrase(n, 'unit')} ({num(L * 1000, 0)} mm)"
        if as_bool(item.get("shelf_led"), as_bool(asm.get("shelf_led"), True)):
            add_led(b, ctx, L, runs=n, profile=True)
            txt += " with concealed LED"
        parts_txt.append(txt)
    # 4. side / tall units
    su = item.get("side_units")
    if su:
        sd = su if isinstance(su, dict) else {"qty": int(su)}
        side_item = {"type": "tall_unit", "preset": sd.get("preset", "display_unit"),
                     "width": sd.get("width", 0.45), "height": sd.get("height"), "depth": sd.get("depth"),
                     "qty": sd.get("qty", 2), "front_board": front, "carcass_board": carcass,
                     "door_type": sd.get("door_type"), "led": sd.get("led")}
        info = calc_cabinet_core(b, {k: v for k, v in side_item.items() if v is not None}, ctx, label="side unit")
        parts_txt.append(f"Side {info['label'].lower()}s, {count_phrase(info['qty'], 'unit')}")
    # 5. extras
    if as_bool(item.get("tv_bracket"), as_bool(asm.get("tv_bracket"), False)) and asm.get("tv_bracket_material"):
        b.material(asm["tv_bracket_material"], 1, "TV wall bracket")
        b.labour("installer", 0.75, "TV bracket")
        parts_txt.append("TV wall bracket supplied and fixed")
    if as_bool(item.get("cable_management"), True):
        if asm.get("grommet_material"):
            b.material(asm["grommet_material"], 2, "cable grommets")
        cm = ctx.rates.material(ctx.rates.assembly("electrical_point").get("conduit_material", "conduit_20"))
        b.material(cm["key"], linear_units(ctx.rates, cm, float(asm.get("conduit_m", 3))), "concealed cable route")
        parts_txt.append("Concealed cable management")
    r = b.res
    r.measure_qty, r.measure_unit = int(item.get("qty", 1)), "Unit"
    r.title = item.get("title") or "TV Unit"
    r.subtitle = item.get("subtitle") or "Media wall"
    r.description = (f"Complete TV unit, {num(W * 1000, 0)} mm wide, finished in {_board_name(ctx, front)}, supplied, fabricated, "
                     "and installed exactly as per the approved reference image.")
    for t in parts_txt:
        b.include(t)
    r.summary_line = f"{num(W, 1)} m media wall" + (f", {n} shelves" if n else "")


@calculator("headboard", "upholstered_headboard", "bed_front", category="Bespoke Joinery")
def calc_headboard(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("headboard")
    notes = b.res.notes
    W = dim(item.get("width", asm.get("width", 2.0)), "width", notes)
    H = dim(item.get("height", asm.get("height", 1.2)), "height", notes)
    qty = int(item.get("qty", 1))
    style = str(item.get("style", "plain")).lower()
    a = W * H
    board_sheets(b, item.get("backing_board") or asm.get("backing_board", "ply_12"), a * 1.05 * qty, "headboard backing")
    fkey = asm.get("frame_material", "timber_batten")
    fm = ctx.rates.material(fkey)
    frame_lm = (2 * (W + H) + H * ceil_int(W / 0.6)) * qty
    b.material(fkey, linear_units(ctx.rates, fm, frame_lm), f"frame {num(frame_lm)} lm")
    b.material(asm.get("foam_material", "foam_50mm"), a * 1.1 * qty, f"{num(a)} m² + 10%")
    if asm.get("batting_material"):
        b.material(asm["batting_material"], a * 1.2 * qty, f"{num(a)} m² + 20% wrap")
    fab = item.get("fabric") or asm.get("fabric_material", "upholstery_fabric")
    fmat = ctx.rates.material(fab)
    fw = float(fmat.get("width_mm", 1400)) / 1000
    fwaste = float(asm.get("fabric_waste_pct", 20))
    metres = ((W + 0.3) * (H + 0.3) / fw) * (1 + fwaste / 100) * qty
    b.material(fab, metres, f"({num(W)}+0.3) x ({num(H)}+0.3) m / {fw:g} m wide + {fwaste:g}%")
    factor = float(asm.get("style_factor", {}).get(style, 1.0))
    uh = qty * (float(asm.get("base_hours", 3)) + a * float(asm.get("hours_per_m2", 2.5))) * factor
    b.labour("upholsterer", uh, f"{qty} x ({asm.get('base_hours', 3)} + {num(a)} m² x {asm.get('hours_per_m2', 2.5)}) x {factor:g} ({style})")
    b.labour("carpenter", qty * float(asm.get("frame_hours", 2)), "backing frame")
    b.labour("installer", qty * float(asm.get("install_hours", 1.5)), "wall fixing")
    r = b.res
    r.measure_qty, r.measure_unit = qty, "Unit"
    r.title = item.get("title") or "Upholstered Headboard"
    r.subtitle = f"{style} upholstery · {num(W * 1000, 0)} x {num(H * 1000, 0)} mm"
    r.description = f"Upholstered bed front ({style}), {num(W * 1000, 0)} x {num(H * 1000, 0)} mm, in client-approved fabric, wall mounted."
    b.include(f"Upholstered bed front (headboard), {style} finish")
    b.include("High-density foam on plywood backing, fabric as per approved sample")
    r.summary_line = f"Headboard {num(W, 1)} x {num(H, 1)} m"


@calculator("bed_box", "bed", "bed_frame", "bed_base", category="Bespoke Joinery")
def calc_bed(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("bed_box")
    notes = b.res.notes
    size = str(item.get("size", asm.get("size", "king"))).lower()
    mattress = asm.get("sizes", {}).get(size, [1.8, 2.0])
    W = dim(item.get("width"), "width", notes) or mattress[0] + 0.1
    L = dim(item.get("length"), "length", notes) or mattress[1] + 0.1
    H = dim(item.get("height", asm.get("height", 0.35)), "height", notes)
    storage = as_bool(item.get("storage"), True)
    carcass = item.get("carcass_board") or asm.get("carcass_board", "mfc_18")
    platform = item.get("platform_board") or asm.get("platform_board", "ply_18")
    thin = asm.get("bottom_board", "mdf_06")
    board_sheets(b, carcass, 2 * L * H + 2 * W * H + L * H, "bed box sides, ends, centre rail")
    board_sheets(b, platform, W * L, "mattress platform")
    if storage:
        board_sheets(b, thin, W * L, "storage base")
        if asm.get("gas_lift_material"):
            b.material(asm["gas_lift_material"], 1, "gas lift mechanism (pair)")
    uph = as_bool(item.get("upholstered"), False)
    if uph:
        fab = asm.get("fabric_material", "upholstery_fabric")
        perim = 2 * (W + L)
        b.material(fab, perim * (H + 0.2) / 1.4 * 1.2, f"wrap {num(perim)} m x {num(H + 0.2)} m / 1.4 m + 20%")
        b.material(asm.get("foam_thin_material", "foam_25mm"), perim * H * 1.1, "thin foam wrap")
        b.labour("upholsterer", float(asm.get("upholstery_hours", 6)), "wrap bed box")
    b.labour("carpenter", float(asm.get("fab_hours", 8)) + (2 if storage else 0), "bed box fabrication")
    b.labour("installer", float(asm.get("install_hours", 2)), "assembly on site")
    r = b.res
    r.measure_qty, r.measure_unit = int(item.get("qty", 1)), "Unit"
    r.title = item.get("title") or "Bed Base"
    r.subtitle = f"{size} · {'storage' if storage else 'platform'}"
    r.description = f"{size.title()} bed base with {'lift-up storage' if storage else 'solid platform'}, {num(W * 1000, 0)} x {num(L * 1000, 0)} mm."
    b.include("Bed storage box with gas-lift platform" if storage else "Bed platform base")
    if uph:
        b.include("Fully upholstered bed box")
    r.summary_line = f"{size.title()} bed box"


@calculator("countertop", "worktop", "vanity_top", category="Countertops")
def calc_countertop(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("countertop")
    notes = b.res.notes
    L = dim(item.get("length"), "length", notes, mm_above=WALL_MM)
    if not L:
        raise SpecError("countertop needs `length` (m)")
    Dp = dim(item.get("depth", asm.get("depth", 0.6)), "depth", notes)
    key = item.get("material") or asm.get("default_material", "quartz_countertop")
    mat = ctx.rates.material(key)
    q = L if str(mat.get("unit")).lower() in ("m", "lm") else L * Dp
    b.material(key, q, f"{num(L)} lm" + ("" if str(mat.get('unit')).lower() in ('m', 'lm') else f" x {num(Dp)} m"))
    cut = int(item.get("cutouts", 0)) + int(item.get("sink", 0)) + int(item.get("hob", 0))
    if cut and asm.get("cutout_material"):
        b.material(asm["cutout_material"], cut, f"{cut} cut-outs")
    sb = dim(item.get("splashback"), "splashback", notes)
    if sb:
        sbkey = asm.get("splashback_material", key)
        sbm = ctx.rates.material(sbkey)
        b.material(sbkey, L * sb if str(sbm.get("unit")).lower() in ("m2", "m²") else L, f"splashback {num(L)} x {num(sb)} m")
    b.labour(asm.get("trade", "installer"), L * float(asm.get("install_hours_per_m", 1.0)), f"{num(L)} lm")
    r = b.res
    r.measure_qty, r.measure_unit = round(L, 2), "lm"
    r.title = item.get("title") or "Countertop"
    r.subtitle = mat.get("short", "Stone worktop")
    r.description = f"Supply, template, fabrication and installation of {mat.get('name', key).lower()}, {num(L, 2)} lm."
    b.include(f"{mat.get('name', key)}, {num(L, 2)} lm")
    if cut:
        b.include(f"Cut-outs, {count_phrase(cut, 'unit')}")
    r.summary_line = f"{mat.get('short', 'Countertop')} {num(L, 2)} lm"


# ============================================================== SOFT FURNISHINGS
@calculator("curtains", "curtain", "drapes", category="Soft Furnishings")
def calc_curtains(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("curtains")
    notes = b.res.notes
    W = dim(item.get("width"), "width", notes)
    if not W:
        raise SpecError("curtains needs `width` (window/track width, m)")
    H = dim(item.get("height"), "height", notes) or ((rooms[0].height if rooms else ctx.default_height) - 0.05)
    n = int(item.get("qty", item.get("windows", 1)))
    layers = item.get("layers") or [item.get("fabric", "blackout")]
    if isinstance(layers, str):
        layers = [layers]
    fullness = float(item.get("fullness", asm.get("fullness", 2.2)))
    motor = as_bool(item.get("motorised"))
    for layer in layers:
        key = asm.get("fabrics", {}).get(layer, layer)
        mat = ctx.rates.material(key)
        fw = float(mat.get("width_mm", 2800)) / 1000
        if H + 0.3 <= fw:  # wide-width fabric, railroaded
            m = W * fullness + 0.4
            calc = f"railroaded: {num(W)} m x {fullness:g} fullness + 0.4 m hems"
        else:
            drops = ceil_int(W * fullness / fw)
            m = drops * (H + 0.4)
            calc = f"{drops} drops x ({num(H)} + 0.4) m"
        b.material(key, m * n, calc + (f" x {n} windows" if n > 1 else ""))
        if asm.get("stitching_material"):
            b.material(asm["stitching_material"], W * n, f"making up {num(W)} m finished width x {n}")
        tkey = asm.get("track_material", "curtain_track")
        tm = ctx.rates.material(tkey)
        b.material(tkey, linear_units(ctx.rates, tm, (W + 0.2) * n), f"({num(W)} + 0.2) m x {n}")
        if motor and asm.get("motor_material"):
            b.material(asm["motor_material"], n, f"{n} motor(s)")
    b.labour(asm.get("trade", "installer"), n * len(layers) * float(asm.get("hours_per_track", 1.25)), f"{n} x {len(layers)} tracks")
    r = b.res
    r.measure_qty, r.measure_unit = n, "window" if n == 1 else "windows"
    r.title = item.get("title") or "Curtains"
    r.subtitle = " & ".join(l.title() for l in layers) + (" · motorised" if motor else "")
    r.description = f"Made-to-measure {' and '.join(layers)} curtains, {num(W)} x {num(H)} m, on ceiling-fixed track{'s' if len(layers) > 1 else ''}."
    b.include(f"{' and '.join(l.title() for l in layers)} curtains at {fullness:g}x fullness")
    b.include("Ceiling-fixed track" + (" with motor" if motor else ""))
    r.summary_line = f"Curtains {num(W, 1)} m" + (f" x{n}" if n > 1 else "")


@calculator("blinds", "blind", "roller_blind", category="Soft Furnishings")
def calc_blinds(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("blinds")
    notes = b.res.notes
    W = dim(item.get("width"), "width", notes)
    H = dim(item.get("height"), "height", notes)
    if not W or not H:
        raise SpecError("blinds needs `width` and `height`")
    n = int(item.get("qty", 1))
    key = item.get("material") or asm.get("default_material", "roller_blind")
    a = max(W * H, float(asm.get("min_area_m2", 1.0)))
    b.material(key, a * n, f"{n} x max({num(W * H)}, {asm.get('min_area_m2', 1.0)}) m²")
    if as_bool(item.get("motorised")) and asm.get("motor_material"):
        b.material(asm["motor_material"], n, "blind motors")
    b.labour(asm.get("trade", "installer"), n * float(asm.get("hours_each", 0.75)), f"{n} blinds")
    r = b.res
    r.measure_qty, r.measure_unit = n, "pcs"
    r.title = item.get("title") or "Roller Blinds"
    r.subtitle = ctx.rates.material(key).get("short", "Blinds")
    r.description = f"Supply and installation of {ctx.rates.material(key).get('name', 'roller blinds').lower()}, {num(W)} x {num(H)} m."
    b.include(f"{ctx.rates.material(key).get('name', 'Roller blinds')}, {count_phrase(n, 'unit')}")
    r.summary_line = f"{n} blinds"


# ============================================================== DEMOLITION / SUPPLY / CUSTOM
@calculator("demolition", "removal", "strip_out", category="Preparation")
def calc_demolition(b: Builder, item: dict, ctx, rooms):
    asm = ctx.rates.assembly("demolition")
    what = str(item.get("what", "tiles")).lower()
    A = parse_area(item.get("area"), "area")
    if A is None and rooms and not item.get("hours"):
        A = _sum_rooms(rooms, "area")
    h = float(item.get("hours") or (A or 0) * float(asm.get("hours_per_m2", {}).get(what, 0.3)))
    b.labour(asm.get("trade", "helper"), h, f"{num(A or 0)} m² x {asm.get('hours_per_m2', {}).get(what, 0.3)} h/m² ({what})" if A else "as specified")
    if A:
        b.other("Debris bagging & disposal", A * float(asm.get("disposal_per_m2", 4)), None,
                f"{num(A)} m² x AED {asm.get('disposal_per_m2', 4)}")
        ctx.demolition_m2 += A
    ctx.flags.add("demolition")
    r = b.res
    r.measure_qty, r.measure_unit = (round(A, 1), "m²") if A else (1, "Lot")
    r.title = item.get("title") or "Strip-out & Removal"
    r.subtitle = f"Existing {what}"
    r.description = f"Careful removal of existing {what}, bagging and disposal of debris off site."
    b.include(f"Removal of existing {what}" + (f", {num(A, 1)} m²" if A else ""))
    b.include("Debris bagging and disposal")
    r.summary_line = f"Remove {what}"


@calculator("supply", "furniture", "ffe", "appliance", "accessory", "loose_furniture", "decor", category="Furniture & Decor")
def calc_supply(b: Builder, item: dict, ctx, rooms):
    name = item.get("name") or item.get("description") or item.get("title")
    if not name:
        raise SpecError("supply items need a `name`")
    qty = float(item.get("qty", 1))
    if item.get("material"):
        b.material(item["material"], qty, f"{qty:g} x supply")
    else:
        if item.get("cost") is None:
            raise SpecError(f"supply '{name}' needs `cost` (unit purchase price) or `material`")
        cost = float(item["cost"])
        mk = item.get("markup_pct", ctx.rates.price("ffe_markup_pct", 25))
        sell = float(item["sell"]) if item.get("sell") is not None else cost * (1 + float(mk) / 100)
        b.other(name, cost, sell, f"{qty:g} x AED {cost:g} + {mk}%" if item.get("sell") is None else f"{qty:g} x AED {sell:g}",
                qty=qty, unit=item.get("unit", "pc"), ref="supply")
    if item.get("install_hours"):
        b.labour("installer", float(item["install_hours"]) * qty, "delivery, assembly & placement")
    r = b.res
    r.measure_qty, r.measure_unit = qty, item.get("unit", "pc")
    r.title = item.get("title") or name
    r.subtitle = item.get("subtitle") or "Supply & placement"
    r.description = item.get("description") or f"Supply, delivery and placement of {name.lower()}."
    b.include(f"{name}" + (f", {count_phrase(int(qty), 'unit')}" if qty > 1 and float(qty).is_integer() else ""))
    r.summary_line = name


@calculator("custom", "lump_sum", category="Works")
def calc_custom(b: Builder, item: dict, ctx, rooms):
    for i, ln in enumerate(item.get("lines", [])):
        q = float(ln.get("qty", 1))
        if ln.get("material"):
            b.material(ln["material"], q, ln.get("calc", ""))
        elif ln.get("trade") or ln.get("labour"):
            b.labour(ln.get("trade") or ln.get("labour"), float(ln.get("hours", q)), ln.get("calc", ""))
        else:
            if ln.get("cost") is None:
                raise SpecError(f"custom line {i + 1} needs material, trade/hours, or cost")
            b.other(ln.get("description", f"Item {i + 1}"), float(ln["cost"]),
                    float(ln["sell"]) if ln.get("sell") is not None else None, ln.get("calc", ""), qty=q,
                    unit=ln.get("unit", "item"))
    r = b.res
    r.measure_qty, r.measure_unit = float(item.get("qty_display", 1)), item.get("unit", "Lot")
    r.title = item.get("title") or "Custom Works"
    r.description = item.get("description", "")
    for inc in item.get("includes", []):
        b.include(inc)
    r.summary_line = item.get("summary_line", r.title)
