import Foundation

// A minimal PDF 1.4 writer with no dependencies: no CoreGraphics, no zlib. Content streams are
// stored uncompressed (plain ASCII operators), which keeps the output deterministic, easy to
// diff and to inspect with any text editor. Only the two standard fonts the plan renderer needs
// are used (Helvetica, Helvetica-Bold, /WinAnsiEncoding), so nothing is embedded.
//
// Coordinates are PDF user space: points (1/72 inch), origin at the bottom-left of the page,
// +y up. `PDFUnits.mm` converts millimetres.

public enum PDFUnits {
    public static let pointsPerMillimetre = 72.0 / 25.4

    /// Millimetres to PDF points.
    public static func mm(_ millimetres: Double) -> Double { millimetres * pointsPerMillimetre }
    /// PDF points to millimetres.
    public static func millimetres(_ points: Double) -> Double { points / pointsPerMillimetre }
}

/// The standard-14 faces available to `PDFPage.text`.
public enum PDFFont: String, CaseIterable, Sendable {
    case helvetica = "Helvetica"
    case helveticaBold = "Helvetica-Bold"

    /// Name of the font in every page's resource dictionary.
    public var resourceName: String {
        switch self {
        case .helvetica: return "F1"
        case .helveticaBold: return "F2"
        }
    }

    public var isBold: Bool { self == .helveticaBold }
}

public enum PDFLineCap: Int, Sendable { case butt = 0, round = 1, square = 2 }
public enum PDFLineJoin: Int, Sendable { case miter = 0, round = 1, bevel = 2 }

/// Number and string formatting for PDF syntax. Locale independent, never scientific notation,
/// never NaN or infinity.
enum PDFSyntax {
    /// PDF 1.4 viewers are only required to handle real numbers up to this magnitude.
    static let limit = 32767.0

    /// "12.5", "-0.25", "0". At most three decimals, trailing zeros removed.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let clamped = Swift.max(-limit, Swift.min(limit, value))
        let scaled = (abs(clamped) * 1000).rounded()
        if scaled == 0 { return "0" }
        let n = Int64(scaled)
        let whole = n / 1000
        let fraction = n % 1000
        var text = clamped < 0 ? "-" : ""
        text += String(whole)
        if fraction != 0 {
            var digits = String(fraction)
            while digits.count < 3 { digits = "0" + digits }
            while digits.hasSuffix("0") { digits.removeLast() }
            text += "." + digits
        }
        return text
    }

    static func unit(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return number(Swift.max(0, Swift.min(1, value)))
    }

    /// A literal string "( ... )" holding raw bytes: ( ) \ escaped, everything outside printable
    /// ASCII written as a 3-digit octal escape so the stream stays 7-bit clean.
    static func literal(_ bytes: [UInt8]) -> String {
        var out = "("
        for b in bytes {
            switch b {
            case 0x28: out += "\\("
            case 0x29: out += "\\)"
            case 0x5C: out += "\\\\"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(b))
            default:
                let octal = String(b, radix: 8)
                out += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
            }
        }
        return out + ")"
    }

    /// A text string for the Info dictionary: plain literal for ASCII, otherwise UTF-16BE hex
    /// with a byte-order mark so any Unicode survives.
    static func textString(_ text: String) -> String {
        if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) {
            return literal(Array(text.utf8))
        }
        var hex = "<FEFF"
        for unit in text.utf16 {
            let h = String(unit, radix: 16, uppercase: true)
            hex += String(repeating: "0", count: 4 - h.count) + h
        }
        return hex + ">"
    }

    /// "D:20261009120000Z" for a date, in UTC, from pure integer arithmetic.
    static func date(_ date: Date) -> String {
        let c = PDFCivilDate(unixSeconds: date.timeIntervalSince1970)
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        let year = String(repeating: "0", count: Swift.max(0, 4 - String(c.year).count)) + String(c.year)
        return "D:\(year)\(two(c.month))\(two(c.day))\(two(c.hour))\(two(c.minute))\(two(c.second))Z"
    }
}

