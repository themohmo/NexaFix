import SwiftUI
import NexaFixCore

// The views that draw measurements. The wording they show and speak (`MeasurementParts`,
// `SpokenMeasurement`, `ProvenanceDescription`, `VerificationSummary`) lives in
// `App/MeasurementFormatting.swift`, which has no SwiftUI import so it can be checked on Linux.

// MARK: - Style

/// The four sizes a measurement is shown at.
enum MeasurementStyle {
    /// 52 pt light with tight tracking: the area of a room, a selected length.
    case hero
    /// 22 pt semibold.
    case title
    /// 17 pt medium: rows.
    case body
    /// 12 pt medium: annotations.
    case caption

    fileprivate var numberWeight: Font.Weight {
        switch self {
        case .hero: return .light
        case .title: return .semibold
        case .body, .caption: return .medium
        }
    }

    /// One weight lighter than the number.
    fileprivate var unitWeight: Font.Weight {
        switch self {
        case .hero: return .thin
        case .title: return .medium
        case .body, .caption: return .regular
        }
    }

    /// Letter-spacing in em: large numerals want less, small text near none, captions a touch more.
    fileprivate var trackingEm: CGFloat {
        switch self {
        case .hero: return -0.02
        case .title: return -0.01
        case .body: return 0
        case .caption: return 0.01
        }
    }

    /// The unit's size relative to the number's.
    fileprivate var unitScale: CGFloat {
        switch self {
        case .hero: return 0.42
        case .title: return 0.82
        case .body: return 0.88
        case .caption: return 0.92
        }
    }
}

// MARK: - MeasurementText

/// A number and its unit: monospaced digits so columns line up, the unit one weight lighter and muted,
/// and a VoiceOver label that says the full unit ("3245 millimetres").
struct MeasurementText: View {
    private let parts: MeasurementParts
    private let style: MeasurementStyle
    private var numberTint: Color = Palette.ink

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12

    /// A length given in metres, shown in the user's length unit.
    init(length metres: Double, units: DisplayUnits, style: MeasurementStyle = .body) {
        self.parts = MeasurementParts.length(metres, units: units)
        self.style = style
    }

    /// An area given in square metres, shown in the user's area unit.
    init(area squareMetres: Double, units: DisplayUnits, style: MeasurementStyle = .body) {
        self.parts = MeasurementParts.area(squareMetres, units: units)
        self.style = style
    }

    /// An angle in degrees.
    init(angle degrees: Double, style: MeasurementStyle = .body) {
        self.parts = MeasurementParts.angle(degrees)
        self.style = style
    }

    /// Overrides the colour of the number (the unit stays muted). Call this first in a modifier chain.
    func numberColor(_ color: Color) -> MeasurementText {
        var copy = self
        copy.numberTint = color
        return copy
    }

    private var pointSize: CGFloat {
        switch style {
        case .hero: return heroSize
        case .title: return titleSize
        case .body: return bodySize
        case .caption: return captionSize
        }
    }

    var body: some View {
        let size = pointSize
        HStack(alignment: .firstTextBaseline, spacing: max(2, size * 0.08)) {
            // The number is the flexible part: when width runs out it shrinks (down to 40 %) ...
            Text(verbatim: parts.number)
                .font(.system(size: size, weight: style.numberWeight).monospacedDigit())
                .tracking(style.trackingEm * size)
                .foregroundStyle(numberTint)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            // ... and the unit keeps its full width, offered first, so a value never loses its unit.
            if let unit = parts.unit {
                Text(verbatim: unit)
                    .font(.system(size: size * style.unitScale, weight: style.unitWeight))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.spoken)
    }
}

// MARK: - ProvenanceBadge

/// Whether a value was measured by a person or only scanned. Never colour alone: verified has a check
/// mark and the source name, scanned has a triangle and the word "Scanned" with its typical tolerance.
struct ProvenanceBadge: View {
    private let info: ProvenanceDescription
    private let compact: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - measured: The value to describe.
    ///   - units: Used for the tolerance text ("±22 mm").
    ///   - compact: Leave out the tolerance. For tight rows and labels.
    init(_ measured: Measured, units: DisplayUnits, compact: Bool = false) {
        self.info = ProvenanceDescription(measured, units: units, compact: compact)
        self.compact = compact
    }

    var body: some View {
        // At accessibility text sizes the glyph sits above the words, as in `VerificationProgress`. At every
        // size the words wrap onto a second line rather than being cut off, so the tolerance is never lost.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.xs))
        layout {
            Image(systemName: info.isVerified ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(info.isVerified ? Palette.verified : Palette.caution)
                .accessibilityHidden(true)
            Text(verbatim: info.visibleText)
                .foregroundStyle(info.isVerified ? Palette.verified : Palette.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font((compact ? Font.caption : Font.footnote).weight(.semibold))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spoken)
    }
}

// MARK: - VerificationProgress

/// "9 of 21 checked" with a ring. Stacks vertically at accessibility text sizes.
struct VerificationProgress: View {
    private let summary: VerificationSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var ringSize: CGFloat = 24

    init(verified: Int, total: Int) {
        self.summary = VerificationSummary(verified: verified, total: total)
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(spacing: Spacing.s))
        layout {
            ProgressRing(fraction: summary.fraction, lineWidth: 3.5)
                .frame(width: ringSize, height: ringSize)
                .accessibilityHidden(true)
            Text(verbatim: summary.text)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.spoken)
    }
}

// MARK: - Accessibility helper

extension View {
    /// Makes a whole row one VoiceOver element that reads like a sentence:
    /// "Wall A, 3245 millimetres, verified with laser". Any controls inside the row become unreachable
    /// by VoiceOver, so give the row its own accessibility actions if it has them.
    func accessibilityMeasurement(_ name: String, value: String, provenance: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue("\(value), \(SpokenMeasurement.midSentence(provenance))")
    }
}
