"""Shared helpers for the NexaFix PDF renderers (reportlab only).

Fonts, brand colours, number formatting, text sanitising, letter-spaced
labels, image helpers and a page-numbering canvas used by both
``quote_pdf`` (client quotation) and ``costsheet_pdf`` (internal cost sheet).
"""
from __future__ import annotations

import math
import os
import unicodedata
from xml.sax.saxutils import escape as _xml_escape

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.platypus import Flowable

__all__ = [
    "FONT_DIR", "Fonts", "get_fonts", "Brand", "mix", "to_num", "fmt_num",
    "fmt_money", "fmt_qty", "fmt_pct", "safe", "esc", "style", "spaced_width",
    "draw_spaced", "wrap_spaced", "fit_text", "SpacedText", "TitleRow",
    "load_image", "draw_image", "numbered_canvas", "draw_footer",
    "contact_line", "display_name",
]

FONT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "fonts"))

# role -> (registered name, ttf file, built-in fallback)
_FONT_TABLE = {
    "serif": ("NF-Serif", "CormorantGaramond-Medium.ttf", "Times-Roman"),
    "serif_bold": ("NF-Serif-SemiBold", "CormorantGaramond-SemiBold.ttf", "Times-Bold"),
    "serif_italic": ("NF-Serif-Italic", "CormorantGaramond-MediumItalic.ttf", "Times-Italic"),
    "sans_light": ("NF-Sans-Light", "Jost-Light.ttf", "Helvetica"),
    "sans": ("NF-Sans", "Jost-Regular.ttf", "Helvetica"),
    "sans_medium": ("NF-Sans-Medium", "Jost-Medium.ttf", "Helvetica-Bold"),
    "sans_bold": ("NF-Sans-SemiBold", "Jost-SemiBold.ttf", "Helvetica-Bold"),
}


# --------------------------------------------------------------------------- fonts
class Fonts:
    """Resolved font names by role. ``charset`` is the set of code points every
    loaded TTF can draw (``None`` when running on the built-in fallbacks)."""

    def __init__(self):
        self.serif = self.serif_bold = self.serif_italic = "Times-Roman"
        self.sans_light = self.sans = self.sans_medium = self.sans_bold = "Helvetica"
        self.charset: set[int] | None = None
        self.embedded = False


_FONTS: Fonts | None = None
_DIGIT_NAMES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]


def _post_glyph_ids(path: str, wanted: set[str]) -> dict[str, int]:
    """Glyph ids for named glyphs, read from a TrueType 'post' table (format 2)."""
    import struct
    with open(path, "rb") as fh:
        data = fh.read()
    num_tables = struct.unpack(">H", data[4:6])[0]
    off = length = None
    for i in range(num_tables):
        tag, _, t_off, t_len = struct.unpack(">4sLLL", data[12 + 16 * i: 28 + 16 * i])
        if tag == b"post":
            off, length = t_off, t_len
            break
    if off is None or struct.unpack(">L", data[off:off + 4])[0] != 0x00020000:
        return {}
    p = off + 32
    count = struct.unpack(">H", data[p:p + 2])[0]
    p += 2
    index = struct.unpack(">%dH" % count, data[p:p + 2 * count])
    p += 2 * count
    names, end = [], off + length
    while p < end:
        n = data[p]
        names.append(data[p + 1:p + 1 + n].decode("latin-1"))
        p += 1 + n
    found = {}
    for gid, ni in enumerate(index):
        if ni >= 258 and ni - 258 < len(names) and names[ni - 258] in wanted:
            found[names[ni - 258]] = gid
    return found


def _use_lining_figures(font_name: str, path: str) -> None:
    """Cormorant defaults to old-style figures ('01' reads as 'OI'). reportlab
    cannot apply the OpenType 'lnum' feature, so point the digit code points at
    the font's own lining glyphs (zero.lf ...). Silently skipped if absent."""
    try:
        face = pdfmetrics.getFont(font_name).face
        ids = _post_glyph_ids(path, {d + ".lf" for d in _DIGIT_NAMES})
        if len(ids) != 10:
            return
        ref_gid = face.charToGlyph[ord("0")]
        scale = face.charWidths[ord("0")] / float(face.hmetrics[ref_gid][0])
        for i, name in enumerate(_DIGIT_NAMES):
            gid = ids[name + ".lf"]
            face.charToGlyph[48 + i] = gid
            face.charWidths[48 + i] = face.hmetrics[gid][0] * scale
    except Exception:
        return


