from mk import *
H = '''// SHIM of Apple's RealityKit (the parts the 3D viewer and the AR review screen touch). Declarations are copied from
// Apple's documentation (RealityKit pages, iOS column); each carries a `// doc:` tag that docs/verify_shims.py re-checks.
// Bodies are `fatalError()`: this is for type checking only and is never run.
//
// RealityKit is Swift-native, so its docs show `@MainActor @preconcurrency` explicitly (copied verbatim). Name clashes
// with SwiftUI (`Scene`, `Material`) are real: a file that imports both must not use those names unqualified.
@_exported import Foundation
@_exported import simd
import UIKit
import ARKit

'''
B = []
def add(s): B.append(s)
def cases(paths, indent='        '):
    lines = [l.strip() for l in emit_members(paths, indent='').split('\n') if l.strip()]
    add('\n'.join(indent + l for l in lines))

add('''// doc: RealityKit/Material
public protocol Material {}

// doc: RealityKit/Entity
@MainActor @preconcurrency open class Entity: HasHierarchy, HasTransform {''')
add(emit_members(['realitykit/entity/init()','realitykit/entity/name','realitykit/entity/isenabled'], cls_open=True))
add('''}
// doc: RealityKit/HasHierarchy
@MainActor @preconcurrency public protocol HasHierarchy: Entity {}
extension HasHierarchy {''')
add(emit_members(['realitykit/hashierarchy/addchild(_:preservingworldtransform:)','realitykit/hashierarchy/parent','realitykit/hashierarchy/removefromparent(preservingworldtransform:)']))
add('''}
// doc: RealityKit/HasTransform
@MainActor @preconcurrency public protocol HasTransform: Entity {}
extension HasTransform {''')
add(emit_members(['realitykit/hastransform/look(at:from:upvector:relativeto:)','realitykit/hastransform/look(at:from:upvector:relativeto:forward:)']))
add('''}
extension Entity {
    // doc: RealityKit/Entity/ForwardDirection
    public enum ForwardDirection: Hashable {''')
cases(['realitykit/entity/forwarddirection/negativez','realitykit/entity/forwarddirection/positivez'])
add('''    }
}
// doc: RealityKit/HasAnchoring
@MainActor @preconcurrency public protocol HasAnchoring: Entity {}
// doc: RealityKit/AnchorEntity
@MainActor @preconcurrency open class AnchorEntity: Entity, HasAnchoring {''')
add(emit_members(['realitykit/anchorentity/init()','realitykit/anchorentity/init(world:)'], cls_open=True))
add('''}
// doc: RealityKit/HasModel
@MainActor @preconcurrency public protocol HasModel: HasTransform {}
extension HasModel {''')
add(emit_members(['realitykit/hasmodel/model']))
add('''}
// doc: RealityKit/ModelEntity
@MainActor @preconcurrency open class ModelEntity: Entity, HasModel {''')
add(emit_members(['realitykit/modelentity/init()','realitykit/modelentity/init(mesh:materials:)'], cls_open=True))
add('''}
// doc: RealityKit/ModelComponent
public struct ModelComponent {''')
add(emit_members(['realitykit/modelcomponent/materials']))
add('''}
// doc: RealityKit/HasPerspectiveCamera
@MainActor @preconcurrency public protocol HasPerspectiveCamera: HasTransform {}
extension HasPerspectiveCamera {''')
add(emit_members(['realitykit/hasperspectivecamera/camera']))
add('''}
// doc: RealityKit/PerspectiveCamera
@MainActor @preconcurrency open class PerspectiveCamera: Entity, HasPerspectiveCamera {''')
add(emit_members(['realitykit/perspectivecamera/init()'], cls_open=True))
add('''}
// doc: RealityKit/PerspectiveCameraComponent
public struct PerspectiveCameraComponent {''')
add(emit_members(['realitykit/perspectivecameracomponent/init(near:far:fieldofviewindegrees:)','realitykit/perspectivecameracomponent/init(near:far:fieldofviewindegrees:fieldofvieworientation:)','realitykit/perspectivecameracomponent/near','realitykit/perspectivecameracomponent/far','realitykit/perspectivecameracomponent/fieldofviewindegrees','realitykit/perspectivecameracomponent/fieldofvieworientation']))
add('''}
// doc: RealityKit/CameraFieldOfViewOrientation
public enum CameraFieldOfViewOrientation: Hashable {''')
cases(['realitykit/camerafieldofvieworientation/horizontal','realitykit/camerafieldofvieworientation/vertical'], '    ')
add('''}

// doc: RealityKit/Scene
@MainActor @preconcurrency open class Scene {''')
add(emit_members(['realitykit/scene/addanchor(_:)','realitykit/scene/removeanchor(_:)'], cls_open=True))
add('''}

// doc: RealityKit/ARView
@MainActor @objc @preconcurrency open class ARView: UIView {''')
add(emit_members(['realitykit/arview/init(frame:cameramode:automaticallyconfiguresession:)','realitykit/arview/init(frame:)','realitykit/arview/init(coder:)','realitykit/arview/session','realitykit/arview/scene','realitykit/arview/rendereoptions-swift.property'.replace('rendereoptions','renderoptions'),'realitykit/arview/environment-swift.property','realitykit/arview/project(_:)','realitykit/arview/ray(through:)','realitykit/arview/raycast(from:allowing:alignment:)'], cls_open=True))
add('''}
extension ARView {
    // doc: RealityKit/ARView/CameraMode-swift.enum
    public enum CameraMode: Hashable {''')
