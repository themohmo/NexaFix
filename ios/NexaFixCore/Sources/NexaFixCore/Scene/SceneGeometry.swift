import Foundation

// Triangle meshes for the 3D viewer, built from the saved rooms with no Apple framework involved.
// The app turns a `RoomScene` into whatever its renderer wants; `ScenePicker` (a sibling file) casts
// rays against the very same triangles, so what a person taps is what the maths measures.
//
// Conventions: world space is metres, Y up, right-handed (see Vectors.swift). Triangles wind
// counter-clockwise seen from outside, so the right-hand-rule normal points out of every solid. Every
// face carries its own flat normal (vertices are not shared between faces).
//
// Honesty about geometry: the clear (room-facing) wall faces, the floor, the underside of the ceiling and
// the object boxes come from the scan. Everything else is built by this file from assumptions (wall
// thickness, frame bars, slab thickness). Those meshes are marked `isMeasurable == false` so the viewer
// never lets a tape measurement land on a made-up surface.

// MARK: - Mesh data

/// Flat vertex data for one mesh: positions and normals as x, y, z triples, and triangle indices.
public struct MeshBuffer: Hashable, Sendable {
    /// x, y, z per vertex, world space, metres (includes `Room.floorElevation`).
    public var positions: [Float]
    /// Unit normal x, y, z per vertex, same count as `positions`.
    public var normals: [Float]
    /// Three indices per triangle, counter-clockwise seen from the front.
    public var indices: [UInt32]

    public init(positions: [Float] = [], normals: [Float] = [], indices: [UInt32] = []) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    /// The position of vertex `i`. `i` must be less than `vertexCount`.
    public func vertex(_ i: Int) -> Point3 {
        Point3(Double(positions[3 * i]), Double(positions[3 * i + 1]), Double(positions[3 * i + 2]))
    }

    /// The normal of vertex `i`. `i` must be less than `vertexCount`.
    public func normal(_ i: Int) -> Point3 {
        Point3(Double(normals[3 * i]), Double(normals[3 * i + 1]), Double(normals[3 * i + 2]))
    }

    /// The corners of triangle `t`, or nil when `t` is out of range or an index points past the vertices.
    public func triangle(_ t: Int) -> (Point3, Point3, Point3)? {
        guard t >= 0, 3 * t + 2 < indices.count else { return nil }
        let a = Int(indices[3 * t]), b = Int(indices[3 * t + 1]), c = Int(indices[3 * t + 2])
        let n = vertexCount
        guard a < n, b < n, c < n else { return nil }
        return (vertex(a), vertex(b), vertex(c))
    }

    /// The smallest box around the vertices, or nil for an empty buffer.
    public var bounds: (min: Point3, max: Point3)? {
        guard positions.count >= 3 else { return nil }
        var lo = Point3(Double(positions[0]), Double(positions[1]), Double(positions[2]))
        var hi = lo
        var i = 3
        while i + 2 < positions.count {
            let x = Double(positions[i]), y = Double(positions[i + 1]), z = Double(positions[i + 2])
            lo = Point3(Swift.min(lo.x, x), Swift.min(lo.y, y), Swift.min(lo.z, z))
            hi = Point3(Swift.max(hi.x, x), Swift.max(hi.y, y), Swift.max(hi.z, z))
            i += 3
        }
        return (lo, hi)
    }

    /// One buffer holding all of `buffers`, in order, with indices shifted to match. Used by renderers that
    /// want one draw call per material instead of one per mesh.
    public static func merging(_ buffers: [MeshBuffer]) -> MeshBuffer {
        var merged = MeshBuffer()
        merged.positions.reserveCapacity(buffers.reduce(0) { $0 + $1.positions.count })
        merged.normals.reserveCapacity(buffers.reduce(0) { $0 + $1.normals.count })
        merged.indices.reserveCapacity(buffers.reduce(0) { $0 + $1.indices.count })
        for buffer in buffers where !buffer.isEmpty {
            let base = UInt32(merged.positions.count / 3)
            merged.positions.append(contentsOf: buffer.positions)
            merged.normals.append(contentsOf: buffer.normals)
            merged.indices.append(contentsOf: buffer.indices.map { $0 + base })
        }
        return merged
    }
}

/// What a mesh is made of, so the renderer can pick a look for it.
public enum SceneMaterialKind: String, Codable, CaseIterable, Sendable {
    /// Wall faces and wall tops.
    case wall
    /// The faces inside a door or window opening (jambs, head and sill).
    case wallReveal
    case floor
    case ceiling
    case doorFrame
    case windowGlass
    /// Furniture and fixtures, drawn as boxes.
    case object
    /// Reserved for tape lines drawn in the scene.
    case measureLine
}

/// One piece of the model: a wall piece (or part of one), a floor, a ceiling, an object, a frame or a pane.
public struct SceneMesh: Hashable, Identifiable, Sendable {
    /// Stable across rebuilds: "room:<uuid>:wall:<uuid>:piece:<n>", "room:<uuid>:floor", "room:<uuid>:object:<uuid>",
    /// "room:<uuid>:opening:<uuid>:frame" and so on. A wall piece may add ":shell" (outer face, top, free ends)
    /// or ":reveal" (faces inside an opening) after its own id.
    public var id: String
    public var roomID: UUID
    public var material: SceneMaterialKind
    public var buffer: MeshBuffer
    /// A name a person would recognise: "Wall A", "Door 1 frame", "Sofa 1".
    public var label: String
    /// True when every face of this mesh is scan-derived (see the file header). A tape point may only be
    /// placed on a measurable mesh.
    public var isMeasurable: Bool
    /// Box around the vertices, for quick ray rejection. Equal (zero) for an empty mesh.
    public var boundsMin: Point3
    public var boundsMax: Point3

