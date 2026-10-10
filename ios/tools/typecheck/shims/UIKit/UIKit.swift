// SHIM of Apple's UIKit (the parts NexaFix Scan touches). Declarations are copied from Apple's documentation
// (UIKit pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks. Bodies are
// `fatalError()`: this is for type checking only and is never run.
//
// Isolation: Apple's docs show `@MainActor class UIView` (an Objective-C import). The clang importer treats
// those imports as `@preconcurrency`, so in Swift 5 mode a use from a nonisolated context is not an error;
// the shim writes `@MainActor @preconcurrency` to match. UIKit re-exports Foundation, QuartzCore and CoreGraphics
// types that Foundation on Linux already provides.
@_exported import Foundation
@_exported import QuartzCore
@_exported import simd

// doc: UIKit/UIResponder
@MainActor @preconcurrency @objc open class UIResponder: NSObject {
    // shim: designated init
    public override init() { super.init() }
    // doc: UIKit/UIResponder/touchesBegan(_:with:)
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { fatalError() }
    // doc: UIKit/UIResponder/touchesMoved(_:with:)
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { fatalError() }
    // doc: UIKit/UIResponder/touchesEnded(_:with:)
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { fatalError() }
    // doc: UIKit/UIResponder/touchesCancelled(_:with:)
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { fatalError() }
}

// doc: UIKit/UIView
@MainActor @preconcurrency @objc open class UIView: UIResponder, NSCoding {
    // shim: NSCoding.encode
    public func encode(with coder: NSCoder) { fatalError() }
    // doc: UIKit/UIView/init(frame:)
    public init(frame: CGRect) { fatalError() }
    // doc: UIKit/UIView/init(coder:)
    public required init?(coder: NSCoder) { fatalError() }
    // doc: UIKit/UIView/init()
    public convenience override init() { fatalError() }
    // doc: UIKit/UIView/backgroundColor
    open var backgroundColor: UIColor? { get { fatalError() } set { } }
    // doc: UIKit/UIView/isMultipleTouchEnabled
    open var isMultipleTouchEnabled: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIView/isUserInteractionEnabled
    open var isUserInteractionEnabled: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIView/addGestureRecognizer(_:)
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) { fatalError() }
    // doc: UIKit/UIView/addSubview(_:)
    open func addSubview(_ view: UIView) { fatalError() }
    // doc: UIKit/UIView/autoresizingMask-swift.property
    open var autoresizingMask: UIView.AutoresizingMask { get { fatalError() } set { } }
    // doc: UIKit/UIView/bounds
    open var bounds: CGRect { get { fatalError() } set { } }
    // doc: UIKit/UIView/frame
    open var frame: CGRect { get { fatalError() } set { } }
    // doc: UIKit/UIView/window
    open var window: UIWindow? { fatalError() }
    // doc: UIKit/UIView/didMoveToWindow()
    open func didMoveToWindow() { fatalError() }
    // doc-unconfirmed: member of the NSObject UIAccessibility category (UIAccessibilityProtocol); no page is reachable in the docs data
    public var isAccessibilityElement: Bool { get { fatalError() } set { } }
    // doc-unconfirmed: member of the NSObject UIAccessibility category (UIAccessibilityProtocol); no page is reachable in the docs data
    public var accessibilityElementsHidden: Bool { get { fatalError() } set { } }
}
extension UIView {
    // doc: UIKit/UIView/AutoresizingMask-swift.struct
    public struct AutoresizingMask: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/init(rawValue:)
        public init(rawValue: UInt) { self.rawValue = rawValue }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleLeftMargin
        public static var flexibleLeftMargin: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleWidth
        public static var flexibleWidth: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleRightMargin
        public static var flexibleRightMargin: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleTopMargin
        public static var flexibleTopMargin: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleHeight
        public static var flexibleHeight: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
        // doc: UIKit/UIView/AutoresizingMask-swift.struct/flexibleBottomMargin
        public static var flexibleBottomMargin: UIView.AutoresizingMask { AutoresizingMask(rawValue: 0) }
    }
}

