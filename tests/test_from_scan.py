"""Tests for the NexaFix Scan -> costing bridge (skills/nexa-costing/scripts/from_scan.py).

The fixture tests/fixtures/scan_costing_spec.json is the costing spec the Swift side writes for a
hand-built studio (NexaFixCore, DataExportTests.testWriteFixturesWhenRequested):
    NEXAFIX_FIXTURE_DIR=<dir> swift test --filter DataExportTests/testWriteFixturesWhenRequested

Run: python -m pytest tests/test_from_scan.py -q
"""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "nexa-costing"
SCRIPTS = SKILL / "scripts"
FIXTURE = ROOT / "tests" / "fixtures" / "scan_costing_spec.json"
sys.path.insert(0, str(SCRIPTS))

import from_scan  # noqa: E402
from nexa_costing.spec import build_room  # noqa: E402
from nexa_costing.util import SpecError  # noqa: E402


# ---------------------------------------------------------------- helpers
def fixture() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def write_spec(tmp_path: Path, spec: dict, name: str = "scan.json") -> Path:
    p = tmp_path / name
    p.write_text(json.dumps(spec, ensure_ascii=False), encoding="utf-8")
    return p


def run(*args, cwd=None) -> subprocess.CompletedProcess:
    """Run from_scan.py exactly as a user would."""
    return subprocess.run([sys.executable, str(SCRIPTS / "from_scan.py"), *map(str, args)],
                          capture_output=True, text=True, cwd=cwd)


