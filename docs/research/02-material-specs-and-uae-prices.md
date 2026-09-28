# NexaFix Costing Engine: Material Specs, Take-off Formulas and Indicative UAE Prices (AED, 2025-2026)

Compiled 28-Sep-2026 as **placeholder defaults**. The owner should replace them with his supplier prices.

## 0. Conventions used in this file

| Topic | Convention |
|---|---|
| Currency / VAT | AED. UAE VAT is 5%. Prices are **ex-VAT unless marked "inc"**. Online shops (fepy, ACE, noon, amazon.ae) show both. |
| Price basis | "Trade" = Deira/Sharjah/Ajman wholesaler or B2B portal (fepy.com, tasawwur.ae, MIH, meeramore). "Retail" = ACE, Danube Home, noon, amazon.ae, or consumer "supply & install" sites. Trade is usually **10-30% below retail**, and 40-60% below "supply & install" web prices. |
| "estimate" | No live UAE price was found. The figure is an informed estimate. Check it with a supplier before quoting. |
| Rounding | Always round the final quantity **up to whole packs** (boxes, rolls, sheets, bags, lengths) after adding waste. |
| Waste | Unless stated otherwise, waste % is applied to the **net** take-off before rounding to packs. |
| Dimensions | mm for material sizes and m for room dimensions. lm = linear (running) metre. |

Room geometry that every formula below assumes:

```
L, W = room length & width (m);  H = ceiling height (m)
floor_area   = L*W (+ extra rectangles for L-shapes)
perimeter    = 2*(L+W)
wall_area_gross = perimeter * H
openings_area   = Σ(door w*h) + Σ(window w*h)
wall_area_net   = wall_area_gross - openings_area          (paint, wallpaper, cladding)
skirting_lm     = perimeter - Σ(door widths)
```

---

## 1. FLOORING

### 1.1 Standard pack sizes

| Product | Common sizes (mm) | Thickness | Pack | Box coverage | Source / note |
|---|---|---|---|---|---|
| SPC click plank | **1220×180** | 4 / 5 / 6 mm (+1-1.5 mm IXPE attached) | 10 pcs | **2.196 m²** | luxury-materials.com (10 planks = 2.196 m²) |
| SPC plank | 1220×183 | 4-5 mm | 10 pcs | 2.233 m² | typical, estimate |
| SPC long plank | 1500×228 / 1830×180 | 5-6 mm | 6-8 pcs | 2.05-2.74 m² | typical. Use pcs×L×W |
| SPC herringbone | 600×120 / 615×123 | 5-6 mm | 24-36 pcs (A+B) | 1.73-2.6 m² | typical. Ordered in A/B pairs |
| SPC wear layer | 0.3 mm residential / 0.5 mm commercial | | | | |
| Laminate 8 mm (AC3/AC4) | 1380×193 | 8 mm | 8 pcs | **2.131 m²** | Kronotex 8 mm box = 22.94 ft² (biiibo.com) |
| Laminate 12 mm (AC4/AC5) | 1380×193 / 1218×198 | 12 mm | 5-6 pcs | 1.33-1.60 m² | typical, estimate |
| Engineered parquet | 1200-1900 × 150-190 | 14-15 mm (3-4 mm top layer) | box | 1.5-2.6 m² | typical |
| Porcelain 60×60 | 600×600 | 9-10 mm | **4 pcs** | **1.44 m²** | UAE standard |
| Porcelain 60×120 | 600×1200 | 9-10 mm | **2 pcs** | **1.44 m²** | danubehome.com listing |
| Porcelain 80×80 | 800×800 | 9-10 mm | 3 pcs | 1.92 m² | typical |
| Outdoor porcelain 2 cm | 600×1200×20 | 20 mm | 1 pc | 0.72 m² | danubehome.com |
| Tile adhesive | 20 kg or 25 kg bag | | | | Laticrete, Weber, Puma are 20 kg. Mapei Kerabond/Keraflex are 25 kg |
| Grout (cementitious) | 5 kg bag (also 2 kg, 20 kg) | | | | Mapei Ultracolor Plus is 5 kg |
| Self-levelling compound | 25 kg bag | 3-30 mm | | | Mapei Ultraplan Maxi |
| Skirting PVC | 60 / 80 / 100 mm high | | 2.4 m (also 2.5 / 2.9 m) | | |
| Skirting MDF (primed or wrapped) | 80-120 × 12-15 mm | | 2.4-2.44 m | | |
| Skirting aluminium | 40 / 60 / 80 / 100 mm | | 2.5 m or 3.0 m | | |
| Transition / threshold | T-bar, reducer, end-cap, stair nose | | 0.9 m (door) / 2.7 m | | |

### 1.2 Indicative supply prices

| Item | Unit | Low | Typical (default) | High | Source |
|---|---|---|---|---|---|
| SPC 4-5 mm budget (IXPE attached) | m² | 38 | **55** | 70 | luxury-materials.com 38/m². tilesman.com 40/m² (5 mm 180×1220, sale price). A 2.196 m² box at 143 inc = 65/m² (search snippet) |
| SPC premium 5-6 mm, 0.5 wear layer | m² | 90 | 110 | 130 | spatialfit.ae (Gerbur 5 mm 130/m²). Retail |
| Laminate 8 mm | m² | 40 | **50** | 60 | onlineflooring.ae / floorworlddubai.ae (retail) |
| Laminate 12 mm (water-resistant) | m² | 70 | **80** | 95 | same (retail) |
| Engineered oak 14-15 mm | m² | 90 | **150** | 300 | search snippets from several UAE flooring retailers: 90-150 budget, 135+ mid, 280+ semi-solid (lushloom.ae) |
| Porcelain 60×60 standard / Indian | m² | 34 | **55** | 65 | tilemountain.ae blog (40-65), danubehome |
| Porcelain 60×60 polished mid | m² | 65 | 90 | 120 | tilemountain.ae blog |
| Porcelain 60×120 | m² | 34 | **70** | 101 | danubehome.com: 49/69/79/89/145 per 1.44 m² box = 34-101/m² (retail) |
| Tile adhesive, basic grey or white 20 kg (Laticrete 305, Al Bustan) | bag | 9 | **25** | 30 | etihadsouq.ae (Laticrete 305 is 17-28) |
| Tile adhesive, standard C1 (Webercol, Puma, Ceresit CM9, Mapei Kerabond T 25 kg) | bag | 30 | **45** | 65 | etihadsouq.ae: CM9 30-34, Kerabond T 36, Webercol 48, Puma 58 |
| Tile adhesive, flexible C2TE/S1 for large format (Keraflex, CM16, Laticrete 325) | bag | 52 | **75** | 100 | etihadsouq.ae: CM16 52-55, Keraflex 75-80, Laticrete 325 100 |
| Grout, polymer-modified 5 kg (Mapei Ultracolor Plus) | bag | 65 | **70** | 99 | nqcart.ae 73.50 inc. bullshardware.com 65-99 |
| Grout, basic cement 5 kg | bag | 15 | 20 | 30 | estimate |
| Epoxy grout 5 kg (Kerapoxy class) | kit | 250 | 300 | 380 | estimate |
| Self-levelling compound 25 kg (Mapei Ultraplan Maxi) | bag | 70 | **120** | 126 | fepy.com 120 ex / 126 inc. Generic brands (e.g. Rakam) estimate 70-90 |
| SPC/LVT underlay IXPE 1-1.5 mm (only if not pre-attached) | m² | 4 | **6** | 9 | estimate |
| Laminate foam underlay 2-3 mm + PE vapour barrier | m² | 3 | **5** | 8 | estimate |
| PVC skirting 60-100 mm | lm | 8 | **12** | 18 | search snippet (Dubai flooring retailers): 12-18/lm. floorlands.ae 20-30/lm retail |
| MDF skirting primed or wrapped 80-100 mm | lm | 8 | **12** | 18 | estimate (18 mm MDF strip plus finish) |
| Aluminium skirting 60 mm matt | lm | 22 | **25** | 40 | search snippet (UAE aluminium skirting sites): 22-25/lm (60 mm), 28-40/lm (100 mm brushed). 55-70/lm installed |
| Aluminium T / reducer threshold 0.9 m | pc | 15 | **30** | 90 | estimate. Generic 15-35, Profilpas-grade 40-90 |

