// SHIM of SwiftUI, part 1: the protocols, result builders and plumbing that every view uses.
//
// Written by hand; every Apple declaration carries a `// doc:` tag naming the documentation page it was copied from
// (docs/verify_shims.py re-checks the text). Lines tagged `// shim:` are scaffolding that is not an Apple signature,
// and `// doc-unconfirmed:` marks what the documentation snapshot does not show (listed in ../../README.md).
//
// Bodies are `fatalError()` or `self`: this module exists to be type-checked against, never to run.
//
// Isolation follows the documentation exactly: `View`, `ViewModifier`, `App`, `Scene` are
// `@MainActor @preconcurrency`, so a struct that conforms in its primary declaration is main-actor isolated and
// `Text`, `VStack` ... (which the docs show as `nonisolated`) conform in extensions instead. Swift 6.0 cannot
// spell `nonisolated struct`, so the keyword is left off the shim's type headers (the verifier ignores it there).
@_exported import Foundation

// MARK: - Views

// doc: SwiftUI/View
@MainActor @preconcurrency public protocol View {
    // doc: SwiftUI/View/Body-swift.associatedtype
    associatedtype Body: View
    // doc: SwiftUI/View/body-8kl5o
    @ContentBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

// shim: `Never` is the Body of every primitive view, scene, gesture and toolbar content (one extension: the
// conformances share the same `Body` typealias and `body` witness). `return fatalError()` keeps the protocols'
// result-builder attribute from being inferred onto the witness.
extension Never: View, Scene, Gesture, ToolbarContent {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { return fatalError() }
    // shim: Gesture.Value of Never
    public typealias Value = Never
}

// shim: every Apple primitive view (Text, VStack ...) is `View` with `Body == Never`; conforming through this
// protocol keeps each shim type's conformance a one-line extension and lets it supply `body` once
public protocol _PrimitiveView: View where Body == Never {}
extension _PrimitiveView {
    // shim: primitive body
    public var body: Never { return fatalError() }
}

// doc: SwiftUI/ContentBuilder
public typealias ContentBuilder = ViewBuilder

// doc: SwiftUI/EmptyContent
public typealias EmptyContent = EmptyView

// doc: SwiftUI/ViewBuilder
@resultBuilder public struct ViewBuilder {
    // doc: SwiftUI/ViewBuilder/buildBlock()
    public static func buildBlock() -> EmptyContent { EmptyView() }
    // doc-fixed: SwiftUI/ViewBuilder/buildBlock(_:) | ) -> Content => ) -> Content where Content : View | the docs omit the View constraint of this inlinable builder method; without it any type would be accepted as a child
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: View { content }
    // doc-unconfirmed: the docs show only the zero- and one-child buildBlock for ViewBuilder (and "EmptyContent" for the
    // empty one). The parameter-pack form below is copied from the documented SceneBuilder.buildBlock<each Content>
    // (SwiftUI/SceneBuilder/buildBlock(_:)) and matches the Xcode 16+ swiftinterface as I know it: no 10-child limit.
    public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleView<(repeat each Content)> where repeat each Content: View { TupleView((repeat each content)) }
    // doc-fixed: SwiftUI/ViewBuilder/buildEither(first:) | -> _ConditionalContent<TrueContent, FalseContent> => -> _ConditionalContent<TrueContent, FalseContent> where TrueContent : View, FalseContent : View | the docs omit the View constraints of this inlinable builder method
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View { fatalError() }
    // doc-fixed: SwiftUI/ViewBuilder/buildEither(second:) | -> _ConditionalContent<TrueContent, FalseContent> => -> _ConditionalContent<TrueContent, FalseContent> where TrueContent : View, FalseContent : View | the docs omit the View constraints of this inlinable builder method
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View { fatalError() }
    // doc-fixed: SwiftUI/ViewBuilder/buildIf(_:) | -> Content? => -> Content? where Content : View | the docs omit the View constraint of this inlinable builder method
    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: View { content }
    // doc-unconfirmed: docs list buildLimitedAvailability only for the Commands builder; ViewBuilder has the same hook returning AnyView
    public static func buildLimitedAvailability<Content>(_ content: Content) -> AnyView where Content: View { AnyView(content) }
}

// shim: SwiftUI makes `Optional` a View when its Wrapped is one (what `buildIf` returns; the View page lists Optional
// among its conforming types)
extension Optional: View where Wrapped: View {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { return fatalError() }
}

// doc-unconfirmed: the type is named by the documented return type of ViewBuilder.buildEither but has no page of its own
public struct _ConditionalContent<TrueContent, FalseContent> {}
// shim: _ConditionalContent is a View when both branches are (the View page lists it among its conforming types)
extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { return fatalError() }
}

