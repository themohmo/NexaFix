import Foundation

/// A point in the 3D viewer that a tap or an AR crosshair should jump to, so a custom
/// measurement starts and ends exactly on a corner instead of "near" one.
public struct SnapPoint: Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case floorCorner, ceilingCorner, openingCorner, objectCorner, wallMidFloor
    }

    /// Stable across runs and edits: built from the ids of the wall, opening or object
    /// the point belongs to (for example "fc:<wall uuid>").
    public var id: String
    public var kind: Kind
    /// World space (Y up), including the room's `floorElevation`.
    public var position: Point3
    public var label: String

    public init(id: String, kind: Kind, position: Point3, label: String) {
        self.id = id
        self.kind = kind
        self.position = position
        self.label = label
    }

    /// The snap point closest to `p` and within `radius` metres (inclusive), or nil.
    /// On equal distance the earlier point in `points` wins, so results are deterministic.
    /// A negative or NaN radius, a NaN `p` or an empty list give nil.
    public static func nearest(to p: Point3, in points: [SnapPoint], within radius: Double) -> SnapPoint? {
        guard radius >= 0, p.x.isFinite, p.y.isFinite, p.z.isFinite else { return nil }
        var best: SnapPoint?
        var bestDistance = Double.infinity
        for candidate in points {
            let d = candidate.position.distance(to: p)
            guard d.isFinite, d <= radius, d < bestDistance else { continue }
            best = candidate
            bestDistance = d
        }
        return best
    }
}

public extension Room {
    /// Every corner worth snapping to, in world space, from the SCANNED geometry (verification
    /// never moves geometry). Order is fixed: floor corners, ceiling corners, wall mid-points,
    /// opening corners, object corners.
    ///
    /// - Floor corner `i`: the start of wall `i`, at floor level. Labelled "Corner A" after the
    ///   wall that starts there.
    /// - Ceiling corner `i`: directly above it at `ceilingHeight.scanned`.
    /// - Wall mid-floor: the middle of each SOLID wall at floor level (open-plan boundaries have no wall).
    /// - Opening corners: the four corners of each opening on its wall from `Opening.planSegment`,
    ///   at sill and head heights. "near" is the edge closer to the wall's start corner.
    ///   Openings that are not on a wall of this room have no position and give none.
    /// - Object corners: the four footprint corners at the object's bottom and at its top.
    ///
    /// Points with a non-finite coordinate are skipped.
    func snapPoints() -> [SnapPoint] {
        var out: [SnapPoint] = []
        out.reserveCapacity(walls.count * 3 + openings.count * 4 + objects.count * 8)

        func add(_ id: String, _ kind: SnapPoint.Kind, _ p: Point3, _ label: String) {
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return }
            out.append(SnapPoint(id: id, kind: kind, position: p, label: label))
        }

        let floorY = floorElevation
        let ceilingY = floorElevation + ceilingHeight.scanned

        for (i, wall) in walls.enumerated() {
            let letter = Room.wallLetters(forIndex: i)
            add("fc:\(wall.id.uuidString)", .floorCorner, wall.start.world(elevation: floorY),
                "Floor corner \(letter)")
        }
        for (i, wall) in walls.enumerated() {
            let letter = Room.wallLetters(forIndex: i)
            add("cc:\(wall.id.uuidString)", .ceilingCorner, wall.start.world(elevation: ceilingY),
                "Ceiling corner \(letter)")
        }
        for (i, wall) in walls.enumerated() where wall.kind == .solid {
            add("wm:\(wall.id.uuidString)", .wallMidFloor, wall.midpoint.world(elevation: floorY),
                "\(wallTitle(at: i)) middle")
        }

        let openingTitles = measureOpeningTitles()
        for index in measureOpeningOrder() {
            let opening = openings[index]
            guard let wallID = opening.wallID, let wall = self.wall(withID: wallID) else { continue }
            let (near, far) = opening.planSegment(on: wall)
            let bottom = floorY + opening.sillHeight.scanned
            let top = bottom + opening.height.scanned
            let title = openingTitles[opening.id] ?? opening.kind.displayName
            let corners: [(String, Point2, Double, String)] = [
                ("0", near, bottom, "bottom near"), ("1", far, bottom, "bottom far"),
                ("2", far, top, "top far"), ("3", near, top, "top near"),
            ]
            for (suffix, plan, y, name) in corners {
                add("oc:\(opening.id.uuidString):\(suffix)", .openingCorner, plan.world(elevation: y),
                    "\(title) \(name)")
            }
        }

        var objectCounters: [ObjectKind: Int] = [:]
        for object in objects {
            let n = (objectCounters[object.kind] ?? 0) + 1
            objectCounters[object.kind] = n
            let title = "\(object.kind.displayName) \(n)"
            let bottom = floorY + object.elevation
            let top = bottom + object.height
            for (level, y) in [("b", bottom), ("t", top)] {
                for (k, corner) in object.footprint.enumerated() {
                    add("ob:\(object.id.uuidString):\(level)\(k)", .objectCorner, corner.world(elevation: y),
                        "\(title) \(level == "b" ? "bottom" : "top") corner \(k + 1)")
                }
            }
        }
        return out
    }
}