/// Proleptic Gregorian calendar date and time of day from Unix seconds (UTC), with an optional
/// fixed offset. Pure integer maths, so it behaves identically on every platform.
struct PDFCivilDate: Equatable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int

    init(unixSeconds: Double, offsetSeconds: Int = 0) {
        let whole = unixSeconds.isFinite ? Int(Swift.max(-1e12, Swift.min(1e12, unixSeconds.rounded(.down)))) : 0
        let t = whole + offsetSeconds
        var days = t / 86400
        var rem = t % 86400
        if rem < 0 { rem += 86400; days -= 1 }
        hour = rem / 3600
        minute = (rem % 3600) / 60
        second = rem % 60
        // Howard Hinnant's days-to-civil algorithm.
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        day = doy - (153 * mp + 2) / 5 + 1
        month = mp < 10 ? mp + 3 : mp - 9
        year = month <= 2 ? y + 1 : y
    }
}

// MARK: - Page

/// One page: a size in points and the content-stream operators drawn on it so far.
///
/// All drawing methods append PDF operators; the page is a value type, so build it with
/// `var page = PDFPage(...)`, draw, then hand it to `PDFWriter.addPage`.
public struct PDFPage: Sendable {
    public let width: Double
    public let height: Double
    /// Content stream operators (7-bit ASCII).
    public private(set) var content: String = ""
    /// Number of `save()` calls not yet matched by `restore()`.
    public private(set) var saveDepth = 0

    public init(width: Double, height: Double) {
        self.width = width.isFinite && width > 0 ? width : 595.276
        self.height = height.isFinite && height > 0 ? height : 841.89
    }

    /// A page sized in millimetres.
    public init(widthMM: Double, heightMM: Double) {
        self.init(width: PDFUnits.mm(widthMM), height: PDFUnits.mm(heightMM))
    }

    // MARK: Graphics state

    public mutating func save() { content += "q\n"; saveDepth += 1 }

    public mutating func restore() {
        guard saveDepth > 0 else { return }
        content += "Q\n"
        saveDepth -= 1
    }

    public mutating func setLineWidth(_ points: Double) {
        content += "\(PDFSyntax.number(Swift.max(0, points))) w\n"
    }

    public mutating func setLineCap(_ cap: PDFLineCap) { content += "\(cap.rawValue) J\n" }
    public mutating func setLineJoin(_ join: PDFLineJoin) { content += "\(join.rawValue) j\n" }
    public mutating func setMiterLimit(_ limit: Double) { content += "\(PDFSyntax.number(Swift.max(1, limit))) M\n" }

    /// Dash pattern in points: `[on, off, ...]` starting `phase` points in. An empty array is solid.
    public mutating func setDash(_ pattern: [Double], phase: Double = 0) {
        let clean = pattern.filter { $0.isFinite && $0 >= 0 }
        if clean.isEmpty || clean.allSatisfy({ $0 == 0 }) {
            content += "[] 0 d\n"
        } else {
            content += "[\(clean.map(PDFSyntax.number).joined(separator: " "))] \(PDFSyntax.number(phase)) d\n"
        }
    }

    public mutating func setStrokeColor(r: Double, g: Double, b: Double) {
        content += "\(PDFSyntax.unit(r)) \(PDFSyntax.unit(g)) \(PDFSyntax.unit(b)) RG\n"
    }

    public mutating func setFillColor(r: Double, g: Double, b: Double) {
        content += "\(PDFSyntax.unit(r)) \(PDFSyntax.unit(g)) \(PDFSyntax.unit(b)) rg\n"
    }

    public mutating func setStrokeColor(_ c: DrawColor) { setStrokeColor(r: c.r, g: c.g, b: c.b) }
    public mutating func setFillColor(_ c: DrawColor) { setFillColor(r: c.r, g: c.g, b: c.b) }

    // MARK: Paths

