import Foundation

/// What a piece of cut-up wall is, relative to the openings around it.
public enum WallPieceRole: String, Codable, Sendable {
    /// Solid wall from the floor to the top of the wall, where no opening cuts it.
    case full
    /// Wall above an opening (head to wall top): a lintel. Also the wall between two stacked openings.
    case aboveOpening
    /// Wall below an opening that does not reach the floor (floor to sill): the panel under a window.
    case belowWindow
}

/// A flat rectangle of solid wall, in the wall's own frame, ready to extrude in the 3D viewer.
public struct WallPiece: Hashable, Sendable {
    public var wallID: UUID
    /// The opening this piece sits above or below; nil for `.full` pieces.
    public var openingID: UUID?
    /// Span along the wall, metres from `Wall.start`. Always `lowerBound < upperBound`.
    public var along: ClosedRange<Double>
    /// Metres above the room's floor. Always `bottom < top`.
    public var bottom: Double
    public var top: Double
    public var role: WallPieceRole

    public init(wallID: UUID, openingID: UUID?, along: ClosedRange<Double>, bottom: Double, top: Double,
                role: WallPieceRole) {
        self.wallID = wallID
        self.openingID = openingID
        self.along = along
        self.bottom = bottom
        self.top = top
        self.role = role
    }

    public var width: Double { along.upperBound - along.lowerBound }
    public var height: Double { top - bottom }
    /// Face area, square metres.
    public var area: Double { width * height }
}

public extension Room {
    /// Every solid wall cut around its openings: the rectangles that remain when openings are
    /// removed, so that summed piece area plus opening area is wall length x wall height.
    ///
    /// - A wall with no opening gives one `.full` piece.
    /// - Between openings: `.full` pieces from floor to wall top.
    /// - Above each opening: an `.aboveOpening` lintel from its head to the wall top.
    /// - Below each opening that does not reach the floor: a `.belowWindow` panel from the floor
    ///   to its sill (any raised opening, not only windows).
    /// - `.virtual` walls give nothing.
    ///
    /// Uses SCANNED geometry (stored corners, `Wall.height.scanned`, `Opening.width.scanned` and
    /// friends), never verified values. Openings are clipped to their wall; an opening that is
    /// off the wall, or has no size once clipped, is ignored. Overlapping openings are handled
    /// exactly: the wall is cut into vertical strips at every opening edge, the openings
    /// active in a strip are merged, and equal neighbouring strips are re-joined, so pieces never
    /// overlap and the removed area is the UNION of the openings. A lintel or panel above or below
    /// merged openings is attributed to the one that defines its edge (the earliest in
    /// `openings` on a tie). Pieces thinner than 1e-10 m are dropped and edges closer than that
    /// are treated as one.
    ///
    /// Order: wall loop order, then left to right along each wall, then bottom to top.
    func wallPieces() -> [WallPiece] {
        walls.flatMap { wallPieces(on: $0) }
    }

