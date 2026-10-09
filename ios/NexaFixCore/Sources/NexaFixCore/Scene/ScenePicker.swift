import Foundation

// Picking in the 3D viewer: which point of the model is under a tap, and which known corner (if any) that
// tap should jump to. Pure maths on the same triangles the renderer draws (`RoomScene`), so it is
// unit-tested off-device. The app turns a screen tap into a `Ray3` with its renderer's unproject call.

/// A half-line in world space (metres, Y up).
public struct Ray3: Hashable, Sendable {
    public var origin: Point3
    /// Direction of travel. Need not be a unit vector, but must not be zero.
    public var direction: Point3

    public init(origin: Point3, direction: Point3) {
        self.origin = origin
        self.direction = direction
    }

    /// Finite origin, finite direction, and a direction that is not (nearly) zero.
    public var isValid: Bool {
        origin.x.isFinite && origin.y.isFinite && origin.z.isFinite
            && direction.x.isFinite && direction.y.isFinite && direction.z.isFinite
            && direction.length > 1e-12
    }

    /// The direction scaled to length 1, or nil for an invalid ray.
    public var unitDirection: Point3? {
        isValid ? direction / direction.length : nil
    }

    /// The point `t` direction-lengths along the ray.
    public func point(at t: Double) -> Point3 { origin + direction * t }

    /// Where the ray crosses the horizontal plane at height `y`, or nil when it never does in front of the
    /// origin (parallel or pointing away).
    public func intersectionWithPlane(y: Double) -> Point3? {
        guard isValid, abs(direction.y) > 1e-12 else { return nil }
        let t = (y - origin.y) / direction.y
        guard t.isFinite, t > 0 else { return nil }
        return point(at: t)
    }
}

/// A straight edge worth snapping to, such as the vertical line where two walls meet.
public struct SnapEdge: Hashable, Identifiable, Sendable {
    /// Stable across runs: "ec:<wall uuid>" (corner edge), "eb:<wall uuid>" (wall base), "et:<wall uuid>" (wall top).
    public var id: String
    public var a: Point3
    public var b: Point3
    public var label: String

    public init(id: String, a: Point3, b: Point3, label: String) {
        self.id = id
        self.a = a
        self.b = b
        self.label = label
    }
}

/// How the picker treats made-up geometry.
public enum PickMode: Sendable {
    /// Every surface can be hit, including the outer faces and tops of walls. The result says whether the
    /// surface is `isMeasurable`. Use while walls are solid: what you see is what you tap.
    case opaque
    /// Only scan-derived surfaces can be hit; made-up ones are ignored as if they were glass. Use while
    /// walls are see-through.
    case seeThrough
}

/// What a ray found.
public struct PickResult: Hashable, Sendable {
    /// Where to put a measurement point: the snapped corner when a snap engaged, else the surface point.
    public var point: Point3
    /// Where the ray met a surface, or nil when it met none (a snap can still engage).
    public var surfacePoint: Point3?
    /// Unit normal of the surface that was hit, facing the ray; the reverse of the ray when there was no surface.
    public var normal: Point3
    /// The mesh that was hit.
    public var meshID: String?
    /// Distance from the ray origin to `surfacePoint` (or to `point` when there was no surface), metres.
    public var distance: Double
    /// The corner the point snapped to, if one did.
    public var snapped: SnapPoint?
    /// The edge the point snapped to, if one did (only when no corner snapped).
    public var snappedEdge: SnapEdge?
    /// False when the first surface hit is built from assumptions (outside of a wall, its top, a frame bar):
    /// a measurement placed there would include made-up numbers.
    public var isMeasurable: Bool

    public var isSnapped: Bool { snapped != nil || snappedEdge != nil }
    /// "Floor corner A", "Wall A base" ... for the thing snapped to.
    public var snapLabel: String? { snapped?.label ?? snappedEdge?.label }

