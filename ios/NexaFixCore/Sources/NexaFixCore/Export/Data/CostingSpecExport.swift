import Foundation

// The project spec the nexa-costing engine (skills/nexa-costing) consumes, produced from a scan.
//
// The engine's parsing rules are exact, so this file follows them to the letter
// (skills/nexa-costing/scripts/nexa_costing/spec.py and util.py):
//  - Lengths are METRES. The engine reads a plain number above 20 (room height, openings), above 60
//    (room length and width) or above 150 (perimeter) as MILLIMETRES, so a value over its limit is
//    written as text with a unit ("72.5m"), which the engine never rescales.
//  - A rectangular room is `length` + `width`; any other room is `area` + `perimeter`. A rectangle
//    with open-plan edges also gets `perimeter` (solid walls only), because skirting and paint
//    would otherwise be over-counted along the open edge.
//  - `doors` and `windows` are `[[w, h], ...]` in metres using the EFFECTIVE size (the verified one
//    when somebody laser-checked it). They are written even when empty: an empty list means "the
//    scan found none", while leaving the key out would make the engine assume one door.
//  - Tags come from `RoomKind.costingTags`; a balcony carries `outdoor`, which excludes it from the
//    engine's `all` / `dry` room selectors.
//  - `scope` is ALWAYS empty. The engine rejects an empty scope, so the file is a starting point:
//    skills/nexa-costing/scripts/from_scan.py (or the estimator) adds the scope.
//  - `x_nexafix_scan` is an extra top-level object the engine ignores. It says how much of the
//    geometry was verified on site and lists every joinery-critical dimension that was not, with
//    a warning to show to a person. For each room it also says whether the three quantities the
//    engine prices from (floor area, perimeter, height) rest on verified dimensions.
//  - The engine ADDS tags guessed from the room name to the ones written here (and takes `wet` from
//    them when it is absent); nothing in the spec can remove a guessed tag. `notes` therefore lists
//    every room whose tags the engine will change (`CostingEngineGuess` mirrors `_guess_tags`).

/// The costing project spec for one property.
public struct CostingSpec: Codable, Hashable, Sendable {

    public static let scanSchemaName = "nexafix.costing-spec"
    public static let scanSchemaVersion = 1

    public var project: Project
    public var rooms: [RoomEntry]
    /// Always empty when produced by the app.
    public var scope: [ScopeItem]
    /// Written as `x_nexafix_scan`.
    public var scanInfo: ScanInfo

    enum CodingKeys: String, CodingKey {
        case project, rooms, scope
        case scanInfo = "x_nexafix_scan"
    }

    // MARK: Project

    public struct Project: Codable, Hashable, Sendable {
        public var client: String
        public var name: String
        public var location: String
        public var ref: String
        /// Default room height for the engine, metres: the most common room ceiling height.
        public var ceilingHeight: Double?

        enum CodingKeys: String, CodingKey {
            case client, name, location, ref
            case ceilingHeight = "ceiling_height"
        }
    }

    // MARK: Lengths

    /// A length in metres in the form the engine reads without rescaling: a JSON number, or text
    /// such as "72.5m" when the number would be at or above the engine's millimetre threshold.
    public enum Length: Codable, Hashable, Sendable {
        case metres(Double)
        case text(String)

        /// The length in metres, whichever form it was written in.
        public var inMetres: Double {
            switch self {
            case .metres(let v): return v
            case .text(let s): return Double(s.dropLast()) ?? 0
            }
        }

        static func make(_ metres: Double, millimetreThreshold: Double) -> Length {
            let v = DataNumber.round4(metres)
            if v > millimetreThreshold { return .text(trimmed(v) + "m") }
            return .metres(v)
        }