def estimate(spec_path: Path, out: Path) -> dict:
    """Price a spec with the real engine (no PDFs) and return estimate.json."""
    r = subprocess.run([sys.executable, str(SCRIPTS / "estimate.py"), str(spec_path), "--out", str(out), "--no-pdf"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout
    files = list(out.glob("*/estimate.json"))
    assert len(files) == 1, files
    return json.loads(files[0].read_text(encoding="utf-8"))


def rooms_of(spec: dict) -> list:
    return [build_room(r, 2.8, []) for r in spec["rooms"]]


# ---------------------------------------------------------------- the fixture itself
def test_fixture_has_the_shape_the_app_writes():
    spec = fixture()
    assert set(spec) == {"project", "rooms", "scope", "x_nexafix_scan"}
    assert spec["scope"] == []                         # the engine rejects an empty scope: this file is a starting point
    assert set(spec["project"]) == {"client", "name", "location", "ref", "ceiling_height"}
    living, bath, balcony = spec["rooms"]
    # L-shaped room: area + perimeter, no length / width. Rectangles: length + width.
    assert "area" in living and "perimeter" in living and "length" not in living
    assert "length" in bath and "width" in bath and "area" not in bath
    assert balcony["tags"] == ["outdoor"]
    assert bath["wet"] is True and bath["tags"] == ["bathroom"]
    for r in spec["rooms"]:
        assert isinstance(r["doors"], list) and isinstance(r["windows"], list)   # always explicit, never defaulted
    scan = spec["x_nexafix_scan"]
    assert scan["schema"] == "nexafix.costing-spec" and scan["version"] == 1
    assert scan["warning"] and scan["unverified_joinery"]
    assert scan["joinery_verified_count"] < scan["joinery_measurement_count"]
    assert len(scan["unverified_joinery"]) == scan["joinery_measurement_count"] - scan["joinery_verified_count"]


def test_fixture_rooms_load_through_the_engine_parser():
    notes: list = []
    spec = fixture()
    rooms = [build_room(r, spec["project"]["ceiling_height"], notes) for r in spec["rooms"]]
    assert notes == []                                  # no value was rescaled or estimated
    living, bath, balcony = rooms
    # L-shape 5.6 x 4.6 less a 2.2 x 2.2 notch = 20.92 m2; walls 5.62 + 2.4 + 2.2 + 2.2 + 3.4 + 4.61 = 20.43 m.
    assert living.area == pytest.approx(20.92)
    assert living.perimeter == pytest.approx(20.43)
    assert living.height == pytest.approx(2.92)
    assert len(living.doors) == 1 and living.doors[0] == pytest.approx((0.9, 2.1))
    assert living.windows[0] == pytest.approx((1.8, 2.3))
    assert bath.area == pytest.approx(2.2 * 1.8) and bath.perimeter == pytest.approx(2 * (2.2 + 1.8))
    assert bath.wet and "bathroom" in bath.tags
    assert "outdoor" in balcony.tags and not balcony.matches("all") and not balcony.matches("dry")
    assert balcony.area == pytest.approx(3.8 * 1.5)


# ---------------------------------------------------------------- the main flows
def test_starter_scope_prices_with_the_real_engine(tmp_path):
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    assert r.stdout == ""                               # --out: nothing on stdout
    spec = json.loads(out.read_text(encoding="utf-8"))
    assert [s["title"] for s in spec["scope"]] == ["SPC Flooring", "Painting"]
    assert spec["scope"][0]["rooms"] == "dry" and spec["scope"][1]["surfaces"] == "both"
    assert spec["x_nexafix_scan"] == fixture()["x_nexafix_scan"]   # provenance travels with the spec

    est = estimate(out, tmp_path / "out")
    assert est["totals"]["grand_total"] > 0
    assert [s["title"] for s in est["scope"]] == ["SPC Flooring", "Painting"]
    assert est["totals"]["subtotal"] == pytest.approx(sum(s["amount"] for s in est["scope"]), abs=0.02)

    # What the engine understood of the scan, against numbers worked out by hand:
    rooms = {x["name"]: x for x in est["internal"]["rooms"]}
    assert rooms["Living / Kitchen"]["area"] == pytest.approx(20.92)
    assert rooms["Living / Kitchen"]["perimeter"] == pytest.approx(20.43)
    # walls = 20.43 x 2.92 - (0.9 x 2.1 + 1.8 x 2.3) = 59.6556 - 6.03 = 53.6256
    assert rooms["Living / Kitchen"]["wall_area"] == pytest.approx(53.63, abs=0.01)
    # bathroom walls = 8.0 x 2.6 - 0.75 x 2.1 = 19.225
    assert rooms["Bathroom"]["wall_area"] == pytest.approx(19.23, abs=0.01)
    assert rooms["Bathroom"]["wet"] is True and rooms["Balcony"]["wet"] is False

    flooring = next(l for l in est["scope"][0]["internal"]["lines"] if l["ref"] == "spc_plank")
    assert flooring["calc"].startswith("20.92 m")        # dry indoor rooms only: no bathroom, no balcony
    paint = [l["calc"] for l in est["scope"][1]["internal"]["lines"]]
    assert any("walls 72.85" in c for c in paint)        # 53.6256 + 19.225
    assert any("ceilings 24.88" in c for c in paint)     # 20.92 + 3.96
    # The engine did not need any default: the app's explicit doors / windows were used.
    assert not any("estimated" in str(w) for w in est["internal"]["warnings"])


def test_scope_from_json_file_with_project_overrides(tmp_path):
    scope = {"project": {"vat": False, "discount_pct": 10, "salutation": "Dear Ms. Layla,"},
             "scope": [{"title": "TV Unit", "type": "media_unit", "width": 2.4, "room": "Living / Kitchen"},
                       {"title": "Vanity", "type": "vanity", "width": 0.9, "room": "Bathroom"}]}
    sp = tmp_path / "scope.json"
    sp.write_text(json.dumps(scope), encoding="utf-8")
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--scope", sp, "--out", out)
    assert r.returncode == 0, r.stderr
    spec = json.loads(out.read_text(encoding="utf-8"))
    assert [s["title"] for s in spec["scope"]] == ["TV Unit", "Vanity"]
    assert spec["project"]["vat"] is False and spec["project"]["discount_pct"] == 10
    assert spec["project"]["name"] == "Studio 1207"      # the scan's own project keys survive
    assert "project overrides" in r.stderr
    est = estimate(out, tmp_path / "out")
    assert est["totals"]["vat"] == 0
    assert est["totals"]["discount"] > 0
    assert est["totals"]["grand_total"] == pytest.approx(est["totals"]["net"])


def test_scope_from_yaml_file_and_list_form(tmp_path):
    pytest.importorskip("yaml")
    sp = tmp_path / "scope.yaml"
    sp.write_text("- {title: Wardrobe, type: wardrobe, width: 2.2, room: Living / Kitchen}\n"
                  "- {title: Cove, type: cove_lighting, rooms: [Living / Kitchen]}\n", encoding="utf-8")
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--scope", sp, "--out", out)
    assert r.returncode == 0, r.stderr
    spec = json.loads(out.read_text(encoding="utf-8"))
    assert [s["title"] for s in spec["scope"]] == ["Wardrobe", "Cove"]
    assert estimate(out, tmp_path / "out")["totals"]["grand_total"] > 0

    # mapping form, YAML, with a rooms: list that must be ignored (rooms come from the scan)
    sp2 = tmp_path / "scope2.yml"
    sp2.write_text("project: {vat: false}\nrooms: [{name: Ghost, length: 3, width: 3}]\n"
                   "scope:\n  - {title: Paint, type: painting, rooms: all}\n", encoding="utf-8")
    out2 = tmp_path / "spec2.json"
    r2 = run(FIXTURE, "--scope", sp2, "--out", out2)
    assert r2.returncode == 0, r2.stderr
    assert "rooms:` ignored" in r2.stderr
    spec2 = json.loads(out2.read_text(encoding="utf-8"))
    assert [x["name"] for x in spec2["rooms"]] == ["Living / Kitchen", "Bathroom", "Balcony"]


def test_scope_and_starter_combine_and_starter_does_not_double_up(tmp_path):
    sp = tmp_path / "scope.json"
    sp.write_text(json.dumps([{"title": "Laminate", "type": "laminate", "rooms": "dry"}]), encoding="utf-8")
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--scope", sp, "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    spec = json.loads(out.read_text(encoding="utf-8"))
    # The estimator already chose flooring: only painting is added.
    assert [s["title"] for s in spec["scope"]] == ["Laminate", "Painting"]
    assert "starter flooring skipped" in r.stderr
    assert estimate(out, tmp_path / "out")["totals"]["grand_total"] > 0


def test_starter_skips_what_the_scan_cannot_take(tmp_path):
    spec = fixture()
    spec["rooms"] = [r for r in spec["rooms"] if r["name"] == "Balcony"]          # outdoor only
    r = run(write_spec(tmp_path, spec), "--starter", "--out", tmp_path / "o.json")
    assert r.returncode == 2                                                       # nothing left: empty scope
    assert "empty scope" in r.stderr
    assert "starter flooring skipped: no dry indoor room" in r.stderr and "starter painting skipped: no indoor room" in r.stderr
    assert not (tmp_path / "o.json").exists()

    spec = fixture()
    spec["rooms"] = [r for r in spec["rooms"] if r["name"] == "Bathroom"]          # wet only: painting yes, flooring no
    out = tmp_path / "wet.json"
    r = run(write_spec(tmp_path, spec, "wet_scan.json"), "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    assert [s["title"] for s in json.loads(out.read_text())["scope"]] == ["Painting"]
    assert estimate(out, tmp_path / "wet_out")["totals"]["grand_total"] > 0


# ---------------------------------------------------------------- refusals
def test_refuses_to_write_an_empty_scope(tmp_path):
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--out", out)
    assert r.returncode == 2
    assert "empty scope" in r.stderr
    assert not out.exists()
    # An empty scope FILE is no better.
    sp = tmp_path / "empty.json"
    sp.write_text("[]", encoding="utf-8")
    r = run(FIXTURE, "--scope", sp, "--out", out)
    assert r.returncode == 2 and not out.exists()
    # And nothing is printed on stdout either.
    assert r.stdout == ""


@pytest.mark.parametrize("mutate, message", [
    (lambda s: s.update(rooms=[]), "no rooms"),
    (lambda s: s.pop("rooms"), "no rooms"),
    (lambda s: s["rooms"].append("not a room"), "every entry of `rooms`"),
    (lambda s: s["rooms"][0].pop("area"), "needs length + width, or area"),
    (lambda s: s["rooms"][0].update(area="lots"), "can't read area"),
    (lambda s: s["rooms"][1].update(length="long"), "can't read length"),
    (lambda s: s.update(scope="nope"), "`scope` must be a list"),
    (lambda s: s.update(project=[1]), "`project` must be an object"),
])
def test_bad_scans_are_rejected_before_anything_is_written(tmp_path, mutate, message):
    spec = fixture()
    mutate(spec)
    out = tmp_path / "spec.json"
    r = run(write_spec(tmp_path, spec), "--starter", "--out", out)
    assert r.returncode == 2, r.stdout
    assert message in r.stderr, r.stderr
    assert not out.exists()


def test_unreadable_inputs(tmp_path):
    out = tmp_path / "spec.json"
    r = run(tmp_path / "missing.json", "--starter", "--out", out)
    assert r.returncode == 2 and "cannot read" in r.stderr
    bad = tmp_path / "bad.json"
    bad.write_text("{ not json", encoding="utf-8")
    r = run(bad, "--starter", "--out", out)
    assert r.returncode == 2 and "not valid JSON" in r.stderr
    r = run(FIXTURE, "--scope", tmp_path / "nope.yaml", "--out", out)
    assert r.returncode == 2 and "cannot read" in r.stderr
    notscope = tmp_path / "scope.json"
    notscope.write_text(json.dumps({"title": "x"}), encoding="utf-8")
    r = run(FIXTURE, "--scope", notscope, "--out", out)
    assert r.returncode == 2 and "no `scope:` list" in r.stderr
    binary = tmp_path / "bin.json"
    binary.write_bytes(b"\xff\xfe\x00\x00garbage")
    r = run(binary, "--starter", "--out", out)
    assert r.returncode == 2
    assert not out.exists()


@pytest.mark.parametrize("scope, message", [
    ([{"title": "Wardrobe", "type": "wardrobe", "width": 2, "room": "Master Bedroom"}], "no room matches 'Master Bedroom'"),
    ([{"title": "Floor", "type": "flooring", "rooms": ["dry", "Attic"]}], "no room matches 'Attic'"),
    ([{"title": "No type"}], "needs either `type`"),
    (["just a string"], "must be a mapping"),
    ([{"title": "Pkg", "room": "Balcony", "items": ["oops"]}], "must be a mapping"),
])
def test_invalid_scope_entries_are_caught(tmp_path, scope, message):
    sp = tmp_path / "scope.json"
    sp.write_text(json.dumps(scope), encoding="utf-8")
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--scope", sp, "--out", out)
    assert r.returncode == 2, r.stderr
    assert message in r.stderr, r.stderr
    assert "Rooms: Living / Kitchen, Bathroom, Balcony" in r.stderr or "room matches" not in message
    assert not out.exists()


def test_check_flag_runs_the_engine(tmp_path):
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--starter", "--check", "--out", out)
    assert r.returncode == 0, r.stderr
    assert "engine dry run: ok" in r.stderr
    # A scope the shape check accepts but the engine cannot price is caught by --check, and nothing is written.
    sp = tmp_path / "scope.json"
    sp.write_text(json.dumps([{"title": "Floor", "type": "flooring", "material": "no_such_material", "rooms": "dry"}]),
                  encoding="utf-8")
    bad = tmp_path / "bad.json"
    r = run(FIXTURE, "--scope", sp, "--check", "--out", bad)
    assert r.returncode == 2 and "no_such_material" in r.stderr
    assert not bad.exists()
    # Without --check the same file is written (the shape is valid) - the check is opt-in.
    r = run(FIXTURE, "--scope", sp, "--out", bad)
    assert r.returncode == 0 and bad.exists()


# ---------------------------------------------------------------- the unverified-dimension warning
def test_warning_block_lists_unverified_joinery_dimensions(tmp_path):
    r = run(FIXTURE, "--starter", "--out", tmp_path / "spec.json")
    err = r.stderr
    scan = fixture()["x_nexafix_scan"]
    n = len(scan["unverified_joinery"])
    assert "WARNING: JOINERY-CRITICAL DIMENSIONS NOT VERIFIED ON SITE" in err
    assert f"Studio 1207 (scanned 2026-10-07): {n} of {scan['joinery_measurement_count']} joinery-critical" in err
    assert "BUDGET" in err
    # Real entries, with scanned millimetres and the typical tolerance (1.5 % of 2.4 m = 36 mm).
    assert "Living / Kitchen: Wall B length - 2400 mm (typically +/-36 mm)" in err
    # Verified items are NOT listed: wall A, wall F and the ceiling of the living room were laser-checked.
    assert "Living / Kitchen: Wall A length" not in err
    assert "Living / Kitchen: Ceiling height" not in err
    # Only the first 15 are listed; the rest are counted.
    assert err.count("\n  - ") == 15
    assert f"... and {n - 15} more" in err


def test_no_warning_when_everything_is_verified(tmp_path):
    spec = fixture()
    scan = spec["x_nexafix_scan"]
    scan["unverified_joinery"] = []
    scan["warning"] = None
    scan["joinery_verified_count"] = scan["joinery_measurement_count"]
    r = run(write_spec(tmp_path, spec), "--starter", "--out", tmp_path / "o.json", "--strict")
    assert r.returncode == 0, r.stderr
    assert "WARNING" not in r.stderr and "NOT VERIFIED" not in r.stderr


def test_spec_without_scan_block_is_flagged_not_trusted(tmp_path):
    spec = fixture()
    del spec["x_nexafix_scan"]
    r = run(write_spec(tmp_path, spec), "--starter", "--out", tmp_path / "o.json")
    assert r.returncode == 0
    assert "did not come from the NexaFix Scan app" in r.stderr
    assert "WARNING: JOINERY" not in r.stderr          # nothing is claimed either way


def test_strict_fails_after_writing_when_dimensions_are_unverified(tmp_path):
    out = tmp_path / "spec.json"
    r = run(FIXTURE, "--starter", "--out", out, "--strict")
    assert r.returncode == 3
    assert "--strict" in r.stderr
    assert out.exists()                                  # written: the estimator can still budget with it
    assert json.loads(out.read_text())["scope"]


# ---------------------------------------------------------------- output handling
def test_stdout_carries_clean_json_when_no_out_is_given(tmp_path):
    r = run(FIXTURE, "--starter")
    assert r.returncode == 0
    spec = json.loads(r.stdout)                          # warnings must not leak into stdout
    assert len(spec["scope"]) == 2 and len(spec["rooms"]) == 3
    assert "WARNING" in r.stderr


def test_input_is_never_modified_and_output_is_atomic(tmp_path):
    scan = tmp_path / "scan.json"
    scan.write_bytes(FIXTURE.read_bytes())
    before = scan.read_bytes()
    out = tmp_path / "nested" / "dir" / "spec.json"
    r = run(scan, "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    assert scan.read_bytes() == before
    assert [p.name for p in out.parent.iterdir()] == ["spec.json"]       # no temp file left behind
    # Overwriting works and stays valid JSON.
    r = run(scan, "--starter", "--out", out)
    assert r.returncode == 0
    assert json.loads(out.read_text())["scope"]


def test_unicode_survives(tmp_path):
    spec = fixture()
    spec["rooms"][0]["name"] = "غرفة المعيشة / Majlis"
    spec["project"]["client"] = "السيد أحمد"
    out = tmp_path / "spec.json"
    r = run(write_spec(tmp_path, spec), "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    text = out.read_text(encoding="utf-8")
    assert "غرفة المعيشة / Majlis" in text               # written as UTF-8, not \u escapes
    assert json.loads(text)["project"]["client"] == "السيد أحمد"
    est = estimate(out, tmp_path / "out")
    assert est["meta"]["client"] == "السيد أحمد"
    assert "غرفة المعيشة / Majlis" in [x["name"] for x in est["internal"]["rooms"]]


def test_file_with_a_byte_order_mark_loads(tmp_path):
    p = tmp_path / "scan.json"
    p.write_bytes(b"\xef\xbb\xbf" + FIXTURE.read_bytes())
    r = run(p, "--starter", "--out", tmp_path / "o.json")
    assert r.returncode == 0, r.stderr


def test_existing_scope_is_kept_and_reported(tmp_path):
    spec = fixture()
    spec["scope"] = [{"title": "Painting", "type": "painting", "rooms": "all"}]
    out = tmp_path / "spec.json"
    r = run(write_spec(tmp_path, spec), "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    assert "already has 1 scope item" in r.stderr
    assert [s["title"] for s in json.loads(out.read_text())["scope"]] == ["Painting", "SPC Flooring"]
    assert "starter painting skipped" in r.stderr


# ---------------------------------------------------------------- units: what the engine rescales
def test_numbers_the_engine_would_read_as_millimetres_are_reported(tmp_path):
    """The app writes big lengths as text ("72.5m"); a hand-edited plain number is flagged."""
    spec = fixture()
    spec["rooms"][1]["length"] = 3200                  # someone typed millimetres into a metres field
    r = run(write_spec(tmp_path, spec), "--starter", "--out", tmp_path / "o.json")
    assert r.returncode == 0
    assert "read as millimetres (3.2 m)" in r.stderr   # surfaced, not silent


def test_big_rooms_written_as_text_are_not_rescaled():
    notes: list = []
    hall = build_room({"name": "Warehouse", "length": "72.5m", "width": 31.25, "height": 9,
                       "perimeter": "280m", "area": 2265.625, "tags": [], "doors": [], "windows": []}, 2.8, notes)
    assert notes == []
    assert hall.length == pytest.approx(72.5) and hall.perimeter == pytest.approx(280)
    # The same value as a plain number is read as 72.5 mm: exactly the trap the app avoids.
    trap: list = []
    plain = build_room({"name": "Warehouse", "length": 72.5, "width": 31.25, "area": 100}, 2.8, trap)
    assert plain.length == pytest.approx(0.0725)
    assert trap and "millimetres" in trap[0]


# ---------------------------------------------------------------- unit-level
def test_validate_returns_engine_rooms_and_notes():
    spec = fixture()
    rooms, notes = from_scan.validate(spec)
    assert [r.name for r in rooms] == ["Living / Kitchen", "Bathroom", "Balcony"]
    assert notes == []
    with pytest.raises(SpecError):
        from_scan.validate({**spec, "scope": [{"title": "x", "type": "painting", "rooms": "Attic"}]})


def test_starter_scope_function():
    rooms, _ = from_scan.validate(fixture())
    items, skipped = from_scan.starter_scope(rooms, [])
    assert [i["type"] for i in items] == ["flooring", "painting"] and skipped == []
    # package-style scope entries count too
    items, skipped = from_scan.starter_scope(rooms, [{"title": "Pkg", "items": [{"type": "spc"}]}])
    assert [i["type"] for i in items] == ["painting"] and len(skipped) == 1


def test_build_spec_does_not_mutate_its_inputs(tmp_path):
    p = tmp_path / "scan.json"
    p.write_text(json.dumps(fixture()), encoding="utf-8")
    spec, warnings, info = from_scan.build_spec(p, None, True)
    assert spec["scope"] and json.loads(p.read_text()) == fixture()
    assert copy.deepcopy(spec) == spec


def test_runs_from_any_directory(tmp_path):
    r = run(FIXTURE, "--starter", "--out", "spec.json", cwd=tmp_path)
    assert r.returncode == 0, r.stderr
    assert (tmp_path / "spec.json").exists()
    r = subprocess.run([sys.executable, str(SCRIPTS / "from_scan.py"), "--help"], capture_output=True, text=True)
    assert r.returncode == 0 and "--starter" in r.stdout


# ---------------------------------------------------------------- --strict fails closed
def verified(spec: dict) -> dict:
    """The fixture with a scan block that proves everything joinery-critical was verified."""
    scan = spec["x_nexafix_scan"]
    scan["unverified_joinery"] = []
    scan["warning"] = None
    scan["joinery_verified_count"] = scan["joinery_measurement_count"]
    return spec


def _drop_block(s):
    del s["x_nexafix_scan"]


def _drop_list(s):
    verified(s)
    del s["x_nexafix_scan"]["unverified_joinery"]


def _list_empty_counts_say_unverified(s):
    s["x_nexafix_scan"].update(unverified_joinery=[], warning=None)     # joinery_verified_count stays below the total


def _counts_missing(s):
    verified(s)
    del s["x_nexafix_scan"]["joinery_verified_count"]


def _counts_zero(s):
    verified(s)
    s["x_nexafix_scan"].update(joinery_measurement_count=0, joinery_verified_count=0)


def _counts_overclaim(s):
    verified(s)
    s["x_nexafix_scan"]["joinery_verified_count"] = s["x_nexafix_scan"]["joinery_measurement_count"] + 3


def _counts_not_numbers(s):
    verified(s)
    s["x_nexafix_scan"]["joinery_verified_count"] = "all"


def _counts_disagree_with_list(s):
    s["x_nexafix_scan"]["joinery_verified_count"] -= 2                  # list now has too few entries for the counts


def _block_is_not_an_object(s):
    s["x_nexafix_scan"] = ["verified"]


def _all_verified_but_list_not_empty(s):
    verified(s)
    s["x_nexafix_scan"]["unverified_joinery"] = [{"room": "X", "item": "Wall A length", "scanned_m": 3.0}]


@pytest.mark.parametrize("mutate, why", [
    (_drop_block, "no `x_nexafix_scan` block"),
    (_drop_list, "`x_nexafix_scan.unverified_joinery` is missing"),
    (_list_empty_counts_say_unverified, "joinery-critical dimensions are verified"),
    (_counts_missing, "are missing or not whole numbers"),
    (_counts_zero, "counts no joinery-critical dimensions"),
    (_counts_overclaim, "claims"),
    (_counts_not_numbers, "are missing or not whole numbers"),
    (_counts_disagree_with_list, "disagree"),
    (_block_is_not_an_object, "no `x_nexafix_scan` block"),
    (_all_verified_but_list_not_empty, "listed as unverified"),
])
def test_strict_fails_closed_when_verification_is_unknown_or_inconsistent(tmp_path, mutate, why):
    spec = fixture()
    mutate(spec)
    out = tmp_path / "o.json"
    r = run(write_spec(tmp_path, spec), "--starter", "--out", out, "--strict")
    assert r.returncode == 3, r.stderr
    assert "--strict" in r.stderr and why in r.stderr, r.stderr
    assert out.exists()                       # still written: the estimator can budget with it, the exit code is the gate
    # Without --strict the same file is accepted (the gate is opt-in).
    r = run(write_spec(tmp_path, spec, "again.json"), "--starter", "--out", tmp_path / "o2.json")
    assert r.returncode == 0, r.stderr


def test_strict_passes_only_when_the_scan_proves_everything_is_verified(tmp_path):
    r = run(write_spec(tmp_path, verified(fixture())), "--starter", "--out", tmp_path / "o.json", "--strict")
    assert r.returncode == 0, r.stderr
    assert "ERROR" not in r.stderr and "WARNING" not in r.stderr
    # The strict gate also applies when the spec goes to stdout.
    r = run(write_spec(tmp_path, verified(fixture())), "--starter", "--strict")
    assert r.returncode == 0 and json.loads(r.stdout)["scope"]


def test_strict_problems_function_lists_every_reason():
    spec = fixture()
    problems = from_scan.strict_problems(spec, [])
    assert len(problems) == 1 and "dimension(s) are LiDAR-scanned only" in problems[0]
    # Counts that contradict the list are a second, separate reason.
    spec["x_nexafix_scan"]["joinery_verified_count"] = 0
    problems = from_scan.strict_problems(spec, [])
    assert len(problems) == 2 and "disagree" in problems[1]
    del spec["x_nexafix_scan"]
    assert from_scan.strict_problems(spec, []) == ["no `x_nexafix_scan` block, so nothing says which dimensions were verified on site"]
    assert from_scan.strict_problems(verified(fixture()), []) == []


# ---------------------------------------------------------------- the engine's name guessing
def finding_spec() -> dict:
    """Four rooms as the app exports them (tags from the room KIND), with names that make the engine change three."""
    def room(name, length, width, tags, wet=None):
        r = {"name": name, "length": length, "width": width, "height": 2.8, "doors": [[0.9, 2.1]], "windows": [], "tags": tags}
        if wet is not None:
            r["wet"] = wet
        return r
    spec = verified(fixture())
    spec["rooms"] = [room("Living Room", 6, 4, ["living"], False),
                     room("Corridor to Balcony", 5, 1.2, ["circulation"], False),
                     room("Master Bedroom Terrace Side", 4, 4, ["bedroom"], False),
                     room("Showcase Area", 4, 3, [])]                      # kind "other": `wet` is left to the engine
    return spec


def test_the_engine_really_reclassifies_these_rooms():
    """Independent of the code under test: what the engine's own parser does to the four rooms."""
    living, corridor, master, showcase = rooms_of(finding_spec())
    assert corridor.tags == {"circulation", "outdoor"} and not corridor.matches("all") and not corridor.matches("dry")
    assert master.tags == {"bedroom", "outdoor"} and not master.matches("dry")
    assert showcase.tags == {"bathroom"} and showcase.wet and not showcase.matches("dry") and showcase.matches("all")
    assert living.matches("dry") and living.matches("all")


def test_reclassified_rooms_are_reported_with_their_areas(tmp_path):
    spec = finding_spec()
    rooms = rooms_of(spec)
    changes = from_scan.engine_reclassifications(spec, rooms)
    assert [c["room"] for c in changes] == ["Corridor to Balcony", "Master Bedroom Terrace Side", "Showcase Area"]
    assert all(c["excluded"] for c in changes)
    assert changes[0]["added"] == ["outdoor"] and changes[0]["area"] == pytest.approx(6.0)
    assert changes[2]["became_wet"] is True and changes[2]["added"] == ["bathroom"]
    assert "6.0 m2" in changes[0]["message"] and "outdoor" in changes[0]["message"]
    assert "wet area" in changes[2]["message"]

    p = write_spec(tmp_path, spec)
    r = run(p, "--starter", "--check", "--out", tmp_path / "o.json")
    assert r.returncode == 0, r.stderr                      # a warning, not a failure, without --strict
    assert "engine dry run: ok" in r.stderr
    assert "WARNING: THE COSTING ENGINE LEAVES 3 ROOM(S) OUT BECAUSE OF THEIR NAMES" in r.stderr
    for name in ("Corridor to Balcony (6.0 m2)", "Master Bedroom Terrace Side (16.0 m2)", "Showcase Area (12.0 m2)"):
        assert name in r.stderr
    assert "Living Room" not in r.stderr.split("LEAVES")[1].split("Rename the room")[0]
    # What it costs: flooring covers the living room only (24 m2) although three indoor rooms are dry.
    est = estimate(tmp_path / "o.json", tmp_path / "out")
    flooring = next(l for l in est["scope"][0]["internal"]["lines"] if l["ref"] == "spc_plank")
    assert flooring["calc"].startswith("24 m"), flooring["calc"]


def test_strict_refuses_a_scan_the_engine_would_under_quote(tmp_path):
    r = run(write_spec(tmp_path, finding_spec()), "--starter", "--out", tmp_path / "o.json", "--strict")
    assert r.returncode == 3, r.stderr                     # every dimension is verified, but three rooms drop out
    assert "--strict: the engine leaves out of the `all` / `dry` selectors" in r.stderr
    assert "Corridor to Balcony" in r.stderr.split("--strict:")[1]
    # Renaming the rooms fixes it.
    spec = finding_spec()
    for r_, new in zip(spec["rooms"], ["Living Room", "Passage", "Main Suite", "Display Area"]):
        r_["name"] = new
    r = run(write_spec(tmp_path, spec, "renamed.json"), "--starter", "--out", tmp_path / "o2.json", "--strict")
    assert r.returncode == 0, r.stderr
    assert "LEAVES" not in r.stderr


def test_a_tag_added_without_dropping_the_room_is_only_a_note(tmp_path):
    # "Living / Kitchen" is a living room whose name adds `kitchen`: informational, and --strict still passes.
    r = run(write_spec(tmp_path, verified(fixture())), "--starter", "--out", tmp_path / "o.json", "--strict")
    assert r.returncode == 0, r.stderr
    assert "NOTE: Living / Kitchen (20.9 m2): the engine also tags it `kitchen` from its name" in r.stderr
    assert "WARNING: THE COSTING ENGINE" not in r.stderr


def test_unchanged_rooms_produce_no_reclassification_output():
    spec = fixture()
    for r in spec["rooms"]:
        r["name"] = {"Living / Kitchen": "Main Area", "Bathroom": "Bathroom", "Balcony": "Balcony"}[r["name"]]
    assert from_scan.engine_reclassifications(spec) == []


def test_reclassification_when_the_file_has_no_wet_flag_for_a_dry_looking_room():
    spec = fixture()
    spec["rooms"][0]["name"] = "Wc Lobby"
    spec["rooms"][0].pop("wet", None)
    spec["rooms"][0]["tags"] = []
    [c] = [c for c in from_scan.engine_reclassifications(spec) if c["room"] == "Wc Lobby"]
    assert c["became_wet"] and c["excluded"] and set(c["added"]) == {"bathroom", "circulation"}


# The same table as DataExportTests.engineGuessTable on the Swift side. The Swift mirror of the engine's
# name guessing is only a heads-up in the exported notes; this proves it and the engine agree.
ENGINE_GUESS_TABLE = [
    ("Corridor to Balcony", ["circulation", "outdoor"]), ("Master Bedroom Terrace Side", ["outdoor"]),
    ("Showcase Area", ["bathroom"]), ("Bedroom 2 Ensuite", ["bathroom"]), ("Living Room", ["living"]),
    ("Maid's Room", ["utility"]), ("Master Bath", ["bathroom"]), ("Master", ["bedroom"]), ("Hall", ["circulation"]),
    ("Wallpaper Store", ["utility"]), ("Store Room", ["utility"]), ("Majlis", ["living"]), ("Kitchenette", ["kitchen"]),
    ("غرفة المعيشة", []), ("", []),
    ("BALCONY", ["outdoor"]), ("Dining", ["living"]), ("Powder Room", ["bathroom"]), ("Entrance", ["circulation"]),
    ("Lobby / Foyer", ["circulation"]), ("Study", []), ("Terrace", ["outdoor"]), ("Master Bedroom", ["bedroom"]),
    ("Walk-in WC", ["bathroom"]), ("Bedroom", ["bedroom"]), ("Hallway Bedroom", ["bedroom", "circulation"]),
    ("Entry", ["circulation"]), ("Kitchen", ["kitchen"]), ("Laundry", ["utility"]), ("Storage", []), ("Office", []),
    ("Reception", []), ("Meeting Room", []), ("Room", []), ("Living", ["living"]), ("Cinema Room", []),
    ("Master Suite Balcony", ["outdoor"]), ("Master Laundry", ["utility"]),
]


@pytest.mark.parametrize("name, expected", ENGINE_GUESS_TABLE)
def test_swift_name_guess_table_matches_the_engine(name, expected):
    from nexa_costing.spec import _guess_tags
    assert sorted(_guess_tags(name)) == expected


def test_malformed_room_fields_are_reported_not_crashed(tmp_path):
    spec = fixture()
    spec["rooms"][0]["tags"] = 5                           # the engine's parser raises TypeError on this
    out = tmp_path / "o.json"
    r = run(write_spec(tmp_path, spec), "--starter", "--out", out)
    assert r.returncode == 2, r.stderr
    assert "Traceback" not in r.stderr and "cannot be read" in r.stderr and "Living / Kitchen" in r.stderr
    assert not out.exists()


# ---------------------------------------------------------------- output encoding, file mode, floors
def test_stdout_is_utf8_even_when_the_console_cannot_encode_it(tmp_path):
    spec = fixture()
    spec["rooms"][0]["name"] = "غرفة المعيشة / Majlis"
    spec["project"]["client"] = "السيد أحمد"
    env = {**os.environ, "PYTHONIOENCODING": "ascii", "PYTHONUTF8": "0"}
    r = subprocess.run([sys.executable, str(SCRIPTS / "from_scan.py"), str(write_spec(tmp_path, spec)), "--starter"],
                       capture_output=True, env=env)
    assert r.returncode == 0, r.stderr.decode("utf-8", "replace")
    assert b"Traceback" not in r.stderr and b"UnicodeEncodeError" not in r.stderr
    parsed = json.loads(r.stdout.decode("utf-8"))
    assert parsed["rooms"][0]["name"] == spec["rooms"][0]["name"]
    assert parsed["project"]["client"] == spec["project"]["client"]
    assert len(parsed["scope"]) == 2


@pytest.mark.skipif(os.name == "nt", reason="POSIX permission bits")
def test_out_file_gets_the_normal_mode_not_the_temp_file_mode(tmp_path):
    old = os.umask(0o022)
    try:
        out = tmp_path / "spec.json"
        r = run(FIXTURE, "--starter", "--out", out)
        assert r.returncode == 0, r.stderr
        assert (out.stat().st_mode & 0o777) == 0o644          # 0666 minus the umask, not mkstemp's 0600
        # Overwriting keeps whatever mode the file already had.
        out.chmod(0o640)
        r = run(FIXTURE, "--starter", "--out", out)
        assert r.returncode == 0, r.stderr
        assert (out.stat().st_mode & 0o777) == 0o640
        # A stricter umask is honoured for a new file.
        os.umask(0o077)
        other = tmp_path / "private.json"
        assert run(FIXTURE, "--starter", "--out", other).returncode == 0
        assert (other.stat().st_mode & 0o777) == 0o600
    finally:
        os.umask(old)


def test_unverified_list_names_the_floor_when_the_property_has_several():
    spec = fixture()
    items = spec["x_nexafix_scan"]["unverified_joinery"]
    for i, item in enumerate(items):
        item["floor"] = "Ground" if i % 2 == 0 else "First"
    lines = "\n".join(from_scan.unverified_block(spec))
    assert f"  - {items[0]['room']} (Ground): {items[0]['item']}" in lines
    assert f"  - {items[1]['room']} (First): {items[1]['item']}" in lines
    # One floor only: no clutter.
    for item in items:
        item["floor"] = "Ground"
    assert "(Ground)" not in "\n".join(from_scan.unverified_block(spec))
    # The same name on two floors stays distinguishable.
    twins = [{"room": "Bedroom", "floor": f, "item": "Wall A length", "scanned_m": 4.0, "typical_tolerance_m": 0.06} for f in ("Ground", "First")]
    spec["x_nexafix_scan"]["unverified_joinery"] = twins
    text = "\n".join(from_scan.unverified_block(spec))
    assert "Bedroom (Ground): Wall A length" in text and "Bedroom (First): Wall A length" in text
