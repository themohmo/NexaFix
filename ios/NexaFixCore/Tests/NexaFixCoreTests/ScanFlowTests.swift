import XCTest
@testable import NexaFixCore

final class ScanFlowTests: XCTestCase {

    // MARK: Helpers

    private func draft(_ id: UUID = UUID(), walls: Int = 4) -> RoomDraft {
        RoomDraft(id: id, wallCount: walls, doorCount: 1, windowCount: 1, floorAreaM2: 12)
    }

    /// A flow driven to the state under test through legal events.
    private func flow(in target: ScanStateKind, rooms named: [String] = []) -> ScanFlow {
        var f = ScanFlow()
        for name in named {
            f.send(f.state == .idle ? .start : .scanNext)
            f.send(.finishRoom)
            f.send(.roomFinished(draft()))
            f.send(.named(name: name, kind: .other))
        }
        switch target {
        case .idle:
            XCTAssertTrue(named.isEmpty, "idle with rooms is not reachable without reset")
        case .scanning:
            f.send(named.isEmpty ? .start : .scanNext)
        case .processing:
            f.send(named.isEmpty ? .start : .scanNext)
            f.send(.finishRoom)
        case .awaitingName:
            f.send(named.isEmpty ? .start : .scanNext)
            f.send(.finishRoom)
            f.send(.roomFinished(draft()))
        case .betweenRooms:
            XCTAssertFalse(named.isEmpty)
        case .merging:
            XCTAssertFalse(named.isEmpty)
            f.send(.finishProperty)
        case .finished:
            XCTAssertFalse(named.isEmpty)
            f.send(.finishProperty)
            f.send(.mergeCompleted)
        case .failed:
            XCTAssertFalse(named.isEmpty)
            f.send(.finishProperty)
            f.send(.mergeFailed(message: "No"))
        }
        return f
    }

    enum ScanStateKind { case idle, scanning, processing, awaitingName, betweenRooms, merging, finished, failed }

    private func allEvents() -> [ScanEvent] {
        [.start, .finishRoom, .roomFinished(RoomDraft()), .named(name: "Kitchen", kind: .kitchen), .scanNext,
         .finishProperty, .cancelRoom, .rescanRoom, .mergeCompleted, .mergeFailed(message: "x"), .reset]
    }

    // MARK: Happy path

    func testThreeRoomsFromStartToFinished() {
        var f = ScanFlow()
        XCTAssertEqual(f.state, .idle)

        XCTAssertEqual(f.send(.start), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 0))
        XCTAssertTrue(f.canFinishRoom)

        XCTAssertEqual(f.send(.finishRoom), [.stopCapture(keepARSession: true), .buildRoom])
        XCTAssertEqual(f.state, .processingRoom(roomIndex: 0))
        XCTAssertTrue(f.isProcessingRoom)

        let d1 = draft()
        XCTAssertEqual(f.send(.roomFinished(d1)), [])
        XCTAssertEqual(f.state, .awaitingName(d1))
        XCTAssertEqual(f.draftAwaitingName, d1)

        XCTAssertEqual(f.send(.named(name: "  Living   Room ", kind: .livingRoom)), [])
        XCTAssertEqual(f.state, .betweenRooms)
        XCTAssertEqual(f.rooms.map(\.name), ["Living Room"])
        XCTAssertEqual(f.rooms.first?.id, d1.id)

