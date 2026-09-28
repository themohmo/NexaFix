"""Client quotation PDF (NexaFix quotation template).

``render_quote(estimate, out_path)`` reads the estimate JSON contract
(see references/estimate-json.md) and writes an A4 quotation:

* page 1   cover: wordmark, reference, title, summary, prepared-for /
           quotation details, covering letter, numbered cover tiles
* pages 2+ scope of work, about two items per page (never split)
* last     investment summary, totals, terms & conditions, acceptance

Nothing under any ``internal`` key is ever read here.
"""
from __future__ import annotations

import os

from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Flowable, Frame, KeepTogether,
                                NextPageTemplate, PageBreak, PageTemplate, Paragraph,
                                Spacer, Table, TableStyle)

from .pdf_common import (Brand, SpacedText, TitleRow, contact_line, display_name,
                         draw_footer, draw_image, draw_spaced, esc, fit_text, fmt_money,
                         fmt_num, fmt_qty, get_fonts, load_image, numbered_canvas, safe,
                         spaced_width, style, to_num, wrap_spaced)

PAGE_W, PAGE_H = A4
MX = 56.0                      # side margins
BODY_W = PAGE_W - 2 * MX
BODY_BOTTOM = 72.0             # frames stop above the footer
FOOT_RULE_Y = 52.0
FOOT_TEXT_Y = 38.0
COVER_TOP = PAGE_H - 50.0
HEADER_BASE = PAGE_H - 58.0    # wordmark baseline on inner pages
HEADER_RULE = PAGE_H - 84.0
BODY_TOP = PAGE_H - 106.0

DEFAULT_LETTER = [
    "Thank you for extending to {company} the opportunity to submit our quotation for the "
    "above mentioned project.",
    "We are pleased to present our proposal for the supply, fabrication, and installation of "
    "bespoke furniture and wall cladding, executed with high quality materials and superior "
    "craftsmanship, in strict accordance with the approved drawings, samples, and "
    "specifications.",
    "We trust that our offer meets your expectations, and we look forward to your valued "
    "confirmation.",
]
INCLUSIVE_NOTE = ("All amounts are inclusive of supply, fabrication, delivery, and professional "
                  "installation as per the approved drawings, samples, and specifications.")
ACCEPTANCE_TEXT = ("Signature below constitutes acceptance of this quotation and the terms and "
                   "conditions stated herein.")


def _s(value, default: str = "") -> str:
    """Sanitised, stripped string with a default for None / blanks."""
    if value is None:
        return default
    text = safe(value).strip()
    return text or default


