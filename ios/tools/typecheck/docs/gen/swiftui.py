from mk import *
SH = SHIMS + 'SwiftUI/'
HDR = '''// SHIM of SwiftUI, generated section. GENERATED from Apple's documentation pages: every declaration below is the
// text of a documentation page (iOS declaration, attributes verbatim) tagged with `// doc: <page>`;
// docs/verify_shims.py re-checks all of them against docs/declarations.json. Bodies are `fatalError()` (or `self`
// for `some View` modifiers): this module exists to be type-checked against, never to run.
// Declarations that mention a type this shim does not define were left out (listed in ../../docs/gen/prune.txt).
@_exported import Foundation
@_exported import CoreGraphics
import UIKit
import Observation

'''
def nm(path):
    n = docs.page_path(docs.fetch(path)).split('/', 1)[1].replace('/', '.')
    return re.sub(r'-swift\.\w+', '', n)

def prim(path, **kw):
    """A primitive view type: the documented type plus `extension T: _PrimitiveView {}`."""
    return emit_type(path, **kw) + f'extension {nm(path)}: _PrimitiveView {{}}\n'

def val(path, **kw):
    return emit_type(path, **kw)

FIXUPS = [
    ('public struct AccessibilityTraits: Equatable, Sendable {', 'public struct AccessibilityTraits: Equatable, Sendable, SetAlgebra {\n    // shim: SetAlgebra requirements (the docs list SetAlgebra and ExpressibleByArrayLiteral as conformances but have no member pages for the requirements)\n    // shim: SetAlgebra requirement\n    public typealias Element = AccessibilityTraits\n    // shim: SetAlgebra requirement\n    public init() { }\n    // shim: SetAlgebra requirement\n    public func contains(_ member: AccessibilityTraits) -> Bool { fatalError() }\n    // shim: SetAlgebra requirement\n    public func union(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }\n    // shim: SetAlgebra requirement\n    public func intersection(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }\n    // shim: SetAlgebra requirement\n    public func symmetricDifference(_ other: AccessibilityTraits) -> AccessibilityTraits { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func insert(_ newMember: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func remove(_ member: AccessibilityTraits) -> AccessibilityTraits? { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func update(with newMember: AccessibilityTraits) -> AccessibilityTraits? { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func formUnion(_ other: AccessibilityTraits) { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func formIntersection(_ other: AccessibilityTraits) { fatalError() }\n    // shim: SetAlgebra requirement\n    public mutating func formSymmetricDifference(_ other: AccessibilityTraits) { fatalError() }'),
    # Angle is Comparable; the `<` operator page is not in this docs snapshot
    ('public struct Angle: Equatable, Hashable, Comparable, Sendable {', 'public struct Angle: Equatable, Hashable, Comparable, Sendable {\n    // shim: Comparable requirement (this docs snapshot has no page for Angle.<)\n    public static func < (lhs: Angle, rhs: Angle) -> Bool { fatalError() }'),
    ('@dynamicMemberLookup @propertyWrapper public struct Bindable<Value> {', '@dynamicMemberLookup @propertyWrapper public struct Bindable<Value> {\n    // shim: a stored property so the type has no implicit init() (property wrappers require it to be public)\n    private var _shim: Int'),
    ('    @propertyWrapper public struct Binding {', '    @propertyWrapper public struct Binding {\n        // shim: a stored property so the type has no implicit init() (property wrappers require it to be public)\n        private var _shim: Int'),
]
def write(name, parts):
    s = HDR + '\n'.join(parts)
    s = s.replace('Label == Label<', 'Label == SwiftUI.Label<')
    for a, b in FIXUPS:
        s = s.replace(a, b)
    open(SH + name, 'w').write(finalize(s))

