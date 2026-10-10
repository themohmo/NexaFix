import Foundation

// Turning a finished scan into a saved property.
//
// One scan session is one AR coordinate frame. Rooms from different sessions are NOT in the same
// frame, so every session becomes its own `Floor` and rooms of different floors are never drawn on
// the same plan. `ScanCommit.apply` is the pure step between "the scan screen handed back rooms" and
// "the property is saved": it builds the new floor, keeps names unique, and lists the files the app
// must write BEFORE it saves the property, so the property never points at a file that is missing.

public enum ScanCommit {

    // MARK: Assets

    /// Which of a scan's files exist. A path is only recorded in the property for a file that does.
    public struct AvailableAssets: Equatable, Sendable {
        /// The merged USDZ model of the floor.
        public var structureUSDZ: Bool
        /// The archived AR world map.
        public var worldMap: Bool
        /// Rooms that have RoomPlan `CapturedRoom` JSON.
        public var capturedRoomIDs: Set<UUID>

        public init(structureUSDZ: Bool = false, worldMap: Bool = false, capturedRoomIDs: Set<UUID> = []) {
            self.structureUSDZ = structureUSDZ
            self.worldMap = worldMap
            self.capturedRoomIDs = capturedRoomIDs
        }

        /// No files at all.
        public static let none = AvailableAssets()
    }

    /// A file to write into the property's folder before the property is saved.
    public struct PlannedAsset: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case structureUSDZ(floorID: UUID)
            case worldMap(floorID: UUID)
            case capturedRoom(roomID: UUID)
        }

        /// Relative to the property folder, for `PropertyStore.writeAsset(_:relativePath:for:)`.
        public var relativePath: String
        public var kind: Kind

        public init(relativePath: String, kind: Kind) {
            self.relativePath = relativePath
            self.kind = kind
        }
    }

    /// `floors/<floorID>/model.usdz`
    public static func structurePath(floorID: UUID) -> String { "floors/\(floorID.uuidString)/model.usdz" }
    /// `floors/<floorID>/world.map`
    public static func worldMapPath(floorID: UUID) -> String { "floors/\(floorID.uuidString)/world.map" }
    /// `rooms/<roomID>.roomplan.json`
    public static func capturedRoomPath(roomID: UUID) -> String { "rooms/\(roomID.uuidString).roomplan.json" }

    // MARK: Result

    /// A room whose name had to change because another room on the same floor already used it.
    public struct Rename: Equatable, Sendable {
        public var original: String
        public var final: String
    }

    /// What applying a scan produced.
    public struct CommitPlan: Sendable {
        /// The property with the new floor. Equal to the input when nothing was added.
        public var property: Property
        /// Files to write first, in a fixed order: the floor's model, its world map, then each room's capture.
        public var assets: [PlannedAsset]
        /// A sentence for the person: "Added 5 rooms to Level 23."
        public var summary: String
        /// The new floor, or nil when nothing was added.
        public var floorID: UUID?
        /// Rooms that were added, in scan order.
        public var addedRoomIDs: [UUID]
        /// Rooms that were left out because the property already holds a room with that id.
        public var skippedRoomIDs: [UUID]
        public var renames: [Rename]

        /// Nothing was added (empty scan, or the scan was applied before).
        public var isNoOp: Bool { floorID == nil }
    }

    // MARK: Apply

    /// Adds a finished scan to a property as a NEW floor.
    ///
    /// - The floor is named `Level <story>` ("Level 23"); if a floor already has that name the new one is
    ///   "Level 23 (2)", then "Level 23 (3)".
    /// - Room names are made unique on the floor (ignoring case, accents and extra spaces) the way the scan
    ///   screen does: a second "Bedroom" becomes "Bedroom 2". A blank name becomes the room kind's name.
    ///   Nothing is overwritten and no room is dropped.
    /// - Asset paths are recorded only for files that exist (`available`): `FloorAssets.structureUSDZ`,
    ///   `FloorAssets.worldMap`, `Room.capturedRoomFile`. The same paths come back in `assets` so the app
    ///   can write the files before saving. A room with no capture file gets `capturedRoomFile = nil`.
    /// - Applying the same scan again changes nothing: rooms whose id the property already holds are
    ///   skipped, and when no room is left the result is a no-op with the property unchanged.
    /// - An empty floor with no files, such as the one a brand-new property starts with, is removed when a
    ///   floor with rooms is added.
    /// - Each room keeps the time it was captured. `scannedAt` stamps the property's `updatedAt`.
    ///
    /// - Parameter makeID: Source of the new floor's id (pass a fixed one for tests, or to re-apply the same
    ///   commit on a newer copy of the property).
    public static func apply(rooms: [Room], story: Int, scannedAt: Date, to property: Property,
                             available: AvailableAssets = .none,
                             makeID: () -> UUID = { UUID() }) -> CommitPlan {
        // Rooms the property already holds, and repeats within the scan, are skipped.
        var knownIDs = Set(property.allRooms.map(\.id))
        var fresh: [Room] = []
        var skipped: [UUID] = []
        for room in rooms {
            if knownIDs.insert(room.id).inserted {
                fresh.append(room)
            } else {
                skipped.append(room.id)
            }
        }

        guard !fresh.isEmpty else {
            let summary = rooms.isEmpty ? "There are no rooms to save." : "These rooms are already saved."
            return CommitPlan(property: property, assets: [], summary: summary, floorID: nil,
                              addedRoomIDs: [], skippedRoomIDs: skipped, renames: [])
        }

        let floorID = makeID()
        var kept = property.floors.filter { !($0.rooms.isEmpty && $0.assets == FloorAssets()) }
        let floorName = uniqueFloorName(base: levelName(story), existing: kept.map(\.name))

        var assets: [PlannedAsset] = []
        var assetRecord = FloorAssets()
        if available.structureUSDZ {
            let path = structurePath(floorID: floorID)
            assetRecord.structureUSDZ = path
            assets.append(PlannedAsset(relativePath: path, kind: .structureUSDZ(floorID: floorID)))
        }
        if available.worldMap {
            let path = worldMapPath(floorID: floorID)
            assetRecord.worldMap = path
            assets.append(PlannedAsset(relativePath: path, kind: .worldMap(floorID: floorID)))
        }

        var usedNames: [String] = []
        var renames: [Rename] = []
        var placed: [Room] = []
        for original in fresh {
            var room = original
            let wanted = ScanFlow.cleaned(original.name)
            let base = wanted.isEmpty ? original.kind.displayName : wanted
            let final = RoomKindSuggester.freeName(base: base, taken: usedNames)
            if !wanted.isEmpty, ScanFlow.key(final) != ScanFlow.key(wanted) {
                renames.append(Rename(original: wanted, final: final))
            }
            usedNames.append(final)
            room.name = final

            if available.capturedRoomIDs.contains(room.id) {
                let path = capturedRoomPath(roomID: room.id)
                room.capturedRoomFile = path
                assets.append(PlannedAsset(relativePath: path, kind: .capturedRoom(roomID: room.id)))
            } else {
                room.capturedRoomFile = nil
            }
            placed.append(room)
        }

        kept.append(Floor(id: floorID, name: floorName, level: story, rooms: placed, assets: assetRecord))
        var updated = property
        updated.floors = kept
        updated.updatedAt = scannedAt

        return CommitPlan(property: updated, assets: assets,
                          summary: summary(count: placed.count, floor: floorName, renames: renames,
                                           skipped: skipped.count),
                          floorID: floorID, addedRoomIDs: placed.map(\.id), skippedRoomIDs: skipped,
                          renames: renames)
    }

    /// "Level 23", "Level 0" for the ground floor, "Level -1" for a basement: the name a scan of this
    /// story starts with, before `uniqueFloorName` numbers it.
    public static func levelName(_ story: Int) -> String { "Level \(story)" }

    /// `base` if no floor has that name, otherwise "base (2)", "base (3)" ... Names compare ignoring case
    /// and extra spaces.
    public static func uniqueFloorName(base: String, existing: [String]) -> String {
        let taken = Set(existing.map(ScanFlow.key))
        if !taken.contains(ScanFlow.key(base)) { return base }
        var number = 2
        while taken.contains(ScanFlow.key("\(base) (\(number))")) { number += 1 }
        return "\(base) (\(number))"
    }

    private static func summary(count: Int, floor: String, renames: [Rename], skipped: Int) -> String {
        var text = "Added \(count) \(count == 1 ? "room" : "rooms") to \(floor)."
        if renames.count == 1, let rename = renames.first {
            text += " \u{201C}\(rename.original)\u{201D} became \u{201C}\(rename.final)\u{201D} because that name was taken."
        } else if renames.count > 1 {
            text += " \(renames.count) rooms were renamed because their names were taken."
        }
        if skipped > 0 {
            text += " \(skipped) \(skipped == 1 ? "room was" : "rooms were") already saved and \(skipped == 1 ? "was" : "were") skipped."
        }
        return text
    }
}

