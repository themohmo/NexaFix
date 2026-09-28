"""Internal cost sheet PDF (owner only, landscape A4).

``render_costsheet(estimate, out_path)`` shows how the selling price was
built: key figures, warnings and placeholder prices, per-item margins, the
cost bridge, line-by-line take-off, the purchase list, board usage, labour,
schedule and preliminaries. Marked CONFIDENTIAL - NOT FOR CLIENT throughout.
"""
from __future__ import annotations

import os

from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Flowable, Frame, KeepTogether,
                                PageTemplate, Paragraph, Spacer, Table, TableStyle)

from .pdf_common import (Brand, SpacedText, TitleRow, draw_footer, draw_spaced, esc, fit_text,
                         fmt_money, fmt_num, fmt_pct, fmt_qty, get_fonts, mix, numbered_canvas,
                         safe, spaced_width, style, to_num, wrap_spaced)

PAGE_W, PAGE_H = landscape(A4)
MX = 34.0
BODY_W = PAGE_W - 2 * MX
HEADER_BASE = PAGE_H - 36.0
HEADER_RULE = PAGE_H - 47.0
BODY_TOP = PAGE_H - 58.0
BODY_BOTTOM = 42.0
FOOT_RULE_Y = 30.0
FOOT_TEXT_Y = 19.0
CONFIDENTIAL = "INTERNAL COST SHEET · CONFIDENTIAL — NOT FOR CLIENT"


def _s(value, default: str = "") -> str:
    if value is None:
        return default
    text = safe(value).strip()
    return text or default


def _d(value) -> dict:
    return value if isinstance(value, dict) else {}


def _l(value) -> list:
    return value if isinstance(value, list) else []


def _hex(color) -> str:
    return "#%02X%02X%02X" % (round(color.red * 255), round(color.green * 255),
                              round(color.blue * 255))


class _Ctx:
    def __init__(self, estimate: dict):
        e = _d(estimate)
        self.meta, self.company = _d(e.get("meta")), _d(e.get("company"))
        self.totals, self.internal = _d(e.get("totals")), _d(e.get("internal"))
        self.scope = [s for s in _l(e.get("scope")) if isinstance(s, dict)]
        self.b = Brand(self.company.get("brand"))
        self.f = get_fonts()
        self.currency = _s(self.meta.get("currency"), "AED")
        self.ref = _s(self.meta.get("ref"), "DRAFT")
        self.date = _s(self.meta.get("date"))
        self.name = _s(self.company.get("name"), "NEXA FIX")
        self.target = to_num(self.internal.get("target_margin_pct"), 35.0)
        self.minimum = to_num(self.internal.get("min_margin_pct"), 25.0)
        f, b = self.f, self.b
        self.st = {
            "c": style("c", f.sans, 7.2, 9.2, b.ink),
            "cr": style("cr", f.sans, 7.2, 9.2, b.ink, "right"),
            "cc": style("cc", f.sans, 7.2, 9.2, b.ink, "center"),
            "cb": style("cb", f.sans_medium, 7.2, 9.2, b.ink),
            "cbr": style("cbr", f.sans_medium, 7.2, 9.2, b.ink, "right"),
            "cm": style("cm", f.sans_light, 6.6, 8.4, b.muted),
            "cmr": style("cmr", f.sans_light, 6.6, 8.4, b.muted, "right"),
            "kind": style("kd", f.sans_medium, 6.0, 8.4, b.muted),
            "no": style("no", f.serif_bold, 10, 11, b.accent),
            "note": style("nt", f.sans_light, 6.9, 9.2, b.body),
            "bullet": style("bu", f.sans, 7.3, 9.6, b.ink, leftIndent=9, bulletIndent=0,
                            bulletFontName=f.serif_bold, bulletFontSize=10, bulletColor=b.muted),
            "box_t": style("bt", f.sans_bold, 7.6, 10, b.amber),
            "box_s": style("bs", f.sans, 7.2, 9.6, b.ink),
            "item_l": style("il", f.sans_medium, 8.8, 11, b.ink),
            "item_r": style("ir", f.sans, 7.2, 11, b.muted, "right"),
            "sub": style("sb", f.sans, 7.6, 10, b.muted),
            "empty": style("em", f.sans_light, 7.2, 9.2, b.muted),
        }

    def net_sell(self) -> float:
        """internal.sell_net, else totals.net, else subtotal - discount."""
        tot = self.totals
        subtotal = to_num(tot.get("subtotal"),
                          sum(to_num(s.get("amount")) for s in self.scope))
        fallback = to_num(tot.get("net"), subtotal - to_num(tot.get("discount")))
        return to_num(self.internal.get("sell_net"), fallback)

    def status(self, margin: float, has_data: bool = True):
        b = self.b
        if not has_data:
            return "NO COST DATA", b.muted, b.paper
        if margin >= self.target:
            return "ON TARGET", b.green, b.green_bg
        if margin >= self.minimum:
            return "BELOW TARGET", b.amber, b.amber_bg
        return "BELOW MINIMUM", b.red, b.red_bg

    def p(self, text, key="c"):
        return Paragraph(esc(text), self.st[key])

    def head(self, text, align="left"):
        return SpacedText(text, self.f.sans_medium, 5.9, self.b.muted, 0.9, align=align,
                          leading=7.6)

    def head_block(self, title, aside="", need=110.0) -> list:
        """Section heading that never sits alone at the foot of a page."""
        return [CondPageBreak(need), self.section(title, aside)]

    def section(self, title, aside="", space_before=18.0):
        f, b = self.f, self.b
        return TitleRow(title, f.serif, 15, b.ink, aside=aside, aside_font=f.sans_medium,
                        aside_size=6.0, aside_color=b.muted, aside_cs=1.6, rule_color=b.line,
                        rule_gap=5.0, space_before=space_before, space_after=6)