class _Ctx:
    """Everything the quotation needs, resolved once with safe defaults."""

    def __init__(self, estimate: dict):
        e = estimate if isinstance(estimate, dict) else {}
        self.meta = e.get("meta") if isinstance(e.get("meta"), dict) else {}
        self.company = e.get("company") if isinstance(e.get("company"), dict) else {}
        self.totals = e.get("totals") if isinstance(e.get("totals"), dict) else {}
        self.scope = [s for s in (e.get("scope") or []) if isinstance(s, dict)]
        self.terms = e.get("terms") if isinstance(e.get("terms"), list) else []
        self.b = Brand(self.company.get("brand"))
        self.f = get_fonts()
        m, co = self.meta, self.company
        self.currency = _s(m.get("currency"), "AED")
        self.ref = _s(m.get("ref"), "DRAFT")
        self.date = _s(m.get("date"))
        self.title = _s(m.get("title"), "Quotation")
        self.summary = _s(m.get("summary"))
        self.client = _s(m.get("client"), "Client Name")
        self.project = _s(m.get("project"))
        self.location = _s(m.get("location"))
        self.name = _s(co.get("name"), "NEXA FIX")
        self.name_display = display_name(self.name) or self.name
        self.tagline = _s(co.get("tagline"), "Where craft meets quality")
        self.division = _s(co.get("division"), "JOINERY & FIT-OUT")
        self.signatory = _s(co.get("signatory"))
        vd = co.get("validity_days")
        self.validity = f"{fmt_qty(vd)} Days" if vd not in (None, "") else "15 Days"
        self.warranty = _s(co.get("warranty_short"), "2 Years")
        self.salutation = _s(m.get("salutation"), "Dear Sir / Madam,")
        letter = m.get("letter")
        if not isinstance(letter, list) or not any(str(p or "").strip() for p in letter):
            letter = [p.format(company=self.name_display) for p in DEFAULT_LETTER]
        self.letter = [_s(p) for p in letter if str(p or "").strip()]
        self.show_rates = bool(m.get("show_unit_rates"))
        self.contact = contact_line(co)
        self._styles()

    # -- paragraph styles ------------------------------------------------
    def _styles(self):
        f, b = self.f, self.b
        self.st = {
            "item_title": style("it", f.serif, 21, 24, b.ink),
            "desc": style("ds", f.sans_light, 9.3, 14.6, b.body),
            "bullet": style("bl", f.sans_light, 9.0, 13.6, b.body, leftIndent=12,
                            bulletIndent=0, bulletFontName=f.serif_bold, bulletFontSize=12,
                            bulletColor=b.accent, spaceAfter=2.5),
            "qty": style("qv", f.serif, 16, 19, b.ink),
            "amount": style("av", f.serif_bold, 17, 20, b.ink),
            "rate": style("rv", f.serif, 15, 19, b.ink),
            "cell_no": style("cn", f.serif_bold, 12.5, 15, b.accent),
            "cell_item": style("ci", f.sans_medium, 9.2, 12.4, b.ink),
            "cell_qty": style("cq", f.sans, 8.8, 12, b.ink, "center"),
            "cell_amt": style("ca", f.sans, 9.0, 12, b.ink, "right"),
            "tot_label": style("tl", f.sans_light, 8.8, 12, b.muted),
            "tot_value": style("tv", f.sans, 9.0, 12, b.ink, "right"),
            "grand_label": style("gl", f.serif, 16, 19, b.ink),
            "grand_value": style("gv", f.serif_bold, 21, 24, b.ink, "right"),
            "note": style("nt", f.sans_light, 8.0, 12, b.muted),
            "term_no": style("tn", f.serif_bold, 12.5, 14, b.accent),
            "term": style("tt", f.sans_light, 8.4, 12.6, b.body),
            "accept": style("ac", f.sans_light, 8.8, 13.2, b.body),
            "empty": style("em", f.sans_light, 9, 13, b.muted),
        }

    # -- scope helpers ---------------------------------------------------
    @staticmethod
    def item_no(item: dict, index: int) -> str:
        no = _s(item.get("no"))
        return no or f"{index + 1:02d}"

    @staticmethod
    def qty_text(item: dict) -> str:
        qd = _s(item.get("qty_display"))
        if qd:
            return qd
        qty = item.get("qty")
        unit = _s(item.get("unit"))
        if qty in (None, ""):
            return "1"
        return f"{fmt_qty(qty)} {unit}".strip()

    def rate_markup(self, item: dict) -> str:
        """'AED 400 / m²' with the currency and unit set small and muted."""
        rate = item.get("unit_rate")
        if rate in (None, ""):
            qty = to_num(item.get("qty"), 0.0)
            rate = to_num(item.get("amount")) / qty if qty else to_num(item.get("amount"))
        small = f'<font name="{self.f.sans}" size="8" color="#{_hex(self.b.muted)}">'
        unit = _s(item.get("unit"))
        text = f"{small}{esc(self.currency)}</font> {esc(fmt_money(rate, ''))}"
        return text + (f" {small}/ {esc(unit)}</font>" if unit else "")


