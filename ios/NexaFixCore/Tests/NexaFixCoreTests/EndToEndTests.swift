import XCTest
@testable import NexaFixCore

/// The whole data path as the person on site will use it, with nothing stubbed but the camera:
///
///     CaptureFixtures (what RoomPlan reports) -> RoomReconstructor.build -> ScanFlow (naming) ->
///     ScanCommit (one floor per scan session, two sessions on one property) -> PropertyStore save ->
///     a NEW PropertyStore on the same folder (the app relaunches) -> VerifyModel (typed text) ->
///     save again -> reload -> ExportEngine, every format, every display unit.
///
/// The exports are read back by code that shares nothing with the exporters (a small CSV reader, a JSON
/// reader, scanners for the PDF text and the DXF entities) and the expected numbers are worked out here
/// from the typed readings and the scanned lengths, not read from the exporters. The Python side
/// (`tests/test_scan_pipeline.py`) does the same with pypdf, ezdxf, the csv module and the real costing
/// engine, from the bundle this file writes when `NEXAFIX_FIXTURE_DIR` is set
/// (`testWriteFixturesWhenRequested`); `testCommittedFixturesMatchTheCurrentCode` keeps that bundle current.
final class EndToEndTests: XCTestCase {

    // MARK: Dates and ids

    /// First visit: 2026-10-09T10:00:00Z, 14:00 in Dubai.
    static let day1 = Date(timeIntervalSince1970: 1_791_540_000)
    /// Second visit, three days later: 2026-10-12T05:30:00Z, 09:30 in Dubai.
    static let day2 = Date(timeIntervalSince1970: 1_791_783_000)
    /// When the laser readings are typed in: 2026-10-12T09:00:00Z.
    static let verifiedAt = Date(timeIntervalSince1970: 1_791_795_600)
    /// The date in the export file names: 2026-10-12T10:00:00Z, still 12 October in Dubai.
    static let exportedAt = Date(timeIntervalSince1970: 1_791_799_200)

    static let propertyID = RoomReconstructor.stableUUID("e2e|property")
    static let floor1ID = RoomReconstructor.stableUUID("e2e|floor|1")
    static let floor2ID = RoomReconstructor.stableUUID("e2e|floor|2")

    /// The five ways a person can set the display units. Square feet go with the imperial lengths.
    static let unitChoices: [(tag: String, units: DisplayUnits)] = [
        ("mm", DisplayUnits(length: .millimetres, area: .squareMetres)),
        ("cm", DisplayUnits(length: .centimetres, area: .squareMetres)),
        ("m", DisplayUnits(length: .metres, area: .squareMetres)),
        ("in", DisplayUnits(length: .inches, area: .squareFeet)),
        ("ftin", DisplayUnits(length: .feetAndInches, area: .squareFeet)),
    ]

    // MARK: The scenario

    /// One room as it is scanned: the shape RoomPlan reports and the name and kind the person gives it.
    struct ScannedRoom {
        var name: String
        var kind: RoomKind
        var fixture: CaptureFixtures.Fixture
    }

    static func extras(_ label: String, origin: Point2 = .zero,
                       objects: [CaptureFixtures.FixtureObject] = []) -> CaptureFixtures.Extras {
        var extras = CaptureFixtures.Extras()
        extras.label = label          // every room of every session needs its own: ids come from the label
        extras.origin = origin
        extras.objects = objects
        return extras
    }

    /// Session 1: a rectangle with furniture, a small kitchen, an L-shaped lounge and an open-plan dining
    /// area whose west side has no wall.
    static func session1() -> [ScannedRoom] {
        [ScannedRoom(name: "Living Room", kind: .livingRoom,
                     fixture: CaptureFixtures.rectangle(
                        width: 6.2, depth: 4.5, height: 2.8,
                        doors: [.door(wall: 0, offset: 0.5)],
                        windows: [.window(wall: 2, offset: 1.0, width: 3.0, height: 2.4, sill: 0.3)],
                        noise: .light, seed: 11,
                        extras: extras("e2e-living", objects: CaptureFixtures.sampleObjects(width: 6.2, depth: 4.5)))),
         ScannedRoom(name: "Kitchen", kind: .kitchen,
                     fixture: CaptureFixtures.rectangle(
                        width: 3.2, depth: 2.8, height: 2.8,
                        doors: [.door(wall: 3, offset: 0.9)],
                        windows: [.window(wall: 0, offset: 1.0, width: 1.2, height: 1.2, sill: 1.05)],
                        noise: .realistic, seed: 12, extras: extras("e2e-kitchen", origin: Point2(6.35, 0)))),
         ScannedRoom(name: "Lounge", kind: .other,
                     fixture: CaptureFixtures.lShape(
                        width: 6.0, depth: 4.0, notchWidth: 2.0, notchDepth: 2.0, height: 2.8,
                        doors: [.door(wall: 0, offset: 1.0)], noise: .light, seed: 13,
                        extras: extras("e2e-lounge", origin: Point2(0, 5.0)))),
         ScannedRoom(name: "Open Dining", kind: .dining,
                     fixture: CaptureFixtures.openPlan(
                        width: 5.0, depth: 4.0, missingWall: 3, height: 2.8,
                        windows: [.window(wall: 1, offset: 1.0, width: 1.5, height: 1.4, sill: 0.9)],
                        noise: .light, seed: 14, extras: extras("e2e-dining", origin: Point2(0, 10.0))))]
    }

    /// Session 2, another visit with its own AR session: noisy scans, a name the first visit already used,
    /// and a balcony.
    static func session2() -> [ScannedRoom] {
        [ScannedRoom(name: "Bedroom", kind: .bedroom,
                     fixture: CaptureFixtures.rectangle(
                        width: 4.1, depth: 3.5, height: 2.7,
                        doors: [.door(wall: 0, offset: 0.4)],
                        windows: [.window(wall: 2, offset: 0.8, width: 1.8, height: 1.5, sill: 0.8)],
                        noise: .realistic, seed: 21, extras: extras("e2e-bedroom"))),
         ScannedRoom(name: "Kitchen", kind: .kitchen,       // taken by session 1: ScanFlow must offer another
                     fixture: CaptureFixtures.rectangle(
                        width: 2.9, depth: 2.4, height: 2.7, noise: .realistic, seed: 22,
                        extras: extras("e2e-kitchen-2", origin: Point2(5, 0)))),
         ScannedRoom(name: "Balcony", kind: .balcony,
                     fixture: CaptureFixtures.rectangle(
                        width: 4.5, depth: 1.5, height: 2.7,
                        doors: [OpeningSpec(wall: 2, kind: .door, offset: 1.0, width: 2.4, height: 2.2)],
                        noise: .realistic, seed: 23, extras: extras("e2e-balcony", origin: Point2(0, 4))))]
    }

    // MARK: Driving a scan like the scan screen does

    struct SessionResult {
        var rooms: [Room]
        var flow: ScanFlow
        /// The names the person typed that the flow had to change, "Kitchen -> Kitchen 2".
        var renamed: [String]
    }

    /// What `ScanSessionController` does, event by event: the capture is finished, the room is built once to
    /// show a draft, the person names it, the flow moves on, and at the end every room is built again with its
    /// final name and kind.
    static func scan(_ scanned: [ScannedRoom], existingRoomNames: [String], story: Int, at date: Date,
                     file: StaticString = #filePath, line: UInt = #line) -> SessionResult {
        var flow = ScanFlow(existingRoomNames: existingRoomNames)
        var records: [UUID: RawCapture] = [:]
        var renamed: [String] = []
        XCTAssertEqual(flow.send(.start), [.startCapture], file: file, line: line)
        for (index, item) in scanned.enumerated() {
            if index > 0 { XCTAssertEqual(flow.send(.scanNext), [.startCapture], file: file, line: line) }
            XCTAssertEqual(flow.send(.finishRoom), [.stopCapture(keepARSession: true), .buildRoom],
                           file: file, line: line)
            var raw = item.fixture.capture
            raw.story = story
            let draftRoom = RoomReconstructor.build(from: raw, name: "Room", kind: .other, now: date).room
            let draft = RoomDraft(id: UUID(), stats: LiveScanStats(capture: raw),
                                  floorAreaM2: draftRoom.metrics.floorArea)
            records[draft.id] = raw
            _ = flow.send(.roomFinished(draft))
            XCTAssertEqual(flow.draftAwaitingName?.id, draft.id, file: file, line: line)
            var name = item.name
            switch flow.validate(name: name) {
            case .valid:
                break
            case .duplicate(_, let suggestion):
                renamed.append(name + " -> " + suggestion)
                name = suggestion
            case let other:
                XCTFail("name \(name) refused: \(String(describing: other.message))", file: file, line: line)
            }
            _ = flow.send(.named(name: name, kind: item.kind))
        }
        XCTAssertEqual(flow.send(.finishProperty), [.mergeStructure], file: file, line: line)
        let rooms = flow.rooms.map { entry -> Room in
            RoomReconstructor.build(from: records[entry.id] ?? RawCapture(), name: entry.name, kind: entry.kind,
                                    now: date).room
        }
        XCTAssertEqual(flow.send(.mergeCompleted), [.saveResult], file: file, line: line)
        XCTAssertEqual(flow.state, .finished, file: file, line: line)
        return SessionResult(rooms: rooms, flow: flow, renamed: renamed)
    }

    /// The bytes standing in for the merged USDZ of a level. Not a real model: the export must pass the bytes
    /// through untouched.
    static func fakeUSDZ(_ tag: String) -> Data {
        var bytes = Data([0x50, 0x4B, 0x03, 0x04])
        bytes.append(Data("fake-usdz-\(tag)".utf8))
        bytes.append(Data((0..<64).map { UInt8($0) }))
        return bytes
    }

    // MARK: Both sessions, saved

    struct Run {
        var root: URL
        var scan1: SessionResult
        var scan2: SessionResult
        var plan1: ScanCommit.CommitPlan
        var plan2: ScanCommit.CommitPlan
        /// The property as the second save left it.
        var saved: Property
    }

    /// Writes the files a commit plans, then saves the property, the order `ScanIntake.commit` uses.
    static func commit(_ plan: ScanCommit.CommitPlan, usdz: Data, store: PropertyStore) throws -> Property {
        for asset in plan.assets {
            switch asset.kind {
            case .structureUSDZ:
                try store.writeAsset(usdz, relativePath: asset.relativePath, for: plan.property.id)
            case .worldMap:
                try store.writeAsset(Data("map".utf8), relativePath: asset.relativePath, for: plan.property.id)
            case .capturedRoom(let id):
                try store.writeAsset(Data("{\"room\":\"\(id.uuidString)\"}".utf8), relativePath: asset.relativePath,
                                     for: plan.property.id)
            }
        }
        return try store.save(plan.property)
    }

