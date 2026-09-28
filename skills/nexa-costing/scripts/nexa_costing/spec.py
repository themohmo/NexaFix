"""Project spec loading: project info, rooms (with geometry) and scope packages."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from .ratebook import Ratebook
from .util import SpecError, area as parse_area, dim, slug

DOOR_W, DOOR_H = 0.9, 2.1


@dataclass
class Room:
    name: str
    area: float
    perimeter: float
    height: float
    wet: bool = False
    doors: list = field(default_factory=list)     # list of (w, h)
    windows: list = field(default_factory=list)   # list of (w, h)
    tags: set = field(default_factory=set)
    estimated: bool = False                        # geometry guessed from a typology
    length: float | None = None
    width: float | None = None

    @property
    def opening_area(self) -> float:
        return sum(w * h for w, h in self.doors) + sum(w * h for w, h in self.windows)

    @property
    def door_width_total(self) -> float:
        return sum(w for w, _ in self.doors)

    @property
    def wall_area(self) -> float:
        return max(0.0, self.perimeter * self.height - self.opening_area)

    def matches(self, selector: str) -> bool:
        s = selector.strip().lower()
        indoor = "outdoor" not in self.tags
        if s in ("everything", "all_including_outdoor"):
            return True
        if s in ("all", "*", "whole", "whole unit", "apartment", "indoor", "all rooms"):
            return indoor
        if s in ("dry", "dry areas", "dry area"):
            return not self.wet and indoor
        if s in ("wet", "wet areas"):
            return self.wet
        if s in self.tags:
            return True
        if s in ("bedrooms", "bedroom") and ("bedroom" in self.tags or "bed" in self.name.lower()):
            return True
        return slug(s) == slug(self.name)


def _openings(value, default_count: int, dflt_w: float, dflt_h: float, label: str, notes: list) -> list:
    if value is None:
        return [(dflt_w, dflt_h)] * default_count
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return [(dflt_w, dflt_h)] * int(value)
    out = []
    for o in value:
        if isinstance(o, dict):
            out.append((dim(o.get("width", dflt_w), label, notes), dim(o.get("height", dflt_h), label, notes)))
        elif isinstance(o, (list, tuple)) and len(o) == 2:
            out.append((dim(o[0], label, notes), dim(o[1], label, notes)))
        else:
            out.append((dim(o, label, notes), dflt_h))
    return out


def _guess_tags(name: str) -> set:
    n = name.lower()
    tags = set()
    for key, tag in (("bed", "bedroom"), ("master", "bedroom"), ("living", "living"), ("majlis", "living"),
                     ("dining", "living"), ("kitchen", "kitchen"), ("bath", "bathroom"), ("toilet", "bathroom"),
                     ("wc", "bathroom"), ("powder", "bathroom"), ("ensuite", "bathroom"), ("laundry", "utility"),
                     ("maid", "utility"), ("store", "utility"), ("corridor", "circulation"), ("hall", "circulation"),
                     ("entr", "circulation"), ("foyer", "circulation"), ("lobby", "circulation"),
                     ("balcony", "outdoor"), ("terrace", "outdoor")):
        if key in n:
            tags.add(tag)
    return tags


def build_room(r: dict, default_height: float, notes: list) -> Room:
    name = r.get("name") or "Room"
    L = dim(r.get("length"), f"{name} length", notes)
    W = dim(r.get("width"), f"{name} width", notes)
    A = parse_area(r.get("area"), f"{name} area")
    if A is None and L and W:
        A = L * W
    if A is None:
        raise SpecError(f"Room '{name}' needs length + width, or area")
    P = dim(r.get("perimeter"), f"{name} perimeter", notes)
    if P is None:
        if L and W:
            P = 2 * (L + W)
        else:
            a = math.sqrt(A * 1.3)
            P = 2 * (a + A / a)
            notes.append(f"{name}: perimeter estimated at {P:.1f} m from area (1.3:1 room shape)")
    H = dim(r.get("height"), f"{name} height", notes) or default_height
    tags = set(t.lower() for t in r.get("tags", [])) | _guess_tags(name)
    wet = r.get("wet")
    if wet is None:
        wet = bool(tags & {"bathroom"}) or "wet" in tags
    doors = _openings(r.get("doors"), 0 if "outdoor" in tags else 1, DOOR_W, DOOR_H, f"{name} door", notes)
    windows = _openings(r.get("windows"), 0, 1.5, 1.5, f"{name} window", notes)
    return Room(name=name, area=A, perimeter=P, height=H, wet=bool(wet), doors=doors, windows=windows,
                tags=tags, estimated=bool(r.get("estimated")), length=L, width=W)


def rooms_from_typology(rates: Ratebook, typology: str, total_area: float | None, notes: list) -> list[dict]:
    key = slug(typology)
    t = rates.typologies.get(key)
    if t is None:
        raise SpecError(f"Unknown typology '{typology}'. Known: {', '.join(rates.typologies)}")
    rooms = [dict(r) for r in t.get("rooms", [])]
    base = sum(r["area"] for r in rooms)
    scale = (total_area / base) if total_area else 1.0
    for r in rooms:
        r["area"] = round(r["area"] * scale, 2)
        r["estimated"] = True
    notes.append(
        f"Room sizes estimated from the typical Dubai {t.get('label', typology)} layout"
        + (f" scaled to {total_area:g} m²" if total_area else f" ({base:g} m²)")
        + " — replace with floor-plan dimensions for a firm quote")
    return rooms


@dataclass
class Package:
    """One numbered scope item on the quotation (may hold several components)."""
    title: str
    items: list
    subtitle: str = ""
    description: str = ""
    includes: list | None = None
    summary_line: str = ""
    room: str | None = None
    rooms: object = None
    qty: float | None = None
    unit: str | None = None
    image: str | None = None
    sell: float | None = None          # lump-sum override
    markup_pct: float | None = None
    tile: str | None = None            # short cover tile label
    raw: dict = field(default_factory=dict)


_PKG_KEYS = {"title", "subtitle", "description", "includes", "summary_line", "items", "image",
             "qty", "unit", "price", "tile", "package"}


def build_packages(scope: list) -> list[Package]:
    pkgs = []
    for i, s in enumerate(scope):
        if not isinstance(s, dict):
            raise SpecError(f"scope[{i}] must be a mapping")
        if "items" in s:
            items = s["items"]
        elif "type" in s:  # shorthand: a single item scope entry
            items = [{k: v for k, v in s.items() if k not in _PKG_KEYS - {"qty"} or k == "type"}]
            # qty on a single-item shorthand belongs to the item (e.g. 4 sockets)
            if "qty" in s:
                items[0]["qty"] = s["qty"]
        else:
            raise SpecError(f"scope[{i}] needs either `type` (single item) or `items` (package)")
        pkgs.append(Package(
            title=s.get("title", ""), items=items, subtitle=s.get("subtitle", ""),
            description=s.get("description", ""), includes=s.get("includes"),
            summary_line=s.get("summary_line", ""), room=s.get("room"), rooms=s.get("rooms"),
            qty=s.get("qty") if "items" in s else None, unit=s.get("unit") if "items" in s else None,
            image=s.get("image"), sell=s.get("price") if "items" in s else None,
            markup_pct=s.get("markup_pct"), tile=s.get("tile"), raw=s))
    return pkgs


def load_spec_file(path: str | Path) -> dict:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if p.suffix.lower() in (".yaml", ".yml"):
        try:
            import yaml  # type: ignore
        except ModuleNotFoundError as exc:
            raise SpecError("PyYAML is not installed — `pip install pyyaml` or pass the spec as JSON") from exc
        data = yaml.safe_load(text)
    else:
        data = json.loads(text)
    if not isinstance(data, dict):
        raise SpecError("Project spec must be a mapping with `project`, `rooms` and `scope`")
    return data
