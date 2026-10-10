"""The whole NexaFix Scan data path, read back by tools that are not the app.

The Swift test `EndToEndTests` (ios/NexaFixCore) runs the path a person takes on site:
two scan sessions on one property -> ScanFlow naming -> ScanCommit -> PropertyStore save and reload ->
readings typed into VerifyModel ("3,245" on a wall, a ceiling height, a window width ...) -> ExportEngine with
every format in every display unit. It writes what came out to tests/fixtures/scan_demo_*.json
(see EndToEndTests.testWriteFixturesWhenRequested):

    scan_demo_scan.json                    the scan file, readings typed in
    scan_demo_costing_spec.json            its costing spec (most joinery still LiDAR-only)
    scan_demo_costing_spec_verified.json   the same property with EVERY dimension verified
    scan_demo_artifacts.json               what was typed + the PDF / DXF / CSV / USDZ files of each display unit

This file opens those files with pypdf, pdftoppm, ezdxf, the csv module, json and the real costing engine, and
checks them against SCAN-FILE-FORMAT.md and against each other. The rule behind most of it: after a reading is
typed in, the VERIFIED number is what every file shows and prices from, the scanned number stays beside it
(JSON, CSV) or disappears (plan labels), and the geometry never moves.

Optional tools: pypdf, ezdxf, pdftoppm and Pillow. A test that needs one skips cleanly without it.

Run: python -m pytest tests/test_scan_pipeline.py -q
"""
from __future__ import annotations

import base64
import csv
import io
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "tests" / "fixtures"
SCRIPTS = ROOT / "skills" / "nexa-costing" / "scripts"
FORMAT_DOC = ROOT / "ios" / "docs" / "SCAN-FILE-FORMAT.md"
sys.path.insert(0, str(SCRIPTS))

from nexa_costing.spec import build_room  # noqa: E402

DISCLAIMER = "LiDAR dimensions are typically within 1-2 %. Verify every dimension joinery will be cut to with a laser measure."
UNITS = ["mm", "cm", "m", "in", "ftin"]
# CSV column suffix -> metres per unit, and square feet.
CSV_SUFFIX = {"mm": ("_mm", 0.001, "_m2", 1.0), "cm": ("_cm", 0.01, "_m2", 1.0), "m": ("_m", 1.0, "_m2", 1.0),
              "in": ("_in", 0.0254, "_sqft", 0.09290304), "ftin": ("_ft", 0.3048, "_sqft", 0.09290304)}


# ---------------------------------------------------------------- loading
def _load(name: str):
    path = FIX / name
    assert path.exists(), (f"{path} is missing: regenerate it with "
                           "NEXAFIX_FIXTURE_DIR=<repo>/tests/fixtures swift test --filter EndToEndTests/testWriteFixturesWhenRequested")
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def scan() -> dict:
    return _load("scan_demo_scan.json")


@pytest.fixture(scope="module")
def bundle() -> dict:
    return _load("scan_demo_artifacts.json")


@pytest.fixture(scope="module")
def files(bundle, tmp_path_factory) -> dict:
    """{unit: {suffix-less key: Path}} with every file of the bundle written out under its real name."""
    root = tmp_path_factory.mktemp("exports")
    out: dict = {}
    for unit, entry in bundle["units"].items():
        folder = root / unit
        folder.mkdir()
        out[unit] = {}
        for name, file in entry["files"].items():
            data = base64.b64decode(file["data"]) if file["encoding"] == "base64" else file["data"].encode("utf-8")
            path = folder / name
            path.write_bytes(data)
            out[unit][name] = path
    return out


def find(files: dict, unit: str, suffix: str) -> Path:
    matches = [p for n, p in files[unit].items() if n.endswith(suffix)]
    assert len(matches) == 1, (unit, suffix, sorted(files[unit]))
    return matches[0]


def read_csv(path: Path) -> list[dict]:
    raw = path.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf"), f"{path.name} has no UTF-8 byte order mark"
    assert raw.endswith(b"\r\n"), f"{path.name} does not end with CRLF"
    rows = list(csv.reader(io.StringIO(raw.decode("utf-8-sig"), newline="")))
    width = len(rows[0])
    assert all(len(r) == width for r in rows), f"{path.name} has ragged rows"
    return [dict(zip(rows[0], r)) for r in rows[1:]]


def rooms_of(scan: dict) -> list[dict]:
    return [r for f in scan["floors"] for r in f["rooms"]]


def room_named(scan: dict, name: str) -> dict:
    return next(r for r in rooms_of(scan) if r["name"] == name)


def measured_of(scan: dict, check: dict) -> dict:
    room = room_named(scan, check["room"])
    q = check["quantity"]
    if q == "ceilingHeight":
        return room["ceilingHeight"]
    if q == "wallLength":
        return next(w for w in room["walls"] if w["label"] == check["label"])["length"]
    if q == "openingWidth":
        return next(o for o in room["openings"] if o["label"] == check["label"])["width"]
    if q == "customLength":
        return next(c for c in room["customMeasurements"] if c["label"] == check["label"])["length"]
    raise AssertionError(q)


# ---------------------------------------------------------------- the app's number formats, written again here
def fmt_len(metres: float, unit: str) -> str:
    """What the app prints for a length in a display unit (UnitFormatter, precise)."""
    if unit == "mm":
        return f"{metres * 1000:.0f} mm"
    if unit == "cm":
        return f"{metres * 100:.1f} cm"
    if unit == "m":
        return f"{metres:.3f} m"
    if unit == "in":
        return f"{metres / 0.0254:.2f} in"
    return ft_in(metres)


def fmt_bare(metres: float, unit: str) -> str:
    """The number alone, as inside an opening label ("W 1185v x 1200"); feet and inches use decimal inches."""
    return {"mm": f"{metres * 1000:.0f}", "cm": f"{metres * 100:.1f}", "m": f"{metres:.3f}".rstrip("0").rstrip("."),
            "in": f"{metres / 0.0254:.2f}", "ftin": f"{metres / 0.0254:.2f}"}[unit]


def nearby(value: float, step: float = 6e-5) -> list[float]:
    """The scan file rounds metres to 0.1 mm, so a printed figure can sit one rounding step either side of it."""
    return [value - step, value, value + step]


def ft_in(metres: float, denominator: int = 16) -> str:
    sixteenths = int(math.floor(abs(metres) / 0.0254 * denominator + 0.5))
    inches_total, fraction = divmod(sixteenths, denominator)
    feet, inches = divmod(inches_total, 12)
    out = f"{feet}' " if feet > 0 else ""
    out += str(inches)
    if fraction:
        n, d = fraction, denominator
        while n % 2 == 0 and d % 2 == 0:
            n //= 2
            d //= 2
        out += f" {n}/{d}"
    return out + '"'


