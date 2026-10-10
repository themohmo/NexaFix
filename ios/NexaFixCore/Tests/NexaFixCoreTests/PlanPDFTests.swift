import XCTest
@testable import NexaFixCore

/// Five-room apartment used by the plan and PDF tests: a living room, a master bedroom, an
/// L-shaped kitchen, a bathroom and a second bedroom with one out-of-square corner. One wall and
/// the master ceiling are laser-verified.
enum PlanPDFFixture {
    static let now = Date(timeIntervalSince1970: 1_791_540_000)   // 2026-10-09 10:00 UTC

    static func demoRooms() -> [Room] {
        var living = Room.rectangle(name: "Living Room", kind: .livingRoom, width: 6.2, depth: 4.5, openings: [
            .door(wall: 0, offset: 0.5),
            .door(wall: 1, offset: 0.5),
            OpeningSpec(wall: 2, kind: .opening, offset: 3.2, width: 1.2, height: 2.4),
            .window(wall: 3, offset: 1.0, width: 2.2, height: 1.5, sill: 0.9),
        ])
        living.walls[0].length.verify(6.21, source: .laser)
        living.objects = [
            RoomObject(kind: .sofa, center: Point2(2.2, 1.0), yaw: 0, width: 2.2, depth: 0.95, height: 0.85),
            RoomObject(kind: .table, center: Point2(3.4, 2.7), yaw: 0.3, width: 1.4, depth: 0.8, height: 0.45),
            RoomObject(kind: .television, center: Point2(2.2, 4.3), yaw: 0, width: 1.4, depth: 0.15, height: 0.8),
        ]

        var master = Room.rectangle(name: "Master Bedroom", kind: .masterBedroom, origin: Point2(6.4, 0),
                                    width: 4.0, depth: 4.5, openings: [
            .door(wall: 3, offset: 3.1),
            .window(wall: 0, offset: 0.8, width: 1.4, height: 1.4, sill: 0.9),
            .window(wall: 1, offset: 1.2, width: 1.6, height: 1.4, sill: 0.9),
            .door(wall: 2, offset: 2.0),
        ])
        master.ceilingHeight.verify(2.78, source: .laser)
        master.objects = [
            RoomObject(kind: .bed, center: Point2(9.0, 2.0), yaw: Double.pi / 2, width: 2.1, depth: 1.8, height: 0.5),
            RoomObject(kind: .storage, center: Point2(7.9, 0.35), yaw: 0, width: 2.4, depth: 0.6, height: 2.4),
        ]

        var kitchen = Room.polygon(name: "Kitchen", kind: .kitchen, corners: [
            Point2(0, 4.7), Point2(4.2, 4.7), Point2(4.2, 6.7), Point2(2.4, 6.7), Point2(2.4, 8.2), Point2(0, 8.2),
        ], openings: [
            OpeningSpec(wall: 0, kind: .opening, offset: 1.8, width: 1.2, height: 2.4),
            .door(wall: 1, offset: 0.6, width: 0.8),
            .window(wall: 5, offset: 1.0, width: 1.2, height: 1.2, sill: 1.0),
        ])
        kitchen.objects = [
            RoomObject(kind: .refrigerator, center: Point2(0.4, 7.8), yaw: 0, width: 0.7, depth: 0.7, height: 1.8),
            RoomObject(kind: .stove, center: Point2(1.4, 7.9), yaw: 0, width: 0.6, depth: 0.6, height: 0.9),
            RoomObject(kind: .sink, center: Point2(2.0, 7.9), yaw: 0, width: 0.8, depth: 0.55, height: 0.9),
        ]

        let bath = Room.rectangle(name: "Bathroom", kind: .bathroom, origin: Point2(4.4, 4.7), width: 2.0, depth: 2.0, openings: [
            .door(wall: 3, offset: 0.6, width: 0.8),
            .window(wall: 2, offset: 0.5, width: 0.6, height: 0.6, sill: 1.2),
        ])

        // Pentagon whose corner P3 is 92.5 degrees (out of square); P4 is 177.5 degrees, a straight corner.
        let l3 = 2.5
        let dx = l3 * cos(267.5 * Double.pi / 180)
        let dy = l3 * sin(267.5 * Double.pi / 180)
        let p3 = Point2(6.6 - dx, 8.2)
        let bedroom2 = Room.polygon(name: "Bedroom 2", kind: .bedroom, corners: [
            Point2(6.6, 4.7), Point2(10.4, 4.7), Point2(10.4, 8.2), p3, p3 + Point2(dx, dy),
        ], openings: [
            .door(wall: 0, offset: 0.9),
            .window(wall: 1, offset: 1.0, width: 1.5, height: 1.4, sill: 0.9),
        ])
        return [living, master, kitchen, bath, bedroom2]
    }

    static func demoProperty(floors: Int = 1) -> Property {
        var list: [Floor] = [Floor(name: "Level 23", level: 23, rooms: demoRooms())]
        if floors > 1 {
            let loft = Room.rectangle(name: "Loft Study", kind: .office, width: 4.1, depth: 3.3,
                                      openings: [.door(wall: 0, offset: 0.4)])
            list.append(Floor(name: "Loft", level: 24, rooms: [loft]))
        }
        return Property(name: "Marina Gate 2304", client: "Mr. Ahmed Al Mansoori",
                        address: "Marina Gate 1, Dubai Marina, Dubai", reference: "NF-2026-1009-01",
                        kind: .apartment, floors: list)
    }
}

// MARK: - PDF inspection helpers

/// A small reader for the PDFs this module writes: enough to check the structure byte by byte
/// and to pull out every string a page shows.
private struct PDFProbe {
    let bytes: [UInt8]
    /// The file as ISO Latin-1, one character per byte, so byte offsets equal string offsets.
    let text: String

    init(_ data: Data) {
        bytes = [UInt8](data)
        text = String(decoding: bytes.map { UInt16($0) }, as: UTF16.self)
    }

    /// Everything wrong with the file's structure; empty when it is sound.
    func problems() -> [String] {
        var issues: [String] = []
        let chars = Array(text.unicodeScalars)
        func slice(_ from: Int, _ count: Int) -> String {
            guard from >= 0, from + count <= chars.count else { return "" }
            return String(String.UnicodeScalarView(chars[from..<from + count]))
        }
        if !text.hasPrefix("%PDF-1.4\n") { issues.append("header") }
        if !text.hasSuffix("%%EOF\n") { issues.append("EOF marker") }

        // startxref points at the xref table.
        guard let sx = text.range(of: "startxref\n", options: .backwards) else { return issues + ["no startxref"] }
        let tail = text[sx.upperBound...]
        guard let offset = Int(tail.prefix(while: { $0 != "\n" })) else { return issues + ["bad startxref"] }
        if slice(offset, 5) != "xref\n" { issues.append("startxref does not point at xref (\(offset))") }

        // The table: "0 N", then N 20-byte entries.
        let afterXref = offset + 5
        let header = String(text[text.index(text.startIndex, offsetBy: afterXref)...].prefix(while: { $0 != "\n" }))
        let parts = header.split(separator: " ")
        guard parts.count == 2, parts[0] == "0", let count = Int(parts[1]) else { return issues + ["xref header \(header)"] }
        let firstEntry = afterXref + header.count + 1
        for i in 0..<count {
            let entry = slice(firstEntry + 20 * i, 20)
            if entry.count != 20 || !entry.hasSuffix(" \n") { issues.append("entry \(i) is not 20 bytes: \(entry.debugDescription)"); continue }
            if i == 0 {
                if entry != "0000000000 65535 f \n" { issues.append("free entry") }
                continue
            }
            guard let at = Int(entry.prefix(10)), entry.dropFirst(10).hasPrefix(" 00000 n") else {
                issues.append("entry \(i) malformed"); continue
            }
            if slice(at, "\(i) 0 obj\n".count) != "\(i) 0 obj\n" { issues.append("object \(i) is not at offset \(at)") }
        }
        // The trailer names the right size and the catalog.
        if !text.contains("trailer\n<< /Size \(count) /Root 1 0 R /Info 5 0 R") { issues.append("trailer") }

        // Every stream's /Length is exact and `endstream` follows the data.
        var search = text.startIndex
        while let r = text.range(of: "<< /Length ", range: search..<text.endIndex) {
            let rest = text[r.upperBound...]
            guard let length = Int(rest.prefix(while: { $0.isNumber })) else { issues.append("length"); break }
            guard let streamStart = text.range(of: ">>\nstream\n", range: r.upperBound..<text.endIndex) else { issues.append("stream"); break }
            let dataStart = text.distance(from: text.startIndex, to: streamStart.upperBound)
            if slice(dataStart + length, 10) != "endstream\n" { issues.append("stream at \(dataStart): /Length \(length) wrong") }
            search = streamStart.upperBound
        }
        return issues
    }

    /// The decoded content stream of each page, in page order.
    var streams: [String] {
        var out: [String] = []
        var search = text.startIndex
        while let start = text.range(of: ">>\nstream\n", range: search..<text.endIndex) {
            guard let end = text.range(of: "endstream\n", range: start.upperBound..<text.endIndex) else { break }
            out.append(String(text[start.upperBound..<end.lowerBound]))
            search = end.upperBound
        }
        return out
    }

    /// Width and height in points of every page's MediaBox, in page order.
    var mediaBoxes: [(Double, Double)] {
        var out: [(Double, Double)] = []
        var search = text.startIndex
        while let r = text.range(of: "/MediaBox [0 0 ", range: search..<text.endIndex) {
            let nums = text[r.upperBound...].prefix(while: { $0 != "]" }).split(separator: " ").compactMap { Double($0) }
            if nums.count == 2 { out.append((nums[0], nums[1])) }
            search = r.upperBound
        }
        return out
    }

    var pageCount: Int { mediaBoxes.count }

    /// Strings shown with `Tj`, decoded from their PDF literal form, as Latin-1 text.
    static func shownStrings(_ stream: String) -> [String] {
        var out: [String] = []
        for line in stream.split(separator: "\n") where line.hasPrefix("(") && line.hasSuffix(") Tj") {
            let body = Array(line.unicodeScalars.dropFirst().dropLast(4))
            var s = ""
            var i = 0
            while i < body.count {
                if body[i] == "\\", i + 1 < body.count {
                    let n = body[i + 1]
                    if n.value >= 0x30 && n.value <= 0x37 {
                        var v = 0
                        var j = i + 1
                        while j < body.count, j < i + 4, body[j].value >= 0x30, body[j].value <= 0x37 { v = v * 8 + Int(body[j].value - 0x30); j += 1 }
                        s.unicodeScalars.append(Unicode.Scalar(UInt8(v)))
                        i = j
                    } else {
                        s.unicodeScalars.append(n)
                        i += 2
                    }
                } else {
                    s.unicodeScalars.append(body[i])
                    i += 1
                }
            }
            out.append(s)
        }
        return out
    }

    func shown(page: Int) -> [String] { PDFProbe.shownStrings(streams[page]) }
}

private func numbersIn(_ line: Substring) -> [Double] {
    line.split(separator: " ").compactMap { Double($0) }
}

/// `x y m` + `x y l` + `S` triples in a content stream: stroked straight segments in points.
private func strokedSegments(_ stream: String) -> [(x0: Double, y0: Double, x1: Double, y1: Double)] {
    let lines = stream.split(separator: "\n")
    var out: [(Double, Double, Double, Double)] = []
    var i = 0
    while i + 2 < lines.count {
        if lines[i].hasSuffix(" m"), lines[i + 1].hasSuffix(" l"), lines[i + 2] == "S" {
            let a = numbersIn(lines[i]), b = numbersIn(lines[i + 1])
            if a.count == 2, b.count == 2 { out.append((a[0], a[1], b[0], b[1])) }
            i += 3
        } else {
            i += 1
        }
    }
    return out
}

private func points(_ mm: Double) -> Double { mm * 72 / 25.4 }

private func render(_ property: Property, _ options: PlanPDFOptions = PlanPDFOptions(),
                    now: Date = PlanPDFFixture.now) -> (probe: PDFProbe, data: Data) {
    let data = PlanPDFRenderer.render(property: property, options: options, now: now)
    return (PDFProbe(data), data)
}

private func property(rooms: [Room], name: String = "Test Property") -> Property {
    Property(name: name, client: "Client", address: "Address", reference: "REF-1",
             floors: [Floor(name: "Level 1", level: 1, rooms: rooms)])
}

// MARK: - Writer tests

final class PDFWriterTests: XCTestCase {

    func testNumberFormattingIsPlainDecimalAndNeverScientific() {
        XCTAssertEqual(PDFSyntax.number(0), "0")
        XCTAssertEqual(PDFSyntax.number(-0.0), "0")
        XCTAssertEqual(PDFSyntax.number(12.5), "12.5")
        XCTAssertEqual(PDFSyntax.number(-3.25), "-3.25")
        XCTAssertEqual(PDFSyntax.number(123.4567), "123.457")
        XCTAssertEqual(PDFSyntax.number(0.0004), "0", "below half a thousandth rounds to zero, with no minus sign")
        XCTAssertEqual(PDFSyntax.number(-0.0004), "0")
        XCTAssertEqual(PDFSyntax.number(0.0005), "0.001")
        XCTAssertEqual(PDFSyntax.number(1e-12), "0")
        XCTAssertEqual(PDFSyntax.number(100), "100")
        XCTAssertEqual(PDFSyntax.number(0.1), "0.1")
        XCTAssertEqual(PDFSyntax.number(2.05), "2.05")
        XCTAssertEqual(PDFSyntax.number(7.001), "7.001")
        XCTAssertEqual(PDFSyntax.number(.nan), "0")
        XCTAssertEqual(PDFSyntax.number(.infinity), "0")
        XCTAssertEqual(PDFSyntax.number(-.infinity), "0")
        XCTAssertEqual(PDFSyntax.number(1e12), "32767", "clamped to the PDF 1.4 real-number limit")
        XCTAssertEqual(PDFSyntax.number(-1e12), "-32767")
        XCTAssertEqual(PDFSyntax.unit(1.5), "1")
        XCTAssertEqual(PDFSyntax.unit(-1), "0")
        XCTAssertEqual(PDFSyntax.unit(.nan), "0")
    }

