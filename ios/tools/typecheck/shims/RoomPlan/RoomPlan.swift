// SHIM of Apple's RoomPlan (everything NexaFix Scan touches). Declarations are copied from Apple's documentation
// (RoomPlan pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks. Bodies are
// `fatalError()`: this is for type checking only and is never run.
//
// CapturedRoom and its parts are Swift structs with get-only properties and no public memberwise initialiser,
// exactly as documented, so nothing in the app can build one by hand (the Simulator path uses Core's fixtures).
@_exported import Foundation
@_exported import simd
import UIKit
import ARKit

// doc: RoomPlan/RoomCaptureSession
public class RoomCaptureSession {
    // doc: RoomPlan/RoomCaptureSession/init(arSession:)
    public init(arSession: ARSession? = nil) { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/init()
    public init() { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/isSupported
    public static var isSupported: Bool { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/run(configuration:)
    public func run(configuration: RoomCaptureSession.Configuration) { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/stop()
    public func stop() { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/stop(pauseARSession:)
    public func stop(pauseARSession: Bool = true) { fatalError() }
    // doc: RoomPlan/RoomCaptureSession/delegate
    public var delegate: (any RoomCaptureSessionDelegate)? = nil
    // doc: RoomPlan/RoomCaptureSession/arSession
    public var arSession: ARSession { get { fatalError() } set { } }
}
extension RoomCaptureSession {
    // doc: RoomPlan/RoomCaptureSession/Configuration
    public struct Configuration {
        // doc: RoomPlan/RoomCaptureSession/Configuration/init()
        public init() { isCoachingEnabled = true }
        // doc: RoomPlan/RoomCaptureSession/Configuration/isCoachingEnabled
        public var isCoachingEnabled: Bool = true
    }
    // doc: RoomPlan/RoomCaptureSession/CaptureError
    public enum CaptureError: Error, Hashable, LocalizedError, Sendable {
        // doc: RoomPlan/RoomCaptureSession/CaptureError/deviceNotSupported
        case deviceNotSupported
        // doc: RoomPlan/RoomCaptureSession/CaptureError/deviceTooHot
        case deviceTooHot
        // doc: RoomPlan/RoomCaptureSession/CaptureError/exceedSceneSizeLimit
        case exceedSceneSizeLimit
        // doc: RoomPlan/RoomCaptureSession/CaptureError/invalidARConfiguration
        case invalidARConfiguration
        // doc: RoomPlan/RoomCaptureSession/CaptureError/worldTrackingFailure
        case worldTrackingFailure
        // doc: RoomPlan/RoomCaptureSession/CaptureError/internalError
        case internalError
        // doc: RoomPlan/RoomCaptureSession/CaptureError/errorDescription
        public var errorDescription: String? { fatalError() }
    }
    // doc: RoomPlan/RoomCaptureSession/Instruction
    public enum Instruction: Hashable {
        // doc: RoomPlan/RoomCaptureSession/Instruction/normal
        case normal
        // doc: RoomPlan/RoomCaptureSession/Instruction/moveCloseToWall
        case moveCloseToWall
        // doc: RoomPlan/RoomCaptureSession/Instruction/moveAwayFromWall
        case moveAwayFromWall
        // doc: RoomPlan/RoomCaptureSession/Instruction/turnOnLight
        case turnOnLight
        // doc: RoomPlan/RoomCaptureSession/Instruction/slowDown
        case slowDown
        // doc: RoomPlan/RoomCaptureSession/Instruction/lowTexture
        case lowTexture
    }
}

// doc: RoomPlan/RoomCaptureSessionDelegate
public protocol RoomCaptureSessionDelegate: AnyObject {
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didStartWith:)
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didAdd:)
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didRemove:)
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didChange:)
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didUpdate:)
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didProvide:)
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction)
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didEndWith:error:)
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?)
}
extension RoomCaptureSessionDelegate {
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didStartWith:)-3c74n
    public func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) { }
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didUpdate:)-77zyg
    public func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) { }
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didRemove:)-9gs76
    public func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) { }
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didChange:)-gv3t
    public func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) { }
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didProvide:)-5hvhl
    public func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) { }
    // doc: RoomPlan/RoomCaptureSessionDelegate/captureSession(_:didEndWith:error:)-5f0mc
    public func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) { }
}