    public init(point: Point3, surfacePoint: Point3?, normal: Point3, meshID: String?, distance: Double,
                snapped: SnapPoint?, snappedEdge: SnapEdge?, isMeasurable: Bool) {
        self.point = point
        self.surfacePoint = surfacePoint
        self.normal = normal
        self.meshID = meshID
        self.distance = distance
        self.snapped = snapped
        self.snappedEdge = snappedEdge
        self.isMeasurable = isMeasurable
    }
}

public enum ScenePicker {
    /// How close to a surface a snap point may be and still count as visible, metres. Snap points sit on
    /// surfaces, so a hit this close to one is the surface it belongs to.
    static let visibilityMargin = 0.02

    /// Casts `ray` into `scene` and returns the surface it hits first, or a corner it should snap to.
    ///
    /// - Snapping prefers corners near the ray over the raw surface point. A corner qualifies when it is
    ///   in front of the ray, no nearer surface hides it, and its distance from the ray is at most
    ///   `max(snapRadius, distance x tan(snapAngle))`: an angle, so the catch zone grows with distance and
    ///   matches a fingertip on screen, and never shrinks below `snapRadius` metres up close. The corner
    ///   nearest to the ray (by angle) wins; ties go to the nearer, then to the smaller id.
    /// - With no corner, the closest point on a `snapEdges` edge is used the same way.
    /// - With no snap, the raw surface hit is returned; nil when the ray hits nothing at all.
    /// - Faces that point away from the ray are ignored (`cullBackFaces`), so a ray from outside the model
    ///   passes through the inside face of a wall it has already entered, and a ray from below passes up
    ///   through the floor.
    /// - Openings are real holes in the walls, so a ray through a door hits whatever is beyond it.
    ///
    /// - Parameters:
    ///   - snapAngle: degrees.
    ///   - snapRadius: metres.
    ///   - mode: whether made-up geometry blocks the ray (`opaque`) or not (`seeThrough`).
    public static func pick(ray: Ray3, in scene: RoomScene, snapPoints: [SnapPoint], snapAngle: Double = 2.5,
                            snapRadius: Double = 0.08, snapEdges: [SnapEdge] = [], mode: PickMode = .opaque,
                            cullBackFaces: Bool = true) -> PickResult? {
        guard let d = ray.unitDirection else { return nil }
        let o = ray.origin
        let surface = firstHit(origin: o, direction: d, in: scene, maxDistance: .infinity, mode: mode,
                               cull: cullBackFaces)
        let angle = snapAngle.isFinite ? Swift.min(Swift.max(snapAngle, 0), 45) : 2.5
        let radius = snapRadius.isFinite ? Swift.max(snapRadius, 0) : 0.08
        let tanAngle = tan(angle * Double.pi / 180)

        func visible(_ target: Point3) -> Bool {
            let v = target - o
            let distance = v.length
            guard distance > visibilityMargin else { return true }
            return firstHit(origin: o, direction: v / distance, in: scene,
                            maxDistance: distance - visibilityMargin, mode: mode, cull: cullBackFaces) == nil
        }

        // 1. A corner near the ray.
        var corners: [(angle: Double, t: Double, point: SnapPoint)] = []
        for sp in snapPoints {
            let v = sp.position - o
            guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { continue }
            let t = v.dot(d)
            guard t > 1e-6 else { continue }
            let perpendicular = (v - d * t).length
            guard perpendicular <= Swift.max(radius, t * tanAngle) else { continue }
            corners.append((atan2(perpendicular, t), t, sp))
        }
        corners.sort { a, b in
            if abs(a.angle - b.angle) > 1e-12 { return a.angle < b.angle }
            if abs(a.t - b.t) > 1e-9 { return a.t < b.t }
            return a.point.id < b.point.id
        }
        for c in corners where visible(c.point.position) {
            return assemble(point: c.point.position, surface: surface, direction: d, distance: c.t,
                            snapped: c.point, edge: nil, measurable: true)
        }

        // 2. An edge near the ray.
        var edges: [(angle: Double, t: Double, point: Point3, edge: SnapEdge)] = []
        for edge in snapEdges {
            guard let near = closestPoint(onSegment: edge.a, edge.b, toRayFrom: o, direction: d) else { continue }
            guard near.t > 1e-6, near.distance <= Swift.max(radius, near.t * tanAngle) else { continue }
            edges.append((atan2(near.distance, near.t), near.t, near.point, edge))
        }
        edges.sort { a, b in
            if abs(a.angle - b.angle) > 1e-12 { return a.angle < b.angle }
            if abs(a.t - b.t) > 1e-9 { return a.t < b.t }
            return a.edge.id < b.edge.id
        }
        for e in edges where visible(e.point) {
            return assemble(point: e.point, surface: surface, direction: d, distance: e.t,
                            snapped: nil, edge: e.edge, measurable: true)
        }

        // 3. The surface itself.
        guard let hit = surface else { return nil }
        return PickResult(point: hit.point, surfacePoint: hit.point, normal: hit.normal, meshID: hit.meshID,
                          distance: hit.t, snapped: nil, snappedEdge: nil, isMeasurable: hit.isMeasurable)
    }

