// SHIM of SwiftUI, part 2: the protocols that app code adopts (ShapeStyle, Shape, Gesture, ButtonStyle, the
// representable protocols, ...). Hand-written; requirement lines are copied from the documentation pages named in
// their `// doc:` tags, `// shim:` marks scaffolding. See Core.swift for the conventions.
@_exported import Foundation
import UIKit

// MARK: - ShapeStyle

// doc: SwiftUI/ShapeStyle
public protocol ShapeStyle: Sendable {
    // doc-unconfirmed: `Resolved` is the iOS 17 associated type behind resolve(in:); the docs list resolve(in:) but not the
    // associated type's default, so a default of Never is assumed (that is what lets Color etc. conform without naming it)
    associatedtype Resolved: ShapeStyle = Never
}
extension ShapeStyle {
    // doc: SwiftUI/ShapeStyle/resolve(in:)
    public func resolve(in environment: EnvironmentValues) -> Self.Resolved { fatalError() }
}
// shim: Never is the Resolved type of leaf styles
extension Never: ShapeStyle {}

// MARK: - Shapes

// shim: the View that backs `Shape.body` and `Shape.fill(_:)` (Apple's is also named _ShapeView)
public struct _ShapeView<Content: Shape, Style: ShapeStyle>: _PrimitiveView {}

// doc: SwiftUI/Shape
public protocol Shape: Sendable, Animatable, View {
    // doc: SwiftUI/Shape/path(in:)
    nonisolated func path(in rect: CGRect) -> Path
    // doc: SwiftUI/Shape/role
    nonisolated static var role: ShapeRole { get }
    // doc: SwiftUI/Shape/layoutDirectionBehavior
    nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { get }
    // doc: SwiftUI/Shape/sizeThatFits(_:)
    nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
}
extension Shape {
    // shim: default implementations of the optional requirements
    public static var role: ShapeRole { fatalError() }
    // shim: default implementations of the optional requirements
    public var layoutDirectionBehavior: LayoutDirectionBehavior { fatalError() }
    // shim: default implementations of the optional requirements
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { fatalError() }
    // shim: every Shape is a View whose Body is Apple's private _ShapeView
    public var body: _ShapeView<Self, ForegroundStyle> { fatalError() }
}

// doc: SwiftUI/InsettableShape
public protocol InsettableShape: Shape {
    // doc: SwiftUI/InsettableShape/InsetShape
    associatedtype InsetShape: InsettableShape
    // doc: SwiftUI/InsettableShape/inset(by:)
    nonisolated func inset(by amount: CGFloat) -> Self.InsetShape
}

// MARK: - Gestures

// doc: SwiftUI/Gesture
@MainActor @preconcurrency public protocol Gesture<Value> {
    // doc: SwiftUI/Gesture/Value
    associatedtype Value
    // doc: SwiftUI/Gesture/Body-swift.associatedtype
    associatedtype Body: Gesture
    // doc: SwiftUI/Gesture/body-swift.property
    @MainActor @preconcurrency var body: Self.Body { get }
}
// shim: primitive gestures have Body == Never
public protocol _PrimitiveGesture: Gesture where Body == Never {}
extension _PrimitiveGesture {
    // shim: primitive body
    public var body: Never { return fatalError() }
}
// shim: the gesture produced by `onEnded`
public struct _EndedGesture<Content: Gesture>: _PrimitiveGesture { public typealias Value = Content.Value }
// shim: the gesture produced by `onChanged`
public struct _ChangedGesture<Content: Gesture>: _PrimitiveGesture { public typealias Value = Content.Value }

// MARK: - Button styles

// doc: SwiftUI/ButtonStyle
@MainActor @preconcurrency public protocol ButtonStyle {
    // doc: SwiftUI/ButtonStyle/Body
    associatedtype Body: View
    // doc: SwiftUI/ButtonStyle/Configuration
    typealias Configuration = ButtonStyleConfiguration
    // doc: SwiftUI/ButtonStyle/makeBody(configuration:)
    @ContentBuilder @MainActor @preconcurrency func makeBody(configuration: Self.Configuration) -> Self.Body
}

// MARK: - Layout

