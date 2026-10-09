import Foundation

/// How far the LiDAR scan was from the laser, over every dimension a person has checked.
///
/// This is the honest answer to "how accurate is this phone in these rooms": it only looks at
/// values that have a `Verification`, compares the verified number with the scanned one, and
/// does plain arithmetic on the differences. It never changes the model.
///
/// Conventions (all lengths metres):
/// - **error** of one check is `Measured.deviation`, `verified - scanned`. Positive means the
///   scan read SHORT. `meanSignedError` (the bias) has the same sign.
/// - **percent** of one check is `|error| / |verified| x 100`, as in `Measured.deviationPercent`.
///   A check whose verified value is zero (a door sill) has no percentage; it still counts for
///   every other statistic.
/// - **p90** uses the nearest-rank method: sort the absolute errors ascending and take the value
///   at rank `ceil(0.9 n)`. It is always one of the observed errors.
/// - **size bands** split by the VERIFIED value: under 2 m is `shortBand`, 2 m and over is `longBand`.
public struct AccuracyReport: Sendable {

    /// One verified dimension.
    public struct Sample: Hashable, Sendable {
        public var roomID: UUID
        public var roomName: String
        public var target: MeasureTarget
        /// "Living: Wall A length".
        public var label: String
        public var scanned: Double
        public var verified: Double
        public var source: VerificationSource
        public var date: Date

        /// verified - scanned, metres.
        public var error: Double { verified - scanned }
        public var absoluteError: Double { abs(error) }
        /// |error| / |verified| x 100; nil when the verified value is about zero.
        public var absolutePercent: Double? {
            abs(verified) > 1e-9 ? absoluteError / abs(verified) * 100 : nil
        }
    }

    /// Summary statistics over a set of samples.
    public struct Stats: Hashable, Sendable {
        public let sampleCount: Int
        /// Mean of |verified - scanned|, metres.
        public let meanAbsoluteError: Double
        /// Mean of (verified - scanned), metres. Positive: the scan reads short on average.
        public let meanSignedError: Double
        /// Mean of the per-check absolute percentages (checks with a verified value of zero excluded).
        public let meanAbsolutePercent: Double
        public let maxAbsoluteError: Double
        /// 90th percentile of |error|, nearest rank.
        public let p90AbsoluteError: Double

        public static let empty = Stats(sampleCount: 0, meanAbsoluteError: 0, meanSignedError: 0,
                                        meanAbsolutePercent: 0, maxAbsoluteError: 0, p90AbsoluteError: 0)

        init(sampleCount: Int, meanAbsoluteError: Double, meanSignedError: Double,
             meanAbsolutePercent: Double, maxAbsoluteError: Double, p90AbsoluteError: Double) {
            self.sampleCount = sampleCount
            self.meanAbsoluteError = meanAbsoluteError
            self.meanSignedError = meanSignedError
            self.meanAbsolutePercent = meanAbsolutePercent
            self.maxAbsoluteError = maxAbsoluteError
            self.p90AbsoluteError = p90AbsoluteError
        }

        public init(samples: [Sample]) {
            let n = samples.count
            guard n > 0 else {
                self = .empty
                return
            }
            let absolute = samples.map(\.absoluteError)
            let sorted = absolute.sorted()
            let percents = samples.compactMap(\.absolutePercent)
            // Nearest rank: ceil(0.9 n) in integer arithmetic.
            let rank = min(n, max(1, (9 * n + 9) / 10))
            self.sampleCount = n
            self.meanAbsoluteError = absolute.reduce(0, +) / Double(n)
            self.meanSignedError = samples.reduce(0) { $0 + $1.error } / Double(n)
            self.meanAbsolutePercent = percents.isEmpty ? 0 : percents.reduce(0, +) / Double(percents.count)
            self.maxAbsoluteError = sorted[n - 1]
            self.p90AbsoluteError = sorted[rank - 1]
        }
    }

