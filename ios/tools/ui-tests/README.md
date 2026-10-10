# Simulator smoke tests (UI tests)

Runtime checks for NexaFix Scan. They start the real app in the iPhone Simulator, tap through the screens that do
not need a camera, and leave **screenshots** behind so you can see what the app really draws. The code is in
`ios/NexaFixScanUITests/` (`SmokeTests.swift` and `Helpers.swift`), the Xcode target is `NexaFixScanUITests`
(defined in `ios/project.yml`), and the GitHub Actions job is `ui-tests` in `.github/workflows/ios.yml`.

They were written without a Mac and have not run yet: expect to iterate. See "If it fails" at the end.

## What the tests do

Every test launches the app with `-UITestResetData YES`, so it starts as on a first launch: the saved properties,
the scan recovery copies and the saved settings are deleted before the app builds its model. That hook is in
`NexaFixScan/App/UITestSupport.swift`, is called from `NexaFixScanApp.init`, and exists only in Debug builds (the
whole file is inside `#if DEBUG`). A normal launch is not affected.

| Test | What it does | Screenshots |
|---|---|---|
| T1 first launch | Empty state: "No properties yet", "Scan a property", "Try the demo apartment", Settings. Light appearance. | `T1-01-home-empty` |
| T2 demo flow | Demo apartment, tap the plan (a few spots, until the selection card shows), Rooms tab, first room, tap the first dimension that is only scanned, type a plausible value in the Verify sheet, Save, and check the room has one more checked dimension (rows carry the identifier `room.dimension.verified` / `room.dimension.scanned`). | `T2-01` to `T2-07` |
| T3 export | Open Export from the demo, switch DXF and CSV on (the switch is found as a switch, a toggle or any element with the identifier, and its value is read before and after each tap), press Share. If the system share sheet appears it is photographed and dismissed; if it cannot be detected the test taps the dimmed strip at the top of the screen in case it is up anyway. Either way the Export sheet is then closed with Done, tapped again if the first tap only cleared a share sheet. | `T3-01` to `T3-05` |
| T4 settings | Open Settings, change the length unit to Centimetres, check the live example line changed, close. | `T4-01` to `T4-04` |
| T5 3D | Open the 3D tab, check the viewer's controls exist ("Close 3D view", "Show whole floor"), close it. RealityKit may draw nothing in the Simulator; only "no crash, chrome exists" is asserted. | `T5-01` to `T5-03` |
| T6 simulated scan | New property "Practice Villa", Start scanning, the no-LiDAR screen offers "Simulate a scan" (Simulator builds only), simulate, name the room "Test Lounge", Finish property, then the property shows a plan, the room is in the Rooms tab, and the home screen has the card. | `T6-01` to `T6-10` |
| T7a dark mode, T7b largest text | Launch with `-AppleInterfaceStyle Dark`, then with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`; screenshots of the home screen, the property plan, a room, the Verify sheet and the home screen with the demo. | `T7a-dark-*`, `T7b-xxxl-*` |
| T8a, T8b, T8c crash guard | Three tests, one per screen: T8a opens and closes Settings and New property five times each, T8b the Export sheet five times, T8c the Verify sheet five times. After every round they assert that the app is still running in the foreground. (Three short tests instead of one long one: each stays far inside the CI time limit and a failure in one does not hide the others.) | `T8a-01`, `T8b-01`, `T8c-01` |

Each test is independent, fails with a message that says what it was looking for, and attaches a whole-screen
screenshot named `FAILURE-...` when it fails.

Rows below the fold (the dimension rows of a room, the CSV switch of the Export sheet, the demo button at the largest
text size) are brought into reach with plain `app.swipeUp()` swipes (`scrollToHittable` in `Helpers.swift`) before
they are tapped, instead of relying on XCUITest's own scroll-to-visible, which can fail on SwiftUI scroll views.

### What cannot be tested here

- Real scanning and the AR review: the Simulator has no camera, no LiDAR, no RoomPlan and no AR session. The
  "Simulate a scan" path stands in for scanning; it builds a practice room from fixtures.
- The app mark above the empty state's title is hidden from accessibility (it is decorative), so a UI test cannot see
  it. It is in the screenshot.
- Pixels: nothing asserts on how anything looks. Look at the screenshots.
- Real 3D rendering (T5 only checks that the viewer opens and closes).

## Reading the CI result

Open the workflow run, then the `UI smoke tests` job.

1. The step **Summary of failures (read this first)**: failed test cases, unique `error:` lines, crash lines, the
   `** TEST FAILED **` line and the last 30 lines of the log, then **did every test run?**: every test method
   defined in `SmokeTests.swift` must appear as passed in the log (or the result bundle must report that many
   passed tests). The job is red otherwise, even when `xcodebuild` itself exited with 0: an empty or undiscovered
   test target ends with "Executed 0 tests" and exit code 0, and without this check that would look like a pass.
   Adding a test method needs no change to the workflow.
2. Artifacts at the bottom of the run page:
   - **ui-screenshots**: every attachment of every test, exported with `xcresulttool export attachments`. The file
     names are generated; `INDEX.txt` and `manifest.json` map them to tests and to the names used in the tests
     (`T2-05-verify-sheet`...). A screenshot of a failure has `FAILURE` in its name.
   - **ui-tests-log**: the complete `xcodebuild` output (`ui-tests.log`) plus the JSON from
     `xcresulttool get test-results summary` and `... tests`.
   - **ui-xcresult**: the result bundle zipped. Unzip it and open it in Xcode for the full report, with a timeline
     of every tap.
3. The job is red when any test failed or did not run (after the artifacts have been uploaded). It never commits
   anything.

Time limits (all in `ios.yml`, none in the test code): `xcodebuild` runs with `-test-timeouts-enabled YES
-default-test-execution-time-allowance 420 -maximum-test-execution-time-allowance 600`, so a single test may take up
to 7 minutes before it is stopped as hung. XCTest rounds such limits up to whole minutes and caps a test's own
`executionTimeAllowance` at the maximum flag, and Apple does not say when a value set inside a test method is read, so
the tests set none. The step "Choose, boot and prepare a Simulator" has `timeout-minutes: 15` and the step that builds
and runs the tests `timeout-minutes: 40`; a step that times out still lets the artifact and summary steps run.

The CI picks a Simulator by itself: the newest iOS runtime, preferring iPhone 17 Pro Max, then iPhone 17 Pro, then
any other "iPhone ... Pro", then any iPhone (the name is printed in the step "Choose, boot and prepare a Simulator").

## Running them locally

On a Mac with Xcode 26 or later (the project is made for Xcode 27):

```
cd ios
xcodegen generate                 # or use the committed NexaFixScan.xcodeproj
open NexaFixScan.xcodeproj
```

In Xcode: pick the scheme **NexaFixScan** and an iPhone Simulator as the destination, then **Product > Test**
(Cmd-U). Open the Report navigator (Cmd-9), pick the test run, and click a test to see its attachments (screenshots).
Right-click a screenshot to save it.

From the command line:

```
cd ios
xcodebuild test -project NexaFixScan.xcodeproj -scheme NexaFixScan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath ../TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool get test-results summary --path ../TestResults.xcresult
xcrun xcresulttool export attachments --path ../TestResults.xcresult --output-path ../attachments
```

One test only: add `-only-testing:NexaFixScanUITests/SmokeTests/testT2_DemoApartmentFlowAndVerifyADimension`.

The tests use only the Simulator; no signing team is needed. The scheme's build action does not include the test
bundle, so a normal build (`xcodebuild -scheme NexaFixScan -destination generic/platform=iOS build`) is unchanged.

## Accessibility identifiers the tests rely on

Added to the app only where the visible label is not unique or not stable. The tests look for the identifier first and
for the visible English label second.

`home.scanProperty`, `home.demoButton`, `home.newScan`, `home.settings`, `home.propertyCard`, `property.segment`,
`property.addScan`, `property.ar`, `property.export`, `plan.canvas`, `plan.selection.close`, `rooms.row`,
`room.dimension.scanned` / `room.dimension.verified` (the identifier follows the row's state), `verify.field`,
`verify.save`, `verify.clear`, `verify.cancel`, `export.format.<format>`, `export.share`, `export.done`,
`settings.lengthUnit`, `settings.areaUnit`, `settings.example`, `settings.done`, `newProperty.field.<field>`,
`newProperty.startScanning`, `newProperty.save`, `newProperty.cancel`, `scan.primer.simulate`, `scan.simulate`,
`scan.cancel`, `roomName.field`, `roomName.nextRoom`, `roomName.finishProperty`.

## If it fails

Look in this order:

1. **The build or the test runner did not start** (no `Test Case ... started` lines): the target `NexaFixScanUITests`
   or the scheme's test action from `project.yml`; signing of the UI test runner (`CODE_SIGNING_ALLOWED=NO` is
   used; if the runner will not install, try `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES`);
   Swift errors in `Helpers.swift` / `SmokeTests.swift` (they were only syntax-checked and type-checked against a
   hand-written stand-in for XCTest, never against the real SDK).
2. **The app crashes at launch**: T1 fails first with "did not reach the foreground". The device log is in the
   result bundle (Diagnostics).
3. **An element is not found**: the failure message names it, the `FAILURE-...` screenshot shows the screen. Check the
   identifier in the app (`grep -rn accessibilityIdentifier ios/NexaFixScan`). SwiftUI sometimes exposes a control as a
   different element type than expected; the helpers search all types by identifier or label, but the typed lookups
   (segmented control, text fields, menu items) can be wrong. The Export switches are looked up as `switch`, then
   `toggle`, then any element; if the identifier lands on an element with no value, the test taps the trailing end of
   the row once and cannot verify the result.
4. **Typing does not work** (T2, T6): the Simulator may show a hardware keyboard or no keyboard; the helpers tolerate
   both, but `typeText` needs keyboard focus.
5. **Share sheet / menus** (T3, T4): the system UI changes between iOS versions; T3 tolerates a share sheet it cannot
   detect, T4 does not tolerate a unit menu it cannot read.
6. **"did every test run?" fails although `xcodebuild` succeeded**: the list under "Not seen as passed" names the
   tests. If it names all of them and `ui-tests.log` says "Executed 0 tests", the scheme's test action did not pick up
   the `NexaFixScanUITests` target (see `project.yml`, the `NexaFixScan` scheme's `test:` block). If it names a few,
   they failed or were killed (look for "Restarting after unexpected exit, crash, or test timeout" in the log).
7. **A test was stopped for taking too long**: the log says the test exceeded its execution time allowance. The limit
   is the `-default-test-execution-time-allowance` flag in `ios.yml`; a test that needs more than 7 minutes is
   usually stuck on an element wait, so read its last screenshot first.
