# NexaFix Scan

An internal iPhone app for site visits. Walk through an apartment or office with the LiDAR sensor,
and get the rooms mapped in 3D, a floor plan with every wall length and corner angle, and files you can send on:
a PDF plan, a CAD drawing, a 3D model and a costing spec for the quotation engine in this repo.

Joinery is cut from these numbers, so the app keeps two kinds of dimension apart: **scanned** (LiDAR,
typically within 1–2 %) and **verified** (you measured it with a laser and typed it in). Exports use the
verified number whenever there is one, and a scanned number is never styled like a verified one.

## What you need

| | |
|---|---|
| iPhone | Pro or Pro Max with LiDAR (you have an iPhone 17 Pro Max). iOS 17 or later. |
| Mac | Xcode 26 or later (you have Xcode 27). |
| Account | A free Apple ID is enough to run it on your own phone. The paid developer account ($99/yr) is only needed for TestFlight / App Store, which an internal tool does not need. |
| Homebrew | To install XcodeGen. If you do not have it: <https://brew.sh> |

Without LiDAR (an older iPhone, an iPad without LiDAR, or the Simulator) everything except scanning
still works: demo data, verification, plans, the 3D viewer and exports. The Simulator even offers a
"Simulate a scan" button so you can try the whole flow.

## Install it on your iPhone (first time, about 15 minutes)

1. **Get the code** (skip if you already have it):
   ```bash
   git clone https://github.com/themohmo/NexaFix.git
   cd NexaFix
   git checkout claude/gallant-ride-jzhsjk
   ```
2. **Install XcodeGen** (one time). It builds the Xcode project from `ios/project.yml`:
   ```bash
   brew install xcodegen
   ```
3. **Generate and open the project**:
   ```bash
   cd ios
   xcodegen generate
   open NexaFixScan.xcodeproj
   ```
4. **Signing.** In Xcode click the blue project icon, choose the **NexaFixScan** target, open
   **Signing & Capabilities**, and under **Team** pick your Apple ID (add it with *Add an Account…* if it is
   not listed). If Xcode says the bundle identifier is not available, change **Bundle Identifier** to
   something unique, for example `com.yourname.nexafixscan`. Then run **once**
   `ios/tools/remember-signing.sh`: it saves your Team (and identifier) in `ios/Config/Local.xcconfig`, which
   git ignores, so you do not have to pick it again each time `xcodegen generate` re-creates the project.
5. **Prepare the phone.** Plug it in and tap *Trust* on the phone. Then, on the phone, turn on
   **Settings ▸ Privacy & Security ▸ Developer Mode** (it restarts the phone once).
6. **Run.** Choose your iPhone in the device menu at the top of Xcode and press **▶**. The first time,
   Xcode spends a few minutes preparing the phone. Use the **NexaFixScan** scheme while fixing build
   errors; for real site scans choose the **NexaFixScan Release** scheme (Debug builds are unoptimised and
   the geometry and AR code is noticeably slower in them).
7. **First launch with a free Apple ID.** If the phone says the developer is not trusted, go to
   **Settings ▸ General ▸ VPN & Device Management**, tap your Apple ID and choose **Trust**. A free-account
   install stops opening after 7 days; press ▶ in Xcode again to renew it. Your saved scans are kept.

