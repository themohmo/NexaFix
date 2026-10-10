// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/Rectangle
public struct Rectangle: Sendable {
    // doc: SwiftUI/Rectangle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/Rectangle
extension Rectangle: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> Rectangle { fatalError() }
}

// doc: SwiftUI/RoundedRectangle
public struct RoundedRectangle: Sendable {
    // doc: SwiftUI/RoundedRectangle/init(cornerRadius:style:)
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/RoundedRectangle/init(cornerSize:style:)
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/RoundedRectangle/cornerSize
    public var cornerSize: CGSize { get { fatalError() } set { } }
    // doc: SwiftUI/RoundedRectangle/style
    public var style: RoundedCornerStyle { get { fatalError() } set { } }
}
// doc: SwiftUI/RoundedRectangle
extension RoundedRectangle: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> RoundedRectangle { fatalError() }
}

// doc: SwiftUI/Circle
public struct Circle: Sendable {
    // doc: SwiftUI/Circle/init()
    public init() { fatalError() }
}
// doc: SwiftUI/Circle
extension Circle: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> Circle { fatalError() }
}

// doc: SwiftUI/Capsule
public struct Capsule: Sendable {
    // doc: SwiftUI/Capsule/init(style:)
    public init(style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/Capsule/style
    public var style: RoundedCornerStyle { get { fatalError() } set { } }
}
// doc: SwiftUI/Capsule
extension Capsule: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> Capsule { fatalError() }
}

// doc: SwiftUI/Ellipse
public struct Ellipse: Sendable {
    // doc: SwiftUI/Ellipse/init()
    public init() { fatalError() }
}
// doc: SwiftUI/Ellipse
extension Ellipse: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> Ellipse { fatalError() }
}

// doc: SwiftUI/UnevenRoundedRectangle
public struct UnevenRoundedRectangle: Sendable {
    // doc: SwiftUI/UnevenRoundedRectangle/init(cornerRadii:style:)
    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/UnevenRoundedRectangle/init(topLeadingRadius:bottomLeadingRadius:bottomTrailingRadius:topTrailingRadius:style:)
    public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/UnevenRoundedRectangle/cornerRadii
    public var cornerRadii: RectangleCornerRadii { get { fatalError() } set { } }
    // doc: SwiftUI/UnevenRoundedRectangle/style
    public var style: RoundedCornerStyle { get { fatalError() } set { } }
}
// doc: SwiftUI/UnevenRoundedRectangle
extension UnevenRoundedRectangle: InsettableShape {
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path { fatalError() }
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> UnevenRoundedRectangle { fatalError() }
}