# ---- plain value types and enums
VALUES = ['swiftui/alignment','swiftui/horizontalalignment','swiftui/verticalalignment','swiftui/edge','swiftui/axis','swiftui/edgeinsets','swiftui/unitpoint','swiftui/angle',
  'swiftui/strokestyle','swiftui/animation','swiftui/transaction','swiftui/anytransition','swiftui/font','swiftui/dynamictypesize','swiftui/colorscheme','swiftui/colorschemecontrast',
  'swiftui/griditem','swiftui/contentshapekinds','swiftui/presentationdetent','swiftui/localizedstringkey','swiftui/toolbaritemplacement','swiftui/sensoryfeedback',
  'swiftui/submitlabel','swiftui/textinputautocapitalization','swiftui/visibility','swiftui/scrollbouncebehavior','swiftui/scrollindicatorvisibility','swiftui/buttonrole','swiftui/controlsize',
  'swiftui/gradient','swiftui/material','swiftui/symbolrenderingmode','swiftui/blendmode','swiftui/layoutdirection','swiftui/textalignment','swiftui/safeareaedges','swiftui/accessibilitytraits',
  'swiftui/accessibilityactionkind','swiftui/coordinatespace','swiftui/horizontaledge','swiftui/verticaledge','swiftui/truncationmode','swiftui/fillstyle','swiftui/roundedcornerstyle',
  'swiftui/shaperole','swiftui/layoutdirectionbehavior','swiftui/proposedviewsize','swiftui/timelineschedulemode','swiftui/hierarchicalshapestyle','swiftui/anyshapestyle',
  'swiftui/foregroundstyle','swiftui/backgroundstyle','swiftui/tintshapestyle','swiftui/toolbaritemgroup_',
  'swiftui/colormode','swiftui/graphicscontext','swiftui/image/renderingmode','swiftui/symbolvariants','swiftui/viewdimensions',
  'swiftui/searchfieldplacement','swiftui/safearearegions','swiftui/submittriggers','swiftui/colorrenderingmode','swiftui/primitivebuttonstyleconfiguration','swiftui/shadowstyle',
  'swiftui/scrolldismisseskeyboardmode','swiftui/userinterfacesizeclass','swiftui/toolbarplacement','swiftui/pinnedscrollableviews','swiftui/alert','swiftui/navigationpath',
  'swiftui/anygradient','swiftui/angulargradient','swiftui/radialgradient','swiftui/ellipticalgradient','swiftui/offsetshape','swiftui/scaledshape','swiftui/transformedshape','swiftui/rotatedshape',
  'swiftui/rectanglecornerradii','swiftui/animationcontext','swiftui/spring','swiftui/unitcurve','swiftui/viewspacing','swiftui/layoutsubviews','swiftui/layoutsubview','swiftui/layoutproperties',
  'swiftui/accessibilitychildbehavior','swiftui/accessibilityattachmentmodifier','swiftui/accessibilityheadinglevel','swiftui/accessibilitytextcontenttype','swiftui/accessibilityadjustmentdirection',
  'swiftui/keyboardshortcut','swiftui/textselection','swiftui/presentationbackgroundinteraction','swiftui/presentationcontentinteraction','swiftui/scenephase','swiftui/glass','swiftui/navigationbaritem','swiftui/dismissaction','swiftui/refreshaction','swiftui/gesturemask','swiftui/previewtrait_']
VP = [val(p) for p in VALUES if not p.endswith('_')]
VP.append('// shim: AccessibilityAttachmentModifier is the ViewModifier behind the accessibility* modifiers (Apple documents it as a plain struct)\nextension AccessibilityAttachmentModifier: ViewModifier {\n    // shim: modifier plumbing\n    public typealias Body = Never\n}\n')
VP.append(val('swiftui/defaultglasseffectshape') + '// shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages\nextension DefaultGlassEffectShape: InsettableShape {\n    // shim: witness\n    public func path(in rect: CGRect) -> Path { fatalError() }\n    // shim: witness\n    public func inset(by amount: CGFloat) -> DefaultGlassEffectShape { fatalError() }\n}\n')
FUNCS = emit_members(['swiftui/withtransaction(_:_:)','swiftui/withanimation(_:_:)','swiftui/withanimation(_:completioncriteria:_:completion:)'], indent='')
VP.append(FUNCS)
write('Gen_Values.swift', VP)

SKIPS = {'swiftui/contentunavailableview': ('SwiftUI/ContentUnavailableView/SearchUnavailableContent', 'SwiftUI/SearchUnavailableContent'), 'swiftui/text': ('SwiftUI/Text/Layout','SwiftUI/Text/LayoutKey','SwiftUI/Text/Proxy')}
VIEWS = ['swiftui/text','swiftui/image','swiftui/button','swiftui/label','swiftui/toggle','swiftui/picker','swiftui/stepper','swiftui/textfield','swiftui/texteditor','swiftui/menu',
  'swiftui/divider','swiftui/spacer','swiftui/progressview','swiftui/list','swiftui/section','swiftui/foreach','swiftui/scrollview','swiftui/lazyvstack','swiftui/lazyvgrid',
  'swiftui/vstack','swiftui/hstack','swiftui/zstack','swiftui/geometryreader','swiftui/canvas','swiftui/timelineview','swiftui/navigationstack','swiftui/navigationlink',
  'swiftui/viewthatfits','swiftui/contentunavailableview','swiftui/disclosuregroup','swiftui/group','swiftui/color','swiftui/lineargradient','swiftui/geometryproxy']