### 1.3 Take-off formulas

| Item | Formula | Notes |
|---|---|---|
| Plank / tile area | `order_m2 = floor_area × (1 + waste)` then `boxes = ceil(order_m2 / box_m2)` | Waste from §1.4 |
| Box coverage | `box_m2 = pcs × L_mm × W_mm / 1e6` | Use this when a supplier lists only pcs/box |
| Underlay | `underlay_m2 = floor_area × 1.05` (overlap), then round to rolls | Skip if the SPC has attached IXPE |
| Tile adhesive (kg) | `adhesive_kg = area × rate`, then `bags = ceil(adhesive_kg / bag_kg)` | Rates in §1.5 |
| Grout (kg/m²) | `g = (A + B)/(A × B) × T × J × 1.6` (A, B = tile sides mm, T = tile thickness mm, J = joint width mm, 1.6 = density) then `×1.15` waste | Mapei grout formula. 60×60×9, 2 mm joint gives 0.096 kg/m². 60×120×9, 2 mm gives 0.072. 30×60×9, 3 mm gives 0.216. Use at least 0.15 kg/m² on small jobs |
| Self-levelling | `kg = area × avg_depth_mm × 1.6` (1.7 for fibre-reinforced), then `bags = ceil(kg/25)` | 25 kg ≈ 5.2 m² at 3 mm. Default depth 3 mm if the floor is only being levelled |
| Primer for SLC | about 0.1-0.2 kg/m² | estimate |
| Skirting | `skirting_lm = (perimeter − Σ door widths + Σ returns) × 1.10`, then `pcs = ceil(lm / piece_len)` | Add 1 piece per 4 external or internal corners for offcuts. Waste 10% |
| Skirting fixing | adhesive at 1 cartridge per 8-10 lm, or pins/clips at 400-600 mm | |
| Thresholds | `1 per door opening where floor type/level changes` + `transition_lm` along material changes | Piece length ≥ door leaf + 50 mm |
| Tile trims (edge profiles) | `lm of exposed tile edge × 1.10`, then pieces of 2.5 m | |
| Tile spacers / levelling clips | 60×60: about 12 clips/m². 60×120: about 8/m² | estimate. About AED 0.1-0.3 per clip |

### 1.4 Waste factors (defaults)

| Layout | SPC / laminate / engineered | Porcelain ≤60×60 | Large format 60×120+ |
|---|---|---|---|
| Straight lay, simple room >15 m² | **7%** | **8%** | **10%** |
| Straight lay, small room / many corners / <8 m² | 10% | 12% | 15% |
| Brick or 1/3 offset | 8% | 10% | 12% |
| Diagonal (45°) | **12-15%** | **15%** | 18% |
| Herringbone | **15-20%** (use 18%) | 15% | n/a |
| Chevron | 20% | 20% | n/a |
| Stairs / nosings | count per step, 10% | | |

A common practice also adds **1 unopened spare box** per product for future repairs. Make this optional in the engine.

### 1.5 Adhesive consumption

| Application | Trowel | kg/m² (default) | Source |
|---|---|---|---|
| Mosaic / wall tiles ≤30×60 | 6 mm | 3.0-3.5 | Mapei Keraflex: 2-5 kg/m² |
| Floor 60×60 | 8-10 mm | **5.0** | Mapei range. estimate |
| Floor 60×120 and larger (back-buttered) | 10-12 mm | **7.0** | Keraflex Maxi S1: 1.2 kg/m² per mm of bed, so a 5-6 mm bed = 6-7 kg |
| External / uneven | 12 mm | 8.0 | estimate |
| Engineered parquet glue-down (MS polymer) | B11-B13 | 1.0-1.2 kg/m² | estimate. About AED 15-25/m² |

---

## 2. WALL CLADDING

### 2.1 Specs and prices

| Product | Size (mm) | Coverage / pc | Indicative price | Unit | Source / note |
|---|---|---|---|---|---|
| WPC fluted panel, interior PE/PVC-WPC | **160 × 2900** × 21-24 | 0.464 m² (face) | **25-45 / pc (default 35)** ≈ 55-95/m² | pc | estimate (trade). Size from wbm.ae (Sharjah) "2900×160 mm". Web supply+install is 120-250/m² (tilemountain.ae blog) |
| WPC fluted, co-extrusion / ASA | 219×26×2900 / 224×19×2900 | 0.635 / 0.650 m² | 60-110 / pc | pc | Sizes from timbermartwpc.com. Price estimate |
| WPC flat or 3D wide panel | 400-600 × 2900 × 8-9 | 1.16-1.74 m² | 45-90 / pc | pc | estimate |
| PVC UV marble sheet 1.2 mm (budget) | 1220 × 2440 | 2.977 m² | **73.50-100.80 / sheet** | sheet | arona.store (8×4 ft, 1.2 mm) |
| PVC UV marble sheet 2.5-3 mm | 1220 × 2440 | 2.977 m² | **110-170 / sheet (default 140)** | sheet | estimate. Retail PVC marble 120-200/m² (tilemountain.ae) |
| PVC UV marble sheet 3 mm | 1220 × 2800 / 1220 × 2900 | 3.416 / 3.538 m² | 140-210 / sheet | sheet | estimate |
| PVC marble mouldings / trims | 2.9 m length | | 36.75-100.80 / pc | pc | arona.store (FR3025 36.75, FR6021 52.50, SK12012 73.50, IC11427 100.80) |
| Aluminium trims (U edge, H joint, L/external corner) | 2.5-3.0 m | | 10-25 / pc | pc | estimate |
| PU faux-stone panel | 1200 × 600 × 20-50 | 0.72 m² | **60-120 / pc (default 85)** | pc | wallpaperland.ae "from 60 AED". Corner pieces cost about 1.3× |
| Acoustic slat panel (veneer slats on 9 mm PET felt) | 2400 × 600 × 21 | 1.44 m² | **150-250 / pc** generic (estimate) | pc | Premium Trepanel 2850×480: 336.75-449 / pc (tilemountain.ae) = 245-330/m² |
| Acoustic slat square | 600 × 600 × 21 | 0.36 m² | 81.75 | pc | tilemountain.ae (Trepanel, on sale) |
| MDF slat panel (factory, wrapped or veneered) | 2400-2700 × 600 | 1.44-1.62 m² | 110-220 / pc | pc | estimate. MDF panels 150-300/m² retail (tilemountain.ae) |
| In-house MDF slats | 18 mm MDF ripped to 30-60 mm | | 1 sheet ≈ 68 lm of 40 mm slat | | Derived: 1220/(40+3 mm kerf) = 28 strips × 2.44 m |
| Construction adhesive (MS polymer / "No More Nails" 290-300 ml) | cartridge | | 12-25 | pc | estimate |
| Timber batten white wood 2"×1" (≈45×20) | 3.0-3.6 m | | 8-15 / length (≈3-4 / lm) | pc | estimate |
| MR MDF / ply batten ripped in-house | 18 mm × 40-50 | | ≈1.5-2.5 / lm | lm | derived from sheet price |
| Frame fixings (nylon plug + screw) | | | 0.15-0.30 each | pc | estimate |

### 2.2 Take-off formulas

