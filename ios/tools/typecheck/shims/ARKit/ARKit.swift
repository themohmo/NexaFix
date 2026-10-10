// SHIM of Apple's ARKit (the parts NexaFix Scan touches). Declarations are copied from Apple's documentation
// (ARKit pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks. Bodies are
// `fatalError()`: this is for type checking only and is never run.
@_exported import Foundation
@_exported import simd
import UIKit
import AVFoundation

// shim: the ObjC typedef `dispatch_queue_t` as the Dispatch overlay exposes it to Swift (ARSession.delegateQueue)
public typealias dispatch_queue_t = DispatchQueue

// doc: ARKit/ARSession
@objc open class ARSession: NSObject {
    // shim: ARSession() is NSObject.init(), declared here because shim classes need a designated init
    public override init() { super.init() }

    // doc: ARKit/ARSession/run(_:options:)
    open func run(_ configuration: ARConfiguration, options: ARSession.RunOptions = []) { fatalError() }
    // doc: ARKit/ARSession/pause()
    open func pause() { fatalError() }
    // doc: ARKit/ARSession/delegate
    open var delegate: (any ARSessionDelegate)? { get { fatalError() } set { } }
    // doc: ARKit/ARSession/delegateQueue
    open var delegateQueue: dispatch_queue_t? { get { fatalError() } set { } }
    // doc: ARKit/ARSession/currentFrame
    open var currentFrame: ARFrame? { fatalError() }
    // doc: ARKit/ARSession/identifier
    open var identifier: UUID { fatalError() }
    // doc: ARKit/ARSession/configuration
    open var configuration: ARConfiguration? { fatalError() }
    // doc: ARKit/ARSession/add(anchor:)
    open func add(anchor: ARAnchor) { fatalError() }
    // doc: ARKit/ARSession/remove(anchor:)
    open func remove(anchor: ARAnchor) { fatalError() }
    // doc: ARKit/ARSession/getCurrentWorldMap(completionHandler:)#0
    open func getCurrentWorldMap(completionHandler: @escaping @Sendable (ARWorldMap?, (any Error)?) -> Void) { fatalError() }
    // doc: ARKit/ARSession/getCurrentWorldMap(completionHandler:)#1
    open func currentWorldMap() async throws -> ARWorldMap { fatalError() }
    // doc: ARKit/ARSession/raycast(_:)
    open func raycast(_ query: ARRaycastQuery) -> [ARRaycastResult] { fatalError() }
    // doc: ARKit/ARSession/setWorldOrigin(relativeTransform:)
    open func setWorldOrigin(relativeTransform: simd_float4x4) { fatalError() }
}
extension ARSession {
    // doc: ARKit/ARSession/RunOptions
    public struct RunOptions: OptionSet, Sendable {
        // shim: OptionSet storage; the documented init(rawValue:) below sets it
        public let rawValue: UInt
        // doc: ARKit/ARSession/RunOptions/init(rawValue:)
        public init(rawValue: UInt) { self.rawValue = rawValue }
        // doc: ARKit/ARSession/RunOptions/resetTracking
        public static var resetTracking: ARSession.RunOptions { RunOptions(rawValue: 0) }
        // doc: ARKit/ARSession/RunOptions/removeExistingAnchors
        public static var removeExistingAnchors: ARSession.RunOptions { RunOptions(rawValue: 0) }
        // doc: ARKit/ARSession/RunOptions/stopTrackedRaycasts
        public static var stopTrackedRaycasts: ARSession.RunOptions { RunOptions(rawValue: 0) }
        // doc: ARKit/ARSession/RunOptions/resetSceneReconstruction
        public static var resetSceneReconstruction: ARSession.RunOptions { RunOptions(rawValue: 0) }
    }
}

// doc: ARKit/ARSessionObserver
@objc public protocol ARSessionObserver: ObjectiveC.NSObjectProtocol {
    // doc: ARKit/ARSessionObserver/session(_:cameraDidChangeTrackingState:)
    @objc optional func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera)
    // doc: ARKit/ARSessionObserver/sessionWasInterrupted(_:)
    @objc optional func sessionWasInterrupted(_ session: ARSession)
    // doc: ARKit/ARSessionObserver/sessionInterruptionEnded(_:)
    @objc optional func sessionInterruptionEnded(_ session: ARSession)
    // doc: ARKit/ARSessionObserver/sessionShouldAttemptRelocalization(_:)
    @objc optional func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool
    // doc: ARKit/ARSessionObserver/session(_:didFailWithError:)
    @objc optional func session(_ session: ARSession, didFailWithError error: any Error)
}

