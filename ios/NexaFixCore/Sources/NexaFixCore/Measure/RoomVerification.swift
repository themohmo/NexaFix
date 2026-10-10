import Foundation

// Laser verification of a room's dimensions.
//
// Verification is provenance, not geometry: setting a `Verification` NEVER moves a wall,
// opening or custom point. Outlines, 3D solids, snap points and corner angles keep using the
// scanned geometry. Everything that reports a dimension (metrics, exports, costing) reads the
// effective value, `Measured.value`, which is the verified number when there is one.

public extension Room {

    // MARK: Lookup

    /// Every target that exists in this room, in a stable order: each wall's length then
    /// height in loop order, the ceiling, each opening's width, height and sill in numbering
    /// order (wall index, then offset), then custom measurements in creation order.
    func measureTargets() -> [MeasureTarget] {
        var out: [MeasureTarget] = []
        out.reserveCapacity(walls.count * 2 + openings.count * 3 + customMeasurements.count + 1)
        for wall in walls {
            out.append(.wallLength(wall.id))
            out.append(.wallHeight(wall.id))
        }
        out.append(.ceilingHeight)
        for index in measureOpeningOrder() {
            let id = openings[index].id
            out.append(.openingWidth(id))
            out.append(.openingHeight(id))
            out.append(.openingSill(id))
        }
        for custom in customMeasurements { out.append(.customLength(custom.id)) }
        return out
    }

    /// The measured value a target points at, or nil when the wall, opening or custom
    /// measurement is not (or no longer) in this room.
    func measured(_ t: MeasureTarget) -> Measured? {
        switch t {
        case .wallLength(let id): return walls.first { $0.id == id }?.length
        case .wallHeight(let id): return walls.first { $0.id == id }?.height
        case .openingWidth(let id): return openings.first { $0.id == id }?.width
        case .openingHeight(let id): return openings.first { $0.id == id }?.height
        case .openingSill(let id): return openings.first { $0.id == id }?.sillHeight
        case .ceilingHeight: return ceilingHeight
        case .customLength(let id): return customMeasurements.first { $0.id == id }?.length
        }
    }

    /// Record (or, with nil, clear) a site check for a target.
    ///
    /// Returns false, and changes nothing, when the target does not exist or the value is not
    /// usable: not finite, negative, zero for anything but an opening sill, or outside the range a
    /// person can measure (`UnitParser.isPlausibleLength`: from 0.1 mm to 200 m). The range is
    /// enforced here, not only in the sheet that usually calls this, so a value from any other
    /// route (an import, future code) cannot be stored as "verified" and preferred over the scan.
    /// Geometry is never modified; only the target's `Measured.verification` changes.
    @discardableResult
    mutating func setVerification(_ v: Verification?, for t: MeasureTarget) -> Bool {
        if let v {
            guard UnitParser.isPlausibleLength(v.value, allowZero: t.allowsZeroValue) else { return false }
        }
        switch t {
        case .wallLength(let id):
            guard let i = walls.firstIndex(where: { $0.id == id }) else { return false }
            walls[i].length.verification = v
        case .wallHeight(let id):
            guard let i = walls.firstIndex(where: { $0.id == id }) else { return false }
            walls[i].height.verification = v
        case .openingWidth(let id):
            guard let i = openings.firstIndex(where: { $0.id == id }) else { return false }
            openings[i].width.verification = v
        case .openingHeight(let id):
            guard let i = openings.firstIndex(where: { $0.id == id }) else { return false }
            openings[i].height.verification = v
        case .openingSill(let id):
            guard let i = openings.firstIndex(where: { $0.id == id }) else { return false }
            openings[i].sillHeight.verification = v
        case .ceilingHeight:
            ceilingHeight.verification = v
        case .customLength(let id):
            guard let i = customMeasurements.firstIndex(where: { $0.id == id }) else { return false }
            customMeasurements[i].length.verification = v
        }
        return true
    }

    // MARK: Labels

