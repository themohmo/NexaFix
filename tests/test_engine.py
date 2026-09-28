"""Tests for the NexaFix costing engine. Run: python -m pytest tests -q"""
from __future__ import annotations

import math
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "nexa-costing"
sys.path.insert(0, str(SKILL / "scripts"))

from nexa_costing.engine import run_estimate  # noqa: E402
from nexa_costing.joinery import build_cabinet, hinges_for_height  # noqa: E402
from nexa_costing.ratebook import Ratebook, set_dotted  # noqa: E402
from nexa_costing.spec import load_spec_file  # noqa: E402
from nexa_costing.util import SpecError, dim  # noqa: E402


@pytest.fixture()
def rates():
    return Ratebook.load(SKILL / "rates.toml")


def lines(est, no="01", kind=None):
    sc = next(s for s in est["scope"] if s["no"] == no)
    return [l for l in sc["internal"]["lines"] if kind is None or l["kind"] == kind]


def purchase(est, ref):
    return next(p for p in est["internal"]["purchase_list"] if p["ref"] == ref)


def run(rates, scope, rooms=None, **project):
    project.setdefault("ceiling_height", 2.8)
    return run_estimate({"project": project, "rooms": rooms or [], "scope": scope}, rates)


# ------------------------------------------------------------------ the owner's own example
def test_spc_example_planks_cost_and_resale(rates):
    """42.5 m² of SPC, plank 1800 x 180 (0.324 m²), cost 35, resale 110, 8% waste."""
    est = run(rates, [{"type": "flooring", "material": "spc_plank", "area": 42.5, "skirting": False,
                       "thresholds": False}])
    plank = next(l for l in lines(est) if l["ref"] == "spc_plank")
    expected = 42.5 * 1.08 / 0.324
    assert plank["qty"] == pytest.approx(expected, rel=1e-3)          # 141.67 planks
    assert plank["unit_cost"] == 35 and plank["unit_sell"] == 110
    assert plank["sell"] == pytest.approx(expected * 110, rel=1e-3)
    assert purchase(est, "spc_plank")["qty_to_buy"] == 142
    # resale price covers installation: labour costed but not charged again
    lab = lines(est, kind="labour")
    assert lab and all(l["sell"] == 0 for l in lab) and all(l["cost"] > 0 for l in lab)


def test_tiles_60x60_boxes_and_setting_materials(rates):
    est = run(rates, [{"type": "tiles", "material": "tile_60x60", "area": 20, "skirting": False,
                       "thresholds": False}])
    tiles = next(l for l in lines(est) if l["ref"] == "tile_60x60")
    assert tiles["qty"] == pytest.approx(20 * 1.08 / 0.36, rel=1e-3)   # 60 tiles
    p = purchase(est, "tile_60x60")
    assert p["qty_to_buy"] == (math.ceil(60 / 4) + 1) * 4              # 15 boxes + 1 spare
    refs = {l["ref"] for l in lines(est)}
    assert {"tile_adhesive", "tile_grout", "tile_clips"} <= refs


# ------------------------------------------------------------------ joinery
def test_board_sheets_are_pooled_across_items(rates):
    """Several small units share sheets instead of each buying a whole one."""
    scope = [{"type": "nightstand", "title": f"N{i}"} for i in range(5)]
    est = run(rates, scope)
    p = purchase(est, "mfc_18")
    assert p["qty_required"] < 3                     # ~1.1 sheets of parts in total
    assert p["qty_to_buy"] == math.ceil(p["qty_required"])
    assert est["internal"]["stock_rounding_cost"] > 0


def test_hinge_rule():
    assert hinges_for_height(0.7) == 2
    assert hinges_for_height(1.2) == 3
    assert hinges_for_height(1.9) == 4
    assert hinges_for_height(2.5, [[0.9, 2], [1.6, 3], [2.0, 4], [2.6, 5], [99, 6]]) == 5


