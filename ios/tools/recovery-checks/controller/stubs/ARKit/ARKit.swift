import Foundation
import simd
// Stand-ins for ARKit. Signatures copied from Apple's documentation pages (ARSession run(_:options:), configuration,
// delegate, ARSessionDelegate's four methods, ARSessionObserver, ARWorldTrackingConfiguration, ARError.Code).
// NOTE: on Apple platforms the delegate methods are @objc optional and are called with optional chaining
// (previous?.session?(...)); a protocol with default implementations stands in for that here, and controller/run.sh removes
// the `?(` from those lines in the staged copy.
public protocol ARSessionObserver: NSObjectProtocol {
    func session(_ session: ARSession, didFailWithError error: Error)
    func sessionWasInterrupted(_ session: ARSession)
    func sessionInterruptionEnded(_ session: ARSession)
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera)
}
public extension ARSessionObserver {
    func session(_ session: ARSession, didFailWithError error: Error) {}
    func sessionWasInterrupted(_ session: ARSession) {}
    func sessionInterruptionEnded(_ session: ARSession) {}
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {}
}
public class ARAnchor { public init() {} }
public protocol ARSessionDelegate: ARSessionObserver {
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor])
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor])
    func session(_ session: ARSession, didRemove anchors: [ARAnchor])
}
public extension ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {}
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {}
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {}
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {}
}
open class ARWorldMap: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    public func encode(with coder: NSCoder) {}
}
public struct ARError: Error, CustomNSError {
    public enum Code: Int { case requestFailed = 100, cameraUnauthorized = 103, fileIOFailed = 104, insufficientFeatures = 400, invalidConfiguration = 300, invalidWorldMap = 105, sensorFailed = 102, sensorUnavailable = 101, unsupportedConfiguration = 200, worldTrackingFailed = 2001 }
    public static var errorDomain: String { "ARErrorDomain" }
    public var errorCode: Int { code.rawValue }
    public var code: Code
    public init(_ code: Code) { self.code = code }
}
public class ARCamera {
    @frozen public enum TrackingState: Equatable {
        case notAvailable
        case limited(Reason)
        case normal
        public enum Reason: Equatable { case initializing, relocalizing, excessiveMotion, insufficientFeatures }
    }
    public var trackingState: TrackingState = .normal
    public init() {}
}
public class ARFrame {
    public enum WorldMappingStatus: Int { case notAvailable, limited, extending, mapped }
    public var camera = ARCamera()
    public var worldMappingStatus: WorldMappingStatus = .mapped
    public init() {}
}
open class ARConfiguration {
    public struct FrameSemantics: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let sceneDepth = FrameSemantics(rawValue: 1) }
    public struct SceneReconstruction: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let mesh = SceneReconstruction(rawValue: 1) }
    public var frameSemantics: FrameSemantics = []
    /// Test knob: what this device supports.
    nonisolated(unsafe) public static var deviceHasLiDAR = true
    public class func supportsFrameSemantics(_ frameSemantics: FrameSemantics) -> Bool { deviceHasLiDAR }
    public init() {}
}
open class ARWorldTrackingConfiguration: ARConfiguration {
    public var sceneReconstruction: ARConfiguration.SceneReconstruction = []
    public class func supportsSceneReconstruction(_ sceneReconstruction: ARConfiguration.SceneReconstruction) -> Bool { deviceHasLiDAR }
    public override init() { super.init() }
}
open class ARSession: NSObject {
    public struct RunOptions: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let resetTracking = RunOptions(rawValue: 1)
        public static let removeExistingAnchors = RunOptions(rawValue: 2) }
    public weak var delegate: ARSessionDelegate?
    public var currentFrame: ARFrame?
    public private(set) var configuration: ARConfiguration?
    // Test records.
    public var pauseCount = 0
    public var worldMapRequests = 0
    public var runCalls: [(configuration: ARConfiguration, options: RunOptions)] = []
    public override init() { super.init() }
    public func run(_ configuration: ARConfiguration, options: RunOptions = []) {
        runCalls.append((configuration, options))
        self.configuration = configuration
    }
    public func pause() { pauseCount += 1 }
    public func getCurrentWorldMap(completionHandler: @escaping @Sendable (ARWorldMap?, (any Error)?) -> Void) {
        worldMapRequests += 1
        completionHandler(ARWorldMap(), nil)
    }
}
