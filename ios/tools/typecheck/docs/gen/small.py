from mk import *
SH = SHIMS
import os
for m in ('ObjectiveC','QuartzCore','AVFoundation','Accessibility'): os.makedirs(SH + m, exist_ok=True)

# ---------------- ObjectiveC
open(SH + 'ObjectiveC/ObjectiveC.swift', 'w').write('''// SHIM of the part of Apple's ObjectiveC module that Swift code needs for selectors. NSObject comes from the Linux
// Foundation, which provides it. On Apple platforms Foundation re-exports ObjectiveC, so run.sh imports this module into
// every file implicitly (-import-module). The reverse is NOT true (ObjectiveC does not re-export Foundation), so this module
// imports Foundation without re-exporting it: a file that forgets `import Foundation` must not get it through here.
import Foundation

// doc: ObjectiveC/NSObjectProtocol
@objc public protocol NSObjectProtocol {}
// shim: Foundation on Linux defines its own, non-@objc NSObjectProtocol; every ObjC protocol in the shims refines THIS one
// (written ObjectiveC.NSObjectProtocol) so that `@objc protocol` refinement and `optional` requirements type-check
extension NSObject: ObjectiveC.NSObjectProtocol {}

// doc: ObjectiveC/Selector
public struct Selector: ExpressibleByStringLiteral, Hashable, Sendable {
    // shim: storage
    public let name: String
''' + emit_members(['objectivec/selector/init(_:)']).replace('{ fatalError() }','{ name = str }') + '''
    // shim: lets `#selector(...)` and string literals build a Selector
    public init(stringLiteral value: String) { name = value }
}
''')

# ---------------- QuartzCore
open(SH + 'QuartzCore/QuartzCore.swift', 'w').write('''// SHIM of the part of Apple's QuartzCore the app touches (CADisplayLink). Declarations copied from the docs.
@_exported import Foundation

// shim: CFTimeInterval is a CoreFoundation typealias that Foundation re-exports on Apple platforms
public typealias CFTimeInterval = Double

// doc: QuartzCore/CADisplayLink
public class CADisplayLink: NSObject {
''' + emit_members(['quartzcore/cadisplaylink/init(target:selector:)','quartzcore/cadisplaylink/add(to:formode:)','quartzcore/cadisplaylink/invalidate()','quartzcore/cadisplaylink/timestamp','quartzcore/cadisplaylink/targettimestamp','quartzcore/cadisplaylink/ispaused','quartzcore/cadisplaylink/duration']) + '''
}
''')

# ---------------- AVFoundation
open(SH + 'AVFoundation/AVFoundation.swift', 'w').write('''// SHIM of the part of Apple's AVFoundation the app touches (camera permission). Declarations copied from the docs.
@_exported import Foundation

// doc: AVFoundation/AVMediaType
public struct AVMediaType: Hashable, RawRepresentable, Sendable {
    // shim: RawRepresentable storage
    public let rawValue: String
''' + emit_members(['avfoundation/avmediatype/init(rawvalue:)']).replace('{ fatalError() }','{ self.rawValue = rawValue }') + '\n' + emit_members(['avfoundation/avmediatype/video','avfoundation/avmediatype/audio']).replace('{ fatalError() }','{ AVMediaType(rawValue: "") }') + '''
}

// doc: AVFoundation/AVAuthorizationStatus
public enum AVAuthorizationStatus: Int, Sendable {
''' + '\n'.join('    ' + l.strip() for l in emit_members([f'avfoundation/avauthorizationstatus/{n}' for n in ['notdetermined','restricted','denied','authorized']], indent='').split('\n')) + '''
}

// doc: AVFoundation/AVCaptureDevice
public class AVCaptureDevice: NSObject {
''' + emit_members(['avfoundation/avcapturedevice/authorizationstatus(for:)','avfoundation/avcapturedevice/requestaccess(for:completionhandler:)']).replace('public class func','public class func') + '''
}
''')

# ---------------- Accessibility
open(SH + 'Accessibility/Accessibility.swift', 'w').write('''// SHIM of the part of Apple's Accessibility framework the app touches (VoiceOver announcements).
@_exported import Foundation

// doc: Accessibility/AccessibilityNotification
public enum AccessibilityNotification {
    // doc: Accessibility/AccessibilityNotification/Announcement
    public struct Announcement {
''' + emit_members(['accessibility/accessibilitynotification/announcement/init(_:)-621va','accessibility/accessibilitynotification/announcement/init(_:)-btpf','accessibility/accessibilitynotification/announcement/post()'], indent='        ') + '''
    }
}
''')

# OBJC_POST: classes in the shims are Swift classes rooted in Linux Foundation's NSObject, which the compiler does not
# treat as Objective-C; mark them @objc so they can appear in @objc protocol signatures like on iOS.
import re as _re, glob as _g
for _p in _g.glob('' + SHIMS + '*/*.swift'):
    _t = open(_p).read()
    _t = _re.sub(r'^((?:@MainActor @preconcurrency )?)(public|open) class ', lambda m: m.group(1) + '@objc ' + m.group(2) + ' class ', _t, flags=_re.M)
    _t = finalize(_t)
    open(_p, 'w').write(_t)
