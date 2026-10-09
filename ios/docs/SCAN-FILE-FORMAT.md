# NexaFix Scan: file formats

What the app saves and exports, field by field, and how to use each file. Everything here is
produced by `NexaFixCore` (`Export/Data/` and `Storage/`) and the examples below are real output,
not hand-written (see [Regenerating the examples](#regenerating-the-examples)).

| File | Made by | Format | Use it for |
|---|---|---|---|
| `NexaFix_<Property>_<date>_scan.json` | `ScanExport` | JSON, schema `nexafix.scan` v1 | Archive of everything: geometry, every dimension with its provenance. Scripts, audits, re-import. |
| `rooms.csv`, `walls.csv`, `openings.csv`, `objects.csv` (+ `custom_measurements.csv`) | `CSVExport` | CSV, UTF-8 with BOM | Excel / Numbers / pandas: cut lists, measurement review, checking what was verified. |
| `NexaFix_<Property>_<date>_costing-spec.json` | `CostingSpecExport` | JSON for the nexa-costing engine | Pricing. Finish it with `skills/nexa-costing/scripts/from_scan.py`, then `estimate.py`. |
| `<app storage>/<PROPERTY-UUID>/property.json` | `PropertyStore` | JSON envelope, schema version 1 | The app's own working copy. Not an interchange format. |

## Conventions (all files)

- **Lengths are metres, angles are degrees.** Rounded to 0.1 mm (angles to 0.001 degree) so float
  noise like `3.0000000000000004` never appears. The CSV can show other units; the JSON and the
  costing spec never do.
- **Plan space**: `x` east, `y` north when the floor plan is drawn top-down (world X, and minus world Z).
  Rooms are listed counter-clockwise, so the room is on the LEFT of every wall: wall `i` runs from corner
  `i` to corner `i + 1`. Custom measurements are the one exception: their end points are 3D world
  points (Y up) in the scan session's frame.
- **Provenance.** Every dimension is LiDAR-scanned, laser/tape-verified, or both. The scanned number
  is never overwritten; a verified number sits next to it. **Use `valueM`** (verified when there is
  one, scanned otherwise), and treat a dimension with `verifiedM: null` as an estimate. LiDAR is typically
  within 1-2 %, which is not good enough to cut joinery from. No export ever labels a scanned number as verified.
- **Dates** are ISO 8601 in UTC with milliseconds: `2026-10-08T09:30:00.000Z`. The *file name* date is the Dubai
  date (UTC+04:00).
- **Text** is UTF-8. Names keep their original characters (Arabic, accents, emoji).
- **Deterministic**: the same property gives byte-identical files (sorted JSON keys, model order for
  floors, rooms, walls; openings by wall then position). The only clock reading is the `generatedAt`
  the caller passes in.
- **Scan file: nothing is omitted.** Optional fields are written as `null`, not left out. (The costing spec is the exception:
  it leaves out a key where the engine would misread it, see below.)

## File names

`NexaFix_<Property>_<yyyy-MM-dd>_<kind>.<ext>`, for example `NexaFix_Marina-Gate-2304_2026-10-09_scan.json`.
`ExportNaming` keeps only ASCII letters, digits, `-`, `_` and `.`: spaces, slashes, colons, quotes and emoji
become a single `-`, accents are folded (`Cafe`), `&` becomes `and`, apostrophes vanish, names are cut at
40 characters, and a name with nothing usable left (empty, emoji only, Arabic only) becomes `Property`.
`ExportNaming.uniqueName` appends `-2`, `-3` ... on a clash (case-insensitively, as iOS and Windows do).

## The scan file: `nexafix.scan` v1

Top level:

| Key | Type | Meaning |
|---|---|---|
| `schema` | string | Always `"nexafix.scan"`. |
| `version` | int | `1`. Incompatible changes bump it; new optional keys do not, so ignore keys you do not know. |
| `generatedAt` | string | When the export was made. |
| `generator` | string | `"NexaFix Scan"`. |
| `units` | object | `storage: "metres"`, `angles: "degrees"`, `coordinates:` a sentence describing plan space. |
| `property` | object | `id, name, client, address, reference, kind, notes, createdAt, updatedAt`. `kind` is `apartment`, `villa`, `office`, `retail` or `other`. |
| `summary` | object | `roomCount, floorCount, totalFloorAreaM2, indoorFloorAreaM2, verifiedCount, measurementCount, joineryVerifiedCount, joineryMeasurementCount`. Areas are the sums of each room's `effectiveFloorAreaM2` (indoor excludes balconies). The counts are over **checkable dimensions** (see below). |
| `floors[]` | array | `id, name, level, assets{structureUSDZ, worldMap}, rooms[]`. `level`: 0 ground, -1 basement. |

### Measured object

Every dimension (wall length and height, ceiling height, opening width / height / sill, custom measurement):

| Key | Meaning |
|---|---|
| `scannedM` | What LiDAR measured. Never changes. |
| `verifiedM` | What a person measured on site; `null` if nobody did. |
| `valueM` | **The number to use**: `verifiedM` if present, else `scannedM`. |
| `source` | `"laser"`, `"tape"` or `"drawing"`; `null` if unverified. |
| `verifiedAt` | When it was verified; `null` if unverified. |
| `note` | Free text from the person who verified it; may be `null`. |
| `deviationM` | `verifiedM - scannedM`. Positive means the scan read short. `null` if unverified. |

### Room

| Key | Meaning |
|---|---|
| `id, name, kind` | `kind` is the `RoomKind` raw value: `livingRoom, dining, kitchen, bedroom, masterBedroom, bathroom, corridor, entrance, balcony, maidsRoom, laundry, storage, office, meetingRoom, reception, other`. |
| `floorAreaM2` | Area of the scanned outline (geometry; verification never moves a wall). |
| `effectiveFloorAreaM2` | Area to use: for a rectangle, `lengthM x widthM` from the effective side lengths (so verified walls flow in); otherwise the outline area. |
| `perimeterM`, `wallPerimeterM` | Sum of effective wall lengths: all walls / solid walls only (open-plan boundaries excluded). |
| `ceilingHeight` | Measured object. |
| `isRectangular`, `lengthM`, `widthM` | A room is a rectangle when it has four sides with every corner within 5 degrees of square. `lengthM` (longer) and `widthM` (shorter) are `null` otherwise. |
| `volumeM3` | Outline area x effective ceiling height. |
| `grossWallAreaM2`, `openingAreaM2`, `netWallAreaM2` | Solid wall length x wall height; doors, windows and openings on solid walls (effective sizes); gross minus openings, never negative. |
| `corners[]` | `index, x, y, interiorAngleDeg, deviationFrom90Deg, isReflex, isOutOfSquare`. Interior angle is 0..<360 (the inside of an L-shape reads about 270). `isOutOfSquare`: more than 1 degree from square; straight continuations and reflex corners are not flagged. Empty for a loop of fewer than three walls. |
| `walls[]` | `id, index, label, start{x,y}, end{x,y}, kind, isCurved, length, height`. `label` is `Wall A`, `Wall B` ... by loop index. `kind` is `solid` or `virtual` (an open-plan boundary: no wall, no wall area). `length` and `height` are measured objects. |
| `openings[]` | `id, kind, label, wallId, wallIndex, offsetFromStartM, offsetFromEndM, width, height, sillHeight`. `kind`: `door`, `window`, `opening` (doorless passage). `label`: `Door 1`, `Window 2` ... numbered per kind in wall order. `offsetFromStartM`: wall start corner to the opening's near edge, in the LiDAR geometry. `offsetFromEndM`: far edge to the wall's end corner (wall length - offset - scanned width). `wallId` / `wallIndex` / `offsetFromEndM` are `null` for an opening not matched to a wall. |
| `objects[]` | RoomPlan's furniture: `id, kind, center{x,y}, yawDeg, widthM, depthM, heightM, elevationM`. `yawDeg` is 0..<360 counter-clockwise from plan +x. These are estimates and cannot be verified. |
| `customMeasurements[]` | Tape-measure readings taken in the AR view: `id, label, a{x,y,z}, b{x,y,z}, length, createdAt, note`. `a`, `b` are world points (Y up). `length` is a measured object. |
| `verification` | `verified, total, joineryVerified, joineryTotal`. |
| `scannedAt, floorElevationM, capturedRoomFile, notes` | Housekeeping: when the room was scanned, the floor's world Y in the scan session, the relative path of the saved RoomPlan capture, free notes. |

### What counts as a checkable dimension

`verification`, `summary.measurementCount` and the CSV counts use the same list as the app's on-site checklist
(`VerificationChecklist` in `Measure/`; the exports carry their own copy of its rules, `DataMeasureList`, so they do not
depend on the UI-facing module. Keep the two in step):
each wall's length, each wall's height (not for `virtual` walls), the ceiling height, each opening's width and
height, each opening's sill height (only when the sill is above 5 mm or somebody verified it, so ordinary doors
add none), and each custom measurement. **Joinery-critical** means: wall lengths of solid walls, ceiling height,
opening widths and heights, and custom measurements. Wall heights, sills and open-plan boundary lengths are
checkable but not joinery-critical.

### Annotated example

Real output for the demo property "Marina Gate 2304" (four rooms; only the Living Room has site checks:
wall A and wall C length, ceiling height, and the door width). Lists are shortened: `"…"` stands for omitted entries.
Measured objects are collapsed onto one line. Note the living room: wall A was scanned at 6.2 m and
laser-checked at 6.24 m, so `lengthM` and `effectiveFloorAreaM2` (6.24 x 4.5 = 28.08) use 6.24, while
`floorAreaM2` (27.9) stays the outline area; wall B was never checked, so its `verifiedM` is `null`.

```json
{
  "schema": "nexafix.scan",
  "version": 1,
  "generatedAt": "2026-10-09T10:00:00.000Z",
  "generator": "NexaFix Scan",
  "units": {
    "angles": "degrees",
    "coordinates": "plan space: x east, y north when drawn top-down; world points (custom measurements) are Y up",
    "storage": "metres"
  },
  "property": {
    "id": "00000000-0000-0000-0000-000000000001",
    "name": "Marina Gate 2304",
    "client": "Mr. Ahmed Khan",
    "address": "Dubai Marina, Dubai",
    "reference": "NF-2026-1009-01",
    "kind": "apartment",
    "notes": "Tower B, unit 2304",
    "createdAt": "2026-10-07T08:15:00.000Z",
    "updatedAt": "2026-10-09T09:00:00.000Z"
  },
  "summary": {
    "floorCount": 1,
    "indoorFloorAreaM2": 53.12,
    "joineryMeasurementCount": 31,
    "joineryVerifiedCount": 4,
    "measurementCount": 49,
    "roomCount": 4,
    "totalFloorAreaM2": 59.52,
    "verifiedCount": 4
  },
  "floors": [
    {
      "id": "00000000-0000-0000-0000-000000000002",
      "name": "Level 23",
      "level": 23,
      "assets": {
        "structureUSDZ": "floors/level23.usdz",
        "worldMap": null
      },
      "rooms": [
        {
          "id": "00000000-0000-0000-0000-000000000010",
          "name": "Living Room",
          "kind": "livingRoom",
          "floorAreaM2": 27.9,
          "effectiveFloorAreaM2": 28.08,
          "perimeterM": 21.48,
          "wallPerimeterM": 21.48,
          "ceilingHeight": {"deviationM": 0.05, "note": null, "scannedM": 2.8, "source": "laser", "valueM": 2.85, "verifiedAt": "2026-10-08T09:30:00.000Z", "verifiedM": 2.85},
          "isRectangular": true,
          "lengthM": 6.24,
          "widthM": 4.5,
          "volumeM3": 79.515,
          "grossWallAreaM2": 60.144,
          "openingAreaM2": 9.132,
          "netWallAreaM2": 51.012,
          "corners": [
            {
              "index": 0,
              "x": 0,
              "y": 0,
              "interiorAngleDeg": 90,
              "deviationFrom90Deg": 0,
              "isReflex": false,
              "isOutOfSquare": false
            },
            "…"
          ],
          "walls": [
            {
              "id": "00000000-0000-0000-0000-000000000101",
              "index": 0,
              "label": "Wall A",
              "start": {
                "x": 0,
                "y": 0
              },
              "end": {
                "x": 6.2,
                "y": 0
              },
              "kind": "solid",
              "isCurved": false,
              "length": {"deviationM": 0.04, "note": "tape on skirting", "scannedM": 6.2, "source": "laser", "valueM": 6.24, "verifiedAt": "2026-10-08T09:30:00.000Z", "verifiedM": 6.24},
              "height": {"deviationM": null, "note": null, "scannedM": 2.8, "source": null, "valueM": 2.8, "verifiedAt": null, "verifiedM": null}
            },
            {
              "id": "00000000-0000-0000-0000-000000000102",
              "index": 1,
              "label": "Wall B",
              "start": {
                "x": 6.2,
                "y": 0
              },
              "end": {
                "x": 6.2,
                "y": 4.5
              },
              "kind": "solid",
              "isCurved": false,
              "length": {"deviationM": null, "note": null, "scannedM": 4.5, "source": null, "valueM": 4.5, "verifiedAt": null, "verifiedM": null},
              "height": {"deviationM": null, "note": null, "scannedM": 2.8, "source": null, "valueM": 2.8, "verifiedAt": null, "verifiedM": null}
            },
            "…"
          ],
          "openings": [
            {
              "id": "00000000-0000-0000-0000-000000000132",
              "kind": "door",
              "label": "Door 1",
              "wallId": "00000000-0000-0000-0000-000000000101",
              "wallIndex": 0,
              "offsetFromStartM": 0.5,
              "offsetFromEndM": 4.8,
              "width": {"deviationM": 0.02, "note": null, "scannedM": 0.9, "source": "tape", "valueM": 0.92, "verifiedAt": "2026-10-08T09:30:00.000Z", "verifiedM": 0.92},
              "height": {"deviationM": null, "note": null, "scannedM": 2.1, "source": null, "valueM": 2.1, "verifiedAt": null, "verifiedM": null},
              "sillHeight": {"deviationM": null, "note": null, "scannedM": 0, "source": null, "valueM": 0, "verifiedAt": null, "verifiedM": null}
            },
            "…"
          ],
          "objects": [],
          "customMeasurements": [],
          "verification": {
            "joineryTotal": 9,
            "joineryVerified": 4,
            "total": 13,
            "verified": 4
          },
          "scannedAt": "2026-10-07T08:15:00.000Z",
          "floorElevationM": 0,
          "capturedRoomFile": null,
          "notes": ""
        },
        "…"
      ]
    }
  ]
}
```

Reading it from Python:

```python
import json
scan = json.load(open("NexaFix_Marina-Gate-2304_2026-10-09_scan.json", encoding="utf-8"))
for floor in scan["floors"]:
    for room in floor["rooms"]:
        for wall in room["walls"]:
            m = wall["length"]
            print(room["name"], wall["label"], m["valueM"], "verified" if m["verifiedM"] is not None else "LiDAR only")
```

## The CSV files

Four files, always, plus `custom_measurements.csv` when the property has at least one custom measurement.

- **UTF-8 with a byte order mark** (`EF BB BF`). Excel on Windows opens a BOM-less CSV in the old ANSI code page and
  garbles Arabic, accents and degree signs; the BOM is how it recognises UTF-8. In pandas use
  `pd.read_csv(path, encoding="utf-8-sig")`; Python's `csv` module needs the same encoding.
- **RFC 4180**: `\r\n` line ends (also after the last row), fields with a comma, quote, CR or LF are quoted and
  quotes doubled. A note with a line break stays in one cell.
- **Numbers** are plain ASCII with `.` as the decimal point, no thousands separators, whatever the phone's locale.
- **Units are in the column names.** With the default display units: `_mm` (1 decimal), `_m2` (3 decimals), `_m3`.
  Other choices change the suffix and decimals: `_cm` (2), `_m` (4), `_in` (3), `_ft` (decimal feet, 4; "feet and
  inches" is exported as decimal feet so the column stays numeric), `_sqft` (2), `_ft3` (2).
- **Every measured dimension is four columns in a row**: `X_mm` (the value to use), `X_scanned_mm` (what LiDAR read),
  `X_verified` (`yes` / `no`) and `X_source` (`laser`, `tape`, `drawing`, or empty). When `X_verified` is `no`,
  `X_mm` equals `X_scanned_mm`: the number is an estimate.
- **Formula guard**: free text that starts with `=`, `+`, `-`, `@`, a tab or a CR gets a leading apostrophe so a
  spreadsheet shows it instead of running it. Numbers are never changed (a negative coordinate stays `-1500.0`).
- Rows are in model order: floors, rooms, walls in loop order, openings by wall then position. Every table has the
  `floor`, `room_id` and `room` columns, so rows can be joined back to `rooms.csv`.

Columns (shown with the default units):

**`rooms.csv`**: one row per room.
`floor, level, room_id, room, kind, scanned_at, floor_area_m2, effective_floor_area_m2, perimeter_mm, wall_perimeter_mm,
ceiling_height_mm, ceiling_height_scanned_mm, ceiling_height_verified, ceiling_height_source, is_rectangular, length_mm,
width_mm, volume_m3, gross_wall_area_m2, opening_area_m2, net_wall_area_m2, verified_count, measurement_count,
joinery_verified_count, joinery_measurement_count, walls, openings, objects, notes`.
`length_mm` / `width_mm` are empty unless `is_rectangular` is `yes`; `walls`, `openings`, `objects` are counts.

**`walls.csv`**: one row per wall.
`floor, room_id, room, wall_id, wall_index, wall, kind, curved, start_x_mm, start_y_mm, end_x_mm, end_y_mm,
length_mm, length_scanned_mm, length_verified, length_source, height_mm, height_scanned_mm, height_verified, height_source`.
`wall_index` counts from 0; `wall` is `Wall A`. Coordinates are plan space.

**`openings.csv`**: one row per door, window or opening.
`floor, room_id, room, opening_id, opening, kind, wall_id, wall, offset_from_start_mm, offset_from_end_mm,
width_mm, width_scanned_mm, width_verified, width_source, height_mm, height_scanned_mm, height_verified, height_source,
sill_height_mm, sill_height_scanned_mm, sill_height_verified, sill_height_source, area_m2`.
`area_m2` is the effective width x effective height.

**`objects.csv`**: one row per recognised object.
`floor, room_id, room, object_id, kind, center_x_mm, center_y_mm, yaw_deg, width_mm, depth_mm, height_mm, elevation_mm, verified`.
Objects are RoomPlan estimates and cannot be verified in the app, so `verified` is always `no`.

**`custom_measurements.csv`**: one row per tape-measure reading.
`floor, room_id, room, measurement_id, label, length_mm, length_scanned_mm, length_verified, length_source, created_at, note`.

Real rows from the demo property (first wall, first opening), one column per line:

```
floor                        Level 23
room_id                      00000000-0000-0000-0000-000000000010
room                         Living Room
wall_id                      00000000-0000-0000-0000-000000000101
wall_index                   0
wall                         Wall A
kind                         solid
curved                       no
start_x_mm                   0.0
start_y_mm                   0.0
end_x_mm                     6200.0
end_y_mm                     0.0
length_mm                    6240.0
length_scanned_mm            6200.0
length_verified              yes
length_source                laser
height_mm                    2800.0
height_scanned_mm            2800.0
height_verified              no
height_source                
```

```
floor                        Level 23
room_id                      00000000-0000-0000-0000-000000000010
room                         Living Room
opening_id                   00000000-0000-0000-0000-000000000132
opening                      Door 1
kind                         door
wall_id                      00000000-0000-0000-0000-000000000101
wall                         Wall A
offset_from_start_mm         500.0
offset_from_end_mm           4800.0
width_mm                     920.0
width_scanned_mm             900.0
width_verified               yes
width_source                 tape
height_mm                    2100.0
height_scanned_mm            2100.0
height_verified              no
height_source                
sill_height_mm               0.0
sill_height_scanned_mm       0.0
sill_height_verified         no
sill_height_source           
area_m2                      1.932
```

## The costing spec

`CostingSpecExport` writes the project spec that `skills/nexa-costing` consumes (format: `skills/nexa-costing/references/spec-format.md`).
It follows the engine's parsing rules exactly:

| Spec key | Comes from |
|---|---|
| `project.client / name / location / ref` | Property `client / name / address / reference`. |
| `project.ceiling_height` | The most common effective ceiling height (to 1 cm; the taller one on a tie). The engine uses it only for rooms without a `height`; every room here has one. |
| `rooms[].name` | Room name (empty becomes the kind's name; a repeated name becomes `Name (2)`, because the engine selects rooms by name). |
| `rooms[].length`, `width` | Rectangles only: effective side lengths (verified walls flow in). |
| `rooms[].area`, `perimeter` | Any other room: outline area, and the perimeter of the **solid** walls (an open-plan edge has nothing to paint or skirt). A rectangle with an open-plan edge gets `perimeter` as well. |
| `rooms[].height` | Effective ceiling height. |
| `rooms[].doors`, `windows` | `[[w, h], ...]` in metres, EFFECTIVE sizes (verified when laser-checked). Doorless openings count as doors. Only openings on solid walls count, as in the wall-area maths. Always written, even when empty: an empty list means "none found", while a missing key would make the engine assume one door. |
| `rooms[].tags` | `RoomKind.costingTags` (`living`, `kitchen`, `bedroom`, `bathroom`, `circulation`, `outdoor`, `utility`, `office`). A balcony is `outdoor`, which the engine leaves out of its `all` and `dry` selectors. |
| `rooms[].wet` | `true` for bathroom and laundry, `false` for other known kinds; left out for `other`, so the engine decides from the room name. |
| `scope` | **Always `[]`.** The engine rejects an empty scope, so the file cannot be priced as exported. |
| `x_nexafix_scan` | Extra top-level object the engine ignores. See below. |

**Units are exact.** The engine reads a plain number above 60 (room length / width), 150 (perimeter) or 20 (heights,
door and window sizes) as *millimetres*. A 72.5 m warehouse would silently become 72.5 mm. So a length over its limit
is written as text with a unit, `"72.5m"`, which the engine never rescales. In normal flats every value is a plain number.

`x_nexafix_scan` (keys are snake_case, like the rest of the engine's spec):
`schema` (`"nexafix.costing-spec"`), `version`, `generator`, `property_id`, `scan_date` (Dubai date of the latest room
scan), `verified_count` / `measurement_count` / `joinery_verified_count` / `joinery_measurement_count`, `rooms[]`
(`name, floor, kind, verified, total, joinery_verified, joinery_total`), `unverified_joinery[]`
(`room, item, scanned_m, typical_tolerance_m` for every joinery-critical dimension nobody checked), `warning`
(a sentence, or `null` when everything joinery-critical was verified) and `notes[]` (rooms left out, renamed or
adjusted, openings dropped).

Real output for the same demo property (shortened):

```json
{
  "project": {"ceiling_height": 2.8, "client": "Mr. Ahmed Khan", "location": "Dubai Marina, Dubai", "name": "Marina Gate 2304", "ref": "NF-2026-1009-01"},
  "rooms": [
    {
      "doors": [
        [0.92, 2.1]
      ],
      "height": 2.85,
      "length": 6.24,
      "name": "Living Room",
      "tags": ["living"],
      "wet": false,
      "width": 4.5,
      "windows": [
        [3, 2.4]
      ]
    },
    {"area": 20, "doors": [], "height": 2.8, "name": "Open Plan", "perimeter": 20, "tags": [], "windows": []},
    "…"
  ],
  "scope": [],
  "x_nexafix_scan": {
    "schema": "nexafix.costing-spec",
    "version": 1,
    "generator": "NexaFix Scan",
    "property_id": "00000000-0000-0000-0000-000000000001",
    "scan_date": "2026-10-09",
    "verified_count": 4,
    "measurement_count": 49,
    "joinery_verified_count": 4,
    "joinery_measurement_count": 31,
    "rooms": [
      {"floor": "Level 23", "joinery_total": 9, "joinery_verified": 4, "kind": "livingRoom", "name": "Living Room", "total": 13, "verified": 4},
      {"floor": "Level 23", "joinery_total": 7, "joinery_verified": 0, "kind": "bathroom", "name": "Master Bathroom", "total": 11, "verified": 0},
      "…"
    ],
    "unverified_joinery": [
      {"item": "Wall B length", "room": "Living Room", "scanned_m": 4.5, "typical_tolerance_m": 0.0675},
      {"item": "Wall D length", "room": "Living Room", "scanned_m": 4.5, "typical_tolerance_m": 0.0675},
      "…"
    ],
    "warning": "27 of 31 joinery-critical dimensions are LiDAR-scanned only and have not been verified on site. LiDAR dimensions are typically within 1-2 %. Verify every dimension joinery will be cut to with a laser measure. Treat this as a budget estimate until they are verified.",
    "notes": []
  }
}
```

### From the app to a quote

```
python skills/nexa-costing/scripts/from_scan.py NexaFix_Marina-Gate-2304_2026-10-09_costing-spec.json --starter --out spec.json
python skills/nexa-costing/scripts/estimate.py spec.json
```

- `--scope scope.yaml` (or `.json`) adds the real scope; the file is a list of scope items, or a mapping with
  `scope:` and optional `project:` keys (VAT, discount, salutation ...) merged over the scan's project block.
- `--starter` appends a rough-budget scope: SPC flooring for the dry rooms, painting (walls and ceilings) for all
  indoor rooms. A starter item is skipped when the scope already has that kind of item. `--scope` and `--starter` combine.
- It refuses to write an empty scope, validates the rooms and scope through `nexa_costing.spec`, and checks that every
  room selector matches a scanned room. `--check` also dry-runs the engine (no PDFs).
- When `unverified_joinery` is not empty it prints a warning block on stderr (the first 15 dimensions, with the scanned
  size and typical tolerance). `--strict` turns that into exit code 3. The quote is a budget until the dimensions are verified.
- JSON goes to stdout unless `--out` is given; warnings and notes always go to stderr.

## Property storage (`property.json`)

The app keeps one folder per property under its storage root, named by the property id:

```
<root>/<PROPERTY-UUID>/property.json           {"schemaVersion": 1, "property": { ... }}
<root>/<PROPERTY-UUID>/property.json.bak       the previous good property.json
<root>/<PROPERTY-UUID>/property.json.corrupt   a damaged property.json, kept aside after a recovery
<root>/<PROPERTY-UUID>/...                     assets (USDZ, RoomPlan JSON, world maps), by relative path
```

- The `property` value is the app's model encoded as-is: dates are ISO 8601 strings with a fractional part that
  reads back to exactly the same instant; lengths are metres at full precision (unlike the exports, nothing is rounded).
- **Atomic**: a save writes a temporary file and swaps it in, so a crash leaves the old file or the new one.
  Before replacing a `property.json` that still decodes, its bytes become `property.json.bak`. A damaged file is never
  promoted to backup. Saving the identical content again changes nothing.
- **Recovery**: if `property.json` does not decode, `load` returns the backup and reports `recoveredFromBackup`
  (`PropertySummary.health` says the same in the list). If both are unreadable the property is listed as `unreadable`
  instead of vanishing, and `load` throws.
- **No silent edits**: `save` stores exactly what it is given; `updatedAt` changes only when the caller passes a date.
- **Versions**: unknown keys are ignored. A file written by a newer app (`schemaVersion` above 1) is refused, not
  guessed at, and is never overwritten. Older shapes go through registered migrations; a bare property with no envelope
  (version 0) is upgraded automatically. A change an older build cannot read, such as a new case in a model enum
  (`RoomKind`, `ObjectKind` ...), must bump `schemaVersion`: an unknown enum value makes the whole file fail to
  decode, and an older build would then treat it as damage and fall back to the backup.
- **Asset paths** (`resolve`, `writeAsset`, `readAsset`) must be relative and stay inside the property folder: empty
  paths, absolute paths, `~`, `.` / `..` components, backslashes and control characters are refused, and so are
  symlinks (including dangling ones) that lead out of the folder. The store's own files cannot be overwritten as assets.
- `duplicate` copies a property with new ids for the property, floors, rooms, walls, openings, objects and custom
  measurements (openings keep pointing at the copies of their walls) and copies the asset files to the same relative paths.

## Regenerating the examples

The examples in this document, and the fixture `tests/fixtures/scan_costing_spec.json` used by `tests/test_from_scan.py`,
come from a Swift test that writes them when asked:

```
cd ios/NexaFixCore
NEXAFIX_FIXTURE_DIR=/some/folder swift test --filter DataExportTests/testWriteFixturesWhenRequested
```

`scan_costing_spec.json` goes to `/some/folder`; the demo property's exports (scan JSON, costing spec, CSVs) go to
`/some/folder/example/`. Without the variable the test only checks that the fixture builds.
