import Foundation

// Low-level building blocks for the DXF exporter: the group-code writer, number and text
// encoding, handle allocation, colour and lineweight mapping. Nothing here knows about
// floor plans; `DXFExporter` composes these into a drawing.
//
// Everything produced is 7-bit ASCII so the same string is valid whether the caller saves it as
// UTF-8 or Windows-1252 (the code page declared in the header). Non-ASCII text is written as AutoCAD
// control codes (`%%d`, `%%p`, `%%c`) or `\U+XXXX` escapes, which every DXF reader understands.

// MARK: - Handles

/// Hands out unique, ascending DXF handles (hexadecimal, upper case, never "0").
struct DXFHandleAllocator {
    private(set) var nextValue: Int

    init(first: Int = 1) { nextValue = Swift.max(1, first) }

    mutating func allocate() -> String {
        defer { nextValue += 1 }
        return String(nextValue, radix: 16, uppercase: true)
    }

    /// Value for `$HANDSEED`: the first handle that has not been handed out.
    var seed: String { String(nextValue, radix: 16, uppercase: true) }
}

// MARK: - Tag writer

/// A group value, expressible by literal so fixed records read like the DXF reference.
enum DXFValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    case text(String)
    case integer(Int)
    case real(Double)

    init(stringLiteral value: String) { self = .text(value) }
    init(integerLiteral value: Int) { self = .integer(value) }
    init(floatLiteral value: Double) { self = .real(value) }
}

/// Appends DXF group-code/value pairs to a string. Group codes are right-aligned in three columns
/// the way AutoCAD writes them; line endings are LF by default or CRLF on request.
struct DXFWriter {
    private(set) var output: String = ""
    private let newline: String

    init(windowsLineEndings: Bool = false) {
        newline = windowsLineEndings ? "\r\n" : "\n"
    }

    /// A string value. Line breaks are replaced and non-ASCII scalars escaped, so a caller can
    /// never inject a group or break the file structure with odd input.
    mutating func tag(_ code: Int, _ value: String) {
        writeCode(code)
        output += DXFFormat.safeLine(value)
        output += newline
    }

    mutating func tag(_ code: Int, _ value: Int) {
        writeCode(code)
        output += String(value)
        output += newline
    }

    mutating func tag(_ code: Int, _ value: Double) {
        writeCode(code)
        output += DXFFormat.number(value)
        output += newline
    }

    /// A 2D or 3D point: groups `code`, `code + 10` and (when `z` is given) `code + 20`.
    mutating func point(_ x: Double, _ y: Double, _ z: Double? = nil, code: Int = 10) {
        tag(code, x)
        tag(code + 10, y)
        if let z = z { tag(code + 20, z) }
    }

    mutating func beginSection(_ name: String) {
        tag(0, "SECTION")
        tag(2, name)
    }

    mutating func endSection() {
        tag(0, "ENDSEC")
    }

    /// Several groups at once; keeps long, fixed records (tables, header) compact.
    mutating func tags(_ pairs: [(Int, DXFValue)]) {
        for (code, value) in pairs {
            switch value {
            case .text(let s): tag(code, s)
            case .integer(let i): tag(code, i)
            case .real(let d): tag(code, d)
            }
        }
    }

    /// Append text that was produced by another writer with the same line-ending style.
    mutating func append(_ other: DXFWriter) {
        output += other.output
    }

    private mutating func writeCode(_ code: Int) {
        let digits = String(code)
        if digits.utf8.count < 3 { output += String(repeating: " ", count: 3 - digits.utf8.count) }
        output += digits
        output += newline
    }
}

// MARK: - Number and text encoding

enum DXFFormat {
    /// Largest coordinate magnitude the exporter will write, in drawing units. Anything beyond is
    /// treated as corrupt input and the entity is skipped (AutoCAD itself stores 1e20 as "unset").
    static let maxCoordinate = 1e12

