import Foundation

// The archival scan file: everything the app knows about a property, as plain JSON that other
// tools (Python, Excel Power Query, a future web viewer) can read without NexaFixCore.
// Format reference: ios/docs/SCAN-FILE-FORMAT.md.
//
// Rules this file keeps:
//  - Lengths are metres, angles degrees, rounded to 0.1 mm (angles to 0.001 degree) so float
//    noise (3.0000000000000004) never reaches the file.
//  - Every dimension is a "measured object" that carries BOTH the LiDAR number and the site
//    check, so a merely-scanned value can never be mistaken for a verified one. `valueM` is the
//    number to use (the verified one when there is one).
//  - Numbers DERIVED from several dimensions (a rectangle's length and width, perimeters, the
//    effective floor area) carry provenance too: the scanned-only figure and a flag that says
//    whether every dimension that went into them was verified. A figure that blends verified and
//    scanned walls matches neither measurement, and its flag is false.
//  - Output is deterministic: sorted keys, model order for floors, rooms, walls and openings
//    (openings are ordered by wall, then position along the wall).

// MARK: - Shared internals (used by the CSV, costing-spec and store files too)

/// Rounding and fixed-point text helpers. Internal to the data exporters.
enum DataNumber {
    /// Rounds to 0.1 mm (1e-4). Non-finite numbers cannot be written to JSON and become 0, and
    /// negative zero is normalised, so output is stable.
    static func round4(_ v: Double) -> Double { rounded(v, scale: 10_000) }

    /// Rounds to 0.001 (angles in degrees).
    static func round3(_ v: Double) -> Double { rounded(v, scale: 1_000) }

    static func rounded(_ v: Double, scale: Double) -> Double {
        guard v.isFinite else { return 0 }
        let scaled = v * scale
        guard scaled.isFinite else { return v }
        let r = scaled.rounded() / scale
        return r == 0 ? 0 : r
    }

    /// `%.Nf` without locale, never "-0.0". Uses the C formatter so it matches on every platform.
    static func fixed(_ v: Double, decimals: Int) -> String {
        guard v.isFinite else { return "" }
        var s = String(format: "%.\(max(0, decimals))f", v)
        if Double(s) == 0 { s = String(s.drop(while: { $0 == "-" })) }
        return s
    }
}

/// "Wall A", "Wall B" ... "Wall Z", "Wall AA". Same lettering as the on-site verification list.
enum DataLabels {
    static func wallLetters(_ index: Int) -> String {
        guard index >= 0 else { return "?" }
        var n = index + 1
        var letters: [Character] = []
        while n > 0 {
            n -= 1
            letters.append(Character(UnicodeScalar(UInt8(65 + n % 26))))
            n /= 26
        }
        return String(letters.reversed())
    }

    static func wall(_ index: Int) -> String { "Wall " + wallLetters(index) }
}

/// An opening with its numbering. Openings are ordered by the loop index of their wall, then by
/// offset along the wall, then by array position; openings without a wall come last. Numbers
/// ("Door 1", "Window 2") count per kind in that order.
struct DataOpeningRef {
    let index: Int            // position in `room.openings`
    let opening: Opening
    let wallIndex: Int?       // loop index of the wall, nil when it is not a wall of this room
    let label: String         // "Door 1"
}

enum DataOpenings {
    static func ordered(in room: Room) -> [DataOpeningRef] {
        var wallIndex: [UUID: Int] = [:]
        for (i, wall) in room.walls.enumerated() where wallIndex[wall.id] == nil { wallIndex[wall.id] = i }

        func key(_ i: Int) -> (Int, Double) {
            let o = room.openings[i]
            let w = o.wallID.flatMap { wallIndex[$0] } ?? Int.max
            let off = o.offsetFromWallStart.isFinite ? o.offsetFromWallStart : Double.greatestFiniteMagnitude
            return (w, off)
        }
        let order = room.openings.indices.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return a < b
        }
        var counters: [OpeningKind: Int] = [:]
        return order.map { i in
            let o = room.openings[i]
            let n = (counters[o.kind] ?? 0) + 1
            counters[o.kind] = n
            return DataOpeningRef(index: i, opening: o, wallIndex: o.wallID.flatMap { wallIndex[$0] },
                                  label: "\(o.kind.displayName) \(n)")
        }
    }
}