        private static func trimmed(_ v: Double) -> String {
            var s = DataNumber.fixed(v, decimals: 4)
            while s.contains("."), s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Double.self) { self = .metres(v); return }
            self = .text(try c.decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .metres(let v): try c.encode(v)
            case .text(let s): try c.encode(s)
            }
        }
    }

    // MARK: Rooms

    public struct RoomEntry: Codable, Hashable, Sendable {
        public var name: String
        /// Rectangles only (effective, longer side).
        public var length: Length?
        /// Rectangles only (effective, shorter side).
        public var width: Length?
        /// Rooms that are not rectangles.
        public var area: Double?
        /// Rooms that are not rectangles, and rectangles with open-plan edges. Solid walls only.
        public var perimeter: Length?
        public var height: Length
        /// `[[width, height], ...]`, effective sizes, metres.
        public var doors: [[Double]]
        public var windows: [[Double]]
        public var tags: [String]
        /// nil (key omitted) for `RoomKind.other`, so the engine can decide from the room name.
        public var wet: Bool?
    }

    /// Placeholder for an item the estimator adds later. The app never writes one.
    public struct ScopeItem: Codable, Hashable, Sendable {}

    // MARK: Provenance

    public struct ScanInfo: Codable, Hashable, Sendable {
        public var schema: String
        public var version: Int
        public var generator: String
        public var propertyId: String
        /// `yyyy-MM-dd` (Dubai time) of the most recent room scan; nil with no rooms.
        public var scanDate: String?
        public var verifiedCount: Int
        public var measurementCount: Int
        public var joineryVerifiedCount: Int
        public var joineryMeasurementCount: Int
        public var rooms: [RoomInfo]
        public var unverifiedJoinery: [UnverifiedItem]
        /// Set whenever `unverifiedJoinery` is not empty.
        public var warning: String?
        public var notes: [String]

        enum CodingKeys: String, CodingKey {
            case schema, version, generator, rooms, warning, notes
            case propertyId = "property_id"
            case scanDate = "scan_date"
            case verifiedCount = "verified_count"
            case measurementCount = "measurement_count"
            case joineryVerifiedCount = "joinery_verified_count"
            case joineryMeasurementCount = "joinery_measurement_count"
            case unverifiedJoinery = "unverified_joinery"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schema, forKey: .schema)
            try c.encode(version, forKey: .version)
            try c.encode(generator, forKey: .generator)
            try c.encode(propertyId, forKey: .propertyId)
            try c.encode(scanDate, forKey: .scanDate)
            try c.encode(verifiedCount, forKey: .verifiedCount)
            try c.encode(measurementCount, forKey: .measurementCount)
            try c.encode(joineryVerifiedCount, forKey: .joineryVerifiedCount)
            try c.encode(joineryMeasurementCount, forKey: .joineryMeasurementCount)
            try c.encode(rooms, forKey: .rooms)
            try c.encode(unverifiedJoinery, forKey: .unverifiedJoinery)
            try c.encode(warning, forKey: .warning)
            try c.encode(notes, forKey: .notes)
        }
    }

    public struct RoomInfo: Codable, Hashable, Sendable {
        /// The name used in `rooms[].name` (made unique if the property repeats a name).
        public var name: String
        public var floor: String
        public var kind: String
        public var verified: Int
        public var total: Int
        public var joineryVerified: Int
        public var joineryTotal: Int
        /// The floor area given to the engine rests on verified dimensions only (a rectangle whose four
        /// sides were all checked). Never true for an irregular room: its area is from scanned corners.
        public var areaVerified: Bool
        /// The perimeter the engine uses rests on verified wall lengths only.
        public var perimeterVerified: Bool
        /// The ceiling height given to the engine was verified on site.
        public var heightVerified: Bool

        enum CodingKeys: String, CodingKey {
            case name, floor, kind, verified, total
            case joineryVerified = "joinery_verified"
            case joineryTotal = "joinery_total"
            case areaVerified = "area_verified"
            case perimeterVerified = "perimeter_verified"
            case heightVerified = "height_verified"
        }
    }

    public struct UnverifiedItem: Codable, Hashable, Sendable {
        /// The name used in `rooms[].name` (so it matches `x_nexafix_scan.rooms[].name`, `Name (2)` and all).
        /// A room left out of the costing rooms has no such name: its name is followed by " (not costed)".
        public var room: String
        /// The floor the room is on.
        public var floor: String
        /// "Wall A length", "Door 1 width", "Ceiling height", ...
        public var item: String
        /// The LiDAR value the quote is currently based on, metres.
        public var scannedM: Double
        /// Typical LiDAR error for that value, metres (`ScanAccuracy.typicalTolerance`).
        public var typicalToleranceM: Double

        enum CodingKeys: String, CodingKey {
            case room, floor, item
            case scannedM = "scanned_m"
            case typicalToleranceM = "typical_tolerance_m"
        }
    }
}