// doc: SwiftUI/Layout
@preconcurrency public protocol Layout: Sendable, Animatable {
    // doc: SwiftUI/Layout/Cache
    associatedtype Cache = Void
    // doc: SwiftUI/Layout/Subviews
    typealias Subviews = LayoutSubviews
    // doc: SwiftUI/Layout/sizeThatFits(proposal:subviews:cache:)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize
    // doc: SwiftUI/Layout/placeSubviews(in:proposal:subviews:cache:)
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)
}

// MARK: - Styles

// doc: SwiftUI/ListStyle
public protocol ListStyle {}
// doc: SwiftUI/PickerStyle
public protocol PickerStyle {}

// MARK: - Timelines

// doc: SwiftUI/TimelineSchedule
public protocol TimelineSchedule {
    // doc: SwiftUI/TimelineSchedule/Entries
    associatedtype Entries: Sequence where Self.Entries.Element == Date
    // doc: SwiftUI/TimelineSchedule/Mode
    typealias Mode = TimelineScheduleMode
    // doc: SwiftUI/TimelineSchedule/entries(from:mode:)
    func entries(from startDate: Date, mode: Self.Mode) -> Self.Entries
}

// MARK: - Toolbars

// doc: SwiftUI/ToolbarContent
@MainActor @preconcurrency public protocol ToolbarContent {
    // doc: SwiftUI/ToolbarContent/Body-swift.associatedtype
    associatedtype Body: ToolbarContent
    // doc: SwiftUI/ToolbarContent/body-swift.property
    @ContentBuilder @MainActor @preconcurrency var body: Self.Body { get }
}
// shim: primitive toolbar content has Body == Never
public protocol _PrimitiveToolbarContent: ToolbarContent where Body == Never {}
extension _PrimitiveToolbarContent {
    // shim: primitive body
    public var body: Never { return fatalError() }
}

// doc: SwiftUI/ToolbarContentBuilder
@resultBuilder public struct ToolbarContentBuilder {
    // doc-unconfirmed: not listed on the ToolbarContentBuilder page in this snapshot; ToolbarContentBuilder is the builder behind `content:` of View.toolbar
    public static func buildBlock<each Content>(_ content: repeat each Content) -> _ToolbarContentTuple<repeat each Content> where repeat each Content: ToolbarContent { fatalError() }
    // doc-unconfirmed: see buildBlock
    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: ToolbarContent { content }
    // doc-unconfirmed: see buildBlock
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalToolbarContent<TrueContent, FalseContent> where TrueContent: ToolbarContent, FalseContent: ToolbarContent { fatalError() }
    // doc-unconfirmed: see buildBlock
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalToolbarContent<TrueContent, FalseContent> where TrueContent: ToolbarContent, FalseContent: ToolbarContent { fatalError() }
}
// shim: tuple of toolbar contents (Apple's is ToolbarContentBuilder's private tuple type)
public struct _ToolbarContentTuple<each Content: ToolbarContent>: _PrimitiveToolbarContent {}
// shim: conditional toolbar content
public struct _ConditionalToolbarContent<TrueContent: ToolbarContent, FalseContent: ToolbarContent>: _PrimitiveToolbarContent {}
// shim: Optional of toolbar content is toolbar content
extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { fatalError() }
}

// MARK: - Environment

// doc: SwiftUI/EnvironmentKey
public protocol EnvironmentKey {
    // doc: SwiftUI/EnvironmentKey/Value
    associatedtype Value
    // doc: SwiftUI/EnvironmentKey/defaultValue
    static var defaultValue: Self.Value { get }
}

// MARK: - Preferences

// doc: SwiftUI/PreferenceKey
public protocol PreferenceKey {
    // doc: SwiftUI/PreferenceKey/Value
    associatedtype Value
    // doc: SwiftUI/PreferenceKey/defaultValue
    static var defaultValue: Self.Value { get }
    // doc: SwiftUI/PreferenceKey/reduce(value:nextValue:)
    static func reduce(value: inout Self.Value, nextValue: () -> Self.Value)
}
extension View {
    // doc: SwiftUI/View/onPreferenceChange(_:perform:)
    public nonisolated func onPreferenceChange<K>(_ key: K.Type = K.self, perform action: @escaping (K.Value) -> Void) -> some View where K : PreferenceKey, K.Value : Equatable { self }
    // doc: SwiftUI/View/preference(key:value:)
    public nonisolated func preference<K>(key: K.Type = K.self, value: K.Value) -> some View where K : PreferenceKey { self }
}