    func testLiteralStringsEscapeParenthesesBackslashesAndHighBytes() {
        XCTAssertEqual(PDFSyntax.literal(Array("abc".utf8)), "(abc)")
        XCTAssertEqual(PDFSyntax.literal(Array("a(b)c\\d".utf8)), "(a\\(b\\)c\\\\d)")
        XCTAssertEqual(PDFSyntax.literal([0xB0]), "(\\260)", "degree sign as octal")
        XCTAssertEqual(PDFSyntax.literal([0x00, 0x0A, 0x7F, 0xFF]), "(\\000\\012\\177\\377)")
        XCTAssertTrue(PDFSyntax.literal(WinAnsiEncoding.encode("Caf\u{E9} 90\u{00B0} \u{00B1}1 m\u{00B2} (x) \\")).unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F })
    }

    func testWinAnsiEncoding() {
        XCTAssertEqual(WinAnsiEncoding.encode("A z 09"), Array("A z 09".utf8))
        XCTAssertEqual(WinAnsiEncoding.encode("\u{00B0}"), [0xB0], "degree")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{00B1}"), [0xB1], "plus-minus")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{00B2}"), [0xB2], "superscript two")
        XCTAssertEqual(WinAnsiEncoding.encode("m\u{00B2}"), [0x6D, 0xB2])
        XCTAssertEqual(WinAnsiEncoding.encode("\u{00D7}"), [0xD7], "multiplication sign")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{20AC}"), [0x80], "euro")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{2013}\u{2014}"), [0x96, 0x97], "dashes")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{2018}\u{2019}\u{201C}\u{201D}"), [0x91, 0x92, 0x93, 0x94])
        XCTAssertEqual(WinAnsiEncoding.encode("\u{2026}\u{2022}\u{2122}"), [0x85, 0x95, 0x99])
        XCTAssertEqual(WinAnsiEncoding.encode("\u{2212}"), [0x2D], "minus sign becomes a hyphen")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{2192}\u{03A9}\u{0627}"), [0x3F, 0x3F, 0x3F], "unsupported becomes ?")
        XCTAssertEqual(WinAnsiEncoding.encode("\u{1F600}"), [0x3F], "an astral character is one ?")
        XCTAssertEqual(WinAnsiEncoding.encode("e\u{0301}"), [0xE9], "decomposed e + acute is composed first")
        XCTAssertEqual(WinAnsiEncoding.encode("a\tb\nc\rd"), Array("a b c d".utf8), "whitespace controls become spaces")
        XCTAssertEqual(WinAnsiEncoding.encode("a\u{0001}b"), [0x61, 0x3F, 0x62], "other controls become ?")
        XCTAssertEqual(WinAnsiEncoding.encode("a\u{200B}b"), [0x61, 0x62], "zero-width characters are dropped")
        XCTAssertEqual(WinAnsiEncoding.encode(""), [])
    }

    func testHelveticaAdvanceWidthsMatchTheAFM() {
        // Values from the Adobe core-14 AFM files, listed here by hand.
        let regular: [(Character, Int)] = [(" ", 278), ("0", 556), ("9", 556), ("A", 667), ("H", 722), ("M", 833), ("W", 944),
                                           ("i", 222), ("l", 222), ("m", 833), ("e", 556), ("o", 556), ("f", 278), ("t", 278),
                                           ("%", 889), ("'", 191), ("(", 333), ("@", 1015), ("\u{00B0}", 400), ("\u{00B1}", 584),
                                           ("\u{00B2}", 333), ("\u{00D7}", 584), ("\u{00E9}", 556), ("-", 333), (".", 278)]
        for (ch, width) in regular {
            let b = WinAnsiEncoding.encode(String(ch))[0]
            XCTAssertEqual(HelveticaMetrics.advance(ofByte: b, bold: false), width, "Helvetica \(ch)")
        }
        let bold: [(Character, Int)] = [(" ", 278), ("0", 556), ("A", 722), ("H", 722), ("M", 833), ("W", 944), ("i", 278),
                                        ("l", 278), ("m", 889), ("e", 556), ("o", 611), ("'", 238), ("@", 975), ("\u{00B0}", 400)]
        for (ch, width) in bold {
            let b = WinAnsiEncoding.encode(String(ch))[0]
            XCTAssertEqual(HelveticaMetrics.advance(ofByte: b, bold: true), width, "Helvetica-Bold \(ch)")
        }
        XCTAssertEqual(HelveticaMetrics.regularWidths.count, 224)
        XCTAssertEqual(HelveticaMetrics.boldWidths.count, 224)
        XCTAssertEqual(HelveticaMetrics.advance(ofByte: 10, bold: false), 0, "no glyph below 32")
        XCTAssertTrue(HelveticaMetrics.regularWidths.allSatisfy { $0 >= 180 && $0 <= 1100 })
        XCTAssertTrue(HelveticaMetrics.boldWidths.allSatisfy { $0 >= 180 && $0 <= 1100 })
    }

    func testFullAlphabetsAndDigitsMatchTheAFM() {
        let regular: [Character: Int] = [
            "A": 667, "B": 667, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778, "H": 722, "I": 278, "J": 500,
            "K": 667, "L": 556, "M": 833, "N": 722, "O": 778, "P": 667, "Q": 778, "R": 722, "S": 667, "T": 611,
            "U": 722, "V": 667, "W": 944, "X": 667, "Y": 667, "Z": 611,
            "a": 556, "b": 556, "c": 500, "d": 556, "e": 556, "f": 278, "g": 556, "h": 556, "i": 222, "j": 222,
            "k": 500, "l": 222, "m": 833, "n": 556, "o": 556, "p": 556, "q": 556, "r": 333, "s": 500, "t": 278,
            "u": 556, "v": 500, "w": 722, "x": 500, "y": 500, "z": 500,
            "1": 556, "2": 556, "3": 556, "4": 556, "5": 556, "6": 556, "7": 556, "8": 556,
            ":": 278, ";": 278, "/": 278, "+": 584, "=": 584, "<": 584, ">": 584, "?": 556, "#": 556, "$": 556,
            "&": 667, "*": 389, ")": 333, ",": 278, "[": 278, "\\": 278, "]": 278, "^": 469, "_": 556, "`": 333,
            "{": 334, "|": 260, "}": 334, "~": 584, "\"": 355, "!": 278,
        ]
        let bold: [Character: Int] = [
            "A": 722, "B": 722, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778, "H": 722, "I": 278, "J": 556,
            "K": 722, "L": 611, "M": 833, "N": 722, "O": 778, "P": 667, "Q": 778, "R": 722, "S": 667, "T": 611,
            "U": 722, "V": 667, "W": 944, "X": 667, "Y": 667, "Z": 611,
            "a": 556, "b": 611, "c": 556, "d": 611, "e": 556, "f": 333, "g": 611, "h": 611, "i": 278, "j": 278,
            "k": 556, "l": 278, "m": 889, "n": 611, "o": 611, "p": 611, "q": 611, "r": 389, "s": 556, "t": 333,
            "u": 611, "v": 556, "w": 778, "x": 556, "y": 556, "z": 500,
            "1": 556, "5": 556, "9": 556, ":": 333, ";": 333, "?": 611, "&": 722, "!": 333, "\"": 474,
        ]
        for (ch, width) in regular {
            XCTAssertEqual(HelveticaMetrics.advance(ofByte: WinAnsiEncoding.encode(String(ch))[0], bold: false), width, "Helvetica \(ch)")
        }
        for (ch, width) in bold {
            XCTAssertEqual(HelveticaMetrics.advance(ofByte: WinAnsiEncoding.encode(String(ch))[0], bold: true), width, "Helvetica-Bold \(ch)")
        }
        // Whole-table fingerprints (sum and position-weighted sum) taken from the AFM data when the table was
        // generated; any edit to a single entry changes them.
        func fingerprint(_ t: [Int]) -> (Int, Int) { (t.reduce(0, +), t.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element }) }
        XCTAssertEqual(fingerprint(HelveticaMetrics.regularWidths).0, 120_823)
        XCTAssertEqual(fingerprint(HelveticaMetrics.regularWidths).1, 13_843_886)
        XCTAssertEqual(fingerprint(HelveticaMetrics.boldWidths).0, 125_109)
        XCTAssertEqual(fingerprint(HelveticaMetrics.boldWidths).1, 14_313_620)
    }

    func testNonBreakingSpaceKeepsItsByte() {
        XCTAssertEqual(WinAnsiEncoding.encode("a\u{00A0}b"), [0x61, 0xA0, 0x62])
        XCTAssertEqual(HelveticaMetrics.advance(ofByte: 0xA0, bold: false), 278)
    }

    func testStringWidthsAreSummedAndScaledByFontSize() {
        // "Hello": H 722 + e 556 + l 222 + l 222 + o 556 = 2278 units.
        XCTAssertEqual(HelveticaMetrics.width(of: "Hello", fontSize: 10), 22.78, accuracy: 1e-9)
        // Bold: 722 + 556 + 278 + 278 + 611 = 2445.
        XCTAssertEqual(HelveticaMetrics.width(of: "Hello", bold: true, fontSize: 10), 24.45, accuracy: 1e-9)
        // "6200 mm": 4 x 556 + 278 + 2 x 833 = 4168.
        XCTAssertEqual(HelveticaMetrics.width(of: "6200 mm", fontSize: 1000), 4168, accuracy: 1e-9)
        // Character spacing adds per glyph.
        XCTAssertEqual(HelveticaMetrics.width(of: "ab", fontSize: 10, characterSpacing: 2), 5.56 + 5.56 + 4, accuracy: 1e-9)
        XCTAssertEqual(HelveticaMetrics.width(of: "", fontSize: 10), 0)
        // The degree sign counts as one byte of 400 units, not as two bytes of UTF-8.
        XCTAssertEqual(HelveticaMetrics.width(of: "90\u{00B0}", fontSize: 10), (556 + 556 + 400) / 100.0, accuracy: 1e-9)
        XCTAssertEqual(PDFPage.textWidth("Hello", size: 10), 22.78, accuracy: 1e-9)
    }

    func testTruncationAndWrappingNeverExceedTheWidth() {
        let text = "Master Bedroom with Walk-in Wardrobe and Balcony"
        for width in [30.0, 60, 100, 200] {
            let t = HelveticaMetrics.truncated(text, toWidth: width, fontSize: 10)
            XCTAssertLessThanOrEqual(HelveticaMetrics.width(of: t, fontSize: 10), width + 1e-9)
            if width < HelveticaMetrics.width(of: text, fontSize: 10) {
                XCTAssertTrue(t.hasSuffix("..."))
                XCTAssertTrue(text.hasPrefix(String(t.dropLast(3))), "keeps the start of the text")
            }
        }
        XCTAssertEqual(HelveticaMetrics.truncated("short", toWidth: 500, fontSize: 10), "short")
        XCTAssertEqual(HelveticaMetrics.truncated("anything", toWidth: 1, fontSize: 10), "", "not even an ellipsis fits")

        let lines = HelveticaMetrics.wrapped(text, maxWidth: 90, fontSize: 10)
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertEqual(lines.joined(separator: " "), text, "nothing lost")
        for l in lines { XCTAssertLessThanOrEqual(HelveticaMetrics.width(of: l, fontSize: 10), 90 + 1e-9) }
        let longWord = HelveticaMetrics.wrapped("Supercalifragilisticexpialidocious ok", maxWidth: 60, fontSize: 10)
        XCTAssertTrue(longWord.allSatisfy { HelveticaMetrics.width(of: $0, fontSize: 10) <= 60 + 1e-9 })
        XCTAssertEqual(HelveticaMetrics.wrapped("", maxWidth: 60, fontSize: 10), [])
    }

    // MARK: Structure

    private func sampleDocument() -> PDFWriter {
        var writer = PDFWriter(title: "Sample (1)", author: "A. Author", subject: "Subject",
                               creationDate: Date(timeIntervalSince1970: 1_791_540_000))
        for i in 0..<3 {
            var page = PDFPage(widthMM: 210, heightMM: 297)
            page.setStrokeColor(r: 0.1, g: 0.2, b: 0.3)
            page.setLineWidth(0.5)
            page.move(to: 10, 10); page.line(to: 100, 10 + Double(i)); page.stroke()
            page.arc(centerX: 100, centerY: 100, radius: 30, startDegrees: 0, endDegrees: 200); page.stroke()
            page.text("Page \(i + 1) (\u{00B0}) \\ x", x: 50, y: 700, font: .helveticaBold, size: 12)
            writer.addPage(page)
        }
        return writer
    }

    func testFileStructureIsExactlyAsTheXrefTableSays() {
        let data = sampleDocument().data()
        let probe = PDFProbe(data)
        XCTAssertEqual(probe.problems(), [])
        XCTAssertEqual(probe.pageCount, 3)
        XCTAssertEqual(probe.streams.count, 3)
        // Object count: catalog, pages, 2 fonts, info + 2 per page = 11, plus the free entry = 12.
        XCTAssertTrue(probe.text.contains("trailer\n<< /Size 12 /Root 1 0 R"))
        XCTAssertTrue(probe.text.contains("/Type /Pages /Kids [6 0 R 8 0 R 10 0 R] /Count 3"))
        XCTAssertTrue(probe.text.contains("/BaseFont /Helvetica /Encoding /WinAnsiEncoding"))
        XCTAssertTrue(probe.text.contains("/BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding"))
        // The binary comment after the header makes transfer tools treat the file as binary.
        XCTAssertEqual(Array(data[9..<14]), [0x25, 0xE2, 0xE3, 0xCF, 0xD3])
    }

    func testInfoDictionaryAndTrailerIdentifier() {
        let probe = PDFProbe(sampleDocument().data())
        XCTAssertTrue(probe.text.contains("/Title (Sample \\(1\\))"), "title with escaped parentheses")
        XCTAssertTrue(probe.text.contains("/Author (A. Author)"))
        XCTAssertTrue(probe.text.contains("/Producer (NexaFix Scan)"))
        XCTAssertTrue(probe.text.contains("/Creator (NexaFix Scan)"))
        XCTAssertTrue(probe.text.contains("/CreationDate (D:20261009100000Z)"), "2026-10-09 10:00:00 UTC")
        // /ID is two identical 32-hex-digit strings.
        let range = probe.text.range(of: "/ID [<")!
        let id = probe.text[range.upperBound...].prefix(32)
        XCTAssertEqual(id.count, 32)
        XCTAssertTrue(id.allSatisfy { $0.isHexDigit })
        XCTAssertTrue(probe.text.contains("/ID [<\(id)> <\(id)>]"))
    }

    func testOutputIsDeterministicAndFollowsTheInjectedDate() {
        XCTAssertEqual(sampleDocument().data(), sampleDocument().data())
        var other = sampleDocument()
        other.creationDate = Date(timeIntervalSince1970: 0)
        let probe = PDFProbe(other.data())
        XCTAssertTrue(probe.text.contains("/CreationDate (D:19700101000000Z)"))
        XCTAssertNotEqual(other.data(), sampleDocument().data())
        XCTAssertEqual(probe.problems(), [])
    }

    func testUnicodeInfoStringsUseUTF16() {
        let writer = PDFWriter(title: "Villa \u{0645}", creationDate: Date(timeIntervalSince1970: 0))
        let text = PDFProbe(writer.data()).text
        // "Villa " then U+0645, as UTF-16BE with a byte-order mark.
        XCTAssertTrue(text.contains("/Title <FEFF00560069006C006C006100200645>"))
    }

    func testDocumentWithoutPagesGetsOneBlankA4Page() {
        let probe = PDFProbe(PDFWriter(title: "Empty", creationDate: Date(timeIntervalSince1970: 0)).data())
        XCTAssertEqual(probe.problems(), [])
        XCTAssertEqual(probe.pageCount, 1)
        XCTAssertEqual(probe.mediaBoxes[0].0, 595.276, accuracy: 0.001)
        XCTAssertEqual(probe.mediaBoxes[0].1, 841.89, accuracy: 0.001)
    }

    func testUnbalancedSaveIsClosedAndExtraRestoreIgnored() {
        var page = PDFPage(width: 100, height: 100)
        page.restore()                       // nothing to restore: ignored
        page.save(); page.save()
        XCTAssertEqual(page.saveDepth, 2)
        var writer = PDFWriter(title: "t", creationDate: Date(timeIntervalSince1970: 0))
        writer.addPage(page)
        let probe = PDFProbe(writer.data())
        XCTAssertEqual(probe.streams[0], "q\nq\nQ\nQ\n")
        XCTAssertEqual(probe.problems(), [])
    }

    func testPageSizeInMillimetresConvertsToPoints() {
        let page = PDFPage(widthMM: 210, heightMM: 297)
        XCTAssertEqual(page.width, 595.276, accuracy: 0.001)
        XCTAssertEqual(page.height, 841.890, accuracy: 0.001)
        XCTAssertEqual(PDFUnits.mm(25.4), 72, accuracy: 1e-12)
        XCTAssertEqual(PDFUnits.millimetres(72), 25.4, accuracy: 1e-12)
        let bad = PDFPage(width: .nan, height: -4)
        XCTAssertGreaterThan(bad.width, 0)
        XCTAssertGreaterThan(bad.height, 0)
    }

    // MARK: Operators

    func testGraphicsOperators() {
        var page = PDFPage(width: 200, height: 200)
        page.setStrokeColor(r: 1, g: 0.5, b: 0)
        page.setFillColor(r: 0, g: 0.25, b: 1)
        page.setLineWidth(1.4173)
        page.setLineCap(.round); page.setLineJoin(.bevel); page.setMiterLimit(4)
        page.setDash([6.2362, 3.1181]); page.setDash([])
        page.rect(x: 1, y: 2, width: 3, height: 4); page.fillAndStroke()
        page.move(to: 0, 0); page.line(to: 5, 5); page.closePath(); page.closeAndStroke()
        page.fill(); page.fill(evenOdd: true); page.stroke(); page.endPath(); page.clip()
        XCTAssertEqual(page.content, """
        1 0.5 0 RG
        0 0.25 1 rg
        1.417 w
        1 J
        2 j
        4 M
        [6.236 3.118] 0 d
        [] 0 d
        1 2 3 4 re
        B
        0 0 m
        5 5 l
        h
        s
        f
        f*
        S
        n
        W n

        """)
    }

    func testDashPatternRejectsNonsense() {
        var page = PDFPage(width: 10, height: 10)
        page.setDash([.nan, -1, 0])
        page.setDash([0, 0])
        XCTAssertEqual(page.content, "[] 0 d\n[] 0 d\n")
    }

    func testNonFiniteInputNeverReachesTheStream() {
        var page = PDFPage(width: 100, height: 100)
        page.move(to: .nan, .infinity); page.line(to: -.infinity, 3)
        page.setLineWidth(.nan)
        page.setStrokeColor(r: .nan, g: 2, b: -1)
        page.arc(centerX: .nan, centerY: 0, radius: 5, startDegrees: 0, endDegrees: 90)
        page.arc(centerX: 0, centerY: 0, radius: .infinity, startDegrees: 0, endDegrees: 90)
        page.text("x", x: .nan, y: 0, size: 10)
        page.text("x", x: 0, y: 0, size: .nan)
        page.text("x", x: 0, y: 0, size: 10, rotationDegrees: .nan)
        XCTAssertFalse(page.content.contains("nan"))
        XCTAssertFalse(page.content.contains("inf"))
        XCTAssertFalse(page.content.lowercased().contains("e+"))
        XCTAssertTrue(page.content.contains("1 0 0 1 0 0 Tm"), "NaN rotation is treated as 0")
    }

    func testTextOperators() {
        var page = PDFPage(width: 200, height: 200)
        page.text("Hi (1)", x: 10, y: 20, font: .helvetica, size: 12)
        page.text("90\u{00B0}", x: 30, y: 40, font: .helveticaBold, size: 8.5, rotationDegrees: 90)
        page.text("W", x: 1, y: 2, size: 5, characterSpacing: 3)
        page.text("", x: 1, y: 2, size: 5)
        XCTAssertEqual(page.content, """
        BT
        /F1 12 Tf
        1 0 0 1 10 20 Tm
        (Hi \\(1\\)) Tj
        ET
        BT
        /F2 8.5 Tf
        0 1 -1 0 30 40 Tm
        (90\\260) Tj
        ET
        BT
        /F1 5 Tf
        1 0 0 1 1 2 Tm
        3 Tc
        (W) Tj
        0 Tc
        ET

        """)
        var rotated = PDFPage(width: 10, height: 10)
        rotated.text("a", x: 0, y: 0, size: 10, rotationDegrees: 30)
        XCTAssertTrue(rotated.content.contains("0.866 0.5 -0.5 0.866 0 0 Tm"), "cos 30, sin 30")
    }

    /// Parse the cubic segments of a path: (c1, c2, end) triples.
    private func beziers(_ content: String) -> [(Point2, Point2, Point2)] {
        content.split(separator: "\n").compactMap { line in
            guard line.hasSuffix(" c") else { return nil }
            let n = numbersIn(line)
            return n.count == 6 ? (Point2(n[0], n[1]), Point2(n[2], n[3]), Point2(n[4], n[5])) : nil
        }
    }

    func testArcsAreCubicBeziersWithTinyRadialError() {
        var page = PDFPage(width: 400, height: 400)
        page.arc(centerX: 200, centerY: 150, radius: 100, startDegrees: 0, endDegrees: 90)
        XCTAssertTrue(page.content.hasPrefix("300 150 m\n"), "starts on the circle at angle 0")
        let segs = beziers(page.content)
        XCTAssertEqual(segs.count, 1)
        // Control points of a quarter circle: k = 4/3 tan(pi/8) = 0.5523 of the radius from each end.
        XCTAssertEqual(segs[0].0.x, 300, accuracy: 1e-3); XCTAssertEqual(segs[0].0.y, 150 + 55.228, accuracy: 1e-3)
        XCTAssertEqual(segs[0].1.x, 200 + 55.228, accuracy: 1e-3); XCTAssertEqual(segs[0].1.y, 250, accuracy: 1e-3)
        XCTAssertEqual(segs[0].2.x, 200, accuracy: 1e-3); XCTAssertEqual(segs[0].2.y, 250, accuracy: 1e-3)
        // Bezier midpoint (t = 0.5) is (p0 + 3 c1 + 3 c2 + p3) / 8; it should sit on the circle.
        let p0 = Point2(300, 150)
        let mid = (p0 + segs[0].0 * 3 + segs[0].1 * 3 + segs[0].2) / 8
        XCTAssertEqual(mid.distance(to: Point2(200, 150)), 100, accuracy: 0.03, "error below 0.03 % of the radius")
        XCTAssertEqual(mid.x, 200 + 100 * cos(Double.pi / 4), accuracy: 0.03)
    }

    func testArcSweepsSplitIntoNinetyDegreeSegmentsAndWrapAround() {
        func segments(_ start: Double, _ end: Double) -> [(Point2, Point2, Point2)] {
            var page = PDFPage(width: 100, height: 100)
            page.arc(centerX: 0, centerY: 0, radius: 10, startDegrees: start, endDegrees: end)
            return beziers(page.content)
        }
        XCTAssertEqual(segments(0, 45).count, 1)
        XCTAssertEqual(segments(0, 90).count, 1)
        XCTAssertEqual(segments(0, 91).count, 2)
        XCTAssertEqual(segments(0, 180).count, 2)
        XCTAssertEqual(segments(0, 270).count, 3)
        XCTAssertEqual(segments(0, 360).count, 4)
        XCTAssertEqual(segments(0, 720).count, 4, "clamped to one full circle")
        // Wrap: from 350 to 10 degrees is a 20 degree counter-clockwise arc, one segment ending at angle 10.
        let wrap = segments(350, 10)
        XCTAssertEqual(wrap.count, 1)
        XCTAssertEqual(wrap[0].2.x, 10 * cos(10 * Double.pi / 180), accuracy: 1e-3)
        XCTAssertEqual(wrap[0].2.y, 10 * sin(10 * Double.pi / 180), accuracy: 1e-3)
        // A negative end angle wraps too: from 90 to -90 is 180 degrees counter-clockwise (through 180).
        let half = segments(90, -90)
        XCTAssertEqual(half.count, 2)
        XCTAssertEqual(half[0].2.x, -10, accuracy: 1e-3, "passes through 180 degrees")
        XCTAssertEqual(half[1].2.y, -10, accuracy: 1e-3)
        // Every segment end of a full circle is on the circle.
        for s in segments(0, 360) { XCTAssertEqual(s.2.length, 10, accuracy: 1e-3) }
        // A zero sweep just positions the pen; a bad radius draws nothing.
        var none = PDFPage(width: 10, height: 10)
        none.arc(centerX: 0, centerY: 0, radius: 0, startDegrees: 0, endDegrees: 90)
        none.arc(centerX: 0, centerY: 0, radius: -3, startDegrees: 0, endDegrees: 90)
        XCTAssertEqual(none.content, "")
    }

    func testArcWithAHugeAngleFinishesAndMatchesTheReducedArc() {
        // `while sweep < 0 { sweep += 360 }` needed ~3e14 turns for these and never came back.
        var huge = PDFPage(width: 100, height: 100)
        huge.arc(centerX: 10, centerY: 10, radius: 5, startDegrees: 1e17, endDegrees: 0)
        // 1e17 is exactly representable and leaves remainder 280 on division by 360 (10^n mod 360 = 280 for n >= 3),
        // so this is the arc from 280 to 360 degrees.
        var reduced = PDFPage(width: 100, height: 100)
        reduced.arc(centerX: 10, centerY: 10, radius: 5, startDegrees: 280, endDegrees: 360)
        XCTAssertEqual(huge.content, reduced.content)
        XCTAssertEqual(beziers(huge.content).count, 1, "an 80 degree sweep is one segment")

        // Any magnitude, either sign: finishes, only finite numbers, at most a full circle of four segments.
        for (start, end) in [(1e300, 0.0), (0.0, 1e300), (-1e300, 1e300), (1e300, -1e300), (-1e17, 0.0), (0.0, -1e17),
                             (1e308, -1e308), (-1e308, 1e308), (1e17, 1e17), (123.0, 123.0 - 720)] {
            var page = PDFPage(width: 100, height: 100)
            page.arc(centerX: 10, centerY: 10, radius: 5, startDegrees: start, endDegrees: end)
            XCTAssertFalse(page.content.contains("nan") || page.content.contains("inf"), "\(start) -> \(end)")
            XCTAssertLessThanOrEqual(beziers(page.content).count, 4, "\(start) -> \(end)")
        }
        // Whole turns behave as before: a sweep of 360 or more is a full circle, a negative multiple of 360 is none.
        var full = PDFPage(width: 100, height: 100)
        full.arc(centerX: 0, centerY: 0, radius: 5, startDegrees: 10, endDegrees: 1e9)
        XCTAssertEqual(beziers(full.content).count, 4)
        var none = PDFPage(width: 100, height: 100)
        none.arc(centerX: 0, centerY: 0, radius: 5, startDegrees: 360, endDegrees: 0)
        XCTAssertEqual(beziers(none.content).count, 0, "a sweep of -360 degrees is empty, as it always was")
    }

    func testTruncationMatchesTheSimpleMethodAndStaysFastOnVeryLongText() {
        // The straightforward method: drop a character at a time (and the spaces before the ellipsis) until it fits.
        func reference(_ text: String, _ maxWidth: Double, bold: Bool, size: Double) -> String {
            if HelveticaMetrics.width(of: text, bold: bold, fontSize: size) <= maxWidth { return text }
            if HelveticaMetrics.width(of: "...", bold: bold, fontSize: size) > maxWidth { return "" }
            var chars = Array(text)
            while !chars.isEmpty {
                chars.removeLast()
                while let last = chars.last, last == " " { chars.removeLast() }
                let candidate = String(chars) + "..."
                if HelveticaMetrics.width(of: candidate, bold: bold, fontSize: size) <= maxWidth { return candidate }
            }
            return "..."
        }
        var rng = LCG(state: 5)
        let alphabet = Array("abcdefghij KLMNOP 0123456789 .-mw")
        for _ in 0..<300 {
            let length = Int(rng.range(0, 40))
            let text = String((0..<length).map { _ in alphabet[Int(rng.range(0, Double(alphabet.count)))] })
            let width = rng.range(0, 260)
            let bold = rng.next() < 0.5
            XCTAssertEqual(HelveticaMetrics.truncated(text, toWidth: width, bold: bold, fontSize: 8),
                           reference(text, width, bold: bold, size: 8), "\(text.debugDescription) in \(width)")
        }
        // A 20,000-character name: seconds with the old loop became minutes for several such fields.
        let long = String(repeating: "Villa Marina Tower ", count: 1000)
        let start = Date()
        let cut = HelveticaMetrics.truncated(long, toWidth: 150, fontSize: 9)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
        XCTAssertTrue(cut.hasSuffix("..."))
        XCTAssertLessThanOrEqual(HelveticaMetrics.width(of: cut, fontSize: 9), 150)
        XCTAssertTrue(long.hasPrefix(String(cut.dropLast(3))))
    }

    func testCharactersThePDFCannotPrintAreReported() {
        XCTAssertEqual(WinAnsiEncoding.unencodableCharacters(in: "Maid's Room (2) \u{B0} \u{20AC} Caf\u{E9} \u{FC}"), [])
        XCTAssertEqual(WinAnsiEncoding.unencodableCharacters(in: "e\u{0301} a\u{0301}"), [], "composes to Latin-1 letters")
        XCTAssertEqual(WinAnsiEncoding.unencodableCharacters(in: "a\u{200B}b\u{FEFF}"), [], "dropped, nothing visible is lost")
        XCTAssertEqual(String(WinAnsiEncoding.unencodableCharacters(in: "\u{0641}\u{064A}\u{0644}\u{0627}")), "\u{0641}\u{064A}\u{0644}\u{0627}",
                       "Arabic letters, in order")
        XCTAssertEqual(WinAnsiEncoding.unencodableCharacters(in: "Villa \u{4F60}\u{597D} \u{1F600} \u{3A9}").count, 4)
        XCTAssertEqual(WinAnsiEncoding.unencodableCharacters(in: "x\u{0301}").count, 1, "a letter with an accent the encoding lacks")
        // It agrees with `encode`: a text without a literal "?" has a "?" in its bytes exactly when something is reported.
        for text in ["plain", "Caf\u{E9}", "\u{0627}\u{0644}", "mixed \u{0627} text", "\u{1F600}", "tab\there", "\u{2212}5"] {
            let reported = !WinAnsiEncoding.unencodableCharacters(in: text).isEmpty
            XCTAssertEqual(reported, WinAnsiEncoding.encode(text).contains(0x3F), text)
        }
    }

    func testCircleIsFourSegmentsAndClosed() {
        var page = PDFPage(width: 100, height: 100)
        page.circle(centerX: 50, centerY: 50, radius: 10)
        XCTAssertEqual(beziers(page.content).count, 4)
        XCTAssertTrue(page.content.hasSuffix("h\n"))
    }

    func testPDFDateFormattingAcrossCalendarEdges() {
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: 0)), "D:19700101000000Z")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: 951_782_400)), "D:20000229000000Z", "2000 is a leap year")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: 1_709_164_800 + 86_399)), "D:20240229235959Z")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: 4_107_542_400)), "D:21000301000000Z", "2100 is not a leap year")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: -1)), "D:19691231235959Z")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: 1_791_540_000)), "D:20261009100000Z")
        XCTAssertEqual(PDFSyntax.date(Date(timeIntervalSince1970: .nan)), "D:19700101000000Z")
        let c = PDFCivilDate(unixSeconds: 1_791_540_000 + 43_199, offsetSeconds: 4 * 3600)   // 2026-10-09 21:59:59 UTC
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 10, 10, 1, 59, 59])
    }

    func testFileIdentifierDependsOnContent() {
        XCTAssertEqual(PDFWriter.fileIdentifier(of: [1, 2, 3]), PDFWriter.fileIdentifier(of: [1, 2, 3]))
        XCTAssertNotEqual(PDFWriter.fileIdentifier(of: [1, 2, 3]), PDFWriter.fileIdentifier(of: [1, 2, 4]))
        XCTAssertEqual(PDFWriter.fileIdentifier(of: []).count, 32)
    }
}


