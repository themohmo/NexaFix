import Foundation

// File names for everything the app exports or shares, plus the small date helpers the data
// exporters and the property store share.
//
// Names look like `NexaFix_Marina-Gate-2304_2026-10-09_scan.json`. Only ASCII letters, digits,
// `-`, `_` and `.` ever appear, so the same name is valid on iOS, macOS, Windows (Excel, email
// gateways), WhatsApp and AirDrop. Nothing here reads the clock or the current time zone: the
// caller passes the date (and, optionally, the zone).

/// Builds filesystem-safe export file names and avoids collisions.
public enum ExportNaming {

    /// Every export starts with this.
    public static let prefix = "NexaFix"

    /// Dubai is UTC+04:00 all year (no daylight saving). Fixed on purpose: the date in a file
    /// name is the site date, not the date wherever the phone happens to be.
    public static let dubaiTimeZone: TimeZone = TimeZone(secondsFromGMT: 4 * 3600) ?? TimeZone.gmt

    /// Longest sanitised property / kind component, characters.
    public static let defaultMaxComponentLength = 40

    // MARK: Components

    /// Turns any user text into a short ASCII token that is safe in a file name.
    ///
    /// - Accents are folded to their base letter (`Café` -> `Cafe`), `ß`, `æ`, `ø`, `ł` and a few
    ///   other Latin letters are transliterated, `&` becomes `and`, apostrophes are dropped
    ///   (`Maid's` -> `Maids`).
    /// - Everything else that is not a letter or digit (spaces, slashes, colons, quotes, emoji,
    ///   Arabic or CJK text, control characters) collapses into a single `-`.
    /// - The result never starts or ends with `-`, is at most `maxLength` characters, and is
    ///   `fallback` when nothing usable is left (empty names, emoji-only names, Arabic-only names).
    public static func sanitizedComponent(_ raw: String, maxLength: Int = defaultMaxComponentLength,
                                          fallback: String = "Untitled") -> String {
        var out = ""
        var pendingSeparator = false

        func emit(_ s: String) {
            if pendingSeparator && !out.isEmpty { out.append("-") }
            pendingSeparator = false
            out.append(s)
        }

        // NFD splits "é" into "e" + a combining mark, which is then skipped.
        for scalar in raw.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark
                || scalar.properties.generalCategory == .spacingMark
                || scalar.properties.generalCategory == .enclosingMark {
                continue
            }
            switch scalar.value {
            case 0x27, 0x60, 0xB4, 0x2018, 0x2019, 0x201B, 0x2032, 0x02BC:   // apostrophes
                continue
            case 0x26:   // &
                pendingSeparator = !out.isEmpty
                emit("and")
                pendingSeparator = true
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                emit(String(scalar))
            default:
                if let mapped = transliterations[scalar.value] {
                    emit(mapped)
                } else {
                    pendingSeparator = true
                }
            }
        }

        let limit = max(1, maxLength)
        if out.count > limit {
            out = String(out.prefix(limit))
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? fallback : out
    }

    /// `yyyy-MM-dd` for a date in the given zone (default Dubai). No `DateFormatter`, so the
    /// result is identical on every platform and locale.
    public static func dateStamp(_ date: Date, timeZone: TimeZone = dubaiTimeZone) -> String {
        DataDates.dateStamp(date, offsetSeconds: timeZone.secondsFromGMT(for: date))
    }

    // MARK: File names

    /// `NexaFix_<Property>_<yyyy-MM-dd>_<kind>.<ext>`
    ///
    /// - `kind` is what the file is: `scan`, `costing-spec`, `floor-plan`, `rooms`, `model` ...
    ///   It is sanitised like the property name.
    /// - `ext` is lower-cased and reduced to letters and digits (`".PDF"` -> `pdf`).
    public static func fileName(propertyName: String, date: Date, kind: String, ext: String,
                                timeZone: TimeZone = dubaiTimeZone) -> String {
        let property = sanitizedComponent(propertyName, fallback: "Property")
        let kindToken = sanitizedComponent(kind, maxLength: 24, fallback: "export")
        let extToken = extensionToken(ext)
        return "\(prefix)_\(property)_\(dateStamp(date, timeZone: timeZone))_\(kindToken).\(extToken)"
    }

    public static func fileName(for property: Property, date: Date, kind: String, ext: String,
                                timeZone: TimeZone = dubaiTimeZone) -> String {
        fileName(propertyName: property.name, date: date, kind: kind, ext: ext, timeZone: timeZone)
    }

