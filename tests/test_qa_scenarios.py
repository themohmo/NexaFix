"""QA scenarios for the NexaFix costing engine.

Two kinds of tests live here:
  * regression tests for behaviour that was hand-verified against
    references/takeoff.md (they must keep passing), and
  * regression tests, one per bug found in QA review (all fixed).

Expected values are derived from the rate book at run time wherever possible,
so re-tuning prices / productivities does not break these tests.

Run: python -m pytest tests -q
"""
from __future__ import annotations

import math
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "nexa-costing"
SCRIPTS = SKILL / "scripts"
sys.path.insert(0, str(SCRIPTS))

from nexa_costing.engine import Context, run_estimate  # noqa: E402
from nexa_costing.joinery import build_cabinet  # noqa: E402
from nexa_costing.ratebook import Ratebook, set_dotted, set_values  # noqa: E402
from nexa_costing.spec import load_spec_file  # noqa: E402
from nexa_costing.util import SpecError, area, dim  # noqa: E402


# ------------------------------------------------------------------ helpers
@pytest.fixture()
def rates():
    return Ratebook.load(SKILL / "rates.toml")


@pytest.fixture()
def rates_copy(tmp_path):
    p = tmp_path / "rates.toml"
    shutil.copy(SKILL / "rates.toml", p)
    return p


def run(rates, scope, rooms=None, **project):
    project.setdefault("ceiling_height", 2.8)
    return run_estimate({"project": project, "rooms": rooms or [], "scope": scope}, rates)


def lines(est, i=0, kind=None):
    return [l for l in est["scope"][i]["internal"]["lines"] if kind is None or l["kind"] == kind]


def qty(est, ref, i=0):
    return sum(l["qty"] for l in lines(est, i) if l["ref"] == ref)


def purchase(est, ref):
    return next(p for p in est["internal"]["purchase_list"] if p["ref"] == ref)


def uplift(rates):
    return 1 + rates.price("site_labour_uplift_pct", 0) / 100


APARTMENT = [
    {"name": "Living Room", "length": 6.2, "width": 4.5, "windows": [[3.0, 2.4]]},
    {"name": "Master Bedroom", "length": 4.6, "width": 4.0},
    {"name": "Corridor", "length": 5.0, "width": 1.4, "doors": 0},
    {"name": "Master Bathroom", "length": 2.6, "width": 2.2},
    {"name": "Balcony", "length": 3.0, "width": 1.5},
]


# ================================================================== quantities (verified correct)
def test_spc_dry_rooms_area_skirting_thresholds(rates):
    est = run(rates, [{"type": "flooring", "rooms": "dry"}], rooms=APARTMENT)
    A = 6.2 * 4.5 + 4.6 * 4.0 + 5.0 * 1.4                  # balcony + bathroom excluded
    assert est["scope"][0]["qty"] == pytest.approx(round(A, 1))
    plank = rates.material("spc_plank")
    ua = plank["length_mm"] * plank["width_mm"] / 1e6
    assert qty(est, "spc_plank") == pytest.approx(A * (1 + plank["waste_pct"] / 100) / ua, rel=1e-3)
    perim = 2 * (6.2 + 4.5) + 2 * (4.6 + 4.0) + 2 * (5.0 + 1.4)
    lm = perim - 2 * 0.9                                   # corridor has no door
    sk = rates.material(plank["skirting_material"])
    assert qty(est, sk["key"]) == pytest.approx(lm * (1 + sk["waste_pct"] / 100) / (sk["length_mm"] / 1000), rel=1e-3)
    assert qty(est, "threshold_profile") == 2