/// One dimension somebody can check on site.
struct DataMeasureItem {
    /// "Wall A length", "Door 1 width", "Ceiling height", a custom measurement's label.
    let label: String
    let measured: Measured
    /// Joinery, doors and fittings are cut to this dimension: wall lengths, ceiling height,
    /// opening widths and heights, custom measurements.
    let isJoinery: Bool
}

/// The list of checkable dimensions of a room, with the same membership rules as the app's
/// on-site verification checklist so the counts in exports match the counts on screen:
///  - the height of an open-plan boundary (virtual wall) has no wall, so it is not listed;
///  - the sill of an opening that sits on the floor (scanned under 5 mm) is not listed unless
///    somebody verified it;
///  - an open-plan boundary's length is listed but is not joinery-critical.
enum DataMeasureList {
    static func items(for room: Room) -> [DataMeasureItem] {
        var out: [DataMeasureItem] = []
        for (i, wall) in room.walls.enumerated() {
            let virtual = wall.kind == .virtual
            out.append(DataMeasureItem(label: DataLabels.wall(i) + " length", measured: wall.length,
                                       isJoinery: !virtual))
            if !virtual {
                out.append(DataMeasureItem(label: DataLabels.wall(i) + " height", measured: wall.height,
                                           isJoinery: false))
            }
        }
        out.append(DataMeasureItem(label: "Ceiling height", measured: room.ceilingHeight, isJoinery: true))
        for ref in DataOpenings.ordered(in: room) {
            let o = ref.opening
            out.append(DataMeasureItem(label: ref.label + " width", measured: o.width, isJoinery: true))
            out.append(DataMeasureItem(label: ref.label + " height", measured: o.height, isJoinery: true))
            if o.sillHeight.scanned >= 0.005 || o.sillHeight.isVerified {
                out.append(DataMeasureItem(label: ref.label + " sill height", measured: o.sillHeight,
                                           isJoinery: false))
            }
        }
        for custom in room.customMeasurements {
            let label = custom.label.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(DataMeasureItem(label: label.isEmpty ? "Custom measurement" : label,
                                       measured: custom.length, isJoinery: true))
        }
        return out
    }

    struct Counts: Equatable {
        var verified = 0
        var total = 0
        var joineryVerified = 0
        var joineryTotal = 0

        static func + (a: Counts, b: Counts) -> Counts {
            Counts(verified: a.verified + b.verified, total: a.total + b.total,
                   joineryVerified: a.joineryVerified + b.joineryVerified,
                   joineryTotal: a.joineryTotal + b.joineryTotal)
        }
    }

    static func counts(for room: Room) -> Counts {
        counts(of: items(for: room))
    }

    static func counts(of items: [DataMeasureItem]) -> Counts {
        var c = Counts()
        for item in items {
            c.total += 1
            if item.measured.isVerified { c.verified += 1 }
            if item.isJoinery {
                c.joineryTotal += 1
                if item.measured.isVerified { c.joineryVerified += 1 }
            }
        }
        return c
    }

    static func counts(for property: Property) -> Counts {
        property.allRooms.reduce(Counts()) { $0 + counts(for: $1) }
    }
}

/// Where the numbers `RoomMetrics` derives from wall lengths come from: the LiDAR-only figure and whether
/// every wall that went into the figure was verified. Mirrors `RoomMetrics` exactly (its rectangle rule is
/// `length = max(a, b)` with `a`, `b` the means of opposite sides), so `value` and `scanned` differ only by
/// what verification changed.
struct DataDerived {
    /// Sum of LiDAR wall lengths, all walls / solid walls only.
    let perimeterScanned: Double
    let wallPerimeterScanned: Double
    /// Every wall (every solid wall) has a site check. False with no walls.
    let perimeterVerified: Bool
    let wallPerimeterVerified: Bool