// MARK: - Editing rooms in place

public extension Property {

    /// Where a room sits: indexes into `floors` and that floor's `rooms`. nil when no floor holds the id.
    func roomLocation(of id: UUID) -> (floor: Int, room: Int)? {
        for (floorIndex, floor) in floors.enumerated() {
            if let roomIndex = floor.rooms.firstIndex(where: { $0.id == id }) {
                return (floorIndex, roomIndex)
            }
        }
        return nil
    }

    /// The floor that holds a room.
    func floorHolding(room id: UUID) -> Floor? {
        roomLocation(of: id).map { floors[$0.floor] }
    }

    /// The room with this id, whichever floor it is on.
    func findRoom(_ id: UUID) -> Room? {
        roomLocation(of: id).map { floors[$0.floor].rooms[$0.room] }
    }

    /// Changes one room in place. Returns false, and changes nothing, when the property has no such room.
    @discardableResult
    mutating func modifyRoom(id: UUID, _ change: (inout Room) -> Void) -> Bool {
        guard let at = roomLocation(of: id) else { return false }
        change(&floors[at.floor].rooms[at.room])
        return true
    }

    /// Removes a room. A floor left with no rooms goes with it (its files stay on disk). Returns false when
    /// the property has no such room.
    @discardableResult
    mutating func deleteRoom(id: UUID) -> Bool {
        guard let at = roomLocation(of: id) else { return false }
        floors[at.floor].rooms.remove(at: at.room)
        if floors[at.floor].rooms.isEmpty { floors.remove(at: at.floor) }
        return true
    }

    /// Names a room, keeping names on its floor unique: if another room there already has the name, the
    /// result is numbered ("Bedroom 2"). A blank name keeps the old one. Returns the name the room now has,
    /// or nil when the property has no such room.
    @discardableResult
    mutating func renameRoom(id: UUID, to name: String) -> String? {
        guard let at = roomLocation(of: id) else { return nil }
        let cleaned = ScanFlow.cleaned(name)
        guard !cleaned.isEmpty else { return floors[at.floor].rooms[at.room].name }
        let others = floors[at.floor].rooms.enumerated().filter { $0.offset != at.room }.map { $0.element.name }
        let final = RoomKindSuggester.freeName(base: cleaned, taken: others)
        floors[at.floor].rooms[at.room].name = final
        return final
    }
}
