import Foundation
import NexaFixCore

// Everything the screens do to a property that is not drawing: duplicate, rename, delete, change a
// room, record a check, take in a finished scan. Plain Swift on Foundation, NexaFixCore and the app's own
// plain-Swift types, so it is type-checked and run on Linux (see ios/tools). The views stay thin and call
// these.
//
// Every change to a saved property goes through `AppModel.update`, so a failed save is never silent and
// unsaved changes stay listed until they are written.

// MARK: - Actions on properties and rooms

@MainActor
struct PropertyActions {
    let model: AppModel

    // MARK: Properties

    /// Copies a property, its rooms and its files under new ids ("Marina copy"). Returns the copy, or nil
    /// after showing an error.
    @discardableResult
    func duplicate(_ id: UUID) -> Property? {
        guard let current = model.property(id) else { return nil }
        // The copy is made from what is on disk, so anything only in memory is saved first.
        if model.unsavedPropertyIDs.contains(id), !model.save(current) { return nil }
        do {
            let copy = try model.store.duplicate(id: id)
            model.refresh()
            return copy
        } catch {
            report(error, context: "duplicate \(displayName(of: current))")
            return nil
        }
    }

    /// Gives a property a new name. A blank name is ignored.
    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.update(propertyID: id) { $0.name = clean }
    }

    /// Changes the details shown on the header and in every export. Blank client, address and reference are
    /// allowed; a blank name is ignored.
    func updateDetails(_ id: UUID, name: String, client: String, address: String, reference: String,
                       kind: PropertyKind) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        model.update(propertyID: id) { property in
            if !clean.isEmpty { property.name = clean }
            property.client = client
            property.address = address
            property.reference = reference
            property.kind = kind
        }
    }

    /// Deletes a property and its files. The caller has already asked the person.
    func delete(_ id: UUID) {
        model.delete(id)
    }

    // MARK: Rooms

    func renameRoom(propertyID: UUID, roomID: UUID, to name: String) {
        model.update(propertyID: propertyID) { $0.renameRoom(id: roomID, to: name) }
    }

    func setRoomKind(propertyID: UUID, roomID: UUID, to kind: RoomKind) {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.kind = kind }
        }
    }

    /// Deletes a room (a floor left with no rooms goes with it). The caller has already asked the person.
    func deleteRoom(propertyID: UUID, roomID: UUID) {
        model.update(propertyID: propertyID) { $0.deleteRoom(id: roomID) }
    }

    func setNotes(propertyID: UUID, roomID: UUID, to notes: String) {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.notes = notes }
        }
    }

    // MARK: Checks and measurements

    /// Records a site check for one dimension, or clears it with nil. Applied to the room as it is now, so
    /// nothing else in the room changes. Returns whether the change reached storage.
    @discardableResult
    func saveVerification(propertyID: UUID, roomID: UUID, target: MeasureTarget,
                          verification: Verification?) -> Bool {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.setVerification(verification, for: target) }
        }
    }

    /// Adds a measurement taken in AR or in the 3D viewer to the room it belongs to.
    @discardableResult
    func addMeasurement(_ measurement: CustomMeasurement, propertyID: UUID, roomID: UUID) -> Bool {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { room in
                guard !room.customMeasurements.contains(where: { $0.id == measurement.id }) else { return }
                room.customMeasurements.append(measurement)
            }
        }
    }

    // MARK: Errors

    /// Shows a lesser error unless the person still has an unacknowledged "your work is not saved" alert.
    private func report(_ error: Error, context: String) {
        if model.presentedError?.severity == .dataAtRisk { return }
        model.presentedError = UserFacingError(error, context: context)
    }

    private func displayName(of property: Property) -> String {
        let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "this property" : "\u{201C}\(name)\u{201D}"
    }
}

// MARK: - Taking in a finished scan

/// Saves what the scan screen hands back: the files first, then the property with its new floor.
@MainActor
enum ScanIntake {