# =========================================================================== cover
class _Cover(Flowable):
    """Page 1, laid out absolutely and scaled down if the content is long."""

    def __init__(self, q: _Ctx):
        super().__init__()
        self.q = q

    def wrap(self, availWidth, availHeight):
        self.width, self.height = availWidth, availHeight
        return availWidth, availHeight

    # tiles --------------------------------------------------------------
    def _tiles(self):
        m = self.q.meta
        tiles = m.get("cover_tiles")
        if tiles is None:  # derive from scope when the engine gave nothing
            tiles = [s.get("room") or s.get("title") for s in self.q.scope]
        tiles = [_s(t) for t in (tiles or []) if _s(t)][:4]
        images = m.get("cover_images") if isinstance(m.get("cover_images"), list) else []
        return [(t, load_image(images[i]) if i < len(images) else None)
                for i, t in enumerate(tiles)]

    def _tile_block_h(self, s: float, n: int) -> float:
        if not n:
            return 0.0
        tw = (self.width - (n - 1) * 12.0) / n
        th = min(112.0 * s, tw * 0.95)
        return th + 24.0

    # layout -------------------------------------------------------------
    def _layout(self, s: float, extra: float, draw: bool) -> float:
        """Lay out the top part; returns the height it used."""
        q, f, b, c = self.q, self.q.f, self.q.b, (self.canv if draw else None)
        W, top = self.width, self.height
        y = top

        # masthead: wordmark + tagline left, contact right, hairline
        if draw:
            draw_spaced(c, 0, y - 25, q.name, f.serif_bold, 27, b.ink, 5.0)
            c.setFont(f.serif_italic, 12.5)
            c.setFillColor(b.muted)
            c.drawString(1, y - 44, q.tagline)
            info = [q.company.get(k) for k in ("phone", "email", "website", "address")]
            info = [_s(v) for v in info if _s(v)]
            if _s(q.company.get("trn")):
                info.append("TRN " + _s(q.company.get("trn")))
            for i, line in enumerate(info[:4]):
                line = fit_text(line, f.sans_light, 7.4, W * 0.42)
                draw_spaced(c, W, y - 12 - i * 10.5, line, f.sans_light, 7.4, b.muted, 0.2,
                            "right")
            c.setStrokeColor(b.line)
            c.setLineWidth(0.6)
            c.line(0, y - 62, W, y - 62)
        y -= 62

        # label + reference
        y -= 38 * s + extra
        if draw:
            c.setStrokeColor(b.accent)
            c.setLineWidth(0.8)
            c.line(0, y - 3.2, 18, y - 3.2)
            draw_spaced(c, 28, y - 6.5, "QUOTATION", f.sans_medium, 8.6, b.accent, 6.2)
        y -= 8.6 + 9
        ref_line = f"REF {q.ref}" + (f"  ·  {q.date}" if q.date else "")
        if draw:
            draw_spaced(c, 28, y - 6.5, fit_text(ref_line, f.sans, 7.2, W - 28, 2.2), f.sans,
                        7.2, b.muted, 2.2)
        y -= 7.2

        # title + summary
        y -= 20 * s
        ts = max(24.0, 34.0 * s)
        title = Paragraph(esc(q.title), style("ct", f.serif, ts, ts * 1.1, b.ink))
        _, h = title.wrap(W * 0.86, 1000)
        if draw:
            title.drawOn(c, 0, y - h)
        y -= h
        if q.summary:
            y -= 12 * s
            ss = max(8.6, 10.0 * s)
            summ = Paragraph(esc(q.summary), style("cs", f.sans_light, ss, ss * 1.55, b.body))
            _, h = summ.wrap(W * 0.80, 1000)
            if draw:
                summ.drawOn(c, 0, y - h)
            y -= h

        # prepared for / quotation details
        y -= 32 * s + extra
        gutter = 44.0
        cw = (W - gutter) / 2.0
        x2 = cw + gutter
        if draw:
            for x, label in ((0, "PREPARED FOR"), (x2, "QUOTATION DETAILS")):
                draw_spaced(c, x, y - 7, label, f.sans_medium, 7.0, b.accent, 2.6)
                c.setStrokeColor(b.accent_soft)
                c.setLineWidth(0.6)
                c.line(x, y - 15, x + cw, y - 15)
        by = y - 15
        # left block
        ly = by - 9
        name_p = Paragraph(esc(q.client), style("cn", f.serif_bold, 18, 20.5, b.ink))
        _, h = name_p.wrap(cw, 200)
        if draw:
            name_p.drawOn(c, 0, ly - h)
        ly -= h + 4
        for text, font, col in ((q.project, f.sans, b.ink), (q.location, f.sans_light, b.muted)):
            if not text:
                continue
            p = Paragraph(esc(text), style("cp", font, 9.0, 13, col))
            _, h = p.wrap(cw, 200)
            if draw:
                p.drawOn(c, 0, ly - h)
            ly -= h + 1
        # right block
        rows = [("Date of Issue", q.date or "–"), ("Validity", q.validity),
                ("Warranty", q.warranty), ("Scope Items", f"{len(q.scope):02d}")]
        ry = by
        pitch = 18.0
        for key, val in rows:
            ry -= pitch
            if draw:
                c.setFont(f.sans_light, 8.4)
                c.setFillColor(b.muted)
                c.drawString(x2, ry + 5.5, key)
                val = fit_text(val, f.sans, 8.8, cw * 0.6)
                draw_spaced(c, x2 + cw, ry + 5.5, val, f.sans, 8.8, b.ink, 0.0, "right")
                c.setStrokeColor(b.line)
                c.setLineWidth(0.4)
                c.line(x2, ry, x2 + cw, ry)
        y = min(ly, ry)

        # covering letter
        y -= 30 * s + extra
        lw = W * 0.9
        ls = max(8.0, 9.2 * s)
        lead = ls * 1.56
        sal = Paragraph(esc(q.salutation), style("sa", f.sans, ls + 0.4, lead, b.ink))
        _, h = sal.wrap(lw, 200)
        if draw:
            sal.drawOn(c, 0, y - h)
        y -= h + 7 * s
        body_style = style("lt", f.sans_light, ls, lead, b.body)
        for para in q.letter:
            p = Paragraph(esc(para), body_style)
            _, h = p.wrap(lw, 1000)
            if draw:
                p.drawOn(c, 0, y - h)
            y -= h + 6 * s
        y -= 8 * s
        yf = Paragraph("Yours faithfully,", body_style)
        _, h = yf.wrap(lw, 100)
        if draw:
            yf.drawOn(c, 0, y - h)
        y -= h + 3
        sig = max(15.0, 20.0 * s)
        if draw:
            c.setFont(f.serif_italic, sig)
            c.setFillColor(b.ink)
            c.drawString(0, y - sig * 0.85, fit_text(q.name_display, f.serif_italic, sig, lw))
        y -= sig * 0.85 + 7
        if q.signatory:
            if draw:
                c.setFont(f.sans, 8.4)
                c.setFillColor(b.ink)
                c.drawString(0, y - 8, fit_text(q.signatory, f.sans, 8.4, lw))
            y -= 8 + 6
        if draw:
            draw_spaced(c, 0, y - 6.6, q.division, f.sans, 6.6, b.muted, 2.4)
        y -= 6.6
        return top - y

    def _draw_tiles(self, tiles, s: float):
        f, b, c = self.q.f, self.q.b, self.canv
        n = len(tiles)
        gap = 12.0
        tw = (self.width - (n - 1) * gap) / n
        th = self._tile_block_h(s, n) - 24.0
        y0 = 24.0
        for i, (label, img) in enumerate(tiles):
            x = i * (tw + gap)
            if img is not None:
                c.setFillColor(b.panel)
                c.rect(x, y0, tw, th, stroke=0, fill=1)
                draw_image(c, img, x, y0, tw, th, "cover")
            else:
                c.setFillColor(b.panel)
                c.rect(x, y0, tw, th, stroke=0, fill=1)
                c.setStrokeColor(b.accent_faint)
                c.setLineWidth(0.5)
                c.rect(x + 5, y0 + 5, tw - 10, th - 10, stroke=1, fill=0)
                num_size = min(46.0, th * 0.42)
                c.setFont(f.serif, num_size)
                c.setFillColor(b.accent_faint)
                c.drawCentredString(x + tw / 2.0, y0 + th / 2.0 - num_size * 0.32, f"{i + 1:02d}")
            c.setStrokeColor(b.line)
            c.setLineWidth(0.5)
            c.rect(x, y0, tw, th, stroke=1, fill=0)
            # caption: number + label
            num = f"{i + 1:02d}"
            draw_spaced(c, x, y0 - 14, num, f.serif_bold, 11.5, b.accent, 0.4)
            nw = spaced_width(num, f.serif_bold, 11.5, 0.4) + 7
            text = fit_text(label.upper(), f.sans_medium, 6.6, tw - nw, 1.8)
            draw_spaced(c, x + nw, y0 - 13, text, f.sans_medium, 6.6, b.ink, 1.8)

    def draw(self):
        tiles = self._tiles()
        H = self.height
        chosen = None
        for s in (1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7):
            need = self._layout(s, 0.0, False) + 26.0 + self._tile_block_h(s, len(tiles))
            if need <= H:
                chosen = s
                break
        if chosen is None:  # very long letter: drop the tiles before shrinking further
            tiles, chosen = [], 0.7
        need = self._layout(chosen, 0.0, False) + 26.0 + self._tile_block_h(chosen, len(tiles))
        extra = max(0.0, min((H - need) * 0.45, 54.0)) / 3.0
        self._layout(chosen, extra, True)
        if tiles:
            self._draw_tiles(tiles, chosen)


