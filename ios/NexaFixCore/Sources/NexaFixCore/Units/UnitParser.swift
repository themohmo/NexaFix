import Foundation

/// Turns what a person types after reading a laser meter or a tape into metres.
///
/// The parser is deliberately strict: a wrong number that parses is worse than a
/// rejected one, because joinery is cut from these values. It returns `nil` rather than guess.
///
/// Accepted input (case-insensitive, any amount of spacing):
/// ```
/// 3245   3245mm   3.245 m   3,245 m   324.5cm   127 in   127"   10'   10' 7"   10'7 3/4"
/// 10 ft 7 in   7 3/4"   10ft   1/2   10'-7"   3 245 mm   3 m 24 cm 5 mm
/// ```
///
/// Rules:
/// - **Decimal separator.** A comma is ALWAYS a decimal separator, exactly like a full stop:
///   `3,245` is 3.245 (not 3245). A number containing two separators (`3,245.5`, `1,000,000`)
///   is rejected rather than guessed. The Arabic decimal separator is treated the same way.
/// - **Spaces.** A single space between a group of 1-3 digits and a group of exactly three
///   digits is a thousands separator (`3 245` is 3245); anywhere else spaces only separate
///   tokens. No-break and thin spaces count as spaces.
/// - **Bare numbers** use `defaultUnit`. For `.feetAndInches` a bare number is feet and for
///   `.inches` it is inches. A bare number never follows a unit, with one exception: after
///   a feet part a trailing bare number is inches (`10' 7` is 10 ft 7 in).
/// - **Units** (`mm cm m in ft`, their long spellings `metre(s)`, `meter(s)`, `inch(es)`,
///   `foot`/`feet`, plus `'` for feet and `"` for inches) may be written with a trailing full
///   stop (`in.`). Typographic quotes from phone keyboards (`’ ” ′ ″`) and two apostrophes (`''`)
///   mean the same as `'` and `"`.
/// - **Fractions** are whole-number numerators and denominators: `1/2`, `7 3/4`, `7-3/4`.
///   The vulgar fractions `½ ¼ ¾ ⅛ ⅜ ⅝ ⅞` are accepted too. A zero denominator is rejected.
/// - **Compound lengths** chain parts of ONE system in strictly descending order:
///   metric `m` then `cm` then `mm` (`3 m 24 cm 5 mm`), imperial `ft` then `in`
///   (`10 ft 7 in`, `10'-7 3/4"`). Mixing systems (`3m 2cm 4in`), repeating a unit
///   (`3m 2m`) or going up (`7 in 2 ft`) is rejected.
///   - **Each part after the first must be smaller than what carries into the part before it:**
///     inches below 12 after feet, centimetres below 100 after metres, millimetres below 10 after
///     centimetres and below 1000 after metres. `10' 75` (a mistyped `10' 7.5"`), `10' 71/2"`
///     (a missing space), `3 m 150 cm` and `3 m 2000 mm` are rejected, never read as a longer length.
///     A part that stands alone or leads is not limited: `127"` and `150 cm` are fine.
///   - **Only the last part may be fractional or decimal** (`10 ft 7.5 in`); `10.5' 7"` has no
///     sensible reading and is rejected.
///   - An architectural hyphen after the foot mark (`10'-7"`, `10' - 7"`) must be spaced the same
///     on both sides. A hyphen touching only the number (`10' -7"`) is a minus sign and is rejected.
/// - **Digits** may be Western or Arabic-Indic.
/// - **Invisible formatting characters** (direction marks, zero-width spaces, a byte-order mark and
///   the rest of Unicode category Cf) are dropped before parsing, because numbers pasted from
///   WhatsApp, Notes or an Arabic keyboard often carry them.
/// - Rejected: empty text, zero (unless `allowZero`), negative or `+`-signed numbers, a number
///   ending in a separator (`5.`), anything that is not a number with a recognised unit
///   (`abc`, `1e3`, `inf`, `nan`), a unit with no number, input over 120 characters, any
///   result over `maximumLengthMetres` and any non-zero result under `minimumLengthMetres`.
///
/// A parsed value says nothing about plausibility: `3,245` typed into a millimetre field is
/// 3.245 mm. Callers that want a safety net can compare against `suspiciouslySmallMetres`.
public enum UnitParser {

    /// Lengths above this many metres are rejected (a typo, not a room).
    public static let maximumLengthMetres = 200.0

    /// A result below this many metres (1 cm) is legal but probably a unit mistake;
    /// UI can ask the user to confirm.
    public static let suspiciouslySmallMetres = 0.01

    /// Non-zero lengths below this many metres (0.1 mm) are rejected: no tape or laser reads
    /// that, so such a number is a unit slip. Zero is decided by `allowZero` alone.
    public static let minimumLengthMetres = 0.0001