def get_fonts(font_dir: str | None = None) -> Fonts:
    """Register the brand TTFs once (falling back per font to Times/Helvetica)."""
    global _FONTS
    if _FONTS is not None and font_dir is None:
        return _FONTS
    fonts = Fonts()
    directory = font_dir or FONT_DIR
    charset: set[int] | None = None
    loaded: dict[str, bool] = {}
    for role, (name, filename, fallback) in _FONT_TABLE.items():
        path = os.path.join(directory, filename)
        ok = False
        if os.path.isfile(path):
            try:
                if name not in pdfmetrics.getRegisteredFontNames():
                    pdfmetrics.registerFont(TTFont(name, path))
                    if role.startswith("serif"):
                        _use_lining_figures(name, path)
                font = pdfmetrics.getFont(name)
                cmap = set(getattr(font.face, "charToGlyph", {}).keys())
                charset = cmap if charset is None else (charset & cmap)
                ok = True
            except Exception:  # corrupt / unreadable font -> fallback
                ok = False
        setattr(fonts, role, name if ok else fallback)
        loaded[role] = ok
    fonts.charset = charset
    fonts.embedded = any(loaded.values())
    # Family mappings so <b>/<i> inside Paragraph markup resolve sensibly.
    if loaded.get("sans"):
        pdfmetrics.registerFontFamily(fonts.sans, normal=fonts.sans, bold=fonts.sans_bold,
                                      italic=fonts.sans, boldItalic=fonts.sans_bold)
    if loaded.get("sans_light"):
        pdfmetrics.registerFontFamily(fonts.sans_light, normal=fonts.sans_light,
                                      bold=fonts.sans_medium, italic=fonts.sans_light,
                                      boldItalic=fonts.sans_medium)
    if loaded.get("sans_medium"):
        pdfmetrics.registerFontFamily(fonts.sans_medium, normal=fonts.sans_medium,
                                      bold=fonts.sans_bold, italic=fonts.sans_medium,
                                      boldItalic=fonts.sans_bold)
    if loaded.get("serif"):
        pdfmetrics.registerFontFamily(fonts.serif, normal=fonts.serif, bold=fonts.serif_bold,
                                      italic=fonts.serif_italic, boldItalic=fonts.serif_bold)
    if font_dir is None:
        _FONTS = fonts
    return fonts


# --------------------------------------------------------------------------- text
_REPLACEMENTS = {
    " ": " ", " ": " ", " ": " ", " ": " ", " ": " ",
    "​": "", "﻿": "", "‐": "-", "‑": "-", "‒": "–",
    "―": "—", "→": "-", "←": "-", "↔": "-", "⇒": "-",
    "≤": "<=", "≥": ">=", "≈": "~", "≠": "!=", "✓": "",
    "✔": "", "✗": "x", "●": "•", "▪": "•", "■": "•",
    "‣": "•", "⁃": "-", "′": "'", "″": '"', "×": "×",
    "✕": "×", "✖": "×", "₂": "2", "³": "³",
}
_CHAR_CACHE: dict[str, str] = {}


def _supported(ch: str) -> bool:
    fonts = get_fonts()
    if fonts.charset is not None:
        return ord(ch) in fonts.charset
    try:
        ch.encode("cp1252")
        return True
    except UnicodeEncodeError:
        return False


def _map_char(ch: str) -> str:
    if ch in _CHAR_CACHE:
        return _CHAR_CACHE[ch]
    if ch in "\n\t" or _supported(ch):
        out = ch
    else:
        rep = _REPLACEMENTS.get(ch)
        if rep is not None and all(_supported(c) for c in rep):
            out = rep
        else:
            decomposed = unicodedata.normalize("NFKD", ch)
            out = "".join(c for c in decomposed if _supported(c) and not unicodedata.combining(c))
            if not out and rep:
                out = "".join(c for c in rep if _supported(c))
    _CHAR_CACHE[ch] = out
    return out


def safe(text) -> str:
    """Plain text limited to glyphs the embedded fonts can draw."""
    if text is None:
        return ""
    if not isinstance(text, str):
        text = str(text)
    if text.isascii():
        return text
    return "".join(_map_char(ch) for ch in text)


def esc(text) -> str:
    """Sanitise + escape text for reportlab Paragraph markup."""
    s = _xml_escape(safe(text))
    return s.replace("\r\n", "\n").replace("\n", "<br/>")