    /// "A" for index 0 ... "Z" for 25, then "AA", "AB" ... Negative indexes give "?".
    static func wallLetters(forIndex index: Int) -> String {
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

    /// "Wall A" for the wall at loop index 0, "Wall B" for 1, and so on.
    func wallTitle(at index: Int) -> String { "Wall " + Room.wallLetters(forIndex: index) }

    /// "Wall A" for a wall id, or nil when the id is not a wall of this room.
    func wallTitle(forID id: UUID) -> String? {
        walls.firstIndex { $0.id == id }.map { wallTitle(at: $0) }
    }

    /// The short human name of the thing a target measures:
    /// "Wall A", "Door 1", "Window 2", "Ceiling height", or a custom measurement's label.
    ///
    /// Openings are numbered per kind in order of wall (loop index) and then offset along the wall;
    /// openings that are not on a wall of this room come last. A target that does not exist gives
    /// "Unknown measurement". Pair with `detail(for:)` for the quantity ("Length", "Width").
    func title(for t: MeasureTarget) -> String {
        switch t {
        case .wallLength(let id), .wallHeight(let id):
            return wallTitle(forID: id) ?? "Unknown measurement"
        case .openingWidth(let id), .openingHeight(let id), .openingSill(let id):
            return measureOpeningTitles()[id] ?? "Unknown measurement"
        case .ceilingHeight:
            return "Ceiling height"
        case .customLength(let id):
            guard let custom = customMeasurements.first(where: { $0.id == id }) else {
                return "Unknown measurement"
            }
            let label = custom.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "Custom measurement" : label
        }
    }

    /// Which quantity of the titled thing a target is, for a subtitle: "Length", "Height",
    /// "Width \u{00B7} Wall B" or "Sill height \u{00B7} Wall B" (quantity, a middle dot U+00B7 with a
    /// space either side, then the wall the opening is on; just the quantity when the opening has no
    /// wall), "Length \u{00B7} open boundary" for an open-plan boundary. nil for the ceiling (its title
    /// says it) and for a custom measurement without a note (a note is returned when present).
    /// Also nil when the target does not exist. The middle dot is not ASCII: a consumer that writes
    /// to DXF or CSV should use `fullTitle(for:)` instead.
    func detail(for t: MeasureTarget) -> String? {
        switch t {
        case .wallLength(let id):
            guard let wall = walls.first(where: { $0.id == id }) else { return nil }
            return wall.kind == .virtual ? "Length \u{00B7} open boundary" : "Length"
        case .wallHeight(let id):
            return walls.contains { $0.id == id } ? "Height" : nil
        case .openingWidth(let id):
            return openingDetail("Width", id)
        case .openingHeight(let id):
            return openingDetail("Height", id)
        case .openingSill(let id):
            return openingDetail("Sill height", id)
        case .ceilingHeight:
            return nil
        case .customLength(let id):
            guard let custom = customMeasurements.first(where: { $0.id == id }) else { return nil }
            let note = (custom.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : note
        }
    }

    /// Title and quantity together, for places with no room for a subtitle:
    /// "Wall A length", "Door 1 width", "Window 2 sill height", "Ceiling height".
    func fullTitle(for t: MeasureTarget) -> String {
        let base = title(for: t)
        switch t {
        case .wallLength: return base + " length"
        case .wallHeight: return base + " height"
        case .openingWidth: return base + " width"
        case .openingHeight: return base + " height"
        case .openingSill: return base + " sill height"
        case .ceilingHeight, .customLength: return base
        }
    }

    // MARK: Opening numbering (module-internal; shared with snap points)

    /// Indexes into `openings` ordered by the loop index of their wall, then offset along the
    /// wall, then array position. Openings without a matching wall sort last.
    internal func measureOpeningOrder() -> [Int] {
        var wallIndex: [UUID: Int] = [:]
        for (i, wall) in walls.enumerated() where wallIndex[wall.id] == nil { wallIndex[wall.id] = i }
        func key(_ i: Int) -> (Int, Double) {
            let o = openings[i]
            let w = o.wallID.flatMap { wallIndex[$0] } ?? Int.max
            let off = o.offsetFromWallStart.isFinite ? o.offsetFromWallStart : Double.greatestFiniteMagnitude
            return (w, off)
        }
        return openings.indices.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return a < b
        }
    }

    /// "Door 1", "Door 2", "Window 1" ... keyed by opening id (first occurrence wins on duplicate ids).
    internal func measureOpeningTitles() -> [UUID: String] {
        var counters: [OpeningKind: Int] = [:]
        var titles: [UUID: String] = [:]
        for i in measureOpeningOrder() {
            let o = openings[i]
            let n = (counters[o.kind] ?? 0) + 1
            counters[o.kind] = n
            if titles[o.id] == nil { titles[o.id] = "\(o.kind.displayName) \(n)" }
        }
        return titles
    }

    private func openingDetail(_ quantity: String, _ id: UUID) -> String? {
        guard let opening = openings.first(where: { $0.id == id }) else { return nil }
        if let wallID = opening.wallID, let wall = wallTitle(forID: wallID) {
            return quantity + " \u{00B7} " + wall
        }
        return quantity
    }
}
