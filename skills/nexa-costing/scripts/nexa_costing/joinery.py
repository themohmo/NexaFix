"""Panel model for bespoke joinery: turns a cabinet description into board m²,
edge-banding metres and hardware counts.

Every cabinet is modelled as a box: two sides, top, bottom, optional
vertical dividers, shelves, back, plinth, fronts (doors / drawer fronts)
and drawer boxes. That is how a workshop cutting list is built, so the
board usage tracks what the carpenter actually cuts.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field


@dataclass
class Part:
    name: str
    length: float      # m
    width: float       # m
    qty: int
    board: str         # role: carcass | front | back | drawer | shelf | plinth
    thin_edges: float = 0.0   # banded length per piece, carcass edge tape (m)
    thick_edges: float = 0.0  # banded length per piece, front edge tape (m)

    @property
    def area(self) -> float:
        return self.length * self.width * self.qty


@dataclass
class CabinetModel:
    parts: list[Part] = field(default_factory=list)
    doors: int = 0
    door_height: float = 0.0
    drawers: int = 0
    flaps: int = 0
    shelves: int = 0
    sections: int = 1
    hanging_m: float = 0.0
    front_area: float = 0.0
    sliding: bool = False
    glass_area: float = 0.0

    def area_by_role(self) -> dict:
        out: dict[str, float] = {}
        for p in self.parts:
            out[p.board] = out.get(p.board, 0.0) + p.area
        return out

    @property
    def thin_edge_m(self) -> float:
        return sum(p.thin_edges * p.qty for p in self.parts)

    @property
    def thick_edge_m(self) -> float:
        return sum(p.thick_edges * p.qty for p in self.parts)

    def cutting_list(self) -> list[str]:
        return [f"{p.qty} x {p.name} {p.length * 1000:.0f} x {p.width * 1000:.0f} ({p.board})" for p in self.parts]


def hinges_for_height(h: float, rule: list | None = None) -> int:
    """Hinges per door by height. rule = [[max_h, hinges], ...]."""
    rule = rule or [[0.9, 2], [1.6, 3], [2.2, 4], [99, 5]]
    for max_h, n in rule:
        if h <= max_h:
            return int(n)
    return int(rule[-1][1])


def build_cabinet(W: float, H: float, D: float, *, sections: int = 1, shelves: int = 0,
                  doors: int | str = "auto", door_type: str = "hinged", drawers: int = 0,
                  drawer_height: float = 0.18, drawer_columns: int = 1, flaps: int = 0,
                  back: bool = True, plinth: float = 0.0, top: bool = True,
                  hanging_sections: int = 0, max_door_width: float = 0.6,
                  fixed_shelves: bool = False) -> CabinetModel:
    """Build a panel model for one cabinet (all dimensions in metres)."""
    m = CabinetModel(sections=max(1, int(sections)))
    body_h = max(0.05, H - plinth)
    sec_w = W / m.sections
    t = 0.018

    # carcass
    m.parts.append(Part("side", body_h, D, 2, "carcass", thin_edges=body_h))
    if top:
        m.parts.append(Part("top", W, D, 1, "carcass", thin_edges=W))
    m.parts.append(Part("bottom", W, D, 1, "carcass", thin_edges=W))
    if m.sections > 1:
        m.parts.append(Part("divider", body_h - 2 * t, D - 0.02, m.sections - 1, "carcass", thin_edges=body_h))
    if shelves > 0:
        m.parts.append(Part("shelf", sec_w - 0.005, D - 0.03, int(shelves), "carcass", thin_edges=sec_w))
        m.shelves = int(shelves)
    if back:
        m.parts.append(Part("back", W, body_h, 1, "back"))
    if plinth > 0:
        m.parts.append(Part("plinth", W, plinth, 1, "front", thin_edges=W))
    m.hanging_m = sec_w * max(0, int(hanging_sections))

    # drawers (fronts + boxes); drawers stack in `drawer_columns` columns
    drawer_front_area = 0.0
    if drawers > 0:
        cols = max(1, int(drawer_columns))
        dw = W / cols if cols > 1 or m.sections == 1 else sec_w
        m.drawers = int(drawers)
        m.parts.append(Part("drawer front", dw - 0.004, drawer_height, m.drawers, "front",
                            thick_edges=2 * (dw + drawer_height)))
        drawer_front_area = m.drawers * dw * drawer_height
        inner_h = max(0.08, drawer_height - 0.05)
        depth = max(0.25, D - 0.05)
        m.parts.append(Part("drawer side", depth, inner_h, 2 * m.drawers, "drawer", thin_edges=depth))
        m.parts.append(Part("drawer front/back (inner)", dw - 0.08, inner_h, 2 * m.drawers, "drawer",
                            thin_edges=dw - 0.08))
        m.parts.append(Part("drawer bottom", dw - 0.06, depth, m.drawers, "back"))

    # flaps (lift-up / drop-down fronts)
    flap_area = 0.0
    if flaps > 0:
        fh = min(0.45, body_h / 2)
        m.flaps = int(flaps)
        fw = W / m.flaps
        m.parts.append(Part("flap", fw - 0.004, fh, m.flaps, "front", thick_edges=2 * (fw + fh)))
        flap_area = W * fh

    # doors
    door_type = (door_type or "hinged").lower()
    door_zone = max(0.0, W * body_h - drawer_front_area - flap_area)
    if door_type in ("none", "open") or doors == 0 or (door_type != "sliding" and W and door_zone / W < 0.15):
        m.doors = 0   # drawers / flaps fill the face
    else:
        if door_type == "sliding":
            m.sliding = True
            n = 2 if W <= 2.0 else (3 if W <= 3.2 else math.ceil(W / 1.1))
            if doors not in ("auto", None):
                n = int(doors)
            dw = W / n * 1.04  # overlap
            dh = body_h - 0.03
        else:
            n = math.ceil(W / max_door_width - 1e-9) if doors in ("auto", None) else int(doors)
            n = max(1, n)
            # doors cover whatever height is left after drawers/flaps in the door column
            dh = door_zone / W if W else body_h
            dw = W / n
        m.doors = n
        m.door_height = dh
        role = "glass" if door_type == "glass" else "front"
        if role == "glass":
            m.glass_area += n * dw * dh
            # aluminium/timber frame doors: count stiles as front board strips
            m.parts.append(Part("glass door frame", 2 * (dw + dh), 0.06, n, "front", thick_edges=0))
        else:
            m.parts.append(Part("door", dh - 0.003, dw - 0.003, n, "front", thick_edges=2 * (dw + dh)))

    m.front_area = sum(p.area for p in m.parts if p.board == "front")
    return m


def floating_shelf_parts(length: float, depth: float, thickness: float, count: int) -> list[Part]:
    """Box-built floating shelf (top, bottom, front, 2 ends) — reads as a thick slab."""
    parts = [
        Part("shelf top/bottom", length, depth, 2 * count, "front", thin_edges=0),
        Part("shelf front", length, thickness, count, "front", thick_edges=2 * length),
        Part("shelf end", depth, thickness, 2 * count, "front", thick_edges=depth),
    ]
    return parts