def display_name(name: str) -> str:
    """'NEXA FIX' -> 'Nexa Fix' (keeps LLC / FZE style suffixes upper-case)."""
    name = safe(name).strip()
    if not name or not name.isupper():
        return name
    keep = {"LLC", "L.L.C", "L.L.C.", "FZE", "FZC", "FZCO", "FZ-LLC", "DMCC", "LTD", "UAE", "&"}
    return " ".join(w if w in keep else w.capitalize() for w in name.split())


# --------------------------------------------------------------------------- numbers
def to_num(value, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        f = float(str(value).replace(",", "")) if isinstance(value, str) else float(value)
    except (TypeError, ValueError):
        return default
    if math.isnan(f) or math.isinf(f):
        return default
    return f


def fmt_num(value, decimals: int = 2) -> str:
    """12500 -> '12,500.00'."""
    x = round(to_num(value), decimals)
    if x == 0:
        x = 0.0  # avoid '-0.00'
    return f"{x:,.{decimals}f}"


def fmt_money(value, currency: str = "AED", decimals: int | None = None) -> str:
    """12500 -> 'AED 12,500'; 2472.5 -> 'AED 2,472.50' (decimals=None: auto)."""
    x = to_num(value)
    if decimals is None:
        decimals = 0 if abs(x - round(x)) < 0.005 else 2
    s = fmt_num(x, decimals)
    return f"{currency} {s}".strip() if currency else s


def fmt_qty(value, max_decimals: int = 2) -> str:
    """1.0 -> '1', 131.9 -> '131.9', 0.333 -> '0.33'."""
    x = to_num(value)
    if abs(x - round(x)) < 1e-9:
        return f"{int(round(x)):,}"
    s = f"{x:,.{max_decimals}f}".rstrip("0").rstrip(".")
    return s


def fmt_pct(value, decimals: int = 1) -> str:
    return f"{to_num(value):.{decimals}f}%"


# --------------------------------------------------------------------------- colours
def _parse_color(value, default: str) -> Color:
    for candidate in (value, default):
        if not candidate or not isinstance(candidate, str):
            continue
        h = candidate.strip().lstrip("#")
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) == 6:
            try:
                int(h, 16)
                return HexColor("#" + h)
            except ValueError:
                continue
    return HexColor(default)


def mix(a: Color, b: Color, t: float) -> Color:
    """Blend colour a toward b by t (0 = a, 1 = b)."""
    return Color(a.red + (b.red - a.red) * t,
                 a.green + (b.green - a.green) * t,
                 a.blue + (b.blue - a.blue) * t)


class Brand:
    """Brand palette from ``estimate['company']['brand']`` plus derived tones."""

    DEFAULTS = {"ink": "#1F1D1A", "accent": "#9C7B52", "paper": "#FBF8F3",
                "line": "#DDD3C4", "muted": "#7A7268"}

    def __init__(self, brand: dict | None = None):
        b = brand if isinstance(brand, dict) else {}
        self.ink = _parse_color(b.get("ink"), self.DEFAULTS["ink"])
        self.accent = _parse_color(b.get("accent"), self.DEFAULTS["accent"])
        self.paper = _parse_color(b.get("paper"), self.DEFAULTS["paper"])
        self.line = _parse_color(b.get("line"), self.DEFAULTS["line"])
        self.muted = _parse_color(b.get("muted"), self.DEFAULTS["muted"])
        white = HexColor("#FFFFFF")
        self.white = white
        self.body = mix(self.ink, self.paper, 0.12)          # soft ink for long text
        self.panel = mix(self.paper, self.line, 0.38)        # placeholder panels / bands
        self.panel_soft = mix(self.paper, self.line, 0.18)
        self.accent_soft = mix(self.accent, self.paper, 0.55)
        self.accent_faint = mix(self.accent, self.paper, 0.80)
        self.zebra = mix(self.paper, white, 0.25)
        self.head_bg = mix(self.line, white, 0.45)
        # functional colours for the internal sheet
        self.green = HexColor("#2F7A4B")
        self.amber = HexColor("#B26A00")
        self.red = HexColor("#B3261E")
        self.green_bg = HexColor("#E6F2EA")
        self.amber_bg = HexColor("#FCF0D9")
        self.red_bg = HexColor("#F9E1DE")


# --------------------------------------------------------------------------- styles
def style(name: str, font: str, size: float, leading: float | None = None, color=None,
          align: str = "left", **kw) -> ParagraphStyle:
    alignment = {"left": TA_LEFT, "right": TA_RIGHT, "center": TA_CENTER}.get(align, TA_LEFT)
    return ParagraphStyle(name, fontName=font, fontSize=size,
                          leading=leading if leading is not None else size * 1.3,
                          textColor=color, alignment=alignment, **kw)