| Item | Formula | Waste |
|---|---|---|
| Fluted / slat vertical panels | `cols = ceil(wall_width / panel_face_width)`; `rows = ceil(wall_height / panel_length)` (normally 1 if H ≤ 2.9 m); `pcs = cols × rows × (1+waste)` | **5%** (10% if many cut-outs) |
| Sheet panels (PVC marble, MDF, SPC wall) | `sheets = ceil(net_area / sheet_area × (1+waste))`. For vein book-match, lay out per wall: `sheets_per_wall = ceil(wall_w/1.22) × ceil(wall_h/sheet_len)` | **10%**, or 15% for book-match |
| PU stone panels | `pcs = ceil(area / 0.72 × 1.08)` plus corner pieces = `ceil(external_corner_height / 0.6)` | 8% |
| Trims | `edge_lm = Σ(exposed edges) + Σ(sheet joints if H-joint used)`, then `pcs = ceil(edge_lm × 1.10 / piece_len)` | 10% |
| Adhesive | Direct glue on sheet or slat: **1 cartridge per 1.5-2.0 m²** (default 0.6 cart/m²). PU stone: 1 cartridge per 1-2 panels (0.9 cart/m²). WPC on clips: 0.3 cart/m² (spot glue) | none, round up |
| Battens / framing | Horizontal battens at spacing s (0.4-0.6 m): `batten_lm = wall_w × (ceil(H/s)+1) × 1.10`. Vertical (for horizontal panels) is similar with wall_h. Default s = 0.45 m, about **2.4-2.6 lm/m²** | 10% |
| Batten fixings | 1 plug+screw every 0.5-0.6 m of batten, about **5 per m²** | |
| WPC clips | 1 clip per panel per batten crossing, about **(1/panel_width) × (1/s)** per m². For 160 mm panels at 0.45 m that is ≈14/m² | 5% |
| Acoustic slat screws | 12-20 black screws per 2400×600 panel | |

---

## 3. GYPSUM (drywall partitions and suspended ceilings)

### 3.1 Material prices (FEPY and similar B2B, ex-VAT unless noted)

| Item | Size | Price | Source |
|---|---|---|---|
| Gyproc Regular board | 1200×2400×12.5 | **21.26** (22.32 inc) | fepy.com |
| Knauf Regular board | 1200×2400×12.5 | 27.91 (29.31 inc) | fepy.com |
| Generic / local regular board | 1200×2400×12 | 15-25 | fepy.com blog, yasutrading.com |
| Gyproc Regular board | **1200×3000×12.5** | **34.78** (36.52 inc) | fepy.com |
| Moisture-resistant (MR) board | 1200×2400×12.5 | **28-43** (Knauf MR 42.90-43.41). Knauf MRH2 48.65 | fepy.com blog / fepy.com |
| Fire-rated board | 1200×2400×12.5 | Gyproc Firestop 33.83. Knauf FR **58.50** | fepy.com |
| Fire-rated 15 mm (Type F) | 1200×2400×15 | 35-55 (Gyproc Firestop MR 15 mm 101.75) | fepy.com blog |
| C-stud, generic GI 70 mm | 3000 | **8.00** | radiantbmt.com |
| Knauf CW stud 70×35×0.5 | 3000 | 27.00 (branded) | fepy.com |
| Knauf CW stud 50×35×0.5 | 3000 | 23.00 | fepy.com |
| Gyproc Gypframe I-stud 70I70 | 3000 | 59.50 (premium acoustic) | fepy.com |
| GI U-track 72 mm × 0.4-0.5 | 3000 | **9.49-9.80** | fepy.com / sharaby.ae |
| Ceiling main channel 38 × 0.35 | 3000 | **5.00** | fepy.com |
| Furring channel 35×24×0.35 / 35×22×0.5 | 3000 | **9.09-9.70** | fepy.com |
| Wall angle (perimeter) | 3000 | 9.80-15.22 | fepy.com blog |
| Paper joint tape 50 mm | 150 m roll | 31.98-37.70 | fepy.com blog |
| Drywall screws 25 mm | box 1000 | 37-58 | fepy.com blog |
| Joint compound (setting/air-dry) | 28 kg bag | 57.50 | fepy.com blog |
| Corner bead | 3000 | 3-5 generic (21.12 branded paper-faced) | estimate / fepy.com blog |
| Access panel 400×400 / 500×500 | pc | 66-84 / 87 | fepy.com blog |
| Rockwool slab 50 mm, 48 kg/m³ | m² | **15-45** (default 25) | search snippet (uae.acartzy.com, now offline). Treat as estimate |
| Hanger (threaded rod 6 mm or GI wire + anchor + clip) | set | 1.5-3.0 | estimate |
| Frame anchors (nailing anchor 6×40) | pc | 0.15-0.30 | estimate |

Benchmarks for sanity-checking (supply & install): single-layer, double-sided partition **AED 80-120/m²**, double-layer / acoustic / FR **150-220/m²** (woodenboxtrading.com). Flat ceiling **35-55/m²**, MR ceiling 50-75/m², stepped / bulkhead 90-160/m² (fepy.com blog).

### 3.2 Partition take-off (single metal frame, 1 layer 12.5 mm each side, H ≤ 3.0 m)

| Component | Formula (L = partition length m, H = height m, A = L×H − openings) | Per m² of wall (default) |
|---|---|---|
| Boards | `boards = ceil(A × sides × layers × 1.10 / board_area)`. board_area = 2.88 (1200×2400) or 3.6 (1200×3000). Use 3000 boards when H > 2.4 m to avoid butt joints | 2.2 m² board |
| C-studs | `studs = (ceil(L / s) + 1) × ceil(H / 3.0)`, s = 0.6 m (standard) or 0.4 m (tiles, heavy loads, MR areas). **+2 studs per door opening**, +1 per T-junction / end | ≈ **2.0 lm/m²** at 600 mm, ≈ 2.9 lm/m² at 400 mm |
| U-tracks | `track_lm = 2 × L × 1.05` + door heads (door width + 0.3 m each) | ≈ 0.7 lm/m² (H = 2.8-3.0) |
| Drywall screws | 25 mm for layer 1, 35-40 mm for layer 2. **15 screws per m² per board layer-face** (field 230 mm, edge 150 mm c/c) | 30/m² (1+1). Knauf W111 ≈ 28/m² |
| Joint tape | `≈ 1.0 lm per m² per face` (full-height boards, vertical joints at 1.2 m) + internal corners. 1.5 lm/m²/face if boards are staggered or cut | 2.0-3.0 lm/m² |
| Joint compound | **0.4 kg/m² per face** (Q2, joints + screw heads). **1.2 kg/m²** for a full skim (Q3/Q4) | 0.8 kg/m² (both faces, Q2) |
| Corner bead | `external corners lm × 1.05` | |
| Insulation | `A × 1.05` if acoustic / thermal requested | 1.05 m² |
| Track fixings | `ceil(2L / 0.6) + 2` | ≈ 1.2/m² |
| Double layer / FR | Boards × 2, screws + 50%, compound + 30% | |

The simplified formulas in woodenboxtrading.com's calculator match: Boards = (Net Area / Board Area) × Sides × Layers × 1.10. Studs = (Length / Spacing + 1) × Height / 3 m. Track = Length × 2 / 3 m.

### 3.3 Suspended flat ceiling take-off (UAE MF system: main channel + furring channel)

| Component | Spacing / rule | Per m² of ceiling (default) |
|---|---|---|
| Main channel (primary, 38 mm) | 1200 mm c/c, fixed to hangers | 0.83 lm, so **0.9 lm/m²** with laps (+8%) |
| Furring channel (secondary) | **400 mm c/c** for 12.5 mm board (600 max), fixed across mains | 2.5 lm, so **2.75 lm/m²** with laps (1.8 lm/m² at 600) |
| Hangers | 1200 × 1200 grid, max 1200 along main | **0.7-1.0 pc/m²** (use 1.0 for rooms < 10 m²) |
| Hanger rod / wire length | ceiling void + 0.15 m | per hanger |
| Connector clips (main to furring) | 1 per crossing | ≈ 2.1/m² at 400 mm |
| Wall angle / perimeter channel | room perimeter × 1.05 | = perimeter |
| Board | area × 1.10 (flat), × 1.15 (many cut-outs) | 1.1 m² |
| Screws | 15-20/m² | 18/m² |
| Joint tape | 1.0-1.2 lm/m² | 1.1 lm/m² |
| Joint compound | 0.5 kg/m² (joints + screws) | 0.5 kg/m² |
| Cut-outs | downlights, AC grilles, access panels: count individually | |

### 3.4 Bulkheads, coves and girth