// MARK: - Renderer tests

private func rectRoom(_ w: Double, _ d: Double, name: String = "Room") -> Room {
    Room.rectangle(name: name, kind: .other, width: w, depth: d)
}

private func contains(_ haystack: [String], sequence needle: [String]) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    for i in 0...(haystack.count - needle.count) where Array(haystack[i..<i + needle.count]) == needle { return true }
    return false
}

final class PlanPDFTests: XCTestCase {

    // MARK: Pages

    func testPageCountsMatchTheFloorsAndTheScheduleSwitch() {
        let one = render(PlanPDFFixture.demoProperty()).probe
        XCTAssertEqual(one.problems(), [])
        XCTAssertEqual(one.pageCount, 2, "one floor + schedule")
        XCTAssertEqual(render(PlanPDFFixture.demoProperty(floors: 2)).probe.pageCount, 3)
        XCTAssertEqual(render(PlanPDFFixture.demoProperty(), PlanPDFOptions(includeSchedule: false)).probe.pageCount, 1)

        let infos = PlanPDFRenderer.pageInfos(property: PlanPDFFixture.demoProperty(floors: 2), options: PlanPDFOptions())
        XCTAssertEqual(infos.map(\.kind), [.plan, .plan, .schedule])
        XCTAssertEqual(infos.map(\.title), ["Level 23", "Loft", "Room schedule"])
        XCTAssertEqual(infos.last?.scale, nil)
        XCTAssertEqual(infos.last?.scaleLabel, "NTS")
    }