If the build shows errors, copy them to Claude (the red messages in Xcode's issue list). See
[What has and has not been tested](#what-has-and-has-not-been-tested): the app layer has never been compiled
by Apple's tools, so one or two small errors on the very first build would not be surprising.

## Using the app

### Try the demo first
On the empty home screen tap **Try the demo apartment**: a two-bedroom Marina Gate flat with some
dimensions already verified and a few not. Open it, tap a wall in the plan, press **Verify**, export a
PDF. Nothing needs LiDAR.

### Scan a property
1. **New scan**, enter the property name and client (the reference is suggested), **Start scanning**.
2. Allow the camera when asked. Walk slowly along the walls, aim at the corners and the ceiling edge,
   and wait for the room to appear. Tap **Finish room**.
3. Name the room, then **Scan next room** or **Finish property**. Rooms are merged into one 3D model.

For the best scans: good light; open the doors between rooms and keep going without stopping the
session; keep each room under about 9 × 9 m; do not scan through mirrors, glass or very dark glossy
surfaces (the sensor is fooled by them); do the whole level in one go. Rooms scanned in a later visit
appear as a separate level/drawing, because they cannot be placed on the same plan.

### Check dimensions with a laser (the important part)
Open a room (or tap a wall in the plan) and tap any dimension: **Verify**. Type what your laser shows,
in any unit (`3245`, `3.245 m`, `10' 7 3/4"`), pick Laser / Tape / Drawing and save. You see at once
how far the scan was off. The badge turns green and every export, the plan labels and the costing spec
use your number from then on. The room's checklist shows what is still unchecked, wall lengths, ceiling
height and opening sizes first, because those are what joinery depends on.

### Review in AR
Open the property, tap **AR**, stand where you started scanning and look at the walls you scanned. When
the status says it is lined up, wall lengths, corner angles (red if the corner is out of square), door and
window sizes and the floor area float on the real room. **Measure** places two points with the LiDAR and
reads the distance. The overlay is never drawn until AR has really lined up with the scan, so a number
is never shown on the wrong wall.

### 3D viewer
The **3D** tab shows the whole level with real door and window openings. **Measure** snaps to corners
and edges: use it months later to take a measurement you forgot. Save it with a name and it is stored on
the room. A tape measurement from the model is a scan-derived number, so it is marked as scanned.

### Export
**Export** offers six outputs. They go through the iOS share sheet (AirDrop, Mail, Files, WhatsApp…).

| Output | What it is |
|---|---|
| Floor plan PDF | Scaled plan per level with dimensions, angles and a room schedule. A disclaimer is printed on every page. |
| CAD drawing DXF | Editable drawing in millimetres for AutoCAD and other CAD programs, one file per level, with layers. |
| 3D model USDZ | The scanned model of each level; opens in AR Quick Look and most 3D tools. |
| Data JSON | Everything in one file for other software. Format: [`docs/SCAN-FILE-FORMAT.md`](docs/SCAN-FILE-FORMAT.md). |
| Spreadsheets CSV | Rooms, walls, openings and objects as tables for Excel / Numbers. |
| Costing spec | Room sizes in the form the costing engine reads. |

The export screen states how many dimensions are laser-verified before you send anything.

Your data stays on the phone, and in its iPhone backup if you back it up; nothing is sent anywhere unless you export it. It is in the Files app under **On My iPhone ▸ NexaFix Scan**.

### From scan to quote
Send the costing spec to your Mac (or to Claude), then:
```bash
python skills/nexa-costing/scripts/from_scan.py NexaFix_<…>_costing-spec.json --starter --out spec.json
python skills/nexa-costing/scripts/estimate.py spec.json
```
`--starter` adds flooring and painting for a rough budget; use `--scope scope.yaml` for the real scope.
The script lists any joinery dimension nobody has verified with a laser. Treat the number as a budget
until that list is empty, and use `--strict` for anything that goes to a client. Details:
`skills/nexa-costing/references/intake.md`, section 5.

## How accurate is it?

LiDAR scanning on an iPhone is typically within 1–2 % (about 2 cm on a 3 m wall) and can be worse near glass,
mirrors and dark glossy surfaces. That is fine for layouts and budgets, not for cutting a wardrobe.
**Verify every dimension joinery is cut to with a laser.** After you have verified some,
**Settings ▸ How accurate is my phone?** shows your real error from your own checks, so you learn how far
to trust a scan in your kind of rooms.

## When something goes wrong

| What you see | What to do |
|---|---|
| `xcodegen: command not found` | `brew install xcodegen` (install Homebrew first from brew.sh) |
| *Signing requires a development team* | Pick your Team (step 4), then run `ios/tools/remember-signing.sh` so it survives re-generating. |
| *Failed to register bundle identifier* / *not available* | Change the Bundle Identifier in Signing & Capabilities to something unique, then run `ios/tools/remember-signing.sh`. |
| `xcodegen generate` fails | Send the message to Claude. The least essential lines in `project.yml` are `xcodeVersion`, the `configFiles` block and the second scheme; removing them still leaves a working project. |
| *Untrusted developer* on the phone | Settings ▸ General ▸ VPN & Device Management ▸ Trust. |
| *Developer Mode required* | Settings ▸ Privacy & Security ▸ Developer Mode ▸ On, restart. |
| Scan button says LiDAR is needed | The device has no LiDAR (iPhone Pro / iPad Pro only). |
| *Not lined up* in AR | Go back to where you started the scan and look at the walls you scanned; tap **Keep trying**. |
| A red "not saved" banner | The save failed (usually a full phone). Free some space and tap **Try again**; your work is still in memory, do not close the app. |
| Build errors in Xcode | Copy the red messages to Claude. |

## What has and has not been tested

- **Tested (about 1,100 automated Swift tests and 240 Python tests, run on Linux):** all geometry and
  logic: rebuilding rooms from scan data, corner angles, unit parsing, verification, the PDF / DXF / CSV / JSON /
  costing exports (the DXF opened with a CAD library, the PDF rendered and inspected, the costing spec priced by
  the real engine), storage and crash recovery, and the AR / 3D / plan logic.
- **Checked against Apple's documentation, never compiled or run:** everything that touches SwiftUI, ARKit,
  RealityKit and RoomPlan. The machine this was built on has no Apple SDKs. All 49 app files were compiled
  *together* against the real core using stand-in modules whose signatures were copied from Apple's
  documentation (`ios/tools/typecheck`), and every Apple API call was audited against the docs, including
  what iOS 26/27 renamed or deprecated. That proves the app is consistent with itself and with what the docs
  say. It does not prove Apple's real compiler agrees, so **expect a small number of build errors the first
  time** (send them to Claude) and a few harmless warnings.
- **Not yet seen on a device:** how it looks and feels, how well real RoomPlan data reconstructs rooms, and
  whether AR lines up. The first real scans decide the tuning.

### First-run checklist (about 30 minutes)

Please go through these once and tell Claude what you see:

1. **It builds and opens.** Run the demo apartment: select a wall, **Verify**, export a PDF.
2. **A scan completes.** Scan two rooms. If scanning stops with an "AR configuration" message or the room
   never appears, tell Claude first: it points at one specific setting.
3. **The scan screen is readable.** Apple's own coaching text sits at the top of the camera view; check it does
   not overlap the app's pills or the close button.
4. **Accuracy.** Pick one room whose walls you have measured with a laser. Compare each wall in the app with
   the laser, then verify them in the app. Send the numbers to Claude.
5. **AR lines up.** Tap **AR**, stand where you started scanning and look at the walls. The status should
   reach *Lined up* within a few seconds; the labels should sit on the right walls.
6. **Plan and 3D feel right.** Pinch and double-tap the plan; in 3D, **Measure** between two corners.
7. **Exports open.** The PDF in Preview, the DXF in your CAD program, the CSV in Numbers or Excel.
8. **Costing hand-off.** Run `from_scan.py` on the costing spec, then `estimate.py`.

## For developers

```
ios/
  project.yml          XcodeGen project definition (the .xcodeproj is generated, not committed)
  NexaFixCore/         Swift package, Foundation only, tested on Linux and in Xcode
    Sources/NexaFixCore  Model, Geometry, Units, Capture (RoomReconstructor), Measure, Overlay,
                         Scene, Plan, Drawing, Export (PDF, DXF, JSON, CSV, costing), Storage, Flow, Sample
    Tests/               1,000+ tests
  NexaFixScan/         the SwiftUI app: App, DesignSystem, Capture, AR, Plan, Viewer, Screens, Resources
  docs/DESIGN.md       design language (colour, type, motion, haptics, screens)
  docs/SCAN-FILE-FORMAT.md   JSON / CSV / costing spec formats
  Config/              signing (Signing.xcconfig; your own Local.xcconfig is git-ignored), generated Info.plist
  tools/               icon generator, preflight.py (build-config + privacy checks), remember-signing.sh,
                       typecheck/ (compiles the whole app against the real core with Apple stand-ins)
```

Run the core tests (Mac or Linux): `cd ios/NexaFixCore && swift test`.
Check the build configuration and privacy manifest: `python3 ios/tools/preflight.py`.
Regenerate the app icon: `python3 ios/tools/make_icon.py`.
The Python side (costing engine and the scan bridge): `python3 -m pytest -q` from the repo root.
Design principles: `docs/DESIGN.md`. The app follows Apple's design principles: simple, one primary action
per screen, springs, touch-down feedback, Dynamic Type, Reduce Motion / Transparency, and Liquid Glass on iOS 26+.
