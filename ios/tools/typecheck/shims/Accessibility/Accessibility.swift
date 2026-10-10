// SHIM of the part of Apple's Accessibility framework the app touches (VoiceOver announcements).
@_exported import Foundation

// doc: Accessibility/AccessibilityNotification
public enum AccessibilityNotification {
    // doc: Accessibility/AccessibilityNotification/Announcement
    public struct Announcement {
        // doc: Accessibility/AccessibilityNotification/Announcement/init(_:)-621va
        public init(_ announcement: String) { fatalError() }
        // doc: Accessibility/AccessibilityNotification/Announcement/init(_:)-btpf
        public init(_ announcement: AttributedString) { fatalError() }
        // doc: Accessibility/AccessibilityNotification/Announcement/post()
        public func post() { fatalError() }
    }
}