# ================================================================ the bundle itself
def test_bundle_is_what_the_swift_test_writes(bundle):
    assert bundle["schema"] == "nexafix.e2e-artifacts" and bundle["version"] == 1
    assert set(bundle["units"]) == set(UNITS)
    assert [f["name"] for f in bundle["property"]["floors"]] == ["Level 23", "Level 23 (2)"]
    assert [f["rooms"] for f in bundle["property"]["floors"]] == [["Living Room", "Kitchen", "Lounge", "Open Dining"],
                                                                  ["Bedroom", "Kitchen 2", "Balcony"]]
    typed = bundle["typed"]
    assert [c["quantity"] for c in typed] == ["wallLength", "ceilingHeight", "openingWidth", "wallLength", "wallLength",
                                              "customLength", "ceilingHeight"]
    assert typed[0]["typed"] == "3,245" and typed[0]["verifiedM"] == 3.245       # a comma is a decimal point
    assert {c["source"] for c in typed} == {"laser", "tape", "drawing"}
    for unit in UNITS:
        names = sorted(bundle["units"][unit]["files"])
        assert any(n.endswith("_floor-plan.pdf") for n in names)
        assert any(n.endswith("_rooms.csv") for n in names) and any(n.endswith("_walls.csv") for n in names)
        assert any(n.endswith("plan-Level-23.dxf") for n in names)
    assert len(bundle["units"]["mm"]["files"]) == 10     # PDF, 2 DXF, 2 USDZ, 5 CSV (custom measurements included)


def test_usdz_bytes_pass_through_untouched(files):
    one = find(files, "mm", "model-Level-23.usdz").read_bytes()
    two = find(files, "mm", "model-Level-23-2.usdz").read_bytes()
    assert one.startswith(b"PK\x03\x04fake-usdz-level-1") and one.endswith(bytes(range(64)))
    assert two.startswith(b"PK\x03\x04fake-usdz-level-2") and two.endswith(bytes(range(64)))


# ================================================================ scan JSON vs SCAN-FILE-FORMAT.md
def _doc_rows(section_start: str, section_end: str) -> dict[str, list[str]]:
    """Rows of the markdown tables between two headings: {first cell: [other cells]} with backticks kept."""
    text = FORMAT_DOC.read_text(encoding="utf-8")
    start = text.index(section_start)
    end = text.index(section_end, start + 1)
    rows: dict[str, list[str]] = {}
    for line in text[start:end].splitlines():
        if not line.startswith("|") or set(line) <= set("|- "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0].startswith("`"):
            rows[cells[0]] = cells[1:]
    return rows


def _names(cell: str) -> set[str]:
    """Identifiers inside backticks: "`id, name, kind`" -> {id, name, kind}; `start{x,y}` -> {start}; `rooms[]` -> {rooms}."""
    found: set[str] = set()
    for chunk in re.findall(r"`([^`]+)`", cell):
        chunk = re.sub(r"\{[^}]*\}", "", chunk)
        for token in chunk.split(","):
            token = token.strip().rstrip("[]")
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", token):
                found.add(token)
    return found


def _first_list(cells: list[str]) -> set[str]:
    """The first backticked, comma-separated list in a row's description cells."""
    for cell in cells:
        m = re.search(r"`([^`]*,[^`]*)`", cell)
        if m:
            return _names("`" + m.group(1) + "`")
    raise AssertionError(cells)


def test_scan_json_has_exactly_the_documented_fields(scan):
    top = _doc_rows("Top level:", "### Measured object")
    assert set(scan) == {k.strip("`").rstrip("[]") for k in top}
    assert scan["schema"] == "nexafix.scan" and scan["version"] == 1 and scan["generator"] == "NexaFix Scan"
    assert set(scan["property"]) == _first_list(top["`property`"])
    assert set(scan["summary"]) == _first_list(top["`summary`"])
    floor = scan["floors"][0]
    assert set(floor) == _first_list(top["`floors[]`"])
    assert set(floor["assets"]) == {"structureUSDZ", "worldMap"}

    measured = _doc_rows("### Measured object", "### Room")
    keys = {k.strip("`") for k in measured if k.startswith("`")}
    room_rows = _doc_rows("### Room", "### What counts as a checkable dimension")
    doc_room_keys: set[str] = set()
    for cell in room_rows:
        doc_room_keys |= _names(cell)
    for room in rooms_of(scan):
        assert set(room) == doc_room_keys, set(room) ^ doc_room_keys
        assert set(room["ceilingHeight"]) == keys
        assert set(room["verification"]) == _first_list(room_rows["`verification`"])
        for corner in room["corners"]:
            assert set(corner) == _first_list(room_rows["`corners[]`"])
        for wall in room["walls"]:
            assert set(wall) == _first_list(room_rows["`walls[]`"])
            assert set(wall["length"]) == keys and set(wall["height"]) == keys
        for opening in room["openings"]:
            assert set(opening) == _first_list(room_rows["`openings[]`"])
            assert set(opening["width"]) == keys and set(opening["sillHeight"]) == keys
        for obj in room["objects"]:
            assert set(obj) == _first_list(room_rows["`objects[]`"])
        for custom in room["customMeasurements"]:
            assert set(custom) == _first_list(room_rows["`customMeasurements[]`"])
            assert set(custom["length"]) == keys


def test_scan_json_types_and_conventions(scan):
    assert scan["units"]["storage"] == "metres" and scan["units"]["angles"] == "degrees"
    iso = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$")
    assert iso.match(scan["generatedAt"]) and iso.match(scan["property"]["createdAt"])
    assert scan["property"]["kind"] == "apartment"
    assert scan["summary"]["roomCount"] == 7 and scan["summary"]["floorCount"] == 2
    ids = [r["id"] for r in rooms_of(scan)]
    assert len(set(ids)) == 7
    for room in rooms_of(scan):
        assert iso.match(room["scannedAt"])
        for m in [room["ceilingHeight"]] + [w["length"] for w in room["walls"]] + [w["height"] for w in room["walls"]]:
            assert m["valueM"] == (m["verifiedM"] if m["verifiedM"] is not None else m["scannedM"])
            if m["verifiedM"] is None:
                assert m["source"] is None and m["verifiedAt"] is None and m["deviationM"] is None
            else:
                assert m["source"] in ("laser", "tape", "drawing") and iso.match(m["verifiedAt"])
                assert m["deviationM"] == pytest.approx(m["verifiedM"] - m["scannedM"], abs=1.5e-4)
        # Walls: wall i runs from corner i to corner i + 1 and the room is counter-clockwise.
        pts = [(w["start"]["x"], w["start"]["y"]) for w in room["walls"]]
        for i, w in enumerate(room["walls"]):
            nxt = pts[(i + 1) % len(pts)]
            assert (w["end"]["x"], w["end"]["y"]) == nxt
            assert w["index"] == i and w["label"].startswith("Wall ")
        area = sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1])) / 2
        assert area > 0, f"{room['name']} is not counter-clockwise"
        assert room["floorAreaM2"] == pytest.approx(area, abs=2e-3)
        for w in room["walls"]:
            if w["kind"] == "solid":
                assert w["length"]["scannedM"] == pytest.approx(math.dist((w["start"]["x"], w["start"]["y"]),
                                                                          (w["end"]["x"], w["end"]["y"])), abs=2e-4)
    open_plan = room_named(scan, "Open Dining")
    assert [w["kind"] for w in open_plan["walls"]].count("virtual") == 1
    assert room_named(scan, "Lounge")["isRectangular"] is False and room_named(scan, "Lounge")["lengthM"] is None