    /// What happened, in words for the person.
    struct Outcome {
        /// "Added 5 rooms to Level 23."
        var summary: String
        /// Things to tell the person: the scan screen's own warnings, and files that could not be saved.
        var warnings: [String]
        var floorID: UUID?
        /// The property with the new floor reached storage.
        var saved: Bool
    }

    /// Adds the scan to the property as a new floor.
    ///
    /// The order matters: files are written first, and the property only mentions files that were written.
    /// A room is never lost because a file failed (the failure is reported and the room is kept without
    /// that file). Applying the same result twice adds nothing the second time.
    static func commit(_ result: ScanResult, to propertyID: UUID, model: AppModel, now: Date = Date()) -> Outcome {
        guard let property = model.property(propertyID) else {
            return Outcome(summary: "The scan could not be added because the property could not be opened.",
                           warnings: result.warnings, floorID: nil, saved: false)
        }

        let available = ScanCommit.AvailableAssets(
            structureUSDZ: !(result.structureUSDZ?.isEmpty ?? true),
            worldMap: !(result.worldMapData?.isEmpty ?? true),
            capturedRoomIDs: Set(result.rooms.map(\.id).filter { !(result.capturedRoomJSON[$0]?.isEmpty ?? true) }))
        let plan = ScanCommit.apply(rooms: result.rooms, story: result.story, scannedAt: now, to: property,
                                    available: available)
        guard let floorID = plan.floorID else {
            return Outcome(summary: plan.summary, warnings: result.warnings, floorID: nil, saved: false)
        }

        // Files first.
        var written = ScanCommit.AvailableAssets()
        var warnings = result.warnings
        for asset in plan.assets {
            let data: Data?
            switch asset.kind {
            case .structureUSDZ: data = result.structureUSDZ
            case .worldMap: data = result.worldMapData
            case .capturedRoom(let roomID): data = result.capturedRoomJSON[roomID]
            }
            guard let data, model.writeAsset(data, relativePath: asset.relativePath, propertyID: propertyID) != nil else {
                warnings.append(failureWarning(for: asset.kind))
                continue
            }
            switch asset.kind {
            case .structureUSDZ: written.structureUSDZ = true
            case .worldMap: written.worldMap = true
            case .capturedRoom(let roomID): written.capturedRoomIDs.insert(roomID)
            }
        }

        // Then the property, applied to its latest copy so edits made meanwhile are kept. The same floor id
        // makes the result identical to the plan.
        let rooms = result.rooms
        let story = result.story
        let saved = model.update(propertyID: propertyID) { live in
            live = ScanCommit.apply(rooms: rooms, story: story, scannedAt: now, to: live, available: written,
                                    makeID: { floorID }).property
        }
        return Outcome(summary: plan.summary, warnings: warnings, floorID: floorID, saved: saved)
    }

    private static func failureWarning(for kind: ScanCommit.PlannedAsset.Kind) -> String {
        switch kind {
        case .structureUSDZ: return "The 3D model could not be saved, so it cannot be exported. The rooms were kept."
        case .worldMap: return "The AR map could not be saved, so AR review will not line up. The rooms were kept."
        case .capturedRoom: return "One room\u{2019}s detailed scan data could not be saved. The room itself was kept."
        }
    }
}

// MARK: - Defaults for a new property

enum PropertyDefaults {
    /// Levels the picker offers: basements to the top of a tower.
    static let storyRange = -5...200
    /// Ground level.
    static let firstStory = 0

    /// `NF-<year>-<month day>-01` for the Dubai calendar day of `date`: "NF-2026-1009-01".
    static func suggestedReference(on date: Date) -> String {
        let parts = ExportNaming.dateStamp(date).split(separator: "-")
        guard parts.count == 3 else { return "NF-" + ExportNaming.dateStamp(date) + "-01" }
        return "NF-\(parts[0])-\(parts[1])\(parts[2])-01"
    }

    /// The level to offer for the next scan of a property: the one that was last looked at, else the one
    /// most recently scanned, else ground.
    static func nextStory(in property: Property, preferring floorID: UUID? = nil) -> Int {
        if let floorID, let floor = property.floors.first(where: { $0.id == floorID }) { return floor.level }
        return property.floors.last?.level ?? firstStory
    }
}