# =========================================================================== scope
class _ItemNumber(Flowable):
    """Large bronze item number with a hairline running to the room label."""

    def __init__(self, q: _Ctx, no: str, room: str):
        super().__init__()
        self.q, self.no, self.room = q, safe(no), safe(room).upper()

    def wrap(self, availWidth, availHeight):
        self.width, self.height = availWidth, 40.0
        return self.width, self.height

    def draw(self):
        f, b, c = self.q.f, self.q.b, self.canv
        c.setFont(f.serif, 40)
        c.setFillColor(b.accent)
        c.drawString(-1.5, 6, self.no)
        nw = pdfmetrics.stringWidth(self.no, f.serif, 40)
        ry = 6 + 12.5
        end = self.width
        if self.room:
            room = fit_text(self.room, f.sans, 6.6, self.width * 0.45, 2.2)
            rw = draw_spaced(c, self.width, ry - 2.4, room, f.sans, 6.6, b.muted, 2.2, "right")
            end = self.width - rw - 12
        c.setStrokeColor(b.line)
        c.setLineWidth(0.6)
        c.line(nw + 14, ry, max(nw + 14, end), ry)


class _ImageBox(Flowable):
    """Approved reference image, or an elegant empty frame labelled as such."""

    CAPTION = "APPROVED REFERENCE IMAGE"

    def __init__(self, q: _Ctx, path, width: float, height: float):
        super().__init__()
        self.q, self.img = q, load_image(path)
        self.box_w, self.box_h = width, height
        if self.img is not None:  # follow the photo's proportions, within limits
            iw, ih = self.img.getSize()
            self.box_h = max(width * 0.6, min(width * 1.3, width * ih / float(iw)))

    def wrap(self, availWidth, availHeight):
        self.width = min(self.box_w, availWidth)
        self.height = self.box_h + (18.0 if self.img is not None else 0.0)
        return self.width, self.height

    def draw(self):
        f, b, c = self.q.f, self.q.b, self.canv
        w, h = self.width, self.box_h
        y0 = self.height - h
        c.setFillColor(b.panel)
        c.rect(0, y0, w, h, stroke=0, fill=1)
        if self.img is not None:
            draw_image(c, self.img, 0, y0, w, h, "contain")
            c.setStrokeColor(b.line)
            c.setLineWidth(0.5)
            c.rect(0, y0, w, h, stroke=1, fill=0)
            draw_spaced(c, 0, 4, self.CAPTION, f.sans_medium, 6.2, b.muted, 2.2)
            return
        inset = 7.0
        c.setStrokeColor(b.accent_faint)
        c.setLineWidth(0.5)
        c.rect(inset, y0 + inset, w - 2 * inset, h - 2 * inset, stroke=1, fill=0)
        # corner marks
        c.setStrokeColor(b.accent)
        c.setLineWidth(0.8)
        m = 11.0
        for cx, cy, dx, dy in ((inset, y0 + inset, 1, 1), (w - inset, y0 + inset, -1, 1),
                               (inset, y0 + h - inset, 1, -1), (w - inset, y0 + h - inset, -1, -1)):
            c.line(cx, cy, cx + dx * m, cy)
            c.line(cx, cy, cx, cy + dy * m)
        # centred label
        lines = wrap_spaced("APPROVED\nREFERENCE IMAGE", f.sans_medium, 6.6, 2.6, w - 30)
        mid = y0 + h / 2.0
        c.setStrokeColor(b.accent)
        c.setLineWidth(0.7)
        c.line(w / 2.0 - 10, mid + 14, w / 2.0 + 10, mid + 14)
        for i, line in enumerate(lines):
            draw_spaced(c, w / 2.0, mid - 1 - i * 11, line, f.sans_medium, 6.6, b.muted, 2.6,
                        "center")


