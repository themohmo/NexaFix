// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

// doc: SwiftUI/Text
public struct Text: Equatable, Sendable {
    // doc: SwiftUI/Text/init(_:tableName:bundle:comment:)
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) { fatalError() }
    // doc: SwiftUI/Text/init(_:)
    public init(_ attributedContent: AttributedString) { fatalError() }
    // doc: SwiftUI/Text/init(verbatim:)
    public init(verbatim content: String) { fatalError() }
    // doc: SwiftUI/Text/init(_:style:)
    public init(_ date: Date, style: Text.DateStyle) { fatalError() }
    // doc: SwiftUI/Text/init(_:format:)  [iOS 18.0]
    public init<F>(_ input: F.FormatInput, format: F) where F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == AttributedString { fatalError() }
    // doc: SwiftUI/Text/init(_:formatter:)
    public init<Subject>(_ subject: Subject, formatter: Formatter) where Subject : NSObject { fatalError() }
    // doc: SwiftUI/Text/init(timerInterval:pauseTime:countsDown:showsHours:)
    public init(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true) { fatalError() }
    // doc: SwiftUI/Text/font(_:)
    public nonisolated func font(_ font: Font?) -> Text { fatalError() }
    // doc: SwiftUI/Text/fontWeight(_:)
    public nonisolated func fontWeight(_ weight: Font.Weight?) -> Text { fatalError() }
    // doc: SwiftUI/Text/fontDesign(_:)
    public nonisolated func fontDesign(_ design: Font.Design?) -> Text { fatalError() }
    // doc: SwiftUI/Text/fontWidth(_:)
    public nonisolated func fontWidth(_ width: Font.Width?) -> Text { fatalError() }
    // doc: SwiftUI/Text/foregroundStyle(_:)
    public nonisolated func foregroundStyle<S>(_ style: S) -> Text where S : ShapeStyle { fatalError() }
    // doc: SwiftUI/Text/bold()
    public nonisolated func bold() -> Text { fatalError() }
    // doc: SwiftUI/Text/bold(_:)
    public nonisolated func bold(_ isActive: Bool) -> Text { fatalError() }
    // doc: SwiftUI/Text/italic()
    public nonisolated func italic() -> Text { fatalError() }
    // doc: SwiftUI/Text/italic(_:)
    public nonisolated func italic(_ isActive: Bool) -> Text { fatalError() }
    // doc: SwiftUI/Text/strikethrough(_:color:)
    public nonisolated func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text { fatalError() }
    // doc: SwiftUI/Text/strikethrough(_:pattern:color:)
    public nonisolated func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text { fatalError() }
    // doc: SwiftUI/Text/underline(_:color:)
    public nonisolated func underline(_ isActive: Bool = true, color: Color? = nil) -> Text { fatalError() }
    // doc: SwiftUI/Text/underline(_:pattern:color:)
    public nonisolated func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern, color: Color? = nil) -> Text { fatalError() }
    // doc: SwiftUI/Text/monospaced(_:)
    public nonisolated func monospaced(_ isActive: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/monospacedDigit()
    public nonisolated func monospacedDigit() -> Text { fatalError() }
    // doc: SwiftUI/Text/kerning(_:)
    public nonisolated func kerning(_ kerning: CGFloat) -> Text { fatalError() }
    // doc: SwiftUI/Text/tracking(_:)
    public nonisolated func tracking(_ tracking: CGFloat) -> Text { fatalError() }
    // doc: SwiftUI/Text/baselineOffset(_:)
    public nonisolated func baselineOffset(_ baselineOffset: CGFloat) -> Text { fatalError() }
    // doc: SwiftUI/Text/Case
    public enum Case: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/Case/lowercase
        case lowercase
        // doc: SwiftUI/Text/Case/uppercase
        case uppercase
    }
    // doc: SwiftUI/Text/DateStyle
    public struct DateStyle: Equatable, Sendable {
        // doc: SwiftUI/Text/DateStyle/date
        public static var date: Text.DateStyle { fatalError() }
        // doc: SwiftUI/Text/DateStyle/offset
        public static var offset: Text.DateStyle { fatalError() }
        // doc: SwiftUI/Text/DateStyle/relative
        public static var relative: Text.DateStyle { fatalError() }
        // doc: SwiftUI/Text/DateStyle/time
        public static var time: Text.DateStyle { fatalError() }
        // doc: SwiftUI/Text/DateStyle/timer
        public static var timer: Text.DateStyle { fatalError() }
    }
    // doc: SwiftUI/Text/LineStyle
    public struct LineStyle: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/LineStyle/single
        public static var single: Text.LineStyle { fatalError() }
        // doc: SwiftUI/Text/LineStyle/init(pattern:color:)
        public init(pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) { fatalError() }
        // doc: SwiftUI/Text/LineStyle/Pattern
        public struct Pattern: Sendable {
            // doc: SwiftUI/Text/LineStyle/Pattern/solid
            public static var solid: Text.LineStyle.Pattern { fatalError() }
            // doc: SwiftUI/Text/LineStyle/Pattern/dot
            public static var dot: Text.LineStyle.Pattern { fatalError() }
            // doc: SwiftUI/Text/LineStyle/Pattern/dash
            public static var dash: Text.LineStyle.Pattern { fatalError() }
            // doc: SwiftUI/Text/LineStyle/Pattern/dashDot
            public static var dashDot: Text.LineStyle.Pattern { fatalError() }
            // doc: SwiftUI/Text/LineStyle/Pattern/dashDotDot
            public static var dashDotDot: Text.LineStyle.Pattern { fatalError() }
        }
    }
    // doc: SwiftUI/Text/textScale(_:isEnabled:)
    public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/Scale
    public struct Scale: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/Scale/default
        public static var `default`: Text.Scale { fatalError() }
        // doc: SwiftUI/Text/Scale/secondary
        public static var secondary: Text.Scale { fatalError() }
    }
    // doc: SwiftUI/Text/TruncationMode
    public enum TruncationMode: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/TruncationMode/head
        case head
        // doc: SwiftUI/Text/TruncationMode/middle
        case middle
        // doc: SwiftUI/Text/TruncationMode/tail
        case tail
    }
    // doc: SwiftUI/Text/typesettingLanguage(_:isEnabled:)
    public func typesettingLanguage(_ language: Locale.Language, isEnabled: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/speechAdjustedPitch(_:)
    public func speechAdjustedPitch(_ value: Double) -> Text { fatalError() }
    // doc: SwiftUI/Text/speechAlwaysIncludesPunctuation(_:)
    public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/speechAnnouncementsQueued(_:)
    public func speechAnnouncementsQueued(_ value: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/speechSpellsOutCharacters(_:)
    public func speechSpellsOutCharacters(_ value: Bool = true) -> Text { fatalError() }
    // doc: SwiftUI/Text/accessibilityHeading(_:)
    public nonisolated func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> Text { fatalError() }
    // doc: SwiftUI/Text/accessibilityTextContentType(_:)
    public nonisolated func accessibilityTextContentType(_ value: AccessibilityTextContentType) -> Text { fatalError() }
    // doc: SwiftUI/Text/+(_:_:)
    public static func + (lhs: Text, rhs: Text) -> Text { fatalError() }
    // doc: SwiftUI/Text/foregroundColor(_:)
    public nonisolated func foregroundColor(_ color: Color?) -> Text { fatalError() }
    // doc: SwiftUI/Text/AlignmentStrategy
    public struct AlignmentStrategy: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/AlignmentStrategy/default  [iOS 26.0]
        public static var `default`: Text.AlignmentStrategy { fatalError() }
        // doc: SwiftUI/Text/AlignmentStrategy/layoutBased  [iOS 26.0]
        public static var layoutBased: Text.AlignmentStrategy { fatalError() }
        // doc: SwiftUI/Text/AlignmentStrategy/writingDirectionBased  [iOS 26.0]
        public static var writingDirectionBased: Text.AlignmentStrategy { fatalError() }
    }
    // doc: SwiftUI/Text/WritingDirectionStrategy
    public struct WritingDirectionStrategy: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Text/WritingDirectionStrategy/contentBased  [iOS 26.0]
        public static var contentBased: Text.WritingDirectionStrategy { fatalError() }
        // doc: SwiftUI/Text/WritingDirectionStrategy/default  [iOS 26.0]
        public static var `default`: Text.WritingDirectionStrategy { fatalError() }
        // doc: SwiftUI/Text/WritingDirectionStrategy/layoutBased  [iOS 26.0]
        public static var layoutBased: Text.WritingDirectionStrategy { fatalError() }
    }
    // doc: SwiftUI/Text/init(_:)-4k7ab
    public init(_ dates: ClosedRange<Date>) { fatalError() }
    // doc: SwiftUI/Text/init(_:)-60ax7
    public init(_ image: Image) { fatalError() }
    // doc: SwiftUI/Text/accessibilityLabel(_:)-9hhwt
    public nonisolated func accessibilityLabel(_ label: Text) -> Text { fatalError() }
    // doc: SwiftUI/Text/init(_:formatter:)-2he2c
    public init<Subject>(_ subject: Subject, formatter: Formatter) where Subject : ReferenceConvertible { fatalError() }
    // doc: SwiftUI/Text/accessibilityLabel(_:)-9afwr
    public nonisolated func accessibilityLabel(_ labelKey: LocalizedStringKey) -> Text { fatalError() }
    // doc: SwiftUI/Text/init(_:format:)-3mxzg
    public init<F>(_ input: F.FormatInput, format: F) where F : FormatStyle, F.FormatInput : Equatable, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Text/init(_:)-9d1g4
    public init<S>(_ content: S) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Text/init(_:)-56n81
    public init(_ interval: DateInterval) { fatalError() }
    // doc: SwiftUI/Text/accessibilityLabel(_:)-6l0ln
    public nonisolated func accessibilityLabel<S>(_ label: S) -> Text where S : StringProtocol { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Text: _PrimitiveView {}

// doc: SwiftUI/Image
public struct Image: Equatable, Sendable {
    // doc: SwiftUI/Image/init(_:bundle:)
    public init(_ name: String, bundle: Bundle? = nil) { fatalError() }
    // doc: SwiftUI/Image/init(_:variableValue:bundle:)
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) { fatalError() }
    // doc: SwiftUI/Image/init(_:bundle:label:)
    public init(_ name: String, bundle: Bundle? = nil, label: Text) { fatalError() }
    // doc: SwiftUI/Image/init(_:variableValue:bundle:label:)
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil, label: Text) { fatalError() }
    // doc: SwiftUI/Image/init(decorative:bundle:)
    public init(decorative name: String, bundle: Bundle? = nil) { fatalError() }
    // doc: SwiftUI/Image/init(decorative:variableValue:bundle:)
    public init(decorative name: String, variableValue: Double?, bundle: Bundle? = nil) { fatalError() }
    // doc: SwiftUI/Image/init(systemName:)
    public init(systemName: String) { fatalError() }
    // doc: SwiftUI/Image/init(systemName:variableValue:)
    public init(systemName: String, variableValue: Double?) { fatalError() }
    // doc: SwiftUI/Image/init(size:label:opaque:colorMode:renderer:)
    public init(size: CGSize, label: Text? = nil, opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, renderer: @escaping (inout GraphicsContext) -> Void) { fatalError() }
    // doc: SwiftUI/Image/resizable(capInsets:resizingMode:)
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image { fatalError() }
    // doc: SwiftUI/Image/antialiased(_:)
    public func antialiased(_ isAntialiased: Bool) -> Image { fatalError() }
    // doc: SwiftUI/Image/symbolRenderingMode(_:)
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image { fatalError() }
    // doc: SwiftUI/Image/renderingMode(_:)
    public func renderingMode(_ renderingMode: Image.TemplateRenderingMode?) -> Image { fatalError() }
    // doc: SwiftUI/Image/interpolation(_:)
    public func interpolation(_ interpolation: Image.Interpolation) -> Image { fatalError() }
    // doc: SwiftUI/Image/TemplateRenderingMode
    public enum TemplateRenderingMode: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Image/TemplateRenderingMode/original
        case original
        // doc: SwiftUI/Image/TemplateRenderingMode/template
        case template
    }
    // doc: SwiftUI/Image/Interpolation
    public enum Interpolation: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Image/Interpolation/high
        case high
        // doc: SwiftUI/Image/Interpolation/low
        case low
        // doc: SwiftUI/Image/Interpolation/medium
        case medium
        // doc: SwiftUI/Image/Interpolation/none
        case none
    }
    // doc: SwiftUI/Image/allowedDynamicRange(_:)
    public func allowedDynamicRange(_ range: Image.DynamicRange?) -> Image { fatalError() }
    // doc: SwiftUI/EnvironmentValues/allowedDynamicRange
    public var allowedDynamicRange: Image.DynamicRange? { get { fatalError() } set { } }
    // doc: SwiftUI/Image/DynamicRange
    public struct DynamicRange: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Image/DynamicRange/standard
        public static var standard: Image.DynamicRange { fatalError() }
        // doc: SwiftUI/Image/DynamicRange/high
        public static var high: Image.DynamicRange { fatalError() }
        // doc: SwiftUI/Image/DynamicRange/constrainedHigh
        public static var constrainedHigh: Image.DynamicRange { fatalError() }
    }
    // doc: SwiftUI/Image/Orientation
    public enum Orientation: Equatable, Hashable, Sendable, CaseIterable {
        // doc: SwiftUI/Image/Orientation/up
        case up
        // doc: SwiftUI/Image/Orientation/down
        case down
        // doc: SwiftUI/Image/Orientation/left
        case left
        // doc: SwiftUI/Image/Orientation/right
        case right
        // doc: SwiftUI/Image/Orientation/upMirrored
        case upMirrored
        // doc: SwiftUI/Image/Orientation/downMirrored
        case downMirrored
        // doc: SwiftUI/Image/Orientation/leftMirrored
        case leftMirrored
        // doc: SwiftUI/Image/Orientation/rightMirrored
        case rightMirrored
    }
    // doc: SwiftUI/Image/ResizingMode
    public enum ResizingMode: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Image/ResizingMode/stretch
        case stretch
        // doc: SwiftUI/Image/ResizingMode/tile
        case tile
    }
    // doc: SwiftUI/Image/Scale
    public enum Scale: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Image/Scale/small
        case small
        // doc: SwiftUI/Image/Scale/medium
        case medium
        // doc: SwiftUI/Image/Scale/large
        case large
    }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Image: _PrimitiveView {}

