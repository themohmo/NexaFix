import Foundation

// MARK: - Room kinds

public enum RoomKind: String, Codable, CaseIterable, Sendable {
    case livingRoom, dining, kitchen, bedroom, masterBedroom, bathroom, corridor, entrance
    case balcony, maidsRoom, laundry, storage
    case office, meetingRoom, reception
    case other

    public var displayName: String {
        switch self {
        case .livingRoom: return "Living Room"
        case .dining: return "Dining"
        case .kitchen: return "Kitchen"
        case .bedroom: return "Bedroom"
        case .masterBedroom: return "Master Bedroom"
        case .bathroom: return "Bathroom"
        case .corridor: return "Corridor"
        case .entrance: return "Entrance"
        case .balcony: return "Balcony"
        case .maidsRoom: return "Maid's Room"
        case .laundry: return "Laundry"
        case .storage: return "Storage"
        case .office: return "Office"
        case .meetingRoom: return "Meeting Room"
        case .reception: return "Reception"
        case .other: return "Room"
        }
    }

    /// Wet areas get moisture-resistant boards and tiles in the costing engine.
    public var isWet: Bool { self == .bathroom || self == .laundry }
    public var isOutdoor: Bool { self == .balcony }

    /// Tags understood by the NexaFix costing engine (`rooms[].tags`).
    public var costingTags: [String] {
        switch self {
        case .livingRoom, .dining: return ["living"]
        case .kitchen: return ["kitchen"]
        case .bedroom, .masterBedroom: return ["bedroom"]
        case .bathroom: return ["bathroom"]
        case .corridor, .entrance: return ["circulation"]
        case .balcony: return ["outdoor"]
        case .maidsRoom, .laundry, .storage: return ["utility"]
        case .office, .meetingRoom, .reception: return ["office"]
        case .other: return []
        }
    }
}

// MARK: - Walls

public enum WallKind: String, Codable, Sendable {
    /// A physical wall.
    case solid
    /// A boundary edge with no wall (open-plan room edge). Drawn dashed, excluded from wall area.
    case virtual
}

/// One edge of a room's boundary loop.
public struct Wall: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Corner at the start of the wall (plan space, metres).
    public var start: Point2
    /// Corner at the end of the wall.
    public var end: Point2
    public var kind: WallKind
    /// RoomPlan reported a curved wall; the model stores the straight chord.
    public var isCurved: Bool
    /// Clear length between the two corners. `scanned` equals the chord length at build time.
    public var length: Measured
    /// Floor-to-ceiling height of this wall.
    public var height: Measured

    public init(id: UUID = UUID(), start: Point2, end: Point2, kind: WallKind = .solid,
                isCurved: Bool = false, length: Measured? = nil, height: Measured) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.isCurved = isCurved
        self.length = length ?? Measured(scanned: start.distance(to: end))
        self.height = height
    }

    /// Straight-line distance between the corners from the stored coordinates.
    public var geometricLength: Double { start.distance(to: end) }
    public var midpoint: Point2 { start.lerp(to: end, t: 0.5) }
    /// Unit vector from start to end.
    public var direction: Point2 { (end - start).normalized }
    /// Unit normal pointing into the room (rooms are stored counter-clockwise, so interior is to the left).
    public var inwardNormal: Point2 { direction.perpendicularCCW }
}

// MARK: - Openings

public enum OpeningKind: String, Codable, CaseIterable, Sendable {
    case door, window
    /// A doorless passage or archway.
    case opening

    public var displayName: String {
        switch self {
        case .door: return "Door"
        case .window: return "Window"
        case .opening: return "Opening"
        }
    }
}

public struct Opening: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: OpeningKind
    /// The wall that holds this opening (nil if it could not be matched to a wall).
    public var wallID: UUID?
    /// Distance along the wall from `wall.start` to the opening's near edge, metres.
    public var offsetFromWallStart: Double
    public var width: Measured
    public var height: Measured
    /// Height of the bottom edge above the floor (0 for doors and openings).
    public var sillHeight: Measured

    public init(id: UUID = UUID(), kind: OpeningKind, wallID: UUID?, offsetFromWallStart: Double,
                width: Measured, height: Measured, sillHeight: Measured = Measured(scanned: 0)) {
        self.id = id
        self.kind = kind
        self.wallID = wallID
        self.offsetFromWallStart = offsetFromWallStart
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
    }

    /// Top edge above the floor, using scanned geometry.
    public var headHeight: Double { sillHeight.scanned + height.scanned }

    /// The two plan-space end points of the opening along its wall (scanned geometry).
    public func planSegment(on wall: Wall) -> (Point2, Point2) {
        let d = wall.direction
        let a = wall.start + d * offsetFromWallStart
        return (a, a + d * width.scanned)
    }
}

// MARK: - Objects

/// Furniture / fixtures RoomPlan recognises. Names follow `CapturedRoom.Object.Category`.
public enum ObjectKind: String, Codable, CaseIterable, Sendable {
    case storage, refrigerator, stove, bed, sink, washerDryer, toilet, bathtub
    case oven, dishwasher, table, sofa, chair, fireplace, television, stairs
    case other

