import XCTest
@testable import NexaFixCore

// Tests for the DXF exporter. Three layers:
//   1. unit tests of the encoders (numbers, text, colour, lineweight, handles);
//   2. structural tests that parse the exported text with a small independent DXF reader written here
//      (sections, tables, handles, entity counts, lengths, coordinates);
//   3. an external check (see `DXFExternalValidationTests`) that opens the same files with ezdxf when
//      Python and ezdxf are installed, audits them and renders them to PNG.

// MARK: - Minimal independent DXF reader (tests only)

/// One group code / value pair.
private struct DXFPair {
    let code: Int
    let value: String
}

/// A record: the group-0 type followed by its other groups, in file order.
private struct DXFRecord {
    let type: String
    let pairs: [DXFPair]

    func strings(_ code: Int) -> [String] { pairs.filter { $0.code == code }.map { $0.value } }
    func string(_ code: Int) -> String? { pairs.first(where: { $0.code == code })?.value }
    func double(_ code: Int) -> Double? { string(code).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
    func int(_ code: Int) -> Int? { string(code).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
    func doubles(_ code: Int) -> [Double] { strings(code).compactMap { Double($0) } }
    var layer: String { string(8) ?? "" }
    var handle: String? { string(5) ?? string(105) }
}

private struct DXFParsed {
    let sections: [(name: String, records: [DXFRecord])]
    let headerPairs: [DXFPair]
    let endsWithEOF: Bool

    func section(_ name: String) -> [DXFRecord] {
        sections.first(where: { $0.name == name })?.records ?? []
    }
    var entities: [DXFRecord] { section("ENTITIES") }

    /// Value groups following a header variable, e.g. `header("$INSUNITS")` -> [(70, "4")].
    func header(_ name: String) -> [DXFPair] {
        var found = false
        var out: [DXFPair] = []
        for pair in headerPairs {
            if pair.code == 9 {
                if found { break }
                found = pair.value == name
            } else if found {
                out.append(pair)
            }
        }
        return out
    }

    /// All handles the file defines (groups 5 and 105 on records outside HEADER).
    var definedHandles: [String] {
        sections.filter { $0.name != "HEADER" }.flatMap { $0.records.compactMap { $0.handle } }
    }

    /// Every reference to another object (owner 330, hard pointers 340, 350, 390).
    var referencedHandles: [String] {
        sections.filter { $0.name != "HEADER" }.flatMap { section in
            section.records.flatMap { record in
                record.pairs.filter { [330, 340, 350, 390].contains($0.code) }.map { $0.value }
            }
        }
    }
}

private enum DXFReader {
    /// Split into lines on LF and strip a trailing CR (byte level, so "\r\n" being one Character does not matter).
    static func lines(_ text: String) -> [String] {
        var lines: [String] = []
        var current: [UInt8] = []
        for byte in text.utf8 {
            if byte == 0x0A {
                if current.last == 0x0D { current.removeLast() }
                lines.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty { lines.append(String(decoding: current, as: UTF8.self)) }
        return lines
    }

    static func pairs(_ text: String) -> [DXFPair]? {
        let lines = lines(text)
        guard lines.count % 2 == 0 else { return nil }
        var pairs: [DXFPair] = []
        pairs.reserveCapacity(lines.count / 2)
        var i = 0
        while i < lines.count {
            guard let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) else { return nil }
            pairs.append(DXFPair(code: code, value: lines[i + 1]))
            i += 2
        }
        return pairs
    }

    static func parse(_ text: String) -> DXFParsed? {
        guard let all = pairs(text) else { return nil }
        var sections: [(name: String, records: [DXFRecord])] = []
        var headerPairs: [DXFPair] = []
        var i = 0
        var sawEOF = false
        while i < all.count {
            let pair = all[i]
            guard pair.code == 0 else { return nil }
            if pair.value == "EOF" {
                sawEOF = i == all.count - 1
                break
            }
            guard pair.value == "SECTION", i + 1 < all.count, all[i + 1].code == 2 else { return nil }
            let name = all[i + 1].value
            i += 2
            var body: [DXFPair] = []
            var closed = false
            while i < all.count {
                if all[i].code == 0 && all[i].value == "ENDSEC" {
                    closed = true
                    i += 1
                    break
                }
                body.append(all[i])
                i += 1
            }
            guard closed else { return nil }
            if name == "HEADER" {
                headerPairs = body
                sections.append((name, []))
                continue
            }
            var records: [DXFRecord] = []
            var type: String?
            var current: [DXFPair] = []
            for p in body {
                if p.code == 0 {
                    if let t = type { records.append(DXFRecord(type: t, pairs: current)) }
                    type = p.value
                    current = []
                } else {
                    current.append(p)
                }
            }
            if let t = type { records.append(DXFRecord(type: t, pairs: current)) }
            sections.append((name, records))
        }
        return DXFParsed(sections: sections, headerPairs: headerPairs, endsWithEOF: sawEOF)
    }
}

// MARK: - Fixtures

enum DXFFixtures {
    static let wall = StrokeStyle(weight: 0.5, color: .black)
    static let door = StrokeStyle(weight: 0.25, color: .black)
    static let thin = StrokeStyle(weight: 0.13, color: DrawColor(0.4, 0.4, 0.4))
    static let dim = StrokeStyle(weight: 0.13, color: DrawColor(0.2, 0.5, 0.2))
    static let dashedBlue = StrokeStyle(weight: 0.25, color: DrawColor(0, 0, 1), dashed: true)
    static let window = StrokeStyle(weight: 0.18, color: .black)
    static let red = StrokeStyle(weight: 0.13, color: DrawColor(1, 0, 0))
    static let ink = DrawColor(0.1, 0.1, 0.1)

    static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2] {
        [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]
    }

    /// A hand-built 5 x 4 m room: walls, a door with swing arc, a dashed boundary, windows, a fill-hatched
    /// wardrobe, a column, two dimensions, angle marks, rotated text with degree signs and a rotated note.
    static func samplePlan(origin: Point2 = .zero) -> PlanDrawing {
        let o = origin
        func p(_ x: Double, _ y: Double) -> Point2 { Point2(o.x + x, o.y + y) }
        func pts(_ list: [Point2]) -> [Point2] { list.map { Point2(o.x + $0.x, o.y + $0.y) } }

        var items: [LayeredPrimitive] = []
        // Walls: closed outline, two partition lines, a filled wall section (hatch only).
        items.append(LayeredPrimitive(.walls, .polyline(pts(box(0, 0, 5, 4)), closed: true, stroke: wall, fill: nil)))
        items.append(LayeredPrimitive(.walls, .line(p(2, 0), p(2, 1.5), wall)))
        items.append(LayeredPrimitive(.walls, .line(p(2, 1.5), p(3.2, 1.5), wall)))
        items.append(LayeredPrimitive(.walls, .polyline(pts(box(5, 0, 5.2, 4)), closed: true, stroke: nil,
                                                       fill: DrawColor(0.2, 0.2, 0.2))))
        // Door: leaf, head, swing arc.
        items.append(LayeredPrimitive(.doors, .line(p(3, 0), p(3, 0.9), door)))
        items.append(LayeredPrimitive(.doors, .line(p(3, 0), p(3.9, 0), door)))
        items.append(LayeredPrimitive(.doors, .arc(center: p(3, 0), radius: 0.9, startAngle: 0, endAngle: 90, door)))
        // Dashed open-plan boundary.
        items.append(LayeredPrimitive(.wallsOpen, .polyline(pts(box(0.5, 0.5, 4.5, 3.5)), closed: true,
                                                            stroke: dashedBlue, fill: nil)))
        // Window: three parallel lines.
        for dy in [-0.05, 0, 0.05] {
            items.append(LayeredPrimitive(.windows, .line(p(1, 4 + dy), p(2, 4 + dy), window)))
        }
        // Furniture: filled wardrobe, round column, open L-shaped polyline.
        items.append(LayeredPrimitive(.furniture, .polyline(pts(box(3.5, 2.5, 4.9, 3.1)), closed: true, stroke: thin,
                                                            fill: DrawColor(0.85, 0.85, 0.85))))
        items.append(LayeredPrimitive(.furniture, .circle(center: p(4.5, 3.6), radius: 0.15, thin)))
        items.append(LayeredPrimitive(.furniture, .polyline([p(0.2, 0.2), p(1.2, 0.2), p(1.2, 0.8)], closed: false,
                                                            stroke: thin, fill: nil)))
        // Dimensions: horizontal chain and a vertical one with 90 degree text.
        items.append(LayeredPrimitive(.dimensions, .line(p(0, -0.6), p(5, -0.6), dim)))
        items.append(LayeredPrimitive(.dimensions, .line(p(0, -0.1), p(0, -0.7), dim)))
        items.append(LayeredPrimitive(.dimensions, .line(p(5, -0.1), p(5, -0.7), dim)))
        items.append(LayeredPrimitive(.dimensions, .line(p(-0.6, 0), p(-0.6, 4), dim)))
        items.append(LayeredPrimitive(.dimensions, .text("5000 mm", at: p(2.5, -0.55), height: 0.125, rotation: 0,
                                                         anchor: .center, color: ink, bold: false)))
        items.append(LayeredPrimitive(.dimensions, .text("4000 mm", at: p(-0.65, 2), height: 0.125, rotation: 90,
                                                         anchor: .center, color: ink, bold: false)))
        // Angles: two arcs and a label with a degree sign.
        items.append(LayeredPrimitive(.angles, .arc(center: p(0, 0), radius: 0.25, startAngle: 0, endAngle: 90, red)))
        items.append(LayeredPrimitive(.angles, .arc(center: p(5, 4), radius: 0.25, startAngle: 180, endAngle: 270,
                                                    red)))
        items.append(LayeredPrimitive(.angles, .text("90.0\u{00B0}", at: p(0.3, 0.3), height: 0.1, rotation: 0,
                                                     anchor: .left, color: DrawColor(1, 0, 0), bold: false)))
        // Room labels: bold name, area with a superscript two.
        items.append(LayeredPrimitive(.roomLabels, .text("LIVING ROOM", at: p(2.5, 2.2), height: 0.18, rotation: 0,
                                                         anchor: .center, color: .black, bold: true)))
        items.append(LayeredPrimitive(.roomLabels, .text("20.0 m\u{00B2}", at: p(2.5, 1.9), height: 0.125, rotation: 0,
                                                         anchor: .center, color: .black, bold: false)))
        // Notes: rotated, right aligned, with degree and plus-minus; one with a diameter sign and a percent.
        items.append(LayeredPrimitive(.notes, .text("Tilt 12.5\u{00B0} \u{00B1}2 mm", at: p(5.4, 1.0), height: 0.1,
                                                    rotation: 30, anchor: .right, color: ink, bold: false)))
        items.append(LayeredPrimitive(.notes, .text("\u{2300}50 pipe at 100% \u{2013} check", at: p(1, -1.0),
                                                    height: 0.1, rotation: -45, anchor: .left, color: ink,
                                                    bold: false)))

        let bounds = Bounds2(min: p(-0.9, -2.4), max: p(5.6, 4.3))
        return PlanDrawing(primitives: items, bounds: bounds, options: PlanOptions(scale: 50),
                           title: "Sample", subtitle: "5 x 4 m")
    }
}

// MARK: - Helpers

/// Options for the tests of the plan-to-DXF mapping: the provenance note is off, so the entities in the file are
/// exactly the ones the input primitives map to. The note has its own tests (`DXFProvenanceNoteTests`).
private let dxfMappingOptions = DXFExporter.Options(includeProvenanceNote: false)

private func dxfExport(_ drawing: PlanDrawing, _ options: DXFExporter.Options = dxfMappingOptions) -> String {
    DXFExporter.export(drawing, options: options)
}

private func dxfParsed(_ drawing: PlanDrawing, _ options: DXFExporter.Options = dxfMappingOptions,
                    file: StaticString = #filePath, line: UInt = #line) throws -> DXFParsed {
    let text = DXFExporter.export(drawing, options: options)
    return try XCTUnwrap(DXFReader.parse(text), "exported text is not well-formed DXF", file: file, line: line)
}

private func dxfEmptyDrawing() -> PlanDrawing {
    PlanDrawing(primitives: [], bounds: Bounds2(min: .zero, max: .zero), options: PlanOptions())
}

private func dxfDrawing(_ items: [LayeredPrimitive], scale: Double = 50) -> PlanDrawing {
    var points: [Point2] = []
    for item in items {
        switch item.primitive {
        case let .line(a, b, _): points += [a, b]
        case let .polyline(p, _, _, _): points += p
        case let .arc(c, r, _, _, _): points += [Point2(c.x - r, c.y - r), Point2(c.x + r, c.y + r)]
        case let .circle(c, r, _): points += [Point2(c.x - r, c.y - r), Point2(c.x + r, c.y + r)]
        case let .text(_, at, _, _, _, _, _): points.append(at)
        }
    }
    let finite = points.filter { $0.x.isFinite && $0.y.isFinite }
    let bounds = Bounds2(points: finite) ?? Bounds2(min: .zero, max: .zero)
    return PlanDrawing(primitives: items, bounds: bounds, options: PlanOptions(scale: scale))
}

/// Count of entities by "LAYER|TYPE", computed from the input primitives the way the documented mapping says:
/// line -> LINE; stroked polyline -> LWPOLYLINE; filled polyline -> HATCH; arc -> ARC; circle -> CIRCLE; text -> TEXT.
private func dxfExpectedCounts(_ items: [LayeredPrimitive], text: Bool = true, fills: Bool = true) -> [String: Int] {
    var counts: [String: Int] = [:]
    func bump(_ layer: PlanLayer, _ type: String) { counts["\(layer.rawValue)|\(type)", default: 0] += 1 }
    for item in items {
        switch item.primitive {
        case .line: bump(item.layer, "LINE")
        case let .polyline(_, _, stroke, fill):
            if stroke != nil { bump(item.layer, "LWPOLYLINE") }
            if fill != nil && fills { bump(item.layer, "HATCH") }
        case .arc: bump(item.layer, "ARC")
        case .circle: bump(item.layer, "CIRCLE")
        case .text: if text { bump(item.layer, "TEXT") }
        }
    }
    return counts
}

private func dxfActualCounts(_ doc: DXFParsed) -> [String: Int] {
    var counts: [String: Int] = [:]
    for record in doc.entities { counts["\(record.layer)|\(record.type)", default: 0] += 1 }
    return counts
}

private func dxfLineLength(_ items: [LayeredPrimitive]) -> Double {
    items.reduce(0) { total, item in
        if case let .line(a, b, _) = item.primitive { return total + a.distance(to: b) }
        return total
    }
}

private func dxfLineLength(_ doc: DXFParsed) -> Double {
    doc.entities.filter { $0.type == "LINE" }.reduce(0) { total, record in
        guard let x1 = record.double(10), let y1 = record.double(20), let x2 = record.double(11),
              let y2 = record.double(21) else { return total }
        return total + ((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)).squareRoot()
    }
}

private func dxfIsASCII(_ text: String) -> Bool { text.utf8.allSatisfy { $0 < 0x80 } }

// MARK: - 1. Encoders

final class DXFEncoderTests: XCTestCase {

    func testNumbersArePlainDecimalsWithOneTrailingDigit() {
        XCTAssertEqual(DXFFormat.number(0), "0.0")
        XCTAssertEqual(DXFFormat.number(-0.0), "0.0")
        XCTAssertEqual(DXFFormat.number(1), "1.0")
        XCTAssertEqual(DXFFormat.number(-2.5), "-2.5")
        XCTAssertEqual(DXFFormat.number(0.1 + 0.2), "0.3")
        XCTAssertEqual(DXFFormat.number(100_000), "100000.0")
        XCTAssertEqual(DXFFormat.number(100_000.123456789), "100000.123456789")
        XCTAssertEqual(DXFFormat.number(1e9 + 0.5), "1000000000.5")
        XCTAssertEqual(DXFFormat.number(1e-12), "0.0")          // below nine decimals
        XCTAssertEqual(DXFFormat.number(-1e-12), "0.0")         // never "-0.0"
        XCTAssertEqual(DXFFormat.number(2.9999999999), "3.0")
        XCTAssertEqual(DXFFormat.number(.nan), "0.0")
        XCTAssertEqual(DXFFormat.number(.infinity), "0.0")
        XCTAssertFalse(DXFFormat.number(1.5e11).contains("e"), "no exponent notation")
        XCTAssertFalse(DXFFormat.number(1.5e11).contains(","), "no locale separators")
    }

    func testNumbersRoundTripThroughAParser() {
        var generator = DXFSeededGenerator(seed: 7)
        for _ in 0..<500 {
            let v = Double.random(in: -2_000_000...2_000_000, using: &generator)
            let parsed = Double(DXFFormat.number(v))
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed ?? .nan, v, accuracy: 6e-10)
        }
    }

    func testTextControlCodesForDegreePlusMinusDiameter() {
        XCTAssertEqual(DXFFormat.text("90.0\u{00B0}"), "90.0%%d")
        XCTAssertEqual(DXFFormat.text("\u{00B1}22 mm"), "%%p22 mm")
        XCTAssertEqual(DXFFormat.text("\u{2300}50"), "%%c50")
        XCTAssertEqual(DXFFormat.text("\u{2205}"), "%%c")
        XCTAssertEqual(DXFFormat.text("12.5\u{00B0} \u{00B1}0.5\u{00B0}"), "12.5%%d %%p0.5%%d")
    }

    func testTextUnicodeEscapes() {
        XCTAssertEqual(DXFFormat.text("20.0 m\u{00B2}"), "20.0 m\\U+00B2")
        XCTAssertEqual(DXFFormat.text("a\u{2013}b"), "a\\U+2013b")
        XCTAssertEqual(DXFFormat.text("\u{00D8}stergade"), "\\U+00D8stergade")    // Latin O-stroke is a letter, not a diameter
        XCTAssertEqual(DXFFormat.text("\u{0645}"), "\\U+0645")
        XCTAssertEqual(DXFFormat.text("\u{1F600}"), "\\U+D83D\\U+DE00")          // surrogate pair
        XCTAssertEqual(DXFFormat.text("caf\u{00E9}"), "caf\\U+00E9")
    }

    func testPercentSignsThatWouldBecomeControlCodesAreEscaped() {
        XCTAssertEqual(DXFFormat.text("100%"), "100%")
        XCTAssertEqual(DXFFormat.text("50% off"), "50% off")
        XCTAssertEqual(DXFFormat.text("50%%"), "50%%037%%037")
        XCTAssertEqual(DXFFormat.text("%\u{00B0}"), "%%037%%d")
        XCTAssertEqual(DXFFormat.text("\u{00B0}%"), "%%d%")
        XCTAssertEqual(DXFFormat.text("%%d"), "%%037%%037d")       // literal text "%%d" must not become a degree sign
    }

    func testTextBackslashAndControlCharacters() {
        XCTAssertEqual(DXFFormat.text("a\\U+0041"), "a\\U+005CU+0041")
        XCTAssertEqual(DXFFormat.text("line1\nline2\r\n\ttab"), "line1 line2   tab")
        XCTAssertEqual(DXFFormat.text("a\u{0000}b\u{007F}c"), "a b c")
        XCTAssertEqual(DXFFormat.text(""), "")
    }

    func testTextIsCutOnAnEscapeBoundary() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(DXFFormat.text(long).count, 255)
        // 254 plain characters then a superscript two: the nine-character escape does not fit, so it is dropped whole.
        let nearLimit = String(repeating: "a", count: 254) + "\u{00B2}"
        XCTAssertEqual(DXFFormat.text(nearLimit), String(repeating: "a", count: 254))
        // 252 plain characters then a degree sign: "%%d" is three characters and fits exactly.
        let fits = String(repeating: "a", count: 252) + "\u{00B0}"
        XCTAssertEqual(DXFFormat.text(fits).count, 255)
        XCTAssertTrue(DXFFormat.text(fits).hasSuffix("%%d"))
    }

    func testSafeLineNeverBreaksTheGroupStructure() {
        XCTAssertEqual(DXFFormat.safeLine("abc\n  0\nEOF"), "abc   0 EOF")
        XCTAssertEqual(DXFFormat.safeLine("a\r\nb"), "a  b")
        XCTAssertEqual(DXFFormat.safeLine("m\u{00B2}"), "m\\U+00B2")
        var w = DXFWriter()
        w.tag(1, "x\ny")
        XCTAssertEqual(DXFReader.lines(w.output), ["  1", "x y"])
    }

    func testWriterPadsGroupCodesAndHonoursLineEndings() {
        var lf = DXFWriter()
        lf.tag(0, "SECTION"); lf.tag(100, "AcDbEntity"); lf.tag(370, -1); lf.tag(40, 2.5); lf.point(1, 2, 3, code: 10)
        XCTAssertEqual(lf.output, "  0\nSECTION\n100\nAcDbEntity\n370\n-1\n 40\n2.5\n 10\n1.0\n 20\n2.0\n 30\n3.0\n")
        var crlf = DXFWriter(windowsLineEndings: true)
        crlf.tag(8, "NF-WALLS")
        XCTAssertEqual(Array(crlf.output.utf8), Array("  8\r\nNF-WALLS\r\n".utf8))
    }

