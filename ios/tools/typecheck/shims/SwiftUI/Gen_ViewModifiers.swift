// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

extension View {
    // doc: SwiftUI/View/modifier(_:)
    public nonisolated func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> { fatalError() }
    // doc: SwiftUI/View/accessibilityAction(_:_:)
    public nonisolated func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityAction(action:label:)
    public nonisolated func accessibilityAction<Label>(action: @escaping () -> Void, @ContentBuilder label: () -> Label) -> some View where Label : View { self }
    // doc: SwiftUI/View/accessibilityElement(children:)
    public nonisolated func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    // doc: SwiftUI/View/accessibilityChildren(children:)
    public nonisolated func accessibilityChildren<V>(@ContentBuilder children: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/accessibilityHidden(_:)
    public nonisolated func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityHidden(_:isEnabled:)  [iOS 18.0]
    public nonisolated func accessibilityHidden(_ hidden: Bool, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityIdentifier(_:)
    public nonisolated func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityAddTraits(_:)
    public nonisolated func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/foregroundStyle(_:)
    public nonisolated func foregroundStyle<S>(_ style: S) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/View/foregroundStyle(_:_:)
    public nonisolated func foregroundStyle<S1, S2>(_ primary: S1, _ secondary: S2) -> some View where S1 : ShapeStyle, S2 : ShapeStyle { self }
    // doc: SwiftUI/View/foregroundStyle(_:_:_:)
    public nonisolated func foregroundStyle<S1, S2, S3>(_ primary: S1, _ secondary: S2, _ tertiary: S3) -> some View where S1 : ShapeStyle, S2 : ShapeStyle, S3 : ShapeStyle { self }
    // doc: SwiftUI/View/tint(_:)
    public nonisolated func tint(_ tint: Color?) -> some View { self }
    // doc: SwiftUI/View/preferredColorScheme(_:)
    public nonisolated func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View { self }
    // doc: SwiftUI/View/overlay(alignment:content:)
    public nonisolated func overlay<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/overlay(_:ignoresSafeAreaEdges:)
    public nonisolated func overlay<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/View/overlay(_:in:fillStyle:)
    public nonisolated func overlay<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S : ShapeStyle, T : Shape { self }
    // doc: SwiftUI/View/background(alignment:content:)
    public nonisolated func background<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/background(_:ignoresSafeAreaEdges:)
    public nonisolated func background<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/View/background(ignoresSafeAreaEdges:)
    public nonisolated func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View { self }
    // doc: SwiftUI/View/background(_:in:fillStyle:)
    public nonisolated func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S : ShapeStyle, T : InsettableShape { self }
    // doc: SwiftUI/View/background(in:fillStyle:)
    public nonisolated func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S : InsettableShape { self }
    // doc: SwiftUI/View/listRowBackground(_:)
    public nonisolated func listRowBackground<V>(_ view: V?) -> some View where V : View { self }
    // doc: SwiftUI/View/scrollContentBackground(_:)
    public nonisolated func scrollContentBackground(_ visibility: Visibility) -> some View { self }
    // doc: SwiftUI/View/scrollBounceBehavior(_:axes:)
    public nonisolated func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { self }
    // doc: SwiftUI/View/hidden()
    public nonisolated func hidden() -> some View { self }
    // doc: SwiftUI/View/labelsHidden()
    public nonisolated func labelsHidden() -> some View { self }
    // doc: SwiftUI/View/listRowSeparator(_:edges:)
    public nonisolated func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
    // doc: SwiftUI/View/scrollIndicators(_:axes:)
    public nonisolated func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View { self }
    // doc: SwiftUI/View/sensoryFeedback(_:trigger:)
    public nonisolated func sensoryFeedback<T>(_ feedback: SensoryFeedback, trigger: T) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/sensoryFeedback(trigger:_:)
    public nonisolated func sensoryFeedback<T>(trigger: T, _ feedback: @escaping () -> SensoryFeedback?) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/sensoryFeedback(_:trigger:condition:)
    public nonisolated func sensoryFeedback<T>(_ feedback: SensoryFeedback, trigger: T, condition: @escaping (T, T) -> Bool) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/font(_:)
    public nonisolated func font(_ font: Font?) -> some View { self }
    // doc: SwiftUI/View/dynamicTypeSize(_:)
    public nonisolated func dynamicTypeSize(_ size: DynamicTypeSize) -> some View { self }
    // doc: SwiftUI/View/bold(_:)
    public nonisolated func bold(_ isActive: Bool = true) -> some View { self }
    // doc: SwiftUI/View/monospacedDigit()
    public nonisolated func monospacedDigit() -> some View { self }
    // doc: SwiftUI/View/minimumScaleFactor(_:)
    public nonisolated func minimumScaleFactor(_ factor: CGFloat) -> some View { self }
    // doc: SwiftUI/View/tracking(_:)
    public nonisolated func tracking(_ tracking: CGFloat) -> some View { self }
    // doc: SwiftUI/View/lineLimit(_:)
    public nonisolated func lineLimit(_ limit: ClosedRange<Int>) -> some View { self }
    // doc: SwiftUI/View/lineLimit(_:reservesSpace:)
    public nonisolated func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View { self }
    // doc: SwiftUI/View/multilineTextAlignment(_:)
    public nonisolated func multilineTextAlignment(_ alignment: TextAlignment) -> some View { self }
    // doc: SwiftUI/View/multilineTextAlignment(strategy:)  [iOS 26.0]
    public nonisolated func multilineTextAlignment(strategy: Text.AlignmentStrategy) -> some View { self }
    // doc: SwiftUI/View/autocorrectionDisabled(_:)
    public nonisolated func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }
    // doc: SwiftUI/View/keyboardType(_:)
    public nonisolated func keyboardType(_ type: UIKeyboardType) -> some View { self }
    // doc: SwiftUI/View/scrollDismissesKeyboard(_:)
    public nonisolated func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View { self }
    // doc: SwiftUI/View/textInputAutocapitalization(_:)
    public nonisolated func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { self }
    // doc: SwiftUI/View/navigationBarTitleDisplayMode(_:)
    public nonisolated func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    // doc: SwiftUI/View/navigationDestination(for:destination:)
    public nonisolated func navigationDestination<D, C>(for data: D.Type, @ContentBuilder destination: @escaping (D) -> C) -> some View where D : Hashable, C : View { self }
    // doc: SwiftUI/View/navigationDestination(isPresented:destination:)
    public nonisolated func navigationDestination<V>(isPresented: Binding<Bool>, @ContentBuilder destination: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/navigationDestination(item:destination:)
    public nonisolated func navigationDestination<D, C>(item: Binding<Optional<D>>, @ContentBuilder destination: @escaping (D) -> C) -> some View where D : Hashable, C : View { self }
    // doc-fixed: SwiftUI/View/toolbar(content:) | @ContentBuilder content: () -> Content) -> some View where Content : ToolbarContent => @ToolbarContentBuilder content: () -> Content) -> some View where Content : ToolbarContent | the docs print every result-builder attribute as ContentBuilder; for a ToolbarContent closure the builder has to be ToolbarContentBuilder (ViewBuilder cannot build ToolbarItem)
    public nonisolated func toolbar<Content>(@ToolbarContentBuilder content: () -> Content) -> some View where Content : ToolbarContent { self }
    // doc: SwiftUI/View/toolbar(_:for:)
    public nonisolated func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View { self }
    // doc: SwiftUI/View/contextMenu(menuItems:)
    public nonisolated func contextMenu<MenuItems>(@ContentBuilder menuItems: () -> MenuItems) -> some View where MenuItems : View { self }
    // doc: SwiftUI/View/contextMenu(menuItems:preview:)
    public nonisolated func contextMenu<M, P>(@ContentBuilder menuItems: () -> M, @ContentBuilder preview: () -> P) -> some View where M : View, P : View { self }
    // doc: SwiftUI/View/contextMenu(forSelectionType:menu:primaryAction:)
    public nonisolated func contextMenu<I, M>(forSelectionType itemType: I.Type = I.self, @ContentBuilder menu: @escaping (Set<I>) -> M, primaryAction: ((Set<I>) -> Void)? = nil) -> some View where I : Hashable, M : View { self }
    // doc: SwiftUI/View/glassEffect(_:in:)  [iOS 26.0]
    public nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View { self }
    // doc: SwiftUI/View/buttonStyle(_:)
    public nonisolated func buttonStyle<S>(_ style: S) -> some View where S : ButtonStyle { self }
    // doc: SwiftUI/View/pickerStyle(_:)
    public nonisolated func pickerStyle<S>(_ style: S) -> some View where S : PickerStyle { self }
    // doc: SwiftUI/View/listStyle(_:)
    public nonisolated func listStyle<S>(_ style: S) -> some View where S : ListStyle { self }
    // doc: SwiftUI/View/frame(width:height:alignment:)
    public nonisolated func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    // doc: SwiftUI/View/frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)
    public nonisolated func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    // doc: SwiftUI/View/fixedSize()
    public nonisolated func fixedSize() -> some View { self }
    // doc: SwiftUI/View/fixedSize(horizontal:vertical:)
    public nonisolated func fixedSize(horizontal: Bool, vertical: Bool) -> some View { self }
    // doc: SwiftUI/View/layoutPriority(_:)
    public nonisolated func layoutPriority(_ value: Double) -> some View { self }
    // doc: SwiftUI/View/position(_:)
    public nonisolated func position(_ position: CGPoint) -> some View { self }
    // doc: SwiftUI/View/position(x:y:)
    public nonisolated func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    // doc: SwiftUI/View/offset(_:)
    public nonisolated func offset(_ offset: CGSize) -> some View { self }
    // doc: SwiftUI/View/offset(x:y:)
    public nonisolated func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    // doc: SwiftUI/View/padding(_:)
    public nonisolated func padding(_ insets: EdgeInsets) -> some View { self }
    // doc: SwiftUI/View/padding(_:_:)
    public nonisolated func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    // doc: SwiftUI/View/listRowInsets(_:)
    public nonisolated func listRowInsets(_ insets: EdgeInsets?) -> some View { self }
    // doc: SwiftUI/View/listRowInsets(_:_:)  [iOS 26.0]
    public nonisolated func listRowInsets(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View { self }
    // doc: SwiftUI/View/ignoresSafeArea(_:edges:)
    public nonisolated func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }
    // doc: SwiftUI/View/ignoresSafeArea(_:edges:alignment:)  [iOS 27.0]
    public nonisolated func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all, alignment: Alignment?) -> some View { self }
    // doc: SwiftUI/View/safeAreaInset(edge:alignment:spacing:content:)
    public nonisolated func safeAreaInset<V>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/clipped(antialiased:)
    public nonisolated func clipped(antialiased: Bool = false) -> some View { self }
    // doc: SwiftUI/View/clipShape(_:style:)
    public nonisolated func clipShape<S>(_ shape: S, style: FillStyle = FillStyle()) -> some View where S : Shape { self }
    // doc: SwiftUI/View/scaleEffect(x:y:anchor:)
    public nonisolated func scaleEffect(x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center) -> some View { self }
    // doc: SwiftUI/View/rotationEffect(_:anchor:)
    public nonisolated func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { self }
    // doc: SwiftUI/View/opacity(_:)
    public nonisolated func opacity(_ opacity: Double) -> some View { self }
    // doc: SwiftUI/View/brightness(_:)
    public nonisolated func brightness(_ amount: Double) -> some View { self }
    // doc: SwiftUI/View/shadow(color:radius:x:y:)
    public nonisolated func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    // doc: SwiftUI/View/animation(_:value:)
    public nonisolated func animation<V>(_ animation: Animation?, value: V) -> some View where V : Equatable { self }
    // doc: SwiftUI/View/disabled(_:)
    public nonisolated func disabled(_ disabled: Bool) -> some View { self }
    // doc: SwiftUI/View/swipeActions(edge:allowsFullSwipe:content:)
    public nonisolated func swipeActions<T>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ContentBuilder content: () -> T) -> some View where T : View { self }
    // doc: SwiftUI/View/swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)  [iOS 27.0]
    public nonisolated func swipeActions(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ContentBuilder content: () -> some View, onPresentationChanged: @escaping (Bool) -> Void) -> some View { self }
    // doc: SwiftUI/View/onTapGesture(count:perform:)
    public nonisolated func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { self }
    // doc: SwiftUI/View/gesture(_:isEnabled:)
    public nonisolated func gesture<T>(_ gesture: T, isEnabled: Bool) -> some View where T : Gesture { self }
    // doc: SwiftUI/View/gesture(_:name:isEnabled:)  [iOS 18.0]
    public nonisolated func gesture<T>(_ gesture: T, name: String, isEnabled: Bool = true) -> some View where T : Gesture { self }
    // doc: SwiftUI/View/gesture(_:including:)
    public nonisolated func gesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T : Gesture { self }
    // doc: SwiftUI/View/focused(_:equals:)
    public nonisolated func focused<Value>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View where Value : Hashable { self }
    // doc: SwiftUI/View/focused(_:)
    public nonisolated func focused(_ condition: FocusState<Bool>.Binding) -> some View { self }
    // doc: SwiftUI/View/onSubmit(of:_:)
    public nonisolated func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View { self }
    // doc: SwiftUI/View/submitLabel(_:)
    public nonisolated func submitLabel(_ submitLabel: SubmitLabel) -> some View { self }
    // doc: SwiftUI/View/onAppear(perform:)
    public nonisolated func onAppear(perform action: (() -> Void)? = nil) -> some View { self }
    // doc: SwiftUI/View/onDisappear(perform:)
    public nonisolated func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }
    // doc: SwiftUI/View/onChange(of:initial:_:)
    public nonisolated func onChange<V>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View where V : Equatable { self }
    // doc: SwiftUI/View/task(id:name:executorPreference:priority:file:line:_:)  [iOS 26.4]
    public nonisolated func task<T>(id: T, name: String? = nil, executorPreference taskExecutor: any TaskExecutor, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line, _ action: sending @escaping @isolated(any) () async -> Void) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/task(id:name:priority:file:line:_:)
    public nonisolated func task<T>(id: T, name: String? = nil, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line, _ action: sending @escaping @isolated(any) () async -> Void) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/task(name:executorPreference:priority:file:line:action:)  [iOS 26.4]
    public nonisolated func task(name: String? = nil, executorPreference taskExecutor: any TaskExecutor, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line, action: sending @escaping @isolated(any) () async -> Void) -> some View { self }
    // doc: SwiftUI/View/task(name:priority:file:line:_:)
    public nonisolated func task(name: String? = nil, priority: TaskPriority = .userInitiated, file: String = #fileID, line: Int = #line, _ action: sending @escaping @isolated(any) () async -> Void) -> some View { self }
    // doc: SwiftUI/View/allowsHitTesting(_:)
    public nonisolated func allowsHitTesting(_ enabled: Bool) -> some View { self }
    // doc: SwiftUI/View/contentShape(_:eoFill:)
    public nonisolated func contentShape<S>(_ shape: S, eoFill: Bool = false) -> some View where S : Shape { self }
    // doc: SwiftUI/View/contentShape(_:_:eoFill:)
    public nonisolated func contentShape<S>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View where S : Shape { self }
    // doc: SwiftUI/View/alert(_:item:actions:)
    public nonisolated func alert<A, T>(_ title: Text, item data: Binding<T?>, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/alert(error:actions:)
    @_disfavoredOverload public nonisolated func alert<E, A>(error: Binding<E?>, @ContentBuilder actions: () -> A) -> some View where E : LocalizedError, A : View { self }
    // doc: SwiftUI/View/alert(isPresented:error:actions:)
    public nonisolated func alert<E, A>(isPresented: Binding<Bool>, error: E?, @ContentBuilder actions: () -> A) -> some View where E : LocalizedError, A : View { self }
    // doc: SwiftUI/View/alert(_:item:actions:message:)
    public nonisolated func alert<A, M, T>(_ titleKey: LocalizedStringKey, item data: Binding<T?>, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/alert(error:actions:message:)
    @_disfavoredOverload public nonisolated func alert<E, A, M>(error: Binding<E?>, @ContentBuilder actions: (E) -> A, @ContentBuilder message: (E) -> M) -> some View where E : LocalizedError, A : View, M : View { self }
    // doc: SwiftUI/View/alert(isPresented:error:actions:message:)
    public nonisolated func alert<E, A, M>(isPresented: Binding<Bool>, error: E?, @ContentBuilder actions: (E) -> A, @ContentBuilder message: (E) -> M) -> some View where E : LocalizedError, A : View, M : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:)
    public nonisolated func confirmationDialog<A, T>(_ title: Text, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:message:)
    public nonisolated func confirmationDialog<A, M, T>(_ title: Text, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/sheet(isPresented:onDismiss:content:)
    public nonisolated func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View where Content : View { self }
    // doc: SwiftUI/View/sheet(item:onDismiss:content:)
    public nonisolated func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping (Item) -> Content) -> some View where Item : Identifiable, Content : View { self }
    // doc: SwiftUI/View/fullScreenCover(isPresented:onDismiss:content:)
    public nonisolated func fullScreenCover<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View where Content : View { self }
    // doc: SwiftUI/View/fullScreenCover(item:onDismiss:content:)
    public nonisolated func fullScreenCover<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping (Item) -> Content) -> some View where Item : Identifiable, Content : View { self }
    // doc: SwiftUI/View/interactiveDismissDisabled(_:)
    public nonisolated func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { self }
    // doc: SwiftUI/View/presentationDetents(_:)
    public nonisolated func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    // doc: SwiftUI/View/presentationDetents(_:selection:)
    public nonisolated func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View { self }
    // doc: SwiftUI/View/presentationDragIndicator(_:)
    public nonisolated func presentationDragIndicator(_ visibility: Visibility) -> some View { self }
    // doc: SwiftUI/View/presentationBackground(_:)
    public nonisolated func presentationBackground<S>(_ style: S) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/View/presentationBackground(alignment:content:)
    public nonisolated func presentationBackground<V>(alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/presentationCornerRadius(_:)
    public nonisolated func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View { self }
    // doc: SwiftUI/View/tag(_:includeOptional:)
    public nonisolated func tag<V>(_ tag: V, includeOptional: Bool = true) -> some View where V : Hashable { self }
    // doc: SwiftUI/View/id(_:)
    public nonisolated func id<ID>(_ id: ID) -> some View where ID : Hashable { self }
    // doc: SwiftUI/View/environment(_:)
    public nonisolated func environment<T>(_ object: T?) -> some View where T : AnyObject, T : Observable { self }
    // doc: SwiftUI/View/environment(_:_:)
    public nonisolated func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View { self }
    // doc: SwiftUI/View/colorScheme(_:)
    public nonisolated func colorScheme(_ colorScheme: ColorScheme) -> some View { self }
    // doc: SwiftUI/View/background(_:alignment:)
    public nonisolated func background<Background>(_ background: Background, alignment: Alignment = .center) -> some View where Background : View { self }
    // doc: SwiftUI/View/overlay(_:alignment:)
    public nonisolated func overlay<Overlay>(_ overlay: Overlay, alignment: Alignment = .center) -> some View where Overlay : View { self }
    // doc: SwiftUI/View/frame()
    public nonisolated func frame() -> some View { self }
    // doc: SwiftUI/View/animation(_:)-1hc0p
    public nonisolated func animation(_ animation: Animation?) -> some View { self }
    // doc: SwiftUI/View/onChange(of:perform:)
    public nonisolated func onChange<V>(of value: V, perform action: @escaping (V) -> Void) -> some View where V : Equatable { self }
    // doc: SwiftUI/View/onTapGesture(count:coordinateSpace:perform:)-36x9h
    public nonisolated func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local, perform action: @escaping (CGPoint) -> Void) -> some View { self }
    // doc: SwiftUI/View/alert(isPresented:content:)
    public nonisolated func alert(isPresented: Binding<Bool>, content: () -> Alert) -> some View { self }
    // doc: SwiftUI/View/alert(item:content:)
    public nonisolated func alert<Item>(item: Binding<Item?>, content: (Item) -> Alert) -> some View where Item : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:placement:prompt:suggestions:)
    public nonisolated func searchable<S>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder suggestions: () -> S) -> some View where S : View { self }
    // doc: SwiftUI/View/navigationTitle(_:)-43srq
    public nonisolated func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)-9quvm
    public nonisolated func confirmationDialog<S, A, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)-1iv4u
    public nonisolated func confirmationDialog<A, M, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/searchable(text:editableTokens:placement:prompt:token:)-8y2px
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: some StringProtocol, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/alert(_:isPresented:actions:message:)-8dvt8
    public nonisolated func alert<A, M>(_ title: Text, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:)-4rhk6
    public nonisolated func alert<A, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/searchable(text:placement:prompt:)-1bjj3
    public nonisolated func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:)-87n66
    public nonisolated func confirmationDialog<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/accessibilityAction(named:_:)-8ssvg
    public nonisolated func accessibilityAction<S>(named name: S, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:)-55h6a
    public nonisolated func confirmationDialog<A>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:placement:prompt:token:)-9m40k
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : MutableCollection, C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityLabel(_:isEnabled:)-u1du  [iOS 18.0]
    public nonisolated func accessibilityLabel(_ label: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/searchable(text:placement:prompt:)-18a8f
    public nonisolated func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View { self }
    // doc: SwiftUI/View/sensoryFeedback(trigger:_:)-7r5v7
    public nonisolated func sensoryFeedback<T>(trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?) -> some View where T : Equatable { self }
    // doc: SwiftUI/View/lineLimit(_:)-513mb
    public nonisolated func lineLimit(_ number: Int?) -> some View { self }
    // doc: SwiftUI/View/alert(error:actions:)-dxc7  [iOS 27.0]
    public nonisolated func alert<E, A>(error: Binding<E?>, @ContentBuilder actions: () -> A) -> some View where E : Error, A : View { self }
    // doc: SwiftUI/View/searchable(text:placement:prompt:suggestions:)-1er8o
    public nonisolated func searchable<V, S>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S, @ContentBuilder suggestions: () -> V) -> some View where V : View, S : StringProtocol { self }
    // doc: SwiftUI/View/safeAreaInset(edge:alignment:spacing:content:)-4s51l
    public nonisolated func safeAreaInset<V>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ContentBuilder content: () -> V) -> some View where V : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:)-46zbb
    public nonisolated func confirmationDialog<S, A>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/searchable(text:isPresented:placement:prompt:)-5hhxx
    public nonisolated func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View { self }
    // doc: SwiftUI/View/accessibilityLabel(_:)-5f0zj
    public nonisolated func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)-3s8wb
    public nonisolated func confirmationDialog<S, A, M, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:message:)-8584l
    public nonisolated func alert<S, A, M, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:)-6ifmg
    public nonisolated func confirmationDialog<S, A, T>(_ title: S, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:placement:prompt:token:)-8xk6g
    public nonisolated func searchable<C, T, S>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: S, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : MutableCollection, C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, S : StringProtocol, C.Element : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)-8qwnr
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/alert(_:item:actions:)-28uwn
    public nonisolated func alert<A, T>(_ titleKey: LocalizedStringKey, item data: Binding<T?>, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/accessibilityHint(_:)-3i2vu
    public nonisolated func accessibilityHint(_ hintKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/alert(_:isPresented:actions:message:)-6awwp
    public nonisolated func alert<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/transition(_:)-5h5h0
    public nonisolated func transition(_ t: AnyTransition) -> some View { self }
    // doc: SwiftUI/View/searchable(text:placement:prompt:suggestions:)-2rnll
    public nonisolated func searchable<S>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder suggestions: () -> S) -> some View where S : View { self }
    // doc: SwiftUI/View/searchable(text:placement:prompt:)-co5e
    public nonisolated func searchable<S>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View where S : StringProtocol { self }
    // doc: SwiftUI/View/alert(_:isPresented:actions:)-2gsoj
    public nonisolated func alert<A>(_ title: Text, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)-d4wj
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:isPresented:placement:prompt:)-478q9
    public nonisolated func searchable<S>(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View where S : StringProtocol { self }
    // doc: SwiftUI/View/accessibilityValue(_:)-2bwuz
    public nonisolated func accessibilityValue<S>(_ value: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/alert(_:item:actions:)-4pwxo
    public nonisolated func alert<S, A, T>(_ title: S, item data: Binding<T?>, @ContentBuilder actions: (T) -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/alert(error:actions:message:)-27vbr  [iOS 27.0]
    public nonisolated func alert<E, A, M>(error: Binding<E?>, @ContentBuilder actions: (E) -> A, @ContentBuilder message: (E) -> M) -> some View where E : Error, A : View, M : View { self }
    // doc: SwiftUI/View/alert(_:isPresented:actions:)-3200l
    public nonisolated func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/lineLimit(_:)-7ufty
    public nonisolated func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View { self }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:)-7bbim
    public nonisolated func confirmationDialog<A, T>(_ titleKey: LocalizedStringKey, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/accessibilityHint(_:)-6gek2
    public nonisolated func accessibilityHint<S>(_ hint: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/alert(_:item:actions:message:)-43pdu
    public nonisolated func alert<S, A, M, T>(_ title: S, item data: Binding<T?>, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:message:)-1bs32
    public nonisolated func confirmationDialog<A, M, T>(_ titleKey: LocalizedStringKey, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/searchable(text:editableTokens:isPresented:placement:prompt:token:)-4r2b3
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityHint(_:)-3rdgs
    public nonisolated func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/lineLimit(_:)-251ko
    public nonisolated func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View { self }
    // doc: SwiftUI/View/padding(_:)-68shk
    public nonisolated func padding(_ length: CGFloat) -> some View { self }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:message:)-29bp4
    public nonisolated func alert<A, M, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)-9ibgk
    public nonisolated func confirmationDialog<A, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/accessibilityValue(_:isEnabled:)-6iqiq  [iOS 18.0]
    public nonisolated func accessibilityValue<S>(_ value: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/navigationTitle(_:)-7onr8
    public nonisolated func navigationTitle(_ title: Binding<String>) -> some View { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)-9xxr1
    public nonisolated func searchable<C, T, S>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : MutableCollection, C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, S : StringProtocol, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityHint(_:isEnabled:)-1eojf  [iOS 18.0]
    public nonisolated func accessibilityHint(_ hintKey: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/confirmationDialog(_:item:titleVisibility:actions:message:)-izi6
    public nonisolated func confirmationDialog<S, A, M, T>(_ title: S, item data: Binding<T?>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/dynamicTypeSize(_:)-26aj0
    public nonisolated func dynamicTypeSize<T>(_ range: T) -> some View where T : RangeExpression, T.Bound == DynamicTypeSize { self }
    // doc: SwiftUI/View/searchable(text:tokens:isPresented:placement:prompt:token:)-1r77c
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityLabel(_:)-9ek2h
    public nonisolated func accessibilityLabel(_ labelKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:)-78spw
    public nonisolated func alert<A, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:message:)-1r2g1
    public nonisolated func confirmationDialog<S, A, M>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/accessibilityAction(named:_:)-9ra29
    public nonisolated func accessibilityAction(named nameKey: LocalizedStringKey, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/searchable(text:editableTokens:isPresented:placement:prompt:token:)-68xwn
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:editableTokens:placement:prompt:token:)-4ip1h
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/navigationTitle(_:)-5di1u
    public nonisolated func navigationTitle(_ title: Text) -> some View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)-51pyu
    public nonisolated func confirmationDialog<A, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where A : View { self }
    // doc: SwiftUI/View/accessibilityLabel(_:isEnabled:)-6l5hm  [iOS 18.0]
    public nonisolated func accessibilityLabel(_ labelKey: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/tint(_:)-93mfq
    public nonisolated func tint<S>(_ tint: S?) -> some View where S : ShapeStyle { self }
    // doc: SwiftUI/View/searchable(text:tokens:suggestedTokens:placement:prompt:token:)-9q3oc
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : MutableCollection, C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:)-9h5um
    public nonisolated func alert<S, A, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/searchable(text:tokens:placement:prompt:token:)-35t4f
    public nonisolated func searchable<C, T, S>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: S, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, S : StringProtocol, C.Element : Identifiable { self }
    // doc: SwiftUI/View/navigationTitle(_:)-avgj
    public nonisolated func navigationTitle<S>(_ title: S) -> some View where S : StringProtocol { self }
    // doc: SwiftUI/View/accessibilityValue(_:)-z9mo
    public nonisolated func accessibilityValue(_ valueDescription: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityValue(_:isEnabled:)-8eox8  [iOS 18.0]
    public nonisolated func accessibilityValue(_ valueKey: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/background(in:fillStyle:)-96bda
    public nonisolated func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S : Shape { self }
    // doc: SwiftUI/View/searchable(text:tokens:placement:prompt:token:)-85ahx
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityAction(named:_:)-6t20v
    public nonisolated func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)-8y541
    public nonisolated func confirmationDialog<A, M, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/background(_:in:fillStyle:)-89n7j
    public nonisolated func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S : ShapeStyle, T : Shape { self }
    // doc: SwiftUI/View/searchable(text:tokens:placement:prompt:token:)-2c10v
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/accessibilityHint(_:isEnabled:)-8w0ey  [iOS 18.0]
    public nonisolated func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityValue(_:)-8esl7
    public nonisolated func accessibilityValue(_ valueKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/accessibilityValue(_:isEnabled:)-4f2s0  [iOS 18.0]
    public nonisolated func accessibilityValue(_ valueDescription: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { fatalError() }
    // doc: SwiftUI/View/scaleEffect(_:anchor:)-7q7as
    public nonisolated func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View { self }
    // doc: SwiftUI/View/searchable(text:tokens:isPresented:placement:prompt:token:)-2kr2g
    public nonisolated func searchable<C, T, S>(text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, S : StringProtocol, C.Element : Identifiable { self }
    // doc: SwiftUI/View/onChange(of:initial:_:)-4psgg
    public nonisolated func onChange<V>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View where V : Equatable { self }
    // doc: SwiftUI/View/toolbar(content:)-7vdkx
    public nonisolated func toolbar<Content>(@ContentBuilder content: () -> Content) -> some View where Content : View { self }
    // doc: SwiftUI/View/accessibilityLabel(_:)-1d7jv
    public nonisolated func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/searchable(text:editableTokens:isPresented:placement:prompt:token:)-2ilmg
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: some StringProtocol, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:editableTokens:placement:prompt:token:)-41gcr
    public nonisolated func searchable<C>(text: Binding<String>, editableTokens: Binding<C>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil, @ContentBuilder token: @escaping (Binding<C.Element>) -> some View) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, C.Element : Identifiable { self }
    // doc: SwiftUI/View/scaleEffect(_:anchor:)-pmi7
    public nonisolated func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View { self }
    // doc: SwiftUI/View/searchable(text:tokens:isPresented:placement:prompt:token:)-e813
    public nonisolated func searchable<C, T>(text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey, @ContentBuilder token: @escaping (C.Element) -> T) -> some View where C : RandomAccessCollection, C : RangeReplaceableCollection, T : View, C.Element : Identifiable { self }
    // doc: SwiftUI/View/searchable(text:isPresented:placement:prompt:)-1hn4y
    public nonisolated func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View { self }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:message:)-2tbci
    public nonisolated func confirmationDialog<A, M>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/alert(_:isPresented:actions:)-1bkka
    public nonisolated func alert<S, A>(_ title: S, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A) -> some View where S : StringProtocol, A : View { self }
    // doc: SwiftUI/View/alert(_:isPresented:actions:message:)-3rabc
    public nonisolated func alert<S, A, M>(_ title: S, isPresented: Binding<Bool>, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where S : StringProtocol, A : View, M : View { self }
    // doc: SwiftUI/View/accessibilityLabel(_:isEnabled:)-5s916  [iOS 18.0]
    public nonisolated func accessibilityLabel<S>(_ label: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/confirmationDialog(_:isPresented:titleVisibility:actions:message:)-2s7pz
    public nonisolated func confirmationDialog<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ContentBuilder actions: () -> A, @ContentBuilder message: () -> M) -> some View where A : View, M : View { self }
    // doc: SwiftUI/View/accessibilityHint(_:isEnabled:)-5xqaw  [iOS 18.0]
    public nonisolated func accessibilityHint<S>(_ hint: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S : StringProtocol { fatalError() }
    // doc: SwiftUI/View/alert(_:isPresented:presenting:actions:message:)-3md6l
    public nonisolated func alert<A, M, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View where A : View, M : View { self }
}
extension View where Self: Equatable {
    // doc: SwiftUI/View/animation(_:)
    public nonisolated func animation(_ animation: Animation?) -> some View { self }
}