def _figures_table(q: _Ctx, item: dict, width: float) -> Table:
    f, b, st = q.f, q.b, q.st

    def lab(t):
        return SpacedText(t, f.sans_medium, 6.4, b.muted, 2.2)

    amount = item.get("amount")
    amount_markup = (f'<font name="{f.sans}" size="8" color="#{_hex(b.muted)}">'
                     f'{esc(q.currency)}</font> {esc(fmt_num(amount, 0 if _whole(amount) else 2))}')
    cells_l = [lab("QUANTITY")]
    cells_v = [Paragraph(esc(q.qty_text(item)), st["qty"])]
    widths = [0.34]
    if q.show_rates:
        cells_l.append(lab("RATE"))
        cells_v.append(Paragraph(q.rate_markup(item), st["rate"]))
        widths = [0.24, 0.38]
    cells_l.append(lab("AMOUNT"))
    cells_v.append(Paragraph(amount_markup, st["amount"]))
    widths.append(1.0 - sum(widths))
    t = Table([cells_l, cells_v], colWidths=[width * w for w in widths])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, 0), 9), ("BOTTOMPADDING", (0, 0), (-1, 0), 3),
        ("TOPPADDING", (0, 1), (-1, 1), 0), ("BOTTOMPADDING", (0, 1), (-1, 1), 0),
        ("LINEABOVE", (0, 0), (-1, 0), 0.6, b.line),
    ]))
    return t