// MARK: - What a property card shows

/// The numbers and drawing behind one card on the home screen.
struct PropertyCardInfo {
    let roomCount: Int
    let floorCount: Int
    let areaM2: Double
    let verified: Int
    let total: Int
    /// A plain outline of the first floor that has rooms; nil when nothing is drawable.
    let drawing: PlanDrawing?

    static func make(_ property: Property) -> PropertyCardInfo {
        let progress = VerificationChecklist.propertyProgress(property)
        let area = property.allRooms.reduce(0.0) { $0 + $1.metrics.effectiveFloorArea }
        var drawing: PlanDrawing?
        if let floor = property.floors.first(where: { !$0.rooms.isEmpty }) {
            let options = PlanOptions(scale: 100, showDimensions: false, showAngles: false, showFurniture: false,
                                      showRoomLabels: false, showOpeningSizes: false, markVerified: false)
            drawing = PlanDrawingBuilder.build(floor: floor, property: property, options: options)
        }
        return PropertyCardInfo(roomCount: property.roomCount, floorCount: property.floors.count,
                                areaM2: area.isFinite ? area : 0, verified: progress.verified,
                                total: progress.total, drawing: drawing)
    }

    var summary: VerificationSummary { VerificationSummary(verified: verified, total: total) }

    /// "8 rooms \u{00B7} 112 m\u{00B2} \u{00B7} 14 of 52 checked".
    func line(units: DisplayUnits) -> String {
        var parts = [roomCount == 1 ? "1 room" : "\(roomCount) rooms"]
        if roomCount > 0 { parts.append(PropertyCardInfo.areaText(areaM2, unit: units.area)) }
        parts.append(summary.text)
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The same for VoiceOver: "8 rooms, 112 square metres, 14 of 52 dimensions checked".
    func spoken(units: DisplayUnits) -> String {
        var parts = [roomCount == 1 ? "1 room" : "\(roomCount) rooms"]
        if roomCount > 0 { parts.append(SpokenMeasurement.area(areaM2.rounded(), unit: units.area)) }
        parts.append(summary.spoken)
        return parts.joined(separator: ", ")
    }

    /// Whole units, because a card is a glance: "112 m\u{00B2}", "1205 sq ft".
    static func areaText(_ squareMetres: Double, unit: AreaUnit) -> String {
        let value = unit == .squareMetres ? squareMetres : squareMetres / UnitFormatter.squareMetresPerSquareFoot
        return "\(Int(value.rounded())) \(unit.symbol)"
    }
}

/// Remembers the card info for each property so scrolling does not rebuild drawings. An entry is reused
/// while the property's `updatedAt` is unchanged.
@MainActor
final class PropertyCardCache {
    private var entries: [UUID: (stamp: Date, info: PropertyCardInfo)] = [:]

    func info(for property: Property) -> PropertyCardInfo {
        if let entry = entries[property.id], entry.stamp == property.updatedAt { return entry.info }
        let info = PropertyCardInfo.make(property)
        entries[property.id] = (property.updatedAt, info)
        return info
    }

    /// Forgets properties that are no longer listed.
    func keep(_ ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}

// MARK: - The plan on screen

/// Builds the plan of a floor once and reuses it until the floor, the units or the property name change.
final class PlanDrawingCache {
    private struct Key: Equatable {
        var floor: Floor
        var units: DisplayUnits
        var propertyName: String
    }

    private var key: Key?
    private var drawing: PlanDrawing?

    /// Plans are drawn at 1:50 on screen; the canvas scales them to fit.
    static let onScreenScale = 50.0

