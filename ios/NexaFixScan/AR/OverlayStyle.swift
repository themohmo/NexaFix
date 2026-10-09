import SwiftUI
import NexaFixCore

/// Sizes and colours for the AR overlay. `OverlayStyle.standard` follows DESIGN.md.
///
/// The overlay is drawn over a live camera image, so every line gets a faint dark outline under it and
/// every label sits on its own dark chip. Colour is never the only signal: verified labels carry a check
/// mark, caution a triangle and critical an octagon.
struct OverlayStyle {
    // MARK: Lines

    /// Width of the thin white wireframe and dimension lines, points.
    var lineWidth: CGFloat = 1
    /// Extra width of the dark outline drawn under every line, points.
    var outlineExtraWidth: CGFloat = 2
    var outlineOpacity: Double = 0.35
    /// Angle arcs are a little heavier than the wireframe so they read at a glance.
    var arcLineWidth: CGFloat = 1.5
    /// The measurement in progress.
    var measurementLineWidth: CGFloat = 2
    /// Radius of the dots at the ends of a measurement, points.
    var endpointRadius: CGFloat = 4
    /// Points sampled per 90 degrees of an arc.
    var arcSamplesPerQuarter = 10

    // MARK: Labels

    /// The chip radius from the design scale. (Labels are drawn into a Canvas, which rasterises them, so they
    /// are dark chips rather than blurred glass; see `AROverlayLabelChip`.)
    var labelCornerRadius: CGFloat = Radius.chip
    var labelHorizontalPadding: CGFloat = Spacing.s
    var labelVerticalPadding: CGFloat = Spacing.xs
    /// How opaque the dark label chip is when Reduce Transparency is off.
    var labelFillOpacity: Double = 0.74
    /// Largest Dynamic Type size labels grow to. A label cannot reflow around the world, so past this size
    /// VoiceOver (and the accessible list of labels) carries the full text instead.
    var labelMaxTypeSize: DynamicTypeSize = .xxxLarge

    static let standard = OverlayStyle()

    // MARK: Colours

    /// Wireframe lines: the room's edges.
    var wireColor: Color { Color.white.opacity(0.88) }
    /// Door and window outlines.
    var openingColor: Color { Palette.accent }
    /// The tape measure.
    var measurementColor: Color { Palette.accent }
    var outlineColor: Color { Color.black.opacity(outlineOpacity) }

    /// The accent for a state: glyphs, arcs and dimension lines.
    func tint(for state: OverlayState) -> Color {
        switch state {
        case .verified: return Palette.verified
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        case .scanned, .neutral: return Color.white.opacity(0.9)
        }
    }

    /// The colour of a segment.
    func color(for kind: OverlaySegmentKind, state: OverlayState) -> Color {
        switch kind {
        case .wallBase, .wallTop, .wallCorner: return wireColor
        case .openingEdge: return openingColor
        case .measurement: return measurementColor
        case .dimension: return tint(for: state)
        }
    }

    func width(for kind: OverlaySegmentKind) -> CGFloat {
        kind == .measurement ? measurementLineWidth : lineWidth
    }

    /// The colour of the main text on a label: ink, except where the state itself is the message.
    func titleColor(for state: OverlayState) -> Color {
        switch state {
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        case .scanned, .verified, .neutral: return Palette.ink
        }
    }

    /// SF Symbol shown on a label so colour is never the only signal. Scanned and neutral labels have none:
    /// their line of small print ("±22 mm") already says what they are.
    func glyph(for state: OverlayState) -> String? {
        switch state {
        case .verified: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .scanned, .neutral: return nil
        }
    }
}
