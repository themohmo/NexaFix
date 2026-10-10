import Foundation

// Plan symbols: door swings, sliding doors, windows, doorless openings, the right-angle mark and
// dimension ticks, plus the bookkeeping that draws a door two rooms share only once.

extension PlanDrawingBuilder {

    // MARK: Openings

    /// Door leaf and swing, sliding panels, window glazing lines and doorless-opening threshold
    /// lines. The gaps themselves are cut by `addWalls`. Openings on open boundaries (virtual walls)
    /// have no wall to sit in and are not drawn. An opening that another room recorded in the same
    /// wall and that this plan draws from there (see `OpeningLinks`) is skipped here.
    static func addOpenings(_ g: RoomGeometry, _ context: inout Context) {
        let ink = Palette.ink
        let t = wallThickness
        for w in g.walls where w.isUsable && w.wall.kind == .solid {
            for span in spans(on: w, in: g.room) {
                if context.links.suppressedSymbols.contains(OpeningRef(room: g.index, opening: span.opening.id)) { continue }
                switch span.opening.kind {
                case .door:
                    if span.width > slidingDoorWidth + 1e-6 {
                        // A door this wide is a sliding door: two panels that overlap in the middle.
                        addSlidingPanels(on: w, span: span, &context)
                    } else if span.width > doubleDoorWidth + 1e-6 {
                        // A door wider than 1.3 m is a pair of leaves, each half the width, hinged at both
                        // edges, each opened 90 degrees into the room with the quarter-circle it sweeps.
                        let half = span.width / 2
                        addDoorLeaf(hinge: w.point(at: span.s0), closed: w.direction, inward: w.inward,
                                    length: half, &context)
                        addDoorLeaf(hinge: w.point(at: span.s1), closed: -w.direction, inward: w.inward,
                                    length: half, &context)
                    } else {
                        // A leaf opened 90 degrees into the room, hinged at the opening's start edge on the
                        // inner face of the wall.
                        addDoorLeaf(hinge: w.point(at: span.s0), closed: w.direction, inward: w.inward,
                                    length: span.width, &context)
                    }
                case .window:
                    // Three parallel lines across the gap: inner face, middle, outer face.
                    for inset in [0.0, -t / 2, -t] {
                        context.line(.windows, w.point(at: span.s0, inset: inset), w.point(at: span.s1, inset: inset),
                                     weight: Weight.window, color: ink)
                    }
                case .opening:
                    // Dashed threshold lines on both faces of the gap.
                    for inset in [0.0, -t] {
                        context.line(.openings, w.point(at: span.s0, inset: inset), w.point(at: span.s1, inset: inset),
                                     weight: Weight.opening, color: Palette.muted, dashed: true)
                    }
                }
            }
        }
    }

    /// Doors wider than this (metres) are drawn as two leaves.
    static let doubleDoorWidth = 1.3

    /// Doors wider than this (metres) are drawn as a sliding door: the model cannot tell a slider
    /// from a swing door, and a leaf this wide (a balcony door, a patio door) is a slider in practice.
    static let slidingDoorWidth = 2.0

    /// One open door leaf: the line from `hinge` straight into the room and the quarter circle it
    /// sweeps from its closed position (`closed`, a unit vector along the wall) to the open one.
    static func addDoorLeaf(hinge: Point2, closed: Point2, inward: Point2, length: Double, _ context: inout Context) {
        context.line(.doors, hinge, hinge + inward * length, weight: Weight.doorLeaf, color: Palette.ink)
        let closedAngle = atan2(closed.y, closed.x) * 180 / Double.pi
        let openAngle = atan2(inward.y, inward.x) * 180 / Double.pi
        // Arcs run counter-clockwise: from the closed leaf to the open one when the open leaf is a quarter
        // turn anticlockwise of it, otherwise the other way round.
        let (from, to) = closed.cross(inward) > 0 ? (closedAngle, openAngle) : (openAngle, closedAngle)
        let swing = DrawingPrimitive.arc(center: hinge, radius: length,
                                         startAngle: normalizedDegrees(from), endAngle: normalizedDegrees(to),
                                         StrokeStyle(weight: Weight.doorArc, color: Palette.muted))
        context.add(.doors, swing)
        // Room labels keep out of the swept quarter circle.
        if let box = Bounds2(points: extentPoints(of: swing) + [hinge]) { context.obstacles.insert(box) }
    }