    /// Whether `metres` is a length a person could have measured: finite, no more than
    /// `maximumLengthMetres`, and either at least `minimumLengthMetres` or exactly zero with
    /// `allowZero`. The parser and `Room.setVerification(_:for:)` both use this, so a value the
    /// parser accepts is never refused by the model, and one the parser refuses cannot reach the
    /// model by another route.
    public static func isPlausibleLength(_ metres: Double, allowZero: Bool = false) -> Bool {
        guard metres.isFinite else { return false }
        if metres == 0 { return allowZero }
        // A relative slack of 1e-9 keeps "0.1 mm" (0.1 / 1000 is not exactly 0.0001) legal.
        return metres >= minimumLengthMetres * (1 - 1e-9) && metres <= maximumLengthMetres
    }

    /// Input longer than this many characters is rejected without parsing.
    private static let maximumInputLength = 120

    // MARK: Public API

    /// Parse a length typed by a person. Returns METRES, or nil when the text is not a clear,
    /// positive length no larger than `maximumLengthMetres`. See the type documentation for the grammar.
    public static func parseLength(_ text: String, defaultUnit: LengthUnit) -> Double? {
        parseLength(text, defaultUnit: defaultUnit, allowZero: false)
    }

    /// As `parseLength(_:defaultUnit:)`, optionally accepting exactly zero. Needed for fields
    /// where 0 is a real answer, such as the sill height of a door.
    public static func parseLength(_ text: String, defaultUnit: LengthUnit, allowZero: Bool) -> Double? {
        guard var cursor = normalise(text) else { return nil }
        let bare: UnitParserDimension
        switch defaultUnit {
        case .millimetres: bare = .millimetre
        case .centimetres: bare = .centimetre
        case .metres: bare = .metre
        case .inches: bare = .inch
        case .feetAndInches: bare = .foot
        }

        var segments: [(value: Double, unit: UnitParserDimension?)] = []
        var pendingSeparator = false
        while !cursor.atEnd {
            guard let value = cursor.scanQuantity() else { return nil }
            pendingSeparator = false
            cursor.skipSpaces()
            var unit: UnitParserDimension?
            if let ch = cursor.peek {
                if ch == "'" {
                    unit = .foot
                    cursor.advance()
                } else if ch == "\"" {
                    unit = .inch
                    cursor.advance()
                } else if ch.isLetter {
                    guard let found = UnitParserDimension(word: cursor.takeLetters()) else { return nil }
                    unit = found
                    if cursor.peek == "." { cursor.advance() }   // "in." / "ft."
                } else {
                    return nil
                }
            }
            segments.append((value, unit))
            let spaceBeforeHyphen = cursor.peek == " "
            cursor.skipSpaces()
            // Architectural style 10'-7": a hyphen may follow a feet mark, spaced the same on both
            // sides. "10' -7" has a minus sign on the number, which is never a length.
            if unit == .foot, cursor.peek == "-" {
                cursor.advance()
                let spaceAfterHyphen = cursor.peek == " "
                guard spaceBeforeHyphen == spaceAfterHyphen else { return nil }
                cursor.skipSpaces()
                pendingSeparator = true
            }
        }
        if pendingSeparator || segments.isEmpty { return nil }

        var total = 0.0
        if segments.count == 1 {
            total = (segments[0].unit ?? bare).metres(segments[0].value)
        } else {
            var previous: UnitParserDimension?
            for (index, segment) in segments.enumerated() {
                var unit = segment.unit
                if unit == nil {
                    // Only "10' 7": a bare final number straight after a feet part is inches.
                    guard index == segments.count - 1, index >= 1, segments[index - 1].unit == .foot else {
                        return nil
                    }
                    unit = .inch
                }
                guard let u = unit else { return nil }
                if let p = previous {
                    guard p.isMetric == u.isMetric, u.rank < p.rank else { return nil }
                    // The part must not reach a whole unit of the one before it: "10' 75" is a
                    // typo for 10' 7.5", not 16 ft 3 in, and "3 m 150 cm" is not 4.5 m.
                    guard let carry = u.countPer(p), segment.value < carry else { return nil }
                }
                // Every part but the last carries a whole number ("10.5' 7" has no sensible reading).
                if index < segments.count - 1, segment.value != segment.value.rounded(.towardZero) {
                    return nil
                }
                previous = u
                total += u.metres(segment.value)
            }
        }

        return isPlausibleLength(total, allowZero: allowZero) ? total : nil
    }

