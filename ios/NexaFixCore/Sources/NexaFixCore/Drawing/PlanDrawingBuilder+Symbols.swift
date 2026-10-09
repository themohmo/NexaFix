import Foundation

// Plan symbols: door swings, windows, doorless openings, the right-angle mark and dimension ticks.

extension PlanDrawingBuilder {

    // MARK: Openings

    /// Door leaf and swing, window glazing lines and doorless-opening threshold lines. The gaps
    /// themselves are cut by `addWalls`. Openings on open boundaries (virtual walls) have no wall
    /// to sit in and are not drawn.
    static func addOpenings(_ g: RoomGeometry, _ context: inout Context) {
        let ink = Palette.ink
        let t = wallThickness
        for w in g.walls where w.isUsable && w.wall.kind == .solid {
            for span in spans(on: w, in: g.room) {
                switch span.opening.kind {
                case .door:
                    // A leaf opened 90 degrees into the room, hinged at the opening's start edge on the inner
                    // face of the wall, with the quarter-circle it sweeps. A door wider than 1.3 m is a pair
                    // of leaves, each half the width, hinged at both edges.
                    if span.width > doubleDoorWidth {
                        let half = span.width / 2
                        addDoorLeaf(hinge: w.point(at: span.s0), closed: w.direction, inward: w.inward,
                                    length: half, &context)
                        addDoorLeaf(hinge: w.point(at: span.s1), closed: -w.direction, inward: w.inward,
                                    length: half, &context)
                    } else {
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

    /// One open door leaf: the line from `hinge` straight into the room and the quarter circle it
    /// sweeps from its closed position (`closed`, a unit vector along the wall) to the open one.
    static func addDoorLeaf(hinge: Point2, closed: Point2, inward: Point2, length: Double, _ context: inout Context) {
        context.line(.doors, hinge, hinge + inward * length, weight: Weight.doorLeaf, color: Palette.ink)
        let closedAngle = atan2(closed.y, closed.x) * 180 / Double.pi
        let openAngle = atan2(inward.y, inward.x) * 180 / Double.pi
        // Arcs run counter-clockwise: from the closed leaf to the open one when the open leaf is a quarter
        // turn anticlockwise of it, otherwise the other way round.
        let (from, to) = closed.cross(inward) > 0 ? (closedAngle, openAngle) : (openAngle, closedAngle)
        context.add(.doors, .arc(center: hinge, radius: length,
                                 startAngle: normalizedDegrees(from), endAngle: normalizedDegrees(to),
                                 StrokeStyle(weight: Weight.doorArc, color: Palette.muted)))
    }

    // MARK: Corner mark

    /// The small square that stands for a right angle: two short lines meeting at 90 degrees,
    /// `size` metres along each wall from the corner.
    static func addRightAngleMark(corner: Point2, towardsNext next: Point2, towardsPrevious previous: Point2,
                                  size: Double, _ context: inout Context) {
        let a = corner + next * size
        let c = corner + previous * size
        let b = a + previous * size
        context.add(.angles, .polyline([a, b, c], closed: false,
                                       stroke: StrokeStyle(weight: Weight.squareMark, color: Palette.muted),
                                       fill: nil))
    }

    // MARK: Dimension ticks

    /// A short 45-degree architectural tick across a dimension line at `point`.
    static func addTick(at point: Point2, lineDirection: Point2, halfLength: Double, _ context: inout Context) {
        let diagonal = lineDirection.rotated(by: Double.pi / 4)
        context.line(.dimensions, point - diagonal * halfLength, point + diagonal * halfLength,
                     weight: Weight.tick, color: Palette.ink)
    }
}