def test_tiles_setting_materials_follow_takeoff(rates):
    asm = rates.assembly("flooring")
    est = run(rates, [{"type": "tiles", "area": 20, "skirting": False, "thresholds": False}])
    assert qty(est, "tile_adhesive") == pytest.approx(20 / asm["tile_adhesive_m2_per_bag"], rel=1e-3)
    assert qty(est, "tile_grout") == pytest.approx(20 / asm["tile_grout_m2_per_bag"], rel=1e-3)
    assert qty(est, "tile_clips") == pytest.approx(20 * asm["tile_clips_per_m2"], rel=1e-3)
    big = run(rates, [{"type": "tiles", "material": "tile_120x60", "area": 20, "skirting": False}])
    assert qty(big, "tile_adhesive") == pytest.approx(20 / asm["tile_adhesive_m2_per_bag_large"], rel=1e-3)


def test_laminate_sqft_area_and_box_rounding(rates):
    est = run(rates, [{"type": "laminate", "area": "250 sqft"}])
    A = 250 * 0.09290304
    mat = rates.material("laminate_8mm")
    req = A * (1 + mat["waste_pct"] / 100)
    assert qty(est, "laminate_8mm") == pytest.approx(req, rel=1e-3)
    p = purchase(est, "laminate_8mm")
    assert p["qty_to_buy"] == pytest.approx(math.ceil(req / mat["pack_size"]) * mat["pack_size"], abs=0.01)
    assert qty(est, "spc_underlay") == pytest.approx(A * 1.05, rel=1e-3)   # laminate needs underlay


def test_fluted_strips_per_column_with_openings(rates):
    mat = rates.material("wpc_fluted_panel")
    est = run(rates, [{"type": "wall_cladding", "material": "wpc_fluted_panel", "width": 4500, "height": 2.8,
                       "openings": [[1.0, 2.1]]}])
    cols = math.ceil(4.5 / (mat["width_mm"] / 1000))
    ratio = (4.5 * 2.8 - 2.1) / (4.5 * 2.8)
    assert qty(est, "wpc_fluted_panel") == math.ceil(cols * ratio * (1 + mat["waste_pct"] / 100))
    notes = est["scope"][0]["internal"]["notes"]
    assert not any("taller than" in n for n in notes)       # 2.8 m wall is shorter than a 2.9 m panel


def test_pvc_sheets_rounded_per_wall_not_pooled(rates):
    est = run(rates, [{"title": "Two walls", "items": [
        {"type": "wall_cladding", "material": "pvc_marble_sheet", "width": 1.0, "height": 2.8},
        {"type": "wall_cladding", "material": "pvc_marble_sheet", "width": 1.0, "height": 2.8}]}])
    assert purchase(est, "pvc_marble_sheet")["qty_to_buy"] == 2    # 0.9 sheet each wall -> 1 + 1


@pytest.mark.parametrize("length, runs, drivers", [
    (5, 1, {"led_driver_100w": 1}),       # 50 W: 60 W driver is 83% loaded -> 100 W
    (12, 1, {"led_driver_150w": 1}),      # 120 W = exactly 80% of 150 W
    (30, 1, {"led_driver_200w": 2}),      # 300 W -> 2 x 150 W each -> 200 W drivers
    (38, 1, {"led_driver_300w": 2}),
    (25, 2, {"led_driver_300w": 3}),      # 500 W -> 3 drivers at 167 W
])
def test_led_driver_sizing_at_80_percent(rates, length, runs, drivers):
    est = run(rates, [{"type": "led_strip", "length": length, "runs": runs, "profile": False}])
    got = {l["ref"]: l["qty"] for l in lines(est) if l["ref"].startswith("led_driver")}
    assert got == drivers
    W = length * runs * 10
    assert sum(rates.material(k)["watts"] * 0.8 * n for k, n in got.items()) >= W
    assert qty(est, "led_connector_kit") == runs * math.ceil(length / 10)


