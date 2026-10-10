from mk import *
H = '''// SHIM of Apple's UIKit (the parts NexaFix Scan touches). Declarations are copied from Apple's documentation
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

'''
B = []
def add(s): B.append(s)
def cls(tag, header, paths, ctx='type', extra='', post=None):
    add(f'\n// doc: {tag}\n{header} {{\n{extra}')
    add(emit_members(paths, ctx, cls_open=(' class ' in header)))
    add('}')
def cases(paths, indent='    '):
    lines = [l.strip() for l in emit_members(paths, indent='').split('\n') if l.strip()]
    add('\n'.join(indent + l for l in lines))
def req(s): return s.replace('public init?(coder: NSCoder)', 'public required init?(coder: NSCoder)')

# ---- responder, view, window
add('''// doc: UIKit/UIResponder
@MainActor @preconcurrency open class UIResponder: NSObject {
    // shim: designated init
    public override init() { super.init() }''')
add(emit_members(['uikit/uiresponder/touchesbegan(_:with:)','uikit/uiresponder/touchesmoved(_:with:)','uikit/uiresponder/touchesended(_:with:)','uikit/uiresponder/touchescancelled(_:with:)'], cls_open=True))
add('}')
add('''
// doc: UIKit/UIView
@MainActor @preconcurrency open class UIView: UIResponder, NSCoding {
    // shim: NSCoding.encode
    public func encode(with coder: NSCoder) { fatalError() }''')
add(req(emit_members(['uikit/uiview/init(frame:)','uikit/uiview/init(coder:)','uikit/uiview/init()','uikit/uiview/backgroundcolor','uikit/uiview/ismultipletouchenabled','uikit/uiview/isuserinteractionenabled',
  'uikit/uiview/addgesturerecognizer(_:)','uikit/uiview/addsubview(_:)','uikit/uiview/autoresizingmask-swift.property','uikit/uiview/bounds','uikit/uiview/frame','uikit/uiview/window','uikit/uiview/didmovetowindow()'], cls_open=True).replace('public convenience init() { fatalError() }','public convenience override init() { fatalError() }')))
add('''    // doc-unconfirmed: member of the NSObject UIAccessibility category (UIAccessibilityProtocol); no page is reachable in the docs data
    public var isAccessibilityElement: Bool { get { fatalError() } set { } }
    // doc-unconfirmed: member of the NSObject UIAccessibility category (UIAccessibilityProtocol); no page is reachable in the docs data
    public var accessibilityElementsHidden: Bool { get { fatalError() } set { } }
}
extension UIView {
    // doc: UIKit/UIView/AutoresizingMask-swift.struct
    public struct AutoresizingMask: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt''')