// doc: SwiftUI/Button
public struct Button<Label> where Label : View {
    // doc: SwiftUI/Button/init(action:label:)
    @preconcurrency public nonisolated init(action: @escaping @MainActor () -> Void, @ContentBuilder label: () -> Label) { fatalError() }
}
extension Button where Label == SwiftUI.Label<Text, Image> {
    // doc: SwiftUI/Button/init(_:systemImage:action:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) { fatalError() }
    // doc: SwiftUI/Button/init(_:systemImage:role:action:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) { fatalError() }
    // doc: SwiftUI/Button/init(_:systemImage:role:action:)-32hud
    public nonisolated init<S>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Button/init(_:systemImage:action:)-23bvz
    public nonisolated init<S>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) where S : StringProtocol { fatalError() }
}
extension Button where Label: View {
    // doc: SwiftUI/Button/init(role:action:label:)
    @preconcurrency public nonisolated init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ContentBuilder label: () -> Label) { fatalError() }
}
extension Button where Label == Text {
    // doc: SwiftUI/Button/init(_:action:)-1asy
    @preconcurrency public nonisolated init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) { fatalError() }
    // doc: SwiftUI/Button/init(_:role:action:)-93ek6
    @preconcurrency public nonisolated init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) { fatalError() }
    // doc: SwiftUI/Button/init(_:role:action:)-8y5yk
    @preconcurrency public nonisolated init<S>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Button/init(_:action:)-lpm7
    @preconcurrency public nonisolated init<S>(_ title: S, action: @escaping @MainActor () -> Void) where S : StringProtocol { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Button: _PrimitiveView {}

// doc: SwiftUI/Label
public struct Label<Title, Icon> where Title : View, Icon : View {
    // doc: SwiftUI/Label/init(title:icon:)
    public nonisolated init(@ContentBuilder title: () -> Title, @ContentBuilder icon: () -> Icon) { fatalError() }
    // doc: SwiftUI/View/labelIconToTitleSpacing(_:)  [iOS 26.0]
    public nonisolated func labelIconToTitleSpacing(_ value: CGFloat) -> some View { fatalError() }
    // doc: SwiftUI/View/labelReservedIconWidth(_:)  [iOS 26.0]
    public nonisolated func labelReservedIconWidth(_ value: CGFloat) -> some View { fatalError() }
}
extension Label where Title == Text, Icon == Image {
    // doc: SwiftUI/Label/init(_:image:)-73eec
    public nonisolated init(_ titleKey: LocalizedStringKey, image name: String) { fatalError() }
    // doc: SwiftUI/Label/init(_:image:)-6zbvg
    public nonisolated init<S>(_ title: S, image name: String) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Label/init(_:systemImage:)-2veqt
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage name: String) { fatalError() }
    // doc: SwiftUI/Label/init(_:systemImage:)-2z97t
    public nonisolated init<S>(_ title: S, systemImage name: String) where S : StringProtocol { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Label: _PrimitiveView {}

// doc: SwiftUI/Toggle
public struct Toggle<Label> where Label : View {
    // doc: SwiftUI/Toggle/init(isOn:label:)
    public nonisolated init(isOn: Binding<Bool>, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/Toggle/init(sources:isOn:label:)
    public nonisolated init<C>(sources: C, isOn: KeyPath<C.Element, Binding<Bool>>, @ContentBuilder label: () -> Label) where C : RandomAccessCollection { fatalError() }
}
extension Toggle where Label == SwiftUI.Label<Text, Image> {
    // doc: SwiftUI/Toggle/init(_:systemImage:isOn:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) { fatalError() }
    // doc: SwiftUI/Toggle/init(_:systemImage:sources:isOn:)
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, systemImage: String, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) where C : RandomAccessCollection { fatalError() }
    // doc: SwiftUI/Toggle/init(_:systemImage:isOn:)-864oj
    public nonisolated init<S>(_ title: S, systemImage: String, isOn: Binding<Bool>) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Toggle/init(_:systemImage:sources:isOn:)-9gjf
    public nonisolated init<S, C>(_ title: S, systemImage: String, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) where S : StringProtocol, C : RandomAccessCollection { fatalError() }
}
extension Toggle where Label == Text {
    // doc: SwiftUI/Toggle/init(_:isOn:)-8qx3l
    public nonisolated init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) { fatalError() }
    // doc: SwiftUI/Toggle/init(_:isOn:)-2qurm
    public nonisolated init<S>(_ title: S, isOn: Binding<Bool>) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Toggle/init(_:sources:isOn:)-39rkx
    public nonisolated init<S, C>(_ title: S, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) where S : StringProtocol, C : RandomAccessCollection { fatalError() }
    // doc: SwiftUI/Toggle/init(_:sources:isOn:)-17gec
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) where C : RandomAccessCollection { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Toggle: _PrimitiveView {}

// doc: SwiftUI/Picker
public struct Picker<Label, SelectionValue, Content> where Label : View, SelectionValue : Hashable, Content : View {
}
extension Picker where Label: View, SelectionValue: Hashable, Content: View {
    // doc: SwiftUI/Picker/init(selection:content:label:)
    public nonisolated init(selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/Picker/init(sources:selection:content:label:)
    public nonisolated init<C>(sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) where C : RandomAccessCollection { fatalError() }
    // doc: SwiftUI/Picker/init(selection:label:content:)
    public nonisolated init(selection: Binding<SelectionValue>, label: Label, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Picker/init(selection:content:label:currentValueLabel:)  [iOS 18.0]
    public nonisolated init(selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label, @ContentBuilder currentValueLabel: () -> some View) { fatalError() }
    // doc: SwiftUI/Picker/init(sources:selection:content:label:currentValueLabel:)  [iOS 18.0]
    public nonisolated init<C>(sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label, @ContentBuilder currentValueLabel: () -> some View) where C : RandomAccessCollection { fatalError() }
}
extension Picker where Label == SwiftUI.Label<Text, Image>, SelectionValue: Hashable, Content: View {
    // doc: SwiftUI/Picker/init(_:systemImage:selection:content:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:sources:selection:content:)
    public nonisolated init<C, S>(_ title: S, systemImage: String, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content) where C : RandomAccessCollection, S : StringProtocol, C.Element == Binding<SelectionValue> { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:selection:content:currentValueLabel:)  [iOS 18.0]
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:sources:selection:content:currentValueLabel:)  [iOS 18.0]
    public nonisolated init<C, S>(_ title: S, systemImage: String, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where C : RandomAccessCollection, S : StringProtocol, C.Element == Binding<SelectionValue> { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:selection:content:)-4uaqe
    public nonisolated init<S>(_ title: S, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:selection:content:currentValueLabel:)-46wgz  [iOS 18.0]
    public nonisolated init<S>(_ title: S, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:sources:selection:content:)-cahh
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, systemImage: String, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content) where C : RandomAccessCollection, C.Element == Binding<SelectionValue> { fatalError() }
    // doc: SwiftUI/Picker/init(_:systemImage:sources:selection:content:currentValueLabel:)-ikai  [iOS 18.0]
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, systemImage: String, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where C : RandomAccessCollection, C.Element == Binding<SelectionValue> { fatalError() }
}
extension Picker where Label == Text, SelectionValue: Hashable, Content: View {
    // doc: SwiftUI/Picker/init(_:selection:content:currentValueLabel:)-53raj  [iOS 18.0]
    public nonisolated init<S>(_ title: S, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:sources:selection:content:currentValueLabel:)-9crbh  [iOS 18.0]
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where C : RandomAccessCollection { fatalError() }
    // doc: SwiftUI/Picker/init(_:selection:content:)-5njtq
    public nonisolated init<S>(_ title: S, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:sources:selection:content:)-6e1x
    public nonisolated init<C>(_ titleKey: LocalizedStringKey, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content) where C : RandomAccessCollection { fatalError() }
    // doc: SwiftUI/Picker/init(_:sources:selection:content:)-7ng1o
    public nonisolated init<C, S>(_ title: S, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content) where C : RandomAccessCollection, S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:sources:selection:content:currentValueLabel:)-1drec  [iOS 18.0]
    public nonisolated init<C, S>(_ title: S, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) where C : RandomAccessCollection, S : StringProtocol { fatalError() }
    // doc: SwiftUI/Picker/init(_:selection:content:)-6lwfn
    public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Picker/init(_:selection:content:currentValueLabel:)-2ht82  [iOS 18.0]
    public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder currentValueLabel: () -> some View) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Picker: _PrimitiveView {}

// doc: SwiftUI/Stepper
public struct Stepper<Label> where Label : View {
    // doc: SwiftUI/Stepper/init(label:onIncrement:onDecrement:onEditingChanged:)
    public nonisolated init(@ContentBuilder label: () -> Label, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }) { fatalError() }
}
extension Stepper where Label: View {
    // doc: SwiftUI/Stepper/init(value:step:label:onEditingChanged:)
    @_disfavoredOverload public nonisolated init<V>(value: Binding<V>, step: V.Stride = 1, @ContentBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(value:step:format:label:onEditingChanged:)
    public nonisolated init<F>(value: Binding<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, @ContentBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(value:in:step:label:onEditingChanged:)
    @_disfavoredOverload public nonisolated init<V>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ContentBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(value:in:step:format:label:onEditingChanged:)
    public nonisolated init<F>(value: Binding<F.FormatInput>, in bounds: ClosedRange<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, @ContentBuilder label: () -> Label, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(value:step:onEditingChanged:label:)
    public nonisolated init<V>(value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ContentBuilder label: () -> Label) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(value:in:step:onEditingChanged:label:)
    public nonisolated init<V>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ContentBuilder label: () -> Label) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(onIncrement:onDecrement:onEditingChanged:label:)
    public nonisolated init(onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ContentBuilder label: () -> Label) { fatalError() }
}
extension Stepper where Label == Text {
    // doc: SwiftUI/Stepper/init(_:value:in:step:format:onEditingChanged:)-8yger
    public nonisolated init<S, F>(_ title: S, value: Binding<F.FormatInput>, in bounds: ClosedRange<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where S : StringProtocol, F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:step:format:onEditingChanged:)-6l846
    public nonisolated init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:in:step:format:onEditingChanged:)-1mpvw
    public nonisolated init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, in bounds: ClosedRange<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:step:onEditingChanged:)-8nkqz
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where S : StringProtocol, V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:in:step:onEditingChanged:)-99t9q
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where S : StringProtocol, V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:step:onEditingChanged:)-8fa3q
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:step:format:onEditingChanged:)-164rp
    public nonisolated init<S, F>(_ title: S, value: Binding<F.FormatInput>, step: F.FormatInput.Stride = 1, format: F, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where S : StringProtocol, F : ParseableFormatStyle, F.FormatInput : BinaryFloatingPoint, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/Stepper/init(_:onIncrement:onDecrement:onEditingChanged:)-5pmbh
    public nonisolated init(_ titleKey: LocalizedStringKey, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }) { fatalError() }
    // doc: SwiftUI/Stepper/init(_:value:in:step:onEditingChanged:)-erv1
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V : Strideable { fatalError() }
    // doc: SwiftUI/Stepper/init(_:onIncrement:onDecrement:onEditingChanged:)-42t6m
    public nonisolated init<S>(_ title: S, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where S : StringProtocol { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Stepper: _PrimitiveView {}

// doc: SwiftUI/TextField
public struct TextField<Label> where Label : View {
}
extension TextField where Label == Text {
    // doc: SwiftUI/TextField/init(_:text:)
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>) { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:)
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, formatter: Formatter) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onEditingChanged:onCommit:)
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onCommit:)
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onEditingChanged:)
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onEditingChanged:onCommit:)
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, formatter: Formatter, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onCommit:)
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, formatter: Formatter, onCommit: @escaping () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onEditingChanged:)
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, formatter: Formatter, onEditingChanged: @escaping (Bool) -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:)-dym8
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:selection:prompt:axis:)-80y12  [iOS 18.0]
    public nonisolated init<S>(_ title: S, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:prompt:)-8kpfa
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, prompt: Text?) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:axis:)-7n1bm
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onEditingChanged:onCommit:)-588cl
    public nonisolated init<S>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:prompt:)-4kzyv
    public nonisolated init<S>(_ title: S, text: Binding<String>, prompt: Text?) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onCommit:)-1zeco
    public nonisolated init<S>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:format:prompt:)-4g6if
    public nonisolated init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil) where F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:format:prompt:)-6ug7k
    public nonisolated init<S, F>(_ title: S, value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil) where S : StringProtocol, F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onCommit:)-22hg
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, onCommit: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:)-2laoi
    public nonisolated init<S>(_ title: S, text: Binding<String>) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onEditingChanged:)-487wv
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, onEditingChanged: @escaping (Bool) -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:prompt:axis:)-8qr48
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:axis:)-8rujz
    public nonisolated init<S>(_ title: S, text: Binding<String>, axis: Axis) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:selection:prompt:axis:)-4kras  [iOS 18.0]
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:prompt:)-70zi2
    public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:prompt:axis:)-9r5m8
    public nonisolated init<S>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:text:onEditingChanged:)-6dntz
    public nonisolated init<S>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:onEditingChanged:onCommit:)-6ab2i
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:formatter:prompt:)-8xa65
    public nonisolated init<S, V>(_ title: S, value: Binding<V>, formatter: Formatter, prompt: Text?) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:format:prompt:)-3fh51
    public nonisolated init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil) where F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/TextField/init(_:value:format:prompt:)-7flsn
    public nonisolated init<S, F>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil) where S : StringProtocol, F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
}
extension TextField where Label: View {
    // doc: SwiftUI/TextField/init(text:prompt:label:)
    public nonisolated init(text: Binding<String>, prompt: Text? = nil, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/TextField/init(text:prompt:axis:label:)
    public nonisolated init(text: Binding<String>, prompt: Text? = nil, axis: Axis, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/TextField/init(value:format:prompt:label:)
    public nonisolated init<F>(value: Binding<F.FormatInput>, format: F, prompt: Text? = nil, @ContentBuilder label: () -> Label) where F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
    // doc: SwiftUI/TextField/init(value:formatter:prompt:label:)
    public nonisolated init<V>(value: Binding<V>, formatter: Formatter, prompt: Text? = nil, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/TextField/init(text:selection:prompt:axis:label:)  [iOS 18.0]
    public nonisolated init(text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/TextField/init(value:format:prompt:label:)-5325h
    public nonisolated init<F>(value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil, @ContentBuilder label: () -> Label) where F : ParseableFormatStyle, F.FormatOutput == String { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension TextField: _PrimitiveView {}

// doc: SwiftUI/TextEditor
public struct TextEditor {
    // doc: SwiftUI/TextEditor/init(text:)
    public nonisolated init(text: Binding<String>) { fatalError() }
    // doc: SwiftUI/TextEditor/init(text:selection:)-7gpwi  [iOS 18.0]
    public nonisolated init(text: Binding<String>, selection: Binding<TextSelection?>) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension TextEditor: _PrimitiveView {}

// doc: SwiftUI/Menu
public struct Menu<Label, Content> where Label : View, Content : View {
}
extension Menu where Label: View, Content: View {
    // doc: SwiftUI/Menu/init(content:label:)
    public nonisolated init(@ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/Menu/init(content:label:primaryAction:)
    public nonisolated init(@ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label, primaryAction: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/Menu/init(_:content:primaryAction:)-1t1lw
    public nonisolated init<S>(_ title: S, @ContentBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text, S : StringProtocol { fatalError() }
    // doc: SwiftUI/Menu/init(_:content:primaryAction:)-1349t
    public nonisolated init(_ titleKey: LocalizedStringKey, @ContentBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text { fatalError() }
    // doc: SwiftUI/Menu/init(_:content:)-7tkrw
    public nonisolated init<S>(_ title: S, @ContentBuilder content: () -> Content) where Label == Text, S : StringProtocol { fatalError() }
    // doc: SwiftUI/Menu/init(_:content:)-7v768
    public nonisolated init(_ titleKey: LocalizedStringKey, @ContentBuilder content: () -> Content) where Label == Text { fatalError() }
}
extension Menu where Label == SwiftUI.Label<Text, Image>, Content: View {
    // doc: SwiftUI/Menu/init(_:systemImage:content:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Menu/init(_:systemImage:content:primaryAction:)
    public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, @ContentBuilder content: () -> Content, primaryAction: @escaping () -> Void) { fatalError() }
    // doc: SwiftUI/Menu/init(_:systemImage:content:)-7axwe
    public nonisolated init<S>(_ title: S, systemImage: String, @ContentBuilder content: () -> Content) where S : StringProtocol { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Menu: _PrimitiveView {}

// doc: SwiftUI/Divider
public struct Divider {
    // doc: SwiftUI/Divider/init()
    public nonisolated init() { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Divider: _PrimitiveView {}

// doc: SwiftUI/Spacer
public struct Spacer: Sendable {
    // doc: SwiftUI/Spacer/init(minLength:)
    public init(minLength: CGFloat? = nil) { fatalError() }
    // doc: SwiftUI/Spacer/minLength
    public var minLength: CGFloat? = nil
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Spacer: _PrimitiveView {}

// doc: SwiftUI/ProgressView
public struct ProgressView<Label, CurrentValueLabel> where Label : View, CurrentValueLabel : View {
}
extension ProgressView where Label: View, CurrentValueLabel == EmptyView {
    // doc: SwiftUI/ProgressView/init()
    public nonisolated init() where Label == EmptyView { fatalError() }
    // doc: SwiftUI/ProgressView/init(label:)
    public nonisolated init(@ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/ProgressView/init(_:)-6k5se
    public nonisolated init(_ titleKey: LocalizedStringKey) where Label == Text { fatalError() }
    // doc: SwiftUI/ProgressView/init(_:)-3q5nf
    public nonisolated init<S>(_ title: S) where Label == Text, S : StringProtocol { fatalError() }
}
extension ProgressView where Label: View, CurrentValueLabel: View {
    // doc: SwiftUI/ProgressView/init(_:)-l5vj
    public nonisolated init(_ progress: Progress) where Label == EmptyView, CurrentValueLabel == EmptyView { fatalError() }
    // doc: SwiftUI/ProgressView/init(value:total:)
    public nonisolated init<V>(value: V?, total: V = 1.0) where Label == EmptyView, CurrentValueLabel == EmptyView, V : BinaryFloatingPoint { fatalError() }
    // doc: SwiftUI/ProgressView/init(value:total:label:)
    public nonisolated init<V>(value: V?, total: V = 1.0, @ContentBuilder label: () -> Label) where CurrentValueLabel == EmptyView, V : BinaryFloatingPoint { fatalError() }
    // doc: SwiftUI/ProgressView/init(value:total:label:currentValueLabel:)
    public nonisolated init<V>(value: V?, total: V = 1.0, @ContentBuilder label: () -> Label, @ContentBuilder currentValueLabel: () -> CurrentValueLabel) where V : BinaryFloatingPoint { fatalError() }
    // doc: SwiftUI/ProgressView/init(timerInterval:countsDown:label:currentValueLabel:)
    public nonisolated init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ContentBuilder label: () -> Label, @ContentBuilder currentValueLabel: () -> CurrentValueLabel) { fatalError() }
    // doc: SwiftUI/ProgressView/init(_:value:total:)-6z48w
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, value: V?, total: V = 1.0) where Label == Text, CurrentValueLabel == EmptyView, V : BinaryFloatingPoint { fatalError() }
    // doc: SwiftUI/ProgressView/init(_:value:total:)-7halz
    public nonisolated init<S, V>(_ title: S, value: V?, total: V = 1.0) where Label == Text, CurrentValueLabel == EmptyView, S : StringProtocol, V : BinaryFloatingPoint { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ProgressView: _PrimitiveView {}

// doc: SwiftUI/List
public struct List<SelectionValue, Content> where SelectionValue : Hashable, Content : View {
    // doc: SwiftUI/List/body
    public nonisolated var body: some View { fatalError() }
    // doc: SwiftUI/List/init(selection:content:)-1pisz
    public nonisolated init(selection: Binding<SelectionValue?>?, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/List/init(selection:content:)-4sffx
    public nonisolated init(selection: Binding<Set<SelectionValue>>?, @ContentBuilder content: () -> Content) { fatalError() }
}
extension List where SelectionValue == Never, Content: View {
    // doc: SwiftUI/List/init(content:)
    public nonisolated init(@ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/List/init(_:rowContent:)
    public nonisolated init<Data, RowContent>(_ data: Binding<Data>, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:id:rowContent:)
    public nonisolated init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:id:rowContent:)-4s0aj
    public nonisolated init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
    // doc: SwiftUI/List/init(_:rowContent:)-3vn6i
    public nonisolated init<Data, RowContent>(_ data: Data, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }
    // doc: SwiftUI/List/init(_:rowContent:)-9jce2
    public nonisolated init<RowContent>(_ data: Range<Int>, @ContentBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, RowContent>, RowContent : View { fatalError() }
}
extension List where SelectionValue: Hashable, Content: View {
    // doc: SwiftUI/List/init(_:selection:rowContent:)
    public nonisolated init<Data, RowContent>(_ data: Binding<Data>, selection: Binding<SelectionValue?>?, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:id:selection:rowContent:)
    public nonisolated init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>?, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:id:selection:rowContent:)-2r2u9
    public nonisolated init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>?, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
    // doc: SwiftUI/List/init(_:id:selection:rowContent:)-5idq3
    public nonisolated init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:id:selection:rowContent:)-9a28m
    public nonisolated init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
    // doc: SwiftUI/List/init(_:selection:rowContent:)-3pchc
    public nonisolated init<Data, RowContent>(_ data: Data, selection: Binding<SelectionValue?>?, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }
    // doc: SwiftUI/List/init(_:selection:rowContent:)-4kita
    public nonisolated init<Data, RowContent>(_ data: Binding<Data>, selection: Binding<Set<SelectionValue>>?, @ContentBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }
    // doc: SwiftUI/List/init(_:selection:rowContent:)-434g3
    public nonisolated init<RowContent>(_ data: Range<Int>, selection: Binding<SelectionValue?>?, @ContentBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, RowContent>, RowContent : View { fatalError() }
    // doc: SwiftUI/List/init(_:selection:rowContent:)-2bobo
    public nonisolated init<RowContent>(_ data: Range<Int>, selection: Binding<Set<SelectionValue>>?, @ContentBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, HStack<RowContent>>, RowContent : View { fatalError() }
    // doc: SwiftUI/List/init(_:selection:rowContent:)-8iuwp
    public nonisolated init<Data, RowContent>(_ data: Data, selection: Binding<Set<SelectionValue>>?, @ContentBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension List: _PrimitiveView {}

// doc: SwiftUI/Section
public struct Section<Parent, Content, Footer> {
    // doc: SwiftUI/Section/init(content:header:footer:)
    public init(@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent, @ContentBuilder footer: () -> Footer) { fatalError() }
}
extension Section where Parent == EmptyView, Footer == EmptyView {
    // doc: SwiftUI/Section/init(content:)
    public init(@ContentBuilder content: () -> Content) { fatalError() }
}
extension Section where Parent == Text, Footer == EmptyView {
    // doc: SwiftUI/Section/init(_:content:)
    public init(_ titleKey: LocalizedStringKey, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Section/init(_:isExpanded:content:)
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/Section/init(_:isExpanded:content:)-31e4h
    public init<S>(_ title: S, isExpanded: Binding<Bool>, @ContentBuilder content: () -> Content) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/Section/init(_:content:)-3saon
    public init<S>(_ title: S, @ContentBuilder content: () -> Content) where S : StringProtocol { fatalError() }
}
extension Section where Footer == EmptyView {
    // doc: SwiftUI/Section/init(content:header:)
    public init(@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent) { fatalError() }
    // doc: SwiftUI/Section/init(isExpanded:content:header:)
    public init(isExpanded: Binding<Bool>, @ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent) { fatalError() }
}
extension Section where Parent == EmptyView {
    // doc: SwiftUI/Section/init(content:footer:)
    public init(@ContentBuilder content: () -> Content, @ContentBuilder footer: () -> Footer) { fatalError() }
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
    // doc: SwiftUI/Section/init(header:content:)
    public init(header: Parent, @ContentBuilder content: () -> Content) { fatalError() }
}
extension Section where Parent == EmptyView, Content: View, Footer: View {
    // doc: SwiftUI/Section/init(footer:content:)
    public init(footer: Footer, @ContentBuilder content: () -> Content) { fatalError() }
}
extension Section where Parent: View, Content: View, Footer: View {
    // doc: SwiftUI/Section/init(header:footer:content:)
    public init(header: Parent, footer: Footer, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Section: _PrimitiveView {}

// doc: SwiftUI/ForEach
public struct ForEach<Data, ID, Content> where Data : RandomAccessCollection, ID : Hashable {
    // doc: SwiftUI/ForEach/content
    public var content: (Data.Element) -> Content { get { fatalError() } set { } }
    // doc: SwiftUI/ForEach/data
    public var data: Data { get { fatalError() } set { } }
}
extension ForEach where Data: RandomAccessCollection, ID: Hashable {
    // doc: SwiftUI/ForEach/init(_:id:content:)-9unpd
    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, @ContentBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C : MutableCollection, C : RandomAccessCollection, C.Index : Hashable { fatalError() }
    // doc: SwiftUI/ForEach/init(_:id:content:)-67eeu
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ContentBuilder content: @escaping (Data.Element) -> Content) { fatalError() }
    // doc: SwiftUI/ForEach/init(_:content:)-2283g
    public init<C>(_ data: Binding<C>, @ContentBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C : MutableCollection, C : RandomAccessCollection, C.Element : Identifiable, C.Index : Hashable { fatalError() }
}
extension ForEach where Data: RandomAccessCollection, ID == Data.Element.ID, Data.Element: Identifiable {
    // doc: SwiftUI/ForEach/init(_:content:)-6if9a
    public init(_ data: Data, @ContentBuilder content: @escaping (Data.Element) -> Content) { fatalError() }
}
extension ForEach where Data == Range<Int>, ID == Int {
    // doc: SwiftUI/ForEach/init(_:content:)-ktgx
    public init(_ data: Range<Int>, @ContentBuilder content: @escaping (Int) -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ForEach: _PrimitiveView {}

// doc: SwiftUI/ScrollView
public struct ScrollView<Content> where Content : View {
    // doc: SwiftUI/ScrollView/init(_:showsIndicators:content:)
    public nonisolated init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ContentBuilder content: () -> Content) { fatalError() }
    // doc: SwiftUI/ScrollView/content
    public var content: Content { get { fatalError() } set { } }
    // doc: SwiftUI/ScrollView/axes
    public nonisolated var axes: Axis.Set { get { fatalError() } set { } }
    // doc: SwiftUI/ScrollView/showsIndicators
    public nonisolated var showsIndicators: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/ScrollView/body
    public nonisolated var body: some View { fatalError() }
}
extension ScrollView where Content: View {
    // doc: SwiftUI/ScrollView/init(_:content:)
    public nonisolated init(_ axes: Axis.Set = .vertical, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ScrollView: _PrimitiveView {}

// doc: SwiftUI/LazyVStack
public struct LazyVStack<Content> where Content : View {
    // doc: SwiftUI/LazyVStack/init(alignment:spacing:pinnedViews:content:)
    public nonisolated init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension LazyVStack: _PrimitiveView {}

// doc: SwiftUI/LazyVGrid
public struct LazyVGrid<Content> where Content : View {
    // doc: SwiftUI/LazyVGrid/init(columns:alignment:spacing:pinnedViews:content:)
    public nonisolated init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension LazyVGrid: _PrimitiveView {}

// doc: SwiftUI/VStack
public struct VStack<Content> where Content : View {
    // doc: SwiftUI/VStack/init(alignment:spacing:content:)
    public nonisolated init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension VStack: _PrimitiveView {}

// doc: SwiftUI/HStack
public struct HStack<Content> where Content : View {
    // doc: SwiftUI/HStack/init(alignment:spacing:content:)
    public nonisolated init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension HStack: _PrimitiveView {}

// doc: SwiftUI/ZStack
public struct ZStack<Content> where Content : View {
    // doc: SwiftUI/ZStack/init(alignment:content:)
    public nonisolated init(alignment: Alignment = .center, @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ZStack: _PrimitiveView {}

// doc: SwiftUI/GeometryReader
public struct GeometryReader<Content> where Content : View {
    // doc: SwiftUI/GeometryReader/init(content:)
    public nonisolated init(@ContentBuilder content: @escaping (GeometryProxy) -> Content) { fatalError() }
    // doc: SwiftUI/GeometryReader/content
    public var content: (GeometryProxy) -> Content { get { fatalError() } set { } }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension GeometryReader: _PrimitiveView {}

// doc: SwiftUI/Canvas
public struct Canvas<Symbols> where Symbols : View {
    // doc: SwiftUI/Canvas/init(opaque:colorMode:rendersAsynchronously:renderer:symbols:)
    public nonisolated init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ContentBuilder symbols: () -> Symbols) { fatalError() }
    // doc: SwiftUI/Canvas/isOpaque
    public nonisolated var isOpaque: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/Canvas/colorMode
    public nonisolated var colorMode: ColorRenderingMode { get { fatalError() } set { } }
    // doc: SwiftUI/Canvas/symbols
    public var symbols: Symbols { get { fatalError() } set { } }
    // doc: SwiftUI/Canvas/rendersAsynchronously
    public nonisolated var rendersAsynchronously: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/Canvas/renderer
    public var renderer: (inout GraphicsContext, CGSize) -> Void { get { fatalError() } set { } }
}
extension Canvas where Symbols == EmptyView {
    // doc: SwiftUI/Canvas/init(opaque:colorMode:rendersAsynchronously:renderer:)
    public nonisolated init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Canvas: _PrimitiveView {}

// doc: SwiftUI/TimelineView
public struct TimelineView<Schedule, Content> where Schedule : TimelineSchedule {
    // doc: SwiftUI/TimelineView/Context
    public struct Context {
        // doc: SwiftUI/TimelineView/Context/date
        public var date: Date { fatalError() }
        // doc: SwiftUI/TimelineView/Context/cadence-swift.property
        public var cadence: TimelineView<Schedule, Content>.Context.Cadence { fatalError() }
        // doc: SwiftUI/TimelineView/Context/Cadence-swift.enum
        public enum Cadence: Equatable, Hashable, Comparable, Sendable {
            // doc: SwiftUI/TimelineView/Context/Cadence-swift.enum/live
            case live
            // doc: SwiftUI/TimelineView/Context/Cadence-swift.enum/seconds
            case seconds
            // doc: SwiftUI/TimelineView/Context/Cadence-swift.enum/minutes
            case minutes
        }
    }
}
extension TimelineView where Schedule: TimelineSchedule, Content: View {
    // doc: SwiftUI/TimelineView/init(_:content:)-67h35  [deprecated]
    public nonisolated init(_ schedule: Schedule, @ContentBuilder content: @escaping (TimelineView<Schedule, Content>.Context) -> Content) { fatalError() }
}
extension TimelineView.Context where Schedule: TimelineSchedule {
    // doc: SwiftUI/TimelineView/Context/invalidateTimelineContent()
    public func invalidateTimelineContent() { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension TimelineView: _PrimitiveView {}

// doc: SwiftUI/NavigationStack
public struct NavigationStack<Data, Root> where Root : View {
    // doc: SwiftUI/NavigationStack/init(root:)
    public nonisolated init(@ContentBuilder root: () -> Root) where Data == NavigationPath { fatalError() }
    // doc: SwiftUI/NavigationStack/init(path:root:)
    public nonisolated init(path: Binding<Data>, @ContentBuilder root: () -> Root) where Data : MutableCollection, Data : RandomAccessCollection, Data : RangeReplaceableCollection, Data.Element : Hashable { fatalError() }
    // doc: SwiftUI/NavigationStack/init(path:root:)-63x0h
    public nonisolated init(path: Binding<NavigationPath>, @ContentBuilder root: () -> Root) where Data == NavigationPath { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension NavigationStack: _PrimitiveView {}

// doc: SwiftUI/NavigationLink
public struct NavigationLink<Label, Destination> where Label : View, Destination : View {
    // doc: SwiftUI/NavigationLink/init(destination:label:)
    public nonisolated init(@ContentBuilder destination: () -> Destination, @ContentBuilder label: () -> Label) { fatalError() }
}
extension NavigationLink where Label == Text, Destination: View {
    // doc: SwiftUI/NavigationLink/init(_:destination:)
    public nonisolated init(_ titleKey: LocalizedStringKey, @ContentBuilder destination: () -> Destination) { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:isActive:destination:)
    public nonisolated init(_ titleKey: LocalizedStringKey, isActive: Binding<Bool>, @ContentBuilder destination: () -> Destination) { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:tag:selection:destination:)
    public nonisolated init<S, V>(_ title: S, tag: V, selection: Binding<V?>, @ContentBuilder destination: () -> Destination) where S : StringProtocol, V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:isActive:)
    public nonisolated init(_ titleKey: LocalizedStringKey, destination: Destination, isActive: Binding<Bool>) { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:tag:selection:)
    public nonisolated init<S, V>(_ title: S, destination: Destination, tag: V, selection: Binding<V?>) where S : StringProtocol, V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:tag:selection:)-1rm3u
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, destination: Destination, tag: V, selection: Binding<V?>) where V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:isActive:)-3v44
    public nonisolated init<S>(_ title: S, destination: Destination, isActive: Binding<Bool>) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:)-6z03e
    public nonisolated init<S>(_ title: S, @ContentBuilder destination: () -> Destination) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:tag:selection:destination:)-510fq
    public nonisolated init<V>(_ titleKey: LocalizedStringKey, tag: V, selection: Binding<V?>, @ContentBuilder destination: () -> Destination) where V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:)-6hslu
    public nonisolated init<S>(_ title: S, destination: Destination) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:isActive:destination:)-6xw7h
    public nonisolated init<S>(_ title: S, isActive: Binding<Bool>, @ContentBuilder destination: () -> Destination) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:destination:)-3xblz
    public nonisolated init(_ titleKey: LocalizedStringKey, destination: Destination) { fatalError() }
}
extension NavigationLink where Label: View, Destination == Never {
    // doc: SwiftUI/NavigationLink/init(value:label:)
    public nonisolated init<P>(value: P?, @ContentBuilder label: () -> Label) where P : Decodable, P : Encodable, P : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:value:)-kj9v
    public nonisolated init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:value:)-9ziux
    public nonisolated init<S, P>(_ title: S, value: P?) where Label == Text, S : StringProtocol, P : Decodable, P : Encodable, P : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(value:label:)-4jswo
    public nonisolated init<P>(value: P?, @ContentBuilder label: () -> Label) where P : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:value:)-91u0d
    public nonisolated init<S, P>(_ title: S, value: P?) where Label == Text, S : StringProtocol, P : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(_:value:)-810b2
    public nonisolated init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P : Decodable, P : Encodable, P : Hashable { fatalError() }
}
extension NavigationLink where Label: View, Destination: View {
    // doc: SwiftUI/NavigationLink/isDetailLink(_:)
    public nonisolated func isDetailLink(_ isDetailLink: Bool) -> some View { fatalError() }
    // doc: SwiftUI/NavigationLink/init(isActive:destination:label:)
    public nonisolated init(isActive: Binding<Bool>, @ContentBuilder destination: () -> Destination, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/NavigationLink/init(tag:selection:destination:label:)
    public nonisolated init<V>(tag: V, selection: Binding<V?>, @ContentBuilder destination: () -> Destination, @ContentBuilder label: () -> Label) where V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(destination:isActive:label:)
    public nonisolated init(destination: Destination, isActive: Binding<Bool>, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/NavigationLink/init(destination:tag:selection:label:)
    public nonisolated init<V>(destination: Destination, tag: V, selection: Binding<V?>, @ContentBuilder label: () -> Label) where V : Hashable { fatalError() }
    // doc: SwiftUI/NavigationLink/init(destination:label:)-9dxix
    public nonisolated init(destination: Destination, @ContentBuilder label: () -> Label) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension NavigationLink: _PrimitiveView {}

// doc: SwiftUI/ViewThatFits
public struct ViewThatFits<Content> where Content : View {
    // doc: SwiftUI/ViewThatFits/init(in:content:)
    public nonisolated init(in axes: Axis.Set = [.horizontal, .vertical], @ContentBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ViewThatFits: _PrimitiveView {}

// doc: SwiftUI/ContentUnavailableView
public struct ContentUnavailableView<Label, Description, Actions> where Label : View, Description : View, Actions : View {
    // doc: SwiftUI/ContentUnavailableView/init(label:description:actions:)
    public nonisolated init(@ContentBuilder label: () -> Label, @ContentBuilder description: () -> Description = { EmptyView() }, @ContentBuilder actions: () -> Actions = { EmptyView() }) { fatalError() }
}
extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    // doc: SwiftUI/ContentUnavailableView/init(_:image:description:)-7xnlo
    public nonisolated init<S>(_ title: S, image name: String, description: Text? = nil) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/ContentUnavailableView/init(_:systemImage:description:)-6b6h
    public nonisolated init<S>(_ title: S, systemImage name: String, description: Text? = nil) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/ContentUnavailableView/init(_:systemImage:description:)-4490a
    public nonisolated init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) { fatalError() }
    // doc: SwiftUI/ContentUnavailableView/init(_:image:description:)-1mmir
    public nonisolated init(_ title: LocalizedStringKey, image name: String, description: Text? = nil) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension ContentUnavailableView: _PrimitiveView {}

// doc: SwiftUI/DisclosureGroup
public struct DisclosureGroup<Label, Content> where Label : View, Content : View {
    // doc: SwiftUI/DisclosureGroup/init(content:label:)
    public nonisolated init(@ContentBuilder content: @escaping () -> Content, @ContentBuilder label: () -> Label) { fatalError() }
    // doc: SwiftUI/DisclosureGroup/init(isExpanded:content:label:)
    public nonisolated init(isExpanded: Binding<Bool>, @ContentBuilder content: @escaping () -> Content, @ContentBuilder label: () -> Label) { fatalError() }
}
extension DisclosureGroup where Label == Text, Content: View {
    // doc: SwiftUI/DisclosureGroup/init(_:content:)-9byxn
    public nonisolated init<S>(_ label: S, @ContentBuilder content: @escaping () -> Content) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/DisclosureGroup/init(_:content:)-1h8f8
    public nonisolated init(_ titleKey: LocalizedStringKey, @ContentBuilder content: @escaping () -> Content) { fatalError() }
    // doc: SwiftUI/DisclosureGroup/init(_:isExpanded:content:)-3s5nf
    public nonisolated init<S>(_ label: S, isExpanded: Binding<Bool>, @ContentBuilder content: @escaping () -> Content) where S : StringProtocol { fatalError() }
    // doc: SwiftUI/DisclosureGroup/init(_:isExpanded:content:)-8ki39
    public nonisolated init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ContentBuilder content: @escaping () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension DisclosureGroup: _PrimitiveView {}

// doc: SwiftUI/Group
public struct Group<Content> {
    // doc: SwiftUI/Group/init(content:)
    public nonisolated init(@ContentBuilder content: () -> Content) { fatalError() }
}
extension Group where Content: Scene {
    // doc: SwiftUI/Group/init(content:)-36wa3
    public nonisolated init(@SceneBuilder content: () -> Content) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Group: _PrimitiveView {}

// doc: SwiftUI/GeometryProxy
public struct GeometryProxy {
    // doc: SwiftUI/GeometryProxy/concentricCornerRadii  [iOS 27.0]
    public var concentricCornerRadii: RectangleCornerRadii? { fatalError() }
    // doc: SwiftUI/GeometryProxy/concentricCornerRadii(in:)  [iOS 27.0]
    public func concentricCornerRadii(in frame: CGRect) -> RectangleCornerRadii? { fatalError() }
    // doc: SwiftUI/GeometryProxy/size
    public var size: CGSize { fatalError() }
    // doc: SwiftUI/GeometryProxy/safeAreaInsets
    public var safeAreaInsets: EdgeInsets { fatalError() }
    // doc: SwiftUI/GeometryProxy/reservedRegions(kind:options:layoutDirectionBehavior:)  [iOS 27.1]
    public func reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion] { fatalError() }
    // doc: SwiftUI/ReservedRegion
    public struct ReservedRegion: Equatable, Hashable, Sendable, Identifiable {
        // doc: SwiftUI/ReservedRegion/id-swift.property  [iOS 27.1]
        public var id: ReservedRegion.ID { fatalError() }
        // doc: SwiftUI/ReservedRegion/ID-swift.struct
        public struct ID: Equatable, Hashable, Sendable {
        }
        // doc: SwiftUI/ReservedRegion/frame  [iOS 27.1]
        public var frame: CGRect { fatalError() }
        // doc: SwiftUI/ReservedRegion/isActive  [iOS 27.1]
        public var isActive: Bool { fatalError() }
        // doc: SwiftUI/ReservedRegion/kind-swift.property  [iOS 27.1]
        public var kind: ReservedRegion.Kind { fatalError() }
        // doc: SwiftUI/ReservedRegion/Kind-swift.struct
        public struct Kind: Equatable, Hashable, Sendable {
            // doc: SwiftUI/ReservedRegion/Kind-swift.struct/division  [iOS 27.1]
            public static var division: ReservedRegion.Kind { fatalError() }
            // doc: SwiftUI/ReservedRegion/Kind-swift.struct/occlusion  [iOS 27.1]
            public static var occlusion: ReservedRegion.Kind { fatalError() }
        }
        // doc: SwiftUI/ReservedRegion/margins  [iOS 27.1]
        public var margins: EdgeInsets { fatalError() }
        // doc: SwiftUI/ReservedRegion/QueryOptions
        public struct QueryOptions: Equatable, Hashable, Sendable, OptionSet {
            // shim: OptionSet storage (the docs page set has no rawValue page for this type)
            public let rawValue: Int
            // shim: OptionSet requirement
            public init(rawValue: Int) { self.rawValue = rawValue }
            // doc: SwiftUI/ReservedRegion/QueryOptions/includeInactive  [iOS 27.1]
            public static var includeInactive: ReservedRegion.QueryOptions { fatalError() }
        }
    }
    // doc: SwiftUI/ReservedRegion/Kind-swift.struct
    public struct Kind: Equatable, Hashable, Sendable {
        // doc: SwiftUI/ReservedRegion/Kind-swift.struct/division  [iOS 27.1]
        public static var division: ReservedRegion.Kind { fatalError() }
        // doc: SwiftUI/ReservedRegion/Kind-swift.struct/occlusion  [iOS 27.1]
        public static var occlusion: ReservedRegion.Kind { fatalError() }
    }
    // doc: SwiftUI/ReservedRegion/QueryOptions
    public struct QueryOptions: Equatable, Hashable, Sendable, OptionSet {
        // shim: OptionSet storage (the docs page set has no rawValue page for this type)
        public let rawValue: Int
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: SwiftUI/ReservedRegion/QueryOptions/includeInactive  [iOS 27.1]
        public static var includeInactive: ReservedRegion.QueryOptions { fatalError() }
    }
    // doc: SwiftUI/GeometryProxy/frame(in:)-4d7dw
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect { fatalError() }
}

// doc: SwiftUI/StrokeShapeView
public struct StrokeShapeView<Content, Style, Background> where Content : Shape, Style : ShapeStyle, Background : View {
    // doc: SwiftUI/StrokeShapeView/init(shape:style:strokeStyle:isAntialiased:background:)
    public nonisolated init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) { fatalError() }
    // doc: SwiftUI/StrokeShapeView/background
    public nonisolated var background: Background { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeShapeView/isAntialiased
    public nonisolated var isAntialiased: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeShapeView/shape
    public nonisolated var shape: Content { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeShapeView/strokeStyle
    public nonisolated var strokeStyle: StrokeStyle { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeShapeView/style
    public nonisolated var style: Style { get { fatalError() } set { } }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension StrokeShapeView: _PrimitiveView {}

// doc: SwiftUI/StrokeBorderShapeView
public struct StrokeBorderShapeView<Content, Style, Background> where Content : InsettableShape, Style : ShapeStyle, Background : View {
    // doc: SwiftUI/StrokeBorderShapeView/init(shape:style:strokeStyle:isAntialiased:background:)
    public nonisolated init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) { fatalError() }
    // doc: SwiftUI/StrokeBorderShapeView/background
    public nonisolated var background: Background { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeBorderShapeView/isAntialiased
    public nonisolated var isAntialiased: Bool { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeBorderShapeView/shape
    public var shape: Content { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeBorderShapeView/strokeStyle
    public nonisolated var strokeStyle: StrokeStyle { get { fatalError() } set { } }
    // doc: SwiftUI/StrokeBorderShapeView/style
    public nonisolated var style: Style { get { fatalError() } set { } }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension StrokeBorderShapeView: _PrimitiveView {}

// doc: SwiftUI/Color
public struct Color: Equatable, Hashable, Sendable, ShapeStyle {
    // doc: SwiftUI/Color/init(_:bundle:)
    public init(_ name: String, bundle: Bundle? = nil) { fatalError() }
    // doc: SwiftUI/Color/init(_:)
    public init(_ resolved: Color.Resolved) { fatalError() }
    // doc: SwiftUI/Color/resolve(in:)
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved { fatalError() }
    // doc: SwiftUI/Color/init(hue:saturation:brightness:opacity:)
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) { fatalError() }
    // doc: SwiftUI/Color/init(_:white:opacity:)
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) { fatalError() }
    // doc: SwiftUI/Color/init(_:red:green:blue:opacity:)
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) { fatalError() }
    // doc: SwiftUI/Color/RGBColorSpace
    public enum RGBColorSpace: Equatable, Hashable, Sendable {
        // doc: SwiftUI/Color/RGBColorSpace/sRGB
        case sRGB
        // doc: SwiftUI/Color/RGBColorSpace/sRGBLinear
        case sRGBLinear
        // doc: SwiftUI/Color/RGBColorSpace/displayP3
        case displayP3
    }
    // doc: SwiftUI/Color/init(uiColor:)
    public init(uiColor: UIColor) { fatalError() }
    // doc: SwiftUI/Color/black
    public static var black: Color { fatalError() }
    // doc: SwiftUI/Color/blue
    public static var blue: Color { fatalError() }
    // doc: SwiftUI/Color/brown
    public static var brown: Color { fatalError() }
    // doc: SwiftUI/Color/clear
    public static var clear: Color { fatalError() }
    // doc: SwiftUI/Color/cyan
    public static var cyan: Color { fatalError() }
    // doc: SwiftUI/Color/gray
    public static var gray: Color { fatalError() }
    // doc: SwiftUI/Color/green
    public static var green: Color { fatalError() }
    // doc: SwiftUI/Color/indigo
    public static var indigo: Color { fatalError() }
    // doc: SwiftUI/Color/mint
    public static var mint: Color { fatalError() }
    // doc: SwiftUI/Color/orange
    public static var orange: Color { fatalError() }
    // doc: SwiftUI/Color/pink
    public static var pink: Color { fatalError() }
    // doc: SwiftUI/Color/purple
    public static var purple: Color { fatalError() }
    // doc: SwiftUI/Color/red
    public static var red: Color { fatalError() }
    // doc: SwiftUI/Color/teal
    public static var teal: Color { fatalError() }
    // doc: SwiftUI/Color/white
    public static var white: Color { fatalError() }
    // doc: SwiftUI/Color/yellow
    public static var yellow: Color { fatalError() }
    // doc: SwiftUI/Color/accentColor
    public static var accentColor: Color { fatalError() }
    // doc: SwiftUI/Color/primary
    public static var primary: Color { fatalError() }
    // doc: SwiftUI/Color/secondary
    public static var secondary: Color { fatalError() }
    // doc: SwiftUI/Color/opacity(_:)
    public func opacity(_ opacity: Double) -> Color { fatalError() }
    // doc: SwiftUI/Color/gradient
    public var gradient: AnyGradient { fatalError() }
    // doc: SwiftUI/Color/mix(with:by:in:)  [iOS 18.0]
    public func mix(with rhs: Color, by fraction: Double, in colorSpace: Gradient.ColorSpace = .perceptual) -> Color { fatalError() }
    // doc: SwiftUI/Color/exposureAdjust(_:)  [iOS 26.0]
    public func exposureAdjust(_ stops: Double) -> Color { fatalError() }
    // doc: SwiftUI/Color/headroom(_:)  [iOS 26.0]
    public func headroom(_ headroom: Double?) -> Color { fatalError() }
    // doc: SwiftUI/Color/resolveHDR(in:)  [iOS 26.0]
    public func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR { fatalError() }
    // doc: SwiftUI/Color/ResolvedHDR
    public struct ResolvedHDR: Equatable, Hashable, Sendable, ShapeStyle {
        // doc: SwiftUI/Color/ResolvedHDR/init(_:headroom:)  [iOS 26.0]
        public init(_ color: Color.Resolved, headroom: Float? = nil) { fatalError() }
        // doc: SwiftUI/Color/ResolvedHDR/red  [iOS 26.0]
        public var red: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/green  [iOS 26.0]
        public var green: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/blue  [iOS 26.0]
        public var blue: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/linearRed  [iOS 26.0]
        public var linearRed: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/linearGreen  [iOS 26.0]
        public var linearGreen: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/linearBlue  [iOS 26.0]
        public var linearBlue: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/opacity  [iOS 26.0]
        public var opacity: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/ResolvedHDR/headroom  [iOS 26.0]
        public var headroom: Float? { get { fatalError() } set { } }
    }
    // doc: SwiftUI/Color/description
    public var description: String { fatalError() }
    // doc: SwiftUI/Color/==(_:_:)
    public static func == (lhs: Color, rhs: Color) -> Bool { fatalError() }
    // doc: SwiftUI/Color/hash(into:)
    public func hash(into hasher: inout Hasher) { fatalError() }
    // doc: SwiftUI/Color/Resolved
    public struct Resolved: Equatable, Hashable, Sendable, ShapeStyle {
        // doc: SwiftUI/Color/Resolved/init(colorSpace:red:green:blue:opacity:)
        public init(colorSpace: Color.RGBColorSpace = .sRGB, red: Float, green: Float, blue: Float, opacity: Float = 1) { fatalError() }
        // doc: SwiftUI/Color/Resolved/blue
        public var blue: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/green
        public var green: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/linearBlue
        public var linearBlue: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/linearGreen
        public var linearGreen: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/linearRed
        public var linearRed: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/opacity
        public var opacity: Float { get { fatalError() } set { } }
        // doc: SwiftUI/Color/Resolved/red
        public var red: Float { get { fatalError() } set { } }
    }
    // doc: SwiftUI/Color/init(_:)-12z37  [iOS 26.0]
    public init<T>(_ color: T) where T : Hashable, T : ShapeStyle, T.Resolved == Color.ResolvedHDR { fatalError() }
    // doc: SwiftUI/Color/init(_:)-1hpum  [iOS 26.0]
    public init(_ resolved: Color.ResolvedHDR) { fatalError() }
    // doc: SwiftUI/Color/init(_:)-35ok0
    public init<T>(_ color: T) where T : Hashable, T : ShapeStyle, T.Resolved == Color.Resolved { fatalError() }
    // doc: SwiftUI/Color/init(_:)-5dwxf
    public init(_ color: UIColor) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension Color: _PrimitiveView {}

// doc: SwiftUI/LinearGradient
public struct LinearGradient: Sendable, ShapeStyle {
    // doc: SwiftUI/LinearGradient/init(gradient:startPoint:endPoint:)
    public nonisolated init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) { fatalError() }
    // doc: SwiftUI/LinearGradient/init(colors:startPoint:endPoint:)
    public nonisolated init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) { fatalError() }
    // doc: SwiftUI/LinearGradient/init(stops:startPoint:endPoint:)
    public nonisolated init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) { fatalError() }
}
// shim: primitive-view / toolbar / gesture plumbing conformance
extension LinearGradient: _PrimitiveView {}
