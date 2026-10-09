import Foundation

// Platform-neutral mirror of what RoomPlan's `CapturedRoom` provides. The iOS app converts
// `CapturedRoom` into `RawCapture` (a trivial field-by-field copy) and `RoomBuilder` turns it
// into a `Room`. Keeping this layer free of simd/RoomPlan is what lets the hard geometry be
// unit-tested off-device.
//
// RoomPlan conventions this layer relies on (verify against Apple's docs before changing):
//  - Surfaces (walls, doors, windows, openings, floors) and objects have a 4x4 `transform`
//    (column-major, like simd_float4x4) placing them in the AR session's world frame (Y up).
//  - For walls/doors/windows/openings the local X axis runs along the surface width, local Y is
//    vertical, local Z is the surface normal; `dimensions` = (width, height, ~0 thickness) and the
//    transform's translation is the CENTRE of the surface.
//  - Objects: `dimensions` = (x, y, z) extents of a box centred on the transform's translation.

/// 4x4 transform, 16 values in column-major order (matches `simd_float4x4`: columns 0...3,
/// column 3 is the translation).
public struct Matrix4: Codable, Hashable, Sendable {
    public var columnMajor: [Double]

    public init(columnMajor: [Double]) {
        precondition(columnMajor.count == 16, "Matrix4 needs 16 values")
        self.columnMajor = columnMajor
    }

    public static let identity = Matrix4(columnMajor: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    /// Rotation about world Y by `yaw` radians plus a translation.
    public static func yawTranslation(yaw: Double, _ t: Point3) -> Matrix4 {
        let c = cos(yaw), s = sin(yaw)
        // Columns: X' = (c, 0, -s), Y' = (0, 1, 0), Z' = (s, 0, c), T = t
        return Matrix4(columnMajor: [c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, t.x, t.y, t.z, 1])
    }

    private func column(_ i: Int) -> Point3 {
        Point3(columnMajor[i * 4], columnMajor[i * 4 + 1], columnMajor[i * 4 + 2])
    }
    public var xAxis: Point3 { column(0) }
    public var yAxis: Point3 { column(1) }
    public var zAxis: Point3 { column(2) }
    public var translation: Point3 { column(3) }

    /// Apply to a point given in local coordinates.
    public func transform(_ p: Point3) -> Point3 {
        xAxis * p.x + yAxis * p.y + zAxis * p.z + translation
    }
}

public enum RawSurfaceKind: String, Codable, Sendable {
    case wall, door, window, opening, floor
}

public enum RawConfidence: String, Codable, Sendable {
    case low, medium, high
}

public struct RawSurface: Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: RawSurfaceKind
    public var transform: Matrix4
    /// (width, height, thickness) in metres.
    public var dimensions: Point3
    /// `polygonCorners` from RoomPlan (iOS 17+), in the surface's local frame. nil when unavailable.
    public var polygonCorners: [Point3]?
    public var isCurved: Bool
    /// The wall that holds this door/window/opening, when RoomPlan reports it.
    public var parentID: UUID?
    public var story: Int
    public var confidence: RawConfidence

    public init(id: UUID = UUID(), kind: RawSurfaceKind, transform: Matrix4, dimensions: Point3,
                polygonCorners: [Point3]? = nil, isCurved: Bool = false, parentID: UUID? = nil,
                story: Int = 0, confidence: RawConfidence = .high) {
        self.id = id
        self.kind = kind
        self.transform = transform
        self.dimensions = dimensions
        self.polygonCorners = polygonCorners
        self.isCurved = isCurved
        self.parentID = parentID
        self.story = story
        self.confidence = confidence
    }
}

public struct RawObject: Codable, Hashable, Sendable {
    public var id: UUID
    /// RoomPlan category name, e.g. "storage", "washerDryer". Unknown strings map to `ObjectKind.other`.
    public var category: String
    public var transform: Matrix4
    public var dimensions: Point3
    public var story: Int
    public var confidence: RawConfidence

    public init(id: UUID = UUID(), category: String, transform: Matrix4, dimensions: Point3,
                story: Int = 0, confidence: RawConfidence = .high) {
        self.id = id
        self.category = category
        self.transform = transform
        self.dimensions = dimensions
        self.story = story
        self.confidence = confidence
    }
}

/// One scanned room as RoomPlan reports it.
public struct RawCapture: Codable, Hashable, Sendable {
    public var id: UUID
    public var story: Int
    public var walls: [RawSurface]
    public var doors: [RawSurface]
    public var windows: [RawSurface]
    public var openings: [RawSurface]
    public var floors: [RawSurface]
    public var objects: [RawObject]

    public init(id: UUID = UUID(), story: Int = 0, walls: [RawSurface] = [], doors: [RawSurface] = [],
                windows: [RawSurface] = [], openings: [RawSurface] = [], floors: [RawSurface] = [],
                objects: [RawObject] = []) {
        self.id = id
        self.story = story
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.floors = floors
        self.objects = objects
    }
}