    public init(id: String, roomID: UUID, material: SceneMaterialKind, buffer: MeshBuffer, label: String,
                isMeasurable: Bool = true) {
        self.id = id
        self.roomID = roomID
        self.material = material
        self.buffer = buffer
        self.label = label
        self.isMeasurable = isMeasurable
        let box = buffer.bounds
        self.boundsMin = box?.min ?? .zero
        self.boundsMax = box?.max ?? .zero
    }
}

// MARK: - Camera

/// An orbit camera: looks at `target` from `distance` metres away. Pure maths for the 3D viewer's camera,
/// so orbiting, panning, zooming and framing are unit-tested without a renderer.
///
/// `yawDegrees` is the azimuth of the camera around the target, 0 at world +Z (looking north, towards plan
/// +y) turning towards +X. `pitchDegrees` is the elevation above the horizon, so 90 looks straight down.
public struct SceneCamera: Hashable, Sendable {
    /// Vertical field of view the viewer renders with, degrees.
    public static let fieldOfViewDegrees = 40.0
    /// Where a new viewer starts looking from: a three-quarter view from the south-west.
    public static let defaultYawDegrees = 35.0
    public static let defaultPitchDegrees = 50.0
    /// The camera never goes below the horizon and never quite straight down (the up vector would flip).
    public static let pitchLimits: ClosedRange<Double> = 5...89

    public var target: Point3
    public var distance: Double
    public var yawDegrees: Double
    public var pitchDegrees: Double

    public init(target: Point3, distance: Double, yawDegrees: Double = SceneCamera.defaultYawDegrees,
                pitchDegrees: Double = SceneCamera.defaultPitchDegrees) {
        self.target = target
        self.distance = distance
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
    }

    private var yawRadians: Double { yawDegrees * Double.pi / 180 }
    private var pitchRadians: Double { pitchDegrees * Double.pi / 180 }

    /// Where the camera is.
    public var position: Point3 {
        let cp = cos(pitchRadians)
        return Point3(target.x + distance * cp * sin(yawRadians),
                      target.y + distance * sin(pitchRadians),
                      target.z + distance * cp * cos(yawRadians))
    }

    /// Unit vector from the camera towards the target.
    public var forward: Point3 {
        let cp = cos(pitchRadians)
        return Point3(-cp * sin(yawRadians), -sin(pitchRadians), -cp * cos(yawRadians))
    }

    /// Unit vector pointing to the right on screen (always horizontal).
    public var right: Point3 { Point3(cos(yawRadians), 0, -sin(yawRadians)) }

