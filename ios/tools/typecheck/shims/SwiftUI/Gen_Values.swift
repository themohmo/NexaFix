// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/Alignment
public struct Alignment: Equatable, Sendable {
    // doc: SwiftUI/Alignment/topLeading
    public static var topLeading: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/top
    public static var top: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/topTrailing
    public static var topTrailing: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/leading
    public static var leading: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/center
    public static var center: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/trailing
    public static var trailing: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/bottomLeading
    public static var bottomLeading: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/bottom
    public static var bottom: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/bottomTrailing
    public static var bottomTrailing: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/leadingFirstTextBaseline
    public static var leadingFirstTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/centerFirstTextBaseline
    public static var centerFirstTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/trailingFirstTextBaseline
    public static var trailingFirstTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/leadingLastTextBaseline
    public static var leadingLastTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/centerLastTextBaseline
    public static var centerLastTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/trailingLastTextBaseline
    public static var trailingLastTextBaseline: Alignment { fatalError() }
    // doc: SwiftUI/Alignment/init(horizontal:vertical:)
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) { fatalError() }
    // doc: SwiftUI/Alignment/horizontal
    public var horizontal: HorizontalAlignment { get { fatalError() } set { } }
    // doc: SwiftUI/Alignment/vertical
    public var vertical: VerticalAlignment { get { fatalError() } set { } }
}

// doc: SwiftUI/HorizontalAlignment
public struct HorizontalAlignment: Equatable, Sendable {
    // doc: SwiftUI/HorizontalAlignment/leading
    public static var leading: HorizontalAlignment { fatalError() }
    // doc: SwiftUI/HorizontalAlignment/center
    public static var center: HorizontalAlignment { fatalError() }
    // doc: SwiftUI/HorizontalAlignment/trailing
    public static var trailing: HorizontalAlignment { fatalError() }
    // doc: SwiftUI/HorizontalAlignment/listRowSeparatorLeading
    public static var listRowSeparatorLeading: HorizontalAlignment { fatalError() }
    // doc: SwiftUI/HorizontalAlignment/listRowSeparatorTrailing
    public static var listRowSeparatorTrailing: HorizontalAlignment { fatalError() }
    // doc: SwiftUI/HorizontalAlignment/combineExplicit(_:)
    public func combineExplicit<S>(_ values: S) -> CGFloat? where S : Sequence, S.Element == CGFloat? { fatalError() }
}

// doc: SwiftUI/VerticalAlignment
public struct VerticalAlignment: Equatable, Sendable {
    // doc: SwiftUI/VerticalAlignment/top
    public static var top: VerticalAlignment { fatalError() }
    // doc: SwiftUI/VerticalAlignment/center
    public static var center: VerticalAlignment { fatalError() }
    // doc: SwiftUI/VerticalAlignment/bottom
    public static var bottom: VerticalAlignment { fatalError() }
    // doc: SwiftUI/VerticalAlignment/firstTextBaseline
    public static var firstTextBaseline: VerticalAlignment { fatalError() }
    // doc: SwiftUI/VerticalAlignment/lastTextBaseline
    public static var lastTextBaseline: VerticalAlignment { fatalError() }
    // doc: SwiftUI/VerticalAlignment/combineExplicit(_:)
    public func combineExplicit<S>(_ values: S) -> CGFloat? where S : Sequence, S.Element == CGFloat? { fatalError() }
}

// doc: SwiftUI/Edge
public enum Edge: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/Edge/top
    case top
    // doc: SwiftUI/Edge/bottom
    case bottom
    // doc: SwiftUI/Edge/leading
    case leading
    // doc: SwiftUI/Edge/trailing
    case trailing
    // doc: SwiftUI/Edge/Set
    public struct Set: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/Edge/Set/all
        public static var all: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/top
        public static var top: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/bottom
        public static var bottom: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/leading
        public static var leading: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/trailing
        public static var trailing: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/horizontal
        public static var horizontal: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/vertical
        public static var vertical: Edge.Set { fatalError() }
        // doc: SwiftUI/Edge/Set/init(_:)
        public init(_ e: Edge) { fatalError() }
    }
    // doc: SwiftUI/Edge/Corner
    public enum Corner: Equatable, Hashable, Sendable, CaseIterable {
        // doc: SwiftUI/Edge/Corner/Set
        public struct Set: Equatable, Hashable, Sendable, OptionSet {
            // shim: OptionSet storage (the docs page set has no rawValue page for this type)
            public let rawValue: Int8
            // doc: SwiftUI/Edge/Corner/Set/init(_:)  [iOS 26.0]
            public init(_ corner: Edge.Corner) { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/init(rawValue:)  [iOS 26.0]
            public init(rawValue: Int8) { self.rawValue = rawValue }
            // doc: SwiftUI/Edge/Corner/Set/contains(_:)  [iOS 26.0]
            public func contains(_ corner: Edge.Corner) -> Bool { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/all  [iOS 26.0]
            public static var all: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/bottom  [iOS 26.0]
            public static var bottom: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/bottomLeading  [iOS 26.0]
            public static var bottomLeading: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/bottomTrailing  [iOS 26.0]
            public static var bottomTrailing: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/leading  [iOS 26.0]
            public static var leading: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/none  [iOS 26.0]
            public static var none: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/top  [iOS 26.0]
            public static var top: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/topLeading  [iOS 26.0]
            public static var topLeading: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/topTrailing  [iOS 26.0]
            public static var topTrailing: Edge.Corner.Set { fatalError() }
            // doc: SwiftUI/Edge/Corner/Set/trailing  [iOS 26.0]
            public static var trailing: Edge.Corner.Set { fatalError() }
        }
        // doc: SwiftUI/Edge/Corner/Style
        public struct Style: Equatable, Hashable, Sendable {
            // doc: SwiftUI/Edge/Corner/Style/concentric  [iOS 26.0]
            public static var concentric: Edge.Corner.Style { fatalError() }
            // doc: SwiftUI/Edge/Corner/Style/concentric(minimum:)  [iOS 26.0]
            public static func concentric(minimum: Edge.Corner.Style? = nil) -> Edge.Corner.Style { fatalError() }
            // doc: SwiftUI/Edge/Corner/Style/fixed(_:)  [iOS 26.0]
            public static func fixed(_ radius: CGFloat) -> Edge.Corner.Style { fatalError() }
        }
        // doc: SwiftUI/Edge/Corner/bottomLeading  [iOS 26.0]
        case bottomLeading
        // doc: SwiftUI/Edge/Corner/bottomTrailing  [iOS 26.0]
        case bottomTrailing
        // doc: SwiftUI/Edge/Corner/topLeading  [iOS 26.0]
        case topLeading
        // doc: SwiftUI/Edge/Corner/topTrailing  [iOS 26.0]
        case topTrailing
    }
}

// doc: SwiftUI/Axis
public enum Axis: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/Axis/horizontal
    case horizontal
    // doc: SwiftUI/Axis/vertical
    case vertical
    // doc: SwiftUI/Axis/Set
    public struct Set: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/Axis/Set/horizontal
        public static var horizontal: Axis.Set { fatalError() }
        // doc: SwiftUI/Axis/Set/vertical
        public static var vertical: Axis.Set { fatalError() }
    }
}

// doc: SwiftUI/EdgeInsets
public struct EdgeInsets: Equatable, Sendable {
    // doc: SwiftUI/EdgeInsets/top
    public var top: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EdgeInsets/bottom
    public var bottom: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EdgeInsets/leading
    public var leading: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EdgeInsets/trailing
    public var trailing: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/EdgeInsets/init()
    public init() { fatalError() }
    // doc: SwiftUI/EdgeInsets/init(top:leading:bottom:trailing:)
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) { fatalError() }
}

// doc: SwiftUI/UnitPoint
public struct UnitPoint: Equatable, Hashable, Sendable {
    // doc: SwiftUI/UnitPoint/zero
    public static var zero: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/topLeading
    public static var topLeading: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/top
    public static var top: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/topTrailing
    public static var topTrailing: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/leading
    public static var leading: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/center
    public static var center: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/trailing
    public static var trailing: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/bottomLeading
    public static var bottomLeading: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/bottom
    public static var bottom: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/bottomTrailing
    public static var bottomTrailing: UnitPoint { fatalError() }
    // doc: SwiftUI/UnitPoint/init()
    public init() { fatalError() }
    // doc: SwiftUI/UnitPoint/init(x:y:)
    public init(x: CGFloat, y: CGFloat) { fatalError() }
    // doc: SwiftUI/UnitPoint/x
    public var x: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/UnitPoint/y
    public var y: CGFloat { get { fatalError() } set { } }
}

// doc: SwiftUI/Angle
public struct Angle: Equatable, Hashable, Comparable, Sendable {
    // shim: Comparable requirement (this docs snapshot has no page for Angle.<)
    public static func < (lhs: Angle, rhs: Angle) -> Bool { fatalError() }
    // doc: SwiftUI/Angle/zero
    public static var zero: Angle { fatalError() }
    // doc: SwiftUI/Angle/degrees(_:)
    public static func degrees(_ degrees: Double) -> Angle { fatalError() }
    // doc: SwiftUI/Angle/radians(_:)
    public static func radians(_ radians: Double) -> Angle { fatalError() }
    // doc: SwiftUI/Angle/init()
    public init() { fatalError() }
    // doc: SwiftUI/Angle/init(degrees:)
    public init(degrees: Double) { fatalError() }
    // doc: SwiftUI/Angle/init(radians:)
    public init(radians: Double) { fatalError() }
    // doc: SwiftUI/Angle/degrees
    public var degrees: Double { get { fatalError() } set { } }
    // doc: SwiftUI/Angle/radians
    public var radians: Double { get { fatalError() } set { } }
}