// doc: ARKit/ARSessionDelegate
@objc public protocol ARSessionDelegate: ARSessionObserver {
    // doc: ARKit/ARSessionDelegate/session(_:didUpdate:)-9v2kw
    @objc(session:didUpdateFrame:) optional func session(_ session: ARSession, didUpdate frame: ARFrame)
    // doc: ARKit/ARSessionDelegate/session(_:didAdd:)
    @objc optional func session(_ session: ARSession, didAdd anchors: [ARAnchor])
    // doc: ARKit/ARSessionDelegate/session(_:didUpdate:)-3qtt8
    @objc optional func session(_ session: ARSession, didUpdate anchors: [ARAnchor])
    // doc: ARKit/ARSessionDelegate/session(_:didRemove:)
    @objc optional func session(_ session: ARSession, didRemove anchors: [ARAnchor])
}

// doc: ARKit/ARConfiguration
@objc open class ARConfiguration: NSObject, NSCopying {
    // shim: NSCopying requirement and a designated init
    public override init() { super.init() }
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: ARKit/ARConfiguration/isSupported
    open class var isSupported: Bool { fatalError() }
    // doc: ARKit/ARConfiguration/worldAlignment-swift.property
    open var worldAlignment: ARConfiguration.WorldAlignment { get { fatalError() } set { } }
    // doc: ARKit/ARConfiguration/isLightEstimationEnabled
    open var isLightEstimationEnabled: Bool { get { fatalError() } set { } }
}
extension ARConfiguration {
    // doc: ARKit/ARConfiguration/SceneReconstruction
    public struct SceneReconstruction: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt
        // doc: ARKit/ARConfiguration/SceneReconstruction/init(rawValue:)
        public init(rawValue: UInt) { self.rawValue = rawValue }
        // doc: ARKit/ARConfiguration/SceneReconstruction/mesh
        public static var mesh: ARConfiguration.SceneReconstruction { SceneReconstruction(rawValue: 1) }
        // doc: ARKit/ARConfiguration/SceneReconstruction/meshWithClassification
        public static var meshWithClassification: ARConfiguration.SceneReconstruction { SceneReconstruction(rawValue: 1) }
    }
    // doc: ARKit/ARConfiguration/WorldAlignment-swift.enum
    public enum WorldAlignment: Int, Sendable {
        // doc: ARKit/ARConfiguration/WorldAlignment-swift.enum/gravity
        case gravity
        // doc: ARKit/ARConfiguration/WorldAlignment-swift.enum/gravityAndHeading
        case gravityAndHeading
        // doc: ARKit/ARConfiguration/WorldAlignment-swift.enum/camera
        case camera
    }
}

// doc: ARKit/ARWorldTrackingConfiguration
@objc open class ARWorldTrackingConfiguration: ARConfiguration {

    // doc: ARKit/ARWorldTrackingConfiguration/init()
    public override init() { fatalError() }
    // doc: ARKit/ARWorldTrackingConfiguration/initialWorldMap
    open var initialWorldMap: ARWorldMap? { get { fatalError() } set { } }
    // doc: ARKit/ARWorldTrackingConfiguration/planeDetection-swift.property
    open var planeDetection: ARWorldTrackingConfiguration.PlaneDetection { get { fatalError() } set { } }
    // doc: ARKit/ARWorldTrackingConfiguration/sceneReconstruction
    open var sceneReconstruction: ARConfiguration.SceneReconstruction { get { fatalError() } set { } }
    // doc: ARKit/ARWorldTrackingConfiguration/supportsSceneReconstruction(_:)
    open class func supportsSceneReconstruction(_ sceneReconstruction: ARConfiguration.SceneReconstruction) -> Bool { fatalError() }
}
extension ARWorldTrackingConfiguration {
    // doc: ARKit/ARWorldTrackingConfiguration/PlaneDetection-swift.struct
    public struct PlaneDetection: OptionSet, Sendable {
        // shim: OptionSet storage
        public let rawValue: UInt
        // doc: ARKit/ARWorldTrackingConfiguration/PlaneDetection-swift.struct/init(rawValue:)
        public init(rawValue: UInt) { self.rawValue = rawValue }
        // doc: ARKit/ARWorldTrackingConfiguration/PlaneDetection-swift.struct/horizontal
        public static var horizontal: ARWorldTrackingConfiguration.PlaneDetection { PlaneDetection(rawValue: 1) }
        // doc: ARKit/ARWorldTrackingConfiguration/PlaneDetection-swift.struct/vertical
        public static var vertical: ARWorldTrackingConfiguration.PlaneDetection { PlaneDetection(rawValue: 1) }
    }
}

