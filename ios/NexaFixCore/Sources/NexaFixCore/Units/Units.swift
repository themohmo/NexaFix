import Foundation

public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case millimetres, centimetres, metres, inches, feetAndInches

    public var displayName: String {
        switch self {
        case .millimetres: return "Millimetres"
        case .centimetres: return "Centimetres"
        case .metres: return "Metres"
        case .inches: return "Inches"
        case .feetAndInches: return "Feet & inches"
        }
    }

    public var symbol: String {
        switch self {
        case .millimetres: return "mm"
        case .centimetres: return "cm"
        case .metres: return "m"
        case .inches: return "in"
        case .feetAndInches: return "ft"
        }
    }
}

public enum AreaUnit: String, Codable, CaseIterable, Sendable {
    case squareMetres, squareFeet

    public var displayName: String {
        switch self {
        case .squareMetres: return "Square metres"
        case .squareFeet: return "Square feet"
        }
    }

    public var symbol: String {
        switch self {
        case .squareMetres: return "m\u{00B2}"
        case .squareFeet: return "sq ft"
        }
    }
}

/// The user's display preferences. Storage and exports are always metric; this only changes presentation.
public struct DisplayUnits: Codable, Hashable, Sendable {
    public var length: LengthUnit
    public var area: AreaUnit

    public init(length: LengthUnit = .millimetres, area: AreaUnit = .squareMetres) {
        self.length = length
        self.area = area
    }

    public static let `default` = DisplayUnits()
}

/// How many digits to show. `precise` for schedules and detail views, `compact` for labels on a drawing.
public enum UnitPrecision: Sendable {
    case precise, compact
}

public enum UnitFormatter {
    public static let metresPerInch = 0.0254
    public static let metresPerFoot = 0.3048
    public static let squareMetresPerSquareFoot = 0.09290304

    /// Format a length given in metres. Never localised: always "." decimal and ASCII-safe fractions,
    /// so the same text can go into PDFs, DXF and CSV.
    public static func length(_ metres: Double, unit: LengthUnit, precision: UnitPrecision = .precise,
                              includeUnit: Bool = true) -> String {
        switch unit {
        case .millimetres:
            return number(metres * 1000, decimals: 0, suffix: includeUnit ? " mm" : "")
        case .centimetres:
            return number(metres * 100, decimals: precision == .precise ? 1 : 0, suffix: includeUnit ? " cm" : "")
        case .metres:
            return number(metres, decimals: precision == .precise ? 3 : 2, suffix: includeUnit ? " m" : "")
        case .inches:
            return number(metres / metresPerInch, decimals: precision == .precise ? 2 : 1,
                          suffix: includeUnit ? " in" : "")
        case .feetAndInches:
            return feetAndInches(metres, denominator: precision == .precise ? 16 : 2)
        }
    }

    public static func area(_ squareMetres: Double, unit: AreaUnit, precision: UnitPrecision = .precise,
                            includeUnit: Bool = true) -> String {
        switch unit {
        case .squareMetres:
            return number(squareMetres, decimals: precision == .precise ? 2 : 1,
                          suffix: includeUnit ? " m\u{00B2}" : "")
        case .squareFeet:
            return number(squareMetres / squareMetresPerSquareFoot, decimals: precision == .precise ? 1 : 0,
                          suffix: includeUnit ? " sq ft" : "")
        }
    }

    /// "90.0\u{00B0}"
    public static func angle(_ degrees: Double, decimals: Int = 1) -> String {
        number(degrees, decimals: decimals, suffix: "\u{00B0}")
    }

    /// Signed difference such as "+3 mm" or "-0.4 in".
    public static func signedLength(_ metres: Double, unit: LengthUnit, precision: UnitPrecision = .precise) -> String {
        let text = length(abs(metres), unit: unit, precision: precision)
        let isZero = Double(text.filter { "0123456789.".contains($0) }) == 0
        if isZero { return text }
        return (metres < 0 ? "-" : "+") + text
    }

    /// "\u{00B1}22 mm" typical tolerance for a scanned length.
    public static func tolerance(forLength metres: Double, unit: LengthUnit) -> String {
        "\u{00B1}" + length(ScanAccuracy.typicalTolerance(forLength: metres), unit: unit, precision: .compact)
    }

    // MARK: helpers

    /// `String(format:)` with a trailing suffix and no "-0".
    static func number(_ value: Double, decimals: Int, suffix: String = "") -> String {
        var s = String(format: "%.\(decimals)f", value)
        if Double(s) == 0 { s = String(s.drop(while: { $0 == "-" })) }
        return s + suffix
    }

    private static func feetAndInches(_ metres: Double, denominator: Int) -> String {
        let negative = metres < 0
        let totalSixteenths = Int((abs(metres) / metresPerInch * Double(denominator)).rounded())
        let totalInches = totalSixteenths / denominator
        let fraction = totalSixteenths % denominator
        let feet = totalInches / 12
        let inches = totalInches % 12

        var parts = ""
        if feet > 0 { parts += "\(feet)' " }
        parts += "\(inches)"
        if fraction != 0 {
            var n = fraction, d = denominator
            while n % 2 == 0 && d % 2 == 0 { n /= 2; d /= 2 }
            parts += " \(n)/\(d)"
        }
        parts += "\""
        return (negative && totalSixteenths != 0 ? "-" : "") + parts
    }
}