// MARK: - Building

public enum CostingSpecExport {

    /// Rooms smaller than this are not worth costing (and would divide by zero in the engine's
    /// perimeter estimate): they are left out and mentioned in `notes`.
    private static let minimumArea = 0.01

    /// Build the costing spec. Pure and deterministic: the same property always gives the same spec.
    public static func make(property: Property) -> CostingSpec {
        var notes: [String] = []
        var rooms: [CostingSpec.RoomEntry] = []
        var infos: [CostingSpec.RoomInfo] = []
        var unverified: [CostingSpec.UnverifiedItem] = []
        var totals = DataMeasureList.Counts()
        var heights: [Double] = []
        var latestScan: Date?
        var usedSlugs: Set<String> = []
        var wallAreas: [(name: String, scanFile: Double, engine: Double)] = []

        for floor in property.floors {
            for room in floor.rooms {
                let items = DataMeasureList.items(for: room)
                let counts = DataMeasureList.counts(of: items)
                totals = totals + counts
                if latestScan.map({ room.scannedAt > $0 }) ?? true { latestScan = room.scannedAt }

                let displayName = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseName = displayName.isEmpty ? room.kind.displayName : displayName

                let metrics = room.metrics
                let area = metrics.effectiveFloorArea
                let costable = room.walls.count >= 3 && area.isFinite && area >= minimumArea

                // Unique names, because the engine selects rooms by name. It compares names by `slug`, so
                // "Living / Kitchen" and "Living Kitchen" (and any two names without Latin letters) are
                // the same room to it. The unverified list uses this same name, so a reader can tell two
                // rooms called "Bedroom" apart.
                var name = baseName
                if costable {
                    var n = 1
                    while usedSlugs.contains(engineSlug(name)) {
                        n += 1
                        name = "\(baseName) (\(n))"
                    }
                    usedSlugs.insert(engineSlug(name))
                    if n > 1 {
                        notes.append("Room name \"\(baseName)\" is used more than once (the engine compares names ignoring case and punctuation); renamed to \"\(name)\" in the costing rooms.")
                    }
                } else {
                    name = baseName + " (not costed)"
                }

                // Joinery-critical dimensions that were not laser-checked are reported for every
                // room, including rooms that cannot be costed.
                for item in items where item.isJoinery && !item.measured.isVerified {
                    unverified.append(CostingSpec.UnverifiedItem(
                        room: name, floor: floor.name, item: item.label,
                        scannedM: DataNumber.round4(item.measured.scanned),
                        typicalToleranceM: DataNumber.round4(ScanAccuracy.typicalTolerance(forLength: item.measured.scanned))))
                }

                guard costable else {
                    notes.append("\(baseName) (\(floor.name)): left out of the costing rooms (no usable floor outline).")
                    continue
                }

                let built = makeRoom(room, name: name, metrics: metrics)
                notes.append(contentsOf: built.notes)
                if let guess = CostingEngineGuess.reclassification(
                    name: name, kind: room.kind, fileTags: built.entry.tags, wet: built.entry.wet) {
                    notes.append(guess)
                }
                wallAreas.append((name, DataNumber.round4(metrics.netWallArea), DataNumber.round4(built.engineWallArea)))
                rooms.append(built.entry)
                heights.append(metrics.ceilingHeight)
                infos.append(CostingSpec.RoomInfo(
                    name: name, floor: floor.name, kind: room.kind.rawValue,
                    verified: counts.verified, total: counts.total,
                    joineryVerified: counts.joineryVerified, joineryTotal: counts.joineryTotal,
                    areaVerified: built.areaVerified, perimeterVerified: built.perimeterVerified,
                    heightVerified: room.ceilingHeight.isVerified))
            }
        }

        if let note = wallAreaNote(wallAreas) { notes.append(note) }
        if property.roomCount == 0 { notes.append("The property has no rooms.") }

        var warning: String?
        if !unverified.isEmpty {
            warning = "\(unverified.count) of \(totals.joineryTotal) joinery-critical dimensions are LiDAR-scanned only "
                + "and have not been verified on site. " + ScanAccuracy.joineryDisclaimer
                + " Treat this as a budget estimate until they are verified."
        }

        return CostingSpec(
            project: CostingSpec.Project(
                client: property.client, name: property.name, location: property.address,
                ref: property.reference, ceilingHeight: commonCeilingHeight(heights)),
            rooms: rooms,
            scope: [],
            scanInfo: CostingSpec.ScanInfo(
                schema: CostingSpec.scanSchemaName, version: CostingSpec.scanSchemaVersion,
                generator: ScanFile.generatorName, propertyId: property.id.uuidString,
                scanDate: latestScan.map { ExportNaming.dateStamp($0) },
                verifiedCount: totals.verified, measurementCount: totals.total,
                joineryVerifiedCount: totals.joineryVerified, joineryMeasurementCount: totals.joineryTotal,
                rooms: infos, unverifiedJoinery: unverified, warning: warning, notes: notes))
    }