    /// Parse an angle in degrees: `90`, `90.5`, `90,5`, `90.5 deg`, `90.5 degrees`, `90.5\u{00B0}`.
    /// Returns nil unless 0 < angle < 360.
    public static func parseAngle(_ text: String) -> Double? {
        guard var cursor = normalise(text) else { return nil }
        guard let value = cursor.scanPlainDecimal() else { return nil }
        cursor.skipSpaces()
        if let ch = cursor.peek {
            if ch == "\u{00B0}" {
                cursor.advance()
            } else if ch.isLetter {
                let word = cursor.takeLetters()
                guard ["deg", "degs", "degree", "degrees"].contains(word) else { return nil }
                if cursor.peek == "." { cursor.advance() }
            } else {
                return nil
            }
        }
        cursor.skipSpaces()
        guard cursor.atEnd, value.isFinite, value > 0, value < 360 else { return nil }
        return value
    }

    // MARK: Normalisation

    /// Drops invisible formatting characters, lower-cases, maps typographic punctuation, vulgar
    /// fractions and Arabic-Indic digits to ASCII, collapses whitespace to single spaces and trims.
    /// nil for over-long input (measured as pasted, invisible characters included).
    private static func normalise(_ text: String) -> UnitParserCursor? {
        guard text.count <= maximumInputLength else { return nil }
        // Drop Unicode "format" characters (LRM, RLM, ALM, ZWSP, ZWJ, BOM, bidi embeddings and
        // isolates, soft hyphen ...) on SCALARS, before grapheme clustering: ZWJ and ZWNJ would
        // otherwise glue themselves to the digit before them and make it look like another character.
        let visible = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }))
        var out: [Character] = []
        out.reserveCapacity(visible.count + 4)
        for ch in visible {
            if ch.isWhitespace {
                out.append(" ")
                continue
            }
            if let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 {
                let v = scalar.value
                switch v {
                case 0x0660...0x0669:
                    out.append(Character(UnicodeScalar(UInt8(48 + v - 0x0660))))
                    continue
                case 0x06F0...0x06F9:
                    out.append(Character(UnicodeScalar(UInt8(48 + v - 0x06F0))))
                    continue
                case 0x066B:                       // Arabic decimal separator
                    out.append(",")
                    continue
                default:
                    break
                }
            }
            switch ch {
            case "\u{2018}", "\u{2019}", "\u{2032}", "\u{02B9}", "\u{00B4}", "`":
                out.append("'")
            case "\u{201C}", "\u{201D}", "\u{2033}", "\u{02BA}":
                out.append("\"")
            case "\u{00BA}", "\u{02DA}":
                out.append("\u{00B0}")
            case "\u{00BD}": out.append(contentsOf: " 1/2 ")
            case "\u{00BC}": out.append(contentsOf: " 1/4 ")
            case "\u{00BE}": out.append(contentsOf: " 3/4 ")
            case "\u{215B}": out.append(contentsOf: " 1/8 ")
            case "\u{215C}": out.append(contentsOf: " 3/8 ")
            case "\u{215D}": out.append(contentsOf: " 5/8 ")
            case "\u{215E}": out.append(contentsOf: " 7/8 ")
            default:
                if ch.isLetter {
                    out.append(contentsOf: Array(ch.lowercased()))
                } else {
                    out.append(ch)
                }
            }
        }
        // Two apostrophes are the inch mark.
        var merged: [Character] = []
        merged.reserveCapacity(out.count)
        var i = 0
        while i < out.count {
            if out[i] == "'", i + 1 < out.count, out[i + 1] == "'" {
                merged.append("\"")
                i += 2
            } else {
                merged.append(out[i])
                i += 1
            }
        }
        // Collapse runs of spaces, trim both ends.
        var collapsed: [Character] = []
        collapsed.reserveCapacity(merged.count)
        for ch in merged {
            if ch == " " {
                if collapsed.isEmpty || collapsed.last == " " { continue }
            }
            collapsed.append(ch)
        }
        if collapsed.last == " " { collapsed.removeLast() }
        return UnitParserCursor(collapsed)
    }
}

// MARK: - Units

private enum UnitParserDimension {
    case millimetre, centimetre, metre, inch, foot

    init?(word: String) {
        switch word {
        case "mm", "millimetre", "millimetres", "millimeter", "millimeters": self = .millimetre
        case "cm", "centimetre", "centimetres", "centimeter", "centimeters": self = .centimetre
        case "m", "mtr", "mtrs", "metre", "metres", "meter", "meters": self = .metre
        case "in", "inch", "inches": self = .inch
        case "ft", "foot", "feet": self = .foot
        default: return nil
        }
    }

    var isMetric: Bool {
        switch self {
        case .millimetre, .centimetre, .metre: return true
        case .inch, .foot: return false
        }
    }

    /// Larger is a bigger unit within its system.
    var rank: Int {
        switch self {
        case .millimetre, .inch: return 1
        case .centimetre, .foot: return 2
        case .metre: return 3
        }
    }