// doc: SwiftUI/StrokeStyle
public struct StrokeStyle: Equatable, Sendable {
    // doc: SwiftUI/StrokeStyle/init(lineWidth:lineCap:lineJoin:miterLimit:dash:dashPhase:)
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [CGFloat](), dashPhase: CGFloat = 0) { fatalError() }
    // doc: SwiftUI/StrokeStyle/lineWidth
    public var lineWidth: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeStyle/lineCap
    public var lineCap: CGLineCap { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeStyle/lineJoin
    public var lineJoin: CGLineJoin { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeStyle/miterLimit
    public var miterLimit: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeStyle/dash
    public var dash: [CGFloat] { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeStyle/dashPhase
    public var dashPhase: CGFloat { get { fatalError() } set { } }
}

// doc: SwiftUI/Animation
public struct Animation: Equatable, Hashable, Sendable {
    // doc: SwiftUI/Animation/default
    public static var `default`: Animation { fatalError() }
    // doc: SwiftUI/Animation/linear
    public static var linear: Animation { fatalError() }
    // doc: SwiftUI/Animation/linear(duration:)
    public static func linear(duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/easeIn
    public static var easeIn: Animation { fatalError() }
    // doc: SwiftUI/Animation/easeIn(duration:)
    public static func easeIn(duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/easeOut
    public static var easeOut: Animation { fatalError() }
    // doc: SwiftUI/Animation/easeOut(duration:)
    public static func easeOut(duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/easeInOut
    public static var easeInOut: Animation { fatalError() }
    // doc: SwiftUI/Animation/easeInOut(duration:)
    public static func easeInOut(duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/bouncy
    public static var bouncy: Animation { fatalError() }
    // doc: SwiftUI/Animation/bouncy(duration:extraBounce:)
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/smooth
    public static var smooth: Animation { fatalError() }
    // doc: SwiftUI/Animation/smooth(duration:extraBounce:)
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/snappy
    public static var snappy: Animation { fatalError() }
    // doc: SwiftUI/Animation/snappy(duration:extraBounce:)
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/spring
    public static var spring: Animation { fatalError() }
    // doc: SwiftUI/Animation/spring(_:blendDuration:)
    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/spring(duration:bounce:blendDuration:)
    public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/spring(response:dampingFraction:blendDuration:)
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/interactiveSpring
    public static var interactiveSpring: Animation { fatalError() }
    // doc: SwiftUI/Animation/interactiveSpring(response:dampingFraction:blendDuration:)
    @_disfavoredOverload public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: TimeInterval = 0.25) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/interpolatingSpring
    public static var interpolatingSpring: Animation { fatalError() }
    // doc: SwiftUI/Animation/interpolatingSpring(_:initialVelocity:)
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/interpolatingSpring(duration:bounce:initialVelocity:)
    public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0.0, initialVelocity: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/interpolatingSpring(mass:stiffness:damping:initialVelocity:)
    public static func interpolatingSpring(mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0.0) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/timingCurve(_:duration:)
    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/timingCurve(_:_:_:_:duration:)
    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double, duration: TimeInterval = 0.35) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/delay(_:)
    public func delay(_ delay: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/repeatCount(_:autoreverses:)
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/repeatForever(autoreverses:)
    public func repeatForever(autoreverses: Bool = true) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/speed(_:)
    public func speed(_ speed: Double) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/animate(value:time:context:)
    public func animate<V>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Animation/logicallyComplete(after:)
    public func logicallyComplete(after duration: TimeInterval) -> Animation { fatalError() }
    // doc: SwiftUI/Animation/shouldMerge(previous:value:time:context:)
    public func shouldMerge<V>(previous: Animation, value: V, time: TimeInterval, context: inout AnimationContext<V>) -> Bool where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Animation/velocity(value:time:context:)
    public func velocity<V>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Animation/interactiveSpring(duration:extraBounce:blendDuration:)
    public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0.0, blendDuration: TimeInterval = 0.25) -> Animation { fatalError() }
}

// doc: SwiftUI/Transaction
public struct Transaction {
    // doc: SwiftUI/Transaction/init()
    public init() { fatalError() }
    // doc: SwiftUI/Transaction/init(animation:)
    public init(animation: Animation?) { fatalError() }
    // doc: SwiftUI/Transaction/animation
    public var animation: Animation? { get { fatalError() } set { } }
    // doc: SwiftUI/Transaction/disablesAnimations
    public var disablesAnimations: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/Transaction/isContinuous
    public var isContinuous: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/Transaction/scrollTargetAnchor
    public var scrollTargetAnchor: UnitPoint? { get { fatalError() } set { } }
    // doc: SwiftUI/Transaction/tracksVelocity
    public var tracksVelocity: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/Transaction/scrollPositionUpdatePreservesVelocity  [iOS 18.0]
    public var scrollPositionUpdatePreservesVelocity: Bool { get { fatalError() } set { } }
}

// doc: SwiftUI/AnyTransition
public struct AnyTransition {
    // doc: SwiftUI/AnyTransition/identity
    public static var identity: AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/move(edge:)
    public static func move(edge: Edge) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/offset(_:)
    public static func offset(_ offset: CGSize) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/offset(x:y:)
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/opacity
    public nonisolated(unsafe) static var opacity: AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/push(from:)
    public static func push(from edge: Edge) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/scale
    public static var scale: AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/scale(scale:anchor:)
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/slide
    public static var slide: AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/animation(_:)
    public func animation(_ animation: Animation?) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/asymmetric(insertion:removal:)
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/combined(with:)
    public func combined(with other: AnyTransition) -> AnyTransition { fatalError() }
    // doc: SwiftUI/AnyTransition/modifier(active:identity:)
    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E : ViewModifier { fatalError() }
}

// doc: SwiftUI/Font
public struct Font: Equatable, Hashable, Sendable {
    // doc: SwiftUI/Font/largeTitle
    public static var largeTitle: Font { fatalError() }
    // doc: SwiftUI/Font/title
    public static var title: Font { fatalError() }
    // doc: SwiftUI/Font/title2
    public static var title2: Font { fatalError() }
    // doc: SwiftUI/Font/title3
    public static var title3: Font { fatalError() }
    // doc: SwiftUI/Font/headline
    public static var headline: Font { fatalError() }
    // doc: SwiftUI/Font/subheadline
    public static var subheadline: Font { fatalError() }
    // doc: SwiftUI/Font/body
    public static var body: Font { fatalError() }
    // doc: SwiftUI/Font/callout
    public static var callout: Font { fatalError() }
    // doc: SwiftUI/Font/caption
    public static var caption: Font { fatalError() }
    // doc: SwiftUI/Font/caption2
    public static var caption2: Font { fatalError() }
    // doc: SwiftUI/Font/footnote
    public static var footnote: Font { fatalError() }
    // doc: SwiftUI/Font/system(_:design:weight:)
    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font { fatalError() }
    // doc: SwiftUI/Font/system(size:weight:design:)-697b2
    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font { fatalError() }
    // doc: SwiftUI/Font/Design
    public enum Design: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Font/Design/default
        case `default`
        // doc: SwiftUI/Font/Design/monospaced
        case monospaced
        // doc: SwiftUI/Font/Design/rounded
        case rounded
        // doc: SwiftUI/Font/Design/serif
        case serif
    }
    // doc: SwiftUI/Font/TextStyle
    public enum TextStyle: Equatable, Hashable, Sendable, CaseIterable {
        // doc: SwiftUI/Font/TextStyle/largeTitle
        case largeTitle
        // doc: SwiftUI/Font/TextStyle/title
        case title
        // doc: SwiftUI/Font/TextStyle/title2
        case title2
        // doc: SwiftUI/Font/TextStyle/title3
        case title3
        // doc: SwiftUI/Font/TextStyle/headline
        case headline
        // doc: SwiftUI/Font/TextStyle/subheadline
        case subheadline
        // doc: SwiftUI/Font/TextStyle/body
        case body
        // doc: SwiftUI/Font/TextStyle/callout
        case callout
        // doc: SwiftUI/Font/TextStyle/caption
        case caption
        // doc: SwiftUI/Font/TextStyle/caption2
        case caption2
        // doc: SwiftUI/Font/TextStyle/footnote
        case footnote
    }
    // doc: SwiftUI/Font/Weight
    public struct Weight: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Font/Weight/black
        public static var black: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/bold
        public static var bold: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/heavy
        public static var heavy: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/light
        public static var light: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/medium
        public static var medium: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/regular
        public static var regular: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/semibold
        public static var semibold: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/thin
        public static var thin: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Weight/ultraLight
        public static var ultraLight: Font.Weight { fatalError() }
    }
    // doc: SwiftUI/Font/custom(_:fixedSize:)
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { fatalError() }
    // doc: SwiftUI/Font/custom(_:size:relativeTo:)
    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font { fatalError() }
    // doc: SwiftUI/Font/custom(_:size:)
    public static func custom(_ name: String, size: CGFloat) -> Font { fatalError() }
    // doc: SwiftUI/Font/bold()
    public func bold() -> Font { fatalError() }
    // doc: SwiftUI/Font/italic()
    public func italic() -> Font { fatalError() }
    // doc: SwiftUI/Font/monospaced()
    public func monospaced() -> Font { fatalError() }
    // doc: SwiftUI/Font/monospacedDigit()
    public func monospacedDigit() -> Font { fatalError() }
    // doc: SwiftUI/Font/smallCaps()
    public func smallCaps() -> Font { fatalError() }
    // doc: SwiftUI/Font/lowercaseSmallCaps()
    public func lowercaseSmallCaps() -> Font { fatalError() }
    // doc: SwiftUI/Font/uppercaseSmallCaps()
    public func uppercaseSmallCaps() -> Font { fatalError() }
    // doc: SwiftUI/Font/weight(_:)
    public func weight(_ weight: Font.Weight) -> Font { fatalError() }
    // doc: SwiftUI/Font/width(_:)
    public func width(_ width: Font.Width) -> Font { fatalError() }
    // doc: SwiftUI/Font/Width
    public struct Width: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Font/Width/compressed
        public static var compressed: Font.Width { fatalError() }
        // doc: SwiftUI/Font/Width/condensed
        public static var condensed: Font.Width { fatalError() }
        // doc: SwiftUI/Font/Width/expanded
        public static var expanded: Font.Width { fatalError() }
        // doc: SwiftUI/Font/Width/standard
        public static var standard: Font.Width { fatalError() }
        // doc: SwiftUI/Font/Width/init(_:)
        public init(_ value: CGFloat) { fatalError() }
        // doc: SwiftUI/Font/Width/value
        public var value: CGFloat { get { fatalError() } set { } }
    }
    // doc: SwiftUI/Font/leading(_:)
    public func leading(_ leading: Font.Leading) -> Font { fatalError() }
    // doc: SwiftUI/Font/Leading
    public enum Leading: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Font/Leading/standard
        case standard
        // doc: SwiftUI/Font/Leading/loose
        case loose
        // doc: SwiftUI/Font/Leading/tight
        case tight
    }
    // doc: SwiftUI/Font/system(_:design:)
    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font { fatalError() }
    // doc: SwiftUI/Font/system(size:weight:design:)-73a88
    @_disfavoredOverload public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font { fatalError() }
    // doc: SwiftUI/Font/Context
    public struct Context: Equatable, Hashable, Sendable {
    }
    // doc: SwiftUI/Font/Resolved
    public struct Resolved: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Font/Resolved/isBold  [iOS 26.0]
        public var isBold: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/isItalic  [iOS 26.0]
        public var isItalic: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/isLowercaseSmallCaps  [iOS 26.0]
        public var isLowercaseSmallCaps: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/isMonospaced  [iOS 26.0]
        public var isMonospaced: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/isSmallCaps  [iOS 26.0]
        public var isSmallCaps: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/isUppercaseSmallCaps  [iOS 26.0]
        public var isUppercaseSmallCaps: Bool { fatalError() }
        // doc: SwiftUI/Font/Resolved/leading  [iOS 26.0]
        public var leading: Font.Leading { fatalError() }
        // doc: SwiftUI/Font/Resolved/pointSize  [iOS 26.0]
        public var pointSize: CGFloat { fatalError() }
        // doc: SwiftUI/Font/Resolved/weight  [iOS 26.0]
        public var weight: Font.Weight { fatalError() }
        // doc: SwiftUI/Font/Resolved/width  [iOS 26.0]
        public var width: Font.Width { fatalError() }
    }
    // doc: SwiftUI/Font/bold(_:)  [iOS 26.0]
    public func bold(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/italic(_:)  [iOS 26.0]
    public func italic(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/lowercaseSmallCaps(_:)  [iOS 26.0]
    public func lowercaseSmallCaps(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/monospaced(_:)  [iOS 26.0]
    public func monospaced(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/pointSize(_:)  [iOS 26.0]
    public func pointSize(_ size: CGFloat) -> Font { fatalError() }
    // doc: SwiftUI/Font/resolve(in:)  [iOS 26.0]
    public func resolve(in context: Font.Context) -> Font.Resolved { fatalError() }
    // doc: SwiftUI/Font/scaled(by:)  [iOS 26.0]
    public func scaled(by factor: CGFloat) -> Font { fatalError() }
    // doc: SwiftUI/Font/smallCaps(_:)  [iOS 26.0]
    public func smallCaps(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/uppercaseSmallCaps(_:)  [iOS 26.0]
    public func uppercaseSmallCaps(_ isActive: Bool) -> Font { fatalError() }
    // doc: SwiftUI/Font/default  [iOS 26.0]
    public static var `default`: Font { fatalError() }
}

// doc: SwiftUI/DynamicTypeSize
public enum DynamicTypeSize: Equatable, Hashable, Comparable, Sendable, CaseIterable {
    // doc: SwiftUI/DynamicTypeSize/xSmall
    case xSmall
    // doc: SwiftUI/DynamicTypeSize/small
    case small
    // doc: SwiftUI/DynamicTypeSize/medium
    case medium
    // doc: SwiftUI/DynamicTypeSize/large
    case large
    // doc: SwiftUI/DynamicTypeSize/xLarge
    case xLarge
    // doc: SwiftUI/DynamicTypeSize/xxLarge
    case xxLarge
    // doc: SwiftUI/DynamicTypeSize/xxxLarge
    case xxxLarge
    // doc: SwiftUI/DynamicTypeSize/accessibility1
    case accessibility1
    // doc: SwiftUI/DynamicTypeSize/accessibility2
    case accessibility2
    // doc: SwiftUI/DynamicTypeSize/accessibility3
    case accessibility3
    // doc: SwiftUI/DynamicTypeSize/accessibility4
    case accessibility4
    // doc: SwiftUI/DynamicTypeSize/accessibility5
    case accessibility5
    // doc: SwiftUI/DynamicTypeSize/isAccessibilitySize
    public var isAccessibilitySize: Bool { fatalError() }
}

// doc: SwiftUI/ColorScheme
public enum ColorScheme: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/ColorScheme/light
    case light
    // doc: SwiftUI/ColorScheme/dark
    case dark
    // doc: SwiftUI/ColorScheme/init(_:)
    public init?(_ uiUserInterfaceStyle: UIUserInterfaceStyle) { fatalError() }
    // doc: SwiftUI/PreferredColorSchemeKey
    public struct PreferredColorSchemeKey {
    }
}

// doc: SwiftUI/ColorSchemeContrast
public enum ColorSchemeContrast: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/ColorSchemeContrast/standard
    case standard
    // doc: SwiftUI/ColorSchemeContrast/increased
    case increased
    // doc: SwiftUI/ColorSchemeContrast/init(_:)
    public init?(_ uiAccessibilityContrast: UIAccessibilityContrast) { fatalError() }
}

// doc: SwiftUI/GridItem
public struct GridItem: Equatable, Sendable {
    // doc: SwiftUI/GridItem/init(_:spacing:alignment:)
    public init(_ size: GridItem.Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) { fatalError() }
    // doc: SwiftUI/GridItem/alignment
    public var alignment: Alignment? = nil
    // doc: SwiftUI/GridItem/spacing
    public var spacing: CGFloat? = nil
    // doc: SwiftUI/GridItem/size-swift.property
    public var size: GridItem.Size { get { fatalError() } set { } }
    // doc: SwiftUI/GridItem/Size-swift.enum
    public enum Size: Equatable, Sendable {
        // doc: SwiftUI/GridItem/Size-swift.enum/adaptive(minimum:maximum:)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
        // doc: SwiftUI/GridItem/Size-swift.enum/fixed(_:)
        case fixed(CGFloat)
        // doc: SwiftUI/GridItem/Size-swift.enum/flexible(minimum:maximum:)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
    }
}

// doc: SwiftUI/ContentShapeKinds
public struct ContentShapeKinds: Equatable, Sendable, OptionSet {
    // shim: OptionSet storage (the docs page set has no rawValue page for this type)
    public let rawValue: Int
    // doc: SwiftUI/ContentShapeKinds/interaction
    public static var interaction: ContentShapeKinds { fatalError() }
    // doc: SwiftUI/ContentShapeKinds/dragPreview
    public static var dragPreview: ContentShapeKinds { fatalError() }
    // doc: SwiftUI/ContentShapeKinds/contextMenuPreview
    public static var contextMenuPreview: ContentShapeKinds { fatalError() }
    // doc: SwiftUI/ContentShapeKinds/hoverEffect
    public static var hoverEffect: ContentShapeKinds { fatalError() }
    // doc: SwiftUI/ContentShapeKinds/accessibility
    public static var accessibility: ContentShapeKinds { fatalError() }
    // doc: SwiftUI/ContentShapeKinds/init(rawValue:)
    public init(rawValue: Int) { self.rawValue = rawValue }
}

// doc: SwiftUI/PresentationDetent
public struct PresentationDetent: Equatable, Hashable, Sendable {
    // doc: SwiftUI/PresentationDetent/large
    public static var large: PresentationDetent { fatalError() }
    // doc: SwiftUI/PresentationDetent/medium
    public static var medium: PresentationDetent { fatalError() }
    // doc: SwiftUI/PresentationDetent/fraction(_:)
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { fatalError() }
    // doc: SwiftUI/PresentationDetent/height(_:)
    public static func height(_ height: CGFloat) -> PresentationDetent { fatalError() }
    // doc-fixed: SwiftUI/PresentationDetent/Context | @dynamicMemberLookup  =>  | a @dynamicMemberLookup type needs a subscript(dynamicMember:) that the docs do not list; the shim type is never looked up by key path
    public struct Context {
        // doc: SwiftUI/PresentationDetent/Context/maxDetentValue
        public var maxDetentValue: CGFloat { fatalError() }
        // doc: SwiftUI/PresentationDetent/Context/subscript(dynamicMember:)
        public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T { fatalError() }
    }
}

// doc: SwiftUI/LocalizedStringKey
public struct LocalizedStringKey: Equatable {
    // doc: SwiftUI/LocalizedStringKey/init(_:)
    public init(_ value: String) { fatalError() }
    // doc: SwiftUI/LocalizedStringKey/init(stringLiteral:)
    public init(stringLiteral value: String) { fatalError() }
    // doc: SwiftUI/LocalizedStringKey/init(stringInterpolation:)
    public init(stringInterpolation: LocalizedStringKey.StringInterpolation) { fatalError() }
    // doc: SwiftUI/LocalizedStringKey/StringInterpolation
    public struct StringInterpolation {
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)
        public mutating func appendInterpolation(_ attributedSubstring: AttributedSubstring) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:format:)  [iOS 18.0]
        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F) where F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == AttributedString { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:formatter:)
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject : NSObject { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:style:)
        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(timerInterval:pauseTime:countsDown:showsHours:)
        public mutating func appendInterpolation(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendLiteral(_:)
        public mutating func appendLiteral(_ literal: String) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(accessibilityName:)  [iOS 18.0]
        public mutating func appendInterpolation(accessibilityName color: Color) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:formatter:)-9vdw4
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject : ReferenceConvertible { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:format:)-9rpuy
        public mutating func appendInterpolation<F>(_ input: F.FormatInput, format: F) where F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == String { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-5q7y3
        public mutating func appendInterpolation(_ dates: ClosedRange<Date>) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-4lp0j
        public mutating func appendInterpolation(_ substring: Substring) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-4lyw3
        public mutating func appendInterpolation(_ string: String) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-bprj
        public mutating func appendInterpolation(_ interval: DateInterval) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-4qyfo
        public mutating func appendInterpolation(_ text: Text) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-5m52e
        public mutating func appendInterpolation(_ image: Image) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-60fbr
        public mutating func appendInterpolation(_ attributedString: AttributedString) { fatalError() }
        // doc: SwiftUI/LocalizedStringKey/StringInterpolation/appendInterpolation(_:)-2cdg2
        public mutating func appendInterpolation<T>(_ object: T) { fatalError() }
    }
}