parts = [prim(p, skip=SKIPS.get(p, ())) for p in VIEWS if p not in ('swiftui/color','swiftui/lineargradient','swiftui/geometryproxy')]
parts.append(val('swiftui/geometryproxy'))
for p in ('swiftui/strokeshapeview','swiftui/strokebordershapeview'):
    parts.append(prim(p))
parts.append(emit_type('swiftui/color', conf=['Equatable','Hashable','Sendable','ShapeStyle']) + 'extension Color: _PrimitiveView {}\n')
parts.append(emit_type('swiftui/lineargradient', conf=['Sendable','ShapeStyle']) + 'extension LinearGradient: _PrimitiveView {}\n')
write('Gen_Views.swift', parts)

# ---- property wrappers and environment
W = []
W.append(emit_type('swiftui/state', header='@propertyWrapper public struct State<Value>: DynamicProperty'))
W.append(emit_type('swiftui/binding', header='@propertyWrapper @dynamicMemberLookup public struct Binding<Value>: DynamicProperty'))
W.append(emit_type('swiftui/environment', header='@propertyWrapper public struct Environment<Value>: DynamicProperty'))
W.append(emit_type('swiftui/bindable', header='@dynamicMemberLookup @propertyWrapper public struct Bindable<Value>'))
W.append(emit_type('swiftui/focusstate', header='@propertyWrapper public struct FocusState<Value>: DynamicProperty where Value: Hashable'))
W.append(emit_type('swiftui/scaledmetric', header='@propertyWrapper public struct ScaledMetric<Value>: DynamicProperty where Value: BinaryFloatingPoint'))
W.append(emit_type('swiftui/environmentvalues'))
write('Gen_Wrappers.swift', W)

# ---- shapes
S = []
INSET = {'Rectangle': 'Rectangle', 'RoundedRectangle': 'RoundedRectangle', 'Circle': 'Circle', 'Capsule': 'Capsule', 'Ellipse': 'Ellipse', 'UnevenRoundedRectangle': 'UnevenRoundedRectangle'}
for p in ['swiftui/rectangle','swiftui/roundedrectangle','swiftui/circle','swiftui/capsule','swiftui/ellipse','swiftui/unevenroundedrectangle']:
    n = nm(p)
    S.append(emit_type(p, ctx='self:View,Shape,InsettableShape') + f"""extension {n}: InsettableShape {{
    // shim: Apple documents path(in:) and inset(by:) only on the Shape / InsettableShape pages; these are the witnesses
    public func path(in rect: CGRect) -> Path {{ fatalError() }}
    // shim: see path(in:)
    public func inset(by amount: CGFloat) -> {INSET[n]} {{ fatalError() }}
}}
""")
S.append(emit_type('swiftui/path', ctx='self:View,Shape') + '// shim: Apple documents Shape.path(in:) only on the Shape page; this is the witness\nextension Path: Shape {\n    // shim: see above\n    public func path(in rect: CGRect) -> Path { fatalError() }\n}\n')
S.append(emit_ext('swiftui/shape', 'Shape', ctx='self:View,Shape',
    skip_paths=( 'SwiftUI/Shape/path(in:)','SwiftUI/Shape/role','SwiftUI/Shape/layoutDirectionBehavior','SwiftUI/Shape/sizeThatFits(_:)')))
S.append(emit_ext('swiftui/insettableshape', 'InsettableShape', ctx='self:View,Shape,InsettableShape', skip_paths=('SwiftUI/InsettableShape/inset(by:)','SwiftUI/InsettableShape/InsetShape')))
S.append(emit_ext('swiftui/shapestyle', 'ShapeStyle', skip_paths=('SwiftUI/ShapeStyle/resolve(in:)',)))
write('Gen_Shapes.swift', S)

