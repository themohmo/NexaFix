import SwiftUI

// All three styles respond on touch-down: `configuration.isPressed` flips the moment a finger lands,
// the press-in is instant, and only the release is animated. With Reduce Motion the scale is dropped and
// only the dimming remains.

// MARK: - Pressable

/// The base interaction for anything tappable that is not a primary or secondary button: rows, chips,
/// icon buttons. Scales to 0.97 and dims while pressed.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.7

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, pressedScale: pressedScale, pressedOpacity: pressedOpacity)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    let pressedScale: CGFloat
    let pressedOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
            .opacity(pressed ? pressedOpacity : (isEnabled ? 1 : 0.4))
            .animation(pressed ? nil : Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: pressed)
    }
}

// MARK: - Primary

/// The accent capsule: the one thing to do next on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    /// Stretch to the available width.
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, fullWidth: fullWidth)
    }
}

private struct PrimaryBody: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 50

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.accentContrast)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: max(44, minHeight))
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(Palette.accent)
                    Capsule(style: .continuous).fill(Color.black.opacity(pressed ? 0.14 : 0))
                }
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(pressed ? nil : Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: pressed)
    }
}

// MARK: - Secondary

/// A quieter capsule: `surface` with a hairline border, or glass when it sits over the camera feed.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    /// Draw glass instead of a flat surface. Use on the scan and AR screens.
    var onGlass = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration, fullWidth: fullWidth, onGlass: onGlass)
    }
}

private struct SecondaryBody: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    let onGlass: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 50

    var body: some View {
        let pressed = configuration.isPressed
        chrome(
            configuration.label
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.m)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: max(44, minHeight))
        )
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .opacity(pressed ? 0.7 : (isEnabled ? 1 : 0.4))
        .animation(pressed ? nil : Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: pressed)
    }

    @ViewBuilder
    private func chrome<Inner: View>(_ label: Inner) -> some View {
        if onGlass {
            label.glass(in: Capsule(style: .continuous), prominence: .regular)
        } else {
            label
                .background { Capsule(style: .continuous).fill(Palette.surface) }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast))
                }
        }
    }
}

// MARK: - Shortcuts

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)`
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// `.buttonStyle(.primary)`
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// `.buttonStyle(.primaryFullWidth)`
    static var primaryFullWidth: PrimaryButtonStyle { PrimaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    /// `.buttonStyle(.secondary)`
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    /// `.buttonStyle(.secondaryFullWidth)`
    static var secondaryFullWidth: SecondaryButtonStyle { SecondaryButtonStyle(fullWidth: true) }
    /// `.buttonStyle(.secondaryOnGlass)`
    static var secondaryOnGlass: SecondaryButtonStyle { SecondaryButtonStyle(onGlass: true) }
}

// MARK: - Glass icon button

/// A round glass button for icons floating over content: close, flash, toggles. At least 44 pt,
/// growing with Dynamic Type, with the whole circle tappable.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - label: What VoiceOver says. Required, because the button has no visible text.
    init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: max(44, diameter), height: max(44, diameter))
                .glass(in: Circle(), prominence: .thin)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}