// doc: SwiftUI/ToolbarItemPlacement
public struct ToolbarItemPlacement {
    // doc: SwiftUI/ToolbarItemPlacement/automatic
    public static var automatic: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/principal
    public static var principal: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/status
    public static var status: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/primaryAction
    public static var primaryAction: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/secondaryAction
    public static var secondaryAction: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/confirmationAction
    public static var confirmationAction: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/cancellationAction
    public static var cancellationAction: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/destructiveAction
    public static var destructiveAction: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/navigation
    public static var navigation: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/topBarLeading
    @backDeployed(before: iOS 17.0, tvOS 17.0) public static var topBarLeading: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/topBarTrailing
    @backDeployed(before: iOS 17.0, tvOS 17.0) public static var topBarTrailing: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/topBarPinnedTrailing  [iOS 27.0]
    public static var topBarPinnedTrailing: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/bottomBar
    public static var bottomBar: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/keyboard
    public static var keyboard: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/navigationBarLeading
    public static var navigationBarLeading: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/navigationBarTrailing
    public static var navigationBarTrailing: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/largeSubtitle  [iOS 26.0]
    public static var largeSubtitle: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/largeTitle  [iOS 26.0]
    public static var largeTitle: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/subtitle  [iOS 26.0]
    public static var subtitle: ToolbarItemPlacement { fatalError() }
    // doc: SwiftUI/ToolbarItemPlacement/title
    public static var title: ToolbarItemPlacement { fatalError() }
}

// doc: SwiftUI/SensoryFeedback
public struct SensoryFeedback: Equatable, Sendable {
    // doc: SwiftUI/SensoryFeedback/start
    public static var start: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/stop
    public static var stop: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/alignment
    public static var alignment: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/decrease
    public static var decrease: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/increase
    public static var increase: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/levelChange
    public static var levelChange: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/selection
    public static var selection: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/pathComplete
    public static var pathComplete: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/success
    public static var success: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/warning
    public static var warning: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/error
    public static var error: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/impact
    public static var impact: SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/impact(weight:intensity:)
    public static func impact(weight: SensoryFeedback.Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/impact(flexibility:intensity:)
    public static func impact(flexibility: SensoryFeedback.Flexibility, intensity: Double = 1.0) -> SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/Flexibility
    public struct Flexibility: Equatable, Sendable {
        // doc: SwiftUI/SensoryFeedback/Flexibility/rigid
        public static var rigid: SensoryFeedback.Flexibility { fatalError() }
        // doc: SwiftUI/SensoryFeedback/Flexibility/soft
        public static var soft: SensoryFeedback.Flexibility { fatalError() }
        // doc: SwiftUI/SensoryFeedback/Flexibility/solid
        public static var solid: SensoryFeedback.Flexibility { fatalError() }
    }
    // doc: SwiftUI/SensoryFeedback/Weight
    public struct Weight: Equatable, Sendable {
        // doc: SwiftUI/SensoryFeedback/Weight/light
        public static var light: SensoryFeedback.Weight { fatalError() }
        // doc: SwiftUI/SensoryFeedback/Weight/medium
        public static var medium: SensoryFeedback.Weight { fatalError() }
        // doc: SwiftUI/SensoryFeedback/Weight/heavy
        public static var heavy: SensoryFeedback.Weight { fatalError() }
    }
    // doc: SwiftUI/SensoryFeedback/PressFeedback
    public struct PressFeedback: Equatable, Hashable, Sendable {
        // doc: SwiftUI/SensoryFeedback/PressFeedback/button  [iOS 26.0]
        public static var button: SensoryFeedback.PressFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/PressFeedback/buttonIconOnly  [iOS 26.0]
        public static var buttonIconOnly: SensoryFeedback.PressFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/PressFeedback/slider  [iOS 26.0]
        public static var slider: SensoryFeedback.PressFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/PressFeedback/tab  [iOS 26.0]
        public static var tab: SensoryFeedback.PressFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/PressFeedback/toggle  [iOS 26.0]
        public static var toggle: SensoryFeedback.PressFeedback { fatalError() }
    }
    // doc: SwiftUI/SensoryFeedback/ReleaseFeedback
    public struct ReleaseFeedback: Equatable, Hashable, Sendable {
        // doc: SwiftUI/SensoryFeedback/ReleaseFeedback/slider  [iOS 26.0]
        public static var slider: SensoryFeedback.ReleaseFeedback { fatalError() }
    }
    // doc: SwiftUI/SensoryFeedback/SelectionFeedback
    public struct SelectionFeedback: Equatable, Hashable, Sendable {
        // doc: SwiftUI/SensoryFeedback/SelectionFeedback/maximum  [iOS 26.0]
        public static var maximum: SensoryFeedback.SelectionFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/SelectionFeedback/minimum  [iOS 26.0]
        public static var minimum: SensoryFeedback.SelectionFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/SelectionFeedback/off  [iOS 26.0]
        public static var off: SensoryFeedback.SelectionFeedback { fatalError() }
        // doc: SwiftUI/SensoryFeedback/SelectionFeedback/on  [iOS 26.0]
        public static var on: SensoryFeedback.SelectionFeedback { fatalError() }
    }
    // doc: SwiftUI/SensoryFeedback/press(_:)  [iOS 26.0]
    public static func press(_ feedback: SensoryFeedback.PressFeedback) -> SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/release(_:)  [iOS 26.0]
    public static func release(_ feedback: SensoryFeedback.ReleaseFeedback) -> SensoryFeedback { fatalError() }
    // doc: SwiftUI/SensoryFeedback/selection(_:)  [iOS 26.0]
    public static func selection(_ feedback: SensoryFeedback.SelectionFeedback) -> SensoryFeedback { fatalError() }
}

// doc: SwiftUI/SubmitLabel
public struct SubmitLabel: Sendable {
    // doc: SwiftUI/SubmitLabel/continue
    public static var `continue`: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/done
    public static var done: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/go
    public static var go: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/join
    public static var join: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/next
    public static var next: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/return
    public static var `return`: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/route
    public static var route: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/search
    public static var search: SubmitLabel { fatalError() }
    // doc: SwiftUI/SubmitLabel/send
    public static var send: SubmitLabel { fatalError() }
}

// doc: SwiftUI/TextInputAutocapitalization
public struct TextInputAutocapitalization: Sendable {
    // doc: SwiftUI/TextInputAutocapitalization/characters
    public static var characters: TextInputAutocapitalization { fatalError() }
    // doc: SwiftUI/TextInputAutocapitalization/sentences
    public static var sentences: TextInputAutocapitalization { fatalError() }
    // doc: SwiftUI/TextInputAutocapitalization/words
    public static var words: TextInputAutocapitalization { fatalError() }
    // doc: SwiftUI/TextInputAutocapitalization/never
    public static var never: TextInputAutocapitalization { fatalError() }
}

// doc: SwiftUI/Visibility
public enum Visibility: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/Visibility/automatic
    case automatic
    // doc: SwiftUI/Visibility/visible
    case visible
    // doc: SwiftUI/Visibility/hidden
    case hidden
}