    /// A new property (with the empty starter floor `AppModel.createProperty` makes), then two scan
    /// sessions on it, each committed and saved.
    static func scanAndSave(root: URL) throws -> Run {
        let store = PropertyStore(rootURL: root)
        var property = Property(id: propertyID, name: "Marina Gate 2 - Unit 2304", client: "Mr. Ahmed Khan",
                                address: "Marina Gate 2, Dubai Marina, Dubai", reference: "NF-2026-1009-01",
                                kind: .apartment, notes: "end to end", createdAt: day1, updatedAt: day1,
                                floors: [Floor(name: "Main level", level: 0)])
        property = try store.save(property)

        let scan1 = scan(session1(), existingRoomNames: property.allRooms.map(\.name), story: 23, at: day1)
        let plan1 = ScanCommit.apply(
            rooms: scan1.rooms, story: 23, scannedAt: day1, to: property,
            available: ScanCommit.AvailableAssets(structureUSDZ: true, capturedRoomIDs: Set(scan1.rooms.map(\.id))),
            makeID: { floor1ID })
        property = try commit(plan1, usdz: fakeUSDZ("level-1"), store: store)

        let scan2 = scan(session2(), existingRoomNames: property.allRooms.map(\.name), story: 23, at: day2)
        let plan2 = ScanCommit.apply(
            rooms: scan2.rooms, story: 23, scannedAt: day2, to: property,
            available: ScanCommit.AvailableAssets(structureUSDZ: true, capturedRoomIDs: Set(scan2.rooms.map(\.id))),
            makeID: { floor2ID })
        property = try commit(plan2, usdz: fakeUSDZ("level-2"), store: store)
        return Run(root: root, scan1: scan1, scan2: scan2, plan1: plan1, plan2: plan2, saved: property)
    }

    // MARK: Typing readings in

    /// What was typed, and where it went.
    struct TypedCheck {
        enum Quantity { case wallLength, openingWidth, ceilingHeight, customLength }
        var floor: String
        var room: String
        /// "Wall A", "Window 1" or "Ceiling height".
        var label: String
        var quantity: Quantity
        var typed: String
        var unit: LengthUnit
        var source: VerificationSource
        var target: MeasureTarget
        /// What LiDAR read, metres.
        var scannedM: Double
        /// What the person measured, metres.
        var verifiedM: Double
    }

    /// The solid walls of `room` whose scanned length is within 15 cm of `length`, in loop order.
    static func walls(of room: Room, near length: Double) -> [Wall] {
        room.walls.filter { $0.kind == .solid && abs($0.length.scanned - length) < 0.15 }
    }

    /// Types the readings into `VerifyModel` the way the Verify sheet does and saves them through
    /// `Property.modifyRoom` and `PropertyStore.save`. Returns what was typed.
    @discardableResult
    static func verifyOnSite(store: PropertyStore, propertyID: UUID, date: Date) throws -> [TypedCheck] {
        var property = try store.load(id: propertyID)
        var done: [TypedCheck] = []

        func type(floor: String, room roomName: String, text: String, unit: LengthUnit, source: VerificationSource,
                  note: String? = nil, quantity: TypedCheck.Quantity, target pick: (Room) -> MeasureTarget?) {
            guard let floorIndex = property.floors.firstIndex(where: { $0.name == floor }),
                  let room = property.floors[floorIndex].rooms.first(where: { $0.name == roomName }),
                  let aim = pick(room), let scanned = room.measured(aim)?.scanned else {
                XCTFail("nothing to verify in \(roomName)")
                return
            }
            var model = VerifyModel(room: room, target: aim, units: DisplayUnits(length: unit))
            model.text = text
            model.source = source
            if let note { model.note = note }
            XCTAssertEqual(model.check, .ok, "\(roomName): \(text) -> \(String(describing: model.message))")
            guard let check = model.verification(date: date) else {
                XCTFail("\(roomName): \(text) cannot be saved")
                return
            }
            XCTAssertTrue(property.modifyRoom(id: room.id) { $0.setVerification(check, for: aim) })
            done.append(TypedCheck(floor: floor, room: roomName, label: room.title(for: aim), quantity: quantity,
                                   typed: text, unit: unit, source: source, target: aim, scannedM: scanned,
                                   verifiedM: check.value))
        }

        // The kitchen: a wall typed as "3,245" (a comma is a decimal point: 3.245 m), the ceiling in
        // millimetres and the window in centimetres.
        type(floor: "Level 23", room: "Kitchen", text: "3,245", unit: .metres, source: .laser,
             note: "skirting to skirting", quantity: .wallLength) { room in
            walls(of: room, near: 3.2).first.map { .wallLength($0.id) }
        }
        type(floor: "Level 23", room: "Kitchen", text: "2760", unit: .millimetres, source: .laser,
             quantity: .ceilingHeight) { _ in .ceilingHeight }
        type(floor: "Level 23", room: "Kitchen", text: "118.5", unit: .centimetres, source: .tape,
             quantity: .openingWidth) { room in
            room.openings.first { $0.kind == .window }.map { .openingWidth($0.id) }
        }
        // The living room: both long walls, so its length is verified (its width is not).
        type(floor: "Level 23", room: "Living Room", text: "6240", unit: .millimetres, source: .laser,
             quantity: .wallLength) { room in
            let long = walls(of: room, near: 6.2)
            return long.count == 2 ? .wallLength(long[0].id) : nil
        }
        type(floor: "Level 23", room: "Living Room", text: "6.236 m", unit: .metres, source: .laser,
             quantity: .wallLength) { room in
            let long = walls(of: room, near: 6.2)
            return long.count == 2 ? .wallLength(long[1].id) : nil
        }
        // A tape measure taken in the AR view (`PropertyActions.addMeasurement`), then laser-checked.
        let wardrobe = CustomMeasurement(id: RoomReconstructor.stableUUID("e2e|measurement|wardrobe"),
                                         label: "Wardrobe wall", a: Point3(1.0, -0.3, -0.5), b: Point3(2.8, -0.3, -0.5),
                                         createdAt: day2, note: "built-in, floor to ceiling")
        if let living = property.allRooms.first(where: { $0.name == "Living Room" }) {
            XCTAssertTrue(property.modifyRoom(id: living.id) { $0.customMeasurements.append(wardrobe) })
        }
        type(floor: "Level 23", room: "Living Room", text: "1,805", unit: .metres, source: .laser,
             quantity: .customLength) { _ in .customLength(wardrobe.id) }
        // The second visit's bedroom: the ceiling from the drawing, in feet and inches.
        type(floor: "Level 23 (2)", room: "Bedroom", text: "8' 10\"", unit: .feetAndInches, source: .drawing,
             quantity: .ceilingHeight) { _ in .ceilingHeight }

        property.updatedAt = date
        _ = try store.save(property)
        return done
    }

    // MARK: Exporting

    /// The saved model of each level, as files to read when the export runs (what `ExportSheet` does).
    static func usdzSources(for property: Property, store: PropertyStore) throws -> [UUID: USDZSource] {
        var sources: [UUID: USDZSource] = [:]
        for floor in property.floors {
            guard let path = floor.assets.structureUSDZ else { continue }
            sources[floor.id] = .file(try store.resolve(relativePath: path, in: property.id))
        }
        return sources
    }

    static func everything(_ property: Property, units: DisplayUnits, store: PropertyStore,
                           now: Date = exportedAt) throws -> ExportResult {
        try ExportEngine.runDetailed(ExportRequest(property: property, formats: Set(ExportFormat.allCases),
                                                   units: units, usdzSources: try usdzSources(for: property, store: store),
                                                   now: now))
    }

    // MARK: Readers that share nothing with the exporters

    /// A CSV file: RFC 4180, the leading byte order mark noted and removed.
    struct CSVTable {
        var hasBOM: Bool
        var endsWithCRLF: Bool
        var rows: [[String]]

        var header: [String] { rows.first ?? [] }
        var records: [[String: String]] {
            rows.dropFirst().map { row in Dictionary(uniqueKeysWithValues: zip(header, row).map { ($0, $1) }) }
        }
    }