def test_verified_numbers_are_the_values_and_the_scan_stays_beside_them(scan, bundle):
    for check in bundle["typed"]:
        m = measured_of(scan, check)
        assert m["verifiedM"] == check["verifiedM"], check
        assert m["valueM"] == check["verifiedM"], "valueM is the verified number"
        assert m["scannedM"] == check["scannedM"] and m["scannedM"] != m["verifiedM"]
        assert m["source"] == check["source"]
    assert measured_of(scan, bundle["typed"][0])["note"] == "skirting to skirting"
    # 7 readings, and the summary counts exactly those.
    assert scan["summary"]["verifiedCount"] == 7
    verified = [m for r in rooms_of(scan) for m in ([r["ceilingHeight"]] + [w["length"] for w in r["walls"]]
                + [w["height"] for w in r["walls"]] + [o[k] for o in r["openings"] for k in ("width", "height", "sillHeight")]
                + [c["length"] for c in r["customMeasurements"]]) if m["verifiedM"] is not None]
    assert len(verified) == 7


def test_derived_figures_follow_the_effective_walls_and_flag_blends(scan):
    for name in ("Kitchen", "Living Room", "Bedroom"):
        room = room_named(scan, name)
        eff = [w["length"]["valueM"] for w in room["walls"]]
        raw = [w["length"]["scannedM"] for w in room["walls"]]
        pair = [(eff[0] + eff[2]) / 2, (eff[1] + eff[3]) / 2]
        raw_pair = [(raw[0] + raw[2]) / 2, (raw[1] + raw[3]) / 2]
        long = 0 if pair[0] >= pair[1] else 1
        assert room["lengthM"] == pytest.approx(pair[long], abs=1.5e-4), name
        assert room["widthM"] == pytest.approx(pair[1 - long], abs=1.5e-4), name
        assert room["effectiveFloorAreaM2"] == pytest.approx(pair[0] * pair[1], abs=2e-3), name
        assert room["effectiveFloorAreaScannedM2"] == pytest.approx(raw_pair[0] * raw_pair[1], abs=2e-3), name
        assert room["perimeterM"] == pytest.approx(sum(eff), abs=2e-4) and room["perimeterScannedM"] == pytest.approx(sum(raw), abs=2e-4)
        assert room["floorAreaM2"] == pytest.approx(room["effectiveFloorAreaScannedM2"], abs=0.35), "outline stays the scan"
    # One wall of the pair checked: a blend that matches neither number, and says so.
    assert room_named(scan, "Kitchen")["lengthVerified"] is False
    assert room_named(scan, "Kitchen")["effectiveFloorAreaM2"] != room_named(scan, "Kitchen")["effectiveFloorAreaScannedM2"]
    # Both long walls checked.
    living = room_named(scan, "Living Room")
    assert living["lengthVerified"] is True and living["widthVerified"] is False
    assert living["effectiveFloorAreaVerified"] is False and living["perimeterVerified"] is False
    # An L-shape's area comes from scanned corners: never verified.
    assert room_named(scan, "Lounge")["effectiveFloorAreaVerified"] is False
    # Nothing is checked in the balcony.
    assert room_named(scan, "Balcony")["verification"]["verified"] == 0


def test_file_names_follow_the_documented_pattern(bundle):
    pattern = re.compile(r"^NexaFix_[A-Za-z0-9-]+_\d{4}-\d\d-\d\d_(floor-plan|plan-Level-[A-Za-z0-9-]+|model-Level-[A-Za-z0-9-]+|scan|rooms|walls|"
                         r"openings|objects|custom-measurements|costing-spec)\.(pdf|dxf|usdz|json|csv)$")
    for unit in bundle["units"].values():
        for name in unit["files"]:
            assert pattern.match(name), name
    doc = FORMAT_DOC.read_text(encoding="utf-8")
    assert "_custom-measurements.csv" in doc, "the document must name the file the app really writes"
    assert "NexaFix_<Property>_<yyyy-MM-dd>_<kind>.<ext>" in doc


def test_csv_columns_are_the_documented_columns(files):
    """The column lists in SCAN-FILE-FORMAT.md, in order, are the header rows of the files."""
    doc = FORMAT_DOC.read_text(encoding="utf-8")
    for short, suffix in (("rooms.csv", "_rooms.csv"), ("walls.csv", "_walls.csv"), ("openings.csv", "_openings.csv"),
                          ("objects.csv", "_objects.csv"), ("custom_measurements.csv", "_custom-measurements.csv")):
        m = re.search(r"\*\*`" + re.escape(short) + r"`\*\*:[^\n]*\n`([^`]+)`", doc, re.S)
        assert m, short
        documented = [c.strip() for c in m.group(1).replace("\n", " ").split(",")]
        raw = find(files, "mm", suffix).read_bytes().decode("utf-8-sig")
        assert next(csv.reader(io.StringIO(raw))) == documented, short


def test_costing_spec_keys_are_the_documented_keys():
    doc = FORMAT_DOC.read_text(encoding="utf-8")
    start = doc.index("`x_nexafix_scan` (keys are snake_case")
    paragraph = doc[start:doc.index("\n\n", start)]
    documented = {t for chunk in re.findall(r"`([^`]+)`", paragraph) for t in re.findall(r"[a-z][a-z_]+", chunk)}
    spec = _load("scan_demo_costing_spec.json")
    assert set(spec) == {"project", "rooms", "scope", "x_nexafix_scan"}
    info = spec["x_nexafix_scan"]
    keys = set(info) | set(info["rooms"][0]) | set(info["unverified_joinery"][0])
    assert keys <= documented, keys - documented
    assert {"schema", "version", "generator", "property_id", "scan_date", "verified_count", "measurement_count",
            "joinery_verified_count", "joinery_measurement_count", "rooms", "unverified_joinery", "warning", "notes"} <= set(info)
    for room in spec["rooms"]:
        assert set(room) <= {"name", "length", "width", "area", "perimeter", "height", "doors", "windows", "tags", "wet"}
        assert isinstance(room["doors"], list) and isinstance(room["windows"], list)
    assert set(spec["project"]) == {"client", "name", "location", "ref", "ceiling_height"}
    # "The most common effective ceiling height (to 1 cm; the taller one on a tie)": three rooms read 2.80 m.
    assert spec["project"]["ceiling_height"] == 2.8


