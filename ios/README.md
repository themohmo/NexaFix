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
| Mac | Xcode 26 or later (you have Xcode 27, which needs macOS Tahoe 26.6 or later). |
| Account | A free Apple ID is enough to run it on your own phone. The paid developer account ($99/yr) is only needed for TestFlight / App Store, which an internal tool does not need. |
| Homebrew | Only for the optional Terminal route (XcodeGen). Not needed to install the app. |

Without LiDAR (an older iPhone, an iPad without LiDAR, or the Simulator) everything except scanning
still works: demo data, verification, plans, the 3D viewer and exports. The Simulator even offers a
"Simulate a scan" button so you can try the whole flow.

## Install it on your iPhone (first time, about 30 minutes, no Terminal)

The repository contains a ready-made Xcode project. GitHub's own Macs build the app with Apple's real SDKs
on every change (see the **Actions** tab on GitHub), and save the finished project into the repo.

**Which branch?** The app lives on the branch **`claude/gallant-ride-jzhsjk`**. The repository's default branch
holds only the costing tool and has no `ios` folder, so a plain "Clone" of the repository shows no app. The zip
link below always gives the right branch.

0. **First time ever with Xcode:** open it once from Applications, click *Agree*, let it install its extra
   components, and type your Mac password when it asks (it asks a few times; that is normal). Xcode 27 needs
   macOS Tahoe 26.6 or later on an Apple silicon Mac.
1. **Get the code (on the Mac).** In Safari on the Mac, open
   `https://github.com/themohmo/NexaFix/archive/refs/heads/claude/gallant-ride-jzhsjk.zip`. It downloads a zip
   (the repository is public, so no sign-in). If Safari has not unzipped it, double-click the zip. You get a folder
   called **`NexaFix-claude-gallant-ride-jzhsjk`**; drag it into *Documents*. Inside it there must be a folder
   called `ios`.
   *Alternative with Git:* in Xcode choose *Window ▸ Welcome to Xcode ▸ Clone Git Repository…* (or *Source
   Control ▸ Clone…*), paste `https://github.com/themohmo/NexaFix.git`, press Return, click *Clone*, and when a
   branch menu appears choose `claude/gallant-ride-jzhsjk`; then choose a folder. If there is no `ios` folder
   afterwards you are on the wrong branch: delete the folder and use the zip. An empty Xcode window after a clone
   is normal; go on to step 2.
2. **Open the project.** In the menu bar at the top of the screen choose *File ▸ Open…*, go into the `ios`
   folder and select **`NexaFixScan`** (the file with the small blue icon; it may show as `NexaFixScan.xcodeproj`),
   then *Open*. Or double-click that file in Finder. Do not open the `NexaFixCore` folder: that is only the library
   and has no Run button for a phone. Wait until the top bar stops saying *Resolving Package Graph* or
   *Indexing* (there is no download; it takes a moment). Yellow warnings are fine.
3. **Signing.** First sign in: *Xcode ▸ Settings ▸ Apple Accounts*, click **+**, sign in with your Apple Account (the
   one on your iPhone) and enter the two-factor code. Then, in the project window: press ⌘1 if the left sidebar
   is hidden, click the blue **NexaFixScan** item at the very top, under **TARGETS** click **NexaFixScan**, open
   **Signing & Capabilities**, tick **Automatically manage signing**, and under **Team** choose *Your Name
   (Personal Team)*. A free account is enough. If a red message says *Failed to register bundle identifier*,
   type your own **Bundle Identifier**, all lower case, no spaces, for example `com.yourname.nexafixscan`, press
   Return and click *Try Again*. Choose it once and do not keep changing it: a free account can only create about
   ten new IDs a week, and a new ID installs as a new app with no scans in it.
4. **Connect and prepare the phone.** Use the cable that came with the iPhone, straight into the Mac (no hub).
   Unlock the phone, tap **Trust** and enter its passcode. In Xcode choose *Xcode ▸ Open Developer Tool ▸ Device
   Hub*, click your iPhone and click **Pair** if that button shows. Only now, on the iPhone, open **Settings ▸
   Privacy & Security**, scroll to the very bottom, and turn on **Developer Mode** (the switch appears only once the
   phone has been paired with Xcode). Tap **Restart**; when the phone is back, unlock it, tap **Enable** and enter
   the passcode. The restart is expected.
5. **Run.** At the top of Xcode, next to the scheme **NexaFixScan**, click the second menu and choose your own iPhone
   by name under *iOS Devices* (not anything under *Simulators*: the Simulator cannot scan). Press **▶**. The first
   time Xcode spends several minutes preparing the phone (it can take 5 to 10): keep the phone unlocked and plugged in
   and leave Xcode in front. If the Mac asks to let `codesign` use a key, type the Mac password and click *Always
   Allow*. After the app starts you can press Stop and unplug; the app stays on the phone. For real site scans switch
   the scheme (the menu left of the phone's name) to **NexaFixScan Release** and press ▶ again (Debug builds are
   unoptimised and the geometry and AR code is noticeably slower in them).
