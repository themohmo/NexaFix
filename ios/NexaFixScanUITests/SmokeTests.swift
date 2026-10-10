import XCTest

// Runtime smoke tests for NexaFix Scan, run in the iOS Simulator (see ios/tools/ui-tests/README.md).
//
// What they are for: to launch the real app, drive every screen that does not need a camera, and leave screenshots
// behind (attachments with the lifetime .keepAlways) so a person can look at what the app really draws. They check
// that the main flows work and that the app does not crash. They do not check pixels.
//
// What they cannot do: the Simulator has no LiDAR, no camera, no RoomPlan and no AR session, so real scanning and
// the AR review cannot run. The "Simulate a scan" path of the scan flow (Simulator only) stands in for a scan.
//
// Every test starts the app with `-UITestResetData`, so each one begins as on a first launch (no saved properties).
// Test names start with T1...T8 so the order in the result bundle reads like the plan.

final class SmokeTests: SmokeTestCase {

    // MARK: T1 - first launch

    /// The empty home screen: title, the two buttons, Settings. Light appearance.
    func testT1_FirstLaunchShowsTheEmptyState() {
        launchApp(tag: "T1", LaunchOptions(appearance: .light))
        snap("01-home-empty")

        // The app mark above the title is decorative and hidden from accessibility, so XCUITest cannot see it; the
        // screenshot shows it.
        check(app.staticTexts["No properties yet"].waitForExistence(timeout: 10),
              "The empty state's title \"No properties yet\" is not on the home screen.")
        check(match(id: "home.scanProperty", label: "Scan a property").exists,
              "The \"Scan a property\" button is missing from the empty state.")
        check(match(id: "home.demoButton", label: "Try the demo apartment").exists,
              "The \"Try the demo apartment\" button is missing from the empty state.")
        check(match(id: "home.settings", label: "Settings").exists, "The Settings button is missing from the home screen.")
        check(!match(id: "home.propertyCard").exists, "A property card is on screen although the app was reset: the reset hook did not run.")
        assertAlive("on the empty home screen")
    }

    // MARK: T2 - the demo flow

    /// Demo apartment -> plan -> tap the plan -> Rooms -> first room -> Verify a dimension -> back on the room with
    /// one more dimension marked as checked.
    func testT2_DemoApartmentFlowAndVerifyADimension() {
        launchApp(tag: "T2", LaunchOptions(appearance: .light))
        snap("01-home-empty")

        openDemoFromEmptyHome()
        let card = openedCardIsMarinaGate()
        check(card, "The property screen opened, but its title is not the Marina Gate demo apartment.")
        snap("02-property-plan")
        check(match(id: "plan.canvas", label: "Floor plan").exists, "The plan canvas is missing from the Plan tab.")

        // A tap on the plan selects the wall, corner, opening or room under the finger. Where those are depends on
        // how the plan is fitted, so this tries a few places and only records what happened.
        if tapPlanUntilSomethingIsSelected() {
            snap("03-plan-selection-card")
            tap(match(id: "plan.selection.close"), "the Close button of the selection card")
            settle()
        } else {
            snap("03-plan-after-taps-nothing-selected")
        }
        assertAlive("after tapping the plan")

        openFirstRoom()
        snap("04-room-screen")

        let checkedBefore = count(ofIdentifier: "room.dimension.verified")
        let scannedBefore = count(ofIdentifier: "room.dimension.scanned")
        check(scannedBefore > 0, "The first room has no dimension that is still only scanned, so there is nothing to verify.")

        openVerifySheetFromFirstDimension()
        snap("05-verify-sheet")

        let value = plausibleMillimetres()
        enterText(value, into: match(id: "verify.field", label: "Measured value"), "the Measured value field")
        settle()
        snap("06-verify-sheet-typed-\(value)")

        let save = match(id: "verify.save")
        check(save.waitForExistence(timeout: 10), "The Verify sheet has no Save button.")
        check(save.isEnabled, "The Save button is disabled after typing \"\(value)\" into the Measured value field.")
        save.tap()

        waitUntilGone(match(id: "verify.field", label: "Measured value"), "The Verify sheet", timeout: 20)
        check(poll(15) { self.count(ofIdentifier: "room.dimension.verified") > checkedBefore },
              "After saving \"\(value)\" the room shows no additional checked dimension (checked before: \(checkedBefore), now: \(count(ofIdentifier: "room.dimension.verified"))).")
        check(count(ofIdentifier: "room.dimension.scanned") < scannedBefore,
              "After saving, the number of dimensions that are only scanned did not go down.")
        snap("07-room-after-verify")
        assertAlive("after verifying a dimension")
    }