    /// How many of this unit make one `larger` unit of the same system: 100 cm to a metre,
    /// 1000 mm to a metre, 10 mm to a centimetre, 12 in to a foot. nil for a pair that is not a
    /// smaller unit under a larger one of the same system.
    func countPer(_ larger: UnitParserDimension) -> Double? {
        switch (larger, self) {
        case (.metre, .centimetre): return 100
        case (.metre, .millimetre): return 1000
        case (.centimetre, .millimetre): return 10
        case (.foot, .inch): return 12
        default: return nil
        }
    }

    func metres(_ value: Double) -> Double {
        switch self {
        case .millimetre: return value / 1000
        case .centimetre: return value / 100
        case .metre: return value
        case .inch: return value * UnitFormatter.metresPerInch
        case .foot: return value * UnitFormatter.metresPerFoot
        }
    }
}

// MARK: - UnitParserCursor

private extension Character {
    var isUnitParserDigit: Bool {
        guard let a = asciiValue else { return false }
        return a >= 48 && a <= 57
    }
}

/// A tiny hand-written scanner over normalised text.
private struct UnitParserCursor {
    let chars: [Character]
    var index = 0

    init(_ chars: [Character]) { self.chars = chars }

    var atEnd: Bool { index >= chars.count }
    var peek: Character? { index < chars.count ? chars[index] : nil }
    mutating func advance() { index += 1 }

    mutating func skipSpaces() {
        while index < chars.count, chars[index] == " " { index += 1 }
    }

    mutating func readDigits() -> String {
        var s = ""
        while index < chars.count, chars[index].isUnitParserDigit {
            s.append(chars[index])
            index += 1
        }
        return s
    }

    mutating func takeLetters() -> String {
        var s = ""
        while index < chars.count, chars[index].isLetter {
            s.append(chars[index])
            index += 1
        }
        return s
    }

    /// " 245" where exactly three digits follow one space and are not the numerator of a fraction.
    mutating func takeThousandsGroup() -> String? {
        var j = index
        guard j < chars.count, chars[j] == " " else { return nil }
        j += 1
        var digits = ""
        while j < chars.count, chars[j].isUnitParserDigit {
            digits.append(chars[j])
            j += 1
        }
        guard digits.count == 3 else { return nil }
        if j < chars.count, chars[j] == "/" { return nil }
        index = j
        return digits
    }

    /// " 3/4" or "-3/4" straight after a whole number.
    mutating func takeFractionTail() -> Double? {
        var j = index
        guard j < chars.count, chars[j] == " " || chars[j] == "-" else { return nil }
        j += 1
        var num = ""
        while j < chars.count, chars[j].isUnitParserDigit {
            num.append(chars[j])
            j += 1
        }
        guard !num.isEmpty, j < chars.count, chars[j] == "/" else { return nil }
        j += 1
        var den = ""
        while j < chars.count, chars[j].isUnitParserDigit {
            den.append(chars[j])
            j += 1
        }
        guard num.count <= 12, den.count <= 12,
              let n = Double(num), let d = Double(den), d > 0 else { return nil }
        index = j
        return n / d
    }

    /// digits [sep digits] with sep "." or ",". No thousands groups, no fractions.
    mutating func scanPlainDecimal() -> Double? {
        let whole = readDigits()
        var text = whole
        if let ch = peek, ch == "." || ch == "," {
            advance()
            let frac = readDigits()
            guard !frac.isEmpty else { return nil }
            text = (whole.isEmpty ? "0" : whole) + "." + frac
            if let n = peek, n == "." || n == "," { return nil }
        } else if whole.isEmpty {
            return nil
        }
        guard text.count <= 40 else { return nil }
        return Double(text)
    }

    /// One quantity of a length: decimal, thousands-grouped integer, fraction or mixed number.
    mutating func scanQuantity() -> Double? {
        var whole = readDigits()
        var grouped = false
        if !whole.isEmpty, whole.count <= 3 {
            while let group = takeThousandsGroup() {
                whole += group
                grouped = true
            }
        }
        guard whole.count <= 40 else { return nil }

        if let ch = peek, ch == "." || ch == "," {
            advance()
            let frac = readDigits()
            guard !frac.isEmpty, frac.count <= 40 else { return nil }
            if let n = peek, n == "." || n == "," { return nil }
            return Double((whole.isEmpty ? "0" : whole) + "." + frac)
        }
        guard !whole.isEmpty, let w = Double(whole) else { return nil }
        if grouped { return w }

        if peek == "/" {
            advance()
            let den = readDigits()
            guard den.count <= 12, let d = Double(den), d > 0 else { return nil }
            return w / d
        }
        if let f = takeFractionTail() { return w + f }
        return w
    }
}