| Element | Girth assumption (default) | Take-off |
|---|---|---|
| Plain drop bulkhead | drop 0.30 m + soffit 0.60 m = **0.9 m girth** | board m² = lm × girth × 1.15. Framing ≈ **3.5 lm of channel per lm** of bulkhead. Corner bead = 1-2 × lm |
| Perimeter light cove (LED trough) | vertical drop 0.20 + return/soffit 0.25 + upstand lip 0.10 + inner face 0.15 = **0.70 m girth** (range 0.6-0.9) | board m² = lm × 0.70 × 1.15. Framing ≈ 4 lm channel per lm. LED strip 1.0 lm per lm of cove (§5) |
| Step-down ceiling (2-level) | step face 0.10-0.20 m + extra ceiling area | area handled as ceiling, step face as lm × height |
| Pricing rule of thumb | UAE contractors price bulkheads and coves **per lm up to 0.6 m girth**, and per m² (lm × girth) above that | |

---

## 4. JOINERY BOARDS, EDGE BANDING, HARDWARE, FINISHING

### 4.1 Boards

| Board | Size (mm) | Area | Price per sheet | Source |
|---|---|---|---|---|
| Plain MDF 18 mm, China | 1220×2440 | 2.977 m² | **52** | mihhome.com |
| Plain MDF 18 mm, Thailand | 1220×2440 | 2.977 m² | 60-62 (nqcart 61.95 inc) | mihhome.com / nqcart.ae |
| Plain MDF 18 mm, branded retail | 1220×2440 | | 130 ex / 136.50 inc | fepy.com |
| **Default MDF 18 mm** | | | **65** | |
| MR MDF 18 mm (green core) | 1220×2440 | | **78** | mihhome.com |
| FR MDF 18 mm | 1220×2440 | | **97** | mihhome.com |
| MDF 6 mm plain | 1220×2440 | | **30-45** (default 35) | estimate. MIH lists 3 mm 30 and 4 mm 29 |
| MDF 12 mm / 25 mm | 1220×2440 | | 70-105 / 120-155 | mihhome.com (ranges) |
| MDF 18 mm jumbo | 1830×3660 (6×12 ft) | 6.70 m² | 325 | mihhome.com |
| Marine plywood 18 mm (WBP, BS1088-type) | 1220×2440 | | **118.75** ex (124.69 inc). Range 90-185 | fepy.com, fepy.com blog |
| Melamine MDF 18 mm white (double-sided) | 1220×2440 | | **95** (China) / 120 (pure white) | mihhome.com |
| Melamine MDF 18 mm solid colour / woodgrain / 3D | 1220×2440 | | 150-170. fepy.com Thailand beige 179.81 inc | mihhome.com / fepy.com |
| Melamine chipboard (MFC) 18 mm, local | 1220×2440 | | 100 | mihhome.com (concrete décors) |
| Melamine MDF 6 mm white | 1220×2440 | | 55 | mihhome.com |
| **Egger / Kronospan MFC 18 mm** | **2800×2070** | 5.796 m² | **200-320** (default 250) | estimate. UK list ≈ £55-85 ex VAT |
| Egger / Kronospan MFC 8 mm (backs) | 2800×2070 | | 110-170 | estimate |
| HPL laminate 0.7-0.8 mm (Formica / Greenlam / Chinese) | 1220×2440 (also 1300×2800) | | **60-120** (default 85). Chinese 40-60 | estimate. MIH and Greenlam stock it but publish no prices |
| Contact adhesive for HPL | | | ≈ 0.25-0.30 kg/m² (both faces), about AED 6-10/m² | estimate |
| High-gloss acrylic-laminated MDF 18 mm | 1220×2440 | | **310-400** | mihhome.com |
| UV high-gloss MDF 18 mm | 1220×2440 | | **130-170** | mihhome.com |
| Veneered MDF 18 mm, 2 sides (oak / beech) | 1220×2440 | | **110** (mahogany 92) | mihhome.com |
| Veneered MDF 18 mm walnut | 1220×2440 | | 140-220 | estimate |

### 4.2 Edge banding

| Spec | Roll | Price | AED / lm | Source |
|---|---|---|---|---|
| PVC 2 × 40 mm (worktops, thick panels) | 100 m | 260.40 inc | **2.60** | bluerhine.store |
| PVC 2 × 22 mm (doors, fronts) | 100 m | 120-160 | **1.2-1.6** (default 1.4) | estimate (scaled from 40 mm) |
| PVC 0.8-1 × 22 mm (carcass) | 200 m | 80-140 | **0.4-0.7** (default 0.55) | estimate |
| Melamine pre-glued 22 mm | 50-100 m | | 0.3-0.5 | estimate |
| Veneer edge 22-25 mm | 100-200 m | | 1.0-2.0 | estimate |
| Hot-melt EVA glue | | | ~0.02-0.05 AED/lm | estimate |

**Edge-banding take-off rules (per part):**
- Doors, drawer fronts, visible panels: all 4 edges, `2×(h+w)`, in 2 mm (or 1 mm) band.
- Carcass sides, top and bottom: front edge only (1 long edge) in 0.8 mm.
- Adjustable / fixed shelves: front edge (1 long edge), or both long edges if open-backed.
- Exposed end panels / tall-unit sides: front + top (+ bottom if visible).
- Add **50 mm per edge** for trimming and then **+10%**.

### 4.3 Nesting / sheet yield

| Situation | Usable yield (net part area ÷ sheet area) | Default |
|---|---|---|
| Carcass parts, plain / uni-colour board, 1220×2440 | 75-85% | **80%** |
| Carcass parts, 2800×2070 MFC (bigger sheet nests better) | 80-88% | **84%** |
| Doors / fronts with grain direction or book-match | 65-75% | **70%** |
| One-off small jobs (a single vanity or TV unit) | 60-70% | 65% |
| Saw kerf / edge trim | 3.2-4.5 mm kerf. Trim 10 mm off each MFC factory edge | |

`sheets = ceil( Σ(part_w × part_h) / (sheet_area × yield) )`. Charge part-sheets as whole sheets unless the offcuts are stocked.

### 4.4 Hardware (Dubai trade / small-trade, meeramore.com unless noted)

| Item | Generic / economy | Branded (Blum / Hettich / Hafele) | Source |
|---|---|---|---|
| Concealed hinge 110° soft-close clip-on, 35 mm cup, incl. plate | **7-10** each (Al Meera) | Hettich clip-on 14 (meeramore). Blum Clip-top Blumotion 71B3550 **55.42** retail (amazon.ae). **Trade estimate 18-28** | meeramore.com, amazon.ae |
| Wide-angle 165° / blind-corner / 30°-45° angle hinges | 8-17 | 30-60 (estimate) | meeramore.com |
| Hettich Sensys (retail single) | | 92.34 retail (amazon.ae). Trade estimate 15-25 | amazon.ae |
| Drawer runner, ball-bearing side-mount soft-close full-extension (pair) | 250: 22 · 300: 23 · 400: 25 · **450: 30** · 550: 36 · 600: 39 · 700: 45 | Hettich / Blum side-mount 60-120 (estimate) | meeramore.com |
| Undermount concealed soft-close (pair) | 400: 58 · **450: 61** · 500: 66 · 600: 80 · push-to-open 450: 113 | Blum Movento / Tandem 450: 150-250 (estimate. US $54.5) | meeramore.com |
| Metal box drawer system (tandem-box type, per drawer) | 500×84: 86 · 500×199: 126 | Blum Tandembox antaro / Legrabox: 180-450 (estimate. US $63-88 antaro) | meeramore.com |
| Profile handle, aluminium (cut to length) | C-profile 5.9 m: 495 (≈84/lm). L-profile 5.9 m: 365 (≈62/lm) | | meeramore.com |
| Bar / pull handle 128-224 mm | 7-13 (generic 180-212 mm) | designer 35-60 | meeramore.com |
| Wardrobe long handle 700-1000 mm | 42-57 | | meeramore.com |
| Knob | 3-12 (generic), 21 (classic brass) | crystal 109-120 | meeramore.com |
| Gas strut / lift stay 80-120 N | 8-25 each (2 per flap) | Blum Aventos HF/HK/HS set 350-900 (estimate) | estimate |
| Hanging rail oval 30×15 aluminium | 10-20 / lm + 2 end supports at 3-8 | pull-down wardrobe lift 650+ (meeramore) | estimate |
| Shelf pins (5 mm) | 0.10-0.50 each | | estimate |
| Adjustable plastic leg 100-150 mm + plinth clip | 2-6 each | Hettich / Blum-style 8-15 | estimate |
| Cam+dowel / confirmat / screws allowance | 10-15 per carcass | | estimate |
| Soft-close stay / push-latch (tip-on type) | 8-20 | Blum Tip-On 40-70 | estimate |