    private func openedCardIsMarinaGate() -> Bool {
        // The navigation bar of the property screen carries the property's name.
        let predicate = NSPredicate(format: "label BEGINSWITH[c] 'Marina Gate'")
        return poll(10) {
            self.app.navigationBars.matching(predicate).count > 0
                || self.app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH[c] 'Marina Gate'")).count > 0
                || self.app.staticTexts.matching(predicate).count > 0
        }
    }

    // MARK: T3 - export

    /// Export sheet: screenshot, switch formats on, press Share, dismiss.
    func testT3_ExportSheetAndShare() {
        launchApp(tag: "T3", LaunchOptions(appearance: .light))
        openDemoFromEmptyHome()

        openExportSheet()
        snap("01-export-sheet")

        turnSwitchOn(identifier: "export.format.cadDXF", "the \"CAD drawing DXF\" format")
        turnSwitchOn(identifier: "export.format.csv", "the \"Spreadsheets CSV\" format")
        snap("02-export-formats-switched-on")

        let share = match(id: "export.share")
        check(share.exists, "The Share button is missing from the Export sheet.")
        check(share.isEnabled, "The Share button is disabled although formats are chosen and the demo has rooms.")
        share.tap()

        if waitForShareSheet(timeout: 20) {
            settle(0.8)
            snapScreen("03-share-sheet")
            dismissShareSheet()
        } else {
            // Not a failure: whether the system share sheet can appear depends on the machine. The button works
            // (it was enabled and tapped); the screenshot shows what the sheet looks like now.
            snapScreen("03-share-sheet-not-detected")
            // If a share sheet is up after all (only its detection failed), a tap on the dimmed strip at the top of
            // the screen dismisses it. With no share sheet this lands outside the Export sheet and does nothing.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
            settle(0.8)
        }
        assertAlive("after pressing Share")

        // Leave the Export sheet. closeExportSheet() taps Done again if the first tap only cleared a share sheet.
        check(match(id: "export.done").waitForExistence(timeout: 10),
              "The Export sheet's Done button is not on screen after Share, so the sheet cannot be closed.")
        snap("04-export-sheet-after-share")
        closeExportSheet()
        check(match(id: "property.segment").waitForExistence(timeout: 10) || app.segmentedControls.count > 0,
              "The property screen is not back after closing the Export sheet.")
        snap("05-property-after-export")
    }

    private func shareSheetIsVisible() -> Bool {
        app.otherElements["ActivityListView"].exists
            || app.navigationBars["UIActivityContentView"].exists
            || app.buttons["Copy"].exists
            || app.staticTexts["Save to Files"].exists
    }

    private func waitForShareSheet(timeout: TimeInterval) -> Bool {
        poll(timeout) { self.shareSheetIsVisible() }
    }

    /// The close button first, then a tap on the dimmed area above the sheet, then a swipe down.
    private func dismissShareSheet() {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2) {
            close.tap()
            if poll(4, { !self.shareSheetIsVisible() }) { return }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        if poll(4, { !self.shareSheetIsVisible() }) { return }
        let list = app.otherElements["ActivityListView"]
        if list.exists { list.swipeDown() }
        _ = poll(4) { !self.shareSheetIsVisible() }
    }

    // MARK: T4 - settings

