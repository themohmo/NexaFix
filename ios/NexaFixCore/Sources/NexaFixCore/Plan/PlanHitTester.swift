import Foundation

// What is under a finger on the floor plan, and how to name and outline it. Pure maths on the saved rooms, so
// the priorities (a corner beats a door beats a wall beats a piece of furniture beats the room itself) and the
// tie-breaks are unit-tested off-device.

/// Something on the plan a person can tap.
public enum PlanSelection: Hashable, Sendable {
    case room(UUID)
    case wall(room: UUID, wall: UUID)
    /// Corner `index` is the start of wall `index` (see `Room.outline`).
    case corner(room: UUID, index: Int)
    case opening(room: UUID, opening: UUID)
    case object(room: UUID, object: UUID)

    /// The room the selection belongs to.
    public var roomID: UUID {
        switch self {
        case .room(let id): return id
        case .wall(let room, _), .corner(let room, _), .opening(let room, _), .object(let room, _): return room
        }
    }
}

/// The outline to draw around a selection.
public struct PlanHighlight: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A closed shape: the last point joins the first.
        case polygon
        /// An open line through the points.
        case polyline
        /// A single spot (a corner).
        case point
    }

    public var kind: Kind
    /// Plan space, metres.
    public var points: [Point2]

    public init(kind: Kind, points: [Point2]) {
        self.kind = kind
        self.points = points
    }
}

/// How a selection is worded on a card and by VoiceOver.
public struct PlanSelectionSummary: Hashable, Sendable {
    /// What it is: "Wall A", "Door 1", "Corner B", "Sofa 1", or the room's name.
    public var title: String
    /// Where it is: the room's name; nil when the selection is the room itself.
    public var subtitle: String?
    /// The headline number on screen, already in the user's units: "3245 mm", "90.0\u{00B0}", "27.9 m\u{00B2}".
    public var detail: String
    /// A sentence for VoiceOver: units spelled out, provenance stated.
    public var spoken: String
}

/// Finds what a tap on the plan hit.
public struct PlanHitTester: Sendable {
    public let rooms: [Room]

    private struct Prepared: Sendable {
        let room: Room
        let order: Int
        let outline: [Point2]
        let area: Double
        /// Corner indexes that are real corners (not a straight continuation of the wall).
        let realCorners: [Int]
    }

    private let prepared: [Prepared]

    public init(rooms: [Room]) {
        self.rooms = rooms
        var list: [Prepared] = []
        for (order, room) in rooms.enumerated() {
            guard room.walls.count >= 3 else { continue }
            let finite = room.walls.allSatisfy {
                $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite
            }
            guard finite else { continue }
            let outline = room.outline
            let counterClockwise = Polygon.isCounterClockwise(outline)
            var real: [Int] = []
            for i in outline.indices {
                var angle = Polygon.interiorAngle(outline, at: i)
                if !counterClockwise { angle = 360 - angle }
                if angle.isFinite, abs(angle - 180) > RoomMetrics.straightTolerance { real.append(i) }
            }
            list.append(Prepared(room: room, order: order, outline: outline, area: Polygon.area(outline),
                                 realCorners: real))
        }
        self.prepared = list
    }

    // MARK: Hit testing

    /// What `planPoint` hits, within `toleranceMetres` (the caller converts its 22 point fingertip with the
    /// viewport: `viewport.metres(forPoints: 22)`).
    ///
    /// Priority: a corner, then a door, window or opening, then a wall, then a piece of furniture, then the
    /// inside of a room. Within one priority the nearest wins; an exact tie goes to the earlier room, then the
    /// earlier wall, opening or object in the room's own order, so the answer never depends on hashing or
    /// sort stability. Returns nil for empty space and for a point or tolerance that is not a number.
    public func hit(at planPoint: Point2, toleranceMetres: Double) -> PlanSelection? {
        guard planPoint.x.isFinite, planPoint.y.isFinite else { return nil }
        let tolerance = toleranceMetres.isFinite ? Swift.max(toleranceMetres, 0) : 0

        var best: Candidate?
        func offer(_ candidate: Candidate) {
            if let current = best, !candidate.beats(current) { return }
            best = candidate
        }

        for entry in prepared {
            let room = entry.room

            // 1. Corners.
            for i in entry.realCorners {
                let d = planPoint.distance(to: entry.outline[i])
                if d <= tolerance {
                    offer(Candidate(rank: 0, distance: d, room: entry.order, item: i, selection: .corner(room: room.id, index: i)))
                }
            }

            // 2. Doors, windows and openings.
            for (index, opening) in room.openings.enumerated() {
                guard let wallID = opening.wallID, let wall = room.wall(withID: wallID) else { continue }
                let (a, b) = opening.planSegment(on: wall)
                guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
                let d = PlanHitTester.distance(from: planPoint, toSegment: a, b)
                if d <= tolerance {
                    offer(Candidate(rank: 1, distance: d, room: entry.order, item: index,
                                    selection: .opening(room: room.id, opening: opening.id)))
                }
            }

            // 3. Walls.
            for (index, wall) in room.walls.enumerated() {
                let d = PlanHitTester.distance(from: planPoint, toSegment: wall.start, wall.end)
                if d <= tolerance {
                    offer(Candidate(rank: 2, distance: d, room: entry.order, item: index,
                                    selection: .wall(room: room.id, wall: wall.id)))
                }
            }

            // 4. Furniture: inside the footprint, or close to its edge.
            for (index, object) in room.objects.enumerated() {
                let footprint = object.footprint
                guard footprint.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
                let d = Polygon.contains(footprint, planPoint) ? 0 : PlanHitTester.distance(from: planPoint, toPolygon: footprint)
                if d <= tolerance {
                    offer(Candidate(rank: 3, distance: d, room: entry.order, item: index,
                                    selection: .object(room: room.id, object: object.id)))
                }
            }

            // 5. The room itself. Where rooms overlap the smaller one is on top.
            if Polygon.contains(entry.outline, planPoint) {
                offer(Candidate(rank: 4, distance: entry.area, room: entry.order, item: 0, selection: .room(room.id)))
            }
        }
        return best?.selection
    }

