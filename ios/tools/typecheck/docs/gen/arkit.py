from mk import *
H = '''// SHIM of Apple's ARKit (the parts NexaFix Scan touches). Declarations are copied from Apple's documentation
// (ARKit pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks. Bodies are
// `fatalError()`: this is for type checking only and is never run.
@_exported import Foundation
@_exported import simd
import UIKit
import AVFoundation

// shim: the ObjC typedef `dispatch_queue_t` as the Dispatch overlay exposes it to Swift (ARSession.delegateQueue)
public typealias dispatch_queue_t = DispatchQueue
'''
B = []
def add(s): B.append(s)
def cls(tag, header, paths, ctx='type', extra=''):
    add(f'\n// doc: {tag}\n{header} {{\n{extra}')
    add(emit_members(paths, ctx, cls_open=(' class ' in header)))
    add('}')

# ---- ARSession
cls('ARKit/ARSession', 'open class ARSession: NSObject', [
 'arkit/arsession/run(_:options:)','arkit/arsession/pause()','arkit/arsession/delegate','arkit/arsession/delegateQueue',
 'arkit/arsession/currentFrame','arkit/arsession/identifier','arkit/arsession/configuration','arkit/arsession/add(anchor:)',
 'arkit/arsession/remove(anchor:)','arkit/arsession/getCurrentWorldMap(completionHandler:)','arkit/arsession/raycast(_:)',
 'arkit/arsession/setWorldOrigin(relativeTransform:)'],
 extra='    // shim: ARSession() is NSObject.init(), declared here because shim classes need a designated init\n    public override init() { super.init() }\n')
add('''extension ARSession {
    // doc: ARKit/ARSession/RunOptions
    public struct RunOptions: OptionSet, Sendable {
        // shim: OptionSet storage; the documented init(rawValue:) below sets it
        public let rawValue: UInt''')