// doc: SwiftUI/TupleView
public struct TupleView<T> {
    // doc: SwiftUI/TupleView/init(_:)
    public init(_ value: T) { fatalError() }
    // doc: SwiftUI/TupleView/value
    public var value: T
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension TupleView: _PrimitiveView {}

// doc: SwiftUI/EmptyView
public struct EmptyView {
    // doc: SwiftUI/EmptyView/init()
    public init() {}
}
// doc: SwiftUI/EmptyView
extension EmptyView: View, ToolbarContent {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { return fatalError() }
}

// doc: SwiftUI/AnyView
public struct AnyView {
    // doc: SwiftUI/AnyView/init(_:)
    public init<V>(_ view: V) where V: View { fatalError() }
    // doc: SwiftUI/AnyView/init(erasing:)
    public init<V>(erasing view: V) where V: View { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension AnyView: _PrimitiveView {}

// MARK: - View modifiers

// doc: SwiftUI/ViewModifier
@MainActor @preconcurrency public protocol ViewModifier {
    // doc-unconfirmed: associated type Body is not a page of its own in this snapshot (ViewModifier.body(content:) names it)
    associatedtype Body: View
    // doc: SwiftUI/ViewModifier/Content
    typealias Content = _ViewModifier_Content<Self>
    // doc: SwiftUI/ViewModifier/body(content:)
    @ContentBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
}
// shim: placeholder view for `content` inside `body(content:)` (Apple's is also named _ViewModifier_Content)
public struct _ViewModifier_Content<Modifier>: _PrimitiveView where Modifier: ViewModifier {}

extension ViewModifier where Body == Never {
    // shim: modifiers with Body == Never
    public func body(content: Content) -> Never { fatalError() }
}

// doc: SwiftUI/ModifiedContent
public struct ModifiedContent<Content, Modifier> {
    // doc: SwiftUI/ModifiedContent/init(content:modifier:)
    public init(content: Content, modifier: Modifier) { fatalError() }
    // doc: SwiftUI/ModifiedContent/content
    public var content: Content
    // doc: SwiftUI/ModifiedContent/modifier
    public var modifier: Modifier
}
// doc: SwiftUI/View, SwiftUI/ModifiedContent
extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    // shim: primitive body
    public typealias Body = Never
    // shim: primitive body
    public var body: Never { return fatalError() }
}
// doc: SwiftUI/ViewModifier, SwiftUI/ModifiedContent
extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    // shim: modifier chaining
    public typealias Body = Never
}

// MARK: - Apps and scenes

// doc: SwiftUI/Scene
@MainActor @preconcurrency public protocol Scene {
    // doc: SwiftUI/Scene/Body-swift.associatedtype
    associatedtype Body: Scene
    // doc: SwiftUI/Scene/body-swift.property
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

// doc: SwiftUI/SceneBuilder
@resultBuilder public struct SceneBuilder {
    // doc: SwiftUI/SceneBuilder/buildBlock(_:)
    public static func buildBlock<each Content>(_ content: repeat each Content) -> some Scene where repeat each Content: Scene { _SceneTuple() }
    // doc: SwiftUI/SceneBuilder/buildExpression(_:)
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: Scene { content }
}
// shim: opaque result of SceneBuilder.buildBlock
public struct _SceneTuple: Scene {
    // shim: primitive scene
    public typealias Body = Never
    // shim: primitive scene
    public var body: Never { return fatalError() }
}

// doc: SwiftUI/App
@MainActor @preconcurrency public protocol App {
    // doc: SwiftUI/App/Body-swift.associatedtype
    associatedtype Body: Scene
    // doc: SwiftUI/App/body-swift.property
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    // doc: SwiftUI/App/init()
    @MainActor @preconcurrency init()
}
extension App {
    // doc: SwiftUI/App/main()
    @MainActor @preconcurrency public static func main() { fatalError() }
}

// doc: SwiftUI/WindowGroup
public struct WindowGroup<Content> where Content: View {
    // doc: SwiftUI/WindowGroup/init(content:)
    public init(@ContentBuilder content: () -> Content) { fatalError() }
}
// doc: SwiftUI/WindowGroup
extension WindowGroup: Scene {
    // shim: primitive scene
    public typealias Body = Never
    // shim: primitive scene
    public var body: Never { return fatalError() }
}

// MARK: - Dynamic properties

// doc: SwiftUI/DynamicProperty
public protocol DynamicProperty {
    // doc: SwiftUI/DynamicProperty/update()
    mutating func update()
}
extension DynamicProperty {
    // shim: default so wrappers need not implement it
    public mutating func update() {}
}

// MARK: - Animation plumbing

// doc: SwiftUI/VectorArithmetic
public protocol VectorArithmetic: AdditiveArithmetic {
    // doc: SwiftUI/VectorArithmetic/magnitudeSquared
    var magnitudeSquared: Double { get }
    // doc: SwiftUI/VectorArithmetic/scale(by:)
    mutating func scale(by rhs: Double)
}
extension VectorArithmetic {
    // doc: SwiftUI/VectorArithmetic/scaled(by:)
    public func scaled(by rhs: Double) -> Self { fatalError() }
    // doc: SwiftUI/VectorArithmetic/interpolate(towards:amount:)
    public mutating func interpolate(towards other: Self, amount: Double) { fatalError() }
    // doc: SwiftUI/VectorArithmetic/interpolated(towards:amount:)
    public func interpolated(towards other: Self, amount: Double) -> Self { fatalError() }
}
// shim: Double conforms to VectorArithmetic in SwiftUI (the VectorArithmetic page lists only SwiftUI's own conforming types)
extension Double: VectorArithmetic {
    // shim: Double is VectorArithmetic in SwiftUI
    public var magnitudeSquared: Double { self * self }
    // shim: Double is VectorArithmetic in SwiftUI
    public mutating func scale(by rhs: Double) { self *= rhs }
}
// shim: Float conforms to VectorArithmetic in SwiftUI (the VectorArithmetic page lists only SwiftUI's own conforming types)
extension Float: VectorArithmetic {
    // shim: Float is VectorArithmetic in SwiftUI
    public var magnitudeSquared: Double { Double(self * self) }
    // shim: Float is VectorArithmetic in SwiftUI
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
}
// shim: CGFloat conforms to VectorArithmetic in SwiftUI (the VectorArithmetic page lists only SwiftUI's own conforming types)
extension CGFloat: VectorArithmetic {
    // shim: CGFloat is VectorArithmetic in SwiftUI
    public var magnitudeSquared: Double { Double(self * self) }
    // shim: CGFloat is VectorArithmetic in SwiftUI
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
}

// doc: SwiftUI/Animatable
public protocol Animatable {
    // doc: SwiftUI/Animatable/AnimatableData-swift.associatedtype
    associatedtype AnimatableData: VectorArithmetic
    // doc: SwiftUI/Animatable/animatableData-6nydg
    var animatableData: Self.AnimatableData { get set }
}
extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    // shim: SwiftUI supplies a default animatableData for types with nothing to animate
    public var animatableData: EmptyAnimatableData {
        // shim: default
        get { EmptyAnimatableData() }
        // shim: default
        set {}
    }
}

// doc: SwiftUI/EmptyAnimatableData
public struct EmptyAnimatableData: VectorArithmetic {
    // doc: SwiftUI/EmptyAnimatableData/init()
    public init() {}
    // doc: SwiftUI/EmptyAnimatableData/magnitudeSquared
    public var magnitudeSquared: Double { 0 }
    // shim: VectorArithmetic / AdditiveArithmetic requirements
    public mutating func scale(by rhs: Double) {}
    // shim: AdditiveArithmetic requirement
    public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    // shim: AdditiveArithmetic requirement
    public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    // shim: AdditiveArithmetic requirement
    public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
}

// doc: SwiftUI/AnimatablePair
public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    // doc: SwiftUI/AnimatablePair/init(_:_:)
    public init(_ first: First, _ second: Second) { self.first = first; self.second = second }
    // doc: SwiftUI/AnimatablePair/first
    public var first: First
    // doc: SwiftUI/AnimatablePair/second
    public var second: Second
    // doc: SwiftUI/AnimatablePair/magnitudeSquared
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
    // shim: VectorArithmetic requirement
    public mutating func scale(by rhs: Double) { first.scale(by: rhs); second.scale(by: rhs) }
    // shim: AdditiveArithmetic requirement
    public static var zero: AnimatablePair<First, Second> { AnimatablePair(First.zero, Second.zero) }
    // shim: AdditiveArithmetic requirement
    public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> { AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second) }
    // shim: AdditiveArithmetic requirement
    public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> { AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second) }
}