def _whole(value) -> bool:
    x = to_num(value)
    return abs(x - round(x)) < 0.005


def _scope_flowables(q: _Ctx, item: dict, index: int, frame_h: float) -> list:
    f, b, st = q.f, q.b, q.st
    img_w = round(BODY_W * 0.40)
    gutter = 26.0
    left_w = BODY_W - img_w - gutter
    no = q.item_no(item, index)
    left = [Paragraph(esc(_s(item.get("title"), "Scope item")), st["item_title"])]
    subtitle = _s(item.get("subtitle"))
    if subtitle:
        left += [Spacer(1, 6), SpacedText(subtitle, f.sans_medium, 7.0, b.accent, 2.4)]
    desc = _s(item.get("description"))
    if desc:
        left += [Spacer(1, 11), Paragraph(esc(desc), st["desc"])]
    includes = [_s(x) for x in (item.get("includes") or []) if _s(x)]
    if includes:
        left += [Spacer(1, 13), SpacedText("SCOPE INCLUDES", f.sans_medium, 6.6, b.muted, 2.4,
                                           space_after=6)]
        left += [Paragraph(esc(x), st["bullet"], bulletText="•") for x in includes]
    left += [Spacer(1, 14), _figures_table(q, item, left_w)]
    image = _ImageBox(q, item.get("image"), img_w, round(img_w * 1.02))

    inner = Table([[left, "", image]], colWidths=[left_w, gutter, img_w])
    inner.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    number = _ItemNumber(q, no, _s(item.get("room")))
    outer = Table([[[number, Spacer(1, 12), inner]]], colWidths=[BODY_W])
    outer.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    outer.spaceBefore = 30
    _, h = outer.wrap(BODY_W, frame_h)
    if h <= frame_h - 2:
        return [outer]
    # Too tall for one page (extreme text): fall back to a splittable stack that
    # starts on a fresh page so it splits as little as possible.
    number.spaceBefore = 30
    stacked = [CondPageBreak(frame_h - 8), number, Spacer(1, 12)] + left[:-1]
    stacked += [Spacer(1, 12), KeepTogether([_figures_table(q, item, BODY_W), Spacer(1, 12),
                                             _ImageBox(q, item.get("image"), img_w,
                                                       round(img_w * 0.8))])]
    return stacked


# =========================================================================== summary
class _SignLine(Flowable):
    def __init__(self, q: _Ctx, label: str, value: str = ""):
        super().__init__()
        self.q, self.label, self.value = q, label, safe(value)

    def wrap(self, availWidth, availHeight):
        self.width, self.height = availWidth, 23.5
        return self.width, self.height

    def draw(self):
        f, b, c = self.q.f, self.q.b, self.canv
        draw_spaced(c, 0, 5, self.label, f.sans, 6.2, b.muted, 2.0)
        x = 64.0
        c.setStrokeColor(b.accent_soft)
        c.setLineWidth(0.6)
        c.line(x, 3, self.width, 3)
        if self.value:
            c.setFont(f.sans, 8.8)
            c.setFillColor(b.ink)
            c.drawString(x + 4, 7, fit_text(self.value, f.sans, 8.8, self.width - x - 6))


