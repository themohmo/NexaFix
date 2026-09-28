# Intake — turning property info into a spec

Goal: a spec good enough to price, with the fewest questions. Extract what
you can, default the rest, list the assumptions, ask only about the
things that swing the price.

## 1. Reading the property

**Floor plan (image / PDF).** For each room read the dimension strings
(usually mm or m, sometimes ft-in on older Dubai plans: 12'6" = 3.81 m).
Record `length` × `width`; for L-shaped rooms split into two rectangles or
use `area` + `perimeter`. Note windows (full-height glazing in towers
matters for painting and curtains), door positions (skirting and
thresholds), wet rooms, balconies (outdoor, excluded from `all`/`dry`).
If the plan shows total area only, check it against the room sum; brochure
areas include walls and balconies (~10–15% more than carpet area).

**Brochure / listing ("2BR, 1,250 sqft, JVC").** Use `typology` +
`total_area` (sqft is fine: `"1250 sqft"`). This is a rough budget: say so.

**Photos / site visit notes.** Look for existing floor finish (removal?),
ceiling type (existing gypsum? cove?), wall condition (paint prep level),
socket positions, window sizes for curtains.

**Client brief / WhatsApp list.** Map every noun to an item type
(`references/spec-format.md`). Words like "full apartment", "all rooms",
"whole unit" → room selectors (`dry`, `all`).

## 2. Defaults when the brief is silent

| Item | Default used | Ask if… |
|---|---|---|
| Ceiling height | 2.8 m (towers 2.7–3.0; villas 3.0–3.3) | villa or double-height space |
| Flooring rooms | all dry indoor rooms (living, bedrooms, kitchen, corridor) | kitchen or bathrooms should differ |
| Skirting | yes, PVC 80 mm with SPC | — |
| Wall cladding height | room height (floor to ceiling) | "half wall" or wainscot mentioned |
| Cladding lighting | none unless mentioned; "with lighting" → one LED run the wall width | — |
| TV unit | 2.4 m wide, floating base 400 mm high with 2 drawers, back panel full height, 2 floating shelves 1.2 m with LED | TV size / wall width unknown and it matters |
| Wardrobe | floor-to-ceiling 2.6 m, 600 deep, hinged doors ≤ 500 mm, 60% hanging | width unknown — **always ask or measure**, it drives the price |
| Kitchen | base 870 incl. plinth, wall units 720, quartz top | run length unknown — ask |
| Vanity | floating 550 H x 500 D, 2 drawers, MR-MDF | width |
| Nightstands | pair, 500 × 450 × 400, floating, 1 drawer | — |
| Headboard | 2.0 × 1.2 m, plain upholstery | style (channel/tufted adds hours) |
| Mirror | clear 5 mm, polished edge | size |
| Sockets | new points, 13 A double | relocate vs new (price differs) |
| Cove lighting | room perimeter, 24 V 10 W/m 3000K, no gypsum work | whether the gypsum cove exists or must be built |
| Painting | walls only, light prep, 1 primer + 2 coats | ceilings too? occupied (furniture)? |
| Finish board | Egger MFC 18 mm (laminate) | lacquer/acrylic/veneer requested (big cost swing) |

## 3. Questions worth asking (one message, only if missing)

1. Wardrobe / kitchen / TV wall **widths** (the largest price drivers).
2. Joinery **finish**: laminate (Egger) vs lacquered vs acrylic vs veneer.
3. Is the flooring going over existing tiles (no removal) or does it need removal/levelling?
4. Cove lighting: existing gypsum cove, or build new?
5. Building: tower (NOC fee, lift booking) or villa? Occupied or vacant?

Everything else: assume, list it under **Assumptions**, and let the owner correct.

## 4. Sanity bands (flag if outside — not hard rules)

Indicative Dubai **selling** prices, 2025–26, supply & install, ex VAT:

| Item | Typical range |
|---|---|
| SPC flooring (mid-range) | AED 60–120 per m² (owner's own pricing may be higher) |
| Porcelain 60×60 | AED 110–180 per m² |
| Gypsum partition (2 sides) | AED 85–140 per m² |
| Gypsum ceiling flat | AED 55–95 per m² |
| Cove incl. LED | AED 150–250 per lm |
| Painting walls (2 coats) | AED 12–30 per m² |
| WPC fluted cladding | AED 200–350 per m² |
| PVC marble cladding | AED 180–300 per m² |
| MFC wardrobe | AED 1,500–2,800 per lm |
| Lacquered wardrobe | AED 2,500–4,500 per lm |
| TV unit / media wall | AED 4,000–15,000 each |
| New socket point | AED 250–500 per point |
| Mirror clear, polished | AED 250–450 per m² (minimum AED 350) |

If a line lands far outside, check the inputs (mm vs m, count vs length)
before questioning the rate book.