    /// Unit vector pointing up on screen.
    public var up: Point3 {
        let f = forward, r = right
        return Point3(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
    }

    /// Unit vector along the ground, away from the camera.
    public var groundForward: Point3 { Point3(-sin(yawRadians), 0, -cos(yawRadians)) }

    /// The camera turned by the given angles. Pitch is held inside `pitchLimits`; yaw wraps into -180...180.
    public func orbited(yawDelta: Double, pitchDelta: Double) -> SceneCamera {
        var copy = self
        copy.yawDegrees = SceneCamera.wrapped(yawDegrees + yawDelta)
        copy.pitchDegrees = Swift.min(Swift.max(pitchDegrees + pitchDelta, SceneCamera.pitchLimits.lowerBound),
                                      SceneCamera.pitchLimits.upperBound)
        return copy
    }

    /// The camera moved closer (`factor` above 1) or further away (below 1), kept inside `limits`.
    /// A factor that is not a positive finite number changes nothing.
    public func zoomed(by factor: Double, limits: ClosedRange<Double>) -> SceneCamera {
        guard factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.distance = Swift.min(Swift.max(distance / factor, limits.lowerBound), limits.upperBound)
        return copy
    }

    /// The target moved along the ground: `right` metres to the screen right, `forward` metres away from the
    /// camera. The target keeps its height.
    public func panned(right dx: Double, forward dz: Double) -> SceneCamera {
        guard dx.isFinite, dz.isFinite else { return self }
        let r = right, f = groundForward
        var copy = self
        copy.target = Point3(target.x + r.x * dx + f.x * dz, target.y, target.z + r.z * dx + f.z * dz)
        return copy
    }

    /// The same view direction, aimed at the middle of the box and far enough back to show all of it.
    /// - Parameters:
    ///   - aspect: view width divided by height.
    ///   - verticalFieldOfViewKnown: pass false when the renderer might apply `fieldOfViewDegrees` to the
    ///     horizontal axis; the distance is then the largest of the possibilities, so nothing is cut off.
    public func framing(boundsMin lo: Point3, boundsMax hi: Point3, aspect: Double,
                        verticalFieldOfViewKnown: Bool = true) -> SceneCamera {
        var copy = self
        copy.target = Point3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let radius = Point3(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z).length / 2
        copy.distance = SceneCamera.fittingDistance(radius: radius, aspect: aspect,
                                                    verticalFieldOfViewKnown: verticalFieldOfViewKnown)
        return copy
    }

    /// How far back a camera must sit to see a sphere of `radius` metres in full, with a little margin.
    public static func fittingDistance(radius: Double, aspect: Double, verticalFieldOfViewKnown: Bool = true) -> Double {
        let r = radius.isFinite ? Swift.max(radius, 0.05) : 0.05
        let a = aspect.isFinite && aspect > 0.05 ? aspect : 1
        let tv = tan(fieldOfViewDegrees * Double.pi / 360)
        var limiting = Swift.min(tv, tv * a)
        if !verticalFieldOfViewKnown { limiting = Swift.min(limiting, tv / a) }
        return r / sin(atan(limiting)) * 1.1
    }

    /// Zoom limits that suit a scene of the given size: close enough to read a detail, far enough to see the lot.
    public static func distanceLimits(forSceneDiagonal diagonal: Double) -> ClosedRange<Double> {
        let d = diagonal.isFinite ? Swift.max(diagonal, 1) : 1
        return 0.3...Swift.max(12, d * 4)
    }

    /// Angles in -180...180.
    public static func wrapped(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// `to` with its yaw shifted by whole turns so that going there from `self` takes the short way round.
    public func shortestPath(to other: SceneCamera) -> SceneCamera {
        var copy = other
        copy.yawDegrees = yawDegrees + SceneCamera.wrapped(other.yawDegrees - yawDegrees)
        return copy
    }
}

// MARK: - Scene

/// Everything the 3D viewer draws and the picker tests rays against.
public struct RoomScene: Hashable, Sendable {
    public var meshes: [SceneMesh]
    /// Box around every vertex of every mesh. Both zero for an empty scene.
    public var boundsMin: Point3
    public var boundsMax: Point3
    /// A good first view of the whole scene (before the real view shape is known; use `camera(framingRoom:aspect:)`).
    public var suggestedCamera: SceneCamera

    public init(meshes: [SceneMesh]) {
        let box = RoomScene.union(of: meshes)
        let lo = box?.min ?? Point3.zero
        let hi = box?.max ?? Point3.zero
        self.meshes = meshes
        self.boundsMin = lo
        self.boundsMax = hi
        self.suggestedCamera = RoomScene.camera(min: lo, max: hi, hasContent: box != nil, aspect: 1)
    }

    public static let empty = RoomScene(meshes: [])

    public var isEmpty: Bool { meshes.isEmpty }
    public var center: Point3 {
        Point3((boundsMin.x + boundsMax.x) / 2, (boundsMin.y + boundsMax.y) / 2, (boundsMin.z + boundsMax.z) / 2)
    }
    /// Length of the box's diagonal, metres.
    public var diagonal: Double {
        Point3(boundsMax.x - boundsMin.x, boundsMax.y - boundsMin.y, boundsMax.z - boundsMin.z).length
    }

    /// The box around one room's meshes, or nil when the room has none.
    public func bounds(forRoom id: UUID) -> (min: Point3, max: Point3)? {
        RoomScene.union(of: meshes.filter { $0.roomID == id })
    }

    /// A camera that shows the whole scene, or one room when `roomID` names a room that has meshes.
    /// - Parameter aspect: view width divided by height.
    public func camera(framingRoom roomID: UUID?, aspect: Double, verticalFieldOfViewKnown: Bool = true) -> SceneCamera {
        if let id = roomID, let box = bounds(forRoom: id) {
            return RoomScene.camera(min: box.min, max: box.max, hasContent: true, aspect: aspect,
                                    verticalFieldOfViewKnown: verticalFieldOfViewKnown)
        }
        return RoomScene.camera(min: boundsMin, max: boundsMax, hasContent: !meshes.isEmpty, aspect: aspect,
                                verticalFieldOfViewKnown: verticalFieldOfViewKnown)
    }

    fileprivate static func camera(min lo: Point3, max hi: Point3, hasContent: Bool, aspect: Double,
                                   verticalFieldOfViewKnown: Bool = true) -> SceneCamera {
        guard hasContent else { return SceneCamera(target: .zero, distance: 6) }
        return SceneCamera(target: .zero, distance: 1)
            .framing(boundsMin: lo, boundsMax: hi, aspect: aspect, verticalFieldOfViewKnown: verticalFieldOfViewKnown)
    }

    fileprivate static func union(of meshes: [SceneMesh]) -> (min: Point3, max: Point3)? {
        var lo: Point3?
        var hi: Point3?
        for mesh in meshes where !mesh.buffer.isEmpty {
            if let l = lo, let h = hi {
                lo = Point3(Swift.min(l.x, mesh.boundsMin.x), Swift.min(l.y, mesh.boundsMin.y), Swift.min(l.z, mesh.boundsMin.z))
                hi = Point3(Swift.max(h.x, mesh.boundsMax.x), Swift.max(h.y, mesh.boundsMax.y), Swift.max(h.z, mesh.boundsMax.z))
            } else {
                lo = mesh.boundsMin
                hi = mesh.boundsMax
            }
        }
        if let l = lo, let h = hi { return (l, h) }
        return nil
    }
}

// MARK: - Options

/// What `SceneBuilder` builds and how thick it makes things.
public struct SceneOptions: Hashable, Sendable {
    /// Wall thickness, metres. Walls are built OUTWARD from the clear face, so every clear dimension of the
    /// room is exactly what was scanned. Held between 1 cm and 1 m.
    public var wallThickness: Double
    /// Build the ceiling (its underside, and a slab above it when `ceilingSlabThickness` is above zero).
    public var includeCeiling: Bool
    /// Build furniture and fixtures as boxes.
    public var includeObjects: Bool
    /// Build door and window frames and window panes.
    public var includeOpeningFrames: Bool
    /// Thickness of the slab above the ceiling plane, metres. Zero builds only the underside.
    public var ceilingSlabThickness: Double

    public init(wallThickness: Double = 0.12, includeCeiling: Bool = false, includeObjects: Bool = true,
                includeOpeningFrames: Bool = true, ceilingSlabThickness: Double = 0.05) {
        self.wallThickness = wallThickness
        self.includeCeiling = includeCeiling
        self.includeObjects = includeObjects
        self.includeOpeningFrames = includeOpeningFrames
        self.ceilingSlabThickness = ceilingSlabThickness
    }

    public static let standard = SceneOptions()
}

// MARK: - Builder

/// Builds the 3D model of a floor from its rooms.
public enum SceneBuilder {
    /// Frame bar width and the glass thickness, metres.
    static let frameBarWidth = 0.05
    static let frameBarDepth = 0.06
    static let glassThickness = 0.008
    /// Faces and wall pieces smaller than this (in metres, or square metres for areas) are dropped.
    static let minimumSize = 1e-6

    /// The model of `rooms`, which share one coordinate frame. Rooms are built one after another in the order
    /// given, so ids and order are deterministic. A room with fewer than three walls or a non-finite corner
    /// gives nothing.
    public static func scene(for rooms: [Room], options: SceneOptions = SceneOptions()) -> RoomScene {
        var meshes: [SceneMesh] = []
        for room in rooms { meshes.append(contentsOf: self.meshes(for: room, options: options)) }
        return RoomScene(meshes: meshes)
    }

    /// The meshes of one room.
    ///
    /// - Walls come from `Room.wallPieces()`: boxes built outward from the clear face, mitred with the
    ///   neighbouring solid wall so that no gap shows at a corner. Faces that touch another piece (the side of a
    ///   piece against its neighbour, the mitre against the next wall) are left out, so the walls are free of
    ///   hidden internal faces and translucent walls look clean. Open-plan (`.virtual`) walls give nothing.
    /// - The floor is the room outline, triangulated (L and U shapes work). The ceiling is its mirror image at
    ///   the scanned ceiling height.
    /// - Objects are boxes from footprint, elevation and height.
    /// - Door and window frames are four thin bars inside the opening; windows also get a glass pane.
    public static func meshes(for room: Room, options: SceneOptions = SceneOptions()) -> [SceneMesh] {
        RoomMeshBuilder(room: room, options: options).build()
    }
}

// MARK: - Small vector helpers (module-internal)

enum SceneVector {
    static func cross(_ a: Point3, _ b: Point3) -> Point3 {
        Point3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func normalized(_ a: Point3) -> Point3? {
        let l = a.length
        guard l.isFinite, l > 1e-12 else { return nil }
        return a / l
    }
}

// MARK: - Face writer

/// Collects planar faces into one buffer. Each face gets its own vertices and one flat normal.
struct FaceWriter {
    private(set) var positions: [Float] = []
    private(set) var normals: [Float] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var buffer: MeshBuffer { MeshBuffer(positions: positions, normals: normals, indices: indices) }

    /// Adds a planar convex polygon. The order of `points` does not matter: the face is wound so that its
    /// normal points the same way as `facing`. A polygon with no area is skipped.
    mutating func addFace(_ points: [Point3], facing hint: Point3) {
        guard points.count >= 3 else { return }
        // Newell's method: robust for any planar polygon.
        var n = Point3.zero
        for i in 0..<points.count {
            let p = points[i], q = points[(i + 1) % points.count]
            n = Point3(n.x + (p.y - q.y) * (p.z + q.z),
                       n.y + (p.z - q.z) * (p.x + q.x),
                       n.z + (p.x - q.x) * (p.y + q.y))
        }
        let area = n.length / 2
        guard area.isFinite, area > SceneBuilder.minimumSize, let unit = SceneVector.normalized(n) else { return }
        var ordered = points
        var normal = unit
        if unit.dot(hint) < 0 {
            ordered.reverse()
            normal = Point3(-unit.x, -unit.y, -unit.z)
        }
        let base = UInt32(positions.count / 3)
        for p in ordered {
            positions.append(Float(p.x))
            positions.append(Float(p.y))
            positions.append(Float(p.z))
            normals.append(Float(normal.x))
            normals.append(Float(normal.y))
            normals.append(Float(normal.z))
        }
        for i in 1..<(ordered.count - 1) {
            indices.append(base)
            indices.append(base + UInt32(i))
            indices.append(base + UInt32(i + 1))
        }
    }
}

// MARK: - Room mesh builder

/// A solid wall prepared for extrusion: the vectors, the mitred outer corners and who it joins.
private struct SolidWall {
    let wall: Wall
    let index: Int
    let start: Point2
    let direction: Point2
    /// Unit normal into the room.
    let inward: Point2
    let length: Double
    var outerStart: Point2
    var outerEnd: Point2
    /// Index into the frames array of the solid wall mitred at the start / at the end, if any.
    var previous: Int?
    var next: Int?

    func inner(at s: Double) -> Point2 { start + direction * s }

    /// The point on the outer face `s` metres along the wall; the mitred corner at either end.
    func outer(at s: Double, thickness: Double) -> Point2 {
        if s <= 1e-9 { return outerStart }
        if s >= length - 1e-9 { return outerEnd }
        return start + direction * s - inward * thickness
    }
}

private struct RoomMeshBuilder {
    let room: Room
    let options: SceneOptions
    let thickness: Double
    let floorY: Double
    let clockwise: Bool

    init(room: Room, options: SceneOptions) {
        self.room = room
        self.options = options
        let t = options.wallThickness
        self.thickness = t.isFinite ? Swift.min(Swift.max(t, 0.01), 1) : 0.12
        self.floorY = room.floorElevation.isFinite ? room.floorElevation : 0
        self.clockwise = !Polygon.isCounterClockwise(room.outline)
    }

    private var roomPrefix: String { "room:\(room.id.uuidString)" }

    func build() -> [SceneMesh] {
        guard room.walls.count >= 3 else { return [] }
        for wall in room.walls {
            guard wall.start.x.isFinite, wall.start.y.isFinite, wall.end.x.isFinite, wall.end.y.isFinite else { return [] }
        }
        guard Polygon.area(room.outline) > 1e-9 else { return [] }

        var meshes: [SceneMesh] = []
        let frames = makeFrames()
        let piecesByWall = Dictionary(grouping: room.wallPieces(), by: \.wallID)
        for frame in frames.compactMap({ $0 }) {
            meshes.append(contentsOf: wallMeshes(frame, frames: frames, piecesByWall: piecesByWall))
        }
        meshes.append(contentsOf: floorMeshes())
        if options.includeCeiling { meshes.append(contentsOf: ceilingMeshes()) }
        if options.includeOpeningFrames { meshes.append(contentsOf: openingMeshes(frames: frames)) }
        if options.includeObjects { meshes.append(contentsOf: objectMeshes()) }
        return meshes
    }

    // MARK: Wall frames

    /// One entry per wall of the loop: nil for open-plan walls and walls too short to build.
    private func makeFrames() -> [SolidWall?] {
        let n = room.walls.count
        var frames: [SolidWall?] = room.walls.enumerated().map { index, wall in
            guard wall.kind == .solid else { return nil }
            let length = wall.start.distance(to: wall.end)
            guard length.isFinite, length > 1e-6 else { return nil }
            let direction = wall.direction
            let inward = clockwise ? -direction.perpendicularCCW : direction.perpendicularCCW
            return SolidWall(wall: wall, index: index, start: wall.start, direction: direction, inward: inward,
                             length: length, outerStart: wall.start - inward * thickness,
                             outerEnd: wall.end - inward * thickness, previous: nil, next: nil)
        }
        // A wall is mitred with the wall before / after it when that one is solid and meets it at the same corner.
        // Zero-length walls in between are skipped, as in the plan drawing.
        func neighbour(of i: Int, step: Int) -> Int? {
            var j = (i + step + n) % n
            var guardCount = 0
            while room.walls[j].start.distance(to: room.walls[j].end) <= 1e-6 {
                j = (j + step + n) % n
                guardCount += 1
                if guardCount > n { return nil }
            }
            return j == i ? nil : j
        }
        for i in 0..<n {
            guard let me = frames[i] else { continue }
            if let p = neighbour(of: i, step: -1), let prev = frames[p],
               prev.wall.end.distance(to: me.wall.start) < 1e-3 {
                frames[i]?.previous = p
                let m = SceneBuilder.mitre(previous: prev.inward, current: me.inward)
                frames[i]?.outerStart = me.start - m * thickness
            }
            if let q = neighbour(of: i, step: 1), let nextFrame = frames[q],
               me.wall.end.distance(to: nextFrame.wall.start) < 1e-3 {
                frames[i]?.next = q
                let m = SceneBuilder.mitre(previous: me.inward, current: nextFrame.inward)
                frames[i]?.outerEnd = me.wall.end - m * thickness
            }
        }
        return frames
    }

    private func world(_ p: Point2, _ y: Double) -> Point3 { Point3(p.x, y, -p.y) }
    private func worldVector(_ v: Point2) -> Point3 { Point3(v.x, 0, -v.y) }

    // MARK: Walls

    private func wallMeshes(_ f: SolidWall, frames: [SolidWall?], piecesByWall: [UUID: [WallPiece]]) -> [SceneMesh] {
        let pieces = piecesByWall[f.wall.id] ?? []
        let wallHeight = f.wall.height.scanned
        let inwardHint = worldVector(f.inward)
        let outwardHint = worldVector(-f.inward)
        let alongHint = worldVector(f.direction)
        let backHint = worldVector(-f.direction)
        let title = room.wallTitle(at: f.index)
        var meshes: [SceneMesh] = []

        for (n, piece) in pieces.enumerated() {
            let a = piece.along.lowerBound, b = piece.along.upperBound
            let y0 = floorY + piece.bottom, y1 = floorY + piece.top
            let ai = f.inner(at: a), bi = f.inner(at: b)
            let ao = f.outer(at: a, thickness: thickness), bo = f.outer(at: b, thickness: thickness)

            var inner = FaceWriter()
            var shell = FaceWriter()
            var reveal = FaceWriter()

            // The clear face: what the scan measured.
            inner.addFace([world(ai, y0), world(bi, y0), world(bi, y1), world(ai, y1)], facing: inwardHint)
            // The outer face and the top.
            shell.addFace([world(ao, y0), world(bo, y0), world(bo, y1), world(ao, y1)], facing: outwardHint)
            let topFace = [world(ai, y1), world(bi, y1), world(bo, y1), world(ao, y1)]
            if piece.top >= wallHeight - 1e-9 {
                shell.addFace(topFace, facing: Point3(0, 1, 0))
            } else {
                reveal.addFace(topFace, facing: Point3(0, 1, 0))
            }
            if piece.bottom > 1e-9 {
                reveal.addFace([world(ai, y0), world(bi, y0), world(bo, y0), world(ao, y0)], facing: Point3(0, -1, 0))
            }

            // The two ends. Whatever a neighbour covers is hidden; the rest is visible.
            let startCover = cover(atStartOf: piece, wall: f, pieces: pieces, frames: frames, piecesByWall: piecesByWall)
            let endCover = cover(atEndOf: piece, wall: f, pieces: pieces, frames: frames, piecesByWall: piecesByWall)
            let startIsFreeCorner = a <= 1e-9 && f.previous == nil
            let endIsFreeCorner = b >= f.length - 1e-9 && f.next == nil
            for r in SceneBuilder.subtract(piece.bottom...piece.top, covered: startCover) {
                let face = [world(ai, floorY + r.lowerBound), world(ai, floorY + r.upperBound),
                            world(ao, floorY + r.upperBound), world(ao, floorY + r.lowerBound)]
                if startIsFreeCorner { shell.addFace(face, facing: backHint) } else { reveal.addFace(face, facing: backHint) }
            }
            for r in SceneBuilder.subtract(piece.bottom...piece.top, covered: endCover) {
                let face = [world(bi, floorY + r.lowerBound), world(bi, floorY + r.upperBound),
                            world(bo, floorY + r.upperBound), world(bo, floorY + r.lowerBound)]
                if endIsFreeCorner { shell.addFace(face, facing: alongHint) } else { reveal.addFace(face, facing: alongHint) }
            }

            let base = "\(roomPrefix):wall:\(f.wall.id.uuidString):piece:\(n)"
            let role: String
            switch piece.role {
            case .full: role = ""
            case .aboveOpening: role = ", above opening"
            case .belowWindow: role = ", below window"
            }
            let label = title + role
            if !inner.isEmpty {
                meshes.append(SceneMesh(id: base, roomID: room.id, material: .wall, buffer: inner.buffer,
                                        label: label, isMeasurable: true))
            }
            if !shell.isEmpty {
                meshes.append(SceneMesh(id: base + ":shell", roomID: room.id, material: .wall, buffer: shell.buffer,
                                        label: label, isMeasurable: false))
            }
            if !reveal.isEmpty {
                meshes.append(SceneMesh(id: base + ":reveal", roomID: room.id, material: .wallReveal,
                                        buffer: reveal.buffer, label: label, isMeasurable: false))
            }
        }
        return meshes
    }

    /// Vertical ranges (metres above the floor) that other solid pieces cover at the start of `piece`.
    private func cover(atStartOf piece: WallPiece, wall f: SolidWall, pieces: [WallPiece], frames: [SolidWall?],
                       piecesByWall: [UUID: [WallPiece]]) -> [ClosedRange<Double>] {
        if piece.along.lowerBound <= 1e-9 {
            guard let p = f.previous, let prev = frames[p] else { return [] }
            return (piecesByWall[prev.wall.id] ?? [])
                .filter { $0.along.upperBound >= prev.length - 1e-9 }
                .map { $0.bottom...$0.top }
        }
        return pieces
            .filter { abs($0.along.upperBound - piece.along.lowerBound) <= 1e-9 }
            .map { $0.bottom...$0.top }
    }

    /// Vertical ranges that other solid pieces cover at the end of `piece`.
    private func cover(atEndOf piece: WallPiece, wall f: SolidWall, pieces: [WallPiece], frames: [SolidWall?],
                       piecesByWall: [UUID: [WallPiece]]) -> [ClosedRange<Double>] {
        if piece.along.upperBound >= f.length - 1e-9 {
            guard let q = f.next, let next = frames[q] else { return [] }
            return (piecesByWall[next.wall.id] ?? [])
                .filter { $0.along.lowerBound <= 1e-9 }
                .map { $0.bottom...$0.top }
        }
        return pieces
            .filter { abs($0.along.lowerBound - piece.along.upperBound) <= 1e-9 }
            .map { $0.bottom...$0.top }
    }

    // MARK: Floor and ceiling

    private var roomTitle: String { room.name.isEmpty ? room.kind.displayName : room.name }

    private func floorMeshes() -> [SceneMesh] {
        let outline = room.outline
        var writer = FaceWriter()
        for t in Polygon.triangulate(outline) {
            writer.addFace(t.map { world(outline[$0], floorY) }, facing: Point3(0, 1, 0))
        }
        guard !writer.isEmpty else { return [] }
        return [SceneMesh(id: "\(roomPrefix):floor", roomID: room.id, material: .floor, buffer: writer.buffer,
                          label: "\(roomTitle) floor", isMeasurable: true)]
    }

    /// The scanned ceiling height, or the tallest wall when the ceiling height is unusable.
    private var ceilingHeight: Double {
        let c = room.ceilingHeight.scanned
        if c.isFinite, c > 0.05 { return c }
        let tallest = room.walls.map { $0.height.scanned }.filter { $0.isFinite }.max() ?? 0
        return tallest > 0.05 ? tallest : 2.4
    }

    private func ceilingMeshes() -> [SceneMesh] {
        let outline = room.outline
        let triangles = Polygon.triangulate(outline)
        guard !triangles.isEmpty else { return [] }
        let ceilingY = floorY + ceilingHeight
        var meshes: [SceneMesh] = []

        var underside = FaceWriter()
        for t in triangles {
            underside.addFace(t.map { world(outline[$0], ceilingY) }, facing: Point3(0, -1, 0))
        }
        if !underside.isEmpty {
            meshes.append(SceneMesh(id: "\(roomPrefix):ceiling", roomID: room.id, material: .ceiling,
                                    buffer: underside.buffer, label: "\(roomTitle) ceiling", isMeasurable: true))
        }

        let slab = options.ceilingSlabThickness
        if slab.isFinite, slab > 1e-4 {
            let topY = ceilingY + Swift.min(slab, 1)
            var writer = FaceWriter()
            for t in triangles {
                writer.addFace(t.map { world(outline[$0], topY) }, facing: Point3(0, 1, 0))
            }
            for i in 0..<outline.count {
                let p = outline[i], q = outline[(i + 1) % outline.count]
                let edge = (q - p).normalized
                let outward = clockwise ? edge.perpendicularCCW : -edge.perpendicularCCW
                writer.addFace([world(p, ceilingY), world(q, ceilingY), world(q, topY), world(p, topY)],
                               facing: worldVector(outward))
            }
            if !writer.isEmpty {
                meshes.append(SceneMesh(id: "\(roomPrefix):ceiling:slab", roomID: room.id, material: .ceiling,
                                        buffer: writer.buffer, label: "\(roomTitle) ceiling", isMeasurable: false))
            }
        }
        return meshes
    }

    // MARK: Objects

    private func objectMeshes() -> [SceneMesh] {
        var meshes: [SceneMesh] = []
        var counters: [ObjectKind: Int] = [:]
        for object in room.objects {
            let n = (counters[object.kind] ?? 0) + 1
            counters[object.kind] = n
            guard object.center.x.isFinite, object.center.y.isFinite, object.yaw.isFinite,
                  object.width.isFinite, object.depth.isFinite, object.height.isFinite, object.elevation.isFinite,
                  object.width > 0.01, object.depth > 0.01, object.height > 0.01 else { continue }
            let footprint = object.footprint
            let y0 = floorY + object.elevation, y1 = y0 + object.height
            var writer = FaceWriter()
            writer.addFace(footprint.map { world($0, y0) }, facing: Point3(0, -1, 0))
            writer.addFace(footprint.map { world($0, y1) }, facing: Point3(0, 1, 0))
            for i in 0..<footprint.count {
                let p = footprint[i], q = footprint[(i + 1) % footprint.count]
                let edge = (q - p).normalized
                // The footprint is counter-clockwise, so outside is to the right of each edge.
                let outward = -edge.perpendicularCCW
                writer.addFace([world(p, y0), world(q, y0), world(q, y1), world(p, y1)], facing: worldVector(outward))
            }
            guard !writer.isEmpty else { continue }
            meshes.append(SceneMesh(id: "\(roomPrefix):object:\(object.id.uuidString)", roomID: room.id,
                                    material: .object, buffer: writer.buffer,
                                    label: "\(object.kind.displayName) \(n)", isMeasurable: true))
        }
        return meshes
    }

    // MARK: Door and window frames

    private func openingMeshes(frames: [SolidWall?]) -> [SceneMesh] {
        var meshes: [SceneMesh] = []
        let titles = room.measureOpeningTitles()
        for index in room.measureOpeningOrder() {
            let opening = room.openings[index]
            guard let wallID = opening.wallID,
                  let f = frames.compactMap({ $0 }).first(where: { $0.wall.id == wallID }),
                  let hole = SceneBuilder.clip(opening, to: f.wall) else { continue }
            let title = titles[opening.id] ?? opening.kind.displayName
            let bar = Swift.min(SceneBuilder.frameBarWidth, 0.25 * Swift.min(hole.x1 - hole.x0, hole.y1 - hole.y0))
            guard bar >= 0.01, hole.x1 - hole.x0 >= 0.2, hole.y1 - hole.y0 >= 0.2 else { continue }
            let eps = 0.002
            let depth = Swift.min(thickness, SceneBuilder.frameBarDepth)
            let hasSill = opening.kind == .window || hole.y0 > 0.05
            let u0 = hole.x0 + eps, u1 = hole.x1 - eps
            let v0 = hole.y0 + eps, v1 = hole.y1 - eps

            var frame = FaceWriter()
            let jambBottom = hasSill ? v0 + bar : v0
            box(&frame, f, u0, u0 + bar, jambBottom, v1, 0, depth)
            box(&frame, f, u1 - bar, u1, jambBottom, v1, 0, depth)
            box(&frame, f, u0, u1, v1 - bar, v1, 0, depth)
            if hasSill { box(&frame, f, u0, u1, v0, v0 + bar, 0, depth) }
            if !frame.isEmpty {
                meshes.append(SceneMesh(id: "\(roomPrefix):opening:\(opening.id.uuidString):frame", roomID: room.id,
                                        material: .doorFrame, buffer: frame.buffer, label: "\(title) frame",
                                        isMeasurable: false))
            }

            if opening.kind == .window {
                var glass = FaceWriter()
                let mid = thickness / 2
                box(&glass, f, u0 + bar, u1 - bar, v0 + bar, v1 - bar,
                    mid - SceneBuilder.glassThickness / 2, mid + SceneBuilder.glassThickness / 2)
                if !glass.isEmpty {
                    meshes.append(SceneMesh(id: "\(roomPrefix):opening:\(opening.id.uuidString):glass", roomID: room.id,
                                            material: .windowGlass, buffer: glass.buffer, label: "\(title) glass",
                                            isMeasurable: false))
                }
            }
        }
        return meshes
    }

    /// A closed box in a wall's own frame: `u` metres along the wall, `v` metres above the floor, `w` metres
    /// outward from the clear face.
    private func box(_ writer: inout FaceWriter, _ f: SolidWall, _ u0: Double, _ u1: Double, _ v0: Double,
                     _ v1: Double, _ w0: Double, _ w1: Double) {
        guard u1 - u0 > 1e-6, v1 - v0 > 1e-6, w1 - w0 > 1e-6 else { return }
        func p(_ u: Double, _ v: Double, _ w: Double) -> Point3 {
            world(f.start + f.direction * u - f.inward * w, floorY + v)
        }
        let along = worldVector(f.direction)
        let outward = worldVector(-f.inward)
        let up = Point3(0, 1, 0)
        func neg(_ a: Point3) -> Point3 { Point3(-a.x, -a.y, -a.z) }
        writer.addFace([p(u0, v0, w0), p(u0, v1, w0), p(u0, v1, w1), p(u0, v0, w1)], facing: neg(along))
        writer.addFace([p(u1, v0, w0), p(u1, v1, w0), p(u1, v1, w1), p(u1, v0, w1)], facing: along)
        writer.addFace([p(u0, v0, w0), p(u1, v0, w0), p(u1, v0, w1), p(u0, v0, w1)], facing: neg(up))
        writer.addFace([p(u0, v1, w0), p(u1, v1, w0), p(u1, v1, w1), p(u0, v1, w1)], facing: up)
        writer.addFace([p(u0, v0, w0), p(u1, v0, w0), p(u1, v1, w0), p(u0, v1, w0)], facing: neg(outward))
        writer.addFace([p(u0, v0, w1), p(u1, v0, w1), p(u1, v1, w1), p(u0, v1, w1)], facing: outward)
    }
}

// MARK: - Shared geometry helpers

extension SceneBuilder {
    /// Displacement of the offset outline's corner, for a unit offset along the inward normals of two
    /// consecutive walls: where the two offset lines meet. Limited to three times the offset so a very sharp
    /// corner does not shoot a spike out of the model. Same rule as the plan drawing's wall bands.
    static func mitre(previous: Point2, current: Point2) -> Point2 {
        let denominator = 1 + previous.dot(current)
        if denominator < 1e-6 { return current }
        var m = (previous + current) / denominator
        let length = m.length
        if length > 3 { m = m * (3 / length) }
        return m
    }

    /// The parts of `range` that no range in `covered` touches. Pieces shorter than a micrometre are dropped.
    static func subtract(_ range: ClosedRange<Double>, covered: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var remaining: [ClosedRange<Double>] = []
        var cursor = range.lowerBound
        for c in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if c.lowerBound - cursor > minimumSize {
                remaining.append(cursor...Swift.min(c.lowerBound, range.upperBound))
            }
            cursor = Swift.max(cursor, c.upperBound)
            if cursor >= range.upperBound { break }
        }
        if range.upperBound - cursor > minimumSize { remaining.append(cursor...range.upperBound) }
        return remaining.filter { $0.upperBound - $0.lowerBound > minimumSize }
    }

    /// An opening clipped to the extent of its wall, in the wall's own frame (metres along the wall and above
    /// the floor), or nil when nothing is left. The same clipping `Room.wallPieces()` applies.
    static func clip(_ opening: Opening, to wall: Wall) -> (x0: Double, x1: Double, y0: Double, y1: Double)? {
        let length = wall.geometricLength, height = wall.height.scanned
        let offset = opening.offsetFromWallStart, width = opening.width.scanned
        let sill = opening.sillHeight.scanned, openingHeight = opening.height.scanned
        guard length.isFinite, height.isFinite, offset.isFinite, width.isFinite, sill.isFinite,
              openingHeight.isFinite else { return nil }
        let x0 = Swift.max(0, offset), x1 = Swift.min(length, offset + width)
        let y0 = Swift.max(0, sill), y1 = Swift.min(height, sill + openingHeight)
        guard x1 - x0 > 1e-10, y1 - y0 > 1e-10 else { return nil }
        return (x0, x1, y0, y1)
    }
}
