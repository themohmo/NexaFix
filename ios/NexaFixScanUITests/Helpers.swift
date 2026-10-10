import XCTest

// Shared plumbing for the UI smoke tests in SmokeTests.swift.
//
// Rules this file keeps (the tests are written without being able to compile them on the machine they were
// written on, so they stay close to the documented XCTest / XCUIAutomation API):
//   - Every wait is `waitForExistence(timeout:)` or a short polling loop with a timeout. The only fixed pauses are
//     the tiny `settle()` delays between two taps.
//   - Every failure goes through `check(...)`: it attaches a screenshot of the whole screen, then fails with a
//     message that says what was being looked for. A teardown block does the same for failures that did not come
//     from `check` (a failed `XCTAssert`, a crash of the app).
//   - Nothing asserts on pixels. Screenshots are attachments (`.keepAlways`) for a human or for the CI artifacts.
//   - Elements are found by accessibility identifier first (see the `accessibilityIdentifier` calls in the app),
//     then by the visible English label, because the app is not localised.

/// How a test starts the app.
struct LaunchOptions {
    enum Appearance {
        case light
        case dark
    }

    /// nil leaves the Simulator's own setting alone.
    var appearance: Appearance?
    /// For example `UICTContentSizeCategoryAccessibilityXXXL`. nil leaves the Simulator's own setting alone.
    var contentSizeCategory: String?
}

/// Base class of the smoke tests. One instance exists per test method, so the state below belongs to one test.
@MainActor
class SmokeTestCase: XCTestCase {

    // MARK: State

    private var launchedApp: XCUIApplication?
    private var tag = "T"
    private var didRegisterFailureCapture = false
    private var didCaptureFailure = false

    /// The app under test. Valid after `launchApp(tag:_:)`.
    var app: XCUIApplication {
        guard let launchedApp else {
            fatalError("launchApp(tag:_:) must be called before the app is used")
        }
        return launchedApp
    }

    // MARK: Launching