    private static func assemble(point: Point3, surface: SurfaceHit?, direction d: Point3, distance: Double,
                                 snapped: SnapPoint?, edge: SnapEdge?, measurable: Bool) -> PickResult {
        PickResult(point: point, surfacePoint: surface?.point,
                   normal: surface?.normal ?? Point3(-d.x, -d.y, -d.z), meshID: surface?.meshID,
                   distance: surface?.t ?? distance, snapped: snapped, snappedEdge: edge, isMeasurable: measurable)
    }

    // MARK: Edges

    /// The edges worth snapping to: the vertical line at every corner that touches a solid wall, and the base
    /// and top line of every solid wall. Open-plan boundaries have no edges.
    public static func cornerEdges(for rooms: [Room]) -> [SnapEdge] {
        var out: [SnapEdge] = []
        for room in rooms {
            let n = room.walls.count
            guard n >= 3 else { continue }
            let floorY = room.floorElevation.isFinite ? room.floorElevation : 0
            for (i, wall) in room.walls.enumerated() {
                let previous = room.walls[(i + n - 1) % n]
                let letter = Room.wallLetters(forIndex: i)
                var heights: [Double] = []
                if wall.kind == .solid { heights.append(wall.height.scanned) }
                if previous.kind == .solid { heights.append(previous.height.scanned) }
                if let top = heights.filter({ $0.isFinite && $0 > 0.05 }).min(),
                   wall.start.x.isFinite, wall.start.y.isFinite {
                    out.append(SnapEdge(id: "ec:\(wall.id.uuidString)", a: wall.start.world(elevation: floorY),
                                        b: wall.start.world(elevation: floorY + top), label: "Corner \(letter) edge"))
                }
                guard wall.kind == .solid, wall.geometricLength.isFinite, wall.geometricLength > 1e-6 else { continue }
                let title = room.wallTitle(at: i)
                out.append(SnapEdge(id: "eb:\(wall.id.uuidString)", a: wall.start.world(elevation: floorY),
                                    b: wall.end.world(elevation: floorY), label: "\(title) base"))
                let h = wall.height.scanned
                if h.isFinite, h > 0.05 {
                    out.append(SnapEdge(id: "et:\(wall.id.uuidString)", a: wall.start.world(elevation: floorY + h),
                                        b: wall.end.world(elevation: floorY + h), label: "\(title) top"))
                }
            }
        }
        return out
    }

    // MARK: Ray against the mesh

    struct SurfaceHit {
        var t: Double
        var point: Point3
        var normal: Point3
        var meshID: String
        var isMeasurable: Bool
    }

