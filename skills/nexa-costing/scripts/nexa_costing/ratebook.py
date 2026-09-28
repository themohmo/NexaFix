"""The NexaFix rate book: one TOML file holding every price, productivity and default.

The owner enters prices once (or tells Claude to update them) and every
estimate reads from here. Edits are made line-by-line so comments and
layout in rates.toml survive.
"""
from __future__ import annotations

import difflib
import os
import re
from pathlib import Path

try:  # Python 3.11+
    import tomllib as _toml
except ModuleNotFoundError:  # pragma: no cover - older sandboxes
    try:
        import tomli as _toml  # type: ignore
    except ModuleNotFoundError as exc:  # pragma: no cover
        raise SystemExit("Python 3.11+ (tomllib) or `pip install tomli` is required") from exc

from .util import SpecError

SKILL_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RATES = SKILL_ROOT / "rates.toml"

# Units measured continuously (bought by length/area/weight/volume). Everything
# else (plank, pc, sheet, box, roll...) is bought in whole units.
CONTINUOUS_UNITS = {"m", "lm", "m2", "m²", "kg", "l", "ltr", "litre", "hr", "h"}
CONFIRMED_STATUSES = {"owner", "confirmed", "supplier", "quoted"}


def rates_path(explicit: str | os.PathLike | None = None) -> Path:
    """Explicit path > $NEXA_RATES > rates.toml in the skill folder."""
    if explicit:
        return Path(explicit)
    env = os.environ.get("NEXA_RATES")
    if env:
        return Path(env)
    return DEFAULT_RATES


class Ratebook:
    def __init__(self, data: dict, path: Path | None = None):
        self.data = data
        self.path = path
        self.company: dict = data.get("company", {})
        self.brand: dict = data.get("brand", {})
        self.pricing: dict = data.get("pricing", {})
        self.schedule: dict = data.get("schedule", {})
        self.prelims: dict = data.get("preliminaries", {})
        self.materials: dict = data.get("materials", {})
        self.trades: dict = data.get("trades", {})
        self.assemblies: dict = data.get("assemblies", {})
        self.typologies: dict = data.get("typologies", {})
        self.terms: dict = data.get("terms", {})
        self.used_placeholders: set[str] = set()

    # ---------------------------------------------------------------- loading
    @classmethod
    def load(cls, path: str | os.PathLike | None = None) -> "Ratebook":
        p = rates_path(path)
        if not p.exists():
            raise SpecError(f"Rate book not found at {p}")
        with open(p, "rb") as fh:
            try:
                data = _toml.load(fh)
            except Exception as exc:  # tomllib.TOMLDecodeError
                raise SpecError(f"rates.toml has a syntax error: {exc}") from exc
        return cls(data, p)

    # ---------------------------------------------------------------- lookups
    def material(self, key: str) -> dict:
        m = self.materials.get(key)
        if m is None:
            close = difflib.get_close_matches(key, self.materials.keys(), n=4, cutoff=0.4)
            hint = f" Did you mean: {', '.join(close)}?" if close else ""
            raise SpecError(f"Unknown material '{key}' — add it to rates.toml under [materials.{key}].{hint}")
        out = dict(m)
        out["key"] = key
        return out

    def has_material(self, key: str | None) -> bool:
        return bool(key) and key in self.materials

    def trade(self, key: str) -> dict:
        t = self.trades.get(key)
        if t is None:
            close = difflib.get_close_matches(key, self.trades.keys(), n=4, cutoff=0.4)
            hint = f" Did you mean: {', '.join(close)}?" if close else ""
            raise SpecError(f"Unknown trade '{key}' — add it to rates.toml under [trades.{key}].{hint}")
        out = dict(t)
        out["key"] = key
        return out

    def assembly(self, name: str) -> dict:
        return dict(self.assemblies.get(name, {}))

    def price(self, key: str, default: float = 0.0) -> float:
        return float(self.pricing.get(key, default))

    # ---------------------------------------------------------------- material maths
    @staticmethod
    def unit_area(mat: dict) -> float | None:
        """m² covered by one unit (plank, tile, sheet, box...)."""
        if mat.get("coverage_m2"):
            return float(mat["coverage_m2"])
        if mat.get("length_mm") and mat.get("width_mm"):
            return float(mat["length_mm"]) * float(mat["width_mm"]) / 1e6
        return None

    @staticmethod
    def is_continuous(mat: dict) -> bool:
        return str(mat.get("unit", "pc")).lower() in CONTINUOUS_UNITS

    def is_placeholder(self, mat: dict) -> bool:
        return str(mat.get("status", "placeholder")).lower() not in CONFIRMED_STATUSES

    def markup_pct(self, mat: dict) -> float:
        if mat.get("markup_pct") is not None:
            return float(mat["markup_pct"])
        cat = mat.get("category", "")
        cat_markups = self.pricing.get("category_markup_pct", {})
        if cat in cat_markups:
            return float(cat_markups[cat])
        return self.price("default_material_markup_pct", 40)

    def unit_sell(self, mat: dict) -> float:
        """Resale price per unit: explicit `sell`, otherwise cost + markup."""
        if mat.get("sell") not in (None, 0, 0.0):
            return float(mat["sell"])
        return float(mat.get("cost", 0)) * (1 + self.markup_pct(mat) / 100.0)

    def placeholder_materials(self) -> list[str]:
        return sorted(k for k, m in self.materials.items() if self.is_placeholder(m))

    def placeholder_trades(self) -> list[str]:
        return sorted(k for k, t in self.trades.items() if self.is_placeholder(t))