    /// Two thin panels in two tracks inside the wall thickness, the first from the start edge to
    /// just past the middle, the second from just before the middle to the far edge.
    static func addSlidingPanels(on w: WallGeometry, span: OpeningSpan, _ context: inout Context) {
        let t = wallThickness
        let panelThickness = 0.03
        let reach = 0.55 * span.width
        let tracks: [(from: Double, to: Double, inset: Double)] = [
            (span.s0, span.s0 + reach, -0.3 * t),
            (span.s1 - reach, span.s1, -0.7 * t),
        ]
        for track in tracks {
            let inner = track.inset + panelThickness / 2
            let outer = track.inset - panelThickness / 2
            context.add(.doors, .polyline([w.point(at: track.from, inset: inner), w.point(at: track.to, inset: inner),
                                           w.point(at: track.to, inset: outer), w.point(at: track.from, inset: outer)],
                                          closed: true,
                                          stroke: StrokeStyle(weight: Weight.doorLeaf, color: Palette.ink),
                                          fill: nil))
        }
    }

    // MARK: Corner mark

    /// The small square that stands for a right angle: two short lines meeting at 90 degrees,
    /// `size` metres along each wall from the corner.
    static func addRightAngleMark(corner: Point2, towardsNext next: Point2, towardsPrevious previous: Point2,
                                  size: Double, _ context: inout Context) {
        context.add(.angles, rightAngleMark(corner: corner, towardsNext: next, towardsPrevious: previous, size: size))
    }

    static func rightAngleMark(corner: Point2, towardsNext next: Point2, towardsPrevious previous: Point2,
                               size: Double) -> DrawingPrimitive {
        let a = corner + next * size
        let c = corner + previous * size
        let b = a + previous * size
        return .polyline([a, b, c], closed: false,
                         stroke: StrokeStyle(weight: Weight.squareMark, color: Palette.muted), fill: nil)
    }

    // MARK: Dimension ticks

    /// A short 45-degree architectural tick across a dimension line at `point`.
    static func addTick(at point: Point2, lineDirection: Point2, halfLength: Double, _ context: inout Context) {
        let diagonal = lineDirection.rotated(by: Double.pi / 4)
        context.line(.dimensions, point - diagonal * halfLength, point + diagonal * halfLength,
                     weight: Weight.tick, color: Palette.ink)
    }
}

// MARK: - Openings shared between rooms

/// Identifies an opening within one plan: the room's position among the drawn rooms and the
/// opening's own id.
struct OpeningRef: Hashable {
    let room: Int
    let opening: UUID
}

/// Identifies a wall within one plan: the room's position among the drawn rooms and the wall's index.
struct WallRef: Hashable {
    let room: Int
    let wall: Int
}

/// Rooms are scanned one at a time, so a door between two rooms is usually recorded twice, once in
/// each room's wall, and the two walls are a partition apart. Drawn naively that gives two opposed
/// swings and two size tags for one door, and one room's wall band still fills the doorway the other
/// room cut.
///
/// `OpeningLinks` finds the openings that are the same physical opening (same kind, in facing walls
/// at most `maxPartition` apart, overlapping along the wall, of similar width) and decides:
/// - the swing, panels or glazing lines are drawn by one room only: for a door, the room it opens
///   into by the usual rule (never a corridor or entrance, else the smaller room); otherwise the
///   room that comes first;
/// - the size tag is printed from the record with more verified values (so a laser-checked size is
///   never hidden behind an unchecked one), else from the drawing room;
/// - the drawn opening's span is cut out of the wall bands of every facing wall of another room,
///   so the doorway is open through the whole partition.
struct OpeningLinks {
    /// Openings whose symbol is drawn by the partner room, and which cut nothing themselves.
    var suppressedSymbols: Set<OpeningRef> = []
    /// Openings whose size tag is printed from the partner room's record.
    var suppressedTags: Set<OpeningRef> = []
    /// Extra cut-outs, as distances along the wall, in the wall bands of facing walls.
    var foreignGaps: [WallRef: [(Double, Double)]] = [:]
    /// How many pairs of records were recognised as one opening.
    var sharedCount = 0