    func testAPropertyWithNoFloorsStillGivesAValidDocument() {
        let empty = Property(name: "Empty")
        let withSchedule = render(empty)
        XCTAssertEqual(withSchedule.probe.problems(), [])
        XCTAssertEqual(withSchedule.probe.pageCount, 2)
        XCTAssertTrue(withSchedule.probe.shown(page: 0).contains("No floors have been scanned yet."))
        XCTAssertTrue(withSchedule.probe.shown(page: 1).contains("No rooms have been scanned yet."))
        let planOnly = render(empty, PlanPDFOptions(includeSchedule: false))
        XCTAssertEqual(planOnly.probe.pageCount, 1)
        XCTAssertEqual(planOnly.probe.problems(), [])
        XCTAssertTrue(planOnly.probe.text.contains("/Title (Empty - floor plans)"))
        XCTAssertTrue(render(Property(name: "")).probe.text.contains("/Title (NexaFix site survey)"))
    }

    func testAFloorWithoutRoomsShowsAMessageInsteadOfAnEmptySheet() {
        let p = Property(name: "P", floors: [Floor(name: "Roof", rooms: [])])
        let r = render(p, PlanPDFOptions(includeSchedule: false))
        XCTAssertEqual(r.probe.problems(), [])
        let shown = r.probe.shown(page: 0)
        XCTAssertTrue(shown.contains("No rooms have been scanned on this floor."))
        XCTAssertTrue(shown.contains("Roof"))
        XCTAssertTrue(shown.contains(ScanAccuracy.joineryDisclaimer), "the disclaimer is on every page, even empty ones")
    }

    func testPageSizesFollowPaperAndOrientation() {
        let property = PlanPDFFixture.demoProperty()
        let sizes: [(PDFPaper, Double, Double)] = [(.a4, 210, 297), (.a3, 297, 420)]
        for (paper, short, long) in sizes {
            let landscape = render(property, PlanPDFOptions(paper: paper, orientation: .landscape)).probe.mediaBoxes
            let portrait = render(property, PlanPDFOptions(paper: paper, orientation: .portrait)).probe.mediaBoxes
            XCTAssertEqual(landscape.count, 2)
            for box in landscape {
                XCTAssertEqual(box.0, points(long), accuracy: 0.001); XCTAssertEqual(box.1, points(short), accuracy: 0.001)
            }
            for box in portrait {
                XCTAssertEqual(box.0, points(short), accuracy: 0.001); XCTAssertEqual(box.1, points(long), accuracy: 0.001)
            }
        }
        // Known absolute sizes: A4 is 595.276 x 841.89 pt, A3 is 841.89 x 1190.551 pt.
        XCTAssertEqual(render(property, PlanPDFOptions(paper: .a4, orientation: .portrait)).probe.mediaBoxes[0].1, 841.89, accuracy: 0.001)
        XCTAssertEqual(render(property, PlanPDFOptions(paper: .a3, orientation: .landscape)).probe.mediaBoxes[0].0, 1190.551, accuracy: 0.001)
        // Auto: the schedule is portrait.
        let auto = PlanPDFRenderer.pageInfos(property: property, options: PlanPDFOptions())
        XCTAssertFalse(auto.last!.isLandscape)
        XCTAssertEqual(auto.last!.widthMM, 297); XCTAssertEqual(auto.last!.heightMM, 420)
    }

    // MARK: Scale and orientation

    private func scale(of rooms: [Room], _ options: PlanPDFOptions) -> Double? {
        PlanPDFRenderer.pageInfos(property: property(rooms: rooms), options: options)[0].scale
    }

    func testAutoScalePicksTheLargestStandardScaleThatFits() {
        // A3 landscape: sheet 420 x 297, frame 10 mm in from each edge (400 x 277), title block 34 mm,
        // plan area inset 6 left/right/bottom and 11 top: 388 x 226 mm available.
        let a3 = PlanPDFOptions(paper: .a3, orientation: .landscape)
        // 12 x 8 m room, 12.24 x 8.24 m with the walls. 1:25 needs 489.6 mm (too wide);
        // 1:50 needs 244.8 x 164.8 mm and fits.
        XCTAssertEqual(scale(of: [rectRoom(12, 8)], a3), 50)
        // 3 x 2.5 m fits even at 1:20 (162 x 137 mm).
        XCTAssertEqual(scale(of: [rectRoom(3, 2.5)], a3), 20)
        // 7 x 5: 1:25 -> 289.6 x 209.6 fits; 1:20 -> 362 x 262 does not (height).
        XCTAssertEqual(scale(of: [rectRoom(7, 5)], a3), 25)
        // 40 x 20 m: 1:150 -> 268.8 x 135 fits, 1:100 -> 403 mm does not.
        XCTAssertEqual(scale(of: [rectRoom(40, 20)], a3), 150)
        // 60 x 30 m: 1:200 -> 301 x 151 fits; 1:150 -> 401 mm does not.
        XCTAssertEqual(scale(of: [rectRoom(60, 30)], a3), 200)
        // 90 x 45 m: 1:250 -> 361 x 181 fits; 1:200 -> 451 does not.
        XCTAssertEqual(scale(of: [rectRoom(90, 45)], a3), 250)
        // 150 x 60 m: 1:500 -> 300 x 120.
        XCTAssertEqual(scale(of: [rectRoom(150, 60)], a3), 500)
        // Beyond 1:500 the renderer keeps going rather than clip: 200 x 100 m needs 1:750 (267 mm).
        XCTAssertEqual(scale(of: [rectRoom(200, 100)], a3), 750)
        // A4 landscape plan area is 265 x 139 mm: 12 x 8 m needs 1:75 (163 x 110).
        XCTAssertEqual(scale(of: [rectRoom(12, 8)], PlanPDFOptions(paper: .a4, orientation: .landscape)), 75)
    }

    func testRoomsThatCannotBeDrawnDoNotInfluenceTheScale() {
        // The undrawable room (a NaN corner) has a finite corner 5 km away; it must not shrink the plan.
        let bad = Room.polygon(name: "Bad", corners: [Point2(0, 0), Point2(5000, 5000), Point2(.nan, 1)])
        let infos = PlanPDFRenderer.pageInfos(property: property(rooms: [bad, rectRoom(12, 8)]),
                                              options: PlanPDFOptions(paper: .a3, orientation: .landscape))
        XCTAssertEqual(infos[0].scale, 50)
    }

    func testAutoScaleOnlyEverReturnsStandardScales() {
        var rng = LCG(state: 42)
        for _ in 0..<25 {
            let w = rng.range(2, 60), d = rng.range(2, 40)
            let s = scale(of: [rectRoom(w, d)], PlanPDFOptions())!
            XCTAssertTrue(PlanPDFRenderer.standardScales.contains(s) || PlanPDFRenderer.fallbackScales.contains(s), "1:\(s)")
        }
    }

    func testChosenScaleIsTheLargestThatFitsByIndependentCheck() {
        // For random rooms, the drawing built at the chosen scale fits the 388 x 226 mm area (A3 landscape)
        // and the next larger standard scale does not.
        var rng = LCG(state: 7)
        let candidates = PlanPDFRenderer.standardScales
        for _ in 0..<12 {
            let room = rectRoom(rng.range(3, 45), rng.range(3, 30))
            guard let chosen = scale(of: [room], PlanPDFOptions(paper: .a3, orientation: .landscape)), let index = candidates.firstIndex(of: chosen) else { continue }
            func fits(_ scale: Double) -> Bool {
                let d = PlanDrawingBuilder.build(rooms: [room], title: "", subtitle: "",
                                                 options: PlanPDFRenderer.planOptions(scale: scale, from: PlanPDFOptions()))
                return d.bounds.width * 1000 / scale <= 388 + 1e-6 && d.bounds.height * 1000 / scale <= 226 + 1e-6
            }
            XCTAssertTrue(fits(chosen), "1:\(chosen) fits")
            if index > 0 { XCTAssertFalse(fits(candidates[index - 1]), "1:\(candidates[index - 1]) does not") }
        }
    }

    func testAutoOrientationPicksTheSheetThatAllowsTheLargerScale() {
        // 4 x 12 m room (4.24 x 12.24 with walls). Landscape plan area is 388 x 226: 1:50 needs 245 mm of height,
        // so 1:75. Portrait plan area is 265 x 349: 1:50 fits (84.8 x 244.8).
        let tall = [rectRoom(4, 12)]
        let landscape = PlanPDFRenderer.pageInfos(property: property(rooms: tall), options: PlanPDFOptions(paper: .a3, orientation: .landscape))[0]
        XCTAssertEqual(landscape.scale, 75)
        let auto = PlanPDFRenderer.pageInfos(property: property(rooms: tall), options: PlanPDFOptions(paper: .a3))[0]
        XCTAssertEqual(auto.scale, 50)
        XCTAssertFalse(auto.isLandscape)
        // The mirror image goes landscape.
        let wide = PlanPDFRenderer.pageInfos(property: property(rooms: [rectRoom(12, 4)]), options: PlanPDFOptions(paper: .a3))[0]
        XCTAssertEqual(wide.scale, 50)
        XCTAssertTrue(wide.isLandscape)
        // Tie on scale: the sheet the plan fills more of wins. 12 x 8 on A4 is 1:75 either way; landscape is fuller.
        let tie = PlanPDFRenderer.pageInfos(property: property(rooms: [rectRoom(12, 8)]), options: PlanPDFOptions(paper: .a4))[0]
        XCTAssertEqual(tie.scale, 75)
        XCTAssertTrue(tie.isLandscape)
        // Forced portrait is honoured even when landscape would be bigger.
        let forced = PlanPDFRenderer.pageInfos(property: property(rooms: [rectRoom(12, 4)]), options: PlanPDFOptions(paper: .a3, orientation: .portrait))[0]
        XCTAssertFalse(forced.isLandscape)
    }

    func testFixedScaleIsUsedWhenItFitsAndStepsDownWhenItDoesNot() {
        let room = [rectRoom(12, 8)]
        func fixed(_ s: PlanPDFScale) -> Double? { scale(of: room, PlanPDFOptions(paper: .a3, orientation: .landscape, scale: s)) }
        XCTAssertEqual(fixed(.fixed(100)), 100, "fits, so exactly what was asked for (not the larger 1:50)")
        XCTAssertEqual(fixed(.fixed(50)), 50)
        XCTAssertEqual(fixed(.fixed(20)), 50, "1:20 and 1:25 are too big: next standard scale that fits")
        XCTAssertEqual(fixed(.fixed(33)), 50, "non-standard scale that does not fit: next standard scale")
        XCTAssertEqual(fixed(.fixed(60)), 60, "a non-standard scale that fits is kept")
        XCTAssertEqual(fixed(.fixed(0)), 50, "nonsense falls back to auto")
        XCTAssertEqual(fixed(.fixed(-4)), 50)
        XCTAssertEqual(fixed(.fixed(.nan)), 50)
        XCTAssertEqual(fixed(.auto), 50)
        // Never a larger drawing than requested.
        for s in [20.0, 25, 33, 50, 75, 100] { XCTAssertGreaterThanOrEqual(fixed(.fixed(s))!, s) }
    }