    /// Rectangles only: the side pair behind `RoomMetrics.length` / `width`, scanned figure and flag.
    let lengthScanned: Double?
    let widthScanned: Double?
    let lengthVerified: Bool?
    let widthVerified: Bool?

    /// What `RoomMetrics.effectiveFloorArea` would be with no site checks, and whether it rests on
    /// verified dimensions. The area of a non-rectangular room comes from the scanned corner
    /// coordinates, which verification never moves, so it is never verified.
    let effectiveAreaScanned: Double
    let effectiveAreaVerified: Bool

    init(room: Room, metrics m: RoomMetrics) {
        perimeterScanned = room.walls.reduce(0) { $0 + $1.length.scanned }
        let solid = room.walls.filter { $0.kind == .solid }
        wallPerimeterScanned = solid.reduce(0) { $0 + $1.length.scanned }
        perimeterVerified = !room.walls.isEmpty && room.walls.allSatisfy { $0.length.isVerified }
        wallPerimeterVerified = !solid.isEmpty && solid.allSatisfy { $0.length.isVerified }

        if m.isRectangular, m.sides.count == 4 {
            let s = m.sides
            let a = (s[0].length + s[2].length) / 2, b = (s[1].length + s[3].length) / 2
            let aScanned = (s[0].scannedLength + s[2].scannedLength) / 2
            let bScanned = (s[1].scannedLength + s[3].scannedLength) / 2
            let aVerified = s[0].isVerified && s[2].isVerified
            let bVerified = s[1].isVerified && s[3].isVerified
            let aIsLength = a >= b                      // RoomMetrics: length = max(a, b)
            lengthScanned = aIsLength ? aScanned : bScanned
            widthScanned = aIsLength ? bScanned : aScanned
            lengthVerified = aIsLength ? aVerified : bVerified
            widthVerified = aIsLength ? bVerified : aVerified
            effectiveAreaScanned = aScanned * bScanned
            effectiveAreaVerified = aVerified && bVerified
        } else {
            lengthScanned = nil
            widthScanned = nil
            lengthVerified = nil
            widthVerified = nil
            effectiveAreaScanned = m.floorArea
            effectiveAreaVerified = false
        }
    }
}

// MARK: - The scan file

/// The decoded form of `nexafix.scan` version 1.
///
/// Build one with `ScanExport.make(property:generatedAt:)` and serialise it with
/// `ScanExport.json(property:generatedAt:)`. Every type is `Codable`, so a reader written in
/// Swift can decode the file back; optional fields are always written (as `null`), never left out.
public struct ScanFile: Codable, Hashable, Sendable {

    public static let schemaName = "nexafix.scan"
    public static let currentVersion = 1
    public static let generatorName = "NexaFix Scan"

    public var schema: String
    public var version: Int
    /// ISO 8601, UTC, milliseconds.
    public var generatedAt: String
    public var generator: String
    public var units: UnitsInfo
    public var property: PropertyInfo
    public var summary: Summary
    public var floors: [FloorEntry]

    // MARK: Nested types

    public struct UnitsInfo: Codable, Hashable, Sendable {
        /// Always "metres".
        public var storage: String
        /// Always "degrees".
        public var angles: String
        /// How plan coordinates read.
        public var coordinates: String
    }