    func testHandlesAreHexAscendingAndSeedIsBeyondTheLastOne() {
        var a = DXFHandleAllocator(first: 1)
        let first = (0..<20).map { _ in a.allocate() }
        XCTAssertEqual(first.prefix(10).map { $0 }, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A"])
        XCTAssertEqual(first[15], "10")
        XCTAssertEqual(first.last, "14")
        XCTAssertEqual(a.seed, "15")
        XCTAssertEqual(Set(first).count, first.count)
        var zero = DXFHandleAllocator(first: 0)
        XCTAssertEqual(zero.allocate(), "1", "handle 0 means null and is never issued")
    }

    func testNearestACIMatchesHandWorkedColours() {
        XCTAssertEqual(DXFColor.nearestACI(.black), 7)
        XCTAssertEqual(DXFColor.nearestACI(.white), 255)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(1, 0, 0)), 1)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(1, 1, 0)), 2)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(0, 1, 0)), 3)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(0, 1, 1)), 4)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(0, 0, 1)), 5)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(1, 0, 1)), 6)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x333333)), 7)         // dark neutral: ink, ACI 7
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x1F1D1A)), 7)         // the plan's ink
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x3F3F3F)), 7)         // 63: the last near-black value
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x404040)), 251)       // 64 is a grey: ACI 251 = 91 is nearest
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x3F0000)), 16, "dark red is a colour, not ink")
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x848484)), 252)       // 132: 19 from ACI 252 = 113, 20 from 253
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0xFF7F00)), 30)        // orange
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x7F0000)), 14)        // half-brightness red
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0xFF7F7F)), 11)        // pastel red
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(hex: 0x0000FF)), 5)
        // Out-of-range and NaN components are clamped, never crash.
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(2, 2, 2)), 255)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(-1, -1, -1)), 7)
        XCTAssertEqual(DXFColor.nearestACI(DrawColor(.nan, .nan, .nan)), 7)
    }

    func testNearestACIAgainstBruteForce() {
        func check(_ r: Int, _ g: Int, _ b: Int, file: StaticString = #filePath, line: UInt = #line) {
            let color = DrawColor(Double(r) / 255, Double(g) / 255, Double(b) / 255)
            let chosen = DXFColor.nearestACI(color)
            let neutral = max(r, g, b) - min(r, g, b) <= 24
            if neutral && max(r, g, b) < 64 {
                XCTAssertEqual(chosen, 7, "near-black neutral (\(r),\(g),\(b)) is ink", file: file, line: line)
                return
            }
            guard let c = DXFColor.rgb(ofACI: chosen) else {
                return XCTFail("ACI \(chosen) is not a candidate index", file: file, line: line)
            }
            if neutral {
                XCTAssertTrue(c.r == c.g && c.g == c.b, "neutral (\(r),\(g),\(b)) maps to a neutral ACI", file: file, line: line)
            }
            let best = (c.r - r) * (c.r - r) + (c.g - g) * (c.g - g) + (c.b - b) * (c.b - b)
            for other in DXFColor.candidates where !neutral || (other.r == other.g && other.g == other.b) {
                let d = (other.r - r) * (other.r - r) + (other.g - g) * (other.g - g) + (other.b - b) * (other.b - b)
                XCTAssertLessThanOrEqual(best, d, "ACI \(chosen) is not the nearest for (\(r),\(g),\(b))", file: file, line: line)
            }
        }
        var generator = DXFSeededGenerator(seed: 99)
        for _ in 0..<400 {
            check(Int.random(in: 0...255, using: &generator), Int.random(in: 0...255, using: &generator),
                  Int.random(in: 0...255, using: &generator))
        }
        // Neutral colours are rare in a uniform sample: walk every grey, and greys with a warm or cool tint.
        for v in 0...255 {
            check(v, v, v)
            check(min(255, v + 20), v, max(0, v - 4))
            check(max(0, v - 5), v, min(255, v + 19))
        }
    }

    func testPaletteEntriesAndIndices() {
        func rgb(_ i: Int) -> [Int]? { DXFColor.rgb(ofACI: i).map { [$0.r, $0.g, $0.b] } }
        XCTAssertEqual(rgb(1), [255, 0, 0])
        XCTAssertEqual(rgb(10), [255, 0, 0])
        XCTAssertEqual(rgb(11), [255, 127, 127])
        XCTAssertEqual(rgb(14), [127, 0, 0])
        XCTAssertEqual(rgb(15), [127, 63, 63])
        XCTAssertEqual(rgb(16), [76, 0, 0])
        XCTAssertEqual(rgb(17), [76, 38, 38])
        XCTAssertEqual(rgb(20), [255, 63, 0])
        XCTAssertEqual(rgb(30), [255, 127, 0])
        XCTAssertEqual(rgb(40), [255, 191, 0])
        XCTAssertEqual(rgb(50), [255, 255, 0])
        XCTAssertEqual(rgb(60), [191, 255, 0])
        XCTAssertEqual(rgb(90), [0, 255, 0])
        XCTAssertEqual(rgb(94), [0, 127, 0])
        XCTAssertEqual(rgb(95), [63, 127, 63])
        XCTAssertEqual(rgb(130), [0, 255, 255])
        XCTAssertEqual(rgb(150), [0, 127, 255])
        XCTAssertEqual(rgb(170), [0, 0, 255])
        XCTAssertEqual(rgb(190), [127, 0, 255])
        XCTAssertEqual(rgb(210), [255, 0, 255])
        XCTAssertEqual(rgb(240), [255, 0, 63])
        XCTAssertEqual(rgb(255), [255, 255, 255])
        // Greys: only the middle of the ramp, at the middle of the values in circulation.
        XCTAssertEqual(rgb(251), [91, 91, 91]); XCTAssertEqual(rgb(252), [113, 113, 113])
        XCTAssertEqual(rgb(253), [152, 152, 152]); XCTAssertEqual(rgb(254), [203, 203, 203])
        XCTAssertNil(rgb(250), "ACI 250 is 51 in some tables and black in others")
        XCTAssertNil(rgb(8), "ACI 8 and 9 are excluded: applications disagree on their brightness")
        XCTAssertNil(rgb(9))
        for irregular in [147, 157, 167, 177, 187, 197] {
            XCTAssertNil(rgb(irregular), "ACI \(irregular) has blue 126 in the AutoCAD table, not the ramp's 76")
        }
        XCTAssertNil(rgb(0)); XCTAssertNil(rgb(256))
        let indices = DXFColor.candidates.map { $0.index }
        XCTAssertEqual(Set(indices).count, indices.count, "no duplicate candidate")
        XCTAssertTrue(indices.allSatisfy { (1...255).contains($0) })
        // 6 pure + black, 24 hues x 6 variants less the 6 irregular entries, 4 greys and white.
        XCTAssertEqual(indices.count, 7 + 24 * 6 - 6 + 4 + 1)
    }

    /// The grey ramp is the one place the sources disagree; every entry stays within 25 of each value in circulation.
    func testGreyRampIsWithinTolerableDistanceOfEveryPublishedTable() {
        let sources: [[Int]] = [[80, 105, 130, 190], [101, 102, 153, 204], [91, 132, 173, 214]]
        for (offset, index) in [251, 252, 253, 254].enumerated() {
            let value = DXFColor.rgb(ofACI: index)?.r ?? -999
            for source in sources {
                XCTAssertLessThanOrEqual(abs(value - source[offset]), 25, "ACI \(index) against \(source[offset])")
            }
        }
    }

    func testPlanColoursMapToTheColoursTheyShouldBe() throws {
        typealias Palette = PlanDrawingBuilder.Palette
        XCTAssertEqual(DXFColor.nearestACI(Palette.ink), 7, "ink follows the CAD background")
        // The status colours are pinned to an unmistakable red and green; the nearest entries would be an orange-red
        // (ACI 20, 255/63/0) and a greyish green (ACI 105).
        XCTAssertEqual(DXFColor.aci(for: Palette.warning), 1)
        XCTAssertEqual(DXFColor.aci(for: Palette.verified), 94)
        XCTAssertEqual(DXFColor.nearestACI(Palette.warning), 20)
        XCTAssertEqual(DXFColor.aci(for: Palette.ink), 7, "other colours are the nearest entry")
        XCTAssertEqual(DXFColor.aci(for: DrawColor(hex: 0xC62829)), DXFColor.nearestACI(DrawColor(hex: 0xC62829)),
                       "one byte off the warning colour is not the warning colour")
        XCTAssertEqual(DXFColor.nearestACI(Palette.paper), 255)
        XCTAssertEqual(DXFColor.nearestACI(Palette.muted), 252)                    // (122, 114, 104) against grey 113
        XCTAssertEqual(DXFColor.nearestACI(Palette.furnitureFill), 254)           // (230, 225, 217) against grey 203
        XCTAssertTrue(DXFColor.isPlanStatusColor(Palette.verified))
        XCTAssertTrue(DXFColor.isPlanStatusColor(Palette.warning))
        for colour in [Palette.ink, Palette.muted, Palette.bronze, Palette.paper, Palette.hairline, Palette.furnitureFill,
                       DrawColor.black, DrawColor(0.18, 0.48, 0.30), DrawColor(0.78, 0.16, 0.16)] {
            XCTAssertFalse(DXFColor.isPlanStatusColor(colour), "\(colour)")
        }
    }

    func testTrueColorPacksRGB() {
        XCTAssertEqual(DXFColor.trueColor(DrawColor(1, 0, 0)), 0xFF0000)
        XCTAssertEqual(DXFColor.trueColor(DrawColor(hex: 0x12AB9F)), 0x12AB9F)
        XCTAssertEqual(DXFColor.trueColor(DrawColor(2, -1, .nan)), 0xFF0000)
        XCTAssertEqual(DXFColor.trueColor(.white), 0xFFFFFF)
    }

    func testLineweightNearestValid() {
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.25), 25)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.5), 50)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.18), 18)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.19), 18, "tie between 18 and 20 goes to the thinner")
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.1), 9)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.55), 53)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0.045), 5)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 0), 0)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 1.0), 100)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 1.9), 200)
        XCTAssertEqual(DXFLineweight.nearest(toMillimetres: 9), 211, "heavier than the maximum clamps to 2.11 mm")
        XCTAssertNil(DXFLineweight.nearest(toMillimetres: -0.1))
        XCTAssertNil(DXFLineweight.nearest(toMillimetres: .nan))
        XCTAssertNil(DXFLineweight.nearest(toMillimetres: .infinity))
        // Every result is on the list AutoCAD accepts.
        let accepted: Set<Int> = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140,
                                  158, 200, 211]
        for hundredths in stride(from: 0, through: 400, by: 3) {
            XCTAssertTrue(accepted.contains(DXFLineweight.nearest(toMillimetres: Double(hundredths) / 100) ?? -9))
        }
    }

    func testLayerStylesAreDistinctAndValid() {
        let styles = PlanLayer.allCases.map { DXFLayerStyle.style(for: $0) }
        XCTAssertEqual(styles.count, 10)
        XCTAssertEqual(Set(styles.map { $0.aci }).count, styles.count, "layer colours are distinct")
        XCTAssertTrue(styles.allSatisfy { (1...255).contains($0.aci) && $0.aci != 0 && $0.aci != 256 })
        XCTAssertTrue(styles.allSatisfy { DXFLineweight.valid.contains($0.lineweight) })
        XCTAssertGreaterThan(DXFLayerStyle.style(for: .walls).lineweight, DXFLayerStyle.style(for: .dimensions).lineweight,
                             "walls are heavier than dimension lines")
    }
}

/// Deterministic generator so the randomised tests are reproducible.
private struct DXFSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - 2. Structure and content

final class DXFExporterTests: XCTestCase {

    // MARK: document structure

    func testSectionsAreInAutoCADOrderAndEndWithEOF() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        XCTAssertEqual(doc.sections.map { $0.name }, ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"])
        XCTAssertTrue(doc.endsWithEOF, "EOF is the last group of the file")
        let text = dxfExport(DXFFixtures.samplePlan())
        XCTAssertTrue(text.hasPrefix("  0\nSECTION\n  2\nHEADER\n"))
        XCTAssertTrue(text.hasSuffix("  0\nEOF\n"))
    }

