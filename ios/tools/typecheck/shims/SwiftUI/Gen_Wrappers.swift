// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/State
@propertyWrapper public struct State<Value>: DynamicProperty {
    // doc: SwiftUI/State/init(wrappedValue:)
    public init(wrappedValue value: Value) { fatalError() }
    // doc: SwiftUI/State/init(initialValue:)
    public init(initialValue value: Value) { fatalError() }
    // doc: SwiftUI/State/wrappedValue
    public var wrappedValue: Value { get { fatalError() } nonmutating set { } }
    // doc: SwiftUI/State/projectedValue
    public var projectedValue: Binding<Value> { fatalError() }
}
extension State where Value: ExpressibleByNilLiteral {
    // doc: SwiftUI/State/init()
    public init() { fatalError() }
}

// doc: SwiftUI/Binding
@propertyWrapper @dynamicMemberLookup public struct Binding<Value>: DynamicProperty {
    // doc: SwiftUI/Binding/init(_:)
    public init<V>(_ base: Binding<V>) where Value == AnyHashable, V : Hashable { fatalError() }
    // doc: SwiftUI/Binding/init(projectedValue:)
    public init(projectedValue: Binding<Value>) { fatalError() }
    // doc: SwiftUI/Binding/init(get:set:)
    @preconcurrency public init(get: @escaping @isolated(any) @Sendable () -> Value, set: @escaping @isolated(any) @Sendable (Value) -> Void) { fatalError() }
    // doc: SwiftUI/Binding/constant(_:)
    public static func constant(_ value: Value) -> Binding<Value> { fatalError() }
    // doc: SwiftUI/Binding/wrappedValue
    public var wrappedValue: Value { get { fatalError() } nonmutating set { } }
    // doc: SwiftUI/Binding/projectedValue
    public var projectedValue: Binding<Value> { fatalError() }
    // doc: SwiftUI/Binding/subscript(dynamicMember:)
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { fatalError() }
    // doc: SwiftUI/Binding/animation(_:)
    public func animation(_ animation: Animation? = .default) -> Binding<Value> { fatalError() }
    // doc: SwiftUI/Binding/transaction(_:)
    public func transaction(_ transaction: Transaction) -> Binding<Value> { fatalError() }
    // doc: SwiftUI/Binding/transaction
    public var transaction: Transaction { get { fatalError() } set { } }
    // doc: SwiftUI/Binding/init(get:set:)-6g3d5
    @preconcurrency public init(get: @escaping @isolated(any) @Sendable () -> Value, set: @escaping @isolated(any) @Sendable (Value, Transaction) -> Void) { fatalError() }
    // doc: SwiftUI/Binding/init(_:)-5z9t9
    public init?(_ base: Binding<Value?>) { fatalError() }
    // doc: SwiftUI/Binding/init(_:)-6krsi
    public init<V>(_ base: Binding<V>) where Value == V? { fatalError() }
}
extension Binding where Value: Identifiable {
    // doc: SwiftUI/Binding/id
    public var id: Value.ID { fatalError() }
}

// doc: SwiftUI/Environment
@propertyWrapper public struct Environment<Value>: DynamicProperty {
    // doc: SwiftUI/Environment/init(_:)
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { fatalError() }
    // doc: SwiftUI/Environment/wrappedValue
    public var wrappedValue: Value { fatalError() }
    // doc: SwiftUI/Environment/init(_:)-7pint
    public init(_ objectType: Value.Type) where Value : AnyObject, Value : Observable { fatalError() }
    // doc: SwiftUI/Environment/init(_:)-8slkf
    public init<T>(_ objectType: T.Type) where Value == T?, T : AnyObject, T : Observable { fatalError() }
}