**Hardware quantity rules:**

| Rule | Default |
|---|---|
| Hinges per door by height | ≤900 mm: **2** · 901-1600: **3** · 1601-2000: **4** · 2001-2400: **5** (+1 if door width >600 mm or heavy/mirrored) |
| Max single-door width | 600 mm (above that, split into 2 doors) |
| Drawer runner length | = internal carcass depth rounded down to a standard size (e.g. 560 mm carcass takes 500 mm runners) |
| Handles | 1 per door / drawer front (2 on drawers >900 mm wide). Profile handle lm = Σ front widths |
| Legs | base unit ≤600 wide: 4 · 601-1200: 6 · >1200: 8. Plinth clips = front legs |
| Shelf pins | 4 per adjustable shelf |
| Gas struts | 2 per lift-up flap (size by flap weight × height) |
| Hanging rail | 1 per hanging section. lm = internal width. 2 supports per rail (+1 centre if >1.0 m) |

### 4.5 Finishing: PU lacquer subcontract (UAE)

| Finish | AED per m² per face | Note |
|---|---|---|
| Matt / satin PU (primer + 2 top coats), one face + edges | **55-90** (default 70) | estimate. Sharjah / Ajman spray shops often quote ≈ AED 6-10 per ft² |
| Matt / satin PU, both faces | 90-150 (default 120) | estimate |
| High-gloss PU, sanded and polished | **140-250** per face (default 190) | estimate |
| Metallic / textured / special | +20-30% | estimate |
| Reference: vinyl wrapping of existing kitchen fronts | from 110/m² | lushloom.ae |
| Reference: spray-painting a whole kitchen | 5,000-10,000 per kitchen | search snippet |

Lacquered area = Σ(door/panel area) × faces. Edges are included. Minimum charge per job is typically AED 300-500 (estimate).

---

## 5. LED / LIGHTING

### 5.1 Components and prices

| Item | Spec | Price | Source |
|---|---|---|---|
| LED strip 24 V COB 9-10 W/m, 5 m roll | IP20, 320-480 chips/m | **26.25** / roll (V.Max). KingOn 24 V 10 W/m 73.50 | tasawwur.ae (B2B) |
| LED strip 12 V COB 10 W/m, 5 m | | 26.25-29.40 | tasawwur.ae |
| LED strip 24 V 14.4 W/m SMD, 5 m (premium, 5-yr warranty) | 60 LED/m, 1050 lm/m | 150-300 / roll (estimate) | inspired-lighting.ae (spec). Price estimate |
| RGB COB 24 V 21 W/m, 5 m | | 195 (sale) | salhiyalighting.com (retail) |
| **Default strip cost** | generic 24 V COB | **AED 9/m** (≈45 per 5 m), premium AED 30-60/m | |
| Driver, generic 24 V 100-400 W IP44 (MODI) | CV | 26.25 | tasawwur.ae |
| Driver 24 V 400 W (ESNCO) | CV | 31.50 | tasawwur.ae |
| Driver 24 V 100 W (KingOn) | CV | 47.25 | tasawwur.ae |
| Driver 24 V 500 W IP67 (AIDEN) | CV | 110.25 | tasawwur.ae |
| Mean Well LPV-100-24 (IP67) | 100 W | 99 | amazon.ae |
| Mean Well LPV-150-24 | 150 W | 163.34 | amazon.ae |
| Mean Well PWM-120-24DA (DALI dimmable) | 120 W | 136.50 | tasawwur.ae |
| Aluminium profile, surface 17×7 | 2 m / 3 m | 7.88 / 15.75 | tasawwur.ae (EVB) |
| Aluminium profile 25×7 | 2 m / 3 m | 10.50 / 15.75 | tasawwur.ae |
| Aluminium profile 20×15 / 30×20 | 2 m | 15.75 / 23.10 | tasawwur.ae |
| Aluminium profile 50×35 / 70×35 (large recessed / pendant) | 2 m | 33.60 / 42.00 | tasawwur.ae |
| Branded profile + diffuser (Tiras 17×8.5) | 2 m | 62-82 | dubailighting.ae (retail) |
| Silicone neon profile 15×15 / 20×10 | per m | 12.60 / 16.80-18.90 | tasawwur.ae |
| End caps (pair) / mounting clips | | 1-3 / 0.5-1 each (3 clips per 2 m) | estimate |
| Inline PWM dimmer / RF / Wi-Fi (Tuya) controller 24 V | | 20-80 | estimate |
| Recessed downlight 7 W (Megaman) | | 14 (sale, reg. 25) | salhiyalighting.com |
| Recessed COB 7 W (Ledvance) | | 49 inc | deluxeuae.com |
| Downlight / spot, generic COB 7-12 W | | **12-30** (default 20) | estimate |
| Downlight, branded / trimless | | 45-150 | estimate |

### 5.2 Rules and take-off

| Rule | Default |
|---|---|
| Driver sizing | `driver_W ≥ strip_W / 0.8` (load ≤ **80%**). Choose the smallest standard size (60/100/150/200/300/400 W) that meets it |
| Strip power | `strip_W = strip_lm × W_per_m` (COB 10 W/m, SMD 9.6/14.4 W/m) |
| Max run per feed | 24 V ≤10 W/m: **10 m** single-end feed. 24 V 14.4-20 W/m: **5-8 m**. 12 V: **5 m**. Beyond that, feed both ends or add parallel feeds |
| Cove LED | `strip_lm = cove_lm × rows + 0.2 m per feed/corner` then × 1.05. `rolls = ceil(strip_lm / 5)`. rows = 1 (2 for high ceilings or double-sided coves) |
| Profiles (joinery, shelves, mirrors) | `pcs = ceil(run_lm × 1.05 / profile_len)`. End caps = 2 × runs. Clips = 3 per 2 m |
| Number of drivers | `max(ceil(total_W / (driver_W×0.8)), number of separately switched zones)` |
| Feed cable (2-core 1.0-1.5 mm²) | 2-5 m per feed point (estimate) |
| Downlights | 1 per 1.5-2.5 m² for general lighting (≈ 1.2-1.5 m grid). Fixture count × price + 1 driver each (usually integrated) |

---

## 6. ELECTRICAL

| Item | Generic | MK / Schneider (branded) | Source |
|---|---|---|---|
| 13 A twin switched socket (DP) | 10-18 (estimate) | MK Logic Plus K2747 **40-54**. Schneider Vivace KB25N (neon) **31-38** | noon.com, mepkart.com |
| 13 A single switched socket | 6-12 (estimate) | MK Essentials 1G 26 | amazon.ae |
| 13 A socket + 2× USB | 35-60 (estimate) | Schneider Vivace AKB15USB **132** inc. MK twin + USB 120-180 (estimate) | mepkart.com |
| Light switch 1G 1-way / 2G | 4-10 / 6-14 (estimate) | 10-20 / 15-30 (estimate) | estimate |
| TV (coax) / data RJ45 Cat6 outlet | 10-20 (estimate) | 25-50 (estimate) | estimate |
| 20 A DP switch with neon (AC / water heater) | 15-30 (estimate) | Schneider Vivace 1G **67**, 2G 78 | mepkart.com |
| 45 A cooker control / DP isolator | 30-50 (estimate) | 60-100 (estimate) | estimate |
| Weatherproof IP66 twin socket | | MK 204.75 ex | fepy.com |
| GI back box 3×3 | **1.75** ex (1.84 inc) | brass-terminal / branded 20-26 | fepy.com, amazon.ae |
| GI back box 3×6 | 2.5-4 (estimate) | | estimate |
| Dry-lining (gypsum) PVC box | 2-5 (estimate) | | estimate |
| Ducab 2.5 mm² single-core PVC, **100 yd (91.4 m) coil** | | **184-242** (≈2.0-2.65/m). supplyvan 280 | fepy.com |
| Ducab 1.5 mm² single-core, 100 yd | | 120-160 (estimate. fepy shows no live price) | estimate |
| Ducab 4 mm² / 6 mm² single-core, 100 yd | | 280-310 / 467-491 | fepy.com |
| PVC conduit 20 mm × 3 m | **7.80** inc | | canvasgt.ae |
| PVC conduit 25 mm × 3 m | 9-12 (estimate) | | estimate |
| Flexible conduit 20 mm, 50 m | 40-70 (estimate) | | estimate |