// doc: RoomPlan/RoomCaptureView
@MainActor @objc @preconcurrency public class RoomCaptureView: UIView {
    // doc: RoomPlan/RoomCaptureView/init(frame:arSession:)
    @MainActor @preconcurrency public init(frame: CGRect, arSession: ARSession) { fatalError() }
    // doc: RoomPlan/RoomCaptureView/init(frame:)
    @MainActor @preconcurrency public override dynamic init(frame: CGRect) { fatalError() }
    // doc: RoomPlan/RoomCaptureView/init(coder:)
    @MainActor @preconcurrency public required dynamic init?(coder: NSCoder) { fatalError() }
    // doc: RoomPlan/RoomCaptureView/captureSession
    @MainActor @preconcurrency public var captureSession: RoomCaptureSession! { fatalError() }
    // doc: RoomPlan/RoomCaptureView/delegate
    @MainActor @preconcurrency public var delegate: (any RoomCaptureViewDelegate)? = nil
    // doc: RoomPlan/RoomCaptureView/isModelEnabled
    @MainActor @preconcurrency public var isModelEnabled: Bool { get { fatalError() } set { } }
}
// doc: RoomPlan/RoomCaptureViewDelegate
public protocol RoomCaptureViewDelegate: NSCoding {
    // doc: RoomPlan/RoomCaptureViewDelegate/captureView(shouldPresent:error:)
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool
    // doc: RoomPlan/RoomCaptureViewDelegate/captureView(didPresent:error:)
    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?)
}
extension RoomCaptureViewDelegate {
    // doc: RoomPlan/RoomCaptureViewDelegate/captureView(shouldPresent:error:)-5l74q
    public func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }
    // doc: RoomPlan/RoomCaptureViewDelegate/captureView(didPresent:error:)-6em1r
    public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) { }
}

// doc: RoomPlan/RoomBuilder
public class RoomBuilder {
    // doc: RoomPlan/RoomBuilder/init(options:)
    public init(options: RoomBuilder.ConfigurationOptions) { fatalError() }
    // doc: RoomPlan/RoomBuilder/capturedRoom(from:)
    public func capturedRoom(from capturedRoomData: CapturedRoomData) async throws -> CapturedRoom { fatalError() }
}
extension RoomBuilder {
    // doc: RoomPlan/RoomBuilder/ConfigurationOptions
    public struct ConfigurationOptions: OptionSet {
        // shim: OptionSet storage
        public let rawValue: Int
        // doc: RoomPlan/RoomBuilder/ConfigurationOptions/init(rawValue:)
        public init(rawValue: Int) { self.rawValue = rawValue }
        // doc: RoomPlan/RoomBuilder/ConfigurationOptions/beautifyObjects
        public static var beautifyObjects: RoomBuilder.ConfigurationOptions { ConfigurationOptions(rawValue: 1) }
    }
    // doc: RoomPlan/RoomBuilder/BuildError
    public enum BuildError: Error, Hashable, LocalizedError, Sendable {
        // doc: RoomPlan/RoomBuilder/BuildError/insufficientInput
        case insufficientInput
        // doc: RoomPlan/RoomBuilder/BuildError/invalidInput
        case invalidInput
        // doc: RoomPlan/RoomBuilder/BuildError/exceedSceneSizeLimit
        case exceedSceneSizeLimit
        // doc: RoomPlan/RoomBuilder/BuildError/internalError
        case internalError
        // doc: RoomPlan/RoomBuilder/BuildError/deviceNotSupported
        case deviceNotSupported
        // doc: RoomPlan/RoomBuilder/BuildError/errorDescription
        public var errorDescription: String? { fatalError() }
    }
}