    func drawing(for floor: Floor, in property: Property, units: DisplayUnits) -> PlanDrawing {
        let wanted = Key(floor: floor, units: units, propertyName: property.name)
        if let key, key == wanted, let drawing { return drawing }
        let built = PlanDrawingBuilder.build(floor: floor, property: property,
                                             options: PlanOptions(scale: PlanDrawingCache.onScreenScale, units: units))
        key = wanted
        drawing = built
        return built
    }
}

// MARK: - Corners

/// One corner of a room as the Room screen and the selection card describe it.
struct CornerReading: Identifiable, Equatable {
    enum Level: Equatable {
        /// Within 1 degree of a right angle.
        case square
        /// 1 to 3 degrees off: worth knowing, drawn in the caution colour.
        case slightlyOff
        /// 3 degrees or more off: drawn in the critical colour.
        case outOfSquare
        /// The inside of an L-shape; not a fault.
        case reflex
    }

    /// Corner `index` is the start of wall `index` (and the end of the wall before it).
    let index: Int
    /// "Wall D to Wall A".
    let title: String
    /// Interior angle, degrees.
    let angle: Double
    /// Interior angle minus 90, degrees.
    let deviation: Double
    let level: Level

    var id: Int { index }

    /// "Square", "2.4\u{00B0} off square", "Inside corner of an L-shape".
    var note: String {
        switch level {
        case .square: return "Square"
        case .slightlyOff, .outOfSquare:
            let size = UnitFormatter.angle(abs(deviation))
            return deviation > 0 ? "\(size) wider than square" : "\(size) tighter than square"
        case .reflex: return "Inside corner of an L-shape"
        }
    }

    /// For VoiceOver: "Wall D to Wall A, 92.4 degrees, 2.4 degrees wider than square".
    var spoken: String {
        let degrees = SpokenMeasurement.angle(angle)
        switch level {
        case .square: return "\(title), \(degrees), square"
        case .reflex: return "\(title), \(degrees), inside corner of an L-shape"
        case .slightlyOff, .outOfSquare:
            return "\(title), \(degrees), " + SpokenMeasurement.angle(abs(deviation))
                + (deviation > 0 ? " wider than square" : " tighter than square")
        }
    }

    static func level(forAngle angle: Double) -> Level {
        let deviation = angle - 90
        if angle > 180 + RoomMetrics.straightTolerance { return .reflex }
        if abs(deviation) <= RoomMetrics.squareTolerance { return .square }
        return abs(deviation) < 3 ? .slightlyOff : .outOfSquare
    }

    /// The corners of a room that are worth showing: straight continuations of a wall are left out.
    static func readings(for room: Room) -> [CornerReading] {
        guard room.walls.count >= 3 else { return [] }
        return room.metrics.corners.filter { !$0.isStraight }.map { reading(for: $0, in: room) }
    }

    /// One corner by index; nil when the room has no such corner.
    static func reading(at index: Int, in room: Room) -> CornerReading? {
        guard room.walls.count >= 3, index >= 0, index < room.walls.count else { return nil }
        return reading(for: room.metrics.corners[index], in: room)
    }

    private static func reading(for corner: Corner, in room: Room) -> CornerReading {
        let before = (corner.index + room.walls.count - 1) % room.walls.count
        return CornerReading(index: corner.index,
                             title: "\(room.wallTitle(at: before)) to \(room.wallTitle(at: corner.index))",
                             angle: corner.interiorAngle, deviation: corner.deviationFrom90,
                             level: level(forAngle: corner.interiorAngle))
    }
}

// MARK: - Volume

/// Room volume, which `UnitFormatter` has no word for: cubic metres, or cubic feet with square-foot users.
struct VolumeText {
    let visible: String
    let spoken: String

    init(cubicMetres: Double, units: DisplayUnits) {
        guard cubicMetres.isFinite else {
            visible = "\u{2013}"
            spoken = "No value"
            return
        }
        switch units.area {
        case .squareMetres:
            let number = String(format: "%.1f", cubicMetres)
            visible = "\(number) m\u{00B3}"
            spoken = "\(SpokenMeasurement.trimmed(number)) cubic metres"
        case .squareFeet:
            let number = String(Int((cubicMetres / 0.028316846592).rounded()))
            visible = "\(number) cu ft"
            spoken = "\(number) cubic feet"
        }
    }
}
