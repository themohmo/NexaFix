import XCTest
@testable import NexaFixCore

/// Tests for turning a finished scan into a saved property: one new floor per session, unique names,
/// the files to write first, and idempotence.
final class ScanCommitTests: XCTestCase {

    // MARK: Fixtures

    private func id(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-" + padded) ?? UUID()
    }

    private let day1 = Date(timeIntervalSince1970: 1_791_360_900)
    private let day2 = Date(timeIntervalSince1970: 1_791_536_400)

    private func room(_ n: Int, _ name: String, kind: RoomKind = .other, width: Double = 4, depth: Double = 3) -> Room {
        Room.rectangle(name: name, kind: kind, width: width, depth: depth, id: id(n))
    }

    private func scan3() -> [Room] {
        [room(1, "Living Room", kind: .livingRoom), room(2, "Kitchen", kind: .kitchen), room(3, "Bedroom", kind: .bedroom)]
    }

    private func empty() -> Property { Property(name: "Marina", floors: []) }

    // MARK: Basics

    func testAddsOneNewFloorNamedAfterTheStory() {
        let plan = ScanCommit.apply(rooms: scan3(), story: 23, scannedAt: day1, to: empty(), makeID: { self.id(900) })
        XCTAssertFalse(plan.isNoOp)
        XCTAssertEqual(plan.floorID, id(900))
        XCTAssertEqual(plan.property.floors.count, 1)
        let floor = plan.property.floors[0]
        XCTAssertEqual(floor.id, id(900))
        XCTAssertEqual(floor.name, "Level 23")
        XCTAssertEqual(floor.level, 23)
        XCTAssertEqual(floor.rooms.map(\.name), ["Living Room", "Kitchen", "Bedroom"])
        XCTAssertEqual(floor.rooms.map(\.id), [id(1), id(2), id(3)], "scan order and ids are kept")
        XCTAssertEqual(plan.addedRoomIDs, [id(1), id(2), id(3)])
        XCTAssertEqual(plan.property.updatedAt, day1)
        XCTAssertEqual(plan.summary, "Added 3 rooms to Level 23.")
        XCTAssertTrue(plan.renames.isEmpty)
        XCTAssertTrue(plan.skippedRoomIDs.isEmpty)
    }

    func testSingularSummary() {
        let plan = ScanCommit.apply(rooms: [room(1, "Hall")], story: 0, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.summary, "Added 1 room to Level 0.")
    }

    func testRoomsKeepTheirOwnScanTimeAndContent() {
        var r = room(1, "Hall")
        r.scannedAt = day2
        r.notes = "check the skirting"
        r.walls[0].length.verify(4.01, date: day2)
        let plan = ScanCommit.apply(rooms: [r], story: 1, scannedAt: day1, to: empty())
        let saved = plan.property.floors[0].rooms[0]
        XCTAssertEqual(saved, r)
        XCTAssertEqual(saved.scannedAt, day2)
    }

    func testInputPropertyIsNotChanged() {
        let original = empty()
        _ = ScanCommit.apply(rooms: scan3(), story: 2, scannedAt: day1, to: original)
        XCTAssertTrue(original.floors.isEmpty)
    }

    func testOtherPropertyFieldsAreKept() {
        var p = empty()
        p.client = "Mr. Khan"
        p.address = "Marina Gate 2"
        p.reference = "NF-2026-1009-01"
        p.notes = "keys with security"
        let plan = ScanCommit.apply(rooms: scan3(), story: 4, scannedAt: day1, to: p)
        XCTAssertEqual(plan.property.id, p.id)
        XCTAssertEqual(plan.property.client, "Mr. Khan")
        XCTAssertEqual(plan.property.address, "Marina Gate 2")
        XCTAssertEqual(plan.property.reference, "NF-2026-1009-01")
        XCTAssertEqual(plan.property.notes, "keys with security")
        XCTAssertEqual(plan.property.createdAt, p.createdAt)
    }

    // MARK: Floors