    public var displayName: String {
        switch self {
        case .washerDryer: return "Washer / Dryer"
        case .television: return "Television"
        case .other: return "Object"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public struct RoomObject: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ObjectKind
    /// Centre of the object's footprint (plan space, metres).
    public var center: Point2
    /// Rotation of the object's local width axis, counter-clockwise from plan +x, radians.
    public var yaw: Double
    /// Extent along the object's local width axis, metres.
    public var width: Double
    /// Extent along the object's local depth axis, metres.
    public var depth: Double
    public var height: Double
    /// Height of the object's bottom face above the floor, metres.
    public var elevation: Double

    public init(id: UUID = UUID(), kind: ObjectKind, center: Point2, yaw: Double,
                width: Double, depth: Double, height: Double, elevation: Double = 0) {
        self.id = id
        self.kind = kind
        self.center = center
        self.yaw = yaw
        self.width = width
        self.depth = depth
        self.height = height
        self.elevation = elevation
    }

    /// The four footprint corners in plan space, counter-clockwise.
    public var footprint: [Point2] {
        let u = Point2(1, 0).rotated(by: yaw)
        let v = u.perpendicularCCW
        let hw = width / 2, hd = depth / 2
        return [center - u * hw - v * hd, center + u * hw - v * hd,
                center + u * hw + v * hd, center - u * hw + v * hd]
    }
}

// MARK: - Custom measurements

/// A measurement the user took between two points in the AR view or the 3D viewer
/// (e.g. "Wardrobe wall", "Counter run"). `a` and `b` are world-space points.
public struct CustomMeasurement: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var a: Point3
    public var b: Point3
    public var length: Measured
    public var createdAt: Date
    public var note: String?

    public init(id: UUID = UUID(), label: String, a: Point3, b: Point3,
                length: Measured? = nil, createdAt: Date = Date(), note: String? = nil) {
        self.id = id
        self.label = label
        self.a = a
        self.b = b
        self.length = length ?? Measured(scanned: a.distance(to: b))
        self.createdAt = createdAt
        self.note = note
    }
}

// MARK: - Room

public struct Room: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: RoomKind
    /// The boundary loop, counter-clockwise: wall `i` runs from corner `i` to corner `i + 1`.
    public var walls: [Wall]
    public var ceilingHeight: Measured
    public var openings: [Opening]
    public var objects: [RoomObject]
    public var customMeasurements: [CustomMeasurement]
    /// World Y of the floor in the scan session's coordinate frame (needed to place AR overlays).
    public var floorElevation: Double
    public var scannedAt: Date
    /// Relative path (inside the property folder) of the saved RoomPlan `CapturedRoom` JSON, if any.
    public var capturedRoomFile: String?
    public var notes: String

    public init(id: UUID = UUID(), name: String, kind: RoomKind = .other, walls: [Wall],
                ceilingHeight: Measured, openings: [Opening] = [], objects: [RoomObject] = [],
                customMeasurements: [CustomMeasurement] = [], floorElevation: Double = 0,
                scannedAt: Date = Date(), capturedRoomFile: String? = nil, notes: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.walls = walls
        self.ceilingHeight = ceilingHeight
        self.openings = openings
        self.objects = objects
        self.customMeasurements = customMeasurements
        self.floorElevation = floorElevation
        self.scannedAt = scannedAt
        self.capturedRoomFile = capturedRoomFile
        self.notes = notes
    }

    /// Corner points in loop order (counter-clockwise).
    public var outline: [Point2] { walls.map(\.start) }

    public func wall(withID id: UUID) -> Wall? { walls.first { $0.id == id } }
    public func openings(on wall: Wall) -> [Opening] {
        openings.filter { $0.wallID == wall.id }.sorted { $0.offsetFromWallStart < $1.offsetFromWallStart }
    }
}

// MARK: - Floors and properties

/// Files that belong to a whole scan session (all rooms of one floor scanned in one AR session).
public struct FloorAssets: Codable, Hashable, Sendable {
    /// Relative path of the merged USDZ model.
    public var structureUSDZ: String?
    /// Relative path of the archived ARWorldMap used to re-localise AR overlays later.
    public var worldMap: String?
    public init(structureUSDZ: String? = nil, worldMap: String? = nil) {
        self.structureUSDZ = structureUSDZ
        self.worldMap = worldMap
    }
}

public struct Floor: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// 0 = ground, 1 = first floor, -1 = basement.
    public var level: Int
    public var rooms: [Room]
    public var assets: FloorAssets

    public init(id: UUID = UUID(), name: String, level: Int = 0, rooms: [Room] = [],
                assets: FloorAssets = FloorAssets()) {
        self.id = id
        self.name = name
        self.level = level
        self.rooms = rooms
        self.assets = assets
    }
}

public enum PropertyKind: String, Codable, CaseIterable, Sendable {
    case apartment, villa, office, retail, other
    public var displayName: String {
        switch self {
        case .apartment: return "Apartment"
        case .villa: return "Villa"
        case .office: return "Office"
        case .retail: return "Retail"
        case .other: return "Other"
        }
    }
}

public struct Property: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var client: String
    public var address: String
    /// NexaFix job / quote reference, e.g. "NF-2026-1009-01".
    public var reference: String
    public var kind: PropertyKind
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public var floors: [Floor]

    public init(id: UUID = UUID(), name: String, client: String = "", address: String = "",
                reference: String = "", kind: PropertyKind = .apartment, notes: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date(), floors: [Floor] = []) {
        self.id = id
        self.name = name
        self.client = client
        self.address = address
        self.reference = reference
        self.kind = kind
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.floors = floors
    }

    public var allRooms: [Room] { floors.flatMap(\.rooms) }
    public var roomCount: Int { floors.reduce(0) { $0 + $1.rooms.count } }
}