# ================================================================ CSV
@pytest.mark.parametrize("unit", UNITS)
def test_csv_parses_and_agrees_with_the_json_in_every_unit(files, scan, unit):
    length_suffix, to_m, area_suffix, to_m2 = CSV_SUFFIX[unit]
    rooms = read_csv(find(files, unit, "_rooms.csv"))
    walls = read_csv(find(files, unit, "_walls.csv"))
    assert [r["room"] for r in rooms] == [r["name"] for r in rooms_of(scan)]
    assert len(walls) == sum(len(r["walls"]) for r in rooms_of(scan))
    # Values come back to the JSON's metres within the CSV's own rounding.
    for row, room in zip(rooms, rooms_of(scan)):
        assert float(row["perimeter" + length_suffix]) * to_m == pytest.approx(room["perimeterM"], abs=2e-4)
        assert float(row["perimeter_scanned" + length_suffix]) * to_m == pytest.approx(room["perimeterScannedM"], abs=2e-4)
        assert float(row["effective_floor_area" + area_suffix]) * to_m2 == pytest.approx(room["effectiveFloorAreaM2"], rel=2e-3, abs=2e-3)
        assert float(row["ceiling_height" + length_suffix]) * to_m == pytest.approx(room["ceilingHeight"]["valueM"], abs=2e-4)
        assert row["ceiling_height_verified"] == ("yes" if room["ceilingHeight"]["verifiedM"] is not None else "no")
        assert row["effective_floor_area_verified"] == ("yes" if room["effectiveFloorAreaVerified"] else "no")
        assert row["is_rectangular"] == ("yes" if room["isRectangular"] else "no")
        assert (row["length_verified"] == ("yes" if room["lengthVerified"] else "no")) if room["isRectangular"] else row["length_verified"] == ""
        assert int(row["verified_count"]) == room["verification"]["verified"] and int(row["measurement_count"]) == room["verification"]["total"]
    by_room = {r["name"]: r for r in rooms_of(scan)}
    for row in walls:
        wall = next(w for w in by_room[row["room"]]["walls"] if w["label"] == row["wall"])
        assert float(row["length" + length_suffix]) * to_m == pytest.approx(wall["length"]["valueM"], abs=2e-4)
        assert float(row["length_scanned" + length_suffix]) * to_m == pytest.approx(wall["length"]["scannedM"], abs=2e-4)
        assert float(row["start_x" + length_suffix]) * to_m == pytest.approx(wall["start"]["x"], abs=2e-4)
        assert float(row["end_y" + length_suffix]) * to_m == pytest.approx(wall["end"]["y"], abs=2e-4)
        verified = wall["length"]["verifiedM"] is not None
        assert row["length_verified"] == ("yes" if verified else "no")
        assert row["length_source"] == (wall["length"]["source"] or "")
        if not verified:
            assert row["length" + length_suffix] == row["length_scanned" + length_suffix], "an unchecked number is the scan"


def test_csv_effective_values_for_every_typed_reading(files, scan, bundle):
    rooms = read_csv(find(files, "mm", "_rooms.csv"))
    walls = read_csv(find(files, "mm", "_walls.csv"))
    openings = read_csv(find(files, "mm", "_openings.csv"))
    customs = read_csv(find(files, "mm", "_custom-measurements.csv"))
    assert len(read_csv(find(files, "mm", "_objects.csv"))) == 4
    for c in bundle["typed"]:
        q = c["quantity"]
        if q == "wallLength":
            row, col = next(r for r in walls if r["room"] == c["room"] and r["wall"] == c["label"]), "length"
        elif q == "openingWidth":
            row, col = next(r for r in openings if r["room"] == c["room"] and r["opening"] == c["label"]), "width"
        elif q == "ceilingHeight":
            row, col = next(r for r in rooms if r["room"] == c["room"]), "ceiling_height"
        else:
            row, col = next(r for r in customs if r["room"] == c["room"] and r["label"] == c["label"]), "length"
        assert row[col + "_mm"] == f"{c['verifiedM'] * 1000:.1f}", c
        assert row[col + "_scanned_mm"] == f"{c['scannedM'] * 1000:.1f}", c
        assert row[col + "_verified"] == "yes" and row[col + "_source"] == c["source"]
    # The bundle's own claim, from the JSON side: 7 verified in total.
    assert sum(int(r["verified_count"]) for r in rooms) == 7


def test_csv_text_is_safe_for_spreadsheets(files):
    for unit in UNITS:
        for name in ("_rooms.csv", "_walls.csv"):
            for row in read_csv(find(files, unit, name)):
                for key, value in row.items():
                    if key in ("room", "wall", "floor", "kind", "notes") or key.endswith("_source"):
                        assert not value.startswith(("=", "+", "@", "\t", "\r")), (unit, name, key, value)
                    else:
                        assert re.fullmatch(r"[A-Za-z0-9\-_ .:,Z']*", value), (unit, name, key, value)


# ================================================================ PDF
def _pdf(files, unit):
    pdf_module = pytest.importorskip("pypdf")
    return pdf_module.PdfReader(str(find(files, unit, "_floor-plan.pdf")), strict=True)


def _lines(page) -> list[str]:
    return [ln.strip() for ln in page.extract_text().splitlines() if ln.strip()]


@pytest.mark.parametrize("unit", UNITS)
def test_pdf_pages_disclaimer_and_schedule(files, scan, unit):
    reader = _pdf(files, unit)
    assert len(reader.pages) == 3
    assert reader.metadata["/Title"] == "Marina Gate 2 - Unit 2304 - floor plans"
    texts = [page.extract_text() for page in reader.pages]
    for i, text in enumerate(texts):
        assert DISCLAIMER in " ".join(text.split()), f"page {i + 1} lacks the joinery disclaimer"
        assert f"Sheet {i + 1} of 3" in text
        assert "Marina Gate 2 - Unit 2304" in text and "NF-2026-1009-01" in text and "Mr. Ahmed Khan" in text
        assert "12 Oct 2026" in text
    assert "LEVEL 23  -  FLOOR PLAN" in texts[0] and "LEVEL 23 (2)  -  FLOOR PLAN" in texts[1]
    assert "Room schedule" in texts[2]
    # A3 sheets: portrait for the tall first floor, landscape for the second.
    sizes = [(round(float(p.mediabox.width)), round(float(p.mediabox.height))) for p in reader.pages]
    assert sizes == [(842, 1191), (1191, 842), (842, 1191)]

    # Schedule: one row per room with the effective area, the ceiling and verified/total.
    schedule = _lines(reader.pages[2])
    is_metric = unit in ("mm", "cm", "m")
    def area_texts(area: float) -> list[str]:
        if is_metric:
            return [f"{a:.2f} m²" for a in nearby(area)]
        return [f"{a / 0.09290304:.1f} sq ft" for a in nearby(area, 6e-4)]

    for room in rooms_of(scan):
        row = next((ln for ln in schedule if any(ln.startswith(f"{room['name']} {t}") for t in area_texts(room["effectiveFloorAreaM2"]))), None)
        assert row is not None, f"{unit}: no schedule row for {room['name']}: {schedule}"
        v = room["verification"]
        assert row.endswith(f"{v['verified']}/{v['total']}"), row
        ceiling = room["ceilingHeight"]
        mark = {None: "", "laser": " v", "tape": " v", "drawing": " d"}[ceiling["source"]]
        assert any(fmt_len(c, unit) + mark in row for c in nearby(ceiling["valueM"])), (unit, row)
    total = sum(r["effectiveFloorAreaM2"] for r in rooms_of(scan))
    counts = f"{scan['summary']['verifiedCount']}/{scan['summary']['measurementCount']}"
    assert any(ln.startswith("Total (7 rooms) " + t) and ln.endswith(counts) for ln in schedule for t in area_texts(total)), schedule
    assert scan["summary"]["totalFloorAreaM2"] == pytest.approx(total, abs=1e-3)
    assert scan["summary"]["verifiedCount"] == 7 and sum(r["verification"]["total"] for r in rooms_of(scan)) == scan["summary"]["measurementCount"]