    func testEveryGroupCodeIsValidAndPairsAreComplete() throws {
        let text = dxfExport(DXFFixtures.samplePlan())
        let pairs = try XCTUnwrap(DXFReader.pairs(text))
        XCTAssertGreaterThan(pairs.count, 500)
        XCTAssertTrue(pairs.allSatisfy { (0...1071).contains($0.code) })
        XCTAssertTrue(dxfIsASCII(text), "output is 7-bit ASCII so UTF-8 and Windows-1252 writes are identical")
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("nan") || lower.contains("inf"), "no non-finite number leaked into the file")
    }

    func testHeaderVariables() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        XCTAssertEqual(doc.header("$ACADVER").first?.value, "AC1015")
        XCTAssertEqual(doc.header("$INSUNITS").first?.value, "4")
        XCTAssertEqual(doc.header("$MEASUREMENT").first?.value, "1")
        XCTAssertEqual(doc.header("$DWGCODEPAGE").first?.value, "ANSI_1252")
        XCTAssertEqual(doc.header("$LTSCALE").first?.value, "1.0")
        XCTAssertEqual(doc.header("$CLAYER").first?.value, "0")
        XCTAssertEqual(doc.header("$TEXTSTYLE").first?.value, "Standard")
        // Drawing bounds (-0.9, -2.4) to (5.6, 4.3) m, in millimetres.
        XCTAssertEqual(doc.header("$EXTMIN").compactMap { Double($0.value) }, [-900, -2400, 0])
        XCTAssertEqual(doc.header("$EXTMAX").compactMap { Double($0.value) }, [5600, 4300, 0])
        XCTAssertEqual(doc.header("$DIMSCALE").first?.value, "50.0")
        XCTAssertEqual(doc.header("$TEXTSIZE").first?.value, "125.0")      // 2.5 mm on paper at 1:50
        // Paper space limits are an A3 sheet in drawing units (LibreCAD sizes its print page from them).
        XCTAssertEqual(doc.header("$PLIMMIN").compactMap { Double($0.value) }, [0, 0])
        XCTAssertEqual(doc.header("$PLIMMAX").compactMap { Double($0.value) }, [420, 297])
    }

    func testMetreUnits() throws {
        var options = dxfMappingOptions
        options.units = .metres
        let doc = try dxfParsed(DXFFixtures.samplePlan(), options)
        XCTAssertEqual(doc.header("$INSUNITS").first?.value, "6")
        XCTAssertEqual(doc.header("$EXTMIN").compactMap { Double($0.value) }, [-0.9, -2.4, 0])
        XCTAssertEqual(doc.header("$EXTMAX").compactMap { Double($0.value) }, [5.6, 4.3, 0])
        XCTAssertEqual(doc.header("$PLIMMAX").compactMap { Double($0.value) }, [0.42, 0.297])
        XCTAssertEqual(DXFUnits.metres.insunitsCode, 6)
        XCTAssertEqual(DXFUnits.millimetres.insunitsCode, 4)
        XCTAssertEqual(DXFUnits.metres.unitsPerMetre, 1)
        XCTAssertEqual(DXFUnits.millimetres.unitsPerMetre, 1000)
        // The 5 x 4 m outline is 5.0 x 4.0 in the file.
        let outline = try XCTUnwrap(doc.entities.first(where: { $0.type == "LWPOLYLINE" }))
        XCTAssertEqual(outline.doubles(10), [0, 5, 5, 0])
        XCTAssertEqual(outline.doubles(20), [0, 0, 4, 4])
        // Text height 0.125 m stays 0.125, not 125.
        let text = try XCTUnwrap(doc.entities.first(where: { $0.type == "TEXT" }))
        XCTAssertEqual(text.double(40), 0.125)
        XCTAssertEqual(dxfLineLength(doc), 17.7, accuracy: 1e-9)
    }

    func testTablesAreCompleteAndCountsMatch() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let records = doc.section("TABLES")
        let tables = records.filter { $0.type == "TABLE" }
        XCTAssertEqual(tables.compactMap { $0.string(2) },
                       ["VPORT", "LTYPE", "LAYER", "STYLE", "VIEW", "UCS", "APPID", "DIMSTYLE", "BLOCK_RECORD"])
        // Group 70 of each table header equals the number of records it holds.
        var current: String?
        var counts: [String: Int] = [:]
        for record in records {
            if record.type == "TABLE" { current = record.string(2); counts[current ?? ""] = 0 }
            else if record.type == "ENDTAB" { current = nil }
            else if let c = current { counts[c, default: 0] += 1 }
        }
        for table in tables {
            let name = table.string(2) ?? ""
            XCTAssertEqual(table.int(70), counts[name], "table \(name) record count")
        }
        XCTAssertEqual(counts["LAYER"], 11)
        XCTAssertEqual(counts["LTYPE"], 4)
        XCTAssertEqual(counts["STYLE"], 2)
        XCTAssertEqual(counts["BLOCK_RECORD"], 2)
    }

    func testLayerTableHasEveryPlanLayerWithItsColourAndLineweight() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let layers = doc.section("TABLES").filter { $0.type == "LAYER" }
        XCTAssertEqual(layers.count, 11)
        // Hand-typed expectation: ACI colour and lineweight (1/100 mm).
        let expected: [String: (aci: Int, lineweight: Int)] = [
            "NF-WALLS": (7, 50), "NF-WALLS-OPEN": (150, 25), "NF-DOORS": (30, 25), "NF-WINDOWS": (4, 25),
            "NF-OPENINGS": (6, 25), "NF-FURNITURE": (8, 13), "NF-DIMENSIONS": (190, 13), "NF-ANGLES": (42, 13),
            "NF-ROOM-LABELS": (5, 18), "NF-NOTES": (32, 18),
        ]
        for layer in PlanLayer.allCases {
            let record = try XCTUnwrap(layers.first(where: { $0.string(2) == layer.rawValue }), layer.rawValue)
            XCTAssertEqual(record.int(62), expected[layer.rawValue]?.aci, layer.rawValue)
            XCTAssertEqual(record.int(370), expected[layer.rawValue]?.lineweight, layer.rawValue)
            XCTAssertEqual(record.string(6), "Continuous")
            XCTAssertEqual(record.int(70), 0, "layers are on, thawed and unlocked")
        }
        XCTAssertNotNil(layers.first(where: { $0.string(2) == "0" }))
        let colours = layers.filter { $0.string(2) != "0" }.compactMap { $0.int(62) }
        XCTAssertEqual(Set(colours).count, 10, "ten distinct ACI colours")
    }

    func testLinetypeStyleAndBlockRecords() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let tables = doc.section("TABLES")
        let ltypes = tables.filter { $0.type == "LTYPE" }
        XCTAssertEqual(ltypes.compactMap { $0.string(2) }, ["ByBlock", "ByLayer", "Continuous", "DASHED"])
        let dashed = try XCTUnwrap(ltypes.last)
        XCTAssertEqual(dashed.int(73), 2, "two pattern elements")
        // Plan scale 1:50: 3 mm dash and 1.5 mm gap on paper are 150 mm and 75 mm in model space.
        XCTAssertEqual(dashed.doubles(49), [150, -75])
        XCTAssertEqual(dashed.double(40), 225, "pattern length is the sum of absolute element lengths")
        XCTAssertEqual(dashed.int(72), 65)
        let styles = tables.filter { $0.type == "STYLE" }
        XCTAssertEqual(styles.compactMap { $0.string(2) }, ["Standard", "NF-BOLD"])
        XCTAssertEqual(styles.compactMap { $0.string(3) }, ["arial.ttf", "arialbd.ttf"])
        XCTAssertEqual(styles[1].int(1071), 33_554_466, "bold + Arial family flag in the ACAD XDATA")
        XCTAssertEqual(tables.filter { $0.type == "APPID" }.compactMap { $0.string(2) }, ["ACAD"])
        XCTAssertEqual(tables.filter { $0.type == "BLOCK_RECORD" }.compactMap { $0.string(2) },
                       ["*Model_Space", "*Paper_Space"])
        XCTAssertEqual(tables.filter { $0.type == "VPORT" }.compactMap { $0.string(2) }, ["*Active"])
        XCTAssertEqual(tables.filter { $0.type == "DIMSTYLE" }.compactMap { $0.string(2) }, ["Standard"])
    }

    func testPlanScaleDrivesDashPatternAndDimensionScale() throws {
        let one100 = dxfDrawing([], scale: 100)
        let doc = try dxfParsed(one100)
        let dashed = try XCTUnwrap(doc.section("TABLES").first(where: { $0.string(2) == "DASHED" }))
        XCTAssertEqual(dashed.doubles(49), [300, -150])
        XCTAssertEqual(doc.header("$DIMSCALE").first?.value, "100.0")
        // A nonsense scale falls back to 1:50 instead of writing a zero-length pattern.
        for bad in [0.0, -5.0, .nan, .infinity] {
            let d = try dxfParsed(dxfDrawing([], scale: bad))
            let ltype = try XCTUnwrap(d.section("TABLES").first(where: { $0.string(2) == "DASHED" }))
            XCTAssertEqual(ltype.doubles(49), [150, -75], "scale \(bad)")
        }
        // In metres the same pattern is 0.15 m and 0.075 m.
        var options = dxfMappingOptions
        options.units = .metres
        let m = try dxfParsed(dxfDrawing([], scale: 50), options)
        let metric = try XCTUnwrap(m.section("TABLES").first(where: { $0.string(2) == "DASHED" }))
        XCTAssertEqual(metric.doubles(49).count, 2)
        XCTAssertEqual(metric.doubles(49)[0], 0.15, accuracy: 1e-12)
        XCTAssertEqual(metric.doubles(49)[1], -0.075, accuracy: 1e-12)
    }

    func testBlocksForModelAndPaperSpace() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let blocks = doc.section("BLOCKS")
        XCTAssertEqual(blocks.map { $0.type }, ["BLOCK", "ENDBLK", "BLOCK", "ENDBLK"])
        XCTAssertEqual(blocks[0].string(2), "*Model_Space")
        XCTAssertEqual(blocks[2].string(2), "*Paper_Space")
        XCTAssertEqual(blocks[2].int(67), 1, "paper space block is flagged")
        let recordHandles = doc.section("TABLES").filter { $0.type == "BLOCK_RECORD" }.compactMap { $0.handle }
        XCTAssertEqual(blocks[0].string(330), recordHandles[0])
        XCTAssertEqual(blocks[1].string(330), recordHandles[0])
        XCTAssertEqual(blocks[2].string(330), recordHandles[1])
        XCTAssertEqual(blocks[0].strings(100), ["AcDbEntity", "AcDbBlockBegin"])
        XCTAssertEqual(blocks[1].strings(100), ["AcDbEntity", "AcDbBlockEnd"])
    }

    func testObjectsSectionHasRootDictionaryAndLayouts() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let objects = doc.section("OBJECTS")
        let root = try XCTUnwrap(objects.first)
        XCTAssertEqual(root.type, "DICTIONARY")
        XCTAssertEqual(root.string(330), "0", "the root dictionary has no owner")
        XCTAssertEqual(root.strings(3), ["ACAD_GROUP", "ACAD_LAYOUT", "ACAD_MLINESTYLE", "ACAD_PLOTSETTINGS",
                                         "ACAD_PLOTSTYLENAME"])
        XCTAssertEqual(objects.filter { $0.type == "LAYOUT" }.compactMap { $0.strings(1).last }, ["Model", "Layout1"])
        XCTAssertEqual(objects.filter { $0.type == "ACDBPLACEHOLDER" }.count, 1)
        // The CLASSES section declares exactly the non-entity classes used.
        let classes = doc.section("CLASSES").compactMap { $0.string(1) }
        XCTAssertEqual(classes, ["ACDBDICTIONARYWDFLT", "ACDBPLACEHOLDER", "LAYOUT"])
        // Block records point at their layouts and the layouts point back.
        let blockRecords = doc.section("TABLES").filter { $0.type == "BLOCK_RECORD" }
        let layouts = objects.filter { $0.type == "LAYOUT" }
        for (record, layout) in zip(blockRecords, layouts) {
            XCTAssertEqual(record.string(340), layout.handle)
            XCTAssertEqual(layout.strings(330).last, record.handle)
        }
    }

    // MARK: handles

    func testHandlesAreUniqueResolvableAndBelowTheSeed() throws {
        for item in [DXFFixtures.samplePlan(), dxfEmptyDrawing()] {
            let doc = try dxfParsed(item)
            let defined = doc.definedHandles
            XCTAssertEqual(Set(defined).count, defined.count, "every handle is unique")
            XCTAssertFalse(defined.contains("0"))
            XCTAssertTrue(defined.allSatisfy { $0.range(of: "^[0-9A-F]+$", options: .regularExpression) != nil })
            let numbers = defined.compactMap { Int($0, radix: 16) }
            let seed = try XCTUnwrap(Int(doc.header("$HANDSEED").first?.value ?? "", radix: 16))
            XCTAssertGreaterThan(seed, numbers.max() ?? 0, "$HANDSEED is beyond every handle used")
            let known = Set(defined).union(["0"])
            for reference in doc.referencedHandles {
                XCTAssertTrue(known.contains(reference), "dangling reference \(reference)")
            }
        }
    }

    func testEveryEntityIsOwnedByModelSpaceAndOnAKnownLayer() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let modelRecord = try XCTUnwrap(doc.section("TABLES").first(where: { $0.string(2) == "*Model_Space" })?.handle)
        let layerNames = Set(doc.section("TABLES").filter { $0.type == "LAYER" }.compactMap { $0.string(2) })
        XCTAssertGreaterThan(doc.entities.count, 25)
        for entity in doc.entities {
            XCTAssertEqual(entity.string(330), modelRecord, "\(entity.type) owner")
            XCTAssertTrue(layerNames.contains(entity.layer), "layer \(entity.layer)")
            XCTAssertNotNil(entity.handle)
            XCTAssertEqual(entity.strings(100).first, "AcDbEntity")
        }
    }

    func testSubclassMarkersAndGroupOrderPerEntityType() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let expected: [String: [String]] = [
            "LINE": ["AcDbEntity", "AcDbLine"],
            "LWPOLYLINE": ["AcDbEntity", "AcDbPolyline"],
            "ARC": ["AcDbEntity", "AcDbCircle", "AcDbArc"],
            "CIRCLE": ["AcDbEntity", "AcDbCircle"],
            "TEXT": ["AcDbEntity", "AcDbText", "AcDbText"],
            "HATCH": ["AcDbEntity", "AcDbHatch"],
        ]
        var seen = Set<String>()
        for entity in doc.entities {
            XCTAssertEqual(entity.strings(100), expected[entity.type], entity.type)
            seen.insert(entity.type)
            if entity.type == "TEXT" {
                // The second AcDbText marker introduces the vertical alignment group (73).
                let codes = entity.pairs.map { $0.code }
                let secondMarker = codes.indices.filter { codes[$0] == 100 }.last ?? 0
                XCTAssertEqual(codes[secondMarker + 1], 73)
                XCTAssertEqual(entity.int(73), 0, "text anchors are baseline anchors")
            }
        }
        XCTAssertEqual(seen, Set(expected.keys), "the sample exercises every entity type")
    }

    // MARK: counts, lengths, geometry

    func testEntityCountsPerLayerAndTypeMatchTheInput() throws {
        let plan = DXFFixtures.samplePlan()
        let doc = try dxfParsed(plan)
        // Counted by hand from the fixture.
        let byHand: [String: Int] = [
            "NF-WALLS|LWPOLYLINE": 1, "NF-WALLS|LINE": 2, "NF-WALLS|HATCH": 1,
            "NF-DOORS|LINE": 2, "NF-DOORS|ARC": 1,
            "NF-WALLS-OPEN|LWPOLYLINE": 1,
            "NF-WINDOWS|LINE": 3,
            "NF-FURNITURE|LWPOLYLINE": 2, "NF-FURNITURE|HATCH": 1, "NF-FURNITURE|CIRCLE": 1,
            "NF-DIMENSIONS|LINE": 4, "NF-DIMENSIONS|TEXT": 2,
            "NF-ANGLES|ARC": 2, "NF-ANGLES|TEXT": 1,
            "NF-ROOM-LABELS|TEXT": 2,
            "NF-NOTES|TEXT": 2,
        ]
        XCTAssertEqual(dxfActualCounts(doc), byHand)
        XCTAssertEqual(dxfExpectedCounts(plan.primitives), byHand, "the counting helper agrees with the hand count")
        XCTAssertEqual(doc.entities.count, 28)
    }

    func testTotalLineLengthEqualsInput() throws {
        let plan = DXFFixtures.samplePlan()
        let doc = try dxfParsed(plan)
        // 2.7 (walls) + 1.8 (door) + 3.0 (window) + 10.2 (dimensions) = 17.7 m.
        XCTAssertEqual(dxfLineLength(plan.primitives), 17.7, accuracy: 1e-12)
        XCTAssertEqual(dxfLineLength(doc), 17_700, accuracy: 1e-6)
    }

    func testPolylineVerticesClosedFlagsAndHatchBoundaries() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let polylines = doc.entities.filter { $0.type == "LWPOLYLINE" }
        XCTAssertEqual(polylines.map { $0.int(90) }, [4, 4, 4, 3])
        XCTAssertEqual(polylines.map { $0.int(70) }, [1, 1, 1, 0], "closed flag only on closed shapes")
        XCTAssertEqual(polylines[0].doubles(10), [0, 5000, 5000, 0])
        XCTAssertEqual(polylines[0].doubles(20), [0, 0, 4000, 4000])
        XCTAssertEqual(polylines[1].doubles(10), [500, 4500, 4500, 500])        // dashed boundary
        XCTAssertEqual(polylines[3].doubles(10), [200, 1200, 1200])             // open L
        XCTAssertEqual(polylines[3].doubles(20), [200, 200, 800])
        let hatches = doc.entities.filter { $0.type == "HATCH" }
        XCTAssertEqual(hatches.count, 2)
        for hatch in hatches {
            XCTAssertEqual(hatch.string(2), "SOLID")
            XCTAssertEqual(hatch.int(70), 1, "solid fill flag")
            XCTAssertEqual(hatch.int(91), 1, "one boundary path")
            XCTAssertEqual(hatch.int(92), 3)
            XCTAssertEqual(hatch.int(93), 4, "four vertices")
            XCTAssertEqual(hatch.int(73), 1, "closed path")
            XCTAssertEqual(hatch.doubles(10).count, 5, "elevation x plus four vertices")
        }
        // Wall section 5000..5200 x 0..4000: shoelace area of the vertices equals 200 x 4000 mm.
        let xs = Array(hatches[0].doubles(10).dropFirst()), ys = Array(hatches[0].doubles(20).dropFirst())
        var twiceArea = 0.0
        for i in xs.indices {
            let j = (i + 1) % xs.count
            twiceArea += xs[i] * ys[j] - xs[j] * ys[i]
        }
        XCTAssertEqual(twiceArea / 2, 800_000, accuracy: 1e-6)
    }

    func testHatchFillColoursAreExplicit() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let hatches = doc.entities.filter { $0.type == "HATCH" }
        // (0.2, 0.2, 0.2) -> bytes 51, a near-black neutral -> ACI 7; (0.85, ...) -> 217 -> ACI 254 (203).
        // Group 420 is not part of release 2000, so the default export leaves it out.
        XCTAssertEqual(hatches[0].int(62), 7)
        XCTAssertNil(hatches[0].string(420))
        XCTAssertEqual(hatches[1].int(62), 254)
        XCTAssertNil(hatches[1].string(420))
        // In true-colour mode (release 2004) the exact tint is written as well.
        var options = dxfMappingOptions
        options.colorMode = .trueColor
        let exact = try dxfParsed(DXFFixtures.samplePlan(), options).entities.filter { $0.type == "HATCH" }
        XCTAssertEqual(exact[0].int(62), 7)
        XCTAssertEqual(exact[0].int(420), 0x333333)
        XCTAssertEqual(exact[1].int(62), 254)
        XCTAssertEqual(exact[1].int(420), 0xD9D9D9)
    }

    func testArcsAndCircles() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let arcs = doc.entities.filter { $0.type == "ARC" }
        XCTAssertEqual(arcs.count, 3)
        let door = arcs[0]
        XCTAssertEqual(door.double(10), 3000); XCTAssertEqual(door.double(20), 0)
        XCTAssertEqual(door.double(40), 900)
        XCTAssertEqual(door.double(50), 0); XCTAssertEqual(door.double(51), 90)
        XCTAssertEqual(arcs[2].double(10), 5000); XCTAssertEqual(arcs[2].double(20), 4000)
        XCTAssertEqual(arcs[2].double(40), 250)
        XCTAssertEqual(arcs[2].double(50), 180); XCTAssertEqual(arcs[2].double(51), 270)
        let circle = try XCTUnwrap(doc.entities.first(where: { $0.type == "CIRCLE" }))
        XCTAssertEqual(circle.double(10), 4500); XCTAssertEqual(circle.double(20), 3600)
        XCTAssertEqual(circle.double(40), 150)
    }

    func testArcAngleHandling() throws {
        func arc(_ start: Double, _ end: Double, radius: Double = 0.5) -> LayeredPrimitive {
            LayeredPrimitive(.doors, .arc(center: Point2(1, 2), radius: radius, startAngle: start, endAngle: end,
                                          DXFFixtures.door))
        }
        // Wrap through 0 degrees: 350 -> 10 is a 20 degree arc, kept as written.
        var doc = try dxfParsed(dxfDrawing([arc(350, 10)]))
        XCTAssertEqual(doc.entities.map { $0.type }, ["ARC"])
        XCTAssertEqual(doc.entities[0].double(50), 350); XCTAssertEqual(doc.entities[0].double(51), 10)
        // Negative angles are folded into 0..<360.
        doc = try dxfParsed(dxfDrawing([arc(-90, 0)]))
        XCTAssertEqual(doc.entities[0].double(50), 270); XCTAssertEqual(doc.entities[0].double(51), 0)
        doc = try dxfParsed(dxfDrawing([arc(45.5, 135.25)]))
        XCTAssertEqual(doc.entities[0].double(50), 45.5); XCTAssertEqual(doc.entities[0].double(51), 135.25)
        doc = try dxfParsed(dxfDrawing([arc(450, 540)]))
        XCTAssertEqual(doc.entities[0].double(50), 90); XCTAssertEqual(doc.entities[0].double(51), 180)
        // A full turn is a circle, not an arc with equal start and end.
        for (s, e) in [(0.0, 360.0), (10, 370), (0, 720), (90, -270)] {
            doc = try dxfParsed(dxfDrawing([arc(s, e)]))
            XCTAssertEqual(doc.entities.map { $0.type }, ["CIRCLE"], "sweep \(s)...\(e)")
            XCTAssertEqual(doc.entities[0].double(40), 500)
        }
        // Zero sweep, zero or negative radius and non-finite values draw nothing.
        for item in [arc(10, 10), arc(0, 90, radius: 0), arc(0, 90, radius: -1), arc(.nan, 90), arc(0, .infinity),
                     arc(0, 90, radius: .nan), arc(370, 10 + 360 * 0 + 360)] {
            let d = try dxfParsed(dxfDrawing([item]))
            XCTAssertTrue(d.entities.isEmpty || d.entities.first?.type == "CIRCLE", "\(item)")
        }
        doc = try dxfParsed(dxfDrawing([arc(10, 10)]))
        XCTAssertTrue(doc.entities.isEmpty)
    }

    func testTextHeightRotationAnchorStyleAndEncoding() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let texts = doc.entities.filter { $0.type == "TEXT" }
        XCTAssertEqual(texts.compactMap { $0.string(1) }, [
            "5000 mm", "4000 mm", "90.0%%d", "LIVING ROOM", "20.0 m\\U+00B2", "Tilt 12.5%%d %%p2 mm",
            "%%c50 pipe at 100% \\U+2013 check",
        ])
        XCTAssertEqual(texts.compactMap { $0.double(40) }, [125, 125, 100, 180, 125, 100, 100])
        // Rotation: group 50 is omitted for 0, -45 becomes 315.
        XCTAssertEqual(texts.map { $0.double(50) }, [nil, 90, nil, nil, nil, 30, 315])
        // Justification: left has no 72/11, centre is 1, right is 2, each with the anchor repeated in 11/21/31.
        XCTAssertEqual(texts.map { $0.int(72) }, [1, 1, nil, 1, 1, 2, nil])
        XCTAssertEqual(texts.map { $0.double(11) }, [2500, -650, nil, 2500, 2500, 5400, nil])
        XCTAssertEqual(texts.map { $0.double(21) }, [-550, 2000, nil, 2200, 1900, 1000, nil])
        XCTAssertEqual(texts.map { $0.double(10) }, [2500, -650, 300, 2500, 2500, 5400, 1000])
        // Bold text uses the NF-BOLD style, everything else the default.
        XCTAssertEqual(texts.map { $0.string(7) }, [nil, nil, nil, "NF-BOLD", nil, nil, nil])
        // No character above U+007E and no unescaped percent code survives.
        XCTAssertTrue(texts.allSatisfy { dxfIsASCII($0.string(1) ?? "") })
    }

    func testTextAnchorsAreWrittenTheWayAutoCADExpects() throws {
        func text(_ anchor: TextAnchor) -> LayeredPrimitive {
            LayeredPrimitive(.notes, .text("Hello", at: Point2(1.5, 2.5), height: 0.1, rotation: 15, anchor: anchor,
                                           color: .black, bold: false))
        }
        let left = try dxfParsed(dxfDrawing([text(.left)])).entities[0]
        XCTAssertNil(left.string(72)); XCTAssertNil(left.string(11))
        XCTAssertEqual(left.double(10), 1500); XCTAssertEqual(left.double(20), 2500)
        let centre = try dxfParsed(dxfDrawing([text(.center)])).entities[0]
        XCTAssertEqual(centre.int(72), 1)
        XCTAssertEqual(centre.double(11), 1500); XCTAssertEqual(centre.double(21), 2500); XCTAssertEqual(centre.double(31), 0)
        XCTAssertEqual(centre.double(10), 1500); XCTAssertEqual(centre.double(20), 2500)
        let right = try dxfParsed(dxfDrawing([text(.right)])).entities[0]
        XCTAssertEqual(right.int(72), 2)
        XCTAssertEqual(right.double(11), 1500)
        for record in [left, centre, right] { XCTAssertEqual(record.double(50), 15) }
    }

    func testTextRotationIsFoldedIntoZeroTo360() throws {
        func rotated(_ degrees: Double) throws -> Double? {
            let item = LayeredPrimitive(.notes, .text("x", at: .zero, height: 0.1, rotation: degrees, anchor: .left,
                                                      color: .black, bold: false))
            return try dxfParsed(dxfDrawing([item])).entities.first?.double(50)
        }
        XCTAssertEqual(try rotated(30), 30)
        XCTAssertEqual(try rotated(-90), 270)
        XCTAssertEqual(try rotated(390), 30)
        XCTAssertEqual(try rotated(-370), 350)
        XCTAssertNil(try rotated(0))
        XCTAssertNil(try rotated(720))
        XCTAssertNil(try rotated(-360))
    }

    // MARK: styling

    func testByLayerIsTheDefaultSoStrokesAndTextCarryNoColour() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        for entity in doc.entities where entity.type != "HATCH" {
            XCTAssertNil(entity.string(62), "\(entity.type) on \(entity.layer)")
            XCTAssertNil(entity.string(420))
        }
    }

    func testNearestACIAndTrueColourModes() throws {
        var options = dxfMappingOptions
        options.colorMode = .nearestACI
        var doc = try dxfParsed(DXFFixtures.samplePlan(), options)
        let dashed = try XCTUnwrap(doc.entities.first(where: { $0.layer == "NF-WALLS-OPEN" }))
        XCTAssertEqual(dashed.int(62), 5, "pure blue")
        XCTAssertNil(dashed.string(420))
        let wall = try XCTUnwrap(doc.entities.first(where: { $0.layer == "NF-WALLS" }))
        XCTAssertEqual(wall.int(62), 7, "black is ACI 7")
        let dim = try XCTUnwrap(doc.entities.first(where: { $0.layer == "NF-DIMENSIONS" }))
        // (0.2, 0.5, 0.2) -> bytes (51, 128, 51); nearest candidate is ACI 95 = (63, 127, 63), distance squared 289.
        XCTAssertEqual(dim.int(62), 95)
        options.colorMode = .trueColor
        doc = try dxfParsed(DXFFixtures.samplePlan(), options)
        let blue = try XCTUnwrap(doc.entities.first(where: { $0.layer == "NF-WALLS-OPEN" }))
        XCTAssertEqual(blue.int(62), 5)
        XCTAssertEqual(blue.int(420), 0x0000FF)
        let green = try XCTUnwrap(doc.entities.first(where: { $0.layer == "NF-DIMENSIONS" && $0.type == "LINE" }))
        // (0.2, 0.5, 0.2) -> bytes (51, 128, 51) -> 0x338033.
        XCTAssertEqual(green.int(420), 0x338033)
        let text = try XCTUnwrap(doc.entities.first(where: { $0.type == "TEXT" && $0.layer == "NF-ANGLES" }))
        XCTAssertEqual(text.int(420), 0xFF0000, "text colour is written too")
        XCTAssertEqual(text.int(62), 1)
    }

    func testDashedStrokesUseTheDashedLinetypeAndNothingElseDoes() throws {
        let doc = try dxfParsed(DXFFixtures.samplePlan())
        let withLinetype = doc.entities.filter { $0.string(6) != nil }
        XCTAssertEqual(withLinetype.count, 1)
        XCTAssertEqual(withLinetype[0].string(6), "DASHED")
        XCTAssertEqual(withLinetype[0].layer, "NF-WALLS-OPEN")
        // Dashed lines, arcs and circles too.
        let dashed = StrokeStyle(weight: 0.25, color: .black, dashed: true)
        let items = [
            LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(1, 0), dashed)),
            LayeredPrimitive(.walls, .arc(center: .zero, radius: 1, startAngle: 0, endAngle: 90, dashed)),
            LayeredPrimitive(.walls, .circle(center: .zero, radius: 1, dashed)),
            LayeredPrimitive(.walls, .polyline([Point2(0, 0), Point2(1, 0)], closed: false, stroke: dashed, fill: nil)),
            LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(1, 1), DXFFixtures.wall)),
        ]
        let d = try dxfParsed(dxfDrawing(items))
        XCTAssertEqual(d.entities.map { $0.string(6) }, ["DASHED", "DASHED", "DASHED", "DASHED", nil])
    }

    func testLineweightsAreWrittenOnlyWhenTheyDifferFromTheLayer() throws {
        func line(_ layer: PlanLayer, weight: Double) -> LayeredPrimitive {
            LayeredPrimitive(layer, .line(Point2(0, 0), Point2(1, 0), StrokeStyle(weight: weight)))
        }
        let items = [
            line(.walls, weight: 0.5),            // equals the layer's 50: BYLAYER
            line(.walls, weight: 0.25),           // 25 differs
            line(.dimensions, weight: 0.5),       // 50 on a 13 layer
            line(.dimensions, weight: 0.19),      // tie 18/20 -> 18
            line(.dimensions, weight: 0.13),      // equals layer
            line(.dimensions, weight: 9),         // clamps to 211
            line(.dimensions, weight: 0),         // hairline -> 0
            line(.dimensions, weight: -2),        // invalid -> BYLAYER
            line(.dimensions, weight: .nan),      // invalid -> BYLAYER
        ]
        let doc = try dxfParsed(dxfDrawing(items))
        XCTAssertEqual(doc.entities.map { $0.int(370) }, [nil, 25, 50, 18, nil, 211, 0, nil, nil])
        var options = dxfMappingOptions
        options.entityLineweights = false
        let plain = try dxfParsed(dxfDrawing(items), options)
        XCTAssertTrue(plain.entities.allSatisfy { $0.string(370) == nil })
    }

    func testFillsComeBeforeTheirOutline() throws {
        let item = LayeredPrimitive(.furniture, .polyline(DXFFixtures.box(0, 0, 1, 1), closed: true,
                                                          stroke: DXFFixtures.thin, fill: DrawColor(0.9, 0.9, 0.9)))
        let doc = try dxfParsed(dxfDrawing([item]))
        XCTAssertEqual(doc.entities.map { $0.type }, ["HATCH", "LWPOLYLINE"], "outline drawn on top of the fill")
        var options = dxfMappingOptions
        options.includeFills = false
        let none = try dxfParsed(dxfDrawing([item]), options)
        XCTAssertEqual(none.entities.map { $0.type }, ["LWPOLYLINE"])
        // Fill only (no stroke): a hatch and no polyline.
        let fillOnly = LayeredPrimitive(.furniture, .polyline(DXFFixtures.box(0, 0, 1, 1), closed: true, stroke: nil,
                                                              fill: .black))
        XCTAssertEqual(try dxfParsed(dxfDrawing([fillOnly])).entities.map { $0.type }, ["HATCH"])
        XCTAssertEqual(try dxfParsed(dxfDrawing([fillOnly]), options).entities.count, 0)
    }

    func testOptionsSwitchTextAndFillsOff() throws {
        let plan = DXFFixtures.samplePlan()
        var options = dxfMappingOptions
        options.includeTextLayers = false
        var doc = try dxfParsed(plan, options)
        XCTAssertEqual(doc.entities.filter { $0.type == "TEXT" }.count, 0)
        XCTAssertEqual(doc.entities.count, 28 - 7)
        XCTAssertEqual(dxfActualCounts(doc), dxfExpectedCounts(plan.primitives, text: false))
        options.includeFills = false
        doc = try dxfParsed(plan, options)
        XCTAssertEqual(doc.entities.count, 28 - 7 - 2)
        XCTAssertEqual(dxfActualCounts(doc), dxfExpectedCounts(plan.primitives, text: false, fills: false))
        XCTAssertEqual(dxfLineLength(doc), 17_700, accuracy: 1e-6, "geometry is untouched")
    }

    // MARK: degenerate and hostile input

    func testDegenerateGeometryIsSkippedNotWritten() throws {
        let p = Point2(1, 1)
        let stroke = DXFFixtures.wall
        let items: [LayeredPrimitive] = [
            LayeredPrimitive(.walls, .line(p, p, stroke)),                                          // zero length
            LayeredPrimitive(.walls, .line(p, Point2(p.x + 1e-12, p.y), stroke)),                   // sub-nanometre
            LayeredPrimitive(.walls, .polyline([], closed: true, stroke: stroke, fill: .black)),    // empty
            LayeredPrimitive(.walls, .polyline([p], closed: false, stroke: stroke, fill: nil)),     // one point
            LayeredPrimitive(.walls, .polyline([p, p, p], closed: true, stroke: stroke, fill: .black)), // all equal
            LayeredPrimitive(.walls, .polyline(DXFFixtures.box(0, 0, 1, 1), closed: true, stroke: nil, fill: nil)),
            LayeredPrimitive(.notes, .text("", at: p, height: 0.1, rotation: 0, anchor: .left, color: .black, bold: false)),
            LayeredPrimitive(.notes, .text("   ", at: p, height: 0.1, rotation: 0, anchor: .left, color: .black, bold: false)),
            LayeredPrimitive(.notes, .text("x", at: p, height: 0, rotation: 0, anchor: .left, color: .black, bold: false)),
            LayeredPrimitive(.notes, .text("x", at: p, height: -0.1, rotation: 0, anchor: .left, color: .black, bold: false)),
            LayeredPrimitive(.notes, .circle(center: p, radius: 0, stroke)),
            LayeredPrimitive(.notes, .circle(center: p, radius: -1, stroke)),
        ]
        let doc = try dxfParsed(dxfDrawing(items))
        XCTAssertEqual(doc.entities.count, 0, "nothing drawable in this list: \(doc.entities.map { $0.type })")
    }

    func testNonFiniteAndAbsurdCoordinatesNeverReachTheFile() throws {
        let nan = Double.nan, inf = Double.infinity
        let stroke = DXFFixtures.wall
        var items: [LayeredPrimitive] = [
            LayeredPrimitive(.walls, .line(Point2(nan, 0), Point2(1, 1), stroke)),
            LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(inf, 1), stroke)),
            LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(1e10, 1), stroke)),            // 1e13 mm is beyond the limit
            LayeredPrimitive(.walls, .polyline([Point2(0, 0), Point2(1, nan), Point2(2, 2)], closed: false, stroke: stroke,
                                               fill: .black)),
            LayeredPrimitive(.walls, .circle(center: Point2(nan, 0), radius: 1, stroke)),
            LayeredPrimitive(.walls, .circle(center: .zero, radius: inf, stroke)),
            LayeredPrimitive(.walls, .arc(center: .zero, radius: 1, startAngle: nan, endAngle: 5, stroke)),
            LayeredPrimitive(.notes, .text("x", at: Point2(inf, 0), height: 0.1, rotation: 0, anchor: .left, color: .black,
                                           bold: false)),
            LayeredPrimitive(.notes, .text("x", at: .zero, height: nan, rotation: 0, anchor: .left, color: .black, bold: false)),
            LayeredPrimitive(.notes, .text("x", at: .zero, height: 0.1, rotation: nan, anchor: .left, color: .black,
                                           bold: false)),
        ]
        // One good line proves the rest of the file still works.
        items.append(LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(2, 0), stroke)))
        let plan = PlanDrawing(primitives: items, bounds: Bounds2(min: Point2(nan, 0), max: Point2(inf, inf)),
                               options: PlanOptions(scale: .nan))
        let text = dxfExport(plan)
        let doc = try XCTUnwrap(DXFReader.parse(text))
        XCTAssertEqual(doc.entities.map { $0.type }, ["LINE"])
        XCTAssertEqual(dxfLineLength(doc), 2000, accuracy: 1e-9)
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("nan") || lower.contains("inf"))
        // The invalid bounds are ignored; the extents come from the geometry that was written.
        XCTAssertEqual(doc.header("$EXTMIN").compactMap { Double($0.value) }, [0, 0, 0])
        XCTAssertEqual(doc.header("$EXTMAX").compactMap { Double($0.value) }, [2000, 0, 0])
    }

    func testPolylineVertexCleaning() throws {
        let stroke = DXFFixtures.wall
        func polyline(_ pts: [Point2], closed: Bool, fill: DrawColor? = nil, stroke s: StrokeStyle? = stroke) -> LayeredPrimitive {
            LayeredPrimitive(.walls, .polyline(pts, closed: closed, stroke: s, fill: fill))
        }
        // Consecutive duplicates collapse.
        var doc = try dxfParsed(dxfDrawing([polyline([Point2(0, 0), Point2(0, 0), Point2(1, 0), Point2(1, 0),
                                                       Point2(1, 1)], closed: false)]))
        XCTAssertEqual(doc.entities[0].int(90), 3)
        XCTAssertEqual(doc.entities[0].doubles(10), [0, 1000, 1000])
        // A closed shape that repeats its first point at the end does not keep the repeat.
        doc = try dxfParsed(dxfDrawing([polyline([Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 0)], closed: true)]))
        XCTAssertEqual(doc.entities[0].int(90), 3)
        XCTAssertEqual(doc.entities[0].int(70), 1)
        // Two points: an open polyline even when asked closed (it would draw the segment twice).
        doc = try dxfParsed(dxfDrawing([polyline([Point2(0, 0), Point2(1, 0)], closed: true)]))
        XCTAssertEqual(doc.entities[0].int(90), 2)
        XCTAssertEqual(doc.entities[0].int(70), 0)
        // Two points cannot be filled.
        doc = try dxfParsed(dxfDrawing([polyline([Point2(0, 0), Point2(1, 0)], closed: false, fill: .black)]))
        XCTAssertEqual(doc.entities.map { $0.type }, ["LWPOLYLINE"])
        // An open polyline that returns to its start is kept as drawn but its fill boundary has no repeated vertex.
        let loop = [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 0)]
        doc = try dxfParsed(dxfDrawing([polyline(loop, closed: false, fill: DrawColor(0.5, 0.5, 0.5))]))
        XCTAssertEqual(doc.entities.map { $0.type }, ["HATCH", "LWPOLYLINE"])
        XCTAssertEqual(doc.entities[0].int(93), 3)
        XCTAssertEqual(doc.entities[1].int(90), 4)
        XCTAssertEqual(doc.entities[1].int(70), 0)
    }

    func testTextCannotInjectGroupsOrBreakTheFile() throws {
        let nasty = "x\n  0\nENDSEC\n  0\nEOF\r\n  0\nSECTION"
        let item = LayeredPrimitive(.notes, .text(nasty, at: .zero, height: 0.1, rotation: 0, anchor: .left,
                                                  color: .black, bold: false))
        let text = dxfExport(dxfDrawing([item]))
        let doc = try XCTUnwrap(DXFReader.parse(text))
        XCTAssertEqual(doc.entities.map { $0.type }, ["TEXT"])
        XCTAssertEqual(doc.entities[0].string(1), "x   0 ENDSEC   0 EOF    0 SECTION")
        XCTAssertEqual(doc.sections.count, 6)
        XCTAssertTrue(doc.endsWithEOF)
    }

    func testNonASCIIInputStillGivesASCIIOutput() throws {
        let strings = ["caf\u{00E9}", "\u{0645}\u{0643}\u{062A}\u{0628}", "\u{1F600}", "\u{4E2D}\u{6587}", "\u{00B0}\u{00B1}\u{2300}"]
        let items = strings.map {
            LayeredPrimitive(.roomLabels, .text($0, at: .zero, height: 0.1, rotation: 0, anchor: .center, color: .black,
                                                bold: false))
        }
        let text = dxfExport(dxfDrawing(items))
        XCTAssertTrue(dxfIsASCII(text))
        let doc = try XCTUnwrap(DXFReader.parse(text))
        XCTAssertEqual(doc.entities.count, strings.count)
        XCTAssertEqual(doc.entities[2].string(1), "\\U+D83D\\U+DE00")
        XCTAssertEqual(doc.entities[4].string(1), "%%d%%p%%c")
    }

    // MARK: options, determinism, size

    func testOutputIsDeterministicAndIndependentOfTitle() {
        let a = DXFFixtures.samplePlan()
        var b = DXFFixtures.samplePlan()
        b.title = "Another title"
        b.subtitle = "\u{00E9}"
        XCTAssertEqual(dxfExport(a), dxfExport(a))
        XCTAssertEqual(dxfExport(a), dxfExport(b), "title and subtitle are not written to the file")
        XCTAssertNotEqual(dxfExport(a), dxfExport(a, DXFExporter.Options(units: .metres, includeProvenanceNote: false)))
    }

    func testDataIsTheASCIIBytesOfTheText() {
        let plan = DXFFixtures.samplePlan()
        XCTAssertEqual(DXFExporter.data(plan, options: dxfMappingOptions), Data(dxfExport(plan).utf8))
        XCTAssertEqual(DXFExporter.data(plan), Data(DXFExporter.export(plan).utf8), "default options too")
        XCTAssertTrue(DXFExporter.data(plan).allSatisfy { $0 < 0x80 })
    }

    func testWindowsLineEndings() throws {
        var options = dxfMappingOptions
        options.windowsLineEndings = true
        let plan = DXFFixtures.samplePlan()
        let text = dxfExport(plan, options)
        let bytes = Array(text.utf8)
        let lf = bytes.filter { $0 == 0x0A }.count
        let crlf = zip(bytes, bytes.dropFirst()).filter { $0 == 0x0D && $1 == 0x0A }.count
        XCTAssertGreaterThan(lf, 1000)
        XCTAssertEqual(lf, crlf, "every line feed is preceded by a carriage return")
        XCTAssertFalse(bytes.contains(0x0D) && bytes.filter { $0 == 0x0D }.count != crlf, "no stray CR")
        // Same content as the LF file.
        let lfDoc = try dxfParsed(plan)
        let crDoc = try XCTUnwrap(DXFReader.parse(text))
        XCTAssertEqual(crDoc.entities.count, lfDoc.entities.count)
        XCTAssertEqual(DXFReader.pairs(text)?.map { "\($0.code)=\($0.value)" },
                       DXFReader.pairs(dxfExport(plan))?.map { "\($0.code)=\($0.value)" })
    }

    func testOptionsDefaultsAndCodable() throws {
        let defaults = DXFExporter.Options()
        XCTAssertEqual(defaults.units, .millimetres)
        XCTAssertTrue(defaults.includeTextLayers)
        XCTAssertTrue(defaults.includeFills)
        XCTAssertEqual(defaults.colorMode, .byLayer)
        XCTAssertTrue(defaults.entityLineweights)
        XCTAssertFalse(defaults.windowsLineEndings)
        XCTAssertTrue(defaults.includeProvenanceNote, "the hand-off carries its provenance note unless asked not to")
        let custom = DXFExporter.Options(units: .metres, includeTextLayers: false, includeFills: false,
                                         colorMode: .trueColor, entityLineweights: false, windowsLineEndings: true,
                                         includeProvenanceNote: false)
        let data = try JSONEncoder().encode(custom)
        XCTAssertEqual(try JSONDecoder().decode(DXFExporter.Options.self, from: data), custom)
    }

    func testEmptyDrawingIsAValidFile() throws {
        let doc = try dxfParsed(dxfEmptyDrawing())
        XCTAssertEqual(doc.sections.map { $0.name }, ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"])
        XCTAssertEqual(doc.entities.count, 0)
        XCTAssertEqual(doc.header("$EXTMIN").map { $0.value }, ["1.000000000000000E+20", "1.000000000000000E+20",
                                                                "1.000000000000000E+20"], "AutoCAD's marker for nothing drawn")
        XCTAssertEqual(doc.header("$EXTMAX").map { $0.value }, ["-1.000000000000000E+20", "-1.000000000000000E+20",
                                                                "-1.000000000000000E+20"])
        XCTAssertEqual(doc.section("TABLES").filter { $0.type == "LAYER" }.count, 11, "layers exist even with no geometry")
        XCTAssertTrue(doc.endsWithEOF)
    }

    func testExtentsAreTheUnionOfBoundsAndGeometry() throws {
        // Bounds claim 0..1 m but a line runs to 10 m: the header covers the line.
        let line = LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(10, 0), DXFFixtures.wall))
        let plan = PlanDrawing(primitives: [line], bounds: Bounds2(min: .zero, max: Point2(1, 1)),
                               options: PlanOptions())
        let doc = try dxfParsed(plan)
        XCTAssertEqual(doc.header("$EXTMAX").compactMap { Double($0.value) }, [10_000, 1_000, 0])
        // Bounds larger than the geometry (room for text) are honoured.
        let wide = PlanDrawing(primitives: [line], bounds: Bounds2(min: Point2(-2, -3), max: Point2(12, 4)),
                               options: PlanOptions())
        let wideDoc = try dxfParsed(wide)
        XCTAssertEqual(wideDoc.header("$EXTMIN").compactMap { Double($0.value) }, [-2000, -3000, 0])
        XCTAssertEqual(wideDoc.header("$EXTMAX").compactMap { Double($0.value) }, [12_000, 4_000, 0])
        // Inverted bounds are ignored.
        let inverted = PlanDrawing(primitives: [line], bounds: Bounds2(min: Point2(5, 5), max: Point2(-5, -5)),
                                   options: PlanOptions())
        let invDoc = try dxfParsed(inverted)
        XCTAssertEqual(invDoc.header("$EXTMIN").compactMap { Double($0.value) }, [0, 0, 0])
        XCTAssertEqual(invDoc.header("$EXTMAX").compactMap { Double($0.value) }, [10_000, 0, 0])
    }

    func testLargeCoordinateOffsets() throws {
        // A room at x = 100 m (1e5 mm), and far out at 1e6 m.
        for origin in [Point2(100, 100), Point2(1_000_000, -2_000_000)] {
            let plan = DXFFixtures.samplePlan(origin: origin)
            let text = dxfExport(plan)
            let doc = try XCTUnwrap(DXFReader.parse(text))
            XCTAssertEqual(doc.entities.count, 28)
            XCTAssertEqual(dxfLineLength(doc), 17_700, accuracy: 1e-3, "origin \(origin)")
            let outline = try XCTUnwrap(doc.entities.first(where: { $0.type == "LWPOLYLINE" }))
            XCTAssertEqual(outline.doubles(10), [origin.x * 1000, origin.x * 1000 + 5000, origin.x * 1000 + 5000,
                                                 origin.x * 1000])
            XCTAssertEqual(outline.doubles(20), [origin.y * 1000, origin.y * 1000, origin.y * 1000 + 4000,
                                                 origin.y * 1000 + 4000])
            // Plain decimal notation, no exponent in any number written for an entity.
            for entity in doc.entities {
                for pair in entity.pairs where (10...59).contains(pair.code) {
                    XCTAssertFalse(pair.value.uppercased().contains("E"), "group \(pair.code): \(pair.value)")
                    XCTAssertNotNil(Double(pair.value))
                }
            }
            // The header extents moved with the room.
            let extMin = doc.header("$EXTMIN").compactMap { Double($0.value) }
            XCTAssertEqual(extMin[0], origin.x * 1000 - 900, accuracy: 1e-6)
        }
    }

    func testManyEntitiesStayFastAndExact() throws {
        var items: [LayeredPrimitive] = []
        var generator = DXFSeededGenerator(seed: 5)
        var total = 0.0
        for _ in 0..<20_000 {
            let a = Point2(Double.random(in: -50...50, using: &generator), Double.random(in: -50...50, using: &generator))
            let b = Point2(Double.random(in: -50...50, using: &generator), Double.random(in: -50...50, using: &generator))
            total += a.distance(to: b)
            items.append(LayeredPrimitive(.walls, .line(a, b, DXFFixtures.wall)))
        }
        let big = (0..<10_000).map { Point2(Double($0) * 0.001, sin(Double($0) * 0.01)) }
        items.append(LayeredPrimitive(.furniture, .polyline(big, closed: false, stroke: DXFFixtures.thin, fill: nil)))
        let plan = dxfDrawing(items)
        let start = Date()
        let text = dxfExport(plan)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "export of 20k lines and a 10k polyline")
        let doc = try XCTUnwrap(DXFReader.parse(text))
        XCTAssertEqual(doc.entities.count, 20_001)
        XCTAssertEqual(dxfLineLength(doc) / 1000, total, accuracy: 1e-4)
        XCTAssertEqual(doc.entities.last?.int(90), 10_000)
        let defined = doc.definedHandles
        XCTAssertEqual(Set(defined).count, defined.count)
    }
}


