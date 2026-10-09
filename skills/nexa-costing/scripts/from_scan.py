#!/usr/bin/env python3
"""Bridge from the NexaFix Scan app into the costing engine.

The iPhone app exports a costing spec (`*_costing-spec.json`): the project block and the scanned
rooms, with an EMPTY scope, because the engine rejects an empty scope and what to quote is the
estimator's call. This script adds the scope and writes a spec `estimate.py` can price.

    python from_scan.py scan_costing_spec.json --starter --out spec.json
    python from_scan.py scan_costing_spec.json --scope scope.yaml --out spec.json
    python from_scan.py scan_costing_spec.json --scope scope.yaml --starter --out spec.json
    python estimate.py spec.json

    --scope FILE   scope items from a .yaml/.yml/.json file. The file is either a list of scope
                   items, or a mapping with `scope:` and optionally `project:` keys (vat,
                   discount_pct, salutation ... merged over the scan's project block).
    --starter      append a rough-budget scope: SPC flooring for the dry rooms and painting
                   (walls and ceilings) for all indoor rooms, so a budget can be priced at once.
                   A starter item is skipped when the scope already has that kind of item.
    --out FILE     write the spec here (default: print it on stdout).
    --check        also dry-run the engine on the result (no PDFs) so unknown rooms, materials
                   or missing sizes show up now; --rates picks a rate book.
    --strict       exit 3 when any joinery-critical dimension is still LiDAR-only.

Rooms come from the scan only; a `rooms:` list in a scope file is ignored with a warning.
Nothing is written when the scope would be empty, or when the rooms or scope do not load
through the engine's own spec parser (`nexa_costing.spec`).

Exit codes: 0 ok, 2 error (bad input, empty scope, invalid spec), 3 --strict and unverified.
Warnings and notes go to stderr, so stdout stays clean JSON when no --out is given.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nexa_costing.spec import build_packages, build_room  # noqa: E402
from nexa_costing.util import SpecError, dim  # noqa: E402

SCAN_BLOCK = "x_nexafix_scan"
MAX_LISTED = 15

# Item types that count as "already has flooring / painting" for the starter scope.
_FLOORING = {"flooring", "floor", "spc", "spc_flooring", "laminate", "parquet", "vinyl", "tiles", "floor_tiles", "tiling"}
_PAINTING = {"painting", "paint"}


# ------------------------------------------------------------------ loading
def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise SpecError(f"cannot read {path}: {exc.strerror or exc}") from exc
    except UnicodeDecodeError as exc:
        raise SpecError(f"{path} is not UTF-8 text") from exc


def _load_structured(path: Path):
    """JSON or YAML, chosen by the file extension (JSON first for anything else)."""
    text = _read_text(path)
    suffix = path.suffix.lower()
    if suffix in (".yaml", ".yml"):
        return _yaml(text, path)
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        if suffix == ".json":
            raise SpecError(f"{path} is not valid JSON ({exc})") from exc
    return _yaml(text, path)


def _yaml(text: str, path: Path):
    try:
        import yaml  # type: ignore
    except ModuleNotFoundError as exc:
        raise SpecError("PyYAML is not installed - `pip install pyyaml` or pass the scope as JSON") from exc
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise SpecError(f"{path} is not valid YAML ({exc})") from exc


def load_scan_spec(path: Path) -> dict:
    data = _load_structured(path)
    if not isinstance(data, dict):
        raise SpecError(f"{path}: a costing spec is a JSON object with `project`, `rooms` and `scope`")
    rooms = data.get("rooms")
    if not isinstance(rooms, list) or not rooms:
        raise SpecError(f"{path}: no rooms - nothing to cost (was the scan saved with at least one room?)")
    if not all(isinstance(r, dict) for r in rooms):
        raise SpecError(f"{path}: every entry of `rooms` must be an object")
    if not isinstance(data.get("project", {}), dict):
        raise SpecError(f"{path}: `project` must be an object")
    if not isinstance(data.get("scope", []), list):
        raise SpecError(f"{path}: `scope` must be a list")
    return data


def load_scope_file(path: Path) -> tuple[list, dict, list]:
    """(scope items, project overrides, warnings) from a scope file."""
    data = _load_structured(path)
    warnings: list[str] = []
    if isinstance(data, list):
        return data, {}, warnings
    if not isinstance(data, dict):
        raise SpecError(f"{path}: expected a list of scope items, or a mapping with a `scope:` list")
    scope = data.get("scope")
    if not isinstance(scope, list):
        raise SpecError(f"{path}: no `scope:` list found")
    project = data.get("project") or {}
    if not isinstance(project, dict):
        raise SpecError(f"{path}: `project:` must be a mapping")
    if data.get("rooms"):
        warnings.append(f"{path}: `rooms:` ignored - rooms come from the scan")
    return scope, project, warnings


# ------------------------------------------------------------------ scope helpers
def _item_types(scope: list) -> set:
    types = set()
    for entry in scope:
        if not isinstance(entry, dict):
            continue
        if entry.get("type"):
            types.add(str(entry["type"]).lower())
        for item in entry.get("items") or []:
            if isinstance(item, dict) and item.get("type"):
                types.add(str(item["type"]).lower())
    return types


def starter_scope(rooms: list, scope: list) -> tuple[list, list]:
    """A rough-budget scope for the rooms, and the reasons for anything left out.

    SPC flooring for dry indoor rooms and painting (walls and ceilings) for all indoor rooms.
    `rooms` are engine Room objects (balconies carry the `outdoor` tag and are excluded by the
    engine's `dry` / `all` selectors).
    """
    items: list = []
    skipped: list[str] = []
    present = _item_types(scope)

    dry = [r for r in rooms if r.matches("dry")]
    if present & _FLOORING:
        skipped.append("starter flooring skipped: the scope already has a flooring item")
    elif not dry:
        skipped.append("starter flooring skipped: no dry indoor room in the scan")
    else:
        items.append({"title": "SPC Flooring", "subtitle": "Supply & installation to all dry areas",
                      "type": "flooring", "material": "spc_plank", "rooms": "dry"})

    indoor = [r for r in rooms if r.matches("all")]
    if present & _PAINTING:
        skipped.append("starter painting skipped: the scope already has a painting item")
    elif not indoor:
        skipped.append("starter painting skipped: no indoor room in the scan")
    else:
        items.append({"title": "Painting", "subtitle": "Walls & ceilings", "type": "painting",
                      "rooms": "all", "surfaces": "both"})
    return items, skipped


# ------------------------------------------------------------------ validation
def validate(spec: dict) -> tuple[list, list]:
    """Load the spec the way the engine does. Returns (engine Room objects, notes).

    Raises SpecError for rooms the engine cannot parse, malformed scope entries, and scope items
    that select a room the scan does not have.
    """
    notes: list[str] = []
    project = spec.get("project") or {}
    height = dim(project.get("ceiling_height"), "ceiling height", notes)
    if height is None:
        height = 2.8
    rooms = [build_room(r, height, notes) for r in spec.get("rooms") or []]
    packages = build_packages(spec.get("scope") or [])

    names = ", ".join(r.name for r in rooms) or "no rooms defined"
    for pkg in packages:
        for item in pkg.items:
            if not isinstance(item, dict):
                raise SpecError(f"scope item '{pkg.title or item}' must be a mapping")
            for sel in (item.get("rooms"), item.get("room"), pkg.rooms, pkg.room):
                if sel is None:
                    continue
                for s in sel if isinstance(sel, (list, tuple)) else [sel]:
                    if not any(r.matches(str(s)) for r in rooms):
                        raise SpecError(f"scope '{pkg.title or item.get('type')}': no room matches '{s}'. Rooms: {names}")
                break   # the engine uses the first selector present
    return rooms, notes


def engine_dry_run(spec: dict, rates_path: str | None) -> dict:
    """Run the real engine without PDFs; raises SpecError exactly as estimate.py would."""
    from nexa_costing.engine import run_estimate
    from nexa_costing.ratebook import Ratebook

    rates = Ratebook.load(rates_path)
    return run_estimate(json.loads(json.dumps(spec)), rates, base_dir=Path.cwd())


# ------------------------------------------------------------------ warnings
def unverified_block(spec: dict) -> list[str]:
    """Lines to show when the scan lists joinery-critical dimensions nobody checked on site."""
    scan = spec.get(SCAN_BLOCK)
    if not isinstance(scan, dict):
        return [f"NOTE: no `{SCAN_BLOCK}` block - this spec did not come from the NexaFix Scan app, "
                "so there is no information about which dimensions were verified."]
    unverified = scan.get("unverified_joinery") or []
    if not unverified:
        return []
    project = (spec.get("project") or {}).get("name") or "this property"
    when = f" (scanned {scan['scan_date']})" if scan.get("scan_date") else ""
    total = scan.get("joinery_measurement_count")
    lines = [
        "=" * 72,
        "WARNING: JOINERY-CRITICAL DIMENSIONS NOT VERIFIED ON SITE",
        "=" * 72,
        f"{project}{when}: {len(unverified)}"
        + (f" of {total}" if total else "")
        + " joinery-critical dimensions are LiDAR-scanned only.",
    ]
    if scan.get("warning"):
        lines.append(str(scan["warning"]))
    lines.append("This quote is a BUDGET until they are checked with a laser measure. Unverified:")
    for u in unverified[:MAX_LISTED]:
        scanned, tol = u.get("scanned_m"), u.get("typical_tolerance_m")
        detail = ""
        if isinstance(scanned, (int, float)):
            detail = f" - {scanned * 1000:.0f} mm"
            if isinstance(tol, (int, float)):
                detail += f" (typically +/-{tol * 1000:.0f} mm)"
        lines.append(f"  - {u.get('room', '?')}: {u.get('item', '?')}{detail}")
    if len(unverified) > MAX_LISTED:
        lines.append(f"  ... and {len(unverified) - MAX_LISTED} more (see {SCAN_BLOCK}.unverified_joinery)")
    lines.append("=" * 72)
    return lines


# ------------------------------------------------------------------ output
def write_json_atomic(path: Path, spec: dict) -> None:
    text = json.dumps(spec, indent=2, ensure_ascii=False) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def build_spec(scan_path: Path, scope_path: Path | None, starter: bool) -> tuple[dict, list, list]:
    """The merged spec, plus (warnings, info lines). Raises SpecError on anything unusable."""
    spec = load_scan_spec(scan_path)
    warnings: list[str] = []
    info: list[str] = []
    scope: list = list(spec.get("scope") or [])
    if scope:
        warnings.append(f"{scan_path} already has {len(scope)} scope item(s); new items are appended")

    if scope_path is not None:
        items, project, scope_warnings = load_scope_file(scope_path)
        warnings += scope_warnings
        scope += items
        if project:
            spec["project"] = {**(spec.get("project") or {}), **project}
            info.append(f"project overrides from {scope_path.name}: {', '.join(sorted(project))}")
        info.append(f"{len(items)} scope item(s) from {scope_path.name}")

    # Parse the rooms now: the starter scope needs them, and a bad room is an error either way.
    rooms, notes = validate({**spec, "scope": []})
    warnings += [f"engine note: {n}" for n in notes]

    if starter:
        items, skipped = starter_scope(rooms, scope)
        scope += items
        info += [f"starter scope: {i['title']}" for i in items]
        warnings += skipped
        if items:
            warnings.append("the starter scope is a rough-budget placeholder - replace it with the real scope before quoting")

    if not scope:
        why = [w for w in warnings if w.startswith("starter ")]
        hint = ("; ".join(why) + ". Pass --scope FILE with the items to quote." if why
                else "Pass --scope FILE and/or --starter.")
        raise SpecError(f"refusing to write a spec with an empty scope (the costing engine rejects it). {hint}")
    spec["scope"] = scope
    validate(spec)   # scope shape and room selectors
    return spec, warnings, info


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Add a scope to a NexaFix Scan costing spec so the engine can price it")
    ap.add_argument("scan", help="costing spec exported by the NexaFix Scan app (.json)")
    ap.add_argument("--scope", help="scope file (.yaml / .yml / .json)")
    ap.add_argument("--starter", action="store_true", help="append a rough-budget scope (SPC flooring + painting)")
    ap.add_argument("--out", help="write the spec here (default: stdout)")
    ap.add_argument("--check", action="store_true", help="dry-run the engine on the result (no PDFs)")
    ap.add_argument("--rates", help="rate book for --check (default: the skill's rates.toml, or $NEXA_RATES)")
    ap.add_argument("--strict", action="store_true", help="exit 3 if any joinery-critical dimension is unverified")
    args = ap.parse_args(argv)

    try:
        spec, warnings, info = build_spec(Path(args.scan), Path(args.scope) if args.scope else None, args.starter)
        if args.check:
            engine_dry_run(spec, args.rates)
            info.append("engine dry run: ok")
    except SpecError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    for line in info:
        print(f"- {line}", file=sys.stderr)
    for w in warnings:
        print(f"NOTE: {w}", file=sys.stderr)
    block = unverified_block(spec)
    for line in block:
        print(line, file=sys.stderr)

    if args.out:
        try:
            write_json_atomic(Path(args.out), spec)
        except OSError as exc:
            print(f"ERROR: cannot write {args.out}: {exc.strerror or exc}", file=sys.stderr)
            return 2
        print(f"Wrote {args.out}: {len(spec['rooms'])} rooms, {len(spec['scope'])} scope item(s). "
              f"Next: python estimate.py {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(json.dumps(spec, indent=2, ensure_ascii=False) + "\n")

    scan = spec.get(SCAN_BLOCK)
    if args.strict and isinstance(scan, dict) and scan.get("unverified_joinery"):
        print("ERROR: --strict: joinery-critical dimensions are not verified", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