    private struct Candidate {
        var rank: Int
        var distance: Double
        var room: Int
        var item: Int
        var selection: PlanSelection

        /// Strictly better than `other`: lower rank, then nearer, then earlier room, then earlier item.
        func beats(_ other: Candidate) -> Bool {
            if rank != other.rank { return rank < other.rank }
            if abs(distance - other.distance) > 1e-9 { return distance < other.distance }
            if room != other.room { return room < other.room }
            return item < other.item
        }
    }

    // MARK: Lookup

    /// Does the selection still point at something that exists?
    public func contains(_ selection: PlanSelection) -> Bool {
        guard let room = room(for: selection) else { return false }
        switch selection {
        case .room: return true
        case .wall(_, let wall): return room.wall(withID: wall) != nil
        case .corner(_, let index): return index >= 0 && index < room.walls.count
        case .opening(_, let opening): return room.openings.contains { $0.id == opening }
        case .object(_, let object): return room.objects.contains { $0.id == object }
        }
    }

    private func room(for selection: PlanSelection) -> Room? {
        rooms.first { $0.id == selection.roomID }
    }

    // MARK: Highlight

    /// The outline of a selection in plan metres: a room or a piece of furniture is a closed polygon, a wall or an
    /// opening a line, a corner a single point. Empty when the selection no longer exists.
    public func highlight(for selection: PlanSelection) -> PlanHighlight? {
        guard contains(selection), let room = room(for: selection) else { return nil }
        switch selection {
        case .room:
            return PlanHighlight(kind: .polygon, points: room.outline)
        case .wall(_, let id):
            guard let wall = room.wall(withID: id) else { return nil }
            return PlanHighlight(kind: .polyline, points: [wall.start, wall.end])
        case .corner(_, let index):
            return PlanHighlight(kind: .point, points: [room.outline[index]])
        case .opening(_, let id):
            guard let opening = room.openings.first(where: { $0.id == id }),
                  let wallID = opening.wallID, let wall = room.wall(withID: wallID) else { return nil }
            let (a, b) = opening.planSegment(on: wall)
            return PlanHighlight(kind: .polyline, points: [a, b])
        case .object(_, let id):
            guard let object = room.objects.first(where: { $0.id == id }) else { return nil }
            return PlanHighlight(kind: .polygon, points: object.footprint)
        }
    }

    /// The points of `highlight(for:)`, or an empty list.
    public func highlightGeometry(for selection: PlanSelection) -> [Point2] {
        highlight(for: selection)?.points ?? []
    }

    // MARK: Words

    /// What the selection is called: "Wall A", "Door 1", "Corner B", "Sofa 1", or the room's name.
    /// Numbering matches the 3D viewer and the verification lists. Nil when the selection no longer exists.
    public func selectionTitle(for selection: PlanSelection) -> String? {
        guard contains(selection), let room = room(for: selection) else { return nil }
        switch selection {
        case .room:
            return PlanHitTester.name(of: room)
        case .wall(_, let id):
            return room.wallTitle(forID: id)
        case .corner(_, let index):
            return "Corner " + Room.wallLetters(forIndex: index)
        case .opening(_, let id):
            return room.measureOpeningTitles()[id] ?? "Opening"
        case .object(_, let id):
            return PlanHitTester.objectTitles(in: room)[id] ?? "Object"
        }
    }