    /// Starts the app with a clean first-run state (`-UITestResetData`, handled in `UITestSupport.swift`) and waits
    /// for the home screen.
    func launchApp(tag: String, _ options: LaunchOptions = LaunchOptions()) {
        self.tag = tag
        continueAfterFailure = false
        // No per-test time limit is set here on purpose: the CI job passes -test-timeouts-enabled YES with
        // -default-test-execution-time-allowance and -maximum-test-execution-time-allowance (ios.yml), which is the
        // one place the limit is defined. (XCTestCase.executionTimeAllowance is rounded up to whole minutes and is
        // capped by the maximum flag, and Apple does not say when XCTest reads it.)
        registerFailureCapture()

        let application = XCUIApplication()
        // "-UITestResetData YES": an option with a value, so Foundation's argument parser cannot take the next
        // option for its value. English is forced because the tests look for the app's English labels.
        var arguments = ["-UITestResetData", "YES",
                         "-AppleLanguages", "(en)",
                         "-AppleLocale", "en_US"]
        switch options.appearance {
        case .light?: arguments += ["-AppleInterfaceStyle", "Light"]
        case .dark?: arguments += ["-AppleInterfaceStyle", "Dark"]
        case nil: break
        }
        if let category = options.contentSizeCategory {
            arguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        application.launchArguments = arguments
        application.launch()
        launchedApp = application

        check(application.wait(for: .runningForeground, timeout: 30),
              "The app did not reach the foreground within 30 s of launching. It probably crashed at start-up.")
        check(poll(30) { self.isHomeVisible() },
              "The home screen (navigation bar \"Properties\" or its buttons) did not appear within 30 s of launching.")
    }

    func isHomeVisible() -> Bool {
        app.navigationBars["Properties"].exists
            || match(id: "home.newScan").exists
            || match(id: "home.scanProperty").exists
            || match(id: "home.propertyCard").exists
    }

    // MARK: Finding

    /// The first element with this accessibility identifier and/or this exact label, of any type.
    func match(id: String? = nil, label: String? = nil, type: XCUIElement.ElementType = .any) -> XCUIElement {
        var clauses: [String] = []
        var values: [String] = []
        if let id {
            clauses.append("identifier == %@")
            values.append(id)
        }
        if let label {
            clauses.append("label == %@")
            values.append(label)
        }
        precondition(!clauses.isEmpty, "match needs an identifier or a label")
        let predicate = NSPredicate(format: clauses.joined(separator: " OR "), argumentArray: values)
        return app.descendants(matching: type).matching(predicate).firstMatch
    }

    /// How many elements carry this identifier. Used to see a number go up, never to compare with a fixed value.
    func count(ofIdentifier identifier: String) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).count
    }

    // MARK: Waiting

    /// Runs `condition` about every 0.2 s until it is true or `timeout` seconds have passed.
    @discardableResult
    func poll(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return condition()
    }

    /// A tiny pause between two taps, so an animation that was just started can begin.
    func settle(_ seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Acting

    /// Waits for the element, scrolls it into reach when it is off screen, then taps it.
    func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) {
        check(element.waitForExistence(timeout: timeout), "Could not find \(what) within \(Int(timeout)) s.")
        if !element.isHittable && !poll(1.5, { element.isHittable }) {
            scrollToHittable(element)
        }
        element.tap()
    }

    /// Scrolls the screen with plain swipes until the element can be hit.
    ///
    /// Apple's page for `isHittable` says it is false for an element that is off screen, covered by another element,
    /// or missing, "even if calling tap() would scroll the element into a hittable position". XCUITest's own
    /// scroll-to-visible works on most screens but is known to fail on some SwiftUI scroll views, so this does the
    /// scrolling itself. It uses `app.swipeUp()` / `app.swipeDown()` (no per-element swipe) and does nothing when the
    /// element is already hittable. Swipes down are only used when the element is wholly above the visible area, so
    /// a sheet is never pulled down by this helper unless its content is already scrolled.
    func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while element.exists && !element.isHittable && swipes < maxSwipes {
            let frame = element.frame
            // A zero-sized element (not laid out) cannot be scrolled to.
            if frame.isEmpty { return }
            if frame.maxY < 120 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            swipes += 1
            settle(0.3)
        }
    }

    /// Waits until the element is gone (a sheet that was dismissed, for example).
    func waitUntilGone(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 15) {
        check(poll(timeout) { !element.exists }, "\(what) was still on screen \(Int(timeout)) s after it should have closed.")
    }

    /// Taps a field and types into it. With `replacing`, whatever is in the field is deleted first.
    func enterText(_ text: String, into field: XCUIElement, _ what: String, replacing: Bool = true) {
        tap(field, what)
        _ = poll(3) { self.app.keyboards.count > 0 }
        if replacing {
            let current = (field.value as? String) ?? ""
            let placeholder = field.placeholderValue ?? ""
            if !current.isEmpty && current != placeholder {
                // A tap puts the caret where the finger was; one at the right-hand end puts it after the text.
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
            }
        }
        field.typeText(text)
    }

    /// Presses Return until the keyboard has gone (a few presses: in the New property sheet Return moves on to the
    /// next field). Does nothing when there is no software keyboard, which happens when the Simulator has a
    /// hardware keyboard connected.
    func dismissKeyboard() {
        for _ in 0..<5 {
            guard app.keyboards.count > 0 else { return }
            let returnKeys = NSPredicate(
                format: "label ==[c] 'return' OR label ==[c] 'done' OR label ==[c] 'go' OR label BEGINSWITH[c] 'next'")
            let key = app.keyboards.buttons.matching(returnKeys).firstMatch
            if key.exists {
                key.tap()
            } else {
                app.typeText("\n")
            }
            settle(0.5)
        }
    }

    // MARK: Screenshots and failures

    /// Attaches a screenshot of the app to the test result, named for the test and the step.
    func snap(_ name: String) {
        attach(app.screenshot(), named: "\(tag)-\(name)")
    }

    /// The same for the whole screen (system UI such as the share sheet is not part of the app's own window).
    func snapScreen(_ name: String) {
        attach(XCUIScreen.main.screenshot(), named: "\(tag)-\(name)")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One screenshot of the whole screen for a failing test (a second call is ignored).
    func captureFailure(_ reason: String) {
        guard !didCaptureFailure else { return }
        didCaptureFailure = true
        let short = String(reason.prefix(50))
        attach(XCUIScreen.main.screenshot(), named: "FAILURE-\(tag)-\(short)")
    }

    /// Fails the test with `message` after taking a screenshot. The test stops here (`continueAfterFailure` is off).
    func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String,
               file: StaticString = #filePath, line: UInt = #line) {
        guard condition() else {
            let text = message()
            captureFailure(text)
            XCTFail(text, file: file, line: line)
            return
        }
    }

    /// The app is still running in the foreground: no crash, no exit.
    func assertAlive(_ moment: String, file: StaticString = #filePath, line: UInt = #line) {
        check(app.state == .runningForeground,
              "The app is not running in the foreground \(moment) (XCUIApplication.State raw value \(app.state.rawValue)). It has probably crashed.",
              file: file, line: line)
    }

    /// A safety net for failures that did not come from `check`: a failed XCTAssert, or a test that ended early.
    private func registerFailureCapture() {
        guard !didRegisterFailureCapture else { return }
        didRegisterFailureCapture = true
        // The synchronous overload: `addTeardownBlock(_ block: @escaping @MainActor @Sendable () throws -> Void)`.
        // Its block runs on the main thread (Apple's page for addTeardownBlock), so it can call this class's
        // main-actor methods directly, with no `await` and no hop through the async overload.
        addTeardownBlock { [weak self] in
            self?.captureFailureIfTestFailed()
        }
    }

    private func captureFailureIfTestFailed() {
        guard let run = testRun, run.totalFailureCount > 0 else { return }
        captureFailure("test-failed")
    }
}