    func testScaleLabelsAndPageInfoText() {
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(50), "1:50")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(750), "1:750")
        XCTAssertEqual(PlanPDFRenderer.standardScales, [20, 25, 50, 75, 100, 150, 200, 250, 500])
        let info = PlanPDFRenderer.pageInfos(property: PlanPDFFixture.demoProperty(), options: PlanPDFOptions())[0]
        XCTAssertEqual(info.scaleLabel, "1:50")
        XCTAssertEqual(info.paper, .a3)
        XCTAssertTrue(info.isLandscape)
    }

    // MARK: Title block, legend, disclaimer

    func testEveryPageHasTheTitleBlockLegendAndTheDisclaimer() {
        let r = render(PlanPDFFixture.demoProperty(floors: 2))
        XCTAssertEqual(r.probe.problems(), [])
        for page in 0..<r.probe.pageCount {
            let shown = r.probe.shown(page: page)
            XCTAssertTrue(shown.contains(ScanAccuracy.joineryDisclaimer), "page \(page + 1): disclaimer in one piece")
            for needle in ["NEXAFIX", "SITE SURVEY", "Marina Gate 2304", "Mr. Ahmed Al Mansoori", "NF-2026-1009-01",
                           "Marina Gate 1, Dubai Marina, Dubai", "9 Oct 2026", "PROPERTY", "CLIENT", "REFERENCE", "DATE", "SCALE",
                           "v = verified on site", "red angle = out of square", "dashed = open boundary",
                           "Sheet \(page + 1) of 3"] {
                XCTAssertTrue(shown.contains(needle), "page \(page + 1) lacks \(needle)")
            }
        }
        // Per-page specifics.
        XCTAssertTrue(r.probe.shown(page: 0).contains("Level 23"))
        XCTAssertTrue(r.probe.shown(page: 0).contains("FLOOR"))
        XCTAssertTrue(r.probe.shown(page: 1).contains("Loft"))
        XCTAssertTrue(r.probe.shown(page: 2).contains("Room schedule"))
        XCTAssertTrue(r.probe.shown(page: 2).contains("SHEET"))
        XCTAssertTrue(r.probe.shown(page: 2).contains("NTS"))
        XCTAssertTrue(r.probe.shown(page: 0).contains("1:50"))
        XCTAssertTrue(r.probe.shown(page: 0).contains("A3 landscape"))
        XCTAssertTrue(r.probe.shown(page: 2).contains("A3 portrait"))
    }

    func testDisclaimerFitsOnOneLineOnEverySheet() {
        for paper in PDFPaper.allCases {
            for orientation in [PDFOrientation.portrait, .landscape] {
                let r = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(paper: paper, orientation: orientation))
                for page in 0..<r.probe.pageCount {
                    XCTAssertTrue(r.probe.shown(page: page).contains(ScanAccuracy.joineryDisclaimer), "\(paper) \(orientation)")
                }
            }
        }
    }

    func testTitleBlockTruncatesLongTextInsteadOfOverflowingAndEscapesSpecialCharacters() {
        let p = Property(name: String(repeating: "Very Long Property Name ", count: 8), client: "Mr. (Al) \\ Client",
                         address: "Caf\u{E9} \u{2013} \u{2192} Dubai \u{0645}", reference: "R",
                         floors: [Floor(name: "Level 1", rooms: [rectRoom(5, 4)])])
        let r = render(p, PlanPDFOptions(includeSchedule: false))
        XCTAssertEqual(r.probe.problems(), [])
        let shown = r.probe.shown(page: 0)
        let long = shown.first { $0.hasPrefix("Very Long") }!
        XCTAssertTrue(long.hasSuffix("..."))
        XCTAssertLessThanOrEqual(HelveticaMetrics.width(of: long, bold: true, fontSize: 9.5), (0.31 * 400 - 6) * 72 / 25.4 + 1e-6)
        XCTAssertTrue(shown.contains("Mr. (Al) \\ Client"), "parentheses and backslash survive the PDF string escaping")
        XCTAssertTrue(shown.contains { $0.hasPrefix("Caf\u{E9} \u{96} ? Dubai ?") }, "e-acute kept, en dash mapped, unsupported -> ?")
    }

    func testDateComesFromTheInjectedNowAndTheDubaiOffset() {
        let evening = Date(timeIntervalSince1970: 1_791_540_000 + 11 * 3600)   // 2026-10-09 21:00 UTC = 01:00 on the 10th in Dubai
        XCTAssertTrue(render(PlanPDFFixture.demoProperty(), now: evening).probe.shown(page: 0).contains("10 Oct 2026"))
        var utc = PlanPDFOptions(); utc.utcOffsetMinutes = 0
        XCTAssertTrue(render(PlanPDFFixture.demoProperty(), utc, now: evening).probe.shown(page: 0).contains("9 Oct 2026"))
        XCTAssertEqual(PlanPDFRenderer.dateText(Date(timeIntervalSince1970: 0), offsetMinutes: 0), "1 Jan 1970")
        XCTAssertEqual(PlanPDFRenderer.dateText(Date(timeIntervalSince1970: 1_709_164_800), offsetMinutes: 240), "29 Feb 2024")
        XCTAssertEqual(PlanPDFRenderer.dateText(Date(timeIntervalSince1970: 1_700_000_000), offsetMinutes: -300), "14 Nov 2023")
        // Creation date in the Info dictionary is UTC.
        XCTAssertTrue(render(PlanPDFFixture.demoProperty(), now: evening).probe.text.contains("/CreationDate (D:20261009210000Z)"))
    }

    func testScaleBarLengthIsARoundDistanceAtTheStatedScale() {
        // At each scale: the longest round length (0.1 ... 500 m) whose paper length is at most 42 mm.
        let expectedMM: [Double: Double] = [20: 25, 25: 40, 50: 40, 75: 26.667, 100: 20, 150: 33.333, 200: 25, 250: 40, 500: 40]
        let tiny = [rectRoom(3, 2.5)]
        for (scale, mm) in expectedMM {
            let r = render(property(rooms: tiny), PlanPDFOptions(paper: .a3, scale: .fixed(scale), includeSchedule: false))
            let stream = r.probe.streams[0]
            let widths = stream.split(separator: "\n").filter { $0.hasSuffix(" re") }.map { numbersIn($0) }.filter { $0.count == 4 }.map { $0[2] }
            XCTAssertTrue(widths.contains { abs($0 - points(mm)) < 0.01 }, "1:\(scale): bar of \(mm) mm = \(points(mm)) pt, widths \(widths)")
            XCTAssertTrue(widths.contains { abs($0 - points(mm) / 2) < 0.01 }, "two equal halves")
        }
        // Labels at 1:50: 0, 1, 2 m.
        let shown = render(property(rooms: tiny), PlanPDFOptions(paper: .a3, scale: .fixed(50), includeSchedule: false)).probe.shown(page: 0)
        XCTAssertTrue(contains(shown, sequence: ["0", "1", "2 m"]))
        // Imperial: feet, 5 ft = 1.524 m = 30.48 mm at 1:50; 10 ft would be 61 mm.
        let imperial = render(property(rooms: tiny), PlanPDFOptions(paper: .a3, scale: .fixed(50), units: DisplayUnits(length: .feetAndInches, area: .squareFeet), includeSchedule: false))
        XCTAssertTrue(contains(imperial.probe.shown(page: 0), sequence: ["0", "2.5", "5 ft"]))
    }

    // MARK: Drawing on paper

    func testLineWeightsOnPaperAreWallsHalfAMillimetreAndDimensionsAThirteenthOfOne() {
        let stream = render(PlanPDFFixture.demoProperty()).probe.streams[0]
        func pt(_ mm: Double) -> String { String(format: "%.3f", mm * 72 / 25.4) }   // 0.5 -> 1.417, 0.13 -> 0.369
        XCTAssertEqual(pt(0.5), "1.417")
        XCTAssertEqual(pt(0.13), "0.369")
        let widths = stream.split(separator: "\n").filter { $0.hasSuffix(" w") }.compactMap { Double($0.dropLast(2)) }
        func has(_ mm: Double) -> Bool { widths.contains { abs($0 - mm * 72 / 25.4) < 0.0006 } }
        XCTAssertTrue(has(0.5), "walls 0.5 mm: \(widths)")
        XCTAssertTrue(has(0.13), "dimension lines 0.13 mm")
        XCTAssertTrue(has(0.18), "ticks, windows and angle arcs 0.18 mm")
        XCTAssertFalse(has(0.2), "no stray weights")
        // Dashed open boundaries and openings: 2.2 mm on, 1.1 mm off.
        let demoWithOpen: Property = {
            var room = Room.rectangle(name: "Open", width: 5, depth: 4)
            room.walls[1].kind = .virtual
            return property(rooms: [room])
        }()
        let open = render(demoWithOpen).probe.streams[0]
        XCTAssertTrue(open.contains("[6.236 3.118] 0 d"))
        XCTAssertTrue(open.contains("[] 0 d"), "and back to solid")
    }

    func testPlanIsDrawnAtTheStatedScale() {
        let r = render(PlanPDFFixture.demoProperty())
        let info = PlanPDFRenderer.pageInfos(property: PlanPDFFixture.demoProperty(), options: PlanPDFOptions())[0]
        let scale = info.scale!
        XCTAssertEqual(scale, 50)
        let segments = strokedSegments(r.probe.streams[0])
        func length(_ s: (x0: Double, y0: Double, x1: Double, y1: Double)) -> Double { hypot(s.x1 - s.x0, s.y1 - s.y0) }
        // The living room's south dimension line runs the full 6.2 m clear length: 124 mm at 1:50.
        let expected = 6.2 * 1000 / scale * 72 / 25.4
        XCTAssertEqual(expected, 351.496, accuracy: 0.001)
        XCTAssertTrue(segments.contains { abs(length($0) - expected) < 0.005 && abs($0.y1 - $0.y0) < 1e-9 }, "no horizontal 6.2 m segment")
        // So does each 4.5 m wall (90 mm) and the 4.0 m master bedroom wall (80 mm), vertical and horizontal.
        for (metres, horizontal) in [(4.5, false), (4.0, true)] {
            let e = metres * 1000 / scale * 72 / 25.4
            XCTAssertTrue(segments.contains { abs(length($0) - e) < 0.005 && (horizontal ? abs($0.y1 - $0.y0) < 1e-9 : abs($0.x1 - $0.x0) < 1e-9) }, "\(metres) m")
        }
        // At 1:100 every length is halved.
        let half = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(scale: .fixed(100)))
        let halfSegments = strokedSegments(half.probe.streams[0])
        XCTAssertTrue(halfSegments.contains { abs(length($0) - expected / 2) < 0.005 })
        XCTAssertFalse(halfSegments.contains { abs(length($0) - expected) < 0.005 })
    }

    func testNothingOfThePlanIsDrawnOutsideTheSheetFrame() {
        for options in [PlanPDFOptions(paper: .a3), PlanPDFOptions(paper: .a4, orientation: .portrait)] {
            let r = render(PlanPDFFixture.demoProperty(), options)
            let box = r.probe.mediaBoxes[0]
            let margin = points(10)
            for line in r.probe.streams[0].split(separator: "\n") where line.hasSuffix(" m") || line.hasSuffix(" l") {
                let n = numbersIn(line)
                XCTAssertGreaterThanOrEqual(n[0], margin - 0.01); XCTAssertLessThanOrEqual(n[0], box.0 - margin + 0.01)
                XCTAssertGreaterThanOrEqual(n[1], margin - 0.01); XCTAssertLessThanOrEqual(n[1], box.1 - margin + 0.01)
            }
        }
    }

    func testPlanIsClippedAndGraphicsStateIsBalanced() {
        let r = render(PlanPDFFixture.demoProperty())
        for stream in r.probe.streams {
            let lines = stream.split(separator: "\n")
            XCTAssertEqual(lines.filter { $0 == "q" }.count, lines.filter { $0 == "Q" }.count)
        }
        XCTAssertTrue(r.probe.streams[0].contains("W n"), "the plan is clipped to its drawing area")
    }

    func testPlanPageShowsTheDimensionsAndVerifiedMarks() {
        let shown = render(PlanPDFFixture.demoProperty()).probe.shown(page: 0)
        for needle in ["6200 mm", "6210 mm v", "4500 mm", "4000 mm", "3800 mm", "2000 mm", "1500 mm",
                       "Living Room", "Master Bedroom", "Kitchen", "Bathroom", "Bedroom 2", "27.9 m\u{B2}", "12.0 m\u{B2}",
                       "Ceiling 2800 mm", "Ceiling 2780 mm v", "92.5\u{B0}", "270.0\u{B0}",
                       "D 900x2100", "W 2200x1500 H900", "O 1200x2400", "Sofa", "Bed"] {
            XCTAssertTrue(shown.contains(needle), "missing \(needle)")
        }
        XCTAssertFalse(shown.contains("6210 mm"), "a verified wall never appears without its mark")
        // Exactly the verified items carry a "v": wall 6210 and ceiling 2780.
        XCTAssertEqual(Set(shown.filter { $0.hasSuffix(" v") && $0 != "v = verified on site" }), ["6210 mm v", "Ceiling 2780 mm v"])
    }

    func testDimensionAngleAndFurnitureTogglesRemoveTheirContent() {
        let all = render(PlanPDFFixture.demoProperty()).probe.shown(page: 0)
        XCTAssertTrue(all.contains("6200 mm")); XCTAssertTrue(all.contains("92.5\u{B0}")); XCTAssertTrue(all.contains("Sofa"))

        let noDims = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(showDimensions: false)).probe.shown(page: 0)
        XCTAssertFalse(noDims.contains("6200 mm")); XCTAssertFalse(noDims.contains("D 900x2100"), "opening sizes go with dimensions")
        XCTAssertTrue(noDims.contains("Living Room")); XCTAssertTrue(noDims.contains("92.5\u{B0}"))

        let noAngles = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(showAngles: false)).probe.shown(page: 0)
        XCTAssertFalse(noAngles.contains("92.5\u{B0}")); XCTAssertFalse(noAngles.contains("270.0\u{B0}"))
        XCTAssertTrue(noAngles.contains("6200 mm"))

        let noFurniture = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(showFurniture: false)).probe.shown(page: 0)
        XCTAssertFalse(noFurniture.contains("Sofa")); XCTAssertFalse(noFurniture.contains("Bed"))
        XCTAssertTrue(noFurniture.contains("6200 mm"))
    }

    func testUnitsFlowIntoPlanAndSchedule() {
        let imperial = DisplayUnits(length: .feetAndInches, area: .squareFeet)
        let r = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(units: imperial))
        let plan = r.probe.shown(page: 0)
        XCTAssertTrue(plan.contains("20' 4 1/2\" v"), "6.21 m verified = 244.5 in")
        XCTAssertTrue(plan.contains("301 sq ft"), "27.92 m2 / 0.0929 = 300.6")
        XCTAssertFalse(plan.contains("6200 mm"))
        let schedule = r.probe.shown(page: 1)
        XCTAssertTrue(schedule.contains { $0.hasSuffix(" sq ft") })
        XCTAssertFalse(schedule.contains { $0.hasSuffix(" mm") })

        let metres = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(units: DisplayUnits(length: .metres, area: .squareMetres)))
        XCTAssertTrue(metres.probe.shown(page: 0).contains("6.210 m v"), "a checked wall keeps its millimetre in metres")
        XCTAssertTrue(metres.probe.shown(page: 1).contains("21.410 m"), "schedule uses precise formatting")
    }

    // MARK: Schedule

    func testScheduleRowsAreTheRoomsInOrderWithHandCheckedFigures() {
        let r = render(PlanPDFFixture.demoProperty())
        let shown = r.probe.shown(page: 1)
        // Living: the long walls are 6.21 (laser-verified) and 6.20 (scanned), so the length prints as the
        // two walls, the scanned one bare and the verified one marked; the short walls are both 4.5 scanned.
        // Area is the derived 6.205 x 4.5. Perimeter 6.21 + 4.5 + 6.2 + 4.5 = 21.41, checks: 4 lengths +
        // 4 heights + ceiling + (2 doors x 2) + doorless opening 2 + window 3 (width, height, sill 0.9) = 18,
        // one verified.
        XCTAssertTrue(contains(shown, sequence: ["Living Room", "27.92 m\u{B2}", "6200 - 6210 v mm", "4500 mm", "2800 mm", "21410 mm", "1/18"]))
        // Master: 4.5 x 4.0 = 18.00, ceiling verified 2.78, perimeter 17.0, checks 8 + 1 + (2 doors x 2 + 2 windows x 3) = 19.
        XCTAssertTrue(contains(shown, sequence: ["Master Bedroom", "18.00 m\u{B2}", "4500 mm", "4000 mm", "2780 mm v", "17000 mm", "1/19"]))
        // Kitchen is an L: no length or width. Perimeter 4.2 + 2 + 1.8 + 1.5 + 2.4 + 3.5 = 15.4; checks 6 + 6 + 1 + 2 + 2 + 3 = 20.
        XCTAssertTrue(contains(shown, sequence: ["Kitchen", "12.00 m\u{B2}", "-", "-", "2800 mm", "15400 mm", "0/20"]))
        // Bathroom 2 x 2: 4.00 m2, perimeter 8.0, checks 4 + 4 + 1 + 2 + 3 (window sill 1.2) = 14.
        XCTAssertTrue(contains(shown, sequence: ["Bathroom", "4.00 m\u{B2}", "2000 mm", "2000 mm", "2800 mm", "8000 mm", "0/14"]))
        XCTAssertTrue(shown.contains("Bedroom 2"))
        // Order: rooms appear in model order.
        let order = ["Living Room", "Master Bedroom", "Kitchen", "Bathroom", "Bedroom 2"].map { n in shown.firstIndex(of: n)! }
        XCTAssertEqual(order, order.sorted())
        // Headers: length and width have a column each.
        XCTAssertTrue(contains(shown, sequence: ["ROOM", "AREA", "LENGTH", "WIDTH", "CEILING", "PERIMETER", "VERIFIED"]))
        // The averaged 6205 that the old schedule printed is a number no wall measured.
        XCTAssertFalse(shown.contains { $0.contains("6205") })
    }

    func testScheduleTotalsRow() {
        let property = PlanPDFFixture.demoProperty()
        let shown = render(property).probe.shown(page: 1)
        let rooms = property.allRooms
        // Total checks: 18 + 19 + 20 + 14 + 16 = 87, verified 2 (a wall and a ceiling).
        let totalIndex = shown.firstIndex(of: "Total (5 rooms)")!
        XCTAssertEqual(shown[totalIndex + 3], "2/87")
        // Perimeter is the sum of effective wall lengths.
        let perimeter = rooms.reduce(0.0) { $0 + $1.walls.reduce(0.0) { $0 + $1.length.value } }
        XCTAssertEqual(shown[totalIndex + 2], "\(Int((perimeter * 1000).rounded())) mm")
        // Total area equals the sum of the printed row areas, to rounding (5 rows x 0.005).
        let printed = shown.filter { $0.hasSuffix(" m\u{B2}") }.compactMap { Double($0.dropLast(3)) }
        XCTAssertEqual(printed.count, 6, "five rooms and the total")
        XCTAssertEqual(printed.last!, printed.dropLast().reduce(0, +), accuracy: 0.03)
        XCTAssertEqual(shown[totalIndex + 1], String(format: "%.2f m\u{B2}", printed.last!))
    }

    func testVerifiedCountsFollowTheOnSiteChecklistRules() {
        // 4 x 3 room: 4 lengths + 4 wall heights + ceiling = 9; door: width, height (floor sill excluded) = 2;
        // window: width, height, sill 0.9 = 3; custom measurement 1. Total 15.
        var room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)])
        room.customMeasurements = [CustomMeasurement(label: "Run", a: Point3(0, 0, 0), b: Point3(2, 0, 0))]
        XCTAssertEqual(PlanPDFRenderer.verificationCounts(of: room).total, 15)
        XCTAssertEqual(PlanPDFRenderer.verificationCounts(of: room).verified, 0)
        room.walls[0].length.verify(4.0)
        room.ceilingHeight.verify(2.8)
        room.openings[1].sillHeight.verify(0.92)
        room.openings[0].sillHeight.verify(0)           // a verified floor sill now counts
        room.customMeasurements[0].length.verify(2.01)
        let c = PlanPDFRenderer.verificationCounts(of: room)
        XCTAssertEqual(c.verified, 5)
        XCTAssertEqual(c.total, 16, "the verified floor sill joins the list")
        // An open boundary has no wall height to check: 4 lengths + 3 heights + ceiling + door 2 + window 3 = 13.
        var open = Room.rectangle(name: "Open", width: 4, depth: 3, openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)])
        open.walls[1].kind = .virtual
        XCTAssertEqual(PlanPDFRenderer.verificationCounts(of: open).total, 13)
    }

    // MARK: Length and width

    private func lengthAndWidth(_ room: Room, _ unit: LengthUnit = .millimetres) -> (length: String, width: String)? {
        PlanPDFRenderer.lengthAndWidthTexts(room: room, metrics: room.metrics, unit: unit)
    }

    /// A 6 x 4 m room: walls 0 and 2 are the 6 m pair (the length), walls 1 and 3 the 4 m pair.
    private func sixByFour(verifiedLong: Bool = false, verifiedShort: Bool = false) -> Room {
        var room = Room.rectangle(name: "R", width: 6, depth: 4)
        if verifiedLong { room.walls[0].length.verify(6.0); room.walls[2].length.verify(6.0) }
        if verifiedShort { room.walls[1].length.verify(4.0); room.walls[3].length.verify(4.0) }
        return room
    }

    func testLengthAndWidthPrintTheTwoWallsNotAnAverageNobodyMeasured() {
        // Review case: long walls laser-verified at 6.225 and 6.210, short walls verified at 4.500.
        var room = Room.rectangle(name: "R", width: 6.2, depth: 4.5)
        room.walls[0].length.verify(6.225); room.walls[2].length.verify(6.210)
        room.walls[1].length.verify(4.5); room.walls[3].length.verify(4.5)
        let t = lengthAndWidth(room)
        XCTAssertEqual(t?.length, "6210 v - 6225 v mm", "both walls, smaller first, each marked by its own check")
        XCTAssertEqual(t?.width, "4500 v mm", "the short walls agree, so one number")
        // (6225 + 6210) / 2 = 6217.5: a size that no wall has.
        let all = (t?.length ?? "") + (t?.width ?? "")
        XCTAssertFalse(all.contains("6217") || all.contains("6218"), all)

        // One side verified and the other not (the demo's Living Room): the bare number is the scanned wall.
        var half = Room.rectangle(name: "R", width: 6.2, depth: 4.5)
        half.walls[0].length.verify(6.21)
        XCTAssertEqual(lengthAndWidth(half)?.length, "6200 - 6210 v mm")
        // The same two values the other way round: still smaller first, the mark stays with its wall.
        var other = Room.rectangle(name: "R", width: 6.2, depth: 4.5)
        other.walls[2].length.verify(6.19)
        XCTAssertEqual(lengthAndWidth(other)?.length, "6190 v - 6200 mm")
    }

    func testEveryCombinationOfVerifiedSidesReadsDifferently() {
        // Nothing verified, only the short walls, only the long walls, both: four different texts, and the
        // mark always sits on the number whose walls were checked.
        let none = lengthAndWidth(sixByFour())
        let shortOnly = lengthAndWidth(sixByFour(verifiedShort: true))
        let longOnly = lengthAndWidth(sixByFour(verifiedLong: true))
        let both = lengthAndWidth(sixByFour(verifiedLong: true, verifiedShort: true))
        XCTAssertEqual(none?.length, "6000 mm");   XCTAssertEqual(none?.width, "4000 mm")
        XCTAssertEqual(shortOnly?.length, "6000 mm", "the scanned 6000 is not marked just because 4000 was checked")
        XCTAssertEqual(shortOnly?.width, "4000 v mm")
        XCTAssertEqual(longOnly?.length, "6000 v mm"); XCTAssertEqual(longOnly?.width, "4000 mm")
        XCTAssertEqual(both?.length, "6000 v mm");     XCTAssertEqual(both?.width, "4000 v mm")
        let joined = [none, shortOnly, longOnly, both].map { ($0?.length ?? "") + " | " + ($0?.width ?? "") }
        XCTAssertEqual(Set(joined).count, 4, "\(joined)")
    }

    func testOneCheckedWallOfAPairDoesNotMarkTheNumber() {
        var room = sixByFour()
        room.walls[0].length.verify(6.0)       // wall 2 is still LiDAR only, and reads the same
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 mm", "half the evidence is not a verified number")
        room.walls[2].length.verify(6.0)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 v mm")
        // Two checked values that agree to the millimetre are one number.
        var close = sixByFour()
        close.walls[0].length.verify(6.0004); close.walls[2].length.verify(5.9996)
        XCTAssertEqual(lengthAndWidth(close)?.length, "6000 v mm")
        // ...but not in a unit fine enough to tell them apart: centimetres print one decimal (a millimetre).
        XCTAssertEqual(lengthAndWidth(close, .centimetres)?.length, "600.0 v cm")
        close.walls[2].length.verify(5.9990)
        XCTAssertEqual(lengthAndWidth(close)?.length, "5999 v - 6000 v mm")
    }

    func testDrawingAndTapeSourcesAreMarkedForWhatTheyAre() {
        var room = sixByFour()
        room.walls[0].length.verify(6.0, source: .tape); room.walls[2].length.verify(6.0, source: .laser)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 v mm", "tape and laser are both site checks")
        room.walls[2].length.verify(6.0, source: .drawing)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 d mm", "the weaker of the two sources")
        room.walls[2].length.verify(6.01, source: .drawing)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 v - 6010 d mm")
        // The schedule's ceiling cell follows the same rule.
        var withDrawingCeiling = sixByFour()
        withDrawingCeiling.ceilingHeight.verify(2.74, source: .drawing)
        let p = property(rooms: [withDrawingCeiling])
        guard case .room(let line)? = PlanPDFRenderer.scheduleRows(property: p, options: PlanPDFOptions()).first else {
            return XCTFail("no row")
        }
        XCTAssertEqual(line.ceiling, "2740 mm d")
    }

    func testLengthIsTheLongerPairWhicheverWayTheRoomIsTurned() {
        // 3 wide, 5 deep: walls 0 and 2 are the short pair; the length comes from walls 1 and 3.
        var room = Room.rectangle(name: "R", width: 3, depth: 5)
        XCTAssertEqual(lengthAndWidth(room)?.length, "5000 mm")
        XCTAssertEqual(lengthAndWidth(room)?.width, "3000 mm")
        room.walls[1].length.verify(5.0); room.walls[3].length.verify(5.0)
        XCTAssertEqual(lengthAndWidth(room)?.length, "5000 v mm")
        XCTAssertEqual(lengthAndWidth(room)?.width, "3000 mm")
        // A square: the first pair is the length.
        XCTAssertEqual(lengthAndWidth(Room.rectangle(name: "S", width: 3, depth: 3))?.length, "3000 mm")
    }

    func testLengthAndWidthInEveryUnit() {
        let room = sixByFour(verifiedLong: true)
        XCTAssertEqual(lengthAndWidth(room, .metres)?.length, "6.000 v m")
        XCTAssertEqual(lengthAndWidth(room, .centimetres)?.width, "400.0 cm")
        XCTAssertEqual(lengthAndWidth(room, .inches)?.length, "236.22 v in")        // 6 / 0.0254
        // Feet and inches carry their own marks and no trailing unit: 236.2205 in = 19 ft 8.25 in to a sixteenth.
        XCTAssertEqual(lengthAndWidth(room, .feetAndInches)?.length, "19' 8 1/4\" v")
        XCTAssertEqual(lengthAndWidth(room, .feetAndInches)?.width, "13' 1 1/2\"")
    }

    func testLengthAndWidthOfStraightContinuationsAndOddShapes() {
        // A rectangle whose north wall is two collinear walls: still four sides. The side counts as checked
        // only when both of its walls were.
        let corners = [Point2(0, 0), Point2(6, 0), Point2(6, 4), Point2(3, 4), Point2(0, 4)]
        var room = Room.polygon(name: "Split", corners: corners)
        XCTAssertEqual(room.walls.count, 5)
        room.walls[0].length.verify(6.0)
        room.walls[2].length.verify(3.0)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 mm", "north side: only one of its two walls is checked")
        room.walls[3].length.verify(3.0)
        XCTAssertEqual(lengthAndWidth(room)?.length, "6000 v mm", "south side checked, north side checked in two parts")
        XCTAssertEqual(lengthAndWidth(room)?.width, "4000 mm")
        // L-shapes, triangles and open plans have no length x width.
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        XCTAssertNil(lengthAndWidth(l))
        XCTAssertNil(lengthAndWidth(Room.polygon(name: "T", corners: [Point2(0, 0), Point2(4, 0), Point2(0, 3)])))
    }

    func testPrintedLengthsAreAlwaysAWallOfTheRoomAndMarksNeedEveryWallChecked() {
        // 300 random rectangles with random scan error and random checks: whatever the combination, every
        // number printed is the effective length of one of the two walls of its pair (to the millimetre), and
        // a "v" follows a number only when each wall that has that length was laser-checked.
        var rng = LCG(state: 20260610)
        for trial in 0..<300 {
            let width = 2 + 6 * rng.next(), depth = 2 + 6 * rng.next()
            var room = Room.rectangle(name: "R\(trial)", width: width, depth: depth)
            for i in 0..<4 {
                room.walls[i].length.scanned += rng.range(-0.03, 0.03)
                if rng.next() < 0.5 { room.walls[i].length.verify(room.walls[i].length.scanned + rng.range(-0.02, 0.02)) }
                if rng.next() < 0.2 { room.walls[i].length.verify(room.walls[(i + 2) % 4].length.value) }
            }
            guard let t = lengthAndWidth(room) else { XCTFail("rectangle \(trial) has no length x width"); continue }
            for (text, pair) in [(t.length, 0), (t.width, 1)] {
                // Which pair is the length? The pair with the larger mean effective length.
                let mean0 = (room.walls[0].length.value + room.walls[2].length.value) / 2
                let mean1 = (room.walls[1].length.value + room.walls[3].length.value) / 2
                let lengthPair = mean0 >= mean1 ? 0 : 1
                let walls = (pair == 0 ? lengthPair : 1 - lengthPair) == 0 ? [room.walls[0], room.walls[2]] : [room.walls[1], room.walls[3]]
                let values = walls.map { Int(($0.length.value * 1000).rounded()) }
                let printed = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                XCTAssertTrue(printed.allSatisfy { values.contains($0) }, "trial \(trial): \(text) vs walls \(values)")
                XCTAssertTrue(Set(values) == Set(printed), "trial \(trial): both walls' values appear, none other: \(text) vs \(values)")
                // A mark follows a number only when every wall with that number is checked.
                for wall in walls {
                    let n = Int((wall.length.value * 1000).rounded())
                    if text.contains("\(n) v"), !wall.length.isVerified {
                        // Allowed only if the other wall printed the same number and is the checked one... no: an
                        // unchecked wall behind a marked number is exactly the defect.
                        XCTFail("trial \(trial): \(n) marked v but one of its walls is LiDAR only: \(text)")
                    }
                }
            }
        }
    }


    func testSchedulePaginationHandComputedForSixtyRooms() {
        // A4 portrait: frame 277 mm high, title block 34 mm, so 243 mm of page body. Page 1 has
        // 12 mm padding + 19 mm heading + 8 mm header + 16 mm footnote reserved: 188 mm = 26 rows of 7.2 mm
        // (26 x 7.2 = 187.2; 27 would be 194.4). Later pages reserve 10 mm for the heading: 197 mm = 27 rows.
        // 60 rooms: 26 + 27 + 7, with the 8.2 mm totals row on the last page (7 x 7.2 + 8.2 = 58.6).
        let rooms = (1...60).map { rectRoom(3, 2.5, name: "Room \($0)") }
        let p = property(rooms: rooms)
        let r = render(p, PlanPDFOptions(paper: .a4, orientation: .auto, includeSchedule: true))
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertEqual(r.probe.pageCount, 4, "1 plan + 3 schedule pages")
        let counts = (1...3).map { page in r.probe.shown(page: page).filter { $0.hasPrefix("Room ") && Int($0.dropFirst(5)) != nil }.count }
        XCTAssertEqual(counts, [26, 27, 7])
        XCTAssertFalse(r.probe.shown(page: 1).contains { $0.hasPrefix("Total") })
        XCTAssertFalse(r.probe.shown(page: 2).contains { $0.hasPrefix("Total") })
        XCTAssertTrue(r.probe.shown(page: 3).contains("Total (60 rooms)"))
        // Nothing lost or repeated, in order.
        let all = (1...3).flatMap { r.probe.shown(page: $0) }.filter { $0.hasPrefix("Room ") && Int($0.dropFirst(5)) != nil }
        XCTAssertEqual(all, (1...60).map { "Room \($0)" })
        XCTAssertTrue(r.probe.shown(page: 2).contains("Room schedule (continued)"))
        XCTAssertTrue(r.probe.shown(page: 3).contains("Room schedule (continued)"))
        for page in 1...3 {
            XCTAssertTrue(r.probe.shown(page: page).contains("Room schedule"), "title block names the sheet in full on page \(page + 1)")
        }
        XCTAssertTrue(r.probe.shown(page: 1).contains("Room schedule"))
        for page in 1...3 {
            XCTAssertTrue(r.probe.shown(page: page).contains(ScanAccuracy.joineryDisclaimer))
            XCTAssertTrue(r.probe.shown(page: page).contains("Sheet \(page + 1) of 4"))
            XCTAssertTrue(contains(r.probe.shown(page: page), sequence: ["ROOM", "AREA"]), "header repeats on every page")
        }
        // Total: 60 rooms of 3 x 2.5 = 7.5 m2 each = 450 m2; perimeter 11 m each = 660 m.
        XCTAssertTrue(r.probe.shown(page: 3).contains("450.00 m\u{B2}"))
        XCTAssertTrue(r.probe.shown(page: 3).contains("660000 mm"))
    }

    func testTotalsRowNeverStandsAloneOnAPage() {
        // 188 mm of rows on page 1. 25 rooms are 180 mm and fit, but the 8.2 mm totals row would reach 188.2,
        // so the last room moves to the next page with it.
        let p = property(rooms: (1...25).map { rectRoom(3, 2.5, name: "Room \($0)") })
        let r = render(p, PlanPDFOptions(paper: .a4))
        XCTAssertEqual(r.probe.pageCount, 3, "plan + 2 schedule pages")
        let first = r.probe.shown(page: 1)
        let second = r.probe.shown(page: 2)
        XCTAssertTrue(first.contains("Room 24")); XCTAssertFalse(first.contains("Room 25"))
        XCTAssertTrue(second.contains("Room 25"))
        XCTAssertTrue(second.contains("Total (25 rooms)"))
        // 24 rooms (172.8 mm) do fit with the total (181 mm) on one page.
        let fits = render(property(rooms: (1...24).map { rectRoom(3, 2.5, name: "Room \($0)") }), PlanPDFOptions(paper: .a4))
        XCTAssertEqual(fits.probe.pageCount, 2)
    }

    func testFloorHeadersAppearForMultipleFloorsAndNeverEndAPage() {
        let a = Floor(name: "Level A", rooms: (1...25).map { rectRoom(3, 2.5, name: "A\($0)") })
        let b = Floor(name: "Level B", rooms: (1...3).map { rectRoom(3, 2.5, name: "B\($0)") })
        let r = render(Property(name: "P", floors: [a, b]), PlanPDFOptions(paper: .a4))
        // Page 1 body: header 6.5 + 25 x 7.2 = 186.5; Level B header would still fit (193.0 <= 197) but B1 would not,
        // so the header moves to the next page with its first room.
        XCTAssertEqual(r.probe.pageCount, 4, "two plan pages and two schedule pages")
        let firstSchedule = r.probe.shown(page: 2)
        let secondSchedule = r.probe.shown(page: 3)
        XCTAssertTrue(firstSchedule.contains("LEVEL A"))
        XCTAssertFalse(firstSchedule.contains("LEVEL B"), "a floor header is never the last row of a page")
        XCTAssertTrue(contains(secondSchedule, sequence: ["LEVEL B", "B1"]), "it leads the next page with its first room")
        XCTAssertTrue(secondSchedule.contains("Total (28 rooms)"))
        let single = render(property(rooms: [rectRoom(3, 2.5)]), PlanPDFOptions(paper: .a4)).probe.shown(page: 1)
        XCTAssertFalse(single.contains("LEVEL 1"), "no floor header for a single floor")
    }

    func testScheduleCanBeLandscape() {
        let r = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(paper: .a4, orientation: .landscape))
        XCTAssertEqual(r.probe.mediaBoxes[1].0, points(297), accuracy: 0.001)
        XCTAssertEqual(r.probe.problems(), [])
    }

    // MARK: Robustness and determinism

    func testRenderingIsDeterministic() {
        let a = render(PlanPDFFixture.demoProperty(floors: 2)).data
        let b = render(PlanPDFFixture.demoProperty(floors: 2)).data
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, render(PlanPDFFixture.demoProperty(floors: 2), now: Date(timeIntervalSince1970: 0)).data)
    }

    func testBadGeometryStillProducesAValidPDF() {
        let nan = Room.polygon(name: "NaN", corners: [Point2(0, 0), Point2(.nan, 0), Point2(1, 1)])
        let flat = Room.polygon(name: "Flat", corners: [Point2(0, 0), Point2(5, 0), Point2(10, 0)])
        let bad = Property(name: "Bad", floors: [Floor(name: "L", rooms: [nan, flat, rectRoom(4, 3)])])
        let r = render(bad)
        XCTAssertEqual(r.probe.problems(), [])
        for word in ["nan", "inf"] {
            if let range = r.probe.text.range(of: word) {
                let around = r.probe.text[r.probe.text.index(range.lowerBound, offsetBy: -40)..<r.probe.text.index(range.upperBound, offsetBy: 30)]
                XCTFail("found \(word) near: \(around.debugDescription)")
            }
        }
        XCTAssertGreaterThanOrEqual(r.probe.pageCount, 2)

        let onlyBad = render(Property(name: "Bad", floors: [Floor(name: "L", rooms: [nan])]), PlanPDFOptions(includeSchedule: false))
        XCTAssertEqual(onlyBad.probe.problems(), [])
        let message = onlyBad.probe.shown(page: 0).joined(separator: " ")
        XCTAssertFalse(message.contains("No rooms have been scanned"), "the floor has a room; it just cannot be drawn")
        XCTAssertTrue(message.contains("None of the 1 room on this floor could be drawn"), message)
    }

    func testAHugeSiteIsStillValidAndSaysWhichScaleItUsed() {
        let r = render(property(rooms: [rectRoom(5000, 3000)]), PlanPDFOptions(includeSchedule: false))
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertTrue(r.probe.shown(page: 0).contains("1:10000"))
        XCTAssertFalse(r.probe.text.contains("e+"))
    }

    func testRoomNamesWithSpecialCharactersSurviveInPlanAndSchedule() {
        let room = Room.rectangle(name: "Maid's (Room) \\ 2\u{00B2}", kind: .maidsRoom, width: 4, depth: 3)
        let r = render(property(rooms: [room]))
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertTrue(r.probe.shown(page: 0).contains("Maid's (Room) \\ 2\u{B2}"))
        XCTAssertTrue(r.probe.shown(page: 1).contains("Maid's (Room) \\ 2\u{B2}"))
    }

    func testOptionsRoundTripThroughCodable() throws {
        var options = PlanPDFOptions(paper: .a4, orientation: .landscape, scale: .fixed(75),
                                     units: DisplayUnits(length: .feetAndInches, area: .squareFeet), showAngles: false)
        options.utcOffsetMinutes = -300
        let back = try JSONDecoder().decode(PlanPDFOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(back, options)
        let auto = try JSONDecoder().decode(PlanPDFOptions.self, from: JSONEncoder().encode(PlanPDFOptions()))
        XCTAssertEqual(auto.scale, .auto)
        XCTAssertEqual(auto.paper, .a3)
        XCTAssertEqual(auto.orientation, .auto)
        XCTAssertEqual(PDFPaper.a3.displayName, "A3")
    }

    func testDefaultOptions() {
        let o = PlanPDFOptions()
        XCTAssertEqual(o.paper, .a3)
        XCTAssertEqual(o.orientation, .auto)
        XCTAssertEqual(o.scale, .auto)
        XCTAssertEqual(o.units, .default)
        XCTAssertTrue(o.showDimensions && o.showAngles && o.showFurniture && o.includeSchedule)
        XCTAssertEqual(o.utcOffsetMinutes, 240)
    }

    func testManyFloorsAndRoomsStayFast() {
        let rooms = (0..<40).map { i in
            Room.rectangle(name: "R\(i)", origin: Point2(Double(i % 8) * 6.2, Double(i / 8) * 5.2), width: 6, depth: 5, openings: [.door(wall: 0, offset: 1), .window(wall: 2, offset: 1, width: 2)])
        }
        let p = Property(name: "Big", floors: [Floor(name: "L1", rooms: rooms), Floor(name: "L2", rooms: rooms)])
        let start = Date()
        let r = render(p)
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertLessThan(Date().timeIntervalSince(start), 20, "a 80-room property renders in seconds even in a debug build")
    }

    // MARK: Scale label

    func testScaleLabelsAreExactAndNeverTrap() {
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(50), "1:50")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(49.999), "1:50", "within half a hundredth of a whole number")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(37.5), "1:37.5", "drawn at 1:37.5, so labelled 1:37.5")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(62.5), "1:62.5")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(33.33), "1:33.33")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(0.4), "1:0.4")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(10000), "1:10000")
        XCTAssertEqual(PlanPDFRenderer.scaleLabel(1e19), "1:10000000000000000000", "beyond Int.max: no conversion to Int")
        for bad in [Double.nan, .infinity, -.infinity, 0, -5] {
            XCTAssertEqual(PlanPDFRenderer.scaleLabel(bad), "1:?", "\(bad)")
        }

        // A fixed non-standard scale is printed as it is drawn: scale bar, wall lengths and the title block agree.
        let info = PlanPDFRenderer.pageInfos(property: PlanPDFFixture.demoProperty(), options: PlanPDFOptions(scale: .fixed(37.5)))[0]
        XCTAssertEqual(info.scale, 37.5)
        XCTAssertEqual(info.scaleLabel, "1:37.5")
        let r = render(PlanPDFFixture.demoProperty(), PlanPDFOptions(scale: .fixed(37.5)))
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertTrue(r.probe.shown(page: 0).contains("1:37.5"))
        XCTAssertFalse(r.probe.shown(page: 0).contains("1:38"))
    }

    func testAnAbsurdFixedScaleStillRenders() {
        for scale in [1e19, 1e300, .infinity, .nan, -3, 0] {
            let options = PlanPDFOptions(scale: .fixed(scale))
            let r = render(PlanPDFFixture.demoProperty(), options)
            XCTAssertEqual(r.probe.problems(), [], "\(scale)")
            XCTAssertFalse(r.probe.text.contains("nan"), "\(scale)")
            for info in PlanPDFRenderer.pageInfos(property: PlanPDFFixture.demoProperty(), options: options) {
                XCTAssertFalse(info.scaleLabel.isEmpty)
            }
        }
    }

    // MARK: Schedule layout

    func testNoNumberInTheScheduleIsCutShort() {
        // Three halls of 61.3 x 41.7 m in square feet and feet-and-inches on A4: the totals used to print
        // "82544.4 s..." and "2027' 6 11/1...".
        let halls = (0..<3).map { Room.rectangle(name: "Hall \($0)", width: 61.3, depth: 41.7) }
        let p = Property(name: "Big", floors: [Floor(name: "L1", rooms: halls)])
        let imperial = PlanPDFOptions(paper: .a4, units: DisplayUnits(length: .feetAndInches, area: .squareFeet))
        let page = render(p, imperial).probe.shown(page: 1)
        XCTAssertFalse(page.contains { $0.contains("...") }, "\(page.filter { $0.contains("...") })")
        guard let totalIndex = page.firstIndex(of: "Total (3 rooms)"), totalIndex + 1 < page.count else {
            return XCTFail("no totals row: \(page)")
        }
        XCTAssertEqual(page[totalIndex + 1], "82544.4 sq ft", "3 x 61.3 x 41.7 = 7669.2 m2 / 0.09290304")
        // And a villa over a thousand square metres, where the 12 % area column used to give out.
        let villa = Property(name: "V", floors: [Floor(name: "L1", rooms: [Room.rectangle(name: "Great hall", width: 40, depth: 30)])])
        let big = render(villa, PlanPDFOptions(paper: .a4, units: DisplayUnits(length: .feetAndInches, area: .squareFeet))).probe.shown(page: 1)
        XCTAssertTrue(big.contains("12916.7 sq ft"), "1200 m2")
        XCTAssertFalse(big.contains { $0.contains("...") })
        // The helper itself: shrinks in quarter points until the text fits, and says what size it settled on.
        let fitted = PlanPDFRenderer.fittedNumber("82544.4 sq ft", widthMM: 14, size: 8.5, bold: true)
        XCTAssertEqual(fitted.text, "82544.4 sq ft")
        XCTAssertLessThan(fitted.size, 8.5)
        XCTAssertLessThanOrEqual(PlanPDFRenderer.Canvas.textWidthMM(fitted.text, size: fitted.size, bold: true), 14 + 1e-9)
        XCTAssertGreaterThan(PlanPDFRenderer.Canvas.textWidthMM(fitted.text, size: fitted.size + 0.25, bold: true), 14,
                             "the largest size in quarter-point steps that fits")
        let roomy = PlanPDFRenderer.fittedNumber("12", widthMM: 30, size: 8, bold: false)
        XCTAssertEqual(roomy.size, 8); XCTAssertEqual(roomy.text, "12")
        // Only below 4 pt does the last resort apply.
        let hopeless = PlanPDFRenderer.fittedNumber("123456789012345678901234567890", widthMM: 5, size: 8, bold: false)
        XCTAssertEqual(hopeless.size, 4)
        XCTAssertTrue(hopeless.text.hasSuffix("..."))
    }

    func testContinuationPagesRepeatTheirFloorHeader() {
        // 3 floors x 24 rooms on A4: three schedule pages. A page that starts in the middle of a floor opens with
        // that floor's header again, so "F2 Room 5" is never an unlabelled row.
        let floors = (1...3).map { f in
            Floor(name: "Level \(f)", level: f, rooms: (1...24).map { Room.rectangle(name: "F\(f) Room \($0)", width: 3, depth: 3) })
        }
        let p = Property(name: "Tower", floors: floors)
        let pages = PlanPDFRenderer.schedulePages(property: p, options: PlanPDFOptions(paper: .a4, orientation: .portrait))
        XCTAssertGreaterThanOrEqual(pages.count, 3)
        var floorOfRow: [String] = []
        for (index, page) in pages.enumerated() {
            guard case .schedule(let rows, _, _, _) = page.content else { return XCTFail("not a schedule page") }
            guard case .floorHeader(let first)? = rows.first else { return XCTFail("page \(index) does not start with a floor header: \(String(describing: rows.first))") }
            // The header names the floor of the first room on the page.
            guard let firstRoom = rows.compactMap({ row -> String? in if case .room(let l) = row { return l.name }; return nil }).first else { continue }
            let floorNumber = firstRoom.dropFirst().prefix(1)
            XCTAssertTrue(first.hasPrefix("Level \(floorNumber)"), "page \(index): \(first) for \(firstRoom)")
            if index > 0 { XCTAssertTrue(first.hasSuffix("(cont.)") || rows.count > 1, first) }
            floorOfRow.append(first)
        }
        // Every row on every page sits under a header of its own floor.
        for page in pages {
            guard case .schedule(let rows, _, _, _) = page.content else { continue }
            var current = ""
            for row in rows {
                switch row {
                case .floorHeader(let name): current = name
                case .room(let line): XCTAssertTrue(current.hasPrefix("Level \(line.name.dropFirst().prefix(1))"), "\(line.name) under \(current)")
                default: break
                }
            }
        }
        XCTAssertTrue(floorOfRow.contains { $0.hasSuffix("(cont.)") }, "a floor really did continue across a page: \(floorOfRow)")
        // In the PDF the header is drawn in capitals.
        let shown = render(p, PlanPDFOptions(paper: .a4, orientation: .portrait))
        XCTAssertGreaterThanOrEqual(shown.probe.pageCount, 6, "3 plan pages and at least 3 schedule pages")
        let schedulePages = shown.probe.pageCount > 3 ? (3..<shown.probe.pageCount).map { shown.probe.shown(page: $0) } : []
        XCTAssertTrue(schedulePages.dropFirst().allSatisfy { page in page.contains { $0.hasPrefix("LEVEL ") } })
        // The height of the repeated header counts against the page: nothing runs off the bottom.
        XCTAssertEqual(shown.probe.problems(), [])
    }

    func testRoomsThatCannotBeDrawnAreSaidSoOnThePlanAndInTheSchedule() {
        let broken = Room(name: "Broken room", walls: [Wall(start: .zero, end: Point2(2, 0), height: Measured(scanned: 2.8))],
                          ceilingHeight: Measured(scanned: 2.8))
        let nan = Room.polygon(name: "NaN room", corners: [Point2(0, 0), Point2(.nan, 0), Point2(1, 1)])
        let good = Room.rectangle(name: "Good", width: 3, depth: 3)

        // A floor of nothing but undrawable rooms does not claim that nothing was scanned.
        let onlyBroken = Property(name: "P", floors: [Floor(name: "L1", rooms: [broken])])
        let emptyPlan = render(onlyBroken, PlanPDFOptions(includeSchedule: false)).probe.shown(page: 0).joined(separator: " ")
        XCTAssertFalse(emptyPlan.contains("No rooms have been scanned"), emptyPlan)
        XCTAssertTrue(emptyPlan.contains("None of the 1 room on this floor could be drawn"), emptyPlan)
        XCTAssertTrue(emptyPlan.contains("Broken room"), "the message names it")

        // Mixed floor: the plan page carries a note, the page info lists the names.
        let mixed = Property(name: "P", floors: [Floor(name: "L1", rooms: [broken, good, nan])])
        let info = PlanPDFRenderer.pageInfos(property: mixed, options: PlanPDFOptions())[0]
        XCTAssertEqual(info.undrawableRoomNames, ["Broken room", "NaN room"])
        let page = render(mixed, PlanPDFOptions()).probe.shown(page: 0)
        XCTAssertTrue(page.contains { $0.hasPrefix("2 rooms not drawn: Broken room, NaN room") }, "\(page.filter { $0.contains("drawn") })")
        XCTAssertTrue(page.contains("Good"))

        // The schedule lists them but counts nothing for them: no area, no perimeter, no checks.
        let rows = PlanPDFRenderer.scheduleRows(property: mixed, options: PlanPDFOptions())
        guard rows.count == 4, case .room(let brokenLine) = rows[0], case .room(let goodLine) = rows[1],
              case .total(let total) = rows[3] else {
            return XCTFail("unexpected rows \(rows)")
        }
        XCTAssertTrue(brokenLine.isNotDrawn)
        XCTAssertEqual([brokenLine.area, brokenLine.length, brokenLine.width, brokenLine.perimeter, brokenLine.verified],
                       ["-", "-", "-", "-", "not drawn"])
        XCTAssertFalse(goodLine.isNotDrawn)
        XCTAssertEqual(total.name, "Total (1 rooms)", "only the room that is on the plan")
        XCTAssertEqual(total.area, "9.00 m\u{B2}")
        XCTAssertEqual(total.perimeter, "12000 mm", "the good room's 4 x 3 m only; the broken room's 2 m is not added")
        XCTAssertEqual(total.totalCount, goodLine.totalCount)
        let schedule = render(mixed, PlanPDFOptions()).probe.shown(page: 1)
        XCTAssertTrue(schedule.contains("not drawn"))
        XCTAssertTrue(schedule.contains { $0.hasPrefix("Not drawn: the scan has fewer than three walls") }, "footnote")
    }

    func testCurvedWallsAreFlaggedOnThePlanAndInTheSchedule() {
        var bay = Room.rectangle(name: "Bay Lounge", kind: .livingRoom, width: 6, depth: 4)
        bay.walls[0].isCurved = true
        let p = property(rooms: [bay, Room.rectangle(name: "Plain", width: 3, depth: 3)])
        let r = render(p)
        let plan = r.probe.shown(page: 0)
        XCTAssertTrue(plan.contains("6000 mm chord"), "the straight length is called what it is")
        XCTAssertTrue(plan.contains("chord = curved wall"), "and the legend explains it")
        let schedule = r.probe.shown(page: 1)
        XCTAssertTrue(schedule.contains("Bay Lounge*"), "starred in the schedule")
        XCTAssertTrue(schedule.contains("Plain"), "an ordinary room is not")
        XCTAssertTrue(schedule.contains { $0.hasPrefix("* Has a curved wall, measured as a straight chord") })
        // Without a curved wall, neither the flag nor the legend entry appears.
        let flat = render(property(rooms: [Room.rectangle(name: "Plain", width: 3, depth: 3)]))
        XCTAssertFalse(flat.probe.shown(page: 0).contains("chord = curved wall"))
        XCTAssertFalse(flat.probe.shown(page: 1).contains { $0.hasPrefix("* Has a curved wall") })
    }

    func testTheLegendExplainsDOnlyWhereTheSheetUsesIt() {
        var room = Room.rectangle(name: "R", width: 6, depth: 4)
        let plain = render(property(rooms: [room])).probe
        XCTAssertTrue(plain.shown(page: 0).contains("v = verified on site"))
        XCTAssertFalse(plain.shown(page: 0).contains("d = from drawing"))
        room.walls[0].length.verify(6.02, source: .drawing)
        let withDrawing = render(property(rooms: [room])).probe
        XCTAssertTrue(withDrawing.shown(page: 0).contains("d = from drawing"))
        XCTAssertTrue(withDrawing.shown(page: 0).contains("6020 mm d"))
        XCTAssertTrue(withDrawing.shown(page: 1).contains("d = from drawing"), "the schedule page legend too")
        XCTAssertFalse(withDrawing.shown(page: 0).contains("6020 mm v"), "a drawing is not a site check")
        // The schedule heading spells out all three states.
        let heading = withDrawing.shown(page: 1).joined(separator: " ")
        XCTAssertTrue(heading.contains("v = verified on site (laser or tape)"))
        XCTAssertTrue(heading.contains("d = taken from an approved drawing, not measured on site"))
        XCTAssertTrue(heading.contains("A number with no mark is LiDAR only"))
        // Everything fits in the legend row, whatever it holds (it shrinks, never wraps to a third line).
        let all = render(property(rooms: [room]), PlanPDFOptions(paper: .a4, orientation: .portrait)).probe
        XCTAssertEqual(all.problems(), [])
    }

    func testPageInfoSaysWhenASheetIsTooSmallForItsRooms() {
        // 20 bedrooms of 4.0 x 3.5 m: on A4 the plan lands at 1:150 where the dimensions cannot all be printed;
        // on A3 it is 1:75 or larger and everything fits. ExportEngine can use isLegible to prefer A3.
        var rooms: [Room] = []
        for row in 0..<4 {
            for col in 0..<5 {
                rooms.append(Room.rectangle(name: "R\(row)\(col)", kind: .bedroom,
                                            origin: Point2(Double(col) * 4.15, Double(row) * 3.65), width: 4.0, depth: 3.5,
                                            openings: [.door(wall: 0, offset: 0.5)]))
            }
        }
        let p = property(rooms: rooms)
        let a4 = PlanPDFRenderer.pageInfos(property: p, options: PlanPDFOptions(paper: .a4, includeSchedule: false))[0]
        XCTAssertEqual(a4.scale, 150)
        XCTAssertGreaterThan(a4.omittedDimensionCount, 0)
        XCTAssertFalse(a4.isLegible)
        let a3 = PlanPDFRenderer.pageInfos(property: p, options: PlanPDFOptions(paper: .a3, includeSchedule: false))[0]
        XCTAssertLessThanOrEqual(a3.scale ?? 999, 100)
        XCTAssertEqual(a3.omittedDimensionCount, 0)
        XCTAssertTrue(a3.isLegible)
        // The A4 sheet says so on its face and in the warnings.
        let result = PlanPDFRenderer.renderWithReport(property: p, options: PlanPDFOptions(paper: .a4, includeSchedule: false), now: PlanPDFFixture.now)
        XCTAssertTrue(result.warnings.contains { $0.contains("wall dimensions were left out") && $0.contains("1:150") && $0.contains("A4") }, "\(result.warnings)")
        let page = PDFProbe(result.data).shown(page: 0)
        XCTAssertTrue(page.contains { $0.contains("dimensions left out: too small for 1:150 on A4") }, "\(page.filter { $0.contains("left out") })")
        XCTAssertTrue(PlanPDFRenderer.renderWithReport(property: p, options: PlanPDFOptions(paper: .a3, includeSchedule: false), now: PlanPDFFixture.now).warnings.isEmpty)
    }

    func testTextThePDFCannotPrintIsReportedNotSilentlyReplaced() {
        // Arabic names print as ? with the standard fonts; the export needs to be able to say so.
        let room = Room.rectangle(name: "\u{063A}\u{0631}\u{0641}\u{0629} \u{0627}\u{0644}\u{062E}\u{0627}\u{062F}\u{0645}\u{0629}", kind: .maidsRoom, width: 3, depth: 3)
        let p = Property(name: "\u{0641}\u{064A}\u{0644}\u{0627} \u{0627}\u{0644}\u{0646}\u{062E}\u{064A}\u{0644} (Palm Villa)",
                         client: "\u{0627}\u{0644}\u{0633}\u{064A}\u{062F} \u{0623}\u{062D}\u{0645}\u{062F}", address: "Dubai", reference: "NF-1",
                         floors: [Floor(name: "Ground", rooms: [room])])
        let result = PlanPDFRenderer.renderWithReport(property: p, options: PlanPDFOptions(), now: PlanPDFFixture.now)
        guard result.warnings.count == 1, let warning = result.warnings.first else {
            return XCTFail("expected exactly one warning, got \(result.warnings)")
        }
        XCTAssertTrue(warning.hasPrefix("3 text values contain characters this PDF cannot print"), warning)
        XCTAssertTrue(warning.contains("property name") && warning.contains("client") && warning.contains("room name"), warning)
        XCTAssertTrue(warning.contains("\u{0641}\u{064A}\u{0644}\u{0627}"), "it quotes the text so the person can find it")
        // `render` is the same document.
        XCTAssertEqual(PlanPDFRenderer.render(property: p, options: PlanPDFOptions(), now: PlanPDFFixture.now), result.data)
        XCTAssertEqual(PDFProbe(result.data).problems(), [])
        // The PDF's own metadata keeps the real characters.
        XCTAssertTrue(PDFProbe(result.data).text.contains("<FEFF"), "the Info title is UTF-16")
        // Names the fonts do cover, accents included, raise nothing; neither does a property with no problems at all.
        let fine = Property(name: "Caf\u{E9} Residence \u{2013} Unit 5\u{B2}", client: "M\u{FC}ller", address: "Dubai", reference: "NF-1",
                            floors: [Floor(name: "Ground", rooms: [Room.rectangle(name: "Salon", width: 4, depth: 4)])])
        XCTAssertTrue(PlanPDFRenderer.renderWithReport(property: fine, options: PlanPDFOptions(), now: PlanPDFFixture.now).warnings.isEmpty)
        // Singular wording.
        let one = Property(name: "\u{0641}\u{064A}\u{0644}\u{0627}", floors: [Floor(name: "G", rooms: [Room.rectangle(name: "R", width: 3, depth: 3)])])
        XCTAssertEqual(PlanPDFRenderer.renderWithReport(property: one, options: PlanPDFOptions(), now: PlanPDFFixture.now)
            .warnings.first?.hasPrefix("1 text value contains"), true)
    }

    func testEnormousNamesDoNotStallTheRenderer() {
        // 18,000-character names in every field made the old quadratic truncation run for minutes.
        let long = String(repeating: "Marina Gate Tower ", count: 1000)
        let room = Room.rectangle(name: long, width: 4, depth: 3)
        let p = Property(name: long, client: long, address: long, reference: long, floors: [Floor(name: long, rooms: [room])])
        let start = Date()
        let r = render(p)
        XCTAssertLessThan(Date().timeIntervalSince(start), 20)
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertFalse(r.probe.pageCount == 0)
        // The room label is cut to fit the room, the schedule name to its column.
        let plan = r.probe.shown(page: 0)
        XCTAssertTrue(plan.allSatisfy { $0.count < 2000 }, "no 18,000-character line in the content stream")
    }

    func testAThreeHundredRoomFloorRendersInSeconds() {
        var rooms: [Room] = []
        for row in 0..<15 {
            for col in 0..<20 {
                rooms.append(Room.rectangle(name: "R\(row)-\(col)", kind: .bedroom,
                                            origin: Point2(Double(col) * 4.15, Double(row) * 3.65), width: 4.0, depth: 3.5,
                                            openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)]))
            }
        }
        let start = Date()
        let r = render(property(rooms: rooms))
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(r.probe.problems(), [])
        XCTAssertLessThan(seconds, 40, "300 rooms took \(seconds) s in a debug build")
    }

    func testVerificationCountsAgreeWithTheOnSiteChecklist() {
        // The schedule's x/y is the checklist's own count, for every kind of room the app can hold.
        var rooms = PlanPDFFixture.demoRooms() + DemoProperty.make().allRooms
        var open = Room.rectangle(name: "Open", width: 4, depth: 3, openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)])
        open.walls[1].kind = .virtual
        open.walls[0].length.verify(4); open.ceilingHeight.verify(2.8)
        open.openings[1].sillHeight.verify(0.9); open.openings[0].sillHeight.verify(0)
        open.customMeasurements = [CustomMeasurement(label: "Run", a: Point3(0, 0, 0), b: Point3(2, 0, 0))]
        rooms.append(open)
        rooms.append(Room(name: "Empty", walls: [], ceilingHeight: Measured(scanned: 2.8)))
        for room in rooms {
            let checklist = VerificationChecklist(room: room)
            let counts = PlanPDFRenderer.verificationCounts(of: room)
            XCTAssertEqual(counts.total, checklist.totalCount, room.name)
            XCTAssertEqual(counts.verified, checklist.verifiedCount, room.name)
        }
        let property = Property(name: "P", floors: [Floor(name: "L", rooms: rooms.filter { PlanDrawingBuilder.isDrawable($0) })])
        let rows = PlanPDFRenderer.scheduleRows(property: property, options: PlanPDFOptions())
        guard case .total(let total)? = rows.last else { return XCTFail("no total") }
        let progress = VerificationChecklist.roomsProgress(property.allRooms)
        XCTAssertEqual(total.verified, "\(progress.verified)/\(progress.total)")
    }

    /// Throwaway: writes PDFs for inspection with pypdf and pdftoppm when NEXAFIX_PDF_OUT is set.
    func testWriteValidationPDFs() throws {
        guard let dir = ProcessInfo.processInfo.environment["NEXAFIX_PDF_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ property: Property, _ options: PlanPDFOptions) throws {
            let data = PlanPDFRenderer.render(property: property, options: options, now: PlanPDFFixture.now)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        try write("demo_a3.pdf", PlanPDFFixture.demoProperty(), PlanPDFOptions(paper: .a3))
        try write("demo_a4.pdf", PlanPDFFixture.demoProperty(floors: 2), PlanPDFOptions(paper: .a4))
        try write("demo_a4_portrait_m.pdf", PlanPDFFixture.demoProperty(), PlanPDFOptions(
            paper: .a4, orientation: .portrait, units: DisplayUnits(length: .metres, area: .squareMetres)))
        try write("demo_a3_imperial.pdf", PlanPDFFixture.demoProperty(), PlanPDFOptions(
            paper: .a3, scale: .fixed(50), units: DisplayUnits(length: .feetAndInches, area: .squareFeet)))
        let rooms = (1...60).map { rectRoom(3, 2.5, name: "Room \($0)") }
        try write("schedule_60.pdf", property(rooms: rooms), PlanPDFOptions(paper: .a4))

        try write("demo_property_a3.pdf", Property(name: "Demo flat", client: "NexaFix", address: "Dubai", reference: "DEMO",
                                                    floors: [Floor(name: "Level 1", rooms: DemoProperty.make().allRooms)]), PlanPDFOptions(paper: .a3))
        try write("demo_property_a4.pdf", Property(name: "Demo flat", client: "NexaFix", address: "Dubai", reference: "DEMO",
                                                    floors: [Floor(name: "Level 1", rooms: DemoProperty.make().allRooms)]), PlanPDFOptions(paper: .a4))
        var grid: [Room] = []
        for row in 0..<4 {
            for col in 0..<5 {
                grid.append(Room.rectangle(name: "Bedroom \(row * 5 + col + 1)", kind: .bedroom,
                                           origin: Point2(Double(col) * 4.15, Double(row) * 3.65), width: 4.0, depth: 3.5,
                                           openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)]))
            }
        }
        try write("twenty_a4.pdf", property(rooms: grid), PlanPDFOptions(paper: .a4))
        try write("twenty_a3.pdf", property(rooms: grid), PlanPDFOptions(paper: .a3))

        var special = Room.rectangle(name: "Bay Lounge", kind: .livingRoom, width: 6.2, depth: 4.5, openings: [.door(wall: 1, offset: 1)])
        special.walls[0].isCurved = true
        special.walls[2].length.verify(6.31, source: .drawing, note: "architect drawing rev B")
        special.walls[1].length.verify(4.52, source: .tape)
        special.walls[3].length.verify(4.5, source: .laser)
        special.ceilingHeight.verify(2.74, source: .drawing)
        var unequal = Room.rectangle(name: "Study", kind: .office, origin: Point2(6.4, 0), width: 6.2, depth: 4.5, openings: [.door(wall: 3, offset: 1.0)])
        unequal.walls[0].length.verify(6.225); unequal.walls[2].length.verify(6.210)
        unequal.walls[1].length.verify(4.5); unequal.walls[3].length.verify(4.5)
        let broken = Room(name: "Broken room", walls: [Wall(start: .zero, end: Point2(1, 0), height: Measured(scanned: 2.8))],
                          ceilingHeight: Measured(scanned: 2.8))
        try write("marks.pdf", Property(name: "\u{0641}\u{064A}\u{0644}\u{0627} Palm Villa", client: "Client", address: "Dubai", reference: "R",
                                        floors: [Floor(name: "Ground", rooms: [special, unequal, broken])]), PlanPDFOptions(paper: .a3))

        let floors = (1...3).map { f in
            Floor(name: "Level \(f)", level: f, rooms: (1...24).map { Room.rectangle(name: "F\(f) Room \($0)", width: 3, depth: 3) })
        }
        try write("continuation.pdf", Property(name: "Tower", floors: floors), PlanPDFOptions(paper: .a4, orientation: .portrait))
        let halls = (0..<3).map { Room.rectangle(name: "Hall \($0)", width: 61.3, depth: 41.7) }
        try write("imperial_halls.pdf", Property(name: "Big", floors: [Floor(name: "L1", rooms: halls)]),
                  PlanPDFOptions(paper: .a4, units: DisplayUnits(length: .feetAndInches, area: .squareFeet)))
        let a = Room.rectangle(name: "Bedroom", kind: .bedroom, width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0), .window(wall: 0, offset: 1, width: 1.5)])
        let b = Room.rectangle(name: "Corridor", kind: .corridor, origin: Point2(4.15, 0), width: 3, depth: 3, openings: [.door(wall: 3, offset: 1.02)])
        try write("partition.pdf", property(rooms: [a, b]), PlanPDFOptions(paper: .a3, scale: .fixed(25)))
    }
}

/// Small deterministic generator for the scale tests.
private struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}
