import Foundation

/// Describes a door/window to add when building a room by hand (tests, demo data).
public struct OpeningSpec: Sendable {
    /// Index of the wall in the room's loop (for `Room.rectangle`: 0 south, 1 east, 2 north, 3 west).
    public var wall: Int
    public var kind: OpeningKind
    /// Distance from the wall's start corner to the opening's near edge, metres.
    public var offset: Double
    public var width: Double
    public var height: Double
    public var sill: Double

    public init(wall: Int, kind: OpeningKind, offset: Double, width: Double, height: Double, sill: Double = 0) {
        self.wall = wall
        self.kind = kind
        self.offset = offset
        self.width = width
        self.height = height
        self.sill = sill
    }

    public static func door(wall: Int, offset: Double, width: Double = 0.9, height: Double = 2.1) -> OpeningSpec {
        OpeningSpec(wall: wall, kind: .door, offset: offset, width: width, height: height)
    }

    public static func window(wall: Int, offset: Double, width: Double, height: Double = 1.4,
                              sill: Double = 0.9) -> OpeningSpec {
        OpeningSpec(wall: wall, kind: .window, offset: offset, width: width, height: height, sill: sill)
    }
}

public extension Room {
    /// Build a room from corner points (plan space, metres). Points are re-wound counter-clockwise.
    /// Used by tests and demo data; real rooms come from `RoomReconstructor`.
    static func polygon(name: String, kind: RoomKind = .other, corners: [Point2], ceilingHeight: Double = 2.8,
                        openings: [OpeningSpec] = [], floorElevation: Double = 0, id: UUID = UUID()) -> Room {
        let pts = Polygon.counterClockwise(corners)
        let height = Measured(scanned: ceilingHeight)
        let walls = pts.indices.map { i in
            Wall(start: pts[i], end: pts[(i + 1) % pts.count], height: height)
        }
        let ops = openings.compactMap { spec -> Opening? in
            guard walls.indices.contains(spec.wall) else { return nil }
            return Opening(kind: spec.kind, wallID: walls[spec.wall].id, offsetFromWallStart: spec.offset,
                           width: Measured(scanned: spec.width), height: Measured(scanned: spec.height),
                           sillHeight: Measured(scanned: spec.sill))
        }
        return Room(id: id, name: name, kind: kind, walls: walls, ceilingHeight: height, openings: ops,
                    floorElevation: floorElevation)
    }

    /// Axis-aligned rectangle with its south-west corner at `origin`. Wall order: south, east, north, west.
    static func rectangle(name: String, kind: RoomKind = .other, origin: Point2 = .zero, width: Double,
                          depth: Double, ceilingHeight: Double = 2.8, openings: [OpeningSpec] = [],
                          id: UUID = UUID()) -> Room {
        let o = origin
        return polygon(name: name, kind: kind,
                       corners: [o, o + Point2(width, 0), o + Point2(width, depth), o + Point2(0, depth)],
                       ceilingHeight: ceilingHeight, openings: openings, id: id)
    }
}