    func testEveryScanSessionBecomesItsOwnFloor() {
        let first = ScanCommit.apply(rooms: scan3(), story: 23, scannedAt: day1, to: empty())
        let second = ScanCommit.apply(rooms: [room(10, "Study"), room(11, "Balcony", kind: .balcony)], story: 23,
                                      scannedAt: day2, to: first.property)
        XCTAssertEqual(second.property.floors.count, 2)
        XCTAssertEqual(second.property.floors[0], first.property.floors[0], "the first floor is untouched")
        XCTAssertEqual(second.property.floors[1].rooms.map(\.name), ["Study", "Balcony"])
        XCTAssertEqual(second.property.roomCount, 5)
        XCTAssertNotEqual(second.property.floors[0].id, second.property.floors[1].id)
    }

    func testFloorNamesAreDisambiguated() {
        var property = empty()
        var names: [String] = []
        for n in 0..<4 {
            let plan = ScanCommit.apply(rooms: [room(100 + n, "Room \(n)")], story: 23, scannedAt: day1, to: property)
            property = plan.property
            names.append(property.floors.last?.name ?? "")
        }
        XCTAssertEqual(names, ["Level 23", "Level 23 (2)", "Level 23 (3)", "Level 23 (4)"])
    }

    func testAnotherLevelDoesNotCollide() {
        let first = ScanCommit.apply(rooms: [room(1, "A")], story: 23, scannedAt: day1, to: empty())
        let second = ScanCommit.apply(rooms: [room(2, "B")], story: 24, scannedAt: day1, to: first.property)
        XCTAssertEqual(second.property.floors.map(\.name), ["Level 23", "Level 24"])
        XCTAssertEqual(second.property.floors.map(\.level), [23, 24])
    }

    func testGroundAndBasementLevels() {
        let ground = ScanCommit.apply(rooms: [room(1, "A")], story: 0, scannedAt: day1, to: empty())
        let basement = ScanCommit.apply(rooms: [room(2, "B")], story: -1, scannedAt: day1, to: ground.property)
        XCTAssertEqual(basement.property.floors.map(\.name), ["Level 0", "Level -1"])
        XCTAssertEqual(basement.property.floors.map(\.level), [0, -1])
    }

    func testFloorNameClashIgnoresCaseAndSpaces() {
        var p = empty()
        p.floors = [Floor(name: "  level  23 ", level: 23, rooms: [room(1, "A")])]
        let plan = ScanCommit.apply(rooms: [room(2, "B")], story: 23, scannedAt: day1, to: p)
        XCTAssertEqual(plan.property.floors.last?.name, "Level 23 (2)")
    }

    func testUniqueFloorName() {
        XCTAssertEqual(ScanCommit.uniqueFloorName(base: "Level 1", existing: []), "Level 1")
        XCTAssertEqual(ScanCommit.uniqueFloorName(base: "Level 1", existing: ["Level 2"]), "Level 1")
        XCTAssertEqual(ScanCommit.uniqueFloorName(base: "Level 1", existing: ["Level 1"]), "Level 1 (2)")
        XCTAssertEqual(ScanCommit.uniqueFloorName(base: "Level 1", existing: ["Level 1", "Level 1 (2)"]), "Level 1 (3)")
        XCTAssertEqual(ScanCommit.uniqueFloorName(base: "Level 1", existing: ["Level 1", "Level 1 (3)"]), "Level 1 (2)")
    }

    func testEmptyStarterFloorIsReplaced() {
        // What a brand-new property holds before its first scan.
        var p = empty()
        p.floors = [Floor(name: "Main level", level: 0)]
        let plan = ScanCommit.apply(rooms: scan3(), story: 23, scannedAt: day1, to: p)
        XCTAssertEqual(plan.property.floors.map(\.name), ["Level 23"])
    }

    func testEmptyFloorWithFilesIsKept() {
        var p = empty()
        p.floors = [Floor(name: "Level 5", level: 5, rooms: [],
                          assets: FloorAssets(structureUSDZ: "floors/x/model.usdz"))]
        let plan = ScanCommit.apply(rooms: [room(1, "A")], story: 5, scannedAt: day1, to: p)
        XCTAssertEqual(plan.property.floors.map(\.name), ["Level 5", "Level 5 (2)"])
    }

    func testFloorsWithRoomsAreNeverRemoved() {
        let first = ScanCommit.apply(rooms: scan3(), story: 1, scannedAt: day1, to: empty())
        let second = ScanCommit.apply(rooms: [room(20, "X")], story: 2, scannedAt: day1, to: first.property)
        XCTAssertEqual(second.property.floors.count, 2)
    }