    /// A real number as plain decimal text: never exponent notation, never locale dependent, at
    /// most nine decimals, trailing zeros trimmed but one decimal kept ("12.0"), no "-0.0".
    /// Non-finite values (which callers filter out beforehand) are written as zero.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        var text = String(format: "%.9f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text += "0" }
        return text == "-0.0" ? "0.0" : text
    }

    /// Replace line breaks and control characters with a space and escape non-ASCII scalars as
    /// `\U+XXXX` (UTF-16 surrogate pairs above U+FFFF). Used for every string value.
    static func safeLine(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x20...0x7E: out.unicodeScalars.append(scalar)
            case 0x00...0x1F, 0x7F: out += " "
            default: out += unicodeEscape(scalar)
            }
        }
        return out
    }

    /// Encode text for a TEXT entity (group 1).
    ///
    /// - U+00B0 degree sign  -> `%%d`, U+00B1 plus-minus -> `%%p`, U+2300 diameter / U+2205 -> `%%c`
    ///   (the AutoCAD text control codes, understood by AutoCAD, BricsCAD, LibreCAD, Rhino and ezdxf).
    /// - every other non-ASCII character (m with U+00B2 superscript two, en dash, ...) -> `\U+XXXX`.
    /// - a literal `%` that would be read as part of a control code is written as `%%037`.
    /// - a backslash is written as `\U+005C` so it cannot start an accidental escape.
    /// - tabs and line breaks become spaces (a TEXT entity is a single line).
    /// - the result is cut to `maxLength` characters (the DXF limit is 255) on an escape boundary.
    static func text(_ source: String, maxLength: Int = 255) -> String {
        let scalars = Array(source.unicodeScalars)
        var tokens: [String] = []
        tokens.reserveCapacity(scalars.count)
        for (i, scalar) in scalars.enumerated() {
            switch scalar.value {
            case 0x00B0: tokens.append("%%d")
            case 0x00B1: tokens.append("%%p")
            case 0x2300, 0x2205: tokens.append("%%c")
            case 0x25: // "%"
                let previousIsPercent = i > 0 && scalars[i - 1].value == 0x25
                let next = i + 1 < scalars.count ? scalars[i + 1].value : 0
                let nextIsControl = next == 0x25 || next == 0x00B0 || next == 0x00B1 || next == 0x2300
                    || next == 0x2205
                tokens.append(previousIsPercent || nextIsControl ? "%%037" : "%")
            case 0x5C: tokens.append("\\U+005C")
            case 0x20...0x7E: tokens.append(String(scalar))
            case 0x00...0x1F, 0x7F: tokens.append(" ")
            default: tokens.append(unicodeEscape(scalar))
            }
        }
        var out = ""
        var length = 0
        for token in tokens {
            if length + token.utf8.count > maxLength { break }
            out += token
            length += token.utf8.count
        }
        return out
    }

    private static func unicodeEscape(_ scalar: Unicode.Scalar) -> String {
        func hex4(_ v: UInt32) -> String {
            let s = String(v, radix: 16, uppercase: true)
            return "\\U+" + String(repeating: "0", count: Swift.max(0, 4 - s.count)) + s
        }
        let v = scalar.value
        if v <= 0xFFFF { return hex4(v) }
        let offset = v - 0x10000
        return hex4(0xD800 + (offset >> 10)) + hex4(0xDC00 + (offset & 0x3FF))
    }
}

// MARK: - Colour

