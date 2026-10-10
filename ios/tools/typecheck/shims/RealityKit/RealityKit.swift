// SHIM of Apple's RealityKit (the parts the 3D viewer and the AR review screen touch). Declarations are copied from
// Apple's documentation (RealityKit pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks.
// Bodies are `fatalError()`: this is for type checking only and is never run.
//
// RealityKit is Swift-native, so its docs show `@MainActor @preconcurrency` explicitly (copied verbatim). Name clashes
// with SwiftUI (`Scene`, `Material`) are real: a file that imports both must not use those names unqualified.
@_exported import Foundation
@_exported import simd
import UIKit
import ARKit

// doc: RealityKit/Material
public protocol Material {}

// doc: RealityKit/Entity
@MainActor @preconcurrency open class Entity: HasHierarchy, HasTransform {
    // doc: RealityKit/Entity/init()
    @MainActor @preconcurrency public required init() { fatalError() }
    // doc: RealityKit/Entity/name
    @MainActor @preconcurrency open var name: String { get { fatalError() } set { } }
    // doc: RealityKit/Entity/isEnabled
    @MainActor @preconcurrency open var isEnabled: Bool { get { fatalError() } set { } }
}
// doc: RealityKit/HasHierarchy
@MainActor @preconcurrency public protocol HasHierarchy: Entity {}
extension HasHierarchy {
    // doc: RealityKit/HasHierarchy/addChild(_:preservingWorldTransform:)
    @MainActor @preconcurrency public func addChild(_ entity: Entity, preservingWorldTransform: Bool = false) { fatalError() }
    // doc: RealityKit/HasHierarchy/parent
    @MainActor @preconcurrency public var parent: Entity? { fatalError() }
    // doc: RealityKit/HasHierarchy/removeFromParent(preservingWorldTransform:)
    @MainActor @preconcurrency public func removeFromParent(preservingWorldTransform: Bool = false) { fatalError() }
}
// doc: RealityKit/HasTransform
@MainActor @preconcurrency public protocol HasTransform: Entity {}
extension HasTransform {
    // doc: RealityKit/HasTransform/look(at:from:upVector:relativeTo:)
    @MainActor @preconcurrency public func look(at target: SIMD3<Float>, from position: SIMD3<Float>, upVector: SIMD3<Float> = SIMD3<Float>(0, 1, 0), relativeTo referenceEntity: Entity?) { fatalError() }
    // doc: RealityKit/HasTransform/look(at:from:upVector:relativeTo:forward:)  [iOS 18.0]
    @MainActor @preconcurrency public func look(at target: SIMD3<Float>, from position: SIMD3<Float>, upVector: SIMD3<Float> = SIMD3<Float>(0, 1, 0), relativeTo referenceEntity: Entity?, forward: Entity.ForwardDirection = .negativeZ) { fatalError() }
}
extension Entity {
    // doc: RealityKit/Entity/ForwardDirection
    public enum ForwardDirection: Hashable {
        // doc: RealityKit/Entity/ForwardDirection/negativeZ  [iOS 18.0]
        case negativeZ
        // doc: RealityKit/Entity/ForwardDirection/positiveZ  [iOS 18.0]
        case positiveZ
    }
}
// doc: RealityKit/HasAnchoring
@MainActor @preconcurrency public protocol HasAnchoring: Entity {}
// doc: RealityKit/AnchorEntity
@MainActor @preconcurrency open class AnchorEntity: Entity, HasAnchoring {
    // doc: RealityKit/AnchorEntity/init()
    @MainActor @preconcurrency public required init() { fatalError() }
    // doc: RealityKit/AnchorEntity/init(world:)
    @MainActor @preconcurrency public convenience init(world position: SIMD3<Float>) { fatalError() }
}
// doc: RealityKit/HasModel
@MainActor @preconcurrency public protocol HasModel: HasTransform {}
extension HasModel {
    // doc: RealityKit/HasModel/model
    @MainActor @preconcurrency public var model: ModelComponent? { get { fatalError() } set { } }
}
// doc: RealityKit/ModelEntity
@MainActor @preconcurrency open class ModelEntity: Entity, HasModel {
    // doc: RealityKit/ModelEntity/init()
    @MainActor @preconcurrency public required init() { fatalError() }
    // doc: RealityKit/ModelEntity/init(mesh:materials:)
    @MainActor @preconcurrency public init(mesh: MeshResource, materials: [any Material] = []) { fatalError() }
}
// doc: RealityKit/ModelComponent
public struct ModelComponent {
    // doc: RealityKit/ModelComponent/materials
    public var materials: [any Material] { get { fatalError() } set { } }
}
// doc: RealityKit/HasPerspectiveCamera
@MainActor @preconcurrency public protocol HasPerspectiveCamera: HasTransform {}
extension HasPerspectiveCamera {
    // doc: RealityKit/HasPerspectiveCamera/camera
    @MainActor @preconcurrency public var camera: PerspectiveCameraComponent { get { fatalError() } set { } }
}
// doc: RealityKit/PerspectiveCamera
@MainActor @preconcurrency open class PerspectiveCamera: Entity, HasPerspectiveCamera {
    // doc: RealityKit/PerspectiveCamera/init()
    @MainActor @preconcurrency public required init() { fatalError() }
}
// doc: RealityKit/PerspectiveCameraComponent
public struct PerspectiveCameraComponent {
    // doc: RealityKit/PerspectiveCameraComponent/init(near:far:fieldOfViewInDegrees:)
    public init(near: Float = 0.01, far: Float = .infinity, fieldOfViewInDegrees: Float = 60.0) { fatalError() }
    // doc: RealityKit/PerspectiveCameraComponent/init(near:far:fieldOfViewInDegrees:fieldOfViewOrientation:)  [iOS 18.0]
    public init(near: Float = 0.01, far: Float = .infinity, fieldOfViewInDegrees: Float = 60.0, fieldOfViewOrientation: CameraFieldOfViewOrientation = .vertical) { fatalError() }
    // doc: RealityKit/PerspectiveCameraComponent/near
    public var near: Float { get { fatalError() } set { } }
    // doc: RealityKit/PerspectiveCameraComponent/far
    public var far: Float { get { fatalError() } set { } }
    // doc: RealityKit/PerspectiveCameraComponent/fieldOfViewInDegrees
    public var fieldOfViewInDegrees: Float { get { fatalError() } set { } }
    // doc: RealityKit/PerspectiveCameraComponent/fieldOfViewOrientation  [iOS 18.0]
    public var fieldOfViewOrientation: CameraFieldOfViewOrientation { get { fatalError() } set { } }
}
// doc: RealityKit/CameraFieldOfViewOrientation
public enum CameraFieldOfViewOrientation: Hashable {
    // doc: RealityKit/CameraFieldOfViewOrientation/horizontal  [iOS 18.0]
    case horizontal
    // doc: RealityKit/CameraFieldOfViewOrientation/vertical  [iOS 18.0]
    case vertical
}

