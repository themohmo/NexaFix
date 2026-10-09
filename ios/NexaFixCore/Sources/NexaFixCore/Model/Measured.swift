import Foundation

/// How a scanned value was checked against reality.
public enum VerificationSource: String, Codable, Sendable, CaseIterable {
    case laser      // laser distance meter
    case tape       // steel tape
    case drawing    // taken from an approved drawing / survey

    public var displayName: String {
        switch self {
        case .laser: return "Laser"
        case .tape: return "Tape"
        case .drawing: return "Drawing"
        }
    }
}

/// A value a person has checked on site and typed in.
public struct Verification: Codable, Hashable, Sendable {
    /// The checked value, metres.
    public var value: Double
    public var source: VerificationSource
    public var date: Date
    public var note: String?

    public init(value: Double, source: VerificationSource = .laser, date: Date = Date(), note: String? = nil) {
        self.value = value
        self.source = source
        self.date = date
        self.note = note
    }
}

/// A dimension that remembers where it came from.
///
/// `scanned` is what LiDAR measured and never changes. `verification` is what a person
/// measured on site. `value` is what everything downstream (labels, exports, costing,
/// joinery schedules) should use: the verified number when there is one, the scan otherwise.
public struct Measured: Codable, Hashable, Sendable {
    /// LiDAR value, metres.
    public var scanned: Double
    public var verification: Verification?

    public init(scanned: Double, verification: Verification? = nil) {
        self.scanned = scanned
        self.verification = verification
    }

    /// The number to use: verified if present, otherwise scanned. Metres.
    public var value: Double { verification?.value ?? scanned }
    public var isVerified: Bool { verification != nil }

    /// verified - scanned, metres. Positive means the scan under-read.
    public var deviation: Double? { verification.map { $0.value - scanned } }

    /// (verified - scanned) / verified, as a percentage. nil when unverified or verified is ~0.
    public var deviationPercent: Double? {
        guard let v = verification, abs(v.value) > 1e-9 else { return nil }
        return (v.value - scanned) / v.value * 100
    }

    public mutating func verify(_ value: Double, source: VerificationSource = .laser,
                                note: String? = nil, date: Date = Date()) {
        verification = Verification(value: value, source: source, date: date, note: note)
    }

    public mutating func clearVerification() { verification = nil }
}

/// Typical LiDAR error budget. These are honest planning numbers, not guarantees; the
/// real figure for this phone and these rooms comes from `AccuracyReport` once enough
/// values have been checked with a laser.
public enum ScanAccuracy {
    /// Typical (not worst-case) error for a scanned length, metres:
    /// 1.5 % of the length, never less than 10 mm.
    public static func typicalTolerance(forLength metres: Double) -> Double {
        max(0.010, 0.015 * abs(metres))
    }

    /// Joinery is cut to these dimensions, so anything not laser-checked should be treated as
    /// an estimate. Shown wherever scanned numbers are presented as dimensions.
    public static let joineryDisclaimer =
        "LiDAR dimensions are typically within 1-2 %. Verify every dimension joinery will be cut to with a laser measure."
}
