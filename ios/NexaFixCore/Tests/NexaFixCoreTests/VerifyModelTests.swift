import XCTest
@testable import NexaFixCore

/// Tests for the Verify sheet's logic: parsing in the user's unit, the live deviation sentence,
/// typo protection with an explicit override, the opposite-wall hint, and what commit records.
final class VerifyModelTests: XCTestCase {

    // MARK: Fixtures

    private let nb = "\u{00A0}"
    private let mm = DisplayUnits(length: .millimetres)
    private let metres = DisplayUnits(length: .metres)
    private let centimetres = DisplayUnits(length: .centimetres)
    private let inches = DisplayUnits(length: .inches)
    private let feet = DisplayUnits(length: .feetAndInches)
    private let when = Date(timeIntervalSince1970: 1_791_540_000)

    /// 6.2 x 4.5 rectangle: wall 0 south 6.2, wall 1 east 4.5, wall 2 north 6.2, wall 3 west 4.5.
    /// A door on wall 0 (sill 0) and a window on wall 2 (sill 0.9).
    private func living() -> Room {
        Room.rectangle(name: "Living Room", kind: .livingRoom, width: 6.2, depth: 4.5, ceilingHeight: 2.8,
                       openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1.0, width: 3.0)])
    }

    /// 3.0 x 2.4: a 3 m wall makes the percentages easy to check.
    private func small() -> Room {
        Room.rectangle(name: "Study", kind: .office, width: 3.0, depth: 2.4, ceilingHeight: 2.6)
    }

    private func model(_ room: Room, _ target: MeasureTarget, _ units: DisplayUnits? = nil,
                       text: String = "") -> VerifyModel {
        var m = VerifyModel(room: room, target: target, units: units ?? mm)
        m.text = text
        return m
    }

    // MARK: Empty and unreadable

    func testEmptyFieldHasNothingToSave() {
        let room = living()
        let m = model(room, .wallLength(room.walls[0].id))
        XCTAssertEqual(m.check, .empty)
        XCTAssertNil(m.parsedValue)
        XCTAssertNil(m.deviationText)
        XCTAssertNil(m.message)
        XCTAssertFalse(m.canSave)
        XCTAssertFalse(m.needsConfirmation)
        XCTAssertNil(m.commit(date: when))
        XCTAssertEqual(m.placeholder, "3245")
    }

    func testWhitespaceOnlyIsEmpty() {
        let room = living()
        XCTAssertEqual(model(room, .wallLength(room.walls[0].id), text: "  \n ").check, .empty)
    }

    func testTitleAndScannedText() {
        let room = living()
        let m = model(room, .wallLength(room.walls[0].id))
        XCTAssertEqual(m.title, "Wall A length")
        XCTAssertEqual(m.roomName, "Living Room")
        XCTAssertEqual(m.scannedText, "6\(nb)200\(nb)mm")
        XCTAssertEqual(m.scannedValue ?? 0, 6.2, accuracy: 1e-9)
        XCTAssertEqual(m.toleranceText, "\u{00B1}93 mm")
    }

    func testUnreadableTextGetsACalmMessageWithAnExample() {
        let room = living()
        let id = room.walls[0].id
        for bad in ["abc", "3245 kg", "1e3", "-5", "12..3", "10'7\"\"x"] {
            let m = model(room, .wallLength(id), text: bad)
            XCTAssertEqual(m.check, .unreadable("That doesn\u{2019}t look like a length. Try 3245 or 3.245 m."),
                           "text: \(bad)")
            XCTAssertFalse(m.canSave, bad)
            XCTAssertNil(m.deviationText, bad)
            XCTAssertNil(m.commit(date: when), bad)
        }
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "x").message,
                       "That doesn\u{2019}t look like a length. Try 3.245 or 3245 mm.")
        XCTAssertEqual(model(room, .wallLength(id), centimetres, text: "x").message,
                       "That doesn\u{2019}t look like a length. Try 324.5 or 3.245 m.")
        XCTAssertEqual(model(room, .wallLength(id), feet, text: "x").message,
                       "That doesn\u{2019}t look like a length. Try 10' 7 3/4\" or 3245 mm.")
    }

    func testZeroIsRejectedForEverythingButASill() {
        let room = living()
        XCTAssertEqual(model(room, .wallLength(room.walls[0].id), text: "0").check,
                       .unreadable("That doesn\u{2019}t look like a length. Try 3245 or 3.245 m."))
        XCTAssertEqual(model(room, .ceilingHeight, text: "0").check,
                       .unreadable("That doesn\u{2019}t look like a length. Try 3245 or 3.245 m."))
    }

    func testAnAbsurdlyLargeNumberIsUnreadable() {
        let room = living()
        // 300 m: the parser refuses anything over 200 m.
        XCTAssertEqual(model(room, .wallLength(room.walls[0].id), text: "300000").check,
                       .unreadable("That doesn\u{2019}t look like a length. Try 3245 or 3.245 m."))
    }

    // MARK: Parsing in the user's unit

    func testMillimetreUserTypesBareMillimetres() {
        let room = living()
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), mm, text: "6180").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), mm, text: "6.18 m").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), mm, text: "6 180").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), mm, text: "618 cm").parsedValue ?? 0, 6.18, accuracy: 1e-9)
    }

    func testMetreUserTypesBareMetres() {
        let room = living()
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "6.18").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "6,18").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "6180 mm").parsedValue ?? 0, 6.18, accuracy: 1e-9)
    }

    func testCentimetreAndInchUsers() {
        let room = living()
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), centimetres, text: "618").parsedValue ?? 0, 6.18, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), inches, text: "244").parsedValue ?? 0, 244 * 0.0254, accuracy: 1e-9)
    }

    func testFeetAndInchesUserTypesFeetAndInches() {
        let room = living()
        let id = room.walls[0].id
        let expected = 20 * 0.3048 + 4 * 0.0254
        XCTAssertEqual(model(room, .wallLength(id), feet, text: "20'4\"").parsedValue ?? 0, expected, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), feet, text: "20' 4").parsedValue ?? 0, expected, accuracy: 1e-9)
        // A bare number is feet.
        XCTAssertEqual(model(room, .wallLength(id), feet, text: "20").parsedValue ?? 0, 20 * 0.3048, accuracy: 1e-9)
        XCTAssertEqual(model(room, .wallLength(id), feet, text: "").placeholder, "10' 7\"")
    }

    // MARK: Deviation sentence

    func testScanReadShort() {
        let room = small()   // wall 0 is 3.000 m
        let m = model(room, .wallLength(room.walls[0].id), text: "3012")
        XCTAssertEqual(m.deviationText, "Scan read 12\(nb)mm short (0.4 %)")
        XCTAssertEqual(m.deviation ?? 0, 0.012, accuracy: 1e-9)
        XCTAssertEqual(m.check, .ok)
        XCTAssertTrue(m.canSave)
    }

    func testScanReadLong() {
        let room = small()
        let m = model(room, .wallLength(room.walls[0].id), text: "2992")
        XCTAssertEqual(m.deviationText, "Scan read 8\(nb)mm long (0.3 %)")
        XCTAssertEqual(m.deviation ?? 0, -0.008, accuracy: 1e-9)
    }

    func testMatchesTheScan() {
        let room = small()
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), text: "3000").deviationText, "Matches the scan")
        // Under half a millimetre counts as matching.
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "3.0004").deviationText, "Matches the scan")
        XCTAssertNotEqual(model(room, .wallLength(id), metres, text: "3.001").deviationText, "Matches the scan")
    }

    func testLargeDeviationUsesGroupedDigits() {
        let room = living()   // 6.2 m
        let m = model(room, .wallLength(room.walls[0].id), text: "5000")
        XCTAssertEqual(m.deviationText, "Scan read 1\(nb)200\(nb)mm long (24.0 %)")
    }

    func testDeviationFollowsTheInputUnit() {
        let room = small()
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), metres, text: "3.012").deviationText,
                       "Scan read 0.012\(nb)m short (0.4 %)")
        XCTAssertEqual(model(room, .wallLength(id), centimetres, text: "301.2").deviationText,
                       "Scan read 1.2\(nb)cm short (0.4 %)")
    }

    func testFeetAndInchesDeviation() {
        let room = living()   // 6.2 m = 20' 4 1/8"
        let m = model(room, .wallLength(room.walls[0].id), feet, text: "20'3\"")
        // 20' 3" = 6.1722 m, so the scan read 27.8 mm long: 1.0945 in, shown to the sixteenth as 1 1/8".
        XCTAssertEqual(m.deviationText, "Scan read 1 1/8\" long (0.5 %)")
    }

    func testNoPercentWhenItRoundsToZero() {
        var room = Room.rectangle(name: "Hall", width: 100, depth: 3)
        room.walls[0].length = Measured(scanned: 100)
        let m = model(room, .wallLength(room.walls[0].id), metres, text: "100.001")
        XCTAssertEqual(m.deviationText, "Scan read 0.001\(nb)m short")
    }

    // MARK: Typo protection

    func testFarAboveTheScanNeedsConfirmation() {
        let room = living()   // 6.2 m
        var m = model(room, .wallLength(room.walls[0].id), text: "20000")
        let message = "That is far from the scan (6\(nb)200\(nb)mm). Check the number or unit."
        XCTAssertEqual(m.check, .farFromScan(message))
        XCTAssertEqual(m.message, message)
        XCTAssertTrue(m.needsConfirmation)
        XCTAssertFalse(m.canSave)
        XCTAssertNil(m.commit(date: when))
        XCTAssertNotNil(m.deviationText, "the deviation still shows so the person can see how far it is")

        m.confirmOverride()
        XCTAssertFalse(m.needsConfirmation)
        XCTAssertTrue(m.canSave)
        let saved = m.commit(date: when)
        XCTAssertEqual(saved?.walls[0].length.verification?.value ?? 0, 20, accuracy: 1e-9)
    }

    func testFarBelowTheScanNeedsConfirmation() {
        let room = living()
        XCTAssertTrue(model(room, .wallLength(room.walls[0].id), text: "2000").needsConfirmation)
        XCTAssertFalse(model(room, .wallLength(room.walls[0].id), text: "2100").needsConfirmation)
    }

    func testThresholdsAreThreeTimesAndAThird() {
        let room = living()   // 6.2 m: 3x is 18.6 m, a third is 2.0667 m
        let id = room.walls[0].id
        XCTAssertEqual(model(room, .wallLength(id), text: "18500").check, .ok)
        XCTAssertNotEqual(model(room, .wallLength(id), text: "18700").check, .ok)
        XCTAssertEqual(model(room, .wallLength(id), text: "2100").check, .ok)
        XCTAssertNotEqual(model(room, .wallLength(id), text: "2000").check, .ok)
    }

    func testUnderOneMillimetreNeedsConfirmation() {
        let room = living()
        let m = model(room, .wallLength(room.walls[0].id), text: "0.5")
        XCTAssertEqual(m.check, .farFromScan("That is under 1 mm. Check the number or unit."))
        XCTAssertFalse(m.canSave)
    }

    func testTypingAgainWithdrawsTheConfirmation() {
        let room = living()
        var m = model(room, .wallLength(room.walls[0].id), text: "20000")
        m.confirmOverride()
        XCTAssertTrue(m.canSave)
        m.text = "20001"
        XCTAssertFalse(m.canSave, "a new number has not been confirmed")
        XCTAssertTrue(m.needsConfirmation)
        m.text = "6200"
        XCTAssertTrue(m.canSave)
    }

    func testConfirmingAPlausibleValueDoesNothing() {
        let room = living()
        var m = model(room, .wallLength(room.walls[0].id), text: "6200")
        m.confirmOverride()
        XCTAssertFalse(m.overrideConfirmed)
    }

    func testDoorSillMayBeZeroAndHasNoRatioTest() {
        let room = living()
        let door = room.openings[0]
        XCTAssertEqual(door.sillHeight.scanned, 0)
        let zero = model(room, .openingSill(door.id), text: "0")
        XCTAssertEqual(zero.check, .ok)
        XCTAssertTrue(zero.canSave)
        XCTAssertEqual(zero.deviationText, "Matches the scan")
        XCTAssertEqual(model(room, .openingSill(door.id), text: "20").check, .ok)   // a 20 mm threshold
        XCTAssertNotEqual(model(room, .openingSill(door.id), text: "900").check, .ok)   // not a threshold
    }

    func testWindowSillOfZeroIsFarFromTheScan() {
        let room = living()
        let window = room.openings[1]
        XCTAssertEqual(window.sillHeight.scanned, 0.9, accuracy: 1e-9)
        XCTAssertNotEqual(model(room, .openingSill(window.id), text: "0").check, .ok)
        XCTAssertEqual(model(room, .openingSill(window.id), text: "880").check, .ok)
    }

    // MARK: Units on the sheet

    func testSwitchingUnitKeepsTheValue() {
        let room = small()
        var m = model(room, .wallLength(room.walls[0].id), mm, text: "3012")
        m.setUnit(.metres)
        XCTAssertEqual(m.inputUnit, .metres)
        XCTAssertEqual(m.text, "3.012")
        XCTAssertEqual(m.parsedValue ?? 0, 3.012, accuracy: 1e-9)
        XCTAssertEqual(m.placeholder, "3.245")
        XCTAssertEqual(m.scannedText, "3.000\(nb)m")
        m.setUnit(.centimetres)
        XCTAssertEqual(m.text, "301.2")
        m.setUnit(.inches)
        XCTAssertEqual(m.text, "118.58")
        m.setUnit(.feetAndInches)
        XCTAssertEqual(m.text, "9' 10 9/16\"")
    }

    func testCyclingThroughEveryUnitDoesNotDriftTheNumber() {
        let room = small()
        var m = model(room, .wallLength(room.walls[0].id), mm, text: "3012")
        var seen: [LengthUnit] = [m.inputUnit]
        for _ in 0..<LengthUnit.allCases.count {
            m.cycleUnit()
            seen.append(m.inputUnit)
        }
        XCTAssertEqual(seen, [.millimetres, .centimetres, .metres, .inches, .feetAndInches, .millimetres])
        XCTAssertEqual(m.text, "3012")
        XCTAssertEqual(m.parsedValue ?? 0, 3.012, accuracy: 1e-12)
    }

    func testSwitchingUnitOnABadOrEmptyFieldOnlyChangesTheUnit() {
        let room = small()
        var empty = model(room, .wallLength(room.walls[0].id), mm)
        empty.setUnit(.metres)
        XCTAssertEqual(empty.text, "")
        var bad = model(room, .wallLength(room.walls[0].id), mm, text: "abc")
        bad.setUnit(.metres)
        XCTAssertEqual(bad.text, "abc")
        XCTAssertEqual(bad.inputUnit, .metres)
    }

    func testSwitchingUnitKeepsAConfirmedOverride() {
        let room = living()
        var m = model(room, .wallLength(room.walls[0].id), mm, text: "20000")
        m.confirmOverride()
        m.setUnit(.metres)
        XCTAssertEqual(m.text, "20.000")
        XCTAssertTrue(m.canSave)
    }

    func testStartingUnitFollowsTheUsersUnits() {
        let room = living()
        XCTAssertEqual(model(room, .ceilingHeight, feet).inputUnit, .feetAndInches)
        XCTAssertEqual(model(room, .ceilingHeight, inches).inputUnit, .inches)
    }

    // MARK: Opposite wall hint

    func testOppositeWallHint() {
        var room = living()
        room.walls[0].length.verify(6.24, source: .laser, date: when)   // south wall, verified
        let north = room.walls[2].id
        let off = model(room, .wallLength(north), text: "6195")   // 45 mm shorter than the south wall
        XCTAssertEqual(off.contradiction, "Opposite wall is 6\(nb)240\(nb)mm: the room may be out of square")
        XCTAssertNil(model(room, .wallLength(north), text: "6230").contradiction, "10 mm apart is fine")
        XCTAssertNil(model(room, .wallLength(north), text: "6269").contradiction, "29 mm apart is within 3 cm")
        XCTAssertNotNil(model(room, .wallLength(north), text: "6271").contradiction, "31 mm apart is not")
        XCTAssertNil(model(room, .wallLength(north), text: "").contradiction)
        XCTAssertNil(model(room, .wallLength(north), text: "abc").contradiction)
    }

    func testOppositeWallHintWorksBothWaysAroundTheRoom() {
        var room = living()
        room.walls[3].length.verify(4.5, date: when)   // west
        let east = room.walls[1].id
        XCTAssertNotNil(model(room, .wallLength(east), text: "4400").contradiction)
        XCTAssertNil(model(room, .wallLength(east), text: "4510").contradiction)
    }

    func testNoHintWhenTheOppositeWallIsOnlyScanned() {
        let room = living()
        XCTAssertNil(model(room, .wallLength(room.walls[2].id), text: "5000").contradiction)
    }

    func testNoHintForOtherTargets() {
        var room = living()
        room.walls[0].length.verify(6.24, date: when)
        XCTAssertNil(model(room, .ceilingHeight, text: "2500").contradiction)
        XCTAssertNil(model(room, .wallHeight(room.walls[2].id), text: "2500").contradiction)
    }

    func testNoHintForRoomsThatAreNotRectangles() {
        var l = Room.polygon(name: "Open Plan", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2),
                                                          Point2(4, 4), Point2(0, 4)])
        l.walls[0].length.verify(6.5, date: when)
        XCTAssertNil(model(l, .wallLength(l.walls[2].id), text: "2000").contradiction)

        // Four walls but not a rectangle.
        var skew = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(6.5, 4), Point2(1.5, 4)])
        skew.walls[0].length.verify(5.2, date: when)
        XCTAssertNil(model(skew, .wallLength(skew.walls[2].id), text: "4000").contradiction)
    }

    func testHintUsesTheInputUnit() {
        var room = living()
        room.walls[0].length.verify(6.24, date: when)
        let hint = model(room, .wallLength(room.walls[2].id), metres, text: "6.195").contradiction
        XCTAssertEqual(hint, "Opposite wall is 6.240\(nb)m: the room may be out of square")
    }

    // MARK: Source and note

    func testNewCheckDefaultsToLaser() {
        let room = living()
        let m = model(room, .ceilingHeight)
        XCTAssertEqual(m.source, .laser)
        XCTAssertEqual(m.note, "")
        XCTAssertFalse(m.isVerified)
        XCTAssertFalse(m.canClear)
    }

    // MARK: Commit

    func testCommitRecordsTheCheckAndLeavesGeometryAlone() throws {
        let room = living()
        var m = model(room, .wallLength(room.walls[0].id), text: "6180")
        m.source = .tape
        m.note = "  measured at skirting  "
        let saved = try XCTUnwrap(m.commit(date: when))

        let check = try XCTUnwrap(saved.walls[0].length.verification)
        XCTAssertEqual(check.value, 6.18, accuracy: 1e-12)
        XCTAssertEqual(check.source, .tape)
        XCTAssertEqual(check.note, "measured at skirting")
        XCTAssertEqual(check.date, when)
        XCTAssertEqual(saved.walls[0].length.scanned, 6.2, "the scan never changes")
        XCTAssertEqual(saved.walls[0].start, room.walls[0].start)
        XCTAssertEqual(saved.walls[0].end, room.walls[0].end)
        XCTAssertEqual(saved.walls.dropFirst(), room.walls.dropFirst())
        XCTAssertEqual(saved.openings, room.openings)
        XCTAssertEqual(saved.ceilingHeight, room.ceilingHeight)
        XCTAssertNil(room.walls[0].length.verification, "the original room value is untouched")
    }

    func testBlankNoteIsStoredAsNil() throws {
        let room = living()
        var m = model(room, .ceilingHeight, text: "2850")
        m.note = "   "
        let saved = try XCTUnwrap(m.commit(date: when))
        XCTAssertNil(saved.ceilingHeight.verification?.note)
        XCTAssertEqual(saved.ceilingHeight.verification?.source, .laser)
    }

    func testCommitWorksForEveryKindOfTarget() throws {
        let room = living()
        let door = room.openings[0], window = room.openings[1]
        var custom = room
        custom.customMeasurements = [CustomMeasurement(label: "Wardrobe wall", a: Point3(0, 0, 0), b: Point3(3, 0, 4),
                                                       createdAt: when)]
        let cases: [(Room, MeasureTarget, String, Double)] = [
            (room, .wallLength(room.walls[0].id), "6190", 6.19),
            (room, .wallHeight(room.walls[0].id), "2780", 2.78),
            (room, .ceilingHeight, "2790", 2.79),
            (room, .openingWidth(door.id), "910", 0.91),
            (room, .openingHeight(door.id), "2100", 2.1),
            (room, .openingSill(window.id), "905", 0.905),
            (custom, .customLength(custom.customMeasurements[0].id), "5010", 5.01),
        ]
        for (r, target, text, expected) in cases {
            let m = model(r, target, text: text)
            let saved = try XCTUnwrap(m.commit(date: when), "\(target)")
            XCTAssertEqual(saved.measured(target)?.verification?.value ?? 0, expected, accuracy: 1e-12, "\(target)")
            XCTAssertEqual(saved.measured(target)?.scanned, r.measured(target)?.scanned, "\(target)")
        }
    }

    func testCommitFailsForATargetThatIsGone() {
        let room = living()
        let m = model(room, .wallLength(UUID()), text: "6000")
        XCTAssertFalse(m.targetExists)
        XCTAssertFalse(m.canSave)
        XCTAssertNil(m.parsedValue)
        XCTAssertNil(m.commit(date: when))
        XCTAssertNil(m.clear())
        XCTAssertNil(m.verification(date: when))
    }

    func testVerificationValueMatchesWhatCommitStores() throws {
        let room = living()
        var m = model(room, .ceilingHeight, text: "2850")
        m.source = .drawing
        let check = try XCTUnwrap(m.verification(date: when))
        XCTAssertEqual(check, Verification(value: 2.85, source: .drawing, date: when, note: nil))
        XCTAssertEqual(m.commit(date: when)?.ceilingHeight.verification, check)
    }

    // MARK: Editing and clearing a check

    func testOpeningAnAlreadyVerifiedValueFillsTheField() throws {
        var room = living()
        room.walls[0].length.verify(6.24, source: .tape, note: "tape on skirting", date: when)
        let m = VerifyModel(room: room, target: .wallLength(room.walls[0].id), units: mm)
        XCTAssertEqual(m.text, "6240")
        XCTAssertEqual(m.source, .tape)
        XCTAssertEqual(m.note, "tape on skirting")
        XCTAssertTrue(m.isVerified)
        XCTAssertTrue(m.canClear)
        XCTAssertTrue(m.canSave)
        XCTAssertEqual(m.deviationText, "Scan read 40\(nb)mm short (0.6 %)")
        XCTAssertEqual(m.currentVerification?.value, 6.24)
    }

    func testOpeningInFeetAndInchesFillsTheFieldInFeetAndInches() {
        var room = living()
        room.walls[0].length.verify(3.245, date: when)
        let m = VerifyModel(room: room, target: .wallLength(room.walls[0].id), units: feet)
        XCTAssertEqual(m.text, "10' 7 3/4\"")
    }

    func testSavingWithoutEditingKeepsTheStoredNumberExactly() throws {
        var room = living()
        room.walls[0].length.verify(6.2437, date: when)   // shown as 6244 mm
        var m = VerifyModel(room: room, target: .wallLength(room.walls[0].id), units: mm)
        XCTAssertEqual(m.text, "6244")
        m.note = "second look"
        let saved = try XCTUnwrap(m.commit(date: when))
        XCTAssertEqual(saved.walls[0].length.verification?.value ?? 0, 6.2437, accuracy: 1e-12)
        XCTAssertEqual(saved.walls[0].length.verification?.note, "second look")

        m.text = "6245"
        XCTAssertEqual(m.commit(date: when)?.walls[0].length.verification?.value ?? 0, 6.245, accuracy: 1e-12)
    }

    func testClearTakesTheCheckOff() throws {
        var room = living()
        room.ceilingHeight.verify(2.85, date: when)
        let m = VerifyModel(room: room, target: .ceilingHeight, units: mm)
        let cleared = try XCTUnwrap(m.clear())
        XCTAssertNil(cleared.ceilingHeight.verification)
        XCTAssertEqual(cleared.ceilingHeight.scanned, 2.8)
        XCTAssertEqual(cleared.ceilingHeight.value, 2.8)
        XCTAssertTrue(room.ceilingHeight.isVerified, "the model itself does not change")
    }

    func testClearOnAnUncheckedValueChangesNothing() throws {
        let room = living()
        let m = model(room, .ceilingHeight)
        XCTAssertEqual(m.clear(), room)
    }

    // MARK: Value semantics

    func testModelsCompareByContent() {
        let room = living()
        let a = model(room, .ceilingHeight, text: "2800")
        var b = model(room, .ceilingHeight, text: "2800")
        XCTAssertEqual(a, b)
        b.note = "x"
        XCTAssertNotEqual(a, b)
    }

    // MARK: GroupedLength

    func testGroupedLengthText() {
        XCTAssertEqual(GroupedLength.text(3.245, unit: .millimetres), "3\(nb)245\(nb)mm")
        XCTAssertEqual(GroupedLength.text(12.5, unit: .millimetres), "12\(nb)500\(nb)mm")
        XCTAssertEqual(GroupedLength.text(0.999, unit: .millimetres), "999\(nb)mm")
        XCTAssertEqual(GroupedLength.text(0.5, unit: .millimetres), "500\(nb)mm")
        XCTAssertEqual(GroupedLength.text(3.245, unit: .metres), "3.245\(nb)m")
        XCTAssertEqual(GroupedLength.text(3.245, unit: .centimetres), "324.5\(nb)cm")
        XCTAssertEqual(GroupedLength.text(33.245, unit: .centimetres), "3\(nb)324.5\(nb)cm")
        XCTAssertEqual(GroupedLength.text(3.245, unit: .inches), "127.76\(nb)in")
        XCTAssertEqual(GroupedLength.text(3.245, unit: .feetAndInches), "10' 7 3/4\"")
        XCTAssertEqual(GroupedLength.text(-3.245, unit: .millimetres), "-3\(nb)245\(nb)mm")
        XCTAssertEqual(GroupedLength.text(0, unit: .millimetres), "0\(nb)mm")
        XCTAssertEqual(GroupedLength.text(.nan, unit: .millimetres), "no value")
        XCTAssertEqual(GroupedLength.text(.infinity, unit: .feetAndInches), "no value")
    }

    func testGroupedLengthNumberAndDimensions() {
        XCTAssertEqual(GroupedLength.number(3.245, unit: .millimetres), "3\(nb)245")
        XCTAssertEqual(GroupedLength.number(3.245, unit: .feetAndInches), "10' 7 3/4\"")
        XCTAssertEqual(GroupedLength.dimensions(6.24, 4.5, unit: .millimetres), "6\(nb)240 \u{00D7} 4\(nb)500\(nb)mm")
        XCTAssertEqual(GroupedLength.dimensions(6.24, 4.5, unit: .metres), "6.240 \u{00D7} 4.500\(nb)m")
        XCTAssertEqual(GroupedLength.dimensions(6.24, 4.5, unit: .feetAndInches), "20' 5 11/16\" \u{00D7} 14' 9 3/16\"")
    }

    func testGroupedLengthGroupHelper() {
        XCTAssertEqual(GroupedLength.group("123"), "123")
        XCTAssertEqual(GroupedLength.group("1234"), "1\(nb)234")
        XCTAssertEqual(GroupedLength.group("12345.5"), "12\(nb)345.5")
        XCTAssertEqual(GroupedLength.group("-1234567"), "-1\(nb)234\(nb)567")
        XCTAssertEqual(GroupedLength.group("1234.5678"), "1\(nb)234.5678")
        XCTAssertEqual(GroupedLength.group("abc1234"), "abc1234")
    }
}