# =========================================================================== tables
def _grid(q: _Ctx, header, rows, widths, align, kinds=None, repeat=1, extra=None):
    """Data table: header labels, rows of str/flowables, per-column alignment
    ('l'/'r'/'c'), optional per-row kind ('data'|'total'|'group'|'warn'|'note')."""
    b = q.b
    amap = {"l": "left", "r": "right", "c": "center"}
    data = [[q.head(h, amap[a]) for h, a in zip(header, align)]]
    kinds = list(kinds) if kinds else ["data"] * len(rows)
    for row, kind in zip(rows, kinds):
        cells = []
        for v, a in zip(row, align):
            if isinstance(v, Flowable) or isinstance(v, list):
                cells.append(v)
            else:
                key = {"l": "c", "r": "cr", "c": "cc"}[a]
                if kind == "total":
                    key = "cbr" if a == "r" else "cb"
                cells.append(Paragraph(esc(v), q.st[key]))
        data.append(cells)
    cmds = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("VALIGN", (0, 0), (-1, 0), "BOTTOM"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3.2), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.4),
        ("TOPPADDING", (0, 0), (-1, 0), 5), ("BOTTOMPADDING", (0, 0), (-1, 0), 4),
        ("BACKGROUND", (0, 0), (-1, 0), b.head_bg),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, b.ink),
        ("LINEBELOW", (0, -1), (-1, -1), 0.5, b.line),
    ]
    zebra = 0
    for i, kind in enumerate(kinds, start=1):
        if kind == "group":
            zebra = 0
            cmds.append(("BACKGROUND", (0, i), (-1, i), b.accent_faint))
            cmds.append(("LINEABOVE", (0, i), (-1, i), 0.5, b.accent_soft))
            continue
        if kind == "total":
            cmds.append(("LINEABOVE", (0, i), (-1, i), 0.7, b.ink))
            cmds.append(("BACKGROUND", (0, i), (-1, i), b.white))
            continue
        if kind == "note":
            cmds.append(("SPAN", (0, i), (-1, i)))
            cmds.append(("BACKGROUND", (0, i), (-1, i), b.white))
            continue
        if kind == "warn":
            cmds.append(("BACKGROUND", (0, i), (-1, i), b.amber_bg))
        elif zebra % 2:
            cmds.append(("BACKGROUND", (0, i), (-1, i), b.zebra))
        zebra += 1
    if extra:
        cmds.extend(extra)
    t = Table(data, colWidths=widths, repeatRows=repeat)
    t.setStyle(TableStyle(cmds))
    return t


def _mark(q: _Ctx, size: float = 10.0) -> str:
    """A clearly visible bullet (Jost's own bullet glyph is very small)."""
    return f'<font name="{q.f.serif_bold}" size="{size}">•</font>&nbsp;'


def _side_by_side(left: list, right: list, left_w: float, gap: float = 22.0):
    t = Table([[left, "", right]], colWidths=[left_w, gap, BODY_W - left_w - gap])
    t.spaceBefore = 18  # a section heading's own spaceBefore is ignored inside a cell
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return t


def _pct_cell(q: _Ctx, margin: float, bold: bool = False) -> Paragraph:
    _, color, _ = q.status(margin)
    font = q.f.sans_bold if bold else q.f.sans_medium
    return Paragraph(f'<font name="{font}" color="{_hex(color)}">{esc(fmt_pct(margin))}</font>',
                     q.st["cr"])


# =========================================================================== KPI strip
class _KPIStrip(Flowable):
    def __init__(self, q: _Ctx, tiles: list[dict]):
        super().__init__()
        self.q, self.tiles = q, tiles

    def wrap(self, availWidth, availHeight):
        self.width, self.height = availWidth, 70.0
        return self.width, self.height

    def draw(self):
        f, b, c = self.q.f, self.q.b, self.canv
        n = max(1, len(self.tiles))
        gap = 8.0
        tw = (self.width - gap * (n - 1)) / n
        H = self.height
        for i, t in enumerate(self.tiles):
            x = i * (tw + gap)
            c.setFillColor(t.get("bg") or b.paper)
            c.setStrokeColor(b.line)
            c.setLineWidth(0.5)
            c.rect(x, 0, tw, H, stroke=1, fill=1)
            c.setFillColor(t.get("bar") or b.accent)
            c.rect(x, H - 2.4, tw, 2.4, stroke=0, fill=1)
            pad = 8.0
            lines = wrap_spaced(t["label"].upper(), f.sans_medium, 5.8, 1.1, tw - 2 * pad)[:2]
            for j, line in enumerate(lines):
                draw_spaced(c, x + pad, H - 13 - j * 7.6, line, f.sans_medium, 5.8, b.muted, 1.1)
            # value: optional small currency prefix + serif number, shrunk to fit
            prefix, value = t.get("prefix", ""), t["value"]
            size = 17.0
            pw = spaced_width(prefix + " ", f.sans, 6.6) if prefix else 0.0
            while size > 9 and pw + stringWidth(value, f.serif_bold, size) > tw - 2 * pad:
                size -= 0.5
            vy = 25.0
            if prefix:
                draw_spaced(c, x + pad, vy, prefix, f.sans, 6.6, b.muted, 0.0)
            c.setFont(f.serif_bold, size)
            c.setFillColor(b.ink)
            c.drawString(x + pad + pw, vy, value)
            sub = fit_text(t.get("sub", ""), f.sans_medium, 6.6, tw - 2 * pad)
            if sub:
                c.setFont(f.sans_medium, 6.6)
                c.setFillColor(t.get("sub_color") or b.muted)
                c.drawString(x + pad, 10.0, sub)


