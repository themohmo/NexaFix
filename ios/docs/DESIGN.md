# NexaFix Scan — design language

Internal tool for site visits. One job: walk into a room, scan it, trust the numbers, send them on.
The interface follows Apple's own design principles (purpose, agency, responsibility, familiarity,
flexibility, simplicity, craft, delight) and the fluid-interface rules from *Designing Fluid Interfaces*,
translated into SwiftUI.

## What the app is for (purpose)

Three verbs, in this order of prominence: **Scan**, **Check**, **Send**.

- *Scan*: room by room, one continuous AR session, no setup.
- *Check*: every dimension shows whether it is **scanned** (LiDAR, ±1–2 %) or **verified** (a person
  measured it with a laser). Joinery is cut from verified numbers only.
- *Send*: PDF plan, DXF for CAD, USDZ 3D model, JSON/CSV data, costing spec for quotes.

Everything else lives one level deeper. A property has four things on screen: the plan, the rooms,
the 3D model, the export button.

## Principles → concrete rules

| Principle | Rule in this app |
|---|---|
| Purpose | One primary action per screen. No dashboards, no onboarding carousel. |
| Agency / forgiveness | Every verification can be edited or cleared. Confirmation dialogs only for deleting a property or room. Scan can be cancelled at any moment without losing earlier rooms. |
| Responsibility | A scanned number is never styled like a verified one. The joinery disclaimer (`ScanAccuracy.joineryDisclaimer`) sits on the export sheet and every PDF. Camera permission is explained before the system prompt. Nothing leaves the phone unless the user exports. |
| Familiarity | `NavigationStack`, large titles, sheets with detents, swipe actions, context menus, `ShareLink`, SF Symbols. No custom navigation. |
| Flexibility | Units are the user's choice (mm / cm / m / in / ft-in; m² / sq ft). Dynamic Type everywhere. iPad and landscape work. A device without LiDAR can still open, measure (3D viewer), verify and export saved scans. |
| Simplicity | Show the common path; advanced options (scale, paper, layers) are one tap deeper. Labels name what a thing is ("Wall A", "Door 1"), never "Item". |
| Craft | 8-pt grid, one corner-radius scale, tabular numerals for all measurements, aligned baselines, consistent icon weights. |
| Delight | Springs that carry momentum, haptics on the moments that matter (a snap, a verification saved, a room finished), a calm warm palette. |

## Colour

Warm neutrals with one bronze accent (the NexaFix brand palette from the quotation PDFs). Define as
dynamic colours (light/dark) in `Theme.swift`; never hard-code hex elsewhere.

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#FBF8F3` | `#141311` | screen background |
| `surface` | `#FFFFFF` | `#1E1C19` | cards, grouped rows |
| `ink` | `#1F1D1A` | `#F4EFE8` | primary text, numbers |
| `muted` | `#716A60` | `#A39A8E` | secondary text, units |
| `line` | `#DDD3C4` | `#3A3631` | hairlines |
| `accent` | `#8A6C45` | `#B8956A` | primary buttons, selection, plan highlight |
| `verified` | `#2F7A4B` | `#5BB77E` | laser-verified values |
| `caution` | `#9C5C00` | `#E0A04B` | scanned-only joinery dimensions, out-of-square < 3° |
| `critical` | `#B3261E` | `#F0776E` | out-of-square ≥ 3°, failures |

The light-mode `muted`, `accent` and `caution` are a shade darker than the print palette of the quotation PDFs
(`#7A7268`, `#9C7B52`, `#B26A00`) so that text and white-on-accent buttons reach WCAG AA 4.5:1
(muted 5.0:1, white on accent 4.9:1, caution 5.0:1). Dark-mode values already pass.

Rules: colour is never the only signal (verified also has a check-mark glyph, caution has a
triangle, out-of-square shows the number). Accent is for the one thing you should do next.
Translucent surfaces never sit on other translucent surfaces.

## Type

System font (SF Pro) with Dynamic Type text styles; no custom faces except the letter-spaced
"NEXAFIX" wordmark (system font, `.light`, tracking +0.18 em, small caps feel).

- Measurements: `.monospacedDigit()`, units one weight lighter and `muted`.
- Hero numbers (area, a selected length): 44–56 pt `.light`/`.regular`, tracking −0.02 em (large text
  wants negative tracking; small text near 0, captions +0.01 em).
- Titles: `.largeTitle` / `.title2` semibold; leading tight on large text, relaxed on body.
- Scale with the user's text size: spacing in multiples of 4/8 pt via `@ScaledMetric` where text is
  adjacent.

## Shape, depth, materials

- Corner radii: 10 (chips, fields), 16 (rows, small cards), 24 (large cards, sheets), capsule for pills.
  Use `.continuous` corners everywhere.
- Content screens are flat: `background` + `surface` cards, hairline `line` borders, no drop shadows.
- *Floating* controls over live content (scan HUD, AR toolbar, 3D toolbar, measurement readout) use
  `.ultraThinMaterial` / `.regularMaterial` with a 0.5 pt inner highlight stroke (`white.opacity(0.35)`)
  on the top edge, so they read as glass. Bigger floating surfaces are thicker (`.regularMaterial`,
  softer larger shadow); small chips are lighter. Never stack translucent on translucent.
- Text over materials uses `ink` at full strength with `.semibold` for small sizes (vibrancy), never a
  flat grey.
- Respect `accessibilityReduceTransparency`: swap materials for opaque `surface`.
  Respect `accessibilityContrast`/`colorSchemeContrast == .increased`: add a 1 pt `line` border.

## Motion (the fluid-interface rules)

- **Respond on touch-down.** Buttons use a custom `ButtonStyle` that scales to 0.97 and dims
  immediately on `isPressed` (no waiting for release). Rows highlight on press.