# --------------------------------------------------------------------------- letter-spacing
def spaced_width(text: str, font: str, size: float, char_space: float = 0.0) -> float:
    """Visual width of text drawn with charSpace (no trailing space counted)."""
    if not text:
        return 0.0
    return pdfmetrics.stringWidth(text, font, size) + char_space * (len(text) - 1)


def draw_spaced(c, x: float, y: float, text, font: str, size: float, color=None,
                char_space: float = 0.0, align: str = "left") -> float:
    """Draw letter-spaced text; x is the left/centre/right anchor. Returns width."""
    text = safe(text)
    w = spaced_width(text, font, size, char_space)
    if align == "right":
        x -= w
    elif align == "center":
        x -= w / 2.0
    c.setFont(font, size)
    if color is not None:
        c.setFillColor(color)
    c.drawString(x, y, text, charSpace=char_space)
    return w


def _break_word(word: str, font: str, size: float, cs: float, width: float) -> list[str]:
    parts, cur = [], ""
    for ch in word:
        if cur and spaced_width(cur + ch, font, size, cs) > width:
            parts.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        parts.append(cur)
    return parts


def wrap_spaced(text, font: str, size: float, char_space: float, width: float) -> list[str]:
    """Greedy word wrap for letter-spaced text."""
    text = safe(text)
    lines: list[str] = []
    for para in text.split("\n"):
        cur = ""
        for word in para.split():
            trial = f"{cur} {word}" if cur else word
            if spaced_width(trial, font, size, char_space) <= width:
                cur = trial
                continue
            if cur:
                lines.append(cur)
            if spaced_width(word, font, size, char_space) > width:
                chunks = _break_word(word, font, size, char_space, width)
                lines.extend(chunks[:-1])
                cur = chunks[-1] if chunks else ""
            else:
                cur = word
        lines.append(cur)
    return [ln for ln in lines if ln] or [""]


def fit_text(text, font: str, size: float, width: float, char_space: float = 0.0) -> str:
    """Truncate with an ellipsis so the text fits the given width."""
    text = safe(text)
    if spaced_width(text, font, size, char_space) <= width:
        return text
    ell = "…" if _supported("…") else "..."
    while text and spaced_width(text + ell, font, size, char_space) > width:
        text = text[:-1]
    return text.rstrip() + ell if text else ""


class SpacedText(Flowable):
    """Letter-spaced (usually upper-case) label that wraps within its width."""

    def __init__(self, text, font: str, size: float, color=None, char_space: float = 2.0,
                 align: str = "left", leading: float | None = None, upper: bool = True,
                 space_before: float = 0.0, space_after: float = 0.0,
                 max_lines: int | None = None):
        super().__init__()
        text = safe(text or "")
        self.text = text.upper() if upper else text
        self.font, self.size, self.color = font, size, color
        self.cs, self.align = char_space, align
        self.leading = leading if leading is not None else size * 1.45
        self.spaceBefore, self.spaceAfter = space_before, space_after
        self.max_lines = max_lines
        self._lines: list[str] = []

    def wrap(self, availWidth, availHeight):
        self.width = availWidth
        lines = wrap_spaced(self.text, self.font, self.size, self.cs, max(availWidth, 1))
        if self.max_lines and len(lines) > self.max_lines:
            lines = lines[: self.max_lines]
            lines[-1] = fit_text(lines[-1] + " …", self.font, self.size, availWidth, self.cs)
        self._lines = lines
        self.height = self.leading * len(lines) - (self.leading - self.size) + 1.0
        return self.width, self.height

    def draw(self):
        c = self.canv
        y = self.height - self.size
        for line in self._lines:
            x = {"left": 0.0, "center": self.width / 2.0, "right": self.width}.get(self.align, 0.0)
            draw_spaced(c, x, y + 1.0, line, self.font, self.size, self.color, self.cs, self.align)
            y -= self.leading