// doc: ARKit/ARFrame
@objc open class ARFrame: NSObject {

    // doc: ARKit/ARFrame/camera
    open var camera: ARCamera { fatalError() }
    // doc: ARKit/ARFrame/timestamp
    open var timestamp: TimeInterval { fatalError() }
    // doc: ARKit/ARFrame/worldMappingStatus-swift.property
    open var worldMappingStatus: ARFrame.WorldMappingStatus { fatalError() }
}
extension ARFrame {
    // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum
    public enum WorldMappingStatus: Int, Sendable {
        // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum/extending
        case extending
        // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum/limited
        case limited
        // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum/mapped
        case mapped
        // doc: ARKit/ARFrame/WorldMappingStatus-swift.enum/notAvailable
        case notAvailable
    }
}

// doc: ARKit/ARCamera
@objc open class ARCamera: NSObject, NSCopying {
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: ARKit/ARCamera/trackingState-6i3pt
    open var trackingState: ARCamera.TrackingState { fatalError() }
    // doc: ARKit/ARCamera/transform
    open var transform: simd_float4x4 { fatalError() }
    // doc: ARKit/ARCamera/unprojectPoint(_:ontoPlane:orientation:viewportSize:)
    open func unprojectPoint(_ point: CGPoint, ontoPlane planeTransform: simd_float4x4, orientation: UIInterfaceOrientation, viewportSize: CGSize) -> simd_float3? { fatalError() }
}
extension ARCamera {
    // doc-unconfirmed: the Swift page for projectPoint(_:orientation:viewportSize:) is missing from the docs; the Objective-C page
    // (ARKit/ARCamera/projectPoint:orientation:viewportSize:) says introduced iOS 11.0, deprecated at 27.0 (not removed)
    public func projectPoint(_ point: simd_float3, orientation: UIInterfaceOrientation, viewportSize: CGSize) -> CGPoint { fatalError() }
    // doc: ARKit/ARCamera/TrackingState-swift.enum
    @frozen public enum TrackingState: Equatable, Sendable {
        // doc: ARKit/ARCamera/TrackingState-swift.enum/notAvailable
        case notAvailable
        // doc: ARKit/ARCamera/TrackingState-swift.enum/limited(_:)
        case limited(ARCamera.TrackingState.Reason)
        // doc: ARKit/ARCamera/TrackingState-swift.enum/normal
        case normal
        // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason
        public enum Reason: Equatable, Hashable, Sendable {
            // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason/initializing
            case initializing
            // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason/relocalizing
            case relocalizing
            // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason/excessiveMotion
            case excessiveMotion
            // doc: ARKit/ARCamera/TrackingState-swift.enum/Reason/insufficientFeatures
            case insufficientFeatures
        }
    }
}

// doc: ARKit/ARWorldMap
@objc open class ARWorldMap: NSObject, NSSecureCoding, NSCopying {
    // shim: NSSecureCoding / NSCopying requirements
    public static var supportsSecureCoding: Bool { true }
    // shim: NSCoding requirement
    public func encode(with coder: NSCoder) { fatalError() }
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: ARKit/ARWorldMap/anchors
    open var anchors: [ARAnchor] { get { fatalError() } set { } }
    // doc: ARKit/ARWorldMap/center
    open var center: simd_float3 { fatalError() }
    // doc: ARKit/ARWorldMap/extent
    open var extent: simd_float3 { fatalError() }
    // doc: ARKit/ARWorldMap/init(coder:)
    public required init?(coder: NSCoder) { fatalError() }
}

// doc: ARKit/ARAnchor
@objc open class ARAnchor: NSObject, NSSecureCoding, NSCopying {
    // shim: NSSecureCoding / NSCopying requirements
    public static var supportsSecureCoding: Bool { true }
    // shim: NSCoding requirement
    public func encode(with coder: NSCoder) { fatalError() }
    // shim: NSCopying requirement
    public func copy(with zone: NSZone? = nil) -> Any { fatalError() }