    public struct PropertyInfo: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var client: String
        public var address: String
        public var reference: String
        public var kind: String
        public var notes: String
        public var createdAt: String
        public var updatedAt: String
    }

    public struct Summary: Codable, Hashable, Sendable {
        public var roomCount: Int
        public var floorCount: Int
        /// Sum of every room's `effectiveFloorAreaM2`, balconies included.
        public var totalFloorAreaM2: Double
        /// The same without balconies / outdoor rooms.
        public var indoorFloorAreaM2: Double
        /// Dimensions with a site check, over all rooms.
        public var verifiedCount: Int
        /// Dimensions that can be checked, over all rooms.
        public var measurementCount: Int
        /// The joinery-critical subset of the two counts above.
        public var joineryVerifiedCount: Int
        public var joineryMeasurementCount: Int
    }

    public struct AssetsInfo: Codable, Hashable, Sendable {
        public var structureUSDZ: String?
        public var worldMap: String?

        enum CodingKeys: String, CodingKey { case structureUSDZ, worldMap }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(structureUSDZ, forKey: .structureUSDZ)
            try c.encode(worldMap, forKey: .worldMap)
        }
    }

    public struct FloorEntry: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var level: Int
        public var assets: AssetsInfo
        public var rooms: [RoomEntry]
    }

    /// A point in plan space: x east, y north when the plan is drawn top-down, metres.
    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
    }

    /// A point in the AR session's world frame: Y up, metres. Not plan space.
    public struct WorldPoint: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double
    }

    /// A dimension with its provenance. Use `valueM`.
    public struct MeasuredValue: Codable, Hashable, Sendable {
        /// What LiDAR measured. Never changes.
        public var scannedM: Double
        /// What a person measured on site; null when nobody did.
        public var verifiedM: Double?
        /// The number to use: `verifiedM` when present, otherwise `scannedM`.
        public var valueM: Double
        /// "laser", "tape" or "drawing"; null when unverified.
        public var source: String?
        public var verifiedAt: String?
        public var note: String?
        /// `verifiedM - scannedM`; positive means the scan read short. Null when unverified.
        public var deviationM: Double?

        public var isVerified: Bool { verifiedM != nil }

        init(_ m: Measured) {
            scannedM = DataNumber.round4(m.scanned)
            verifiedM = m.verification.map { DataNumber.round4($0.value) }
            valueM = DataNumber.round4(m.value)
            source = m.verification?.source.rawValue
            verifiedAt = m.verification.map { DataDates.iso8601Millis($0.date) }
            note = m.verification?.note
            deviationM = m.verification.map { DataNumber.round4($0.value - m.scanned) }
        }

        enum CodingKeys: String, CodingKey {
            case scannedM, verifiedM, valueM, source, verifiedAt, note, deviationM
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(scannedM, forKey: .scannedM)
            try c.encode(verifiedM, forKey: .verifiedM)
            try c.encode(valueM, forKey: .valueM)
            try c.encode(source, forKey: .source)
            try c.encode(verifiedAt, forKey: .verifiedAt)
            try c.encode(note, forKey: .note)
            try c.encode(deviationM, forKey: .deviationM)
        }
    }

    public struct CornerEntry: Codable, Hashable, Sendable {
        public var index: Int
        public var x: Double
        public var y: Double
        /// 0..<360; the inside of an L-shape reads about 270.
        public var interiorAngleDeg: Double
        /// `interiorAngleDeg - 90`.
        public var deviationFrom90Deg: Double
        public var isReflex: Bool
        /// More than 1 degree from square. Straight continuations and reflex corners are not flagged.
        public var isOutOfSquare: Bool
    }

    public struct WallEntry: Codable, Hashable, Sendable {
        public var id: String
        /// Position in the room's counter-clockwise loop.
        public var index: Int
        /// "Wall A", "Wall B", ... by loop index.
        public var label: String
        public var start: Point
        public var end: Point
        /// "solid" or "virtual" (open-plan boundary, no wall).
        public var kind: String
        public var isCurved: Bool
        public var length: MeasuredValue
        public var height: MeasuredValue
    }

    public struct OpeningEntry: Codable, Hashable, Sendable {
        public var id: String
        /// "door", "window" or "opening".
        public var kind: String
        /// "Door 1", "Window 2" ... numbered per kind in wall order.
        public var label: String
        public var wallId: String?
        public var wallIndex: Int?
        /// Distance from the wall's start corner to the opening's near edge, in the LiDAR geometry.
        public var offsetFromStartM: Double
        /// Distance from the opening's far edge to the wall's end corner, in the LiDAR geometry
        /// (wall length minus offset minus scanned width). Null when the wall is unknown.
        public var offsetFromEndM: Double?
        public var width: MeasuredValue
        public var height: MeasuredValue
        /// Bottom edge above the floor.
        public var sillHeight: MeasuredValue

        enum CodingKeys: String, CodingKey {
            case id, kind, label, wallId, wallIndex, offsetFromStartM, offsetFromEndM, width, height, sillHeight
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(label, forKey: .label)
            try c.encode(wallId, forKey: .wallId)
            try c.encode(wallIndex, forKey: .wallIndex)
            try c.encode(offsetFromStartM, forKey: .offsetFromStartM)
            try c.encode(offsetFromEndM, forKey: .offsetFromEndM)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
            try c.encode(sillHeight, forKey: .sillHeight)
        }
    }

    public struct ObjectEntry: Codable, Hashable, Sendable {
        public var id: String
        public var kind: String
        /// Footprint centre, plan space.
        public var center: Point
        /// Rotation of the width axis, counter-clockwise from plan +x, 0..<360 degrees.
        public var yawDeg: Double
        public var widthM: Double
        public var depthM: Double
        public var heightM: Double
        /// Bottom face above the floor.
        public var elevationM: Double
    }

    public struct CustomEntry: Codable, Hashable, Sendable {
        public var id: String
        public var label: String
        /// World-space end points (Y up), not plan space.
        public var a: WorldPoint
        public var b: WorldPoint
        public var length: MeasuredValue
        public var createdAt: String
        public var note: String?

        enum CodingKeys: String, CodingKey { case id, label, a, b, length, createdAt, note }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(label, forKey: .label)
            try c.encode(a, forKey: .a)
            try c.encode(b, forKey: .b)
            try c.encode(length, forKey: .length)
            try c.encode(createdAt, forKey: .createdAt)
            try c.encode(note, forKey: .note)
        }
    }

    public struct VerificationCounts: Codable, Hashable, Sendable {
        /// Dimensions with a site check.
        public var verified: Int
        /// Dimensions that can be checked.
        public var total: Int
        public var joineryVerified: Int
        public var joineryTotal: Int
    }

    public struct RoomEntry: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        /// Area of the scanned outline.
        public var floorAreaM2: Double
        /// Area to use: length x width from the effective side lengths for a rectangle, the
        /// outline area otherwise.
        public var effectiveFloorAreaM2: Double
        /// `effectiveFloorAreaM2` computed from LiDAR lengths only (the outline area for a non-rectangle).
        public var effectiveFloorAreaScannedM2: Double
        /// True only for a rectangle whose four sides were all verified. Always false for any other
        /// shape: its area comes from scanned corner coordinates, which verification does not move.
        public var effectiveFloorAreaVerified: Bool
        /// Sum of effective wall lengths, open-plan boundaries included.
        public var perimeterM: Double
        /// `perimeterM` from LiDAR lengths only.
        public var perimeterScannedM: Double
        /// Every wall's length was verified.
        public var perimeterVerified: Bool
        /// The same for solid walls only.
        public var wallPerimeterM: Double
        public var wallPerimeterScannedM: Double
        /// Every solid wall's length was verified.
        public var wallPerimeterVerified: Bool
        public var ceilingHeight: MeasuredValue
        public var isRectangular: Bool
        /// Longer side (effective); null unless rectangular. When `lengthVerified` is false this is
        /// either the scanned figure or an average of verified and scanned walls: do not cut from it.
        public var lengthM: Double?
        /// The same two opposite sides measured by LiDAR only; null unless rectangular.
        public var lengthScannedM: Double?
        /// Every wall of both opposite sides behind `lengthM` was verified; null unless rectangular.
        public var lengthVerified: Bool?
        /// Shorter side (effective); null unless rectangular.
        public var widthM: Double?
        public var widthScannedM: Double?
        public var widthVerified: Bool?
        public var volumeM3: Double
        public var grossWallAreaM2: Double
        public var openingAreaM2: Double
        public var netWallAreaM2: Double
        public var corners: [CornerEntry]
        public var walls: [WallEntry]
        public var openings: [OpeningEntry]
        public var objects: [ObjectEntry]
        public var customMeasurements: [CustomEntry]
        public var verification: VerificationCounts
        public var scannedAt: String
        /// World Y of the floor in the scan session's frame.
        public var floorElevationM: Double
        /// Relative path of the saved RoomPlan capture, if any.
        public var capturedRoomFile: String?
        public var notes: String

        enum CodingKeys: String, CodingKey {
            case id, name, kind, floorAreaM2, effectiveFloorAreaM2, effectiveFloorAreaScannedM2, effectiveFloorAreaVerified
            case perimeterM, perimeterScannedM, perimeterVerified, wallPerimeterM, wallPerimeterScannedM, wallPerimeterVerified
            case ceilingHeight, isRectangular, lengthM, lengthScannedM, lengthVerified, widthM, widthScannedM, widthVerified
            case volumeM3, grossWallAreaM2, openingAreaM2, netWallAreaM2
            case corners, walls, openings, objects, customMeasurements, verification
            case scannedAt, floorElevationM, capturedRoomFile, notes
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(kind, forKey: .kind)
            try c.encode(floorAreaM2, forKey: .floorAreaM2)
            try c.encode(effectiveFloorAreaM2, forKey: .effectiveFloorAreaM2)
            try c.encode(effectiveFloorAreaScannedM2, forKey: .effectiveFloorAreaScannedM2)
            try c.encode(effectiveFloorAreaVerified, forKey: .effectiveFloorAreaVerified)
            try c.encode(perimeterM, forKey: .perimeterM)
            try c.encode(perimeterScannedM, forKey: .perimeterScannedM)
            try c.encode(perimeterVerified, forKey: .perimeterVerified)
            try c.encode(wallPerimeterM, forKey: .wallPerimeterM)
            try c.encode(wallPerimeterScannedM, forKey: .wallPerimeterScannedM)
            try c.encode(wallPerimeterVerified, forKey: .wallPerimeterVerified)
            try c.encode(ceilingHeight, forKey: .ceilingHeight)
            try c.encode(isRectangular, forKey: .isRectangular)
            try c.encode(lengthM, forKey: .lengthM)
            try c.encode(lengthScannedM, forKey: .lengthScannedM)
            try c.encode(lengthVerified, forKey: .lengthVerified)
            try c.encode(widthM, forKey: .widthM)
            try c.encode(widthScannedM, forKey: .widthScannedM)
            try c.encode(widthVerified, forKey: .widthVerified)
            try c.encode(volumeM3, forKey: .volumeM3)
            try c.encode(grossWallAreaM2, forKey: .grossWallAreaM2)
            try c.encode(openingAreaM2, forKey: .openingAreaM2)
            try c.encode(netWallAreaM2, forKey: .netWallAreaM2)
            try c.encode(corners, forKey: .corners)
            try c.encode(walls, forKey: .walls)
            try c.encode(openings, forKey: .openings)
            try c.encode(objects, forKey: .objects)
            try c.encode(customMeasurements, forKey: .customMeasurements)
            try c.encode(verification, forKey: .verification)
            try c.encode(scannedAt, forKey: .scannedAt)
            try c.encode(floorElevationM, forKey: .floorElevationM)
            try c.encode(capturedRoomFile, forKey: .capturedRoomFile)
            try c.encode(notes, forKey: .notes)
        }
    }
}

