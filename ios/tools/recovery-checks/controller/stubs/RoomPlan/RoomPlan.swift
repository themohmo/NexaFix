import Foundation
import simd
import ARKit
import UIKit

// Stand-ins for RoomPlan, with signatures copied from Apple's documentation (the whole-app typecheck in
// ios/tools/typecheck has the full, documentation-verified shims; these are the few members the scan controller
// uses). Behaviour is invented only where a test needs to drive it.

public struct CapturedRoom: Codable, Sendable {
    public enum Confidence: Codable, Hashable, Sendable { case low, medium, high }

    public struct Surface: Codable, Sendable {
        public enum Category: Codable, Hashable, Sendable {
            case wall, door(isOpen: Bool), window, opening, floor
        }
        public enum Edge: Codable, Hashable, Sendable { case top, bottom, left, right }
        public struct Curve: Codable, Sendable {
            public var startAngle: Double, endAngle: Double, radius: Float
            public var center: simd_float2
            public init(startAngle: Double, endAngle: Double, radius: Float, center: simd_float2) {
                self.startAngle = startAngle; self.endAngle = endAngle; self.radius = radius; self.center = center
            }
        }
        public var identifier: UUID
        public var parentIdentifier: UUID?
        public var category: Category
        public var confidence: Confidence
        public var transform: simd_float4x4
        public var dimensions: simd_float3
        public var story: Int
        public var completedEdges: Set<Edge>
        public var curve: Curve?
        public var polygonCorners: [simd_float3]
        public init(identifier: UUID = UUID(), parentIdentifier: UUID? = nil, category: Category,
                    confidence: Confidence = .high, transform: simd_float4x4, dimensions: simd_float3,
                    story: Int = 0, completedEdges: Set<Edge> = [], curve: Curve? = nil,
                    polygonCorners: [simd_float3] = []) {
            self.identifier = identifier; self.parentIdentifier = parentIdentifier; self.category = category
            self.confidence = confidence; self.transform = transform; self.dimensions = dimensions
            self.story = story; self.completedEdges = completedEdges; self.curve = curve
            self.polygonCorners = polygonCorners
        }
    }

    public struct Object: Codable, Sendable {
        public enum Category: Codable, Hashable, Sendable, CaseIterable {
            case bathtub, bed, chair, dishwasher, fireplace, oven, refrigerator, sink, sofa, stairs
            case storage, stove, table, television, toilet, washerDryer
        }
        public var identifier: UUID
        public var parentIdentifier: UUID?
        public var category: Category
        public var confidence: Confidence
        public var transform: simd_float4x4
        public var dimensions: simd_float3
        public var story: Int
        public init(identifier: UUID = UUID(), parentIdentifier: UUID? = nil, category: Category,
                    confidence: Confidence = .high, transform: simd_float4x4, dimensions: simd_float3, story: Int = 0) {
            self.identifier = identifier; self.parentIdentifier = parentIdentifier; self.category = category
            self.confidence = confidence; self.transform = transform; self.dimensions = dimensions; self.story = story
        }
    }

    public enum Error: Swift.Error, LocalizedError, Hashable, Sendable {
        case deviceNotSupported, urlInvalidFileExtension, urlInvalidFilePath, urlInvalidScheme, urlMissingFileExtension
    }

