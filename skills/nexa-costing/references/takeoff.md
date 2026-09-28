# Take-off formulas

What the engine calculates for each item. Every line in the cost sheet
carries its own `calc` string, so the owner can trace any number. All
parameters named here are in `rates.toml` and can be tuned.

## Flooring & tiles
- Area A = Σ room areas (or `area`).
- Units = A × (1 + waste% + pattern extra%) ÷ unit area.
  SPC 1800 × 180 = 0.324 m²/plank → 42.5 m² × 1.08 ÷ 0.324 = 141.7 planks.
  Pattern extra: diagonal +6%, herringbone +11%; labour × 1.25 / × 1.6.
- Skirting lm = Σ dry-room perimeters − door widths; pieces = lm × 1.10 ÷ piece length.
- Thresholds = number of doors. Underlay = A × 1.05 when the material needs it.
- Tiles: adhesive bags = A ÷ 4 m² (≥ 0.5 m² tiles: ÷ 2.9); grout = A ÷ 15; levelling clips 8/m² for ≥ 60×60.
- Levelling: kg = A × 1.6 × mm → bags of 25 kg.
- Labour = A × install h/m² (SPC 0.32, 60×60 0.9, 120×60 1.2; walls × 1.5) + skirting 0.15 h/lm; removal: tiles 0.7 h/m².

## Wall cladding
- Net area = width × height − openings.
- **Strips** (fluted panels < 400 mm wide): columns = ⌈width ÷ panel width⌉ × ⌈height ÷ panel length⌉, × net/gross, + waste, rounded **per wall**.
- **Sheets** (PVC marble, stone panels): net × (1 + waste) ÷ sheet area, rounded per wall (pattern matching).
- Trims = perimeter + opening perimeters, +10%. Adhesive 0.6 cartridge/m². Optional battens 2.5 lm/m².
- Labour: WPC 0.65, PVC marble 0.55, stone 0.7 h/m²; trims 0.15 h/lm.

## LED strip / cove lighting
- Strip m = length × runs × 1.05, bought in 5 m rolls.
- Watts = length × runs × W/m. Drivers: n = ⌈W ÷ (largest driver × 80%)⌉, then the smallest size that carries W ÷ n at ≤ 80%.
- Feed points = runs × ⌈length ÷ 10 m⌉ (24 V voltage-drop limit) → connector kits + 6 m cable each.
- Profile (when used) = length × runs × 1.05 in 2 m bars.
- Labour: 0.2 h/m strip + 0.2 h/m profile + 0.75 h/driver.
- `build_cove`: gypsum board = length × 0.7 m girth × 1.15; furring 3.5 m/lm; 1.8 h/lm.

## Gypsum
- Partition: area = L × H − doors (0.9 × 2.1) − openings. Boards = area × faces × 1.10 ÷ 2.88 m².
  Studs = ⌈L ÷ 0.6⌉ + 1 + 2 per door, × ⌈H ÷ 3 m⌉. Tracks = 2L + 1.2 per door.
  Per board face: 15 screws, 1.25 m tape, 0.4 kg compound. Labour: 0.35 framing + 0.2 × faces + 0.225 × sides h/m² (≈ 1.2 h/m² for 2 sides).
- Ceiling: boards = A × 1.10 ÷ 2.88; main channel 0.9 m/m²; furring 2.75 m/m²; hangers 1/m²; wall angle = perimeter × 1.05.
  Per m²: 18 screws, 1.1 m tape, 0.5 kg compound. Labour 1.1 h/m²; cove 1.8 h/lm; bulkhead 1.2 h/lm. Wet rooms switch to MR board.

## Electrical points
- Per new point: faceplate + back box + cable (socket: 24 m = ~8 m run × 3 single cores) + conduit 8 m + making good.
- Relocate: box + 12 m cable + 3 m conduit + making good. Faceplate-only: faceplate.
- Labour: new 3.5 h, relocate 2.5 h, faceplate 0.35 h.

