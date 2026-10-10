// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/SpatialTapGesture
public struct SpatialTapGesture {
    // doc: SwiftUI/SpatialTapGesture/coordinateSpace
    public var coordinateSpace: CoordinateSpace { get { fatalError() } set { } }
    // doc: SwiftUI/SpatialTapGesture/count
    public var count: Int { get { fatalError() } set { } }
    // doc: SwiftUI/SpatialTapGesture/Value
    public struct Value: Equatable, Sendable {
        // doc: SwiftUI/SpatialTapGesture/Value/location
        public var location: CGPoint { get { fatalError() } set { } }
    }
    // doc: SwiftUI/SpatialTapGesture/init(count:coordinateSpace:)-1b85g
    public nonisolated init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension SpatialTapGesture: _PrimitiveGesture {}

extension Gesture where Value: Equatable {
    // doc: SwiftUI/Gesture/onChanged(_:)
    public nonisolated func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> { fatalError() }
}
extension Gesture {
    // doc: SwiftUI/Gesture/onEnded(_:)
    public nonisolated func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> { fatalError() }
}

// doc: SwiftUI/ButtonStyleConfiguration
public struct ButtonStyleConfiguration {
    // doc: SwiftUI/ButtonStyleConfiguration/label-swift.property
    public var label: ButtonStyleConfiguration.Label { fatalError() }
    // doc: SwiftUI/ButtonStyleConfiguration/Label-swift.struct
    @MainActor @preconcurrency public struct Label {
    }
    // doc: SwiftUI/ButtonStyleConfiguration/isPressed
    public var isPressed: Bool { fatalError() }
    // doc: SwiftUI/ButtonStyleConfiguration/role
    public var role: ButtonRole? { fatalError() }
}
// shim: the label of a button style is a View (Apple: ButtonStyleConfiguration.Label)
extension ButtonStyleConfiguration.Label: _PrimitiveView {}

// doc: SwiftUI/ToolbarItem
public struct ToolbarItem<ID, Content> where Content : View {
}
extension ToolbarItem where ID == (), Content: View {
    // doc: SwiftUI/ToolbarItem/init(placement:content:)
    public nonisolated init(placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) { fatalError() }
}
extension ToolbarItem where ID == String, Content: View {
    // doc: SwiftUI/ToolbarItem/init(id:placement:content:)
    public nonisolated init(id: String, placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/ToolbarItem/init(id:placement:showsByDefault:content:)
    public nonisolated init(id: String, placement: ToolbarItemPlacement = .automatic, showsByDefault: Bool, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ToolbarItem: _PrimitiveToolbarContent where Content: View {}

// doc: SwiftUI/ToolbarItemGroup
public struct ToolbarItemGroup<Content> where Content : View {
    // doc: SwiftUI/ToolbarItemGroup/init(placement:content:)
    public nonisolated init(placement: ToolbarItemPlacement = .automatic, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/LabeledToolbarItemGroupContent
    public struct LabeledToolbarItemGroupContent<Content, Label> where Content : View, Label : View {
    }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ToolbarItemGroup: _PrimitiveToolbarContent where Content: View {}

// doc: SwiftUI/AnyLayout
public struct AnyLayout: Sendable {
    // doc: SwiftUI/AnyLayout/init(_:)
    public init<L>(_ layout: L) where L : Layout { fatalError() }
}
// doc: SwiftUI/AnyLayout
extension AnyLayout: Layout {
    // shim: Layout witnesses
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize { fatalError() }
    // shim: Layout witnesses
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) { fatalError() }
}

// doc: SwiftUI/HStackLayout
public struct HStackLayout: Sendable {
    // doc: SwiftUI/HStackLayout/init(alignment:spacing:)
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) { fatalError() }
    // doc: SwiftUI/HStackLayout/alignment
    public var alignment: VerticalAlignment { get { fatalError() } set { } }
    // doc: SwiftUI/HStackLayout/spacing
    public var spacing: CGFloat? = nil
}
// doc: SwiftUI/HStackLayout
extension HStackLayout: Layout {
    // shim: Layout witnesses
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize { fatalError() }
    // shim: Layout witnesses
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) { fatalError() }
}

// doc: SwiftUI/VStackLayout
public struct VStackLayout: Sendable {
    // doc: SwiftUI/VStackLayout/init(alignment:spacing:)
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) { fatalError() }
    // doc: SwiftUI/VStackLayout/alignment
    public var alignment: HorizontalAlignment { get { fatalError() } set { } }
    // doc: SwiftUI/VStackLayout/spacing
    public var spacing: CGFloat? = nil
}
// doc: SwiftUI/VStackLayout
extension VStackLayout: Layout {
    // shim: Layout witnesses
    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize { fatalError() }
    // shim: Layout witnesses
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) { fatalError() }
}

extension Layout {
    // doc: SwiftUI/Layout/explicitAlignment(of:in:proposal:subviews:cache:)
    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? { fatalError() }
    // doc: SwiftUI/Layout/spacing(subviews:cache:)
    public func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing { fatalError() }
    // doc: SwiftUI/Layout/layoutProperties
    public static var layoutProperties: LayoutProperties { fatalError() }
    // doc: SwiftUI/Layout/makeCache(subviews:)
    public func makeCache(subviews: Self.Subviews) -> Self.Cache { fatalError() }
    // doc: SwiftUI/Layout/updateCache(_:subviews:)
    public func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews) { fatalError() }
    // doc: SwiftUI/Layout/callAsFunction(_:)
    public func callAsFunction<V>(@ContentBuilder _ content: () -> V) -> some View where V : View { fatalError() }
    // doc: SwiftUI/Layout/explicitAlignment(of:in:proposal:subviews:cache:)-755bz
    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? { fatalError() }
}
extension Layout where Cache == () {
    // doc: SwiftUI/Layout/makeCache(subviews:)-4fu1k
    public func makeCache(subviews: Self.Subviews) -> Self.Cache { fatalError() }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    // doc: SwiftUI/TimelineSchedule/animation
    public static var animation: AnimationTimelineSchedule { fatalError() }
    // doc: SwiftUI/TimelineSchedule/animation(minimumInterval:paused:)
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule { fatalError() }
}
extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    // doc: SwiftUI/TimelineSchedule/everyMinute
    public static var everyMinute: EveryMinuteTimelineSchedule { fatalError() }
}
extension TimelineSchedule {
    // doc: SwiftUI/TimelineSchedule/explicit(_:)
    public static func explicit<S>(_ dates: S) -> ExplicitTimelineSchedule<S> where Self == ExplicitTimelineSchedule<S>, S : Sequence, S.Element == Date { fatalError() }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    // doc: SwiftUI/TimelineSchedule/periodic(from:by:)
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule { fatalError() }
}

