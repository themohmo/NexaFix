import UIKit

/// Haptic feedback for the moments DESIGN.md names, and only those:
/// a snap (`selection`), a saved verification (`success`), a finished room (`impact`),
/// tracking lost or a scan error (`warning`).
///
/// Every call is a no-op when the user switched haptics off (`isEnabled`) and in the simulator.
/// Safe to call from any thread; the feedback itself is fired on the main thread.
enum Haptics {
    private static let lock = NSLock()
    private static var enabled = true

    /// Mirrors the Settings switch. `AppModel` keeps it in step with `AppSettings.hapticsEnabled`.
    static var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            lock.unlock()
        }
    }

    /// A light tick: a measurement point snapped to a corner or edge, a toggle changed.
    static func selection() {
        fire { $0.selection() }
    }

    /// A verification or a property was saved.
    static func success() {
        fire { $0.notify(.success) }
    }

    /// Tracking lost, or a scan error.
    static func warning() {
        fire { $0.notify(.warning) }
    }

    /// A physical thump. `.medium` for a finished room.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        fire { $0.impact(style) }
    }

    // MARK: Plumbing

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func fire(_ work: @escaping @MainActor @Sendable (HapticEngine) -> Void) {
        guard isEnabled, !isSimulator else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { work(HapticEngine.shared) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { work(HapticEngine.shared) }
            }
        }
    }
}

/// Keeps one generator of each kind alive and warm. UIKit's feedback generators belong to the main actor.
@MainActor
private final class HapticEngine {
    static let shared = HapticEngine()

    private var selectionGenerator: UISelectionFeedbackGenerator?
    private var notificationGenerator: UINotificationFeedbackGenerator?
    private var impactGenerators: [Int: UIImpactFeedbackGenerator] = [:]

    func selection() {
        let generator = selectionGenerator ?? UISelectionFeedbackGenerator()
        selectionGenerator = generator
        generator.selectionChanged()
        generator.prepare()
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = notificationGenerator ?? UINotificationFeedbackGenerator()
        notificationGenerator = generator
        generator.notificationOccurred(type)
        generator.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = impactGenerators[style.rawValue] ?? UIImpactFeedbackGenerator(style: style)
        impactGenerators[style.rawValue] = generator
        generator.impactOccurred()
        generator.prepare()
    }
}