def _summary_flowables(q: _Ctx) -> list:
    f, b, st = q.f, q.b, q.st
    out: list = [TitleRow("Investment Summary", f.serif, 22, b.ink,
                          aside=f"ALL AMOUNTS IN {q.currency}", aside_font=f.sans_medium,
                          aside_size=6.6, aside_color=b.muted, aside_cs=2.2,
                          space_after=10)]

    def head(t, align="left"):
        return SpacedText(t, f.sans_medium, 6.4, b.muted, 2.0, align=align)

    widths = [36.0, BODY_W - 36.0 - 72.0 - 98.0, 72.0, 98.0]
    rows = [[head("NO"), head("ITEM"), head("QTY", "center"),
             head(f"AMOUNT ({q.currency})", "right")]]
    for i, item in enumerate(q.scope):
        title = esc(_s(item.get("title"), "Scope item"))
        line = _s(item.get("summary_line")) or _s(item.get("subtitle"))
        cell = title
        if line:
            cell += (f'<br/><font name="{f.sans_light}" size="8" color="#{_hex(b.muted)}">'
                     f"{esc(line)}</font>")
        rows.append([Paragraph(esc(q.item_no(item, i)), st["cell_no"]),
                     Paragraph(cell, st["cell_item"]),
                     Paragraph(esc(q.qty_text(item)), st["cell_qty"]),
                     Paragraph(esc(fmt_num(item.get("amount"), 2)), st["cell_amt"])])
    if not q.scope:
        rows.append(["", Paragraph("No scope items.", st["empty"]), "", ""])
    t = Table(rows, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("VALIGN", (0, 0), (-1, 0), "BOTTOM"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (1, 0), (1, -1), 12),
        ("TOPPADDING", (0, 0), (-1, 0), 0), ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
        ("TOPPADDING", (0, 1), (-1, -1), 5.5), ("BOTTOMPADDING", (0, 1), (-1, -1), 5.5),
        ("LINEBELOW", (0, 0), (-1, 0), 0.8, b.accent),
        ("LINEBELOW", (0, 1), (-1, -1), 0.4, b.line),
    ]))
    out.append(t)

    # totals ------------------------------------------------------------
    tot = q.totals
    subtotal = to_num(tot.get("subtotal"), sum(to_num(s.get("amount")) for s in q.scope))
    discount = to_num(tot.get("discount"))
    net = to_num(tot.get("net"), subtotal - discount)
    vat_pct = to_num(tot.get("vat_pct"), 5.0)
    vat = to_num(tot.get("vat"))
    vat_on = bool(tot.get("vat_registered", vat > 0))
    grand = to_num(tot.get("grand_total"), net + (vat if vat_on else 0.0))
    trs = [("Subtotal", fmt_num(subtotal))]
    if discount > 0:
        label = _s(tot.get("discount_label"))
        trs.append((f"Discount · {label}" if label else "Discount", "– " + fmt_num(discount)))
        trs.append(("Net Amount", fmt_num(net)))
    if vat_on:
        trs.append((f"VAT {fmt_qty(vat_pct)}%", fmt_num(vat)))
    tt = Table([[Paragraph(esc(k), st["tot_label"]), Paragraph(esc(v), st["tot_value"])]
                for k, v in trs], colWidths=[170.0, 98.0])
    tt.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, b.line),
    ]))
    # the inclusive-pricing note sits in the free space left of the subtotal rows
    note_w = BODY_W - 268.0 - 36.0
    totals_row = Table([[Paragraph(esc(INCLUSIVE_NOTE), st["note"]), "", tt]],
                       colWidths=[note_w, 36.0, 268.0])
    totals_row.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (0, 0), 5),
    ]))
    grand_left = [Paragraph("Total Project Amount", st["grand_label"])]
    if vat_on:
        grand_left += [Spacer(1, 3), SpacedText(f"INCLUSIVE OF {fmt_qty(vat_pct)}% VAT",
                                                f.sans_medium, 6.2, b.muted, 2.0)]
    gt = Table([[grand_left, Paragraph(esc(fmt_money(grand, q.currency)), st["grand_value"])]],
               colWidths=[BODY_W * 0.55, BODY_W * 0.45])
    gt.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BACKGROUND", (0, 0), (-1, -1), b.panel),
        ("LINEABOVE", (0, 0), (-1, 0), 1.0, b.accent),
        ("LEFTPADDING", (0, 0), (0, -1), 16), ("RIGHTPADDING", (-1, 0), (-1, -1), 16),
        ("TOPPADDING", (0, 0), (-1, -1), 9), ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
    ]))
    out.append(KeepTogether([Spacer(1, 6), totals_row, Spacer(1, 10), gt]))

    # terms -------------------------------------------------------------
    terms = []
    for term in q.terms:
        if isinstance(term, dict):
            title, text = _s(term.get("title")), _s(term.get("text"))
        else:
            title, text = "", _s(term)
        if title or text:
            terms.append((title, text))
    if terms:
        rows = []
        for i, (title, text) in enumerate(terms):
            body = ""
            if title:
                body = f'<font name="{f.sans_medium}" color="#{_hex(b.ink)}">{esc(title)}</font>'
                if text:
                    body += "&nbsp;&nbsp;–&nbsp; "
            body += esc(text)
            rows.append([Paragraph(f"{i + 1:02d}", st["term_no"]), Paragraph(body, st["term"])])

        def terms_table(part):
            tt = Table(part, colWidths=[32.0, BODY_W - 32.0])
            tt.setStyle(TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]))
            return tt

        # heading stays with the first term; the rest may flow onto the next page
        out.append(KeepTogether([
            TitleRow("Terms & Conditions", f.serif, 19, b.ink, rule_color=b.line,
                     space_before=18, space_after=9), terms_table(rows[:1])]))
        if len(rows) > 1:
            out.append(terms_table(rows[1:]))

    # acceptance --------------------------------------------------------
    col = (BODY_W - 44.0) / 2.0

    def block(label, name=""):
        return [SpacedText(label, f.sans_medium, 6.6, b.accent, 2.2, max_lines=2),
                Spacer(1, 4), _SignLine(q, "NAME", name), _SignLine(q, "SIGNATURE"),
                _SignLine(q, "DATE")]

    sig = Table([[block(f"FOR AND ON BEHALF OF {q.name}", q.signatory), "",
                  block("CLIENT ACCEPTANCE")]],
                colWidths=[col, 44.0, col])
    sig.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    out.append(KeepTogether([
        TitleRow("Acceptance", f.serif, 19, b.ink, rule_color=b.line, space_before=16,
                 space_after=8),
        Paragraph(esc(ACCEPTANCE_TEXT), st["accept"]), Spacer(1, 11), sig]))
    return out