// MARK: - Building and serialising

public enum ScanExport {

    /// Build the scan file for a property. `generatedAt` is injected so output is reproducible.
    public static func make(property: Property, generatedAt: Date) -> ScanFile {
        var verifiedCount = 0, measurementCount = 0, joineryVerified = 0, joineryTotal = 0
        var totalArea = 0.0, indoorArea = 0.0

        let floors: [ScanFile.FloorEntry] = property.floors.map { floor in
            let rooms: [ScanFile.RoomEntry] = floor.rooms.map { room in
                let entry = makeRoom(room)
                verifiedCount += entry.verification.verified
                measurementCount += entry.verification.total
                joineryVerified += entry.verification.joineryVerified
                joineryTotal += entry.verification.joineryTotal
                totalArea += entry.effectiveFloorAreaM2
                if !room.kind.isOutdoor { indoorArea += entry.effectiveFloorAreaM2 }
                return entry
            }
            return ScanFile.FloorEntry(
                id: floor.id.uuidString, name: floor.name, level: floor.level,
                assets: ScanFile.AssetsInfo(structureUSDZ: floor.assets.structureUSDZ,
                                            worldMap: floor.assets.worldMap),
                rooms: rooms)
        }

        return ScanFile(
            schema: ScanFile.schemaName,
            version: ScanFile.currentVersion,
            generatedAt: DataDates.iso8601Millis(generatedAt),
            generator: ScanFile.generatorName,
            units: ScanFile.UnitsInfo(
                storage: "metres", angles: "degrees",
                coordinates: "plan space: x east, y north when drawn top-down; world points (custom measurements) are Y up"),
            property: ScanFile.PropertyInfo(
                id: property.id.uuidString, name: property.name, client: property.client,
                address: property.address, reference: property.reference, kind: property.kind.rawValue,
                notes: property.notes,
                createdAt: DataDates.iso8601Millis(property.createdAt),
                updatedAt: DataDates.iso8601Millis(property.updatedAt)),
            summary: ScanFile.Summary(
                roomCount: property.roomCount, floorCount: property.floors.count,
                totalFloorAreaM2: DataNumber.round4(totalArea),
                indoorFloorAreaM2: DataNumber.round4(indoorArea),
                verifiedCount: verifiedCount, measurementCount: measurementCount,
                joineryVerifiedCount: joineryVerified, joineryMeasurementCount: joineryTotal),
            floors: floors)
    }