// doc: UIKit/UIWindow
@MainActor @preconcurrency @objc open class UIWindow: UIView {
    // shim: designated init required by the subclass chain
    public override init(frame: CGRect) { fatalError() }
    // shim: NSCoding requirement, not an Apple signature
    public required init?(coder: NSCoder) { fatalError() }


}

// doc: UIKit/UIViewController
@MainActor @preconcurrency @objc open class UIViewController: UIResponder, NSCoding {
    // shim: NSCoding.encode and the no-argument init the app calls through the nib initialiser
    public func encode(with coder: NSCoder) { fatalError() }
    // shim: inherited NSObject initializer made explicit so subclasses and callers compile
    public convenience override init() { fatalError() }

    // doc: UIKit/UIViewController/init(coder:)
    public required init?(coder: NSCoder) { fatalError() }
    // doc: UIKit/UIViewController/init(nibName:bundle:)
    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { fatalError() }
    // doc: UIKit/UIViewController/loadView()
    open func loadView() { fatalError() }
    // doc: UIKit/UIViewController/popoverPresentationController
    open var popoverPresentationController: UIPopoverPresentationController? { fatalError() }
    // doc: UIKit/UIViewController/present(_:animated:completion:)
    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) { fatalError() }
    // doc: UIKit/UIViewController/view
    open var view: UIView! { get { fatalError() } set { } }
    // doc: UIKit/UIViewController/viewIfLoaded
    open var viewIfLoaded: UIView? { fatalError() }
}

// doc: UIKit/UIActivityViewController
@preconcurrency open class UIActivityViewController: UIViewController {
    // shim: inherited designated inits
    public required init?(coder: NSCoder) { fatalError() }
    // shim: inherited designated initializer made explicit
    public override init(nibName: String?, bundle: Bundle?) { fatalError() }

    // doc: UIKit/UIActivityViewController/init(activityItems:applicationActivities:)
    public init(activityItems: [Any], applicationActivities: [UIActivity]?) { fatalError() }
    // doc: UIKit/UIActivityViewController/completionWithItemsHandler-swift.property
    open var completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler? { get { fatalError() } set { } }
    // doc: UIKit/UIActivityViewController/CompletionWithItemsHandler-swift.typealias
    public typealias CompletionWithItemsHandler = (UIActivity.ActivityType?, Bool, [Any]?, (any Error)?) -> Void
}

