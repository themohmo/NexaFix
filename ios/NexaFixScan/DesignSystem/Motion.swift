import SwiftUI

/// The app's springs, defined once. See DESIGN.md, "Motion".
///
/// Springs, not durations: they keep the velocity of whatever interrupted them, so a running
/// animation re-targets from where it is instead of jumping.
enum Motion {
    /// Critically damped (no bounce). Things appearing, disappearing and reordering.
    static let standard: Animation = .spring(response: 0.35, dampingFraction: 1)
    /// A little life, for when a gesture carried momentum: a flicked sheet, a thrown plan.
    static let momentum: Animation = .spring(response: 0.30, dampingFraction: 0.8)
    /// Small state changes: a button letting go, a toggle, a badge.
    static let quick: Animation = .spring(response: 0.22, dampingFraction: 1)
    /// While a finger is down and dragging. Follows the touch almost 1:1.
    static let interactive: Animation = .interactiveSpring()
    /// What every spring becomes when Reduce Motion is on: a short cross-fade.
    static let reduced: Animation = .easeInOut(duration: 0.18)

    /// The animation to actually use: `animation`, or a short ease when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

// MARK: - Animating a value

private struct MotionModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Like `animation(_:value:)`, but swaps the spring for a short cross-fade when Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

// MARK: - Transitions

// The two transitions below are deliberately NOT `@MainActor`. Before the iOS 18 SDK (Xcode 15 and 16.0)
// `View` is not main-actor isolated, only `body` is, so a `@MainActor` static could not be used from an
// ordinary helper such as `private var card: some View { ... .transition(.sheetRise) }`. Building an
// `AnyTransition` from a value-type `ViewModifier` needs no main-actor state.

/// Rises a short way from below while fading in, and leaves the same way. With Reduce Motion it only fades.
private struct SheetRiseEffect: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // `nonisolated` so the transition statics can build the effect from any context, on every SDK.
    nonisolated init(isActive: Bool) {
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .offset(y: isActive && !reduceMotion ? 28 : 0)
    }
}

/// Fades while scaling up from 96 %, and leaves the same way. With Reduce Motion it only fades.
private struct FadeScaleEffect: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // `nonisolated` so the transition statics can build the effect from any context, on every SDK.
    nonisolated init(isActive: Bool) {
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .scaleEffect(isActive && !reduceMotion ? 0.96 : 1)
    }
}

extension AnyTransition {
    /// For cards and bars that appear over content, such as the selection card on the plan.
    /// Usable from any view helper on every supported Xcode, with or without `@MainActor`.
    static var sheetRise: AnyTransition {
        .modifier(active: SheetRiseEffect(isActive: true), identity: SheetRiseEffect(isActive: false))
    }

    /// For small things that appear in place, such as a measurement readout.
    /// Usable from any view helper on every supported Xcode, with or without `@MainActor`.
    static var fadeScale: AnyTransition {
        .modifier(active: FadeScaleEffect(isActive: true), identity: FadeScaleEffect(isActive: false))
    }
}