def _kpis(q: _Ctx) -> list:
    i, tot = q.internal, q.totals
    net = q.net_sell()
    direct = to_num(i.get("direct_cost"))
    total_cost = to_num(i.get("total_cost"))
    gp = to_num(i.get("gross_profit"), net - direct)
    gm = to_num(i.get("gross_margin_pct"), (gp / net * 100.0) if net else 0.0)
    np_ = to_num(i.get("net_profit"), net - total_cost)
    nm = to_num(i.get("net_margin_pct"), (np_ / net * 100.0) if net else 0.0)
    mk = to_num(i.get("markup_on_cost_pct"), ((net - direct) / direct * 100.0) if direct else 0.0)
    vat_on = bool(tot.get("vat_registered", to_num(tot.get("vat")) > 0))
    vat = to_num(tot.get("vat"))
    grand = to_num(tot.get("grand_total"), net + (vat if vat_on else 0.0))
    has_data = bool(net and direct)
    g_lab, g_col, g_bg = q.status(gm, has_data)
    n_lab, n_col, n_bg = q.status(nm, has_data)
    cur = q.currency

    def money(v):
        return fmt_money(v, "")

    tiles = [
        {"label": "Selling price · net ex VAT", "prefix": cur, "value": money(net),
         "sub": f"{len(q.scope)} scope item{'s' if len(q.scope) != 1 else ''}"},
        {"label": "Direct cost", "prefix": cur, "value": money(direct),
         "sub": f"Incl. overhead {fmt_num(total_cost, 0)}" if total_cost else ""},
        {"label": "Gross profit · margin", "prefix": cur, "value": money(gp),
         "sub": f"{fmt_pct(gm)} · {g_lab}", "sub_color": g_col, "bar": g_col, "bg": g_bg},
        {"label": "Net profit · after overhead", "prefix": cur, "value": money(np_),
         "sub": f"{fmt_pct(nm)} · {n_lab}", "sub_color": n_col, "bar": n_col, "bg": n_bg},
        {"label": "Markup on cost", "value": fmt_pct(mk), "sub": "on direct cost"},
        {"label": "VAT", "prefix": cur, "value": money(vat if vat_on else 0),
         "sub": f"{fmt_qty(to_num(tot.get('vat_pct'), 5.0))}% · registered" if vat_on
         else "Not VAT registered"},
        {"label": "Grand total", "prefix": cur, "value": money(grand),
         "sub": "Client pays, incl. VAT" if vat_on else "Client pays"},
    ]
    policy = (f"Target margin {fmt_pct(q.target, 0)}  ·  minimum {fmt_pct(q.minimum, 0)}  ·  "
              f"overhead {fmt_pct(to_num(i.get('overhead_pct')), 0)}  ·  contingency "
              f"{fmt_pct(to_num(i.get('contingency_pct')), 0)} "
              f"({fmt_money(i.get('contingency_amount'), cur)}) included in the scope amounts")
    return [_KPIStrip(q, tiles), Spacer(1, 5), Paragraph(esc(policy), q.st["cm"])]


# =========================================================================== alerts
def _placeholder_rows(q: _Ctx):
    """Collect every placeholder-priced ref with what we know about it."""
    i = q.internal
    refs: list[str] = []

    def add(ref):
        ref = _s(ref)
        if ref and ref not in refs:
            refs.append(ref)

    for r in _l(i.get("placeholders_used")):
        add(r)
    info: dict[str, dict] = {}
    used_in: dict[str, list[str]] = {}
    for idx, item in enumerate(q.scope):
        no = _s(item.get("no"), f"{idx + 1:02d}")
        for line in _l(_d(item.get("internal")).get("lines")):
            if not isinstance(line, dict):
                continue
            ref = _s(line.get("ref"))
            if not ref:
                continue
            if line.get("placeholder"):
                add(ref)
            info.setdefault(ref, {"description": line.get("description"),
                                  "unit": line.get("unit"), "rate": line.get("unit_cost")})
            if no not in used_in.setdefault(ref, []):
                used_in[ref].append(no)
    for row in _l(i.get("purchase_list")):
        if not isinstance(row, dict):
            continue
        ref = _s(row.get("ref"))
        if row.get("placeholder"):
            add(ref)
        if ref:
            info[ref] = {"description": row.get("description"), "unit": row.get("unit"),
                         "rate": row.get("unit_cost"), "cost": row.get("cost")}
    rows = []
    for ref in refs:
        d = info.get(ref, {})
        rate = d.get("rate")
        rows.append([ref, _s(d.get("description"), "–"), _s(d.get("unit"), "–"),
                     fmt_num(rate) if rate not in (None, "") else "–",
                     fmt_num(d.get("cost")) if d.get("cost") not in (None, "") else "–",
                     ", ".join(used_in.get(ref, [])) or "–"])
    return rows


def _placeholder_box(q: _Ctx) -> list:
    f, b, st = q.f, q.b, q.st
    out: list = []
    rows = _placeholder_rows(q)
    if rows:
        widths = [110.0, BODY_W - 110 - 60 - 90 - 90 - 110 - 16, 60.0, 90.0, 90.0, 110.0]
        title = Paragraph(f'{_mark(q)}PLACEHOLDER PRICES STILL IN USE ({len(rows)})',
                          st["box_t"])
        sub = Paragraph(esc("These rates are rate-book defaults, not your supplier prices. "
                            "Replace them with real quotes before sending the quotation: "
                            "the cost, margin and purchase totals below depend on them."),
                        st["box_s"])
        data = [[title, "", "", "", "", ""], [sub, "", "", "", "", ""],
                [q.head(h, a) for h, a in (("Ref", "left"), ("Description", "left"),
                                           ("Unit", "left"), ("Placeholder rate", "right"),
                                           ("Purchase cost", "right"),
                                           ("Used in items", "left"))]]
        for r in rows:
            data.append([Paragraph(f'<font name="{f.sans_medium}">{esc(r[0])}</font>', st["c"]),
                         q.p(r[1]), q.p(r[2]), q.p(r[3], "cr"), q.p(r[4], "cr"), q.p(r[5])])
        t = Table(data, colWidths=[w for w in widths[:5]] + [widths[5] + 16], repeatRows=3)
        t.setStyle(TableStyle([
            ("SPAN", (0, 0), (-1, 0)), ("SPAN", (0, 1), (-1, 1)),
            ("BACKGROUND", (0, 0), (-1, -1), b.amber_bg),
            ("LINEBEFORE", (0, 0), (0, -1), 3.0, b.amber),
            ("BOX", (0, 0), (-1, -1), 0.6, b.amber),
            ("LINEBELOW", (0, 2), (-1, 2), 0.5, b.amber),
            ("LINEBELOW", (0, 3), (-1, -1), 0.3, mix(b.amber, b.amber_bg, 0.7)),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 2.6), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.8),
            ("TOPPADDING", (0, 0), (-1, 0), 8), ("BOTTOMPADDING", (0, 1), (-1, 1), 7),
            ("BOTTOMPADDING", (0, -1), (-1, -1), 8),
        ]))
        out += [Spacer(1, 12), t]
    else:
        out += [Spacer(1, 10), Paragraph(
            f'<font color="{_hex(b.green)}" name="{f.sans_medium}">All prices are owner '
            f'confirmed: no placeholder rates in use.</font>', st["c"])]
    return out