        XCTAssertEqual(f.send(.scanNext), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 1))
        f.send(.finishRoom)
        f.send(.roomFinished(draft()))
        f.send(.named(name: "Kitchen", kind: .kitchen))
        f.send(.scanNext)
        XCTAssertEqual(f.state, .scanning(roomIndex: 2))
        f.send(.finishRoom)
        f.send(.roomFinished(draft()))
        f.send(.named(name: "Bedroom", kind: .bedroom))
        XCTAssertEqual(f.rooms.count, 3)
        XCTAssertTrue(f.canFinishProperty)

        XCTAssertEqual(f.send(.finishProperty), [.mergeStructure])
        XCTAssertEqual(f.state, .merging)
        XCTAssertEqual(f.send(.mergeCompleted), [.saveResult])
        XCTAssertEqual(f.state, .finished)
        XCTAssertEqual(f.rooms.map(\.name), ["Living Room", "Kitchen", "Bedroom"])
    }

    func testRoomFinishedIsAcceptedDirectlyWhileScanning() {
        var f = flow(in: .scanning)
        let d = draft()
        XCTAssertEqual(f.send(.roomFinished(d)), [])
        XCTAssertEqual(f.state, .awaitingName(d))
    }

    func testReducingDoesNotMutateTheOriginal() {
        let f = ScanFlow()
        let result = f.reducing(.start)
        XCTAssertEqual(f.state, .idle)
        XCTAssertEqual(result.flow.state, .scanning(roomIndex: 0))
        XCTAssertEqual(result.effects, [.startCapture])
    }

    func testCurrentRoomIndex() {
        var f = ScanFlow()
        XCTAssertEqual(f.currentRoomIndex, 0)
        f.send(.start)
        XCTAssertEqual(f.currentRoomIndex, 0)
        let g = flow(in: .scanning, rooms: ["A", "B"])
        XCTAssertEqual(g.currentRoomIndex, 2)
        XCTAssertEqual(flow(in: .betweenRooms, rooms: ["A", "B"]).currentRoomIndex, 2)
    }

    // MARK: Cancel and rescan

    func testCancelWhileScanningFirstRoomEndsTheScan() {
        var f = flow(in: .scanning)
        XCTAssertEqual(f.send(.cancelRoom), [.stopCapture(keepARSession: false)])
        XCTAssertEqual(f.state, .idle)
        XCTAssertTrue(f.rooms.isEmpty)
    }

    func testCancelWhileScanningLaterRoomKeepsEarlierRoomsAndTheARSession() {
        var f = flow(in: .scanning, rooms: ["Living Room", "Kitchen"])
        XCTAssertEqual(f.send(.cancelRoom), [.stopCapture(keepARSession: true)])
        XCTAssertEqual(f.state, .betweenRooms)
        XCTAssertEqual(f.rooms.map(\.name), ["Living Room", "Kitchen"])
        XCTAssertTrue(f.canFinishProperty)
        // and the person can carry on
        XCTAssertEqual(f.send(.scanNext), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 2))
    }

    func testCancelWhileProcessing() {
        var first = flow(in: .processing)
        XCTAssertEqual(first.send(.cancelRoom), [.stopCapture(keepARSession: false)])
        XCTAssertEqual(first.state, .idle)

        var later = flow(in: .processing, rooms: ["Living Room"])
        XCTAssertEqual(later.send(.cancelRoom), [.stopCapture(keepARSession: true)])
        XCTAssertEqual(later.state, .betweenRooms)
        XCTAssertEqual(later.rooms.count, 1)
    }

    func testLateRoomFinishedAfterCancelIsIgnored() {
        var f = flow(in: .processing, rooms: ["Living Room"])
        f.send(.cancelRoom)
        XCTAssertEqual(f.send(.roomFinished(draft())), [])
        XCTAssertEqual(f.state, .betweenRooms)
        XCTAssertEqual(f.rooms.count, 1)
    }

    func testDiscardingTheDraftAwaitingAName() {
        var first = flow(in: .awaitingName)
        XCTAssertEqual(first.send(.cancelRoom), [.stopCapture(keepARSession: false)])
        XCTAssertEqual(first.state, .idle)

        var later = flow(in: .awaitingName, rooms: ["Living Room"])
        XCTAssertEqual(later.send(.cancelRoom), [.stopCapture(keepARSession: true)])
        XCTAssertEqual(later.state, .betweenRooms)
        XCTAssertEqual(later.rooms.map(\.name), ["Living Room"])
    }

    func testRescanFromTheNameSheet() {
        var f = flow(in: .awaitingName, rooms: ["Living Room"])
        XCTAssertEqual(f.send(.rescanRoom), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 1))
        XCTAssertEqual(f.rooms.count, 1)
        // the old draft is gone: finishing again produces a new one
        f.send(.finishRoom)
        let again = draft()
        f.send(.roomFinished(again))
        XCTAssertEqual(f.state, .awaitingName(again))
    }

    func testCancelTwiceIsHarmless() {
        var f = flow(in: .scanning, rooms: ["Living Room"])
        f.send(.cancelRoom)
        XCTAssertEqual(f.send(.cancelRoom), [])
        XCTAssertEqual(f.state, .betweenRooms)
        XCTAssertEqual(f.rooms.count, 1)

        var g = flow(in: .scanning)
        g.send(.cancelRoom)
        XCTAssertEqual(g.send(.cancelRoom), [])
        XCTAssertEqual(g.state, .idle)
    }

    // MARK: Idempotence and illegal events

    func testRepeatedEventsDoNothingTheSecondTime() {
        var f = ScanFlow()
        f.send(.start)
        XCTAssertEqual(f.send(.start), [], "a second start must not start a second capture")

        XCTAssertFalse(f.send(.finishRoom).isEmpty)
        XCTAssertEqual(f.send(.finishRoom), [], "a second Finish room must not stop twice")

        let d = draft()
        f.send(.roomFinished(d))
        XCTAssertEqual(f.send(.roomFinished(d)), [])
        XCTAssertEqual(f.state, .awaitingName(d))

        f.send(.named(name: "Living Room", kind: .livingRoom))
        XCTAssertEqual(f.send(.named(name: "Living Room", kind: .livingRoom)), [])
        XCTAssertEqual(f.rooms.count, 1)

        XCTAssertEqual(f.send(.scanNext), [.startCapture])
        XCTAssertEqual(f.send(.scanNext), [], "a second Scan next room must not start a second capture")

        var g = flow(in: .betweenRooms, rooms: ["A"])
        XCTAssertEqual(g.send(.finishProperty), [.mergeStructure])
        XCTAssertEqual(g.send(.finishProperty), [], "a second Finish property must not merge twice")
        XCTAssertEqual(g.send(.mergeCompleted), [.saveResult])
        XCTAssertEqual(g.send(.mergeCompleted), [], "the result must be handed over once")
        XCTAssertEqual(g.state, .finished)
    }

    func testEveryIllegalEventIsIgnoredInEveryState() {
        // (state kind, events that are legal there)
        let legal: [(ScanStateKind, ScanFlow, [String])] = [
            (.idle, flow(in: .idle), ["start"]),
            (.scanning, flow(in: .scanning, rooms: ["A"]), ["finishRoom", "roomFinished", "cancelRoom"]),
            (.processing, flow(in: .processing, rooms: ["A"]), ["roomFinished", "cancelRoom"]),
            (.awaitingName, flow(in: .awaitingName, rooms: ["A"]), ["named", "rescanRoom", "cancelRoom"]),
            (.betweenRooms, flow(in: .betweenRooms, rooms: ["A"]), ["scanNext", "finishProperty"]),
            (.merging, flow(in: .merging, rooms: ["A"]), ["mergeCompleted", "mergeFailed"]),
            (.finished, flow(in: .finished, rooms: ["A"]), []),
            (.failed, flow(in: .failed, rooms: ["A"]), ["finishProperty", "scanNext"]),
        ]
        func label(_ e: ScanEvent) -> String {
            switch e {
            case .start: return "start"
            case .finishRoom: return "finishRoom"
            case .roomFinished: return "roomFinished"
            case .named: return "named"
            case .scanNext: return "scanNext"
            case .finishProperty: return "finishProperty"
            case .cancelRoom: return "cancelRoom"
            case .rescanRoom: return "rescanRoom"
            case .mergeCompleted: return "mergeCompleted"
            case .mergeFailed: return "mergeFailed"
            case .reset: return "reset"
            }
        }
        for (kind, start, allowed) in legal {
            for event in allEvents() where event != .reset && !allowed.contains(label(event)) {
                let result = start.reducing(event)
                XCTAssertEqual(result.flow, start, "\(label(event)) must change nothing in \(kind)")
                XCTAssertTrue(result.effects.isEmpty, "\(label(event)) must have no effects in \(kind)")
            }
        }
    }

    func testFinishPropertyWithoutRoomsIsIgnored() {
        var f = ScanFlow()
        XCTAssertEqual(f.send(.finishProperty), [])
        f.send(.start)
        XCTAssertEqual(f.send(.finishProperty), [])
        XCTAssertFalse(f.canFinishProperty)
        XCTAssertEqual(f.state, .scanning(roomIndex: 0))
    }

    func testNamingWithoutAFinishedScanIsIgnored() {
        var f = ScanFlow()
        XCTAssertEqual(f.send(.named(name: "Kitchen", kind: .kitchen)), [])
        f.send(.start)
        XCTAssertEqual(f.send(.named(name: "Kitchen", kind: .kitchen)), [])
        XCTAssertTrue(f.rooms.isEmpty)
    }

    // MARK: Reset

    func testResetClearsEverythingAndStopsWhatIsRunning() {
        for kind in [ScanStateKind.scanning, .processing, .awaitingName] {
            var f = flow(in: kind, rooms: ["A", "B"])
            XCTAssertEqual(f.send(.reset), [.stopCapture(keepARSession: false)], "\(kind)")
            XCTAssertEqual(f.state, .idle)
            XCTAssertTrue(f.rooms.isEmpty)
        }
        for kind in [ScanStateKind.betweenRooms, .merging, .failed] {
            var f = flow(in: kind, rooms: ["A"])
            XCTAssertEqual(f.send(.reset), [.stopCapture(keepARSession: false)], "\(kind)")
            XCTAssertEqual(f.state, .idle)
            XCTAssertTrue(f.rooms.isEmpty)
        }
        var done = flow(in: .finished, rooms: ["A"])
        XCTAssertEqual(done.send(.reset), [])
        XCTAssertEqual(done.state, .idle)
        XCTAssertTrue(done.rooms.isEmpty)

        var idle = ScanFlow()
        XCTAssertEqual(idle.send(.reset), [])
    }

    func testAFlowCanBeUsedAgainAfterReset() {
        var f = flow(in: .finished, rooms: ["Living Room"])
        f.send(.reset)
        XCTAssertEqual(f.send(.start), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 0))
        f.send(.finishRoom)
        f.send(.roomFinished(draft()))
        // "Living Room" is free again after reset
        XCTAssertEqual(f.validate(name: "Living Room"), .valid("Living Room"))
    }

    // MARK: Merge failure keeps the rooms

    func testMergeFailureKeepsRoomsAndAllowsRetryOrMoreScanning() {
        var f = flow(in: .failed, rooms: ["Living Room", "Kitchen"])
        XCTAssertEqual(f.state, .failed("No"))
        XCTAssertEqual(f.rooms.count, 2)
        XCTAssertTrue(f.canFinishProperty)
        XCTAssertTrue(f.canScanNext)

        XCTAssertEqual(f.send(.finishProperty), [.mergeStructure])
        XCTAssertEqual(f.state, .merging)
        f.send(.mergeFailed(message: "Again"))
        XCTAssertEqual(f.state, .failed("Again"))

        XCTAssertEqual(f.send(.scanNext), [.startCapture])
        XCTAssertEqual(f.state, .scanning(roomIndex: 2))
        XCTAssertEqual(f.rooms.count, 2)
    }

    func testMergeFailureCannotBeCancelledAway() {
        var f = flow(in: .failed, rooms: ["A"])
        XCTAssertEqual(f.send(.cancelRoom), [])
        XCTAssertEqual(f.rooms.count, 1)
    }

    // MARK: Validation

    func testNameValidation() {
        let f = flow(in: .betweenRooms, rooms: ["Living Room", "Master Bedroom"])
        XCTAssertEqual(f.validate(name: ""), .empty)
        XCTAssertEqual(f.validate(name: "   \n\t "), .empty)
        XCTAssertEqual(f.validate(name: "  Study  "), .valid("Study"))
        XCTAssertEqual(f.validate(name: "Dining\u{00A0}  Room"), .valid("Dining Room"))
        XCTAssertEqual(f.validate(name: String(repeating: "x", count: 41)), .tooLong(limit: 40))
        XCTAssertEqual(f.validate(name: String(repeating: "x", count: 40)), .valid(String(repeating: "x", count: 40)))

        // duplicates ignore case, accents and spacing
        for typed in ["living room", "LIVING ROOM", " Living   Room ", "Líving Róom"] {
            guard case .duplicate(let existing, let suggestion) = f.validate(name: typed) else {
                XCTFail("\(typed) should be a duplicate"); continue
            }
            XCTAssertEqual(existing, "Living Room")
            XCTAssertEqual(suggestion, "Living Room 2")
        }
        XCTAssertFalse(f.validate(name: "living room").isValid)
        XCTAssertNotNil(f.validate(name: "living room").message)
        XCTAssertNil(f.validate(name: "Study").message)
        XCTAssertEqual(f.validate(name: "").message, "Give this room a name.")
    }

    func testNamesOfThePropertyAreTakenToo() {
        var f = ScanFlow(existingRoomNames: ["Kitchen", "Bedroom 2"])
        XCTAssertFalse(f.validate(name: "kitchen").isValid)
        XCTAssertEqual(f.suggestedName(for: .kitchen), "Kitchen 2")
        XCTAssertEqual(f.suggestedName(for: .bedroom), "Bedroom")
        f.send(.start)
        f.send(.finishRoom)
        f.send(.roomFinished(draft()))
        f.send(.named(name: "Bedroom", kind: .bedroom))
        // "Bedroom" and "Bedroom 2" are now both taken
        XCTAssertEqual(f.suggestedName(for: .bedroom), "Bedroom 3")
    }

    func testInvalidNameIsRejectedAndTheDraftStaysWaiting() {
        var f = flow(in: .awaitingName, rooms: ["Kitchen"])
        let waiting = f.draftAwaitingName
        XCTAssertEqual(f.send(.named(name: "  ", kind: .other)), [])
        XCTAssertEqual(f.send(.named(name: "kitchen", kind: .kitchen)), [])
        XCTAssertEqual(f.draftAwaitingName, waiting)
        XCTAssertEqual(f.rooms.count, 1)
        XCTAssertEqual(f.send(.named(name: "Kitchen 2", kind: .kitchen)), [])
        XCTAssertEqual(f.rooms.map(\.name), ["Kitchen", "Kitchen 2"])
    }

    func testTwoRoomsCanNeverEndUpWithTheSameName() {
        var f = ScanFlow()
        f.send(.start)
        for _ in 0..<4 {
            f.send(.finishRoom)
            f.send(.roomFinished(draft()))
            f.send(.named(name: "Bedroom", kind: .bedroom))     // repeats are rejected
            f.send(.named(name: f.suggestedName(for: .bedroom), kind: .bedroom))
            f.send(.scanNext)
        }
        let names = f.rooms.map(\.name)
        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, names.count)
        XCTAssertEqual(Array(names.prefix(3)), ["Bedroom", "Bedroom 2", "Bedroom 3"])
    }

    // MARK: Suggestions

    func testDefaultNamesAutoIncrement() {
        var f = ScanFlow()
        XCTAssertEqual(f.suggestedName(for: .livingRoom), "Living Room")
        XCTAssertEqual(f.suggestedName(for: .bedroom), "Bedroom")
        XCTAssertEqual(f.suggestedName(for: .other), "Room")
        f.send(.start)
        var seen: [String] = []
        for _ in 0..<3 {
            let name = f.suggestedName(for: .bedroom)
            seen.append(name)
            f.send(.finishRoom)
            f.send(.roomFinished(draft()))
            f.send(.named(name: name, kind: .bedroom))
            f.send(.scanNext)
        }
        XCTAssertEqual(seen, ["Bedroom", "Bedroom 2", "Bedroom 3"])
    }

    func testFreeNameHandlesTrailingNumbersAndGaps() {
        XCTAssertEqual(RoomKindSuggester.freeName(base: "Bedroom", taken: []), "Bedroom")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "Bedroom", taken: ["bedroom"]), "Bedroom 2")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "Bedroom 2", taken: ["Bedroom", "Bedroom 2"]), "Bedroom 3")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "Bedroom 2", taken: ["Bedroom 2"]), "Bedroom")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "Bedroom", taken: ["Bedroom", "Bedroom 3"]), "Bedroom 2")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "", taken: []), "Room")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "  ", taken: ["Room"]), "Room 2")
        XCTAssertEqual(RoomKindSuggester.freeName(base: "3", taken: ["3"]), "3 2")
    }

    func testKindSuggestionsStartWithTheLivingRoomForAnApartment() {
        let fresh = ScanFlow()
        XCTAssertEqual(fresh.suggestedKind, .livingRoom)
        XCTAssertEqual(Array(fresh.suggestedKinds.prefix(4)), [.livingRoom, .kitchen, .dining, .masterBedroom])
    }

    func testKindSuggestionsAdvanceAsRoomsAreScanned() {
        var f = ScanFlow()
        func scan(_ name: String, _ kind: RoomKind) {
            f.send(f.state == .idle ? .start : .scanNext)
            f.send(.finishRoom)
            f.send(.roomFinished(draft()))
            f.send(.named(name: name, kind: kind))
        }
        scan("Living Room", .livingRoom)
        XCTAssertEqual(f.suggestedKind, .kitchen)
        scan("Kitchen", .kitchen)
        scan("Dining", .dining)
        scan("Master Bedroom", .masterBedroom)
        XCTAssertEqual(f.suggestedKind, .bathroom)
        scan("En-suite", .bathroom)
        XCTAssertEqual(f.suggestedKind, .bedroom)
        scan("Bedroom", .bedroom)
        XCTAssertEqual(f.suggestedKind, .bathroom)
    }

    func testEveryKindIsAlwaysOfferedExactlyOnceAndOtherIsLast() {
        let samples: [[RoomKind]] = [[], [.livingRoom], [.bedroom, .bedroom, .bedroom, .bedroom, .bedroom],
                                     [.office, .office, .office], RoomKind.allCases]
        for used in samples {
            for style in [RoomKindSuggester.Style.apartment, .office] {
                let ordered = RoomKindSuggester.ordered(used: used, style: style)
                XCTAssertEqual(ordered.count, RoomKind.allCases.count)
                XCTAssertEqual(Set(ordered), Set(RoomKind.allCases))
                XCTAssertEqual(ordered.last, .other)
            }
        }
    }

    func testOfficesAreRecognised() {
        XCTAssertEqual(RoomKindSuggester.ordered(used: [], style: .office).first, .reception)
        // an office kind scanned in this session switches the order
        XCTAssertEqual(RoomKindSuggester.inferStyle(used: [.reception], existingNames: []), .office)
        // so does a property that already has office-sounding rooms
        XCTAssertEqual(RoomKindSuggester.inferStyle(used: [], existingNames: ["Meeting room A"]), .office)
        XCTAssertEqual(RoomKindSuggester.inferStyle(used: [.kitchen], existingNames: ["Kitchen"]), .apartment)
        let f = ScanFlow(existingRoomNames: [], style: .office)
        XCTAssertEqual(f.suggestedKind, .reception)
        let g = ScanFlow(existingRoomNames: ["Reception"])
        XCTAssertEqual(g.suggestedKind, .office, "the reception is already scanned")
        // an apartment that already has its living room and kitchen moves on
        let h = ScanFlow(existingRoomNames: ["Living Room", "Kitchen 2"])
        XCTAssertEqual(h.suggestedKind, .dining)
        XCTAssertEqual(RoomKindSuggester.kind(named: "Master Bedroom 3"), .masterBedroom)
        XCTAssertNil(RoomKindSuggester.kind(named: "Study"))
        XCTAssertNil(RoomKindSuggester.kind(named: "Room 2"))
    }

    // MARK: Interface questions

    func testWouldLoseWork() {
        XCTAssertFalse(ScanFlow().wouldLoseWork)
        XCTAssertFalse(flow(in: .scanning).wouldLoseWork)
        XCTAssertTrue(flow(in: .processing).wouldLoseWork)
        XCTAssertTrue(flow(in: .awaitingName).wouldLoseWork)
        XCTAssertTrue(flow(in: .betweenRooms, rooms: ["A"]).wouldLoseWork)
        XCTAssertTrue(flow(in: .scanning, rooms: ["A"]).wouldLoseWork)
        XCTAssertTrue(flow(in: .merging, rooms: ["A"]).wouldLoseWork)
    }

    func testButtonAvailability() {
        let scanning = flow(in: .scanning)
        XCTAssertTrue(scanning.canFinishRoom)
        XCTAssertFalse(scanning.canScanNext)
        XCTAssertFalse(scanning.canFinishProperty)
        let between = flow(in: .betweenRooms, rooms: ["A"])
        XCTAssertFalse(between.canFinishRoom)
        XCTAssertTrue(between.canScanNext)
        XCTAssertTrue(between.canFinishProperty)
        XCTAssertFalse(flow(in: .merging, rooms: ["A"]).canScanNext)
    }

    func testDraftFromStats() {
        let stats = LiveScanStats(walls: 5, doors: 2, windows: 3, openings: 1, objects: 4, roughFloorAreaM2: 18.5)
        let d = RoomDraft(stats: stats, warnings: ["Ceiling height guessed"])
        XCTAssertEqual([d.wallCount, d.doorCount, d.windowCount, d.openingCount], [5, 2, 3, 1])
        XCTAssertEqual(d.floorAreaM2, 18.5)
        XCTAssertEqual(d.warnings, ["Ceiling height guessed"])
        XCTAssertEqual(RoomDraft(stats: stats, floorAreaM2: 20).floorAreaM2, 20)
    }

    // MARK: Fuzz

    func testRandomEventSequencesKeepTheInvariants() {
        var seed: UInt64 = 0x5EED
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        let names = ["Living Room", "living room", "Kitchen", "", "Bedroom", "Bedroom 2", "  ", "Bath"]
        for run in 0..<300 {
            var f = ScanFlow(existingRoomNames: run % 3 == 0 ? ["Hall"] : [])
            for _ in 0..<60 {
                let before = f
                let event: ScanEvent
                switch next() % 12 {
                case 0: event = .start
                case 1: event = .finishRoom
                case 2: event = .roomFinished(RoomDraft(wallCount: next() % 6))
                case 3, 4: event = .named(name: names[next() % names.count], kind: RoomKind.allCases[next() % RoomKind.allCases.count])
                case 5: event = .scanNext
                case 6: event = .finishProperty
                case 7: event = .cancelRoom
                case 8: event = .rescanRoom
                case 9: event = .mergeCompleted
                case 10: event = .mergeFailed(message: "x")
                default: event = next() % 8 == 0 ? .reset : .scanNext
                }
                let effects = f.send(event)

                // rooms only grow, except on reset
                if event == .reset {
                    XCTAssertTrue(f.rooms.isEmpty)
                    XCTAssertEqual(f.state, .idle)
                } else {
                    XCTAssertGreaterThanOrEqual(f.rooms.count, before.rooms.count)
                    XCTAssertLessThanOrEqual(f.rooms.count, before.rooms.count + 1)
                    if f.rooms.count > before.rooms.count { XCTAssertEqual(f.rooms.last?.name.isEmpty, false) }
                }

                // names are unique and never empty
                let keys = (f.existingRoomNames + f.rooms.map(\.name)).map(ScanFlow.key)
                XCTAssertEqual(Set(keys).count, keys.count, "run \(run)")
                XCTAssertFalse(f.rooms.contains { $0.name.isEmpty })

                // an ignored event changes nothing
                if effects.isEmpty && f.state == before.state { XCTAssertEqual(f, before) }

                // scanning index points at the next room
                if case .scanning(let index) = f.state { XCTAssertEqual(index, f.rooms.count) }
                if case .processingRoom(let index) = f.state { XCTAssertEqual(index, f.rooms.count) }

                // the capture is started only when a scan begins, and the state agrees
                if effects.contains(.startCapture) { XCTAssertTrue(f.isCapturing) }
                if effects.contains(.mergeStructure) { XCTAssertEqual(f.state, .merging); XCTAssertFalse(f.rooms.isEmpty) }
                if effects.contains(.saveResult) { XCTAssertEqual(f.state, .finished) }
                // merging is only ever entered with rooms
                if f.state == .merging || f.state == .finished { XCTAssertFalse(f.rooms.isEmpty) }
            }
        }
    }

    // MARK: Live stats

    /// A 4 m by 3 m room as RoomPlan would report it: four walls, local x along the wall, centre origin.
    private func rectangleCapture(withFloorPolygon plane: String? = nil, doors: Int = 1, windows: Int = 2) -> RawCapture {
        func wall(_ cx: Double, _ cz: Double, _ width: Double, yaw: Double) -> RawSurface {
            RawSurface(kind: .wall, transform: .yawTranslation(yaw: yaw, Point3(cx, 1.4, cz)),
                       dimensions: Point3(width, 2.8, 0))
        }
        var capture = RawCapture(walls: [
            wall(2, 0, 4, yaw: 0), wall(4, -1.5, 3, yaw: Double.pi / 2),
            wall(2, -3, 4, yaw: 0), wall(0, -1.5, 3, yaw: Double.pi / 2),
        ])
        capture.doors = (0..<doors).map { _ in RawSurface(kind: .door, transform: .identity, dimensions: Point3(0.9, 2.1, 0)) }
        capture.windows = (0..<windows).map { _ in RawSurface(kind: .window, transform: .identity, dimensions: Point3(1.2, 1.2, 0)) }
        if let plane {
            let corners: [Point3] = plane == "xy"
                ? [Point3(-2, -1.5, 0), Point3(2, -1.5, 0), Point3(2, 1.5, 0), Point3(-2, 1.5, 0)]
                : [Point3(-2, 0, -1.5), Point3(2, 0, -1.5), Point3(2, 0, 1.5), Point3(-2, 0, 1.5)]
            capture.floors = [RawSurface(kind: .floor, transform: .identity, dimensions: Point3(4, 3, 0), polygonCorners: corners)]
        }
        return capture
    }

    func testStatsCountsAndHullArea() {
        let stats = LiveScanStats(capture: rectangleCapture())
        XCTAssertEqual([stats.walls, stats.doors, stats.windows, stats.openings, stats.objects], [4, 1, 2, 0, 0])
        XCTAssertEqual(stats.roughFloorAreaM2 ?? 0, 12, accuracy: 1e-9)
        XCTAssertTrue(stats.hasEnoughToFinish)
    }

    func testStatsPreferTheFloorPolygonInAnyPlane() {
        for plane in ["xy", "xz"] {
            let stats = LiveScanStats(capture: rectangleCapture(withFloorPolygon: plane))
            XCTAssertEqual(stats.roughFloorAreaM2 ?? 0, 12, accuracy: 1e-9, plane)
        }
        // a floor polygon wins over the hull even when the walls disagree
        var capture = rectangleCapture(withFloorPolygon: "xy")
        capture.floors[0].polygonCorners = [Point3(0, 0, 0), Point3(1, 0, 0), Point3(1, 1, 0)]
        XCTAssertEqual(LiveScanStats(capture: capture).roughFloorAreaM2 ?? 0, 0.5, accuracy: 1e-9)
    }

    func testStatsFallBackToTheFloorBoundingBoxAndThenToNothing() {
        var capture = RawCapture()
        XCTAssertNil(LiveScanStats(capture: capture).roughFloorAreaM2)
        XCTAssertEqual(LiveScanStats(capture: capture), .empty)
        capture.floors = [RawSurface(kind: .floor, transform: .identity, dimensions: Point3(5, 4, 0))]
        XCTAssertEqual(LiveScanStats(capture: capture).roughFloorAreaM2 ?? 0, 20, accuracy: 1e-9)

        // two walls are not enough for a hull
        var two = RawCapture(walls: Array(rectangleCapture().walls.prefix(2)))
        XCTAssertNil(LiveScanStats(capture: two).roughFloorAreaM2)
        XCTAssertFalse(LiveScanStats(capture: two).hasEnoughToFinish)
        two.walls.append(rectangleCapture().walls[2])
        XCTAssertTrue(LiveScanStats(capture: two).hasEnoughToFinish)
    }

    func testStatsIgnoreNonFiniteGeometry() {
        var capture = rectangleCapture()
        capture.walls[0].transform = Matrix4(columnMajor: [Double.nan, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        let stats = LiveScanStats(capture: capture)
        if let area = stats.roughFloorAreaM2 { XCTAssertTrue(area.isFinite) }
    }

    func testStatsText() {
        let stats = LiveScanStats(walls: 6, doors: 1, windows: 2, roughFloorAreaM2: 14.23)
        XCTAssertEqual(stats.summary(units: .default), "6 walls \u{00B7} 1 door \u{00B7} 2 windows \u{00B7} about 14.2 m\u{00B2}")
        XCTAssertEqual(stats.spokenSummary(units: .default), "6 walls, 1 door, 2 windows, roughly 14.2 square metres")
        let feet = DisplayUnits(length: .feetAndInches, area: .squareFeet)
        XCTAssertEqual(stats.summary(units: feet), "6 walls \u{00B7} 1 door \u{00B7} 2 windows \u{00B7} about 153 sq ft")
        XCTAssertEqual(stats.spokenSummary(units: feet), "6 walls, 1 door, 2 windows, roughly 153 square feet")
        XCTAssertEqual(LiveScanStats(walls: 1).summary(units: .default), "1 wall \u{00B7} 0 doors \u{00B7} 0 windows")
        XCTAssertNil(LiveScanStats.empty.areaText(units: .default))
        XCTAssertNil(LiveScanStats(roughFloorAreaM2: .infinity).areaText(units: .default))
    }

    func testPolygonAndHullMaths() {
        XCTAssertEqual(LiveScanStats.polygonArea3D([Point3(0, 0, 0), Point3(1, 0, 0)]), 0)
        // a unit square tilted in space keeps its area
        let tilted = [Point3(0, 0, 0), Point3(1, 1, 0), Point3(1, 1, 1), Point3(0, 0, 1)]
        XCTAssertEqual(LiveScanStats.polygonArea3D(tilted), 2.0.squareRoot(), accuracy: 1e-9)
        // winding does not matter
        XCTAssertEqual(LiveScanStats.polygonArea3D(tilted.reversed()), 2.0.squareRoot(), accuracy: 1e-9)

        let hull = LiveScanStats.convexHull([Point2(0, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3),
                                             Point2(2, 1), Point2(2, 2), Point2(0, 0)])
        XCTAssertEqual(hull.count, 4)
        XCTAssertEqual(Polygon.area(hull), 12, accuracy: 1e-9)
        XCTAssertTrue(Polygon.isCounterClockwise(hull))
        XCTAssertEqual(LiveScanStats.convexHull([Point2(1, 1)]).count, 1)
        XCTAssertEqual(LiveScanStats.convexHull([]).count, 0)
        // collinear points have no area
        XCTAssertEqual(Polygon.area(LiveScanStats.convexHull([Point2(0, 0), Point2(1, 1), Point2(2, 2)])), 0, accuracy: 1e-9)
    }

    // MARK: Coaching

    func testTrackingTroubleBeatsEverythingElse() {
        let stats = LiveScanStats(walls: 5)
        for issue in ScanTrackingIssue.allCases where issue != .none && issue != .initializing {
            let m = ScanCoach.message(instruction: .turnOnLight, tracking: issue, stats: stats)
            XCTAssertNotEqual(m.text, "Turn on a light", "\(issue)")
            XCTAssertGreaterThanOrEqual(m.level, .caution, "\(issue)")
        }
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .relocalizing, stats: stats).level, .critical)
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .interrupted, stats: stats).level, .critical)
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .excessiveMotion, stats: stats).level, .caution)
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .initializing, stats: stats).level, .info)
    }

    func testStartingUpGivesWayToARealInstruction() {
        let stats = LiveScanStats(walls: 1)
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .initializing, stats: stats).text,
                       "Getting ready. Move the device slowly.")
        XCTAssertEqual(ScanCoach.message(instruction: .turnOnLight, tracking: .initializing, stats: stats).text,
                       "Turn on a light")
        XCTAssertEqual(ScanCoach.message(instruction: .normal, tracking: .none, stats: stats).text,
                       "Move slowly along the walls")
    }

    func testRoomPlanInstructionsGetPlainWords() {
        let stats = LiveScanStats(walls: 2)
        func text(_ i: ScanInstruction) -> String { ScanCoach.message(instruction: i, tracking: .none, stats: stats).text }
        XCTAssertEqual(text(.moveCloseToWall), "Move a little closer to the wall")
        XCTAssertEqual(text(.moveAwayFromWall), "Step back from the wall")
        XCTAssertEqual(text(.slowDown), "Move slowly along the walls")
        XCTAssertEqual(text(.turnOnLight), "Turn on a light")
        XCTAssertEqual(text(.lowTexture), "Aim at the corners")
        XCTAssertEqual(text(.normal), "Move slowly along the walls")
        for instruction in ScanInstruction.allCases {
            let m = ScanCoach.message(instruction: instruction, tracking: .none, stats: stats)
            XCTAssertFalse(m.text.isEmpty)
            XCTAssertFalse(m.symbol.isEmpty)
            XCTAssertEqual(m.level, instruction == .normal ? .info : .caution)
        }
    }

    func testProgressHintFollowsTheWallCount() {
        XCTAssertTrue(ScanCoach.progress(LiveScanStats(walls: 0)).text.hasPrefix("Point at a wall"))
        XCTAssertEqual(ScanCoach.progress(LiveScanStats(walls: 2)).text, "Move slowly along the walls")
        XCTAssertEqual(ScanCoach.progress(LiveScanStats(walls: 3)).text, "Go all the way round, then tap Finish room")
    }

    func testEveryCoachingLineIsSentenceCaseWithoutJargon() {
        let stats = LiveScanStats(walls: 3)
        for instruction in ScanInstruction.allCases {
            for issue in ScanTrackingIssue.allCases {
                let text = ScanCoach.message(instruction: instruction, tracking: issue, stats: stats).text
                XCTAssertTrue(text.first?.isUppercase == true, text)
                // The app also runs on iPad, so no line names the phone.
                for banned in ["LiDAR", "relocalis", "AR session", "error", "phone", "iPhone"] {
                    XCTAssertFalse(text.contains(banned), text)
                }
            }
        }
    }

    // RoomPlan's own capture view prints RoomPlan's instructions, so our pill must not repeat them.

    func testCompanionMessageNeverRepeatsRoomPlansInstructions() {
        // `slowDown` is left out: its words ("Move slowly along the walls") are also the general progress hint.
        let instructionTexts = Set(ScanInstruction.allCases.compactMap { instruction -> String? in
            instruction == .normal || instruction == .slowDown ? nil
                : ScanCoach.message(instruction: instruction, tracking: .none, stats: LiveScanStats(walls: 3)).text
        })
        XCTAssertEqual(instructionTexts.count, 4)
        for walls in [0, 1, 2, 3, 6] {
            let stats = LiveScanStats(walls: walls)
            for issue in ScanTrackingIssue.allCases {
                let m = ScanCoach.companionMessage(tracking: issue, stats: stats)
                XCTAssertFalse(instructionTexts.contains(m.text), "\(issue) \(walls): \(m.text)")
                XCTAssertFalse(m.text.isEmpty)
                XCTAssertFalse(m.symbol.isEmpty)
            }
        }
    }

    func testCompanionMessageKeepsTrackingLossAndOtherwiseGivesTheNextStep() {
        let stats = LiveScanStats(walls: 4)
        for issue in [ScanTrackingIssue.interrupted, .relocalizing, .notAvailable] {
            XCTAssertEqual(ScanCoach.companionMessage(tracking: issue, stats: stats),
                           ScanCoach.message(instruction: .normal, tracking: issue, stats: stats), "\(issue)")
            XCTAssertEqual(ScanCoach.companionMessage(tracking: issue, stats: stats).level, .critical, "\(issue)")
        }
        for issue in [ScanTrackingIssue.none, .initializing, .excessiveMotion, .insufficientFeatures] {
            let m = ScanCoach.companionMessage(tracking: issue, stats: stats)
            XCTAssertEqual(m, ScanCoach.progress(stats), "\(issue)")
            XCTAssertEqual(m.level, .info, "\(issue): trouble that RoomPlan words itself is left to RoomPlan")
        }
    }

    func testReadyToFinishHintDoesNotUseACheckMark() {
        // A check mark means "verified with a laser" in this app; a hint to finish a scan must not borrow it.
        for walls in 0...6 {
            XCTAssertFalse(ScanCoach.progress(LiveScanStats(walls: walls)).symbol.contains("checkmark"), "\(walls)")
        }
    }

    func testAnnouncerSpeaksTroubleOnceAndNotTooOften() {
        var a = ScanCoach.Announcer(minimumInterval: 4)
        let calm = ScanCoachMessage(text: "Fine", symbol: "x", level: .info)
        let light = ScanCoachMessage(text: "Turn on a light", symbol: "x", level: .caution)
        let slow = ScanCoachMessage(text: "Slow down", symbol: "x", level: .caution)
        XCTAssertFalse(a.shouldAnnounce(calm, at: 0))
        XCTAssertTrue(a.shouldAnnounce(light, at: 1))
        XCTAssertFalse(a.shouldAnnounce(light, at: 20), "same words are not repeated")
        XCTAssertFalse(a.shouldAnnounce(slow, at: 3), "too soon after the last one")
        XCTAssertTrue(a.shouldAnnounce(slow, at: 6))
        XCTAssertFalse(a.shouldAnnounce(calm, at: 7))
        XCTAssertTrue(a.shouldAnnounce(slow, at: 30), "trouble that comes back is announced again")
    }

    // MARK: Throttle

    func testThrottleStartsAtMostEveryHalfSecond() {
        var t = LiveRebuildThrottle(minInterval: 0.5)
        XCTAssertEqual(t.next(now: 0), .none, "nothing to build yet")
        t.markDirty()
        XCTAssertEqual(t.next(now: 10), .start)
        XCTAssertEqual(t.next(now: 10.1), .none, "one at a time")
        t.markDirty()
        XCTAssertEqual(t.next(now: 10.1), .none, "still running")
        t.finished()
        guard case .wait(let delay) = t.next(now: 10.2) else { return XCTFail("expected a wait") }
        XCTAssertEqual(delay, 0.3, accuracy: 1e-9)
        XCTAssertEqual(t.next(now: 10.5), .start, "the change that arrived meanwhile is built")
        t.finished()
        XCTAssertEqual(t.next(now: 11), .none, "nothing new")
    }

    func testThrottleResetForgetsPendingWork() {
        var t = LiveRebuildThrottle()
        t.markDirty()
        XCTAssertEqual(t.next(now: 1), .start)
        t.reset()
        XCTAssertEqual(t.next(now: 1.1), .none)
        t.markDirty()
        XCTAssertEqual(t.next(now: 1.1), .start, "reset also forgets the last start time")
    }

    // MARK: Merge steps and failures

    func testMergeSteps() {
        XCTAssertEqual(ScanMergeStep.headline, "Building the 3D model")
        XCTAssertEqual(ScanMergeStep.allCases.map(\.fraction), [0, 1.0 / 3, 2.0 / 3])
        XCTAssertEqual(ScanMergeStep.writingModel.position, "Step 2 of 3")
        XCTAssertEqual(ScanMergeStep.allCases.map(\.title), ["Joining the rooms", "Writing the 3D file", "Saving the AR map"])
    }

    func testEveryFailureHasPlainWords() {
        let all: [ScanFailure] = [.deviceNotSupported, .deviceTooHot, .sceneTooLarge, .trackingFailed, .notEnoughScanned,
                                  .invalidScanData, .roomsNotConnected, .exportFailed, .mergeTooLarge, .cameraUnavailable,
                                  .cameraNotAllowed, .internalError, .unknown]
        for failure in all {
            for rooms in [false, true] {
                let t = failure.text(hasFinishedRooms: rooms)
                XCTAssertFalse(t.title.isEmpty)
                XCTAssertTrue(t.message.hasSuffix("."), "\(failure) \(t.message)")
                XCTAssertTrue(t.recovery.hasSuffix("."), "\(failure) \(t.recovery)")
                XCTAssertFalse(t.title.hasSuffix("."))
                if !rooms { XCTAssertFalse(t.recovery.contains("finished rooms are safe"), "\(failure)") }
            }
        }
        XCTAssertTrue(ScanFailure.deviceTooHot.text(hasFinishedRooms: true).recovery.contains("Your finished rooms are safe."))
        XCTAssertTrue(ScanFailure.sceneTooLarge.mayKeepPartialRoom)
        XCTAssertFalse(ScanFailure.invalidScanData.mayKeepPartialRoom)
        XCTAssertFalse(ScanFailure.mergeTooLarge.mayKeepPartialRoom)
    }

    func testFailureWordsDoNotNameTheIPhoneOnAnIPad() {
        let all: [ScanFailure] = [.deviceNotSupported, .deviceTooHot, .sceneTooLarge, .trackingFailed, .notEnoughScanned,
                                  .invalidScanData, .roomsNotConnected, .exportFailed, .mergeTooLarge, .cameraUnavailable,
                                  .cameraNotAllowed, .internalError, .unknown]
        for failure in all {
            let t = failure.text(hasFinishedRooms: true)
            for part in [t.title, t.message, t.recovery] {
                XCTAssertFalse(part.contains("The iPhone"), "\(failure): \(part)")
                XCTAssertFalse(part.contains("this iPhone"), "\(failure): \(part)")
            }
        }
        XCTAssertEqual(ScanFailure.deviceTooHot.text(hasFinishedRooms: false).title, "The device is too hot")
    }

    // MARK: Failures while joining the rooms

    func testMergeTimeFailuresNeverGiveScanTimeAdvice() {
        let all: [ScanFailure] = [.deviceNotSupported, .deviceTooHot, .sceneTooLarge, .trackingFailed, .notEnoughScanned,
                                  .invalidScanData, .roomsNotConnected, .exportFailed, .mergeTooLarge, .cameraUnavailable,
                                  .cameraNotAllowed, .internalError, .unknown]
        // Advice that only makes sense while the camera is still scanning a room.
        let scanTimeAdvice = ["Walk slowly", "Finish this room", "tap Finish room", "scan the room again", "Scan the room again",
                              "Try scanning", "Try again", "Let it cool", "Go back to the doorway", "Close other apps"]
        for failure in all {
            let warning = failure.mergeWarning
            XCTAssertTrue(warning.hasSuffix("."), warning)
            XCTAssertTrue(warning.first?.isUppercase == true, warning)
            for advice in scanTimeAdvice {
                XCTAssertFalse(warning.contains(advice), "\(failure): \(warning)")
            }
            // The one thing a person needs to know: the rooms and measurements are still there.
            XCTAssertTrue(warning.contains("saved"), "\(failure): \(warning)")
        }
    }

    func testMergeTimeMappingKeepsWhatIsAlreadyAboutMerging() {
        XCTAssertEqual(ScanFailure.roomsNotConnected.duringMerge, .roomsNotConnected)
        XCTAssertEqual(ScanFailure.exportFailed.duringMerge, .exportFailed)
        XCTAssertEqual(ScanFailure.mergeTooLarge.duringMerge, .mergeTooLarge)
        // A floor that is too big for RoomPlan is the realistic one.
        XCTAssertEqual(ScanFailure.sceneTooLarge.duringMerge, .mergeTooLarge)
        for scanTime in [ScanFailure.notEnoughScanned, .invalidScanData, .internalError, .unknown, .deviceTooHot, .trackingFailed] {
            XCTAssertEqual(scanTime.duringMerge, .exportFailed, "\(scanTime)")
        }
        XCTAssertEqual(ScanFailure.sceneTooLarge.mergeWarning,
                       "The floor is too big to join. Your rooms and measurements are saved without a joined model.")
        XCTAssertEqual(ScanFailure.notEnoughScanned.mergeWarning,
                       "Couldn\u{2019}t write the 3D model. Your rooms and measurements are saved without it.")
        // Mapping twice changes nothing.
        for failure in [ScanFailure.sceneTooLarge, .notEnoughScanned, .roomsNotConnected] {
            XCTAssertEqual(failure.duringMerge.duringMerge, failure.duringMerge)
        }
    }
}