class TitleRow(Flowable):
    """Serif section title with an optional letter-spaced aside on the right,
    sharing one baseline, and an optional hairline beneath."""

    def __init__(self, title, font: str, size: float, color, aside: str = "",
                 aside_font: str | None = None, aside_size: float = 6.8, aside_color=None,
                 aside_cs: float = 2.0, rule_color=None, rule_width: float = 0.5,
                 rule_gap: float = 7.0, space_before: float = 0.0, space_after: float = 0.0):
        super().__init__()
        self.title = safe(title)
        self.font, self.size, self.color = font, size, color
        self.aside = safe(aside).upper()
        self.aside_font = aside_font or font
        self.aside_size, self.aside_color, self.aside_cs = aside_size, aside_color, aside_cs
        self.rule_color, self.rule_width, self.rule_gap = rule_color, rule_width, rule_gap
        self.spaceBefore, self.spaceAfter = space_before, space_after

    def wrap(self, availWidth, availHeight):
        self.width = availWidth
        aside_w = spaced_width(self.aside, self.aside_font, self.aside_size, self.aside_cs)
        self._title = fit_text(self.title, self.font, self.size,
                               availWidth - (aside_w + 16 if aside_w else 0))
        rule = (self.rule_gap + self.rule_width) if self.rule_color is not None else 0.0
        self._base = rule + self.size * 0.25
        self.height = self._base + self.size * 0.92
        return self.width, self.height

    def draw(self):
        c = self.canv
        c.setFillColor(self.color)
        c.setFont(self.font, self.size)
        c.drawString(0, self._base, self._title)
        if self.aside:
            draw_spaced(c, self.width, self._base, self.aside, self.aside_font, self.aside_size,
                        self.aside_color, self.aside_cs, "right")
        if self.rule_color is not None:
            c.setStrokeColor(self.rule_color)
            c.setLineWidth(self.rule_width)
            c.line(0, self.rule_width / 2.0, self.width, self.rule_width / 2.0)


# --------------------------------------------------------------------------- images
def load_image(path):
    """Return an ImageReader for a readable local image path, else None."""
    if not path or not isinstance(path, str):
        return None
    p = os.path.expanduser(path.strip())
    if not os.path.isfile(p):
        return None
    try:
        img = ImageReader(p)
        w, h = img.getSize()
        if not w or not h:
            return None
        return img
    except Exception:
        return None


def draw_image(c, img, x: float, y: float, w: float, h: float, mode: str = "contain") -> None:
    """Draw an ImageReader into a box. 'contain' letterboxes, 'cover' crops."""
    iw, ih = img.getSize()
    scale = (min if mode == "contain" else max)(w / float(iw), h / float(ih))
    dw, dh = iw * scale, ih * scale
    dx, dy = x + (w - dw) / 2.0, y + (h - dh) / 2.0
    c.saveState()
    if mode == "cover":
        p = c.beginPath()
        p.rect(x, y, w, h)
        c.clipPath(p, stroke=0, fill=0)
    c.drawImage(img, dx, dy, dw, dh, mask="auto")
    c.restoreState()


# --------------------------------------------------------------------------- pages
def numbered_canvas(draw_page_furniture):
    """Canvas class that defers ``draw_page_furniture(canvas, page, total)`` until
    the whole document is laid out, so footers can say 'PAGE x OF y'."""

    class _NumberedCanvas(rl_canvas.Canvas):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._nf_pages: list[dict] = []

        def showPage(self):
            self._nf_pages.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total = len(self._nf_pages)
            for number, state in enumerate(self._nf_pages, start=1):
                self.__dict__.update(state)
                draw_page_furniture(self, number, total)
                super().showPage()
            super().save()

    return _NumberedCanvas


def draw_footer(c, x0: float, x1: float, y: float, left: str, right: str, font: str,
                size: float, color, char_space: float = 1.8, rule_color=None,
                rule_y: float | None = None, center: str = "", center_font: str | None = None,
                center_size: float | None = None) -> None:
    if rule_color is not None and rule_y is not None:
        c.setStrokeColor(rule_color)
        c.setLineWidth(0.5)
        c.line(x0, rule_y, x1, rule_y)
    lw = draw_spaced(c, x0, y, left, font, size, color, char_space, "left")
    rw = draw_spaced(c, x1, y, right, font, size, color, char_space, "right")
    if center:
        cf = center_font or font
        cs_ = center_size or size
        cw = pdfmetrics.stringWidth(safe(center), cf, cs_)
        mid = (x0 + x1) / 2.0
        if mid - cw / 2.0 > x0 + lw + 14 and mid + cw / 2.0 < x1 - rw - 14:
            draw_spaced(c, mid, y, center, cf, cs_, color, 0.0, "center")


def contact_line(company: dict, sep: str = "  ·  ") -> str:
    company = company or {}
    parts = [company.get(k) for k in ("phone", "email", "website", "address")]
    parts = [safe(p).strip() for p in parts if p and str(p).strip()]
    trn = str(company.get("trn") or "").strip()
    if trn:
        parts.append(f"TRN {safe(trn)}")
    return sep.join(parts)