/// Mapping from plan colours to AutoCAD Color Index (ACI) numbers and true-colour integers.
///
/// Only the ACI entries whose RGB value is the same in every common palette table are candidates
/// (the six pure colours, the full-brightness and 50% pastel hue ramps, the darker hue ramps, the
/// 250-255 grey ramp). ACI 8 and 9 are excluded because applications disagree on their brightness.
/// Black maps to ACI 7, which AutoCAD shows black on a light background and white on a dark one;
/// white maps to ACI 255, which is always white.
enum DXFColor {
    /// (ACI index, red, green, blue) candidates, built once.
    static let candidates: [(index: Int, r: Int, g: Int, b: Int)] = {
        var list: [(index: Int, r: Int, g: Int, b: Int)] = [
            (1, 255, 0, 0), (2, 255, 255, 0), (3, 0, 255, 0), (4, 0, 255, 255), (5, 0, 0, 255),
            (6, 255, 0, 255), (7, 0, 0, 0),
        ]
        // 24 hues, 15 degrees apart, from red through yellow, green, cyan, blue and magenta. Each
        // hue owns ten ACI numbers: 10 + 10 * hue + variant.
        let ramp = [0, 63, 127, 191, 255]
        for hue in 0..<24 {
            let step = hue % 4
            let up = ramp[step], down = ramp[4 - step]
            let base: (Int, Int, Int)
            switch hue / 4 {
            case 0: base = (255, up, 0)
            case 1: base = (down, 255, 0)
            case 2: base = (0, 255, up)
            case 3: base = (0, down, 255)
            case 4: base = (up, 0, 255)
            default: base = (255, 0, down)
            }
            let channels = [base.0, base.1, base.2]
            func scaled(_ level: Int) -> [Int] {
                channels.map { Int((Double($0) * Double(level) / 255).rounded()) }
            }
            func towardsLevel(_ c: [Int], _ level: Int) -> [Int] { c.map { $0 + (level - $0) / 2 } }
            let full = channels, pastel = towardsLevel(full, 255)
            let half = scaled(127), halfPastel = towardsLevel(half, 127)
            let dark = scaled(76), darkPastel = towardsLevel(dark, 76)
            for (variant, c) in [(0, full), (1, pastel), (4, half), (5, halfPastel), (6, dark), (7, darkPastel)] {
                list.append((10 + hue * 10 + variant, c[0], c[1], c[2]))
            }
        }
        list.append((250, 51, 51, 51))
        list.append((251, 91, 91, 91))
        list.append((252, 132, 132, 132))
        list.append((253, 173, 173, 173))
        list.append((254, 214, 214, 214))
        list.append((255, 255, 255, 255))
        return list
    }()

    /// Red, green and blue (0...255) of a candidate ACI number, nil for indices that are not candidates.
    static func rgb(ofACI index: Int) -> (r: Int, g: Int, b: Int)? {
        guard let c = candidates.first(where: { $0.index == index }) else { return nil }
        return (c.r, c.g, c.b)
    }

    /// Components clamped to 0...255 (NaN counts as 0).
    static func bytes(_ color: DrawColor) -> (r: Int, g: Int, b: Int) {
        func byte(_ v: Double) -> Int {
            guard v.isFinite else { return 0 }
            return Int((Swift.min(1, Swift.max(0, v)) * 255).rounded())
        }
        return (byte(color.r), byte(color.g), byte(color.b))
    }

    /// The ACI number whose colour is closest (Euclidean distance in RGB, ties to the lower index).
    static func nearestACI(_ color: DrawColor) -> Int {
        let c = bytes(color)
        var best = 7
        var bestDistance = Int.max
        for candidate in candidates {
            let dr = candidate.r - c.r, dg = candidate.g - c.g, db = candidate.b - c.b
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = candidate.index
            }
        }
        return best
    }

    /// 24-bit RGB for group 420.
    static func trueColor(_ color: DrawColor) -> Int {
        let c = bytes(color)
        return (c.r << 16) | (c.g << 8) | c.b
    }
}

// MARK: - Lineweight

/// DXF lineweights are integers in hundredths of a millimetre, restricted to a fixed list.
enum DXFLineweight {
    static let valid: [Int] = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120,
                               140, 158, 200, 211]

    /// The valid lineweight nearest to `millimetres` on paper (ties go to the thinner one);
    /// nil when the weight is negative or not a number, so the caller falls back to the layer's.
    static func nearest(toMillimetres millimetres: Double) -> Int? {
        guard millimetres.isFinite, millimetres >= 0 else { return nil }
        let hundredths = millimetres * 100
        var best = valid[0]
        var bestDistance = Double.infinity
        for candidate in valid {
            let distance = abs(Double(candidate) - hundredths)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