    /// A folder / archive name without extension, e.g. `NexaFix_Marina-Gate-2304_2026-10-09`.
    public static func baseName(propertyName: String, date: Date, timeZone: TimeZone = dubaiTimeZone) -> String {
        "\(prefix)_\(sanitizedComponent(propertyName, fallback: "Property"))_\(dateStamp(date, timeZone: timeZone))"
    }

    /// Lower-case alphanumeric extension without the dot; `dat` when nothing usable is left.
    public static func extensionToken(_ ext: String) -> String {
        let token = ext.lowercased().unicodeScalars
            .filter { ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x7A) }
            .map(String.init).joined()
        let clipped = String(token.prefix(8))
        return clipped.isEmpty ? "dat" : clipped
    }

    // MARK: Collisions

    /// `name` if it is free, otherwise `name-2.ext`, `name-3.ext`, ... The comparison ignores case
    /// because the iOS / macOS file system (and Windows) treat `A.pdf` and `a.pdf` as one file.
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        return uniqueName(name, isTaken: { taken.contains($0.lowercased()) })
    }

    /// Same as `uniqueName(_:existing:)` but asks the file system about `directory`.
    public static func uniqueName(_ name: String, in directory: URL, fileManager: FileManager = .default) -> String {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return uniqueName(name, existing: Set(names))
    }

    /// Core of the collision helper: `isTaken` says whether a candidate is already used.
    /// Terminates as long as `isTaken` is false for some candidate, which any finite set guarantees.
    public static func uniqueName(_ name: String, isTaken: (String) -> Bool) -> String {
        if !isTaken(name) { return name }
        let (stem, ext) = splitExtension(name)
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            if !isTaken(candidate) { return candidate }
            n += 1
        }
    }

    /// `("a.b.pdf")` -> `("a.b", "pdf")`; a leading dot alone is not an extension.
    static func splitExtension(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty, !ext.contains("/") else { return (name, "") }
        return (String(name[..<dot]), ext)
    }

    // MARK: Transliteration

    /// Letters that do not decompose into base + accent. Anything not listed here and not ASCII
    /// is treated as a separator.
    private static let transliterations: [UInt32: String] = [
        0xDF: "ss", 0x1E9E: "SS",
        0xE6: "ae", 0xC6: "AE", 0x153: "oe", 0x152: "OE",
        0xF8: "o", 0xD8: "O", 0x111: "d", 0x110: "D", 0xF0: "d", 0xD0: "D",
        0x142: "l", 0x141: "L", 0xFE: "th", 0xDE: "Th",
        0x131: "i", 0x130: "I", 0x127: "h", 0x126: "H",
    ]
}

// MARK: - Date helpers shared by the data exporters and the property store

/// Calendar arithmetic and ISO 8601 text without `DateFormatter` / `ISO8601DateFormatter`, so
/// output is byte-identical on Linux, macOS and iOS and never depends on locale or time zone.
enum DataDates {

    private static let referenceToEpoch = 978_307_200            // 2001-01-01 minus 1970-01-01, seconds
    private static let minEpoch = -62_135_596_800                // 0001-01-01T00:00:00Z
    private static let maxEpoch = 253_402_300_799                // 9999-12-31T23:59:59Z

