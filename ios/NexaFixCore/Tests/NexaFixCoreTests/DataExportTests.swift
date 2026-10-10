import XCTest
@testable import NexaFixCore

/// Tests for the data exports: scan JSON, CSV, costing spec and file naming.
///
/// Expected numbers are worked out by hand in the comments (and cross-checked with a separate
/// script), not read back from the code under test.
final class DataExportTests: XCTestCase {

    // MARK: Fixtures

    /// Deterministic ids: 00000000-0000-0000-0000-00000000000N.
    static func id(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-" + padded) ?? UUID()
    }

    static let generatedAt = Date(timeIntervalSince1970: 1_791_540_000)      // 2026-10-09T10:00:00Z
    static let verifiedAt = Date(timeIntervalSince1970: 1_791_451_800)       // 2026-10-08T09:30:00Z
    static let scanDay1 = Date(timeIntervalSince1970: 1_791_360_900)         // 2026-10-07T08:15:00Z
    static let scanDay2 = Date(timeIntervalSince1970: 1_791_536_400)         // 2026-10-09T09:00:00Z

    /// Replace the random ids `Room.polygon` makes with fixed ones, keeping opening -> wall links.
    static func fixedIDs(_ room: Room, base: Int, scannedAt: Date) -> Room {
        var r = room
        var map: [UUID: UUID] = [:]
        for i in r.walls.indices {
            let new = id(base + 1 + i)
            map[r.walls[i].id] = new
            r.walls[i].id = new
        }
        for i in r.openings.indices {
            r.openings[i].id = id(base + 50 + i)
            if let w = r.openings[i].wallID { r.openings[i].wallID = map[w] }
        }
        r.scannedAt = scannedAt
        return r
    }