    /// The costing spec as pretty-printed UTF-8 JSON with sorted keys and a trailing newline.
    public static func json(property: Property) throws -> Data {
        try encode(make(property: property))
    }

    public static func encode(_ spec: CostingSpec) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(spec)
        data.append(0x0A)
        return data
    }

    // MARK: Rooms

    private struct BuiltRoom {
        var entry: CostingSpec.RoomEntry
        var notes: [String]
        var areaVerified: Bool
        var perimeterVerified: Bool
        /// What the engine will compute for the net wall area: perimeter x height - door and window areas.
        var engineWallArea: Double
    }

    private static func makeRoom(_ room: Room, name: String, metrics m: RoomMetrics) -> BuiltRoom {
        var notes: [String] = []
        let hasVirtualWalls = room.walls.contains { $0.kind == .virtual }
        let derived = DataDerived(room: room, metrics: m)

        // Solid walls only: an open-plan edge has nothing to paint or skirt.
        var perimeter = m.wallPerimeter
        var perimeterVerified = derived.wallPerimeterVerified
        if perimeter <= 0 && m.perimeter > 0 {
            perimeter = m.perimeter
            perimeterVerified = derived.perimeterVerified
            notes.append("\(name): has no solid walls; the full outline perimeter was used.")
        }

        var entry = CostingSpec.RoomEntry(
            name: name, length: nil, width: nil, area: nil, perimeter: nil,
            height: .make(m.ceilingHeight, millimetreThreshold: 20),
            doors: [], windows: [], tags: room.kind.costingTags,
            wet: room.kind == .other ? nil : room.kind.isWet)

        var areaVerified = false
        if m.isRectangular, let l = m.length, let w = m.width, l > 0, w > 0 {
            entry.length = .make(l, millimetreThreshold: 60)
            entry.width = .make(w, millimetreThreshold: 60)
            areaVerified = derived.effectiveAreaVerified
            if hasVirtualWalls {
                entry.perimeter = .make(perimeter, millimetreThreshold: 150)
            } else {
                // No `perimeter` key: the engine computes 2 x (length + width), which rests on the same walls.
                perimeterVerified = derived.effectiveAreaVerified
            }
        } else {
            entry.area = DataNumber.round4(m.effectiveFloorArea)
            entry.perimeter = .make(perimeter, millimetreThreshold: 150)
        }

        // Openings count only on solid walls, exactly like the wall-area maths in RoomMetrics.
        let solid = Set(room.walls.filter { $0.kind == .solid }.map(\.id))
        var dropped = 0
        var openingArea = 0.0
        for ref in DataOpenings.ordered(in: room) {
            let o = ref.opening
            let w = o.width.value, h = o.height.value
            guard let wallID = o.wallID, solid.contains(wallID),
                  w.isFinite, h.isFinite, w > 0, h > 0, w <= 20, h <= 20 else {
                dropped += 1
                continue
            }
            let size = [DataNumber.round4(w), DataNumber.round4(h)]
            openingArea += size[0] * size[1]
            if o.kind == .window { entry.windows.append(size) } else { entry.doors.append(size) }
        }
        if dropped > 0 {
            notes.append("\(name): \(dropped) opening(s) not on a solid wall (or with an unusable size) were left out of doors and windows.")
        }
        if room.openings.contains(where: { $0.kind == .opening }) {
            notes.append("\(name): doorless openings are listed as doors (they remove wall and skirting like a door).")
        }
        let engineWallArea = max(0, perimeter * m.ceilingHeight - openingArea)
        return BuiltRoom(entry: entry, notes: notes, areaVerified: areaVerified,
                         perimeterVerified: perimeterVerified, engineWallArea: engineWallArea)
    }

    /// One note when the wall area the costing engine will compute differs from the scan file's. The scan
    /// file multiplies each wall by its own height; the engine multiplies the whole perimeter by the room's
    /// ceiling height. They part ways whenever the ceiling was verified and the wall heights were not (or
    /// the walls differ in height), and the quote uses the engine's figure.
    private static func wallAreaNote(_ rows: [(name: String, scanFile: Double, engine: Double)]) -> String? {
        let differing = rows.filter { abs($0.scanFile - $0.engine) > max(0.05, 0.005 * $0.scanFile) }
        guard let worst = differing.max(by: { abs($0.scanFile - $0.engine) < abs($1.scanFile - $1.engine) }) else { return nil }
        return "Wall area differs between the scan file and the costing engine in \(differing.count) room(s): the scan file "
            + "multiplies each wall by its own height, the engine multiplies the perimeter by the room's ceiling height and "
            + "subtracts the doors and windows. The quote uses the engine's figure. Largest difference: \(worst.name), "
            + "\(DataNumber.fixed(worst.scanFile, decimals: 2)) m2 in the scan file, \(DataNumber.fixed(worst.engine, decimals: 2)) m2 in the costing engine."
    }

    /// Mirror of `slug()` in nexa_costing/util.py: lower-case, every run of characters other than
    /// a-z and 0-9 becomes one `_`, no `_` at either end.
    static func engineSlug(_ text: String) -> String {
        var out = ""
        var pending = false
        for scalar in text.lowercased().unicodeScalars {
            let v = scalar.value
            if (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A) {
                if pending && !out.isEmpty { out.append("_") }
                pending = false
                out.unicodeScalars.append(scalar)
            } else {
                pending = true
            }
        }
        return out
    }

    /// The most frequent ceiling height to 1 cm; on a tie the taller one (it prices more material).
    private static func commonCeilingHeight(_ heights: [Double]) -> Double? {
        let valid = heights.filter { $0.isFinite && $0 > 0 && $0 < 100_000 }     // keeps the centimetre key inside Int
        guard !valid.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for h in valid { counts[Int((h * 100).rounded()), default: 0] += 1 }
        guard let best = counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : a.key < b.key
        }) else { return nil }
        return Double(best.key) / 100
    }
}