// MARK: - 4. Review fixes: colour cue, R2000 purity, degenerate sizes, carets, palette, provenance

/// RGB of the AutoCAD Color Index numbers the tests below rely on, typed from the published table (ezdxf 1.4.4's
/// `DXF_DEFAULT_COLORS`), so that colour tests do not depend on the exporter's own palette.
private let dxfReferenceACI: [Int: (r: Int, g: Int, b: Int)] = [
    1: (255, 0, 0), 4: (0, 255, 255), 5: (0, 0, 255), 6: (255, 0, 255), 8: (128, 128, 128),
    30: (255, 127, 0), 32: (165, 82, 0), 42: (165, 124, 0), 94: (0, 127, 0), 95: (63, 127, 63),
    150: (0, 127, 255), 190: (127, 0, 255),
]

private func dxfIsGreenish(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.g > c.r + 40 && c.g > c.b + 40 }
private func dxfIsReddish(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > c.g + 80 && c.r > c.b + 80 }

/// Two rooms from the real plan builder: a rectangle whose south wall was laser-verified (5.02 m against 5.00 m
/// scanned) and a trapezoid with two out-of-square corners.
private func dxfRealPlan(scale: Double = 50, markVerified: Bool = true) -> PlanDrawing {
    var living = Room.rectangle(name: "Living Room", kind: .livingRoom, width: 5, depth: 4)
    living.walls[0].length.verify(5.02, source: .laser)
    let study = Room.polygon(name: "Study", kind: .office,
                             corners: [Point2(6, 0), Point2(10, 0), Point2(9.4, 3), Point2(6, 3)])
    return PlanDrawingBuilder.build(rooms: [living, study], title: "Marina Gate - Unit 2304", subtitle: "Level 1",
                                    options: PlanOptions(scale: scale, markVerified: markVerified))
}