def test_cabinet_model_counts():
    m = build_cabinet(2.4, 2.6, 0.6, sections=3, shelves=6, doors="auto", door_type="hinged",
                      plinth=0.1, max_door_width=0.5, hanging_sections=2)
    assert m.doors == 5
    assert m.door_height == pytest.approx(2.5, abs=0.01)
    roles = m.area_by_role()
    assert roles["back"] == pytest.approx(2.4 * 2.5)
    assert roles["front"] == pytest.approx(2.4 * 2.5 + 2.4 * 0.1, rel=0.02)
    assert m.hanging_m == pytest.approx(1.6)


def test_wardrobe_hours_in_research_band(rates):
    est = run(rates, [{"type": "wardrobe", "width": 2.4}])
    hrs = est["scope"][0]["internal"]["labour_hours"]
    assert 28 <= hrs["carpenter"] <= 45        # research: ~38 mh for 2.4 x 2.6 wardrobe
    assert 10 <= hrs["installer"] <= 16        # ~5 mh/lm (+10% site access)


def test_media_unit_two_shelves_and_panel(rates):
    est = run(rates, [{"type": "media_unit", "width": 3.0, "shelves": 2,
                       "panel": {"material": "stone_pvc_panel"}}])
    refs = [l["ref"] for l in lines(est)]
    assert "stone_pvc_panel" in refs and "floating_bracket" in refs and "drawer_runner" in refs
    assert any(i.startswith("Floating display shelves, two (2)") for i in est["scope"][0]["includes"])
    one = run(rates, [{"type": "media_unit", "width": 3.0, "shelves": 1}])
    assert one["totals"]["subtotal"] < run(rates, [{"type": "media_unit", "width": 3.0, "shelves": 2}])["totals"]["subtotal"]


# ------------------------------------------------------------------ lighting / electrical / gypsum
def test_led_driver_sizing_respects_80_percent(rates):
    est = run(rates, [{"type": "led_strip", "length": 38, "profile": False}])
    drv = [l for l in lines(est) if l["ref"].startswith("led_driver")]
    assert len(drv) == 1
    watts = int(rates.material(drv[0]["ref"])["watts"])
    n = drv[0]["qty"]
    assert n * watts * 0.8 >= 38 * 10               # 380 W carried at <= 80% load
    strip = next(l for l in lines(est) if l["ref"] == "led_strip_24v")
    assert strip["qty"] == pytest.approx(38 * 1.05)
    assert purchase(est, "led_strip_24v")["qty_to_buy"] == 40   # whole 5 m rolls


def test_socket_points_new_vs_relocate(rates):
    new = run(rates, [{"type": "socket", "count": 4, "mode": "new"}])
    rel = run(rates, [{"type": "socket", "count": 4, "mode": "relocate"}])
    assert new["scope"][0]["qty_display"] == "4 pts"
    assert next(l for l in lines(new) if l["ref"] == "socket_double_13a")["qty"] == 4
    assert new["totals"]["subtotal"] > rel["totals"]["subtotal"]


def test_gypsum_partition_quantities(rates):
    est = run(rates, [{"type": "gypsum_partition", "length": 4.0, "height": 2.8}])
    L = {l["ref"]: l for l in lines(est)}
    area = 4.0 * 2.8
    assert L["gypsum_board_std"]["qty"] == pytest.approx(area * 2 * 1.1 / 2.88, rel=1e-3)
    assert L["stud_c"]["qty"] == math.ceil(4.0 / 0.6) + 1
    assert est["scope"][0]["qty_display"] == "11.2 m²"


def test_wet_room_ceiling_uses_mr_board(rates):
    rooms = [{"name": "Master Bathroom", "length": 2.6, "width": 2.2}]
    est = run(rates, [{"type": "gypsum_ceiling", "rooms": "Master Bathroom"}], rooms=rooms)
    assert any(l["ref"] == "gypsum_board_mr" for l in lines(est))