**Take-off defaults per NEW point** (typical Dubai apartment, extension from the nearest circuit or DB; all estimates):

| Point type | Cable | Conduit (3 m lengths) | Other |
|---|---|---|---|
| New 13 A socket (radial / spur) | route 10 m × 3 cores = **30 m of 2.5 mm²** | **3.5** | 1 back box, 2 bends / couplers |
| New light / switch point | route 8 m × 3 cores = **25 m of 1.5 mm²** | 3 | 1 back box / ceiling box |
| 20 A DP point (AC / heater) | 12 m × 3 = 36 m of 4 mm² | 4 | 1 back box |
| TV / data point | 15 m Cat6 / RG6 | 5 | 1 back box |
| Relocate an existing point | 5 m × 3 = 15 m | 2 | |

Formula: `cable_m = Σ(route_m × cores) × 1.10`, then `coils = ceil(cable_m / 91.44)`. If DB distances are known, replace route_m. Note that Ducab coils are **100 yards**, not 100 m.

---

## 7. MIRRORS / GLASS

| Item | Price | Unit | Source |
|---|---|---|---|
| Mirror glass, general range | 70-200 | m² | alintetharglass.com (2026 guide) |
| Clear mirror 4 mm, cut to size | **55-75** (default 65) | m² | estimate within the range above |
| Clear mirror 5 mm | **65-90** (default 80) | m² | estimate |
| Clear mirror 6 mm | **80-120** (default 100) | m² | estimate |
| Tinted mirror 5-6 mm (bronze / grey / black) | **110-170** (default 140) | m² | estimate (+40-60% over clear) |
| Antique / smoked / fluted mirror | 180-350 | m² | estimate |
| Clear float glass | 25-60 | m² | alintetharglass.com |
| Tempered glass | 80-180 | m² | alintetharglass.com |
| Edge flat polish | 5-10 | lm | estimate |
| Bevel 10-25 mm | 10-25 | lm | estimate |
| Hole drilling / socket cut-out | 5-15 / 20-40 | each | estimate |
| Sandblast / frosted pattern | 30-60 | m² | estimate |
| Installation (glue + clips) | 20-100 | m² | alintetharglass.com |
| Minimum charge | billed at ≥0.5 m² per piece, or ~50-100 per job | | estimate |
| LED back-light add-on (supply) | 24 V strip (perimeter lm) + 30-60 W driver + touch/IR sensor switch (25-60) + back frame / spacer (MDF or alu, 40-80) = **150-350 per mirror ≤1.2 m²** | set | estimate built from §5 prices |
| Demister pad | 40-90 | pc | estimate |
| Retail reference: LED backlit mirror 80×100 installed | 2,200-2,800 | pc | karnakhome.com |

Take-off: `area_m2 = ceil_to_0.05(W) × ceil_to_0.05(H)` (shops bill in 5 cm steps). `polish_lm = 2 × (W + H)`. LED strip lm = `2 × (W + H) − 0.1`.

---

## 8. PAINT

| Item | Pack | Price | Source |
|---|---|---|---|
| Jotun Fenomastic Pure Colour Emulsion Matt | 18 L | **457.60** ex (480.48 inc) | fepy.com |
| Jotun Fenomastic My Home Rich Matt | 18 L | 639 (retail) | aceuae.com |
| Jotun Fenomastic Hygiene Emulsion Matt | 18 L | 143.95-149.95 (noon; likely promo or tinted stock) | noon.com |
| **Jotun emulsion, default contractor price** | 18 L | **280** (range 180-460) | estimate |
| Jotun Fenomastic Emulsion Primer | 18 L | **179** | aceuae.com |
| National Paints Plastic Emulsion, 800 White | 18 L | **55.50** ex (58.27 inc). Colours 109-200 | fepy.com |
| Wall putty powder (generic) | 20 kg | 30-60 | estimate |
| Jotun Stucco putty filler (ready-mix) | 4 L / 18 L | 4 L ≈ 45-70, 18 L ≈ 150-220 | estimate (aceuae.com / amazon.ae list it but no price was captured) |
| Painting benchmark (labour + material) | | 10-20/m² interior | acmaintenanceuae.com |

**Coverage and formulas**

| Parameter | Default |
|---|---|
| Emulsion spread rate (practical, smooth primed wall) | **9 m²/L per coat** (theoretical 10-12, so allow ~15% loss) |
| Primer / sealer spread rate | **8 m²/L** |
| Coats | New gypsum / plaster: 1 primer + **2 finish**. Repaint same colour: 1-2 finish. Dark to light: primer + 3 |
| Litres | `L = area × coats / spread × 1.10`, then `pails = ceil(L / 18)` (use 4 L tins for the remainder if cheaper) |
| Putty / skim | Full skim 2 coats: **1.0 kg/m²**. Spot filling on repaint: **0.2 kg/m²** |
| Areas | walls = wall_area_net. ceiling = floor_area. Add 10% for cut-ins / textured surfaces |

---

## 9. UPHOLSTERY (headboards, panels)