// MARK: - Screens

extension SmokeTestCase {

    // MARK: Home

    /// Taps "Try the demo apartment" and waits for the property screen.
    func openDemoFromEmptyHome() {
        tap(match(id: "home.demoButton", label: "Try the demo apartment"), "the \"Try the demo apartment\" button")
        waitForPropertyScreen()
    }

    func openSettings() {
        tap(match(id: "home.settings", label: "Settings"), "the Settings button on the home screen")
        check(match(id: "settings.done").waitForExistence(timeout: 15), "The Settings sheet did not open (no Done button within 15 s).")
    }

    func closeSettings() {
        tap(match(id: "settings.done"), "the Done button of Settings")
        waitUntilGone(match(id: "settings.done"), "The Settings sheet")
    }

    func openNewPropertyFromEmptyHome() {
        tap(match(id: "home.scanProperty", label: "Scan a property"), "the \"Scan a property\" button")
        check(match(id: "newProperty.cancel").waitForExistence(timeout: 15),
              "The New property sheet did not open (no Cancel button within 15 s).")
    }

    func cancelNewProperty() {
        tap(match(id: "newProperty.cancel"), "the Cancel button of the New property sheet")
        waitUntilGone(match(id: "newProperty.cancel"), "The New property sheet")
    }

    /// Goes back one screen with the navigation bar's back button.
    func goBack() {
        let standard = app.navigationBars.buttons["BackButton"]
        if standard.waitForExistence(timeout: 5) {
            standard.tap()
        } else {
            tap(app.navigationBars.buttons.element(boundBy: 0), "the back button of the navigation bar")
        }
        settle()
    }

    // MARK: Property

    /// Waits until the property screen shows a plan with its Plan / Rooms / 3D control.
    func waitForPropertyScreen(timeout: TimeInterval = 30) {
        check(poll(timeout) { self.match(id: "property.segment").exists || self.app.segmentedControls.count > 0 },
              "The property screen (Plan / Rooms / 3D control) did not appear within \(Int(timeout)) s.")
        check(match(id: "plan.canvas", label: "Floor plan").waitForExistence(timeout: 15),
              "The plan canvas (\"Floor plan\") did not appear on the property screen.")
    }

    /// Plan, Rooms or 3D.
    func selectTab(_ title: String) {
        var control = app.segmentedControls["property.segment"]
        if !control.waitForExistence(timeout: 10) {
            control = app.segmentedControls.firstMatch
        }
        tap(control.buttons[title], "the \"\(title)\" segment of the property screen")
    }

    func openExportSheet() {
        tap(match(id: "property.export", label: "Export"), "the Export button on the property screen")
        check(match(id: "export.done").waitForExistence(timeout: 15), "The Export sheet did not open (no Done button within 15 s).")
        check(match(id: "export.share").waitForExistence(timeout: 15), "The Export sheet has no Share button.")
    }

    /// Closes the Export sheet with its Done button, and tries again if the sheet is still there.
    ///
    /// The retry matters after Share: the system share sheet (presented from a view controller inside the Export
    /// sheet) covers the lower half of the screen and dims the rest, so a first tap on Done can land on the dimming
    /// view. That dismisses the share sheet and leaves the Export sheet open; the second tap then closes it.
    func closeExportSheet() {
        let done = match(id: "export.done")
        tap(done, "the Done button of the Export sheet")
        // Windows of 8 s, then 6 s twice: long enough for a slow dismiss animation on a busy CI machine, so the
        // retry tap does not land on whatever is behind a sheet that was just closing.
        for window in [8.0, 6.0, 6.0] {
            if poll(window, { !done.exists }) { return }
            if done.exists { done.tap() }
        }
        check(poll(4, { !done.exists }), "The Export sheet was still on screen after tapping Done several times.")
    }

    // MARK: Switches

    /// The element of a Toggle. SwiftUI can expose a Toggle as a switch or as a toggle, depending on the OS version,
    /// so both types are tried before falling back to an element of any type with this identifier.
    func switchElement(identifier: String, timeout: TimeInterval = 10) -> XCUIElement? {
        let candidates = [app.switches.matching(identifier: identifier).firstMatch,
                          app.toggles.matching(identifier: identifier).firstMatch,
                          match(id: identifier)]
        _ = poll(timeout) { candidates.contains { $0.exists } }
        return candidates.first { $0.exists }
    }