    func testT4_SettingsChangeTheLengthUnit() {
        launchApp(tag: "T4", LaunchOptions(appearance: .light))
        openSettings()
        snap("01-settings")

        let picker = match(id: "settings.lengthUnit")
        check(picker.waitForExistence(timeout: 10), "The Length unit picker is missing from Settings.")
        let example = match(id: "settings.example")
        check(example.waitForExistence(timeout: 10), "The live example (\"Example: ...\") is missing from Settings.")
        let before = example.label

        tap(picker, "the Length unit picker")
        // .firstMatch on each: a menu can expose one entry as a button and again as an inner element with the same
        // label, and tapping a query that matches twice fails with "multiple matching elements".
        let option = firstExisting([app.buttons["Centimetres"].firstMatch,
                                    app.menuItems["Centimetres"].firstMatch,
                                    app.staticTexts["Centimetres"].firstMatch],
                                   timeout: 10)
        check(option != nil, "The Length unit menu did not offer \"Centimetres\" within 10 s of opening.")
        snap("02-settings-length-menu")
        option?.tap()

        check(poll(10) { self.match(id: "settings.example").label != before },
              "The example line in Settings did not change after choosing Centimetres (it still reads \"\(before)\").")
        snap("03-settings-centimetres")

        closeSettings()
        check(isHomeVisible(), "The home screen is not back after closing Settings.")
        snap("04-home-after-settings")
        assertAlive("after changing a setting")
    }

    private func firstExisting(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        _ = poll(timeout) { elements.contains { $0.exists } }
        return elements.first { $0.exists }
    }

    // MARK: T5 - the 3D tab

    /// RealityKit may draw nothing in the Simulator. This only checks that the viewer opens with its controls, that
    /// the app survives, and that closing it returns to the property.
    func testT5_ThreeDTabOpensAndCloses() {
        launchApp(tag: "T5", LaunchOptions(appearance: .light))
        openDemoFromEmptyHome()

        selectTab("3D")
        let close = match(label: "Close 3D view")
        check(close.waitForExistence(timeout: 30),
              "The 3D viewer did not open: no \"Close 3D view\" button within 30 s of choosing the 3D tab.")
        settle(1.5)
        snap("01-3d-viewer")
        assertAlive("with the 3D viewer open")
        check(match(label: "Show whole floor").exists, "The 3D viewer has no \"Show whole floor\" button.")

        match(label: "Show whole floor").tap()
        settle(1.0)
        snap("02-3d-viewer-whole-floor")
        assertAlive("after \"Show whole floor\"")

        close.tap()
        waitUntilGone(match(label: "Close 3D view"), "The 3D viewer", timeout: 20)
        check(match(id: "plan.canvas", label: "Floor plan").waitForExistence(timeout: 15),
              "The plan is not back after closing the 3D viewer.")
        snap("03-property-after-3d")
        assertAlive("after closing the 3D viewer")
    }

    // MARK: T6 - a simulated scan

    /// New property -> Start scanning -> (no LiDAR in the Simulator) Simulate a scan -> name the room -> Finish
    /// property -> the property is saved with the room in its plan.
    func testT6_SimulatedScanCreatesAPropertyWithARoom() {
        launchApp(tag: "T6", LaunchOptions(appearance: .light))

        openNewPropertyFromEmptyHome()
        snap("01-new-property-sheet")

        let propertyName = "Practice Villa"
        enterText(propertyName, into: match(id: "newProperty.field.name", label: "Name", type: .textField), "the Name field")
        dismissKeyboard()
        snap("02-new-property-named")

        tap(match(id: "newProperty.startScanning", label: "Start scanning"), "the Start scanning button")

        // In the Simulator RoomPlan reports "not supported", so the scan screen is the no-LiDAR explanation with a
        // "Simulate a scan" button (Simulator builds only).
        let primer = match(id: "scan.primer.simulate", label: "Simulate a scan")
        check(primer.waitForExistence(timeout: 30),
              "The scan screen did not offer \"Simulate a scan\" within 30 s of Start scanning. In the Simulator it should show the no-LiDAR screen.")
        snap("03-scan-no-lidar-screen")
        primer.tap()

        let simulate = match(id: "scan.simulate")
        check(simulate.waitForExistence(timeout: 20), "The practice scan screen did not appear (no \"Simulate a scan\" button in the bottom bar).")
        settle(0.5)
        snap("04-practice-scan-stage")
        assertAlive("on the practice scan screen")
        check(simulate.isEnabled, "The \"Simulate a scan\" button in the bottom bar is disabled.")
        simulate.tap()

        let nameField = match(id: "roomName.field", label: "Room name", type: .textField)
        check(nameField.waitForExistence(timeout: 40),
              "The \"Name this room\" sheet did not appear within 40 s of Simulate a scan.")
        snap("05-name-this-room")
        let roomName = "Test Lounge"
        enterText(roomName, into: nameField, "the Room name field")
        dismissKeyboard()
        snap("06-room-named")

        tap(match(id: "roomName.finishProperty", label: "Finish property"), "the Finish property button")

        // Joining the rooms and saving the property. The scan screen closes and the property opens.
        waitForPropertyScreen(timeout: 120)
        snap("07-property-after-scan")
        assertAlive("after finishing the practice scan")

        selectTab("Rooms")
        let rowNamed = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'rooms.row' AND label CONTAINS[c] %@", roomName)).firstMatch
        check(rowNamed.waitForExistence(timeout: 15),
              "The Rooms tab has no room called \"\(roomName)\" after the simulated scan.")
        snap("08-rooms-tab")

        selectTab("Plan")
        check(match(id: "plan.canvas", label: "Floor plan").waitForExistence(timeout: 10),
              "The plan of the scanned property did not come back on the Plan tab.")
        snap("09-plan-of-scanned-room")

        goBack()
        let savedCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'home.propertyCard' AND label BEGINSWITH[c] 'Practice'")).firstMatch
        check(savedCard.waitForExistence(timeout: 15), "The home screen has no card for the property \"\(propertyName)\".")
        snap("10-home-with-the-new-property")
    }