@pytest.mark.parametrize("unit", UNITS)
def test_pdf_shows_verified_numbers_marked_and_never_the_scan_for_them(files, bundle, unit):
    reader = _pdf(files, unit)
    page1 = " ".join(reader.pages[0].extract_text().split())
    page2 = " ".join(reader.pages[1].extract_text().split())
    pages = {"Level 23": page1, "Level 23 (2)": page2}
    for c in bundle["typed"]:
        if c["quantity"] == "customLength":
            continue                                    # a tape measure is not drawn on the plan
        text = pages[c["floor"]]
        mark = "d" if c["source"] == "drawing" else "v"
        if c["quantity"] == "wallLength":
            assert f"{fmt_len(c['verifiedM'], unit)} v" in text, (unit, c)
            if unit == "mm":
                assert f"{c['scannedM'] * 1000:.0f} mm" not in text.replace(f"{c['verifiedM'] * 1000:.0f} mm", ""), \
                    f"the plan still prints the LiDAR number for {c['room']} {c['label']}"
        elif c["quantity"] == "ceilingHeight":
            assert f"Ceiling {fmt_len(c['verifiedM'], unit)} {mark}" in text, (unit, c)
        else:
            assert f"W {fmt_bare(c['verifiedM'], unit)}v x" in text, (unit, c)
    # The legend explains the marks that appear.
    assert "v = verified on site" in page1
    assert "d = from drawing" in page2 and "d = from drawing" not in page1


def test_pdf_plan_is_north_up_and_at_the_stated_scale(files, scan):
    """Room labels sit on their rooms: north is up, and distances are 1:50 on the sheet."""
    reader = _pdf(files, "mm")
    page = reader.pages[0]
    assert "1:50" in page.extract_text()
    at: dict[str, tuple[float, float]] = {}

    def visit(text, cm, tm, font_dict, font_size):
        if text.strip() in ("Living Room", "Lounge", "Open Dining", "Kitchen"):
            at[text.strip()] = (tm[4], tm[5])

    page.extract_text(visitor_text=visit)
    assert set(at) == {"Living Room", "Lounge", "Open Dining", "Kitchen"}
    centre = {}
    for name in at:
        walls = room_named(scan, name)["walls"]
        xs = [w["start"]["x"] for w in walls]
        ys = [w["start"]["y"] for w in walls]
        centre[name] = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
    pt_per_m = 1000 / 50 * 72 / 25.4
    # Vertical distances on the sheet (labels share their layout, so their baselines keep the plan's spacing).
    # (The L-shaped lounge puts its label at the middle of the room's widest part, not the middle of its box.)
    assert at["Open Dining"][1] > at["Lounge"][1] > at["Living Room"][1], "north is up"
    for a, b in (("Living Room", "Open Dining"), ("Kitchen", "Open Dining")):
        assert at[b][1] > at[a][1], f"{b} should be above {a}: north is up"
        sheet = (at[b][1] - at[a][1]) / pt_per_m
        assert sheet == pytest.approx(centre[b][1] - centre[a][1], rel=0.01), (a, b)
    assert at["Kitchen"][0] > at["Living Room"][0], "the kitchen is east of the living room"


def test_pdf_page_one_rasterised(files, scan, tmp_path):
    """pdftoppm draws the page: the plan is inside its frame, not clipped, and measures 1:50 in ink."""
    if shutil.which("pdftoppm") is None:
        pytest.skip("pdftoppm is not installed")
    image_module = pytest.importorskip("PIL.Image")
    numpy = pytest.importorskip("numpy")
    pdf = find(files, "mm", "_floor-plan.pdf")
    subprocess.run(["pdftoppm", "-r", "72", "-png", str(pdf), str(tmp_path / "pg")], check=True, capture_output=True)
    pages = sorted(tmp_path.glob("pg-*.png"))
    assert len(pages) == 3
    for page_number, floor in ((1, scan["floors"][0]), (2, scan["floors"][1])):
        img = numpy.array(image_module.open(tmp_path / f"pg-{page_number}.png").convert("L"))
        height, width = img.shape
        assert (width, height) in ((842, 1191), (1191, 842))
        # The plan lives above the 125 pt title block and inside a 28 pt frame.
        plan = img[28:height - 130, 28:width - 28] < 60
        ys, xs = numpy.where(plan)
        assert xs.size > 2000, "the plan page is blank"
        assert xs.min() > 3 and ys.min() > 3 and xs.max() < plan.shape[1] - 4 and ys.max() < plan.shape[0] - 4, \
            "ink touches the edge of the plan area: the drawing is clipped"
        wall_x = [p for r in floor["rooms"] for w in r["walls"] for p in (w["start"]["x"], w["end"]["x"])]
        wall_y = [p for r in floor["rooms"] for w in r["walls"] for p in (w["start"]["y"], w["end"]["y"])]
        pt_per_m = 1000 / 50 * 72 / 25.4
        # The ink is the wall centre lines plus the wall thickness (about 0.3 m) and nothing else outside them.
        for ink, span in ((xs.max() - xs.min(), max(wall_x) - min(wall_x)), (ys.max() - ys.min(), max(wall_y) - min(wall_y))):
            assert span * pt_per_m <= ink <= (span + 0.6) * pt_per_m, (floor["name"], ink, span * pt_per_m)


@pytest.mark.parametrize("unit", UNITS)
def test_pdf_scale_bar_is_as_long_as_it_says(files, unit, tmp_path):
    """The bar under the plan ("0 1 2 m", "0 2.5 5 ft") measures its label at 1:50 on the sheet."""
    if shutil.which("pdftoppm") is None:
        pytest.skip("pdftoppm is not installed")
    image_module = pytest.importorskip("PIL.Image")
    numpy = pytest.importorskip("numpy")
    reader = _pdf(files, unit)
    label = re.search(r"\n(0(?: [\d.]+)+) (m|ft)\n", reader.pages[0].extract_text())
    assert label, reader.pages[0].extract_text()
    metres = float(label.group(1).split()[-1]) * (1.0 if label.group(2) == "m" else 0.3048)
    subprocess.run(["pdftoppm", "-r", "144", "-f", "1", "-l", "1", "-png", str(find(files, unit, "_floor-plan.pdf")),
                    str(tmp_path / "pg")], check=True, capture_output=True)
    img = numpy.array(image_module.open(next(tmp_path.glob("pg-*.png"))).convert("L"))
    height, width = img.shape
    longest = 0
    for y in range(int(height * 0.90), int(height * 0.97)):      # the title block's scale bar row
        run = 0
        for dark in img[y, : int(width * 0.4)] < 90:
            run = run + 1 if dark else 0
            longest = max(longest, run)
    drawn_pt = longest / 2                                        # 144 dpi = 2 px per point
    assert drawn_pt == pytest.approx(metres * 1000 / 50 * 72 / 25.4, abs=3), (unit, label.group(0), drawn_pt)