    public mutating func move(to x: Double, _ y: Double) {
        content += "\(PDFSyntax.number(x)) \(PDFSyntax.number(y)) m\n"
    }

    public mutating func line(to x: Double, _ y: Double) {
        content += "\(PDFSyntax.number(x)) \(PDFSyntax.number(y)) l\n"
    }

    /// Cubic Bezier from the current point through two control points to (x3, y3).
    public mutating func curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double) {
        content += "\(PDFSyntax.number(c1x)) \(PDFSyntax.number(c1y)) \(PDFSyntax.number(c2x)) "
            + "\(PDFSyntax.number(c2y)) \(PDFSyntax.number(x)) \(PDFSyntax.number(y)) c\n"
    }

    public mutating func rect(x: Double, y: Double, width: Double, height: Double) {
        content += "\(PDFSyntax.number(x)) \(PDFSyntax.number(y)) \(PDFSyntax.number(width)) "
            + "\(PDFSyntax.number(height)) re\n"
    }

    public mutating func closePath() { content += "h\n" }

    /// Counter-clockwise arc (PDF y is up, so this is the usual mathematical sense) from
    /// `startDegrees` to `endDegrees`, approximated by cubic Beziers of at most 90 degrees each
    /// (maximum radial error about 0.03 % of the radius). An end angle below the start is
    /// advanced by whole turns; sweeps beyond 360 degrees are clamped to a full circle.
    /// With `moveToStart` the path begins at the arc's first point, otherwise it continues from the current point.
    public mutating func arc(centerX cx: Double, centerY cy: Double, radius r: Double,
                             startDegrees: Double, endDegrees: Double, moveToStart: Bool = true) {
        guard r.isFinite, r > 0, cx.isFinite, cy.isFinite, startDegrees.isFinite, endDegrees.isFinite else { return }
        var sweep = endDegrees - startDegrees
        while sweep < 0 { sweep += 360 }
        if sweep > 360 { sweep = 360 }
        let a0 = startDegrees * Double.pi / 180
        if moveToStart {
            move(to: cx + r * cos(a0), cy + r * sin(a0))
        }
        guard sweep > 0 else { return }
        let segments = Swift.max(1, Int((sweep / 90).rounded(.up)))
        let step = sweep / Double(segments) * Double.pi / 180
        let k = 4.0 / 3.0 * tan(step / 4)
        var a = a0
        for _ in 0..<segments {
            let b = a + step
            let (ca, sa, cb, sb) = (cos(a), sin(a), cos(b), sin(b))
            curve(c1x: cx + r * (ca - k * sa), c1y: cy + r * (sa + k * ca),
                  c2x: cx + r * (cb + k * sb), c2y: cy + r * (sb - k * cb),
                  x: cx + r * cb, y: cy + r * sb)
            a = b
        }
    }

    /// A closed circle subpath.
    public mutating func circle(centerX cx: Double, centerY cy: Double, radius r: Double) {
        guard r.isFinite, r > 0 else { return }
        arc(centerX: cx, centerY: cy, radius: r, startDegrees: 0, endDegrees: 360)
        closePath()
    }

    // MARK: Painting

    public mutating func stroke() { content += "S\n" }
    public mutating func closeAndStroke() { content += "s\n" }
    public mutating func fill(evenOdd: Bool = false) { content += evenOdd ? "f*\n" : "f\n" }
    public mutating func fillAndStroke(evenOdd: Bool = false) { content += evenOdd ? "B*\n" : "B\n" }
    public mutating func closeFillAndStroke(evenOdd: Bool = false) { content += evenOdd ? "b*\n" : "b\n" }
    /// Ends the path without painting (used after `clip`).
    public mutating func endPath() { content += "n\n" }

    /// Intersect the clip region with the current path. Wrap in `save()` / `restore()`.
    public mutating func clip() { content += "W n\n" }

    /// Clip to a rectangle until the matching `restore()`.
    public mutating func clipRect(x: Double, y: Double, width: Double, height: Double) {
        rect(x: x, y: y, width: width, height: height)
        clip()
    }

    // MARK: Convenience

    public mutating func strokeLine(fromX x0: Double, _ y0: Double, toX x1: Double, _ y1: Double) {
        move(to: x0, y0)
        line(to: x1, y1)
        stroke()
    }

    /// Fill a rectangle with the current fill colour.
    public mutating func fillRect(x: Double, y: Double, width: Double, height: Double) {
        rect(x: x, y: y, width: width, height: height)
        fill()
    }

    /// Stroke a rectangle with the current stroke colour and width.
    public mutating func strokeRect(x: Double, y: Double, width: Double, height: Double) {
        rect(x: x, y: y, width: width, height: height)
        stroke()
    }

    // MARK: Text

    /// Draw `string` with its baseline origin at (x, y), in the current fill colour.
    ///
    /// The text is encoded to WinAnsi (unsupported characters become "?", `(`, `)` and `\` are
    /// escaped). `rotationDegrees` turns it counter-clockwise about the origin.
    /// `characterSpacing` (points) is added after every glyph.
    public mutating func text(_ string: String, x: Double, y: Double, font: PDFFont = .helvetica,
                              size: Double, rotationDegrees: Double = 0, characterSpacing: Double = 0) {
        guard size.isFinite, size > 0, x.isFinite, y.isFinite else { return }
        let bytes = WinAnsiEncoding.encode(string)
        guard !bytes.isEmpty else { return }
        let radians = (rotationDegrees.isFinite ? rotationDegrees : 0) * Double.pi / 180
        let (c, s) = (cos(radians), sin(radians))
        content += "BT\n/\(font.resourceName) \(PDFSyntax.number(size)) Tf\n"
        content += "\(PDFSyntax.number(c)) \(PDFSyntax.number(s)) \(PDFSyntax.number(-s)) "
            + "\(PDFSyntax.number(c)) \(PDFSyntax.number(x)) \(PDFSyntax.number(y)) Tm\n"
        let spaced = characterSpacing.isFinite && characterSpacing != 0
        if spaced { content += "\(PDFSyntax.number(characterSpacing)) Tc\n" }
        content += "\(PDFSyntax.literal(bytes)) Tj\n"
        if spaced { content += "0 Tc\n" }
        content += "ET\n"
    }

    /// Width in points `string` will occupy when drawn with `text`.
    public static func textWidth(_ string: String, font: PDFFont = .helvetica, size: Double,
                                 characterSpacing: Double = 0) -> Double {
        HelveticaMetrics.width(of: string, bold: font.isBold, fontSize: size, characterSpacing: characterSpacing)
    }
}