    /// Two walls this far apart or less (metres) count as the two faces of one partition.
    static let maxPartition = 0.45
    /// Walls may overlap by this much (scan noise) and still face each other.
    static let minPartition = -0.1
    /// Cosine of the largest angle between two walls still treated as parallel (about 20 degrees).
    static let parallel = 0.94

    init() {}

    private struct Entry {
        let ref: OpeningRef
        let kind: OpeningKind
        let s0: Double
        let s1: Double
        let wallStart: Point2
        let direction: Point2
        let inward: Point2
        let a: Point2
        let b: Point2
        let verifiedValues: Int
        var mid: Point2 { (a + b) / 2 }
        var width: Double { s1 - s0 }
        var room: Int { ref.room }
    }

    private struct Cell: Hashable { let x: Int; let y: Int }

    private static func cell(_ p: Point2) -> Cell {
        func i(_ v: Double) -> Int { Int(Swift.max(-1e9, Swift.min(1e9, v.rounded(.down)))) }
        return Cell(x: i(p.x), y: i(p.y))
    }

    init(_ geometries: [PlanDrawingBuilder.RoomGeometry]) {
        guard geometries.count > 1 else { return }

        var entries: [Entry] = []
        for g in geometries {
            for w in g.walls where w.isUsable && w.wall.kind == .solid {
                for span in PlanDrawingBuilder.spans(on: w, in: g.room) {
                    let o = span.opening
                    var values = [o.width, o.height]
                    if o.kind == .window, o.sillHeight.value.isFinite, o.sillHeight.value > 0.005 { values.append(o.sillHeight) }
                    entries.append(Entry(ref: OpeningRef(room: g.index, opening: o.id), kind: o.kind,
                                         s0: span.s0, s1: span.s1, wallStart: w.start, direction: w.direction,
                                         inward: w.inward, a: w.point(at: span.s0), b: w.point(at: span.s1),
                                         verifiedValues: values.filter(\.isVerified).count))
                }
            }
        }
        link(entries, geometries)
    }