    /// The pieces of one wall (see `wallPieces()`). `wall` should be one of this room's walls;
    /// only openings whose `wallID` equals `wall.id` are cut into it.
    func wallPieces(on wall: Wall) -> [WallPiece] {
        let eps = WallSolidsMath.epsilon
        guard wall.kind == .solid else { return [] }
        let length = wall.geometricLength
        let height = wall.height.scanned
        guard length.isFinite, height.isFinite, length > eps, height > eps else { return [] }

        // 1. Clip every opening to the wall.
        var cuts: [WallSolidsMath.Cut] = []
        for (order, opening) in openings.enumerated() where opening.wallID == wall.id {
            let offset = opening.offsetFromWallStart, width = opening.width.scanned
            let sill = opening.sillHeight.scanned, openingHeight = opening.height.scanned
            // (min and max would quietly turn a NaN into a number, so check first.)
            guard offset.isFinite, width.isFinite, sill.isFinite, openingHeight.isFinite else { continue }
            let x0 = max(0, offset), x1 = min(length, offset + width)
            let y0 = max(0, sill), y1 = min(height, sill + openingHeight)
            guard x1 - x0 > eps, y1 - y0 > eps else { continue }
            cuts.append(WallSolidsMath.Cut(id: opening.id, x0: x0, x1: x1, y0: y0, y1: y1, order: order))
        }

        // 2. Vertical strip boundaries: wall ends plus every opening edge, near-equal edges merged.
        var raw: [Double] = [0, length]
        for cut in cuts {
            raw.append(cut.x0)
            raw.append(cut.x1)
        }
        raw.sort()
        var xs: [Double] = []
        for x in raw {
            if let last = xs.last, x - last <= eps { continue }
            xs.append(x)
        }
        xs[0] = 0
        xs[xs.count - 1] = length
        guard xs.count >= 2 else { return [] }

        func edgeIndex(_ x: Double) -> Int {
            var best = 0
            var bestDistance = Double.infinity
            for (i, candidate) in xs.enumerated() {
                let d = abs(candidate - x)
                if d < bestDistance {
                    best = i
                    bestDistance = d
                }
            }
            return best
        }
        let spans = cuts.map { (cut: $0, from: edgeIndex($0.x0), to: edgeIndex($0.x1)) }

        // 3. Cut each strip vertically, re-joining equal pieces of neighbouring strips.
        var pieces: [WallPiece] = []
        var previousStrip: [Int] = []
        for k in 0..<(xs.count - 1) {
            let active = spans.filter { $0.from <= k && k < $0.to }.map(\.cut)
            var current: [Int] = []
            for slice in WallSolidsMath.solidSlices(height: height, cuts: active) {
                if let match = previousStrip.first(where: { index in
                    let p = pieces[index]
                    return p.bottom == slice.bottom && p.top == slice.top && p.role == slice.role
                        && p.openingID == slice.openingID
                }) {
                    pieces[match].along = pieces[match].along.lowerBound...xs[k + 1]
                    current.append(match)
                } else {
                    pieces.append(WallPiece(wallID: wall.id, openingID: slice.openingID, along: xs[k]...xs[k + 1],
                                            bottom: slice.bottom, top: slice.top, role: slice.role))
                    current.append(pieces.count - 1)
                }
            }
            previousStrip = current
        }
        return pieces
    }
}

/// Private maths for `Room.wallPieces()`.
enum WallSolidsMath {
    static let epsilon = 1e-10

    struct Cut {
        var id: UUID
        var x0: Double
        var x1: Double
        var y0: Double
        var y1: Double
        /// Position in `Room.openings`, for deterministic tie-breaks.
        var order: Int
    }

    struct Slice {
        var bottom: Double
        var top: Double
        var role: WallPieceRole
        var openingID: UUID?
    }

    /// The solid vertical slices left in one strip of wall once the `cuts` active in it are removed.
    static func solidSlices(height: Double, cuts: [Cut]) -> [Slice] {
        guard !cuts.isEmpty else {
            return [Slice(bottom: 0, top: height, role: .full, openingID: nil)]
        }
        // Merge vertical intervals that overlap or touch, remembering which opening defines each end.
        let sorted = cuts.sorted { a, b in
            if a.y0 != b.y0 { return a.y0 < b.y0 }
            return a.order < b.order
        }
        struct Group {
            var lo: Double
            var hi: Double
            var loID: UUID
            var hiID: UUID
        }
        var groups: [Group] = []
        for cut in sorted {
            if var last = groups.last, cut.y0 <= last.hi + epsilon {
                if cut.y1 > last.hi {
                    last.hi = cut.y1
                    last.hiID = cut.id
                }
                groups[groups.count - 1] = last
            } else {
                groups.append(Group(lo: cut.y0, hi: cut.y1, loID: cut.id, hiID: cut.id))
            }
        }
        var slices: [Slice] = []
        var floor = 0.0
        for (i, group) in groups.enumerated() {
            if group.lo - floor > epsilon {
                slices.append(i == 0
                    ? Slice(bottom: floor, top: group.lo, role: .belowWindow, openingID: group.loID)
                    : Slice(bottom: floor, top: group.lo, role: .aboveOpening, openingID: groups[i - 1].hiID))
            }
            floor = group.hi
        }
        if height - floor > epsilon, let last = groups.last {
            slices.append(Slice(bottom: floor, top: height, role: .aboveOpening, openingID: last.hiID))
        }
        return slices
    }
}
