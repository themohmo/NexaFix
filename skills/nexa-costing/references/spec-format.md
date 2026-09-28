# Project spec format

A spec is YAML (or JSON) with three parts: `project`, `rooms`, `scope`.
Lengths are metres. Numbers above 20 are read as millimetres (`2400` →
2.4 m), and strings may carry units (`"240 cm"`, `"8ft"`). Areas are m²
(`"135 sqft"` works too).

```yaml
project:
  client: Mr. Ahmed Khan          # printed on the quote ("" -> "Client Name")
  name: Marina Gate 2 — 2304      # project line
  location: Dubai Marina, Dubai
  ref: NF-2026-0928               # optional; default NF-<yyyy>-<mmdd>
  date: 28/09/2026                # optional; default today
  title: Bespoke Joinery Package  # optional; auto from the scope
  summary: ...                    # optional cover paragraph
  ceiling_height: 2.8             # default for rooms without height (rate book default 2.8)
  typology: 2br                   # rough estimate without room list (studio, 1br, 2br, 3br, 4br_villa)
  total_area: 115                 # scales the typology rooms
  building_fees: 500              # NOC/admin fees, passed through at cost
  extras: [{name: Parking permits, cost: 200}]   # any other project cost (sell = cost + prelim markup)
  prelims: {transport: false, protection: 400}   # switch off (false) or fix (number) a preliminary
  contingency_pct: 5              # override the rate book for this job
  discount_pct: 5                 # or discount_amount: 1000, discount_label: "Opening offer"
  vat: true                       # false for export / non-VAT jobs
  show_unit_rates: false          # true prints qty x rate on each scope item
  show_prelims_line: false        # true shows "Preliminaries & Site Works" as its own line

rooms:
  - name: Living Room
    length: 6.2
    width: 4.5
    # area: 27.9                 # instead of length/width
    # perimeter: 21.4            # optional; estimated from area if missing
    # height: 3.0                # overrides ceiling_height
    doors: 1                      # count (0.9 x 2.1) or list [[w, h]]; default 1 (balconies 0)
    windows: [[3.0, 2.4]]         # count (1.5 x 1.5) or list [[w, h]]; default 0
    # wet: true                  # bathrooms/WC/ensuite are detected from the name
    # tags: [outdoor]            # balcony/terrace detected from the name
```

Room selectors (for `room:` / `rooms:`): a room name, a list of names,
`all` (all indoor rooms), `dry` (indoor, not wet), `wet`, `bedrooms`,
`everything` (incl. balconies), or a tag.

## Scope

Each entry in `scope` is **one numbered item on the quotation**. Either a
single item (has `type`) or a package (has `items`):

```yaml
scope:
  - title: SPC Flooring                 # single item
    type: flooring
    rooms: dry

  - title: Master Bedroom Set           # package: one quote line, several components
    subtitle: Complete set with wall cladding
    room: Master Bedroom                # default room for the components
    tile: BEDROOM                       # label on the cover grid (default: title)
    image: refs/bedroom.jpg             # "approved reference image" (path relative to the spec)
    # description / includes / summary_line: optional, auto-written otherwise
    # qty: 1, unit: Set                 # what the quote shows (default 1 Set for packages)
    # price: 15000                      # lump-sum selling price (cost still built up)
    # markup_pct: 30                    # markup for materials without an explicit sell price
    items:
      - {type: nightstand, qty: 2}
      - {type: headboard, width: 2.0, height: 1.2, style: channel}
      - {type: bed_box, size: king}
      - {type: wall_cladding, material: pvc_marble_sheet, width: 4.0}
```