6. **First launch with a free Apple ID.** The first Run usually ends with a red message such as *profile has not
   been explicitly trusted*, and the phone says *Untrusted Developer*. That is expected; the app is already on the
   phone. On the phone open **Settings ▸ General ▸ VPN & Device Management**, under *Developer App* tap
   **Apple Development: your Apple Account**, tap **Trust** (the phone needs internet), then press ▶ in Xcode again
   or tap the NexaFix Scan icon.
7. **You should see:** in Xcode *Running NexaFixScan on <your iPhone>* and the ▶ turns into a square Stop button;
   on the phone the app opens with a large title **Properties**, a gear at top right, and the buttons **Scan a
   property** and **Try the demo apartment**. Tap **Try the demo apartment** first. When you start a scan the phone
   asks to use the camera: tap **Allow** (if you tapped *Don't Allow*, switch it on in the iPhone's Settings under
   NexaFix Scan).

**If the Run button is grey:** wait for the progress text at the top to finish; check the destination is your named
iPhone (not *Any iOS Device*) and the scheme says NexaFixScan; check the left sidebar shows a *NexaFixScan* project and not
just *NexaFixCore*; unlock the phone; if a *Get* button appears next to the destination, click it (it installs the
iOS 27 support files).
**If your iPhone is not in the list:** unlock it and look for the Trust prompt; try the original cable and another
port; check it shows in *Device Hub* (or use *Manage Devices…* in the destination menu); check Developer Mode is on;
restart the iPhone, then the Mac.

**Every 7 days:** a free-account install stops opening after 7 days. Plug the phone in, open the project and press
▶ again. **Never delete the app to fix this**: that would delete the scans on the phone. Export important scans
before the week is up. Free accounts also allow only 3 apps per phone.

**After downloading a newer zip later:** your Team and Bundle Identifier are stored in the project file, so enter
the same ones again (write down your Bundle Identifier). This is also why changing it creates a new, empty app.

Optional, for Terminal users: `bash ios/tools/remember-signing.sh` saves your Team in `ios/Config/Local.xcconfig`,
which git ignores, so it survives the project being regenerated.

If Xcode shows build errors, copy the red messages to Claude. The app has been compiled with Xcode 26 and 27
on GitHub's Macs with no errors, so a build error on your Mac would be new information.

**Prefer Terminal, or the project file looks out of date?** Install XcodeGen (`brew install xcodegen`) and run
`cd ios && xcodegen generate && open NexaFixScan.xcodeproj`. That recreates the project from `ios/project.yml`.

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
| *Signing requires a development team* | Pick your Team (step 3), then run `ios/tools/remember-signing.sh` so it survives re-generating. |
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
- **Compiled by Apple's own tools (GitHub Actions, free on this public repo):** every change is built on
  GitHub's Macs for an iPhone and for the Simulator, with Xcode 26 and Xcode 27, and the core tests are run on
  macOS. Latest result: 0 compile errors and 1,079 core tests passing on Xcode 27.2 (iOS 27.2 SDK). Every Apple API call
  was also audited against Apple's documentation, including what iOS 26 and 27 changed.
- **Never run on a real iPhone:** a successful build proves the code is valid, not that scanning, AR and the
  screens behave well. That needs your phone.
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
  project.yml          XcodeGen project definition (the .xcodeproj is generated from it and committed by CI)
  NexaFixCore/         Swift package, Foundation only, tested on Linux and in Xcode
    Sources/NexaFixCore  Model, Geometry, Units, Capture (RoomReconstructor), Measure, Overlay,
                         Scene, Plan, Drawing, Export (PDF, DXF, JSON, CSV, costing), Storage, Flow, Sample
    Tests/               1,000+ tests
  NexaFixScan/         the SwiftUI app: App, DesignSystem, Capture, AR, Plan, Viewer, Screens, Resources
  docs/DESIGN.md       design language (colour, type, motion, haptics, screens)
  docs/SCAN-FILE-FORMAT.md   JSON / CSV / costing spec formats
  Config/              signing (Signing.xcconfig; your own Local.xcconfig is git-ignored), generated Info.plist
  tools/               icon generator, preflight.py (build-config + privacy checks), remember-signing.sh,
                       typecheck/ (compiles the whole app against the real core with Apple stand-ins),
                       recovery-checks/ (regression tests for the crash-recovery rules: a saved scan copy is
                       never deleted before its rooms are on disk)
```

Run the core tests (Mac or Linux): `cd ios/NexaFixCore && swift test`.
Check the build configuration and privacy manifest: `python3 ios/tools/preflight.py`.
Regenerate the app icon: `python3 ios/tools/make_icon.py`.
The Python side (costing engine and the scan bridge): `python3 -m pytest -q` from the repo root.
Design principles: `docs/DESIGN.md`. The app follows Apple's design principles: simple, one primary action
per screen, springs, touch-down feedback, Dynamic Type, Reduce Motion / Transparency, and Liquid Glass on iOS 26+.