# ================================================================ DXF
def _dxf(files, unit, suffix="plan-Level-23.dxf"):
    ezdxf = pytest.importorskip("ezdxf")
    doc = ezdxf.readfile(str(find(files, unit, suffix)))
    return ezdxf, doc


@pytest.mark.parametrize("unit", UNITS)
def test_dxf_audits_clean_and_is_in_millimetres(files, unit):
    _, doc = _dxf(files, unit)
    auditor = doc.audit()
    assert len(auditor.errors) == 0, [e.message for e in auditor.errors]
    assert doc.header["$INSUNITS"] == 4 and doc.header["$MEASUREMENT"] == 1
    layers = {layer.dxf.name for layer in doc.layers}
    assert {"NF-WALLS", "NF-WALLS-OPEN", "NF-DOORS", "NF-WINDOWS", "NF-DIMENSIONS", "NF-ANGLES", "NF-ROOM-LABELS",
            "NF-NOTES"} <= layers


@pytest.mark.parametrize("suffix,floor_index", [("plan-Level-23.dxf", 0), ("plan-Level-23-2.dxf", 1)])
def test_dxf_entity_counts_follow_the_scan(files, scan, suffix, floor_index):
    ezdxf, doc = _dxf(files, "mm", suffix)
    assert len(doc.audit().errors) == 0
    floor = scan["floors"][floor_index]
    msp = doc.modelspace()
    count = lambda layer, kind: sum(1 for e in msp if e.dxf.layer == layer and e.dxftype() == kind)  # noqa: E731
    rooms = floor["rooms"]
    walls = [w for r in rooms for w in r["walls"]]
    openings = [o for r in rooms for o in r["openings"]]
    assert count("NF-ROOM-LABELS", "TEXT") == 3 * len(rooms)
    assert count("NF-DIMENSIONS", "TEXT") == len(walls)
    assert count("NF-DOORS", "TEXT") == sum(1 for o in openings if o["kind"] == "door")
    assert count("NF-WINDOWS", "TEXT") == sum(1 for o in openings if o["kind"] == "window")
    assert count("NF-WALLS-OPEN", "LINE") == sum(1 for w in walls if w["kind"] == "virtual")
    assert count("NF-WALLS", "LWPOLYLINE") >= sum(1 for w in walls if w["kind"] == "solid")
    assert count("NF-WALLS", "HATCH") == count("NF-WALLS", "LWPOLYLINE")
    notes = " ".join(e.dxf.text for e in msp if e.dxf.layer == "NF-NOTES" and e.dxftype() == "TEXT")
    assert f"Marina Gate 2 - Unit 2304 - {floor['name']}" in notes
    assert "Do not take cutting dimensions from distances measured on" in " ".join(notes.split())
    assert DISCLAIMER.split(" Verify")[0] in notes


def test_dxf_geometry_is_the_scan_in_plan_space_millimetres(files, scan):
    ezdxf, doc = _dxf(files, "mm")
    from ezdxf import bbox
    msp = doc.modelspace()
    floor = scan["floors"][0]
    wall_ext = bbox.extents([e for e in msp if e.dxf.layer in ("NF-WALLS", "NF-WALLS-OPEN")])
    xs = [p for r in floor["rooms"] for w in r["walls"] for p in (w["start"]["x"], w["end"]["x"])]
    ys = [p for r in floor["rooms"] for w in r["walls"] for p in (w["start"]["y"], w["end"]["y"])]
    # Plan metres x 1000 = DXF units (millimetres); the thick walls extend the outline by under half a metre.
    assert wall_ext.extmin.x == pytest.approx(min(xs) * 1000, abs=450)
    assert wall_ext.extmax.x == pytest.approx(max(xs) * 1000, abs=450)
    assert wall_ext.extmin.y == pytest.approx(min(ys) * 1000, abs=450)
    assert wall_ext.extmax.y == pytest.approx(max(ys) * 1000, abs=450)
    assert wall_ext.extmin.x <= min(xs) * 1000 + 1 and wall_ext.extmax.y >= max(ys) * 1000 - 1, "walls cover the outline"
    # North is up: the room labels are ordered like the rooms are.
    labels = {}
    for e in msp:
        if e.dxf.layer == "NF-ROOM-LABELS" and e.dxftype() == "TEXT" and e.dxf.text in {r["name"] for r in floor["rooms"]}:
            labels[e.dxf.text] = (e.dxf.insert.x, e.dxf.insert.y)
    assert set(labels) == {r["name"] for r in floor["rooms"]}
    for room in floor["rooms"]:
        pts = [(w["start"]["x"], w["start"]["y"]) for w in room["walls"]]
        cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2 * 1000
        cy = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2 * 1000
        lx, ly = labels[room["name"]]
        assert abs(lx - cx) < 1500 and abs(ly - cy) < 1500, (room["name"], (lx, ly), (cx, cy))
    # Every scanned corner has a wall outline vertex next to it (the walls are thick, so within a wall width).
    vertices = [(p[0], p[1]) for e in msp if e.dxf.layer == "NF-WALLS" and e.dxftype() == "LWPOLYLINE"
                for p in e.get_points("xy")]
    for room in floor["rooms"]:
        for wall in room["walls"]:
            corner = (wall["start"]["x"] * 1000, wall["start"]["y"] * 1000)
            if wall["kind"] == "solid":
                assert min(math.dist(corner, v) for v in vertices) < 300, (room["name"], wall["label"])


@pytest.mark.parametrize("unit", UNITS)
def test_dxf_text_shows_verified_numbers(files, bundle, unit):
    _, doc = _dxf(files, unit)
    texts = [e.dxf.text for e in doc.modelspace() if e.dxftype() == "TEXT"]
    joined = "\n".join(texts)
    for c in bundle["typed"]:
        if c["floor"] != "Level 23" or c["quantity"] == "customLength":
            continue
        if c["quantity"] == "wallLength":
            assert f"{fmt_len(c['verifiedM'], unit)} v" in texts, (unit, c)
            if unit == "mm":
                assert f"{c['scannedM'] * 1000:.0f} mm" not in texts, f"the drawing still labels the scan for {c['room']} {c['label']}"
        elif c["quantity"] == "ceilingHeight":
            assert f"Ceiling {fmt_len(c['verifiedM'], unit)} v" in texts, (unit, c)
        else:
            assert f"W {fmt_bare(c['verifiedM'], unit)}v x" in joined, (unit, c)
    # The text that is not a number: superscript two and the degree sign are DXF escapes, not "?".
    assert "?" not in joined