// doc: UIKit/UIActivity
@objc open class UIActivity: NSObject {
    // doc: UIKit/UIActivity/ActivityType-swift.struct
    public struct ActivityType: Hashable, RawRepresentable, Sendable {
        // shim: RawRepresentable storage
        public let rawValue: String
        // shim: RawRepresentable / OptionSet storage
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}
// doc: UIKit/UIPopoverPresentationController
@MainActor @preconcurrency @objc open class UIPopoverPresentationController: NSObject {
    // doc: UIKit/UIPopoverPresentationController/sourceView
    public var sourceView: UIView? { get { fatalError() } set { } }
    // doc: UIKit/UIPopoverPresentationController/sourceRect
    public var sourceRect: CGRect { get { fatalError() } set { } }
    // doc: UIKit/UIPopoverPresentationController/permittedArrowDirections
    public var permittedArrowDirections: UIPopoverArrowDirection { get { fatalError() } set { } }
}
// doc: UIKit/UIPopoverArrowDirection
public struct UIPopoverArrowDirection: OptionSet, Sendable {
    // shim: OptionSet storage
    public let rawValue: UInt
    // doc: UIKit/UIPopoverArrowDirection/init(rawValue:)
    public init(rawValue: UInt) { self.rawValue = rawValue }
    // doc: UIKit/UIPopoverArrowDirection/up
    public static var up: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
    // doc: UIKit/UIPopoverArrowDirection/down
    public static var down: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
    // doc: UIKit/UIPopoverArrowDirection/left
    public static var left: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
    // doc: UIKit/UIPopoverArrowDirection/right
    public static var right: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
    // doc: UIKit/UIPopoverArrowDirection/any
    public static var any: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
    // doc: UIKit/UIPopoverArrowDirection/unknown
    public static var unknown: UIPopoverArrowDirection { UIPopoverArrowDirection(rawValue: 0) }
}

// doc: UIKit/UIColor
@objc open class UIColor: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable {
    // shim: NSSecureCoding / NSCopying requirements
    public static var supportsSecureCoding: Bool { true }
    // shim: NSCoding requirement
    public func encode(with coder: NSCoder) { fatalError() }
    // shim: NSCoding requirement, not an Apple signature
    public required init?(coder: NSCoder) { fatalError() }
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: UIKit/UIColor/init(red:green:blue:alpha:)
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { fatalError() }
    // doc: UIKit/UIColor/init(dynamicProvider:)
    public init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) { fatalError() }
    // doc: UIKit/UIColor/init(white:alpha:)
    public init(white: CGFloat, alpha: CGFloat) { fatalError() }
    // doc: UIKit/UIColor/resolvedColor(with:)
    open func resolvedColor(with traitCollection: UITraitCollection) -> UIColor { fatalError() }
    // doc: UIKit/UIColor/getRed(_:green:blue:alpha:)
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { fatalError() }
    // doc: UIKit/UIColor/black
    open class var black: UIColor { fatalError() }
    // doc: UIKit/UIColor/clear
    open class var clear: UIColor { fatalError() }
    // doc: UIKit/UIColor/white
    open class var white: UIColor { fatalError() }
    // doc: UIKit/UIColor/systemBlue
    open class var systemBlue: UIColor { fatalError() }
}

// doc: UIKit/UITraitCollection
@objc open class UITraitCollection: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable {
    // shim: NSSecureCoding / NSCopying requirements
    public static var supportsSecureCoding: Bool { true }
    // shim: NSCoding requirement
    public func encode(with coder: NSCoder) { fatalError() }
    // shim: NSCoding requirement, not an Apple signature
    public required init?(coder: NSCoder) { fatalError() }
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: UIKit/UITraitCollection/init(userInterfaceStyle:)
    public init(userInterfaceStyle: UIUserInterfaceStyle) { fatalError() }
    // doc: UIKit/UITraitCollection/userInterfaceStyle
    open var userInterfaceStyle: UIUserInterfaceStyle { fatalError() }
    // doc: UIKit/UITraitCollection/accessibilityContrast
    open var accessibilityContrast: UIAccessibilityContrast { fatalError() }
}
// doc: UIKit/UIUserInterfaceStyle
public enum UIUserInterfaceStyle: Int, Sendable {
    // doc: UIKit/UIUserInterfaceStyle/unspecified
    case unspecified
    // doc: UIKit/UIUserInterfaceStyle/light
    case light
    // doc: UIKit/UIUserInterfaceStyle/dark
    case dark
}
// doc: UIKit/UIAccessibilityContrast
public enum UIAccessibilityContrast: Int, Sendable {
    // doc: UIKit/UIAccessibilityContrast/unspecified
    case unspecified
    // doc: UIKit/UIAccessibilityContrast/normal
    case normal
    // doc: UIKit/UIAccessibilityContrast/high
    case high
}
// doc: UIKit/UIKeyboardType
public enum UIKeyboardType: Int, Sendable {
    // doc: UIKit/UIKeyboardType/default
    case `default`
    // doc: UIKit/UIKeyboardType/asciiCapable
    case asciiCapable
    // doc: UIKit/UIKeyboardType/numbersAndPunctuation
    case numbersAndPunctuation
    // doc: UIKit/UIKeyboardType/URL
    case URL
    // doc: UIKit/UIKeyboardType/numberPad
    case numberPad
    // doc: UIKit/UIKeyboardType/phonePad
    case phonePad
    // doc: UIKit/UIKeyboardType/namePhonePad
    case namePhonePad
    // doc: UIKit/UIKeyboardType/emailAddress
    case emailAddress
    // doc: UIKit/UIKeyboardType/decimalPad
    case decimalPad
    // doc: UIKit/UIKeyboardType/twitter
    case twitter
    // doc: UIKit/UIKeyboardType/webSearch
    case webSearch
    // doc: UIKit/UIKeyboardType/asciiCapableNumberPad
    case asciiCapableNumberPad
    // doc: UIKit/UIKeyboardType/alphabet
    public static var alphabet: UIKeyboardType { fatalError() }
}
// doc: UIKit/UIInterfaceOrientation
public enum UIInterfaceOrientation: Int, Sendable {
    // doc: UIKit/UIInterfaceOrientation/unknown
    case unknown
    // doc: UIKit/UIInterfaceOrientation/portrait
    case portrait
    // doc: UIKit/UIInterfaceOrientation/portraitUpsideDown
    case portraitUpsideDown
    // doc: UIKit/UIInterfaceOrientation/landscapeLeft
    case landscapeLeft
    // doc: UIKit/UIInterfaceOrientation/landscapeRight
    case landscapeRight
    // doc: UIKit/UIInterfaceOrientation/isLandscape
    public var isLandscape: Bool { fatalError() }
    // doc: UIKit/UIInterfaceOrientation/isPortrait
    public var isPortrait: Bool { fatalError() }
}