// doc: RoomPlan/StructureBuilder
public class StructureBuilder {
    // doc: RoomPlan/StructureBuilder/init(options:)
    public init(options: StructureBuilder.ConfigurationOptions) { fatalError() }
    // doc: RoomPlan/StructureBuilder/ConfigurationOptions
    public typealias ConfigurationOptions = RoomBuilder.ConfigurationOptions
    // doc: RoomPlan/StructureBuilder/capturedStructure(from:)
    public func capturedStructure(from rooms: [CapturedRoom]) async throws -> CapturedStructure { fatalError() }
}
extension StructureBuilder {
    // doc: RoomPlan/StructureBuilder/BuildError
    public enum BuildError: Error, Hashable, LocalizedError, Sendable {
        // doc: RoomPlan/StructureBuilder/BuildError/deviceNotSupported
        case deviceNotSupported
        // doc: RoomPlan/StructureBuilder/BuildError/exceedSceneSizeLimit
        case exceedSceneSizeLimit
        // doc: RoomPlan/StructureBuilder/BuildError/insufficientInput
        case insufficientInput
        // doc: RoomPlan/StructureBuilder/BuildError/internalError
        case internalError
        // doc: RoomPlan/StructureBuilder/BuildError/invalidInput
        case invalidInput
        // doc: RoomPlan/StructureBuilder/BuildError/invalidRoomLocation
        case invalidRoomLocation
        // doc: RoomPlan/StructureBuilder/BuildError/errorDescription
        public var errorDescription: String? { fatalError() }
    }
}

// doc: RoomPlan/CapturedRoomData
public struct CapturedRoomData: Codable, Sendable {
    // doc: RoomPlan/CapturedRoomData/init(from:)
    public init(from decoder: any Decoder) throws { fatalError() }
    // doc: RoomPlan/CapturedRoomData/encode(to:)
    public func encode(to encoder: any Encoder) throws { fatalError() }
}