// MARK: - UIKit bridging

// doc: SwiftUI/UIViewRepresentable
@MainActor @preconcurrency public protocol UIViewRepresentable: View where Self.Body == Never {
    // doc: SwiftUI/UIViewRepresentable/UIViewType
    associatedtype UIViewType: UIView
    // doc: SwiftUI/UIViewRepresentable/Coordinator
    associatedtype Coordinator = Void
    // doc: SwiftUI/UIViewRepresentable/Context
    typealias Context = UIViewRepresentableContext<Self>
    // doc: SwiftUI/UIViewRepresentable/makeUIView(context:)
    @MainActor @preconcurrency func makeUIView(context: Self.Context) -> Self.UIViewType
    // doc: SwiftUI/UIViewRepresentable/updateUIView(_:context:)
    @MainActor @preconcurrency func updateUIView(_ uiView: Self.UIViewType, context: Self.Context)
    // doc: SwiftUI/UIViewRepresentable/makeCoordinator()
    @MainActor @preconcurrency func makeCoordinator() -> Self.Coordinator
    // doc: SwiftUI/UIViewRepresentable/dismantleUIView(_:coordinator:)
    @MainActor @preconcurrency static func dismantleUIView(_ uiView: Self.UIViewType, coordinator: Self.Coordinator)
    // doc: SwiftUI/UIViewRepresentable/sizeThatFits(_:uiView:context:)
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, uiView: Self.UIViewType, context: Self.Context) -> CGSize?
}
extension UIViewRepresentable where Self.Coordinator == Void {
    // shim: documented default: a representable without a coordinator
    @MainActor @preconcurrency public func makeCoordinator() -> Void { () }
}
extension UIViewRepresentable {
    // shim: documented defaults for the optional requirements
    @MainActor @preconcurrency public static func dismantleUIView(_ uiView: Self.UIViewType, coordinator: Self.Coordinator) {}
    // shim: documented defaults for the optional requirements
    @MainActor @preconcurrency public func sizeThatFits(_ proposal: ProposedViewSize, uiView: Self.UIViewType, context: Self.Context) -> CGSize? { nil }
    // shim: representables have Body == Never
    @MainActor @preconcurrency public var body: Never { fatalError() }
}

// doc: SwiftUI/UIViewRepresentableContext
@MainActor @preconcurrency public struct UIViewRepresentableContext<Representable> where Representable: UIViewRepresentable {
    // doc: SwiftUI/UIViewRepresentableContext/coordinator
    @MainActor @preconcurrency public let coordinator: Representable.Coordinator
    // doc: SwiftUI/UIViewRepresentableContext/transaction
    @MainActor @preconcurrency public var transaction: Transaction { fatalError() }
    // doc: SwiftUI/UIViewRepresentableContext/environment
    @MainActor @preconcurrency public var environment: EnvironmentValues { fatalError() }
}

// doc: SwiftUI/UIViewControllerRepresentable
@MainActor @preconcurrency public protocol UIViewControllerRepresentable: View where Self.Body == Never {
    // doc: SwiftUI/UIViewControllerRepresentable/UIViewControllerType
    associatedtype UIViewControllerType: UIViewController
    // doc: SwiftUI/UIViewControllerRepresentable/Coordinator
    associatedtype Coordinator = Void
    // doc: SwiftUI/UIViewControllerRepresentable/Context
    typealias Context = UIViewControllerRepresentableContext<Self>
    // doc: SwiftUI/UIViewControllerRepresentable/makeUIViewController(context:)
    @MainActor @preconcurrency func makeUIViewController(context: Self.Context) -> Self.UIViewControllerType
    // doc: SwiftUI/UIViewControllerRepresentable/updateUIViewController(_:context:)
    @MainActor @preconcurrency func updateUIViewController(_ uiViewController: Self.UIViewControllerType, context: Self.Context)
    // doc: SwiftUI/UIViewControllerRepresentable/makeCoordinator()
    @MainActor @preconcurrency func makeCoordinator() -> Self.Coordinator
    // doc: SwiftUI/UIViewControllerRepresentable/dismantleUIViewController(_:coordinator:)
    @MainActor @preconcurrency static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator)
}
extension UIViewControllerRepresentable where Self.Coordinator == Void {
    // shim: documented default: a representable without a coordinator
    @MainActor @preconcurrency public func makeCoordinator() -> Void { () }
}
extension UIViewControllerRepresentable {
    // shim: documented defaults for the optional requirements
    @MainActor @preconcurrency public static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {}
    // shim: representables have Body == Never
    @MainActor @preconcurrency public var body: Never { fatalError() }
}