// doc: UIKit/UIGestureRecognizer
@MainActor @preconcurrency @objc open class UIGestureRecognizer: NSObject {

    // doc: UIKit/UIGestureRecognizer/init(target:action:)
    public init(target: Any?, action: Selector?) { fatalError() }
    // doc: UIKit/UIGestureRecognizer/cancelsTouchesInView
    open var cancelsTouchesInView: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIGestureRecognizer/delaysTouchesEnded
    open var delaysTouchesEnded: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIGestureRecognizer/delegate
    open var delegate: (any UIGestureRecognizerDelegate)? { get { fatalError() } set { } }
    // doc: UIKit/UIGestureRecognizer/isEnabled
    open var isEnabled: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIGestureRecognizer/location(in:)
    open func location(in view: UIView?) -> CGPoint { fatalError() }
    // doc: UIKit/UIGestureRecognizer/state-swift.property
    open var state: UIGestureRecognizer.State { get { fatalError() } set { } }
    // doc: UIKit/UIGestureRecognizer/view
    open var view: UIView? { fatalError() }
}
extension UIGestureRecognizer {
    // doc: UIKit/UIGestureRecognizer/State-swift.enum
    public enum State: Int, Sendable {
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/possible
        case possible
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/began
        case began
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/changed
        case changed
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/ended
        case ended
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/cancelled
        case cancelled
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/failed
        case failed
        // doc: UIKit/UIGestureRecognizer/State-swift.enum/recognized
        public static var recognized: UIGestureRecognizer.State { fatalError() }
    }
}

// doc: UIKit/UITapGestureRecognizer
@MainActor @preconcurrency @objc open class UITapGestureRecognizer: UIGestureRecognizer {

    // doc: UIKit/UITapGestureRecognizer/numberOfTapsRequired
    open var numberOfTapsRequired: Int { get { fatalError() } set { } }
    // doc: UIKit/UITapGestureRecognizer/numberOfTouchesRequired
    open var numberOfTouchesRequired: Int { get { fatalError() } set { } }
}

// doc: UIKit/UIPanGestureRecognizer
@MainActor @preconcurrency @objc open class UIPanGestureRecognizer: UIGestureRecognizer {