// doc: SwiftUI/Bindable
@dynamicMemberLookup @propertyWrapper public struct Bindable<Value> {
    // shim: a stored property so the type has no implicit init() (property wrappers require it to be public)
    private var _shim: Int
    // doc: SwiftUI/Bindable/wrappedValue
    public var wrappedValue: Value { get { fatalError() } set { } }
    // doc: SwiftUI/Bindable/projectedValue
    public var projectedValue: Bindable<Value> { fatalError() }
    // doc: SwiftUI/Bindable/subscript(dynamicMember:)
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> { fatalError() }
}
extension Bindable where Value: Observable {
    // doc: SwiftUI/Bindable/init(_:)
    public init(_ wrappedValue: Value) { fatalError() }
    // doc: SwiftUI/Bindable/init(wrappedValue:)
    public init(wrappedValue: Value) { fatalError() }
    // doc: SwiftUI/Bindable/init(projectedValue:)
    public init(projectedValue: Bindable<Value>) { fatalError() }
}

// doc: SwiftUI/FocusState
@propertyWrapper public struct FocusState<Value>: DynamicProperty where Value: Hashable {
    // doc: SwiftUI/FocusState/init()
    public init() where Value == Bool { fatalError() }
    // doc: SwiftUI/FocusState/projectedValue
    public var projectedValue: FocusState<Value>.Binding { fatalError() }
    // doc: SwiftUI/FocusState/Binding
    @propertyWrapper public struct Binding {
        // shim: a stored property so the type has no implicit init() (property wrappers require it to be public)
        private var _shim: Int
        // doc: SwiftUI/FocusState/Binding/projectedValue
        public var projectedValue: FocusState<Value>.Binding { fatalError() }
        // doc: SwiftUI/FocusState/Binding/wrappedValue
        public var wrappedValue: Value { get { fatalError() } nonmutating set { } }
    }
    // doc: SwiftUI/FocusState/wrappedValue
    public var wrappedValue: Value { get { fatalError() } nonmutating set { } }
    // doc: SwiftUI/FocusState/init()-2v5rw
    public init<T>() where Value == T?, T : Hashable { fatalError() }
}

// doc: SwiftUI/ScaledMetric
@propertyWrapper public struct ScaledMetric<Value>: DynamicProperty where Value: BinaryFloatingPoint {
    // doc: SwiftUI/ScaledMetric/init(wrappedValue:)
    public init(wrappedValue: Value) { fatalError() }
    // doc: SwiftUI/ScaledMetric/init(wrappedValue:relativeTo:)
    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) { fatalError() }
    // doc: SwiftUI/ScaledMetric/wrappedValue
    public var wrappedValue: Value { fatalError() }
}