# ------------------------------------------------------------------ project level
def test_totals_add_up_and_vat(rates):
    spec = load_spec_file(SKILL / "examples" / "2br-marina-full-fitout.yaml")
    est = run_estimate(spec, rates)
    t = est["totals"]
    assert sum(s["amount"] for s in est["scope"]) == pytest.approx(t["subtotal"])
    assert t["vat"] == pytest.approx(t["net"] * 0.05, abs=0.01)
    assert t["grand_total"] == pytest.approx(t["net"] + t["vat"], abs=0.01)
    assert all(s["amount"] % 50 == 0 for s in est["scope"])
    it = est["internal"]
    assert it["direct_cost"] == pytest.approx(
        it["materials_cost"] + it["labour_cost"] + it["other_cost"] + it["consumables_cost"]
        + it["stock_rounding_cost"] + it["prelims_cost"] + it["snagging_reserve_cost"], abs=0.05)
    assert 0 < it["gross_margin_pct"] < 100
    assert it["schedule"]["total_days"] > 0
    names = {p["name"] for p in it["prelims"]}
    assert {"Transport & delivery", "Floor & site protection", "Final cleaning"} <= names


def test_typology_rough_estimate(rates):
    est = run_estimate({"project": {"typology": "2br", "total_area": "1250 sqft"},
                        "scope": [{"type": "flooring", "rooms": "dry"}]}, rates)
    area = est["scope"][0]["qty"]
    assert 70 < area < 100                       # dry indoor share of ~116 m²
    assert any("typical Dubai" in a for a in est["internal"]["assumptions"])


def test_fixed_price_and_sell_rate(rates):
    est = run(rates, [{"type": "gypsum_partition", "length": 4, "height": 2.5, "sell_rate": 100},
                      {"title": "Package", "price": 5000, "items": [{"type": "mirror", "width": 1, "height": 1}]}])
    assert est["scope"][1]["amount"] == 5000
    assert est["scope"][0]["internal"]["sell_build_up"] == pytest.approx(1000)


def test_discount_and_no_vat(rates):
    est = run(rates, [{"type": "mirror", "width": 1, "height": 1}], discount_pct=10, vat=False)
    t = est["totals"]
    assert t["discount"] == pytest.approx(t["subtotal"] * 0.10)
    assert t["vat"] == 0 and t["grand_total"] == t["net"]


def test_every_item_type_runs(rates):
    rooms = [{"name": "Living Room", "length": 5, "width": 4}, {"name": "Bathroom", "length": 2, "width": 2}]
    scope = [
        {"type": "flooring", "rooms": "Living Room", "pattern": "herringbone", "removal": True, "levelling": 3},
        {"type": "wall_tiles", "material": "tile_120x60", "width": 2, "height": 2.4, "room": "Bathroom"},
        {"type": "wall_cladding", "material": "pvc_marble_sheet", "width": 3.5, "openings": [[1, 1]], "lighting": True},
        {"type": "wall_cladding", "material": "acoustic_slat_panel", "width": 2, "framing": True},
        {"type": "cove_lighting", "rooms": "Living Room", "build_cove": True},
        {"type": "led_strip", "length": 3, "sensor": True},
        {"type": "gypsum_partition", "length": 3, "doors": 1, "insulation": True},
        {"type": "gypsum_ceiling", "rooms": "Living Room", "cove_length": "perimeter", "downlights": 6,
         "supply_downlights": True, "access_panels": 1},
        {"type": "painting", "surfaces": "both", "prep": "full"},
        {"type": "wallpaper", "width": 3.2, "pattern_repeat": 0.53},
        {"type": "switch", "count": 2}, {"type": "data_point", "count": 1}, {"type": "socket", "kind": "isolator", "count": 1},
        {"type": "socket", "count": 3, "mode": "faceplate"},
        {"type": "mirror", "diameter": 0.8, "shape": "round", "edge": "bevel", "frame": True},
        {"type": "wardrobe", "width": 2.0, "door_type": "sliding", "front_board": "mdf_18", "finish": "lacquer"},
        {"type": "kitchen_base", "width": 3.0, "countertop": True, "drawers": 3},
        {"type": "kitchen_wall", "width": 3.0, "handles": "push", "flaps": 2},
        {"type": "vanity", "width": 0.9, "countertop": "quartz_countertop"},
        {"type": "display_unit", "width": 1.2}, {"type": "bookshelf", "width": 1.6}, {"type": "shoe_cabinet", "width": 1.2},
        {"type": "dresser", "width": 1.2, "handles": "profile"}, {"type": "study_desk", "width": 1.4},
        {"type": "media_unit", "width": 3.2, "side_units": 2, "tv_bracket": True, "panel_led": True},
        {"type": "headboard", "style": "tufted"}, {"type": "bed_box", "size": "queen", "upholstered": True},
        {"type": "countertop", "length": 2.4, "sink": 1, "hob": 1, "splashback": 0.6},
        {"type": "curtains", "width": 3.0, "layers": ["blackout", "sheer"], "motorised": True},
        {"type": "blinds", "width": 1.2, "height": 1.5, "qty": 3, "motorised": True},
        {"type": "demolition", "what": "tiles", "area": 12},
        {"type": "supply", "name": "3-seater sofa", "cost": 3500, "qty": 1, "install_hours": 1},
        {"type": "custom", "title": "Door re-skin", "lines": [
            {"material": "mdf_18", "qty": 2}, {"trade": "carpenter", "hours": 6},
            {"description": "Door hardware", "cost": 150, "qty": 2}]},
    ]
    est = run(rates, scope, rooms=rooms, show_prelims_line=True, building_fees=300)
    assert len(est["scope"]) == len(scope) + 1
    for s in est["scope"]:
        assert s["amount"] > 0, s["title"]
        assert s["includes"] or s["title"].startswith(("Door", "Custom")), s["title"]