    // doc: UIKit/UIPanGestureRecognizer/minimumNumberOfTouches
    open var minimumNumberOfTouches: Int { get { fatalError() } set { } }
    // doc: UIKit/UIPanGestureRecognizer/maximumNumberOfTouches
    open var maximumNumberOfTouches: Int { get { fatalError() } set { } }
    // doc: UIKit/UIPanGestureRecognizer/translation(in:)
    open func translation(in view: UIView?) -> CGPoint { fatalError() }
    // doc: UIKit/UIPanGestureRecognizer/setTranslation(_:in:)
    open func setTranslation(_ translation: CGPoint, in view: UIView?) { fatalError() }
    // doc: UIKit/UIPanGestureRecognizer/velocity(in:)
    open func velocity(in view: UIView?) -> CGPoint { fatalError() }
}

// doc: UIKit/UIPinchGestureRecognizer
@MainActor @preconcurrency @objc open class UIPinchGestureRecognizer: UIGestureRecognizer {

    // doc: UIKit/UIPinchGestureRecognizer/scale
    open var scale: CGFloat { get { fatalError() } set { } }
    // doc: UIKit/UIPinchGestureRecognizer/velocity
    open var velocity: CGFloat { fatalError() }
}

// doc: UIKit/UIGestureRecognizerDelegate
@MainActor @preconcurrency @objc public protocol UIGestureRecognizerDelegate: ObjectiveC.NSObjectProtocol {
    // doc: UIKit/UIGestureRecognizerDelegate/gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)
    @objc optional func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    // doc: UIKit/UIGestureRecognizerDelegate/gestureRecognizerShouldBegin(_:)
    @objc optional func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    // doc: UIKit/UIGestureRecognizerDelegate/gestureRecognizer(_:shouldReceive:)-16fuh
    @objc optional func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
}

// doc: UIKit/UITouch
@MainActor @preconcurrency @objc open class UITouch: NSObject {

    // doc: UIKit/UITouch/location(in:)-8rd36
    open func location(in view: UIView?) -> CGPoint { fatalError() }
    // doc: UIKit/UITouch/timestamp
    open var timestamp: TimeInterval { fatalError() }
}

// doc: UIKit/UIEvent
@MainActor @preconcurrency @objc open class UIEvent: NSObject {

    // doc: UIKit/UIEvent/timestamp
    open var timestamp: TimeInterval { fatalError() }
}

// doc: UIKit/UIApplication
@MainActor @preconcurrency @objc open class UIApplication: UIResponder {

    // doc: UIKit/UIApplication/shared
    open class var shared: UIApplication { fatalError() }
    // doc: UIKit/UIApplication/connectedScenes
    open var connectedScenes: Set<UIScene> { fatalError() }
    // doc: UIKit/UIApplication/isIdleTimerDisabled
    open var isIdleTimerDisabled: Bool { get { fatalError() } set { } }
    // doc: UIKit/UIApplication/open(_:options:completionHandler:)#0
    open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey : Any] = [:], completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil) { fatalError() }
    // doc: UIKit/UIApplication/open(_:options:completionHandler:)#1
    open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey : Any] = [:]) async -> Bool { fatalError() }
    // doc: UIKit/UIApplication/openSettingsURLString
    open nonisolated class var openSettingsURLString: String { fatalError() }
}
extension UIApplication {
    // doc: UIKit/UIApplication/OpenExternalURLOptionsKey
    public struct OpenExternalURLOptionsKey: Hashable, RawRepresentable, Sendable {
        // shim: RawRepresentable storage
        public let rawValue: String
        // shim: RawRepresentable / OptionSet storage
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}

// doc: UIKit/UIScene
@MainActor @preconcurrency @objc open class UIScene: UIResponder {