    /// The title, the room it is in, the headline number and a sentence for VoiceOver. Nil when the selection
    /// no longer exists.
    public func summary(for selection: PlanSelection, units: DisplayUnits) -> PlanSelectionSummary? {
        guard let title = selectionTitle(for: selection), let room = room(for: selection) else { return nil }
        let roomName = PlanHitTester.name(of: room)
        func length(_ metres: Double) -> String { UnitFormatter.length(metres, unit: units.length) }
        func spokenLength(_ metres: Double) -> String {
            OverlaySpokenText.expand(length(metres), isOpening: false)
        }

        switch selection {
        case .room:
            let metrics = room.metrics
            let area = UnitFormatter.area(metrics.effectiveFloorArea, unit: units.area)
            var spoken = "\(roomName), floor area " + OverlaySpokenText.expand(area, isOpening: false)
            if metrics.isRectangular, let l = metrics.length, let w = metrics.width {
                spoken += ", " + spokenLength(l) + " by " + spokenLength(w)
            }
            return PlanSelectionSummary(title: title, subtitle: nil, detail: area, spoken: spoken)

        case .wall(_, let id):
            guard let wall = room.wall(withID: id) else { return nil }
            let text = length(wall.length.value)
            let kind = wall.kind == .virtual ? "open boundary, " : ""
            return PlanSelectionSummary(
                title: title, subtitle: roomName, detail: text,
                spoken: "\(title), \(roomName), \(kind)length " + spokenLength(wall.length.value) + ", "
                    + PlanHitTester.spokenProvenance(wall.length))

        case .corner(_, let index):
            guard let corner = room.metrics.corners.first(where: { $0.index == index }) else { return nil }
            let angle = UnitFormatter.angle(corner.interiorAngle)
            var spoken = "\(title), \(roomName), " + OverlaySpokenText.expand(angle, isOpening: false)
            switch OverlayBuilder.angleState(forInteriorAngle: corner.interiorAngle) {
            case .caution: spoken += ", slightly out of square"
            case .critical: spoken += ", out of square"
            default: break
            }
            return PlanSelectionSummary(title: title, subtitle: roomName, detail: angle, spoken: spoken)

        case .opening(_, let id):
            guard let opening = room.openings.first(where: { $0.id == id }) else { return nil }
            let width = length(opening.width.value), height = length(opening.height.value)
            let verified = opening.width.isVerified && opening.height.isVerified
            return PlanSelectionSummary(
                title: title, subtitle: roomName, detail: "\(width) \u{00D7} \(height)",
                spoken: "\(title), \(roomName), width " + spokenLength(opening.width.value) + ", height "
                    + spokenLength(opening.height.value) + ", " + (verified ? "checked" : "scanned, not checked"))

        case .object(_, let id):
            guard let object = room.objects.first(where: { $0.id == id }) else { return nil }
            let size = "\(length(object.width)) \u{00D7} \(length(object.depth))"
            return PlanSelectionSummary(
                title: title, subtitle: roomName, detail: size,
                spoken: "\(title), \(roomName), " + spokenLength(object.width) + " by " + spokenLength(object.depth)
                    + ", " + spokenLength(object.height) + " high, scanned")
        }
    }

    // MARK: Helpers

    /// "Sofa 1", "Sofa 2", "Table 1" ...: numbered per kind in the room's own order.
    static func objectTitles(in room: Room) -> [UUID: String] {
        var counters: [ObjectKind: Int] = [:]
        var titles: [UUID: String] = [:]
        for object in room.objects {
            let n = (counters[object.kind] ?? 0) + 1
            counters[object.kind] = n
            if titles[object.id] == nil { titles[object.id] = "\(object.kind.displayName) \(n)" }
        }
        return titles
    }

    static func name(of room: Room) -> String {
        let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? room.kind.displayName : trimmed
    }

    static func spokenProvenance(_ value: Measured) -> String {
        guard let v = value.verification else { return "scanned, not checked" }
        switch v.source {
        case .laser: return "verified with laser"
        case .tape: return "verified with tape"
        case .drawing: return "verified from drawing"
        }
    }

    /// Distance from `p` to the segment `a`-`b`.
    static func distance(from p: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let ab = b - a
        let lengthSquared = ab.dot(ab)
        guard lengthSquared > 1e-18, lengthSquared.isFinite else { return p.distance(to: a) }
        let t = Swift.min(Swift.max((p - a).dot(ab) / lengthSquared, 0), 1)
        return p.distance(to: a + ab * t)
    }

    /// Distance from `p` to the nearest edge of a closed polygon.
    static func distance(from p: Point2, toPolygon polygon: [Point2]) -> Double {
        var best = Double.infinity
        for i in polygon.indices {
            best = Swift.min(best, distance(from: p, toSegment: polygon[i], polygon[(i + 1) % polygon.count]))
        }
        return best
    }
}