    private mutating func link(_ entries: [Entry], _ geometries: [PlanDrawingBuilder.RoomGeometry]) {
        var grid: [Cell: [Int]] = [:]
        for (i, e) in entries.enumerated() { grid[OpeningLinks.cell(e.mid), default: []].append(i) }

        // Candidate pairs: the same opening seen from two rooms.
        var candidates: [(overlap: Double, i: Int, j: Int)] = []
        for (i, e) in entries.enumerated() {
            let c = OpeningLinks.cell(e.mid)
            for dx in -2...2 {
                for dy in -2...2 {
                    for j in grid[Cell(x: c.x + dx, y: c.y + dy)] ?? [] where j > i {
                        let f = entries[j]
                        guard f.room != e.room, f.kind == e.kind,
                              let overlap = OpeningLinks.sharedOverlap(e, f) else { continue }
                        candidates.append((overlap, i, j))
                    }
                }
            }
        }
        candidates.sort { ($1.overlap, $0.i, $0.j) < ($0.overlap, $1.i, $1.j) }
        var matched = Set<Int>()
        for pair in candidates where !matched.contains(pair.i) && !matched.contains(pair.j) {
            matched.insert(pair.i)
            matched.insert(pair.j)
            let e = entries[pair.i], f = entries[pair.j]
            let drawer = OpeningLinks.symbolOwner(e, f, geometries) ? e : f
            let other = drawer.ref == e.ref ? f : e
            suppressedSymbols.insert(other.ref)
            let tagOwner = e.verifiedValues == f.verifiedValues ? drawer : (e.verifiedValues > f.verifiedValues ? e : f)
            suppressedTags.insert(tagOwner.ref == e.ref ? f.ref : e.ref)
            sharedCount += 1
        }

        // The drawn openings cut the facing walls of other rooms.
        var wallGrid: [Cell: [WallRef]] = [:]
        for g in geometries {
            for w in g.walls where w.isUsable && w.wall.kind == .solid {
                var seen = Set<Cell>()
                let steps = Int(Swift.min(4000, Swift.max(1, (w.length / 0.5).rounded(.up))))   // clamped as a Double first
                for k in 0...steps {
                    let p = w.start + (w.end - w.start) * (Double(k) / Double(steps))
                    if seen.insert(OpeningLinks.cell(p)).inserted {
                        wallGrid[OpeningLinks.cell(p), default: []].append(WallRef(room: g.index, wall: w.index))
                    }
                }
            }
        }
        for e in entries where !suppressedSymbols.contains(e.ref) {
            let c = OpeningLinks.cell(e.mid)
            var seenWalls = Set<WallRef>()
            for dx in -2...2 {
                for dy in -2...2 {
                    for ref in wallGrid[Cell(x: c.x + dx, y: c.y + dy)] ?? [] where ref.room != e.room {
                        guard seenWalls.insert(ref).inserted else { continue }
                        let f = geometries[ref.room].walls[ref.wall]
                        guard f.inward.dot(e.inward) <= -OpeningLinks.parallel else { continue }
                        // How far e's wall lies beyond f's wall face, measured at the opening.
                        let apart = -(e.mid - f.start).dot(f.inward)
                        guard apart >= OpeningLinks.minPartition, apart <= OpeningLinks.maxPartition else { continue }
                        let t0 = (e.a - f.start).dot(f.direction)
                        let t1 = (e.b - f.start).dot(f.direction)
                        let lo = Swift.max(0, Swift.min(t0, t1))
                        let hi = Swift.min(f.length, Swift.max(t0, t1))
                        if hi - lo > 0.01 { foreignGaps[ref, default: []].append((lo, hi)) }
                    }
                }
            }
        }
    }

    /// How far (metres) the two openings overlap along the wall when they are one opening seen
    /// from both sides; nil when they are not.
    private static func sharedOverlap(_ e: Entry, _ f: Entry) -> Double? {
        guard e.inward.dot(f.inward) <= -parallel else { return nil }
        let u1 = (f.mid - e.mid).dot(-e.inward)
        let u2 = (e.mid - f.mid).dot(-f.inward)
        guard u1 >= minPartition, u1 <= maxPartition, u2 >= minPartition, u2 <= maxPartition else { return nil }
        let t0 = (f.a - e.wallStart).dot(e.direction)
        let t1 = (f.b - e.wallStart).dot(e.direction)
        let overlap = Swift.min(Swift.max(t0, t1), e.s1) - Swift.max(Swift.min(t0, t1), e.s0)
        let narrower = Swift.min(e.width, f.width)
        guard overlap >= 0.6 * narrower,
              abs(e.width - f.width) <= Swift.max(0.3, 0.3 * Swift.max(e.width, f.width)) else { return nil }
        return overlap
    }

    /// True when `e`'s room draws the symbol, false when `f`'s does. Doors are drawn from the room
    /// they open into: never a corridor or entrance when the other side is a room, else the smaller
    /// room (bathrooms, bedrooms and kitchens take the swing, not the living room). Ties and
    /// everything that is not a door go to the room that comes first.
    private static func symbolOwner(_ e: Entry, _ f: Entry, _ geometries: [PlanDrawingBuilder.RoomGeometry]) -> Bool {
        guard e.kind == .door else { return e.room <= f.room }
        func isCirculation(_ kind: RoomKind) -> Bool { kind == .corridor || kind == .entrance }
        let roomE = geometries[e.room], roomF = geometries[f.room]
        let circulationE = isCirculation(roomE.room.kind), circulationF = isCirculation(roomF.room.kind)
        if circulationE != circulationF { return !circulationE }
        let areaE = roomE.metrics.floorArea, areaF = roomF.metrics.floorArea
        if abs(areaE - areaF) > 1e-6 { return areaE < areaF }
        return e.room <= f.room
    }
}
