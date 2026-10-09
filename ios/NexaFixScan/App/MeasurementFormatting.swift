import Foundation
import NexaFixCore

// How a measurement is worded: split into a number and a unit for display, spoken for VoiceOver, and
// how provenance ("Scanned" or "Verified") and check counts read. Plain Swift on Foundation and
// NexaFixCore only, so it is type-checked and unit-checked on Linux (see ios/tools/app-logic-checks).
// `MeasurementViews.swift` draws these strings.

/// What a `MeasurementText` shows.
enum MeasurementKind {
    case length, area, angle
}

/// A measurement split into the number and its unit, plus the sentence VoiceOver reads.
struct MeasurementParts: Equatable {
    /// Digits as formatted by `UnitFormatter`. For feet and inches this is the whole `10' 7 3/4"`.
    let number: String
    /// "mm", "m²", "°"... nil when the unit is part of the number (feet and inches).
    let unit: String?
    /// "3245 millimetres": full unit names, no trailing zeros, no digit grouping.
    let spoken: String

    static let unavailable = MeasurementParts(number: "\u{2013}", unit: nil, spoken: "No value")

    static func length(_ metres: Double, units: DisplayUnits) -> MeasurementParts {
        guard metres.isFinite else { return .unavailable }
        let spoken = SpokenMeasurement.length(metres, unit: units.length)
        if units.length == .feetAndInches {
            return MeasurementParts(number: UnitFormatter.length(metres, unit: .feetAndInches),
                                    unit: nil, spoken: spoken)
        }
        return MeasurementParts(number: UnitFormatter.length(metres, unit: units.length, includeUnit: false),
                                unit: units.length.symbol, spoken: spoken)
    }

    static func area(_ squareMetres: Double, units: DisplayUnits) -> MeasurementParts {
        guard squareMetres.isFinite else { return .unavailable }
        return MeasurementParts(number: UnitFormatter.area(squareMetres, unit: units.area, includeUnit: false),
                                unit: units.area.symbol,
                                spoken: SpokenMeasurement.area(squareMetres, unit: units.area))
    }

    static func angle(_ degrees: Double) -> MeasurementParts {
        guard degrees.isFinite else { return .unavailable }
        var text = UnitFormatter.angle(degrees)
        if text.hasSuffix("\u{00B0}") { text.removeLast() }
        return MeasurementParts(number: text, unit: "\u{00B0}", spoken: SpokenMeasurement.angle(degrees))
    }
}

/// Numbers and units written the way VoiceOver should say them.
enum SpokenMeasurement {
    static func length(_ metres: Double, unit: LengthUnit) -> String {
        guard metres.isFinite else { return "No value" }
        switch unit {
        case .feetAndInches:
            return feetAndInches(metres)
        case .millimetres:
            return withNoun(UnitFormatter.length(metres, unit: unit, includeUnit: false), "millimetre", "millimetres")
        case .centimetres:
            return withNoun(UnitFormatter.length(metres, unit: unit, includeUnit: false), "centimetre", "centimetres")
        case .metres:
            return withNoun(UnitFormatter.length(metres, unit: unit, includeUnit: false), "metre", "metres")
        case .inches:
            return withNoun(UnitFormatter.length(metres, unit: unit, includeUnit: false), "inch", "inches")
        }
    }

    static func area(_ squareMetres: Double, unit: AreaUnit) -> String {
        guard squareMetres.isFinite else { return "No value" }
        let digits = UnitFormatter.area(squareMetres, unit: unit, includeUnit: false)
        switch unit {
        case .squareMetres: return withNoun(digits, "square metre", "square metres")
        case .squareFeet: return withNoun(digits, "square foot", "square feet")
        }
    }