    /// Verified values below this many metres go in `shortBand`, the rest in `longBand`.
    public static let sizeBandBoundary = 2.0

    /// Every verified dimension counted, in property order (floors, rooms, `Room.measureTargets()`).
    public let samples: [Sample]
    public let overall: Stats
    /// Dimensions with a verified value under 2 m.
    public let shortBand: Stats
    /// Dimensions with a verified value of 2 m or more.
    public let longBand: Stats

    public var sampleCount: Int { overall.sampleCount }
    public var meanAbsoluteError: Double { overall.meanAbsoluteError }
    /// Bias: positive means the scan reads short on average.
    public var meanSignedError: Double { overall.meanSignedError }
    public var meanAbsolutePercent: Double { overall.meanAbsolutePercent }
    public var maxAbsoluteError: Double { overall.maxAbsoluteError }
    public var p90AbsoluteError: Double { overall.p90AbsoluteError }

    /// All sources by default; pass `[.laser]` to count laser checks only.
    public init(property: Property, sources: Set<VerificationSource> = Set(VerificationSource.allCases)) {
        self.init(rooms: property.allRooms, sources: sources)
    }

    public init(rooms: [Room], sources: Set<VerificationSource> = Set(VerificationSource.allCases)) {
        var collected: [Sample] = []
        for room in rooms {
            for target in room.measureTargets() {
                guard let measured = room.measured(target), let check = measured.verification,
                      sources.contains(check.source),
                      check.value.isFinite, measured.scanned.isFinite else { continue }
                collected.append(Sample(roomID: room.id, roomName: room.name, target: target,
                                        label: room.name + ": " + room.fullTitle(for: target),
                                        scanned: measured.scanned, verified: check.value,
                                        source: check.source, date: check.date))
            }
        }
        self.samples = collected
        self.overall = Stats(samples: collected)
        self.shortBand = Stats(samples: collected.filter { $0.verified < AccuracyReport.sizeBandBoundary })
        self.longBand = Stats(samples: collected.filter { $0.verified >= AccuracyReport.sizeBandBoundary })
    }

    /// The samples with the largest absolute error, worst first. Ties keep property order.
    public func worstSamples(_ count: Int = 5) -> [Sample] {
        guard count > 0 else { return [] }
        let indexed = samples.enumerated().sorted { a, b in
            if a.element.absoluteError != b.element.absoluteError {
                return a.element.absoluteError > b.element.absoluteError
            }
            return a.offset < b.offset
        }
        return indexed.prefix(count).map(\.element)
    }

    // MARK: Text

    /// "12 checks: typically 6 mm (0.3 %), worst 21 mm", or "No laser checks yet".
    /// "Typically" is the mean absolute error; the percentage is the mean absolute percent.
    public var summary: String { summary(unit: .millimetres) }

    public func summary(unit: LengthUnit) -> String {
        guard sampleCount > 0 else { return "No laser checks yet" }
        let typical = UnitFormatter.length(meanAbsoluteError, unit: unit)
        let worst = UnitFormatter.length(maxAbsoluteError, unit: unit)
        let percent = String(format: "%.1f", meanAbsolutePercent)
        let noun = sampleCount == 1 ? "check" : "checks"
        return "\(sampleCount) \(noun): typically \(typical) (\(percent) %), worst \(worst)"
    }

    /// Plain-language reading of the bias, e.g. "Scans read about 4 mm short on average".
    /// "No consistent bias" when the mean signed error is under 1 mm, "" with no checks.
    public func biasDescription(unit: LengthUnit = .millimetres) -> String {
        guard sampleCount > 0 else { return "" }
        let bias = meanSignedError
        if abs(bias) < 0.001 { return "No consistent bias" }
        let size = UnitFormatter.length(abs(bias), unit: unit)
        return "Scans read about \(size) \(bias > 0 ? "short" : "long") on average"
    }
}