// doc: SwiftUI/Path
public struct Path: Equatable, Sendable {
    // doc: SwiftUI/Path/init()
    public init() { fatalError() }
    // doc: SwiftUI/Path/init(_:)
    public init(_ callback: (inout Path) -> ()) { fatalError() }
    // doc: SwiftUI/Path/init(ellipseIn:)
    public init(ellipseIn rect: CGRect) { fatalError() }
    // doc: SwiftUI/Path/init(roundedRect:cornerRadius:style:)
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/Path/init(roundedRect:cornerSize:style:)
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/Path/init(roundedRect:cornerRadii:style:)
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) { fatalError() }
    // doc: SwiftUI/Path/boundingRect
    public var boundingRect: CGRect { fatalError() }
    // doc: SwiftUI/Path/contains(_:eoFill:)
    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool { fatalError() }
    // doc: SwiftUI/Path/currentPoint
    public var currentPoint: CGPoint? { fatalError() }
    // doc: SwiftUI/Path/description
    public var description: String { fatalError() }
    // doc: SwiftUI/Path/isEmpty
    public var isEmpty: Bool { fatalError() }
    // doc: SwiftUI/Path/move(to:)
    public mutating func move(to end: CGPoint) { fatalError() }
    // doc: SwiftUI/Path/addArc(center:radius:startAngle:endAngle:clockwise:transform:)
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addArc(tangent1End:tangent2End:radius:transform:)
    public mutating func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addCurve(to:control1:control2:)
    public mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { fatalError() }
    // doc: SwiftUI/Path/addEllipse(in:transform:)
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addLine(to:)
    public mutating func addLine(to end: CGPoint) { fatalError() }
    // doc: SwiftUI/Path/addLines(_:)
    public mutating func addLines(_ lines: [CGPoint]) { fatalError() }
    // doc: SwiftUI/Path/addPath(_:transform:)
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addQuadCurve(to:control:)
    public mutating func addQuadCurve(to end: CGPoint, control: CGPoint) { fatalError() }
    // doc: SwiftUI/Path/addRect(_:transform:)
    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addRects(_:transform:)
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addRelativeArc(center:radius:startAngle:delta:transform:)
    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/addRoundedRect(in:cornerSize:style:transform:)
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/closeSubpath()
    public mutating func closeSubpath() { fatalError() }
    // doc: SwiftUI/Path/applying(_:)
    public func applying(_ transform: CGAffineTransform) -> Path { fatalError() }
    // doc: SwiftUI/Path/offsetBy(dx:dy:)
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { fatalError() }
    // doc: SwiftUI/Path/trimmedPath(from:to:)
    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path { fatalError() }
    // doc: SwiftUI/Path/intersection(_:eoFill:)
    public func intersection(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/lineIntersection(_:eoFill:)
    public func lineIntersection(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/lineSubtraction(_:eoFill:)
    public func lineSubtraction(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/normalized(eoFill:)
    public func normalized(eoFill: Bool = true) -> Path { fatalError() }
    // doc: SwiftUI/Path/subtracting(_:eoFill:)
    public func subtracting(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/symmetricDifference(_:eoFill:)
    public func symmetricDifference(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/union(_:eoFill:)
    public func union(_ other: Path, eoFill: Bool = false) -> Path { fatalError() }
    // doc: SwiftUI/Path/forEach(_:)
    public func forEach(_ body: (Path.Element) -> Void) { fatalError() }
    // doc: SwiftUI/Path/Element
    public enum Element: Equatable, Sendable {
        // doc: SwiftUI/Path/Element/closeSubpath
        case closeSubpath
        // doc: SwiftUI/Path/Element/curve(to:control1:control2:)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        // doc: SwiftUI/Path/Element/line(to:)
        case line(to: CGPoint)
        // doc: SwiftUI/Path/Element/move(to:)
        case move(to: CGPoint)
        // doc: SwiftUI/Path/Element/quadCurve(to:control:)
        case quadCurve(to: CGPoint, control: CGPoint)
    }
    // doc: SwiftUI/Path/strokedPath(_:)
    public func strokedPath(_ style: StrokeStyle) -> Path { fatalError() }
    // doc: SwiftUI/Path/addRoundedRect(in:cornerRadii:style:transform:)
    public mutating func addRoundedRect(in rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous, transform: CGAffineTransform = .identity) { fatalError() }
    // doc: SwiftUI/Path/init(_:)-87w1j
    public init?(_ string: String) { fatalError() }
    // doc: SwiftUI/Path/init(_:)-912s7
    public init(_ rect: CGRect) { fatalError() }
}
// shim: Apple documents Shape.path(in:) only on the Shape page; this is the witness
extension Path: Shape {
    // shim: see above
    public func path(in rect: CGRect) -> Path { fatalError() }
}

extension Shape where Self == Capsule {
    // doc: SwiftUI/Shape/capsule
    public static var capsule: Capsule { fatalError() }
    // doc: SwiftUI/Shape/capsule(style:)
    public static func capsule(style: RoundedCornerStyle) -> Self { fatalError() }
}
extension Shape where Self == Circle {
    // doc: SwiftUI/Shape/circle
    public static var circle: Circle { fatalError() }
}
extension Shape where Self == Ellipse {
    // doc: SwiftUI/Shape/ellipse
    public static var ellipse: Ellipse { fatalError() }
}
extension Shape where Self == Rectangle {
    // doc: SwiftUI/Shape/rect
    public static var rect: Rectangle { fatalError() }
}
extension Shape where Self == UnevenRoundedRectangle {
    // doc: SwiftUI/Shape/rect(cornerRadii:style:)
    public static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(topLeadingRadius:bottomLeadingRadius:bottomTrailingRadius:topTrailingRadius:style:)
    public static func rect(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) -> Self { fatalError() }
}
extension Shape where Self == RoundedRectangle {
    // doc: SwiftUI/Shape/rect(cornerRadius:style:)
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(cornerSize:style:)
    public static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> Self { fatalError() }
}
extension Shape {
    // doc: SwiftUI/Shape/rect(corners:isUniform:)  [iOS 26.0]
    public static func rect(corners: Edge.Corner.Style, isUniform: Bool = false) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(topLeadingCorner:topTrailingCorner:bottomLeadingCorner:bottomTrailingCorner:)  [iOS 26.0]
    public static func rect(topLeadingCorner: Edge.Corner.Style, topTrailingCorner: Edge.Corner.Style, bottomLeadingCorner: Edge.Corner.Style, bottomTrailingCorner: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformBottomCorners:topLeadingCorner:topTrailingCorner:)  [iOS 26.0]
    public static func rect(uniformBottomCorners: Edge.Corner.Style, topLeadingCorner: Edge.Corner.Style, topTrailingCorner: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformLeadingCorners:topTrailingCorner:bottomTrailingCorner:)  [iOS 26.0]
    public static func rect(uniformLeadingCorners: Edge.Corner.Style, topTrailingCorner: Edge.Corner.Style, bottomTrailingCorner: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformLeadingCorners:uniformTrailingCorners:)  [iOS 26.0]
    public static func rect(uniformLeadingCorners: Edge.Corner.Style, uniformTrailingCorners: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformTopCorners:bottomLeadingCorner:bottomTrailingCorner:)  [iOS 26.0]
    public static func rect(uniformTopCorners: Edge.Corner.Style, bottomLeadingCorner: Edge.Corner.Style, bottomTrailingCorner: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformTopCorners:uniformBottomCorners:)  [iOS 26.0]
    public static func rect(uniformTopCorners: Edge.Corner.Style, uniformBottomCorners: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/rect(uniformTrailingCorners:topLeadingCorner:bottomLeadingCorner:)  [iOS 26.0]
    public static func rect(uniformTrailingCorners: Edge.Corner.Style, topLeadingCorner: Edge.Corner.Style, bottomLeadingCorner: Edge.Corner.Style) -> Self { fatalError() }
    // doc: SwiftUI/Shape/trim(from:to:)
    public nonisolated func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape { self }
    // doc: SwiftUI/Shape/transform(_:)
    public nonisolated func transform(_ transform: CGAffineTransform) -> TransformedShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/size(_:)
    public nonisolated func size(_ size: CGSize) -> some Shape { self }
    // doc: SwiftUI/Shape/size(_:anchor:)  [iOS 18.0]
    public nonisolated func size(_ size: CGSize, anchor: UnitPoint) -> some Shape { self }
    // doc: SwiftUI/Shape/size(width:height:)
    public nonisolated func size(width: CGFloat, height: CGFloat) -> some Shape { self }
    // doc: SwiftUI/Shape/size(width:height:anchor:)  [iOS 18.0]
    public nonisolated func size(width: CGFloat, height: CGFloat, anchor: UnitPoint) -> some Shape { self }
    // doc: SwiftUI/Shape/scale(_:anchor:)
    public nonisolated func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/scale(x:y:anchor:)
    public nonisolated func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/rotation(_:anchor:)
    public nonisolated func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/offset(_:)
    public nonisolated func offset(_ offset: CGPoint) -> OffsetShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/offset(x:y:)
    public nonisolated func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> { fatalError() }
    // doc: SwiftUI/Shape/stroke(_:lineWidth:)
    public nonisolated func stroke<S>(_ content: S, lineWidth: CGFloat = 1) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/Shape/stroke(_:lineWidth:antialiased:)
    public nonisolated func stroke<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/Shape/stroke(lineWidth:)
    public nonisolated func stroke(lineWidth: CGFloat = 1) -> some Shape { self }
    // doc: SwiftUI/Shape/stroke(_:style:)
    public nonisolated func stroke<S>(_ content: S, style: StrokeStyle) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/Shape/stroke(_:style:antialiased:)
    public nonisolated func stroke<S>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/Shape/stroke(style:)
    public nonisolated func stroke(style: StrokeStyle) -> some Shape { self }
    // doc: SwiftUI/Shape/fill(_:style:)
    public nonisolated func fill<S>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/Shape/fill(style:)
    public nonisolated func fill(style: FillStyle = FillStyle()) -> some View { self }
    // doc: SwiftUI/Shape/intersection(_:eoFill:)
    public nonisolated func intersection<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/lineIntersection(_:eoFill:)
    public nonisolated func lineIntersection<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/lineSubtraction(_:eoFill:)
    public nonisolated func lineSubtraction<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/subtracting(_:eoFill:)
    public nonisolated func subtracting<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/symmetricDifference(_:eoFill:)
    public nonisolated func symmetricDifference<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/union(_:eoFill:)
    public nonisolated func union<T>(_ other: T, eoFill: Bool = false) -> some Shape where T : Shape { self }
    // doc: SwiftUI/Shape/fill(_:style:)-5fwbj
    @_disfavoredOverload public nonisolated func fill<S>(_ content: S, style: FillStyle = FillStyle()) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/Shape/offset(_:)-8jkk1
    public nonisolated func offset(_ offset: CGSize) -> OffsetShape<Self> { fatalError() }
}

extension InsettableShape {
    // doc: SwiftUI/InsettableShape/strokeBorder(_:lineWidth:antialiased:)
    public nonisolated func strokeBorder<S>(_ content: S = .foreground, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/InsettableShape/strokeBorder(lineWidth:antialiased:)
    public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { self }
    // doc: SwiftUI/InsettableShape/strokeBorder(_:style:antialiased:)
    public nonisolated func strokeBorder<S>(_ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/InsettableShape/strokeBorder(style:antialiased:)
    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View { self }
    // doc: SwiftUI/InsettableShape/strokeBorder(_:lineWidth:antialiased:)-6rs04
    @_disfavoredOverload public func strokeBorder<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/InsettableShape/strokeBorder(_:style:antialiased:)-3vmk4
    @_disfavoredOverload public func strokeBorder<S>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View where S : ShapeStyle { self }
}

extension ShapeStyle where Self == Color {
    // doc: SwiftUI/ShapeStyle/black
    public static var black: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/blue
    public static var blue: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/brown
    public static var brown: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/clear
    public static var clear: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/cyan
    public static var cyan: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/gray
    public static var gray: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/green
    public static var green: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/indigo
    public static var indigo: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/mint
    public static var mint: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/orange
    public static var orange: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/pink
    public static var pink: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/purple
    public static var purple: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/red
    public static var red: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/teal
    public static var teal: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/white
    public static var white: Color { fatalError() }
    // doc: SwiftUI/ShapeStyle/yellow
    public static var yellow: Color { fatalError() }
}
extension ShapeStyle where Self == AngularGradient {
    // doc: SwiftUI/ShapeStyle/angularGradient(_:center:startAngle:endAngle:)
    public static func angularGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startAngle: Angle, endAngle: Angle) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/angularGradient(colors:center:startAngle:endAngle:)
    public static func angularGradient(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/angularGradient(stops:center:startAngle:endAngle:)
    public static func angularGradient(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/conicGradient(_:center:angle:)
    public static func conicGradient(_ gradient: AnyGradient, center: UnitPoint = .center, angle: Angle = .zero) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/conicGradient(colors:center:angle:)
    public static func conicGradient(colors: [Color], center: UnitPoint, angle: Angle = .zero) -> AngularGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/conicGradient(stops:center:angle:)
    public static func conicGradient(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) -> AngularGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/conicGradient(_:center:angle:)-e0rd
    public static func conicGradient(_ gradient: Gradient, center: UnitPoint, angle: Angle = .zero) -> AngularGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/angularGradient(_:center:startAngle:endAngle:)-378tu
    public static func angularGradient(_ gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient { fatalError() }
}
extension ShapeStyle where Self == EllipticalGradient {
    // doc: SwiftUI/ShapeStyle/ellipticalGradient(_:center:startRadiusFraction:endRadiusFraction:)
    public static func ellipticalGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/ellipticalGradient(colors:center:startRadiusFraction:endRadiusFraction:)
    public static func ellipticalGradient(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/ellipticalGradient(stops:center:startRadiusFraction:endRadiusFraction:)
    public static func ellipticalGradient(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/ellipticalGradient(_:center:startRadiusFraction:endRadiusFraction:)-fmox
    public static func ellipticalGradient(_ gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient { fatalError() }
}
extension ShapeStyle where Self == LinearGradient {
    // doc: SwiftUI/ShapeStyle/linearGradient(_:startPoint:endPoint:)
    public static func linearGradient(_ gradient: AnyGradient, startPoint: UnitPoint, endPoint: UnitPoint) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/linearGradient(colors:startPoint:endPoint:)
    public static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/linearGradient(stops:startPoint:endPoint:)
    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/linearGradient(_:startPoint:endPoint:)-753nc
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient { fatalError() }
}
extension ShapeStyle where Self == RadialGradient {
    // doc: SwiftUI/ShapeStyle/radialGradient(_:center:startRadius:endRadius:)
    public static func radialGradient(_ gradient: AnyGradient, center: UnitPoint = .center, startRadius: CGFloat = 0, endRadius: CGFloat) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/radialGradient(colors:center:startRadius:endRadius:)
    public static func radialGradient(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/radialGradient(stops:center:startRadius:endRadius:)
    public static func radialGradient(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient { fatalError() }
    // doc: SwiftUI/ShapeStyle/radialGradient(_:center:startRadius:endRadius:)-49kel
    public static func radialGradient(_ gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient { fatalError() }
}
extension ShapeStyle where Self == Material {
    // doc: SwiftUI/ShapeStyle/ultraThinMaterial
    public static var ultraThinMaterial: Material { fatalError() }
    // doc: SwiftUI/ShapeStyle/thinMaterial
    public static var thinMaterial: Material { fatalError() }
    // doc: SwiftUI/ShapeStyle/regularMaterial
    public static var regularMaterial: Material { fatalError() }
    // doc: SwiftUI/ShapeStyle/thickMaterial
    public static var thickMaterial: Material { fatalError() }
    // doc: SwiftUI/ShapeStyle/ultraThickMaterial
    public static var ultraThickMaterial: Material { fatalError() }
    // doc: SwiftUI/ShapeStyle/bar
    public static var bar: Material { fatalError() }
}
extension ShapeStyle {
    // doc: SwiftUI/ShapeStyle/secondary-swift.property
    public var secondary: some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/tertiary-swift.property
    public var tertiary: some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/quaternary-swift.property
    public var quaternary: some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/quinary-swift.property
    public var quinary: some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/blendMode(_:)-swift.method
    public func blendMode(_ mode: BlendMode) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/opacity(_:)-swift.method
    public func opacity(_ opacity: Double) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/shadow(_:)-swift.method
    public func shadow(_ style: ShadowStyle) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/in(_:)
    public func `in`(_ rect: CGRect) -> some ShapeStyle { fatalError() }
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    // doc: SwiftUI/ShapeStyle/primary
    public static var primary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/secondary-swift.type.property
    public static var secondary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/tertiary-swift.type.property
    public static var tertiary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/quaternary-swift.type.property
    public static var quaternary: HierarchicalShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/quinary-swift.type.property
    public static var quinary: HierarchicalShapeStyle { fatalError() }
}
extension ShapeStyle where Self == ForegroundStyle {
    // doc: SwiftUI/ShapeStyle/foreground
    public static var foreground: ForegroundStyle { fatalError() }
}
extension ShapeStyle where Self == BackgroundStyle {
    // doc: SwiftUI/ShapeStyle/background
    public static var background: BackgroundStyle { fatalError() }
}
extension ShapeStyle where Self == TintShapeStyle {
    // doc: SwiftUI/ShapeStyle/tint
    public static var tint: TintShapeStyle { fatalError() }
}
extension ShapeStyle where Self == AnyShapeStyle {
    // doc: SwiftUI/ShapeStyle/blendMode(_:)-swift.type.method
    public static func blendMode(_ mode: BlendMode) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/opacity(_:)-swift.type.method
    public static func opacity(_ opacity: Double) -> some ShapeStyle { fatalError() }
    // doc: SwiftUI/ShapeStyle/shadow(_:)-swift.type.method
    public static func shadow(_ style: ShadowStyle) -> some ShapeStyle { fatalError() }
}
extension ShapeStyle where Self: View, Body == _ShapeView<Rectangle, Self> {
    // doc: SwiftUI/ShapeStyle/body
    public var body: _ShapeView<Rectangle, Self> { fatalError() }
}
extension ShapeStyle where Resolved == Never {
    // doc: SwiftUI/ShapeStyle/resolve(in:)-6feyg
    public func resolve(in environment: EnvironmentValues) -> Never { fatalError() }
}
