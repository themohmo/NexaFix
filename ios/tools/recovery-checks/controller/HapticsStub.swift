import UIKit
// Stand-in for DesignSystem/Haptics.swift: same entry points the controller calls.
enum Haptics {
    nonisolated(unsafe) static var log: [String] = []
    static func selection() { log.append("selection") }
    static func success() { log.append("success") }
    static func warning() { log.append("warning") }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) { log.append("impact") }
}