Keys on any item: `title`, `room` / `rooms`, `qty`, `price` (lump sum),
`sell_rate` (AED per m² / lm / point / unit of the item's measure),
`markup_pct`, `min_charge`.

## Item types

Material keys refer to `[materials.<key>]` in `rates.toml`
(`python scripts/rates.py show <word>` lists them).

### Surfaces
| type (aliases) | fields | notes |
|---|---|---|
| `flooring` (`spc`, `laminate`, `parquet`, `vinyl`, `tiles`, `floor_tiles`) | `material`, `area` or `rooms` (default `dry`; tiles default `wet`), `perimeter`, `pattern` straight/diagonal/herringbone, `waste_pct`, `underlay`, `levelling` (true or mm), `skirting` (default true), `skirting_material`, `thresholds`, `threshold_count`, `removal` + `existing` (tiles/spc/laminate/carpet/parquet) | planks/tiles from plank size + waste; tile adhesive, grout and clips added for tiles; skirting = perimeter − door widths |
| `wall_tiles` | `material`, `width` + `height` or `area`, `openings` | labour × `wall_labour_factor` |
| `wall_cladding` (`cladding`, `feature_wall`, `wall_panel`) | `material` (wpc_fluted_panel, pvc_marble_sheet, stone_pvc_panel, acoustic_slat_panel…), `width` (wall length), `height` (default room height), `area`, `openings` [[w,h]], `trims`, `framing`, `backing` (board key), `lighting` (true = one run the wall width, a length, or `{length, runs, strip, profile}`) | strips (fluted) are counted per column and rounded per wall |
| `painting` (`paint`) | `rooms` (default all) or `area`, `surfaces` walls/ceilings/both, `coats` (2), `prep` none/light/medium/full, `paint`, `ceiling_paint`, `primer`, `colour` | wall area = perimeter × height − doors/windows |
| `wallpaper` | `width`, `height`, `material`, `pattern_repeat` | whole rolls from drops per roll |

### Gypsum & lighting
| type | fields | notes |
|---|---|---|
| `gypsum_partition` (`partition`, `drywall`) | `length`, `height`, `sides` (2), `layers` (1), `doors`, `openings`, `board` std/mr/fr or key, `insulation`, `stud_spacing` | studs, tracks, screws, tape, compound; MR board automatic in wet rooms |
| `gypsum_ceiling` (`false_ceiling`, `ceiling`) | `rooms` or `area`, `perimeter`, `board`, `cove_length` (m or `perimeter`), `bulkhead_length`, `downlights`, `supply_downlights`, `access_panels` | channels, furring, hangers, wall angle |
| `cove_lighting` (`cove`) | `length` or `rooms` (perimeter), `runs`, `strip`, `profile`, `build_cove` (also builds the gypsum cove), `cct` | drivers sized at 80% load, re-feed every 10 m |
| `led_strip` (`led`) | `length` or `rooms`, `runs`, `strip`, `profile` (default true), `sensor`, `location` | for shelves, cabinets, niches |

### Electrical & glass
| type | fields | notes |
|---|---|---|
| `electrical_point` (`socket`, `switch`, `data_point`, `light_point`) | `count`, `kind` socket/usb/switch/light/data/isolator, `mode` new/relocate/faceplate, `cable_m`, `new_faceplate` | per point: faceplate, back box, cable (3 single cores), conduit, making good |
| `mirror` | `width` + `height` or `diameter`, `shape` rectangle/round/arch, `qty`, `glass` (mirror_clear_5mm, mirror_bronze_6mm…), `edge` polished/bevel/none, `frame`, `backlit` | minimum chargeable area; backlit adds LED, driver, sensor, frame |

### Joinery
Cabinet presets: `wardrobe`, `kitchen_base`, `kitchen_wall`, `tall_unit`,
`vanity`, `shoe_cabinet`, `dresser`, `nightstand`, `bookshelf`, `storage`,
`console`, `study_desk`, `tv_base`, `display_unit` (or `type: cabinet,
preset: …`). Preset dimensions/composition live in
`[assemblies.cabinet.presets.*]` and every field can be overridden:

| field | meaning |
|---|---|
| `width` (required), `height`, `depth`, `qty` | size in m (or mm) |
| `sections`, `shelves`, `hanging_sections` | internal layout (default from preset) |
| `doors` (`auto` = width / max_door_width), `door_type` hinged/sliding/glass/none | fronts |
| `drawers`, `drawer_height`, `drawer_columns`, `flaps` | drawer fronts + boxes + runners; flaps get stays |
| `plinth`, `floating`, `legs`, `back`, `top` | construction |
| `carcass_board`, `front_board`, `back_board`, `drawer_board` | board keys (mfc_18, melamine_mdf_18, mdf_18 for lacquer, acrylic_18, veneer_mdf_18…) |
| `finish` laminate/lacquer/veneer/acrylic | lacquer & veneer add spray per m² of face; lacquered fronts skip edge band |
| `handles` standard/profile/push/none | handles, profile metres or push latches |
| `led` (true or m), `led_sensor` | LED in profile + driver + sensor |
| `countertop` (true or material key) | worktop along the width |

| type | fields |
|---|---|
| `media_unit` (`tv_unit`, `media_wall`) | `width`; `base` (true/false or `{width, height, depth, drawers, flaps, door_type, floating, led}`), `drawers`, `flaps`, `handles`; `panel` (true/false or `{material, width, height}` — a board or a cladding material like `stone_pvc_panel`), `panel_led`; `shelves` (count, e.g. 1 or 2), `shelf_length`, `shelf_depth`, `shelf_thickness`, `shelf_board`, `shelf_led`; `side_units` (count or `{qty, width, height, preset, door_type}`); `tv_bracket`; `cable_management`; `front_board`, `carcass_board` |
| `headboard` (`bed_front`) | `width`, `height`, `qty`, `style` plain/channel/tufted/panelled, `backing_board`, `fabric` |
| `bed_box` (`bed`, `bed_base`) | `size` single/double/queen/king/super_king or `width` + `length`, `height`, `storage` (gas lift), `upholstered` |
| `countertop` (`worktop`, `vanity_top`) | `length`, `depth`, `material`, `sink`, `hob`, `cutouts`, `splashback` (height m) |

### Soft furnishings, supply, other
| type | fields |
|---|---|
| `curtains` | `width`, `height`, `qty` (windows), `layers` [blackout, sheer], `fullness`, `motorised` |
| `blinds` (`roller_blind`) | `width`, `height`, `qty`, `material`, `motorised` |
| `demolition` (`removal`, `strip_out`) | `what` tiles/spc/carpet/gypsum/joinery…, `area` or `rooms`, or `hours` |
| `supply` (`furniture`, `ffe`, `appliance`, `decor`) | `name`, `qty`, `cost` (unit purchase), `sell` (unit) or `markup_pct` (default `ffe_markup_pct`), or `material`; `install_hours` |
| `custom` (`lump_sum`) | `lines`: `{material: key, qty}`, `{trade: key, hours}`, or `{description, cost, sell, qty, unit}`; plus `includes`, `description` |

## Quick rough estimate (no floor plan)

```yaml
project: {client: Ms. Sara, name: JVC 2BR refresh, typology: 2br, total_area: 110}
scope:
  - {title: SPC Flooring, type: flooring, rooms: dry}
  - {title: Painting, type: painting, surfaces: both}
  - {title: Master Wardrobe, type: wardrobe, width: 2.4}
```
