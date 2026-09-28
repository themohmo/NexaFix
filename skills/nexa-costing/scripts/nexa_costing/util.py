"""Small shared helpers: dimension parsing, rounding, text formatting."""
from __future__ import annotations

import math
import re

_DIM_RE = re.compile(
    r"^\s*(?P<num>-?\d+(?:\.\d+)?)\s*(?P<unit>mm|cm|m|ft|feet|foot|'|in|inch|inches|\")?\s*$",
    re.IGNORECASE,
)
_UNIT_TO_M = {
    None: 1.0, "m": 1.0, "cm": 0.01, "mm": 0.001,
    "ft": 0.3048, "feet": 0.3048, "foot": 0.3048, "'": 0.3048,
    "in": 0.0254, "inch": 0.0254, "inches": 0.0254, '"': 0.0254,
}


class SpecError(ValueError):
    """Raised for invalid project specs or rate-book lookups (message is user-facing)."""


def dim(value, label: str = "dimension", notes: list | None = None, mm_above: float = 20) -> float | None:
    """Parse a length into metres.

    Plain numbers are metres, except numbers above `mm_above` which are taken
    as millimetres (nobody fits a 2400 m wardrobe). Long runs (cove, LED,
    partitions, perimeters) pass a higher threshold. Strings may carry a
    unit: "2400mm", "240 cm", "2.4m", "8ft".
    """
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise SpecError(f"{label}: expected a length, got {value!r}")
    if isinstance(value, (int, float)):
        v = float(value)
        if v > mm_above:
            if notes is not None:
                notes.append(f"{label} {value} read as millimetres ({v / 1000:g} m)")
            return v / 1000.0
        return v
    m = _DIM_RE.match(str(value))
    if not m:
        raise SpecError(f"{label}: can't read length {value!r} (use metres, or add mm/cm/m/ft)")
    num = float(m.group("num"))
    unit = m.group("unit")
    unit = unit.lower() if unit else None
    if unit is None and num > mm_above:
        if notes is not None:
            notes.append(f"{label} {value} read as millimetres ({num / 1000:g} m)")
        return num / 1000.0
    return num * _UNIT_TO_M[unit]


def area(value, label: str = "area") -> float | None:
    """Parse an area in m² ("12.5", "12.5 m2", "135 sqft")."""
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    s = str(value).strip().lower().replace("²", "2")
    m = re.match(r"^(-?\d+(?:\.\d+)?)\s*(m2|sqm|sq\.?\s*m|sqft|sq\.?\s*ft|ft2)?$", s)
    if not m:
        raise SpecError(f"{label}: can't read area {value!r} (use m², e.g. 12.5 or '135 sqft')")
    num = float(m.group(1))
    unit = (m.group(2) or "m2").replace(" ", "").replace(".", "")
    if unit in ("sqft", "ft2"):
        return num * 0.09290304
    return num


def ceil_to(value: float, step: float) -> float:
    """Round up to the next multiple of step (step <= 0 returns value)."""
    if step <= 0:
        return value
    return math.ceil(round(value / step, 9)) * step


def ceil_int(value: float) -> int:
    """math.ceil that ignores float noise (3.0000000001 -> 3)."""
    return int(math.ceil(round(value, 6)))


def r2(v: float) -> float:
    return round(float(v) + 0.0, 2)


def num(v: float, nd: int = 2) -> str:
    """Compact number for calc strings: 3.0 -> '3', 3.456 -> '3.46'."""
    s = f"{v:.{nd}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def number_words(n: int) -> str:
    words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
             "nine", "ten", "eleven", "twelve"]
    return words[n] if 0 <= n < len(words) else str(n)


def count_phrase(n: int, singular: str, plural: str | None = None) -> str:
    """'two (2) units' — the style used in NexaFix quotations."""
    plural = plural or singular + "s"
    return f"{number_words(n)} ({n}) {singular if n == 1 else plural}"


def as_bool(v, default: bool = False) -> bool:
    if v is None:
        return default
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v != 0
    return str(v).strip().lower() in ("1", "true", "yes", "y", "on")


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")