## Mirrors
- Glass m² = qty × max(W × H, 0.3) × 1.10. Edge work = perimeter (polish or bevel).
- Adhesive ≥ 1 cartridge per mirror. Backlit: LED at 90% of perimeter + driver + sensor + 1.5 h backing frame.
- Labour: 0.75 h + 0.9 h/m² per piece.

## Joinery (cabinets, wardrobes, media units)
Each cabinet is a panel model (`scripts/nexa_costing/joinery.py`):
- Carcass: 2 sides (H − plinth) × D, top + bottom W × D, (sections − 1) dividers, shelves (section width × D), back W × H in 6 mm, plinth.
- Fronts: doors fill what drawers/flaps leave; count = ⌈W ÷ max door width⌉ (sliding: 2 up to 2 m, 3 up to 3.2 m).
- Drawers: front + 2 sides + inner front/back + 6 mm bottom each.
- **Boards** are pooled per board type across the whole project: sheets = m² of parts ÷ (sheet m² × yield). Yield: Egger 2800 × 2070 84%, 1220 × 2440 80%, acrylic 72%.
- Edge band: carcass front edges (0.8 mm) + all front perimeters (2 mm), +10%. Lacquered fronts are sprayed instead: m² of fronts × 2.1 (both faces + edges).
- Hardware: hinges per door by height (≤0.9 m: 2, ≤1.6: 3, ≤2.0: 4, ≤2.6: 5, taller: 6), 1 runner pair per drawer, a handle per front (or push latches / profile), 2 stays per flap, 4 pins per shelf, hanging rail, legs (plinth) or concealed hangers (floating).
- Workshop labour = setup (2 h; wardrobe 5 h) + 1.0 h per m² of board + 1.0 h/door + 1.5 h/drawer + 1.2 h/flap + 0.3 h/shelf.
  Checks: 2.4 × 2.6 m wardrobe ≈ 35 h, 3 m TV unit ≈ 20–24 h, 900 vanity ≈ 8 h.
- Site install = per unit + per metre width (wardrobe 2 h + 4.5 h/m; kitchen 3 h/m), × 1.3 when wall-hung.
- Media unit = base box (cabinet model) + feature panel (board with battens, or a cladding material) + floating shelves (box-built: top, bottom, front, ends; concealed brackets every 0.6 m) + LED per shelf + optional side units, TV bracket, cable grommets and conduit.
- Headboard: backing board, batten frame, foam 1.1 × area, batting 1.2 × area, fabric = (W + 0.3)(H + 0.3) ÷ 1.4 m × 1.2; upholsterer 2 h + 1.7 h/m² × style (channel 1.4, tufted 1.8).
- Bed box: sides, ends, centre rail in carcass board; platform in 18 mm ply; 6 mm storage base; gas lift.

## Painting, wallpaper, curtains
- Paint L = area × coats ÷ 9 m²/L × 1.05 (ceilings 10 m²/L); primer area ÷ 8; putty by prep level (light 0.2, full 1.0 kg/m²).
  Labour = area × (0.08 × (coats + 1) + prep h) (ceilings × 1.25).
- Wallpaper rolls = ⌈drops ÷ ⌊roll length ÷ (H + repeat + 0.1)⌋⌉; 1.25 h per roll.
- Curtains: wide-width fabric railroaded = W × fullness (2.3) + 0.4 m; otherwise drops × (H + 0.4). Making-up per m of width; track W + 0.2.

## Project level
- Purchase list pools each material across all items, then rounds up to whole units / packs (+ spare packs where set). The rounding difference = "stock rounding" cost.
- Consumables = 3% of material cost. Snagging reserve 1.5% of sell (internal).
- Preliminaries: trips = 2 + ⌈site days ÷ 3⌉ × AED 300; protection AED 6/m² (min 250); cleaning AED 3/m² (min 300); debris AED 300 (+ skip 700 with strip-out); supervision 2 h per site day; building fees at cost.
- Contingency 5% of selling value. Preliminaries + consumables + rounding + contingency are spread over the scope items pro-rata; each item rounds up to AED 50.
- Site labour hours get +10% for tower access. Timeline = procurement + max(workshop, site trades in parallel) + joinery install.
