import SwiftUI

// MARK: - Screen background

/// Paints the warm `background` behind a screen, edge to edge, and hides the system's own grouped
/// background in lists and scroll views so the paper colour shows through.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { Palette.background.ignoresSafeArea() }
    }
}

extension View {
    /// Apply once at the root of each screen.
    func screenBackground() -> some View {
        modifier(ScreenBackground())
    }
}

// MARK: - Pill

/// A small glass capsule with an optional leading symbol. Used for status ("Relocalising") and for the
/// scan coaching instruction. The text is always `ink`; `tint` colours the symbol.
struct Pill: View {
    private let text: String
    private let systemImage: String?
    private let tint: Color

    @ScaledMetric(relativeTo: .footnote) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var verticalPadding: CGFloat = 7

    init(_ text: String, systemImage: String? = nil, tint: Color = Palette.ink) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Spacing.s - Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .foregroundStyle(Palette.ink)
        }
        .font(.footnote.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .glass(in: Capsule(style: .continuous), prominence: .thin)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section card

/// A titled group of rows on a `surface` card with a hairline border. The title sits above the card,
/// like a grouped list. Put `RowDivider()` between rows.
struct SectionCard<Content: View>: View {
    private let title: String?
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let title {
                Text(verbatim: title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, Spacing.l)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface) }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast))
            }
        }
    }
}

/// A hairline between rows inside a `SectionCard`.
struct RowDivider: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: Hairline.adaptive(contrast))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress ring

/// A circular progress indicator that starts at twelve o'clock. Fills with a spring (a short fade when
/// Reduce Motion is on). `fraction` is clamped to 0...1.
struct ProgressRing: View {
    private let fraction: Double
    private let lineWidth: CGFloat
    private let tint: Color

    init(fraction: Double, lineWidth: CGFloat = 4, tint: Color = Palette.verified) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.tint = tint
    }

    var body: some View {
        let progress = VerificationSummary.clamp(fraction)
        ZStack {
            Circle()
                .stroke(Palette.line, lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: SwiftUI.StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .motion(value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - App mark

/// The icon's mark drawn in the app: two bronze walls meeting at a corner, the angle arc inside it and a
/// dimension line above with the gap where the number would sit. Same geometry as `ios/tools/make_icon.py`.
struct AppMark: View {
    private let size: CGFloat

    init(size: CGFloat = 96) {
        self.size = size
    }

    var body: some View {
        let unit = size / MarkGeometry.designSize
        ZStack {
            MarkWalls()
                .stroke(Palette.accent, style: SwiftUI.StrokeStyle(lineWidth: 58 * unit, lineCap: .butt, lineJoin: .miter))
            MarkAngleArc()
                .stroke(Palette.ink, style: SwiftUI.StrokeStyle(lineWidth: 16 * unit, lineCap: .round))
            MarkDimensionLine()
                .stroke(Palette.ink, style: SwiftUI.StrokeStyle(lineWidth: 12 * unit, lineCap: .butt))
            MarkDots()
                .fill(Palette.ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The icon is drawn on a 1000-unit canvas; this maps the mark's bounding box (about 560 by 540 units,
/// centred on (495.5, 450)) into whatever square the view gets.
private enum MarkGeometry {
    static let designSize: CGFloat = 600
    static let centre = CGPoint(x: 495.5, y: 450)

    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        let unit = min(rect.width, rect.height) / designSize
        return CGPoint(x: rect.midX + (x - centre.x) * unit, y: rect.midY + (y - centre.y) * unit)
    }
}

private struct MarkWalls: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: MarkGeometry.point(250, 250, in: rect))
        path.addLine(to: MarkGeometry.point(250, 690, in: rect))
        path.addLine(to: MarkGeometry.point(770, 690, in: rect))
        return path
    }
}

/// A quarter circle of radius 135 about the inside corner (279, 661), from straight up to straight right,
/// built from one cubic curve (control offset 0.5523 x radius) so the direction cannot be misread.
private struct MarkAngleArc: Shape {
    func path(in rect: CGRect) -> Path {
        let offset: CGFloat = 135 * 0.5523
        var path = Path()
        path.move(to: MarkGeometry.point(279, 526, in: rect))
        path.addCurve(to: MarkGeometry.point(414, 661, in: rect),
                      control1: MarkGeometry.point(279 + offset, 526, in: rect),
                      control2: MarkGeometry.point(414, 661 - offset, in: rect))
        return path
    }
}

private struct MarkDimensionLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The line, split around the gap where the number would sit.
        path.move(to: MarkGeometry.point(221, 215, in: rect))
        path.addLine(to: MarkGeometry.point(443.5, 215, in: rect))
        path.move(to: MarkGeometry.point(547.5, 215, in: rect))
        path.addLine(to: MarkGeometry.point(770, 215, in: rect))
        // End ticks.
        path.move(to: MarkGeometry.point(221, 181, in: rect))
        path.addLine(to: MarkGeometry.point(221, 249, in: rect))
        path.move(to: MarkGeometry.point(770, 181, in: rect))
        path.addLine(to: MarkGeometry.point(770, 249, in: rect))
        return path
    }
}

private struct MarkDots: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / MarkGeometry.designSize
        let radius = 7 * unit
        var path = Path()
        for x: CGFloat in [469.5, 495.5, 521.5] {
            let c = MarkGeometry.point(x, 215, in: rect)
            path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

// MARK: - Wordmark

/// "NEXAFIX" in the system font, light, letter-spaced 0.18 em. VoiceOver says "NexaFix", not the letters.
struct Wordmark: View {
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13

    var body: some View {
        let spacing = size * 0.18
        Text(verbatim: "NEXAFIX")
            .font(.system(size: size, weight: .light))
            .tracking(spacing)
            .foregroundStyle(Palette.ink)
            // Tracking adds space after the last letter too; the same amount in front keeps it centred.
            .padding(.leading, spacing)
            .accessibilityLabel("NexaFix")
    }
}

// MARK: - Empty state

/// The app mark, a title, one sentence and the next step. Scrolls instead of clipping at the largest
/// text sizes.
struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let primaryTitle: String
    private let primaryAction: () -> Void
    private let secondaryTitle: String?
    private let secondaryAction: (() -> Void)?
    private let primaryIdentifier: String
    private let secondaryIdentifier: String

    /// - Parameters:
    ///   - primaryIdentifier: Accessibility identifier of the main button, for UI tests. Empty for none.
    ///   - secondaryIdentifier: The same for the quiet button.
    init(title: String, message: String, primaryTitle: String, primaryAction: @escaping () -> Void,
         secondaryTitle: String? = nil, secondaryAction: (() -> Void)? = nil,
         primaryIdentifier: String = "", secondaryIdentifier: String = "") {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.primaryIdentifier = primaryIdentifier
        self.secondaryIdentifier = secondaryIdentifier
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                content
                    .padding(.vertical, Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var content: some View {
        VStack(spacing: Spacing.xl) {
            AppMark(size: 96)

            VStack(spacing: Spacing.s) {
                Text(verbatim: title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: message)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.s) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier(primaryIdentifier)
                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(verbatim: secondaryTitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier(secondaryIdentifier)
                }
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, Spacing.xl)
    }
}