    static func angle(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "No value" }
        return withNoun(UnitFormatter.angle(degrees).replacingOccurrences(of: "\u{00B0}", with: ""),
                        "degree", "degrees")
    }

    /// "plus or minus 22 millimetres": the typical LiDAR tolerance for a scanned length.
    static func tolerance(forLength metres: Double, unit: LengthUnit) -> String {
        let tolerance = ScanAccuracy.typicalTolerance(forLength: metres)
        let spoken: String
        switch unit {
        case .feetAndInches:
            spoken = feetAndInches(tolerance, denominator: 2)
        default:
            let digits = UnitFormatter.length(tolerance, unit: unit, precision: .compact, includeUnit: false)
            spoken = withNoun(digits, singular(of: unit), plural(of: unit))
        }
        return "plus or minus " + spoken
    }

    /// "10 feet 7 and three quarters inches". Rounds to sixteenths like `UnitFormatter`.
    static func feetAndInches(_ metres: Double, denominator: Int = 16) -> String {
        guard metres.isFinite else { return "No value" }
        let bounded = min(abs(metres), 100_000)
        let steps = Int((bounded / UnitFormatter.metresPerInch * Double(denominator)).rounded())
        let wholeInches = steps / denominator
        let remainder = steps % denominator
        let feet = wholeInches / 12
        let inches = wholeInches % 12
        let sign = metres < 0 && steps != 0 ? "minus " : ""

        var parts: [String] = []
        if feet > 0 { parts.append("\(feet) \(feet == 1 ? "foot" : "feet")") }

        if remainder == 0 {
            if inches > 0 || feet == 0 { parts.append("\(inches) \(inches == 1 ? "inch" : "inches")") }
        } else {
            var n = remainder, d = denominator
            while n % 2 == 0 && d % 2 == 0 { n /= 2; d /= 2 }
            let fraction = fractionWords(n, over: d)
            if inches > 0 {
                parts.append("\(inches) and \(fraction) inches")
            } else {
                parts.append((feet > 0 ? "and " : "") + "\(fraction) of an inch")
            }
        }
        return sign + parts.joined(separator: " ")
    }

    /// "Verified with laser" read after a comma should not start with a capital letter.
    static func midSentence(_ text: String) -> String {
        guard let head = text.first else { return text }
        return head.lowercased() + String(text.dropFirst())
    }

    // MARK: helpers

    /// Drops trailing zeros ("3.200" becomes "3.2") because VoiceOver reads every zero aloud.
    static func trimmed(_ digits: String) -> String {
        guard digits.contains(".") else { return digits }
        var result = digits
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result == "-0" || result.isEmpty ? "0" : result
    }

    static func withNoun(_ digits: String, _ singular: String, _ plural: String) -> String {
        let number = trimmed(digits)
        return number + " " + (number == "1" ? singular : plural)
    }

    private static func singular(of unit: LengthUnit) -> String {
        switch unit {
        case .millimetres: return "millimetre"
        case .centimetres: return "centimetre"
        case .metres: return "metre"
        case .inches, .feetAndInches: return "inch"
        }
    }

    private static func plural(of unit: LengthUnit) -> String {
        switch unit {
        case .millimetres: return "millimetres"
        case .centimetres: return "centimetres"
        case .metres: return "metres"
        case .inches, .feetAndInches: return "inches"
        }
    }

    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
                                      "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen"]

    private static func fractionWords(_ numerator: Int, over denominator: Int) -> String {
        if numerator == 1 && denominator == 2 { return "one half" }
        let top = numerator < numberWords.count ? numberWords[numerator] : "\(numerator)"
        let bottom: String
        switch denominator {
        case 4: bottom = "quarter"
        case 8: bottom = "eighth"
        case 16: bottom = "sixteenth"
        default: bottom = "part"
        }
        return top + " " + bottom + (numerator > 1 ? "s" : "")
    }
}

/// How a `Measured` value's provenance reads, on screen and aloud.
struct ProvenanceDescription: Equatable {
    let isVerified: Bool
    /// "Laser", "Tape", "Drawing" or "Scanned".
    let shortText: String
    /// What the badge shows: "Laser", or "Scanned ±22 mm" ("Scanned" when compact).
    let visibleText: String
    /// The full sentence for VoiceOver.
    let spoken: String

    init(_ measured: Measured, units: DisplayUnits, compact: Bool) {
        if let verification = measured.verification {
            let source = verification.source
            isVerified = true
            shortText = source.displayName
            visibleText = source.displayName
            switch source {
            case .laser: spoken = "Verified with laser"
            case .tape: spoken = "Verified with tape"
            case .drawing: spoken = "Verified from drawing"
            }
        } else {
            isVerified = false
            shortText = "Scanned"
            if compact {
                visibleText = "Scanned"
            } else {
                visibleText = "Scanned \(UnitFormatter.tolerance(forLength: measured.scanned, unit: units.length))"
            }
            spoken = "Scanned, not yet checked. Typically within "
                + SpokenMeasurement.tolerance(forLength: measured.scanned, unit: units.length)
        }
    }

    /// "Verified (Laser)", "Verified (Tape)", "Verified (Drawing)" or "Scanned".
    static func label(for measured: Measured) -> String {
        guard let verification = measured.verification else { return "Scanned" }
        return "Verified (\(verification.source.displayName))"
    }
}

/// The "9 of 21 checked" summary.
struct VerificationSummary: Equatable {
    let verified: Int
    let total: Int

    /// Counts are clamped so `verified` is never negative or more than `total`.
    init(verified: Int, total: Int) {
        let safeTotal = max(total, 0)
        self.total = safeTotal
        self.verified = min(max(verified, 0), safeTotal)
    }

    /// 0...1; 0 when there is nothing to check.
    var fraction: Double { total > 0 ? Double(verified) / Double(total) : 0 }

    var text: String { total > 0 ? "\(verified) of \(total) checked" : "Nothing to check yet" }

    var spoken: String {
        total > 0 ? "\(verified) of \(total) dimensions checked" : "No dimensions to check yet"
    }

    /// Clamps any progress value to 0...1, treating NaN and infinity as 0.
    static func clamp(_ fraction: Double) -> Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }
}