    // MARK: Room names

    func testDuplicateNamesInOneScanAreNumbered() {
        let rooms = [room(1, "Bedroom"), room(2, "Bedroom"), room(3, "bedroom "), room(4, "Bedroom 2")]
        let plan = ScanCommit.apply(rooms: rooms, story: 3, scannedAt: day1, to: empty())
        // A numbered name keeps the casing the person typed.
        XCTAssertEqual(plan.property.floors[0].rooms.map(\.name), ["Bedroom", "Bedroom 2", "bedroom 3", "Bedroom 4"])
        XCTAssertEqual(plan.renames, [ScanCommit.Rename(original: "Bedroom", final: "Bedroom 2"),
                                      ScanCommit.Rename(original: "bedroom", final: "bedroom 3"),
                                      ScanCommit.Rename(original: "Bedroom 2", final: "Bedroom 4")])
        XCTAssertEqual(plan.property.roomCount, 4, "no room is lost")
        XCTAssertEqual(plan.summary, "Added 4 rooms to Level 3. 3 rooms were renamed because their names were taken.")
    }

    func testOneRenameIsNamedInTheSummary() {
        let plan = ScanCommit.apply(rooms: [room(1, "Kitchen"), room(2, "Kitchen")], story: 1, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.summary,
                       "Added 2 rooms to Level 1. \u{201C}Kitchen\u{201D} became \u{201C}Kitchen 2\u{201D} because that name was taken.")
    }

    func testBlankNamesTakeTheirKindsName() {
        let rooms = [room(1, "", kind: .kitchen), room(2, "   ", kind: .kitchen), room(3, "", kind: .other)]
        let plan = ScanCommit.apply(rooms: rooms, story: 1, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.property.floors[0].rooms.map(\.name), ["Kitchen", "Kitchen 2", "Room"])
        XCTAssertTrue(plan.renames.isEmpty, "a name that was never typed is not a rename")
    }

    func testSpacingInNamesIsTidiedWithoutCountingAsARename() {
        let plan = ScanCommit.apply(rooms: [room(1, "  Master   Bedroom ")], story: 1, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.property.floors[0].rooms[0].name, "Master Bedroom")
        XCTAssertTrue(plan.renames.isEmpty)
    }

    func testNamesAreOnlyUniqueWithinTheirFloor() {
        let first = ScanCommit.apply(rooms: [room(1, "Living Room"), room(2, "Bedroom")], story: 1, scannedAt: day1,
                                     to: empty())
        let second = ScanCommit.apply(rooms: [room(3, "Living Room"), room(4, "Bedroom")], story: 2, scannedAt: day1,
                                      to: first.property)
        XCTAssertEqual(second.property.floors[1].rooms.map(\.name), ["Living Room", "Bedroom"])
        XCTAssertTrue(second.renames.isEmpty)
    }

    func testAccentsAndCaseCountAsTheSameName() {
        let plan = ScanCommit.apply(rooms: [room(1, "Café"), room(2, "CAFE")], story: 1, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.property.floors[0].rooms.map(\.name), ["Café", "CAFE 2"])
    }

