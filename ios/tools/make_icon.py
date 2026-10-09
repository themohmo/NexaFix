#!/usr/bin/env python3
"""Generate the NexaFix Scan app icon (1024x1024 PNG, no transparency, no rounded corners:
iOS applies its own mask). Run:  python3 ios/tools/make_icon.py

The mark is a room corner seen from above: two bronze wall strokes meeting at a right angle,
a small interior-angle arc and a dimension line with end ticks. It says "plan, corner, measure"
without any literal ruler or camera clip-art.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
SS = 4                      # supersampling for clean anti-aliased edges
INK = (31, 29, 26)          # #1F1D1A
INK_2 = (44, 41, 37)        # slightly lighter, for the vignette
BRONZE = (156, 123, 82)     # #9C7B52
PAPER = (251, 248, 243)     # #FBF8F3

W = S * SS
img = Image.new("RGB", (W, W), INK)
d = ImageDraw.Draw(img)

# soft radial lift behind the mark so the icon is not a flat slab
cx0, cy0 = W * 0.42, W * 0.42
for r in range(int(W * 0.75), 0, -int(W * 0.004)):
    t = r / (W * 0.75)
    c = tuple(int(INK[i] + (INK_2[i] - INK[i]) * (1 - t) ** 1.6) for i in range(3))
    d.ellipse([cx0 - r, cy0 - r, cx0 + r, cy0 + r], fill=c)

OFFSET = (16, 62)           # centres the mark's bounding box on the canvas

def P(x, y):                # design coordinates are 0..1000
    return ((x + OFFSET[0]) / 1000 * W, (y + OFFSET[1]) / 1000 * W)

wall = int(58 / 1000 * W)
# the corner: vertical wall down the left, horizontal wall along the bottom
x0, y0 = 250, 690           # corner point (inside edge)
top, right = 250, 770
d.line([P(x0, top), P(x0, y0)], fill=BRONZE, width=wall)
d.line([P(x0, y0), P(right, y0)], fill=BRONZE, width=wall)
# square the outer end of the join
d.rectangle([P(x0 - 29, y0 - 29), P(x0 + 29, y0 + 29)], fill=BRONZE)

# interior-angle arc inside the corner
arc_r = 135
acx, acy = x0 + 29, y0 - 29          # inside corner of the two walls
bbox = [P(acx - arc_r, acy - arc_r), P(acx + arc_r, acy + arc_r)]
d.arc([bbox[0][0], bbox[0][1], bbox[1][0], bbox[1][1]], start=270, end=360, fill=PAPER, width=int(16 / 1000 * W))

# dimension line along the top, with end ticks, floating above the horizontal wall
dy = 215
d.line([P(x0 - 29, dy), P(right, dy)], fill=PAPER, width=int(12 / 1000 * W))
for tx in (x0 - 29, right):
    d.line([P(tx, dy - 34), P(tx, dy + 34)], fill=PAPER, width=int(12 / 1000 * W))
# a small gap-and-dot in the middle of the dimension line (where the number would sit)
mid = (x0 - 29 + right) / 2
d.rectangle([P(mid - 52, dy - 12), P(mid + 52, dy + 12)], fill=INK_2)
for k in (-26, 0, 26):
    r = 7
    cxp, cyp = P(mid + k, dy)
    d.ellipse([cxp - r * SS * 1.0, cyp - r * SS * 1.0, cxp + r * SS * 1.0, cyp + r * SS * 1.0], fill=PAPER)

out = img.resize((S, S), Image.LANCZOS)
dest = Path(__file__).resolve().parent.parent / "NexaFixScan/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
dest.parent.mkdir(parents=True, exist_ok=True)
out.save(dest, "PNG", optimize=True)
print("wrote", dest, out.size)