final class DXFReviewFixTests: XCTestCase {

    // MARK: colour cue (verified green, out of square red) survives the default BYLAYER export

    func testVerifiedAndScannedDimensionTextsLookDifferentInTheDefaultExport() throws {
        let plan = dxfRealPlan()
        let doc = try dxfParsed(plan)
        let texts = doc.entities.filter { $0.type == "TEXT" && $0.layer == "NF-DIMENSIONS" }
        let verified = texts.filter { ($0.string(1) ?? "").hasSuffix(" v") }
        let scanned = texts.filter { !($0.string(1) ?? "").hasSuffix(" v") }
        XCTAssertEqual(verified.count, 1, "only the south wall of the living room was verified")
        XCTAssertEqual(scanned.count, 7)
        XCTAssertEqual(verified.first?.string(1), "5020 mm v")
        for text in verified {
            let aci = try XCTUnwrap(text.int(62), "a verified number carries an explicit colour")
            let rgb = try XCTUnwrap(dxfReferenceACI[aci], "ACI \(aci)")
            XCTAssertTrue(dxfIsGreenish(rgb), "verified text is green, got ACI \(aci)")
        }
        // Scanned numbers follow the layer, and the layer is not green (green means verified in the plan and PDF).
        let layerACI = try XCTUnwrap(doc.section("TABLES").first(where: { $0.type == "LAYER" && $0.string(2) == "NF-DIMENSIONS" })?.int(62))
        let layerRGB = try XCTUnwrap(dxfReferenceACI[layerACI], "layer colour ACI \(layerACI)")
        XCTAssertFalse(dxfIsGreenish(layerRGB), "NF-DIMENSIONS must not be green")
        XCTAssertFalse(dxfIsReddish(layerRGB), "NF-DIMENSIONS must not be red")
        for text in scanned { XCTAssertNil(text.string(62), "\(text.string(1) ?? "")") }
    }

    func testOnlyOutOfSquareAnglesAreRedInTheDefaultExport() throws {
        let plan = dxfRealPlan()
        let warning = PlanDrawingBuilder.Palette.warning
        let warned = plan.primitives.filter { item in
            guard item.layer == .angles else { return false }
            switch item.primitive {
            case let .arc(_, _, _, _, stroke): return stroke.color == warning
            case let .text(_, _, _, _, _, color, _): return color == warning
            default: return false
            }
        }
        XCTAssertGreaterThan(warned.count, 0, "the trapezoid has out-of-square corners")
        let doc = try dxfParsed(plan)
        let red = doc.entities.filter { $0.layer == "NF-ANGLES" && $0.string(62) != nil }
        XCTAssertEqual(red.count, warned.count)
        for entity in red {
            let rgb = try XCTUnwrap(dxfReferenceACI[entity.int(62) ?? -1])
            XCTAssertTrue(dxfIsReddish(rgb), "\(entity.type)")
        }
        let layerACI = try XCTUnwrap(doc.section("TABLES").first(where: { $0.type == "LAYER" && $0.string(2) == "NF-ANGLES" })?.int(62))
        let layerRGB = try XCTUnwrap(dxfReferenceACI[layerACI], "layer colour ACI \(layerACI)")
        XCTAssertFalse(dxfIsReddish(layerRGB), "NF-ANGLES must not be red")
        XCTAssertFalse(dxfIsGreenish(layerRGB))
    }

    // MARK: no group 420 in an R2000 file

    func testDefaultAndNearestACIExportsAreR2000WithoutTrueColour() throws {
        for mode in [DXFColorMode.byLayer, .nearestACI] {
            var options = DXFExporter.Options()
            options.colorMode = mode
            let doc = try dxfParsed(dxfRealPlan(), options)
            XCTAssertEqual(doc.header("$ACADVER").first?.value, "AC1015")
            let pairs = try XCTUnwrap(DXFReader.pairs(dxfExport(dxfRealPlan(), options)))
            XCTAssertEqual(pairs.filter { $0.code == 420 }.count, 0, "group 420 is not defined in R2000 (\(mode))")
            let hatches = doc.entities.filter { $0.type == "HATCH" }
            XCTAssertGreaterThan(hatches.count, 0)
            XCTAssertTrue(hatches.allSatisfy { $0.int(62) != nil }, "fills keep their ACI colour")
        }
    }

    func testTrueColourModeDeclaresR2004WhereGroup420IsDefined() throws {
        var options = DXFExporter.Options()
        options.colorMode = .trueColor
        let doc = try dxfParsed(dxfRealPlan(), options)
        XCTAssertEqual(doc.header("$ACADVER").first?.value, "AC1018")
        // Every entity of the real plan has a colour, so every entity carries the exact one next to its ACI fallback.
        XCTAssertGreaterThan(doc.entities.count, 50)
        XCTAssertTrue(doc.entities.allSatisfy { $0.string(420) != nil && $0.string(62) != nil })
        XCTAssertTrue(doc.entities.filter { $0.type == "HATCH" }.count > 0)
    }

    // MARK: sub-resolution sizes are skipped, not written as zero

    func testSizesThatRoundToZeroAreSkipped() throws {
        let stroke = DXFFixtures.wall
        func text(height: Double) -> LayeredPrimitive {
            LayeredPrimitive(.notes, .text("x", at: .zero, height: height, rotation: 0, anchor: .left, color: .black, bold: false))
        }
        let tiny = [
            LayeredPrimitive(.walls, .circle(center: .zero, radius: 4e-13, stroke)),
            LayeredPrimitive(.walls, .arc(center: .zero, radius: 4e-13, startAngle: 0, endAngle: 90, stroke)),
            LayeredPrimitive(.walls, .arc(center: .zero, radius: 4e-13, startAngle: 0, endAngle: 360, stroke)),
            text(height: 4e-13),
        ]
        XCTAssertEqual(try dxfParsed(dxfDrawing(tiny)).entities.count, 0, "millimetres: 4e-10 mm writes as 0.0")
        var metres = DXFExporter.Options()
        metres.units = .metres
        let tinyMetres = [
            LayeredPrimitive(.walls, .circle(center: .zero, radius: 4e-10, stroke)),
            LayeredPrimitive(.walls, .arc(center: .zero, radius: 4e-10, startAngle: 0, endAngle: 90, stroke)),
            text(height: 4e-10),
        ]
        XCTAssertEqual(try dxfParsed(dxfDrawing(tinyMetres), metres).entities.count, 0)
        // The smallest size that still writes as a non-zero number is kept.
        let smallest = [
            LayeredPrimitive(.walls, .circle(center: .zero, radius: 1e-9, stroke)),
            text(height: 1e-9),
        ]
        let doc = try dxfParsed(dxfDrawing(smallest))
        XCTAssertEqual(doc.entities.map { $0.type }, ["CIRCLE", "TEXT"])
        XCTAssertEqual(doc.entities[0].double(40), 1e-6, "1e-9 m is 1e-6 mm")
    }

    func testAFillWithNoAreaIsNotWrittenAsAHatch() throws {
        let collinear = [Point2(0, 0), Point2(1, 0), Point2(2, 0)]
        let item = LayeredPrimitive(.furniture, .polyline(collinear, closed: true, stroke: DXFFixtures.thin, fill: .black))
        XCTAssertEqual(try dxfParsed(dxfDrawing([item])).entities.map { $0.type }, ["LWPOLYLINE"])
        // Collinear along a diagonal: rounding noise must not pass as an area. Three placements: 1 m long 500 km from
        // the origin (the sum is taken relative to the first vertex, or the noise is far above any threshold), and
        // 100 m long near the origin (a threshold that does not grow with the size would be exceeded by the noise).
        // The numbers were picked so that the noise is real: summed from absolute coordinates the first one gives an
        // "area" of 16 mm2, relative to the first vertex 1e-11 mm2; the second gives 4e-7 mm2 either way, which is
        // above 1e-9 but far below 1e-12 x perimeter squared (0.04).
        func diagonalPoints(from start: Point2, slope: Double, step: Double, count: Int) -> [Point2] {
            (0..<count).map { k in
                let x = start.x + Double(k) * step
                return Point2(x, slope * (x - start.x) + start.y)
            }
        }
        let placements: [(start: Point2, slope: Double, step: Double)] = [
            (Point2(500_000.0885180931, 400_000.8005953213), 0.9104618273459089, 0.13015307489056194),
            (Point2(0.1, 0.3), 0.7, 17.123456789),
        ]
        for placement in placements {
            let points = diagonalPoints(from: placement.start, slope: placement.slope, step: placement.step, count: 6)
            let diagonal = LayeredPrimitive(.furniture, .polyline(points, closed: true, stroke: nil, fill: .black))
            XCTAssertEqual(try dxfParsed(dxfDrawing([diagonal])).entities.count, 0, "start \(placement.start)")
        }
        // The same long sliver with a genuine width of 1 mm is kept.
        let sliver = LayeredPrimitive(.furniture, .polyline([Point2(0, 0), Point2(100, 0), Point2(100, 0.001), Point2(0, 0.001)],
                                                            closed: true, stroke: nil, fill: .black))
        XCTAssertEqual(try dxfParsed(dxfDrawing([sliver])).entities.map { $0.type }, ["HATCH"])
        // A thin but real band is kept.
        let band = LayeredPrimitive(.furniture, .polyline(DXFFixtures.box(0, 0, 4, 0.001), closed: true, stroke: nil, fill: .black))
        XCTAssertEqual(try dxfParsed(dxfDrawing([band])).entities.map { $0.type }, ["HATCH"])
    }

    // MARK: caret

    func testLiteralCaretsCannotBeReadAsControlCharacters() {
        XCTAssertEqual(DXFFormat.text("^J"), "^ J")
        XCTAssertEqual(DXFFormat.text("10^2"), "10^ 2")
        XCTAssertEqual(DXFFormat.text("x^Zy"), "x^ Zy")
        XCTAssertEqual(DXFFormat.text("a^"), "a^ ")
        XCTAssertEqual(DXFFormat.text("^^M"), "^ ^ M")
        // Reading back the way AutoCAD notation does ("^ " is a caret, "^X" a control character) restores the input.
        func caretDecode(_ s: String) -> String {
            var out = "", chars = Array(s), i = 0
            while i < chars.count {
                if chars[i] == "^", i + 1 < chars.count {
                    if chars[i + 1] == " " { out.append("^") }
                    else if let v = chars[i + 1].asciiValue, v >= 0x40 { out.append(Character(Unicode.Scalar(v - 0x40))) }
                    else { out.append("^"); i += 1; continue }
                    i += 2
                } else { out.append(chars[i]); i += 1 }
            }
            return out
        }
        for source in ["^J", "10^2", "x^Zy", "a^", "^^M", "m^2 and ^I tab", "caret ^ alone"] {
            XCTAssertEqual(caretDecode(DXFFormat.text(source)), source, source)
        }
        XCTAssertEqual(DXFFormat.text("m\u{00B2}"), "m\\U+00B2", "the superscript two is untouched")
    }
}


// MARK: - 5. Provenance note

final class DXFProvenanceNoteTests: XCTestCase {

    /// The note's entities: whatever the default export writes after the entities the plan maps to.
    private func noteEntities(_ plan: PlanDrawing, _ options: DXFExporter.Options = DXFExporter.Options(),
                              file: StaticString = #filePath, line: UInt = #line) throws -> (note: [DXFRecord], doc: DXFParsed) {
        var plain = options
        plain.includeProvenanceNote = false
        let mapped = try dxfParsed(plan, plain, file: file, line: line)
        let full = try dxfParsed(plan, options, file: file, line: line)
        XCTAssertEqual(full.entities.prefix(mapped.entities.count).map { $0.type },
                       mapped.entities.map { $0.type }, "the note comes after the plan's own entities",
                       file: file, line: line)
        return (Array(full.entities.dropFirst(mapped.entities.count)), full)
    }

    /// The note read back as paragraphs' text: line texts joined by single spaces.
    private func joined(_ lines: [DXFRecord]) -> String {
        lines.compactMap { $0.string(1) }.joined(separator: " ")
    }

    func testDefaultExportCarriesTheDisclaimerAndTheProvenance() throws {
        let (note, _) = try noteEntities(DXFFixtures.samplePlan())
        XCTAssertGreaterThanOrEqual(note.count, 4)
        XCTAssertTrue(note.allSatisfy { $0.type == "TEXT" && $0.layer == "NF-NOTES" })
        let text = joined(note)
        XCTAssertTrue(text.contains(ScanAccuracy.joineryDisclaimer), text)
        XCTAssertTrue(text.contains("Geometry in this file is the LiDAR scan."), text)
        XCTAssertTrue(text.contains("Do not take cutting dimensions from distances measured on the drawing."), text)
        XCTAssertTrue(text.contains("Text values marked v are laser-verified and take precedence over the drawn geometry"),
                      text)
        XCTAssertTrue(dxfIsASCII(text))
    }

    func testNoteHangsUnderThePlanLeftAlignedInTheDocumentedUnits() throws {
        // The sample's bounds run from (-900, -2400) to (5600, 4300) mm; text is 2.5 mm tall on paper at 1:50, so
        // 125 mm. The first baseline is 2.5 text heights below the bounds: -2400 - 312.5. Lines are 1.8 heights apart.
        let (note, doc) = try noteEntities(DXFFixtures.samplePlan())
        XCTAssertEqual(note.first?.string(1), "Sample - 5 x 4 m", "the title comes first")
        XCTAssertEqual(note.first?.string(7), "NF-BOLD")
        var expectedY = -2712.5
        for line in note {
            XCTAssertEqual(line.double(10), -900, "left edge of the plan")
            XCTAssertEqual(try XCTUnwrap(line.double(20)), expectedY, accuracy: 1e-6)
            XCTAssertEqual(line.double(40), 125)
            XCTAssertNil(line.string(72), "left aligned")
            XCTAssertNil(line.string(50), "not rotated")
            XCTAssertEqual(line.int(73), 0, "baseline anchor")
            expectedY -= 225
        }
        let lastBaseline = expectedY + 225
        // The header and the initial view cover the note: bottom at the last baseline, top and left unchanged.
        let extMin = doc.header("$EXTMIN").compactMap { Double($0.value) }
        let extMax = doc.header("$EXTMAX").compactMap { Double($0.value) }
        XCTAssertEqual(extMin[0], -900); XCTAssertEqual(extMin[1], lastBaseline, accuracy: 1e-6)
        XCTAssertEqual(extMax[1], 4300)
        XCTAssertGreaterThanOrEqual(extMax[0], 5600)
        // Metres: same layout divided by 1000.
        let (metreNote, _) = try noteEntities(DXFFixtures.samplePlan(), DXFExporter.Options(units: .metres))
        XCTAssertEqual(metreNote.count, note.count)
        XCTAssertEqual(metreNote.first?.double(10), -0.9)
        XCTAssertEqual(try XCTUnwrap(metreNote.first?.double(20)), -2.7125, accuracy: 1e-9)
        XCTAssertEqual(metreNote.first?.double(40), 0.125)
    }

    func testNoteStaysClearOfThePlanAtAnyScale() throws {
        for scale in [20.0, 50.0, 100.0, 200.0] {
            var plan = DXFFixtures.samplePlan()
            plan.options.scale = scale
            let (note, _) = try noteEntities(plan)
            let height = 2.5 * scale                                    // mm in model space
            let top = try XCTUnwrap(note.first?.double(20)) + height     // cap line of the first note line
            XCTAssertLessThan(top, -2400 - height, "at least one text height of clear space under the plan, 1:\(Int(scale))")
            XCTAssertEqual(note.first?.double(40), height)
        }
    }

    func testNoteIsWrittenWhenPlanTextIsSwitchedOffButNotWhenAskedNotTo() throws {
        let plan = DXFFixtures.samplePlan()
        var textOff = DXFExporter.Options()
        textOff.includeTextLayers = false
        let doc = try dxfParsed(plan, textOff)
        let texts = doc.entities.filter { $0.type == "TEXT" }
        XCTAssertGreaterThanOrEqual(texts.count, 4, "geometry alone says nothing about where its numbers come from")
        XCTAssertTrue(texts.allSatisfy { $0.layer == "NF-NOTES" && ($0.double(20) ?? 0) < -2400 })
        XCTAssertTrue(joined(texts).contains(ScanAccuracy.joineryDisclaimer))
        XCTAssertEqual(doc.entities.count - texts.count, 28 - 7, "all the plan's geometry, none of its text")

        var off = DXFExporter.Options()
        off.includeProvenanceNote = false
        XCTAssertEqual(try dxfParsed(plan, off).entities.count, 28)
        XCTAssertFalse(DXFExporter.export(plan, options: off).contains("LiDAR"))
        off.includeTextLayers = false
        XCTAssertEqual(try dxfParsed(plan, off).entities.filter { $0.type == "TEXT" }.count, 0)
    }

    func testNoteWordingFollowsWhetherVerifiedValuesAreMarked() throws {
        let marked = joined(try noteEntities(dxfRealPlan(markVerified: true)).note)
        XCTAssertTrue(marked.contains("Text values marked v are laser-verified"))
        XCTAssertFalse(marked.contains("not marked"))
        let unmarked = joined(try noteEntities(dxfRealPlan(markVerified: false)).note)
        XCTAssertTrue(unmarked.contains("Laser-verified values are not marked in this file"))
        XCTAssertFalse(unmarked.contains("marked v"), "no claim about a marker the plan does not carry")
        XCTAssertTrue(unmarked.contains(ScanAccuracy.joineryDisclaimer))
    }

    func testTitleLineIsWrittenOnlyWhenThePlanDidNotDrawItAlready() throws {
        var plan = DXFFixtures.samplePlan()
        plan.title = "Marina Gate 2 - Unit 2304"
        plan.subtitle = "Level 1"
        XCTAssertEqual(try noteEntities(plan).note.first?.string(1), "Marina Gate 2 - Unit 2304 - Level 1")
        // The CAD export already captions its plan with the same words on NF-NOTES: not repeated.
        plan.primitives.append(LayeredPrimitive(.notes, .text("Marina Gate 2 - Unit 2304 - Level 1", at: Point2(-0.9, -2.4),
                                                              height: 0.175, rotation: 0, anchor: .left, color: .black,
                                                              bold: true)))
        let withCaption = try noteEntities(plan).note
        XCTAssertEqual(withCaption.first?.string(1)?.hasPrefix("Geometry in this file is the LiDAR scan."), true)
        XCTAssertFalse(withCaption.contains { $0.string(1)?.contains("Marina") == true })
        // With the plan's text switched off the caption is not in the file, so the title is.
        var textOff = DXFExporter.Options()
        textOff.includeTextLayers = false
        XCTAssertEqual(try noteEntities(plan, textOff).note.first?.string(1), "Marina Gate 2 - Unit 2304 - Level 1")
        // Blank title and subtitle: no title line, and a lone title has no dash.
        plan.title = "  "; plan.subtitle = ""
        plan.primitives.removeLast()
        XCTAssertTrue(try noteEntities(plan).note.first?.string(1)?.hasPrefix("Geometry in this file") == true)
        plan.title = "Study"
        XCTAssertEqual(try noteEntities(plan).note.first?.string(1), "Study")
        // Non-ASCII titles are escaped like any other text.
        plan.title = "Caf\u{00E9} \u{00B0}"
        XCTAssertEqual(try noteEntities(plan).note.first?.string(1), "Caf\\U+00E9 %%d")
    }