def _alerts(q: _Ctx) -> list:
    f, b, st = q.f, q.b, q.st
    out: list = []
    # warnings | assumptions
    warns = [_s(w) for w in _l(q.internal.get("warnings")) if _s(w)]
    for idx, item in enumerate(q.scope):
        no = _s(item.get("no"), f"{idx + 1:02d}")
        for w in _l(_d(item.get("internal")).get("warnings")):
            if _s(w):
                warns.append(f"Item {no}: {_s(w)}")
    assumptions = [_s(a) for a in _l(q.internal.get("assumptions")) if _s(a)]
    n = max(len(warns), len(assumptions), 1)
    col = (BODY_W - 16) / 2.0

    def bullet(text, color):
        return Paragraph(esc(text), style("x", f.sans, 7.3, 9.6, b.ink, leftIndent=9,
                                          bulletIndent=0, bulletFontName=f.serif_bold,
                                          bulletFontSize=10, bulletColor=color),
                         bulletText="•")

    data = [[SpacedText(f"Warnings ({len(warns)})", f.sans_bold, 6.4, b.amber if warns
                        else b.muted, 1.4), "",
             SpacedText(f"Assumptions ({len(assumptions)})", f.sans_bold, 6.4, b.muted, 1.4)]]
    for k in range(n):
        w = bullet(warns[k], b.amber) if k < len(warns) else (
            q.p("No warnings.", "empty") if k == 0 else "")
        a = bullet(assumptions[k], b.muted) if k < len(assumptions) else (
            q.p("No assumptions recorded.", "empty") if k == 0 else "")
        data.append([w, "", a])
    t = Table(data, colWidths=[col, 16, col], repeatRows=1)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 0), (0, -1), b.amber_bg if warns else b.zebra),
        ("BACKGROUND", (2, 0), (2, -1), b.zebra),
        ("LINEBEFORE", (0, 0), (0, -1), 2.2, b.amber if warns else b.line),
        ("LINEBEFORE", (2, 0), (2, -1), 2.2, b.line),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("LEFTPADDING", (1, 0), (1, -1), 0), ("RIGHTPADDING", (1, 0), (1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("TOPPADDING", (0, 0), (-1, 0), 7), ("BOTTOMPADDING", (0, 0), (-1, 0), 4),
        ("BOTTOMPADDING", (0, -1), (-1, -1), 7),
    ]))
    out += [Spacer(1, 10), t]
    return out


# =========================================================================== summary + bridge
def _scope_summary(q: _Ctx) -> list:
    has_other = any(to_num(_d(s.get("internal")).get("cost_other")) for s in q.scope)
    header = ["No", "Item", "Cost materials", "Cost labour"] + (["Cost other"] if has_other
                                                                  else [])
    header += ["Cost total", "Client amount", "Profit", "Margin"]
    num_w = 78.0
    n_num = len(header) - 3
    widths = [30.0, BODY_W - 30.0 - num_w * n_num - 62.0] + [num_w] * n_num + [62.0]
    align = ["l", "l"] + ["r"] * (len(header) - 2)
    rows, kinds, extra = [], [], []
    sums = {"m": 0.0, "l": 0.0, "o": 0.0, "c": 0.0, "a": 0.0, "p": 0.0}
    for idx, item in enumerate(q.scope):
        it = _d(item.get("internal"))
        m, lab, oth = (to_num(it.get("cost_materials")), to_num(it.get("cost_labour")),
                       to_num(it.get("cost_other")))
        cost = to_num(it.get("cost_total"), m + lab + oth)
        amount = to_num(item.get("amount"), to_num(it.get("amount")))
        profit = to_num(it.get("profit"), amount - cost)
        margin = to_num(it.get("margin_pct"), (profit / amount * 100.0) if amount else 0.0)
        for k, v in (("m", m), ("l", lab), ("o", oth), ("c", cost), ("a", amount), ("p", profit)):
            sums[k] += v
        row = [Paragraph(esc(_s(item.get("no"), f"{idx + 1:02d}")), q.st["no"]),
               Paragraph(f'{esc(_s(item.get("title"), "Scope item"))}'
                         + (f'<br/><font name="{q.f.sans_light}" size="6.4" '
                            f'color="{_hex(q.b.muted)}">{esc(_s(item.get("room")))}</font>'
                            if _s(item.get("room")) else ""), q.st["cb"]),
               fmt_num(m), fmt_num(lab)] + ([fmt_num(oth)] if has_other else [])
        row += [fmt_num(cost), fmt_num(amount), fmt_num(profit), _pct_cell(q, margin)]
        rows.append(row)
        kinds.append("data")
        _, _, bg = q.status(margin)
        extra.append(("BACKGROUND", (len(header) - 1, len(rows)), (len(header) - 1, len(rows)), bg))
    if not rows:
        rows.append(["", q.p("No scope items.", "empty")] + [""] * (len(header) - 2))
        kinds.append("data")
    else:
        tm = (sums["p"] / sums["a"] * 100.0) if sums["a"] else 0.0
        total = ["", "Total", fmt_num(sums["m"]), fmt_num(sums["l"])]
        total += [fmt_num(sums["o"])] if has_other else []
        total += [fmt_num(sums["c"]), fmt_num(sums["a"]), fmt_num(sums["p"]),
                  _pct_cell(q, tm, bold=True)]
        rows.append(total)
        kinds.append("total")
    return [*q.head_block("Scope summary",
                          f"Amounts in {q.currency} · margin = profit / client amount"),
            _grid(q, header, rows, widths, align, kinds, extra=extra),
            Paragraph(esc("Item costs are the direct take-off per item; consumables, stock "
                          "rounding and preliminaries sit in the cost bridge."), q.st["cm"])]