def test_gypsum_partition_with_door(rates):
    asm = rates.assembly("gypsum_partition")
    est = run(rates, [{"type": "gypsum_partition", "length": 4.0, "height": 3.2, "doors": 1}])
    A = 4.0 * 3.2 - 0.9 * 2.1
    assert qty(est, "gypsum_board_std") == pytest.approx(A * 2 * 1.1 / 2.88, rel=1e-3)
    assert qty(est, "stud_c") == (math.ceil(4.0 / 0.6) + 1 + 2) * math.ceil(3.2 / 3.0)
    assert qty(est, "track_u") == pytest.approx((2 * 4.0 + 1.2) * 1.05 / 3.0, rel=1e-3)
    assert qty(est, "drywall_screws") == pytest.approx(A * 2 * asm["screws_per_m2"], rel=1e-3)
    h = A * (asm["framing_hours_per_m2"] + 2 * asm["boarding_hours_per_m2"] + 2 * asm["finishing_hours_per_m2"])
    assert qty(est, "gypsum") == pytest.approx(h * uplift(rates), rel=1e-3)


def test_gypsum_ceiling_quantities(rates):
    asm = rates.assembly("gypsum_ceiling")
    rooms = [{"name": "Living Room", "length": 6, "width": 4}]
    est = run(rates, [{"type": "gypsum_ceiling", "rooms": "Living Room", "cove_length": "perimeter"}], rooms=rooms)
    A, P = 24.0, 20.0
    assert qty(est, "main_channel") == pytest.approx(A * asm["main_channel_m_per_m2"] / 3, rel=1e-3)
    assert qty(est, "ceiling_hanger") == pytest.approx(A * asm["hangers_per_m2"], rel=1e-3)
    assert qty(est, "wall_angle") == pytest.approx(P * 1.05 / 3, rel=1e-3)
    board = A * 1.1 / 2.88 + P * asm["cove_girth_m"] * 1.15 / 2.88
    assert qty(est, "gypsum_board_std") == pytest.approx(board, rel=1e-3)


def test_socket_point_build_up(rates):
    k = rates.assembly("electrical_point")["kinds"]["socket"]
    est = run(rates, [{"type": "socket", "count": 4}])
    assert qty(est, "socket_double_13a") == 4 and qty(est, "back_box") == 4
    assert qty(est, "cable_2_5") == 4 * k["cable_m"]
    assert qty(est, "conduit_20") == pytest.approx(4 * k["conduit_m"] / 3, rel=1e-3)
    assert est["scope"][0]["qty_display"] == "4 pts"


@pytest.mark.parametrize("item, glass_m2, edge_m", [
    ({"width": 0.9, "height": 1.2}, 0.9 * 1.2 * 1.1, 2 * (0.9 + 1.2)),
    ({"shape": "round", "diameter": 800}, 0.8 * 0.8 * 1.1, math.pi * 0.8),
    ({"shape": "arch", "width": 0.8, "height": 1.8}, 0.8 * 1.8 * 1.1, 2 * 1.8 + math.pi * 0.8 / 2),
    ({"width": 0.4, "height": 0.5}, 0.3 * 1.1, 1.8),        # minimum chargeable area
])
def test_mirror_glass_and_edges(rates, item, glass_m2, edge_m):
    est = run(rates, [dict(type="mirror", **item)])
    assert qty(est, "mirror_clear_5mm") == pytest.approx(glass_m2, rel=1e-3)
    edge = next(l for l in lines(est) if l["ref"] in ("mirror_edge_polish", "mirror_bevel"))
    assert edge["qty"] == pytest.approx(edge_m, rel=1e-3)