# ------------------------------------------------------------------ inputs & errors
def test_dimension_parsing():
    assert dim(2400) == pytest.approx(2.4)
    assert dim("240 cm") == pytest.approx(2.4)
    assert dim("2.4m") == pytest.approx(2.4)
    assert dim("8ft") == pytest.approx(2.4384)
    assert dim(3.2) == pytest.approx(3.2)


def test_helpful_errors(rates):
    with pytest.raises(SpecError, match="Did you mean"):
        run(rates, [{"type": "flooring", "material": "spc_plnk", "area": 10}])
    with pytest.raises(SpecError, match="Unknown item type"):
        run(rates, [{"type": "jacuzzi"}])
    with pytest.raises(SpecError, match="width"):
        run(rates, [{"type": "wardrobe"}])
    with pytest.raises(SpecError, match="No room matches"):
        run(rates, [{"type": "flooring", "rooms": "Garage"}], rooms=[{"name": "Living", "area": 20}])


# ------------------------------------------------------------------ rate book editing
def test_rate_edit_keeps_comments_and_clears_placeholder(tmp_path):
    p = tmp_path / "rates.toml"
    shutil.copy(SKILL / "rates.toml", p)
    before = p.read_text()
    changes = set_dotted(p, "materials.wpc_fluted_panel.cost", 38.5)
    assert any("35.0 -> 38.5" in c for c in changes)
    rb = Ratebook.load(p)
    assert rb.materials["wpc_fluted_panel"]["cost"] == 38.5
    assert not rb.is_placeholder(rb.materials["wpc_fluted_panel"])
    after = p.read_text()
    assert after.count("#") == before.count("#")               # comments survive
    set_dotted(p, "materials.brand_new_panel.cost", 12)         # new section is created
    assert Ratebook.load(p).materials["brand_new_panel"]["cost"] == 12
    set_dotted(p, "pricing.contingency_pct", 7)
    assert Ratebook.load(p).pricing["contingency_pct"] == 7


def test_rate_edit_rejects_breaking_changes(tmp_path):
    p = tmp_path / "rates.toml"
    shutil.copy(SKILL / "rates.toml", p)
    with pytest.raises(SpecError):
        set_dotted(p, "materials", 1)