# ================================================================ the costing chain
def _run(script: str, *args, cwd=None) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / script), *map(str, args)], capture_output=True, text=True, cwd=cwd)


def test_costing_spec_prices_from_the_verified_numbers(scan, bundle):
    spec = _load("scan_demo_costing_spec.json")
    assert spec["scope"] == []
    assert [r["name"] for r in spec["rooms"]] == [r["name"] for r in rooms_of(scan)]
    by_name = {r["name"]: r for r in spec["rooms"]}
    # Heights are the effective ceilings.
    for room in rooms_of(scan):
        assert by_name[room["name"]]["height"] == pytest.approx(room["ceilingHeight"]["valueM"], abs=1.5e-4)
    assert by_name["Kitchen"]["height"] == 2.76 and by_name["Bedroom"]["height"] == pytest.approx(2.6924)
    # The verified window width is the one the engine sees.
    assert by_name["Kitchen"]["windows"] == [[1.185, 1.2]]
    # Rectangles carry effective length and width, the L-shape area and perimeter.
    for name in ("Living Room", "Kitchen", "Bedroom"):
        assert by_name[name]["length"] == pytest.approx(room_named(scan, name)["lengthM"], abs=1.5e-4)
        assert by_name[name]["width"] == pytest.approx(room_named(scan, name)["widthM"], abs=1.5e-4)
    assert by_name["Living Room"]["length"] == pytest.approx((6.24 + 6.236) / 2, abs=1.5e-4)
    lounge = by_name["Lounge"]
    assert "length" not in lounge and lounge["area"] == pytest.approx(room_named(scan, "Lounge")["effectiveFloorAreaM2"], abs=1e-3)
    assert lounge["perimeter"] == pytest.approx(room_named(scan, "Lounge")["wallPerimeterM"], abs=1.5e-4)
    # Open plan: the rectangle also states the perimeter of its solid walls only.
    dining = by_name["Open Dining"]
    assert dining["perimeter"] == pytest.approx(room_named(scan, "Open Dining")["wallPerimeterM"], abs=1.5e-4)
    assert dining["perimeter"] < 2 * (dining["length"] + dining["width"]) - 3.5
    assert by_name["Balcony"]["tags"] == ["outdoor"] and by_name["Kitchen 2"]["doors"] == []

    info = spec["x_nexafix_scan"]
    assert info["verified_count"] == scan["summary"]["verifiedCount"] == 7
    assert info["measurement_count"] == scan["summary"]["measurementCount"]
    assert info["joinery_verified_count"] == scan["summary"]["joineryVerifiedCount"]
    assert info["joinery_measurement_count"] == scan["summary"]["joineryMeasurementCount"]
    unverified = {(u["room"], u["item"]) for u in info["unverified_joinery"]}
    assert len(unverified) == info["joinery_measurement_count"] - info["joinery_verified_count"]
    for c in bundle["typed"]:
        if c["quantity"] == "wallLength":
            assert (c["room"], c["label"] + " length") not in unverified
        elif c["quantity"] == "ceilingHeight":
            assert (c["room"], "Ceiling height") not in unverified
        elif c["quantity"] == "openingWidth":
            assert (c["room"], c["label"] + " width") not in unverified
        else:
            assert (c["room"], c["label"]) not in unverified
    assert ("Kitchen", "Door 1 width") in unverified and ("Bedroom", "Window 1 width") in unverified
    assert info["warning"] and f"{len(unverified)} of {info['joinery_measurement_count']} joinery-critical" in info["warning"]
    kitchen = next(r for r in info["rooms"] if r["name"] == "Kitchen")
    assert kitchen["height_verified"] is True and kitchen["area_verified"] is False and kitchen["perimeter_verified"] is False
    assert info["scan_date"] == "2026-10-12"


def test_costing_spec_with_everything_verified_carries_no_warning(scan):
    spec = _load("scan_demo_costing_spec_verified.json")
    info = spec["x_nexafix_scan"]
    assert info["warning"] is None and info["unverified_joinery"] == []
    assert info["joinery_verified_count"] == info["joinery_measurement_count"] > 50
    assert info["verified_count"] == info["measurement_count"]
    # Rectangles whose four walls were all checked are priced from verified sides; the L-shape never is.
    rooms = {r["name"]: r for r in info["rooms"]}
    assert rooms["Kitchen"]["area_verified"] is True and rooms["Kitchen"]["perimeter_verified"] is True
    assert rooms["Lounge"]["area_verified"] is False
    assert all(r["height_verified"] for r in rooms.values())


def test_engine_rooms_equal_what_the_swift_side_computed(scan, tmp_path):
    """from_scan.py --starter, then the engine's own room maths: areas, perimeters and heights within 0.5 %."""
    out = tmp_path / "spec.json"
    r = _run("from_scan.py", FIX / "scan_demo_costing_spec.json", "--starter", "--out", out)
    assert r.returncode == 0, r.stderr
    assert "JOINERY-CRITICAL DIMENSIONS NOT VERIFIED" in r.stderr
    spec = json.loads(out.read_text(encoding="utf-8"))
    assert [s["type"] for s in spec["scope"]] == ["flooring", "painting"]
    swift = {r["name"]: r for r in rooms_of(scan)}
    expected_indoor_walls = expected_indoor_area = expected_dry_area = 0.0
    for entry in spec["rooms"]:
        room = build_room(entry, 2.8, [])
        s = swift[room.name]
        assert room.area == pytest.approx(s["effectiveFloorAreaM2"], rel=0.005), room.name
        assert room.perimeter == pytest.approx(s["wallPerimeterM"], rel=0.005), room.name
        assert room.height == pytest.approx(s["ceilingHeight"]["valueM"], rel=0.005), room.name
        # Doors and windows on solid walls, at their effective sizes.
        solid = {w["id"] for w in s["walls"] if w["kind"] == "solid"}
        openings = sum(o["width"]["valueM"] * o["height"]["valueM"] for o in s["openings"] if o["wallId"] in solid)
        assert room.opening_area == pytest.approx(openings, rel=0.005, abs=1e-6), room.name
        if "outdoor" not in room.tags:
            expected_indoor_area += s["effectiveFloorAreaM2"]
            expected_indoor_walls += s["wallPerimeterM"] * s["ceilingHeight"]["valueM"] - openings
            if not room.wet:
                expected_dry_area += s["effectiveFloorAreaM2"]
    assert expected_dry_area == pytest.approx(scan["summary"]["indoorFloorAreaM2"], rel=0.005), "no wet rooms in this property"

    r = _run("estimate.py", out, "--no-pdf", "--out", tmp_path / "out")
    assert r.returncode == 0, r.stderr + r.stdout
    est = json.loads(next((tmp_path / "out").glob("*/estimate.json")).read_text(encoding="utf-8"))
    assert est["meta"]["ref"] == "NF-2026-1009-01" and est["meta"]["client"] == "Mr. Ahmed Khan"
    flooring, painting = est["scope"]
    assert flooring["qty"] == pytest.approx(expected_dry_area, rel=0.005)
    assert painting["qty"] == pytest.approx(expected_indoor_walls + expected_indoor_area, rel=0.005)
    assert flooring["amount"] > 0 and painting["amount"] > 0
    assert est["totals"]["subtotal"] == pytest.approx(flooring["amount"] + painting["amount"])