def _hex(color) -> str:
    return "%02X%02X%02X" % (round(color.red * 255), round(color.green * 255),
                             round(color.blue * 255))


# =========================================================================== document
def render_quote(estimate: dict, out_path: str) -> str:
    """Render the client quotation PDF to ``out_path`` and return the path."""
    q = _Ctx(estimate)
    f, b = q.f, q.b
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)

    def background(c):
        c.saveState()
        c.setFillColor(b.paper)
        c.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
        c.restoreState()

    def header(c, right_1, right_2):
        draw_spaced(c, MX, HEADER_BASE, q.name, f.serif_bold, 16, b.ink, 3.4)
        c.setFont(f.serif_italic, 9.5)
        c.setFillColor(b.muted)
        c.drawString(MX + 0.5, HEADER_BASE - 14, q.tagline)
        draw_spaced(c, PAGE_W - MX, HEADER_BASE + 2, right_1, f.sans_medium, 7.0, b.accent, 2.6,
                    "right")
        draw_spaced(c, PAGE_W - MX, HEADER_BASE - 12,
                    fit_text(right_2, f.sans, 6.4, BODY_W * 0.5, 2.0), f.sans, 6.4, b.muted, 2.0,
                    "right")
        c.setStrokeColor(b.line)
        c.setLineWidth(0.6)
        c.line(MX, HEADER_RULE, PAGE_W - MX, HEADER_RULE)

    def on_cover(c, doc):
        background(c)

    def on_scope(c, doc):
        background(c)
        header(c, "SCOPE OF WORK", "PROJECT COST BREAKDOWN")

    def on_summary(c, doc):
        background(c)
        header(c, "SUMMARY & TERMS", f"QUOTATION {q.ref}")

    def furniture(c, page, total):
        c.saveState()
        draw_footer(c, MX, PAGE_W - MX, FOOT_TEXT_Y, f"{q.name} · QUOTATION {q.ref}",
                    f"PAGE {page} OF {total}", f.sans, 6.4, b.muted, 2.0,
                    rule_color=b.line, rule_y=FOOT_RULE_Y,
                    center=q.contact if page > 1 else "", center_font=f.sans_light,
                    center_size=6.6)
        c.restoreState()

    cover_frame = Frame(MX, BODY_BOTTOM, BODY_W, COVER_TOP - BODY_BOTTOM, 0, 0, 0, 0, id="cover")
    body_h = BODY_TOP - BODY_BOTTOM

    def body_frame(fid):
        return Frame(MX, BODY_BOTTOM, BODY_W, body_h, 0, 0, 0, 0, id=fid)

    doc = BaseDocTemplate(
        out_path, pagesize=A4, leftMargin=MX, rightMargin=MX, topMargin=PAGE_H - BODY_TOP,
        bottomMargin=BODY_BOTTOM, title=f"Quotation {q.ref} · {q.title}",
        author=q.name_display, subject=q.project or q.title, creator="NexaFix costing tool")
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[cover_frame], onPage=on_cover),
        PageTemplate(id="scope", frames=[body_frame("scope")], onPage=on_scope),
        PageTemplate(id="summary", frames=[body_frame("summary")], onPage=on_summary),
    ])

    story: list = [NextPageTemplate("scope" if q.scope else "summary"), _Cover(q), PageBreak()]
    if q.scope:
        for i, item in enumerate(q.scope):
            story += _scope_flowables(q, item, i, body_h)
        story += [NextPageTemplate("summary"), PageBreak()]
    story += _summary_flowables(q)
    doc.build(story, canvasmaker=numbered_canvas(furniture))
    return out_path