    func testNoteWrapsToTheWidthOfTheDrawingAndKeepsEveryWord() throws {
        // A narrow drawing (a 1 m wide fitting, text 125 mm tall at 1:50): wrapped to the 40-text-height minimum,
        // 5 m, and no line is wider than that.
        let narrow = dxfDrawing([LayeredPrimitive(.furniture, .polyline(DXFFixtures.box(0, 0, 1, 2), closed: true,
                                                                        stroke: DXFFixtures.thin, fill: nil))])
        let note = try noteEntities(narrow).note
        let paragraphs = [
            "Geometry in this file is the LiDAR scan. Do not take cutting dimensions from distances measured on the drawing.",
            "Text values marked v are laser-verified and take precedence over the drawn geometry: cut joinery from the "
                + "labelled values.",
            ScanAccuracy.joineryDisclaimer,
        ]
        XCTAssertGreaterThan(note.count, paragraphs.count, "long paragraphs wrap on a narrow drawing")
        var widest = 0.0
        for line in note {
            let text = line.string(1) ?? ""
            let width = PlanDrawingBuilder.textWidth(text, height: 0.125, bold: line.string(7) != nil)
            XCTAssertLessThanOrEqual(width, 5.0, text)
            widest = max(widest, width)
        }
        XCTAssertGreaterThan(widest, 4.0, "lines fill the 5 m minimum width, they are not wrapped narrower")
        // The note sticks out to the right of a 1 m wide plan, and the header extents (and so the view) cover it.
        let extMax = try noteEntities(narrow).doc.header("$EXTMAX").compactMap { Double($0.value) }
        XCTAssertGreaterThan(extMax[0], 4_000)
        XCTAssertLessThanOrEqual(extMax[0], 5_000 + 1e-6)
        // Words are neither lost nor split: re-joining gives the paragraphs back in order.
        XCTAssertEqual(joined(note), paragraphs.joined(separator: " "))
        // A wide drawing (30 m) fits each paragraph on one line.
        let wide = dxfDrawing([LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(30, 0), DXFFixtures.wall))])
        let wideNote = try noteEntities(wide).note
        XCTAssertEqual(wideNote.map { $0.string(1) ?? "" }, paragraphs)
    }

    func testEmptyDrawingsAndDrawingsWithNothingWrittenGetNoNote() throws {
        XCTAssertEqual(try dxfParsed(dxfEmptyDrawing(), DXFExporter.Options()).entities.count, 0)
        // Only text, and text is off: nothing was drawn, so there is nothing to caption.
        let textOnly = dxfDrawing([LayeredPrimitive(.notes, .text("x", at: .zero, height: 0.1, rotation: 0, anchor: .left,
                                                                  color: .black, bold: false))])
        var textOff = DXFExporter.Options()
        textOff.includeTextLayers = false
        XCTAssertEqual(try dxfParsed(textOnly, textOff).entities.count, 0)
        // Only skipped primitives.
        let nothing = dxfDrawing([LayeredPrimitive(.walls, .line(.zero, .zero, DXFFixtures.wall))])
        XCTAssertEqual(try dxfParsed(nothing, DXFExporter.Options()).entities.count, 0)
    }

    func testFileWithTheNoteIsStructurallySoundAndDeterministic() throws {
        for options in [DXFExporter.Options(), DXFExporter.Options(units: .metres),
                        DXFExporter.Options(colorMode: .trueColor, windowsLineEndings: true)] {
            let plan = dxfRealPlan()
            let text = DXFExporter.export(plan, options: options)
            XCTAssertEqual(text, DXFExporter.export(plan, options: options))
            XCTAssertTrue(dxfIsASCII(text))
            let doc = try XCTUnwrap(DXFReader.parse(text))
            let defined = doc.definedHandles
            XCTAssertEqual(Set(defined).count, defined.count, "every handle is unique")
            let seed = try XCTUnwrap(Int(doc.header("$HANDSEED").first?.value ?? "", radix: 16))
            XCTAssertGreaterThan(seed, defined.compactMap { Int($0, radix: 16) }.max() ?? 0)
            let known = Set(defined).union(["0"])
            XCTAssertTrue(doc.referencedHandles.allSatisfy { known.contains($0) })
            XCTAssertTrue(doc.endsWithEOF)
            // The header extents cover every point written for every entity.
            let extMin = doc.header("$EXTMIN").compactMap { Double($0.value) }
            let extMax = doc.header("$EXTMAX").compactMap { Double($0.value) }
            for entity in doc.entities where entity.type == "TEXT" || entity.type == "LINE" {
                let x = try XCTUnwrap(entity.double(10)), y = try XCTUnwrap(entity.double(20))
                XCTAssertGreaterThanOrEqual(x, extMin[0] - 1e-6); XCTAssertLessThanOrEqual(x, extMax[0] + 1e-6)
                XCTAssertGreaterThanOrEqual(y, extMin[1] - 1e-6); XCTAssertLessThanOrEqual(y, extMax[1] + 1e-6)
            }
        }
    }

    /// The CAD export of a real property: the hand-off the joiners get. The file must say that its geometry is
    /// the scan, carry the joinery disclaimer once, and name the property and level exactly once (the engine's
    /// caption), not twice.
    func testTheEngineCADDrawingCarriesTheDisclaimerAndNamesThePropertyOnce() throws {
        let property = DemoProperty.make(now: Date(timeIntervalSince1970: 1_700_000_000))
        let floor = try XCTUnwrap(property.floors.first)
        let drawing = ExportEngine.cadDrawing(for: floor, in: property, scale: 50, units: .default)
        let text = DXFExporter.export(drawing, options: DXFExporter.Options(units: .millimetres))
        let doc = try XCTUnwrap(DXFReader.parse(text))
        let notes = doc.entities.filter { $0.type == "TEXT" && $0.layer == "NF-NOTES" }
        XCTAssertTrue(joined(notes).contains(ScanAccuracy.joineryDisclaimer))
        XCTAssertTrue(joined(notes).contains("Geometry in this file is the LiDAR scan."))
        let caption = "\(property.name) - \(floor.name)"
        XCTAssertEqual(notes.filter { $0.string(1) == caption }.count, 1, "caption once: \(notes.compactMap { $0.string(1) })")
        XCTAssertEqual(joined(notes).components(separatedBy: ScanAccuracy.joineryDisclaimer).count - 1, 1,
                       "the disclaimer once")
    }
}

// MARK: - 6. Header, view and options

final class DXFHeaderAndOptionsTests: XCTestCase {