    /// true / false for a switch value ("1" / "0"); nil when the element has no readable value.
    func switchState(_ element: XCUIElement) -> Bool? {
        switch element.value {
        case let text as String:
            switch text.lowercased() {
            case "1", "on", "true": return true
            case "0", "off", "false": return false
            default: return nil
            }
        case let number as NSNumber:
            return number.boolValue
        default:
            return nil
        }
    }

    /// Turns a switch on if it is off. The value is read again before every tap, so a switch is never tapped twice
    /// in a row without looking at what the first tap did.
    func turnSwitchOn(identifier: String, _ what: String) {
        guard let toggle = switchElement(identifier: identifier) else {
            check(false, "Could not find the switch for \(what) (identifier \"\(identifier)\") within 10 s.")
            return
        }
        scrollToHittable(toggle)
        guard let before = switchState(toggle) else {
            // The identifier landed on an element that shows no value, so nothing can be verified: tap the
            // trailing end of the row, where the switch is, once.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            settle()
            return
        }
        if before { return }
        // The UISwitch sits at the trailing end of the padded row; tapping the middle of a SwiftUI Toggle row
        // outside a List does not always reach it.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if poll(3, { self.switchState(toggle) == true }) { return }
        toggle.tap()
        check(poll(3, { self.switchState(toggle) == true }),
              "The switch for \(what) did not turn on (it was off before the taps, its value is now \(String(describing: toggle.value))).")
    }

    /// Taps a few places on the plan until something is selected. Returns true when the selection card appeared.
    /// (Where the walls are depends on the plan's fit, so this tries a spread of points instead of one.)
    @discardableResult
    func tapPlanUntilSomethingIsSelected() -> Bool {
        let canvas = match(id: "plan.canvas", label: "Floor plan")
        check(canvas.waitForExistence(timeout: 10), "The plan canvas was not on screen to tap.")
        let points = [CGVector(dx: 0.5, dy: 0.45), CGVector(dx: 0.3, dy: 0.7), CGVector(dx: 0.7, dy: 0.3),
                      CGVector(dx: 0.2, dy: 0.5), CGVector(dx: 0.5, dy: 0.2), CGVector(dx: 0.8, dy: 0.6)]
        for point in points {
            canvas.coordinate(withNormalizedOffset: point).tap()
            if match(id: "plan.selection.close").waitForExistence(timeout: 1.5) { return true }
        }
        return false
    }

    // MARK: Room and Verify

    /// Opens the Rooms tab and the first room in it.
    func openFirstRoom() {
        selectTab("Rooms")
        tap(match(id: "rooms.row"), "the first room in the Rooms tab")
        check(poll(20) { self.match(id: "room.dimension.scanned").exists || self.match(id: "room.dimension.verified").exists },
              "The room screen showed no dimension rows within 20 s.")
    }

    /// Taps the first dimension that is still only scanned (or, with `scannedOnly` false, any dimension) and waits
    /// for the Verify sheet.
    func openVerifySheetFromFirstDimension(scannedOnly: Bool = true) {
        let scanned = match(id: "room.dimension.scanned")
        let row = (scannedOnly || scanned.exists) ? scanned : match(id: "room.dimension.verified")
        tap(row, scannedOnly ? "a dimension row that is still only scanned" : "a dimension row")
        check(match(id: "verify.field", label: "Measured value").waitForExistence(timeout: 15),
              "The Verify sheet did not open (no \"Measured value\" field within 15 s).")
    }

    func cancelVerifySheet() {
        tap(match(id: "verify.cancel", label: "Cancel"), "the Cancel button of the Verify sheet")
        waitUntilGone(match(id: "verify.field", label: "Measured value"), "The Verify sheet")
    }

    /// The scanned value shown in the Verify sheet, as VoiceOver reads it ("4 150 millimetres, plus or minus ..."),
    /// turned into a plain number of the same size plus a few millimetres: a value a person could really have
    /// read off a laser. "3000" if the text cannot be read.
    func plausibleMillimetres() -> String {
        let scanned = match(label: "Scanned value")
        guard scanned.exists, let spoken = scanned.value as? String else { return "3000" }
        var digits = ""
        for character in spoken {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if character == " " || character == "," || character == "\u{00A0}"
                        || character == "\u{202F}" || character == "\u{2009}" {
                continue
            } else if !digits.isEmpty {
                break
            }
        }
        guard let number = Double(digits), number > 100, number < 100_000 else { return "3000" }
        return String(Int(number.rounded()) + 7)
    }
}