    static func readCSV(_ data: Data) -> CSVTable {
        var scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        let bom = scalars.first == "\u{FEFF}"
        if bom { scalars.removeFirst() }
        let crlf = scalars.count >= 2 && scalars[scalars.count - 2] == "\r" && scalars[scalars.count - 1] == "\n"
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(String(field)); field = String.UnicodeScalarView()
            } else if c == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
                row.append(String(field)); field = String.UnicodeScalarView()
                rows.append(row); row = []
                i += 1
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(String(field)); rows.append(row) }
        return CSVTable(hasBOM: bom, endsWithCRLF: crlf, rows: rows)
    }

    static func readJSON(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("not a JSON object", file: file, line: line)
            return [:]
        }
        return object
    }

    /// Every string the PDF draws (`(text) Tj`), in drawing order, WinAnsi escapes resolved.
    static func pdfStrings(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var out: [String] = []
        var i = 0
        while i < bytes.count {
            guard bytes[i] == UInt8(ascii: "(") else { i += 1; continue }
            var depth = 1
            var j = i + 1
            var scalars = String.UnicodeScalarView()
            while j < bytes.count, depth > 0 {
                let b = bytes[j]
                if b == UInt8(ascii: "\\"), j + 1 < bytes.count {
                    let n = bytes[j + 1]
                    if n >= 0x30, n <= 0x37 {
                        var value = 0
                        var k = j + 1
                        while k < bytes.count, k < j + 4, bytes[k] >= 0x30, bytes[k] <= 0x37 {
                            value = value * 8 + Int(bytes[k] - 0x30)
                            k += 1
                        }
                        scalars.append(Unicode.Scalar(UInt8(value & 0xFF)))   // WinAnsi = Latin-1 for what we print
                        j = k
                    } else {
                        scalars.append(Unicode.Scalar(n))
                        j += 2
                    }
                    continue
                }
                if b == UInt8(ascii: "(") { depth += 1 }
                if b == UInt8(ascii: ")") { depth -= 1; if depth == 0 { break } }
                scalars.append(Unicode.Scalar(b))
                j += 1
            }
            let end = j + 1
            if end + 3 < bytes.count, bytes[end] == 0x20, bytes[end + 1] == UInt8(ascii: "T"),
               bytes[end + 2] == UInt8(ascii: "j") {
                out.append(String(scalars))
            }
            i = max(end, i + 1)
        }
        return out
    }

    static func pdfPageCount(_ data: Data) -> Int {
        String(decoding: data, as: UTF8.self).components(separatedBy: "/Type /Page ").count - 1
    }

    struct DXFEntity {
        var type: String
        var layer: String
        var text: String?
        /// Every group of the entity as "code=value", without the handle (5) and owner (330) groups, which
        /// depend on how many entities came before.
        var groups: [String] = []
    }

    /// The entities of the ENTITIES section: type, layer, groups and, for TEXT, its string.
    static func readDXF(_ data: Data) -> [DXFEntity] {
        let lines = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var entities: [DXFEntity] = []
        var section = ""
        var current: DXFEntity?
        var i = 0
        while i + 1 < lines.count {
            let code = lines[i].trimmingCharacters(in: .whitespaces)
            let value = lines[i + 1]
            i += 2
            if code == "0" {
                if let finished = current { entities.append(finished); current = nil }
                if value == "SECTION" { section = ""; continue }
                if value == "ENDSEC" { section = ""; continue }
                if section == "ENTITIES" { current = DXFEntity(type: value, layer: "", text: nil) }
            } else if code == "2", current == nil, section.isEmpty {
                section = value
            } else if section == "ENTITIES", current != nil {
                if code == "8" { current?.layer = value }
                if code == "1", current?.type == "TEXT" { current?.text = value }
                if code != "5", code != "330" { current?.groups.append(code + "=" + value) }
            }
        }
        return entities
    }

    // MARK: Looking things up in the files

    static func jsonRoom(_ scan: [String: Any], _ name: String) -> [String: Any]? {
        let floors = scan["floors"] as? [[String: Any]] ?? []
        for floor in floors {
            for room in floor["rooms"] as? [[String: Any]] ?? [] where room["name"] as? String == name { return room }
        }
        return nil
    }

    static func jsonMeasured(_ scan: [String: Any], _ check: TypedCheck) -> [String: Any]? {
        guard let room = jsonRoom(scan, check.room) else { return nil }
        switch check.quantity {
        case .ceilingHeight:
            return room["ceilingHeight"] as? [String: Any]
        case .wallLength:
            let walls = room["walls"] as? [[String: Any]] ?? []
            return walls.first { $0["label"] as? String == check.label }?["length"] as? [String: Any]
        case .openingWidth:
            let openings = room["openings"] as? [[String: Any]] ?? []
            return openings.first { $0["label"] as? String == check.label }?["width"] as? [String: Any]
        case .customLength:
            let customs = room["customMeasurements"] as? [[String: Any]] ?? []
            return customs.first { $0["label"] as? String == check.label }?["length"] as? [String: Any]
        }
    }

    // MARK: Scratch folder

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexafix-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }


    // MARK: Helpers for the tests

    /// Both sessions saved, then the readings typed, then a relaunch: what the person has after a day on site.
    private func verifiedProperty() throws -> (before: Property, after: Property, typed: [TypedCheck], store: PropertyStore) {
        let run = try Self.scanAndSave(root: scratch)
        let before = try PropertyStore(rootURL: scratch).load(id: run.saved.id)
        let typed = try Self.verifyOnSite(store: PropertyStore(rootURL: scratch), propertyID: run.saved.id,
                                          date: Self.verifiedAt)
        let store = PropertyStore(rootURL: scratch)             // another launch of the app
        return (before, try store.load(id: run.saved.id), typed, store)
    }

    private static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    private func number(_ value: Any?, _ what: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let n = (value as? NSNumber)?.doubleValue else {
            XCTFail("\(what) is not a number: \(String(describing: value))", file: file, line: line)
            return .nan
        }
        return n
    }

    private func artifact(_ result: ExportResult, _ suffix: String, file: StaticString = #filePath,
                          line: UInt = #line) -> ExportArtifact {
        guard let found = result.artifacts.first(where: { $0.filename.hasSuffix(suffix) }) else {
            XCTFail("no \(suffix) in \(result.artifacts.map(\.filename))", file: file, line: line)
            return ExportArtifact(filename: "", data: Data(), formatKind: .dataJSON, contentTypeIdentifier: "")
        }
        return found
    }

    // MARK: 1. Two scan sessions, one property, a relaunch

    func testTwoScanSessionsBecomeTwoFloorsThatSurviveARelaunch() throws {
        let run = try Self.scanAndSave(root: scratch)

        // ScanFlow offered another name for the repeated kitchen, and nothing else was renamed.
        XCTAssertEqual(run.scan1.renamed, [])
        XCTAssertEqual(run.scan2.renamed, ["Kitchen -> Kitchen 2"])
        XCTAssertEqual(run.scan1.flow.rooms.map(\.name), ["Living Room", "Kitchen", "Lounge", "Open Dining"])
        XCTAssertEqual(run.scan2.flow.rooms.map(\.name), ["Bedroom", "Kitchen 2", "Balcony"])

        // One floor per AR session; the empty starter floor of a new property is gone.
        XCTAssertEqual(run.saved.floors.map(\.name), ["Level 23", "Level 23 (2)"])
        XCTAssertEqual(run.saved.floors.map(\.level), [23, 23])
        XCTAssertEqual(run.saved.floors.map(\.id), [Self.floor1ID, Self.floor2ID])
        XCTAssertEqual(run.saved.floors[0].rooms.map(\.name), ["Living Room", "Kitchen", "Lounge", "Open Dining"])
        XCTAssertEqual(run.saved.floors[1].rooms.map(\.name), ["Bedroom", "Kitchen 2", "Balcony"])
        XCTAssertEqual(run.plan1.summary, "Added 4 rooms to Level 23.")
        XCTAssertEqual(run.plan2.summary, "Added 3 rooms to Level 23 (2).")
        XCTAssertEqual(Set(run.saved.allRooms.map(\.id)).count, 7, "every room has its own id")
        XCTAssertEqual(Set(run.saved.allRooms.flatMap { $0.walls.map(\.id) }).count, run.saved.allRooms.reduce(0) { $0 + $1.walls.count },
                       "every wall of every room has its own id")

        // The reconstructed rooms match the ground truth the fixtures were generated from.
        let truth = Self.session1() + Self.session2()
        for (room, item) in zip(run.saved.allRooms, truth) {
            let fixture = item.fixture
            XCTAssertEqual(room.walls.count, fixture.expectedWallCount, room.name)
            XCTAssertEqual(room.walls.filter { $0.kind == .virtual }.count, fixture.expectedVirtualWallCount, room.name)
            XCTAssertEqual(room.metrics.floorArea, fixture.expectedArea, accuracy: fixture.expectedArea * 0.015, room.name)
            XCTAssertEqual(room.metrics.perimeter, fixture.expectedPerimeter, accuracy: fixture.expectedPerimeter * 0.015, room.name)
            XCTAssertEqual(room.ceilingHeight.scanned, fixture.ceilingHeight, accuracy: 0.03, room.name)
            XCTAssertFalse(room.walls.contains { $0.length.isVerified } || room.ceilingHeight.isVerified, "nothing is verified yet")
            XCTAssertEqual(room.scannedAt, room.name.hasPrefix("Bedroom") || room.name.hasPrefix("Kitchen 2") || room.name == "Balcony"
                           ? Self.day2 : Self.day1, room.name)
        }
        XCTAssertEqual(run.saved.allRooms.map { $0.metrics.isRectangular }, [true, true, false, true, true, true, true])

        // Files: written first, recorded only because they exist, readable by a new store.
        let relaunched = PropertyStore(rootURL: scratch)
        for (floor, tag) in zip(run.saved.floors, ["level-1", "level-2"]) {
            XCTAssertEqual(floor.assets.structureUSDZ, "floors/\(floor.id.uuidString)/model.usdz")
            XCTAssertNil(floor.assets.worldMap)
            XCTAssertEqual(try relaunched.readAsset(relativePath: try XCTUnwrap(floor.assets.structureUSDZ), for: run.saved.id),
                           Self.fakeUSDZ(tag))
            for room in floor.rooms {
                XCTAssertEqual(room.capturedRoomFile, "rooms/\(room.id.uuidString).roomplan.json")
                XCTAssertFalse(try relaunched.readAsset(relativePath: try XCTUnwrap(room.capturedRoomFile),
                                                        for: run.saved.id).isEmpty)
            }
        }

        // A new store on the same folder (the app relaunches) reads back exactly what was saved.
        let loaded = try relaunched.loadWithStatus(id: run.saved.id)
        XCTAssertEqual(loaded.property, run.saved)
        XCTAssertFalse(loaded.recoveredFromBackup)
        XCTAssertFalse(loaded.migrated)
        XCTAssertEqual(loaded.schemaVersionOnDisk, PropertyStore.currentSchemaVersion)
        let list = try relaunched.list()
        XCTAssertEqual(list.map(\.id), [run.saved.id])
        XCTAssertEqual(list[0].roomCount, 7)
        XCTAssertEqual(list[0].health, .ok)
        XCTAssertEqual(list[0].verifiedFraction, 0)
        XCTAssertEqual(list[0].floorAreaM2, run.saved.allRooms.reduce(0) { $0 + $1.metrics.effectiveFloorArea }, accuracy: 1e-3)

        // Applying the same scan result again (a double tap on Save) adds nothing.
        let again = ScanCommit.apply(rooms: run.scan2.rooms, story: 23, scannedAt: Self.day2, to: loaded.property,
                                     available: ScanCommit.AvailableAssets(structureUSDZ: true))
        XCTAssertTrue(again.isNoOp)
        XCTAssertEqual(again.property, loaded.property)
        XCTAssertEqual(again.skippedRoomIDs.count, 3)
    }

    // MARK: 2. Typed readings

    func testTypedReadingsAreVerifiedSavedAndComeBackAfterARelaunch() throws {
        let (before, after, typed, _) = try verifiedProperty()
        XCTAssertEqual(typed.map(\.verifiedM), [3.245, 2.76, 1.185, 6.24, 6.236, 1.805, 2.6924])
        // The wall letters depend on where the reconstructor started each loop; the rest is fixed.
        XCTAssertEqual([typed[1], typed[2], typed[5], typed[6]].map(\.label),
                       ["Ceiling height", "Window 1", "Wardrobe wall", "Ceiling height"])
        XCTAssertTrue([typed[0], typed[3], typed[4]].allSatisfy { $0.label.hasPrefix("Wall ") })

        for check in typed {
            let room = try XCTUnwrap(after.allRooms.first { $0.name == check.room })
            let measured = try XCTUnwrap(room.measured(check.target), "\(check.room) \(check.label)")
            XCTAssertEqual(measured.scanned, check.scannedM, "\(check.room) \(check.label): the scan is never overwritten")
            let verification = try XCTUnwrap(measured.verification, "\(check.room) \(check.label) is verified")
            XCTAssertEqual(verification.value, check.verifiedM, accuracy: 1e-12)
            XCTAssertEqual(verification.source, check.source)
            XCTAssertEqual(verification.date, Self.verifiedAt)
            XCTAssertEqual(measured.value, check.verifiedM, "the number to use is the verified one")
        }
        let kitchenWall = try XCTUnwrap(typed.first { $0.room == "Kitchen" && $0.quantity == .wallLength })
        let kitchen = try XCTUnwrap(after.allRooms.first { $0.name == "Kitchen" })
        XCTAssertEqual(kitchen.measured(kitchenWall.target)?.verification?.note, "skirting to skirting")

        // Only those seven values changed: take the checks away again and the property is what was scanned.
        var undone = after
        for check in typed {
            let room = try XCTUnwrap(undone.allRooms.first { $0.name == check.room })
            XCTAssertTrue(undone.modifyRoom(id: room.id) { $0.setVerification(nil, for: check.target) })
        }
        undone.modifyRoom(id: undone.allRooms.first { $0.name == "Living Room" }!.id) { $0.customMeasurements = [] }
        undone.updatedAt = before.updatedAt
        XCTAssertEqual(undone, before, "verification moved no wall, no opening and no scanned value")

        // And the room list on the Properties screen shows it.
        let summary = try PropertyStore(rootURL: scratch).summary(id: after.id)
        let counts = after.allRooms.reduce((verified: 0, total: 0)) { sum, room in
            let list = VerificationChecklist(room: room)
            return (sum.verified + list.verifiedCount, sum.total + list.totalCount)
        }
        XCTAssertEqual(counts.verified, 7)
        XCTAssertEqual(summary.verifiedFraction, Double(counts.verified) / Double(counts.total), accuracy: 1e-12)
    }

    func testThousandsCommaInAMillimetreFieldIsHeldBackNotSavedAsThreeMillimetres() throws {
        let run = try Self.scanAndSave(root: scratch)
        let kitchen = try XCTUnwrap(run.saved.allRooms.first { $0.name == "Kitchen" })
        let wall = try XCTUnwrap(Self.walls(of: kitchen, near: 3.2).first)

        // Metres: "3,245" is 3.245 m. Plain.
        var metres = VerifyModel(room: kitchen, target: .wallLength(wall.id), units: DisplayUnits(length: .metres))
        metres.text = "3,245"
        XCTAssertEqual(metres.parsedValue ?? 0, 3.245, accuracy: 1e-12)
        XCTAssertEqual(metres.check, .ok)
        XCTAssertTrue(metres.canSave)

        // Millimetres: the same keystrokes read as 3.245 mm. The sheet must stop it and say why.
        var millimetres = VerifyModel(room: kitchen, target: .wallLength(wall.id), units: DisplayUnits(length: .millimetres))
        millimetres.text = "3,245"
        XCTAssertEqual(millimetres.parsedValue ?? 0, 0.003245, accuracy: 1e-12)
        guard case .farFromScan(let message) = millimetres.check else { return XCTFail("expected a warning, got \(millimetres.check)") }
        XCTAssertTrue(message.contains("A comma is read as a decimal point."), message)
        XCTAssertFalse(millimetres.canSave)
        XCTAssertNil(millimetres.commit(date: Self.verifiedAt))
        XCTAssertNil(millimetres.verification(date: Self.verifiedAt))
    }

    // MARK: 3. Every format, every unit

    func testEveryFormatInEveryDisplayUnitIsWellFormedAndDeterministic() throws {
        let (_, property, typed, store) = try verifiedProperty()
        let base = "NexaFix_Marina-Gate-2-Unit-2304_2026-10-12_"
        let expectedNames = [base + "floor-plan.pdf", base + "plan-Level-23.dxf", base + "plan-Level-23-2.dxf",
                             base + "model-Level-23.usdz", base + "model-Level-23-2.usdz", base + "scan.json",
                             base + "rooms.csv", base + "walls.csv", base + "openings.csv", base + "objects.csv",
                             base + "custom-measurements.csv", base + "costing-spec.json"]
        var json: [Data] = []
        var spec: [Data] = []
        for (tag, units) in Self.unitChoices {
            let result = try Self.everything(property, units: units, store: store)
            XCTAssertEqual(result.notes, [], tag)
            XCTAssertEqual(result.artifacts.map(\.filename), expectedNames, tag)
            XCTAssertEqual(result.artifacts.map(\.formatKind),
                           [.planPDF, .cadDXF, .cadDXF, .model3D, .model3D, .dataJSON, .csv, .csv, .csv, .csv, .csv, .costingSpec], tag)
            XCTAssertTrue(result.artifacts.allSatisfy { !$0.data.isEmpty && $0.contentTypeIdentifier == $0.formatKind.contentTypeIdentifier }, tag)

            // The same request gives the same bytes.
            let twice = try Self.everything(property, units: units, store: store)
            XCTAssertEqual(twice, result, "\(tag): not deterministic")

            // USDZ: the saved bytes, untouched.
            XCTAssertEqual(artifact(result, "model-Level-23.usdz").data, Self.fakeUSDZ("level-1"), tag)
            XCTAssertEqual(artifact(result, "model-Level-23-2.usdz").data, Self.fakeUSDZ("level-2"), tag)

            // PDF: two plan sheets and the schedule, every page carrying the joinery disclaimer.
            let pdf = artifact(result, ".pdf").data
            XCTAssertTrue(pdf.starts(with: Data("%PDF-1.4".utf8)), tag)
            XCTAssertTrue(String(decoding: pdf.suffix(8), as: UTF8.self).contains("%%EOF"), tag)
            XCTAssertEqual(Self.pdfPageCount(pdf), 3, tag)
            let texts = Self.pdfStrings(pdf)
            XCTAssertEqual(texts.filter { $0 == ScanAccuracy.joineryDisclaimer }.count, 3, "\(tag): disclaimer on every page")
            for line in ["Room schedule", "LEVEL 23  -  FLOOR PLAN", "LEVEL 23 (2)  -  FLOOR PLAN", "Sheet 1 of 3", "Sheet 2 of 3",
                         "Sheet 3 of 3", "Marina Gate 2 - Unit 2304", "Mr. Ahmed Khan", "NF-2026-1009-01", "12 Oct 2026"] {
                XCTAssertTrue(texts.contains(line), "\(tag): PDF lacks \"\(line)\"")
            }
            for name in property.allRooms.map(\.name) {
                XCTAssertTrue(texts.contains(name), "\(tag): the schedule or the plan lacks \(name)")
            }
            XCTAssertTrue(texts.contains { $0.hasPrefix("Total (7 rooms)") }, tag)

            // DXF: one drawing per floor, millimetres, both real layers and entities.
            for (suffix, floor) in [("plan-Level-23.dxf", property.floors[0]), ("plan-Level-23-2.dxf", property.floors[1])] {
                let data = artifact(result, suffix).data
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(text.hasSuffix("EOF\n") || text.hasSuffix("EOF\r\n"), "\(tag) \(suffix) ends with EOF")
                let entities = Self.readDXF(data)
                let count = { (layer: String, type: String) in entities.filter { $0.layer == layer && $0.type == type }.count }
                XCTAssertEqual(count("NF-ROOM-LABELS", "TEXT"), floor.rooms.count * 3, "\(tag) \(suffix): name, area, ceiling per room")
                XCTAssertEqual(count("NF-DIMENSIONS", "TEXT"), floor.rooms.reduce(0) { $0 + $1.walls.count },
                               "\(tag) \(suffix): one dimension per wall, open boundary included")
                XCTAssertEqual(count("NF-DOORS", "TEXT"), floor.rooms.reduce(0) { $0 + $1.openings.filter { $0.kind == .door }.count }, "\(tag) \(suffix)")
                XCTAssertEqual(count("NF-WINDOWS", "TEXT"), floor.rooms.reduce(0) { $0 + $1.openings.filter { $0.kind == .window }.count }, "\(tag) \(suffix)")
                XCTAssertEqual(count("NF-WALLS-OPEN", "LINE"), floor.rooms.reduce(0) { $0 + $1.walls.filter { $0.kind == .virtual }.count }, "\(tag) \(suffix)")
                XCTAssertGreaterThanOrEqual(count("NF-WALLS", "LWPOLYLINE"), floor.rooms.reduce(0) { $0 + $1.walls.filter { $0.kind == .solid }.count })
                let notes = entities.filter { $0.layer == "NF-NOTES" }.compactMap(\.text).joined(separator: " ")
                XCTAssertTrue(notes.contains("Marina Gate 2 - Unit 2304 - \(floor.name)"), "\(tag) \(suffix): the drawing says which level it is")
                XCTAssertTrue(notes.contains("LiDAR dimensions are typically within 1-2 %"), tag)
                XCTAssertTrue(notes.contains("Do not take cutting dimensions from distances measured on"), tag)
                XCTAssertTrue(text.contains("$INSUNITS"), tag)
            }

            // CSV: BOM, CRLF, the unit in the column names, one row per thing.
            let suffixes = ["mm": ("_mm", "_m2"), "cm": ("_cm", "_m2"), "m": ("_m", "_m2"), "in": ("_in", "_sqft"), "ftin": ("_ft", "_sqft")]
            let (lengthSuffix, areaSuffix) = try XCTUnwrap(suffixes[tag])
            let rooms = Self.readCSV(artifact(result, "_rooms.csv").data)
            let walls = Self.readCSV(artifact(result, "_walls.csv").data)
            let openings = Self.readCSV(artifact(result, "_openings.csv").data)
            let objects = Self.readCSV(artifact(result, "_objects.csv").data)
            let customs = Self.readCSV(artifact(result, "_custom-measurements.csv").data)
            for table in [rooms, walls, openings, objects, customs] {
                XCTAssertTrue(table.hasBOM && table.endsWithCRLF, tag)
                XCTAssertTrue(table.rows.allSatisfy { $0.count == table.header.count }, "\(tag): ragged CSV")
            }
            XCTAssertTrue(rooms.header.contains("perimeter" + lengthSuffix), tag)
            XCTAssertTrue(rooms.header.contains("effective_floor_area" + areaSuffix), tag)
            XCTAssertTrue(walls.header.contains("length" + lengthSuffix), tag)
            XCTAssertEqual(rooms.records.count, 7, tag)
            XCTAssertEqual(walls.records.count, property.allRooms.reduce(0) { $0 + $1.walls.count }, tag)
            XCTAssertEqual(openings.records.count, property.allRooms.reduce(0) { $0 + $1.openings.count }, tag)
            XCTAssertEqual(objects.records.count, property.allRooms.reduce(0) { $0 + $1.objects.count }, tag)
            XCTAssertEqual(customs.records.count, 1, tag)
            XCTAssertEqual(rooms.records.map { $0["room"] ?? "" }, property.allRooms.map(\.name), tag)

            json.append(artifact(result, "_scan.json").data)
            spec.append(artifact(result, "_costing-spec.json").data)
        }
        // Units are a presentation choice: the JSON files never change with them.
        XCTAssertEqual(Set(json).count, 1)
        XCTAssertEqual(Set(spec).count, 1)
        XCTAssertEqual(typed.count, 7)
    }

    // MARK: 4. The effective-value rule, in every file

    /// The verified numbers (and not the scanned ones) are what a person reads in each file; geometry stays
    /// what LiDAR drew.
    func testVerifiedNumbersAppearInEveryFileAndGeometryStaysScanned() throws {
        let (before, after, typed, store) = try verifiedProperty()
        let unverifiedExport = try Self.everything(before, units: .default, store: store)
        let exported = try Self.everything(after, units: .default, store: store)

        // --- scan JSON ------------------------------------------------------------------------------------
        let scanBefore = Self.readJSON(artifact(unverifiedExport, "_scan.json").data)
        let scan = Self.readJSON(artifact(exported, "_scan.json").data)
        for check in typed {
            let m = try XCTUnwrap(Self.jsonMeasured(scan, check), "\(check.room) \(check.label)")
            XCTAssertEqual(number(m["scannedM"], "scannedM"), Self.round4(check.scannedM), accuracy: 1e-9)
            XCTAssertEqual(number(m["verifiedM"], "verifiedM"), Self.round4(check.verifiedM), accuracy: 1e-9, "\(check.room) \(check.label)")
            XCTAssertEqual(number(m["valueM"], "valueM"), Self.round4(check.verifiedM), accuracy: 1e-9, "valueM is the verified number")
            XCTAssertEqual(number(m["deviationM"], "deviationM"), check.verifiedM - check.scannedM, accuracy: 1.5e-4)
            XCTAssertEqual(m["source"] as? String, check.source.rawValue)
            XCTAssertEqual(m["verifiedAt"] as? String, "2026-10-12T09:00:00.000Z")
        }
        let kitchenWallCheck = try XCTUnwrap(typed.first { $0.room == "Kitchen" && $0.quantity == .wallLength })
        XCTAssertEqual(Self.jsonMeasured(scan, kitchenWallCheck)?["note"] as? String, "skirting to skirting")

        // Geometry is untouched: every wall and corner of every room is the same before and after.
        let jsonRoomsBefore = (scanBefore["floors"] as? [[String: Any]] ?? []).flatMap { $0["rooms"] as? [[String: Any]] ?? [] }
        let jsonRoomsAfter = (scan["floors"] as? [[String: Any]] ?? []).flatMap { $0["rooms"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(jsonRoomsBefore.count, 7)
        for (b, a) in zip(jsonRoomsBefore, jsonRoomsAfter) {
            let name = a["name"] as? String ?? "?"
            XCTAssertEqual(NSArray(array: a["corners"] as? [Any] ?? []), NSArray(array: b["corners"] as? [Any] ?? []), "\(name): corners")
            let wallsB = (b["walls"] as? [[String: Any]] ?? []).map { [$0["start"] as Any, $0["end"] as Any, $0["kind"] as Any] }
            let wallsA = (a["walls"] as? [[String: Any]] ?? []).map { [$0["start"] as Any, $0["end"] as Any, $0["kind"] as Any] }
            XCTAssertEqual(NSArray(array: wallsA), NSArray(array: wallsB), "\(name): wall coordinates")
            XCTAssertEqual(a["floorAreaM2"] as? NSNumber, b["floorAreaM2"] as? NSNumber, "\(name): outline area")
            XCTAssertEqual(NSArray(array: a["openings"] as? [Any] ?? []).count, NSArray(array: b["openings"] as? [Any] ?? []).count)
        }

        // Derived figures follow the effective walls and say which are blends.
        func sides(_ name: String) throws -> (wall: [Double], scanned: [Double]) {
            let room = try XCTUnwrap(after.allRooms.first { $0.name == name })
            return (room.walls.map { $0.length.value }, room.walls.map { $0.length.scanned })
        }
        for name in ["Kitchen", "Living Room"] {
            let room = try XCTUnwrap(Self.jsonRoom(scan, name))
            let s = try sides(name)
            let pairs = [(s.wall[0] + s.wall[2]) / 2, (s.wall[1] + s.wall[3]) / 2]
            let scannedPairs = [(s.scanned[0] + s.scanned[2]) / 2, (s.scanned[1] + s.scanned[3]) / 2]
            let longIndex = pairs[0] >= pairs[1] ? 0 : 1
            XCTAssertEqual(number(room["lengthM"], "lengthM"), pairs[longIndex], accuracy: 1.5e-4, name)
            XCTAssertEqual(number(room["widthM"], "widthM"), pairs[1 - longIndex], accuracy: 1.5e-4, name)
            XCTAssertEqual(number(room["effectiveFloorAreaM2"], "area"), pairs[0] * pairs[1], accuracy: 2e-3, name)
            XCTAssertEqual(number(room["effectiveFloorAreaScannedM2"], "scanned area"), scannedPairs[0] * scannedPairs[1], accuracy: 2e-3, name)
            XCTAssertEqual(number(room["perimeterM"], "perimeter"), s.wall.reduce(0, +), accuracy: 2e-4, name)
            XCTAssertEqual(number(room["perimeterScannedM"], "scanned perimeter"), s.scanned.reduce(0, +), accuracy: 2e-4, name)
            XCTAssertEqual(room["effectiveFloorAreaVerified"] as? Bool, false, "\(name): width is not verified")
            XCTAssertEqual(room["perimeterVerified"] as? Bool, false, name)
        }
        // Kitchen: one wall of the pair checked, so the length is a blend and is NOT flagged verified.
        XCTAssertEqual(Self.jsonRoom(scan, "Kitchen")?["lengthVerified"] as? Bool, false)
        // Living room: both walls of the long pair checked.
        XCTAssertEqual(Self.jsonRoom(scan, "Living Room")?["lengthVerified"] as? Bool, true)
        XCTAssertEqual(Self.jsonRoom(scan, "Living Room")?["widthVerified"] as? Bool, false)
        // The scan summary and the checks agree.
        let summary = try XCTUnwrap(scan["summary"] as? [String: Any])
        XCTAssertEqual(summary["verifiedCount"] as? Int, 7)
        let readiness = ExportReadiness(property: after)
        XCTAssertEqual(readiness.verified, 7)
        XCTAssertEqual(summary["measurementCount"] as? Int, readiness.total)
        XCTAssertEqual(summary["joineryVerifiedCount"] as? Int, readiness.joineryVerified)
        XCTAssertEqual(summary["joineryMeasurementCount"] as? Int, readiness.joineryTotal)

        // --- CSV -------------------------------------------------------------------------------------------
        let wallsAfter = Self.readCSV(artifact(exported, "_walls.csv").data).records
        let wallsBefore = Self.readCSV(artifact(unverifiedExport, "_walls.csv").data).records
        XCTAssertEqual(wallsAfter.count, wallsBefore.count)
        for (a, b) in zip(wallsAfter, wallsBefore) {
            for column in ["start_x_mm", "start_y_mm", "end_x_mm", "end_y_mm", "length_scanned_mm", "height_mm", "height_scanned_mm"] {
                XCTAssertEqual(a[column], b[column], "\(a["room"] ?? "") \(a["wall"] ?? ""): \(column) changed by verification")
            }
        }
        let openingsAfter = Self.readCSV(artifact(exported, "_openings.csv").data).records
        let roomsAfter = Self.readCSV(artifact(exported, "_rooms.csv").data).records
        let customsAfter = Self.readCSV(artifact(exported, "_custom-measurements.csv").data).records
        func mm(_ metres: Double) -> String { String(format: "%.1f", metres * 1000) }
        for check in typed {
            let row: [String: String]?
            let column: String
            switch check.quantity {
            case .wallLength:
                row = wallsAfter.first { $0["room"] == check.room && $0["wall"] == check.label }; column = "length"
            case .openingWidth:
                row = openingsAfter.first { $0["room"] == check.room && $0["opening"] == check.label }; column = "width"
            case .ceilingHeight:
                row = roomsAfter.first { $0["room"] == check.room }; column = "ceiling_height"
            case .customLength:
                row = customsAfter.first { $0["room"] == check.room && $0["label"] == check.label }; column = "length"
            }
            let r = try XCTUnwrap(row, "\(check.room) \(check.label)")
            XCTAssertEqual(r[column + "_mm"], mm(check.verifiedM), "\(check.room) \(check.label): value to use")
            XCTAssertEqual(r[column + "_scanned_mm"], mm(check.scannedM), "\(check.room) \(check.label): scanned")
            XCTAssertEqual(r[column + "_verified"], "yes")
            XCTAssertEqual(r[column + "_source"], check.source.rawValue)
        }
        // A wall nobody checked says so, and its value is the scan.
        let unchecked = try XCTUnwrap(wallsAfter.first { $0["room"] == "Kitchen 2" })
        XCTAssertEqual(unchecked["length_verified"], "no")
        XCTAssertEqual(unchecked["length_mm"], unchecked["length_scanned_mm"])
        XCTAssertEqual(unchecked["length_source"], "")
        let kitchenRow = try XCTUnwrap(roomsAfter.first { $0["room"] == "Kitchen" })
        XCTAssertEqual(kitchenRow["length_verified"], "no")
        XCTAssertEqual(kitchenRow["effective_floor_area_verified"], "no")
        XCTAssertEqual(roomsAfter.first { $0["room"] == "Living Room" }?["length_verified"], "yes")

        // --- PDF and DXF text, in every unit ---------------------------------------------------------------
        // What each unit must print for the verified numbers: worked out by hand from 3.245 m, 2.76 m, 1.185 m
        // (window, centimetres typed), 6.24 m, 6.236 m and the 8' 10" drawing ceiling (2.6924 m).
        let expected: [String: [String]] = [
            "mm": ["3245 mm v", "Ceiling 2760 mm v", "W 1185v x 1200", "6240 mm v", "6236 mm v", "Ceiling 2692 mm d"],
            "cm": ["324.5 cm v", "Ceiling 276.0 cm v", "W 118.5v x 120", "624.0 cm v", "623.6 cm v", "Ceiling 269.2 cm d"],
            "m": ["3.245 m v", "Ceiling 2.760 m v", "W 1.185v x 1.2", "6.240 m v", "6.236 m v", "Ceiling 2.692 m d"],
            "in": ["127.76 in v", "Ceiling 108.66 in v", "W 46.65v x 47.24", "245.67 in v", "245.51 in v", "Ceiling 106.00 in d"],
            "ftin": ["10' 7 3/4\" v", "Ceiling 9' 0 11/16\" v", "W 46.65v x 47.24", "20' 5 11/16\" v", "20' 5 1/2\" v",
                     "Ceiling 8' 10\" d"],
        ]
        for (tag, units) in Self.unitChoices {
            let result = try Self.everything(after, units: units, store: store)
            let pdf = Set(Self.pdfStrings(artifact(result, ".pdf").data))
            let dxf = Set(Self.readDXF(artifact(result, "plan-Level-23.dxf").data).compactMap(\.text)
                          + Self.readDXF(artifact(result, "plan-Level-23-2.dxf").data).compactMap(\.text))
            for text in try XCTUnwrap(expected[tag]) {
                // The window label is "W 1185v x 1200 H1050 ..." in one string; the others are whole labels.
                let inPDF = pdf.contains { $0 == text || ($0.hasPrefix(text) && text.hasPrefix("W ")) || $0.hasSuffix(" " + text) }
                let inDXF = dxf.contains { $0 == text || ($0.hasPrefix(text) && text.hasPrefix("W ")) }
                XCTAssertTrue(inPDF, "\(tag): the PDF should show \"\(text)\"")
                XCTAssertTrue(inDXF, "\(tag): the DXF should show \"\(text)\"")
            }
        }
        // The verified walls never print their LiDAR number any more (millimetres: 3199 and 6206 / 6198 etc.).
        let result = try Self.everything(after, units: .default, store: store)
        let pdfText = Set(Self.pdfStrings(artifact(result, ".pdf").data))
        let dxfText = Set((Self.readDXF(artifact(result, "plan-Level-23.dxf").data)).compactMap(\.text))
        for check in typed where check.quantity == .wallLength {
            let scannedLabel = String(format: "%.0f mm", check.scannedM * 1000)
            XCTAssertFalse(pdfText.contains(scannedLabel), "PDF still prints the scan \(scannedLabel) for \(check.room) \(check.label)")
            XCTAssertFalse(dxfText.contains(scannedLabel), "DXF still prints the scan \(scannedLabel) for \(check.room) \(check.label)")
        }
        // Wall geometry in the DXF is the scan: identical groups before and after.
        let dxfBefore = Self.readDXF(artifact(unverifiedExport, "plan-Level-23.dxf").data).filter { $0.layer == "NF-WALLS" }
        let dxfAfter = Self.readDXF(artifact(exported, "plan-Level-23.dxf").data).filter { $0.layer == "NF-WALLS" }
        XCTAssertFalse(dxfAfter.isEmpty)
        XCTAssertEqual(dxfAfter.map(\.groups), dxfBefore.map(\.groups), "verification moved a wall in the DXF")
        // The schedule gives the blended length as two numbers, the verified one marked.
        XCTAssertTrue(pdfText.contains { $0.hasPrefix("Kitchen") } )

        // --- costing spec ----------------------------------------------------------------------------------
        let costing = Self.readJSON(artifact(exported, "_costing-spec.json").data)
        let rooms = try XCTUnwrap(costing["rooms"] as? [[String: Any]])
        func costingRoom(_ name: String) throws -> [String: Any] {
            try XCTUnwrap(rooms.first { $0["name"] as? String == name }, name)
        }
        let kitchen = try costingRoom("Kitchen")
        XCTAssertEqual(number(kitchen["height"], "height"), 2.76, accuracy: 1e-9, "the verified ceiling, not the scan")
        let kitchenWindows = try XCTUnwrap(kitchen["windows"] as? [[Double]])
        XCTAssertEqual(kitchenWindows.count, 1)
        XCTAssertEqual(kitchenWindows[0][0], 1.185, accuracy: 1e-9, "the verified window width")
        let kitchenSides = try sides("Kitchen")
        let kitchenPairs = [(kitchenSides.wall[0] + kitchenSides.wall[2]) / 2, (kitchenSides.wall[1] + kitchenSides.wall[3]) / 2]
        XCTAssertEqual(number(kitchen["length"], "length"), max(kitchenPairs[0], kitchenPairs[1]), accuracy: 1.5e-4)
        XCTAssertEqual(number(kitchen["width"], "width"), min(kitchenPairs[0], kitchenPairs[1]), accuracy: 1.5e-4)
        XCTAssertEqual(number(try costingRoom("Living Room")["length"], "living length"), 6.238, accuracy: 1.5e-4)
        XCTAssertEqual(number(try costingRoom("Bedroom")["height"], "bedroom height"), 2.6924, accuracy: 1e-9)
        XCTAssertEqual(number(try costingRoom("Lounge")["height"], "lounge height"),
                       try XCTUnwrap(after.allRooms.first { $0.name == "Lounge" }).ceilingHeight.scanned, accuracy: 1.5e-4,
                       "a room nobody checked keeps its scan")

        let provenance = try XCTUnwrap(costing["x_nexafix_scan"] as? [String: Any])
        XCTAssertEqual(provenance["verified_count"] as? Int, readiness.verified)
        XCTAssertEqual(provenance["measurement_count"] as? Int, readiness.total)
        XCTAssertEqual(provenance["joinery_verified_count"] as? Int, readiness.joineryVerified)
        let listed = (provenance["unverified_joinery"] as? [[String: Any]] ?? [])
        XCTAssertEqual(listed.count, readiness.unverifiedJoinery.count)
        XCTAssertFalse(listed.contains { $0["room"] as? String == "Kitchen" && ($0["item"] as? String == "Ceiling height" || $0["item"] as? String == "Window 1 width" || $0["item"] as? String == kitchenWallCheck.label + " length") },
                       "a dimension that was verified is not listed as unverified")
        XCTAssertTrue(listed.contains { $0["room"] as? String == "Kitchen" && $0["item"] as? String == "Door 1 width" })
        XCTAssertNotNil(provenance["warning"] as? String, "joinery is still LiDAR-only in most rooms")
        let costingRooms = try XCTUnwrap(provenance["rooms"] as? [[String: Any]])
        XCTAssertEqual(costingRooms.first { $0["name"] as? String == "Kitchen" }?["height_verified"] as? Bool, true)
        XCTAssertEqual(costingRooms.first { $0["name"] as? String == "Kitchen" }?["area_verified"] as? Bool, false)
        XCTAssertEqual(costingRooms.first { $0["name"] as? String == "Lounge" }?["height_verified"] as? Bool, false)
    }

    /// Opening a saved reading again and pressing Save must not change it, in any unit the sheet is set to: the
    /// number shown in the field is rounded for display, the number saved is the one that was typed.
    func testReopeningAReadingAndSavingKeepsItsValueAndSource() throws {
        let (_, after, typed, _) = try verifiedProperty()
        for check in typed {
            let room = try XCTUnwrap(after.allRooms.first { $0.name == check.room })
            for choice in Self.unitChoices {
                var model = VerifyModel(room: room, target: check.target, units: choice.units)
                XCTAssertEqual(model.currentVerification?.value, check.verifiedM, "\(check.room) \(check.label)")
                XCTAssertFalse(model.text.isEmpty, "the field shows the saved number")
                XCTAssertEqual(model.check, .ok, "\(check.room) \(check.label) in \(choice.tag): \(model.text)")
                XCTAssertEqual(model.source, check.source, "the saved source is preselected")
                model.note = "checked again"
                let updated = try XCTUnwrap(model.commit(date: Self.exportedAt), "\(check.room) \(check.label) in \(choice.tag)")
                let kept = try XCTUnwrap(updated.measured(check.target)?.verification)
                XCTAssertEqual(kept.value, check.verifiedM, "\(check.room) \(check.label) in \(choice.tag): the value drifted")
                XCTAssertEqual(kept.source, check.source)
                XCTAssertEqual(kept.note, "checked again")
                XCTAssertEqual(updated.measured(check.target)?.scanned, check.scannedM, "the scan is never touched")
            }
            // Cycling the unit through the whole list and back changes nothing either.
            var model = VerifyModel(room: room, target: check.target, units: .default)
            for _ in LengthUnit.allCases { model.cycleUnit() }
            XCTAssertEqual(model.parsedValue, check.verifiedM, "\(check.room) \(check.label): cycling units drifted")
        }
    }

    // MARK: 5. A property whose every dimension was verified

    /// Types a reading for every item of every room's checklist (the scan plus 3 mm, in millimetres).
    private func verifyEverything(_ property: Property, store: PropertyStore) throws -> Property {
        var p = property
        for room in property.allRooms {
            for item in VerificationChecklist(room: room).items {
                guard let current = p.findRoom(room.id) else { return p }
                var model = VerifyModel(room: current, target: item.target, units: DisplayUnits(length: .millimetres))
                model.text = String(format: "%.1f", (item.measured.scanned + 0.003) * 1000)
                XCTAssertEqual(model.check, .ok, "\(room.name) \(item.fullTitle): \(model.text) -> \(String(describing: model.message))")
                if let check = model.verification(date: Self.verifiedAt) {
                    XCTAssertTrue(p.modifyRoom(id: room.id) { $0.setVerification(check, for: item.target) })
                }
            }
        }
        return try store.save(p)
    }

    func testFullyVerifiedPropertyHasNoWarningAndNothingListedAsUnverified() throws {
        let (_, after, _, store) = try verifiedProperty()
        let done = try verifyEverything(after, store: store)
        let readiness = ExportReadiness(property: done)
        XCTAssertGreaterThan(readiness.total, 80)
        XCTAssertEqual(readiness.verified, readiness.total)
        XCTAssertEqual(readiness.joineryVerified, readiness.joineryTotal)
        XCTAssertFalse(readiness.hasUnverifiedJoinery)
        XCTAssertEqual(readiness.banner, "All \(readiness.total) dimensions checked.",
                       "a drawing-sourced check keeps the banner from saying \"with a laser\" or \"on site\"")

        let reloaded = try PropertyStore(rootURL: scratch).load(id: done.id)
        XCTAssertEqual(reloaded, done)
        let result = try Self.everything(reloaded, units: .default, store: store)
        let scan = Self.readJSON(artifact(result, "_scan.json").data)
        let summary = try XCTUnwrap(scan["summary"] as? [String: Any])
        XCTAssertEqual(summary["verifiedCount"] as? Int, summary["measurementCount"] as? Int)
        XCTAssertEqual(summary["joineryVerifiedCount"] as? Int, summary["joineryMeasurementCount"] as? Int)
        let costing = Self.readJSON(artifact(result, "_costing-spec.json").data)
        let provenance = try XCTUnwrap(costing["x_nexafix_scan"] as? [String: Any])
        XCTAssertTrue(provenance["warning"] is NSNull || provenance["warning"] == nil, "no warning when everything was checked")
        XCTAssertEqual((provenance["unverified_joinery"] as? [Any])?.count, 0)
        // Rooms that are rectangles with all four walls checked now say so.
        let kitchen = try XCTUnwrap(Self.jsonRoom(scan, "Kitchen"))
        XCTAssertEqual(kitchen["effectiveFloorAreaVerified"] as? Bool, true)
        XCTAssertEqual(kitchen["perimeterVerified"] as? Bool, true)
        XCTAssertEqual(kitchen["lengthVerified"] as? Bool, true)
        // An L-shape never is: its area comes from scanned corners.
        XCTAssertEqual(Self.jsonRoom(scan, "Lounge")?["effectiveFloorAreaVerified"] as? Bool, false)
    }

    // MARK: 5b. The AR review and the accuracy figure read the same numbers

    /// In AR the verified number is what the label says, in the "verified" colour with who checked it; the
    /// scanned walls keep their scan and its tolerance. The lines drawn do not move.
    func testARReviewLabelsFollowTheVerifiedNumbersAndTheWireframeStaysScanned() throws {
        let (before, after, typed, _) = try verifiedProperty()
        let kitchenCheck = try XCTUnwrap(typed.first { $0.room == "Kitchen" && $0.quantity == .wallLength })
        let windowCheck = try XCTUnwrap(typed.first { $0.room == "Kitchen" && $0.quantity == .openingWidth })
        let ceilingCheck = try XCTUnwrap(typed.first { $0.room == "Kitchen" && $0.quantity == .ceilingHeight })
        let kitchenBefore = try XCTUnwrap(before.allRooms.first { $0.name == "Kitchen" })
        let kitchenAfter = try XCTUnwrap(after.allRooms.first { $0.name == "Kitchen" })
        let sceneBefore = OverlayBuilder.scene(for: [kitchenBefore], options: .review, units: .default)
        let sceneAfter = OverlayBuilder.scene(for: [kitchenAfter], options: .review, units: .default)

        let wallID = try XCTUnwrap(kitchenAfter.walls.first { $0.id == kitchenCheck.target.entityID }).id.uuidString
        let label = try XCTUnwrap(sceneAfter.labels.first { $0.kind == .wallLength && $0.targetID == wallID })
        XCTAssertEqual(label.title, "3245 mm")
        XCTAssertEqual(label.state, .verified)
        XCTAssertEqual(label.subtitle, "Laser")
        let unchanged = try XCTUnwrap(sceneBefore.labels.first { $0.kind == .wallLength && $0.targetID == wallID })
        XCTAssertEqual(unchanged.title, String(format: "%.0f mm", kitchenCheck.scannedM * 1000))
        XCTAssertEqual(unchanged.state, .scanned, "before the check the same wall is a LiDAR number")

        // Every other wall is still the scan: its colour says so and the subtitle gives the tolerance.
        for wall in kitchenAfter.walls where wall.id.uuidString != wallID {
            let other = try XCTUnwrap(sceneAfter.labels.first { $0.kind == .wallLength && $0.targetID == wall.id.uuidString })
            XCTAssertEqual(other.state, .scanned)
            XCTAssertEqual(other.title, String(format: "%.0f mm", wall.length.scanned * 1000))
            XCTAssertTrue(other.subtitle?.hasPrefix("\u{00B1}") ?? false, "a scanned number shows how far it can be out")
        }
        let ceiling = try XCTUnwrap(sceneAfter.labels.first { $0.kind == .ceiling })
        XCTAssertEqual(ceiling.title, "Ceiling 2760 mm")
        XCTAssertEqual(ceiling.state, .verified)
        // The window carries the verified width but its height is still the scan, so it is not shown as verified.
        let window = try XCTUnwrap(sceneAfter.labels.first { $0.kind == .opening && $0.title.hasPrefix("W ") })
        XCTAssertTrue(window.title.hasPrefix("W 1185 x 1200"), window.title)
        XCTAssertEqual(window.state, .scanned)
        XCTAssertEqual(window.subtitle, "Width checked")
        XCTAssertEqual(windowCheck.verifiedM, 1.185)
        XCTAssertEqual(ceilingCheck.verifiedM, 2.76)

        // The lines in the room do not move: same ids, same end points.
        func lines(_ scene: OverlayScene) -> [String] {
            scene.segments.map { "\($0.id) \($0.a.x),\($0.a.y),\($0.a.z) \($0.b.x),\($0.b.y),\($0.b.z)" }
        }
        XCTAssertEqual(lines(sceneAfter), lines(sceneBefore), "verification moved a line in the AR view")
        XCTAssertEqual(sceneAfter.arcs.map { "\($0.id) \($0.sweep)" }, sceneBefore.arcs.map { "\($0.id) \($0.sweep)" })
    }

    /// "How accurate is my phone": the figure the Settings screen shows, worked out again from what was typed.
    func testAccuracyFigureIsWhatTheTypedReadingsSay() throws {
        let (_, after, typed, _) = try verifiedProperty()
        let report = AccuracyReport(property: after)
        XCTAssertEqual(report.sampleCount, 7)
        let errors = typed.map { $0.verifiedM - $0.scannedM }
        XCTAssertEqual(report.meanAbsoluteError, errors.map(abs).reduce(0, +) / 7, accuracy: 1e-12)
        XCTAssertEqual(report.meanSignedError, errors.reduce(0, +) / 7, accuracy: 1e-12)
        XCTAssertEqual(report.maxAbsoluteError, errors.map(abs).max() ?? 0, accuracy: 1e-12)
        // Typed: kitchen wall and ceiling, two living-room walls and the wardrobe by laser; the window by tape.
        XCTAssertEqual(report.sampleCount(for: .laser), 5)
        XCTAssertEqual(report.sampleCount(for: .tape), 1)
        XCTAssertEqual(report.sampleCount(for: .drawing), 1)
        let percent = zip(errors, typed).map { abs($0) / $1.verifiedM * 100 }.reduce(0, +) / 7
        let typical = String(format: "%.0f", errors.map(abs).reduce(0, +) / 7 * 1000)
        let worst = String(format: "%.0f", (errors.map(abs).max() ?? 0) * 1000)
        XCTAssertEqual(report.summary, "7 checks (5 laser, 1 tape, 1 drawing): typically \(typical) mm (\(String(format: "%.1f", percent)) %), worst \(worst) mm")
        // Drawings are not evidence about the phone: the figure for the phone alone leaves them out.
        let measured = AccuracyReport(property: after, sources: AccuracyReport.measuredSources)
        XCTAssertEqual(measured.sampleCount, 6)
    }

    /// The 3D viewer's model of each level: a mesh for every room, finite numbers, valid triangles, standing where
    /// the plan says (world X is plan x, world Z is minus plan y) and as tall as the SCANNED walls, whatever was
    /// typed for the ceiling.
    func testThe3DModelOfEachLevelMatchesThePlan() throws {
        let (_, after, _, _) = try verifiedProperty()
        for floor in after.floors {
            let scene = RoomSceneBuilder.scene(for: floor.rooms)
            XCTAssertFalse(scene.isEmpty, floor.name)
            for mesh in scene.meshes {
                let b = mesh.buffer
                XCTAssertEqual(b.positions.count, b.normals.count, mesh.id)
                XCTAssertTrue(b.positions.allSatisfy { $0.isFinite } && b.normals.allSatisfy { $0.isFinite }, mesh.id)
                XCTAssertTrue(b.indices.allSatisfy { Int($0) < b.vertexCount }, "\(mesh.id) points past its vertices")
                for v in 0..<b.vertexCount {
                    XCTAssertEqual(b.normal(v).length, 1, accuracy: 1e-3, mesh.id)
                }
            }
            for room in floor.rooms {
                let box = try XCTUnwrap(scene.bounds(forRoom: room.id), "\(room.name) has no mesh")
                let xs = room.walls.map(\.start.x), ys = room.walls.map(\.start.y)
                let (minX, maxX, minY, maxY) = (try XCTUnwrap(xs.min()), try XCTUnwrap(xs.max()),
                                                try XCTUnwrap(ys.min()), try XCTUnwrap(ys.max()))
                let slack = 0.3     // wall thickness and frames
                XCTAssertEqual(box.min.x, minX, accuracy: slack, "\(room.name) west")
                XCTAssertEqual(box.max.x, maxX, accuracy: slack, "\(room.name) east")
                XCTAssertEqual(box.min.z, -maxY, accuracy: slack, "\(room.name) north (world -Z)")
                XCTAssertEqual(box.max.z, -minY, accuracy: slack, "\(room.name) south")
                let tallest = room.walls.filter { $0.kind == .solid }.map { $0.height.scanned }.max() ?? 0
                XCTAssertEqual(box.min.y, room.floorElevation, accuracy: 0.02, room.name)
                XCTAssertEqual(box.max.y, room.floorElevation + tallest, accuracy: 0.05, "\(room.name): the model is as tall as the scanned walls")
            }
        }
    }

    // MARK: 6. What the person is told

    /// A name in Arabic is common in Dubai. The PDF's standard fonts cannot print it, so it comes out as "?".
    /// The export has to say so (`PlanPDFRenderer.renderWithReport` produces the sentence), or the person sends
    /// a plan with blanks where the room names should be. The other formats keep the text.
    func testExportSaysWhenThePDFCannotPrintAName() throws {
        let (_, after, _, store) = try verifiedProperty()
        var arabic = after
        arabic.floors[0].rooms[0].name = "\u{063A}\u{0631}\u{0641}\u{0629} \u{0627}\u{0644}\u{0645}\u{0639}\u{064A}\u{0634}\u{0629}"
        let request = ExportRequest(property: arabic, formats: Set(ExportFormat.allCases),
                                    usdzSources: try Self.usdzSources(for: arabic, store: store), now: Self.exportedAt)
        let result = try ExportEngine.runDetailed(request)

        let report = PlanPDFRenderer.renderWithReport(property: arabic, options: ExportEngine.pdfOptions(for: request),
                                                      now: Self.exportedAt)
        XCTAssertEqual(report.warnings.count, 1, "the renderer knows about the room name it cannot print")
        XCTAssertEqual(result.notes, report.warnings, "and the export passes it on to the person")
        XCTAssertTrue(result.notes.first?.contains("cannot print") ?? false)

        // Nothing is lost in the formats that can hold the name.
        XCTAssertTrue(String(decoding: artifact(result, "_scan.json").data, as: UTF8.self).contains(arabic.floors[0].rooms[0].name))
        XCTAssertTrue(String(decoding: artifact(result, "_rooms.csv").data, as: UTF8.self).contains(arabic.floors[0].rooms[0].name))
    }

    /// A plan that is too large for its sheet drops the dimensions it cannot print without overlap. That has to
    /// reach the person too.
    func testExportSaysWhenDimensionsHadToBeLeftOut() throws {
        let hall = Room.rectangle(name: "Hall", width: 60, depth: 40)
        let closet = Room.rectangle(name: "Closet", origin: Point2(61, 0), width: 1.0, depth: 0.8)
        let villa = Property(name: "Villa", floors: [Floor(name: "Ground", level: 0, rooms: [hall, closet])])
        let request = ExportRequest(property: villa, formats: [.planPDF], paper: "a4", now: Self.exportedAt)
        let report = PlanPDFRenderer.renderWithReport(property: villa, options: ExportEngine.pdfOptions(for: request),
                                                      now: Self.exportedAt)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains("left out"), report.warnings[0])
        XCTAssertEqual(try ExportEngine.runDetailed(request).notes, report.warnings)
    }

    /// The date in a file name and in the title block is the Dubai date (UTC+4), not the date in Greenwich.
    func testExportDateIsTheDubaiDate() throws {
        let (_, after, _, store) = try verifiedProperty()
        let lateEvening = Date(timeIntervalSince1970: 1_791_840_600)   // 2026-10-12T21:30:00Z = 13 Oct, 01:30 in Dubai
        let result = try Self.everything(after, units: .default, store: store, now: lateEvening)
        XCTAssertTrue(result.artifacts.allSatisfy { $0.filename.contains("_2026-10-13_") }, "\(result.artifacts.map(\.filename))")
        XCTAssertTrue(Self.pdfStrings(artifact(result, ".pdf").data).contains("13 Oct 2026"))
        let scan = Self.readJSON(artifact(result, "_scan.json").data)
        XCTAssertEqual(scan["generatedAt"] as? String, "2026-10-12T21:30:00.000Z", "inside the file the instant is UTC")
        let costing = Self.readJSON(artifact(result, "_costing-spec.json").data)
        XCTAssertEqual((costing["x_nexafix_scan"] as? [String: Any])?["scan_date"] as? String, "2026-10-12",
                       "the second visit was at 09:30 Dubai time on the 12th")
    }

    /// A level whose model file is missing, or that never had one, is named in the notes; the others still export.
    func testExportNotesALevelWhoseModelIsMissing() throws {
        let (_, after, _, store) = try verifiedProperty()
        var sources = try Self.usdzSources(for: after, store: store)
        sources[Self.floor2ID] = nil        // the property still points at a file the export cannot find
        var result = try ExportEngine.runDetailed(ExportRequest(property: after, formats: [.model3D], usdzSources: sources,
                                                                now: Self.exportedAt))
        XCTAssertEqual(result.artifacts.map(\.filename), ["NexaFix_Marina-Gate-2-Unit-2304_2026-10-12_model-Level-23.usdz"])
        XCTAssertEqual(result.notes, ["The saved 3D model of Level 23 (2) could not be read."])

        var neverScannedWithModel = after
        neverScannedWithModel.floors[1].assets.structureUSDZ = nil
        result = try ExportEngine.runDetailed(ExportRequest(property: neverScannedWithModel, formats: [.model3D],
                                                            usdzSources: sources, now: Self.exportedAt))
        XCTAssertEqual(result.notes, ["Level 23 (2) has no 3D model. Scan the level again to create one."])
    }

    // MARK: 7. The bundle the Python side reads

    /// Everything `tests/test_scan_pipeline.py` reads, by file name under `tests/fixtures/`:
    ///
    /// - `scan_demo_scan.json`: the scan file after the readings were typed in.
    /// - `scan_demo_costing_spec.json`: its costing spec (most joinery still LiDAR-only, so it carries a warning).
    /// - `scan_demo_costing_spec_verified.json`: the same property after EVERY dimension was verified.
    /// - `scan_demo_artifacts.json`: what was typed, and the PDF, DXF and CSV files of each display unit
    ///   (the PDF and USDZ base64, the text files as text).
    private func makeFixtures() throws -> [String: Data] {
        let (_, after, typed, store) = try verifiedProperty()

        var units: [String: Any] = [:]
        var scanJSON = Data(), specJSON = Data()
        for (tag, choice) in Self.unitChoices {
            let result = try Self.everything(after, units: choice, store: store)
            var files: [String: Any] = [:]
            for artifact in result.artifacts {
                switch artifact.formatKind {
                case .dataJSON:
                    scanJSON = artifact.data
                    continue
                case .costingSpec:
                    specJSON = artifact.data
                    continue
                default:
                    break
                }
                // Millimetres (the default) gets every file; the other units get the files whose text changes.
                let name = artifact.filename
                let needed = tag == "mm" || name.hasSuffix(".pdf") || name.hasSuffix("plan-Level-23.dxf")
                    || name.hasSuffix("_rooms.csv") || name.hasSuffix("_walls.csv")
                guard needed else { continue }
                switch artifact.formatKind {
                case .planPDF, .model3D:
                    files[name] = ["encoding": "base64", "data": artifact.data.base64EncodedString()]
                default:
                    files[name] = ["encoding": "utf-8", "data": String(decoding: artifact.data, as: UTF8.self)]
                }
            }
            units[tag] = ["length": choice.length.rawValue, "area": choice.area.rawValue, "files": files]
        }

        let bundle: [String: Any] = [
            "schema": "nexafix.e2e-artifacts",
            "version": 1,
            "generatedBy": "EndToEndTests.testWriteFixturesWhenRequested in ios/NexaFixCore",
            "exportedAt": "2026-10-12T10:00:00Z",
            "property": ["name": after.name, "client": after.client, "reference": after.reference,
                         "floors": after.floors.map { ["name": $0.name, "rooms": $0.rooms.map(\.name)] as [String: Any] }],
            "typed": typed.map { check -> [String: Any] in
                ["floor": check.floor, "room": check.room, "label": check.label,
                 "quantity": String(describing: check.quantity), "typed": check.typed, "unit": check.unit.rawValue,
                 "source": check.source.rawValue, "scannedM": Self.round4(check.scannedM),
                 "verifiedM": Self.round4(check.verifiedM)]
            },
            "units": units,
        ]
        let bundleData = try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys, .withoutEscapingSlashes])

        let everything = try verifyEverything(after, store: store)
        let verifiedSpec = try CostingSpecExport.json(property: everything)
        return ["scan_demo_scan.json": scanJSON,
                "scan_demo_costing_spec.json": specJSON,
                "scan_demo_costing_spec_verified.json": verifiedSpec,
                "scan_demo_artifacts.json": bundleData]
    }

    /// Deep equality of two parsed JSON values (numbers compare as numbers, so 2 equals 2.0).
    static func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            return x.count == y.count && x.allSatisfy { key, value in y[key].map { jsonEqual(value, $0) } ?? false }
        case let (x as [Any], y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy { jsonEqual($0, $1) }
        case (is NSNull, is NSNull):
            return true
        case let (x as String, y as String):
            return x == y
        case let (x as NSNumber, y as NSNumber):
            return x.doubleValue == y.doubleValue
        default:
            return false
        }
    }

    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)           // .../ios/NexaFixCore/Tests/NexaFixCoreTests/EndToEndTests.swift
        for _ in 0..<5 { root.deleteLastPathComponent() }    // -> repository root
        return root
    }

    /// With NEXAFIX_FIXTURE_DIR set, writes the files the Python pipeline test reads:
    ///   NEXAFIX_FIXTURE_DIR=../../tests/fixtures swift test --filter EndToEndTests/testWriteFixturesWhenRequested
    func testWriteFixturesWhenRequested() throws {
        let made = try makeFixtures()
        XCTAssertEqual(made.keys.sorted(), ["scan_demo_artifacts.json", "scan_demo_costing_spec.json",
                                            "scan_demo_costing_spec_verified.json", "scan_demo_scan.json"])
        XCTAssertTrue(made.values.allSatisfy { !$0.isEmpty })
        guard let dir = ProcessInfo.processInfo.environment["NEXAFIX_FIXTURE_DIR"], !dir.isEmpty else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (name, data) in made { try data.write(to: base.appendingPathComponent(name)) }
    }

    /// The Python tests read `tests/fixtures/scan_demo_*.json`. They must be what the code produces today, or those
    /// tests would be checking an old format. Compared as data, not bytes: JSONEncoder spaces empty arrays
    /// differently on Linux and Apple platforms.
    func testCommittedFixturesMatchTheCurrentCode() throws {
        let folder = repositoryRoot().appendingPathComponent("tests/fixtures")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("scan_demo_scan.json").path) else {
            throw XCTSkip("no tests/fixtures/scan_demo_*.json next to this checkout")
        }
        let made = try makeFixtures()
        for (name, fresh) in made.sorted(by: { $0.key < $1.key }) {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                XCTFail("tests/fixtures/\(name) is missing: regenerate with NEXAFIX_FIXTURE_DIR (see testWriteFixturesWhenRequested)")
                continue
            }
            let committed = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            let current = try JSONSerialization.jsonObject(with: fresh)
            if !Self.jsonEqual(committed, current) {
                XCTFail("tests/fixtures/\(name) is stale: regenerate with NEXAFIX_FIXTURE_DIR (see testWriteFixturesWhenRequested)")
            }
        }
    }
}