- **Springs, not durations.** Default spring: `response 0.35, dampingFraction 1.0` (critically damped,
  no bounce) for appearing/disappearing/reordering. Use `response 0.30, dampingFraction 0.80` only when
  a gesture carried momentum (a flicked sheet, a thrown plan). Define them once as `Motion.standard`
  and `Motion.momentum`.
- **Interruptible and 1:1.** Drags track the finger exactly from the grab point; pinch/pan on the plan
  and the 3D viewer are never blocked by an animation, and a running animation re-targets from its
  *current* value. Use `.interactiveSpring()` while a gesture is live; on release hand the gesture's
  predicted end (`predictedEndTranslation`, i.e. momentum projection) to the settle spring.
- **Rubber-band at edges** (plan pan beyond the drawing, zoom beyond limits): progressive resistance
  instead of a hard stop.
- **Symmetric paths.** Things leave the way they came: a sheet presented from the bottom dismisses
  to the bottom; the measurement readout that grows out of the tapped point shrinks back into it
  (`matchedGeometryEffect` / anchor-based scale).
- **Reduced motion:** with `accessibilityReduceMotion`, replace slides/scales/springs with short
  cross-fades (≤ 0.2 s) and keep colour/opacity changes that aid comprehension.
- Animate only what changes meaning (selection, state, appearance of controls). Live AR overlays do
  not animate position at all: they are glued to the world every frame.

## Haptics (and only these)

| Moment | Feedback |
|---|---|
| Measurement point snaps to a corner/edge | `UISelectionFeedbackGenerator` selection tick |
| Verification saved | `UINotificationFeedbackGenerator` .success |
| Room finished / property saved | `UIImpactFeedbackGenerator` .medium, then success on save |
| Tracking lost / scan error | .warning |
| Toggle (dimensions / angles / etc.) | `.sensoryFeedback(.selection)` |
Fire haptics on the same frame as the visual change. Provide `Haptics` as a tiny wrapper that is a
no-op in the simulator and when the user disabled haptics in Settings.

## Screens

1. **Properties** (home). Large title. Cards: mini floor plan thumbnail (rendered from the same
   `PlanDrawing`), name, client, "8 rooms · 112 m² · 14 of 52 checked", thin progress bar in
   `verified`. Search. Empty state: the app mark, one sentence, **Scan a property** (accent) and a
   quiet **Try the demo apartment**. Primary action floats at the bottom.
2. **Property.** Header (name, address, reference). A segmented control: **Plan · Rooms · 3D**.
   Plan: pannable/zoomable plan, tap a wall/corner/opening to select it (selection card slides up
   with the value, its provenance and a **Verify** button). Floor chips if more than one floor.
   Bottom floating bar: **Scan room · AR · Export**.
3. **Room.** Hero: area (large), then length × width, perimeter, ceiling height, volume. Sections:
   *Dimensions* (walls, ceiling, openings: each row shows value, a ✓ verified / ▲ scanned badge, and
   tolerance for scanned), *Corners* (angle, deviation from 90°, out-of-square highlighted),
   *Openings*, *Objects*, *Notes*. A checks ring: "9 of 21 checked". Tapping a row opens **Verify**.
4. **Verify** (sheet, medium detent). The scanned value, a big numeric field that parses what you
   type in any unit ("3245", "3.245 m", `10' 7 3/4"`), live deviation ("scan read 12 mm short,
   0.4 %"), a source selector (Laser · Tape · Drawing), optional note, **Save** (success haptic) and
   **Clear**. Keyboard: decimal pad with a unit switcher above it.
5. **Scan** (full-screen cover). Apple's capture view full-bleed. A glass pill at the top carries the
   coaching instruction; live measurement labels float on the walls being detected; bottom: **Finish
   room** (accent) and **Cancel**. After a room: a small sheet to name it (suggestions from
   `RoomKind`), then **Scan next room** or **Finish property**.
6. **AR review.** Camera full-bleed with the saved room overlaid: wall lengths as glass labels with
   dimension ticks, corner angle arcs with degrees, door/window sizes, ceiling height, floor area at
   the centre. Bottom glass bar toggles *Dimensions · Angles · Openings*, plus **Measure** (tap two
   points; a LiDAR-snapped tape measure). A status pill says what AR is doing ("Relocalising — look
   at the room you scanned").
7. **3D viewer.** Orbit/zoom, walls with real door and window cut-outs, floor, objects as boxes.
   **Measure**: tap two snap points, readout shows length and ΔX/ΔY/ΔZ; **Save** names it and stores
   it on the room (and it can be verified like any other value). Toggles: ceiling, wall opacity,
   labels.
8. **Export** (sheet). Rows: Floor plan PDF · CAD drawing DXF · 3D model USDZ · Data JSON · Spreadsheets
   CSV · Costing spec. Options behind a disclosure (paper, scale, units). A banner states how many
   dimensions are laser-verified, and the joinery disclaimer. Output goes through the system share
   sheet / Files.
9. **Settings.** Length unit, area unit, haptics, accuracy report ("12 checks: typically 6 mm
   (0.3 %), worst 21 mm"), about + disclaimer.

## Writing

Plain, specific, sentence case. "Scan next room", not "Continue". "Wall A is 3 245 mm" in
VoiceOver, never "3245". Errors say what happened and what to do ("Tracking was lost. Move back to
the doorway and look at the last wall you scanned.").

## Accessibility

VoiceOver labels on every measurement ("Wall A, length 3 245 millimetres, verified with laser"),
Dynamic Type up to AX5 (rows reflow vertically), 44 pt minimum hit targets (use `contentShape`),
`accessibilityReduceMotion` / `accessibilityReduceTransparency` / increased contrast honoured,
colour never the sole signal.