// doc: SwiftUI/ScrollBounceBehavior
public struct ScrollBounceBehavior: Sendable {
    // doc: SwiftUI/ScrollBounceBehavior/automatic
    public static var automatic: ScrollBounceBehavior { fatalError() }
    // doc: SwiftUI/ScrollBounceBehavior/always
    public static var always: ScrollBounceBehavior { fatalError() }
    // doc: SwiftUI/ScrollBounceBehavior/basedOnSize
    public static var basedOnSize: ScrollBounceBehavior { fatalError() }
}

// doc: SwiftUI/ScrollIndicatorVisibility
public struct ScrollIndicatorVisibility: Equatable {
    // doc: SwiftUI/ScrollIndicatorVisibility/automatic
    public static var automatic: ScrollIndicatorVisibility { fatalError() }
    // doc: SwiftUI/ScrollIndicatorVisibility/hidden
    public static var hidden: ScrollIndicatorVisibility { fatalError() }
    // doc: SwiftUI/ScrollIndicatorVisibility/never
    public static var never: ScrollIndicatorVisibility { fatalError() }
    // doc: SwiftUI/ScrollIndicatorVisibility/visible
    public static var visible: ScrollIndicatorVisibility { fatalError() }
}

// doc: SwiftUI/ButtonRole
public struct ButtonRole: Equatable, Sendable {
    // doc: SwiftUI/ButtonRole/cancel
    public static var cancel: ButtonRole { fatalError() }
    // doc: SwiftUI/ButtonRole/destructive
    public static var destructive: ButtonRole { fatalError() }
    // doc: SwiftUI/ButtonRole/close  [iOS 26.0]
    public static var close: ButtonRole { fatalError() }
    // doc: SwiftUI/ButtonRole/confirm  [iOS 26.0]
    public static var confirm: ButtonRole { fatalError() }
}

// doc: SwiftUI/ControlSize
public enum ControlSize: Equatable, Hashable, Comparable, Sendable, CaseIterable {
    // doc: SwiftUI/ControlSize/mini
    case mini
    // doc: SwiftUI/ControlSize/small
    case small
    // doc: SwiftUI/ControlSize/regular
    case regular
    // doc: SwiftUI/ControlSize/large
    case large
    // doc: SwiftUI/ControlSize/extraLarge
    case extraLarge
}

// doc: SwiftUI/Gradient
public struct Gradient: Equatable, Hashable, Sendable, ShapeStyle {
    // doc: SwiftUI/Gradient/init(colors:)
    public init(colors: [Color]) { fatalError() }
    // doc: SwiftUI/Gradient/init(stops:)
    public init(stops: [Gradient.Stop]) { fatalError() }
    // doc: SwiftUI/Gradient/stops
    public var stops: [Gradient.Stop] { get { fatalError() } set { } }
    // doc: SwiftUI/Gradient/Stop
    public struct Stop: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Gradient/Stop/init(color:location:)
        public init(color: Color, location: CGFloat) { fatalError() }
        // doc: SwiftUI/Gradient/Stop/color
        public var color: Color { get { fatalError() } set { } }
        // doc: SwiftUI/Gradient/Stop/location
        public var location: CGFloat { get { fatalError() } set { } }
    }
    // doc: SwiftUI/Gradient/colorSpace(_:)
    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient { fatalError() }
    // doc: SwiftUI/Gradient/ColorSpace
    public struct ColorSpace: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Gradient/ColorSpace/device
        public static var device: Gradient.ColorSpace { fatalError() }
        // doc: SwiftUI/Gradient/ColorSpace/perceptual
        public static var perceptual: Gradient.ColorSpace { fatalError() }
    }
}

// doc: SwiftUI/Material
public struct Material: Sendable, ShapeStyle {
    // doc: SwiftUI/Material/ultraThin
    public static var ultraThin: Material { fatalError() }
    // doc: SwiftUI/Material/thin
    public static var thin: Material { fatalError() }
    // doc: SwiftUI/Material/regular
    public static var regular: Material { fatalError() }
    // doc: SwiftUI/Material/thick
    public static var thick: Material { fatalError() }
    // doc: SwiftUI/Material/ultraThick
    public static var ultraThick: Material { fatalError() }
    // doc: SwiftUI/Material/bar
    public static var bar: Material { fatalError() }
}

// doc: SwiftUI/SymbolRenderingMode
public struct SymbolRenderingMode: Sendable {
    // doc: SwiftUI/SymbolRenderingMode/hierarchical
    public static var hierarchical: SymbolRenderingMode { fatalError() }
    // doc: SwiftUI/SymbolRenderingMode/monochrome
    public static var monochrome: SymbolRenderingMode { fatalError() }
    // doc: SwiftUI/SymbolRenderingMode/multicolor
    public static var multicolor: SymbolRenderingMode { fatalError() }
    // doc: SwiftUI/SymbolRenderingMode/palette
    public static var palette: SymbolRenderingMode { fatalError() }
}

// doc: SwiftUI/BlendMode
public enum BlendMode: Equatable, Hashable, Sendable {
    // doc: SwiftUI/BlendMode/normal
    case normal
    // doc: SwiftUI/BlendMode/darken
    case darken
    // doc: SwiftUI/BlendMode/multiply
    case multiply
    // doc: SwiftUI/BlendMode/colorBurn
    case colorBurn
    // doc: SwiftUI/BlendMode/plusDarker
    case plusDarker
    // doc: SwiftUI/BlendMode/lighten
    case lighten
    // doc: SwiftUI/BlendMode/screen
    case screen
    // doc: SwiftUI/BlendMode/colorDodge
    case colorDodge
    // doc: SwiftUI/BlendMode/plusLighter
    case plusLighter
    // doc: SwiftUI/BlendMode/overlay
    case overlay
    // doc: SwiftUI/BlendMode/softLight
    case softLight
    // doc: SwiftUI/BlendMode/hardLight
    case hardLight
    // doc: SwiftUI/BlendMode/difference
    case difference
    // doc: SwiftUI/BlendMode/exclusion
    case exclusion
    // doc: SwiftUI/BlendMode/hue
    case hue
    // doc: SwiftUI/BlendMode/saturation
    case saturation
    // doc: SwiftUI/BlendMode/color
    case color
    // doc: SwiftUI/BlendMode/luminosity
    case luminosity
    // doc: SwiftUI/BlendMode/sourceAtop
    case sourceAtop
    // doc: SwiftUI/BlendMode/destinationOver
    case destinationOver
    // doc: SwiftUI/BlendMode/destinationOut
    case destinationOut
}

// doc: SwiftUI/LayoutDirection
public enum LayoutDirection: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/LayoutDirection/leftToRight
    case leftToRight
    // doc: SwiftUI/LayoutDirection/rightToLeft
    case rightToLeft
}

// doc: SwiftUI/TextAlignment
public enum TextAlignment: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/TextAlignment/center
    case center
    // doc: SwiftUI/TextAlignment/leading
    case leading
    // doc: SwiftUI/TextAlignment/trailing
    case trailing
}

// NO PAGE: swiftui/safeareaedges