// MARK: - What the engine will do to the tags

/// Mirror of the name guessing in the engine (`_guess_tags()` and the `wet` default in `build_room()`, in
/// skills/nexa-costing/scripts/nexa_costing/spec.py). The engine unions the tags in the file with tags it
/// guesses from the room NAME, and takes `wet` from the tags when the file has no `wet`. The file cannot
/// remove a guessed tag, so a room called "Corridor to Balcony" is `outdoor` to the engine whatever kind it
/// has. `tests/test_from_scan.py` checks the same table against the Python function; `from_scan.py` asks
/// the engine itself, so it stays right when this mirror drifts.
enum CostingEngineGuess {

    /// (substring of the lower-cased name, tag), in the engine's order.
    static let keywords: [(String, String)] = [
        ("bed", "bedroom"), ("living", "living"), ("majlis", "living"), ("dining", "living"),
        ("kitchen", "kitchen"), ("bath", "bathroom"), ("toilet", "bathroom"), ("wc", "bathroom"),
        ("powder", "bathroom"), ("ensuite", "bathroom"), ("laundry", "utility"), ("maid", "utility"),
        ("store", "utility"), ("corridor", "circulation"), ("hall", "circulation"), ("entr", "circulation"),
        ("foyer", "circulation"), ("lobby", "circulation"), ("balcony", "outdoor"), ("terrace", "outdoor"),
    ]