    // doc: ARKit/ARAnchor/init(transform:)
    public init(transform: simd_float4x4) { fatalError() }
    // doc: ARKit/ARAnchor/name
    open var name: String? { fatalError() }
    // doc: ARKit/ARAnchor/identifier
    open var identifier: UUID { fatalError() }
    // doc: ARKit/ARAnchor/transform
    open var transform: simd_float4x4 { fatalError() }
    // doc: ARKit/ARAnchor/init(coder:)
    public required init?(coder: NSCoder) { fatalError() }
}

// doc: ARKit/ARRaycastQuery
@objc open class ARRaycastQuery: NSObject {

    // doc: ARKit/ARRaycastQuery/init(origin:direction:allowing:alignment:)
    public init(origin: simd_float3, direction: simd_float3, allowing target: ARRaycastQuery.Target, alignment: ARRaycastQuery.TargetAlignment) { fatalError() }
    // doc: ARKit/ARRaycastQuery/origin
    open var origin: simd_float3 { fatalError() }
    // doc: ARKit/ARRaycastQuery/direction
    open var direction: simd_float3 { fatalError() }
}
extension ARRaycastQuery {
    // doc: ARKit/ARRaycastQuery/Target-swift.enum
    public enum Target: Int, Sendable {
        // doc: ARKit/ARRaycastQuery/Target-swift.enum/estimatedPlane
        case estimatedPlane
        // doc: ARKit/ARRaycastQuery/Target-swift.enum/existingPlaneGeometry
        case existingPlaneGeometry
        // doc: ARKit/ARRaycastQuery/Target-swift.enum/existingPlaneInfinite
        case existingPlaneInfinite
    }
    // doc: ARKit/ARRaycastQuery/TargetAlignment-swift.enum
    public enum TargetAlignment: Int, Sendable {
        // doc: ARKit/ARRaycastQuery/TargetAlignment-swift.enum/any
        case any
        // doc: ARKit/ARRaycastQuery/TargetAlignment-swift.enum/horizontal
        case horizontal
        // doc: ARKit/ARRaycastQuery/TargetAlignment-swift.enum/vertical
        case vertical
    }
}

// doc: ARKit/ARRaycastResult
@objc open class ARRaycastResult: NSObject {

    // doc: ARKit/ARRaycastResult/worldTransform
    open var worldTransform: simd_float4x4 { fatalError() }
    // doc: ARKit/ARRaycastResult/anchor
    open var anchor: ARAnchor? { fatalError() }
}

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
    public enum Code: Int, Equatable, Hashable, Sendable {
        // doc: ARKit/ARError/Code/requestFailed
        case requestFailed
        // doc: ARKit/ARError/Code/cameraUnauthorized
        case cameraUnauthorized
        // doc: ARKit/ARError/Code/fileIOFailed
        case fileIOFailed
        // doc: ARKit/ARError/Code/insufficientFeatures
        case insufficientFeatures
        // doc: ARKit/ARError/Code/invalidCollaborationData
        case invalidCollaborationData
        // doc: ARKit/ARError/Code/invalidConfiguration
        case invalidConfiguration
        // doc: ARKit/ARError/Code/invalidReferenceImage
        case invalidReferenceImage
        // doc: ARKit/ARError/Code/invalidReferenceObject
        case invalidReferenceObject
        // doc: ARKit/ARError/Code/invalidWorldMap
        case invalidWorldMap
        // doc: ARKit/ARError/Code/microphoneUnauthorized
        case microphoneUnauthorized
        // doc: ARKit/ARError/Code/objectMergeFailed
        case objectMergeFailed
        // doc: ARKit/ARError/Code/sensorFailed
        case sensorFailed
        // doc: ARKit/ARError/Code/sensorUnavailable
        case sensorUnavailable
        // doc: ARKit/ARError/Code/unsupportedConfiguration
        case unsupportedConfiguration
        // doc: ARKit/ARError/Code/worldTrackingFailed
        case worldTrackingFailed
        // doc: ARKit/ARError/Code/geoTrackingFailed
        case geoTrackingFailed
        // doc: ARKit/ARError/Code/geoTrackingNotAvailableAtLocation
        case geoTrackingNotAvailableAtLocation
        // doc: ARKit/ARError/Code/locationUnauthorized
        case locationUnauthorized
        // doc: ARKit/ARError/Code/highResolutionFrameCaptureFailed
        case highResolutionFrameCaptureFailed
        // doc: ARKit/ARError/Code/highResolutionFrameCaptureInProgress
        case highResolutionFrameCaptureInProgress
    }
}