// doc: SwiftUI/AnimationTimelineSchedule
public struct AnimationTimelineSchedule: Sendable {
    // doc: SwiftUI/AnimationTimelineSchedule/init(minimumInterval:paused:)
    public init(minimumInterval: Double? = nil, paused: Bool = false) { fatalError() }
}
// doc: SwiftUI/AnimationTimelineSchedule
extension AnimationTimelineSchedule: TimelineSchedule {
    // shim: witnesses; Apple documents entries(from:mode:) only on the TimelineSchedule page
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { fatalError() }
}

// doc: SwiftUI/EveryMinuteTimelineSchedule
public struct EveryMinuteTimelineSchedule: Sendable {
    // doc: SwiftUI/EveryMinuteTimelineSchedule/init()
    public init() { fatalError() }
}
// doc: SwiftUI/EveryMinuteTimelineSchedule
extension EveryMinuteTimelineSchedule: TimelineSchedule {
    // shim: witnesses; Apple documents entries(from:mode:) only on the TimelineSchedule page
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { fatalError() }
}

// doc: SwiftUI/PeriodicTimelineSchedule
public struct PeriodicTimelineSchedule: Sendable {
    // doc: SwiftUI/PeriodicTimelineSchedule/init(from:by:)
    public init(from startDate: Date, by interval: TimeInterval) { fatalError() }
}
// doc: SwiftUI/PeriodicTimelineSchedule
extension PeriodicTimelineSchedule: TimelineSchedule {
    // shim: witnesses; Apple documents entries(from:mode:) only on the TimelineSchedule page
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { fatalError() }
}

// doc: SwiftUI/ExplicitTimelineSchedule
public struct ExplicitTimelineSchedule<Entries> where Entries : Sequence, Entries.Element == Date {
    // doc: SwiftUI/ExplicitTimelineSchedule/init(_:)
    public init(_ dates: Entries) { fatalError() }
}
// doc: SwiftUI/ExplicitTimelineSchedule
extension ExplicitTimelineSchedule: TimelineSchedule {
    // shim: witnesses; Apple documents entries(from:mode:) only on the TimelineSchedule page
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] { fatalError() }
}
