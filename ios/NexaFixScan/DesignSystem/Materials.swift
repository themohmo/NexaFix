import SwiftUI

/// How much glass a floating control gets. Small chips are lighter, bigger surfaces thicker.
enum GlassProminence {
    /// Chips, pills and icon buttons. `ultraThinMaterial`, a small tight shadow.
    case thin
    /// Toolbars and the readout. `regularMaterial`, a softer shadow.
    case regular
    /// Large floating sheets. `thickMaterial`, the largest and softest shadow.
    case thick
}

// MARK: - Never glass on glass

private struct InsideGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a view that already has a glass background. A nested `glass()` then draws a flat tint
    /// instead of another blur, because translucent surfaces never sit on other translucent surfaces.
    ///
    /// SwiftUI presentations inherit the environment of the view that presents them, so a sheet, popover
    /// or cover attached to a view *inside* a glass surface would inherit this flag and draw its own glass
    /// controls as faint flat tints. Attach presentation modifiers outside glass containers, or call
    /// `outsideGlass()` on the presented content's root.
    var isInsideGlass: Bool {
        get { self[InsideGlassKey.self] }
        set { self[InsideGlassKey.self] = newValue }
    }
}

// MARK: - The modifier

struct GlassModifier<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape
    let prominence: GlassProminence

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isInsideGlass) private var insideGlass

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), usesSystemGlass {
            // The system's Liquid Glass: it supplies its own blur, highlight and shadow, so none of ours.
            content
                .glassEffect(.regular, in: shape)
                .environment(\.isInsideGlass, true)
        } else {
            content
                .background { fill }
                .overlay { edge }
                .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
                .environment(\.isInsideGlass, true)
        }
    }

    /// Liquid Glass is used only for the top-level glass surface. Reduce Transparency and Increased
    /// Contrast keep the opaque / bordered fallback, and nested glass stays a flat tint (never glass on glass).
    private var usesSystemGlass: Bool {
        !insideGlass && !reduceTransparency && contrast != .increased
    }

    private var material: Material {
        switch prominence {
        case .thin: return .ultraThin
        case .regular: return .regular
        case .thick: return .thick
        }
    }

    /// A little of the paper colour over the blur keeps ink text readable over a dark or busy camera feed.
    private var scrimOpacity: Double {
        switch prominence {
        case .thin: return 0.22
        case .regular: return 0.14
        case .thick: return 0.08
        }
    }

    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        if insideGlass { return (.clear, 0, 0) }
        switch prominence {
        case .thin: return (Color.black.opacity(0.08), 6, 2)
        case .regular: return (Color.black.opacity(0.12), 14, 5)
        case .thick: return (Color.black.opacity(0.16), 28, 10)
        }
    }

    @ViewBuilder private var fill: some View {
        if insideGlass {
            shape.fill(Palette.ink.opacity(0.06))
        } else if reduceTransparency {
            shape.fill(Palette.surface)
        } else {
            ZStack {
                shape.fill(material)
                shape.fill(Palette.background.opacity(scrimOpacity))
            }
        }
    }

    /// The 0.5 pt top-edge highlight that makes the surface read as glass. With Reduce Transparency
    /// (an opaque surface) or Increased Contrast, a plain `line` border takes its place.
    @ViewBuilder private var edge: some View {
        if insideGlass {
            EmptyView()
        } else if reduceTransparency || contrast == .increased {
            shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast))
        } else {
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .center),
                lineWidth: Hairline.width)
        }
    }
}

extension View {
    /// Gives the view a glass background: a material, a top-edge highlight and a shadow.
    ///
    /// - On iOS 26 and later it is the system's Liquid Glass (`glassEffect`); earlier systems get a material
    ///   with a top-edge highlight and a shadow.
    /// - Reduce Transparency swaps the material for an opaque `surface` with a hairline border.
    /// - Increased Contrast adds a 1 pt `line` border.
    /// - Inside another glass surface it draws a flat tint, never a second blur.
    ///
    /// On the scan and AR screens, set `.preferredColorScheme(.dark)` on the screen's root so the glass
    /// and the ink on it both go dark over the camera feed.
    ///
    /// Everything inside the glass view is marked as "inside glass". Do not attach `.sheet`, `.popover`,
    /// `.fullScreenCover` or a dialog to a view inside it, because the presentation would inherit the mark;
    /// attach it outside, or call `outsideGlass()` on the presented content's root.
    func glass(cornerRadius: CGFloat = Radius.card, prominence: GlassProminence = .regular) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                               prominence: prominence))
    }

    /// Clears the "inside glass" mark so glass controls in this subtree draw real material again. Apply it
    /// to the root of a sheet, popover or cover that is presented from inside a glass surface.
    func outsideGlass() -> some View {
        environment(\.isInsideGlass, false)
    }

    /// Glass in any inset shape: `Capsule(style: .continuous)` for pills, `Circle()` for icon buttons.
    func glass<S: InsettableShape>(in shape: S, prominence: GlassProminence = .regular) -> some View {
        modifier(GlassModifier(shape: shape, prominence: prominence))
    }
}