def _bridge(q: _Ctx) -> list:
    i, tot, b = q.internal, q.totals, q.b
    parts = [("Materials", i.get("materials_cost")), ("Labour", i.get("labour_cost")),
             ("Other", i.get("other_cost")), ("Consumables", i.get("consumables_cost")),
             ("Stock rounding (buying full packs and sheets)", i.get("stock_rounding_cost")),
             ("Preliminaries", i.get("prelims_cost"))]
    direct = to_num(i.get("direct_cost"))
    overhead = to_num(i.get("overhead_cost"))
    total_cost = to_num(i.get("total_cost"), direct + overhead)
    net = q.net_sell()
    cur = q.currency
    rows = [[lab, fmt_num(v), ""] for lab, v in parts]
    kinds = ["data"] * len(rows)
    rows.append(["= Direct cost", fmt_num(direct), ""])
    kinds.append("total")
    rows.append([f"+ Overhead ({fmt_pct(to_num(i.get('overhead_pct')), 0)} of direct cost)",
                 fmt_num(overhead), ""])
    kinds.append("data")
    rows.append(["= Total cost", fmt_num(total_cost), ""])
    kinds.append("total")
    rows.append([Paragraph(esc(f"Contingency ({fmt_pct(to_num(i.get('contingency_pct')), 0)}) "
                               "carried inside the scope amounts"), q.st["cm"]),
                 Paragraph(esc(fmt_num(i.get("contingency_amount"))), q.st["cmr"]), ""])
    kinds.append("data")
    parts_sum = sum(to_num(v) for _, v in parts)
    if direct and abs(parts_sum - direct) > 0.51:
        rows.append([Paragraph(f'<font color="{_hex(b.red)}">Check: parts sum to '
                               f'{esc(fmt_num(parts_sum))}, not the direct cost '
                               f'(difference {esc(fmt_num(direct - parts_sum))}).</font>',
                               q.st["c"]), "", ""])
        kinds.append("warn")
    lw = BODY_W * 0.47
    left = _grid(q, ["Cost bridge", f"{cur}", ""], rows, [lw - 150, 90, 60], ["l", "r", "r"],
                 kinds)

    subtotal = to_num(tot.get("subtotal"))
    discount = to_num(tot.get("discount"))
    vat_on = bool(tot.get("vat_registered", to_num(tot.get("vat")) > 0))
    vat = to_num(tot.get("vat"))
    grand = to_num(tot.get("grand_total"), net + (vat if vat_on else 0.0))
    gp = to_num(i.get("gross_profit"), net - direct)
    gm = to_num(i.get("gross_margin_pct"), (gp / net * 100.0) if net else 0.0)
    np_ = to_num(i.get("net_profit"), net - total_cost)
    nm = to_num(i.get("net_margin_pct"), (np_ / net * 100.0) if net else 0.0)
    mk = to_num(i.get("markup_on_cost_pct"), ((net - direct) / direct * 100.0) if direct else 0.0)
    prow = [["Scope amounts (subtotal)", fmt_num(subtotal), ""]]
    pk = ["data"]
    if discount:
        label = _s(tot.get("discount_label"))
        prow.append([f"– Discount{' · ' + label if label else ''}", "–" + fmt_num(discount), ""])
        pk.append("data")
    prow.append(["= Selling price, net ex VAT", fmt_num(net), ""])
    pk.append("total")
    prow.append([f"VAT {fmt_qty(to_num(tot.get('vat_pct'), 5.0))}%" if vat_on
                 else "VAT (not registered)", fmt_num(vat if vat_on else 0), ""])
    pk.append("data")
    prow.append(["= Grand total to client", fmt_num(grand), ""])
    pk.append("total")
    prow.append(["Gross profit (net sell – direct cost)", fmt_num(gp), _pct_cell(q, gm, True)])
    pk.append("data")
    prow.append(["Net profit (after overhead)", fmt_num(np_), _pct_cell(q, nm, True)])
    pk.append("data")
    prow.append(["Markup on direct cost", "", fmt_pct(mk)])
    pk.append("data")
    rw = BODY_W - lw - 22
    right = _grid(q, ["Price & profit", f"{cur}", "Margin"], prow, [rw - 150, 90, 60],
                  ["l", "r", "r"], pk)
    return [KeepTogether([q.section("Cost bridge", "direct cost, overhead and profit"),
                          _side_by_side([left], [right], lw)])]


