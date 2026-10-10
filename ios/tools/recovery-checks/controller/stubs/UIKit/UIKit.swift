import Foundation
@MainActor open class UIView {
    public var isAccessibilityElement = false
    public init(frame: CGRect) {}
    public convenience init() { self.init(frame: .zero) }
}
@MainActor open class UIApplication {
    public static let shared = UIApplication()
    public nonisolated static let openSettingsURLString: String = "app-settings:"
    public var isIdleTimerDisabled = false
    public struct OpenExternalURLOptionsKey: Hashable, RawRepresentable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {}
}
public enum UIAccessibility {
    public static var isVoiceOverRunning: Bool { false }
    public struct Notification: RawRepresentable, Hashable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let announcement = Notification(rawValue: "announcement") }
    @MainActor public static func post(notification: Notification, argument: Any?) {}
}
public class UIImpactFeedbackGenerator { public enum FeedbackStyle: Int { case light, medium, heavy, soft, rigid } }