    public struct USDExportOptions: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public static let parametric = USDExportOptions(rawValue: 1)
        public static let mesh = USDExportOptions(rawValue: 2)
        public static let model = USDExportOptions(rawValue: 4)
    }
    public struct ModelProvider: Sendable { public init() {} }

    public var identifier: UUID
    public var story: Int
    public var version: Int
    public var floors: [Surface]
    public var walls: [Surface]
    public var doors: [Surface]
    public var windows: [Surface]
    public var openings: [Surface]
    public var objects: [Object]

    public init(identifier: UUID = UUID(), story: Int = 0, floors: [Surface] = [], walls: [Surface] = [],
                doors: [Surface] = [], windows: [Surface] = [], openings: [Surface] = [], objects: [Object] = []) {
        self.identifier = identifier; self.story = story; self.version = 1; self.floors = floors; self.walls = walls
        self.doors = doors; self.windows = windows; self.openings = openings; self.objects = objects
    }

    public func export(to url: URL, exportOptions: USDExportOptions) throws {
        try export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: exportOptions)
    }
    public func export(to url: URL, metadataURL: URL? = nil, modelProvider: ModelProvider? = nil,
                       exportOptions: USDExportOptions) throws {
        guard !url.pathExtension.isEmpty else { throw Error.urlMissingFileExtension }
        try Data("usdz:\(identifier)".utf8).write(to: url)
    }
}

public struct CapturedRoomData: Codable, Sendable { public var serial: Int; public init(serial: Int = 0) { self.serial = serial } }

public struct CapturedStructure: Codable, Sendable {
    public typealias Surface = CapturedRoom.Surface
    public typealias USDExportOptions = CapturedRoom.USDExportOptions
    public typealias ModelProvider = CapturedRoom.ModelProvider
    public typealias Error = CapturedRoom.Error
    public var identifier = UUID()
    public var rooms: [CapturedRoom]
    public init(rooms: [CapturedRoom]) { self.rooms = rooms }
    public func export(to url: URL, metadataURL: URL? = nil, modelProvider: CapturedStructure.ModelProvider? = nil,
                       exportOptions: CapturedStructure.USDExportOptions = .mesh) throws {
        guard !url.pathExtension.isEmpty else { throw Error.urlMissingFileExtension }
        try Data("structure-usdz:\(rooms.count)".utf8).write(to: url)
    }
}

public class RoomBuilder {
    public struct ConfigurationOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let beautifyObjects = ConfigurationOptions(rawValue: 1)
    }
    public enum BuildError: Swift.Error, LocalizedError, Hashable, Sendable {
        case insufficientInput, invalidInput, exceedSceneSizeLimit, internalError, deviceNotSupported
    }
    /// Test hook: what the next `capturedRoom(from:)` returns or throws.
    nonisolated(unsafe) public static var nextResults: [Swift.Result<CapturedRoom, Swift.Error>] = []
    /// Test hook: the serial of every capture the builder was asked to process, in order.
    nonisolated(unsafe) public static var seenSerials: [Int] = []
    public init(options: ConfigurationOptions) {}
    public func capturedRoom(from capturedRoomData: CapturedRoomData) async throws -> CapturedRoom {
        RoomBuilder.seenSerials.append(capturedRoomData.serial)
        let next = RoomBuilder.nextResults.isEmpty ? .failure(BuildError.insufficientInput) : RoomBuilder.nextResults.removeFirst()
        return try next.get()
    }
}

public class StructureBuilder {
    public typealias ConfigurationOptions = RoomBuilder.ConfigurationOptions
    public enum BuildError: Swift.Error, LocalizedError, Hashable, Sendable {
        case deviceNotSupported, exceedSceneSizeLimit, insufficientInput, internalError, invalidInput, invalidRoomLocation
    }
    nonisolated(unsafe) public static var failWith: Swift.Error?
    public init(options: ConfigurationOptions) {}
    public func capturedStructure(from rooms: [CapturedRoom]) async throws -> CapturedStructure {
        if let e = StructureBuilder.failWith { throw e }
        return CapturedStructure(rooms: rooms)
    }
}

public protocol RoomCaptureSessionDelegate: AnyObject {
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration)
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom)
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom)
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom)
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom)
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction)
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?)
}
public extension RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {}
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {}
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {}
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {}
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {}
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {}
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {}
}