cases(['realitykit/arview/cameramode-swift.enum/ar','realitykit/arview/cameramode-swift.enum/nonar'])
add('''    }
    // doc: RealityKit/ARView/RenderOptions-swift.struct
    public struct RenderOptions: OptionSet {
        // shim: OptionSet storage''')
add('        public let rawValue: Int')
add(emit_members(['realitykit/arview/renderoptions-swift.struct/disablecameragrain','realitykit/arview/renderoptions-swift.struct/disablehdr','realitykit/arview/renderoptions-swift.struct/disablegroundingshadows','realitykit/arview/renderoptions-swift.struct/disablemotionblur','realitykit/arview/renderoptions-swift.struct/disabledepthoffield'], indent='        ').replace('{ fatalError() }','{ RenderOptions(rawValue: 0) }'))
add('''        // shim: OptionSet requirement
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
    // doc: RealityKit/ARView/Environment-swift.struct
    public struct Environment {''')
add(emit_members(['realitykit/arview/environment-swift.struct/background-swift.property','realitykit/arview/environment-swift.struct/color'], indent='        '))
add('''        // doc: RealityKit/ARView/Environment-swift.struct/Background-swift.struct
        public struct Background {''')
add(emit_members(['realitykit/arview/environment-swift.struct/background-swift.struct/color(_:)-5hh3f','realitykit/arview/environment-swift.struct/background-swift.struct/camerafeed(exposurecompensation:)'], indent='            '))
add('''        }
    }
}

// doc: RealityKit/MeshResource
@MainActor @preconcurrency open class MeshResource {''')
add(emit_members(['realitykit/meshresource/generate(from:)-1yx1'], cls_open=True))
add('''}
// doc: RealityKit/MeshDescriptor
public struct MeshDescriptor {''')
add(emit_members(['realitykit/meshdescriptor/init(name:)','realitykit/meshdescriptor/name','realitykit/meshdescriptor/primitives-swift.property']))
add('''    // doc-unconfirmed: positions/normals are the MeshDescriptor accessors for MeshBuffers.positions/normals; the docs list them as a
    // subscript and a pair of properties whose pages carry no Swift declaration in this snapshot
    public var positions: MeshBuffers.Positions { get { fatalError() } set { } }
    // doc-unconfirmed: see positions
    public var normals: MeshBuffers.Normals { get { fatalError() } set { } }
    // doc: RealityKit/MeshDescriptor/Primitives-swift.enum
    public enum Primitives {''')
cases(['realitykit/meshdescriptor/primitives-swift.enum/polygons(_:_:)','realitykit/meshdescriptor/primitives-swift.enum/triangles(_:)','realitykit/meshdescriptor/primitives-swift.enum/trianglesandquads(triangles:quads:)'])
add('''    }
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
public struct UnlitMaterial: Material {''')
add(emit_members(['realitykit/unlitmaterial/init()','realitykit/unlitmaterial/init(color:)-5zgo5','realitykit/unlitmaterial/init(color:applypostprocesstonemap:)-58wdb','realitykit/unlitmaterial/blending-swift.property','realitykit/unlitmaterial/blending-swift.typealias']))
add('''}
// doc: RealityKit/PhysicallyBasedMaterial
public struct PhysicallyBasedMaterial: Material {
    // doc: RealityKit/PhysicallyBasedMaterial/Blending-swift.enum
    public enum Blending {''')
cases(['realitykit/physicallybasedmaterial/blending-swift.enum/opaque','realitykit/physicallybasedmaterial/blending-swift.enum/transparent(opacity:)'], '        ')
add('''    }
    // doc: RealityKit/PhysicallyBasedMaterial/Opacity
    public struct Opacity: Hashable, ExpressibleByFloatLiteral {''')
add(emit_members(['realitykit/physicallybasedmaterial/opacity/init(floatliteral:)'], indent='        ').replace('{ fatalError() }','{ }'))
add('''    }
}
''')
s = H + '\n'.join(B) + '\n'
s = finalize(s)
open(SHIMS + 'RealityKit/RealityKit.swift','w').write(s)