    /// Tags the engine guesses from `name`. Substrings are searched by Unicode scalar, like Python's `in`.
    static func tags(forName name: String) -> Set<String> {
        let haystack = Array(name.lowercased().unicodeScalars)
        var tags: Set<String> = []
        for (key, tag) in keywords where contains(haystack, key) { tags.insert(tag) }
        if contains(haystack, "master"), tags.isDisjoint(with: ["bathroom", "outdoor", "utility"]) {
            tags.insert("bedroom")
        }
        if !tags.isDisjoint(with: ["bathroom", "outdoor"]) { tags.remove("bedroom") }
        return tags
    }

    /// The tags and wet flag the engine ends up with for a room entry.
    static func engineView(name: String, fileTags: [String], wet: Bool?) -> (tags: Set<String>, wet: Bool) {
        let tags = Set(fileTags.map { $0.lowercased() }).union(self.tags(forName: name))
        return (tags, wet ?? (tags.contains("bathroom") || tags.contains("wet")))
    }

    /// A sentence when the engine will classify the room differently from the file, otherwise nil.
    static func reclassification(name: String, kind: RoomKind, fileTags: [String], wet: Bool?) -> String? {
        let file = Set(fileTags.map { $0.lowercased() })
        let fileWet = wet ?? (file.contains("bathroom") || file.contains("wet"))
        let engine = engineView(name: name, fileTags: fileTags, wet: wet)
        let added = engine.tags.subtracting(file).sorted()
        guard !added.isEmpty || engine.wet != fileWet else { return nil }

        var effects: [String] = []
        if added.contains("outdoor") { effects.append("the \"all\" and \"dry\" room selectors leave it out") }
        if engine.wet && !fileWet { effects.append("it counts as a wet area, so the \"dry\" room selector leaves it out") }
        if effects.isEmpty { effects.append("selectors that use \(added.count == 1 ? "that tag" : "those tags") include it") }
        let tagText = added.isEmpty ? "as wet" : added.map { "\"\($0)\"" }.joined(separator: ", ")
        return "\(name): the costing engine also tags this \(kind.displayName.lowercased()) \(tagText) because of its name, so "
            + effects.joined(separator: " and ") + ". Rename the room if that is wrong."
    }

    private static func contains(_ haystack: [Unicode.Scalar], _ needle: String) -> Bool {
        let n = Array(needle.unicodeScalars)
        guard let first = n.first, haystack.count >= n.count else { return false }
        for i in 0...(haystack.count - n.count) where haystack[i] == first {
            if Array(haystack[i..<(i + n.count)]) == n { return true }
        }
        return false
    }
}
