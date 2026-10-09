import Foundation

/// A corner of the room outline. Corner `i` is the start of wall `i` (and the end of wall `i - 1`).
public struct Corner: Hashable, Sendable {
    public let index: Int
    public let point: Point2
    /// Interior angle in degrees, 0..<360 (reflex corners such as the inside of an L-shape are > 180).
    public let interiorAngle: Double

    public init(index: Int, point: Point2, interiorAngle: Double) {
        self.index = index
        self.point = point
        self.interiorAngle = interiorAngle
    }

    /// Signed difference from a right angle, degrees. Positive = more open than 90.
    public var deviationFrom90: Double { interiorAngle - 90 }
    public var isReflex: Bool { interiorAngle > 180 + RoomMetrics.straightTolerance }
    /// A "corner" that is really a straight continuation of the wall.
    public var isStraight: Bool { abs(interiorAngle - 180) <= RoomMetrics.straightTolerance }
    /// Within `tolerance` degrees of a right angle.
    public func isSquare(tolerance: Double = RoomMetrics.squareTolerance) -> Bool {
        abs(interiorAngle - 90) <= tolerance
    }
}

/// One straight side of the room: consecutive walls that continue in a straight line are merged.
public struct RoomSide: Hashable, Sendable {
    public let wallIDs: [UUID]
    public let start: Point2
    public let end: Point2
    /// Sum of the LiDAR lengths of the constituent walls, metres.
    public let scannedLength: Double
    /// Sum of the effective (verified-if-available) lengths, metres.
    public let length: Double
    /// Every constituent wall has been verified on site.
    public let isVerified: Bool
    /// True when every constituent wall is a solid wall (not an open-plan boundary).
    public let isSolid: Bool
}

/// Derived numbers for a room. Everything here is computed from the stored model;
/// nothing is persisted, so verified values always flow through.
public struct RoomMetrics: Sendable {
    /// Corners within this many degrees of 180 are treated as straight continuations.
    public static let straightTolerance = 3.0
    /// Default tolerance for calling a corner "square" when reporting out-of-square corners.
    public static let squareTolerance = 1.0
    /// A room is treated as a rectangle when its four corners are within this many degrees of 90.
    public static let rectangleTolerance = 5.0

    /// Floor area from the scanned outline, m².
    public let floorArea: Double
    /// Sum of effective lengths of all walls including open-plan boundaries, metres.
    public let perimeter: Double
    /// Sum of effective lengths of solid walls only, metres.
    public let wallPerimeter: Double
    /// Effective ceiling height, metres.
    public let ceilingHeight: Double
    /// floorArea x ceilingHeight, m³.
    public let volume: Double
    /// Solid wall length x wall height, summed, m².
    public let grossWallArea: Double
    /// Door, window and opening area on solid walls (effective sizes), m².
    public let openingArea: Double
    /// grossWallArea - openingArea, never negative, m².
    public let netWallArea: Double
    public let corners: [Corner]
    public let sides: [RoomSide]
    public let isRectangular: Bool
    /// Longer side, effective metres. Only for rectangular rooms.
    public let length: Double?
    /// Shorter side, effective metres. Only for rectangular rooms.
    public let width: Double?
    /// length x width for rectangles (so verified wall lengths flow into the area); scanned outline area otherwise.
    public let effectiveFloorArea: Double
    public let bounds: Bounds2?

    /// Corners that are neither straight continuations nor within `squareTolerance` of 90 degrees
    /// (reflex corners excluded: those are expected in L-shaped rooms).
    public var outOfSquareCorners: [Corner] {
        corners.filter { !$0.isStraight && !$0.isReflex && !$0.isSquare() }
    }

    public init(room: Room) {
        let outline = room.outline
        let ccw = Polygon.isCounterClockwise(outline)

        var corners: [Corner] = []
        for i in 0..<outline.count {
            var a = Polygon.interiorAngle(outline, at: i)
            if !ccw { a = 360 - a }
            corners.append(Corner(index: i, point: outline[i], interiorAngle: a))
        }
        self.corners = corners

        self.floorArea = Polygon.area(outline)
        self.bounds = Bounds2(points: outline)
        self.perimeter = room.walls.reduce(0) { $0 + $1.length.value }
        self.wallPerimeter = room.walls.filter { $0.kind == .solid }.reduce(0) { $0 + $1.length.value }
        self.ceilingHeight = room.ceilingHeight.value
        self.volume = floorArea * room.ceilingHeight.value
        self.grossWallArea = room.walls.filter { $0.kind == .solid }
            .reduce(0) { $0 + $1.length.value * $1.height.value }

        let solidIDs = Set(room.walls.filter { $0.kind == .solid }.map(\.id))
        let openingArea = room.openings
            .filter { $0.wallID.map(solidIDs.contains) ?? false }
            .reduce(0) { $0 + $1.width.value * $1.height.value }
        self.openingArea = openingArea
        self.netWallArea = max(0, grossWallArea - openingArea)

        // Merge walls separated by straight corners into sides.
        let sides = RoomMetrics.buildSides(room: room, corners: corners)
        self.sides = sides

        var rect = false
        var len: Double?
        var wid: Double?
        if sides.count == 4 {
            let squareish = sides.indices.allSatisfy { i -> Bool in
                // The corner at the start of side i is the corner at the start of its first wall.
                let startWall = room.walls.first { $0.id == sides[i].wallIDs[0] }
                guard let w = startWall, let idx = room.walls.firstIndex(of: w) else { return false }
                return abs(corners[idx].interiorAngle - 90) <= RoomMetrics.rectangleTolerance
            }
            if squareish {
                rect = true
                let a = (sides[0].length + sides[2].length) / 2
                let b = (sides[1].length + sides[3].length) / 2
                len = max(a, b)
                wid = min(a, b)
            }
        }
        self.isRectangular = rect
        self.length = len
        self.width = wid
        if rect, let l = len, let w = wid {
            self.effectiveFloorArea = l * w
        } else {
            self.effectiveFloorArea = floorArea
        }
    }

    private static func buildSides(room: Room, corners: [Corner]) -> [RoomSide] {
        let n = room.walls.count
        guard n > 0 else { return [] }
        // Start a side at every non-straight corner.
        let breaks = (0..<n).filter { !corners[$0].isStraight }
        guard !breaks.isEmpty else { return [] }
        var sides: [RoomSide] = []
        for (k, startIdx) in breaks.enumerated() {
            let endIdx = breaks[(k + 1) % breaks.count]   // exclusive wall index where the next side starts
            var idxs: [Int] = []
            var i = startIdx
            repeat {
                idxs.append(i)
                i = (i + 1) % n
            } while i != endIdx
            let walls = idxs.map { room.walls[$0] }
            sides.append(RoomSide(
                wallIDs: walls.map(\.id),
                start: walls.first!.start,
                end: walls.last!.end,
                scannedLength: walls.reduce(0) { $0 + $1.length.scanned },
                length: walls.reduce(0) { $0 + $1.length.value },
                isVerified: walls.allSatisfy { $0.length.isVerified },
                isSolid: walls.allSatisfy { $0.kind == .solid }))
        }
        return sides
    }
}

public extension Room {
    /// Derived areas, lengths and corner angles. Cheap enough to call per render.
    var metrics: RoomMetrics { RoomMetrics(room: self) }
}