def test_wardrobe_hand_takeoff_and_qty(rates):
    est = run(rates, [{"type": "wardrobe", "width": 2.4}])
    assert qty(est, "hinge_soft_close") == 25            # 5 doors x 5 hinges (2.5 m doors)
    assert qty(est, "handle_std") == 5
    assert qty(est, "shelf_pin") == 24                    # 6 shelves x 4
    assert qty(est, "hanging_rail") == pytest.approx(1.6)
    assert qty(est, "adjustable_leg") == 8
    mfc = rates.material("mfc_18")
    carcass = 2 * 2.5 * 0.6 + 2 * 2.4 * 0.6 + 2 * (2.5 - 0.036) * 0.58 + 6 * 0.795 * 0.57
    front = 2.4 * 0.1 + 5 * (2.5 - 0.003) * (0.48 - 0.003)
    sheets = (carcass + front) / (mfc["length_mm"] * mfc["width_mm"] / 1e6 * mfc["yield_pct"] / 100)
    assert qty(est, "mfc_18") == pytest.approx(sheets, rel=1e-3)
    two = run(rates, [{"type": "wardrobe", "width": 2.4, "qty": 2}])
    for ref in ("mfc_18", "hinge_soft_close", "carpenter", "installer"):
        assert qty(two, ref) == pytest.approx(2 * qty(est, ref), abs=0.002)   # line qty is rounded to 3 dp
    assert two["scope"][0]["qty_display"] == "2 Units"


def test_dresser_drawer_boxes():
    m = build_cabinet(1.2, 0.8, 0.45, drawers=4, drawer_columns=2, drawer_height=0.36, door_type="none")
    parts = {p.name: p for p in m.parts}
    assert m.doors == 0 and m.drawers == 4
    assert parts["drawer front"].qty == 4 and parts["drawer side"].qty == 8
    assert parts["drawer front/back (inner)"].qty == 8 and parts["drawer bottom"].qty == 4
    assert m.thick_edge_m == pytest.approx(4 * 2 * (0.6 + 0.36))


@pytest.mark.parametrize("n", [1, 2, 3])
def test_media_unit_shelf_count_scales(rates, n):
    est = run(rates, [{"type": "media_unit", "width": 3.0, "shelves": n, "panel": False, "base": False,
                       "cable_management": False}])
    assert qty(est, "floating_bracket") == n * 2                      # 1.2 m shelf -> 2 brackets each
    assert qty(est, "led_strip_24v") == pytest.approx(1.2 * n * 1.05)
    assert qty(est, "edge_band_thick") == pytest.approx(n * (2 * 1.2 + 2 * 0.25) * 1.1)


def test_headboard_fabric_and_upholstery_hours(rates):
    asm = rates.assembly("headboard")
    est = run(rates, [{"type": "headboard", "width": 2.0, "height": 1.2, "style": "channel"}])
    assert qty(est, "upholstery_fabric") == pytest.approx(2.3 * 1.5 / 1.4 * 1.2, rel=1e-3)
    h = (asm["base_hours"] + 2.4 * asm["hours_per_m2"]) * asm["style_factor"]["channel"]
    assert qty(est, "upholsterer") == pytest.approx(h, rel=1e-3)


def test_curtains_drops_vs_railroaded(rates):
    fullness = rates.assembly("curtains")["fullness"]
    tall = run(rates, [{"type": "curtains", "width": 3.0, "height": 2.7}])     # 2.7 + 0.3 > 2.8 m fabric
    drops = math.ceil(3.0 * fullness / 2.8)
    assert qty(tall, "curtain_blackout") == pytest.approx(drops * (2.7 + 0.4))
    low = run(rates, [{"type": "curtains", "width": 3.0, "height": 2.4}])
    assert qty(low, "curtain_blackout") == pytest.approx(3.0 * fullness + 0.4)