// doc: SwiftUI/EnvironmentValues
public struct EnvironmentValues {
    // doc: SwiftUI/EnvironmentValues/init()
    public init() { fatalError() }
    // doc: SwiftUI/EnvironmentValues/subscript(_:)
    @_disfavoredOverload public subscript<K>(key: K.Type) -> K.Value where K : EnvironmentKey { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/description
    public var description: String { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityAssistiveAccessEnabled  [iOS 18.0]
    public var accessibilityAssistiveAccessEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityDimFlashingLights
    public var accessibilityDimFlashingLights: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityDifferentiateWithoutColor
    public var accessibilityDifferentiateWithoutColor: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityEnabled
    public var accessibilityEnabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/accessibilityInvertColors
    public var accessibilityInvertColors: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityLargeContentViewerEnabled
    public var accessibilityLargeContentViewerEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityPlayAnimatedImages
    public var accessibilityPlayAnimatedImages: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityPrefersCrossFadeTransitions  [iOS 26.4]
    public var accessibilityPrefersCrossFadeTransitions: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/accessibilityQuickActionsEnabled
    public var accessibilityQuickActionsEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityReduceMotion
    public var accessibilityReduceMotion: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityReduceTransparency
    public var accessibilityReduceTransparency: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilitySwitchControlEnabled
    public var accessibilitySwitchControlEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityVoiceOverEnabled
    public var accessibilityVoiceOverEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/dismiss
    public var dismiss: DismissAction { fatalError() }
    // doc: SwiftUI/EnvironmentValues/refresh
    public var refresh: RefreshAction? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/overlayArrangementZIndex  [iOS 27.1]
    public var overlayArrangementZIndex: Int { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/splitArrangementAxis  [iOS 27.1]
    public var splitArrangementAxis: Axis? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/controlSize
    public var controlSize: ControlSize { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/keyboardShortcut
    public var keyboardShortcut: KeyboardShortcut? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/menuIndicatorVisibility
    public var menuIndicatorVisibility: Visibility { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/appearsActive  [iOS 18.0]
    @backDeployed(before: macOS 15.0) public var appearsActive: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/colorScheme
    public var colorScheme: ColorScheme { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/colorSchemeContrast
    public var colorSchemeContrast: ColorSchemeContrast { fatalError() }
    // doc: SwiftUI/EnvironmentValues/displayScale
    public var displayScale: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/horizontalSizeClass
    @backDeployed(before: macOS 14.0, tvOS 17.0, watchOS 10.0) public var horizontalSizeClass: UserInterfaceSizeClass? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/imageScale
    public var imageScale: Image.Scale { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/pixelLength
    public var pixelLength: CGFloat { fatalError() }
    // doc: SwiftUI/EnvironmentValues/verticalSizeClass
    @backDeployed(before: macOS 14.0, tvOS 17.0, watchOS 10.0) public var verticalSizeClass: UserInterfaceSizeClass? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/labelsVisibility  [iOS 18.0]
    public var labelsVisibility: Visibility { get { fatalError() } set { } }
    // doc: SwiftUI/TabBarPlacement
    public struct TabBarPlacement: Equatable, Hashable {
        // doc: SwiftUI/TabBarPlacement/bottomBar  [iOS 18.0]
        public static var bottomBar: TabBarPlacement { fatalError() }
        // doc: SwiftUI/TabBarPlacement/ornament  [iOS 18.0]
        public static var ornament: TabBarPlacement { fatalError() }
        // doc: SwiftUI/TabBarPlacement/pageIndicator  [iOS 18.0]
        public static var pageIndicator: TabBarPlacement { fatalError() }
        // doc: SwiftUI/TabBarPlacement/sidebar  [iOS 18.0]
        public static var sidebar: TabBarPlacement { fatalError() }
        // doc: SwiftUI/TabBarPlacement/topBar  [iOS 18.0]
        public static var topBar: TabBarPlacement { fatalError() }
    }
    // doc: SwiftUI/EnvironmentValues/toolbarVerticalEdge  [iOS 27.1]
    public var toolbarVerticalEdge: HorizontalEdge? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/calendar
    public var calendar: Calendar { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/locale
    public var locale: Locale { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/timeZone
    public var timeZone: TimeZone { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isScrollEnabled
    public var isScrollEnabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/horizontalScrollIndicatorVisibility
    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/verticalScrollIndicatorVisibility
    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/scrollDismissesKeyboardMode
    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/horizontalScrollBounceBehavior
    public var horizontalScrollBounceBehavior: ScrollBounceBehavior { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/verticalScrollBounceBehavior
    public var verticalScrollBounceBehavior: ScrollBounceBehavior { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isActivityFullscreen
    @backDeployed(before: iOS 17.0) public var isActivityFullscreen: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isEnabled
    public var isEnabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isFocused
    public var isFocused: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isFocusEffectEnabled
    public var isFocusEffectEnabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isHoverEffectEnabled
    public var isHoverEffectEnabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isLuminanceReduced
    public var isLuminanceReduced: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isPresented
    public var isPresented: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isSceneCaptured
    public var isSceneCaptured: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isSearching
    public var isSearching: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isTabBarShowingSections  [iOS 18.0]
    public var isTabBarShowingSections: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/scenePhase
    public var scenePhase: ScenePhase { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/supportsMultipleWindows
    public var supportsMultipleWindows: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/allowsTightening
    public var allowsTightening: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/autocorrectionDisabled
    public var autocorrectionDisabled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/dynamicTypeSize
    public var dynamicTypeSize: DynamicTypeSize { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/font
    public var font: Font? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/layoutDirection
    public var layoutDirection: LayoutDirection { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/lineLimit
    public var lineLimit: Int? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/lineSpacing
    public var lineSpacing: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/minimumScaleFactor
    public var minimumScaleFactor: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/multilineTextAlignment
    public var multilineTextAlignment: TextAlignment { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/textCase
    public var textCase: Text.Case? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/truncationMode
    public var truncationMode: Text.TruncationMode { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/allowedDynamicRange
    public var allowedDynamicRange: Image.DynamicRange? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/backgroundMaterial
    public var backgroundMaterial: Material? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/backgroundStyle
    public var backgroundStyle: AnyShapeStyle? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/contentTransitionAddsDrawingGroup
    public var contentTransitionAddsDrawingGroup: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/defaultMinListHeaderHeight
    public var defaultMinListHeaderHeight: CGFloat? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/defaultMinListRowHeight
    public var defaultMinListRowHeight: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/symbolRenderingMode
    public var symbolRenderingMode: SymbolRenderingMode? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/symbolVariants
    public var symbolVariants: SymbolVariants { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/showsWidgetContainerBackground
    public var showsWidgetContainerBackground: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/showsWidgetLabel
    public var showsWidgetLabel: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/widgetContentMargins
    public var widgetContentMargins: EdgeInsets { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityShowButtonShapes
    public var accessibilityShowButtonShapes: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/disableAutocorrection
    public var disableAutocorrection: Bool? { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/presentationMode
    public var presentationMode: Binding<PresentationMode> { fatalError() }
    // doc: SwiftUI/PresentationMode
    public struct PresentationMode {
        // doc: SwiftUI/PresentationMode/isPresented
        public var isPresented: Bool { fatalError() }
        // doc: SwiftUI/PresentationMode/dismiss()
        public mutating func dismiss() { fatalError() }
    }
    // doc: SwiftUI/EnvironmentValues/accessibilityReduceHighlightingEffects  [iOS 26.4]
    public var accessibilityReduceHighlightingEffects: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/accessibilityShowBorders
    @backDeployed(before: iOS 26.1, macOS 26.1, tvOS 26.1, watchOS 26.1, visionOS 26.1) public var accessibilityShowBorders: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/fontResolutionContext
    public var fontResolutionContext: Font.Context { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isActivityUpdateReduced  [iOS 18.0]
    public var isActivityUpdateReduced: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/isDynamicIslandLimitedInWidth  [iOS 27.0]
    public var isDynamicIslandLimitedInWidth: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isTabViewSidebarAvailable  [iOS 27.0]
    public var isTabViewSidebarAvailable: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/isUserAuthenticationEnabled  [iOS 18.0]
    public var isUserAuthenticationEnabled: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/labelIconToTitleSpacing  [iOS 26.0]
    public var labelIconToTitleSpacing: CGFloat? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/labelReservedIconWidth  [iOS 26.0]
    public var labelReservedIconWidth: CGFloat? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/navigationLinkIndicatorVisibility
    public var navigationLinkIndicatorVisibility: Visibility { fatalError() }
    // doc: SwiftUI/EnvironmentValues/supportsImagePlayground  [iOS 18.1]
    public var supportsImagePlayground: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/supportsRemoteScenes  [iOS 26.0]
    public var supportsRemoteScenes: Bool { fatalError() }
    // doc: SwiftUI/EnvironmentValues/systemPrefersReducedResourceUsage  [iOS 27.0]
    public var systemPrefersReducedResourceUsage: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/EnvironmentValues/tabBarPlacement  [iOS 18.0]
    public var tabBarPlacement: TabBarPlacement? { fatalError() }
    // doc: SwiftUI/EnvironmentValues/subscript(_:)-43hzl
    public subscript<T>(objectType: T.Type) -> T? where T : AnyObject, T : Observable { get { fatalError() } set { } }
}