add(emit_members(['uikit/uiview/autoresizingmask-swift.struct/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members([f'uikit/uiview/autoresizingmask-swift.struct/{n}' for n in ['flexibleleftmargin','flexiblewidth','flexiblerightmargin','flexibletopmargin','flexibleheight','flexiblebottommargin']], indent='        ').replace('{ fatalError() }','{ AutoresizingMask(rawValue: 0) }'))
add('    }\n}')
cls('UIKit/UIWindow', '@MainActor @preconcurrency open class UIWindow: UIView', [], extra='    // shim: designated init required by the subclass chain\n    public override init(frame: CGRect) { fatalError() }\n    public required init?(coder: NSCoder) { fatalError() }\n')

# ---- view controller + activity
cls('UIKit/UIViewController', '@MainActor @preconcurrency open class UIViewController: UIResponder, NSCoding',
    ['uikit/uiviewcontroller/init(coder:)','uikit/uiviewcontroller/init(nibname:bundle:)','uikit/uiviewcontroller/loadview()','uikit/uiviewcontroller/popoverpresentationcontroller','uikit/uiviewcontroller/present(_:animated:completion:)','uikit/uiviewcontroller/view','uikit/uiviewcontroller/viewifloaded'],
    extra='    // shim: NSCoding.encode and the no-argument init the app calls through the nib initialiser\n    public func encode(with coder: NSCoder) { fatalError() }\n    public convenience override init() { fatalError() }\n')
B[-2] = req(B[-2]).replace('public init(nibName','public init(nibName')
cls('UIKit/UIActivityViewController', '@preconcurrency open class UIActivityViewController: UIViewController',
    ['uikit/uiactivityviewcontroller/init(activityitems:applicationactivities:)','uikit/uiactivityviewcontroller/completionwithitemshandler-swift.property','uikit/uiactivityviewcontroller/completionwithitemshandler-swift.typealias'],
    extra='    // shim: inherited designated inits\n    public required init?(coder: NSCoder) { fatalError() }\n    public override init(nibName: String?, bundle: Bundle?) { fatalError() }\n')
add('''
// doc: UIKit/UIActivity
open class UIActivity: NSObject {
    // doc: UIKit/UIActivity/ActivityType-swift.struct
    public struct ActivityType: Hashable, RawRepresentable, Sendable {
        // shim: RawRepresentable storage
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}
// doc: UIKit/UIPopoverPresentationController
@MainActor @preconcurrency open class UIPopoverPresentationController: NSObject {''')
add(emit_members(['uikit/uipopoverpresentationcontroller/sourceview','uikit/uipopoverpresentationcontroller/sourcerect','uikit/uipopoverpresentationcontroller/permittedarrowdirections']))
add('}')
add('''// doc: UIKit/UIPopoverArrowDirection
public struct UIPopoverArrowDirection: OptionSet, Sendable {
    // shim: OptionSet storage''')
add('    public let rawValue: UInt')
add(emit_members(['uikit/uipopoverarrowdirection/init(rawvalue:)']).replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members([f'uikit/uipopoverarrowdirection/{n}' for n in ['up','down','left','right','any','unknown']]).replace('{ fatalError() }','{ UIPopoverArrowDirection(rawValue: 0) }'))
add('}')

# ---- colour, traits, enums
cls('UIKit/UIColor', 'open class UIColor: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable',
    ['uikit/uicolor/init(red:green:blue:alpha:)','uikit/uicolor/init(dynamicprovider:)','uikit/uicolor/init(white:alpha:)','uikit/uicolor/resolvedcolor(with:)','uikit/uicolor/getred(_:green:blue:alpha:)','uikit/uicolor/black','uikit/uicolor/clear','uikit/uicolor/white','uikit/uicolor/systemblue'],
    extra='    // shim: NSSecureCoding / NSCopying requirements\n    public static var supportsSecureCoding: Bool { true }\n    public func encode(with coder: NSCoder) { fatalError() }\n    public required init?(coder: NSCoder) { fatalError() }\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
cls('UIKit/UITraitCollection', 'open class UITraitCollection: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable',
    ['uikit/uitraitcollection/init(userinterfacestyle:)','uikit/uitraitcollection/userinterfacestyle','uikit/uitraitcollection/accessibilitycontrast'],
    extra='    // shim: NSSecureCoding / NSCopying requirements\n    public static var supportsSecureCoding: Bool { true }\n    public func encode(with coder: NSCoder) { fatalError() }\n    public required init?(coder: NSCoder) { fatalError() }\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
add('// doc: UIKit/UIUserInterfaceStyle\npublic enum UIUserInterfaceStyle: Int, Sendable {')
cases(['uikit/uiuserinterfacestyle/unspecified','uikit/uiuserinterfacestyle/light','uikit/uiuserinterfacestyle/dark'])
add('}\n// doc: UIKit/UIAccessibilityContrast\npublic enum UIAccessibilityContrast: Int, Sendable {')
cases(['uikit/uiaccessibilitycontrast/unspecified','uikit/uiaccessibilitycontrast/normal','uikit/uiaccessibilitycontrast/high'])
add('}\n// doc: UIKit/UIKeyboardType\npublic enum UIKeyboardType: Int, Sendable {')
cases([f'uikit/uikeyboardtype/{n}' for n in ['default','asciicapable','numbersandpunctuation','url','numberpad','phonepad','namephonepad','emailaddress','decimalpad','twitter','websearch','asciicapablenumberpad']])
add(emit_members(['uikit/uikeyboardtype/alphabet']))
add('}\n// doc: UIKit/UIInterfaceOrientation\npublic enum UIInterfaceOrientation: Int, Sendable {')
cases(['uikit/uiinterfaceorientation/unknown','uikit/uiinterfaceorientation/portrait','uikit/uiinterfaceorientation/portraitupsidedown','uikit/uiinterfaceorientation/landscapeleft','uikit/uiinterfaceorientation/landscaperight'])
add(emit_members(['uikit/uiinterfaceorientation/islandscape','uikit/uiinterfaceorientation/isportrait']))
add('}')

# ---- gestures, touches, events
cls('UIKit/UIGestureRecognizer', '@MainActor @preconcurrency open class UIGestureRecognizer: NSObject',
    ['uikit/uigesturerecognizer/init(target:action:)','uikit/uigesturerecognizer/cancelstouchesinview','uikit/uigesturerecognizer/delaystouchesended','uikit/uigesturerecognizer/delegate','uikit/uigesturerecognizer/isenabled','uikit/uigesturerecognizer/location(in:)','uikit/uigesturerecognizer/state-swift.property','uikit/uigesturerecognizer/view'])
add('extension UIGestureRecognizer {\n    // doc: UIKit/UIGestureRecognizer/State-swift.enum\n    public enum State: Int, Sendable {')
cases(['uikit/uigesturerecognizer/state-swift.enum/possible','uikit/uigesturerecognizer/state-swift.enum/began','uikit/uigesturerecognizer/state-swift.enum/changed','uikit/uigesturerecognizer/state-swift.enum/ended','uikit/uigesturerecognizer/state-swift.enum/cancelled','uikit/uigesturerecognizer/state-swift.enum/failed'], '        ')
add(emit_members(['uikit/uigesturerecognizer/state-swift.enum/recognized'], indent='        '))
add('    }\n}')
cls('UIKit/UITapGestureRecognizer', '@MainActor @preconcurrency open class UITapGestureRecognizer: UIGestureRecognizer', ['uikit/uitapgesturerecognizer/numberoftapsrequired','uikit/uitapgesturerecognizer/numberoftouchesrequired'])
cls('UIKit/UIPanGestureRecognizer', '@MainActor @preconcurrency open class UIPanGestureRecognizer: UIGestureRecognizer', ['uikit/uipangesturerecognizer/minimumnumberoftouches','uikit/uipangesturerecognizer/maximumnumberoftouches','uikit/uipangesturerecognizer/translation(in:)','uikit/uipangesturerecognizer/settranslation(_:in:)','uikit/uipangesturerecognizer/velocity(in:)'])
cls('UIKit/UIPinchGestureRecognizer', '@MainActor @preconcurrency open class UIPinchGestureRecognizer: UIGestureRecognizer', ['uikit/uipinchgesturerecognizer/scale','uikit/uipinchgesturerecognizer/velocity'])
add('''
// doc: UIKit/UIGestureRecognizerDelegate
@MainActor @preconcurrency @objc public protocol UIGestureRecognizerDelegate: ObjectiveC.NSObjectProtocol {''')
add(emit_members(['uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldrecognizesimultaneouslywith:)','uikit/uigesturerecognizerdelegate/gesturerecognizershouldbegin(_:)','uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldreceive:)-16fuh'],'protocol').replace('    optional','    @objc optional'))
add('}')
cls('UIKit/UITouch', '@MainActor @preconcurrency open class UITouch: NSObject', ['uikit/uitouch/location(in:)-8rd36','uikit/uitouch/timestamp'])
cls('UIKit/UIEvent', '@MainActor @preconcurrency open class UIEvent: NSObject', ['uikit/uievent/timestamp'])

# ---- application, scenes, accessibility
cls('UIKit/UIApplication', '@MainActor @preconcurrency open class UIApplication: UIResponder',
    ['uikit/uiapplication/shared','uikit/uiapplication/connectedscenes','uikit/uiapplication/isidletimerdisabled','uikit/uiapplication/open(_:options:completionhandler:)','uikit/uiapplication/opensettingsurlstring'],
    extra='')
add('extension UIApplication {\n    // doc: UIKit/UIApplication/OpenExternalURLOptionsKey\n    public struct OpenExternalURLOptionsKey: Hashable, RawRepresentable, Sendable {\n        // shim: RawRepresentable storage\n        public let rawValue: String\n        public init(rawValue: String) { self.rawValue = rawValue }\n    }\n}')
cls('UIKit/UIScene', '@MainActor @preconcurrency open class UIScene: UIResponder', ['uikit/uiscene/activationstate-swift.property'])
add('extension UIScene {\n    // doc: UIKit/UIScene/ActivationState-swift.enum\n    public enum ActivationState: Int, Sendable {')
cases(['uikit/uiscene/activationstate-swift.enum/unattached','uikit/uiscene/activationstate-swift.enum/foregroundinactive','uikit/uiscene/activationstate-swift.enum/foregroundactive','uikit/uiscene/activationstate-swift.enum/background'], '        ')
add('    }\n}')
cls('UIKit/UIWindowScene', '@MainActor @preconcurrency open class UIWindowScene: UIScene', ['uikit/uiwindowscene/interfaceorientation'])
add('''
// doc: UIKit/UIAccessibility
public struct UIAccessibility {
    // doc: UIKit/UIAccessibility/Notification
    public struct Notification: Hashable, RawRepresentable, Sendable {
        // shim: RawRepresentable storage
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }''')
add(emit_members(['uikit/uiaccessibility/notification/announcement'], indent='        ').replace('{ fatalError() }','{ Notification(rawValue: 0) }'))
add('    }')
add(emit_members(['uikit/uiaccessibility/isvoiceoverrunning','uikit/uiaccessibility/post(notification:argument:)']).replace('@MainActor public static', '@MainActor @preconcurrency public static'))
add('}')

# ---- feedback generators
cls('UIKit/UIFeedbackGenerator', '@MainActor @preconcurrency open class UIFeedbackGenerator: NSObject', ['uikit/uifeedbackgenerator/init()','uikit/uifeedbackgenerator/prepare()'])
B[-2] = B[-2].replace('public init() { fatalError() }','public override init() { fatalError() }')
cls('UIKit/UIImpactFeedbackGenerator', '@MainActor @preconcurrency open class UIImpactFeedbackGenerator: UIFeedbackGenerator', ['uikit/uiimpactfeedbackgenerator/init(style:)','uikit/uiimpactfeedbackgenerator/impactoccurred()'])
add('extension UIImpactFeedbackGenerator {\n    // doc: UIKit/UIImpactFeedbackGenerator/FeedbackStyle\n    public enum FeedbackStyle: Int, Sendable {')
cases([f'uikit/uiimpactfeedbackgenerator/feedbackstyle/{n}' for n in ['heavy','light','medium','rigid','soft']], '        ')
add('    }\n}')
cls('UIKit/UINotificationFeedbackGenerator', '@MainActor @preconcurrency open class UINotificationFeedbackGenerator: UIFeedbackGenerator', ['uikit/uinotificationfeedbackgenerator/notificationoccurred(_:)'])
add('extension UINotificationFeedbackGenerator {\n    // doc: UIKit/UINotificationFeedbackGenerator/FeedbackType\n    public enum FeedbackType: Int, Sendable {')
cases([f'uikit/uinotificationfeedbackgenerator/feedbacktype/{n}' for n in ['error','success','warning']], '        ')
add('    }\n}')
cls('UIKit/UISelectionFeedbackGenerator', '@MainActor @preconcurrency open class UISelectionFeedbackGenerator: UIFeedbackGenerator', ['uikit/uiselectionfeedbackgenerator/selectionchanged()'])
open(SHIMS + 'UIKit/UIKit.swift','w').write(H + '\n'.join(B) + '\n')

# OBJC_POST: classes in the shims are Swift classes rooted in Linux Foundation's NSObject, which the compiler does not
# treat as Objective-C; mark them @objc so they can appear in @objc protocol signatures like on iOS.
import re as _re, glob as _g
for _p in [SHIMS + 'UIKit/UIKit.swift']:
    _t = open(_p).read()
    _t = _re.sub(r'^((?:@MainActor @preconcurrency )?)(public|open) class ', lambda m: m.group(1) + '@objc ' + m.group(2) + ' class ', _t, flags=_re.M)
    _t = finalize(_t)
    open(_p, 'w').write(_t)