def test_wallpaper_rolls(rates):
    est = run(rates, [{"type": "wallpaper", "width": 3.2, "height": 2.8, "pattern_repeat": 0.53}])
    drops, per_roll = math.ceil(3.2 / 0.53), int(10.05 // (2.8 + 0.53 + 0.1))
    assert qty(est, "wallpaper_roll") == math.ceil(drops / per_roll)


def test_painting_litres_and_auto_primer(rates):
    rooms = [{"name": "Bedroom", "length": 4, "width": 3, "windows": [[1.5, 1.5]]}]
    light = run(rates, [{"type": "painting", "rooms": "Bedroom", "surfaces": "both", "prep": "light"}], rooms=rooms)
    wall = 14 * 2.8 - 0.9 * 2.1 - 1.5 * 1.5
    cov = rates.material("paint_emulsion")["coverage_m2_per_l"]
    assert qty(light, "paint_emulsion") == pytest.approx(wall * 2 / cov * 1.05, rel=1e-3)
    assert qty(light, "primer_sealer") == 0                     # primer only for medium/full prep
    full = run(rates, [{"type": "painting", "rooms": "Bedroom", "surfaces": "walls", "prep": "full"}], rooms=rooms)
    assert qty(full, "primer_sealer") == pytest.approx(wall / 8 * 1.05, rel=1e-3)


# ================================================================== pricing invariants (verified correct)
def _check_invariants(est):
    t, it = est["totals"], est["internal"]
    assert sum(s["amount"] for s in est["scope"]) == pytest.approx(t["subtotal"], abs=0.01)
    for s in est["scope"]:
        if not s["internal"]["fixed_price"]:
            assert s["amount"] % 50 == 0, s["title"]
    assert t["vat"] == pytest.approx(t["net"] * t["vat_pct"] / 100, abs=0.01)
    assert t["grand_total"] == pytest.approx(t["net"] + t["vat"], abs=0.01)
    parts = (it["materials_cost"] + it["labour_cost"] + it["other_cost"] + it["consumables_cost"]
             + it["stock_rounding_cost"] + it["prelims_cost"] + it["snagging_reserve_cost"])
    assert it["direct_cost"] == pytest.approx(parts, abs=0.05)
    net, d = t["net"], it["direct_cost"]
    assert it["gross_margin_pct"] == pytest.approx((net - d) / net * 100, abs=0.06)
    assert it["markup_on_cost_pct"] == pytest.approx((net - d) / d * 100, abs=0.06)
    assert it["net_profit"] == pytest.approx(it["gross_profit"] - it["overhead_cost"], abs=0.02)
    for p in it["purchase_list"]:
        assert p["qty_to_buy"] >= p["qty_required"] - 1e-6


@pytest.mark.parametrize("project", [
    {}, {"discount_pct": 7}, {"discount_amount": 500}, {"vat": False}, {"show_prelims_line": True},
    {"contingency_pct": 0, "prelims": {"transport": False, "protection": 400}, "building_fees": 500,
     "extras": [{"name": "Parking", "cost": 200}]},
])
def test_example_invariants(rates, project):
    spec = load_spec_file(SKILL / "examples" / "2br-marina-full-fitout.yaml")
    spec["project"].update(project)
    _check_invariants(run_estimate(spec, rates))


def test_stock_rounding_equals_purchase_rounding(rates):
    spec = load_spec_file(SKILL / "examples" / "2br-marina-full-fitout.yaml")
    spec["scope"] += [{"type": "tiles"}, {"type": "painting", "surfaces": "both"}]
    est = run_estimate(spec, rates)
    req: dict[str, float] = {}
    for s in est["scope"]:
        for l in s["internal"]["lines"]:
            if l["kind"] == "material":
                req[l["ref"]] = req.get(l["ref"], 0) + l["qty"]
    expect = sum((p["qty_to_buy"] - req[p["ref"]]) * p["unit_cost"] for p in est["internal"]["purchase_list"])
    assert est["internal"]["stock_rounding_cost"] == pytest.approx(expect, abs=1.0)
    tile = rates.material("tile_60x60")
    p = purchase(est, "tile_60x60")
    assert p["qty_to_buy"] == (math.ceil(p["qty_required"] / tile["pack_size"]) + tile["spare_packs"]) * tile["pack_size"]
    assert purchase(est, "paint_emulsion")["qty_to_buy"] % 18 == 0
    assert purchase(est, "led_strip_24v")["qty_to_buy"] % 5 == 0


def test_fixed_packages_untouched_and_all_fixed(rates):
    mixed = run(rates, [{"title": "A", "price": 5000, "items": [{"type": "wardrobe", "width": 2.4}]},
                        {"title": "B", "items": [{"type": "flooring", "area": 30}]},
                        {"title": "C", "price": 1234.56, "items": [{"type": "mirror", "width": 1, "height": 1}]}])
    assert [s["amount"] for s in mixed["scope"]][::2] == [5000, 1234.56]
    _check_invariants(mixed)
    fixed = run(rates, [{"title": "A", "price": 5000, "items": [{"type": "wardrobe", "width": 2.4}]}])
    assert fixed["totals"]["subtotal"] == 5000
    assert any("Fixed-price items" in a for a in fixed["internal"]["assumptions"])


def test_spc_labour_costed_not_sold_but_removal_sold(rates):
    est = run(rates, [{"type": "flooring", "material": "spc_plank", "area": 40, "removal": True}])
    fl = [l for l in lines(est, kind="labour") if l["ref"] == "flooring"]
    assert fl and all(l["cost"] > 0 and l["sell"] == 0 for l in fl)
    rem = next(l for l in lines(est, kind="labour") if l["ref"] == "helper")
    assert rem["sell"] > 0


def test_prelims_overrides_fees_and_extras(rates):
    est = run(rates, [{"type": "flooring", "area": 40}, {"type": "wardrobe", "width": 2.4}],
              prelims={"transport": False, "protection": 400, "cleaning": 0},
              building_fees=500, extras=[{"name": "Parking", "cost": 200}, {"name": "Lift", "cost": 100, "sell": 150}])
    pr = {p["name"]: p for p in est["internal"]["prelims"]}
    mk = 1 + rates.prelims["markup_pct"] / 100
    assert "Transport & delivery" not in pr and "Final cleaning" not in pr
    assert pr["Floor & site protection"]["cost"] == 400
    assert pr["Building NOC / management fees"]["sell"] == 500
    assert pr["Parking"]["sell"] == pytest.approx(200 * mk) and pr["Lift"]["sell"] == 150


def test_room_selectors_on_typology(rates):
    ctx = Context(rates, {"project": {"typology": "2br", "total_area": 110}})
    names = lambda sel: {r.name for r in ctx.select_rooms(sel)}  # noqa: E731
    assert sum(r.area for r in ctx.rooms) == pytest.approx(110, abs=0.05)
    assert "Balcony" not in names("dry") | names("all") and "Balcony" in names("everything")
    assert names("wet") == {"Master Bathroom", "Bathroom 2", "Guest WC"}
    assert names("dry").isdisjoint(names("wet"))


def test_dimension_and_area_parsing():
    assert dim(2400) == pytest.approx(2.4) and dim(20) == 20 and dim(21) == pytest.approx(0.021)
    assert dim("2400 MM") == pytest.approx(2.4) and dim("96in") == pytest.approx(2.4384)
    assert dim(150.0, mm_above=150) == 150 and dim(151, mm_above=150) == pytest.approx(0.151)
    assert area("135 sqft") == pytest.approx(12.5419, rel=1e-4) and area("12.5 m²") == 12.5


def test_rate_editor_trade_rate_marks_owner_and_keeps_comments(rates_copy):
    before = rates_copy.read_text()
    set_dotted(rates_copy, "trades.carpenter.cost_per_hour", 24)
    set_dotted(rates_copy, "pricing.contingency_pct", 7)
    rb = Ratebook.load(rates_copy)
    assert rb.trades["carpenter"]["cost_per_hour"] == 24 and not rb.is_placeholder(rb.trades["carpenter"])
    after = rates_copy.read_text()
    assert after.count("#") == before.count("#")
    assert "contingency_pct = 7                # added to the selling price" in after


# ================================================================== regressions for bugs found in QA (all fixed)
def test_bug_price_on_single_item_scope_is_ignored(rates):
    est = run(rates, [{"title": "Wardrobe", "type": "wardrobe", "width": 2.4, "price": 5000}])
    assert est["scope"][0]["amount"] == 5000


@pytest.mark.parametrize("item", [{"type": "media_unit", "width": 3.0}, {"type": "bed_box", "size": "king"}])
def test_bug_media_unit_and_bed_box_ignore_qty(rates, item):
    one = run(rates, [dict(item, qty=1)])["scope"][0]["internal"]["sell_build_up"]
    two = run(rates, [dict(item, qty=2)])["scope"][0]["internal"]["sell_build_up"]
    assert two == pytest.approx(2 * one, rel=0.01)


def test_bug_room_perimeter_above_20_read_as_mm(rates):
    est = run(rates, [{"type": "painting", "rooms": "Living Room"}],
              rooms=[{"name": "Living Room", "area": 27.9, "perimeter": 21.4}])
    assert est["internal"]["rooms"][0]["perimeter"] == pytest.approx(21.4)
    assert est["scope"][0]["amount"] > 0


def test_bug_show_prelims_line_double_counts_prelims_cost(rates):
    est = run(rates, [{"type": "wardrobe", "width": 2.4}, {"type": "flooring", "area": 30}], show_prelims_line=True)
    total = sum(s["internal"]["cost_total"] for s in est["scope"])
    assert total == pytest.approx(est["internal"]["direct_cost"], abs=1.0)


@pytest.mark.parametrize("item, key", [
    ({"type": "switch", "count": 1, "mode": "faceplate"}, "electrical_point"),
    ({"type": "roller_blind", "width": 0.5, "height": 0.5}, "blinds"),
    ({"type": "mirrors", "width": 0.3, "height": 0.3}, "mirror"),
    ({"type": "led", "length": 1}, "led_strip"),
    ({"type": "curtain", "width": 0.5, "height": 0.5}, "curtains"),
])
def test_bug_min_charge_bypassed_by_type_alias(rates, item, key):
    est = run(rates, [{"title": "X", "items": [item]}])
    assert est["scope"][0]["internal"]["sell_build_up"] >= rates.data["min_charges"][key]


def test_bug_bedrooms_selector_includes_bathroom_and_balcony(rates):
    ctx = Context(rates, {"project": {}, "rooms": [
        {"name": "Master Bedroom", "area": 18}, {"name": "Master Bathroom", "area": 6},
        {"name": "Master Balcony", "area": 6}, {"name": "Bedroom 2", "area": 14}]})
    assert {r.name for r in ctx.select_rooms("bedrooms")} == {"Master Bedroom", "Bedroom 2"}


def test_bug_drawer_pack_gets_phantom_door(rates):
    est = run(rates, [{"type": "kitchen_base", "width": 0.6, "drawers": 4, "drawer_height": 0.19}])
    assert qty(est, "hinge_soft_close") == 0
    assert not any("Hinged doors" in i for i in est["scope"][0]["includes"])


def test_bug_ceiling_mr_board_only_for_wet_rooms(rates):
    rooms = [{"name": "Living Room", "length": 6, "width": 4}, {"name": "Bathroom", "length": 2, "width": 2}]
    est = run(rates, [{"type": "gypsum_ceiling"}], rooms=rooms)
    assert qty(est, "gypsum_board_mr") == pytest.approx(4 * 1.1 / 2.88, rel=1e-3)
    assert qty(est, "gypsum_board_std") == pytest.approx(24 * 1.1 / 2.88, rel=1e-3)


@pytest.mark.parametrize("item", [{"type": "gypsum_partition", "length": 4, "board": "std"},
                                  {"type": "gypsum_ceiling", "area": 10, "board": "mr"}])
def test_bug_board_shorthands(rates, item):
    run(rates, [item])


def test_bug_rate_editor_accepts_non_numeric_price(rates_copy):
    r = subprocess.run([sys.executable, str(SCRIPTS / "rates.py"), "--rates", str(rates_copy),
                        "set", "materials.spc_plank.cost", "38,5"], capture_output=True, text=True)
    assert r.returncode != 0
    assert isinstance(Ratebook.load(rates_copy).materials["spc_plank"]["cost"], (int, float))


def test_bug_rates_add_like_loses_category(rates_copy):
    subprocess.run([sys.executable, str(SCRIPTS / "rates.py"), "--rates", str(rates_copy), "add", "tile_80x80",
                    "--name", "Porcelain tile 800 x 800", "--unit", "tile", "--cost", "40",
                    "--length-mm", "800", "--width-mm", "800", "--like", "tile_60x60"], check=True, capture_output=True)
    rb = Ratebook.load(rates_copy)
    assert rb.materials["tile_80x80"]["category"] == "tiles"


def test_bug_rate_editor_writes_into_terms(rates_copy):
    set_values(rates_copy, "quote", {"title": "X"})
    rb = Ratebook.load(rates_copy)
    assert rb.data["terms"][0]["title"] == "Scope of Work"
    assert rb.data["quote"].get("title") == "X"


def test_bug_min_charge_on_zero_quantity(rates):
    est = run(rates, [{"type": "socket", "count": 0}, {"type": "flooring", "area": 20}])
    assert est["scope"][0]["internal"]["sell_build_up"] == 0


def test_bug_round_mirror_without_diameter_error(rates):
    with pytest.raises(SpecError):
        run(rates, [{"type": "mirror", "shape": "round"}])


def test_bug_levelling_labour_not_charged_on_spc(rates):
    est = run(rates, [{"type": "flooring", "material": "spc_plank", "area": 40, "levelling": 3}])
    lev = next(l for l in lines(est, kind="labour") if "levelling" in l["calc"])
    assert lev["sell"] > 0


def test_bug_wallpaper_long_wall_read_as_mm(rates):
    est = run(rates, [{"type": "wallpaper", "width": 22, "height": 2.8}])
    assert est["scope"][0]["qty"] == pytest.approx(22 * 2.8, rel=0.01)


def test_bug_package_sums_unrelated_areas(rates):
    est = run(rates, [{"title": "Refresh", "items": [{"type": "flooring", "area": 30},
                                                     {"type": "painting", "area": 80}]}])
    assert est["scope"][0]["qty_display"] != "110 m²"


def test_bug_unit_on_single_item_scope_is_ignored(rates):
    est = run(rates, [{"type": "supply", "name": "Curtain rods", "cost": 50, "qty": 10, "unit": "set"}])
    assert est["scope"][0]["qty_display"] == "10 set"


def test_bug_separate_backlit_mirrors_share_one_driver(rates):
    est = run(rates, [{"type": "mirror", "width": 0.9, "height": 1.2, "backlit": True, "qty": 4}])
    assert sum(l["qty"] for l in lines(est) if l["ref"].startswith("led_driver")) == 4


def test_bug_zero_length_led_adds_driver(rates):
    est = run(rates, [{"type": "led_strip", "length": 0}, {"type": "flooring", "area": 20}])
    assert not any(l["ref"].startswith("led_driver") for l in lines(est))


def test_bug_confirm_typo_creates_section(rates_copy):
    r = subprocess.run([sys.executable, str(SCRIPTS / "rates.py"), "--rates", str(rates_copy),
                        "confirm", "materials.tile_60x6"], capture_output=True, text=True)
    assert r.returncode != 0 and "tile_60x6" not in Ratebook.load(rates_copy).materials


def test_bug_fixed_item_extras_loaded_onto_other_items(rates):
    b = {"title": "B", "items": [{"type": "flooring", "area": 30}]}
    flex = run(rates, [{"title": "A", "items": [{"type": "wardrobe", "width": 2.4}]}, b])
    fixed = run(rates, [{"title": "A", "price": 5000, "items": [{"type": "wardrobe", "width": 2.4}]}, b])
    assert fixed["scope"][1]["amount"] <= flex["scope"][1]["amount"]