// doc: SwiftUI/UIViewControllerRepresentableContext
@MainActor @preconcurrency public struct UIViewControllerRepresentableContext<Representable> where Representable: UIViewControllerRepresentable {
    // doc: SwiftUI/UIViewControllerRepresentableContext/coordinator
    @MainActor @preconcurrency public let coordinator: Representable.Coordinator
    // doc: SwiftUI/UIViewControllerRepresentableContext/transaction
    @MainActor @preconcurrency public var transaction: Transaction { fatalError() }
    // doc: SwiftUI/UIViewControllerRepresentableContext/environment
    @MainActor @preconcurrency public var environment: EnvironmentValues { fatalError() }
}

// MARK: - #Preview

// doc: DeveloperToolsSupport/Preview
@MainActor public struct Preview {
    // doc: DeveloperToolsSupport/Preview/ViewTraits
    public enum ViewTraits {}
    // doc: DeveloperToolsSupport/Preview/init(_:traits:body:)-8pemr
    @MainActor public init(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., body: @escaping @MainActor () -> any View) { fatalError() }
}
// doc: DeveloperToolsSupport/PreviewTrait
@MainActor public struct PreviewTrait<T> {}

// doc: SwiftUI/Preview(_:body:)
@freestanding(declaration) public macro Preview(_ name: String? = nil, @ContentBuilder body: @escaping @MainActor () -> any View) = #externalMacro(module: "PreviewsMacros", type: "PreviewMacro")

// shim: the #Preview expansion (see ../_macros/PreviewsMacros.swift) wraps the closure body in this ViewBuilder so that
// multi-statement preview bodies type-check the way the real macro's builder allows
@MainActor public func _previewBody<V: View>(@ViewBuilder _ body: () -> V) -> any View { body() }

// MARK: - UIColor(Color), ContentUnavailableView.search

extension UIColor {
    // doc: UIKit/UIColor/init(_:)
    public convenience init(_ color: Color) { self.init(white: 0, alpha: 1) }
}

// shim: Apple nests SearchUnavailableContent (with its Label, Description and Actions views) inside the generic
// ContentUnavailableView. Nested there, the constrained extension below is circular (the compiler crashes on it), so the
// type is declared at top level and aliased into ContentUnavailableView under the documented name.
public struct _SearchUnavailableContent {
    // doc: SwiftUI/SearchUnavailableContent/Label
    public struct Label {}
    // doc: SwiftUI/SearchUnavailableContent/Description
    public struct Description {}
    // doc: SwiftUI/SearchUnavailableContent/Actions
    public struct Actions {}
}
// shim: the three nested views of the search placeholder are primitive views
extension _SearchUnavailableContent.Label: _PrimitiveView {}
// shim: see above
extension _SearchUnavailableContent.Description: _PrimitiveView {}
// shim: see above
extension _SearchUnavailableContent.Actions: _PrimitiveView {}
extension ContentUnavailableView {
    // shim: the documented nested name SearchUnavailableContent
    public typealias SearchUnavailableContent = _SearchUnavailableContent
}
extension ContentUnavailableView where Label == _SearchUnavailableContent.Label, Description == _SearchUnavailableContent.Description, Actions == _SearchUnavailableContent.Actions {
    // doc: SwiftUI/ContentUnavailableView/search
    public static var search: ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions> { fatalError() }
    // doc: SwiftUI/ContentUnavailableView/search(text:)
    public static func search(text: String) -> ContentUnavailableView<Label, Description, Actions> { fatalError() }
}