// MARK: - Document

/// Collects pages and serialises a complete PDF 1.4 file.
///
/// Object layout (stable, so output is deterministic): 1 Catalog, 2 Pages, 3 Helvetica,
/// 4 Helvetica-Bold, 5 Info, then a Page and its content stream for each page (6/7, 8/9, ...).
public struct PDFWriter: Sendable {
    public var title: String
    public var author: String
    public var subject: String
    public var keywords: String
    public var producer: String
    public var creator: String
    /// Injected so output is reproducible; the writer never reads the clock.
    public var creationDate: Date
    public private(set) var pages: [PDFPage] = []

    public init(title: String, author: String = "", subject: String = "", keywords: String = "",
                producer: String = "NexaFix Scan", creator: String = "NexaFix Scan",
                creationDate: Date) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.producer = producer
        self.creator = creator
        self.creationDate = creationDate
    }

    public mutating func addPage(_ page: PDFPage) { pages.append(page) }

    /// Serialise the document. A document with no pages gets one blank A4 page so the file is
    /// always valid. Unbalanced `save()` calls are closed.
    public func data() -> Data {
        let pageList = pages.isEmpty ? [PDFPage(widthMM: 210, heightMM: 297)] : pages

        var out: [UInt8] = []
        var offsets: [Int] = []   // byte offset of object n at index n - 1

        func put(_ text: String) { out.append(contentsOf: Array(text.utf8)) }
        func beginObject(_ number: Int) {
            assert(number == offsets.count + 1, "objects must be written in order")
            offsets.append(out.count)
            put("\(number) 0 obj\n")
        }
        func endObject() { put("endobj\n") }

        put("%PDF-1.4\n")
        out.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])   // binary marker comment

        let firstPageObject = 6
        let kids = pageList.indices.map { "\(firstPageObject + 2 * $0) 0 R" }.joined(separator: " ")

        beginObject(1)
        put("<< /Type /Catalog /Pages 2 0 R /Lang (en-GB) >>\n")
        endObject()

        beginObject(2)
        put("<< /Type /Pages /Kids [\(kids)] /Count \(pageList.count) >>\n")
        endObject()

        for (i, font) in PDFFont.allCases.enumerated() {
            beginObject(3 + i)
            put("<< /Type /Font /Subtype /Type1 /BaseFont /\(font.rawValue) /Encoding /WinAnsiEncoding >>\n")
            endObject()
        }

        let stamp = PDFSyntax.date(creationDate)
        beginObject(5)
        put("<< /Title \(PDFSyntax.textString(title)) /Author \(PDFSyntax.textString(author)) "
            + "/Subject \(PDFSyntax.textString(subject)) /Keywords \(PDFSyntax.textString(keywords)) "
            + "/Creator \(PDFSyntax.textString(creator)) /Producer \(PDFSyntax.textString(producer)) "
            + "/CreationDate (\(stamp)) /ModDate (\(stamp)) >>\n")
        endObject()

        let resources = "<< /Font << " + PDFFont.allCases.enumerated()
            .map { "/\($0.element.resourceName) \(3 + $0.offset) 0 R" }.joined(separator: " ")
            + " >> /ProcSet [/PDF /Text] >>"

        for (i, page) in pageList.enumerated() {
            let pageObject = firstPageObject + 2 * i
            beginObject(pageObject)
            put("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(PDFSyntax.number(page.width)) "
                + "\(PDFSyntax.number(page.height))] /Resources \(resources) /Contents \(pageObject + 1) 0 R >>\n")
            endObject()

            var stream = page.content
            if page.saveDepth > 0 { stream += String(repeating: "Q\n", count: page.saveDepth) }
            let streamBytes = Array(stream.utf8)
            beginObject(pageObject + 1)
            put("<< /Length \(streamBytes.count) >>\nstream\n")
            out.append(contentsOf: streamBytes)
            put("endstream\n")
            endObject()
        }

        let xrefOffset = out.count
        put("xref\n0 \(offsets.count + 1)\n")
        put("0000000000 65535 f \n")
        for offset in offsets {
            let digits = String(offset)
            put(String(repeating: "0", count: Swift.max(0, 10 - digits.count)) + digits + " 00000 n \n")
        }

        let id = PDFWriter.fileIdentifier(of: out)
        put("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R /Info 5 0 R /ID [<\(id)> <\(id)>] >>\n")
        put("startxref\n\(xrefOffset)\n%%EOF\n")
        return Data(out)
    }

    /// 32 hex digits (128 bits) derived from the file body with two FNV-1a passes, so the same
    /// document always gets the same /ID.
    static func fileIdentifier(of bytes: [UInt8]) -> String {
        var a: UInt64 = 0xcbf29ce484222325
        var b: UInt64 = 0x84222325cbf29ce4
        for byte in bytes {
            a = (a ^ UInt64(byte)) &* 0x100000001b3
            b = (b &+ UInt64(byte)) &* 0x100000001b3
            b ^= b >> 29
        }
        func hex(_ v: UInt64) -> String {
            let h = String(v, radix: 16, uppercase: true)
            return String(repeating: "0", count: 16 - h.count) + h
        }
        return hex(a) + hex(b)
    }
}