// doc: RealityKit/Scene
@MainActor @preconcurrency open class Scene {
    // doc: RealityKit/Scene/addAnchor(_:)
    @MainActor @preconcurrency open func addAnchor(_ anchor: any HasAnchoring) { fatalError() }
    // doc: RealityKit/Scene/removeAnchor(_:)
    @MainActor @preconcurrency open func removeAnchor(_ anchor: any HasAnchoring) { fatalError() }
}

// doc: RealityKit/ARView
@MainActor @objc @preconcurrency open class ARView: UIView {
    // doc: RealityKit/ARView/init(frame:cameraMode:automaticallyConfigureSession:)
    @MainActor @preconcurrency public init(frame frameRect: CGRect, cameraMode: ARView.CameraMode, automaticallyConfigureSession: Bool) { fatalError() }
    // doc: RealityKit/ARView/init(frame:)
    @MainActor @preconcurrency public override required dynamic init(frame frameRect: CGRect) { fatalError() }
    // doc: RealityKit/ARView/init(coder:)
    @MainActor @preconcurrency public required dynamic init?(coder decoder: NSCoder) { fatalError() }
    // doc: RealityKit/ARView/session
    @MainActor @preconcurrency public dynamic var session: ARSession { get { fatalError() } set { } }
    // doc: RealityKit/ARView/scene
    @MainActor @preconcurrency open var scene: Scene { fatalError() }
    // doc: RealityKit/ARView/renderOptions-swift.property
    @MainActor @preconcurrency open var renderOptions: ARView.RenderOptions { get { fatalError() } set { } }
    // doc: RealityKit/ARView/environment-swift.property
    @MainActor @preconcurrency open var environment: ARView.Environment { get { fatalError() } set { } }
    // doc: RealityKit/ARView/project(_:)
    @MainActor @preconcurrency open func project(_ point: SIMD3<Float>) -> CGPoint? { fatalError() }
    // doc: RealityKit/ARView/ray(through:)
    @MainActor @preconcurrency open func ray(through screenPoint: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? { fatalError() }
    // doc: RealityKit/ARView/raycast(from:allowing:alignment:)
    @MainActor @preconcurrency open func raycast(from point: CGPoint, allowing target: ARRaycastQuery.Target, alignment: ARRaycastQuery.TargetAlignment) -> [ARRaycastResult] { fatalError() }
}
extension ARView {
    // doc: RealityKit/ARView/CameraMode-swift.enum
    public enum CameraMode: Hashable {
        // doc: RealityKit/ARView/CameraMode-swift.enum/ar
        case ar
        // doc: RealityKit/ARView/CameraMode-swift.enum/nonAR
        case nonAR
    }
    // doc: RealityKit/ARView/RenderOptions-swift.struct
    public struct RenderOptions: OptionSet {
        // shim: OptionSet storage
        public let rawValue: Int
        // doc: RealityKit/ARView/RenderOptions-swift.struct/disableCameraGrain
        public static var disableCameraGrain: ARView.RenderOptions { RenderOptions(rawValue: 0) }
        // doc: RealityKit/ARView/RenderOptions-swift.struct/disableHDR
        public static var disableHDR: ARView.RenderOptions { RenderOptions(rawValue: 0) }
        // doc: RealityKit/ARView/RenderOptions-swift.struct/disableGroundingShadows
        public static var disableGroundingShadows: ARView.RenderOptions { RenderOptions(rawValue: 0) }
        // doc: RealityKit/ARView/RenderOptions-swift.struct/disableMotionBlur
        public static var disableMotionBlur: ARView.RenderOptions { RenderOptions(rawValue: 0) }
        // doc: RealityKit/ARView/RenderOptions-swift.struct/disableDepthOfField
        public static var disableDepthOfField: ARView.RenderOptions { RenderOptions(rawValue: 0) }
        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
    // doc: RealityKit/ARView/Environment-swift.struct
    public struct Environment {
        // doc: RealityKit/ARView/Environment-swift.struct/background-swift.property
        public var background: ARView.Environment.Background { get { fatalError() } set { } }
        // doc: RealityKit/ARView/Environment-swift.struct/Color
        public typealias Color = UIColor
        // doc: RealityKit/ARView/Environment-swift.struct/Background-swift.struct
        public struct Background {
            // doc: RealityKit/ARView/Environment-swift.struct/Background-swift.struct/color(_:)-5hh3f
            public static func color(_ color: ARView.Environment.Color) -> ARView.Environment.Background { fatalError() }
            // doc: RealityKit/ARView/Environment-swift.struct/Background-swift.struct/cameraFeed(exposureCompensation:)
            public static func cameraFeed(exposureCompensation: Float = 0.0) -> ARView.Environment.Background { fatalError() }
        }
    }
}

// doc: RealityKit/MeshResource
@MainActor @preconcurrency open class MeshResource {
    // doc: RealityKit/MeshResource/generate(from:)-1yx1
    @MainActor @preconcurrency public static func generate(from descriptors: [MeshDescriptor]) throws -> MeshResource { fatalError() }
}
// doc: RealityKit/MeshDescriptor
public struct MeshDescriptor {
    // doc: RealityKit/MeshDescriptor/init(name:)
    public init(name: String = "") { fatalError() }
    // doc: RealityKit/MeshDescriptor/name
    public var name: String { get { fatalError() } set { } }
    // doc: RealityKit/MeshDescriptor/primitives-swift.property
    public var primitives: MeshDescriptor.Primitives? = nil
    // doc-unconfirmed: positions/normals are the MeshDescriptor accessors for MeshBuffers.positions/normals; the docs list them as a
    // subscript and a pair of properties whose pages carry no Swift declaration in this snapshot
    public var positions: MeshBuffers.Positions { get { fatalError() } set { } }
    // doc-unconfirmed: see positions
    public var normals: MeshBuffers.Normals { get { fatalError() } set { } }
    // doc: RealityKit/MeshDescriptor/Primitives-swift.enum
    public enum Primitives {
        // doc: RealityKit/MeshDescriptor/Primitives-swift.enum/polygons(_:_:)
        case polygons([UInt8], [UInt32])
        // doc: RealityKit/MeshDescriptor/Primitives-swift.enum/triangles(_:)
        case triangles([UInt32])
        // doc: RealityKit/MeshDescriptor/Primitives-swift.enum/trianglesAndQuads(triangles:quads:)
        case trianglesAndQuads(triangles: [UInt32], quads: [UInt32])
    }
}
// doc: RealityKit/MeshBuffers
public enum MeshBuffers {
    // doc: RealityKit/MeshBuffers/Positions-swift.typealias
    public typealias Positions = MeshBuffer<SIMD3<Float>>
    // doc: RealityKit/MeshBuffers/Normals-swift.typealias
    public typealias Normals = MeshBuffer<SIMD3<Float>>
}
// doc: RealityKit/MeshBuffer
public struct MeshBuffer<Element> {
    // doc: RealityKit/MeshBuffer/init(_:)-11fcy
    public init(_ array: [Element]) { fatalError() }
}

// doc: RealityKit/UnlitMaterial
public struct UnlitMaterial: Material {
    // doc: RealityKit/UnlitMaterial/init()
    public init() { fatalError() }
    // doc: RealityKit/UnlitMaterial/init(color:)-5zgo5
    public init(color: UIColor) { fatalError() }
    // doc: RealityKit/UnlitMaterial/init(color:applyPostProcessToneMap:)-58wdb  [iOS 18.0]
    public init(color: UIColor, applyPostProcessToneMap: Bool) { fatalError() }
    // doc: RealityKit/UnlitMaterial/blending-swift.property
    public var blending: UnlitMaterial.Blending { get { fatalError() } set { } }
    // doc: RealityKit/UnlitMaterial/Blending-swift.typealias
    public typealias Blending = PhysicallyBasedMaterial.Blending
}
// doc: RealityKit/PhysicallyBasedMaterial
public struct PhysicallyBasedMaterial: Material {
    // doc: RealityKit/PhysicallyBasedMaterial/Blending-swift.enum
    public enum Blending {
        // doc: RealityKit/PhysicallyBasedMaterial/Blending-swift.enum/opaque
        case opaque
        // doc: RealityKit/PhysicallyBasedMaterial/Blending-swift.enum/transparent(opacity:)
        case transparent(opacity: PhysicallyBasedMaterial.Opacity)
    }
    // doc: RealityKit/PhysicallyBasedMaterial/Opacity
    public struct Opacity: Hashable, ExpressibleByFloatLiteral {
        // doc: RealityKit/PhysicallyBasedMaterial/Opacity/init(floatLiteral:)
        public init(floatLiteral value: Float) { }
    }
}