    func testDimensionAndUnitVariablesFollowTheDrawingUnit() throws {
        func values(_ doc: DXFParsed, _ names: [String]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: names.map { ($0, doc.header($0).first?.value ?? "<missing>") })
        }
        let names = ["$DIMSCALE", "$DIMASZ", "$DIMEXO", "$DIMDLI", "$DIMEXE", "$DIMTXT", "$DIMCEN", "$DIMGAP",
                     "$DIMDEC", "$DIMTDEC", "$DIMLUNIT", "$LUNITS", "$LUPREC", "$TEXTSIZE", "$TRACEWID", "$CMLSCALE",
                     "$INSUNITS"]
        // Millimetres at 1:50: dimension text 2.5 mm on paper (x 50 by $DIMSCALE), whole millimetres.
        let mm = values(try dxfParsed(DXFFixtures.samplePlan()), names)
        XCTAssertEqual(mm, ["$DIMSCALE": "50.0", "$DIMASZ": "2.5", "$DIMEXO": "0.625", "$DIMDLI": "3.75",
                            "$DIMEXE": "1.25", "$DIMTXT": "2.5", "$DIMCEN": "2.5", "$DIMGAP": "0.625",
                            "$DIMDEC": "0", "$DIMTDEC": "0", "$DIMLUNIT": "2", "$LUNITS": "2", "$LUPREC": "1",
                            "$TEXTSIZE": "125.0", "$TRACEWID": "2.5", "$CMLSCALE": "20.0", "$INSUNITS": "4"])
        // Metres: the same sizes in metres, three decimals for dimensions, four for coordinates.
        var metres = dxfMappingOptions
        metres.units = .metres
        let m = values(try dxfParsed(DXFFixtures.samplePlan(), metres), names)
        XCTAssertEqual(m, ["$DIMSCALE": "50.0", "$DIMASZ": "0.0025", "$DIMEXO": "0.000625", "$DIMDLI": "0.00375",
                           "$DIMEXE": "0.00125", "$DIMTXT": "0.0025", "$DIMCEN": "0.0025", "$DIMGAP": "0.000625",
                           "$DIMDEC": "3", "$DIMTDEC": "3", "$DIMLUNIT": "2", "$LUNITS": "2", "$LUPREC": "4",
                           "$TEXTSIZE": "0.125", "$TRACEWID": "0.0025", "$CMLSCALE": "0.02", "$INSUNITS": "6"])
        // At 1:100 the dimension scale and text size double; the paper sizes do not.
        var hundred = DXFFixtures.samplePlan()
        hundred.options.scale = 100
        let h = values(try dxfParsed(hundred), ["$DIMSCALE", "$DIMTXT", "$TEXTSIZE"])
        XCTAssertEqual(h, ["$DIMSCALE": "100.0", "$DIMTXT": "2.5", "$TEXTSIZE": "250.0"])
    }

    func testDimensionStyleRecordMatchesTheHeader() throws {
        let cases: [(units: DXFUnits, txt: Double, gap: Double, decimals: Int)] = [
            (.millimetres, 2.5, 0.625, 0), (.metres, 0.0025, 0.000625, 3),
        ]
        for (units, txt, gap, decimals) in cases {
            let expected = (txt: txt, gap: gap, decimals: decimals)
            var options = dxfMappingOptions
            options.units = units
            let doc = try dxfParsed(DXFFixtures.samplePlan(), options)
            let style = try XCTUnwrap(doc.section("TABLES").first(where: { $0.type == "DIMSTYLE" }))
            XCTAssertEqual(style.string(2), "Standard")
            XCTAssertEqual(style.double(40), 50, "DIMSCALE")
            XCTAssertEqual(style.double(41), expected.txt, "DIMASZ")
            XCTAssertEqual(try XCTUnwrap(style.double(42)), expected.gap, accuracy: 1e-12, "DIMEXO")
            XCTAssertEqual(style.double(140), expected.txt, "DIMTXT")
            XCTAssertEqual(style.double(141), expected.txt, "DIMCEN")
            XCTAssertEqual(try XCTUnwrap(style.double(147)), expected.gap, accuracy: 1e-12, "DIMGAP")
            XCTAssertEqual(style.int(271), expected.decimals, "DIMDEC")
            XCTAssertEqual(style.int(272), expected.decimals, "DIMTDEC")
            XCTAssertEqual(style.int(77), 1, "DIMTAD above")
            // The STYLE table's fixed text height is the scaled 2.5 mm too.
            let standard = try XCTUnwrap(doc.section("TABLES").first(where: { $0.type == "STYLE" }))
            XCTAssertEqual(try XCTUnwrap(standard.double(42)), units == .millimetres ? 125 : 0.125, accuracy: 1e-12)
        }
    }

    func testViewportIsFramedOnTheExtents() throws {
        func viewport(_ plan: PlanDrawing, _ options: DXFExporter.Options = dxfMappingOptions) throws -> DXFRecord {
            try XCTUnwrap(try dxfParsed(plan, options).section("TABLES").first(where: { $0.type == "VPORT" }))
        }
        // Sample: extents (-900, -2400)..(5600, 4300). Centre (2350, 950); height 6700 is the larger of 6700 and
        // 6500 / 1.5, plus 10 %.
        let v = try viewport(DXFFixtures.samplePlan())
        XCTAssertEqual(v.string(2), "*Active")
        XCTAssertEqual(v.double(12), 2350); XCTAssertEqual(v.double(22), 950)
        XCTAssertEqual(try XCTUnwrap(v.double(40)), 7370, accuracy: 1e-6)
        XCTAssertEqual(v.double(41), 1.5)
        XCTAssertEqual(v.double(14), 100); XCTAssertEqual(v.double(24), 100)
        // Metres: all lengths divided by 1000.
        var metres = dxfMappingOptions
        metres.units = .metres
        let vm = try viewport(DXFFixtures.samplePlan(), metres)
        XCTAssertEqual(vm.double(12), 2.35); XCTAssertEqual(vm.double(22), 0.95)
        XCTAssertEqual(try XCTUnwrap(vm.double(40)), 7.37, accuracy: 1e-9)
        XCTAssertEqual(vm.double(14), 0.1)
        // A wide plan (30 m x 4 m) is framed by its width: 30000 / 1.5 = 20000, plus 10 %. Centre (15000, 2000).
        let wide = dxfDrawing([LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(30, 0), DXFFixtures.wall)),
                               LayeredPrimitive(.walls, .line(Point2(0, 4), Point2(30, 4), DXFFixtures.wall))])
        let vw = try viewport(wide)
        XCTAssertEqual(vw.double(12), 15_000); XCTAssertEqual(vw.double(22), 2_000)
        XCTAssertEqual(try XCTUnwrap(vw.double(40)), 22_000, accuracy: 1e-6)
        // A tiny plan is not zoomed to a point: at least 100 mm of height.
        let tiny = dxfDrawing([LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(0.01, 0), DXFFixtures.wall))])
        XCTAssertEqual(try XCTUnwrap(try viewport(tiny).double(40)), 110, accuracy: 1e-6)
        // An empty drawing opens on a 5 m x 3 m area.
        let empty = try viewport(dxfEmptyDrawing())
        XCTAssertEqual(empty.double(12), 2500); XCTAssertEqual(empty.double(22), 1500); XCTAssertEqual(empty.double(40), 5000)
        // With the note the view reaches down to it: extents (-900, -4062.5 or lower)..(5600, 4300).
        let withNote = try viewport(DXFFixtures.samplePlan(), DXFExporter.Options())
        let doc = try dxfParsed(DXFFixtures.samplePlan(), DXFExporter.Options())
        let extMin = doc.header("$EXTMIN").compactMap { Double($0.value) }
        let extMax = doc.header("$EXTMAX").compactMap { Double($0.value) }
        XCTAssertEqual(try XCTUnwrap(withNote.double(22)), (extMin[1] + extMax[1]) / 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(withNote.double(40)), (extMax[1] - extMin[1]) * 1.1, accuracy: 1e-6)
    }

    func testOptionsDecodeFromPartialOrOlderJSON() throws {
        let decoder = JSONDecoder()
        func options(_ json: String) throws -> DXFExporter.Options {
            try decoder.decode(DXFExporter.Options.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try options("{}"), DXFExporter.Options())
        XCTAssertEqual(try options(#"{"units":"metres"}"#), DXFExporter.Options(units: .metres))
        XCTAssertEqual(try options(#"{"colorMode":"trueColor","includeFills":false,"somethingNew":1}"#),
                       DXFExporter.Options(includeFills: false, colorMode: .trueColor))
        // Options stored before the note existed get the note.
        let old = #"{"units":"millimetres","includeTextLayers":true,"includeFills":true,"colorMode":"byLayer","entityLineweights":true,"windowsLineEndings":false}"#
        XCTAssertEqual(try options(old), DXFExporter.Options())
        XCTAssertTrue(try options(old).includeProvenanceNote)
        // A wrong value is an error, not a silent default.
        XCTAssertThrowsError(try options(#"{"units":"yards"}"#))
        XCTAssertThrowsError(try options(#"{"includeFills":"yes"}"#))
        // Everything round-trips, and all seven keys are written.
        let custom = DXFExporter.Options(units: .metres, includeTextLayers: false, includeFills: false,
                                         colorMode: .nearestACI, entityLineweights: false, windowsLineEndings: true,
                                         includeProvenanceNote: false)
        let data = try JSONEncoder().encode(custom)
        XCTAssertEqual(try decoder.decode(DXFExporter.Options.self, from: data), custom)
        let keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["units", "includeTextLayers", "includeFills", "colorMode", "entityLineweights",
                                   "windowsLineEndings", "includeProvenanceNote"])
    }
}


// MARK: - 3. External validation (ezdxf, GDAL/OGR) -----------------------------------------------------------

/// Expected model-space content computed from the input primitives with plain arithmetic, written as JSON for the
/// Python validator. It only covers well-formed input (no skipped primitives); the edge-case fixture is hand-written.
private enum DXFExpectation {
    static let validWeights = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140,
                               158, 200, 211]
    /// ACI colour and lineweight of each layer, typed by hand (kept in step with `DXFLayerStyle.all`).
    static let layers: [String: [Int]] = [
        "NF-WALLS": [7, 50], "NF-WALLS-OPEN": [150, 25], "NF-DOORS": [30, 25], "NF-WINDOWS": [4, 25],
        "NF-OPENINGS": [6, 25], "NF-FURNITURE": [8, 13], "NF-DIMENSIONS": [190, 13], "NF-ANGLES": [42, 13],
        "NF-ROOM-LABELS": [5, 18], "NF-NOTES": [32, 18],
    ]

    static func lineweight(_ mm: Double, layer: PlanLayer) -> Int {
        guard mm.isFinite, mm >= 0 else { return layers[layer.rawValue]![1] }
        let target = mm * 100
        var best = validWeights[0]
        for w in validWeights where abs(Double(w) - target) < abs(Double(best) - target) { best = w }
        return best
    }

    static func decoded(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2300}", with: "\u{00D8}").replacingOccurrences(of: "\u{2205}", with: "\u{00D8}")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func entities(_ items: [LayeredPrimitive], factor f: Double, options: DXFExporter.Options) -> [[String: Any]] {
        var out: [[String: Any]] = []
        // A colour is written for fills, in the two explicit modes, and for the plan's status colours; group 420
        // only in true-colour mode (release 2004).
        func colour(_ c: DrawColor, into d: inout [String: Any], force: Bool = false) {
            guard force || options.colorMode != .byLayer || DXFColor.isPlanStatusColor(c) else { return }
            d["color"] = DXFColor.aci(for: c)
            if options.colorMode == .trueColor { d["true_color"] = DXFColor.trueColor(c) }
        }
        func stroked(_ type: String, _ layer: PlanLayer, _ geom: [Double], _ s: StrokeStyle) -> [String: Any] {
            var d: [String: Any] = ["type": type, "layer": layer.rawValue, "geom": geom,
                                    "lineweight": lineweight(s.weight, layer: layer),
                                    "linetype": s.dashed ? "DASHED" : "CONTINUOUS"]
            colour(s.color, into: &d)
            return d
        }
        for item in items {
            switch item.primitive {
            case let .line(a, b, s):
                out.append(stroked("LINE", item.layer, [a.x * f, a.y * f, b.x * f, b.y * f], s))
            case let .polyline(pts, closed, s, fill):
                let flat = pts.flatMap { [$0.x * f, $0.y * f] }
                if let fill = fill, options.includeFills {
                    var d: [String: Any] = ["type": "HATCH", "layer": item.layer.rawValue, "geom": flat]
                    colour(fill, into: &d, force: true)
                    out.append(d)
                }
                if let s = s {
                    var d = stroked("LWPOLYLINE", item.layer, flat, s)
                    d["closed"] = closed && pts.count >= 3
                    out.append(d)
                }
            case let .arc(c, r, a0, a1, s):
                func folded(_ d: Double) -> Double { let m = d.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }
                if abs(a1 - a0) >= 360 {
                    out.append(stroked("CIRCLE", item.layer, [c.x * f, c.y * f, r * f], s))
                } else {
                    out.append(stroked("ARC", item.layer, [c.x * f, c.y * f, r * f, folded(a0), folded(a1)], s))
                }
            case let .circle(c, r, s):
                out.append(stroked("CIRCLE", item.layer, [c.x * f, c.y * f, r * f], s))
            case let .text(string, at, height, rotation, anchor, color, bold):
                guard options.includeTextLayers else { continue }
                var angle = rotation.truncatingRemainder(dividingBy: 360)
                if angle < 0 { angle += 360 }
                var d: [String: Any] = ["type": "TEXT", "layer": item.layer.rawValue,
                                        "geom": [at.x * f, at.y * f, height * f, angle],
                                        "halign": anchor == .left ? 0 : (anchor == .center ? 1 : 2),
                                        "style": bold ? "NF-BOLD" : "Standard", "decoded": decoded(string)]
                colour(color, into: &d)
                out.append(d)
            }
        }
        return out
    }

    /// Extents the header must carry: the drawing bounds widened by every point of geometry.
    static func extents(_ plan: PlanDrawing, factor f: Double) -> [[Double]] {
        var pts: [Point2] = [plan.bounds.min, plan.bounds.max]
        for item in plan.primitives {
            switch item.primitive {
            case let .line(a, b, _): pts += [a, b]
            case let .polyline(p, _, _, _): pts += p
            case let .arc(c, r, _, _, _), let .circle(c, r, _): pts += [Point2(c.x - r, c.y - r), Point2(c.x + r, c.y + r)]
            case let .text(_, at, _, _, _, _, _): pts.append(at)
            }
        }
        let xs = pts.map { $0.x * f }, ys = pts.map { $0.y * f }
        return [[xs.min()!, ys.min()!], [xs.max()!, ys.max()!]]
    }

    static func lineLength(_ items: [LayeredPrimitive], factor f: Double) -> Double {
        items.reduce(0) { total, item in
            if case let .line(a, b, _) = item.primitive { return total + a.distance(to: b) * f }
            return total
        }
    }

    /// The whole expectation document for a well-formed plan.
    static func document(case name: String, plan: PlanDrawing, options: DXFExporter.Options) -> [String: Any] {
        let f = options.units.unitsPerMetre
        let entities = self.entities(plan.primitives, factor: f, options: options)
        let hasEntities = !entities.isEmpty
        let ext = hasEntities ? extents(plan, factor: f) : nil
        let scale = plan.options.scale.isFinite && plan.options.scale > 0 ? plan.options.scale : 50
        let unit = options.units == .millimetres ? 1.0 : 0.001
        var document: [String: Any] = [
            "case": name, "units": options.units.insunitsCode, "layers": layers, "entities": entities,
            "version": options.colorMode == .trueColor ? "AC1018" : "AC1015",
            "line_length": lineLength(plan.primitives, factor: f),
            "extmin": ext?[0] ?? NSNull(), "extmax": ext?[1] ?? NSNull(),
            "dash": [3 * scale * unit, -1.5 * scale * unit],
        ]
        // The provenance note: the sentences it must contain (typed here, not read back from the exporter) and the
        // text height it is set in (2.5 mm on paper at the plot scale).
        if options.includeProvenanceNote && hasEntities {
            var needles = ["Geometry in this file is the LiDAR scan.", ScanAccuracy.joineryDisclaimer]
            needles.append(plan.options.markVerified ? "Text values marked v are laser-verified"
                                                     : "Laser-verified values are not marked in this file")
            document["note"] = ["must_contain": needles, "text_height": 2.5 * scale * unit] as [String: Any]
        }
        return document
    }
}

/// A fixture packed with the awkward inputs: wrap-around and full-turn arcs, escapes, scripts outside Latin-1,
/// duplicate vertices, dashed everything, extreme weights, plus primitives that must be dropped.
private func dxfEdgeCasePlan() -> (plan: PlanDrawing, expected: [[String: Any]], lineLength: Double) {
    let nan = Double.nan
    let door = DXFFixtures.door
    let dashed = StrokeStyle(weight: 0.25, color: DrawColor(0, 0, 1), dashed: true)
    func text(_ s: String, _ rotation: Double = 0, _ anchor: TextAnchor = .left) -> LayeredPrimitive {
        LayeredPrimitive(.notes, .text(s, at: Point2(0.5, 0.25), height: 0.1, rotation: rotation, anchor: anchor,
                                       color: .black, bold: false))
    }
    func textExpectation(_ decoded: String, _ rotation: Double, _ halign: Int) -> [String: Any] {
        ["type": "TEXT", "layer": "NF-NOTES", "geom": [500.0, 250.0, 100.0, rotation], "halign": halign,
         "style": "Standard", "decoded": decoded]
    }

    var items: [LayeredPrimitive] = []
    var expected: [[String: Any]] = []

    // Arcs.
    items.append(LayeredPrimitive(.doors, .arc(center: Point2(1, 2), radius: 0.5, startAngle: 350, endAngle: 10, door)))
    expected.append(["type": "ARC", "layer": "NF-DOORS", "geom": [1000.0, 2000.0, 500.0, 350.0, 10.0], "lineweight": 25,
                     "linetype": "CONTINUOUS"])
    items.append(LayeredPrimitive(.doors, .arc(center: Point2(1, 2), radius: 0.5, startAngle: -90, endAngle: 0, dashed)))
    expected.append(["type": "ARC", "layer": "NF-DOORS", "geom": [1000.0, 2000.0, 500.0, 270.0, 0.0], "lineweight": 25,
                     "linetype": "DASHED"])
    items.append(LayeredPrimitive(.doors, .arc(center: Point2(1, 2), radius: 0.5, startAngle: 0, endAngle: 360, door)))
    expected.append(["type": "CIRCLE", "layer": "NF-DOORS", "geom": [1000.0, 2000.0, 500.0], "lineweight": 25,
                     "linetype": "CONTINUOUS"])
    // Text with symbols, scripts, controls.
    items.append(text("\u{2300}20 \u{00B1}0.5 12\u{00B0} \u{2013} 5 m\u{00B2}", 30, .center))
    expected.append(textExpectation("\u{00D8}20 \u{00B1}0.5 12\u{00B0} \u{2013} 5 m\u{00B2}", 30, 1))
    items.append(text("\u{0645}\u{0643}\u{062A}\u{0628}", 0, .right))
    expected.append(textExpectation("\u{0645}\u{0643}\u{062A}\u{0628}", 0, 2))
    items.append(text("smile \u{1F600}", 270))
    expected.append(textExpectation("smile \u{1F600}", 270, 0))
    items.append(text("two\nlines", -45))
    expected.append(textExpectation("two lines", 315, 0))
    items.append(text("100% and 5 % off"))
    expected.append(textExpectation("100% and 5 % off", 0, 0))
    // Polylines: duplicate vertices, closing duplicate, fill-only loop, 2-point closed.
    items.append(LayeredPrimitive(.furniture, .polyline([Point2(0, 0), Point2(0, 0), Point2(1, 0), Point2(1, 1),
                                                         Point2(0, 0)], closed: true, stroke: DXFFixtures.thin,
                                                        fill: DrawColor(0.9, 0.95, 1))))
    expected.append(["type": "HATCH", "layer": "NF-FURNITURE", "geom": [0.0, 0.0, 1000.0, 0.0, 1000.0, 1000.0],
                     "color": DXFColor.nearestACI(DrawColor(0.9, 0.95, 1))])
    expected.append(["type": "LWPOLYLINE", "layer": "NF-FURNITURE", "geom": [0.0, 0.0, 1000.0, 0.0, 1000.0, 1000.0],
                     "closed": true, "lineweight": 13, "linetype": "CONTINUOUS"])
    items.append(LayeredPrimitive(.furniture, .polyline([Point2(2, 0), Point2(3, 0), Point2(3, 1)], closed: false,
                                                        stroke: nil, fill: DrawColor(0.5, 0.5, 0.5))))
    expected.append(["type": "HATCH", "layer": "NF-FURNITURE", "geom": [2000.0, 0.0, 3000.0, 0.0, 3000.0, 1000.0],
                     "color": DXFColor.nearestACI(DrawColor(0.5, 0.5, 0.5))])
    items.append(LayeredPrimitive(.furniture, .polyline([Point2(4, 0), Point2(5, 0)], closed: true, stroke: dashed,
                                                        fill: nil)))
    expected.append(["type": "LWPOLYLINE", "layer": "NF-FURNITURE", "geom": [4000.0, 0.0, 5000.0, 0.0], "closed": false,
                     "lineweight": 25, "linetype": "DASHED"])
    // Lineweights at the extremes on the 0.13 mm dimension layer.
    for (mm, lw) in [(0.0, 0), (9.0, 211), (nan, 13), (-1.0, 13), (0.19, 18)] {
        items.append(LayeredPrimitive(.dimensions, .line(Point2(0, 5), Point2(2, 5), StrokeStyle(weight: mm))))
        expected.append(["type": "LINE", "layer": "NF-DIMENSIONS", "geom": [0.0, 5000.0, 2000.0, 5000.0], "lineweight": lw,
                         "linetype": "CONTINUOUS"])
    }
    // Things that must vanish.
    items.append(LayeredPrimitive(.walls, .line(Point2(nan, 0), Point2(1, 1), door)))
    items.append(LayeredPrimitive(.walls, .line(Point2(1, 1), Point2(1, 1), door)))
    items.append(LayeredPrimitive(.walls, .circle(center: .zero, radius: .infinity, door)))
    items.append(LayeredPrimitive(.walls, .arc(center: .zero, radius: 0, startAngle: 0, endAngle: 90, door)))
    items.append(LayeredPrimitive(.walls, .polyline([Point2(0, 0), Point2(1, nan), Point2(1, 1)], closed: true, stroke: door, fill: .black)))
    items.append(text(""))
    items.append(text("   "))
    items.append(LayeredPrimitive(.notes, .text("x", at: .zero, height: 0, rotation: 0, anchor: .left, color: .black, bold: false)))
    // One good line at the end proves the file is intact after the bad ones.
    items.append(LayeredPrimitive(.walls, .line(Point2(0, 0), Point2(3, 4), DXFFixtures.wall)))
    expected.append(["type": "LINE", "layer": "NF-WALLS", "geom": [0.0, 0.0, 3000.0, 4000.0], "lineweight": 50,
                     "linetype": "CONTINUOUS"])
    let plan = PlanDrawing(primitives: items, bounds: Bounds2(min: Point2(-1, -1), max: Point2(6, 6)),
                           options: PlanOptions(scale: 50))
    return (plan, expected, 5 * 2000.0 + 5000.0)
}

/// 3000 pseudo-random entities: volume and variety.
private func dxfBulkPlan() -> PlanDrawing {
    var g = DXFSeededGenerator(seed: 2024)
    func r(_ lo: Double, _ hi: Double) -> Double { Double.random(in: lo...hi, using: &g) }
    func pt() -> Point2 { Point2(r(-30, 30), r(-30, 30)) }
    func stroke() -> StrokeStyle {
        StrokeStyle(weight: [0.13, 0.18, 0.25, 0.35, 0.5][Int(r(0, 4.999))], color: DrawColor(r(0, 1), r(0, 1), r(0, 1)),
                    dashed: r(0, 1) < 0.2)
    }
    let layers = PlanLayer.allCases
    var items: [LayeredPrimitive] = []
    for i in 0..<3000 {
        let layer = layers[i % layers.count]
        switch i % 6 {
        case 0, 1: items.append(LayeredPrimitive(layer, .line(pt(), pt(), stroke())))
        case 2:
            let n = Int(r(3, 8))
            items.append(LayeredPrimitive(layer, .polyline((0..<n).map { _ in pt() }, closed: r(0, 1) < 0.5, stroke: stroke(),
                                                           fill: r(0, 1) < 0.3 ? DrawColor(r(0, 1), r(0, 1), r(0, 1)) : nil)))
        case 3: items.append(LayeredPrimitive(layer, .circle(center: pt(), radius: r(0.05, 2), stroke())))
        case 4: items.append(LayeredPrimitive(layer, .arc(center: pt(), radius: r(0.05, 2), startAngle: r(-400, 400),
                                                          endAngle: r(10, 350), stroke())))
        default:
            items.append(LayeredPrimitive(layer, .text("T\(i) \(Int(r(0, 360)))\u{00B0}", at: pt(), height: r(0.05, 0.3),
                                                       rotation: r(-180, 360),
                                                       anchor: [.left, .center, .right][Int(r(0, 2.999))],
                                                       color: DrawColor(r(0, 1), r(0, 1), r(0, 1)), bold: r(0, 1) < 0.2)))
        }
    }
    return PlanDrawing(primitives: items, bounds: Bounds2(min: Point2(-40, -40), max: Point2(40, 40)), options: PlanOptions())
}

private let dxfValidatorScript = #"""
#!/usr/bin/env python3
"""Validates NexaFix DXF exports with ezdxf and, when installed, GDAL's OGR DXF driver.

usage: validate_dxf.py <directory holding NAME.dxf and NAME.expect.json pairs>

Exit status 0 when every case passes. Rendering to NAME.png needs matplotlib and is optional. The LibreCAD
print check is slow and runs only when the environment variable NEXAFIX_EXTERNAL_LIBRECAD is 1.
"""
import glob
import json
import math
import os
import re
import sys
from collections import Counter

import ezdxf
import ezdxf.bbox
from ezdxf import recover
from ezdxf.entities import BoundaryPathType
from ezdxf.tools.text import plain_text

TOL = 1e-6
STROKE_TYPES = ("LINE", "LWPOLYLINE", "ARC", "CIRCLE")
failures = []
notes = []


def fail(case, message):
    failures.append("[%s] %s" % (case, message))


def near(a, b, tol=TOL):
    return abs(a - b) <= tol + 1e-12 * abs(b)


def near_list(a, b, tol=TOL):
    return len(a) == len(b) and all(near(x, y, tol) for x, y in zip(a, b))


# ---------------------------------------------------------------- raw text level

def raw_checks(case, path, expect):
    """Independent re-parse of the group structure: ASCII, pairs, handles, references, seed."""
    data = open(path, "rb").read()
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as exc:
        fail(case, "file is not 7-bit ASCII: %s" % exc)
        text = data.decode("latin-1")
    crlf = text.count("\r\n")
    if crlf and crlf != text.count("\n"):
        fail(case, "mixed line endings")
    if "\r" in text.replace("\r\n", ""):
        fail(case, "stray carriage return")
    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) % 2:
        fail(case, "odd number of lines: group code without value")
        return
    tags = []
    for i in range(0, len(lines), 2):
        try:
            code = int(lines[i])
        except ValueError:
            fail(case, "line %d: group code %r is not an integer" % (i + 1, lines[i]))
            return
        if not 0 <= code <= 1071:
            fail(case, "line %d: group code %d out of range" % (i + 1, code))
        tags.append((code, lines[i + 1]))
    if tags[0] != (0, "SECTION") or tags[-1] != (0, "EOF"):
        fail(case, "file must start with SECTION and end with EOF")
    if expect["version"] == "AC1015" and any(code == 420 for code, _ in tags):
        fail(case, "group 420 (true colour) is written into a release 2000 file")
    if re.search(r"(?i)\b(nan|inf|infinity)\b", text):
        fail(case, "non-finite number in file")
    section = None
    defined, refs = [], []
    seed = None
    for index, (code, value) in enumerate(tags):
        if code == 0 and value == "SECTION":
            section = tags[index + 1][1]
        elif code == 0 and value == "ENDSEC":
            section = None
        elif section == "HEADER":
            if code == 9 and value == "$HANDSEED":
                seed = tags[index + 1][1]
        elif section is not None:
            if code in (5, 105):
                defined.append(value)
            elif code in (330, 340, 350, 390):
                refs.append(value)
    if len(set(defined)) != len(defined):
        dup = [h for h, n in Counter(defined).items() if n > 1]
        fail(case, "duplicate handles: %s" % dup[:5])
    if "0" in defined:
        fail(case, "handle 0 is reserved")
    unknown = sorted(set(r for r in refs if r != "0" and r not in set(defined)))
    if unknown:
        fail(case, "references to undefined handles: %s" % unknown[:5])
    if seed is None:
        fail(case, "no $HANDSEED")
    elif defined and int(seed, 16) <= max(int(h, 16) for h in defined):
        fail(case, "$HANDSEED %s is not beyond the highest handle %X" % (seed, max(int(h, 16) for h in defined)))


# ---------------------------------------------------------------- ezdxf

def layer_of(doc, entity):
    return doc.layers.get(entity.dxf.layer)


def effective_lineweight(doc, entity):
    value = entity.dxf.get("lineweight", -1)
    if value in (-1, -2, -3):
        value = layer_of(doc, entity).dxf.lineweight
    return value


def effective_linetype(doc, entity):
    value = entity.dxf.get("linetype", "BYLAYER")
    if value.upper() == "BYLAYER":
        value = layer_of(doc, entity).dxf.linetype
    return value.upper()


def flat(points):
    return [float(c) for p in points for c in p[:2]]


def check_entity(case, doc, index, entity, x):
    where = "entity #%d (%s on %s)" % (index, x["type"], x["layer"])
    kind = entity.dxftype()
    if kind != x["type"]:
        fail(case, "%s: found %s" % (where, kind))
        return
    if entity.dxf.layer != x["layer"]:
        fail(case, "%s: layer is %s" % (where, entity.dxf.layer))
    if entity.dxf.get("color", 256) != x.get("color", 256):
        fail(case, "%s: colour %s, expected %s" % (where, entity.dxf.get("color", 256), x.get("color", 256)))
    if entity.dxf.get("true_color", None) != x.get("true_color"):
        fail(case, "%s: true colour %s, expected %s" % (where, entity.dxf.get("true_color", None), x.get("true_color")))
    if kind in STROKE_TYPES:
        if effective_lineweight(doc, entity) != x["lineweight"]:
            fail(case, "%s: lineweight %s, expected %s" % (where, effective_lineweight(doc, entity), x["lineweight"]))
        if effective_linetype(doc, entity) != x["linetype"]:
            fail(case, "%s: linetype %s, expected %s" % (where, effective_linetype(doc, entity), x["linetype"]))
    if kind == "LINE":
        s, e = entity.dxf.start, entity.dxf.end
        if not near_list([s[0], s[1], e[0], e[1]], x["geom"]) or s[2] != 0 or e[2] != 0:
            fail(case, "%s: points %s -> %s, expected %s" % (where, tuple(s), tuple(e), x["geom"]))
    elif kind == "LWPOLYLINE":
        pts = flat(entity.get_points("xy"))
        if not near_list(pts, x["geom"]):
            fail(case, "%s: vertices differ (got %d numbers, expected %d)" % (where, len(pts), len(x["geom"])))
        if bool(entity.closed) != x["closed"]:
            fail(case, "%s: closed flag %s, expected %s" % (where, entity.closed, x["closed"]))
    elif kind == "ARC":
        c = entity.dxf.center
        got = [c[0], c[1], entity.dxf.radius, entity.dxf.start_angle, entity.dxf.end_angle]
        if not near_list(got, x["geom"]):
            fail(case, "%s: %s, expected %s" % (where, got, x["geom"]))
    elif kind == "CIRCLE":
        c = entity.dxf.center
        if not near_list([c[0], c[1], entity.dxf.radius], x["geom"]):
            fail(case, "%s: circle differs" % where)
    elif kind == "TEXT":
        raw = entity.dxf.text
        if not raw.isascii():
            fail(case, "%s: text is not ASCII: %r" % (where, raw))
        decoded = plain_text(ezdxf.decode_dxf_unicode(raw)).encode("utf-16", "surrogatepass").decode("utf-16")
        if decoded != x["decoded"]:
            fail(case, "%s: text decodes to %r, expected %r (raw %r)" % (where, decoded, x["decoded"], raw))
        insert = entity.dxf.insert
        halign = entity.dxf.get("halign", 0)
        if halign != x["halign"]:
            fail(case, "%s: halign %s, expected %s" % (where, halign, x["halign"]))
        if entity.dxf.get("valign", 0) != 0:
            fail(case, "%s: valign must be baseline" % where)
        anchor = entity.dxf.get("align_point", insert) if halign else insert
        if not near_list([insert[0], insert[1], anchor[0], anchor[1], entity.dxf.height, entity.dxf.get("rotation", 0)],
                         x["geom"][:2] + x["geom"][:2] + x["geom"][2:]):
            fail(case, "%s: placement %s / %s h=%s rot=%s, expected %s" % (
                where, tuple(insert), tuple(anchor), entity.dxf.height, entity.dxf.get("rotation", 0), x["geom"]))
        if entity.dxf.get("style", "Standard") != x["style"]:
            fail(case, "%s: style %s, expected %s" % (where, entity.dxf.get("style", "Standard"), x["style"]))
    elif kind == "HATCH":
        if entity.dxf.solid_fill != 1 or entity.dxf.pattern_name != "SOLID":
            fail(case, "%s: not a solid fill" % where)
        if len(entity.paths.paths) != 1:
            fail(case, "%s: expected one boundary path" % where)
        else:
            path = entity.paths.paths[0]
            if path.type != BoundaryPathType.POLYLINE:
                fail(case, "%s: boundary is not a polyline path" % where)
            if not near_list(flat(path.vertices), x["geom"]):
                fail(case, "%s: boundary differs" % where)
            if not path.is_closed:
                fail(case, "%s: boundary not closed" % where)


def check_note(case, doc, entities, note, expect):
    """The provenance note: TEXT lines on NF-NOTES, left-aligned under the plan, with the required wording."""
    if len(entities) < 3:
        fail(case, "provenance note has %d lines" % len(entities))
        return
    height = note["text_height"]
    texts = []
    previous = None
    for entity in entities:
        if entity.dxftype() != "TEXT" or entity.dxf.layer != "NF-NOTES":
            fail(case, "note entity is %s on %s" % (entity.dxftype(), entity.dxf.layer))
            continue
        raw = entity.dxf.text
        if not raw.isascii():
            fail(case, "note text is not ASCII: %r" % raw)
        texts.append(plain_text(ezdxf.decode_dxf_unicode(raw)))
        insert = entity.dxf.insert
        if not near(entity.dxf.height, height, 1e-9):
            fail(case, "note text height %s, expected %s" % (entity.dxf.height, height))
        if entity.dxf.get("halign", 0) != 0 or entity.dxf.get("valign", 0) != 0 or entity.dxf.get("rotation", 0) != 0:
            fail(case, "note text must be left aligned on the baseline and unrotated")
        if not near(insert[0], expect["extmin"][0], 1e-6):
            fail(case, "note starts at x=%s, plan extents start at %s" % (insert[0], expect["extmin"][0]))
        if insert[1] > expect["extmin"][1] - 2.5 * height + 1e-6:
            fail(case, "note line at y=%s overlaps the plan (bottom %s)" % (insert[1], expect["extmin"][1]))
        if previous is not None and not near(previous - insert[1], 1.8 * height, 1e-6):
            fail(case, "note line spacing %s, expected %s" % (previous - insert[1], 1.8 * height))
        previous = insert[1]
    joined = " ".join(texts)
    for needle in note["must_contain"]:
        if needle not in joined:
            fail(case, "note does not say %r" % needle)
    if previous is not None and not near(doc.header["$EXTMIN"][1], previous, 1e-6):
        fail(case, "header extents end at y=%s, the last note line is at %s" % (doc.header["$EXTMIN"][1], previous))


def ezdxf_checks(case, path, expect):
    try:
        doc = ezdxf.readfile(path)
    except Exception as exc:  # pragma: no cover
        fail(case, "ezdxf.readfile failed: %r" % exc)
        return None
    auditor = doc.audit()
    for item in auditor.errors:
        fail(case, "audit error: %s" % item.message)
    for item in auditor.fixes:
        fail(case, "audit needed a fix: %s" % item.message)
    try:
        rdoc, rauditor = recover.readfile(path)
    except Exception as exc:  # pragma: no cover
        fail(case, "ezdxf.recover.readfile failed: %r" % exc)
        return doc
    for item in rauditor.errors:
        fail(case, "recover error: %s" % item.message)
    for item in rauditor.fixes:
        fail(case, "recover needed a fix: %s" % item.message)
    if len(list(rdoc.modelspace())) != len(list(doc.modelspace())):
        fail(case, "recover mode reads a different number of entities")

    header = doc.header
    if doc.dxfversion != expect["version"] or header["$ACADVER"] != expect["version"]:
        fail(case, "version %s, expected %s" % (doc.dxfversion, expect["version"]))
    note = expect.get("note")
    if header["$INSUNITS"] != expect["units"]:
        fail(case, "$INSUNITS %s, expected %s" % (header["$INSUNITS"], expect["units"]))
    if header["$MEASUREMENT"] != 1:
        fail(case, "$MEASUREMENT is not 1")
    if expect["extmin"] is None:
        if tuple(header["$EXTMIN"]) != (1e20, 1e20, 1e20) or tuple(header["$EXTMAX"]) != (-1e20, -1e20, -1e20):
            fail(case, "empty drawing must carry the +/-1e20 extents marker")
    elif note is None:
        if not near_list(list(header["$EXTMIN"])[:2], expect["extmin"]) or \
                not near_list(list(header["$EXTMAX"])[:2], expect["extmax"]):
            fail(case, "extents %s %s, expected %s %s" % (header["$EXTMIN"], header["$EXTMAX"],
                                                          expect["extmin"], expect["extmax"]))
    else:
        # The note hangs below the plan: same left edge and top, extended downwards (and possibly to the right).
        lo, hi = list(header["$EXTMIN"])[:2], list(header["$EXTMAX"])[:2]
        if not near(lo[0], expect["extmin"][0]) or not near(hi[1], expect["extmax"][1]) or \
                lo[1] > expect["extmin"][1] - 2.5 * note["text_height"] or hi[0] < expect["extmax"][0] - 1e-6:
            fail(case, "extents with note %s %s, plan extents %s %s" % (lo, hi, expect["extmin"], expect["extmax"]))

    # Tables.
    for name, color_and_weight in expect["layers"].items():
        if not doc.layers.has_entry(name):
            fail(case, "layer %s missing" % name)
            continue
        layer = doc.layers.get(name)
        if layer.dxf.color != color_and_weight[0] or layer.dxf.lineweight != color_and_weight[1]:
            fail(case, "layer %s is colour %s weight %s" % (name, layer.dxf.color, layer.dxf.lineweight))
        if layer.dxf.linetype.upper() != "CONTINUOUS":
            fail(case, "layer %s linetype %s" % (name, layer.dxf.linetype))
        if not layer.is_on() or layer.is_frozen() or layer.is_locked():
            fail(case, "layer %s is off, frozen or locked" % name)
    colours = [v[0] for v in expect["layers"].values()]
    if len(set(colours)) != len(colours):
        fail(case, "layer colours are not distinct")
    for table, names in ((doc.linetypes, ["CONTINUOUS", "DASHED", "BYLAYER", "BYBLOCK"]),
                         (doc.styles, ["STANDARD", "NF-BOLD"]), (doc.appids, ["ACAD"])):
        for name in names:
            if not table.has_entry(name):
                fail(case, "table entry %s missing" % name)
    if sorted(b.dxf.name for b in doc.block_records) != ["*Model_Space", "*Paper_Space"]:
        fail(case, "block records: %s" % [b.dxf.name for b in doc.block_records])
    if "Layout1" not in doc.layouts.names() or "Model" not in doc.layouts.names():
        fail(case, "layouts: %s" % doc.layouts.names())
    dashed = [t.value for t in doc.linetypes.get("DASHED").pattern_tags.tags if t.code == 49]
    if not near_list(dashed, expect["dash"], 1e-9):
        fail(case, "DASHED pattern %s, expected %s" % (dashed, expect["dash"]))

    # Entities, in file order.
    all_entities = list(doc.modelspace())
    expected = expect["entities"]
    # The provenance note, when there is one, is written after the last plan entity.
    entities, note_entities = (all_entities[:len(expected)], all_entities[len(expected):]) if note else (all_entities, [])
    if len(entities) != len(expected):
        fail(case, "%d entities, expected %d" % (len(entities), len(expected)))
        got, want = Counter((e.dxf.layer, e.dxftype()) for e in entities), Counter((x["layer"], x["type"]) for x in expected)
        fail(case, "difference (got - expected): %s; (expected - got): %s" % (dict(got - want), dict(want - got)))
    else:
        for index, (entity, x) in enumerate(zip(entities, expected)):
            check_entity(case, doc, index, entity, x)
    if note:
        check_note(case, doc, note_entities, note, expect)
    length = 0.0
    for entity in entities:
        if entity.dxftype() == "LINE":
            length += math.dist(entity.dxf.start, entity.dxf.end)
    if not near(length, expect["line_length"], 1e-6 * max(1.0, expect["line_length"])):
        fail(case, "total LINE length %.6f, expected %.6f" % (length, expect["line_length"]))

    # Everything but text (whose size ezdxf only estimates) lies inside the extents in the header.
    shapes = [e for e in entities if e.dxftype() != "TEXT"]
    if shapes and expect["extmin"] is not None:
        box = ezdxf.bbox.extents(shapes)
        slack = 1e-6 * max(1.0, abs(box.extmax.x), abs(box.extmax.y))
        if box.extmin.x < expect["extmin"][0] - slack or box.extmin.y < expect["extmin"][1] - slack or \
                box.extmax.x > expect["extmax"][0] + slack or box.extmax.y > expect["extmax"][1] + slack:
            fail(case, "geometry %s..%s sticks out of the header extents" % (tuple(box.extmin), tuple(box.extmax)))
    return rdoc


# ---------------------------------------------------------------- GDAL / OGR

def polygon_area(flat_points):
    pts = list(zip(flat_points[0::2], flat_points[1::2]))
    return abs(sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                   for i in range(len(pts)))) / 2


def ogr_checks(case, path, expect):
    """A second, unrelated parser (GDAL's DXF driver) must see the same entities and geometry."""
    try:
        from pyogrio import raw
        import shapely
    except Exception:
        notes.append("pyogrio/shapely not installed: OGR cross-check skipped")
        return
    expected = expect["entities"]
    if not expected:
        return
    note_lines = 0
    if expect.get("note"):
        note_lines = len(list(ezdxf.readfile(path).modelspace())) - len(expected)
    try:
        meta, _, geoms, fields = raw.read(path, layer="entities")
    except Exception as exc:
        fail(case, "OGR could not read the file: %s" % exc)
        return
    names = list(meta["fields"])
    layers, subclasses = fields[names.index("Layer")], fields[names.index("SubClasses")]
    if len(layers) != len(expected) + note_lines:
        fail(case, "OGR sees %d features, expected %d" % (len(layers), len(expected) + note_lines))
        return
    shapes = shapely.from_wkb(geoms)
    if sorted(layers) != sorted([x["layer"] for x in expected] + ["NF-NOTES"] * note_lines):
        fail(case, "OGR layer names differ")
    line_total = sum(shapes[i].length for i in range(len(shapes)) if subclasses[i] == "AcDbEntity:AcDbLine")
    if not near(line_total, expect["line_length"], 1e-6 * max(1.0, expect["line_length"])):
        fail(case, "OGR total LINE length %.6f, expected %.6f" % (line_total, expect["line_length"]))
    areas = sorted(round(shapes[i].area, 3) for i in range(len(shapes)) if subclasses[i] == "AcDbEntity:AcDbHatch")
    want = sorted(round(polygon_area(x["geom"]), 3) for x in expected if x["type"] == "HATCH")
    if len(areas) != len(want) or not all(abs(a - b) <= 1e-3 + 1e-9 * b for a, b in zip(areas, want)):
        fail(case, "OGR hatch areas %s, expected %s" % (areas[:5], want[:5]))
    kinds = Counter(subclasses)
    for sub, kind in (("AcDbEntity:AcDbLine", "LINE"), ("AcDbEntity:AcDbPolyline", "LWPOLYLINE"),
                      ("AcDbEntity:AcDbHatch", "HATCH"), ("AcDbEntity:AcDbText:AcDbText", "TEXT"),
                      ("AcDbEntity:AcDbCircle", "CIRCLE"), ("AcDbEntity:AcDbCircle:AcDbArc", "ARC")):
        n = sum(1 for x in expected if x["type"] == kind) + (note_lines if kind == "TEXT" else 0)
        if kinds.get(sub, 0) != n:
            fail(case, "OGR counts %d %s, expected %d" % (kinds.get(sub, 0), kind, n))


# ---------------------------------------------------------------- LibreCAD (libdxfrw), optional

librecad_state = {"ok": None, "exe": None}


def librecad_print(directory, name, path):
    """Print a DXF to PDF with LibreCAD's console tool; returns the PDF path or None."""
    import subprocess
    import tempfile
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    runtime = tempfile.mkdtemp()
    os.chmod(runtime, 0o700)
    env["XDG_RUNTIME_DIR"] = runtime
    out_dir = os.path.join(directory, "librecad")
    os.makedirs(out_dir, exist_ok=True)
    pdf = os.path.join(out_dir, name + ".pdf")
    if os.path.exists(pdf):
        os.remove(pdf)
    try:
        subprocess.run([librecad_state["exe"], "dxf2pdf", "-a", "-t", out_dir, path], env=env,
                       capture_output=True, text=True, timeout=120)
    except Exception:
        return None
    return pdf if os.path.exists(pdf) else None


def librecad_checks(case, path, expect, directory):
    """LibreCAD (libdxfrw) must open the file and print it to a sensible page with content."""
    import shutil
    if os.environ.get("NEXAFIX_EXTERNAL_LIBRECAD") != "1":
        notes.append("LibreCAD cross-check skipped (set NEXAFIX_EXTERNAL_LIBRECAD=1 to run it)")
        return
    if librecad_state["ok"] is None:
        librecad_state["exe"] = shutil.which("librecad")
        librecad_state["ok"] = False
        if librecad_state["exe"] is None:
            notes.append("librecad not installed: LibreCAD cross-check skipped")
        else:
            canary = os.path.join(directory, "canary.dxf")
            doc = ezdxf.new("R2000")
            doc.modelspace().add_line((0, 0), (100, 100))
            doc.saveas(canary)
            if librecad_print(directory, "canary", canary):
                librecad_state["ok"] = True
            else:
                notes.append("librecad is installed but cannot print headlessly: LibreCAD cross-check skipped")
    if not librecad_state["ok"]:
        return
    pdf = librecad_print(directory, case, path)
    if pdf is None:
        fail(case, "LibreCAD could not print the file")
        return
    data = open(pdf, "rb").read()
    box = re.search(rb"/MediaBox \[0 0 ([0-9.]+) ([0-9.]+)\]", data)
    if box is None:
        fail(case, "LibreCAD PDF has no MediaBox")
    elif float(box.group(1)) > 20000 or float(box.group(2)) > 20000:
        fail(case, "LibreCAD page is %s x %s pt: paper limits are not in drawing units" % (box.group(1).decode(), box.group(2).decode()))
    if expect["entities"] and expect["extmin"] is not None and max(abs(v) for v in expect["extmin"] + expect["extmax"]) < 1e7 \
            and len(data) < 3000:
        fail(case, "LibreCAD printed an empty page (%d bytes)" % len(data))


# ---------------------------------------------------------------- rendering

def render_png(case, rdoc, out_path):
    if rdoc is None or len(list(rdoc.modelspace())) == 0:
        return
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from ezdxf.addons.drawing import Frontend, RenderContext
        from ezdxf.addons.drawing import config as drawing_config
        from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    except Exception as exc:
        notes.append("rendering skipped (%s)" % exc)
        return
    try:
        fig = plt.figure(figsize=(10, 8), dpi=100)
        ax = fig.add_axes([0, 0, 1, 1])
        cfg = drawing_config.Configuration(background_policy=drawing_config.BackgroundPolicy.WHITE)
        Frontend(RenderContext(rdoc), MatplotlibBackend(ax), config=cfg).draw_layout(rdoc.modelspace(), finalize=True)
        fig.savefig(out_path, dpi=100, facecolor="white")
        plt.close(fig)
    except Exception as exc:
        notes.append("rendering %s failed: %r" % (case, exc))


def main(directory):
    expectations = sorted(glob.glob(os.path.join(directory, "*.expect.json")))
    for expect_path in expectations:
        with open(expect_path) as handle:
            expect = json.load(handle)
        case = expect["case"]
        path = os.path.join(directory, case + ".dxf")
        before = len(failures)
        raw_checks(case, path, expect)
        rdoc = ezdxf_checks(case, path, expect)
        ogr_checks(case, path, expect)
        librecad_checks(case, path, expect, directory)
        render_png(case, rdoc, os.path.join(directory, case + ".png"))
        print("%s  %-24s %d entities" % ("ok  " if len(failures) == before else "FAIL", case, len(expect["entities"])))
    for note in sorted(set(notes)):
        print("note: %s" % note)
    for message in failures:
        print("FAILURE: %s" % message)
    print("ezdxf %s; cases: %d; failures: %d" % (ezdxf.__version__, len(expectations), len(failures)))
    return 1 if failures or not expectations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
"""#

/// Opens the exported files with independent readers (ezdxf, and GDAL and LibreCAD when installed).
///
/// Opt-in, because it starts Python and can take a while: run
/// `NEXAFIX_EXTERNAL_DXF=1 swift test --filter DXFExternalValidationTests` (needs python3 with ezdxf).
/// `NEXAFIX_EXTERNAL_LIBRECAD=1` adds a print of every file through LibreCAD, and `NEXAFIX_DXF_OUT=/some/folder`
/// keeps the files in a new subfolder there; otherwise they live in a fresh temporary folder that is removed.
final class DXFExternalValidationTests: XCTestCase {

    /// A new, empty folder for this run, so nothing that exists already is touched or removed.
    private func makeRunDirectory() throws -> (url: URL, keep: Bool) {
        let environment = ProcessInfo.processInfo.environment
        let keep = !(environment["NEXAFIX_DXF_OUT"] ?? "").isEmpty
        let base = keep ? URL(fileURLWithPath: environment["NEXAFIX_DXF_OUT"] ?? "", isDirectory: true)
                        : URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = base.appendingPathComponent("nexafix-dxf-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw XCTSkip("no writable output directory")
        }
        return (url, keep)
    }

    private func write(_ name: String, plan: PlanDrawing, options: DXFExporter.Options = dxfMappingOptions,
                       expectation: [String: Any]? = nil, to directory: URL) throws {
        let text = DXFExporter.export(plan, options: options)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name + ".dxf"))
        let document = expectation ?? DXFExpectation.document(case: name, plan: plan, options: options)
        let json = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try json.write(to: directory.appendingPathComponent(name + ".expect.json"))
    }

    #if os(macOS) || os(Linux)
    /// Runs python3 with the output going to a log file (a pipe could fill up and stall a chatty child) and stops
    /// the process when it has not finished by `timeout` seconds.
    private func runPython(_ arguments: [String], timeout: TimeInterval, logIn directory: URL) throws
        -> (status: Int32, output: String, timedOut: Bool) {
        let log = directory.appendingPathComponent("python-" + UUID().uuidString + ".log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            process.waitUntilExit()
        }
        try? handle.synchronize()
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (process.terminationStatus, output, timedOut)
    }
    #endif

    func testExportedFilesPassExternalValidation() throws {
        #if os(macOS) || os(Linux)
        guard ProcessInfo.processInfo.environment["NEXAFIX_EXTERNAL_DXF"] == "1" else {
            throw XCTSkip("external DXF validation is opt-in: set NEXAFIX_EXTERNAL_DXF=1 (needs python3 with ezdxf)")
        }
        let run = try makeRunDirectory()
        if !run.keep { addTeardownBlock { try? FileManager.default.removeItem(at: run.url) } }
        let dir = run.url

        func mapping(_ edit: (inout DXFExporter.Options) -> Void = { _ in }) -> DXFExporter.Options {
            var options = dxfMappingOptions
            edit(&options)
            return options
        }

        // The mapping of plan primitives to entities, without the note.
        let sample = DXFFixtures.samplePlan()
        try write("sample_mm", plan: sample, to: dir)
        try write("sample_metres", plan: sample, options: mapping { $0.units = .metres }, to: dir)
        try write("sample_truecolor", plan: sample, options: mapping { $0.colorMode = .trueColor }, to: dir)
        try write("sample_aci_crlf", plan: sample,
                  options: mapping { $0.colorMode = .nearestACI; $0.windowsLineEndings = true }, to: dir)
        try write("sample_geometry_only", plan: sample,
                  options: mapping { $0.includeTextLayers = false; $0.includeFills = false }, to: dir)
        try write("sample_offset_100m", plan: DXFFixtures.samplePlan(origin: Point2(100, 100)), to: dir)
        try write("sample_offset_far", plan: DXFFixtures.samplePlan(origin: Point2(1_000_000, -2_000_000)), to: dir)
        var scaled = DXFFixtures.samplePlan(); scaled.options.scale = 100
        try write("sample_scale_1_100", plan: scaled, to: dir)
        let empty = PlanDrawing(primitives: [], bounds: Bounds2(min: .zero, max: .zero), options: PlanOptions())
        try write("empty", plan: empty, to: dir)
        try write("bulk_3000", plan: dxfBulkPlan(), to: dir)
        let edge = dxfEdgeCasePlan()
        let edgeExpectation: [String: Any] = [
            "case": "edge_cases", "units": 4, "version": "AC1015", "layers": DXFExpectation.layers,
            "entities": edge.expected, "line_length": edge.lineLength,
            "extmin": [-1000.0, -1000.0], "extmax": [6000.0, 6000.0], "dash": [150.0, -75.0],
        ]
        try write("edge_cases", plan: edge.plan, expectation: edgeExpectation, to: dir)

        // Plans from the real builder, with the default options: status colours kept in BYLAYER mode, no group
        // 420 in a release 2000 file, and the provenance note under the plan.
        try write("real_plan_default", plan: dxfRealPlan(), options: DXFExporter.Options(), to: dir)
        try write("real_plan_unmarked", plan: dxfRealPlan(markVerified: false), options: DXFExporter.Options(), to: dir)
        try write("real_plan_truecolor", plan: dxfRealPlan(), options: DXFExporter.Options(colorMode: .trueColor), to: dir)
        try write("real_plan_aci_metres", plan: dxfRealPlan(scale: 100),
                  options: DXFExporter.Options(units: .metres, colorMode: .nearestACI), to: dir)
        // The demo floor exactly as the export engine builds it (caption included), the plan the review reproduced.
        let demo = DemoProperty.make(now: Date(timeIntervalSince1970: 1_700_000_000))
        if let floor = demo.floors.first {
            let drawing = ExportEngine.cadDrawing(for: floor, in: demo, scale: 50, units: .default)
            try write("demo_engine_mm", plan: drawing, options: DXFExporter.Options(units: .millimetres), to: dir)
            try write("demo_engine_metres_true", plan: drawing,
                      options: DXFExporter.Options(units: .metres, colorMode: .trueColor), to: dir)
        }
        try write("sample_note_mm", plan: sample, options: DXFExporter.Options(), to: dir)
        try write("sample_note_text_off", plan: sample, options: DXFExporter.Options(includeTextLayers: false), to: dir)

        let script = dir.appendingPathComponent("validate_dxf.py")
        try Data(dxfValidatorScript.utf8).write(to: script)

        guard let probe = try? runPython(["-c", "import ezdxf"], timeout: 60, logIn: dir), probe.status == 0 else {
            throw XCTSkip("python3 with ezdxf is not available; external DXF validation skipped")
        }
        let result = try runPython([script.path, dir.path], timeout: 600, logIn: dir)
        XCTAssertFalse(result.timedOut, "external validation did not finish in 600 s:\n\(result.output)")
        XCTAssertEqual(result.status, 0, "external validation failed:\n\(result.output)")
        XCTAssertTrue(result.output.contains("failures: 0"), result.output)
        print(result.output)
        #else
        throw XCTSkip("external validation needs a desktop OS (Process)")
        #endif
    }
}