    // MARK: Civil calendar (proleptic Gregorian; Howard Hinnant's algorithms)

    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month + (month > 2 ? -3 : 9)
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// Integer division rounding toward negative infinity (dates before 1970 have negative seconds).
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeap(year) ? 29 : 28
        }
    }

    /// Seconds since 1970 for a date, floored, clamped to years 1...9999.
    private static func epochSeconds(floorOf referenceSeconds: Double) -> Int {
        guard referenceSeconds.isFinite else { return 0 }
        let whole = referenceSeconds.rounded(.down)
        let limit = 3.0e11
        let clamped = Swift.min(Swift.max(whole, -limit), limit)
        return Swift.min(Swift.max(Int(clamped) + referenceToEpoch, minEpoch), maxEpoch)
    }

    /// `yyyy-MM-dd` after shifting by `offsetSeconds` from UTC.
    static func dateStamp(_ date: Date, offsetSeconds: Int) -> String {
        let epoch = epochSeconds(floorOf: date.timeIntervalSinceReferenceDate) + offsetSeconds
        let c = civilFromDays(floorDiv(epoch, 86_400))
        return pad(c.year, 4) + "-" + pad(c.month, 2) + "-" + pad(c.day, 2)
    }

    // MARK: ISO 8601 output

    /// `2026-10-09T10:15:30.123Z`: UTC, milliseconds (rounded). For interchange files.
    static func iso8601Millis(_ date: Date) -> String {
        let r = date.timeIntervalSinceReferenceDate
        guard r.isFinite else { return "1970-01-01T00:00:00.000Z" }
        let whole = r.rounded(.down)
        var seconds = epochSeconds(floorOf: r)
        var millis = Int(((r - whole) * 1000).rounded())
        if millis >= 1000 { seconds += 1; millis -= 1000 }
        return format(epochSeconds: seconds, fraction: pad(millis, 3))
    }

    /// UTC text that parses back to exactly the same `Date`, for storage. The fraction has 3, 6, 9
    /// or 12 digits: the shortest that survives `parse` bit-for-bit (a `Date()` from the clock
    /// normally needs 9). Dates outside years 1...9999 or non-finite are clamped, so they do not
    /// round-trip, which no real survey has.
    static func iso8601Exact(_ date: Date) -> String {
        let r = date.timeIntervalSinceReferenceDate
        guard r.isFinite else { return "1970-01-01T00:00:00.000Z" }
        let whole = r.rounded(.down)
        let frac = r - whole     // exact: both operands share the exponent range
        var last = ""
        for digits in [3, 6, 9, 12] {
            var seconds = epochSeconds(floorOf: r)
            let scale = pow10(digits)
            var scaled = Int((frac * Double(scale)).rounded())
            if scaled >= scale { seconds += 1; scaled -= scale }
            let text = format(epochSeconds: seconds, fraction: pad(scaled, digits))
            last = text
            if let back = parse(text), back.timeIntervalSinceReferenceDate == r { return text }
        }
        return last
    }

    private static func pow10(_ n: Int) -> Int {
        var v = 1
        for _ in 0..<n { v *= 10 }
        return v
    }

    private static func format(epochSeconds: Int, fraction: String) -> String {
        let days = floorDiv(epochSeconds, 86_400)
        let secondOfDay = epochSeconds - days * 86_400
        let c = civilFromDays(days)
        return pad(c.year, 4) + "-" + pad(c.month, 2) + "-" + pad(c.day, 2) + "T"
            + pad(secondOfDay / 3600, 2) + ":" + pad((secondOfDay / 60) % 60, 2) + ":" + pad(secondOfDay % 60, 2)
            + "." + fraction + "Z"
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(Swift.max(0, n))
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    // MARK: ISO 8601 input

    /// Reads `YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM|+HHMM)`. A fraction of any length is
    /// accepted. nil for anything else (including impossible dates such as February 30).
    static func parse(_ text: String) -> Date? {
        let b = Array(text.utf8)
        var i = 0

        func digits(_ count: Int) -> Int? {
            guard i + count <= b.count else { return nil }
            var v = 0
            for k in 0..<count {
                let c = b[i + k]
                guard c >= 0x30 && c <= 0x39 else { return nil }
                v = v * 10 + Int(c - 0x30)
            }
            i += count
            return v
        }
        func expect(_ chars: [UInt8]) -> Bool {
            guard i < b.count, chars.contains(b[i]) else { return false }
            i += 1
            return true
        }

        guard let year = digits(4), expect([0x2D]), let month = digits(2), expect([0x2D]), let day = digits(2),
              expect([0x54, 0x74]),
              let hour = digits(2), expect([0x3A]), let minute = digits(2), expect([0x3A]), let second = digits(2)
        else { return nil }
        guard (1...12).contains(month), year >= 1,
              (1...daysInMonth(year: year, month: month)).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }

        var fraction = 0.0
        if i < b.count, b[i] == 0x2E {
            i += 1
            let start = i
            while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
            guard i > start else { return nil }
            fraction = Double("0." + String(decoding: b[start..<i], as: UTF8.self)) ?? 0
        }

        var offset = 0
        if expect([0x5A, 0x7A]) {
            offset = 0
        } else if i < b.count, b[i] == 0x2B || b[i] == 0x2D {
            let sign = b[i] == 0x2B ? 1 : -1
            i += 1
            guard let oh = digits(2) else { return nil }
            _ = expect([0x3A])
            guard let om = digits(2), oh < 24, om < 60 else { return nil }
            offset = sign * (oh * 3600 + om * 60)
        } else {
            return nil
        }
        guard i == b.count else { return nil }

        let epoch = daysFromCivil(year: year, month: month, day: day) * 86_400
            + hour * 3600 + minute * 60 + second - offset
        // Integer seconds first, then add the fraction once: the sum is correctly rounded.
        return Date(timeIntervalSinceReferenceDate: Double(epoch - referenceToEpoch) + fraction)
    }
}