add(emit_members(['arkit/arsession/runoptions/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members(['arkit/arsession/runoptions/resettracking','arkit/arsession/runoptions/removeexistinganchors','arkit/arsession/runoptions/stoptrackedraycasts','arkit/arsession/runoptions/resetscenereconstruction'], indent='        ').replace('{ fatalError() }','{ RunOptions(rawValue: 0) }'))
add('    }\n}')

# ---- delegates
add('''
// doc: ARKit/ARSessionObserver
@objc public protocol ARSessionObserver: ObjectiveC.NSObjectProtocol {''')
add(emit_members(['arkit/arsessionobserver/session(_:cameradidchangetrackingstate:)','arkit/arsessionobserver/sessionwasinterrupted(_:)',
  'arkit/arsessionobserver/sessioninterruptionended(_:)','arkit/arsessionobserver/sessionshouldattemptrelocalization(_:)',
  'arkit/arsessionobserver/session(_:didfailwitherror:)'], 'protocol').replace('    optional','    @objc optional'))
add('}')
add('''
// doc: ARKit/ARSessionDelegate
@objc public protocol ARSessionDelegate: ARSessionObserver {''')
add(emit_members(['arkit/arsessiondelegate/session(_:didupdate:)-9v2kw','arkit/arsessiondelegate/session(_:didadd:)','arkit/arsessiondelegate/session(_:didupdate:)-3qtt8','arkit/arsessiondelegate/session(_:didremove:)'],'protocol').replace('    optional','    @objc optional').replace('@objc optional func session(_ session: ARSession, didUpdate frame: ARFrame)','@objc(session:didUpdateFrame:) optional func session(_ session: ARSession, didUpdate frame: ARFrame)'))
add('}')

# ---- configuration
cls('ARKit/ARConfiguration', 'open class ARConfiguration: NSObject, NSCopying', ['arkit/arconfiguration/issupported','arkit/arconfiguration/worldalignment-swift.property','arkit/arconfiguration/islightestimationenabled'],
    extra='    // shim: NSCopying requirement and a designated init\n    public override init() { super.init() }\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
add('''extension ARConfiguration {
    // doc: ARKit/ARConfiguration/SceneReconstruction
    public struct SceneReconstruction: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt''')
add(emit_members(['arkit/arconfiguration/scenereconstruction/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members(['arkit/arconfiguration/scenereconstruction/mesh','arkit/arconfiguration/scenereconstruction/meshwithclassification'], indent='        ').replace('{ fatalError() }','{ SceneReconstruction(rawValue: 1) }'))
add('''    }
    // doc: ARKit/ARConfiguration/WorldAlignment-swift.enum
    public enum WorldAlignment: Int, Sendable {''')
B.append('        ' + '\n        '.join([l.strip() for l in emit_members(['arkit/arconfiguration/worldalignment-swift.enum/gravity','arkit/arconfiguration/worldalignment-swift.enum/gravityandheading','arkit/arconfiguration/worldalignment-swift.enum/camera']).split('\n')]))
add('    }\n}')
cls('ARKit/ARWorldTrackingConfiguration', 'open class ARWorldTrackingConfiguration: ARConfiguration', ['arkit/arworldtrackingconfiguration/init()','arkit/arworldtrackingconfiguration/initialworldmap','arkit/arworldtrackingconfiguration/planedetection-swift.property','arkit/arworldtrackingconfiguration/scenereconstruction','arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)'])
B[-2] = B[-2].replace('public init() { fatalError() }', 'public override init() { fatalError() }')
add('''extension ARWorldTrackingConfiguration {
    // doc: ARKit/ARWorldTrackingConfiguration/PlaneDetection-swift.struct
    public struct PlaneDetection: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt''')
add(emit_members(['arkit/arworldtrackingconfiguration/planedetection-swift.struct/init(rawvalue:)'], indent='        ').replace('{ fatalError() }','{ self.rawValue = rawValue }'))
add(emit_members(['arkit/arworldtrackingconfiguration/planedetection-swift.struct/horizontal','arkit/arworldtrackingconfiguration/planedetection-swift.struct/vertical'], indent='        ').replace('{ fatalError() }','{ PlaneDetection(rawValue: 1) }'))
add('    }\n}')

# ---- frame, camera
cls('ARKit/ARFrame', 'open class ARFrame: NSObject', ['arkit/arframe/camera','arkit/arframe/timestamp','arkit/arframe/worldmappingstatus-swift.property'])
add('''extension ARFrame {
    // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum
    public enum WorldMappingStatus: Int, Sendable {''')
B.append('        ' + '\n        '.join([l.strip() for l in emit_members(['arkit/arframe/worldmappingstatus-swift.enum/extending','arkit/arframe/worldmappingstatus-swift.enum/limited','arkit/arframe/worldmappingstatus-swift.enum/mapped','arkit/arframe/worldmappingstatus-swift.enum/notavailable']).split('\n')]))
add('    }\n}')
cls('ARKit/ARCamera', 'open class ARCamera: NSObject, NSCopying', ['arkit/arcamera/trackingstate-6i3pt','arkit/arcamera/transform','arkit/arcamera/unprojectpoint(_:ontoplane:orientation:viewportsize:)'],
    extra='    // shim: NSCopying requirement\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
add('''extension ARCamera {
    // doc-unconfirmed: the Swift page for projectPoint(_:orientation:viewportSize:) is missing from the docs; the Objective-C page
    // (ARKit/ARCamera/projectPoint:orientation:viewportSize:) says introduced iOS 11.0, deprecated at 27.0 (not removed)
    public func projectPoint(_ point: simd_float3, orientation: UIInterfaceOrientation, viewportSize: CGSize) -> CGPoint { fatalError() }
    // doc: ARKit/ARCamera/TrackingState-swift.enum
    @frozen public enum TrackingState: Equatable, Sendable {''')
B.append('        ' + '\n        '.join([l.strip() for l in emit_members(['arkit/arcamera/trackingstate-swift.enum/notavailable','arkit/arcamera/trackingstate-swift.enum/limited(_:)','arkit/arcamera/trackingstate-swift.enum/normal']).split('\n')]))
add('''        // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason
        public enum Reason: Equatable, Hashable, Sendable {''')
B.append('            ' + '\n            '.join([l.strip() for l in emit_members(['arkit/arcamera/trackingstate-swift.enum/reason/initializing','arkit/arcamera/trackingstate-swift.enum/reason/relocalizing','arkit/arcamera/trackingstate-swift.enum/reason/excessivemotion','arkit/arcamera/trackingstate-swift.enum/reason/insufficientfeatures']).split('\n')]))
add('        }\n    }\n}')

# ---- world map, anchor, raycast, error
cls('ARKit/ARWorldMap', 'open class ARWorldMap: NSObject, NSSecureCoding, NSCopying', ['arkit/arworldmap/anchors','arkit/arworldmap/center','arkit/arworldmap/extent','arkit/arworldmap/init(coder:)'],
    extra='    // shim: NSSecureCoding / NSCopying requirements\n    public static var supportsSecureCoding: Bool { true }\n    public func encode(with coder: NSCoder) { fatalError() }\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
B[-2] = B[-2].replace('public init?(coder: NSCoder)', 'public required init?(coder: NSCoder)')
cls('ARKit/ARAnchor', 'open class ARAnchor: NSObject, NSSecureCoding, NSCopying', ['arkit/aranchor/init(transform:)','arkit/aranchor/name','arkit/aranchor/identifier','arkit/aranchor/transform','arkit/aranchor/init(coder:)'],
    extra='    // shim: NSSecureCoding / NSCopying requirements\n    public static var supportsSecureCoding: Bool { true }\n    public func encode(with coder: NSCoder) { fatalError() }\n    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }\n')
B[-2] = B[-2].replace('public init?(coder: NSCoder)', 'public required init?(coder: NSCoder)')
cls('ARKit/ARRaycastQuery', 'open class ARRaycastQuery: NSObject', ['arkit/arraycastquery/init(origin:direction:allowing:alignment:)','arkit/arraycastquery/origin','arkit/arraycastquery/direction'])
add('''extension ARRaycastQuery {
    // doc: ARKit/ARRaycastQuery/Target-swift.enum
    public enum Target: Int, Sendable {''')
B.append('        ' + '\n        '.join([l.strip() for l in emit_members(['arkit/arraycastquery/target-swift.enum/estimatedplane','arkit/arraycastquery/target-swift.enum/existingplanegeometry','arkit/arraycastquery/target-swift.enum/existingplaneinfinite']).split('\n')]))
add('''    }
    // doc: ARKit/ARRaycastQuery/TargetAlignment-swift.enum
    public enum TargetAlignment: Int, Sendable {''')
B.append('        ' + '\n        '.join([l.strip() for l in emit_members(['arkit/arraycastquery/targetalignment-swift.enum/any','arkit/arraycastquery/targetalignment-swift.enum/horizontal','arkit/arraycastquery/targetalignment-swift.enum/vertical']).split('\n')]))
add('    }\n}')
cls('ARKit/ARRaycastResult', 'open class ARRaycastResult: NSObject', ['arkit/arraycastresult/worldtransform','arkit/arraycastresult/anchor'])

add('''
// doc: ARKit/ARError
public struct ARError: Error, Hashable, Sendable, CustomNSError {
    // shim: ARError is a value type wrapping its NSError code; stored so that `code` and CustomNSError work
    public let errorCode: Int
    // shim: CustomNSError requirement
    public var errorUserInfo: [String: Any] { [:] }
    // shim: memberwise init for the NSError bridge
    public init(_nsError: NSError) { errorCode = _nsError.code }
    // doc: ARKit/ARError/errorDomain
    public static var errorDomain: String { fatalError() }
    // doc-unconfirmed: ARError.code is not listed on the ARError page (Swift derives it for Error enums imported with NS_ERROR_ENUM)
    public var code: ARError.Code { fatalError() }
    // doc: ARKit/ARError/Code
    public enum Code: Int, Equatable, Hashable, Sendable {''')
names = ['requestfailed','cameraunauthorized','fileiofailed','insufficientfeatures','invalidcollaborationdata','invalidconfiguration','invalidreferenceimage','invalidreferenceobject','invalidworldmap','microphoneunauthorized','objectmergefailed','sensorfailed','sensorunavailable','unsupportedconfiguration','worldtrackingfailed','geotrackingfailed','geotrackingnotavailableatlocation','locationunauthorized','highresolutionframecapturefailed','highresolutionframecaptureinprogress']
B.append('        ' + '\n        '.join([l.strip() for l in emit_members([f'arkit/arerror/code/{n}' for n in names]).split('\n')]))
add('    }\n}')
open(SHIMS + 'ARKit/ARKit.swift','w').write(H + '\n'.join(B) + '\n')

# OBJC_POST: classes in the shims are Swift classes rooted in Linux Foundation's NSObject, which the compiler does not
# treat as Objective-C; mark them @objc so they can appear in @objc protocol signatures like on iOS.
import re as _re, glob as _g
for _p in [SHIMS + 'ARKit/ARKit.swift']:
    _t = open(_p).read()
    _t = _re.sub(r'^((?:@MainActor @preconcurrency )?)(public|open) class ', lambda m: m.group(1) + '@objc ' + m.group(2) + ' class ', _t, flags=_re.M)
    _t = finalize(_t)
    open(_p, 'w').write(_t)