/// Stands in for RoomPlan's own object that may be the AR session's delegate.
public final class StubRoomPlanARDelegate: NSObject, ARSessionDelegate {
    public var frames = 0, anchorAdds = 0, anchorUpdates = 0, anchorRemoves = 0
    public var trackingChanges = 0, interruptions = 0, interruptionEnds = 0, failures = 0
    public func session(_ session: ARSession, didUpdate frame: ARFrame) { frames += 1 }
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { anchorAdds += 1 }
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { anchorUpdates += 1 }
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) { anchorRemoves += 1 }
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) { trackingChanges += 1 }
    public func sessionWasInterrupted(_ session: ARSession) { interruptions += 1 }
    public func sessionInterruptionEnded(_ session: ARSession) { interruptionEnds += 1 }
    public func session(_ session: ARSession, didFailWithError error: Error) { failures += 1 }
}

public class RoomCaptureSession {
    public struct Configuration: Sendable {
        public var isCoachingEnabled: Bool = true
        public init() {}
    }
    public enum Instruction: Sendable { case normal, moveCloseToWall, moveAwayFromWall, turnOnLight, slowDown, lowTexture }
    public enum CaptureError: Swift.Error, LocalizedError, Hashable, Sendable {
        case deviceNotSupported, deviceTooHot, exceedSceneSizeLimit, invalidARConfiguration, worldTrackingFailure, internalError
    }
    public static var isSupported: Bool { true }
    public weak var delegate: (any RoomCaptureSessionDelegate)?
    public private(set) var arSession: ARSession
    // Test controls.
    public var runConfigurations: [Configuration] = []
    public var stopCalls: [Bool] = []
    public var endError: Swift.Error?
    public var deliverEndAsynchronously = false
    public var suppressEnd = false
    public var alsoCallViewDelegate: ((CapturedRoomData, Swift.Error?) -> Void)?

    /// RoomPlan's own AR delegate, which it installs on the session (the demanding case for our bridge).
    public let ownARDelegate = StubRoomPlanARDelegate()
    /// Test knob: RoomPlan takes the AR session's delegate again whenever a capture starts.
    public var takesARDelegateOnRun = false
    public init(arSession: ARSession? = nil, installsOwnDelegate: Bool = true) {
        self.arSession = arSession ?? ARSession()
        if installsOwnDelegate { self.arSession.delegate = ownARDelegate }
    }
    public func run(configuration: Configuration) {
        runConfigurations.append(configuration)
        if takesARDelegateOnRun { arSession.delegate = ownARDelegate }
    }
    public func stop(pauseARSession: Bool = true) {
        stopCalls.append(pauseARSession)
        if pauseARSession { arSession.pause() }
        if suppressEnd { return }
        let serial = stopCalls.count
        let deliver = { [self] in
            delegate?.captureSession(self, didEndWith: CapturedRoomData(serial: serial), error: endError)
            alsoCallViewDelegate?(CapturedRoomData(serial: serial), endError)
        }
        if deliverEndAsynchronously { DispatchQueue.main.async(execute: deliver) } else { deliver() }
    }
}

public protocol RoomCaptureViewDelegate: AnyObject, NSCoding {  // AnyObject: NSCoding is class-bound on Apple platforms
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool
    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?)
}
public extension RoomCaptureViewDelegate {
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }
    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {}
}

@MainActor open class RoomCaptureView: UIView {
    public var captureSession: RoomCaptureSession!
    public weak var delegate: (any RoomCaptureViewDelegate)?
    public var isModelEnabled: Bool = true
    /// Test record: what the AR session looked like when the view was created (Apple's precondition).
    nonisolated(unsafe) public static var arSessionWasRunningWorldTrackingAtInit: [Bool] = []
    public init(frame: CGRect, arSession: ARSession) {
        RoomCaptureView.arSessionWasRunningWorldTrackingAtInit.append(arSession.configuration is ARWorldTrackingConfiguration)
        super.init(frame: frame)
        let session = RoomCaptureSession(arSession: arSession)
        captureSession = session
        session.alsoCallViewDelegate = { [weak self] data, error in
            _ = self?.delegate?.captureView(shouldPresent: data, error: error)
        }
    }
}