# ---- gestures, toolbar, layout
G = []
G.append(emit_type('swiftui/spatialtapgesture', header='public struct SpatialTapGesture') + 'extension SpatialTapGesture: _PrimitiveGesture {}\n')
G.append(emit_ext('swiftui/gesture', 'Gesture', skip_paths=('SwiftUI/Gesture/Value','SwiftUI/Gesture/Body-swift.associatedtype','SwiftUI/Gesture/body-swift.property')))
G.append(emit_type('swiftui/buttonstyleconfiguration') + '// shim: the label of a button style is a View (Apple: ButtonStyleConfiguration.Label)\nextension ButtonStyleConfiguration.Label: _PrimitiveView {}\n')
G.append(emit_type('swiftui/toolbaritem', conf=[]) + 'extension ToolbarItem: _PrimitiveToolbarContent where Content: View {}\n')
G.append(emit_type('swiftui/toolbaritemgroup') + 'extension ToolbarItemGroup: _PrimitiveToolbarContent where Content: View {}\n')
G.append(emit_type('swiftui/anylayout') + 'extension AnyLayout: Layout {\n    // shim: Layout witnesses\n    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize { fatalError() }\n    // shim: Layout witnesses\n    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) { fatalError() }\n}\n')
for p in ('swiftui/hstacklayout','swiftui/vstacklayout'):
    G.append(emit_type(p) + f'extension {nm(p)}: Layout {{\n    // shim: Layout witnesses\n    public func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize {{ fatalError() }}\n    // shim: Layout witnesses\n    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) {{ fatalError() }}\n}}\n')
G.append(emit_ext('swiftui/layout', 'Layout', skip_paths=('SwiftUI/Layout/Cache','SwiftUI/Layout/Subviews','SwiftUI/Layout/sizeThatFits(proposal:subviews:cache:)','SwiftUI/Layout/placeSubviews(in:proposal:subviews:cache:)')))
write('Gen_Misc.swift', G)

G.append(emit_ext('swiftui/timelineschedule', 'TimelineSchedule', skip_paths=('SwiftUI/TimelineSchedule/Entries','SwiftUI/TimelineSchedule/Mode','SwiftUI/TimelineSchedule/entries(from:mode:)')))
for p in ('swiftui/animationtimelineschedule', 'swiftui/everyminutetimelineschedule', 'swiftui/periodictimelineschedule', 'swiftui/explicittimelineschedule'):
    n = nm(p)
    G.append(emit_type(p, skip=(docs.page_path(docs.fetch(p)) + '/Entries', docs.page_path(docs.fetch(p)) + '/entries')) + f'''extension {n}: TimelineSchedule {{
    // shim: witnesses; Apple documents entries(from:mode:) only on the TimelineSchedule page
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {{ fatalError() }}
}}
''')
write('Gen_Misc.swift', G)

# ---- list / picker styles (the protocols are hand-written in Protocols.swift; styles and their static members are generated)
ST = []
for p in ['swiftui/plainliststyle','swiftui/insetgroupedliststyle','swiftui/groupedliststyle','swiftui/insetliststyle','swiftui/sidebarliststyle']:
    ST.append(emit_type(p) + f'extension {nm(p)}: ListStyle {{}}\n')
ST.append(emit_ext('swiftui/liststyle', 'ListStyle'))
for p in ['swiftui/defaultpickerstyle','swiftui/inlinepickerstyle','swiftui/menupickerstyle','swiftui/navigationlinkpickerstyle','swiftui/palettepickerstyle','swiftui/segmentedpickerstyle','swiftui/wheelpickerstyle']:
    ST.append(emit_type(p) + f'extension {nm(p)}: PickerStyle {{}}\n')
ST.append(emit_ext('swiftui/pickerstyle', 'PickerStyle'))
write('Gen_Styles.swift', ST)

# ---- view modifiers
MODS = "environment accessibilityAction accessibilityAddTraits accessibilityChildren accessibilityElement accessibilityHidden accessibilityHint accessibilityLabel accessibilityValue alert allowsHitTesting animation autocorrectionDisabled background bold brightness buttonStyle clipShape clipped colorScheme confirmationDialog contentShape contextMenu disabled dynamicTypeSize environment fixedSize focused font foregroundStyle frame fullScreenCover gesture glassEffect hidden id ignoresSafeArea interactiveDismissDisabled keyboardType labelsHidden layoutPriority lineLimit listRowBackground listRowInsets listRowSeparator listStyle minimumScaleFactor modifier monospacedDigit multilineTextAlignment navigationBarTitleDisplayMode navigationDestination navigationTitle offset onAppear onChange onDisappear onSubmit onTapGesture opacity overlay padding pickerStyle position preferredColorScheme presentationBackground presentationCornerRadius presentationDetents presentationDragIndicator rotationEffect safeAreaInset scaleEffect scrollBounceBehavior scrollContentBackground scrollDismissesKeyboard scrollIndicators searchable sensoryFeedback shadow sheet submitLabel swipeActions tag task textInputAutocapitalization tint toolbar tracking transition".split()
VIEWNAMES = set(n.lower() for n in MODS)
M = [emit_ext('swiftui/view', 'View', names=VIEWNAMES, ctx='view-ext')]
write('Gen_ViewModifiers.swift', M)