    /// The nearest surface along a unit-direction ray within `maxDistance`, by Moller-Trumbore on every
    /// triangle (after a quick box test per mesh).
    static func firstHit(origin o: Point3, direction d: Point3, in scene: RoomScene, maxDistance: Double,
                         mode: PickMode, cull: Bool) -> SurfaceHit? {
        var best: SurfaceHit?
        for mesh in scene.meshes {
            if mode == .seeThrough && !mesh.isMeasurable { continue }
            guard !mesh.buffer.isEmpty, rayMeetsBox(o, d, mesh.boundsMin, mesh.boundsMax, maxDistance) else { continue }
            let buffer = mesh.buffer
            for tri in 0..<buffer.triangleCount {
                guard let (v0, v1, v2) = buffer.triangle(tri) else { continue }
                guard let (t, normal) = intersect(o, d, v0, v1, v2, cull: cull),
                      t <= maxDistance else { continue }
                if let current = best {
                    if t > current.t + 1e-9 { continue }
                    if abs(t - current.t) <= 1e-9 {
                        // A tie (coincident faces, such as the shared wall of two rooms): a measurable
                        // surface wins, then the smaller id, so the answer never depends on mesh order.
                        if mesh.isMeasurable != current.isMeasurable {
                            if !mesh.isMeasurable { continue }
                        } else if mesh.id >= current.meshID {
                            continue
                        }
                    }
                }
                best = SurfaceHit(t: t, point: o + d * t, normal: normal, meshID: mesh.id,
                                  isMeasurable: mesh.isMeasurable)
            }
        }
        return best
    }

    /// Moller-Trumbore. Returns the distance along the unit ray and the unit normal facing the ray, or nil.
    /// A triangle seen from behind is a miss when `cull` is true.
    static func intersect(_ o: Point3, _ d: Point3, _ v0: Point3, _ v1: Point3, _ v2: Point3,
                          cull: Bool) -> (Double, Point3)? {
        let e1 = v1 - v0, e2 = v2 - v0
        let p = SceneVector.cross(d, e2)
        let det = e1.dot(p)
        // det is -(d . N), N = e1 x e2, so a positive det means the ray meets the front face.
        let scale = e1.length * e2.length
        guard scale > 0, det.isFinite else { return nil }
        let threshold = 1e-12 * scale
        if cull {
            guard det > threshold else { return nil }
        } else {
            guard abs(det) > threshold else { return nil }
        }
        let inv = 1 / det
        let s = o - v0
        let u = s.dot(p) * inv
        guard u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        let q = SceneVector.cross(s, e1)
        let v = d.dot(q) * inv
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { return nil }
        let t = e2.dot(q) * inv
        guard t.isFinite, t > 1e-7 else { return nil }
        guard var n = SceneVector.normalized(SceneVector.cross(e1, e2)) else { return nil }
        if n.dot(d) > 0 { n = Point3(-n.x, -n.y, -n.z) }
        return (t, n)
    }

    /// Slab test of a unit ray against a box (padded a little, so a flat mesh still has a box).
    static func rayMeetsBox(_ o: Point3, _ d: Point3, _ lo: Point3, _ hi: Point3, _ maxDistance: Double) -> Bool {
        let pad = 1e-5
        var tMin = 0.0
        var tMax = maxDistance
        let origin = [o.x, o.y, o.z], dir = [d.x, d.y, d.z]
        let low = [lo.x - pad, lo.y - pad, lo.z - pad], high = [hi.x + pad, hi.y + pad, hi.z + pad]
        for axis in 0..<3 {
            if abs(dir[axis]) < 1e-15 {
                if origin[axis] < low[axis] || origin[axis] > high[axis] { return false }
            } else {
                let t1 = (low[axis] - origin[axis]) / dir[axis]
                let t2 = (high[axis] - origin[axis]) / dir[axis]
                tMin = Swift.max(tMin, Swift.min(t1, t2))
                tMax = Swift.min(tMax, Swift.max(t1, t2))
                if tMin > tMax { return false }
            }
        }
        return true
    }