// doc: SwiftUI/AccessibilityTraits
public struct AccessibilityTraits: Equatable, Sendable, SetAlgebra {
    // shim: SetAlgebra requirements (the docs list SetAlgebra and ExpressibleByArrayLiteral as conformances but have no member pages for the requirements)
    // shim: SetAlgebra requirement
    public typealias Element = AccessibilityTraits
    // shim: SetAlgebra requirement
    public init() { }
    // shim: SetAlgebra requirement
    public func contains(_ member: AccessibilityTraits) -> Bool { fatalError() }
    // shim: SetAlgebra requirement
    public func union(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }
    // shim: SetAlgebra requirement
    public func intersection(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }
    // shim: SetAlgebra requirement
    public func symmetricDifference(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func insert(_ newMember: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func remove(_ member: AccessibilityTraits) -> AccessibilityTraits? { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func update(with newMember: AccessibilityTraits) -> AccessibilityTraits? { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func formUnion(_ other: AccessibilityTraits) { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func formIntersection(_ other: AccessibilityTraits) { fatalError() }
    // shim: SetAlgebra requirement
    public mutating func formSymmetricDifference(_ other: AccessibilityTraits) { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/allowsDirectInteraction
    public static var allowsDirectInteraction: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/causesPageTurn
    public static var causesPageTurn: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isButton
    public static var isButton: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isHeader
    public static var isHeader: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isImage
    public static var isImage: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isKeyboardKey
    public static var isKeyboardKey: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isLink
    public static var isLink: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isModal
    public static var isModal: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isSearchField
    public static var isSearchField: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isSelected
    public static var isSelected: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isStaticText
    public static var isStaticText: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isSummaryElement
    public static var isSummaryElement: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isToggle
    public static var isToggle: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/playsSound
    public static var playsSound: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/startsMediaSession
    public static var startsMediaSession: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/updatesFrequently
    public static var updatesFrequently: AccessibilityTraits { fatalError() }
    // doc: SwiftUI/AccessibilityTraits/isTabBar
    public static var isTabBar: AccessibilityTraits { fatalError() }
}

// doc: SwiftUI/AccessibilityActionKind
public struct AccessibilityActionKind: Equatable, Sendable {
    // doc: SwiftUI/AccessibilityActionKind/default
    public static var `default`: AccessibilityActionKind { fatalError() }
    // doc: SwiftUI/AccessibilityActionKind/escape
    public static var escape: AccessibilityActionKind { fatalError() }
    // doc: SwiftUI/AccessibilityActionKind/magicTap
    public static var magicTap: AccessibilityActionKind { fatalError() }
    // doc: SwiftUI/AccessibilityActionKind/init(named:)
    public init(named name: Text) { fatalError() }
}

// doc: SwiftUI/CoordinateSpace
public enum CoordinateSpace: Equatable, Hashable {
    // doc: SwiftUI/CoordinateSpace/global
    case global
    // doc: SwiftUI/CoordinateSpace/local
    case local
    // doc: SwiftUI/CoordinateSpace/named(_:)
    case named(AnyHashable)
    // doc: SwiftUI/CoordinateSpace/isGlobal
    public var isGlobal: Bool { fatalError() }
    // doc: SwiftUI/CoordinateSpace/isLocal
    public var isLocal: Bool { fatalError() }
}

// doc: SwiftUI/HorizontalEdge
public enum HorizontalEdge: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/HorizontalEdge/leading
    case leading
    // doc: SwiftUI/HorizontalEdge/trailing
    case trailing
    // doc: SwiftUI/HorizontalEdge/Set
    public struct Set: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/HorizontalEdge/Set/all
        public static var all: HorizontalEdge.Set { fatalError() }
        // doc: SwiftUI/HorizontalEdge/Set/leading
        public static var leading: HorizontalEdge.Set { fatalError() }
        // doc: SwiftUI/HorizontalEdge/Set/trailing
        public static var trailing: HorizontalEdge.Set { fatalError() }
        // doc: SwiftUI/HorizontalEdge/Set/init(_:)
        public init(_ edge: HorizontalEdge) { fatalError() }
    }
}

// doc: SwiftUI/VerticalEdge
public enum VerticalEdge: Equatable, Hashable, Sendable, CaseIterable {
    // doc: SwiftUI/VerticalEdge/top
    case top
    // doc: SwiftUI/VerticalEdge/bottom
    case bottom
    // doc: SwiftUI/VerticalEdge/Set
    public struct Set: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/VerticalEdge/Set/all
        public static var all: VerticalEdge.Set { fatalError() }
        // doc: SwiftUI/VerticalEdge/Set/top
        public static var top: VerticalEdge.Set { fatalError() }
        // doc: SwiftUI/VerticalEdge/Set/bottom
        public static var bottom: VerticalEdge.Set { fatalError() }
        // doc: SwiftUI/VerticalEdge/Set/init(_:)
        public init(_ e: VerticalEdge) { fatalError() }
    }
}

// NO PAGE: swiftui/truncationmode

// doc: SwiftUI/FillStyle
public struct FillStyle: Equatable, Sendable {
    // doc: SwiftUI/FillStyle/init(eoFill:antialiased:)
    public init(eoFill: Bool = false, antialiased: Bool = true) { fatalError() }
    // doc: SwiftUI/FillStyle/isEOFilled
    public var isEOFilled: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/FillStyle/isAntialiased
    public var isAntialiased: Bool { get { fatalError() } set { } }
}

// doc: SwiftUI/RoundedCornerStyle
public enum RoundedCornerStyle: Equatable, Hashable, Sendable {
    // doc: SwiftUI/RoundedCornerStyle/circular
    case circular
    // doc: SwiftUI/RoundedCornerStyle/continuous
    case continuous
}

// doc: SwiftUI/ShapeRole
public enum ShapeRole: Equatable, Hashable, Sendable {
    // doc: SwiftUI/ShapeRole/fill
    case fill
    // doc: SwiftUI/ShapeRole/stroke
    case stroke
    // doc: SwiftUI/ShapeRole/separator
    case separator
}

// doc: SwiftUI/LayoutDirectionBehavior
public enum LayoutDirectionBehavior: Equatable, Hashable, Sendable {
    // doc: SwiftUI/LayoutDirectionBehavior/fixed
    case fixed
    // doc: SwiftUI/LayoutDirectionBehavior/mirrors
    public static var mirrors: LayoutDirectionBehavior { fatalError() }
    // doc: SwiftUI/LayoutDirectionBehavior/mirrors(in:)
    case mirrors(in: LayoutDirection)
}

// doc: SwiftUI/ProposedViewSize
public struct ProposedViewSize: Equatable, Sendable {
    // doc: SwiftUI/ProposedViewSize/zero
    public static var zero: ProposedViewSize { fatalError() }
    // doc: SwiftUI/ProposedViewSize/infinity
    public static var infinity: ProposedViewSize { fatalError() }
    // doc: SwiftUI/ProposedViewSize/unspecified
    public static var unspecified: ProposedViewSize { fatalError() }
    // doc: SwiftUI/ProposedViewSize/init(_:)
    public init(_ size: CGSize) { fatalError() }
    // doc: SwiftUI/ProposedViewSize/init(width:height:)
    public init(width: CGFloat?, height: CGFloat?) { fatalError() }
    // doc: SwiftUI/ProposedViewSize/height
    public var height: CGFloat? = nil
    // doc: SwiftUI/ProposedViewSize/width
    public var width: CGFloat? = nil
    // doc: SwiftUI/ProposedViewSize/replacingUnspecifiedDimensions(by:)
    public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize { fatalError() }
}

// doc: SwiftUI/TimelineScheduleMode
public enum TimelineScheduleMode: Equatable, Hashable, Sendable {
    // doc: SwiftUI/TimelineScheduleMode/normal
    case normal
    // doc: SwiftUI/TimelineScheduleMode/lowFrequency
    case lowFrequency
}

// doc: SwiftUI/HierarchicalShapeStyle
public struct HierarchicalShapeStyle: Sendable, ShapeStyle {
    // doc: SwiftUI/HierarchicalShapeStyle/primary
    public static var primary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/HierarchicalShapeStyle/secondary
    public static var secondary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/HierarchicalShapeStyle/tertiary
    public static var tertiary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/HierarchicalShapeStyle/quaternary
    public static var quaternary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/HierarchicalShapeStyle/quinary
    public static var quinary: HierarchicalShapeStyle { fatalError() }
}

// doc: SwiftUI/AnyShapeStyle
public struct AnyShapeStyle: Sendable, ShapeStyle {
    // doc: SwiftUI/AnyShapeStyle/init(_:)
    public init<S>(_ style: S) where S : ShapeStyle { fatalError() }
}

// doc: SwiftUI/ForegroundStyle
public struct ForegroundStyle: Sendable, ShapeStyle {
    // doc: SwiftUI/ForegroundStyle/init()
    public init() { fatalError() }
}

// doc: SwiftUI/BackgroundStyle
public struct BackgroundStyle: Sendable, ShapeStyle {
    // doc: SwiftUI/BackgroundStyle/init()
    public init() { fatalError() }
}

// doc: SwiftUI/TintShapeStyle
public struct TintShapeStyle: Sendable, ShapeStyle {
    // doc: SwiftUI/TintShapeStyle/init()
    public init() { fatalError() }
}

// NO PAGE: swiftui/colormode

// doc: SwiftUI/GraphicsContext
public struct GraphicsContext {
    // doc: SwiftUI/GraphicsContext/stroke(_:with:lineWidth:)
    public func stroke(_ path: Path, with shading: GraphicsContext.Shading, lineWidth: CGFloat = 1) { fatalError() }
    // doc: SwiftUI/GraphicsContext/stroke(_:with:style:)
    public func stroke(_ path: Path, with shading: GraphicsContext.Shading, style: StrokeStyle) { fatalError() }
    // doc: SwiftUI/GraphicsContext/fill(_:with:style:)
    public func fill(_ path: Path, with shading: GraphicsContext.Shading, style: FillStyle = FillStyle()) { fatalError() }
    // doc: SwiftUI/GraphicsContext/Shading
    public struct Shading: Sendable {
        // doc: SwiftUI/GraphicsContext/Shading/color(_:)
        public static func color(_ color: Color) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/color(_:red:green:blue:opacity:)
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/color(_:white:opacity:)
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/linearGradient(_:startPoint:endPoint:options:)  [iOS 18.0]
        public static func linearGradient(_ gradient: AnyGradient, startPoint: CGPoint, endPoint: CGPoint, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/radialGradient(_:center:startRadius:endRadius:options:)  [iOS 18.0]
        public static func radialGradient(_ gradient: AnyGradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/conicGradient(_:center:angle:options:)  [iOS 18.0]
        public static func conicGradient(_ gradient: AnyGradient, center: CGPoint, angle: Angle = Angle(), options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/style(_:)
        public static func style<S>(_ style: S) -> GraphicsContext.Shading where S : ShapeStyle { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/foreground
        public static var foreground: GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/tiledImage(_:origin:sourceRect:scale:)
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/palette(_:)
        public static func palette(_ array: [GraphicsContext.Shading]) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/backdrop
        public static var backdrop: GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/radialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)  [iOS 18.2]
        public static func radialGradient(_ gradient: AnyGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/radialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)-2altu  [iOS 18.2]
        public static func radialGradient(_ gradient: Gradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/conicGradient(_:center:angle:options:)-2t9ds
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/radialGradient(_:center:startRadius:endRadius:options:)-95j2v
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
        // doc: SwiftUI/GraphicsContext/Shading/linearGradient(_:startPoint:endPoint:options:)-21wfp
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/GradientOptions
    public struct GradientOptions: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/GraphicsContext/GradientOptions/linearColor
        public static var linearColor: GraphicsContext.GradientOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/GradientOptions/mirror
        public static var mirror: GraphicsContext.GradientOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/GradientOptions/repeat
        public static var `repeat`: GraphicsContext.GradientOptions { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/draw(_:in:)
    public func draw(_ symbol: GraphicsContext.ResolvedSymbol, in rect: CGRect) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:in:style:)
    public func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:at:anchor:)
    public func draw(_ image: GraphicsContext.ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/GraphicsContext/drawLayer(content:)
    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows { fatalError() }
    // doc: SwiftUI/GraphicsContext/resolve(_:)
    public func resolve(_ image: Image) -> GraphicsContext.ResolvedImage { fatalError() }
    // doc: SwiftUI/GraphicsContext/resolveSymbol(id:)
    public func resolveSymbol<ID>(id: ID) -> GraphicsContext.ResolvedSymbol? where ID : Hashable { fatalError() }
    // doc: SwiftUI/GraphicsContext/ResolvedSymbol
    public struct ResolvedSymbol {
        // doc: SwiftUI/GraphicsContext/ResolvedSymbol/size
        public var size: CGSize { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/ResolvedImage
    public struct ResolvedImage {
        // doc: SwiftUI/GraphicsContext/ResolvedImage/size
        public var size: CGSize { fatalError() }
        // doc: SwiftUI/GraphicsContext/ResolvedImage/baseline
        public var baseline: CGFloat { fatalError() }
        // doc: SwiftUI/GraphicsContext/ResolvedImage/shading
        public var shading: GraphicsContext.Shading? = nil
    }
    // doc: SwiftUI/GraphicsContext/ResolvedText
    public struct ResolvedText {
        // doc: SwiftUI/GraphicsContext/ResolvedText/firstBaseline(in:)
        public func firstBaseline(in size: CGSize) -> CGFloat { fatalError() }
        // doc: SwiftUI/GraphicsContext/ResolvedText/lastBaseline(in:)
        public func lastBaseline(in size: CGSize) -> CGFloat { fatalError() }
        // doc: SwiftUI/GraphicsContext/ResolvedText/measure(in:)
        public func measure(in size: CGSize) -> CGSize { fatalError() }
        // doc: SwiftUI/GraphicsContext/ResolvedText/shading
        public var shading: GraphicsContext.Shading { get { fatalError() } set { } }
    }
    // doc: SwiftUI/GraphicsContext/clip(to:style:options:)
    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: GraphicsContext.ClipOptions = ClipOptions()) { fatalError() }
    // doc: SwiftUI/GraphicsContext/clipToLayer(opacity:options:content:)
    public mutating func clipToLayer(opacity: Double = 1, options: GraphicsContext.ClipOptions = ClipOptions(), content: (inout GraphicsContext) throws -> Void) rethrows { fatalError() }
    // doc: SwiftUI/GraphicsContext/clipBoundingRect
    public var clipBoundingRect: CGRect { fatalError() }
    // doc: SwiftUI/GraphicsContext/ClipOptions
    public struct ClipOptions: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/GraphicsContext/ClipOptions/inverse
        public static var inverse: GraphicsContext.ClipOptions { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/opacity
    public var opacity: Double { get { fatalError() } set { } }
    // doc: SwiftUI/GraphicsContext/blendMode-swift.property
    public var blendMode: GraphicsContext.BlendMode { get { fatalError() } set { } }
    // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct
    public struct BlendMode: Equatable, Sendable {
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/normal
        public static var normal: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/darken
        public static var darken: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/multiply
        public static var multiply: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/colorBurn
        public static var colorBurn: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/plusDarker
        public static var plusDarker: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/lighten
        public static var lighten: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/screen
        public static var screen: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/colorDodge
        public static var colorDodge: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/plusLighter
        public static var plusLighter: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/overlay
        public static var overlay: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/softLight
        public static var softLight: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/hardLight
        public static var hardLight: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/difference
        public static var difference: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/exclusion
        public static var exclusion: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/hue
        public static var hue: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/saturation
        public static var saturation: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/color
        public static var color: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/luminosity
        public static var luminosity: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/clear
        public static var clear: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/copy
        public static var copy: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/sourceIn
        public static var sourceIn: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/sourceOut
        public static var sourceOut: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/sourceAtop
        public static var sourceAtop: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/destinationOver
        public static var destinationOver: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/destinationIn
        public static var destinationIn: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/destinationOut
        public static var destinationOut: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/destinationAtop
        public static var destinationAtop: GraphicsContext.BlendMode { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlendMode-swift.struct/xor
        public static var xor: GraphicsContext.BlendMode { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/addFilter(_:options:)
    public mutating func addFilter(_ filter: GraphicsContext.Filter, options: GraphicsContext.FilterOptions = FilterOptions()) { fatalError() }
    // doc: SwiftUI/GraphicsContext/Filter
    public struct Filter: Sendable {
        // doc: SwiftUI/GraphicsContext/Filter/brightness(_:)
        public static func brightness(_ amount: Double) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/contrast(_:)
        public static func contrast(_ amount: Double) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/saturation(_:)
        public static func saturation(_ amount: Double) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/colorInvert(_:)
        public static func colorInvert(_ amount: Double = 1) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/colorMultiply(_:)
        public static func colorMultiply(_ color: Color) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/hueRotation(_:)
        public static func hueRotation(_ angle: Angle) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/grayscale(_:)
        public static func grayscale(_ amount: Double) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/blur(radius:options:)
        public static func blur(radius: CGFloat, options: GraphicsContext.BlurOptions = BlurOptions()) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/shadow(color:radius:x:y:blendMode:options:)
        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0, blendMode: GraphicsContext.BlendMode = .normal, options: GraphicsContext.ShadowOptions = ShadowOptions()) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/luminanceToAlpha
        public static var luminanceToAlpha: GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/alphaThreshold(min:max:color:)
        public static func alphaThreshold(min: Double, max: Double = 1, color: Color = Color.black) -> GraphicsContext.Filter { fatalError() }
        // doc: SwiftUI/GraphicsContext/Filter/alphaMultiply(_:)  [iOS 18.0]
        public static func alphaMultiply(_ color: Color) -> GraphicsContext.Filter { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/FilterOptions
    public struct FilterOptions: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/GraphicsContext/FilterOptions/linearColor
        public static var linearColor: GraphicsContext.FilterOptions { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/BlurOptions
    public struct BlurOptions: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/GraphicsContext/BlurOptions/dithersResult
        public static var dithersResult: GraphicsContext.BlurOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/BlurOptions/opaque
        public static var opaque: GraphicsContext.BlurOptions { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/ShadowOptions
    public struct ShadowOptions: Equatable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/GraphicsContext/ShadowOptions/disablesGroup
        public static var disablesGroup: GraphicsContext.ShadowOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/ShadowOptions/invertsAlpha
        public static var invertsAlpha: GraphicsContext.ShadowOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/ShadowOptions/shadowAbove
        public static var shadowAbove: GraphicsContext.ShadowOptions { fatalError() }
        // doc: SwiftUI/GraphicsContext/ShadowOptions/shadowOnly
        public static var shadowOnly: GraphicsContext.ShadowOptions { fatalError() }
    }
    // doc: SwiftUI/GraphicsContext/scaleBy(x:y:)
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { fatalError() }
    // doc: SwiftUI/GraphicsContext/rotate(by:)
    public mutating func rotate(by angle: Angle) { fatalError() }
    // doc: SwiftUI/GraphicsContext/translateBy(x:y:)
    public mutating func translateBy(x: CGFloat, y: CGFloat) { fatalError() }
    // doc: SwiftUI/GraphicsContext/concatenate(_:)
    public mutating func concatenate(_ matrix: CGAffineTransform) { fatalError() }
    // doc: SwiftUI/GraphicsContext/transform
    public var transform: CGAffineTransform { get { fatalError() } set { } }
    // doc: SwiftUI/GraphicsContext/environment
    public var environment: EnvironmentValues { get { fatalError() } set { } }
    // doc: SwiftUI/GraphicsContext/draw(_:in:)-69ad8
    public func draw(_ text: GraphicsContext.ResolvedText, in rect: CGRect) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:at:anchor:)-6xr87
    public func draw(_ text: GraphicsContext.ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:at:anchor:)-7l217
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:in:)-5opqf
    public func draw(_ text: Text, in rect: CGRect) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:in:style:)-blhz
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) { fatalError() }
    // doc: SwiftUI/GraphicsContext/resolve(_:)-4dx65
    public func resolve(_ text: Text) -> GraphicsContext.ResolvedText { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:at:anchor:)-5dgmd
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/GraphicsContext/draw(_:at:anchor:)-7jmr8
    public func draw(_ symbol: GraphicsContext.ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/GraphicsContext/resolve(_:)-28u0d
    public func resolve(_ shading: GraphicsContext.Shading) -> GraphicsContext.Shading { fatalError() }
}

// NO PAGE: swiftui/image/renderingmode

// doc: SwiftUI/SymbolVariants
public struct SymbolVariants: Equatable, Hashable, Sendable {
    // doc: SwiftUI/SymbolVariants/none
    public static var none: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/circle-swift.type.property
    public static var circle: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/square-swift.type.property
    public static var square: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/rectangle-swift.type.property
    public static var rectangle: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/fill-swift.type.property
    public static var fill: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/slash-swift.type.property
    public static var slash: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/circle-swift.property
    public var circle: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/square-swift.property
    public var square: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/rectangle-swift.property
    public var rectangle: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/fill-swift.property
    public var fill: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/slash-swift.property
    public var slash: SymbolVariants { fatalError() }
    // doc: SwiftUI/SymbolVariants/contains(_:)
    public func contains(_ other: SymbolVariants) -> Bool { fatalError() }
}

// doc: SwiftUI/ViewDimensions
public struct ViewDimensions: Equatable {
    // doc: SwiftUI/ViewDimensions/height
    public var height: CGFloat { fatalError() }
    // doc: SwiftUI/ViewDimensions/width
    public var width: CGFloat { fatalError() }
    // doc: SwiftUI/ViewDimensions/subscript(_:)
    public subscript(guide: HorizontalAlignment) -> CGFloat { fatalError() }
    // doc: SwiftUI/ViewDimensions/subscript(explicit:)
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { fatalError() }
    // doc: SwiftUI/ViewDimensions/subscript(explicit:)-4krm2
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { fatalError() }
    // doc: SwiftUI/ViewDimensions/subscript(_:)-7dtda
    public subscript(guide: VerticalAlignment) -> CGFloat { fatalError() }
}

// doc: SwiftUI/SearchFieldPlacement
public struct SearchFieldPlacement: Sendable {
    // doc: SwiftUI/SearchFieldPlacement/automatic
    public static var automatic: SearchFieldPlacement { fatalError() }
    // doc: SwiftUI/SearchFieldPlacement/navigationBarDrawer
    public static var navigationBarDrawer: SearchFieldPlacement { fatalError() }
    // doc: SwiftUI/SearchFieldPlacement/navigationBarDrawer(displayMode:)
    public static func navigationBarDrawer(displayMode: SearchFieldPlacement.NavigationBarDrawerDisplayMode) -> SearchFieldPlacement { fatalError() }
    // doc: SwiftUI/SearchFieldPlacement/sidebar
    public static var sidebar: SearchFieldPlacement { fatalError() }
    // doc: SwiftUI/SearchFieldPlacement/toolbar
    public static var toolbar: SearchFieldPlacement { fatalError() }
    // doc: SwiftUI/SearchFieldPlacement/NavigationBarDrawerDisplayMode
    public struct NavigationBarDrawerDisplayMode: Sendable {
        // doc: SwiftUI/SearchFieldPlacement/NavigationBarDrawerDisplayMode/always
        public static var always: SearchFieldPlacement.NavigationBarDrawerDisplayMode { fatalError() }
        // doc: SwiftUI/SearchFieldPlacement/NavigationBarDrawerDisplayMode/automatic
        public static var automatic: SearchFieldPlacement.NavigationBarDrawerDisplayMode { fatalError() }
    }
    // doc: SwiftUI/SearchFieldPlacement/toolbarPrincipal
    public static var toolbarPrincipal: SearchFieldPlacement { fatalError() }
}

// doc: SwiftUI/SafeAreaRegions
public struct SafeAreaRegions: Equatable, Sendable, OptionSet {
    // shim: OptionSet storage (the docs page set has no rawValue page for this type)
    public let rawValue: Int
    // shim: OptionSet requirement
    public init(rawValue: Int) { self.rawValue = rawValue }
    // doc: SwiftUI/SafeAreaRegions/all
    public static var all: SafeAreaRegions { fatalError() }
    // doc: SwiftUI/SafeAreaRegions/container
    public static var container: SafeAreaRegions { fatalError() }
    // doc: SwiftUI/SafeAreaRegions/keyboard
    public static var keyboard: SafeAreaRegions { fatalError() }
}

// doc: SwiftUI/SubmitTriggers
public struct SubmitTriggers: Equatable, Sendable, OptionSet {
    // shim: OptionSet storage (the docs page set has no rawValue page for this type)
    public let rawValue: Int
    // doc: SwiftUI/SubmitTriggers/search
    public static var search: SubmitTriggers { fatalError() }
    // doc: SwiftUI/SubmitTriggers/text
    public static var text: SubmitTriggers { fatalError() }
    // doc: SwiftUI/SubmitTriggers/init(rawValue:)
    public init(rawValue: SubmitTriggers.RawValue) { fatalError() }
}

// doc: SwiftUI/ColorRenderingMode
public enum ColorRenderingMode: Equatable, Hashable, Sendable {
    // doc: SwiftUI/ColorRenderingMode/extendedLinear
    case extendedLinear
    // doc: SwiftUI/ColorRenderingMode/linear
    case linear
    // doc: SwiftUI/ColorRenderingMode/nonLinear
    case nonLinear
}

// doc: SwiftUI/PrimitiveButtonStyleConfiguration
public struct PrimitiveButtonStyleConfiguration {
    // doc: SwiftUI/PrimitiveButtonStyleConfiguration/label-swift.property
    public var label: PrimitiveButtonStyleConfiguration.Label { fatalError() }
    // doc: SwiftUI/PrimitiveButtonStyleConfiguration/Label-swift.struct
    @MainActor @preconcurrency public struct Label {
    }
    // doc: SwiftUI/PrimitiveButtonStyleConfiguration/trigger()
    public func trigger() { fatalError() }
    // doc: SwiftUI/PrimitiveButtonStyleConfiguration/role
    public var role: ButtonRole? { fatalError() }
}

// doc: SwiftUI/ShadowStyle
public struct ShadowStyle: Equatable, Sendable {
    // doc: SwiftUI/ShadowStyle/drop(color:radius:x:y:)
    public static func drop(color: Color = .init(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle { fatalError() }
    // doc: SwiftUI/ShadowStyle/inner(color:radius:x:y:)
    public static func inner(color: Color = .init(.sRGBLinear, white: 0, opacity: 0.55), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle { fatalError() }
}

// doc: SwiftUI/ScrollDismissesKeyboardMode
public struct ScrollDismissesKeyboardMode: Equatable, Hashable, Sendable {
    // doc: SwiftUI/ScrollDismissesKeyboardMode/automatic
    public static var automatic: ScrollDismissesKeyboardMode { fatalError() }
    // doc: SwiftUI/ScrollDismissesKeyboardMode/immediately
    public static var immediately: ScrollDismissesKeyboardMode { fatalError() }
    // doc: SwiftUI/ScrollDismissesKeyboardMode/interactively
    public static var interactively: ScrollDismissesKeyboardMode { fatalError() }
    // doc: SwiftUI/ScrollDismissesKeyboardMode/never
    public static var never: ScrollDismissesKeyboardMode { fatalError() }
}

// doc: SwiftUI/UserInterfaceSizeClass
public enum UserInterfaceSizeClass: Equatable, Hashable, Sendable {
    // doc: SwiftUI/UserInterfaceSizeClass/compact
    case compact
    // doc: SwiftUI/UserInterfaceSizeClass/regular
    case regular
}

// doc: SwiftUI/ToolbarPlacement
public struct ToolbarPlacement {
    // doc: SwiftUI/ToolbarPlacement/automatic
    public static var automatic: ToolbarPlacement { fatalError() }
    // doc: SwiftUI/ToolbarPlacement/bottomBar
    public static var bottomBar: ToolbarPlacement { fatalError() }
    // doc: SwiftUI/ToolbarPlacement/navigationBar
    public static var navigationBar: ToolbarPlacement { fatalError() }
    // doc: SwiftUI/ToolbarPlacement/tabBar
    public static var tabBar: ToolbarPlacement { fatalError() }
    // doc: SwiftUI/ToolbarPlacement/statusBar  [iOS 27.0]
    public static var statusBar: ToolbarPlacement { fatalError() }
}

// doc: SwiftUI/PinnedScrollableViews
public struct PinnedScrollableViews: Equatable, Sendable, OptionSet {
    // shim: OptionSet storage (the docs page set has no rawValue page for this type)
    public let rawValue: Int
    // shim: OptionSet requirement
    public init(rawValue: Int) { self.rawValue = rawValue }
    // doc: SwiftUI/PinnedScrollableViews/sectionHeaders
    public static var sectionHeaders: PinnedScrollableViews { fatalError() }
    // doc: SwiftUI/PinnedScrollableViews/sectionFooters
    public static var sectionFooters: PinnedScrollableViews { fatalError() }
}

// doc: SwiftUI/Alert
public struct Alert {
    // doc: SwiftUI/Alert/init(title:message:dismissButton:)
    public init(title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil) { fatalError() }
    // doc: SwiftUI/Alert/init(title:message:primaryButton:secondaryButton:)
    public init(title: Text, message: Text? = nil, primaryButton: Alert.Button, secondaryButton: Alert.Button) { fatalError() }
    // doc: SwiftUI/Alert/Button
    public struct Button {
        // doc: SwiftUI/Alert/Button/default(_:action:)
        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { fatalError() }
        // doc: SwiftUI/Alert/Button/cancel(_:)
        public static func cancel(_ action: (() -> Void)? = {}) -> Alert.Button { fatalError() }
        // doc: SwiftUI/Alert/Button/cancel(_:action:)
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { fatalError() }
        // doc: SwiftUI/Alert/Button/destructive(_:action:)
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { fatalError() }
    }
}

// doc: SwiftUI/NavigationPath
public struct NavigationPath: Equatable {
    // doc: SwiftUI/NavigationPath/init()
    public init() { fatalError() }
    // doc: SwiftUI/NavigationPath/init(_:)
    public init(_ codable: NavigationPath.CodableRepresentation) { fatalError() }
    // doc: SwiftUI/NavigationPath/isEmpty
    public var isEmpty: Bool { fatalError() }
    // doc: SwiftUI/NavigationPath/count
    public var count: Int { fatalError() }
    // doc: SwiftUI/NavigationPath/append(_:)
    public mutating func append<V>(_ value: V) where V : Decodable, V : Encodable, V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationPath/removeLast(_:)
    public mutating func removeLast(_ k: Int = 1) { fatalError() }
    // doc: SwiftUI/NavigationPath/codable
    public var codable: NavigationPath.CodableRepresentation? { fatalError() }
    // doc: SwiftUI/NavigationPath/CodableRepresentation
    public struct CodableRepresentation: Equatable {
    }
    // doc: SwiftUI/NavigationPath/init(_:)-dfls
    public init<S>(_ elements: S) where S : Sequence, S.Element : Hashable { fatalError() }
    // doc: SwiftUI/NavigationPath/init(_:)-7orbl
    public init<S>(_ elements: S) where S : Sequence, S.Element : Decodable, S.Element : Encodable, S.Element : Hashable { fatalError() }
    // doc: SwiftUI/NavigationPath/append(_:)-64o0f
    public mutating func append<V>(_ value: V) where V : Hashable { fatalError() }
}

// doc: SwiftUI/AnyGradient
public struct AnyGradient: Equatable, Hashable, Sendable, ShapeStyle {
    // doc: SwiftUI/AnyGradient/init(_:)
    public init(_ gradient: Gradient) { fatalError() }
    // doc: SwiftUI/AnyGradient/colorSpace(_:)
    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient { fatalError() }
}

// doc: SwiftUI/AngularGradient
public struct AngularGradient: Sendable, ShapeStyle {
    // doc: SwiftUI/AngularGradient/init(gradient:center:angle:)
    public nonisolated init(gradient: Gradient, center: UnitPoint, angle: Angle = .zero) { fatalError() }
    // doc: SwiftUI/AngularGradient/init(colors:center:angle:)
    public nonisolated init(colors: [Color], center: UnitPoint, angle: Angle = .zero) { fatalError() }
    // doc: SwiftUI/AngularGradient/init(stops:center:angle:)
    public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) { fatalError() }
    // doc: SwiftUI/AngularGradient/init(gradient:center:startAngle:endAngle:)
    public nonisolated init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) { fatalError() }
    // doc: SwiftUI/AngularGradient/init(colors:center:startAngle:endAngle:)
    public nonisolated init(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) { fatalError() }
    // doc: SwiftUI/AngularGradient/init(stops:center:startAngle:endAngle:)
    public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) { fatalError() }
}

// doc: SwiftUI/RadialGradient
public struct RadialGradient: Sendable, ShapeStyle {
    // doc: SwiftUI/RadialGradient/init(gradient:center:startRadius:endRadius:)
    public nonisolated init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { fatalError() }
    // doc: SwiftUI/RadialGradient/init(colors:center:startRadius:endRadius:)
    public nonisolated init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { fatalError() }
    // doc: SwiftUI/RadialGradient/init(stops:center:startRadius:endRadius:)
    public nonisolated init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) { fatalError() }
}

// doc: SwiftUI/EllipticalGradient
public struct EllipticalGradient: Sendable, ShapeStyle {
    // doc: SwiftUI/EllipticalGradient/init(gradient:center:startRadiusFraction:endRadiusFraction:)
    public nonisolated init(gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) { fatalError() }
    // doc: SwiftUI/EllipticalGradient/init(colors:center:startRadiusFraction:endRadiusFraction:)
    public nonisolated init(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) { fatalError() }
    // doc: SwiftUI/EllipticalGradient/init(stops:center:startRadiusFraction:endRadiusFraction:)
    public nonisolated init(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) { fatalError() }
}

// doc: SwiftUI/OffsetShape
public struct OffsetShape<Content>: Sendable where Content : Shape {
    // doc: SwiftUI/OffsetShape/init(shape:offset:)
    public init(shape: Content, offset: CGSize) { fatalError() }
    // doc: SwiftUI/OffsetShape/offset
    public var offset: CGSize { get { fatalError() } set { } }
    // doc: SwiftUI/OffsetShape/shape
    public var shape: Content { get { fatalError() } set { } }
}

// doc: SwiftUI/ScaledShape
public struct ScaledShape<Content>: Sendable where Content : Shape {
    // doc: SwiftUI/ScaledShape/init(shape:scale:anchor:)
    public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/ScaledShape/anchor
    public var anchor: UnitPoint { get { fatalError() } set { } }
    // doc: SwiftUI/ScaledShape/scale
    public var scale: CGSize { get { fatalError() } set { } }
    // doc: SwiftUI/ScaledShape/shape
    public var shape: Content { get { fatalError() } set { } }
}

// doc: SwiftUI/TransformedShape
public struct TransformedShape<Content>: Sendable where Content : Shape {
    // doc: SwiftUI/TransformedShape/init(shape:transform:)
    public init(shape: Content, transform: CGAffineTransform) { fatalError() }
    // doc: SwiftUI/TransformedShape/shape
    public var shape: Content { get { fatalError() } set { } }
    // doc: SwiftUI/TransformedShape/transform
    public var transform: CGAffineTransform { get { fatalError() } set { } }
}

// doc: SwiftUI/RotatedShape
public struct RotatedShape<Content>: Sendable where Content : Shape {
    // doc: SwiftUI/RotatedShape/init(shape:angle:anchor:)
    public init(shape: Content, angle: Angle, anchor: UnitPoint = .center) { fatalError() }
    // doc: SwiftUI/RotatedShape/anchor
    public var anchor: UnitPoint { get { fatalError() } set { } }
    // doc: SwiftUI/RotatedShape/angle
    public var angle: Angle { get { fatalError() } set { } }
    // doc: SwiftUI/RotatedShape/shape
    public var shape: Content { get { fatalError() } set { } }
}

// doc: SwiftUI/RectangleCornerRadii
public struct RectangleCornerRadii: Equatable, Sendable {
    // doc: SwiftUI/RectangleCornerRadii/init(topLeading:bottomLeading:bottomTrailing:topTrailing:)
    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) { fatalError() }
    // doc: SwiftUI/RectangleCornerRadii/topLeading
    public var topLeading: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/RectangleCornerRadii/topTrailing
    public var topTrailing: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/RectangleCornerRadii/bottomLeading
    public var bottomLeading: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/RectangleCornerRadii/bottomTrailing
    public var bottomTrailing: CGFloat { get { fatalError() } set { } }
    // doc: SwiftUI/RectangleCornerRadii/subscript(_:)  [iOS 26.0]
    public subscript(corner: Edge.Corner) -> CGFloat { fatalError() }
}

// doc: SwiftUI/AnimationContext
public struct AnimationContext<Value> where Value : VectorArithmetic {
    // doc: SwiftUI/AnimationContext/environment
    public var environment: EnvironmentValues { fatalError() }
    // doc: SwiftUI/AnimationContext/isLogicallyComplete
    public var isLogicallyComplete: Bool { get { fatalError() } set { } }
}

// doc: SwiftUI/Spring
public struct Spring: Equatable, Hashable, Sendable {
    // doc: SwiftUI/Spring/init(duration:bounce:)
    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) { fatalError() }
    // doc: SwiftUI/Spring/init(mass:stiffness:damping:allowOverDamping:)
    public init(mass: Double = 1.0, stiffness: Double, damping: Double, allowOverDamping: Bool = false) { fatalError() }
    // doc: SwiftUI/Spring/init(response:dampingRatio:)
    public init(response: Double, dampingRatio: Double) { fatalError() }
    // doc: SwiftUI/Spring/init(settlingDuration:dampingRatio:epsilon:)
    public init(settlingDuration: TimeInterval, dampingRatio: Double, epsilon: Double = 0.001) { fatalError() }
    // doc: SwiftUI/Spring/bouncy
    public static var bouncy: Spring { fatalError() }
    // doc: SwiftUI/Spring/bouncy(duration:extraBounce:)
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring { fatalError() }
    // doc: SwiftUI/Spring/smooth
    public static var smooth: Spring { fatalError() }
    // doc: SwiftUI/Spring/smooth(duration:extraBounce:)
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring { fatalError() }
    // doc: SwiftUI/Spring/snappy
    public static var snappy: Spring { fatalError() }
    // doc: SwiftUI/Spring/snappy(duration:extraBounce:)
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring { fatalError() }
    // doc: SwiftUI/Spring/bounce
    public var bounce: Double { fatalError() }
    // doc: SwiftUI/Spring/damping
    public var damping: Double { fatalError() }
    // doc: SwiftUI/Spring/dampingRatio
    public var dampingRatio: Double { fatalError() }
    // doc: SwiftUI/Spring/duration
    public var duration: TimeInterval { fatalError() }
    // doc: SwiftUI/Spring/mass
    public var mass: Double { fatalError() }
    // doc: SwiftUI/Spring/response
    public var response: Double { fatalError() }
    // doc: SwiftUI/Spring/settlingDuration
    public var settlingDuration: TimeInterval { fatalError() }
    // doc: SwiftUI/Spring/stiffness
    public var stiffness: Double { fatalError() }
    // doc: SwiftUI/Spring/value(target:initialVelocity:time:)
    public func value<V>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Spring/value(fromValue:toValue:initialVelocity:time:)
    public func value<V>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V where V : Animatable { fatalError() }
    // doc: SwiftUI/Spring/velocity(target:initialVelocity:time:)
    public func velocity<V>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Spring/velocity(fromValue:toValue:initialVelocity:time:)
    public func velocity<V>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V where V : Animatable { fatalError() }
    // doc: SwiftUI/Spring/update(value:velocity:target:deltaTime:)
    public func update<V>(value: inout V, velocity: inout V, target: V, deltaTime: TimeInterval) where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Spring/force(target:position:velocity:)
    public func force<V>(target: V, position: V, velocity: V) -> V where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Spring/force(fromValue:toValue:position:velocity:)
    public func force<V>(fromValue: V, toValue: V, position: V, velocity: V) -> V where V : Animatable { fatalError() }
    // doc: SwiftUI/Spring/settlingDuration(target:initialVelocity:epsilon:)
    public func settlingDuration<V>(target: V, initialVelocity: V = .zero, epsilon: Double) -> TimeInterval where V : VectorArithmetic { fatalError() }
    // doc: SwiftUI/Spring/settlingDuration(fromValue:toValue:initialVelocity:epsilon:)
    public func settlingDuration<V>(fromValue: V, toValue: V, initialVelocity: V, epsilon: Double) -> TimeInterval where V : Animatable { fatalError() }
}

// doc: SwiftUI/UnitCurve
public struct UnitCurve: Equatable, Hashable, Sendable {
    // doc: SwiftUI/UnitCurve/linear
    public static var linear: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/easeIn
    public static var easeIn: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/easeOut
    public static var easeOut: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/easeInOut
    public static var easeInOut: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/circularEaseIn
    public static var circularEaseIn: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/circularEaseOut
    public static var circularEaseOut: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/circularEaseInOut
    public static var circularEaseInOut: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/bezier(startControlPoint:endControlPoint:)
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/inverse
    public var inverse: UnitCurve { fatalError() }
    // doc: SwiftUI/UnitCurve/value(at:)
    public func value(at progress: Double) -> Double { fatalError() }
    // doc: SwiftUI/UnitCurve/velocity(at:)
    public func velocity(at progress: Double) -> Double { fatalError() }
    // doc: SwiftUI/UnitCurve/easeInEaseOut
    public static var easeInEaseOut: UnitCurve { fatalError() }
}

// doc: SwiftUI/ViewSpacing
public struct ViewSpacing: Sendable {
    // doc: SwiftUI/ViewSpacing/init()
    public init() { fatalError() }
    // doc: SwiftUI/ViewSpacing/zero
    public static var zero: ViewSpacing { fatalError() }
    // doc: SwiftUI/ViewSpacing/distance(to:along:)
    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat { fatalError() }
    // doc: SwiftUI/ViewSpacing/formUnion(_:edges:)
    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) { fatalError() }
    // doc: SwiftUI/ViewSpacing/union(_:edges:)
    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing { fatalError() }
}

// doc: SwiftUI/LayoutSubviews
public struct LayoutSubviews: Equatable, Sendable {
    // doc: SwiftUI/LayoutSubviews/layoutDirection
    public var layoutDirection: LayoutDirection { get { fatalError() } set { } }
    // doc: SwiftUI/LayoutSubviews/subscript(_:)
    public subscript(bounds: Range<Int>) -> LayoutSubviews { fatalError() }
    // doc: SwiftUI/LayoutSubviews/startIndex
    public var startIndex: Int { fatalError() }
    // doc: SwiftUI/LayoutSubviews/endIndex
    public var endIndex: Int { fatalError() }
    // doc: SwiftUI/LayoutSubviews/Element
    public typealias Element = LayoutSubview
    // doc: SwiftUI/LayoutSubviews/Index
    public typealias Index = Int
    // doc: SwiftUI/LayoutSubviews/SubSequence
    public typealias SubSequence = LayoutSubviews
    // doc: SwiftUI/LayoutSubviews/subscript(_:)-56yi8
    public subscript<S>(indices: S) -> LayoutSubviews where S : Sequence, S.Element == Int { fatalError() }
    // doc: SwiftUI/LayoutSubviews/subscript(_:)-1gzie
    public subscript(index: Int) -> LayoutSubviews.Element { fatalError() }
}

// doc: SwiftUI/LayoutSubview
public struct LayoutSubview: Equatable {
    // doc: SwiftUI/LayoutSubview/place(at:anchor:proposal:)
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) { fatalError() }
    // doc: SwiftUI/LayoutSubview/dimensions(in:)
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions { fatalError() }
    // doc: SwiftUI/LayoutSubview/sizeThatFits(_:)
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { fatalError() }
    // doc: SwiftUI/LayoutSubview/spacing
    public var spacing: ViewSpacing { fatalError() }
    // doc: SwiftUI/LayoutSubview/priority
    public var priority: Double { fatalError() }
}

// doc: SwiftUI/LayoutProperties
public struct LayoutProperties: Sendable {
    // doc: SwiftUI/LayoutProperties/init()
    public init() { fatalError() }
    // doc: SwiftUI/LayoutProperties/stackOrientation
    public var stackOrientation: Axis? = nil
}

// doc: SwiftUI/AccessibilityChildBehavior
public struct AccessibilityChildBehavior: Equatable, Hashable {
    // doc: SwiftUI/AccessibilityChildBehavior/combine
    public static var combine: AccessibilityChildBehavior { fatalError() }
    // doc: SwiftUI/AccessibilityChildBehavior/contain
    public static var contain: AccessibilityChildBehavior { fatalError() }
    // doc: SwiftUI/AccessibilityChildBehavior/ignore
    public static var ignore: AccessibilityChildBehavior { fatalError() }
}

// doc: SwiftUI/AccessibilityAttachmentModifier
public struct AccessibilityAttachmentModifier {
}

// doc: SwiftUI/AccessibilityHeadingLevel
public enum AccessibilityHeadingLevel: Equatable, Hashable, Sendable {
    // doc: SwiftUI/AccessibilityHeadingLevel/h1
    case h1
    // doc: SwiftUI/AccessibilityHeadingLevel/h2
    case h2
    // doc: SwiftUI/AccessibilityHeadingLevel/h3
    case h3
    // doc: SwiftUI/AccessibilityHeadingLevel/h4
    case h4
    // doc: SwiftUI/AccessibilityHeadingLevel/h5
    case h5
    // doc: SwiftUI/AccessibilityHeadingLevel/h6
    case h6
    // doc: SwiftUI/AccessibilityHeadingLevel/unspecified
    case unspecified
}

// doc: SwiftUI/AccessibilityTextContentType
public struct AccessibilityTextContentType: Sendable {
    // doc: SwiftUI/AccessibilityTextContentType/console
    public static var console: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/fileSystem
    public static var fileSystem: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/messaging
    public static var messaging: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/narrative
    public static var narrative: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/plain
    public static var plain: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/sourceCode
    public static var sourceCode: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/spreadsheet
    public static var spreadsheet: AccessibilityTextContentType { fatalError() }
    // doc: SwiftUI/AccessibilityTextContentType/wordProcessing
    public static var wordProcessing: AccessibilityTextContentType { fatalError() }
}

// doc: SwiftUI/AccessibilityAdjustmentDirection
public enum AccessibilityAdjustmentDirection: Equatable, Hashable, Sendable {
    // doc: SwiftUI/AccessibilityAdjustmentDirection/decrement
    case decrement
    // doc: SwiftUI/AccessibilityAdjustmentDirection/increment
    case increment
}

// doc: SwiftUI/KeyboardShortcut
public struct KeyboardShortcut: Equatable, Hashable, Sendable {
    // doc: SwiftUI/KeyboardShortcut/cancelAction
    public static var cancelAction: KeyboardShortcut { fatalError() }
    // doc: SwiftUI/KeyboardShortcut/defaultAction
    public static var defaultAction: KeyboardShortcut { fatalError() }
    // doc: SwiftUI/KeyboardShortcut/localization-swift.property
    public var localization: KeyboardShortcut.Localization { get { fatalError() } set { } }
    // doc: SwiftUI/KeyboardShortcut/Localization-swift.struct
    public struct Localization: Sendable {
        // doc: SwiftUI/KeyboardShortcut/Localization-swift.struct/automatic
        public static var automatic: KeyboardShortcut.Localization { fatalError() }
        // doc: SwiftUI/KeyboardShortcut/Localization-swift.struct/custom
        public static var custom: KeyboardShortcut.Localization { fatalError() }
        // doc: SwiftUI/KeyboardShortcut/Localization-swift.struct/withoutMirroring
        public static var withoutMirroring: KeyboardShortcut.Localization { fatalError() }
    }
}

// doc: SwiftUI/TextSelection
public struct TextSelection: Equatable, Hashable {
    // doc: SwiftUI/TextSelection/init(insertionPoint:)  [iOS 18.0]
    public init(insertionPoint: String.Index) { fatalError() }
    // doc: SwiftUI/TextSelection/init(range:)  [iOS 18.0]
    public init(range: Range<String.Index>) { fatalError() }
    // doc: SwiftUI/TextSelection/init(ranges:)  [iOS 18.0]
    public init(ranges: RangeSet<String.Index>) { fatalError() }
    // doc: SwiftUI/TextSelection/indices-swift.property  [iOS 18.0]
    public var indices: TextSelection.Indices { get { fatalError() } set { } }
    // doc: SwiftUI/TextSelection/isInsertion  [iOS 18.0]
    public var isInsertion: Bool { fatalError() }
    // doc: SwiftUI/TextSelection/Indices-swift.enum
    public enum Indices: Equatable, Hashable {
        // doc: SwiftUI/TextSelection/Indices-swift.enum/multiSelection(_:)  [iOS 18.0]
        case multiSelection(RangeSet<String.Index>)
        // doc: SwiftUI/TextSelection/Indices-swift.enum/selection(_:)  [iOS 18.0]
        case selection(Range<String.Index>)
    }
}

// doc: SwiftUI/PresentationBackgroundInteraction
public struct PresentationBackgroundInteraction: Sendable {
    // doc: SwiftUI/PresentationBackgroundInteraction/automatic
    public static var automatic: PresentationBackgroundInteraction { fatalError() }
    // doc: SwiftUI/PresentationBackgroundInteraction/disabled
    public static var disabled: PresentationBackgroundInteraction { fatalError() }
    // doc: SwiftUI/PresentationBackgroundInteraction/enabled
    public static var enabled: PresentationBackgroundInteraction { fatalError() }
    // doc: SwiftUI/PresentationBackgroundInteraction/enabled(upThrough:)
    public static func enabled(upThrough detent: PresentationDetent) -> PresentationBackgroundInteraction { fatalError() }
}

// doc: SwiftUI/PresentationContentInteraction
public struct PresentationContentInteraction: Equatable, Sendable {
    // doc: SwiftUI/PresentationContentInteraction/automatic
    public static var automatic: PresentationContentInteraction { fatalError() }
    // doc: SwiftUI/PresentationContentInteraction/resizes
    public static var resizes: PresentationContentInteraction { fatalError() }
    // doc: SwiftUI/PresentationContentInteraction/scrolls
    public static var scrolls: PresentationContentInteraction { fatalError() }
}

// doc: SwiftUI/ScenePhase
public enum ScenePhase: Equatable, Hashable, Comparable, Sendable {
    // doc: SwiftUI/ScenePhase/active
    case active
    // doc: SwiftUI/ScenePhase/inactive
    case inactive
    // doc: SwiftUI/ScenePhase/background
    case background
}

// doc: SwiftUI/Glass
public struct Glass: Equatable, Sendable {
    // doc: SwiftUI/Glass/interactive(_:)  [iOS 26.0]
    public func interactive(_ isEnabled: Bool = true) -> Glass { fatalError() }
    // doc: SwiftUI/Glass/tint(_:)  [iOS 26.0]
    public func tint(_ color: Color?) -> Glass { fatalError() }
    // doc: SwiftUI/Glass/clear  [iOS 26.0]
    public static var clear: Glass { fatalError() }
    // doc: SwiftUI/Glass/identity  [iOS 26.0]
    public static var identity: Glass { fatalError() }
    // doc: SwiftUI/Glass/regular  [iOS 26.0]
    public static var regular: Glass { fatalError() }
}

// doc: SwiftUI/NavigationBarItem
public struct NavigationBarItem: Sendable {
    // doc: SwiftUI/NavigationBarItem/TitleDisplayMode
    public enum TitleDisplayMode: Equatable, Hashable, Sendable {
        // doc: SwiftUI/NavigationBarItem/TitleDisplayMode/automatic
        case automatic
        // doc: SwiftUI/NavigationBarItem/TitleDisplayMode/inline
        case inline
        // doc: SwiftUI/NavigationBarItem/TitleDisplayMode/large
        case large
    }
}

// doc: SwiftUI/DismissAction
@MainActor @preconcurrency public struct DismissAction: Sendable {
    // doc: SwiftUI/DismissAction/callAsFunction()
    @MainActor @preconcurrency public func callAsFunction() { fatalError() }
}

// doc: SwiftUI/RefreshAction
public struct RefreshAction: Sendable {
    // doc: SwiftUI/RefreshAction/callAsFunction()
    public func callAsFunction() async { fatalError() }
}

// doc: SwiftUI/GestureMask
public struct GestureMask: Equatable, Sendable, OptionSet {
    // shim: OptionSet storage (the docs page set has no rawValue page for this type)
    public let rawValue: Int
    // shim: OptionSet requirement
    public init(rawValue: Int) { self.rawValue = rawValue }
    // doc: SwiftUI/GestureMask/all
    public static var all: GestureMask { fatalError() }
    // doc: SwiftUI/GestureMask/gesture
    public static var gesture: GestureMask { fatalError() }
    // doc: SwiftUI/GestureMask/subviews
    public static var subviews: GestureMask { fatalError() }
    // doc: SwiftUI/GestureMask/none
    public static var none: GestureMask { fatalError() }
}

// shim: AccessibilityAttachmentModifier is the ViewModifier behind the accessibility* modifiers (Apple documents it as a plain struct)
extension AccessibilityAttachmentModifier: ViewModifier {
    // shim: modifier plumbing
    public typealias Body = Never
}

// doc: SwiftUI/DefaultGlassEffectShape
public struct DefaultGlassEffectShape: Sendable {
    // doc: SwiftUI/DefaultGlassEffectShape/init()  [iOS 26.0]
    public init() { fatalError() }
}
// shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages
extension DefaultGlassEffectShape: InsettableShape {
    // shim: witness
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: witness
    public func inset(by amount: CGFloat) -> DefaultGlassEffectShape { fatalError() }
}

// doc: SwiftUI/withTransaction(_:_:)
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result { fatalError() }
// doc: SwiftUI/withAnimation(_:_:)
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result { fatalError() }