    func testManyRoomsWithTheSameNameAreAllKept() {
        let rooms = (0..<30).map { room(200 + $0, "Bedroom") }
        let plan = ScanCommit.apply(rooms: rooms, story: 1, scannedAt: day1, to: empty())
        let names = plan.property.floors[0].rooms.map(\.name)
        XCTAssertEqual(names.count, 30)
        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, 30, "every name is different")
        XCTAssertEqual(names.first, "Bedroom")
        XCTAssertEqual(names.last, "Bedroom 30")
    }

    func testRoomsWithoutGeometryAreStillKept() {
        let hollow = Room(id: id(7), name: "Odd", walls: [], ceilingHeight: Measured(scanned: 2.8))
        let plan = ScanCommit.apply(rooms: [hollow], story: 1, scannedAt: day1, to: empty())
        XCTAssertEqual(plan.property.roomCount, 1)
    }

    // MARK: Assets

    func testAssetPathsAndOrder() {
        let rooms = scan3()
        let available = ScanCommit.AvailableAssets(structureUSDZ: true, worldMap: true,
                                                   capturedRoomIDs: [id(1), id(3)])
        let plan = ScanCommit.apply(rooms: rooms, story: 23, scannedAt: day1, to: empty(), available: available,
                                    makeID: { self.id(900) })
        let floorID = id(900).uuidString
        XCTAssertEqual(plan.assets.map(\.relativePath), [
            "floors/\(floorID)/model.usdz",
            "floors/\(floorID)/world.map",
            "rooms/\(id(1).uuidString).roomplan.json",
            "rooms/\(id(3).uuidString).roomplan.json",
        ])
        XCTAssertEqual(plan.assets.map(\.kind), [
            .structureUSDZ(floorID: id(900)), .worldMap(floorID: id(900)),
            .capturedRoom(roomID: id(1)), .capturedRoom(roomID: id(3)),
        ])
        let floor = plan.property.floors[0]
        XCTAssertEqual(floor.assets.structureUSDZ, "floors/\(floorID)/model.usdz")
        XCTAssertEqual(floor.assets.worldMap, "floors/\(floorID)/world.map")
        XCTAssertEqual(floor.rooms[0].capturedRoomFile, "rooms/\(id(1).uuidString).roomplan.json")
        XCTAssertNil(floor.rooms[1].capturedRoomFile, "no capture file, no path")
        XCTAssertEqual(floor.rooms[2].capturedRoomFile, "rooms/\(id(3).uuidString).roomplan.json")
    }

    func testNoFilesNoPaths() {
        let plan = ScanCommit.apply(rooms: scan3(), story: 1, scannedAt: day1, to: empty())
        XCTAssertTrue(plan.assets.isEmpty)
        XCTAssertEqual(plan.property.floors[0].assets, FloorAssets())
        XCTAssertTrue(plan.property.floors[0].rooms.allSatisfy { $0.capturedRoomFile == nil })
    }

    func testOnlyTheFilesThatExistAreRecorded() {
        let worldMapOnly = ScanCommit.apply(rooms: scan3(), story: 1, scannedAt: day1, to: empty(),
                                            available: .init(worldMap: true), makeID: { self.id(900) })
        XCTAssertNil(worldMapOnly.property.floors[0].assets.structureUSDZ)
        XCTAssertNotNil(worldMapOnly.property.floors[0].assets.worldMap)
        XCTAssertEqual(worldMapOnly.assets.count, 1)

        let modelOnly = ScanCommit.apply(rooms: scan3(), story: 1, scannedAt: day1, to: empty(),
                                         available: .init(structureUSDZ: true), makeID: { self.id(900) })
        XCTAssertNotNil(modelOnly.property.floors[0].assets.structureUSDZ)
        XCTAssertNil(modelOnly.property.floors[0].assets.worldMap)
    }

    func testCaptureForUnknownRoomIsIgnored() {
        let plan = ScanCommit.apply(rooms: scan3(), story: 1, scannedAt: day1, to: empty(),
                                    available: .init(capturedRoomIDs: [id(99)]))
        XCTAssertTrue(plan.assets.isEmpty)
    }

    func testStaleCapturedRoomPathIsDroppedWhenThereIsNoFile() {
        var r = room(1, "Hall")
        r.capturedRoomFile = "rooms/old.roomplan.json"
        let plan = ScanCommit.apply(rooms: [r], story: 1, scannedAt: day1, to: empty())
        XCTAssertNil(plan.property.floors[0].rooms[0].capturedRoomFile)
    }

    func testPathHelpers() {
        XCTAssertEqual(ScanCommit.structurePath(floorID: id(5)), "floors/00000000-0000-0000-0000-000000000005/model.usdz")
        XCTAssertEqual(ScanCommit.worldMapPath(floorID: id(5)), "floors/00000000-0000-0000-0000-000000000005/world.map")
        XCTAssertEqual(ScanCommit.capturedRoomPath(roomID: id(5)),
                       "rooms/00000000-0000-0000-0000-000000000005.roomplan.json")
    }

    /// The planned files go through the real store: every path is accepted, can be written and read back,
    /// and the saved property still decodes.
    func testPlannedFilesWorkWithThePropertyStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScanCommitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PropertyStore(rootURL: root)

        let property = empty()
        let available = ScanCommit.AvailableAssets(structureUSDZ: true, worldMap: true, capturedRoomIDs: [id(1), id(2), id(3)])
        let plan = ScanCommit.apply(rooms: scan3(), story: 23, scannedAt: day1, to: property, available: available)

        for asset in plan.assets {
            try store.writeAsset(Data(asset.relativePath.utf8), relativePath: asset.relativePath, for: property.id)
        }
        try store.save(plan.property)

        let loaded = try store.load(id: property.id)
        XCTAssertEqual(loaded, plan.property)
        for asset in plan.assets {
            XCTAssertEqual(try store.readAsset(relativePath: asset.relativePath, for: property.id),
                           Data(asset.relativePath.utf8))
        }
        let floor = loaded.floors[0]
        XCTAssertNoThrow(try store.readAsset(relativePath: floor.assets.structureUSDZ ?? "", for: property.id))
        XCTAssertNoThrow(try store.readAsset(relativePath: floor.assets.worldMap ?? "", for: property.id))
        for room in floor.rooms {
            XCTAssertNoThrow(try store.readAsset(relativePath: room.capturedRoomFile ?? "", for: property.id))
        }
    }

    // MARK: Idempotence

    func testApplyingTheSameScanTwiceChangesNothing() {
        let rooms = scan3()
        let available = ScanCommit.AvailableAssets(structureUSDZ: true, worldMap: true, capturedRoomIDs: [id(1)])
        let first = ScanCommit.apply(rooms: rooms, story: 23, scannedAt: day1, to: empty(), available: available)
        let second = ScanCommit.apply(rooms: rooms, story: 23, scannedAt: day2, to: first.property, available: available)

        XCTAssertTrue(second.isNoOp)
        XCTAssertNil(second.floorID)
        XCTAssertEqual(second.property, first.property, "not even updatedAt moves")
        XCTAssertTrue(second.assets.isEmpty, "nothing to write the second time")
        XCTAssertTrue(second.addedRoomIDs.isEmpty)
        XCTAssertEqual(second.skippedRoomIDs, [id(1), id(2), id(3)])
        XCTAssertEqual(second.summary, "These rooms are already saved.")
        XCTAssertEqual(second.property.floors.count, 1)
    }

    func testReapplyingOnANewerCopyGivesTheSameFloor() {
        // The app plans the files first, then applies the same commit to the live property.
        let rooms = scan3()
        let available = ScanCommit.AvailableAssets(structureUSDZ: true, capturedRoomIDs: [id(2)])
        let planned = ScanCommit.apply(rooms: rooms, story: 23, scannedAt: day1, to: empty(), available: available)
        let floorID = planned.floorID ?? UUID()

        var live = empty()
        live.notes = "edited meanwhile"
        let final = ScanCommit.apply(rooms: rooms, story: 23, scannedAt: day1, to: live, available: available,
                                     makeID: { floorID })
        XCTAssertEqual(final.floorID, floorID)
        XCTAssertEqual(final.property.floors, planned.property.floors)
        XCTAssertEqual(final.assets, planned.assets)
        XCTAssertEqual(final.property.notes, "edited meanwhile")
    }

    func testPartlyKnownScanAddsOnlyTheNewRooms() {
        let first = ScanCommit.apply(rooms: [room(1, "Living Room")], story: 1, scannedAt: day1, to: empty())
        let second = ScanCommit.apply(rooms: [room(1, "Living Room"), room(2, "Kitchen")], story: 1, scannedAt: day2,
                                      to: first.property)
        XCTAssertEqual(second.addedRoomIDs, [id(2)])
        XCTAssertEqual(second.skippedRoomIDs, [id(1)])
        XCTAssertEqual(second.property.roomCount, 2)
        XCTAssertEqual(second.property.floors[1].rooms.map(\.name), ["Kitchen"])
        XCTAssertEqual(second.summary, "Added 1 room to Level 1 (2). 1 room was already saved and was skipped.")
    }

    func testRepeatedIDsWithinOneScanAreOneRoom() {
        let plan = ScanCommit.apply(rooms: [room(1, "A"), room(1, "A copy"), room(2, "B")], story: 1,
                                    scannedAt: day1, to: empty())
        XCTAssertEqual(plan.property.floors[0].rooms.map(\.name), ["A", "B"])
        XCTAssertEqual(plan.skippedRoomIDs, [id(1)])
    }

    // MARK: Empty input

    func testEmptyScanChangesNothing() {
        var p = empty()
        p.floors = [Floor(name: "Main level", level: 0)]
        let plan = ScanCommit.apply(rooms: [], story: 5, scannedAt: day1, to: p,
                                    available: .init(structureUSDZ: true, worldMap: true))
        XCTAssertTrue(plan.isNoOp)
        XCTAssertEqual(plan.property, p, "the starter floor stays when nothing is added")
        XCTAssertTrue(plan.assets.isEmpty)
        XCTAssertEqual(plan.summary, "There are no rooms to save.")
        XCTAssertTrue(plan.addedRoomIDs.isEmpty)
        XCTAssertTrue(plan.skippedRoomIDs.isEmpty)
    }

    // MARK: Editing rooms in place

    private func twoFloors() -> Property {
        var p = empty()
        p.floors = [Floor(id: id(500), name: "Level 1", level: 1, rooms: [room(1, "Living Room"), room(2, "Kitchen")]),
                    Floor(id: id(501), name: "Level 2", level: 2, rooms: [room(3, "Bedroom")])]
        return p
    }

    func testRoomLookup() {
        let p = twoFloors()
        XCTAssertEqual(p.roomLocation(of: id(3))?.floor, 1)
        XCTAssertEqual(p.roomLocation(of: id(3))?.room, 0)
        XCTAssertEqual(p.roomLocation(of: id(2))?.floor, 0)
        XCTAssertEqual(p.roomLocation(of: id(2))?.room, 1)
        XCTAssertNil(p.roomLocation(of: id(99)))
        XCTAssertEqual(p.findRoom(id(3))?.name, "Bedroom")
        XCTAssertNil(p.findRoom(id(99)))
        XCTAssertEqual(p.floorHolding(room: id(3))?.name, "Level 2")
        XCTAssertNil(p.floorHolding(room: id(99)))
    }

    func testModifyRoom() {
        var p = twoFloors()
        XCTAssertTrue(p.modifyRoom(id: id(3)) { $0.notes = "north wall damp" })
        XCTAssertEqual(p.findRoom(id(3))?.notes, "north wall damp")
        XCTAssertEqual(p.findRoom(id(1))?.notes, "")
        let before = p
        XCTAssertFalse(p.modifyRoom(id: id(99)) { $0.notes = "x" })
        XCTAssertEqual(p, before)
    }

    func testModifyRoomCanRecordAVerification() {
        var p = twoFloors()
        let wall = p.floors[0].rooms[0].walls[0].id
        let check = Verification(value: 4.012, source: .laser, date: day1, note: nil)
        XCTAssertTrue(p.modifyRoom(id: id(1)) { $0.setVerification(check, for: .wallLength(wall)) })
        XCTAssertEqual(p.floors[0].rooms[0].walls[0].length.verification, check)
        XCTAssertNil(p.floors[0].rooms[1].walls[0].length.verification)
    }

    func testDeleteRoom() {
        var p = twoFloors()
        XCTAssertTrue(p.deleteRoom(id: id(2)))
        XCTAssertEqual(p.floors[0].rooms.map(\.name), ["Living Room"])
        XCTAssertEqual(p.floors.count, 2)
        XCTAssertFalse(p.deleteRoom(id: id(2)))
    }

    func testDeletingTheLastRoomOfAFloorRemovesTheFloor() {
        var p = twoFloors()
        XCTAssertTrue(p.deleteRoom(id: id(3)))
        XCTAssertEqual(p.floors.map(\.name), ["Level 1"])
    }

    func testRenameRoom() {
        var p = twoFloors()
        XCTAssertEqual(p.renameRoom(id: id(1), to: "  Lounge  "), "Lounge")
        XCTAssertEqual(p.findRoom(id(1))?.name, "Lounge")
        // Same floor: Kitchen is taken.
        XCTAssertEqual(p.renameRoom(id: id(1), to: "kitchen"), "kitchen 2")
        // Another floor: no clash.
        XCTAssertEqual(p.renameRoom(id: id(3), to: "Kitchen"), "Kitchen")
        // Its own name is not a clash.
        XCTAssertEqual(p.renameRoom(id: id(2), to: "Kitchen"), "Kitchen")
        // Blank keeps the name.
        XCTAssertEqual(p.renameRoom(id: id(2), to: "   "), "Kitchen")
        XCTAssertNil(p.renameRoom(id: id(99), to: "X"))
    }
}