# ============================================================== line editor
_HEADER_RE = re.compile(r"^\s*\[\s*([^\[\]]+?)\s*\]\s*(#.*)?$")


def _fmt_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(_fmt_value(v) for v in value) + "]"
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def coerce(raw: str):
    """Turn CLI text into the right TOML type ("35" -> 35.0, "true" -> True)."""
    s = raw.strip()
    if s.lower() in ("true", "false"):
        return s.lower() == "true"
    try:
        if re.fullmatch(r"-?\d+", s):
            return int(s)
        return float(s)
    except ValueError:
        return s


def _split_value_comment(rest: str) -> tuple[str, str]:
    """Split 'value   # comment' respecting quotes."""
    in_str = False
    esc = False
    for i, ch in enumerate(rest):
        if esc:
            esc = False
            continue
        if ch == "\\":
            esc = True
            continue
        if ch == '"':
            in_str = not in_str
        elif ch == "#" and not in_str:
            return rest[:i], rest[i:]
    return rest, ""


def set_values(path: str | os.PathLike, section: str, values: dict) -> list[str]:
    """Set keys inside [section] of a TOML file, keeping comments and layout.

    Creates the section (appended after its sibling group) if missing.
    Returns a list of human-readable changes. The file is re-parsed after
    editing and restored if the result is invalid.
    """
    p = Path(path)
    original = p.read_text(encoding="utf-8")
    lines = original.splitlines()
    changes: list[str] = []

    # locate section
    start = None
    for i, line in enumerate(lines):
        m = _HEADER_RE.match(line)
        if m and m.group(1).strip() == section:
            start = i
            break
    if start is None:
        # insert after the last block whose header shares the parent prefix
        parent = section.rsplit(".", 1)[0] if "." in section else section
        insert_at = len(lines)
        last_sibling = None
        for i, line in enumerate(lines):
            m = _HEADER_RE.match(line)
            if m and (m.group(1).strip() == parent or m.group(1).strip().startswith(parent + ".")):
                last_sibling = i
        if last_sibling is not None:
            insert_at = len(lines)
            for j in range(last_sibling + 1, len(lines)):
                if _HEADER_RE.match(lines[j]):
                    insert_at = j
                    break
        block = [""] if insert_at > 0 and lines[insert_at - 1].strip() else []
        block.append(f"[{section}]")
        for k, v in values.items():
            block.append(f"{k} = {_fmt_value(v)}")
            changes.append(f"[{section}] {k} = {_fmt_value(v)} (new)")
        if insert_at < len(lines):
            block.append("")
        lines[insert_at:insert_at] = block
    else:
        end = len(lines)
        for j in range(start + 1, len(lines)):
            if _HEADER_RE.match(lines[j]):
                end = j
                break
        for k, v in values.items():
            key_re = re.compile(rf"^(\s*){re.escape(k)}(\s*)=(\s*)(.*)$")
            found = False
            for j in range(start + 1, end):
                m = key_re.match(lines[j])
                if m:
                    old_val, comment = _split_value_comment(m.group(4))
                    pad = " " * max(1, len(old_val) - len(old_val.rstrip())) if comment else ""
                    new_val = _fmt_value(v)
                    lines[j] = f"{m.group(1)}{k}{m.group(2)}={m.group(3)}{new_val}{pad}{comment}".rstrip()
                    changes.append(f"[{section}] {k}: {old_val.strip()} -> {new_val}")
                    found = True
                    break
            if not found:
                # insert after the last key line in the section
                last = start
                for j in range(start + 1, end):
                    if lines[j].strip() and not lines[j].lstrip().startswith("#"):
                        last = j
                lines.insert(last + 1, f"{k} = {_fmt_value(v)}")
                end += 1
                changes.append(f"[{section}] {k} = {_fmt_value(v)} (added)")

    new_text = "\n".join(lines) + "\n"
    try:
        _toml.loads(new_text)
    except Exception as exc:
        raise SpecError(f"Edit would break rates.toml ({exc}); nothing was changed") from exc
    p.write_text(new_text, encoding="utf-8")
    return changes


def set_dotted(path: str | os.PathLike, dotted: str, value, mark_owner: bool = True) -> list[str]:
    """set_dotted(rates, "materials.spc_plank.cost", 38).

    Setting a cost/sell/rate on a material or trade marks it status="owner"
    so it stops being flagged as a placeholder.
    """
    if "." not in dotted:
        raise SpecError("Use section.key, e.g. materials.spc_plank.cost")
    section, key = dotted.rsplit(".", 1)
    values = {key: value}
    price_keys = {"cost", "sell", "cost_per_hour", "sell_per_hour", "markup_pct"}
    if mark_owner and key in price_keys and section.split(".")[0] in ("materials", "trades"):
        values["status"] = "owner"
    return set_values(path, section, values)
