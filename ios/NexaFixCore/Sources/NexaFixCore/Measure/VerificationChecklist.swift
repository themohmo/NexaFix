import Foundation

/// The to-do list for checking one room with a laser measure.
///
/// Every dimension a person can verify becomes an `Item`. Items are listed in the order
/// `Room.measureTargets()` gives (walls A, B, C ... then the ceiling, openings, custom
/// measurements). A target is left out when there is no physical dimension to check:
/// - the height of an open-plan boundary (`WallKind.virtual`), which has no wall;
/// - the sill of an opening that sits on the floor (scanned sill under 5 mm) and has not been
///   verified, which is every ordinary door.
///
/// Nothing here changes the room. Progress counts any `Verification`, whatever its source.
public struct VerificationChecklist: Sendable {

    /// Where the item sits in the on-site list.
    public enum Group: String, CaseIterable, Sendable {
        case structure, openings, custom

        public var displayName: String {
            switch self {
            case .structure: return "Walls and ceiling"
            case .openings: return "Doors and windows"
            case .custom: return "Custom measurements"
            }
        }
    }

    /// How much a wrong number costs. Check `.joinery` items first.
    public enum Importance: Int, Comparable, Sendable {
        /// Worth checking, but joinery is not cut from it directly (wall heights, sills, open boundaries).
        case normal = 0
        /// Joinery, doors and fittings are cut to this dimension: wall lengths, ceiling height,
        /// opening widths and heights, and custom measurements (taken for a reason).
        case joinery = 1

        public static func < (a: Importance, b: Importance) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Item: Hashable, Identifiable, Sendable {
        public var target: MeasureTarget
        /// "Wall A", "Door 1", "Ceiling height", a custom label.
        public var title: String
        /// "Length", "Width - Wall B", nil for the ceiling.
        public var detail: String?
        /// "Wall A length", "Door 1 width": title and quantity in one string.
        public var fullTitle: String
        public var group: Group
        public var importance: Importance
        public var measured: Measured
        /// Typical LiDAR error for this value, metres (`ScanAccuracy.typicalTolerance`
        /// of the scanned length). Numeric on purpose: format it with `UnitFormatter`.
        public var typicalTolerance: Double

        public var id: MeasureTarget { target }
        public var isVerified: Bool { measured.isVerified }
    }

    public let items: [Item]

    public init(room: Room) {
        var built: [Item] = []
        for target in room.measureTargets() {
            guard let measured = room.measured(target) else { continue }
            guard let importance = VerificationChecklist.importance(of: target, in: room, measured: measured) else {
                continue
            }
            built.append(Item(target: target,
                              title: room.title(for: target),
                              detail: room.detail(for: target),
                              fullTitle: room.fullTitle(for: target),
                              group: VerificationChecklist.group(of: target),
                              importance: importance,
                              measured: measured,
                              typicalTolerance: ScanAccuracy.typicalTolerance(forLength: measured.scanned)))
        }
        self.items = built
    }

    // MARK: Progress

    public var totalCount: Int { items.count }
    public var verifiedCount: Int { items.reduce(0) { $0 + ($1.isVerified ? 1 : 0) } }
    /// verified / total, 0...1. An empty list gives 0, never "complete".
    public var fraction: Double { totalCount == 0 ? 0 : Double(verifiedCount) / Double(totalCount) }
    public var isComplete: Bool { totalCount > 0 && verifiedCount == totalCount }

    public var joineryItems: [Item] { items.filter { $0.importance == .joinery } }
    public var joineryTotalCount: Int { joineryItems.count }
    public var joineryVerifiedCount: Int { joineryItems.reduce(0) { $0 + ($1.isVerified ? 1 : 0) } }
    public var joineryFraction: Double {
        joineryTotalCount == 0 ? 0 : Double(joineryVerifiedCount) / Double(joineryTotalCount)
    }
    /// Every joinery dimension has been checked.
    public var isJoineryComplete: Bool { joineryTotalCount > 0 && joineryVerifiedCount == joineryTotalCount }

    public var unverifiedItems: [Item] { items.filter { !$0.isVerified } }

    public func items(in group: Group) -> [Item] { items.filter { $0.group == group } }

    /// The next thing to measure: the first unverified joinery item, else the first unverified item.
    public var nextToVerify: Item? {
        items.first { !$0.isVerified && $0.importance == .joinery } ?? items.first { !$0.isVerified }
    }

    // MARK: Roll-ups

    /// Verified and total check counts over every room of a property.
    public static func propertyProgress(_ property: Property) -> (verified: Int, total: Int) {
        roomsProgress(property.allRooms)
    }

    /// Verified and total check counts over the given rooms.
    public static func roomsProgress(_ rooms: [Room]) -> (verified: Int, total: Int) {
        var verified = 0, total = 0
        for room in rooms {
            let list = VerificationChecklist(room: room)
            verified += list.verifiedCount
            total += list.totalCount
        }
        return (verified, total)
    }

    // MARK: Classification

    private static func group(of target: MeasureTarget) -> Group {
        switch target {
        case .wallLength, .wallHeight, .ceilingHeight: return .structure
        case .openingWidth, .openingHeight, .openingSill: return .openings
        case .customLength: return .custom
        }
    }

    /// nil when the target is not worth listing.
    private static func importance(of target: MeasureTarget, in room: Room, measured: Measured) -> Importance? {
        switch target {
        case .wallLength(let id):
            let virtual = room.walls.first { $0.id == id }?.kind == .virtual
            return virtual ? .normal : .joinery
        case .wallHeight(let id):
            let virtual = room.walls.first { $0.id == id }?.kind == .virtual
            return virtual ? nil : .normal
        case .ceilingHeight, .openingWidth, .openingHeight, .customLength:
            return .joinery
        case .openingSill:
            // A sill on the floor (every ordinary door) has nothing to check, unless someone already did.
            if measured.scanned < 0.005 && !measured.isVerified { return nil }
            return .normal
        }
    }
}
