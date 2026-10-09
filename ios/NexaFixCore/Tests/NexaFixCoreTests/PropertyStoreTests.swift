import XCTest
import Dispatch
@testable import NexaFixCore

/// Tests for the on-disk property store. Every test works in its own temporary folder.
final class PropertyStoreTests: XCTestCase {

    private var root: URL!
    private var store: PropertyStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexaFixStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = PropertyStore(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func file(_ id: UUID, _ name: String = PropertyStore.propertyFileName) -> URL {
        store.folderURL(for: id).appendingPathComponent(name)
    }

    private func listing(_ id: UUID) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.folderURL(for: id).path).sorted()
    }

    private func garbage(_ id: UUID, _ name: String = PropertyStore.propertyFileName) throws {
        try Data("{ \"schemaVersion\": 1, \"property\": { truncat".utf8).write(to: file(id, name))
    }

    /// A small property: one floor, one rectangular room.
    private func simple(_ name: String = "Villa", id: UUID = UUID(), updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Property {
        let room = Room.rectangle(name: "Majlis", kind: .livingRoom, width: 5, depth: 4,
                                  openings: [.door(wall: 0, offset: 0.5)])
        return Property(id: id, name: name, client: "Client", createdAt: Date(timeIntervalSince1970: 1_690_000_000),
                        updatedAt: updatedAt, floors: [Floor(name: "Ground", rooms: [room])])
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(any as? [String: Any])
    }

    /// Run `body` for each iteration on many threads, collecting error descriptions.
    private func concurrently(_ iterations: Int, _ body: @escaping (Int) throws -> Void) -> [String] {
        let lock = NSLock()
        var failures: [String] = []
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            do { try body(i) } catch {
                lock.lock(); failures.append("#\(i): \(error)"); lock.unlock()
            }
        }
        return failures
    }

    // MARK: Round trip

    func testSaveThenLoadReturnsTheSameProperty() throws {
        let p = DataExportTests.marina()
        try store.save(p)
        XCTAssertEqual(try store.load(id: p.id), p)
        XCTAssertFalse(try store.loadWithStatus(id: p.id).recoveredFromBackup)
        XCTAssertEqual(try store.loadWithStatus(id: p.id).schemaVersionOnDisk, 1)
    }

    func testClockDatesAndAwkwardDoublesSurviveBitForBit() throws {
        // Date() carries sub-microsecond bits; 0.1 + 0.2 and 1/3 are not representable in decimal.
        let a = 0.1 + 0.2
        var room = Room.polygon(name: "Noisy", corners: [Point2(0, 0), Point2(a, 0), Point2(a, 1.0 / 3.0), Point2(0, 1.0 / 3.0)])
        room.scannedAt = Date()
        room.walls[0].length.verify(1.0 / 3.0, source: .laser, note: "n", date: Date())
        room.customMeasurements = [CustomMeasurement(label: "c", a: Point3(0.1, 0.2, 0.3), b: Point3(1.0 / 7.0, 2, 3), createdAt: Date())]
        let p = Property(name: "Exact", createdAt: Date(), updatedAt: Date(), floors: [Floor(name: "F", rooms: [room])])
        try store.save(p)
        let back = try store.load(id: p.id)
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.createdAt.timeIntervalSinceReferenceDate, p.createdAt.timeIntervalSinceReferenceDate)
        XCTAssertEqual(back.floors[0].rooms[0].walls[1].end.x, a)
        XCTAssertEqual(back.floors[0].rooms[0].walls[1].end.y, 1.0 / 3.0)
    }

    func testFractionalSecondDatesAreExactAfterAFileRoundTrip() throws {
        let dates: [Date] = [
            Date(timeIntervalSince1970: 1_700_000_000.123),
            Date(timeIntervalSince1970: 1_700_000_000.5),
            Date(timeIntervalSinceReferenceDate: 123_456_789.987_654_321),
            Date(timeIntervalSinceReferenceDate: 721_692_800 + (1 - 1.0 / 8_388_608)),   // just under a whole second
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: -86_400.25),
            Date(timeIntervalSince1970: 4_133_980_799.999),
            Date(),
        ]
        for date in dates {
            var p = simple()
            p.updatedAt = date
            p.createdAt = date
            try store.save(p)
            let back = try store.load(id: p.id)
            XCTAssertEqual(back.updatedAt.timeIntervalSinceReferenceDate, date.timeIntervalSinceReferenceDate)
            XCTAssertEqual(back, p)
        }
        // On disk they are ISO 8601 strings with a fractional part, not numbers.
        var p = simple()
        p.updatedAt = Date(timeIntervalSince1970: 1_700_000_000.5)
        try store.save(p)
        let property = try XCTUnwrap(try jsonObject(at: file(p.id))["property"] as? [String: Any])
        XCTAssertEqual(property["updatedAt"] as? String, "2023-11-14T22:13:20.500Z")
    }

    func testEnvelopeOnDisk() throws {
        let p = simple()
        try store.save(p)
        let doc = try jsonObject(at: file(p.id))
        XCTAssertEqual(Set(doc.keys), ["schemaVersion", "property"])
        XCTAssertEqual(doc["schemaVersion"] as? Int, 1)
        let property = try XCTUnwrap(doc["property"] as? [String: Any])
        XCTAssertEqual(property["id"] as? String, p.id.uuidString)
        XCTAssertEqual(property["name"] as? String, "Villa")
        let text = try XCTUnwrap(String(data: Data(contentsOf: file(p.id)), encoding: .utf8))
        XCTAssertTrue(text.contains("\n"), "pretty printed")
        XCTAssertFalse(text.contains("\\/"))
        // The folder is named after the id, upper-case.
        XCTAssertEqual(store.folderURL(for: p.id).lastPathComponent, p.id.uuidString)
        XCTAssertEqual(store.folderURL(for: p.id).deletingLastPathComponent().path,
                       root.standardizedFileURL.path)
        // Deterministic bytes: saving the same property twice writes the same file.
        let first = try Data(contentsOf: file(p.id))
        XCTAssertEqual(try PropertyStore.encode(p), first)
    }

    func testUnicodeAndAwkwardTextRoundTrips() throws {
        var p = simple("\u{0641}\u{064A}\u{0644}\u{0627} \u{1F334} \"Palm\" \\ / \n tab\t")
        p.notes = String(repeating: "x", count: 100_000) + "\u{0}\u{1}"
        p.client = "O'Brien & Sons <ltd>"
        try store.save(p)
        XCTAssertEqual(try store.load(id: p.id), p)
    }

    func testNaNAndInfinityDoNotMakeASurveyUnsaveable() throws {
        var p = simple()
        p.floors[0].rooms[0].walls[0].length = Measured(scanned: .nan)
        p.floors[0].rooms[0].ceilingHeight = Measured(scanned: .infinity)
        try store.save(p)             // must not throw
        let back = try store.load(id: p.id)
        XCTAssertTrue(back.floors[0].rooms[0].walls[0].length.scanned.isNaN)
        XCTAssertEqual(back.floors[0].rooms[0].ceilingHeight.scanned, .infinity)
    }

    func testFirstSaveCreatesTheRootFolder() throws {
        let nested = root.appendingPathComponent("a/b/c", isDirectory: true)
        let s = PropertyStore(rootURL: nested)
        let p = simple()
        XCTAssertEqual(try s.list(), [])                     // nothing there yet, and no error
        try s.save(p)
        XCTAssertEqual(try s.load(id: p.id), p)
    }

    // MARK: Saving does not edit

    func testSaveDoesNotTouchUpdatedAtUnlessAskedTo() throws {
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let now = Date(timeIntervalSince1970: 1_791_540_000)
        let p = simple(updatedAt: old)
        let returned = try store.save(p)
        XCTAssertEqual(returned.updatedAt, old)
        XCTAssertEqual(try store.load(id: p.id).updatedAt, old)

        let stamped = try store.save(p, stampUpdatedAt: now)
        XCTAssertEqual(stamped.updatedAt, now)
        XCTAssertEqual(try store.load(id: p.id).updatedAt, now)
        XCTAssertEqual(p.updatedAt, old, "the caller's value is not mutated")
        var expected = p
        expected.updatedAt = now
        XCTAssertEqual(stamped, expected)                    // nothing else changed
    }

    // MARK: Backup

    func testSaveKeepsOnePreviousGoodFileAsBackup() throws {
        var p = simple("v1")
        try store.save(p)
        XCTAssertEqual(try listing(p.id), ["property.json"])        // nothing to back up yet, no temp files left
        p.name = "v2"
        try store.save(p)
        XCTAssertEqual(try listing(p.id), ["property.json", "property.json.bak"])
        XCTAssertEqual(try PropertyStore.decode(Data(contentsOf: file(p.id, "property.json.bak"))).name, "v1")
        XCTAssertEqual(try store.load(id: p.id).name, "v2")
        p.name = "v3"
        try store.save(p)
        XCTAssertEqual(try PropertyStore.decode(Data(contentsOf: file(p.id, "property.json.bak"))).name, "v2")
        XCTAssertEqual(try listing(p.id), ["property.json", "property.json.bak"])
    }

    func testSaveReplacesTheFileInsteadOfRewritingItInPlace() throws {
        // An in-place rewrite truncates the live file first; a replace swaps in a new, complete file.
        // A new file has a new file number (the old one is still alive while the new one is made).
        func fileNumber(_ url: URL) throws -> UInt64? {
            (try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        }
        var p = simple("v1")
        try store.save(p)
        let first = try fileNumber(file(p.id))
        XCTAssertNotNil(first)
        p.name = "v2"
        try store.save(p)
        let second = try fileNumber(file(p.id))
        XCTAssertNotEqual(first, second, "property.json was rewritten in place")
        p.name = "v3"
        try store.save(p)
        XCTAssertNotEqual(second, try fileNumber(file(p.id)))
        // The same holds for assets.
        try store.writeAsset(Data("a".utf8), relativePath: "a.bin", for: p.id)
        let asset = try fileNumber(file(p.id, "a.bin"))
        try store.writeAsset(Data("b".utf8), relativePath: "a.bin", for: p.id)
        XCTAssertNotEqual(asset, try fileNumber(file(p.id, "a.bin")))
    }

    func testResavingIdenticalContentDoesNotPushTheBackupForward() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try store.save(p)
        try store.save(p)
        XCTAssertEqual(try PropertyStore.decode(Data(contentsOf: file(p.id, "property.json.bak"))).name, "v1")
    }

    // MARK: Corruption recovery

    func testDamagedFileFallsBackToTheBackupAndSaysSo() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try garbage(p.id)

        let loaded = try store.loadWithStatus(id: p.id)
        XCTAssertTrue(loaded.recoveredFromBackup)
        XCTAssertEqual(loaded.property.name, "v1")
        XCTAssertNotNil(loaded.recoveryReason)
        XCTAssertTrue(loaded.recoveryReason?.contains("property.json") ?? false)
        XCTAssertEqual(try store.load(id: p.id).name, "v1")

        let summary = try XCTUnwrap(try store.list().first)
        XCTAssertEqual(summary.health, .recoveredFromBackup)
        XCTAssertEqual(summary.name, "v1")
        XCTAssertNotNil(summary.problem)
    }

    func testSavingAfterRecoveryKeepsTheDamagedFileAsideAndTheGoodBackup() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try garbage(p.id)
        let damaged = try Data(contentsOf: file(p.id))

        var recovered = try store.load(id: p.id)
        recovered.name = "v3"
        try store.save(recovered)

        XCTAssertEqual(try Data(contentsOf: file(p.id, "property.json.corrupt")), damaged)
        // The backup is still the last good file from before the damage, not the garbage.
        XCTAssertEqual(try PropertyStore.decode(Data(contentsOf: file(p.id, "property.json.bak"))).name, "v1")
        let reloaded = try store.loadWithStatus(id: p.id)
        XCTAssertFalse(reloaded.recoveredFromBackup)
        XCTAssertEqual(reloaded.property.name, "v3")
    }

    func testBothFilesDamagedIsAnErrorNotASilentLoss() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try garbage(p.id)
        try garbage(p.id, "property.json.bak")
        XCTAssertThrowsError(try store.load(id: p.id)) { error in
            guard case PropertyStoreError.corrupt(let id, let reason) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(id, p.id)
            XCTAssertTrue(reason.contains("property.json.bak"), reason)
        }
        // It still shows up in the list so the user can see something is wrong.
        let rows = try store.list()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, p.id)
        XCTAssertEqual(rows[0].health, .unreadable)
        XCTAssertNotNil(rows[0].problem)
    }

    func testEmptyFileCountsAsDamage() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try Data().write(to: file(p.id))
        XCTAssertEqual(try store.loadWithStatus(id: p.id).property.name, "v1")
        XCTAssertTrue(try store.loadWithStatus(id: p.id).recoveredFromBackup)
    }

    func testMissingFileWithABackupIsRecovered() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try FileManager.default.removeItem(at: file(p.id))
        let loaded = try store.loadWithStatus(id: p.id)
        XCTAssertTrue(loaded.recoveredFromBackup)
        XCTAssertEqual(loaded.property.name, "v1")
    }

    func testDamagedFileWithoutABackupIsAnError() throws {
        let p = simple()
        try store.save(p)
        try garbage(p.id)
        XCTAssertThrowsError(try store.load(id: p.id)) { error in
            guard case PropertyStoreError.corrupt = error else { return XCTFail("\(error)") }
        }
    }

    func testValidJSONOfTheWrongShapeIsDamageToo() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        for bad in ["[]", "42", "null", "{\"schemaVersion\": 1}", "{\"schemaVersion\": 1, \"property\": {\"name\": 7}}",
                    "{\"schemaVersion\": \"one\"}"] {
            try Data(bad.utf8).write(to: file(p.id))
            let loaded = try store.loadWithStatus(id: p.id)
            XCTAssertTrue(loaded.recoveredFromBackup, bad)
            XCTAssertEqual(loaded.property.name, "v1", bad)
        }
    }

    func testAFileThatHoldsAnotherPropertyIsRejected() throws {
        let a = simple("A"), b = simple("B")
        try store.save(a)
        try store.save(b)
        // Somebody copied A's file over B's.
        try Data(contentsOf: file(a.id)).write(to: file(b.id))
        XCTAssertThrowsError(try store.load(id: b.id)) { error in
            guard case PropertyStoreError.corrupt(_, let reason) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.contains(a.id.uuidString), reason)
        }
        XCTAssertEqual(try store.load(id: a.id).name, "A")
    }

    func testUnknownIdsAreNotFound() throws {
        let id = UUID()
        XCTAssertThrowsError(try store.load(id: id)) { XCTAssertEqual($0 as? PropertyStoreError, .notFound(id)) }
        try store.save(simple())
        XCTAssertThrowsError(try store.load(id: id)) { XCTAssertEqual($0 as? PropertyStoreError, .notFound(id)) }
        XCTAssertFalse(try store.delete(id: id))
    }

    // MARK: Schema versions and migrations

    func testUnknownKeysAreIgnored() throws {
        let p = DataExportTests.marina()
        let data = try PropertyStore.encode(p)
        var doc = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        doc["futureTopLevel"] = ["a": 1]
        var property = try XCTUnwrap(doc["property"] as? [String: Any])
        property["futureField"] = "hello"
        var floors = try XCTUnwrap(property["floors"] as? [[String: Any]])
        floors[0]["futureFloorField"] = [1, 2, 3]
        var rooms = try XCTUnwrap(floors[0]["rooms"] as? [[String: Any]])
        rooms[0]["futureRoomField"] = ["nested": ["deep": true]]
        var walls = try XCTUnwrap(rooms[0]["walls"] as? [[String: Any]])
        walls[0]["futureWallField"] = 3.5
        rooms[0]["walls"] = walls
        floors[0]["rooms"] = rooms
        property["floors"] = floors
        doc["property"] = property
        try FileManager.default.createDirectory(at: store.folderURL(for: p.id), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: doc).write(to: file(p.id))
        let loaded = try store.loadWithStatus(id: p.id)
        XCTAssertFalse(loaded.recoveredFromBackup)
        XCTAssertEqual(loaded.property, p)
    }

    func testANewerFileIsNeitherReadNorOverwritten() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)             // so there is a perfectly good backup too
        let newer = Data("{\"schemaVersion\": 99, \"property\": {\"id\": \"\(p.id.uuidString)\", \"futureShape\": true}}".utf8)
        try newer.write(to: file(p.id))

        XCTAssertThrowsError(try store.load(id: p.id)) { error in
            XCTAssertEqual(error as? PropertyStoreError, .unsupportedSchemaVersion(found: 99, supported: 1))
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("newer version") ?? false)
        }
        // Not treated as damage: no silent fall back to the older backup.
        XCTAssertThrowsError(try store.loadWithStatus(id: p.id))
        // Saving must not clobber a file this version cannot read.
        XCTAssertThrowsError(try store.save(p)) { error in
            XCTAssertEqual(error as? PropertyStoreError, .unsupportedSchemaVersion(found: 99, supported: 1))
        }
        XCTAssertEqual(try Data(contentsOf: file(p.id)), newer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(p.id, "property.json.corrupt").path))
        let rows = try store.list()
        XCTAssertEqual(rows.first?.health, .unreadable)
        XCTAssertTrue(rows.first?.problem?.contains("newer version") ?? false)
    }

    func testAFileInAnUnknownOlderFormatIsNotOverwrittenEither() throws {
        let p = simple()
        try FileManager.default.createDirectory(at: store.folderURL(for: p.id), withIntermediateDirectories: true)
        let odd = Data("{\"schemaVersion\": -1, \"keep\": \"me\"}".utf8)
        try odd.write(to: file(p.id))
        XCTAssertThrowsError(try store.save(p)) { XCTAssertEqual($0 as? PropertyStoreError, .missingMigration(from: -1)) }
        XCTAssertEqual(try Data(contentsOf: file(p.id)), odd)
    }

    func testSaveStopsBeforeReplacingTheOnlyGoodCopyWhenTheBackupCannotBeWritten() throws {
        var p = simple("v1")
        try store.save(p)
        // Something that is not a file is sitting where the backup goes.
        let bak = file(p.id, "property.json.bak")
        try FileManager.default.createDirectory(at: bak, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: bak.appendingPathComponent("blocker"))
        p.name = "v2"
        XCTAssertThrowsError(try store.save(p))
        XCTAssertEqual(try PropertyStore.decode(Data(contentsOf: file(p.id))).name, "v1", "the good file is untouched")
    }

    func testBareUnversionedPropertyFilesAreUpgraded() throws {
        let p = DataExportTests.marina()
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: PropertyStore.encode(p)) as? [String: Any])
        let bare = try JSONSerialization.data(withJSONObject: try XCTUnwrap(envelope["property"]))
        try FileManager.default.createDirectory(at: store.folderURL(for: p.id), withIntermediateDirectories: true)
        try bare.write(to: file(p.id))
        let loaded = try store.loadWithStatus(id: p.id)
        XCTAssertEqual(loaded.property, p)
        XCTAssertEqual(loaded.schemaVersionOnDisk, 0)
        XCTAssertTrue(loaded.migrated)
        XCTAssertFalse(loaded.recoveredFromBackup)
        // The next save writes the current envelope and keeps the old file as the backup.
        try store.save(loaded.property)
        XCTAssertEqual(try jsonObject(at: file(p.id))["schemaVersion"] as? Int, 1)
        XCTAssertEqual(try store.loadWithStatus(id: p.id).migrated, false)
        XCTAssertEqual(try Data(contentsOf: file(p.id, "property.json.bak")), bare)
    }

    func testMigrationHookRunsForOldFormats() throws {
        let p = simple("Migrated")
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: PropertyStore.encode(p)) as? [String: Any])
        // An imaginary version 0 layout: {"legacyHome": <property>, "legacyFlag": true}
        let legacy = try JSONSerialization.data(withJSONObject: ["legacyHome": try XCTUnwrap(envelope["property"]), "legacyFlag": true])
        let custom = PropertyStore.Migration(from: 0) { doc in
            guard let home = doc["legacyHome"] else { throw PropertyStoreError.unsafePath("legacyHome missing") }
            doc = ["property": home]            // the store stamps schemaVersion afterwards
        }
        let s = PropertyStore(rootURL: root, migrations: [custom])
        try FileManager.default.createDirectory(at: s.folderURL(for: p.id), withIntermediateDirectories: true)
        try legacy.write(to: s.folderURL(for: p.id).appendingPathComponent("property.json"))
        let loaded = try s.loadWithStatus(id: p.id)
        XCTAssertEqual(loaded.property, p)
        XCTAssertTrue(loaded.migrated)
        // A migration that fails is an error, not a silent empty property.
        let broken = Data("{\"somethingElse\": 1}".utf8)
        try broken.write(to: s.folderURL(for: p.id).appendingPathComponent("property.json"))
        XCTAssertThrowsError(try s.load(id: p.id))
    }

    func testMissingMigrationIsReportedNotGuessed() throws {
        let p = simple()
        try FileManager.default.createDirectory(at: store.folderURL(for: p.id), withIntermediateDirectories: true)
        try Data("{\"schemaVersion\": -1}".utf8).write(to: file(p.id))
        XCTAssertThrowsError(try store.load(id: p.id)) { error in
            XCTAssertEqual(error as? PropertyStoreError, .missingMigration(from: -1))
        }
    }

    // MARK: List

    func testListSummariesAreHandComputed() throws {
        let p = DataExportTests.marina()
        try store.save(p)
        let rows = try store.list()
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.id, p.id)
        XCTAssertEqual(row.name, "Marina Gate 2304")
        XCTAssertEqual(row.client, "Mr. Ahmed Khan")
        XCTAssertEqual(row.kind, .apartment)
        XCTAssertEqual(row.roomCount, 4)
        // 28.08 + 5.04 + 6.4 + 20 (effective areas; see DataExportTests.testSummaryNumbers)
        XCTAssertEqual(row.floorAreaM2, 59.52, accuracy: 1e-9)
        XCTAssertEqual(row.updatedAt, p.updatedAt)
        // 4 of 49 checkable dimensions are verified.
        XCTAssertEqual(row.verifiedFraction, 4.0 / 49.0, accuracy: 1e-12)
        XCTAssertEqual(row.health, .ok)
        XCTAssertNil(row.problem)
    }

    func testListIsSortedNewestFirstWithStableTies() throws {
        let t1 = Date(timeIntervalSince1970: 1_000), t2 = Date(timeIntervalSince1970: 2_000), t3 = Date(timeIntervalSince1970: 3_000)
        let oldest = simple("Oldest", updatedAt: t1)
        let newest = simple("Newest", updatedAt: t3)
        let tieB = simple("beta", updatedAt: t2)
        let tieA = simple("Alpha", updatedAt: t2)
        for p in [oldest, tieB, newest, tieA] { try store.save(p) }
        let names = try store.list().map(\.name)
        XCTAssertEqual(names, ["Newest", "Alpha", "beta", "Oldest"])
        XCTAssertEqual(try store.list().map(\.name), names, "same order every time")
    }

    func testListIgnoresFoldersThatAreNotProperties() throws {
        let p = simple()
        try store.save(p)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".DS_Store"))
        // A UUID-named folder with only assets (written before the first save).
        let assetsOnly = UUID()
        try store.writeAsset(Data([1, 2, 3]), relativePath: "scan.usdz", for: assetsOnly)
        // A file that merely has a UUID for a name.
        try Data().write(to: root.appendingPathComponent(UUID().uuidString))
        // A leftover staging folder from an interrupted duplicate.
        try fm.createDirectory(at: root.appendingPathComponent(".duplicating-\(UUID().uuidString)"), withIntermediateDirectories: true)
        XCTAssertEqual(try store.list().map(\.id), [p.id])
    }

    // MARK: Delete

    func testDeleteRemovesThePropertyAndItsAssets() throws {
        let p = simple(), other = simple("Other")
        try store.save(p)
        try store.save(other)
        try store.writeAsset(Data("usdz".utf8), relativePath: "floors/level0.usdz", for: p.id)
        XCTAssertTrue(try store.delete(id: p.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folderURL(for: p.id).path))
        XCTAssertThrowsError(try store.load(id: p.id))
        XCTAssertEqual(try store.list().map(\.id), [other.id])
        XCTAssertEqual(try store.load(id: other.id).name, "Other")
        XCTAssertFalse(try store.delete(id: p.id))
    }

    // MARK: Paths

    func testResolveAcceptsPlainRelativePaths() throws {
        let p = simple()
        try store.save(p)
        let folder = store.folderURL(for: p.id).standardizedFileURL.path
        for good in ["rooms/capture.json", "a.usdz", "deep/er/still/file.bin", "name with spaces.png", "rooms//double.json",
                     "trailing/", "unicode/\u{0641}\u{064A}\u{0644}\u{0627}.json", "..hidden", "a..b", "...", ".gitignore"] {
            let url = try store.resolve(relativePath: good, in: p.id)
            XCTAssertTrue(url.path.hasPrefix(folder + "/"), "\(good) -> \(url.path)")
        }
        XCTAssertEqual(try store.resolve(relativePath: "rooms/capture.json", in: p.id).path, folder + "/rooms/capture.json")
        XCTAssertEqual(try store.resolve(relativePath: "rooms//capture.json", in: p.id).path, folder + "/rooms/capture.json")
    }

    func testResolveRejectsTraversalAndAbsolutePaths() throws {
        let p = simple()
        try store.save(p)
        let bad = ["", "/", "/etc/passwd", "//etc/passwd", "../x", "..", "a/../../x", "a/..", "a/../b", "./x", "a/./b", "a/.",
                   ".", "~", "~/x", "a\\b", "..\\x", "x\u{0}y", "x\ny", "x\u{7F}", "../" + p.id.uuidString + "/property.json",
                   "a/b/../../../outside"]
        for path in bad {
            XCTAssertThrowsError(try store.resolve(relativePath: path, in: p.id), "should reject \(path.debugDescription)") { error in
                XCTAssertEqual(error as? PropertyStoreError, .unsafePath(path))
            }
        }
        // The static form checks any folder.
        XCTAssertThrowsError(try PropertyStore.resolve(relativePath: "../x", in: root))
        XCTAssertNoThrow(try PropertyStore.resolve(relativePath: "x", in: root))
    }

    func testResolveRejectsSymlinksThatLeaveTheFolder() throws {
        let p = simple()
        try store.save(p)
        let fm = FileManager.default
        let folder = store.folderURL(for: p.id)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let secret = outside.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)

        // A folder link, a file link and a dangling link, all pointing out.
        try fm.createSymbolicLink(at: folder.appendingPathComponent("escape"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("leak.txt"), withDestinationURL: secret)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("dangling"),
                                  withDestinationURL: outside.appendingPathComponent("not-yet.txt"))
        for path in ["escape", "escape/secret.txt", "escape/new/deeper.txt", "leak.txt", "dangling", "escape/../secret.txt"] {
            XCTAssertThrowsError(try store.resolve(relativePath: path, in: p.id), path)
        }
        XCTAssertThrowsError(try store.readAsset(relativePath: "leak.txt", for: p.id))
        XCTAssertThrowsError(try store.readAsset(relativePath: "escape/secret.txt", for: p.id))
        XCTAssertThrowsError(try store.writeAsset(Data("pwned".utf8), relativePath: "leak.txt", for: p.id))
        XCTAssertThrowsError(try store.writeAsset(Data("pwned".utf8), relativePath: "escape/new.txt", for: p.id))
        XCTAssertThrowsError(try store.writeAsset(Data("pwned".utf8), relativePath: "dangling", for: p.id))
        XCTAssertEqual(try Data(contentsOf: secret), Data("secret".utf8), "nothing was written through a link")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), ["secret.txt"])

        // A link that stays inside the folder is fine.
        try fm.createDirectory(at: folder.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("alias"),
                                  withDestinationURL: folder.appendingPathComponent("inner"))
        XCTAssertNoThrow(try store.resolve(relativePath: "alias/x.json", in: p.id))
        try store.writeAsset(Data("ok".utf8), relativePath: "alias/x.json", for: p.id)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("inner/x.json")), Data("ok".utf8))
    }

    func testResolveWorksBeforeTheFolderExists() throws {
        let id = UUID()
        let url = try store.resolve(relativePath: "rooms/x.json", in: id)
        XCTAssertTrue(url.path.hasSuffix("/\(id.uuidString)/rooms/x.json"))
        XCTAssertThrowsError(try store.resolve(relativePath: "../x", in: id))
    }

    // MARK: Assets

    func testWriteAndReadAssets() throws {
        let p = simple()
        try store.save(p)
        let bytes = Data((0..<255).map { UInt8($0) })
        try store.writeAsset(bytes, relativePath: "rooms/ABC/capture.json", for: p.id)
        XCTAssertEqual(try store.readAsset(relativePath: "rooms/ABC/capture.json", for: p.id), bytes)
        XCTAssertEqual(try Data(contentsOf: store.folderURL(for: p.id).appendingPathComponent("rooms/ABC/capture.json")), bytes)
        // Overwrite is allowed and atomic.
        try store.writeAsset(Data("new".utf8), relativePath: "rooms/ABC/capture.json", for: p.id)
        XCTAssertEqual(try store.readAsset(relativePath: "rooms/ABC/capture.json", for: p.id), Data("new".utf8))
        // The property itself is untouched by asset writes.
        XCTAssertEqual(try store.load(id: p.id), p)
        XCTAssertEqual(try listing(p.id), ["property.json", "rooms"])
        // Empty data is a legitimate file.
        try store.writeAsset(Data(), relativePath: "empty.bin", for: p.id)
        XCTAssertEqual(try store.readAsset(relativePath: "empty.bin", for: p.id), Data())
        XCTAssertThrowsError(try store.readAsset(relativePath: "missing.bin", for: p.id))
    }

    func testAssetsCannotOverwriteTheStoresOwnFiles() throws {
        let p = simple()
        try store.save(p)
        let before = try Data(contentsOf: file(p.id))
        for name in ["property.json", "PROPERTY.JSON", "property.json.bak", "Property.Json.Corrupt", "property.json/"] {
            XCTAssertThrowsError(try store.writeAsset(Data("x".utf8), relativePath: name, for: p.id), name) { error in
                XCTAssertEqual(error as? PropertyStoreError, .reservedPath(name))
            }
        }
        XCTAssertEqual(try Data(contentsOf: file(p.id)), before)
        // A file with that name deeper down is just a file.
        XCTAssertNoThrow(try store.writeAsset(Data("x".utf8), relativePath: "sub/property.json", for: p.id))
        XCTAssertEqual(try store.load(id: p.id), p)
    }

    func testAssetWriteRefusesDirectoriesAndFileParents() throws {
        let p = simple()
        try store.save(p)
        try store.writeAsset(Data("a".utf8), relativePath: "dir/file.bin", for: p.id)
        XCTAssertThrowsError(try store.writeAsset(Data("b".utf8), relativePath: "dir", for: p.id)) { error in
            XCTAssertEqual(error as? PropertyStoreError, .invalidAssetTarget("dir"))
        }
        XCTAssertThrowsError(try store.writeAsset(Data("b".utf8), relativePath: "dir/file.bin/child", for: p.id)) { error in
            XCTAssertEqual(error as? PropertyStoreError, .invalidAssetTarget("dir/file.bin/child"))
        }
        XCTAssertEqual(try store.readAsset(relativePath: "dir/file.bin", for: p.id), Data("a".utf8))
        XCTAssertThrowsError(try store.writeAsset(Data("b".utf8), relativePath: "../escape.bin", for: p.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.bin").path))
    }

    func testAssetsMayBeWrittenBeforeTheFirstSave() throws {
        let p = simple()
        try store.writeAsset(Data("usdz".utf8), relativePath: "floors/ground.usdz", for: p.id)
        XCTAssertEqual(try store.list(), [], "a folder with only assets is not a property yet")
        try store.save(p)
        XCTAssertEqual(try store.list().map(\.id), [p.id])
        XCTAssertEqual(try store.readAsset(relativePath: "floors/ground.usdz", for: p.id), Data("usdz".utf8))
    }

    // MARK: Duplicate

    private func allIDs(_ p: Property) -> [UUID] {
        var ids = [p.id]
        for f in p.floors {
            ids.append(f.id)
            for r in f.rooms {
                ids.append(r.id)
                ids += r.walls.map(\.id)
                ids += r.openings.map(\.id)
                ids += r.objects.map(\.id)
                ids += r.customMeasurements.map(\.id)
            }
        }
        return ids
    }

    func testDuplicateGivesAFreshIDTreeAndKeepsWallReferences() throws {
        let p = DataExportTests.marina()
        try store.save(p)
        try store.writeAsset(Data("usdz-bytes".utf8), relativePath: "floors/level23.usdz", for: p.id)
        try store.writeAsset(Data("{}".utf8), relativePath: "rooms/a/capture.json", for: p.id)
        let now = Date(timeIntervalSince1970: 1_791_600_000)

        let copy = try store.duplicate(id: p.id, now: now)
        XCTAssertEqual(copy.name, "Marina Gate 2304 copy")
        XCTAssertEqual(copy.createdAt, now)
        XCTAssertEqual(copy.updatedAt, now)
        XCTAssertNotEqual(copy.id, p.id)

        // Same number of ids, none shared with the original, none repeated.
        let oldIDs = allIDs(p), newIDs = allIDs(copy)
        XCTAssertEqual(newIDs.count, oldIDs.count)
        XCTAssertEqual(Set(newIDs).count, newIDs.count)
        XCTAssertTrue(Set(newIDs).isDisjoint(with: Set(oldIDs)))

        // Everything else is identical, and each opening sits on the copy of the same wall.
        for (fo, fc) in zip(p.floors, copy.floors) {
            XCTAssertEqual(fo.name, fc.name)
            XCTAssertEqual(fo.assets, fc.assets)
            for (ro, rc) in zip(fo.rooms, fc.rooms) {
                XCTAssertEqual(ro.name, rc.name)
                XCTAssertEqual(ro.kind, rc.kind)
                XCTAssertEqual(ro.scannedAt, rc.scannedAt)
                XCTAssertEqual(ro.ceilingHeight, rc.ceilingHeight)
                XCTAssertEqual(ro.walls.map(\.start), rc.walls.map(\.start))
                XCTAssertEqual(ro.walls.map(\.length), rc.walls.map(\.length))
                XCTAssertEqual(ro.openings.map(\.width), rc.openings.map(\.width))
                XCTAssertEqual(ro.objects.map(\.center), rc.objects.map(\.center))
                XCTAssertEqual(ro.customMeasurements.map(\.label), rc.customMeasurements.map(\.label))
                XCTAssertEqual(ro.metrics.effectiveFloorArea, rc.metrics.effectiveFloorArea)
                XCTAssertEqual(ro.metrics.netWallArea, rc.metrics.netWallArea, "wall links still resolve")
                for (oo, oc) in zip(ro.openings, rc.openings) {
                    let oldWall = ro.walls.firstIndex { $0.id == oo.wallID }
                    let newWall = rc.walls.firstIndex { $0.id == oc.wallID }
                    XCTAssertNotNil(newWall)
                    XCTAssertEqual(oldWall, newWall)
                }
            }
        }

        // Saved, listed, assets copied to the same relative paths, original untouched.
        XCTAssertEqual(try store.load(id: copy.id), copy)
        XCTAssertEqual(try store.load(id: p.id), p)
        XCTAssertEqual(try store.readAsset(relativePath: "floors/level23.usdz", for: copy.id), Data("usdz-bytes".utf8))
        XCTAssertEqual(try store.readAsset(relativePath: "rooms/a/capture.json", for: copy.id), Data("{}".utf8))
        XCTAssertEqual(Set(try store.list().map(\.id)), [p.id, copy.id])
        XCTAssertEqual(try listing(copy.id), ["floors", "property.json", "rooms"])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [])
    }

    func testDuplicateNameAndMissingSource() throws {
        let p = simple()
        try store.save(p)
        XCTAssertEqual(try store.duplicate(id: p.id, newName: "Custom name").name, "Custom name")
        let missing = UUID()
        XCTAssertThrowsError(try store.duplicate(id: missing)) { XCTAssertEqual($0 as? PropertyStoreError, .notFound(missing)) }
        XCTAssertEqual(try store.list().count, 2)
    }

    func testDuplicateDoesNotCopyTheBackupOrDamagedFiles() throws {
        var p = simple("v1")
        try store.save(p)
        p.name = "v2"
        try store.save(p)
        try Data("junk".utf8).write(to: file(p.id, "property.json.corrupt"))
        let copy = try store.duplicate(id: p.id)
        XCTAssertEqual(try listing(copy.id), ["property.json"])
        XCTAssertEqual(copy.name, "v2 copy")
    }

    func testCloneWithNewIDsDrawsIDsInAFixedOrder() {
        var next = 1000
        func make() -> UUID { next += 1; return DataExportTests.id(next) }
        var room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 1, offset: 0.2), .window(wall: 3, offset: 0.2, width: 1)])
        room.objects = [RoomObject(kind: .sofa, center: .zero, yaw: 0, width: 1, depth: 1, height: 1)]
        room.customMeasurements = [CustomMeasurement(label: "c", a: .zero, b: Point3(1, 0, 0))]
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        let copy = PropertyStore.cloneWithNewIDs(p, makeID: make)
        let rc = copy.floors[0].rooms[0]
        XCTAssertEqual(copy.id, DataExportTests.id(1001))
        XCTAssertEqual(copy.floors[0].id, DataExportTests.id(1002))
        XCTAssertEqual(rc.id, DataExportTests.id(1003))
        XCTAssertEqual(rc.walls.map(\.id), (1004...1007).map { DataExportTests.id($0) })
        XCTAssertEqual(rc.openings.map(\.id), [DataExportTests.id(1008), DataExportTests.id(1009)])
        XCTAssertEqual(rc.objects[0].id, DataExportTests.id(1010))
        XCTAssertEqual(rc.customMeasurements[0].id, DataExportTests.id(1011))
        // Door was on wall index 1, window on wall index 3.
        XCTAssertEqual(rc.openings[0].wallID, DataExportTests.id(1005))
        XCTAssertEqual(rc.openings[1].wallID, DataExportTests.id(1007))
        XCTAssertEqual(next, 1011, "exactly one id per entity")
    }

    func testCloneLeavesDanglingAndMissingWallReferencesAlone() {
        let stray = UUID()
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.openings = [
            Opening(kind: .door, wallID: stray, offsetFromWallStart: 0, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)),
            Opening(kind: .door, wallID: nil, offsetFromWallStart: 0, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)),
        ]
        let copy = PropertyStore.cloneWithNewIDs(Property(name: "P", floors: [Floor(name: "F", rooms: [room])]))
        XCTAssertEqual(copy.floors[0].rooms[0].openings[0].wallID, stray)
        XCTAssertNil(copy.floors[0].rooms[0].openings[1].wallID)
        XCTAssertNotEqual(copy.floors[0].rooms[0].openings[0].id, room.openings[0].id)
    }

    func testCloneKeepsRepeatedWallIDsTogether() {
        // Damaged data: two walls share an id. They stay one identity in the copy so links keep working.
        var room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 0, offset: 0.2)])
        room.walls[2].id = room.walls[0].id
        let copy = PropertyStore.cloneWithNewIDs(Property(name: "P", floors: [Floor(name: "F", rooms: [room])]))
        let walls = copy.floors[0].rooms[0].walls
        XCTAssertEqual(walls[0].id, walls[2].id)
        XCTAssertNotEqual(walls[0].id, room.walls[0].id)
        XCTAssertEqual(Set(walls.map(\.id)).count, 3)
        XCTAssertEqual(copy.floors[0].rooms[0].openings[0].wallID, walls[0].id)
    }

    // MARK: Concurrency

    func testManyConcurrentSavesOfDifferentProperties() throws {
        let count = 64
        let properties = (0..<count).map { i in simple("Property \(i)", id: DataExportTests.id(0x500 + i),
                                                      updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))) }
        let store = self.store!
        let failures = concurrently(count) { i in
            try store.save(properties[i])
            // Interleave reads and listings with the writes.
            _ = try store.load(id: properties[i].id)
            if i % 8 == 0 { _ = try store.list() }
        }
        XCTAssertEqual(failures, [])
        let rows = try store.list()
        XCTAssertEqual(rows.count, count)
        XCTAssertEqual(rows.map(\.name), (0..<count).reversed().map { "Property \($0)" })    // newest first
        XCTAssertTrue(rows.allSatisfy { $0.health == .ok })
        for p in properties {
            XCTAssertEqual(try store.load(id: p.id), p)
            XCTAssertEqual(try listing(p.id), ["property.json"])
        }
    }

    func testManyConcurrentSavesOfTheSameProperty() throws {
        let id = UUID()
        let store = self.store!
        try store.save(simple("seed", id: id))
        let failures = concurrently(200) { i in
            var p = self.simple("version \(i)", id: id)
            p.notes = String(repeating: "n", count: 200 * (i % 7))
            try store.save(p)
        }
        XCTAssertEqual(failures, [])
        // Whatever order they landed in, the file and the backup are both complete, readable properties.
        let loaded = try store.loadWithStatus(id: id)
        XCTAssertFalse(loaded.recoveredFromBackup)
        XCTAssertTrue(loaded.property.name.hasPrefix("version "))
        let backup = try PropertyStore.decode(Data(contentsOf: file(id, "property.json.bak")))
        XCTAssertTrue(backup.name.hasPrefix("version "))
        XCTAssertEqual(try listing(id), ["property.json", "property.json.bak"])
    }

    func testReadersNeverSeeATornFileWhileAnotherStoreWrites() throws {
        let id = UUID()
        let writer = self.store!
        let reader = PropertyStore(rootURL: root)       // a second instance: separate lock, same folder
        var seed = simple("seed", id: id)
        seed.notes = String(repeating: "s", count: 1_000_000)
        try writer.save(seed)
        let sawRecovery = NSLock()
        var recovered = 0
        let failures = concurrently(240) { i in
            if i % 3 == 0 {
                var p = self.simple("write \(i)", id: id)
                p.notes = String(repeating: "x", count: 1_000_000)       // ~1 MB: a non-atomic write would be visible for milliseconds
                try writer.save(p)
            } else {
                let loaded = try reader.loadWithStatus(id: id)
                if loaded.recoveredFromBackup { sawRecovery.lock(); recovered += 1; sawRecovery.unlock() }
            }
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(recovered, 0, "a reader saw a half-written property.json")
    }

    func testStoreIsUsableFromManyQueuesAtOnce() throws {
        // Mixed workload: save, duplicate, list, delete, asset writes on different properties.
        let store = self.store!
        let base = (0..<12).map { simple("Base \($0)", id: DataExportTests.id(0x900 + $0)) }
        for p in base { try store.save(p) }
        let failures = concurrently(48) { i in
            let p = base[i % base.count]
            switch i % 4 {
            case 0: try store.writeAsset(Data("a\(i)".utf8), relativePath: "assets/\(i).bin", for: p.id)
            case 1: _ = try store.list()
            case 2: _ = try store.duplicate(id: p.id)
            default: try store.save(p, stampUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)))
            }
        }
        XCTAssertEqual(failures, [])
        let rows = try store.list()
        XCTAssertEqual(rows.count, 12 + 12)          // twelve duplicates, one per i % 4 == 2
        XCTAssertTrue(rows.allSatisfy { $0.health == .ok })
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [])
    }

    func testALargePropertySavesLoadsAndListsQuickly() throws {
        let p = DataExportTests.bigProperty()
        let start = Date()
        try store.save(p)
        try store.save(p, stampUpdatedAt: Date(timeIntervalSince1970: 1_791_540_000))     // second save: backup path
        let back = try store.load(id: p.id)
        let rows = try store.list()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 15, "save + save + load + list of a 120-room survey took \(elapsed) s")
        XCTAssertEqual(back.roomCount, 120)
        XCTAssertEqual(back.floors.map(\.id), p.floors.map(\.id))
        XCTAssertEqual(rows.first?.roomCount, 120)
    }

    // MARK: Errors read well

    func testErrorsHaveHumanReadableDescriptions() {
        let id = UUID()
        let errors: [PropertyStoreError] = [.notFound(id), .corrupt(id, reason: "x"), .unsupportedSchemaVersion(found: 3, supported: 1),
                                           .missingMigration(from: 0), .unsafePath("../x"), .reservedPath("property.json"),
                                           .invalidAssetTarget("a")]
        for e in errors {
            let text = e.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("PropertyStoreError"), text)
        }
        XCTAssertTrue(PropertyStoreError.unsafePath("../x").errorDescription?.contains("../x") ?? false)
    }
}