// doc: RoomPlan/CapturedRoom
public struct CapturedRoom: Codable, Sendable {
    // doc: RoomPlan/CapturedRoom/init(from:)
    public init(from decoder: any Decoder) throws { fatalError() }
    // doc: RoomPlan/CapturedRoom/identifier
    public var identifier: UUID { fatalError() }
    // doc: RoomPlan/CapturedRoom/story
    public var story: Int { fatalError() }
    // doc: RoomPlan/CapturedRoom/floors
    public var floors: [CapturedRoom.Surface] { fatalError() }
    // doc: RoomPlan/CapturedRoom/doors
    public var doors: [CapturedRoom.Surface] { fatalError() }
    // doc: RoomPlan/CapturedRoom/objects
    public var objects: [CapturedRoom.Object] { fatalError() }
    // doc: RoomPlan/CapturedRoom/openings
    public var openings: [CapturedRoom.Surface] { fatalError() }
    // doc: RoomPlan/CapturedRoom/walls
    public var walls: [CapturedRoom.Surface] { fatalError() }
    // doc: RoomPlan/CapturedRoom/windows
    public var windows: [CapturedRoom.Surface] { fatalError() }
    // doc: RoomPlan/CapturedRoom/version
    public var version: Int { fatalError() }
    // doc: RoomPlan/CapturedRoom/encode(to:)
    public func encode(to encoder: any Encoder) throws { fatalError() }
    // doc: RoomPlan/CapturedRoom/export(to:exportOptions:)
    public func export(to url: URL, exportOptions: CapturedRoom.USDExportOptions = .mesh) throws { fatalError() }
    // doc: RoomPlan/CapturedRoom/export(to:metadataURL:modelProvider:exportOptions:)
    public func export(to url: URL, metadataURL: URL? = nil, modelProvider: CapturedRoom.ModelProvider? = nil, exportOptions: CapturedRoom.USDExportOptions = .mesh) throws { fatalError() }
}
extension CapturedRoom {
    // doc: RoomPlan/CapturedRoom/Confidence
    public enum Confidence: Hashable, Sendable {
        // doc: RoomPlan/CapturedRoom/Confidence/high
        case high
        // doc: RoomPlan/CapturedRoom/Confidence/medium
        case medium
        // doc: RoomPlan/CapturedRoom/Confidence/low
        case low
    }
    // doc: RoomPlan/CapturedRoom/Surface
    public struct Surface: Codable, Sendable {
        // doc: RoomPlan/CapturedRoom/Surface/init(from:)
        public init(from decoder: any Decoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/identifier
        public var identifier: UUID { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/parentIdentifier
        public var parentIdentifier: UUID? { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/category-swift.property
        public var category: CapturedRoom.Surface.Category { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/confidence
        public var confidence: CapturedRoom.Confidence { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/transform
        public var transform: simd_float4x4 { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/dimensions
        public var dimensions: simd_float3 { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/story
        public var story: Int { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/completedEdges
        public var completedEdges: Set<CapturedRoom.Surface.Edge> { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/curve-swift.property
        public var curve: CapturedRoom.Surface.Curve? { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/polygonCorners
        public var polygonCorners: [simd_float3] { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/encode(to:)
        public func encode(to encoder: any Encoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum
        public enum Category: Codable, Equatable, Hashable, Sendable {
            // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum/floor
            case floor
            // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum/door(isOpen:)
            case door(isOpen: Bool)
            // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum/opening
            case opening
            // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum/wall
            case wall
            // doc: RoomPlan/CapturedRoom/Surface/Category-swift.enum/window
            case window
        }
        // doc: RoomPlan/CapturedRoom/Surface/Edge
        public enum Edge: CaseIterable, Codable, Hashable, Sendable {
            // doc: RoomPlan/CapturedRoom/Surface/Edge/top
            case top
            // doc: RoomPlan/CapturedRoom/Surface/Edge/bottom
            case bottom
            // doc: RoomPlan/CapturedRoom/Surface/Edge/left
            case left
            // doc: RoomPlan/CapturedRoom/Surface/Edge/right
            case right
        }
        // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct
        public struct Curve: Codable, Sendable {
            // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct/startAngle
            public var startAngle: Measurement<UnitAngle> { fatalError() }
            // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct/endAngle
            public var endAngle: Measurement<UnitAngle> { fatalError() }
            // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct/radius
            public var radius: Float { fatalError() }
            // doc: RoomPlan/CapturedRoom/Surface/Curve-swift.struct/center
            public var center: simd_float2 { fatalError() }
        }
    }
    // doc: RoomPlan/CapturedRoom/Object
    public struct Object: Codable, Sendable {
        // doc: RoomPlan/CapturedRoom/Object/init(from:)
        public init(from decoder: any Decoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/identifier
        public var identifier: UUID { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/parentIdentifier
        public var parentIdentifier: UUID? { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/category-swift.property
        public var category: CapturedRoom.Object.Category { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/confidence
        public var confidence: CapturedRoom.Confidence { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/transform
        public var transform: simd_float4x4 { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/dimensions
        public var dimensions: simd_float3 { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/story
        public var story: Int { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/encode(to:)
        public func encode(to encoder: any Encoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum
        public enum Category: CaseIterable, Codable, Hashable, Sendable {
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/bathtub
            case bathtub
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/bed
            case bed
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/chair
            case chair
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/dishwasher
            case dishwasher
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/fireplace
            case fireplace
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/oven
            case oven
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/refrigerator
            case refrigerator
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/sink
            case sink
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/sofa
            case sofa
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/stairs
            case stairs
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/storage
            case storage
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/stove
            case stove
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/table
            case table
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/television
            case television
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/toilet
            case toilet
            // doc: RoomPlan/CapturedRoom/Object/Category-swift.enum/washerDryer
            case washerDryer
        }
    }
    // doc: RoomPlan/CapturedRoom/USDExportOptions
    public struct USDExportOptions: OptionSet {
        // doc: RoomPlan/CapturedRoom/USDExportOptions/init(rawValue:)
        public init(rawValue: Int32) { self.rawValue = rawValue }
        // doc: RoomPlan/CapturedRoom/USDExportOptions/rawValue
        public let rawValue: Int32
        // doc: RoomPlan/CapturedRoom/USDExportOptions/parametric
        public static var parametric: CapturedRoom.USDExportOptions { USDExportOptions(rawValue: 0) }
        // doc: RoomPlan/CapturedRoom/USDExportOptions/mesh
        public static var mesh: CapturedRoom.USDExportOptions { USDExportOptions(rawValue: 0) }
        // doc: RoomPlan/CapturedRoom/USDExportOptions/model
        public static var model: CapturedRoom.USDExportOptions { USDExportOptions(rawValue: 0) }
    }
    // doc: RoomPlan/CapturedRoom/ModelProvider
    public struct ModelProvider {
        // doc: RoomPlan/CapturedRoom/ModelProvider/init()
        public init() { }
    }
    // doc: RoomPlan/CapturedRoom/Error
    public enum Error: Swift.Error, LocalizedError, Sendable {
        // doc: RoomPlan/CapturedRoom/Error/deviceNotSupported
        case deviceNotSupported
        // doc: RoomPlan/CapturedRoom/Error/urlInvalidFileExtension
        case urlInvalidFileExtension
        // doc: RoomPlan/CapturedRoom/Error/urlInvalidFilePath
        case urlInvalidFilePath
        // doc: RoomPlan/CapturedRoom/Error/urlInvalidScheme
        case urlInvalidScheme
        // doc: RoomPlan/CapturedRoom/Error/urlMissingFileExtension
        case urlMissingFileExtension
        // doc: RoomPlan/CapturedRoom/Error/errorDescription
        public var errorDescription: String? { fatalError() }
    }
}

// doc: RoomPlan/CapturedStructure
public struct CapturedStructure: Codable, Sendable {
    // doc: RoomPlan/CapturedStructure/init(from:)
    public init(from decoder: any Decoder) throws { fatalError() }
    // doc: RoomPlan/CapturedStructure/identifier
    public var identifier: UUID { fatalError() }
    // doc: RoomPlan/CapturedStructure/rooms
    public var rooms: [CapturedRoom] { fatalError() }
    // doc: RoomPlan/CapturedStructure/floors
    public var floors: [CapturedStructure.Surface] { fatalError() }
    // doc: RoomPlan/CapturedStructure/doors
    public var doors: [CapturedStructure.Surface] { fatalError() }
    // doc: RoomPlan/CapturedStructure/objects
    public var objects: [CapturedStructure.Object] { fatalError() }
    // doc: RoomPlan/CapturedStructure/openings
    public var openings: [CapturedStructure.Surface] { fatalError() }
    // doc: RoomPlan/CapturedStructure/walls
    public var walls: [CapturedStructure.Surface] { fatalError() }
    // doc: RoomPlan/CapturedStructure/windows
    public var windows: [CapturedStructure.Surface] { fatalError() }
    // doc: RoomPlan/CapturedStructure/sections
    public var sections: [CapturedStructure.Section] { fatalError() }
    // doc: RoomPlan/CapturedStructure/version
    public var version: Int { fatalError() }
    // doc: RoomPlan/CapturedStructure/encode(to:)
    public func encode(to encoder: any Encoder) throws { fatalError() }
    // doc: RoomPlan/CapturedStructure/export(to:metadataURL:modelProvider:exportOptions:)
    public func export(to url: URL, metadataURL: URL? = nil, modelProvider: CapturedStructure.ModelProvider? = nil, exportOptions: CapturedStructure.USDExportOptions = .mesh) throws { fatalError() }
    // doc: RoomPlan/CapturedStructure/USDExportOptions
    public typealias USDExportOptions = CapturedRoom.USDExportOptions
    // doc: RoomPlan/CapturedStructure/ModelProvider
    public typealias ModelProvider = CapturedRoom.ModelProvider
    // doc: RoomPlan/CapturedStructure/Error
    public typealias Error = CapturedRoom.Error
    // doc: RoomPlan/CapturedStructure/Surface
    public typealias Surface = CapturedRoom.Surface
    // doc: RoomPlan/CapturedStructure/Object
    public typealias Object = CapturedRoom.Object
    // doc: RoomPlan/CapturedStructure/Section
    public typealias Section = CapturedRoom.Section
}
extension CapturedRoom {
    // doc: RoomPlan/CapturedRoom/Section
    public struct Section: Codable, Sendable {
        // doc: RoomPlan/CapturedRoom/Section/init(from:)
        public init(from decoder: any Decoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Section/label-swift.property
        public var label: CapturedRoom.Section.Label { fatalError() }
        // doc: RoomPlan/CapturedRoom/Section/story
        public var story: Int { fatalError() }
        // doc: RoomPlan/CapturedRoom/Section/center
        public var center: simd_float3 { fatalError() }
        // doc: RoomPlan/CapturedRoom/Section/encode(to:)
        public func encode(to encoder: any Encoder) throws { fatalError() }
        // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum
        public enum Label: String, Codable, Hashable, Sendable {
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/livingRoom
            case livingRoom
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/kitchen
            case kitchen
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/diningRoom
            case diningRoom
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/bedroom
            case bedroom
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/bathroom
            case bathroom
            // doc: RoomPlan/CapturedRoom/Section/Label-swift.enum/unidentified
            case unidentified
        }
    }
}
