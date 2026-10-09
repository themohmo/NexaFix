import Foundation

// Glyph metrics for the two PDF standard-14 faces the plan renderer uses (Helvetica and
// Helvetica-Bold), plus the Unicode -> WinAnsi (Windows-1252) byte mapping that goes with
// `/Encoding /WinAnsiEncoding`. A PDF viewer substitutes its own Helvetica for these fonts, and
// the advance widths below are the Adobe core-14 AFM values, so `HelveticaMetrics.width` gives
// the width a viewer will really lay out. That is what makes centred and right-aligned text,
// ellipsis truncation and word wrapping exact. Kerning is not applied by `Tj`, so none is modelled.

/// Maps Unicode text to the single-byte WinAnsi encoding PDF viewers use for the standard fonts.
public enum WinAnsiEncoding {
    /// Byte written for any character the encoding cannot represent.
    public static let replacementByte: UInt8 = 0x3F   // "?"

    /// WinAnsi bytes 0x80...0x9F that are not Latin-1 control codes.
    private static let cp1252Specials: [UInt32: UInt8] = [
        0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86,
        0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
        0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95,
        0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
        0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    ]

    /// The WinAnsi byte for a scalar, or nil when it has no glyph in the encoding.
    ///
    /// Printable ASCII and Latin-1 (so the degree sign, plus-minus, superscripts and the
    /// multiplication sign) map straight through; the Windows-1252 extras (euro, curly quotes,
    /// en/em dash, ellipsis, bullet, trade mark ...) map to their 0x80...0x9F codes; the Unicode
    /// minus sign is written as a hyphen. Tab, line feed and carriage return become a space.
    public static func byte(for scalar: Unicode.Scalar) -> UInt8? {
        let v = scalar.value
        switch v {
        case 0x20...0x7E, 0xA0...0xFF:
            return UInt8(v)
        case 0x09, 0x0A, 0x0D:
            return 0x20
        case 0x2212:
            return 0x2D
        default:
            return cp1252Specials[v]
        }
    }

    /// Encode a string. Unsupported characters become "?"; zero-width format characters are dropped.
    public static func encode(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x200B...0x200F, 0x2060, 0xFEFF, 0xFE00...0xFE0F:
                continue
            default:
                bytes.append(byte(for: scalar) ?? replacementByte)
            }
        }
        return bytes
    }
}

/// Advance widths and vertical metrics of Helvetica and Helvetica-Bold.
public enum HelveticaMetrics {
    /// Cap height, as a fraction of the font size (AFM `CapHeight` 718).
    public static let capHeight = 0.718
    /// Ascender, fraction of the font size.
    public static let ascender = 0.718
    /// Descender magnitude, fraction of the font size (AFM `Descender` -207).
    public static let descender = 0.207

    /// Advance width in 1/1000 em of a WinAnsi byte. Bytes below 32 have no glyph and report 0.
    public static func advance(ofByte byte: UInt8, bold: Bool) -> Int {
        guard byte >= 32 else { return 0 }
        let index = Int(byte) - 32
        return bold ? boldWidths[index] : regularWidths[index]
    }

    /// Width in points of `text` set at `fontSize` points, with optional extra `characterSpacing`
    /// (points, the PDF `Tc` operator) added after every glyph.
    public static func width(of text: String, bold: Bool = false, fontSize: Double,
                             characterSpacing: Double = 0) -> Double {
        let bytes = WinAnsiEncoding.encode(text)
        guard !bytes.isEmpty, fontSize.isFinite else { return 0 }
        var units = 0
        for b in bytes { units += advance(ofByte: b, bold: bold) }
        return Double(units) / 1000 * fontSize + characterSpacing * Double(bytes.count)
    }

    /// `text` shortened with "..." so it is no wider than `maxWidth` points. Returns `text`
    /// unchanged when it already fits, and "" when even the ellipsis does not fit.
    public static func truncated(_ text: String, toWidth maxWidth: Double, bold: Bool = false,
                                 fontSize: Double) -> String {
        if width(of: text, bold: bold, fontSize: fontSize) <= maxWidth { return text }
        let ellipsis = "..."
        if width(of: ellipsis, bold: bold, fontSize: fontSize) > maxWidth { return "" }
        var chars = Array(text)
        while !chars.isEmpty {
            chars.removeLast()
            while let last = chars.last, last == " " { chars.removeLast() }
            let candidate = String(chars) + ellipsis
            if width(of: candidate, bold: bold, fontSize: fontSize) <= maxWidth { return candidate }
        }
        return ellipsis
    }

    /// Greedy word wrap into lines no wider than `maxWidth` points. A single word wider than the
    /// line is truncated with an ellipsis rather than overflowing.
    public static func wrapped(_ text: String, maxWidth: Double, bold: Bool = false,
                               fontSize: Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if width(of: candidate, bold: bold, fontSize: fontSize) <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = truncated(String(word), toWidth: maxWidth, bold: bold, fontSize: fontSize)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: Tables

    // Adobe core-14 AFM advance widths for WinAnsi codes 32...255, 16 per row. Codes with no glyph
    // in WinAnsi (0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D) show as a bullet in viewers and are listed as 350.

    static let regularWidths: [Int] = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,  // 0x20
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,  // 0x30
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,  // 0x40
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,  // 0x50
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,  // 0x60
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 350,  // 0x70
        556, 350, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,  // 0x80
        350, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 350, 500, 667,  // 0x90
        278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,  // 0xA0
        400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,  // 0xB0
        667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,  // 0xC0
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,  // 0xD0
        556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,  // 0xE0
        556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,  // 0xF0
    ]

    static let boldWidths: [Int] = [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,  // 0x20
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,  // 0x30
        975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,  // 0x40
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,  // 0x50
        333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,  // 0x60
        611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 350,  // 0x70
        556, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,  // 0x80
        350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 350, 500, 667,  // 0x90
        278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333,  // 0xA0
        400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,  // 0xB0
        722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,  // 0xC0
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,  // 0xD0
        556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278,  // 0xE0
        611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556,  // 0xF0
    ]
}