# =========================================================================== line build-up
def _line_buildup(q: _Ctx) -> list:
    f, b, st = q.f, q.b, q.st
    heading = q.section("Line build-up by scope item",
                        "take-off, cost and sell per line · amounts in " + q.currency)
    out: list = []
    fixed = [46.0, 160.0, 44.0, 34.0, 58.0, 64.0, 58.0, 64.0]
    calc_w = BODY_W - sum(fixed)
    widths = [fixed[0], fixed[1], calc_w] + fixed[2:]
    header = ["Kind", "Description", "Calc (take-off)", "Qty", "Unit", "Unit cost", "Cost",
              "Unit sell", "Sell"]
    align = ["l", "l", "l", "r", "l", "r", "r", "r", "r"]
    amber = _hex(b.amber)
    muted = _hex(b.muted)
    for idx, item in enumerate(q.scope):
        it = _d(item.get("internal"))
        no = _s(item.get("no"), f"{idx + 1:02d}")
        amount = to_num(item.get("amount"), to_num(it.get("amount")))
        cost = to_num(it.get("cost_total"))
        margin = to_num(it.get("margin_pct"), ((amount - cost) / amount * 100.0) if amount else 0)
        _, mcol, _ = q.status(margin)
        left = Paragraph(f'<font name="{f.serif_bold}" size="11" color="{_hex(b.accent)}">'
                         f'{esc(no)}</font>&nbsp;&nbsp;&nbsp;{esc(_s(item.get("title"), "Scope item"))}'
                         + (f'<font name="{f.sans_light}" size="7" color="{muted}">'
                            f'&nbsp;&nbsp;·&nbsp;&nbsp;{esc(_s(item.get("room")))}</font>'
                            if _s(item.get("room")) else ""), st["item_l"])
        right = Paragraph(
            f'Client {esc(fmt_money(amount, q.currency))}&nbsp;&nbsp;·&nbsp;&nbsp;'
            f'Cost {esc(fmt_num(cost))}&nbsp;&nbsp;·&nbsp;&nbsp;'
            f'Profit {esc(fmt_num(it.get("profit", amount - cost)))}&nbsp;&nbsp;·&nbsp;&nbsp;'
            f'<font name="{f.sans_bold}" color="{_hex(mcol)}">Margin {esc(fmt_pct(margin))}</font>',
            st["item_r"])
        data = [[left, "", "", right, "", "", "", "", ""],
                [q.head(h, {"l": "left", "r": "right"}[a]) for h, a in zip(header, align)]]
        kinds: list[str] = []
        lines = [ln for ln in _l(it.get("lines")) if isinstance(ln, dict)]
        sum_cost = sum_sell = 0.0
        for ln in lines:
            ph = bool(ln.get("placeholder"))
            desc = esc(_s(ln.get("description"), "–"))
            meta = []
            if _s(ln.get("ref")):
                meta.append(f'<font name="{f.sans_light}" size="6" color="{muted}">'
                            f'{esc(_s(ln.get("ref")))}</font>')
            if ph:
                meta.append(f'<font name="{f.sans_bold}" size="6" color="{amber}">'
                            f'{_mark(q, 8)}PLACEHOLDER</font>')
            if meta:
                desc += "<br/>" + "&nbsp;&nbsp;".join(meta)
            sum_cost += to_num(ln.get("cost"))
            sum_sell += to_num(ln.get("sell"))
            data.append([Paragraph(esc(_s(ln.get("kind"), "–").upper()), st["kind"]),
                         Paragraph(desc, st["c"]),
                         Paragraph(esc(_s(ln.get("calc"))), st["cm"]),
                         q.p(fmt_qty(ln.get("qty")), "cr"), q.p(_s(ln.get("unit"))),
                         q.p(fmt_num(ln.get("unit_cost")), "cr"), q.p(fmt_num(ln.get("cost")), "cr"),
                         q.p(fmt_num(ln.get("unit_sell")), "cr"), q.p(fmt_num(ln.get("sell")), "cr")])
            kinds.append("warn" if ph else "data")
        if lines:
            data.append(["", Paragraph("Line totals", st["cb"]), "", "", "", "",
                         q.p(fmt_num(sum_cost), "cbr"), "", q.p(fmt_num(sum_sell), "cbr")])
            kinds.append("total")
        else:
            data.append([q.p("No line build-up recorded for this item.", "empty")] + [""] * 8)
            kinds.append("note")
        # footnote: build-up vs item totals, labour hours, notes, warnings
        bits = [f"Item cost total {esc(fmt_num(cost))}  ·  materials "
                f"{esc(fmt_num(it.get('cost_materials')))}  ·  labour "
                f"{esc(fmt_num(it.get('cost_labour')))}"
                + (f"  ·  other {esc(fmt_num(it.get('cost_other')))}"
                   if to_num(it.get("cost_other")) else "")
                + (f"  ·  sell build-up {esc(fmt_num(it.get('sell_build_up')))}"
                   if it.get("sell_build_up") not in (None, "") else "")
                + f"  ·  client amount {esc(fmt_num(amount))}"]
        hours = _d(it.get("labour_hours"))
        if hours:
            bits.append("Labour hours: " + ", ".join(
                f"{esc(_s(k))} {esc(fmt_qty(v, 1))} h" for k, v in hours.items()))
        notes = [_s(n) for n in _l(it.get("notes")) if _s(n)]
        if notes:
            bits.append("Notes: " + esc("; ".join(notes)))
        warns = [_s(w) for w in _l(it.get("warnings")) if _s(w)]
        if warns:
            bits.append(f'<font name="{f.sans_medium}" color="{amber}">Warnings: '
                        f'{esc("; ".join(warns))}</font>')
        data.append([Paragraph("<br/>".join(bits), st["note"])] + [""] * 8)
        kinds.append("note")

        cmds = [
            ("SPAN", (0, 0), (2, 0)), ("SPAN", (3, 0), (-1, 0)),
            ("BACKGROUND", (0, 0), (-1, 0), b.panel_soft),
            ("LINEABOVE", (0, 0), (-1, 0), 1.0, b.accent),
            ("VALIGN", (0, 0), (-1, 0), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, 0), 5), ("BOTTOMPADDING", (0, 0), (-1, 0), 5),
            ("VALIGN", (0, 1), (-1, 1), "BOTTOM"),
            ("BACKGROUND", (0, 1), (-1, 1), b.head_bg),
            ("LINEBELOW", (0, 1), (-1, 1), 0.6, b.ink),
            ("VALIGN", (0, 2), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 1), (-1, -1), 3.2), ("BOTTOMPADDING", (0, 1), (-1, -1), 3.4),
        ]
        zebra = 0
        for r, kind in enumerate(kinds, start=2):
            if kind == "warn":
                cmds.append(("BACKGROUND", (0, r), (-1, r), b.amber_bg))
                cmds.append(("LINEBEFORE", (0, r), (0, r), 2.0, b.amber))
                zebra += 1
            elif kind == "total":
                cmds.append(("LINEABOVE", (0, r), (-1, r), 0.7, b.ink))
            elif kind == "note":
                cmds.append(("SPAN", (0, r), (-1, r)))
            else:
                if zebra % 2:
                    cmds.append(("BACKGROUND", (0, r), (-1, r), b.zebra))
                zebra += 1
        cmds.append(("LINEBELOW", (0, -1), (-1, -1), 0.5, b.line))
        t = Table(data, colWidths=widths, repeatRows=2)
        t.setStyle(TableStyle(cmds))
        # the section heading travels with the first item's table; an item that
        # fits on one page is kept whole, a longer one splits in place (the item
        # band and column headers repeat on each page)
        block = ([heading] if idx == 0 else []) + [Spacer(1, 10), t]
        if t.wrap(BODY_W, 10000)[1] <= (BODY_TOP - BODY_BOTTOM) - 60:
            out.append(KeepTogether(block))
        else:
            out += [CondPageBreak(170)] + block
    if not q.scope:
        out += [heading, q.p("No scope items.", "empty")]
    return out