    /// The point on segment `a`-`b` that comes closest to the ray, with its distance along the (unit) ray and
    /// its distance from the ray. Nil when the closest approach is behind the origin.
    static func closestPoint(onSegment a: Point3, _ b: Point3, toRayFrom o: Point3, direction d: Point3)
        -> (point: Point3, t: Double, distance: Double)? {
        let u = b - a
        let lengthSquared = u.dot(u)
        guard lengthSquared > 1e-18, lengthSquared.isFinite else { return nil }
        let w = a - o
        let bb = u.dot(d)
        let dd = u.dot(w)
        let ee = d.dot(w)
        let denominator = lengthSquared - bb * bb
        var s = 0.5
        if denominator > 1e-12 * lengthSquared {
            s = (bb * ee - dd) / denominator
        } else {
            // The edge runs along the ray: any point will do; take the one nearest the origin.
            s = -dd / lengthSquared
        }
        s = Swift.min(Swift.max(s, 0), 1)
        let onSegment = a + u * s
        let t = (onSegment - o).dot(d)
        guard t > 1e-6 else { return nil }
        let distance = (onSegment - (o + d * t)).length
        guard distance.isFinite else { return nil }
        return (onSegment, t, distance)
    }
}

// MARK: - Which room does a measurement belong to?

public enum MeasurementRoomLocator {
    /// How far outside an outline a point may be and still count as inside, metres. Corner snap points sit
    /// exactly on the outline, where an inside test is a coin toss.
    static let outlineTolerance = 0.05

    /// The room to store a tape measurement in: the room whose outline contains the plan projection of both
    /// points; failing that the one containing the midpoint, then either point; failing that the nearest room.
    /// When several rooms qualify (rooms that overlap) the focus room wins, then the smallest.
    /// With no rooms at all this is nil.
    public static func roomID(forPointA a: Point3, pointB b: Point3, in rooms: [Room], focusRoomID: UUID?) -> UUID? {
        let usable = rooms.filter { room in
            room.walls.count >= 3 && room.walls.allSatisfy {
                $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite
            }
        }
        guard !usable.isEmpty else {
            if let focus = focusRoomID, rooms.contains(where: { $0.id == focus }) { return focus }
            return rooms.first?.id
        }
        let pa = a.plan, pb = b.plan
        let mid = (pa + pb) / 2
        let steps: [[Point2]] = [[pa, pb], [mid], [pa], [pb]]
        for points in steps where points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) {
            let among = usable.filter { room in points.allSatisfy { contains(room, $0) } }
            if let chosen = preferred(among, focusRoomID: focusRoomID) { return chosen }
        }
        // Nothing contains the points: the room whose outline is nearest to the midpoint.
        var nearest = usable[0]
        var nearestDistance = Double.infinity
        let target = mid.x.isFinite && mid.y.isFinite ? mid : pa
        for room in usable {
            let d = distance(from: target, toOutlineOf: room)
            if d < nearestDistance - 1e-12 {
                nearest = room
                nearestDistance = d
            }
        }
        return nearest.id
    }

    private static func preferred(_ rooms: [Room], focusRoomID: UUID?) -> UUID? {
        guard !rooms.isEmpty else { return nil }
        if let focus = focusRoomID, rooms.contains(where: { $0.id == focus }) { return focus }
        var best = rooms[0]
        var bestArea = Polygon.area(best.outline)
        for room in rooms.dropFirst() {
            let area = Polygon.area(room.outline)
            if area < bestArea - 1e-12 {
                best = room
                bestArea = area
            }
        }
        return best.id
    }

    private static func contains(_ room: Room, _ p: Point2) -> Bool {
        Polygon.contains(room.outline, p) || distance(from: p, toOutlineOf: room) <= outlineTolerance
    }

    static func distance(from p: Point2, toOutlineOf room: Room) -> Double {
        let outline = room.outline
        var best = Double.infinity
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            let t = lengthSquared < 1e-18 ? 0 : Swift.min(Swift.max((p - a).dot(ab) / lengthSquared, 0), 1)
            best = Swift.min(best, p.distance(to: a + ab * t))
        }
        return best
    }
}