    /// The scan file as pretty-printed UTF-8 JSON with sorted keys and a trailing newline.
    public static func json(property: Property, generatedAt: Date) throws -> Data {
        try encode(make(property: property, generatedAt: generatedAt))
    }

    /// Serialise an already-built scan file with the same settings as `json(property:generatedAt:)`.
    public static func encode(_ file: ScanFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(file)
        data.append(0x0A)
        return data
    }

    // MARK: Rooms

    private static func makeRoom(_ room: Room) -> ScanFile.RoomEntry {
        let m = room.metrics
        let r4 = DataNumber.round4

        // A loop of fewer than three walls has no corners, only the degenerate angles of a line.
        let outOfSquare = Set(m.outOfSquareCorners.map(\.index))
        let corners: [ScanFile.CornerEntry] = room.walls.count < 3 ? [] : m.corners.map { corner in
            ScanFile.CornerEntry(
                index: corner.index, x: r4(corner.point.x), y: r4(corner.point.y),
                interiorAngleDeg: DataNumber.round3(corner.interiorAngle),
                deviationFrom90Deg: DataNumber.round3(corner.deviationFrom90),
                isReflex: corner.isReflex,
                isOutOfSquare: outOfSquare.contains(corner.index))
        }

        var wallIndex: [UUID: Int] = [:]
        for (i, wall) in room.walls.enumerated() where wallIndex[wall.id] == nil { wallIndex[wall.id] = i }

        let walls: [ScanFile.WallEntry] = room.walls.enumerated().map { i, wall in
            ScanFile.WallEntry(
                id: wall.id.uuidString, index: i, label: DataLabels.wall(i),
                start: ScanFile.Point(x: r4(wall.start.x), y: r4(wall.start.y)),
                end: ScanFile.Point(x: r4(wall.end.x), y: r4(wall.end.y)),
                kind: wall.kind.rawValue, isCurved: wall.isCurved,
                length: ScanFile.MeasuredValue(wall.length), height: ScanFile.MeasuredValue(wall.height))
        }

        let openings: [ScanFile.OpeningEntry] = DataOpenings.ordered(in: room).map { ref in
            let o = ref.opening
            let wall = ref.wallIndex.map { room.walls[$0] }
            let fromEnd = wall.map { r4($0.geometricLength - o.offsetFromWallStart - o.width.scanned) }
            // A wall id that is not one of this room's walls is a dangling reference: it matches nothing,
            // so it is written as null like an opening that never had a wall.
            return ScanFile.OpeningEntry(
                id: o.id.uuidString, kind: o.kind.rawValue, label: ref.label,
                wallId: wall?.id.uuidString, wallIndex: ref.wallIndex,
                offsetFromStartM: r4(o.offsetFromWallStart), offsetFromEndM: fromEnd,
                width: ScanFile.MeasuredValue(o.width), height: ScanFile.MeasuredValue(o.height),
                sillHeight: ScanFile.MeasuredValue(o.sillHeight))
        }

        let objects: [ScanFile.ObjectEntry] = room.objects.map { obj in
            ScanFile.ObjectEntry(
                id: obj.id.uuidString, kind: obj.kind.rawValue,
                center: ScanFile.Point(x: r4(obj.center.x), y: r4(obj.center.y)),
                yawDeg: yawDegrees(obj.yaw),
                widthM: r4(obj.width), depthM: r4(obj.depth), heightM: r4(obj.height),
                elevationM: r4(obj.elevation))
        }

        let customs: [ScanFile.CustomEntry] = room.customMeasurements.map { c in
            ScanFile.CustomEntry(
                id: c.id.uuidString, label: c.label,
                a: ScanFile.WorldPoint(x: r4(c.a.x), y: r4(c.a.y), z: r4(c.a.z)),
                b: ScanFile.WorldPoint(x: r4(c.b.x), y: r4(c.b.y), z: r4(c.b.z)),
                length: ScanFile.MeasuredValue(c.length),
                createdAt: DataDates.iso8601Millis(c.createdAt), note: c.note)
        }

        let counts = DataMeasureList.counts(for: room)
        let d = DataDerived(room: room, metrics: m)

        return ScanFile.RoomEntry(
            id: room.id.uuidString, name: room.name, kind: room.kind.rawValue,
            floorAreaM2: r4(m.floorArea), effectiveFloorAreaM2: r4(m.effectiveFloorArea),
            effectiveFloorAreaScannedM2: r4(d.effectiveAreaScanned), effectiveFloorAreaVerified: d.effectiveAreaVerified,
            perimeterM: r4(m.perimeter), perimeterScannedM: r4(d.perimeterScanned), perimeterVerified: d.perimeterVerified,
            wallPerimeterM: r4(m.wallPerimeter), wallPerimeterScannedM: r4(d.wallPerimeterScanned),
            wallPerimeterVerified: d.wallPerimeterVerified,
            ceilingHeight: ScanFile.MeasuredValue(room.ceilingHeight),
            isRectangular: m.isRectangular,
            lengthM: m.isRectangular ? m.length.map(r4) : nil,
            lengthScannedM: d.lengthScanned.map(r4), lengthVerified: d.lengthVerified,
            widthM: m.isRectangular ? m.width.map(r4) : nil,
            widthScannedM: d.widthScanned.map(r4), widthVerified: d.widthVerified,
            volumeM3: r4(m.volume), grossWallAreaM2: r4(m.grossWallArea),
            openingAreaM2: r4(m.openingArea), netWallAreaM2: r4(m.netWallArea),
            corners: corners, walls: walls, openings: openings, objects: objects,
            customMeasurements: customs,
            verification: ScanFile.VerificationCounts(
                verified: counts.verified, total: counts.total,
                joineryVerified: counts.joineryVerified, joineryTotal: counts.joineryTotal),
            scannedAt: DataDates.iso8601Millis(room.scannedAt),
            floorElevationM: r4(room.floorElevation),
            capturedRoomFile: room.capturedRoomFile,
            notes: room.notes)
    }

    /// Yaw radians to degrees in 0..<360, rounded to 0.001.
    static func yawDegrees(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        var d = (radians * 180 / Double.pi).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        let r = DataNumber.round3(d)
        return r >= 360 ? 0 : r
    }
}