# =========================================================================== purchasing etc.
def _purchase_list(q: _Ctx) -> list:
    f, b, st = q.f, q.b, q.st
    items = [r for r in _l(q.internal.get("purchase_list")) if isinstance(r, dict)]
    head = q.head_block("Purchase list",
                        f"what to buy · grouped by category · amounts in {q.currency}")
    if not items:
        return [*head, q.p("No purchase list produced.", "empty")]
    fixed = [92.0, 54.0, 50.0, 40.0, 104.0, 60.0, 66.0, 96.0]
    widths = [fixed[0], BODY_W - sum(fixed)] + fixed[1:]
    header = ["Ref", "Description", "Qty required", "Qty to buy", "Unit", "Pack note",
              "Unit cost", "Cost", "Supplier"]
    align = ["l", "l", "r", "r", "l", "l", "r", "r", "l"]
    groups: dict[str, list[dict]] = {}
    for r in items:
        groups.setdefault(_s(r.get("category"), "uncategorised").lower(), []).append(r)
    order = sorted(groups, key=lambda k: (k == "uncategorised", k))
    rows, kinds, extra = [], [], []
    amber, muted = _hex(b.amber), _hex(b.muted)
    grand = 0.0
    for cat in order:
        rs = groups[cat]
        sub = sum(to_num(r.get("cost")) for r in rs)
        grand += sub
        label = SpacedText(f"{cat}  ·  {len(rs)} item{'s' if len(rs) != 1 else ''}",
                           f.sans_bold, 6.4, b.ink, 1.6)
        rows.append([label, "", "", "", "", "", "", q.p(fmt_num(sub), "cbr"), ""])
        kinds.append("group")
        extra.append(("SPAN", (0, len(rows)), (6, len(rows))))
        for r in rs:
            ph = bool(r.get("placeholder"))
            desc = esc(_s(r.get("description"), "–"))
            if ph:
                desc += (f'<br/><font name="{f.sans_bold}" size="6" color="{amber}">'
                         f'{_mark(q, 8)}PLACEHOLDER PRICE</font>')
            supplier = _s(r.get("supplier"))
            rows.append([Paragraph(f'<font name="{f.sans_medium}">{esc(_s(r.get("ref"), "–"))}'
                                   f'</font>', st["c"]),
                         Paragraph(desc, st["c"]), fmt_qty(r.get("qty_required")),
                         fmt_qty(r.get("qty_to_buy")), _s(r.get("unit")),
                         Paragraph(esc(_s(r.get("pack_note"))), st["cm"]),
                         fmt_num(r.get("unit_cost")), fmt_num(r.get("cost")),
                         Paragraph(esc(supplier) if supplier else
                                   f'<font color="{muted}">–</font>', st["c"])])
            kinds.append("warn" if ph else "data")
    rows.append(["", "Total purchase list", "", "", "", "", "", fmt_num(grand), ""])
    kinds.append("total")
    return [*head, _grid(q, header, rows, widths, align, kinds, extra=extra)]


def _boards(q: _Ctx, width: float) -> list:
    boards = [r for r in _l(q.internal.get("boards")) if isinstance(r, dict)]
    head = q.section("Joinery board usage", "wood used")
    if not boards:
        return [head, q.p("No sheet materials in this estimate.", "empty")]
    fixed = [80.0, 44.0, 50.0, 50.0, 48.0]
    widths = [fixed[0], width - sum(fixed)] + fixed[1:]
    header = ["Ref", "Board", "Area m²", "Sheets exact", "Sheets to buy", "Yield"]
    rows, tm2, tbuy, texact = [], 0.0, 0.0, 0.0
    for r in boards:
        exact, buy = to_num(r.get("sheets_exact")), to_num(r.get("sheets_to_buy"))
        tm2 += to_num(r.get("m2"))
        texact += exact
        tbuy += buy
        rows.append([_s(r.get("ref"), "–"), _s(r.get("description"), "–"),
                     fmt_num(r.get("m2"), 1), fmt_qty(exact, 1), fmt_qty(buy),
                     fmt_pct(exact / buy * 100.0, 0) if buy else "–"])
    rows.append(["", "Total", fmt_num(tm2, 1), fmt_qty(texact, 1), fmt_qty(tbuy),
                 fmt_pct(texact / tbuy * 100.0, 0) if tbuy else "–"])
    kinds = ["data"] * len(boards) + ["total"]
    return [head, _grid(q, header, rows, widths, ["l", "l", "r", "r", "r", "r"], kinds)]


def _prelims(q: _Ctx, width: float) -> list:
    pre = [r for r in _l(q.internal.get("prelims")) if isinstance(r, dict)]
    head = q.section("Preliminaries", f"amounts in {q.currency}")
    if not pre:
        return [head, q.p("No preliminaries.", "empty")]
    widths = [width * 0.36, width - width * 0.36 - 136, 68.0, 68.0]
    rows = [[_s(r.get("name"), "–"), Paragraph(esc(_s(r.get("calc"))), q.st["cm"]),
             fmt_num(r.get("cost")), fmt_num(r.get("sell"))] for r in pre]
    rows.append(["Total", "", fmt_num(sum(to_num(r.get("cost")) for r in pre)),
                 fmt_num(sum(to_num(r.get("sell")) for r in pre))])
    kinds = ["data"] * len(pre) + ["total"]
    return [head, _grid(q, ["Item", "Calc", "Cost", "Sell"], rows, widths,
                        ["l", "l", "r", "r"], kinds)]


def _labour(q: _Ctx, width: float) -> list:
    lab = [r for r in _l(q.internal.get("labour")) if isinstance(r, dict)]
    head = q.section("Labour by trade", f"amounts in {q.currency}")
    if not lab:
        return [head, q.p("No labour recorded.", "empty")]
    fixed = [46.0, 40.0, 50.0, 64.0, 50.0, 64.0]
    widths = [width - sum(fixed)] + fixed
    header = ["Trade", "Hours", "Days", "Cost / h", "Cost", "Sell / h", "Sell"]
    rows = []
    th = td = tc = ts = 0.0
    for r in lab:
        h, d, c, s = (to_num(r.get("hours")), to_num(r.get("days")), to_num(r.get("cost")),
                      to_num(r.get("sell")))
        th, td, tc, ts = th + h, td + d, tc + c, ts + s
        rows.append([_s(r.get("label")) or _s(r.get("trade"), "–"), fmt_qty(h, 1), fmt_qty(d, 1),
                     fmt_num(r.get("cost_per_hour")), fmt_num(c), fmt_num(r.get("sell_per_hour")),
                     fmt_num(s)])
    rows.append(["Total", fmt_qty(th, 1), fmt_qty(td, 1), "", fmt_num(tc), "", fmt_num(ts)])
    kinds = ["data"] * len(lab) + ["total"]
    return [head, _grid(q, header, rows, widths, ["l"] + ["r"] * 6, kinds)]