    // doc: UIKit/UIScene/activationState-swift.property
    open var activationState: UIScene.ActivationState { fatalError() }
}
extension UIScene {
    // doc: UIKit/UIScene/ActivationState-swift.enum
    public enum ActivationState: Int, Sendable {
        // doc: UIKit/UIScene/ActivationState-swift.enum/unattached
        case unattached
        // doc: UIKit/UIScene/ActivationState-swift.enum/foregroundInactive
        case foregroundInactive
        // doc: UIKit/UIScene/ActivationState-swift.enum/foregroundActive
        case foregroundActive
        // doc: UIKit/UIScene/ActivationState-swift.enum/background
        case background
    }
}

// doc: UIKit/UIWindowScene
@MainActor @preconcurrency @objc open class UIWindowScene: UIScene {

    // doc: UIKit/UIWindowScene/interfaceOrientation
    open var interfaceOrientation: UIInterfaceOrientation { fatalError() }
}

// doc: UIKit/UIAccessibility
public struct UIAccessibility {
    // doc: UIKit/UIAccessibility/Notification
    public struct Notification: Hashable, RawRepresentable, Sendable {
        // shim: RawRepresentable storage
        public let rawValue: UInt32
        // shim: RawRepresentable / OptionSet storage
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        // doc: UIKit/UIAccessibility/Notification/announcement
        public nonisolated static var announcement: UIAccessibility.Notification { Notification(rawValue: 0) }
    }
    // doc: UIKit/UIAccessibility/isVoiceOverRunning
    @MainActor @preconcurrency public static var isVoiceOverRunning: Bool { fatalError() }
    // doc: UIKit/UIAccessibility/post(notification:argument:)
    @MainActor @preconcurrency public static func post(notification: UIAccessibility.Notification, argument: Any?) { fatalError() }
}

// doc: UIKit/UIFeedbackGenerator
@MainActor @preconcurrency @objc open class UIFeedbackGenerator: NSObject {

    // doc: UIKit/UIFeedbackGenerator/init()
    public override init() { fatalError() }
    // doc: UIKit/UIFeedbackGenerator/prepare()
    open func prepare() { fatalError() }
}

// doc: UIKit/UIImpactFeedbackGenerator
@MainActor @preconcurrency @objc open class UIImpactFeedbackGenerator: UIFeedbackGenerator {

    // doc: UIKit/UIImpactFeedbackGenerator/init(style:)
    public init(style: UIImpactFeedbackGenerator.FeedbackStyle) { fatalError() }
    // doc: UIKit/UIImpactFeedbackGenerator/impactOccurred()
    open func impactOccurred() { fatalError() }
}
extension UIImpactFeedbackGenerator {
    // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle
    public enum FeedbackStyle: Int, Sendable {
        // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle/heavy
        case heavy
        // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle/light
        case light
        // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle/medium
        case medium
        // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle/rigid
        case rigid
        // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle/soft
        case soft
    }
}

// doc: UIKit/UINotificationFeedbackGenerator
@MainActor @preconcurrency @objc open class UINotificationFeedbackGenerator: UIFeedbackGenerator {

    // doc: UIKit/UINotificationFeedbackGenerator/notificationOccurred(_:)
    open func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) { fatalError() }
}
extension UINotificationFeedbackGenerator {
    // doc: UIKit/UINotificationFeedbackGenerator/FeedbackType
    public enum FeedbackType: Int, Sendable {
        // doc: UIKit/UINotificationFeedbackGenerator/FeedbackType/error
        case error
        // doc: UIKit/UINotificationFeedbackGenerator/FeedbackType/success
        case success
        // doc: UIKit/UINotificationFeedbackGenerator/FeedbackType/warning
        case warning
    }
}

// doc: UIKit/UISelectionFeedbackGenerator
@MainActor @preconcurrency @objc open class UISelectionFeedbackGenerator: UIFeedbackGenerator {

    // doc: UIKit/UISelectionFeedbackGenerator/selectionChanged()
    open func selectionChanged() { fatalError() }
}