    /// Four rooms on one floor:
    ///  - Living Room 6.2 x 4.5 (rectangle), wall A and wall C length, ceiling and door width verified.
    ///  - Master Bathroom 2.4 x 2.1 (wet), nothing verified.
    ///  - Balcony 4.0 x 1.6 (outdoor) with a sliding door.
    ///  - Open Plan: an L-shape, 20 m2, kind .other.
    static func marina() -> Property {
        var living = fixedIDs(
            Room.rectangle(name: "Living Room", kind: .livingRoom, width: 6.2, depth: 4.5, ceilingHeight: 2.8,
                           openings: [.door(wall: 0, offset: 0.5),
                                      .window(wall: 2, offset: 1.0, width: 3.0, height: 2.4, sill: 0)],
                           id: id(0x10)),
            base: 0x100, scannedAt: scanDay1)
        living.walls[0].length.verify(6.24, source: .laser, note: "tape on skirting", date: verifiedAt)
        living.walls[2].length.verify(6.24, source: .laser, date: verifiedAt)
        living.ceilingHeight.verify(2.85, source: .laser, date: verifiedAt)
        living.openings[0].width.verify(0.92, source: .tape, date: verifiedAt)

        let bath = fixedIDs(
            Room.rectangle(name: "Master Bathroom", kind: .bathroom, width: 2.4, depth: 2.1, ceilingHeight: 2.6,
                           openings: [.door(wall: 3, offset: 0.6, width: 0.8)], id: id(0x20)),
            base: 0x200, scannedAt: scanDay1)

        var balcony = fixedIDs(
            Room.rectangle(name: "Balcony", kind: .balcony, width: 4.0, depth: 1.6, ceilingHeight: 2.8,
                           openings: [OpeningSpec(wall: 0, kind: .door, offset: 0.8, width: 2.4, height: 2.2)],
                           id: id(0x30)),
            base: 0x300, scannedAt: scanDay2)
        balcony.objects = [RoomObject(id: id(0x31), kind: .chair, center: Point2(1.0, 0.8), yaw: -.pi / 2,
                                      width: 0.5, depth: 0.5, height: 0.9, elevation: 0)]

        var openPlan = fixedIDs(
            Room.polygon(name: "Open Plan", kind: .other,
                         corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)],
                         ceilingHeight: 2.8, id: id(0x40)),
            base: 0x400, scannedAt: scanDay1)
        openPlan.customMeasurements = [
            CustomMeasurement(id: id(0x41), label: "Wardrobe wall", a: Point3(0, 0, 0), b: Point3(3, 0, 4),
                              createdAt: scanDay1, note: nil)
        ]

        let floor = Floor(id: id(2), name: "Level 23", level: 23, rooms: [living, bath, balcony, openPlan],
                          assets: FloorAssets(structureUSDZ: "floors/level23.usdz", worldMap: nil))
        return Property(id: id(1), name: "Marina Gate 2304", client: "Mr. Ahmed Khan", address: "Dubai Marina, Dubai",
                        reference: "NF-2026-1009-01", kind: .apartment, notes: "Tower B, unit 2304",
                        createdAt: scanDay1, updatedAt: scanDay2, floors: [floor])
    }

    static func jsonObject(_ data: Data) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(any as? [String: Any])
    }

    /// Minimal RFC 4180 reader, independent of the exporter. Strips a leading BOM.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
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
        return rows
    }

    /// Rows as dictionaries keyed by header name.
    static func table(_ csv: String) -> [[String: String]] {
        let rows = parseCSV(csv)
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { cells in
            var d: [String: String] = [:]
            for (i, h) in header.enumerated() where i < cells.count { d[h] = cells[i] }
            return d
        }
    }

    // MARK: - ExportNaming

    func testFileNameFollowsThePattern() {
        let name = ExportNaming.fileName(propertyName: "Marina Gate 2304", date: Self.generatedAt,
                                         kind: "scan", ext: "json")
        XCTAssertEqual(name, "NexaFix_Marina-Gate-2304_2026-10-09_scan.json")
        XCTAssertEqual(ExportNaming.fileName(for: Self.marina(), date: Self.generatedAt, kind: "costing-spec", ext: ".JSON"),
                       "NexaFix_Marina-Gate-2304_2026-10-09_costing-spec.json")
        XCTAssertEqual(ExportNaming.baseName(propertyName: "Villa 7", date: Self.generatedAt),
                       "NexaFix_Villa-7_2026-10-09")
    }

    func testDateStampUsesDubaiTimeAndHandlesBoundaries() {
        // 2026-10-09 21:00 UTC is already the 10th in Dubai (UTC+4).
        let lateEvening = Date(timeIntervalSince1970: 1_791_579_600)
        XCTAssertEqual(ExportNaming.dateStamp(lateEvening), "2026-10-10")
        XCTAssertEqual(ExportNaming.dateStamp(lateEvening, timeZone: TimeZone.gmt), "2026-10-09")
        XCTAssertEqual(ExportNaming.dateStamp(lateEvening, timeZone: TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt),
                       "2026-10-09")
        // Before 1970 (negative epoch): 1969-12-31 23:00 UTC is 1970-01-01 03:00 in Dubai.
        let beforeEpoch = Date(timeIntervalSince1970: -3600)
        XCTAssertEqual(ExportNaming.dateStamp(beforeEpoch, timeZone: TimeZone.gmt), "1969-12-31")
        XCTAssertEqual(ExportNaming.dateStamp(beforeEpoch), "1970-01-01")
        // Leap day, and year end in Dubai.
        XCTAssertEqual(ExportNaming.dateStamp(Date(timeIntervalSince1970: 1_709_164_800), timeZone: TimeZone.gmt),
                       "2024-02-29")
        XCTAssertEqual(ExportNaming.dateStamp(Date(timeIntervalSince1970: 1_709_240_400)), "2024-03-01")   // 21:00Z on 29 Feb
        XCTAssertEqual(ExportNaming.dateStamp(Date(timeIntervalSince1970: 1_767_211_200)), "2026-01-01")   // 20:00Z on 31 Dec
        XCTAssertEqual(ExportNaming.dateStamp(Date(timeIntervalSince1970: -2_203_891_200), timeZone: TimeZone.gmt),
                       "1900-03-01")
    }

    func testSanitizingUnsafeCharacters() {
        let s = ExportNaming.sanitizedComponent
        XCTAssertEqual(s("Villa 12/B: \"Palm\" \u{1F334}\u{1F3E0}", 40, "x"), "Villa-12-B-Palm")
        XCTAssertEqual(s("../../etc/passwd", 40, "x"), "etc-passwd")
        XCTAssertEqual(s("C:\\Users\\me\\file.txt", 40, "x"), "C-Users-me-file-txt")
        XCTAssertEqual(s("  spaced   out  ", 40, "x"), "spaced-out")
        XCTAssertEqual(s("Maid's Room", 40, "x"), "Maids-Room")
        XCTAssertEqual(s("Maid\u{2019}s Room", 40, "x"), "Maids-Room")
        XCTAssertEqual(s("Smith & Sons", 40, "x"), "Smith-and-Sons")
        XCTAssertEqual(s("tab\tnew\nline\u{0}nul", 40, "x"), "tab-new-line-nul")
        XCTAssertEqual(s("my_file.v2", 40, "x"), "my-file-v2")
    }

    func testSanitizingTransliteratesAccents() {
        let s = ExportNaming.sanitizedComponent
        XCTAssertEqual(s("Caf\u{00E9} M\u{00FC}ller", 40, "x"), "Cafe-Muller")
        XCTAssertEqual(s("Stra\u{00DF}e", 40, "x"), "Strasse")
        XCTAssertEqual(s("\u{00D8}rsted & S\u{00F8}n", 40, "x"), "Orsted-and-Son")
        XCTAssertEqual(s("\u{0141}\u{00F3}d\u{017A}", 40, "x"), "Lodz")
        // Decomposed input (e + combining acute) gives the same answer as precomposed.
        XCTAssertEqual(s("Cafe\u{0301}", 40, "x"), "Cafe")
    }

    func testSanitizingEmptyAndUnrepresentableNamesUseTheFallback() {
        XCTAssertEqual(ExportNaming.sanitizedComponent("", fallback: "Property"), "Property")
        XCTAssertEqual(ExportNaming.sanitizedComponent("   \t\n", fallback: "Property"), "Property")
        XCTAssertEqual(ExportNaming.sanitizedComponent("\u{1F600}\u{1F680}", fallback: "Property"), "Property")
        XCTAssertEqual(ExportNaming.sanitizedComponent("\u{0645}\u{0646}\u{0632}\u{0644}", fallback: "Property"), "Property")
        XCTAssertEqual(ExportNaming.sanitizedComponent("---", fallback: "Property"), "Property")
        let name = ExportNaming.fileName(propertyName: "", date: Self.generatedAt, kind: "", ext: "")
        XCTAssertEqual(name, "NexaFix_Property_2026-10-09_export.dat")
        // Mixed text keeps the part that can be represented.
        XCTAssertEqual(ExportNaming.sanitizedComponent("Villa \u{0641}\u{064A}\u{0644}\u{0627} 7", fallback: "x"), "Villa-7")
    }

    func testLongNamesAreTruncatedCleanly() {
        let long = String(repeating: "Palm Jumeirah Signature Villa ", count: 20)
        let s = ExportNaming.sanitizedComponent(long)
        XCTAssertLessThanOrEqual(s.count, ExportNaming.defaultMaxComponentLength)
        XCTAssertFalse(s.hasSuffix("-"))
        XCTAssertTrue(s.hasPrefix("Palm-Jumeirah-Signature-Villa"))
        XCTAssertEqual(ExportNaming.sanitizedComponent("abcdef-ghij", maxLength: 7, fallback: "x"), "abcdef")   // cut at the dash, not "abcdef-"
        let name = ExportNaming.fileName(propertyName: long, date: Self.generatedAt, kind: "scan", ext: "json")
        XCTAssertLessThan(name.utf8.count, 100)
        // One huge unbroken name.
        XCTAssertEqual(ExportNaming.sanitizedComponent(String(repeating: "a", count: 5000)).count, 40)
    }

    func testEveryNameIsFilesystemSafe() {
        let nasty = ["", " ", ".", "..", "...", "/", "\\", "a/b", "a\\b", "con", "NUL", "A:B", "a*b?c", "<x>|\"y\"",
                     "\u{1F4A9}", "a\u{200B}b", "\u{202E}gnp.exe", "~", "$HOME", "%00", "-rf", "--version",
                     "name.", "name ", "\u{FEFF}bom", "line1\r\nline2", String(repeating: "\u{00E9}", count: 300)]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        for raw in nasty {
            let name = ExportNaming.fileName(propertyName: raw, date: Self.generatedAt, kind: raw, ext: raw)
            XCTAssertTrue(name.unicodeScalars.allSatisfy(allowed.contains), "unsafe characters in \(name)")
            XCTAssertTrue(name.hasPrefix("NexaFix_"), name)
            XCTAssertFalse(name.contains(".."), name)
            XCTAssertFalse(name.hasPrefix("."), name)
            XCTAssertFalse(name.hasSuffix("."), name)
            XCTAssertLessThan(name.utf8.count, 255)
        }
    }

    func testNamingIsDeterministic() {
        let a = ExportNaming.fileName(propertyName: "Marina Gate", date: Self.generatedAt, kind: "scan", ext: "json")
        let b = ExportNaming.fileName(propertyName: "Marina Gate", date: Self.generatedAt, kind: "scan", ext: "json")
        XCTAssertEqual(a, b)
        XCTAssertEqual(ExportNaming.extensionToken(".PDF"), "pdf")
        XCTAssertEqual(ExportNaming.extensionToken("tar.gz"), "targz")
        XCTAssertEqual(ExportNaming.extensionToken("\u{1F600}"), "dat")
    }

    func testCollisionHelper() {
        let name = "NexaFix_Villa_2026-10-09_scan.json"
        XCTAssertEqual(ExportNaming.uniqueName(name, existing: []), name)
        XCTAssertEqual(ExportNaming.uniqueName(name, existing: [name]), "NexaFix_Villa_2026-10-09_scan-2.json")
        XCTAssertEqual(ExportNaming.uniqueName(name, existing: [name, "NexaFix_Villa_2026-10-09_scan-2.json"]),
                       "NexaFix_Villa_2026-10-09_scan-3.json")
        // File systems on iOS / macOS / Windows ignore case.
        XCTAssertEqual(ExportNaming.uniqueName("A.pdf", existing: ["a.PDF"]), "A-2.pdf")
        // No extension, dotfile, multiple dots.
        XCTAssertEqual(ExportNaming.uniqueName("notes", existing: ["notes"]), "notes-2")
        XCTAssertEqual(ExportNaming.uniqueName(".hidden", existing: [".hidden"]), ".hidden-2")
        XCTAssertEqual(ExportNaming.uniqueName("a.b.csv", existing: ["a.b.csv"]), "a.b-2.csv")
        // A long run of collisions still terminates with the first free number.
        var taken: Set<String> = ["x.pdf"]
        for n in 2...50 { taken.insert("x-\(n).pdf") }
        XCTAssertEqual(ExportNaming.uniqueName("x.pdf", existing: taken), "x-51.pdf")
    }

    func testCollisionHelperAgainstADirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NexaFixNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(ExportNaming.uniqueName("a.csv", in: dir), "a.csv")
        try Data().write(to: dir.appendingPathComponent("a.csv"))
        XCTAssertEqual(ExportNaming.uniqueName("a.csv", in: dir), "a-2.csv")
        XCTAssertEqual(ExportNaming.uniqueName("a.csv", in: dir.appendingPathComponent("missing")), "a.csv")
    }

    // MARK: - Dates

    func testISO8601KnownValues() {
        // 1_700_000_000 is the well-known 2023-11-14T22:13:20Z.
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: 1_700_000_000)), "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Self.generatedAt), "2026-10-09T10:00:00.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: 1_700_000_000.4996)), "2023-11-14T22:13:20.500Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: 1_700_000_000.9996)), "2023-11-14T22:13:21.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: 4_133_980_799)), "2100-12-31T23:59:59.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: -2_203_891_200)), "1900-03-01T00:00:00.000Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSince1970: -0.5)), "1969-12-31T23:59:59.500Z")
        XCTAssertEqual(DataDates.iso8601Millis(Date(timeIntervalSinceReferenceDate: .nan)), "1970-01-01T00:00:00.000Z")
    }

    func testISO8601ParsingAcceptsOffsetsAndRejectsGarbage() throws {
        let utc = try XCTUnwrap(DataDates.parse("2026-10-09T10:00:00Z"))
        XCTAssertEqual(utc.timeIntervalSince1970, 1_791_540_000)
        XCTAssertEqual(DataDates.parse("2026-10-09T14:00:00+04:00"), utc)
        XCTAssertEqual(DataDates.parse("2026-10-09T14:00:00+0400"), utc)
        XCTAssertEqual(DataDates.parse("2026-10-09T05:30:00-04:30"), utc)
        XCTAssertEqual(DataDates.parse("2026-10-09t10:00:00z"), utc)
        XCTAssertEqual(try XCTUnwrap(DataDates.parse("2026-10-09T10:00:00.5Z")).timeIntervalSince1970, 1_791_540_000.5)
        XCTAssertEqual(try XCTUnwrap(DataDates.parse("2026-10-09T10:00:00.250000Z")).timeIntervalSince1970,
                       1_791_540_000.25)
        for bad in ["", "2026-10-09", "2026-10-09T10:00:00", "2026-10-09 10:00:00Z", "2026-13-01T00:00:00Z",
                    "2026-00-10T00:00:00Z", "2026-10-00T00:00:00Z", "2026-02-30T00:00:00Z", "2023-02-29T00:00:00Z",
                    "2100-02-29T00:00:00Z", "2026-10-09T24:00:00Z", "2026-10-09T10:60:00Z", "2026-10-09T10:00:60Z",
                    "2026-10-09T10:00:00.Z", "2026-10-09T10:00:00Zjunk", "0000-01-01T00:00:00Z", "26-10-09T10:00:00Z",
                    "2026-10-09T10:00:00+25:00", "not a date"] {
            XCTAssertNil(DataDates.parse(bad), bad)
        }
        XCTAssertNotNil(DataDates.parse("2024-02-29T00:00:00Z"))
        XCTAssertNotNil(DataDates.parse("2000-02-29T00:00:00Z"))
    }

    func testExactISO8601SurvivesARoundTripBitForBit() {
        var rng = DataTestsSplitMix64(seed: 0xC0FFEE)
        var checked = 0
        for _ in 0..<5000 {
            // 1991 ... 2127, any sub-microsecond noise a real Date() can carry.
            let seconds = Double.random(in: -300_000_000...4_000_000_000, using: &rng)
            let date = Date(timeIntervalSinceReferenceDate: seconds)
            let text = DataDates.iso8601Exact(date)
            XCTAssertEqual(DataDates.parse(text)?.timeIntervalSinceReferenceDate, seconds, text)
            checked += 1
        }
        XCTAssertEqual(checked, 5000)
        // Hand-picked: whole seconds are short, a carry into the next second still round-trips.
        XCTAssertEqual(DataDates.iso8601Exact(Self.generatedAt), "2026-10-09T10:00:00.000Z")
        let nearlyNextSecond = Date(timeIntervalSinceReferenceDate: 721_692_800 + (1 - 1.0 / 8_388_608))
        XCTAssertEqual(DataDates.parse(DataDates.iso8601Exact(nearlyNextSecond)), nearlyNextSecond)
        let half = Date(timeIntervalSince1970: 1_700_000_000.5)
        XCTAssertEqual(DataDates.iso8601Exact(half), "2023-11-14T22:13:20.500Z")
        XCTAssertEqual(DataDates.parse("2023-11-14T22:13:20.500Z"), half)
    }

    func testCalendarArithmeticRoundTrips() {
        // Every day from 1900 to 2200 converts to a civil date and back, one day at a time.
        let first = DataDates.daysFromCivil(year: 1900, month: 1, day: 1)
        let last = DataDates.daysFromCivil(year: 2200, month: 12, day: 31)
        var previous = DataDates.civilFromDays(first)
        XCTAssertEqual(previous.year, 1900)
        XCTAssertEqual(previous.month, 1)
        XCTAssertEqual(previous.day, 1)
        var failures = 0
        for days in (first + 1)...last {
            let c = DataDates.civilFromDays(days)
            if DataDates.daysFromCivil(year: c.year, month: c.month, day: c.day) != days { failures += 1 }
            if c.day < 1 || c.day > DataDates.daysInMonth(year: c.year, month: c.month) { failures += 1 }
            // The day number rises by one or wraps to 1; the month then rises by one or wraps to 1.
            if !(c.day == previous.day + 1 || c.day == 1) { failures += 1 }
            if c.day == 1, !(c.month == previous.month % 12 + 1) { failures += 1 }
            previous = c
        }
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(previous.year, 2200)
        XCTAssertEqual(DataDates.daysFromCivil(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(DataDates.daysFromCivil(year: 2000, month: 3, day: 1) - DataDates.daysFromCivil(year: 2000, month: 2, day: 28), 2)
        XCTAssertEqual(DataDates.daysFromCivil(year: 1900, month: 3, day: 1) - DataDates.daysFromCivil(year: 1900, month: 2, day: 28), 1)
        XCTAssertEqual(DataDates.floorDiv(-1, 86_400), -1)
        XCTAssertEqual(DataDates.floorDiv(-86_400, 86_400), -1)
        XCTAssertEqual(DataDates.floorDiv(-86_401, 86_400), -2)
        XCTAssertEqual(DataDates.floorDiv(86_399, 86_400), 0)
    }

    // MARK: - ScanExport: header, summary, hand-checked numbers

    func testTopLevelShape() throws {
        let data = try ScanExport.json(property: Self.marina(), generatedAt: Self.generatedAt)
        let root = try Self.jsonObject(data)
        XCTAssertEqual(Set(root.keys), ["schema", "version", "generatedAt", "generator", "units", "property", "summary", "floors"])
        XCTAssertEqual(root["schema"] as? String, "nexafix.scan")
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(root["generatedAt"] as? String, "2026-10-09T10:00:00.000Z")
        XCTAssertEqual(root["generator"] as? String, "NexaFix Scan")
        let units = try XCTUnwrap(root["units"] as? [String: Any])
        XCTAssertEqual(units["storage"] as? String, "metres")
        XCTAssertEqual(units["angles"] as? String, "degrees")
        XCTAssertTrue((units["coordinates"] as? String ?? "").contains("x east, y north"))

        let property = try XCTUnwrap(root["property"] as? [String: Any])
        XCTAssertEqual(Set(property.keys), ["id", "name", "client", "address", "reference", "kind", "notes", "createdAt", "updatedAt"])
        XCTAssertEqual(property["id"] as? String, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(property["name"] as? String, "Marina Gate 2304")
        XCTAssertEqual(property["client"] as? String, "Mr. Ahmed Khan")
        XCTAssertEqual(property["reference"] as? String, "NF-2026-1009-01")
        XCTAssertEqual(property["kind"] as? String, "apartment")
        XCTAssertEqual(property["createdAt"] as? String, "2026-10-07T08:15:00.000Z")
        XCTAssertEqual(property["updatedAt"] as? String, "2026-10-09T09:00:00.000Z")

        let floors = try XCTUnwrap(root["floors"] as? [[String: Any]])
        XCTAssertEqual(floors.count, 1)
        XCTAssertEqual(floors[0]["name"] as? String, "Level 23")
        XCTAssertEqual(floors[0]["level"] as? Int, 23)
        XCTAssertEqual((floors[0]["rooms"] as? [[String: Any]])?.count, 4)
        let assets = try XCTUnwrap(floors[0]["assets"] as? [String: Any])
        XCTAssertEqual(assets["structureUSDZ"] as? String, "floors/level23.usdz")
        XCTAssertTrue(assets["worldMap"] is NSNull)
    }

    func testSummaryNumbers() {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        XCTAssertEqual(file.summary.roomCount, 4)
        XCTAssertEqual(file.summary.floorCount, 1)
        // Effective areas: Living 6.24 x 4.5 = 28.08, Bathroom 2.4 x 2.1 = 5.04, Balcony 4.0 x 1.6 = 6.4, L-shape 20.
        XCTAssertEqual(file.summary.totalFloorAreaM2, 28.08 + 5.04 + 6.4 + 20, accuracy: 1e-9)
        XCTAssertEqual(file.summary.indoorFloorAreaM2, 28.08 + 5.04 + 20, accuracy: 1e-9)

        // Checkable dimensions per room (see the checklist rules in DataMeasureList):
        //  Living: 4 wall lengths + 4 wall heights + ceiling + door w,h + window w,h = 13 (no sills: all 0), joinery 9.
        //  Bathroom: 4 + 4 + 1 + door w,h = 11, joinery 7.   Balcony: same as bathroom = 11, joinery 7.
        //  Open Plan: 6 + 6 + 1 + 1 custom = 14, joinery 6 lengths + ceiling + custom = 8.
        XCTAssertEqual(file.summary.measurementCount, 13 + 11 + 11 + 14)
        XCTAssertEqual(file.summary.joineryMeasurementCount, 9 + 7 + 7 + 8)
        // Verified: Living has wall A, wall C, ceiling, door width = 4 (all joinery).
        XCTAssertEqual(file.summary.verifiedCount, 4)
        XCTAssertEqual(file.summary.joineryVerifiedCount, 4)

        let perRoom = file.floors.flatMap(\.rooms).map(\.verification)
        XCTAssertEqual(perRoom.map(\.total), [13, 11, 11, 14])
        XCTAssertEqual(perRoom.map(\.verified), [4, 0, 0, 0])
        XCTAssertEqual(perRoom.reduce(0) { $0 + $1.total }, file.summary.measurementCount)
        XCTAssertEqual(perRoom.reduce(0) { $0 + $1.joineryTotal }, file.summary.joineryMeasurementCount)
    }

    func testLivingRoomNumbersAreHandComputed() throws {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let living = file.floors[0].rooms[0]
        XCTAssertEqual(living.name, "Living Room")
        XCTAssertEqual(living.kind, "livingRoom")
        XCTAssertEqual(living.floorAreaM2, 27.9, accuracy: 1e-9)                 // 6.2 x 4.5 scanned outline
        XCTAssertEqual(living.effectiveFloorAreaM2, 28.08, accuracy: 1e-9)       // 6.24 x 4.5 verified sides
        XCTAssertEqual(living.perimeterM, 6.24 + 4.5 + 6.24 + 4.5, accuracy: 1e-9)
        XCTAssertEqual(living.wallPerimeterM, 21.48, accuracy: 1e-9)
        XCTAssertTrue(living.isRectangular)
        XCTAssertEqual(try XCTUnwrap(living.lengthM), 6.24, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(living.widthM), 4.5, accuracy: 1e-9)
        XCTAssertEqual(living.volumeM3, 27.9 * 2.85, accuracy: 1e-9)             // outline area x effective ceiling = 79.515
        XCTAssertEqual(living.grossWallAreaM2, 21.48 * 2.8, accuracy: 1e-9)      // 60.144; wall heights are not verified
        XCTAssertEqual(living.openingAreaM2, 0.92 * 2.1 + 3.0 * 2.4, accuracy: 1e-9)   // 1.932 + 7.2 = 9.132
        XCTAssertEqual(living.netWallAreaM2, 60.144 - 9.132, accuracy: 1e-9)     // 51.012
        XCTAssertEqual(living.scannedAt, "2026-10-07T08:15:00.000Z")
        XCTAssertEqual(living.id, "00000000-0000-0000-0000-000000000010")
    }

    func testMeasuredObjectCarriesBothNumbers() throws {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let living = file.floors[0].rooms[0]

        let ceiling = living.ceilingHeight
        XCTAssertEqual(ceiling.scannedM, 2.8)
        XCTAssertEqual(ceiling.verifiedM, 2.85)
        XCTAssertEqual(ceiling.valueM, 2.85)
        XCTAssertEqual(ceiling.source, "laser")
        XCTAssertEqual(ceiling.verifiedAt, "2026-10-08T09:30:00.000Z")
        XCTAssertNil(ceiling.note)
        XCTAssertEqual(try XCTUnwrap(ceiling.deviationM), 0.05, accuracy: 1e-12)
        XCTAssertTrue(ceiling.isVerified)

        let wallA = living.walls[0].length
        XCTAssertEqual(wallA.scannedM, 6.2)
        XCTAssertEqual(wallA.valueM, 6.24)
        XCTAssertEqual(wallA.note, "tape on skirting")
        XCTAssertEqual(try XCTUnwrap(wallA.deviationM), 0.04, accuracy: 1e-12)

        let wallB = living.walls[1].length          // never verified
        XCTAssertEqual(wallB.scannedM, 4.5)
        XCTAssertEqual(wallB.valueM, 4.5)
        XCTAssertNil(wallB.verifiedM)
        XCTAssertNil(wallB.source)
        XCTAssertNil(wallB.verifiedAt)
        XCTAssertNil(wallB.deviationM)
        XCTAssertFalse(wallB.isVerified)

        let door = living.openings.first { $0.kind == "door" }
        XCTAssertEqual(door?.width.source, "tape")
        XCTAssertEqual(door?.width.valueM, 0.92)
        XCTAssertEqual(door?.width.scannedM, 0.9)
    }

    func testOptionalFieldsAreWrittenAsExplicitNulls() throws {
        let data = try ScanExport.json(property: Self.marina(), generatedAt: Self.generatedAt)
        let root = try Self.jsonObject(data)
        let rooms = try XCTUnwrap((root["floors"] as? [[String: Any]])?[0]["rooms"] as? [[String: Any]])
        let living = rooms[0], openPlan = rooms[3]
        let wallB = try XCTUnwrap((living["walls"] as? [[String: Any]])?[1])
        let length = try XCTUnwrap(wallB["length"] as? [String: Any])
        XCTAssertEqual(Set(length.keys), ["scannedM", "verifiedM", "valueM", "source", "verifiedAt", "note", "deviationM"])
        for key in ["verifiedM", "source", "verifiedAt", "note", "deviationM"] {
            XCTAssertTrue(length[key] is NSNull, key)
        }
        // lengthM / widthM exist as null for a room that is not a rectangle.
        XCTAssertTrue(openPlan["lengthM"] is NSNull)
        XCTAssertTrue(openPlan["widthM"] is NSNull)
        XCTAssertEqual(openPlan["isRectangular"] as? Bool, false)
        XCTAssertTrue(openPlan["capturedRoomFile"] is NSNull)
        let custom = try XCTUnwrap((openPlan["customMeasurements"] as? [[String: Any]])?[0])
        XCTAssertTrue(custom["note"] is NSNull)
        // Required room keys.
        for key in ["id", "name", "kind", "floorAreaM2", "effectiveFloorAreaM2", "perimeterM", "wallPerimeterM",
                    "ceilingHeight", "isRectangular", "lengthM", "widthM", "volumeM3", "grossWallAreaM2",
                    "openingAreaM2", "netWallAreaM2", "corners", "walls", "openings", "objects",
                    "customMeasurements", "verification"] {
            XCTAssertNotNil(living[key], key)
        }
    }

    func testCornerAngles() {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let living = file.floors[0].rooms[0]
        XCTAssertEqual(living.corners.count, 4)
        for (i, c) in living.corners.enumerated() {
            XCTAssertEqual(c.index, i)
            XCTAssertEqual(c.interiorAngleDeg, 90, accuracy: 1e-9)
            XCTAssertEqual(c.deviationFrom90Deg, 0, accuracy: 1e-9)
            XCTAssertFalse(c.isReflex)
            XCTAssertFalse(c.isOutOfSquare)
        }
        XCTAssertEqual(living.corners[1].x, 6.2)
        XCTAssertEqual(living.corners[1].y, 0)
        XCTAssertEqual(living.corners[2].y, 4.5)

        // L-shape: corner 3 is the inside corner (270 degrees); reflex corners are not "out of square".
        let l = file.floors[0].rooms[3]
        XCTAssertEqual(l.corners.map(\.interiorAngleDeg), [90, 90, 90, 270, 90, 90])
        XCTAssertEqual(l.corners.filter(\.isReflex).map(\.index), [3])
        XCTAssertEqual(l.corners[3].deviationFrom90Deg, 180, accuracy: 1e-9)
        XCTAssertTrue(l.corners.allSatisfy { !$0.isOutOfSquare })
        // Interior angles of a hexagon add up to 720.
        XCTAssertEqual(l.corners.reduce(0) { $0 + $1.interiorAngleDeg }, 720, accuracy: 1e-6)
    }

    func testOutOfSquareCornerIsFlagged() {
        // The top-left corner is pulled 0.21 m out over a 4 m side: the two corners on that side
        // become 90 + atan(0.21 / 4) = 93.005 and 90 - 3.005 = 86.995 degrees.
        let skew = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-0.21, 4)])
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [skew])])
        let entry = ScanExport.make(property: p, generatedAt: Self.generatedAt).floors[0].rooms[0]
        XCTAssertEqual(entry.corners.filter(\.isOutOfSquare).map(\.index), [0, 3])
        XCTAssertEqual(entry.corners[0].interiorAngleDeg, 93.005, accuracy: 0.002)
        XCTAssertEqual(entry.corners[3].interiorAngleDeg, 86.995, accuracy: 0.002)
        XCTAssertEqual(entry.corners[0].deviationFrom90Deg, 3.005, accuracy: 0.002)
        XCTAssertEqual(entry.corners[3].deviationFrom90Deg, -3.005, accuracy: 0.002)
        XCTAssertEqual(entry.corners[1].interiorAngleDeg, 90, accuracy: 1e-9)
        XCTAssertFalse(entry.corners[1].isOutOfSquare)
        XCTAssertEqual(entry.corners.reduce(0) { $0 + $1.interiorAngleDeg }, 360, accuracy: 1e-6)
    }

    func testWallLabelsAndCoordinates() {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let living = file.floors[0].rooms[0]
        XCTAssertEqual(living.walls.map(\.label), ["Wall A", "Wall B", "Wall C", "Wall D"])
        XCTAssertEqual(living.walls.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(living.walls[0].start, ScanFile.Point(x: 0, y: 0))
        XCTAssertEqual(living.walls[0].end, ScanFile.Point(x: 6.2, y: 0))
        XCTAssertEqual(living.walls[2].start, ScanFile.Point(x: 6.2, y: 4.5))
        XCTAssertEqual(living.walls[2].end, ScanFile.Point(x: 0, y: 4.5))
        XCTAssertEqual(living.walls[0].kind, "solid")
        XCTAssertFalse(living.walls[0].isCurved)
        XCTAssertEqual(living.walls[0].id, "00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(DataLabels.wall(25), "Wall Z")
        XCTAssertEqual(DataLabels.wall(26), "Wall AA")
        XCTAssertEqual(DataLabels.wall(27), "Wall AB")
        XCTAssertEqual(DataLabels.wall(701), "Wall ZZ")
        XCTAssertEqual(DataLabels.wall(702), "Wall AAA")
        XCTAssertEqual(DataLabels.wall(-1), "Wall ?")
    }

    func testOpeningsAreOrderedLabelledAndMeasuredFromBothEnds() throws {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let living = file.floors[0].rooms[0]
        XCTAssertEqual(living.openings.map(\.label), ["Door 1", "Window 1"])
        let door = living.openings[0], window = living.openings[1]
        XCTAssertEqual(door.kind, "door")
        XCTAssertEqual(door.wallIndex, 0)
        XCTAssertEqual(door.wallId, "00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(door.offsetFromStartM, 0.5)
        // Wall A is 6.2 m in the LiDAR geometry: 6.2 - 0.5 - 0.9 (scanned width) = 4.8.
        XCTAssertEqual(try XCTUnwrap(door.offsetFromEndM), 4.8, accuracy: 1e-9)
        XCTAssertEqual(window.kind, "window")
        XCTAssertEqual(window.wallIndex, 2)
        XCTAssertEqual(window.offsetFromStartM, 1.0)
        XCTAssertEqual(try XCTUnwrap(window.offsetFromEndM), 6.2 - 1.0 - 3.0, accuracy: 1e-9)
        XCTAssertEqual(window.height.valueM, 2.4)
        XCTAssertEqual(window.sillHeight.valueM, 0)
    }

    func testOpeningsWithoutAWallAreExportedWithNulls() throws {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.openings = [Opening(kind: .door, wallID: nil, offsetFromWallStart: 0.2,
                                 width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)),
                         Opening(kind: .window, wallID: UUID(), offsetFromWallStart: 0.2,
                                 width: Measured(scanned: 1.2), height: Measured(scanned: 1.2),
                                 sillHeight: Measured(scanned: 0.9))]
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        let data = try ScanExport.json(property: p, generatedAt: Self.generatedAt)
        let root = try Self.jsonObject(data)
        let openings = try XCTUnwrap(((root["floors"] as? [[String: Any]])?[0]["rooms"] as? [[String: Any]])?[0]["openings"] as? [[String: Any]])
        XCTAssertEqual(openings.count, 2)
        // Openings without a matching wall sort last, in array order.
        XCTAssertTrue(openings.allSatisfy { $0["wallIndex"] is NSNull && $0["offsetFromEndM"] is NSNull })
        // Both are "not matched to a wall": the second points at a wall id the room does not have, which
        // matches nothing, so it is null too (the docs promise null for every unmatched opening).
        XCTAssertTrue(openings[0]["wallId"] is NSNull)
        XCTAssertTrue(openings[1]["wallId"] is NSNull)
        XCTAssertEqual(openings.map { $0["label"] as? String }, ["Door 1", "Window 1"])
        // The CSV agrees: empty wall_id and wall columns for both.
        let csv = try XCTUnwrap(CSVExport.files(for: p, units: .default).first { $0.name == "openings.csv" })
        let rows = Self.table(csv.content)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0["wall_id"] == "" && $0["wall"] == "" && $0["offset_from_end_mm"] == "" })
    }

    func testObjectsAndCustomMeasurements() throws {
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let chair = file.floors[0].rooms[2].objects[0]
        XCTAssertEqual(chair.kind, "chair")
        XCTAssertEqual(chair.center, ScanFile.Point(x: 1.0, y: 0.8))
        XCTAssertEqual(chair.yawDeg, 270)             // -pi/2 normalised into 0..<360
        XCTAssertEqual(chair.widthM, 0.5)
        XCTAssertEqual(chair.heightM, 0.9)
        XCTAssertEqual(chair.elevationM, 0)

        let custom = file.floors[0].rooms[3].customMeasurements[0]
        XCTAssertEqual(custom.label, "Wardrobe wall")
        XCTAssertEqual(custom.a, ScanFile.WorldPoint(x: 0, y: 0, z: 0))
        XCTAssertEqual(custom.b, ScanFile.WorldPoint(x: 3, y: 0, z: 4))
        XCTAssertEqual(custom.length.scannedM, 5)      // 3-4-5 triangle
        XCTAssertEqual(custom.length.valueM, 5)
        XCTAssertEqual(custom.createdAt, "2026-10-07T08:15:00.000Z")
    }

    func testYawIsNormalisedAndFiniteOnly() {
        XCTAssertEqual(ScanExport.yawDegrees(0), 0)
        XCTAssertEqual(ScanExport.yawDegrees(.pi), 180)
        XCTAssertEqual(ScanExport.yawDegrees(-.pi / 2), 270)
        XCTAssertEqual(ScanExport.yawDegrees(2 * .pi + 0.1), 5.730, accuracy: 1e-9)     // 0.1 rad = 5.7296 deg
        XCTAssertEqual(ScanExport.yawDegrees(-2 * .pi), 0)
        XCTAssertEqual(ScanExport.yawDegrees(-1e-9), 0)                                 // would round to 360
        XCTAssertEqual(ScanExport.yawDegrees(.nan), 0)
        XCTAssertEqual(ScanExport.yawDegrees(.infinity), 0)
    }

    // MARK: ScanExport: rounding, stability, odd input

    /// Every number in a decoded JSON tree.
    static func numbers(in value: Any) -> [Double] {
        if let dict = value as? [String: Any] { return dict.values.flatMap { numbers(in: $0) } }
        if let array = value as? [Any] { return array.flatMap { numbers(in: $0) } }
        if let n = value as? NSNumber { return [n.doubleValue] }     // booleans read as 0 / 1, also on the grid
        return []
    }

    func testFloatNoiseNeverReachesTheFile() throws {
        // 0.1 + 0.2 is 0.30000000000000004 in binary floating point.
        let a = 0.1 + 0.2
        XCTAssertNotEqual(a, 0.3)
        let room = Room.polygon(name: "Noisy", corners: [Point2(0, 0), Point2(a, 0), Point2(a, 1.0 / 3.0), Point2(0, 1.0 / 3.0)])
        var p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        p.floors[0].rooms[0].ceilingHeight = Measured(scanned: 2.7999999999999998 + 1e-13)
        let data = try ScanExport.json(property: p, generatedAt: Self.generatedAt)
        let entry = ScanExport.make(property: p, generatedAt: Self.generatedAt).floors[0].rooms[0]
        XCTAssertEqual(entry.walls[0].end.x, 0.3)
        XCTAssertEqual(entry.walls[1].end.y, 0.3333)               // 1/3 rounded to 0.1 mm
        XCTAssertEqual(entry.ceilingHeight.scannedM, 2.8)

        // Every number in the file sits on the 0.1 mm grid (angles on a 0.001 degree grid, a multiple of it).
        let all = Self.numbers(in: try JSONSerialization.jsonObject(with: data))
        XCTAssertGreaterThan(all.count, 50)
        for n in all {
            XCTAssertEqual(n, (n * 10_000).rounded() / 10_000, "\(n) is not rounded to 0.1 mm")
        }
        // And no ugly digit run made it into the text of a number.
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("0000000001"))
        XCTAssertFalse(text.contains("9999999999"))
    }

    func testRoundingHelper() {
        XCTAssertEqual(DataNumber.round4(1.23456), 1.2346)
        XCTAssertEqual(DataNumber.round4(1.23454), 1.2345)
        XCTAssertEqual(DataNumber.round4(-1.23456), -1.2346)
        XCTAssertEqual(DataNumber.round4(0.00004), 0)
        XCTAssertFalse(DataNumber.round4(-0.00004).sign == .minus)         // negative zero is normalised
        XCTAssertEqual(DataNumber.round4(.nan), 0)
        XCTAssertEqual(DataNumber.round4(.infinity), 0)
        XCTAssertEqual(DataNumber.round4(1e305), 1e305)                    // would overflow when scaled: left alone
        XCTAssertEqual(DataNumber.fixed(-0.00004, decimals: 3), "0.000")
        XCTAssertEqual(DataNumber.fixed(2.5, decimals: 0), "2")            // the C formatter rounds an exact tie to even
        XCTAssertEqual(DataNumber.fixed(1234.5678, decimals: 2), "1234.57")
        XCTAssertEqual(DataNumber.fixed(.nan, decimals: 2), "")
    }

    func testOutputIsDeterministicAndDecodesBack() throws {
        let a = try ScanExport.json(property: Self.marina(), generatedAt: Self.generatedAt)
        let b = try ScanExport.json(property: Self.marina(), generatedAt: Self.generatedAt)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.last, 0x0A)                                       // trailing newline
        let decoded = try JSONDecoder().decode(ScanFile.self, from: a)
        XCTAssertEqual(decoded, ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt))
        // Keys are sorted: "floors" is written before "generatedAt", before "property".
        let text = try XCTUnwrap(String(data: a, encoding: .utf8))
        let positions = ["\"floors\"", "\"generatedAt\"", "\"generator\"", "\"property\"", "\"schema\"", "\"summary\"", "\"units\"", "\"version\""]
            .map { text.range(of: $0)?.lowerBound }
        XCTAssertTrue(positions.allSatisfy { $0 != nil })
        let ordered = positions.compactMap { $0 }
        XCTAssertEqual(ordered, ordered.sorted())
        // Pretty-printed, not slash-escaped.
        XCTAssertTrue(text.contains("\n"))
        XCTAssertFalse(text.contains("\\/"))
    }

    func testGeneratedAtComesFromTheCaller() throws {
        let t1 = ScanExport.make(property: Self.marina(), generatedAt: Date(timeIntervalSince1970: 0))
        let t2 = ScanExport.make(property: Self.marina(), generatedAt: Date(timeIntervalSince1970: 86_400))
        XCTAssertEqual(t1.generatedAt, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(t2.generatedAt, "1970-01-02T00:00:00.000Z")
        var other = t2
        other.generatedAt = t1.generatedAt
        XCTAssertEqual(other, t1)         // nothing else depends on the time
    }

    func testEmptyAndDegenerateProperties() throws {
        let empty = Property(name: "Empty")
        let file = ScanExport.make(property: empty, generatedAt: Self.generatedAt)
        XCTAssertEqual(file.summary.roomCount, 0)
        XCTAssertEqual(file.summary.totalFloorAreaM2, 0)
        XCTAssertEqual(file.summary.measurementCount, 0)
        XCTAssertTrue(file.floors.isEmpty)
        XCTAssertNoThrow(try ScanExport.json(property: empty, generatedAt: Self.generatedAt))

        // A floor with a room that has no walls, one with two walls and a zero-length wall.
        let none = Room(name: "No walls", walls: [], ceilingHeight: Measured(scanned: 2.8))
        let two = Room(name: "Two walls", walls: [
            Wall(start: Point2(0, 0), end: Point2(1, 0), height: Measured(scanned: 2.8)),
            Wall(start: Point2(1, 0), end: Point2(0, 0), height: Measured(scanned: 2.8)),
        ], ceilingHeight: Measured(scanned: 2.8))
        let zero = Room.polygon(name: "Zero", corners: [Point2(0, 0), Point2(0, 0), Point2(0, 0)])
        let p = Property(name: "Odd", floors: [Floor(name: "F", rooms: [none, two, zero])])
        let data = try ScanExport.json(property: p, generatedAt: Self.generatedAt)
        let decoded = try JSONDecoder().decode(ScanFile.self, from: data)
        let rooms = decoded.floors[0].rooms
        XCTAssertEqual(rooms.map(\.corners.count), [0, 0, 3])      // fewer than three walls: no corners
        XCTAssertEqual(rooms[0].floorAreaM2, 0)
        XCTAssertFalse(rooms[0].isRectangular)
        XCTAssertNil(rooms[0].lengthM)
        XCTAssertEqual(rooms[1].walls.count, 2)
    }

    func testNonFiniteNumbersDoNotBreakTheExport() throws {
        var room = Room.rectangle(name: "Odd room", width: 4, depth: 3)
        room.walls[0].length = Measured(scanned: .nan)
        room.ceilingHeight = Measured(scanned: .infinity)
        room.objects = [RoomObject(kind: .table, center: Point2(.nan, 1), yaw: .infinity, width: 1, depth: 1, height: 1)]
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        let data = try ScanExport.json(property: p, generatedAt: Self.generatedAt)      // must not throw
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.lowercased().contains("nan"))
        XCTAssertFalse(text.lowercased().contains("inf"))
        let entry = try JSONDecoder().decode(ScanFile.self, from: data).floors[0].rooms[0]
        XCTAssertEqual(entry.walls[0].length.scannedM, 0)
        XCTAssertEqual(entry.objects[0].center.x, 0)
        XCTAssertEqual(entry.objects[0].yawDeg, 0)
    }

    func testTextIsPreservedExactly() throws {
        let room = Room.rectangle(name: "\u{0627}\u{0644}\u{0645}\u{0639}\u{064A}\u{0634}\u{0629} / \"Majlis\" \u{1F334}", width: 4, depth: 3)
        var p = Property(name: "Villa 7 \\ B", client: "O'Brien & Sons", address: "Line1\nLine2\ttab",
                         floors: [Floor(name: "Ground/Floor", rooms: [room])])
        p.notes = "emoji \u{1F600} and a \u{0001} control"
        let data = try ScanExport.json(property: p, generatedAt: Self.generatedAt)
        let back = try JSONDecoder().decode(ScanFile.self, from: data)
        XCTAssertEqual(back.property.name, "Villa 7 \\ B")
        XCTAssertEqual(back.property.address, "Line1\nLine2\ttab")
        XCTAssertEqual(back.property.notes, p.notes)
        XCTAssertEqual(back.floors[0].name, "Ground/Floor")
        XCTAssertEqual(back.floors[0].rooms[0].name, room.name)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("Ground/Floor"))      // slashes are not escaped
    }

    func testVirtualWallsAndSillsFollowTheChecklistRules() {
        // Right wall is an open-plan boundary: its height is not checkable, its length is not joinery-critical.
        var room = Room.rectangle(name: "Open", kind: .livingRoom, width: 5, depth: 4,
                                  openings: [.window(wall: 0, offset: 1, width: 1, height: 1.2, sill: 0.9),
                                             .door(wall: 2, offset: 1)])
        room.walls[1].kind = .virtual
        let items = DataMeasureList.items(for: room)
        let labels = items.map(\.label)
        XCTAssertTrue(labels.contains("Wall B length"))
        XCTAssertFalse(labels.contains("Wall B height"))
        XCTAssertEqual(items.first { $0.label == "Wall B length" }?.isJoinery, false)
        XCTAssertEqual(items.first { $0.label == "Wall A length" }?.isJoinery, true)
        XCTAssertEqual(items.first { $0.label == "Wall A height" }?.isJoinery, false)
        // A window with a 0.9 m sill lists the sill; a floor-level door does not.
        XCTAssertTrue(labels.contains("Window 1 sill height"))
        XCTAssertFalse(labels.contains("Door 1 sill height"))
        // Verifying a floor-level sill puts it on the list.
        room.openings[1].sillHeight.verify(0.01)
        XCTAssertTrue(DataMeasureList.items(for: room).map(\.label).contains("Door 1 sill height"))
        // 4 lengths + 3 heights + ceiling + window w,h,sill + door w,h,sill(verified) = 14
        XCTAssertEqual(DataMeasureList.counts(for: room).total, 14)
        XCTAssertEqual(DataMeasureList.counts(for: room).verified, 1)
    }

    func testOpeningNumberingIsPerKindInWallOrder() {
        // Declared out of order on purpose: numbering follows wall order, then offset.
        let room = Room.rectangle(name: "R", width: 6, depth: 4, openings: [
            .window(wall: 2, offset: 0.5, width: 1, height: 1),
            .door(wall: 1, offset: 2.0),
            .window(wall: 0, offset: 3.0, width: 1, height: 1),
            .door(wall: 0, offset: 0.2),
            .window(wall: 0, offset: 1.0, width: 1, height: 1),
        ])
        let refs = DataOpenings.ordered(in: room)
        XCTAssertEqual(refs.map(\.label), ["Door 1", "Window 1", "Window 2", "Door 2", "Window 3"])
        XCTAssertEqual(refs.map(\.wallIndex), [0, 0, 0, 1, 2])
        XCTAssertEqual(refs.map(\.index), [3, 4, 2, 1, 0])
    }

    // MARK: - CSV

    func testCSVProducesTheFourFilesInOrder() {
        let files = CSVExport.files(for: Self.marina(), units: .default)
        XCTAssertEqual(files.map(\.name), ["rooms.csv", "walls.csv", "openings.csv", "objects.csv", "custom_measurements.csv"])
        let plain = CSVExport.files(for: Property(name: "P", floors: [Floor(name: "F", rooms: [Room.rectangle(name: "R", width: 3, depth: 3)])]),
                                    units: .default)
        XCTAssertEqual(plain.map(\.name), ["rooms.csv", "walls.csv", "openings.csv", "objects.csv"])
        // Empty property: still the four files, header only.
        let empty = CSVExport.files(for: Property(name: "E"), units: .default)
        XCTAssertEqual(empty.map(\.name), ["rooms.csv", "walls.csv", "openings.csv", "objects.csv"])
        for f in empty { XCTAssertEqual(Self.parseCSV(f.content).count, 1, f.name) }
    }

    func testCSVBytesAreExcelFriendly() throws {
        for file in CSVExport.files(for: Self.marina(), units: .default) {
            XCTAssertTrue(file.content.hasPrefix("\u{FEFF}"), file.name)
            let bytes = Array(file.content.utf8)
            XCTAssertEqual(Array(bytes.prefix(3)), [0xEF, 0xBB, 0xBF], file.name)
            // Exactly one BOM, CRLF everywhere, never a bare LF or CR, ends with CRLF.
            let scalars = Array(file.content.unicodeScalars)
            XCTAssertEqual(scalars.filter { $0 == "\u{FEFF}" }.count, 1)
            for (i, s) in scalars.enumerated() {
                if s == "\n" { XCTAssertTrue(i > 0 && scalars[i - 1] == "\r", "bare LF in \(file.name)") }
                if s == "\r" { XCTAssertTrue(i + 1 < scalars.count && scalars[i + 1] == "\n", "bare CR in \(file.name)") }
            }
            XCTAssertTrue(file.content.hasSuffix("\r\n"), file.name)
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), file.content)
        }
    }

    func testCSVHeadersCarryTheUnit() {
        func header(_ file: String, _ units: DisplayUnits) -> [String] {
            let f = CSVExport.files(for: Self.marina(), units: units).first { $0.name == file }
            return Self.parseCSV(f?.content ?? "").first ?? []
        }
        let mm = header("walls.csv", DisplayUnits(length: .millimetres, area: .squareMetres))
        XCTAssertEqual(mm, ["floor", "room_id", "room", "wall_id", "wall_index", "wall", "kind", "curved",
                            "start_x_mm", "start_y_mm", "end_x_mm", "end_y_mm",
                            "length_mm", "length_scanned_mm", "length_verified", "length_source",
                            "height_mm", "height_scanned_mm", "height_verified", "height_source"])
        XCTAssertTrue(header("walls.csv", DisplayUnits(length: .metres, area: .squareMetres)).contains("length_m"))
        XCTAssertTrue(header("walls.csv", DisplayUnits(length: .centimetres, area: .squareMetres)).contains("length_scanned_cm"))
        XCTAssertTrue(header("walls.csv", DisplayUnits(length: .inches, area: .squareFeet)).contains("length_in"))
        XCTAssertTrue(header("walls.csv", DisplayUnits(length: .feetAndInches, area: .squareFeet)).contains("length_ft"))
        let rooms = header("rooms.csv", DisplayUnits(length: .millimetres, area: .squareMetres))
        for col in ["floor_area_m2", "effective_floor_area_m2", "perimeter_mm", "ceiling_height_mm",
                    "ceiling_height_scanned_mm", "ceiling_height_verified", "volume_m3", "net_wall_area_m2"] {
            XCTAssertTrue(rooms.contains(col), col)
        }
        let imperial = header("rooms.csv", DisplayUnits(length: .feetAndInches, area: .squareFeet))
        for col in ["floor_area_sqft", "perimeter_ft", "volume_ft3", "gross_wall_area_sqft"] {
            XCTAssertTrue(imperial.contains(col), col)
        }
        let openings = header("openings.csv", .default)
        for col in ["width_mm", "width_scanned_mm", "width_verified", "height_mm", "sill_height_mm",
                    "sill_height_verified", "offset_from_start_mm", "offset_from_end_mm", "area_m2"] {
            XCTAssertTrue(openings.contains(col), col)
        }
    }

    func testEveryMeasuredColumnHasScannedAndVerifiedSiblings() {
        for file in CSVExport.files(for: Self.marina(), units: .default) {
            let header = Self.parseCSV(file.content).first ?? []
            for col in header where col.hasSuffix("_verified") {
                let base = String(col.dropLast("_verified".count))
                // Lengths are millimetres by default, areas square metres (the derived floor area).
                let unit = header.contains(base + "_mm") ? "mm" : "m2"
                XCTAssertTrue(header.contains(base + "_" + unit), "\(file.name): \(col) without \(base)_\(unit)")
                XCTAssertTrue(header.contains(base + "_scanned_" + unit), "\(file.name): \(col) without scanned column")
                // value, scanned, verified sit next to each other, in that order.
                if let i = header.firstIndex(of: base + "_" + unit) {
                    XCTAssertEqual(Array(header[i...].prefix(3)), [base + "_" + unit, base + "_scanned_" + unit, base + "_verified"])
                }
            }
        }
    }

    func testCSVValuesAreHandComputed() throws {
        let files = CSVExport.files(for: Self.marina(), units: .default)
        let rooms = Self.table(try XCTUnwrap(files.first { $0.name == "rooms.csv" }).content)
        XCTAssertEqual(rooms.map { $0["room"] }, ["Living Room", "Master Bathroom", "Balcony", "Open Plan"])
        let living = rooms[0]
        XCTAssertEqual(living["floor"], "Level 23")
        XCTAssertEqual(living["level"], "23")
        XCTAssertEqual(living["kind"], "livingRoom")
        XCTAssertEqual(living["floor_area_m2"], "27.900")
        XCTAssertEqual(living["effective_floor_area_m2"], "28.080")
        XCTAssertEqual(living["perimeter_mm"], "21480.0")
        XCTAssertEqual(living["ceiling_height_mm"], "2850.0")
        XCTAssertEqual(living["ceiling_height_scanned_mm"], "2800.0")
        XCTAssertEqual(living["ceiling_height_verified"], "yes")
        XCTAssertEqual(living["ceiling_height_source"], "laser")
        XCTAssertEqual(living["is_rectangular"], "yes")
        XCTAssertEqual(living["length_mm"], "6240.0")
        XCTAssertEqual(living["width_mm"], "4500.0")
        XCTAssertEqual(living["volume_m3"], "79.515")
        XCTAssertEqual(living["net_wall_area_m2"], "51.012")
        XCTAssertEqual(living["verified_count"], "4")
        XCTAssertEqual(living["measurement_count"], "13")
        XCTAssertEqual(living["joinery_measurement_count"], "9")
        XCTAssertEqual(living["scanned_at"], "2026-10-07T08:15:00.000Z")
        let bath = rooms[1]
        XCTAssertEqual(bath["ceiling_height_verified"], "no")
        XCTAssertEqual(bath["ceiling_height_source"], "")
        XCTAssertEqual(bath["ceiling_height_mm"], bath["ceiling_height_scanned_mm"])     // unverified: value is the scan
        XCTAssertEqual(rooms[3]["is_rectangular"], "no")
        XCTAssertEqual(rooms[3]["length_mm"], "")
        XCTAssertEqual(rooms[3]["width_mm"], "")

        let walls = Self.table(try XCTUnwrap(files.first { $0.name == "walls.csv" }).content)
        XCTAssertEqual(walls.count, 4 + 4 + 4 + 6)
        let wallA = walls[0]
        XCTAssertEqual(wallA["wall"], "Wall A")
        XCTAssertEqual(wallA["wall_index"], "0")
        XCTAssertEqual(wallA["length_mm"], "6240.0")
        XCTAssertEqual(wallA["length_scanned_mm"], "6200.0")
        XCTAssertEqual(wallA["length_verified"], "yes")
        XCTAssertEqual(wallA["length_source"], "laser")
        XCTAssertEqual(wallA["end_x_mm"], "6200.0")
        XCTAssertEqual(walls[1]["length_verified"], "no")
        XCTAssertEqual(walls[1]["length_mm"], walls[1]["length_scanned_mm"])
        XCTAssertEqual(walls[1]["height_verified"], "no")

        let openings = Self.table(try XCTUnwrap(files.first { $0.name == "openings.csv" }).content)
        XCTAssertEqual(openings.map { $0["opening"] }, ["Door 1", "Window 1", "Door 1", "Door 1"])
        let door = openings[0]
        XCTAssertEqual(door["room"], "Living Room")
        XCTAssertEqual(door["wall"], "Wall A")
        XCTAssertEqual(door["width_mm"], "920.0")
        XCTAssertEqual(door["width_scanned_mm"], "900.0")
        XCTAssertEqual(door["width_verified"], "yes")
        XCTAssertEqual(door["width_source"], "tape")
        XCTAssertEqual(door["height_verified"], "no")
        XCTAssertEqual(door["offset_from_start_mm"], "500.0")
        XCTAssertEqual(door["offset_from_end_mm"], "4800.0")
        XCTAssertEqual(door["area_m2"], "1.932")             // 0.92 x 2.1 with the verified width
        XCTAssertEqual(openings[1]["area_m2"], "7.200")

        let objects = Self.table(try XCTUnwrap(files.first { $0.name == "objects.csv" }).content)
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(objects[0]["kind"], "chair")
        XCTAssertEqual(objects[0]["yaw_deg"], "270.000")
        XCTAssertEqual(objects[0]["width_mm"], "500.0")
        XCTAssertEqual(objects[0]["verified"], "no")

        let customs = Self.table(try XCTUnwrap(files.first { $0.name == "custom_measurements.csv" }).content)
        XCTAssertEqual(customs.count, 1)
        XCTAssertEqual(customs[0]["label"], "Wardrobe wall")
        XCTAssertEqual(customs[0]["length_mm"], "5000.0")
        XCTAssertEqual(customs[0]["length_verified"], "no")
    }

    func testCSVUnitConversionsAreIndependentlyChecked() throws {
        func rooms(_ units: DisplayUnits) throws -> [String: String] {
            let f = try XCTUnwrap(CSVExport.files(for: Self.marina(), units: units).first { $0.name == "rooms.csv" })
            return Self.table(f.content)[0]
        }
        let inches = try rooms(DisplayUnits(length: .inches, area: .squareMetres))
        XCTAssertEqual(inches["length_in"], "245.669")                        // 6.24 / 0.0254
        let feet = try rooms(DisplayUnits(length: .feetAndInches, area: .squareFeet))
        XCTAssertEqual(feet["length_ft"], "20.4724")                          // 6.24 / 0.3048
        XCTAssertEqual(feet["effective_floor_area_sqft"], "302.25")           // 28.08 / 0.09290304
        XCTAssertEqual(feet["volume_ft3"], "2808.05")                         // 79.515 / 0.3048^3
        let cm = try rooms(DisplayUnits(length: .centimetres, area: .squareMetres))
        XCTAssertEqual(cm["length_cm"], "624.00")
        let m = try rooms(DisplayUnits(length: .metres, area: .squareMetres))
        XCTAssertEqual(m["length_m"], "6.2400")
        XCTAssertEqual(m["ceiling_height_scanned_m"], "2.8000")
    }

    func testCSVNumbersAreLocaleFreeAscii() throws {
        let number = try NSRegularExpression(pattern: "^-?[0-9]+(\\.[0-9]+)?$")
        let numericHeader = try NSRegularExpression(pattern: "(_(mm|cm|m|in|ft|m2|sqft|m3|ft3|deg|count))$|^(level|wall_index)$")
        var checked = 0
        for units in [DisplayUnits.default, DisplayUnits(length: .feetAndInches, area: .squareFeet),
                      DisplayUnits(length: .metres, area: .squareMetres), DisplayUnits(length: .inches, area: .squareMetres)] {
            for file in CSVExport.files(for: Self.marina(), units: units) {
                let rows = Self.parseCSV(file.content)
                for row in rows.dropFirst() {
                    XCTAssertEqual(row.count, rows[0].count, file.name)
                    for (i, cell) in row.enumerated() {
                        let name = rows[0][i]
                        guard numericHeader.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else { continue }
                        if cell.isEmpty { continue }          // e.g. length of a room that is not a rectangle
                        let ok = number.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)) != nil
                        XCTAssertTrue(ok, "\(file.name).\(name) = \(cell)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testCSVQuotingFollowsRFC4180() {
        XCTAssertEqual(CSVExport.field("plain"), "plain")
        XCTAssertEqual(CSVExport.field("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExport.field("line1\nline2"), "\"line1\nline2\"")
        XCTAssertEqual(CSVExport.field("a\rb"), "\"a\rb\"")
        XCTAssertEqual(CSVExport.field(""), "")
        XCTAssertEqual(CSVExport.field("  spaces  "), "  spaces  ")
        XCTAssertEqual(CSVExport.row(["a", "b,c"]), "a,\"b,c\"\r\n")
    }

    func testCSVRoundTripsAwkwardRoomNamesAndNotes() throws {
        let name = "Study, \"Office\"\nsouth \u{0645}\u{0643}\u{062A}\u{0628} \u{1F4DA}"
        var room = Room.rectangle(name: name, kind: .office, width: 3, depth: 3)
        room.notes = "a,b;\"c\"\r\nsecond line"
        let p = Property(name: "P", floors: [Floor(name: "Floor, \"1\"", rooms: [room])])
        let files = CSVExport.files(for: p, units: .default)
        let rooms = Self.table(try XCTUnwrap(files.first { $0.name == "rooms.csv" }).content)
        XCTAssertEqual(rooms.count, 1)
        XCTAssertEqual(rooms[0]["room"], name)
        XCTAssertEqual(rooms[0]["notes"], "a,b;\"c\"\r\nsecond line")
        XCTAssertEqual(rooms[0]["floor"], "Floor, \"1\"")
        let raw = try XCTUnwrap(files.first { $0.name == "rooms.csv" }).content
        XCTAssertTrue(raw.contains("\"Floor, \"\"1\"\"\""))
        // The same awkward name is repeated unchanged in the other tables, whole rows stay aligned.
        let walls = Self.parseCSV(try XCTUnwrap(files.first { $0.name == "walls.csv" }).content)
        XCTAssertTrue(walls.dropFirst().allSatisfy { $0.count == walls[0].count && $0[2] == name })
    }

    func testCSVGuardsAgainstFormulaInjectionInTextOnly() throws {
        XCTAssertEqual(CSVExport.safeText("=1+1"), "'=1+1")
        XCTAssertEqual(CSVExport.safeText("+971 4 000"), "'+971 4 000")
        XCTAssertEqual(CSVExport.safeText("-cmd"), "'-cmd")
        XCTAssertEqual(CSVExport.safeText("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(CSVExport.safeText("\tTAB"), "'\tTAB")
        XCTAssertEqual(CSVExport.safeText("\r=x"), "'\r=x")
        XCTAssertEqual(CSVExport.safeText("Normal = fine"), "Normal = fine")
        XCTAssertEqual(CSVExport.safeText("1+1"), "1+1")
        XCTAssertEqual(CSVExport.safeText(""), "")
        // Guard and quoting compose: the apostrophe goes in front, then the field is quoted as a whole.
        XCTAssertEqual(CSVExport.field(CSVExport.safeText("=HYPERLINK(\"http://x\",\"y\")")),
                       "\"'=HYPERLINK(\"\"http://x\"\",\"\"y\"\")\"")

        var room = Room.rectangle(name: "=cmd|' /C calc'!A0", width: 3, depth: 3)
        room.objects = [RoomObject(kind: .chair, center: Point2(-1.5, -2.0), yaw: 0, width: 0.5, depth: 0.5, height: 1)]
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        let files = CSVExport.files(for: p, units: .default)
        let rooms = Self.table(try XCTUnwrap(files.first { $0.name == "rooms.csv" }).content)
        XCTAssertEqual(rooms[0]["room"], "'=cmd|' /C calc'!A0")
        // Negative numbers are numbers, not text: never prefixed.
        let objects = Self.table(try XCTUnwrap(files.first { $0.name == "objects.csv" }).content)
        XCTAssertEqual(objects[0]["center_x_mm"], "-1500.0")
        XCTAssertEqual(objects[0]["center_y_mm"], "-2000.0")
    }

    func testCSVIsDeterministic() {
        let a = CSVExport.files(for: Self.marina(), units: .default)
        let b = CSVExport.files(for: Self.marina(), units: .default)
        XCTAssertEqual(a.map(\.name), b.map(\.name))
        XCTAssertEqual(a.map(\.content), b.map(\.content))
    }

    func testCSVRowCountsMatchTheModel() throws {
        let p = Self.marina()
        let files = CSVExport.files(for: p, units: .default)
        func count(_ name: String) throws -> Int {
            Self.parseCSV(try XCTUnwrap(files.first { $0.name == name }).content).count - 1
        }
        XCTAssertEqual(try count("rooms.csv"), p.roomCount)
        XCTAssertEqual(try count("walls.csv"), p.allRooms.reduce(0) { $0 + $1.walls.count })
        XCTAssertEqual(try count("openings.csv"), p.allRooms.reduce(0) { $0 + $1.openings.count })
        XCTAssertEqual(try count("objects.csv"), p.allRooms.reduce(0) { $0 + $1.objects.count })
        XCTAssertEqual(try count("custom_measurements.csv"), 1)
    }

    func testCSVNeverCallsAScannedValueVerified() throws {
        // A property where nothing is verified: every "verified" column must say no.
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 0, offset: 0.5),
                                                                          .window(wall: 1, offset: 0.5, width: 1.0)])
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        for file in CSVExport.files(for: p, units: .default) {
            let rows = Self.parseCSV(file.content)
            for (i, name) in rows[0].enumerated() where name.hasSuffix("_verified") || name == "verified" {
                XCTAssertTrue(rows.dropFirst().allSatisfy { $0[i] == "no" }, "\(file.name).\(name)")
            }
            for (i, name) in rows[0].enumerated() where name.hasSuffix("_source") {
                XCTAssertTrue(rows.dropFirst().allSatisfy { $0[i].isEmpty }, "\(file.name).\(name)")
            }
        }
    }

    // MARK: - Costing spec

    /// Mirror of the engine's `dim()` (skills/nexa-costing/scripts/nexa_costing/util.py) for plain numbers
    /// and "<number>m" text, so the tests can see how the engine will read each value.
    static func engineMetres(_ value: CostingSpec.Length, mmAbove: Double) -> Double {
        switch value {
        case .metres(let v): return v > mmAbove ? v / 1000 : v
        case .text(let s):
            XCTAssertTrue(s.hasSuffix("m"), s)
            return Double(s.dropLast()) ?? .nan
        }
    }

    func testCostingProjectBlock() throws {
        let spec = CostingSpecExport.make(property: Self.marina())
        XCTAssertEqual(spec.project.client, "Mr. Ahmed Khan")
        XCTAssertEqual(spec.project.name, "Marina Gate 2304")
        XCTAssertEqual(spec.project.location, "Dubai Marina, Dubai")
        XCTAssertEqual(spec.project.ref, "NF-2026-1009-01")
        // Effective ceiling heights: Living 2.85 (verified), 2.6, 2.8, 2.8  -> most common is 2.8.
        XCTAssertEqual(spec.project.ceilingHeight, 2.8)
        XCTAssertTrue(spec.scope.isEmpty)

        let root = try Self.jsonObject(CostingSpecExport.json(property: Self.marina()))
        XCTAssertEqual(Set(root.keys), ["project", "rooms", "scope", "x_nexafix_scan"])
        XCTAssertEqual((root["scope"] as? [Any])?.count, 0)
        let project = try XCTUnwrap(root["project"] as? [String: Any])
        XCTAssertEqual(Set(project.keys), ["client", "name", "location", "ref", "ceiling_height"])
    }

    func testRectangularRoomsUseLengthAndWidth() throws {
        let rooms = CostingSpecExport.make(property: Self.marina()).rooms
        XCTAssertEqual(rooms.map(\.name), ["Living Room", "Master Bathroom", "Balcony", "Open Plan"])
        let living = rooms[0]
        XCTAssertEqual(living.length, .metres(6.24))            // verified wall lengths flow through
        XCTAssertEqual(living.width, .metres(4.5))
        XCTAssertNil(living.area)
        XCTAssertNil(living.perimeter)
        XCTAssertEqual(living.height, .metres(2.85))            // effective (verified) ceiling height
        XCTAssertEqual(living.tags, ["living"])
        XCTAssertEqual(living.wet, false)
        // EFFECTIVE sizes: the door width was verified at 0.92 (scanned 0.9).
        XCTAssertEqual(living.doors, [[0.92, 2.1]])
        XCTAssertEqual(living.windows, [[3.0, 2.4]])

        let bath = rooms[1]
        XCTAssertEqual(bath.length, .metres(2.4))
        XCTAssertEqual(bath.width, .metres(2.1))
        XCTAssertEqual(bath.tags, ["bathroom"])
        XCTAssertEqual(bath.wet, true)
        XCTAssertEqual(bath.doors, [[0.8, 2.1]])
        XCTAssertEqual(bath.windows, [])
    }

    func testNonRectangularRoomsUseAreaAndPerimeter() throws {
        let l = CostingSpecExport.make(property: Self.marina()).rooms[3]
        XCTAssertNil(l.length)
        XCTAssertNil(l.width)
        XCTAssertEqual(l.area, 20)
        // Walls 6 + 2 + 2 + 2 + 4 + 4 = 20.
        XCTAssertEqual(l.perimeter, .metres(20))
        XCTAssertEqual(l.tags, [])              // RoomKind.other has no tags: the engine guesses from the name
        XCTAssertNil(l.wet)                     // and decides wetness itself
        XCTAssertEqual(l.doors, [])
        let root = try Self.jsonObject(CostingSpecExport.json(property: Self.marina()))
        let json = try XCTUnwrap((root["rooms"] as? [[String: Any]])?[3])
        XCTAssertNil(json["wet"], "wet must be left out for RoomKind.other")
        XCTAssertNil(json["length"])
        XCTAssertEqual(json["area"] as? Double, 20)
        XCTAssertNotNil(json["doors"] as? [Any])                  // an explicit empty list, not a missing key
    }

    func testBalconyIsOutdoorWithoutInventedDoors() {
        let rooms = CostingSpecExport.make(property: Self.marina()).rooms
        let balcony = rooms[2]
        XCTAssertEqual(balcony.tags, ["outdoor"])
        XCTAssertEqual(balcony.wet, false)
        XCTAssertEqual(balcony.doors, [[2.4, 2.2]])         // only what the scan found
        // A balcony with no scanned door has an explicit empty list: the engine's default of one door
        // applies only when the key is missing, and it is never missing.
        let bare = Room.rectangle(name: "Terrace", kind: .balcony, width: 3, depth: 1.5)
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [bare])])
        let spec = CostingSpecExport.make(property: p)
        XCTAssertEqual(spec.rooms[0].doors, [])
        XCTAssertEqual(spec.rooms[0].tags, ["outdoor"])
    }

    func testEveryRoomKindMapsToTheEnginesTags() {
        for kind in RoomKind.allCases {
            let room = Room.rectangle(name: "R", kind: kind, width: 3, depth: 3)
            let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
            let entry = CostingSpecExport.make(property: p).rooms[0]
            XCTAssertEqual(entry.tags, kind.costingTags, "\(kind)")
            XCTAssertEqual(entry.wet, kind == .other ? nil : kind.isWet, "\(kind)")
        }
    }

    func testLengthsAreNeverMisreadAsMillimetres() throws {
        // The engine treats plain numbers above 60 (length / width), 150 (perimeter) and 20 (height)
        // as millimetres. Big rooms are written as text with a unit, which the engine never rescales.
        let hall = Room.rectangle(name: "Warehouse", kind: .other, width: 72.5, depth: 31.25, ceilingHeight: 9)
        let villa = Room.polygon(name: "Great Hall", corners: [Point2(0, 0), Point2(80, 0), Point2(80, 40), Point2(40, 40),
                                                                 Point2(40, 60), Point2(0, 60)], ceilingHeight: 24)
        let p = Property(name: "Big", floors: [Floor(name: "F", rooms: [hall, villa])])
        let rooms = CostingSpecExport.make(property: p).rooms
        XCTAssertEqual(rooms[0].length, .text("72.5m"))
        XCTAssertEqual(rooms[0].width, .metres(31.25))
        XCTAssertEqual(rooms[0].height, .metres(9))
        XCTAssertEqual(Self.engineMetres(try XCTUnwrap(rooms[0].length), mmAbove: 60), 72.5)
        XCTAssertEqual(Self.engineMetres(try XCTUnwrap(rooms[0].width), mmAbove: 60), 31.25)
        // L-shape: perimeter 80 + 40 + 40 + 20 + 40 + 60 = 280 m, height 24 m: both would be read as mm.
        XCTAssertEqual(rooms[1].perimeter, .text("280m"))
        XCTAssertEqual(rooms[1].height, .text("24m"))
        XCTAssertEqual(Self.engineMetres(try XCTUnwrap(rooms[1].perimeter), mmAbove: 150), 280)
        XCTAssertEqual(Self.engineMetres(rooms[1].height, mmAbove: 20), 24)
        // Exactly at the threshold the engine keeps metres (it only rescales values ABOVE it).
        let edge = Room.rectangle(name: "Edge", kind: .other, width: 60, depth: 20, ceilingHeight: 20)
        let e = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [edge])])).rooms[0]
        XCTAssertEqual(e.length, .metres(60))
        XCTAssertEqual(e.height, .metres(20))
        // Everything that is a number round-trips through the engine's rules unchanged.
        for r in CostingSpecExport.make(property: Self.marina()).rooms {
            if let l = r.length { XCTAssertEqual(Self.engineMetres(l, mmAbove: 60), l.inMetres) }
            if let w = r.width { XCTAssertEqual(Self.engineMetres(w, mmAbove: 60), w.inMetres) }
            XCTAssertEqual(Self.engineMetres(r.height, mmAbove: 20), r.height.inMetres)
        }
    }

    func testOpenPlanRectangleKeepsPerimeterOfSolidWallsOnly() {
        // 6 x 4 room whose east side (wall B, 4 m) is an open-plan boundary with a door on it.
        var room = Room.rectangle(name: "Dining", kind: .dining, width: 6, depth: 4,
                                  openings: [.door(wall: 1, offset: 1.0), .door(wall: 0, offset: 1.0), .window(wall: 2, offset: 1, width: 2)])
        room.walls[1].kind = .virtual
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [room])])
        let spec = CostingSpecExport.make(property: p)
        let r = spec.rooms[0]
        XCTAssertEqual(r.length, .metres(6))
        XCTAssertEqual(r.width, .metres(4))
        XCTAssertEqual(r.perimeter, .metres(16))                 // 6 + 6 + 4: the open edge has no wall
        XCTAssertEqual(r.doors, [[0.9, 2.1]])                    // the door on the open edge is not a wall opening
        XCTAssertEqual(r.windows.count, 1)
        XCTAssertTrue(spec.scanInfo.notes.contains { $0.contains("not on a solid wall") })
    }

    func testRoomWithoutSolidWallsFallsBackToFullPerimeter() {
        var room = Room.rectangle(name: "Void", width: 3, depth: 3)
        for i in room.walls.indices { room.walls[i].kind = .virtual }
        let spec = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [room])]))
        XCTAssertEqual(spec.rooms[0].perimeter, .metres(12))
        XCTAssertTrue(spec.scanInfo.notes.contains { $0.contains("no solid walls") })
    }

    func testOpeningsFollowTheEnginesShape() throws {
        var room = Room.rectangle(name: "Bedroom", kind: .bedroom, width: 4, depth: 3, openings: [
            .door(wall: 0, offset: 0.3),
            .window(wall: 2, offset: 0.5, width: 1.6, height: 2.2, sill: 0),
            OpeningSpec(wall: 3, kind: .opening, offset: 0.5, width: 1.2, height: 2.4),
            .window(wall: 1, offset: 0.5, width: 0, height: 1.0),                // zero width: unusable
        ])
        room.openings[1].width.verify(1.63)                                      // window width verified
        room.openings[1].height.verify(2.21)
        let spec = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [room])]))
        let r = spec.rooms[0]
        XCTAssertEqual(r.doors, [[0.9, 2.1], [1.2, 2.4]])         // door, then the doorless opening, in wall order
        XCTAssertEqual(r.windows, [[1.63, 2.21]])                 // verified sizes
        XCTAssertTrue(spec.scanInfo.notes.contains { $0.contains("doorless openings are listed as doors") })
        XCTAssertTrue(spec.scanInfo.notes.contains { $0.contains("1 opening(s)") })
        // JSON shape: [[w, h], ...]
        let root = try Self.jsonObject(CostingSpecExport.json(property: Property(name: "P", floors: [Floor(name: "F", rooms: [room])])))
        let json = try XCTUnwrap((root["rooms"] as? [[String: Any]])?[0])
        XCTAssertEqual(json["doors"] as? [[Double]], [[0.9, 2.1], [1.2, 2.4]])
        XCTAssertEqual(json["windows"] as? [[Double]], [[1.63, 2.21]])
    }

    func testDuplicateAndEmptyRoomNames() {
        let a = Room.rectangle(name: "Bedroom", kind: .bedroom, width: 4, depth: 3)
        let b = Room.rectangle(name: "bedroom", kind: .bedroom, width: 3, depth: 3)
        let c = Room.rectangle(name: "  ", kind: .bathroom, width: 2, depth: 2)
        let d = Room.rectangle(name: "Bedroom", kind: .bedroom, width: 3.5, depth: 3)
        let p = Property(name: "P", floors: [Floor(name: "L1", rooms: [a, b]), Floor(name: "L2", rooms: [c, d])])
        let spec = CostingSpecExport.make(property: p)
        XCTAssertEqual(spec.rooms.map(\.name), ["Bedroom", "bedroom (2)", "Bathroom", "Bedroom (3)"])
        XCTAssertEqual(Set(spec.rooms.map { $0.name.lowercased() }).count, 4)
        XCTAssertEqual(spec.scanInfo.rooms.map(\.name), spec.rooms.map(\.name))
        XCTAssertEqual(spec.scanInfo.rooms.map(\.floor), ["L1", "L1", "L2", "L2"])
        XCTAssertEqual(spec.scanInfo.notes.filter { $0.contains("used more than once") }.count, 2)
    }

    func testRoomNamesAreUniqueTheWayTheEngineComparesThem() {
        // util.slug: lower-case, runs of anything but a-z / 0-9 become "_". Same slug = same room to the engine.
        XCTAssertEqual(CostingSpecExport.engineSlug("Living / Kitchen"), "living_kitchen")
        XCTAssertEqual(CostingSpecExport.engineSlug("  Bedroom 2 (Ensuite)! "), "bedroom_2_ensuite")
        XCTAssertEqual(CostingSpecExport.engineSlug("Maid's Room"), "maid_s_room")
        XCTAssertEqual(CostingSpecExport.engineSlug("\u{0645}\u{0646}\u{0632}\u{0644}"), "")
        XCTAssertEqual(CostingSpecExport.engineSlug("---"), "")
        XCTAssertEqual(CostingSpecExport.engineSlug("A1"), "a1")

        let names = ["Living / Kitchen", "Living Kitchen", "LIVING-KITCHEN",
                     "\u{063A}\u{0631}\u{0641}\u{0629}", "\u{0645}\u{0637}\u{0628}\u{062E}",
                     "Bedroom", "Bedroom", "Bedroom 2"]
        let rooms = names.map { Room.rectangle(name: $0, width: 3, depth: 3) }
        let spec = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: rooms)]))
        let out = spec.rooms.map(\.name)
        XCTAssertEqual(out, ["Living / Kitchen", "Living Kitchen (2)", "LIVING-KITCHEN (3)",
                             "\u{063A}\u{0631}\u{0641}\u{0629}", "\u{0645}\u{0637}\u{0628}\u{062E} (2)",
                             "Bedroom", "Bedroom (2)", "Bedroom 2 (2)"])
        // After renaming, no two names share a slug.
        XCTAssertEqual(Set(out.map(CostingSpecExport.engineSlug)).count, out.count)
    }

    func testRoomsWithoutAnOutlineAreLeftOutButStillReported() {
        let none = Room(name: "Ghost", walls: [], ceilingHeight: Measured(scanned: 2.8))
        let tiny = Room.polygon(name: "Speck", corners: [Point2(0, 0), Point2(0.05, 0), Point2(0.05, 0.05), Point2(0, 0.05)])
        let ok = Room.rectangle(name: "Real", width: 3, depth: 3)
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [none, tiny, ok])])
        let spec = CostingSpecExport.make(property: p)
        XCTAssertEqual(spec.rooms.map(\.name), ["Real"])
        XCTAssertEqual(spec.scanInfo.notes.filter { $0.contains("no usable floor outline") }.count, 2)
        // The unusable rooms' unverified dimensions are still counted: nothing is hidden.
        XCTAssertTrue(spec.scanInfo.unverifiedJoinery.contains { $0.room == "Speck (not costed)" && $0.floor == "F" })
        XCTAssertNoThrow(try CostingSpecExport.json(property: p))
        // No rooms at all.
        let empty = CostingSpecExport.make(property: Property(name: "E"))
        XCTAssertTrue(empty.rooms.isEmpty)
        XCTAssertNil(empty.project.ceilingHeight)
        XCTAssertNil(empty.scanInfo.scanDate)
        XCTAssertNil(empty.scanInfo.warning)
        XCTAssertTrue(empty.scanInfo.notes.contains("The property has no rooms."))
    }

    func testScanInfoReportsWhatIsUnverified() throws {
        let spec = CostingSpecExport.make(property: Self.marina())
        let info = spec.scanInfo
        XCTAssertEqual(info.schema, "nexafix.costing-spec")
        XCTAssertEqual(info.version, 1)
        XCTAssertEqual(info.generator, "NexaFix Scan")
        XCTAssertEqual(info.propertyId, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(info.scanDate, "2026-10-09")         // latest room scan, balcony: 09:00Z = 13:00 Dubai
        XCTAssertEqual(info.measurementCount, 49)
        XCTAssertEqual(info.verifiedCount, 4)
        XCTAssertEqual(info.joineryMeasurementCount, 31)
        XCTAssertEqual(info.joineryVerifiedCount, 4)
        XCTAssertEqual(info.rooms.map(\.verified), [4, 0, 0, 0])
        XCTAssertEqual(info.rooms.map(\.total), [13, 11, 11, 14])
        XCTAssertEqual(info.rooms.map(\.joineryTotal), [9, 7, 7, 8])

        // 31 joinery items, 4 verified: 27 unverified.
        XCTAssertEqual(info.unverifiedJoinery.count, 27)
        let living = info.unverifiedJoinery.filter { $0.room == "Living Room" }.map(\.item)
        XCTAssertEqual(living, ["Wall B length", "Wall D length", "Door 1 height", "Window 1 width", "Window 1 height"])
        XCTAssertFalse(living.contains("Wall A length"))                 // verified
        XCTAssertFalse(living.contains("Ceiling height"))                // verified
        XCTAssertFalse(living.contains("Wall B height"))                 // wall heights are not joinery-critical
        let wallB = try XCTUnwrap(info.unverifiedJoinery.first { $0.room == "Living Room" && $0.item == "Wall B length" })
        XCTAssertEqual(wallB.scannedM, 4.5)
        XCTAssertEqual(wallB.typicalToleranceM, 0.0675, accuracy: 1e-9)  // 1.5 % of 4.5 m
        XCTAssertTrue(info.unverifiedJoinery.contains { $0.room == "Open Plan" && $0.item == "Wardrobe wall" })

        let warning = try XCTUnwrap(info.warning)
        XCTAssertTrue(warning.contains("27 of 31"), warning)
        XCTAssertTrue(warning.contains("not been verified"), warning)
        XCTAssertTrue(warning.contains(ScanAccuracy.joineryDisclaimer), warning)
    }

    func testScanDateIsTheDubaiDay() {
        // 2026-10-09 21:00 UTC is 01:00 on the 10th in Dubai: the site day is the 10th.
        var late = Room.rectangle(name: "R", width: 3, depth: 3)
        late.scannedAt = Date(timeIntervalSince1970: 1_791_579_600)
        var early = Room.rectangle(name: "S", width: 3, depth: 3)
        early.scannedAt = Date(timeIntervalSince1970: 1_791_360_900)          // 2026-10-07 08:15 UTC
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: [early, late])])
        XCTAssertEqual(CostingSpecExport.make(property: p).scanInfo.scanDate, "2026-10-10")     // the latest room scan
        let q = Property(name: "P", floors: [Floor(name: "F", rooms: [late, early])])
        XCTAssertEqual(CostingSpecExport.make(property: q).scanInfo.scanDate, "2026-10-10")     // order does not matter
    }

    func testNoWarningWhenEveryJoineryDimensionIsVerified() throws {
        var p = Self.marina()
        for f in p.floors.indices {
            for r in p.floors[f].rooms.indices {
                var room = p.floors[f].rooms[r]
                for w in room.walls.indices { room.walls[w].length.verify(room.walls[w].length.scanned + 0.01) }
                room.ceilingHeight.verify(room.ceilingHeight.scanned)
                for o in room.openings.indices {
                    room.openings[o].width.verify(room.openings[o].width.scanned)
                    room.openings[o].height.verify(room.openings[o].height.scanned)
                }
                for c in room.customMeasurements.indices { room.customMeasurements[c].length.verify(5.01) }
                p.floors[f].rooms[r] = room
            }
        }
        let info = CostingSpecExport.make(property: p).scanInfo
        XCTAssertTrue(info.unverifiedJoinery.isEmpty)
        XCTAssertNil(info.warning)
        XCTAssertEqual(info.joineryVerifiedCount, info.joineryMeasurementCount)
        // The JSON says null, not a missing key.
        let root = try Self.jsonObject(CostingSpecExport.json(property: p))
        let x = try XCTUnwrap(root["x_nexafix_scan"] as? [String: Any])
        XCTAssertTrue(x["warning"] is NSNull)
        XCTAssertEqual((x["unverified_joinery"] as? [Any])?.count, 0)
    }

    func testScanInfoJSONKeysAreSnakeCase() throws {
        let root = try Self.jsonObject(CostingSpecExport.json(property: Self.marina()))
        let x = try XCTUnwrap(root["x_nexafix_scan"] as? [String: Any])
        XCTAssertEqual(Set(x.keys), ["schema", "version", "generator", "property_id", "scan_date", "verified_count",
                                     "measurement_count", "joinery_verified_count", "joinery_measurement_count", "rooms",
                                     "unverified_joinery", "warning", "notes"])
        let room = try XCTUnwrap((x["rooms"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(room.keys), ["name", "floor", "kind", "verified", "total", "joinery_verified", "joinery_total",
                                        "area_verified", "perimeter_verified", "height_verified"])
        let item = try XCTUnwrap((x["unverified_joinery"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(item.keys), ["room", "floor", "item", "scanned_m", "typical_tolerance_m"])
    }

    func testCostingSpecIsDeterministicAndDecodesBack() throws {
        let a = try CostingSpecExport.json(property: Self.marina())
        let b = try CostingSpecExport.json(property: Self.marina())
        XCTAssertEqual(a, b)
        let back = try JSONDecoder().decode(CostingSpec.self, from: a)
        XCTAssertEqual(back, CostingSpecExport.make(property: Self.marina()))
    }

    func testCommonCeilingHeightPrefersTheMostFrequentThenTheTaller() {
        func spec(_ heights: [Double]) -> Double? {
            let rooms = heights.map { Room.rectangle(name: "R", width: 3, depth: 3, ceilingHeight: $0) }
            return CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: rooms)])).project.ceilingHeight
        }
        XCTAssertEqual(spec([2.8, 2.8, 3.0]), 2.8)
        XCTAssertEqual(spec([2.8, 3.0]), 3.0)                   // tie: the taller (prices more material)
        XCTAssertEqual(spec([3.0, 3.0, 2.8, 2.8, 2.8]), 2.8)
        XCTAssertEqual(spec([2.804, 2.796, 3.1]), 2.8)          // grouped to the centimetre
        XCTAssertEqual(spec([3.3]), 3.3)
    }

    func testAbsurdHeightsNeitherCrashNorBecomeTheProjectDefault() throws {
        let heights: [Double] = [1e300, .nan, .infinity, -3.0, 0, 250_000]
        let rooms = heights.map { Room.rectangle(name: "R", width: 3, depth: 3, ceilingHeight: $0) }
        let p = Property(name: "P", floors: [Floor(name: "F", rooms: rooms)])
        let spec = CostingSpecExport.make(property: p)         // must not trap
        XCTAssertNil(spec.project.ceilingHeight)               // none of them is a usable default
        XCTAssertEqual(spec.rooms.count, 6)
        XCTAssertNoThrow(try CostingSpecExport.json(property: p))
        XCTAssertNoThrow(try ScanExport.json(property: p, generatedAt: Self.generatedAt))
        for file in CSVExport.files(for: p, units: .default) { XCTAssertFalse(file.content.isEmpty) }
        // A sane room next to them still sets the default.
        let withGood = Property(name: "P", floors: [Floor(name: "F", rooms: rooms + [Room.rectangle(name: "OK", width: 3, depth: 3, ceilingHeight: 2.7)])])
        XCTAssertEqual(CostingSpecExport.make(property: withGood).project.ceilingHeight, 2.7)
    }

    /// A villa-sized survey: 3 floors x 40 rooms, 16-sided outlines, 6 openings each.
    static func bigProperty() -> Property {
        let floors = (0..<3).map { f -> Floor in
            let rooms = (0..<40).map { r -> Room in
                let sides = 16
                let corners = (0..<sides).map { i -> Point2 in
                    let a = 2 * Double.pi * Double(i) / Double(sides)
                    return Point2(Double(r % 8) * 7 + 3 * cos(a), Double(r / 8) * 7 + 2 * sin(a))
                }
                let openings = (0..<6).map { i in OpeningSpec.window(wall: i * 2, offset: 0.1, width: 0.3, height: 1.0) }
                return Room.polygon(name: "Room \(f)-\(r)", kind: .bedroom, corners: corners, openings: openings)
            }
            return Floor(name: "Level \(f)", level: f, rooms: rooms)
        }
        return Property(name: "Big villa", floors: floors)
    }

    func testLargePropertiesExportQuicklyAndConsistently() throws {
        let p = Self.bigProperty()
        XCTAssertEqual(p.roomCount, 120)
        let start = Date()
        let scan = try ScanExport.json(property: p, generatedAt: Self.generatedAt)
        let spec = try CostingSpecExport.json(property: p)
        let csv = CSVExport.files(for: p, units: .default)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10, "exports of a 120-room survey took \(elapsed) s")        // typically well under a second
        let decoded = try JSONDecoder().decode(ScanFile.self, from: scan)
        XCTAssertEqual(decoded.summary.roomCount, 120)
        XCTAssertEqual(decoded.floors.flatMap(\.rooms).reduce(0) { $0 + $1.walls.count }, 120 * 16)
        XCTAssertEqual(try JSONDecoder().decode(CostingSpec.self, from: spec).rooms.count, 120)
        let walls = Self.parseCSV(try XCTUnwrap(csv.first { $0.name == "walls.csv" }).content)
        XCTAssertEqual(walls.count, 1 + 120 * 16)
        let openings = Self.parseCSV(try XCTUnwrap(csv.first { $0.name == "openings.csv" }).content)
        XCTAssertEqual(openings.count, 1 + 120 * 6)
    }

    // MARK: - Provenance of derived figures (length, width, perimeter, effective area)

    /// Shorthand: a rectangle with some wall lengths verified.
    private static func verifiedRect(width: Double, depth: Double, verify: [Int: Double], kind: RoomKind = .other,
                                     name: String = "R") -> Room {
        var r = Room.rectangle(name: name, kind: kind, width: width, depth: depth)
        for (wall, value) in verify { r.walls[wall].length.verify(value, source: .laser, date: Self.verifiedAt) }
        return r
    }

    private static func scanRoom(_ room: Room) -> ScanFile.RoomEntry {
        ScanExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [room])]),
                        generatedAt: Self.generatedAt).floors[0].rooms[0]
    }

    func testABlendOfOneVerifiedAndOneScannedWallIsFlaggedAsNeitherMeasurement() throws {
        // 6.20 x 4.50, only the south wall checked: 6.30. Length = mean(6.30, 6.20) = 6.25, which is neither
        // number; area = 6.25 x 4.5 = 28.125 against the scanned 6.2 x 4.5 = 27.9.
        let e = Self.scanRoom(Self.verifiedRect(width: 6.2, depth: 4.5, verify: [0: 6.30]))
        XCTAssertEqual(try XCTUnwrap(e.lengthM), 6.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.lengthScannedM), 6.2, accuracy: 1e-9)
        XCTAssertEqual(e.lengthVerified, false)
        XCTAssertEqual(try XCTUnwrap(e.widthM), 4.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.widthScannedM), 4.5, accuracy: 1e-9)
        XCTAssertEqual(e.widthVerified, false)
        XCTAssertEqual(e.effectiveFloorAreaM2, 28.125, accuracy: 1e-9)
        XCTAssertEqual(e.effectiveFloorAreaScannedM2, 27.9, accuracy: 1e-9)
        XCTAssertEqual(e.effectiveFloorAreaVerified, false)
        // Perimeter 6.30 + 4.5 + 6.2 + 4.5 = 21.5 (scanned 21.4); nothing flagged as verified.
        XCTAssertEqual(e.perimeterM, 21.5, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterScannedM, 21.4, accuracy: 1e-9)
        XCTAssertEqual(e.wallPerimeterM, 21.5, accuracy: 1e-9)
        XCTAssertEqual(e.wallPerimeterScannedM, 21.4, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterVerified, false)
        XCTAssertEqual(e.wallPerimeterVerified, false)
    }

    func testEveryWallVerifiedMakesTheDerivedFiguresVerified() throws {
        // South 6.30, east 4.52, north 6.28, west 4.50: length = 6.29, width = 4.51, area = 28.3679, perimeter 21.6.
        let e = Self.scanRoom(Self.verifiedRect(width: 6.2, depth: 4.5, verify: [0: 6.30, 1: 4.52, 2: 6.28, 3: 4.50]))
        XCTAssertEqual(try XCTUnwrap(e.lengthM), 6.29, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.widthM), 4.51, accuracy: 1e-9)
        XCTAssertEqual(e.lengthVerified, true)
        XCTAssertEqual(e.widthVerified, true)
        XCTAssertEqual(e.effectiveFloorAreaM2, 6.29 * 4.51, accuracy: 1e-4)
        XCTAssertEqual(e.effectiveFloorAreaVerified, true)
        XCTAssertEqual(e.effectiveFloorAreaScannedM2, 27.9, accuracy: 1e-9)       // the LiDAR figure is still there
        XCTAssertEqual(e.perimeterM, 6.30 + 4.52 + 6.28 + 4.50, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterScannedM, 21.4, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterVerified, true)
        XCTAssertEqual(e.wallPerimeterVerified, true)
    }

    func testOnlyOneOppositePairVerifiedFlagsOnlyThatDimension() throws {
        // South and north verified: the long side is verified, the short side and the area are not.
        let e = Self.scanRoom(Self.verifiedRect(width: 6.2, depth: 4.5, verify: [0: 6.30, 2: 6.28]))
        XCTAssertEqual(e.lengthVerified, true)
        XCTAssertEqual(e.widthVerified, false)
        XCTAssertEqual(e.effectiveFloorAreaVerified, false)
        XCTAssertEqual(e.perimeterVerified, false)
    }

    func testLengthAndWidthFlagsFollowTheLongerPairWhicheverWallsItIs() throws {
        // 3 wide x 5 deep: the east and west walls (1 and 3) are the long side.
        let tall = Self.scanRoom(Self.verifiedRect(width: 3, depth: 5, verify: [1: 5.02, 3: 5.00]))
        XCTAssertEqual(try XCTUnwrap(tall.lengthM), 5.01, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(tall.lengthScannedM), 5.0, accuracy: 1e-9)
        XCTAssertEqual(tall.lengthVerified, true)
        XCTAssertEqual(tall.widthVerified, false)
        XCTAssertEqual(try XCTUnwrap(tall.widthScannedM), 3.0, accuracy: 1e-9)
        // Verification can swap which pair is longer: a 3.0 x 3.1 room whose short pair is verified up to 3.3.
        let swapped = Self.scanRoom(Self.verifiedRect(width: 3.0, depth: 3.1, verify: [0: 3.3, 2: 3.3]))
        XCTAssertEqual(try XCTUnwrap(swapped.lengthM), 3.3, accuracy: 1e-9)       // the verified pair is now the long one
        XCTAssertEqual(try XCTUnwrap(swapped.lengthScannedM), 3.0, accuracy: 1e-9)  // scanned figure of the SAME pair
        XCTAssertEqual(swapped.lengthVerified, true)
        XCTAssertEqual(try XCTUnwrap(swapped.widthM), 3.1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(swapped.widthScannedM), 3.1, accuracy: 1e-9)
        XCTAssertEqual(swapped.widthVerified, false)
    }

    func testASideMadeOfSeveralWallsIsVerifiedOnlyWhenEveryPieceIs() throws {
        // A rectangle whose long side is two collinear walls (a 6-wall loop): 2 m + 2 m on the south, one wall north.
        var study = Room.polygon(name: "Study", corners: [Point2(0, 0), Point2(2, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)])
        XCTAssertEqual(study.walls.count, 5)
        study.walls[0].length.verify(2.01, source: .laser, date: Self.verifiedAt)
        var e = Self.scanRoom(study)
        XCTAssertTrue(e.isRectangular)
        XCTAssertEqual(try XCTUnwrap(e.lengthM), (2.01 + 2.0 + 4.0) / 2, accuracy: 1e-9)   // 4.005: matches no measurement
        XCTAssertEqual(e.lengthVerified, false)
        study.walls[1].length.verify(2.0, source: .laser, date: Self.verifiedAt)
        study.walls[2].length.verify(3.0, source: .laser, date: Self.verifiedAt)
        study.walls[3].length.verify(4.0, source: .laser, date: Self.verifiedAt)          // north (4 m)
        study.walls[4].length.verify(3.0, source: .laser, date: Self.verifiedAt)
        e = Self.scanRoom(study)
        XCTAssertEqual(e.lengthVerified, true)
        XCTAssertEqual(e.widthVerified, true)
        XCTAssertEqual(e.effectiveFloorAreaVerified, true)
    }

    func testAnIrregularRoomsAreaIsNeverVerifiedEvenWithEveryWallChecked() throws {
        var l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        for i in l.walls.indices { l.walls[i].length.verify(l.walls[i].geometricLength + 0.01, source: .laser, date: Self.verifiedAt) }
        let e = Self.scanRoom(l)
        XCTAssertFalse(e.isRectangular)
        XCTAssertEqual(e.perimeterVerified, true)                  // wall lengths: all checked
        XCTAssertEqual(e.wallPerimeterVerified, true)
        XCTAssertEqual(e.effectiveFloorAreaVerified, false)        // area: from scanned corners
        XCTAssertEqual(e.effectiveFloorAreaM2, 20, accuracy: 1e-9)
        XCTAssertEqual(e.effectiveFloorAreaScannedM2, 20, accuracy: 1e-9)
        XCTAssertNil(e.lengthM); XCTAssertNil(e.lengthScannedM); XCTAssertNil(e.lengthVerified)
        XCTAssertNil(e.widthM); XCTAssertNil(e.widthScannedM); XCTAssertNil(e.widthVerified)
        // Perimeter 20 + 6 x 0.01 = 20.06 against 20 scanned.
        XCTAssertEqual(e.perimeterM, 20.06, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterScannedM, 20, accuracy: 1e-9)
    }

    func testOpenPlanBoundariesDoNotCountAgainstTheWallPerimeterFlag() throws {
        var r = Self.verifiedRect(width: 4, depth: 3, verify: [0: 4.01, 1: 3.01, 3: 3.0])
        r.walls[2].kind = .virtual                                  // open edge on the north, never checked
        let e = Self.scanRoom(r)
        XCTAssertEqual(e.wallPerimeterVerified, true)               // every SOLID wall checked
        XCTAssertEqual(e.perimeterVerified, false)                  // but not every wall
        XCTAssertEqual(e.wallPerimeterM, 4.01 + 3.01 + 3.0, accuracy: 1e-9)
        XCTAssertEqual(e.wallPerimeterScannedM, 10, accuracy: 1e-9)
        XCTAssertEqual(e.perimeterM, 4.01 + 3.01 + 4.0 + 3.0, accuracy: 1e-9)
    }

    func testNothingVerifiedMeansNothingFlaggedAndScannedEqualsValue() throws {
        let e = Self.scanRoom(Self.verifiedRect(width: 5, depth: 4, verify: [:]))
        XCTAssertEqual(e.lengthM, e.lengthScannedM)
        XCTAssertEqual(e.widthM, e.widthScannedM)
        XCTAssertEqual(e.effectiveFloorAreaM2, e.effectiveFloorAreaScannedM2)
        XCTAssertEqual(e.perimeterM, e.perimeterScannedM)
        XCTAssertEqual(e.wallPerimeterM, e.wallPerimeterScannedM)
        XCTAssertEqual([e.lengthVerified, e.widthVerified, e.effectiveFloorAreaVerified, e.perimeterVerified, e.wallPerimeterVerified]
            .map { $0 == true }, [false, false, false, false, false])
        // A room with no walls at all has nothing verified either.
        let ghost = Self.scanRoom(Room(name: "Ghost", walls: [], ceilingHeight: Measured(scanned: 2.8)))
        XCTAssertEqual(ghost.perimeterVerified, false)
        XCTAssertEqual(ghost.wallPerimeterVerified, false)
        XCTAssertEqual(ghost.effectiveFloorAreaVerified, false)
        XCTAssertNil(ghost.lengthVerified)
    }

    func testDerivedProvenanceIsWrittenToTheJSONAsExplicitKeys() throws {
        let root = try Self.jsonObject(ScanExport.json(property: Self.marina(), generatedAt: Self.generatedAt))
        let rooms = try XCTUnwrap((root["floors"] as? [[String: Any]])?[0]["rooms"] as? [[String: Any]])
        let living = rooms[0], openPlan = rooms[3]
        // Living room: south and north (walls A and C) verified at 6.24, east and west not.
        XCTAssertEqual(living["lengthM"] as? Double, 6.24)
        XCTAssertEqual(living["lengthScannedM"] as? Double, 6.2)
        XCTAssertEqual(living["lengthVerified"] as? Bool, true)
        XCTAssertEqual(living["widthM"] as? Double, 4.5)
        XCTAssertEqual(living["widthVerified"] as? Bool, false)
        XCTAssertEqual(living["effectiveFloorAreaVerified"] as? Bool, false)
        XCTAssertEqual(living["effectiveFloorAreaScannedM2"] as? Double, 27.9)
        XCTAssertEqual(living["perimeterScannedM"] as? Double, 21.4)
        XCTAssertEqual(living["perimeterM"] as? Double, 21.48)
        XCTAssertEqual(living["perimeterVerified"] as? Bool, false)
        // The L-shape has the keys, as null where there is nothing to say.
        XCTAssertTrue(openPlan["lengthScannedM"] is NSNull)
        XCTAssertTrue(openPlan["lengthVerified"] is NSNull)
        XCTAssertTrue(openPlan["widthVerified"] is NSNull)
        XCTAssertEqual(openPlan["effectiveFloorAreaVerified"] as? Bool, false)
        // And the file reads back.
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        let back = try JSONDecoder().decode(ScanFile.self, from: ScanExport.encode(file))
        XCTAssertEqual(back, file)
    }

    func testRoomsCSVCarriesTheDerivedProvenanceColumns() throws {
        let rows = Self.table(try XCTUnwrap(CSVExport.files(for: Self.marina(), units: .default).first { $0.name == "rooms.csv" }).content)
        let living = rows[0], openPlan = rows[3]
        XCTAssertEqual(living["length_mm"], "6240.0")
        XCTAssertEqual(living["length_scanned_mm"], "6200.0")
        XCTAssertEqual(living["length_verified"], "yes")
        XCTAssertEqual(living["width_mm"], "4500.0")
        XCTAssertEqual(living["width_scanned_mm"], "4500.0")
        XCTAssertEqual(living["width_verified"], "no")
        XCTAssertEqual(living["effective_floor_area_m2"], "28.080")
        XCTAssertEqual(living["effective_floor_area_scanned_m2"], "27.900")
        XCTAssertEqual(living["effective_floor_area_verified"], "no")
        XCTAssertEqual(living["perimeter_mm"], "21480.0")
        XCTAssertEqual(living["perimeter_scanned_mm"], "21400.0")
        XCTAssertEqual(living["perimeter_verified"], "no")
        XCTAssertEqual(living["wall_perimeter_verified"], "no")
        // Not a rectangle: no length / width, so the three columns are empty, not "no".
        XCTAssertEqual(openPlan["is_rectangular"], "no")
        XCTAssertEqual([openPlan["length_mm"], openPlan["length_scanned_mm"], openPlan["length_verified"]], ["", "", ""])
        XCTAssertEqual([openPlan["width_mm"], openPlan["width_scanned_mm"], openPlan["width_verified"]], ["", "", ""])
        XCTAssertEqual(openPlan["effective_floor_area_verified"], "no")
    }

    // MARK: - Costing spec: names, floors, flags

    func testUnverifiedItemsUseTheNamesOfTheCostingRoomsSoDuplicatesCanBeToldApart() {
        let rooms = [Room.rectangle(name: "Bedroom", kind: .bedroom, width: 4, depth: 4),
                     Room.rectangle(name: "Bedroom", kind: .bedroom, width: 3, depth: 4,
                                    openings: [.door(wall: 0, offset: 0.5)])]
        let upstairs = [Room.rectangle(name: "Bedroom", kind: .bedroom, width: 3, depth: 3)]
        let p = Property(name: "P", floors: [Floor(name: "Ground", rooms: rooms), Floor(name: "First", level: 1, rooms: upstairs)])
        let spec = CostingSpecExport.make(property: p)
        XCTAssertEqual(spec.rooms.map(\.name), ["Bedroom", "Bedroom (2)", "Bedroom (3)"])
        XCTAssertEqual(spec.scanInfo.rooms.map(\.name), ["Bedroom", "Bedroom (2)", "Bedroom (3)"])

        // Joinery items: 4 wall lengths + ceiling (+ door width and height). 5, 7 and 5.
        var perRoom: [String: Int] = [:]
        for item in spec.scanInfo.unverifiedJoinery { perRoom[item.room, default: 0] += 1 }
        XCTAssertEqual(perRoom, ["Bedroom": 5, "Bedroom (2)": 7, "Bedroom (3)": 5])
        // The counts in x_nexafix_scan.rooms agree with the list, room for room.
        for info in spec.scanInfo.rooms {
            XCTAssertEqual(perRoom[info.name], info.joineryTotal - info.joineryVerified, info.name)
        }
        // The floor travels with every item.
        XCTAssertEqual(Set(spec.scanInfo.unverifiedJoinery.filter { $0.room == "Bedroom (3)" }.map(\.floor)), ["First"])
        XCTAssertEqual(Set(spec.scanInfo.unverifiedJoinery.filter { $0.room != "Bedroom (3)" }.map(\.floor)), ["Ground"])
    }

    func testEveryUnverifiedRoomNameIsACostingRoomOrMarkedNotCosted() {
        let spec = CostingSpecExport.make(property: Self.marina())
        let names = Set(spec.rooms.map(\.name))
        XCTAssertTrue(spec.scanInfo.unverifiedJoinery.allSatisfy { names.contains($0.room) })

        let ghost = Room(name: "Bedroom", walls: [], ceilingHeight: Measured(scanned: 2.8))
        let real = Room.rectangle(name: "Bedroom", width: 3, depth: 3)
        let withGhost = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [ghost, real])]))
        XCTAssertEqual(withGhost.rooms.map(\.name), ["Bedroom"])                  // the ghost did not take the name
        XCTAssertEqual(Set(withGhost.scanInfo.unverifiedJoinery.map(\.room)), ["Bedroom", "Bedroom (not costed)"])
        XCTAssertTrue(withGhost.scanInfo.notes.contains { $0.contains("Bedroom (F)") && $0.contains("left out") })
    }

    func testRoomInfoSaysWhichQuantitiesRestOnVerifiedDimensions() {
        let spec = CostingSpecExport.make(property: Self.marina())
        let byName = Dictionary(uniqueKeysWithValues: spec.scanInfo.rooms.map { ($0.name, $0) })
        // Living room: ceiling checked, long walls checked, short walls not -> height yes, area no, perimeter no.
        XCTAssertEqual(byName["Living Room"]?.heightVerified, true)
        XCTAssertEqual(byName["Living Room"]?.areaVerified, false)
        XCTAssertEqual(byName["Living Room"]?.perimeterVerified, false)
        XCTAssertEqual(byName["Master Bathroom"]?.heightVerified, false)
        // The L-shape's area comes from scanned corners: never verified, even with every wall checked.
        var l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        for i in l.walls.indices { l.walls[i].length.verify(l.walls[i].geometricLength, source: .laser, date: Self.verifiedAt) }
        l.ceilingHeight.verify(2.8, source: .laser, date: Self.verifiedAt)
        let lSpec = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [l])]))
        XCTAssertEqual(lSpec.scanInfo.rooms[0].areaVerified, false)
        XCTAssertEqual(lSpec.scanInfo.rooms[0].perimeterVerified, true)
        XCTAssertEqual(lSpec.scanInfo.rooms[0].heightVerified, true)
        // A fully verified rectangle is verified on all three, with and without an open-plan edge.
        let full = Self.verifiedRect(width: 5, depth: 4, verify: [0: 5.01, 1: 4.01, 2: 5.0, 3: 4.0])
        var open = full
        open.walls[2].kind = .virtual
        for room in [full, open] {
            let s = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [room])]))
            XCTAssertEqual(s.scanInfo.rooms[0].areaVerified, true)
            XCTAssertEqual(s.scanInfo.rooms[0].perimeterVerified, true, "virtual wall: \(room.walls[2].kind)")
        }
        // Only the solid walls count for the perimeter handed to the engine: an unchecked open edge does not spoil it.
        var halfOpen = Self.verifiedRect(width: 5, depth: 4, verify: [0: 5.01, 1: 4.01, 3: 4.0])
        halfOpen.walls[2].kind = .virtual
        let hs = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [halfOpen])]))
        XCTAssertEqual(hs.scanInfo.rooms[0].perimeterVerified, true)
        XCTAssertEqual(hs.scanInfo.rooms[0].areaVerified, false)         // the north edge is part of the area
    }

    // MARK: - Costing spec: what the engine will do to names and wall areas

    /// Expected output of `_guess_tags` in nexa_costing/spec.py for each name (tests/test_from_scan.py runs the
    /// same table against the Python function, so the mirror and the engine cannot drift apart unnoticed).
    static let engineGuessTable: [(String, [String])] = [
        ("Corridor to Balcony", ["circulation", "outdoor"]), ("Master Bedroom Terrace Side", ["outdoor"]),
        ("Showcase Area", ["bathroom"]), ("Bedroom 2 Ensuite", ["bathroom"]), ("Living Room", ["living"]),
        ("Maid's Room", ["utility"]), ("Master Bath", ["bathroom"]), ("Master", ["bedroom"]), ("Hall", ["circulation"]),
        ("Wallpaper Store", ["utility"]), ("Store Room", ["utility"]), ("Majlis", ["living"]), ("Kitchenette", ["kitchen"]),
        ("\u{063A}\u{0631}\u{0641}\u{0629} \u{0627}\u{0644}\u{0645}\u{0639}\u{064A}\u{0634}\u{0629}", []), ("", []),
        ("BALCONY", ["outdoor"]), ("Dining", ["living"]), ("Powder Room", ["bathroom"]), ("Entrance", ["circulation"]),
        ("Lobby / Foyer", ["circulation"]), ("Study", []), ("Terrace", ["outdoor"]), ("Master Bedroom", ["bedroom"]),
        ("Walk-in WC", ["bathroom"]), ("Bedroom", ["bedroom"]), ("Hallway Bedroom", ["bedroom", "circulation"]),
        ("Entry", ["circulation"]), ("Kitchen", ["kitchen"]), ("Laundry", ["utility"]), ("Storage", []), ("Office", []),
        ("Reception", []), ("Meeting Room", []), ("Room", []), ("Living", ["living"]), ("Cinema Room", []),
        ("Master Suite Balcony", ["outdoor"]), ("Master Laundry", ["utility"]),
    ]

    func testTheEngineNameGuessMirrorMatchesTheEnginesOwnTable() {
        for (name, expected) in Self.engineGuessTable {
            XCTAssertEqual(CostingEngineGuess.tags(forName: name).sorted(), expected, name.debugDescription)
        }
        // A combining mark does not hide a keyword (Python searches code points).
        XCTAssertEqual(CostingEngineGuess.tags(forName: "bed\u{0301}room").sorted(), ["bedroom"])
    }

    func testRoomsTheEngineWillReclassifyAreNamedInTheNotes() {
        func spec(_ name: String, _ kind: RoomKind) -> CostingSpec {
            CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [Room.rectangle(name: name, kind: kind, width: 4, depth: 3)])]))
        }
        func guessNotes(_ s: CostingSpec) -> [String] { s.scanInfo.notes.filter { $0.contains("costing engine also tags") } }

        // The four rooms of the review: file tags [living] [circulation] [bedroom] [] -> the engine changes three.
        let corridor = spec("Corridor to Balcony", .corridor)
        XCTAssertEqual(corridor.rooms[0].tags, ["circulation"])
        XCTAssertEqual(guessNotes(corridor).count, 1)
        XCTAssertTrue(guessNotes(corridor)[0].hasPrefix("Corridor to Balcony: "), guessNotes(corridor)[0])
        XCTAssertTrue(guessNotes(corridor)[0].contains("\"outdoor\""))
        XCTAssertTrue(guessNotes(corridor)[0].contains("\"all\" and \"dry\""))
        XCTAssertTrue(guessNotes(corridor)[0].contains("Rename the room"))

        let master = spec("Master Bedroom Terrace Side", .masterBedroom)
        XCTAssertTrue(guessNotes(master)[0].contains("\"outdoor\""))

        let showcase = spec("Showcase Area", .other)           // "wc" inside "showcase"
        XCTAssertNil(showcase.rooms[0].wet)                    // the app leaves `wet` to the engine for kind other...
        XCTAssertTrue(guessNotes(showcase)[0].contains("\"bathroom\""))
        XCTAssertTrue(guessNotes(showcase)[0].contains("wet area"))   // ...so it comes out wet, and the note says so

        let ensuite = spec("Bedroom 2 Ensuite", .bedroom)
        XCTAssertEqual(ensuite.rooms[0].wet, false)            // explicit, so the engine keeps it dry
        XCTAssertTrue(guessNotes(ensuite)[0].contains("\"bathroom\""))
        XCTAssertFalse(guessNotes(ensuite)[0].contains("wet area"))

        // Ordinary names produce no note, for every kind's default name.
        for kind in RoomKind.allCases {
            XCTAssertTrue(guessNotes(spec(kind.displayName, kind)).isEmpty, kind.displayName)
        }
        XCTAssertTrue(guessNotes(spec("Living Room", .livingRoom)).isEmpty)
        XCTAssertTrue(guessNotes(CostingSpecExport.make(property: Self.marina())).isEmpty)
    }

    func testWallAreaDifferenceBetweenScanFileAndEngineIsReportedOnce() throws {
        // Marina's living room: ceiling verified 2.85, walls scanned 2.8.
        // Scan file: 21.48 x 2.8 - 9.132 = 51.012. Engine: 21.48 x 2.85 - 9.132 = 52.086.
        let file = ScanExport.make(property: Self.marina(), generatedAt: Self.generatedAt)
        XCTAssertEqual(file.floors[0].rooms[0].netWallAreaM2, 51.012, accuracy: 1e-9)
        let spec = CostingSpecExport.make(property: Self.marina())
        let living = try XCTUnwrap(spec.rooms.first)
        // Engine side by hand: 2 x (6.24 + 4.5) = 21.48 m of wall, 2.85 m high, less the door and the window.
        XCTAssertEqual(living.length?.inMetres, 6.24)
        XCTAssertEqual(living.width?.inMetres, 4.5)
        XCTAssertEqual(living.height.inMetres, 2.85)
        XCTAssertEqual(2 * (6.24 + 4.5) * 2.85 - (0.92 * 2.1 + 3.0 * 2.4), 52.086, accuracy: 1e-9)
        let notes = spec.scanInfo.notes.filter { $0.hasPrefix("Wall area differs") }
        XCTAssertEqual(notes.count, 1, "one note for the whole property, not one per room")
        XCTAssertTrue(notes[0].contains("Living Room"), notes[0])
        XCTAssertTrue(notes[0].contains("51.01 m2 in the scan file"), notes[0])
        XCTAssertTrue(notes[0].contains("52.09 m2 in the costing engine"), notes[0])

        // No difference, no note: wall heights equal the ceiling height and there are no openings.
        let plain = CostingSpecExport.make(property: Property(name: "P", floors: [Floor(name: "F", rooms: [Room.rectangle(name: "Plain", width: 4, depth: 3)])]))
        XCTAssertTrue(plain.scanInfo.notes.allSatisfy { !$0.hasPrefix("Wall area differs") })
    }

    // MARK: - Fixture generation (run by the lead when the examples need refreshing)

    /// The studio used for tests/fixtures/scan_costing_spec.json on the Python side: a living area
    /// that is an L-shape (area + perimeter), a wet bathroom and a balcony (outdoor).
    static func studio() -> Property {
        let living = fixedIDs(
            Room.polygon(name: "Living / Kitchen", kind: .livingRoom,
                         corners: [Point2(0, 0), Point2(5.6, 0), Point2(5.6, 2.4), Point2(3.4, 2.4), Point2(3.4, 4.6), Point2(0, 4.6)],
                         ceilingHeight: 2.9,
                         openings: [.door(wall: 0, offset: 0.4), .window(wall: 1, offset: 0.2, width: 1.8, height: 2.3, sill: 0)]),
            base: 0x100, scannedAt: Self.scanDay1)
        var livingVerified = living
        livingVerified.walls[0].length.verify(5.62, source: .laser, date: Self.verifiedAt)
        livingVerified.walls[5].length.verify(4.61, source: .laser, date: Self.verifiedAt)
        livingVerified.ceilingHeight.verify(2.92, source: .laser, date: Self.verifiedAt)

        let bath = fixedIDs(
            Room.rectangle(name: "Bathroom", kind: .bathroom, width: 2.2, depth: 1.8, ceilingHeight: 2.6,
                           openings: [.door(wall: 3, offset: 0.5, width: 0.75)]),
            base: 0x200, scannedAt: Self.scanDay1)
        let balcony = fixedIDs(
            Room.rectangle(name: "Balcony", kind: .balcony, width: 3.8, depth: 1.5, ceilingHeight: 2.9,
                           openings: [OpeningSpec(wall: 0, kind: .door, offset: 0.3, width: 2.0, height: 2.3)]),
            base: 0x300, scannedAt: Self.scanDay1)
        return Property(id: Self.id(0xA1), name: "Studio 1207", client: "Ms. Layla Hassan", address: "JVC, Dubai",
                        reference: "NF-2026-1009-02", kind: .apartment, notes: "",
                        createdAt: Self.scanDay1, updatedAt: Self.scanDay1,
                        floors: [Floor(id: Self.id(0xA2), name: "Level 12", level: 12, rooms: [livingVerified, bath, balcony])])
    }

    func testStudioFixtureIsWhatThePythonSideExpects() throws {
        let spec = CostingSpecExport.make(property: Self.studio())
        XCTAssertEqual(spec.rooms.map(\.name), ["Living / Kitchen", "Bathroom", "Balcony"])
        // L-shape: 5.6 x 4.6 less the 2.2 x 2.2 notch = 25.76 - 4.84 = 20.92 m2.
        XCTAssertEqual(spec.rooms[0].area ?? 0, 20.92, accuracy: 1e-9)
        XCTAssertNil(spec.rooms[0].length)
        // Walls: 5.62 (verified) + 2.4 + 2.2 + 2.2 + 3.4 + 4.61 (verified) = 20.43
        XCTAssertEqual(spec.rooms[0].perimeter?.inMetres ?? 0, 20.43, accuracy: 1e-9)
        XCTAssertEqual(spec.rooms[0].height, .metres(2.92))
        XCTAssertEqual(spec.rooms[1].tags, ["bathroom"])
        XCTAssertEqual(spec.rooms[2].tags, ["outdoor"])
        XCTAssertNotNil(spec.scanInfo.warning)
    }

    /// The Python tests read tests/fixtures/scan_costing_spec.json. It must be what the code produces today,
    /// otherwise those tests would be checking an old format. Compared as data, not bytes, because
    /// JSONEncoder spaces empty arrays differently on Linux and Apple platforms.
    func testCommittedFixtureMatchesTheCurrentCode() throws {
        var root = URL(fileURLWithPath: #filePath)           // .../ios/NexaFixCore/Tests/NexaFixCoreTests/DataExportTests.swift
        for _ in 0..<5 { root.deleteLastPathComponent() }    // -> repository root
        let fixture = root.appendingPathComponent("tests/fixtures/scan_costing_spec.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("no tests/fixtures/scan_costing_spec.json next to this checkout")
        }
        let committed = try JSONDecoder().decode(CostingSpec.self, from: Data(contentsOf: fixture))
        if committed != CostingSpecExport.make(property: Self.studio()) {
            XCTFail("tests/fixtures/scan_costing_spec.json is stale: regenerate it with NEXAFIX_FIXTURE_DIR (see testWriteFixturesWhenRequested)")
        }
    }

    /// With NEXAFIX_FIXTURE_DIR set, writes the example files used by the Python tests and the docs:
    ///   scan_costing_spec.json            (the studio's costing spec)
    ///   example/NexaFix_*_scan.json, rooms.csv ...  (the Marina Gate property, all exports)
    func testWriteFixturesWhenRequested() throws {
        let studioJSON = try CostingSpecExport.json(property: Self.studio())
        XCTAssertFalse(studioJSON.isEmpty)
        guard let dir = ProcessInfo.processInfo.environment["NEXAFIX_FIXTURE_DIR"], !dir.isEmpty else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try studioJSON.write(to: base.appendingPathComponent("scan_costing_spec.json"))

        let example = base.appendingPathComponent("example", isDirectory: true)
        try FileManager.default.createDirectory(at: example, withIntermediateDirectories: true)
        let p = Self.marina()
        try ScanExport.json(property: p, generatedAt: Self.generatedAt)
            .write(to: example.appendingPathComponent(ExportNaming.fileName(for: p, date: Self.generatedAt, kind: "scan", ext: "json")))
        try CostingSpecExport.json(property: p)
            .write(to: example.appendingPathComponent(ExportNaming.fileName(for: p, date: Self.generatedAt, kind: "costing-spec", ext: "json")))
        for file in CSVExport.files(for: p, units: .default) {
            try Data(file.content.utf8).write(to: example.appendingPathComponent(file.name))
        }
    }
}

/// Small seeded generator so the randomised tests are reproducible.
struct DataTestsSplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