def _schedule(q: _Ctx, width: float) -> list:
    sc = _d(q.internal.get("schedule"))
    head = q.section("Schedule", "working days")
    if not sc:
        return [head, q.p("No schedule produced.", "empty")]
    rows = [["Procurement", fmt_qty(sc.get("procurement_days"), 1)],
            ["Workshop", fmt_qty(sc.get("workshop_days"), 1)],
            ["Site", fmt_qty(sc.get("site_days"), 1)],
            ["Total days", fmt_qty(sc.get("total_days"), 1)],
            ["Weeks", fmt_qty(sc.get("weeks"), 1)]]
    kinds = ["data", "data", "data", "total", "data"]
    out = [head, _grid(q, ["Stage", "Days"], rows, [width - 70, 70.0], ["l", "r"], kinds)]
    notes = [_s(n) for n in _l(sc.get("notes")) if _s(n)]
    for n in notes:
        out.append(Paragraph(esc(n), q.st["bullet"], bulletText="•"))
    if notes:
        out.insert(2, Spacer(1, 5))
    return out


def _pair(left: list, right: list, left_w: float, short: bool) -> list:
    if short:
        return [_side_by_side(left, right, left_w)]
    return [CondPageBreak(110)] + left + [CondPageBreak(110)] + right


# =========================================================================== document
def render_costsheet(estimate: dict, out_path: str) -> str:
    """Render the internal cost sheet PDF to ``out_path`` and return the path."""
    q = _Ctx(estimate)
    f, b = q.f, q.b
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    def on_page(c, doc):
        c.saveState()
        draw_spaced(c, MX, HEADER_BASE, q.name, f.serif_bold, 13, b.ink, 3.0)
        x = MX + spaced_width(q.name, f.serif_bold, 13, 3.0) + 16
        tw = spaced_width(CONFIDENTIAL, f.sans_bold, 6.6, 1.4)
        c.setFillColor(b.red)
        c.roundRect(x, HEADER_BASE - 4.2, tw + 16, 14.5, 2, stroke=0, fill=1)
        draw_spaced(c, x + 8, HEADER_BASE, CONFIDENTIAL, f.sans_bold, 6.6, b.white, 1.4)
        info = "  ·  ".join(p for p in (q.ref, q.date, _s(q.meta.get("client")),
                                        _s(q.meta.get("project"))) if p)
        room = PAGE_W - MX - (x + tw + 16) - 20
        draw_spaced(c, PAGE_W - MX, HEADER_BASE, fit_text(info, f.sans, 7.0, room, 0.3), f.sans,
                    7.0, b.muted, 0.3, "right")
        c.setStrokeColor(b.line)
        c.setLineWidth(0.6)
        c.line(MX, HEADER_RULE, PAGE_W - MX, HEADER_RULE)
        c.restoreState()

    def furniture(c, page, total):
        c.saveState()
        draw_footer(c, MX, PAGE_W - MX, FOOT_TEXT_Y,
                    f"{q.name} · INTERNAL COST SHEET · {q.ref} · NOT FOR CLIENT",
                    "", f.sans, 6.0, b.muted, 1.6, rule_color=b.line, rule_y=FOOT_RULE_Y)
        c.setFont(f.sans_medium, 7.2)
        c.setFillColor(b.ink)
        c.drawRightString(PAGE_W - MX, FOOT_TEXT_Y, f"Page {page} of {total}")
        c.restoreState()

    frame = Frame(MX, BODY_BOTTOM, BODY_W, BODY_TOP - BODY_BOTTOM, 0, 0, 0, 0, id="body")
    doc = BaseDocTemplate(out_path, pagesize=(PAGE_W, PAGE_H), leftMargin=MX, rightMargin=MX,
                          topMargin=PAGE_H - BODY_TOP, bottomMargin=BODY_BOTTOM,
                          title=f"Internal Cost Sheet {q.ref} (confidential)",
                          author=q.name, subject=_s(q.meta.get("project")),
                          creator="NexaFix costing tool")
    doc.addPageTemplates([PageTemplate(id="body", frames=[frame], onPage=on_page)])

    title = _s(q.meta.get("title"), "Estimate")
    sub = "  ·  ".join(p for p in (_s(q.meta.get("project")), _s(q.meta.get("client")),
                                  _s(q.meta.get("location"))) if p)
    story: list = [
        SpacedText(f"Internal cost sheet  ·  ref {q.ref}" + (f"  ·  {q.date}" if q.date else ""),
                   f.sans_medium, 6.4, b.accent, 1.8, space_after=5),
        Paragraph(esc(title), style("ttl", f.serif, 21, 23, b.ink)),
    ]
    if sub:
        story += [Spacer(1, 2), Paragraph(esc(sub), q.st["sub"])]
    story += [Spacer(1, 10)] + _kpis(q) + _alerts(q)
    story += _scope_summary(q)
    story += _bridge(q)
    story += _placeholder_box(q)
    story += _line_buildup(q)
    story += _purchase_list(q)
    n_boards = len(_l(q.internal.get("boards")))
    n_pre = len(_l(q.internal.get("prelims")))
    n_lab = len(_l(q.internal.get("labour")))
    lw = BODY_W * 0.55
    story += _pair(_boards(q, lw if max(n_boards, n_pre) <= 14 else BODY_W),
                   _prelims(q, BODY_W - lw - 22 if max(n_boards, n_pre) <= 14 else BODY_W),
                   lw, max(n_boards, n_pre) <= 14)
    lw2 = BODY_W * 0.64
    short = n_lab <= 14 and len(_l(_d(q.internal.get("schedule")).get("notes"))) <= 8
    story += _pair(_labour(q, lw2 if short else BODY_W),
                   _schedule(q, BODY_W - lw2 - 22 if short else BODY_W), lw2, short)
    doc.build(story, canvasmaker=numbered_canvas(furniture))
    return out_path