    // MARK: T7 - dark mode and large text

    func testT7a_DarkModeTourOfTheDemo() {
        tourOfTheDemo(tag: "T7a", prefix: "dark", LaunchOptions(appearance: .dark))
    }

    func testT7b_LargestTextSizeTourOfTheDemo() {
        tourOfTheDemo(tag: "T7b", prefix: "xxxl",
                      LaunchOptions(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"))
    }

    /// Home, property plan, room and Verify sheet under the given appearance or text size.
    private func tourOfTheDemo(tag: String, prefix: String, _ options: LaunchOptions) {
        launchApp(tag: tag, options)
        snap("\(prefix)-01-home-empty")

        openDemoFromEmptyHome()
        snap("\(prefix)-02-property-plan")

        openFirstRoom()
        snap("\(prefix)-03-room")

        openVerifySheetFromFirstDimension(scannedOnly: false)
        settle(0.6)
        snap("\(prefix)-04-verify-sheet")
        assertAlive("with the Verify sheet open (\(prefix))")
        cancelVerifySheet()

        goBack()   // room -> property
        goBack()   // property -> home
        check(match(id: "home.propertyCard").waitForExistence(timeout: 15),
              "The home screen has no property card after opening the demo and coming back (\(prefix)).")
        snap("\(prefix)-05-home-with-the-demo")
        assertAlive("on the home screen (\(prefix))")
    }

    // MARK: T8 - sheets survive being opened and closed again and again
    //
    // Three separate tests, one per screen, instead of one long one: each stays far inside the per-test time limit
    // that CI sets, and a failure in one does not hide the result of the others.

    /// Home: Settings and New property, five rounds each, asserting after every round that the app is running.
    func testT8a_HomeSheetsSurviveBeingOpenedRepeatedly() {
        launchApp(tag: "T8a", LaunchOptions(appearance: .light))

        for round in 1...5 {
            openSettings()
            closeSettings()
            openNewPropertyFromEmptyHome()
            cancelNewProperty()
            assertAlive("after Settings and New property, round \(round)")
        }
        snap("01-home-after-sheet-rounds")
        assertAlive("after the home sheet rounds")
    }

    /// Property: the Export sheet, five rounds.
    func testT8b_ExportSheetSurvivesBeingOpenedRepeatedly() {
        launchApp(tag: "T8b", LaunchOptions(appearance: .light))
        openDemoFromEmptyHome()

        for round in 1...5 {
            openExportSheet()
            closeExportSheet()
            assertAlive("after the Export sheet, round \(round)")
        }
        snap("01-property-after-export-rounds")
        assertAlive("after the Export sheet rounds")
    }

    /// Room: the Verify sheet, five rounds.
    func testT8c_VerifySheetSurvivesBeingOpenedRepeatedly() {
        launchApp(tag: "T8c", LaunchOptions(appearance: .light))
        openDemoFromEmptyHome()
        openFirstRoom()

        for round in 1...5 {
            openVerifySheetFromFirstDimension(scannedOnly: false)
            cancelVerifySheet()
            assertAlive("after the Verify sheet, round \(round)")
        }
        snap("01-room-after-verify-rounds")
        assertAlive("after the Verify sheet rounds")
    }
}
