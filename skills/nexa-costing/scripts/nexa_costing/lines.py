"""Cost lines and the per-item builder that prices them from the rate book."""
from __future__ import annotations

from dataclasses import dataclass, field

from .ratebook import Ratebook
from .util import num, r2


@dataclass
class Line:
    kind: str                 # material | labour | other
    ref: str                  # rate-book key (material / trade) or free text id
    description: str
    qty: float
    unit: str
    unit_cost: float
    unit_sell: float
    calc: str = ""
    placeholder: bool = False
    category: str = ""
    purchase: bool = True     # appears on the shopping list (materials only)

    @property
    def cost(self) -> float:
        return self.qty * self.unit_cost

    @property
    def sell(self) -> float:
        return self.qty * self.unit_sell

    def to_dict(self) -> dict:
        return {
            "kind": self.kind, "ref": self.ref, "description": self.description,
            "qty": round(self.qty, 3), "unit": self.unit,
            "unit_cost": r2(self.unit_cost), "cost": r2(self.cost),
            "unit_sell": r2(self.unit_sell), "sell": r2(self.sell),
            "calc": self.calc, "placeholder": self.placeholder,
        }


@dataclass
class ItemResult:
    """Output of one calculator call."""
    lines: list[Line] = field(default_factory=list)
    measure_qty: float = 1.0          # the quantity the client sees (m², lm, pts, units)
    measure_unit: str = "Unit"
    includes: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    title: str = ""                   # default scope title if the spec gives none
    subtitle: str = ""
    description: str = ""
    summary_line: str = ""
    sell_override: float | None = None   # fixed selling price (sell_rate x measure, or lump sum)
    floor_area: float = 0.0              # for site protection / cleaning allowances
    boards: dict = field(default_factory=dict)  # ref -> m² of joinery board used


class Builder:
    """Collects priced lines for one item.

    `labour_in_sell` — set when a material's resale price already covers
    installation (e.g. SPC sold per plank "supply & install"): labour is
    still costed but adds nothing to the selling price.
    """

    def __init__(self, rates: Ratebook, item: dict):
        self.rates = rates
        self.item = item
        self.res = ItemResult()
        self.labour_in_sell = False
        self.markup_override = item.get("markup_pct")

    # ------------------------------------------------------------ materials
    def material(self, key: str, qty: float, calc: str = "", description: str | None = None,
                 purchase: bool = True) -> Line | None:
        if qty is None or qty <= 1e-9:
            return None
        mat = self.rates.material(key)
        unit_cost = float(mat.get("cost", 0))
        if self.markup_override is not None and not mat.get("sell"):
            unit_sell = unit_cost * (1 + float(self.markup_override) / 100)
        else:
            unit_sell = self.rates.unit_sell(mat)
        placeholder = self.rates.is_placeholder(mat)
        if placeholder:
            self.rates.used_placeholders.add(f"materials.{key}")
        line = Line("material", key, description or mat.get("name", key), float(qty),
                    mat.get("unit", "pc"), unit_cost, unit_sell, calc, placeholder,
                    mat.get("category", ""), purchase)
        self.res.lines.append(line)
        if mat.get("category") == "boards":
            ua = self.rates.unit_area(mat) or 0.0
            yield_pct = float(mat.get("yield_pct", 100)) / 100.0
            # m² of board actually cut into parts (excludes offcut loss)
            self.res.boards[key] = self.res.boards.get(key, 0.0) + qty * ua * yield_pct
        return line

    # ------------------------------------------------------------ labour
    def labour(self, trade: str, hours: float, calc: str = "", in_sell: bool | None = None) -> Line | None:
        if hours is None or hours <= 1e-9:
            return None
        t = self.rates.trade(trade)
        uplift = self.rates.price("site_labour_uplift_pct", 0) if t.get("where") in ("site", "install") else 0
        if uplift:
            hours *= 1 + uplift / 100
            calc += f" +{uplift:g}% site access allowance"
        cost = float(t.get("cost_per_hour", 0))
        sell = float(t.get("sell_per_hour", cost))
        charge = not self.labour_in_sell if in_sell is None else in_sell
        if self.rates.is_placeholder(t):
            self.rates.used_placeholders.add(f"trades.{trade}")
        line = Line("labour", trade, t.get("label", trade.title()), float(hours), "h",
                    cost, sell if charge else 0.0,
                    calc + ("" if charge else " (included in material resale price)"),
                    self.rates.is_placeholder(t), "labour", False)
        self.res.lines.append(line)
        return line

    # ------------------------------------------------------------ other
    def other(self, description: str, cost: float, sell: float | None = None, calc: str = "",
              qty: float = 1.0, unit: str = "item", ref: str = "other") -> Line | None:
        if qty <= 1e-9 or (cost <= 0 and not sell):
            return None
        if sell is None:
            mk = self.markup_override if self.markup_override is not None else \
                self.rates.price("default_material_markup_pct", 40)
            sell = cost * (1 + float(mk) / 100)
        line = Line("other", ref, description, float(qty), unit, float(cost), float(sell), calc,
                    False, "other", False)
        self.res.lines.append(line)
        return line

    # ------------------------------------------------------------ helpers
    def note(self, msg: str):
        if msg not in self.res.notes:
            self.res.notes.append(msg)

    def warn(self, msg: str):
        if msg not in self.res.warnings:
            self.res.warnings.append(msg)

    def include(self, text: str):
        if text and text not in self.res.includes:
            self.res.includes.append(text)

    def labour_hours(self) -> dict:
        out: dict[str, float] = {}
        for ln in self.res.lines:
            if ln.kind == "labour":
                out[ln.ref] = out.get(ln.ref, 0.0) + ln.qty
        return out


def fmt_calc(*parts) -> str:
    return " ".join(num(p) if isinstance(p, float) else str(p) for p in parts)