def test_a_real_scope_is_priced_from_the_verified_dimensions(scan, tmp_path):
    """Items that name rooms take their quantities from the app's EFFECTIVE sizes, not from the scan."""
    scope = {"scope": [
        {"title": "Living Flooring", "type": "flooring", "material": "spc_plank", "rooms": "Living Room"},
        {"title": "Kitchen Paint", "type": "painting", "rooms": "Kitchen", "surfaces": "walls"},
        {"title": "Living Cove", "type": "cove_lighting", "rooms": ["Living Room"]},
    ]}
    scope_path = tmp_path / "scope.json"
    scope_path.write_text(json.dumps(scope), encoding="utf-8")
    spec_path = tmp_path / "spec.json"
    r = _run("from_scan.py", FIX / "scan_demo_costing_spec.json", "--scope", scope_path, "--check", "--out", spec_path)
    assert r.returncode == 0, r.stderr
    r = _run("estimate.py", spec_path, "--no-pdf", "--out", tmp_path / "out")
    assert r.returncode == 0, r.stderr + r.stdout
    est = json.loads(next((tmp_path / "out").glob("*/estimate.json")).read_text(encoding="utf-8"))
    flooring, paint, cove = est["scope"]

    living = room_named(scan, "Living Room")
    assert living["effectiveFloorAreaM2"] != living["effectiveFloorAreaScannedM2"]
    # Flooring: the effective area (a verified length x a scanned width), nearer to it than to the LiDAR-only figure.
    assert abs(flooring["qty"] - living["effectiveFloorAreaM2"]) < abs(flooring["qty"] - living["effectiveFloorAreaScannedM2"])
    assert flooring["qty"] == pytest.approx(living["effectiveFloorAreaM2"], abs=0.05)
    # Cove lighting runs the room's effective perimeter (both long walls were laser-checked).
    assert abs(cove["qty"] - living["perimeterM"]) < abs(cove["qty"] - living["perimeterScannedM"])
    assert cove["qty"] == pytest.approx(living["perimeterM"], abs=0.05)

    # Painting: walls of every room the engine's selector "Kitchen" picks, perimeter x effective ceiling less openings.
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    expected = expected_scanned = 0.0
    for entry in spec["rooms"]:
        if not build_room(entry, 2.8, []).matches("Kitchen"):
            continue
        s = room_named(scan, entry["name"])
        solid = {w["id"] for w in s["walls"] if w["kind"] == "solid"}
        openings = sum(o["width"]["valueM"] * o["height"]["valueM"] for o in s["openings"] if o["wallId"] in solid)
        expected += s["wallPerimeterM"] * s["ceilingHeight"]["valueM"] - openings
        expected_scanned += s["wallPerimeterScannedM"] * s["ceilingHeight"]["scannedM"] - openings
    assert expected > 0 and expected != pytest.approx(expected_scanned, rel=0.005), "the verified ceiling must make a difference"
    assert paint["qty"] == pytest.approx(expected, rel=0.005)


def test_quotation_pdf_carries_the_line_items_and_the_swift_areas(scan, tmp_path):
    pypdf_module = pytest.importorskip("pypdf")
    pytest.importorskip("reportlab")
    spec_path = tmp_path / "spec.json"
    assert _run("from_scan.py", FIX / "scan_demo_costing_spec.json", "--starter", "--out", spec_path).returncode == 0
    r = _run("estimate.py", spec_path, "--out", tmp_path / "quotes")
    assert r.returncode == 0, r.stderr + r.stdout
    folder = next((tmp_path / "quotes").iterdir())
    quote = folder / "NF-2026-1009-01_Quotation.pdf"
    assert quote.exists() and (folder / "NF-2026-1009-01_Cost_Sheet.pdf").exists()
    text = "\n".join(p.extract_text() for p in pypdf_module.PdfReader(str(quote)).pages)
    flat = " ".join(text.split())
    for needed in ("QUOTATION", "NF-2026-1009-01", "Mr. Ahmed Khan", "Marina Gate 2 - Unit 2304", "SPC Flooring", "Painting",
                   "Total Project Amount"):
        assert needed in flat, needed
    # The quantities on the quotation are the app's effective areas, not a rounding of the scan.
    indoor = scan["summary"]["indoorFloorAreaM2"]
    qty = [float(q) for q in re.findall(r"QUANTITY\s+AMOUNT\s+([\d.]+) m²", text)]
    assert len(qty) == 2, text
    assert qty[0] == pytest.approx(indoor, rel=0.005), "flooring: every indoor room"
    walls = 0.0
    for room in rooms_of(scan):
        if room["kind"] == "balcony":
            continue
        solid = {w["id"] for w in room["walls"] if w["kind"] == "solid"}
        openings = sum(o["width"]["valueM"] * o["height"]["valueM"] for o in room["openings"] if o["wallId"] in solid)
        walls += room["wallPerimeterM"] * room["ceilingHeight"]["valueM"] - openings
    assert qty[1] == pytest.approx(walls + indoor, rel=0.005), "painting: walls and ceilings"
    est = json.loads((folder / "estimate.json").read_text(encoding="utf-8"))
    amounts = [f"{item['amount']:,.0f}" for item in est["scope"]]
    assert all(a in flat for a in amounts), (amounts, flat[:400])
    assert f"{est['totals']['grand_total']:,.0f}" in flat


def test_strict_gate_fails_closed_until_everything_is_verified(tmp_path):
    partial = _run("from_scan.py", FIX / "scan_demo_costing_spec.json", "--starter", "--strict", "--out", tmp_path / "a.json")
    assert partial.returncode == 3, partial.stderr
    assert (tmp_path / "a.json").exists(), "the spec is written, then the gate fails"
    assert "48 of 55 joinery-critical dimensions are LiDAR-scanned only" in partial.stderr
    assert "Kitchen (Level 23): Door 1 width" in partial.stderr
    # The dimensions that WERE typed in are not on the list.
    assert "Kitchen (Level 23): Window 1 width" not in partial.stderr
    assert "Kitchen (Level 23): Ceiling height" not in partial.stderr

    full = _run("from_scan.py", FIX / "scan_demo_costing_spec_verified.json", "--starter", "--strict", "--out", tmp_path / "b.json")
    assert full.returncode == 0, full.stderr
    assert "NOT VERIFIED" not in full.stderr
    r = _run("estimate.py", tmp_path / "b.json", "--no-pdf", "--out", tmp_path / "out")
    assert r.returncode == 0, r.stderr + r.stdout