| Item | Spec | Price | Source |
|---|---|---|---|
| PU foam D28-D32, 25 mm (1") | sheet ≈1×2 m | 30-55 / sheet | estimate |
| PU foam D32, **50 mm (2")** | sheet ≈1×2 m | **60-110 / sheet** (≈30-55/m²) | estimate (Dubai foam shops quote by sheet) |
| HR / D40 foam | | +30-50% | estimate |
| Polyester wadding (dacron) 100-200 g | per m² | 5-10 | estimate |
| Upholstery fabric 140 cm, budget (polyester, basic velvet) | per lm | **25-60** (default 45) | estimate |
| Upholstery fabric 140 cm, mid (velvet, boucle, linen-look) | per lm | 60-120 | estimate |
| Velvet / designer | per lm | 150-500 | curtainsonline.ae (velvet 150-500/m, retail) |
| Spray adhesive (500 ml) | can | 20-35 (≈1 can per 3-4 m²) | estimate |
| Buttons (tufting) | each | 1-3 (16-25 per m² for diamond tufting) | estimate |
| Backing board | 12-18 mm MDF / ply | see §4 | |

**Headboard take-off**
```
wrap      = foam_t + board_t + 0.05 m (staple allowance)
cut_w     = W + 2*wrap ;  cut_h = H + 2*wrap
foam_m2   = W*H*1.05                → sheets = ceil(foam_m2 / 2.0)
wadding_m2= cut_w*cut_h*1.05
fabric (140 cm usable ≈ 1.35 m):
  if cut_h <= 1.35 and fabric can be railroaded:  fabric_lm = cut_w + 0.10
  else: drops = ceil(cut_w / 1.35);  fabric_lm = drops * (cut_h + repeat) + 0.10
add 10% for piping / pattern matching; for channel/panel tufting add 25-40%
```
Example: king 1.9 × 1.2 m, 50 mm foam + 18 mm board gives wrap ≈ 0.12, cut 2.14 × 1.44. That exceeds 1.35, so 2 drops × 1.44 + 0.10 ≈ **3.0 lm** (3.3 lm with 10% for piping). If the fabric is 280 cm wide and railroaded, it needs 2.14 + 0.10 ≈ 2.3 lm.

---

## 10. CURTAINS & BLINDS

| Item | Spec | Price | Source |
|---|---|---|---|
| Blackout fabric 280 cm (3-pass) | per lm | retail **95-125** (sale). Trade estimate **35-70** (default 55) | search snippet (Dubai curtain shops); curtainsonline.ae 70-250 |
| Sheer / voile 280-300 cm | per lm | retail 30-150. Trade estimate **15-40** (default 28) | curtainsonline.ae |
| Linen-look / cotton blend | per lm | 55-220 | curtainsonline.ae |
| Stitching (wave / S-fold) | per lm of finished width | 60-110 | curtainsonline.ae |
| Stitching (pinch pleat / eyelet / pencil) | per lm | 50-100 / 30-60 / 40-80 | curtainsonline.ae |
| Lining | per lm | 20-80 | curtainsonline.ae |
| Manual aluminium ceiling track (incl. gliders, brackets) | per lm | retail from **30**. Trade estimate **12-25** (default 20) | curtaininstallation.ae / estimate |
| Wave track with carriers + spacing cord | per lm | 25-45 | estimate |
| Motorised track + motor, Somfy (Irismo / Glydea) | per window ≈3-4 m | **1,000-2,000** installed. Motor alone from ~800 | creativevisionglobal.com |
| Motorised, generic (Dooya / Tuya Wi-Fi) | motor + track per window | motor 300-600 + track 40-80/lm | estimate |
| Roller blind, supply & install (retail) | per m² | sunscreen **95-280**. Blackout 140-400. From 85 | lushloom.ae, curtainsandblind.ae |
| Roller blind, trade supply only (generic fabric, 38 mm tube) | per m² | **45-90** (default 65) | estimate |
| Roller blind motor (Somfy / tubular) | per blind | +500 and up (generic 250-400) | search snippet (Dubai blind retailers) / estimate |

**Formulas**

| Parameter | Default |
|---|---|
| Track length | `window_w + 2 × stack_back` (0.15-0.25 m each side), or wall-to-wall. Round up to 0.1 m |
| Fullness | **Wave / S-fold 2.3** (Silent Gliss std. 2.1-2.3) · pinch / double pleat **2.5** · eyelet 1.8-2.0 · pencil 2.0-2.5 · sheers 2.5-2.8 |
| Finished drop | floor-to-track − 10-15 mm clearance |
| Fabric (280/300 cm railroaded, drop + 0.30 ≤ fabric width) | `fabric_lm = track_lm × fullness + 0.20 × panels` (side hems) |
| Fabric (drop too tall for railroading) | `widths = ceil(track_lm × fullness / fabric_w)`, then `fabric_lm = widths × (drop + 0.30 + repeat)` |
| Hem + heading allowance | 0.30 m (0.15-0.20 hem + 0.10 heading) |
| Layers | Blackout + sheer = 2 tracks (or a double track) |
| Roller blinds | `area = max(W × H, 1.0 m²)` per blind (minimum billing 1.0-1.5 m²). Max width ≈ 2.8-3.0 m per fabric |

---

## 11. WALLPAPER

| Roll | Size | Area | Notes |
|---|---|---|---|
| Euro standard | **0.53 × 10.05 m** | 5.33 m² (usable ≈4.5-5.0) | most European / Korean designs |
| Wide roll | 1.06 × 10.05 m | 10.65 m² | |
| "Big roll" (commercial vinyl, common in UAE) | **1.06 × 15.6 m** | 16.5 m² | |
| Other | 0.70 × 10 m | 7.0 m² | some Chinese / Italian |

| Price band | AED / roll (0.53 × 10) | Source |
|---|---|---|
| Economy | 35-85 | wallpaperland.ae |
| Standard vinyl / non-woven | **85-180** (default 120) | wallpaperland.ae |
| Premium textured | 180-350 | wallpaperland.ae |
| Grasscloth / fabric | 300-600 | wallpaperland.ae |
| Custom mural / digital print | 80-150 / m² (premium 150-280) | wallpaperland.ae |
| Installation labour | 50-120 / roll | wallpaperland.ae |
| Adhesive (powder, 200-250 g) | 15-30 per pack. 1 pack per 4-5 standard rolls | estimate |

**Rolls calculation (drop method; handles pattern repeat)**
```
wall_run      = Σ(width of walls to paper)        (deduct openings only if > 1 roll width)
drops_needed  = ceil(wall_run / roll_width)
drop_len      = H + 0.10 (trim allowance)
if repeat R > 0:  drop_len = ceil(drop_len / R) * R   (+ R/2 for half-drop match)
drops_per_roll= floor(roll_length / drop_len)
rolls         = ceil(drops_needed / drops_per_roll) + 1 spare  (or ×1.10 on big jobs)
```
Example: a 4.0 m wall at H 2.7 m with a 0.53 roll gives 8 drops. With R = 0.64, drop = 3.20, so 3 drops/roll and **3 rolls + 1 spare**. With a 1.06 × 15.6 roll it takes 4 drops at 4 drops/roll, so **1 roll** (+ spare).

---

## 12. COUNTERTOPS (quartz)

| Item | Price | Source |
|---|---|---|
| Quartz slab supply, low-end (Chinese / Indian) | **250-300 / m²** | bestimate.ae (via search snippet) |
| Quartz mid-range | **350-500 / m²** (default 400) | bestimate.ae |
| Quartz premium brands (Caesarstone, Silestone) | 600-800+ / m² | bestimate.ae |
| Retail quartz slab | 450-889 / m² | tilesman.com (via search snippet) |
| Standard slab | 3200×1600×20 = **5.12 m²** (jumbo 3200×1800 / 3300×2000). 12-15 mm and 30 mm also available | tilesman.com |
| Fabricated & installed worktop, 600-650 deep, 20 mm, eased edge | **450-900 / lm** budget-mid (default 650). Premium 900-1,800 / lm | estimate |
| Whole-kitchen benchmark (quartz / granite) | 4,000-15,000+ | bestimate.ae |
| Upstand 100 mm | 80-150 / lm | estimate |
| Full-height splashback | slab rate + 20-30% fabrication | estimate |
| Undermount sink cut-out + polished | **150-300** each | estimate |
| Top-mount sink / hob cut-out | **75-150** each | estimate |
| Tap hole / socket cut-out | 20-50 / 30-60 | estimate |
| Drainer grooves | 150-300 / set | estimate |
| Mitred edge / waterfall end | 80-150 / lm of mitre | estimate |

**Take-off**
```
worktop_lm   = Σ runs along the wall (L-shape: measure one leg to the back corner, the other from the front edge)
worktop_m2   = worktop_lm × depth (0.62 default) + island area + waterfall ends (h × depth)
slabs        = ceil(worktop_m2 / (5.12 × yield))     yield = 0.75-0.85 (0.80 default)
cutouts      = sinks + hobs + taps + sockets (count individually)
```

---

## 13. ENGINE DEFAULTS (machine-readable summary; AED ex-VAT; replace with supplier prices)

```yaml
vat: 0.05
flooring:
  spc_5mm:            {unit: m2, price: 55,  box_m2: 2.196, waste: 0.07, herringbone_waste: 0.18, diagonal_waste: 0.13}
  laminate_8mm:       {unit: m2, price: 50,  box_m2: 2.131, waste: 0.07}
  laminate_12mm:      {unit: m2, price: 80,  box_m2: 1.598, waste: 0.07}
  engineered_oak:     {unit: m2, price: 150, box_m2: 2.0,   waste: 0.08}
  porcelain_60x60:    {unit: m2, price: 55,  box_m2: 1.44, pcs_per_box: 4, waste: 0.08, diagonal_waste: 0.15}
  porcelain_60x120:   {unit: m2, price: 70,  box_m2: 1.44, pcs_per_box: 2, waste: 0.10}
  tile_adhesive:      {unit: bag20kg, price: 45, kg_per_m2: {wall: 3.5, floor_60: 5.0, large_format: 7.0}}
  grout_5kg:          {unit: bag, price: 70, formula: "(A+B)/(A*B)*T*J*1.6*1.15", min_kg_m2: 0.15}
  slc_25kg:           {unit: bag, price: 120, kg_per_m2_per_mm: 1.6, default_mm: 3}
  underlay_ixpe:      {unit: m2, price: 6, overlap: 0.05}
  skirting_pvc:       {unit: lm, price: 12, piece_m: 2.4, waste: 0.10}
  skirting_mdf:       {unit: lm, price: 12, piece_m: 2.44, waste: 0.10}
  skirting_alu_60:    {unit: lm, price: 25, piece_m: 3.0, waste: 0.10}
  threshold_alu:      {unit: pc, price: 30, piece_m: 0.9}
cladding:
  wpc_fluted_160x2900:{unit: pc, price: 35, face_m2: 0.464, waste: 0.05}
  pvc_marble_1220x2440_3mm: {unit: sheet, price: 140, m2: 2.977, waste: 0.10}
  pvc_marble_1220x2800_3mm: {unit: sheet, price: 170, m2: 3.416, waste: 0.10}
  pu_stone_1200x600:  {unit: pc, price: 85, m2: 0.72, waste: 0.08}
  acoustic_slat_2400x600: {unit: pc, price: 200, m2: 1.44, waste: 0.05}
  trim_2_9m:          {unit: pc, price: 18, piece_m: 2.9}
  adhesive_cartridge: {unit: pc, price: 18, per_m2: 0.6}
  batten:             {unit: lm, price: 3.5, lm_per_m2: 2.5}
gypsum:
  board_std_1200x2400:{unit: sheet, price: 22, m2: 2.88}
  board_std_1200x3000:{unit: sheet, price: 35, m2: 3.6}
  board_mr_1200x2400: {unit: sheet, price: 43, m2: 2.88}
  board_fr_1200x2400: {unit: sheet, price: 45, m2: 2.88}
  stud_70_3m:         {unit: pc, price: 10}      # generic 8, Knauf 27
  track_72_3m:        {unit: pc, price: 9.5}
  main_channel_3m:    {unit: pc, price: 5}
  furring_3m:         {unit: pc, price: 9.1}
  wall_angle_3m:      {unit: pc, price: 10}
  screws_1000:        {unit: box, price: 45}
  tape_150m:          {unit: roll, price: 34}
  compound_28kg:      {unit: bag, price: 57.5}
  rockwool_50mm:      {unit: m2, price: 25}
  partition_per_m2:   {board_m2: 2.2, stud_lm: 2.0, track_lm: 0.7, screws: 30, tape_lm: 2.5, compound_kg: 0.8}
  ceiling_per_m2:     {board_m2: 1.1, main_lm: 0.9, furring_lm: 2.75, hangers: 1.0, screws: 18, tape_lm: 1.1, compound_kg: 0.5}
  cove_girth_m: 0.70
  bulkhead_girth_m: 0.90
joinery:
  mdf_18_1220x2440:   {unit: sheet, price: 65}
  mdf_mr_18:          {unit: sheet, price: 78}
  mdf_6:              {unit: sheet, price: 35}
  marine_ply_18:      {unit: sheet, price: 120}
  melamine_mdf_18:    {unit: sheet, price: 130}
  mfc_egger_18_2800x2070: {unit: sheet, price: 250, m2: 5.796}
  hpl_0_8:            {unit: sheet, price: 85}
  acrylic_gloss_18:   {unit: sheet, price: 330}
  veneer_mdf_18:      {unit: sheet, price: 115}
  edge_0_8x22:        {unit: lm, price: 0.55}
  edge_2x22:          {unit: lm, price: 1.4}
  yield: {carcass_1220: 0.80, carcass_2800: 0.84, fronts: 0.70}
  hinge_softclose_generic: {unit: pc, price: 9}
  hinge_blum_clip_top:     {unit: pc, price: 25}
  runner_ball_450_pair:    {unit: pair, price: 30}
  runner_undermount_450:   {unit: pair, price: 61}
  handle_bar:              {unit: pc, price: 12}
  profile_handle:          {unit: lm, price: 70}
  gas_strut:               {unit: pc, price: 15}
  hanging_rail:            {unit: lm, price: 15}
  leg_adjustable:          {unit: pc, price: 4}
  shelf_pin:               {unit: pc, price: 0.3}
  hinges_by_door_height_mm: {900: 2, 1600: 3, 2000: 4, 2400: 5}
  pu_lacquer_matt_per_face_m2: 70
  pu_lacquer_gloss_per_face_m2: 190
led:
  strip_24v_cob:  {unit: m, price: 9, w_per_m: 10, roll_m: 5, max_run_m: 10}
  driver_rule_load: 0.8
  driver_price: {60: 25, 100: 35, 150: 45, 200: 55, 300: 75}   # generic; Mean Well ≈ 2.5-3x
  profile_2m:     {unit: pc, price: 12}
  downlight:      {unit: pc, price: 20}
electrical:
  socket_twin_generic: 15
  socket_twin_mk: 45
  socket_usb: 60
  switch_1g: 12
  tv_data_point: 25
  dp_20a: 45
  back_box_3x3: 1.75
  cable_2_5_coil_91m: 200
  cable_1_5_coil_91m: 140
  conduit_20_3m: 7.5
  per_new_socket: {cable_2_5_m: 30, conduits: 3.5, back_boxes: 1}
  per_new_light:  {cable_1_5_m: 25, conduits: 3, back_boxes: 1}
mirror:
  clear_4mm_m2: 65
  clear_5mm_m2: 80
  clear_6mm_m2: 100
  tinted_6mm_m2: 140
  polish_lm: 7
  bevel_lm: 18
  led_backlight_addon: 250
paint:
  emulsion_18l: 280
  primer_18l: 179
  spread_m2_per_l_coat: 9
  primer_spread: 8
  coats_new: {primer: 1, finish: 2}
  putty_kg_m2: {full_skim: 1.0, spot: 0.2}
upholstery:
  foam_50mm_sheet_2m2: 85
  fabric_140_lm: 45
curtains:
  blackout_280_lm: 55
  sheer_280_lm: 28
  stitching_wave_lm: 80
  track_lm: 20
  fullness: {wave: 2.3, pinch: 2.5, eyelet: 2.0, sheer: 2.5}
  motor_generic: 450
  motor_somfy: 1100
  roller_blind_m2: 65
wallpaper:
  roll_053x10: {price: 120, width: 0.53, length: 10.05}
  roll_106x156:{price: 300, width: 1.06, length: 15.6}   # estimate
  install_per_roll: 60
countertop:
  quartz_m2_supply: 400
  quartz_lm_installed: 650
  slab_m2: 5.12
  yield: 0.80
  cutout_sink_undermount: 200
  cutout_hob: 100
  tap_hole: 35
```

---

### Source domains consulted
fepy.com (plus its blog pages on gypsum ceilings and plywood) · mihhome.com · meeramore.com · tasawwur.ae · etihadsouq.ae · nqcart.ae · bluerhine.store · arona.store · danubehome.com · tilemountain.ae · luxury-materials.com · tilesman.com (via search) · spatialfit.ae · onlineflooring.ae / floorworlddubai.ae · mapei.com (Keraflex, Keraflex Maxi S1) · woodenboxtrading.com · radiantbmt.com · sharaby.ae · canvasgt.ae · mepkart.com · noon.com · amazon.ae · aceuae.com · salhiyalighting.com · deluxeuae.com · dubailighting.ae · inspired-lighting.ae · alintetharglass.com · karnakhome.com · bestimate.ae · wallpaperland.ae · curtainsonline.ae · creativevisionglobal.com · lushloom.ae · wbm.ae · timbermartwpc.com · buildingclub.info (Knauf W111 consumption) · Silent Gliss fullness standard via fibrecalcs.com.

Items marked **estimate** have no live UAE price. Get quotes for them first: WPC fluted per piece, 3 mm PVC marble sheets, Egger MFC in the UAE, HPL, Blum/Hettich trade prices, PU lacquer subcontract, mirror per m², quartz per lm and cut-outs, foam, fabrics, and trade curtain prices.
