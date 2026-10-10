import XCTest
@testable import NexaFixCore

// Tests for PlanDrawingBuilder. Expected numbers are worked out by hand in the comments, not read
// back from the code under test.

// MARK: - Helpers

private typealias TextItem = (string: String, at: Point2, height: Double, rotation: Double,
                              anchor: TextAnchor, color: DrawColor, bold: Bool)

private extension PlanDrawing {
    func items(_ layer: PlanLayer) -> [DrawingPrimitive] {
        primitives.filter { $0.layer == layer }.map(\.primitive)
    }

    func lines(_ layer: PlanLayer) -> [(a: Point2, b: Point2, style: DrawStroke)] {
        items(layer).compactMap {
            if case let .line(a, b, s) = $0 { return (a, b, s) }
            return nil
        }
    }

    func polylines(_ layer: PlanLayer) -> [(points: [Point2], closed: Bool, stroke: DrawStroke?, fill: DrawColor?)] {
        items(layer).compactMap {
            if case let .polyline(p, c, s, f) = $0 { return (p, c, s, f) }
            return nil
        }
    }

    func arcs(_ layer: PlanLayer) -> [(center: Point2, radius: Double, start: Double, end: Double, style: DrawStroke)] {
        items(layer).compactMap {
            if case let .arc(c, r, a, b, s) = $0 { return (c, r, a, b, s) }
            return nil
        }
    }

    func texts(_ layer: PlanLayer) -> [TextItem] {
        items(layer).compactMap {
            if case let .text(s, at, h, r, anchor, color, bold) = $0 { return (s, at, h, r, anchor, color, bold) }
            return nil
        }
    }

    func allTexts() -> [TextItem] {
        primitives.compactMap {
            if case let .text(s, at, h, r, anchor, color, bold) = $0.primitive { return (s, at, h, r, anchor, color, bold) }
            return nil
        }
    }
}

/// Everything off: only wall bands are drawn.
private let wallsOnly = PlanOptions(scale: 50, showDimensions: false, showAngles: false, showFurniture: false,
                                    showRoomLabels: false, showOpeningSizes: false, markVerified: true)

private func plan(_ room: Room, _ options: PlanOptions = PlanOptions()) -> PlanDrawing {
    PlanDrawingBuilder.build(room: room, options: options)
}

private func assertPoint(_ p: Point2, _ x: Double, _ y: Double, accuracy: Double = 1e-9,
                         _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(p.x, x, accuracy: accuracy, "x. \(message)", file: file, line: line)
    XCTAssertEqual(p.y, y, accuracy: accuracy, "y. \(message)", file: file, line: line)
}

private func shoelace(_ p: [Point2]) -> Double { abs(Polygon.signedArea(p)) }

/// Every number reachable in a primitive, to prove nothing is NaN or infinite.
private func numbers(of primitive: DrawingPrimitive) -> [Double] {
    switch primitive {
    case let .line(a, b, s): return [a.x, a.y, b.x, b.y, s.weight]
    case let .polyline(p, _, s, _): return p.flatMap { [$0.x, $0.y] } + [s?.weight ?? 0]
    case let .arc(c, r, a, b, s): return [c.x, c.y, r, a, b, s.weight]
    case let .circle(c, r, s): return [c.x, c.y, r, s.weight]
    case let .text(_, at, h, r, _, _, _): return [at.x, at.y, h, r]
    }
}

/// Small deterministic generator for fuzz tests.
private struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

final class PlanDrawingTests: XCTestCase {

    // MARK: Empty and degenerate input

    func testEmptyRoomListGivesEmptyDrawingWithSaneBounds() {
        let d = PlanDrawingBuilder.build(rooms: [], title: "T", subtitle: "S", options: PlanOptions())
        XCTAssertTrue(d.primitives.isEmpty)
        XCTAssertEqual(d.title, "T")
        XCTAssertEqual(d.subtitle, "S")
        XCTAssertGreaterThan(d.bounds.width, 0)
        XCTAssertGreaterThan(d.bounds.height, 0)
        XCTAssertTrue(d.bounds.width.isFinite && d.bounds.height.isFinite)
    }

    func testRoomsTooDegenerateToDrawAreSkippedWithoutCrashing() {
        let twoWalls = Room(name: "Two", walls: [
            Wall(start: Point2(0, 0), end: Point2(1, 0), height: Measured(scanned: 2.8)),
            Wall(start: Point2(1, 0), end: Point2(0, 0), height: Measured(scanned: 2.8)),
        ], ceilingHeight: Measured(scanned: 2.8))
        let nan = Room.polygon(name: "NaN", corners: [Point2(0, 0), Point2(.nan, 0), Point2(1, 1)])
        let empty = Room(name: "None", walls: [], ceilingHeight: Measured(scanned: 2.8))
        let d = PlanDrawingBuilder.build(rooms: [twoWalls, nan, empty], title: "", subtitle: "", options: PlanOptions())
        XCTAssertTrue(d.primitives.isEmpty)
        XCTAssertGreaterThan(d.bounds.width, 0)
    }

    func testZeroLengthWallIsSkippedAndTheRestStillDraws() {
        // The same square with a repeated corner: a zero-length wall between (4,0) and (4,0).
        let room = Room.polygon(name: "Dup", corners: [Point2(0, 0), Point2(4, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)])
        let d = plan(room, wallsOnly)
        guard d.polylines(.walls).count == 4 else { return XCTFail("expected 4, got \(d.polylines(.walls).count)") }
        for item in d.primitives { XCTAssertTrue(numbers(of: item.primitive).allSatisfy(\.isFinite)) }
    }

    // MARK: Wall bands

    func testRectangleWallsAreFourMitredBandsOutwardOfTheClearOutline() {
        let d = plan(Room.rectangle(name: "R", width: 4, depth: 3), wallsOnly)
        guard d.primitives.count == 4 else { return XCTFail("expected 4, got \(d.primitives.count)") }
        let bands = d.polylines(.walls)
        guard bands.count == 4 else { return XCTFail("expected 4, got \(bands.count)") }

        // South wall: inner (0,0)-(4,0); outer face 0.12 m below, mitred at 45 degrees at both ends.
        let south = bands[0].points
        guard south.count == 4 else { return XCTFail("expected 4, got \(south.count)") }
        assertPoint(south[0], 0, 0)
        assertPoint(south[1], 4, 0)
        assertPoint(south[2], 4.12, -0.12)
        assertPoint(south[3], -0.12, -0.12)
        // East wall: (4,0)-(4,3), outer face 0.12 m to the right.
        assertPoint(bands[1].points[2], 4.12, 3.12)
        assertPoint(bands[1].points[3], 4.12, -0.12)

        // Together the bands tile the ring between the 4x3 clear outline and the 4.24x3.24 outer
        // outline: 4.24 * 3.24 - 4 * 3 = 1.7376 m2. Each band is a trapezoid: 2 * ((4 + 4.24)/2 +
        // (3 + 3.24)/2) * 0.12 = 1.7376.
        let total = bands.reduce(0) { $0 + shoelace($1.points) }
        XCTAssertEqual(total, 4.24 * 3.24 - 12, accuracy: 1e-9)
        XCTAssertEqual(shoelace(bands[0].points), (4 + 4.24) / 2 * 0.12, accuracy: 1e-9)

        for b in bands {
            XCTAssertTrue(b.closed)
            XCTAssertNotNil(b.fill)
            XCTAssertEqual(b.stroke?.weight ?? 0, 0.5, accuracy: 1e-12, "walls are 0.5 mm on paper")
            XCTAssertFalse(b.stroke?.dashed ?? true)
        }
    }

    func testBandsLieOutsideTheOutlineForEveryWallOfAnLShape() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        let d = plan(l, wallsOnly)
        let bands = d.polylines(.walls)
        guard bands.count == 6 else { return XCTFail("expected 6, got \(bands.count)") }
        for b in bands {
            // Points 2 and 3 are the outer face: never inside the room.
            XCTAssertFalse(Polygon.contains(l.outline, b.points[2]))
            XCTAssertFalse(Polygon.contains(l.outline, b.points[3]))
        }
        // Walls: 0:(0,0)-(6,0) 1:(6,0)-(6,2) 2:(6,2)-(4,2) 3:(4,2)-(4,4) 4:(4,4)-(0,4) 5:(0,4)-(0,0).
        // Wall 2 ends at the reflex corner (4,2) and wall 3 starts there. Their outer faces are
        // y = 2.12 and x = 4.12, which cross at (4.12, 2.12), inside the notch.
        assertPoint(bands[2].points[2], 4.12, 2.12, accuracy: 1e-9, "wall 2 outer end at the reflex corner")
        assertPoint(bands[3].points[3], 4.12, 2.12, accuracy: 1e-9, "wall 3 outer start at the reflex corner")
        // Convex corner (6,2): wall 1 ends there going north, wall 2 starts going west; the outer faces
        // x = 6.12 and y = 2.12 cross at (6.12, 2.12).
        assertPoint(bands[1].points[2], 6.12, 2.12, accuracy: 1e-9)
    }

    func testVirtualWallIsADashedLineOnTheOpenLayerAndNeighbourBandsAreSquaredOff() {
        var room = Room.rectangle(name: "Open", width: 4, depth: 3)
        room.walls[1].kind = .virtual   // east side open
        let d = plan(room, wallsOnly)
        let open = d.lines(.wallsOpen)
        guard open.count == 1 else { return XCTFail("expected 1, got \(open.count)") }
        assertPoint(open[0].a, 4, 0)
        assertPoint(open[0].b, 4, 3)
        XCTAssertTrue(open[0].style.dashed)
        guard d.polylines(.walls).count == 3 else { return XCTFail("no band for the open boundary: expected 3, got \(d.polylines(.walls).count)") }
        // South wall now ends square at x = 4 instead of mitring towards (4.12, -0.12).
        let south = d.polylines(.walls)[0].points
        assertPoint(south[2], 4, -0.12)
        assertPoint(south[3], -0.12, -0.12)
        // North wall runs (4,3)->(0,3); its start is square, at (4, 3.12).
        let north = d.polylines(.walls)[1].points
        assertPoint(north[3], 4, 3.12)
    }

    func testOpeningsOnAnOpenBoundaryAreNotDrawn() {
        var room = Room.rectangle(name: "Open", width: 4, depth: 3, openings: [.door(wall: 1, offset: 0.5)])
        room.walls[1].kind = .virtual
        let d = plan(room, wallsOnly)
        XCTAssertTrue(d.items(.doors).isEmpty)
    }

    func testCurvedWallIsDrawnAsItsChordAndSaysSo() {
        // The model stores only the chord, so the geometry is the straight wall...
        var curved = Room.rectangle(name: "C", width: 4, depth: 3)
        curved.walls[0].isCurved = true
        let straight = Room.rectangle(name: "C", width: 4, depth: 3)
        XCTAssertEqual(plan(curved).items(.walls), plan(straight).items(.walls), "the band is the chord")
        XCTAssertEqual(plan(curved).lines(.dimensions).count, plan(straight).lines(.dimensions).count)
        // ...but the printed plan must not pass it off as a straight 4000 mm run.
        let curvedTexts = plan(curved).texts(.dimensions).map(\.string)
        XCTAssertEqual(curvedTexts.first, "4000 mm chord", "straight length of a curved wall, flagged")
        XCTAssertEqual(plan(straight).texts(.dimensions).first?.string, "4000 mm")
        XCTAssertEqual(curvedTexts.filter { $0.contains("chord") }.count, 1, "only the curved wall is flagged")
        XCTAssertEqual(plan(curved).texts(.dimensions)[0].color, PlanDrawingBuilder.Palette.bronze)
        let detailed = PlanDrawingBuilder.buildDetailed(room: curved, options: PlanOptions())
        XCTAssertEqual(detailed.report.chordLabels, 1, "the report tells the legend to explain the flag")
        XCTAssertEqual(PlanDrawingBuilder.buildDetailed(room: straight, options: PlanOptions()).report.chordLabels, 0)
        // A checked chord keeps its mark and the flag: "4045 mm v chord".
        curved.walls[0].length.verify(4.045)
        XCTAssertEqual(plan(curved).texts(.dimensions)[0].string, "4045 mm v chord")
        XCTAssertEqual(plan(curved).texts(.dimensions)[0].color, PlanDrawingBuilder.Palette.verified)
    }

    func testClockwiseWindingStillPutsBandsOutsideAndDimensionsInside() {
        // A square with its walls in clockwise order (violating the model contract).
        let pts = [Point2(0, 0), Point2(0, 3), Point2(4, 3), Point2(4, 0)]
        let walls = pts.indices.map { i in
            Wall(start: pts[i], end: pts[(i + 1) % 4], height: Measured(scanned: 2.8))
        }
        let room = Room(name: "CW", walls: walls, ceilingHeight: Measured(scanned: 2.8))
        XCTAssertFalse(Polygon.isCounterClockwise(room.outline))
        let d = plan(room, PlanOptions(scale: 50, showAngles: false, showFurniture: false, showRoomLabels: false,
                                       showOpeningSizes: false))
        for b in d.polylines(.walls) {
            XCTAssertFalse(Polygon.contains(room.outline, b.points[2]))
            XCTAssertFalse(Polygon.contains(room.outline, b.points[3]))
        }
        for l in d.lines(.dimensions) where abs(l.a.distance(to: l.b)) > 0.5 {
            XCTAssertTrue(Polygon.contains(room.outline, (l.a + l.b) / 2), "dimension lines are inside the room")
        }
    }

    // MARK: Doors, windows, openings

    func testDoorCutsTheBandAndDrawsLeafAndNinetyDegreeSwingIntoTheRoom() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 0, offset: 1.0, width: 0.9)])
        let d = plan(room, wallsOnly)

        // South wall band is in two pieces, [0, 1.0] and [1.9, 4].
        let bands = d.polylines(.walls)
        guard bands.count == 5 else { return XCTFail("expected 5, got \(bands.count)") }
        let first = bands[0].points
        assertPoint(first[0], 0, 0); assertPoint(first[1], 1.0, 0)
        assertPoint(first[2], 1.0, -0.12); assertPoint(first[3], -0.12, -0.12)
        let second = bands[1].points
        assertPoint(second[0], 1.9, 0); assertPoint(second[1], 4, 0)
        assertPoint(second[2], 4.12, -0.12); assertPoint(second[3], 1.9, -0.12)

        // Leaf from the hinge (start edge, x = 1.0) straight into the room.
        let leaf = d.lines(.doors)
        guard leaf.count == 1 else { return XCTFail("expected 1, got \(leaf.count)") }
        assertPoint(leaf[0].a, 1.0, 0)
        assertPoint(leaf[0].b, 1.0, 0.9)
        // Swing: quarter circle about the hinge from the closed leaf (along the wall, 0 deg) to the open leaf (90 deg).
        let swing = d.arcs(.doors)
        guard swing.count == 1 else { return XCTFail("expected 1, got \(swing.count)") }
        assertPoint(swing[0].center, 1.0, 0)
        XCTAssertEqual(swing[0].radius, 0.9, accuracy: 1e-12)
        XCTAssertEqual(swing[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(swing[0].end, 90, accuracy: 1e-9)
    }

    func testDoorOnTheEastWallSwingsWestFromItsStartEdge() {
        // East wall runs (4,0)->(4,3), so its start edge is the southern one and the room is to the west.
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 1, offset: 0.5, width: 0.8)])
        let d = plan(room, wallsOnly)
        let leaf = d.lines(.doors)[0]
        assertPoint(leaf.a, 4, 0.5)
        assertPoint(leaf.b, 3.2, 0.5)
        let swing = d.arcs(.doors)[0]
        XCTAssertEqual(swing.start, 90, accuracy: 1e-9)
        XCTAssertEqual(swing.end, 180, accuracy: 1e-9)
        // The arc's mid-point is inside the room.
        let mid = (swing.start + swing.end) / 2 * Double.pi / 180
        let p = swing.center + Point2(cos(mid), sin(mid)) * swing.radius
        XCTAssertTrue(Polygon.contains(room.outline, p))
    }

    func testWideDoorIsAPairOfLeavesHingedAtBothEdges() {
        // 1.6 m wide on the south wall of a 5 x 4 room, from x = 0.5 to 2.1.
        let room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 0, offset: 0.5, width: 1.6, height: 2.2)])
        let d = plan(room, wallsOnly)
        let leaves = d.lines(.doors)
        guard leaves.count == 2 else { return XCTFail("two leaves, got \(leaves.count)") }
        assertPoint(leaves[0].a, 0.5, 0); assertPoint(leaves[0].b, 0.5, 0.8)
        assertPoint(leaves[1].a, 2.1, 0); assertPoint(leaves[1].b, 2.1, 0.8)
        let arcs = d.arcs(.doors)
        guard arcs.count == 2 else { return XCTFail("two swings, got \(arcs.count)") }
        assertPoint(arcs[0].center, 0.5, 0)
        XCTAssertEqual(arcs[0].radius, 0.8, accuracy: 1e-12)
        XCTAssertEqual(arcs[0].start, 0, accuracy: 1e-9); XCTAssertEqual(arcs[0].end, 90, accuracy: 1e-9)
        // The second leaf swings from the far edge back towards the middle: 90 -> 180 degrees.
        assertPoint(arcs[1].center, 2.1, 0)
        XCTAssertEqual(arcs[1].start, 90, accuracy: 1e-9); XCTAssertEqual(arcs[1].end, 180, accuracy: 1e-9)
        // Both quarter circles meet in the middle of the opening (x = 1.3) on the wall line.
        XCTAssertEqual(arcs[0].center.x + arcs[0].radius, 1.3, accuracy: 1e-9)
        XCTAssertEqual(arcs[1].center.x - arcs[1].radius, 1.3, accuracy: 1e-9)
        // 1.3 m and narrower stay a single leaf.
        let single = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 0, offset: 0.5, width: 1.3)])
        XCTAssertEqual(plan(single, wallsOnly).lines(.doors).count, 1)
        // A pair of leaves also swings into the room on a wall that runs the other way (north wall, runs west),
        // and a 2.0 m door is still a pair of leaves: only wider than that is a slider.
        let north = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 2, offset: 0.5, width: 2.0)])
        XCTAssertEqual(plan(north, wallsOnly).arcs(.doors).count, 2)
        for a in plan(north, wallsOnly).arcs(.doors) {
            var sweep = a.end - a.start
            if sweep < 0 { sweep += 360 }
            XCTAssertEqual(sweep, 90, accuracy: 1e-9)
            let mid = (a.start + 45) * Double.pi / 180
            XCTAssertTrue(Polygon.contains(north.outline, a.center + Point2(cos(mid), sin(mid)) * (a.radius * 0.8)))
        }
    }

    func testADoorWiderThanTwoMetresIsASlidingDoorNotASwing() {
        // The 2.4 m balcony door of the demo flat: two panels in two tracks, no leaf and no swing.
        let room = Room.rectangle(name: "Balcony", width: 5, depth: 3,
                                  openings: [.door(wall: 0, offset: 1.0, width: 2.4, height: 2.2)])
        let d = plan(room, wallsOnly)
        XCTAssertTrue(d.lines(.doors).isEmpty, "no leaf")
        XCTAssertTrue(d.arcs(.doors).isEmpty, "no swing arc")
        let panels = d.polylines(.doors)
        guard panels.count == 2 else { return XCTFail("two panels, got \(panels.count)") }
        for panel in panels {
            XCTAssertTrue(panel.closed)
            XCTAssertEqual(panel.points.count, 4)
        }
        // Along the wall the panels cover 55 % of the 2.4 m each (1.32 m), from the two ends, overlapping by 0.24 m
        // in the middle: x from 1.0 to 2.32 and from 2.08 to 3.4.
        func xRange(_ p: [Point2]) -> (Double, Double) { (p.map(\.x).min()!, p.map(\.x).max()!) }
        XCTAssertEqual(xRange(panels[0].points).0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(xRange(panels[0].points).1, 2.32, accuracy: 1e-9)
        XCTAssertEqual(xRange(panels[1].points).0, 2.08, accuracy: 1e-9)
        XCTAssertEqual(xRange(panels[1].points).1, 3.4, accuracy: 1e-9)
        // In two different tracks inside the 0.12 m wall: 0.036 and 0.084 m out from the inner face.
        let y0 = panels[0].points.map(\.y).reduce(0, +) / 4, y1 = panels[1].points.map(\.y).reduce(0, +) / 4
        XCTAssertEqual(y0, -0.036, accuracy: 1e-9)
        XCTAssertEqual(y1, -0.084, accuracy: 1e-9)
        // The doorway is still cut through the wall band, and it still gets its size tag.
        XCTAssertEqual(d.polylines(.walls).count, 5, "south wall in two pieces, plus three more walls")
        XCTAssertEqual(plan(room).texts(.doors).map(\.string), ["D 2400x2200"])
    }

    func testEveryDoorSwingFallsInsideTheRoomForAllWallDirections() {
        var specs: [OpeningSpec] = []
        for wall in 0..<4 { specs.append(.door(wall: wall, offset: 0.6, width: 0.8)) }
        let room = Room.rectangle(name: "R", width: 5, depth: 4, openings: specs)
        let d = plan(room, wallsOnly)
        let swings = d.arcs(.doors)
        guard swings.count == 4 else { return XCTFail("expected 4, got \(swings.count)") }
        for s in swings {
            var sweep = s.end - s.start
            if sweep < 0 { sweep += 360 }
            XCTAssertEqual(sweep, 90, accuracy: 1e-9)
            let mid = (s.start + sweep / 2) * Double.pi / 180
            let p = s.center + Point2(cos(mid), sin(mid)) * (s.radius * 0.9)
            XCTAssertTrue(Polygon.contains(room.outline, p), "door swings into the room, not out of it")
        }
    }

    func testWindowIsAGapWithThreeParallelThinLines() {
        // North wall runs (4,3)->(0,3): offset 1.0 width 1.5 spans x = 3.0 down to 1.5.
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.window(wall: 2, offset: 1.0, width: 1.5)])
        let d = plan(room, wallsOnly)
        let lines = d.lines(.windows)
        guard lines.count == 3 else { return XCTFail("expected 3, got \(lines.count)") }
        let ys = lines.map { $0.a.y }.sorted()
        XCTAssertEqual(ys[0], 3.0, accuracy: 1e-9)
        XCTAssertEqual(ys[1], 3.06, accuracy: 1e-9)
        XCTAssertEqual(ys[2], 3.12, accuracy: 1e-9)
        for l in lines {
            XCTAssertEqual(l.a.y, l.b.y, accuracy: 1e-9)
            XCTAssertEqual(Set([l.a.x, l.b.x].map { ($0 * 1000).rounded() / 1000 }), [3.0, 1.5])
            XCTAssertLessThanOrEqual(l.style.weight, 0.2)
        }
        // The band is interrupted: pieces [0, 1.0] and [2.5, 4] of the north wall.
        let north = d.polylines(.walls).filter { $0.points.allSatisfy { $0.y >= 3 - 1e-9 && $0.y <= 3.12 + 1e-9 } && $0.points.map(\.x).max()! - $0.points.map(\.x).min()! > 0.5 }
        guard north.count == 2 else { return XCTFail("expected 2, got \(north.count)") }
        let northSpans = north.map { ($0.points.map(\.x).min()!, $0.points.map(\.x).max()!) }.sorted { $0.0 < $1.0 }
        XCTAssertEqual(northSpans[0].1, 1.5, accuracy: 1e-9)   // [0, 1.5] ... window spans x = 1.5 ... 3.0
        XCTAssertEqual(northSpans[1].0, 3.0, accuracy: 1e-9)
    }

    func testDoorlessOpeningHasDashedEdgesOnBothFaces() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3,
                                  openings: [OpeningSpec(wall: 0, kind: .opening, offset: 1, width: 1.2, height: 2.4)])
        let d = plan(room, wallsOnly)
        let lines = d.lines(.openings)
        guard lines.count == 2 else { return XCTFail("expected 2, got \(lines.count)") }
        XCTAssertTrue(lines.allSatisfy { $0.style.dashed })
        XCTAssertEqual(lines.map { $0.a.y }.sorted(), [-0.12, 0], "inner and outer face")
        XCTAssertTrue(d.items(.doors).isEmpty)
        XCTAssertTrue(d.items(.windows).isEmpty)
    }

    func testOverlappingOpeningsShareOneGap() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [
            .window(wall: 0, offset: 1.0, width: 1.0), .window(wall: 0, offset: 1.5, width: 1.0)])
        let d = plan(room, wallsOnly)
        // Gap [1.0, 2.5]: south band pieces [0,1.0] and [2.5,4], not three pieces.
        let south = d.polylines(.walls).filter { $0.points.allSatisfy { $0.y <= 1e-9 && $0.y >= -0.12 - 1e-9 } && $0.points.map(\.x).max()! - $0.points.map(\.x).min()! > 0.5 }
        guard south.count == 2 else { return XCTFail("expected 2, got \(south.count)") }
        let spans = south.map { ($0.points.map(\.x).min()!, $0.points.map(\.x).max()!) }.sorted { $0.0 < $1.0 }
        XCTAssertEqual(spans[0].1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(spans[1].0, 2.5, accuracy: 1e-9)
        guard d.lines(.windows).count == 6 else { return XCTFail("expected 6, got \(d.lines(.windows).count)") }
    }

    func testOpeningsOutsideTheWallAreClippedOrIgnored() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [
            .door(wall: 0, offset: 3.5, width: 1.0),     // sticks out of the east end: clipped to [3.5, 4]
            .window(wall: 2, offset: 6.0, width: 1.0),   // entirely beyond the wall
            .window(wall: 3, offset: -0.3, width: 1.0),  // starts before the wall: clipped to [0, 0.7]
        ])
        let d = plan(room, wallsOnly)
        let swing = d.arcs(.doors)
        guard swing.count == 1 else { return XCTFail("expected 1, got \(swing.count)") }
        XCTAssertEqual(swing[0].radius, 0.5, accuracy: 1e-9, "radius is the clipped width")
        XCTAssertTrue(d.lines(.windows).count == 3, "only the clipped window on wall 3 is drawn")
        XCTAssertTrue(d.primitives.allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
    }

    func testUnmatchedAndNonFiniteOpeningsAreIgnored() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.openings = [
            Opening(kind: .door, wallID: nil, offsetFromWallStart: 1, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)),
            Opening(kind: .door, wallID: UUID(), offsetFromWallStart: 1, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)),
            Opening(kind: .window, wallID: room.walls[0].id, offsetFromWallStart: .nan, width: Measured(scanned: 1), height: Measured(scanned: 1)),
            Opening(kind: .window, wallID: room.walls[0].id, offsetFromWallStart: 1, width: Measured(scanned: .infinity), height: Measured(scanned: 1)),
        ]
        let d = plan(room)
        XCTAssertTrue(d.items(.doors).isEmpty)
        XCTAssertTrue(d.items(.windows).isEmpty)
        guard d.polylines(.walls).count == 4 else { return XCTFail("expected 4, got \(d.polylines(.walls).count)") }
        XCTAssertTrue(d.primitives.allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
    }

    // MARK: Furniture

    func testFurnitureIsALightGreyFootprintWithItsKindName() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.objects = [RoomObject(kind: .sofa, center: Point2(2, 1.5), yaw: 0, width: 1.0, depth: 0.5, height: 0.8)]
        let d = plan(room)
        let shapes = d.polylines(.furniture)
        guard shapes.count == 1 else { return XCTFail("expected 1, got \(shapes.count)") }
        // Footprint of a 1.0 x 0.5 box centred on (2, 1.5), unrotated.
        let p = shapes[0].points
        assertPoint(p[0], 1.5, 1.25); assertPoint(p[1], 2.5, 1.25); assertPoint(p[2], 2.5, 1.75); assertPoint(p[3], 1.5, 1.75)
        XCTAssertEqual(shapes[0].fill, PlanDrawingBuilder.Palette.furnitureFill)
        XCTAssertTrue(shapes[0].closed)
        let labels = d.texts(.furniture)
        XCTAssertEqual(labels.map(\.string), ["Sofa"])
        XCTAssertEqual(labels[0].rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(labels[0].anchor, .center)
        XCTAssertEqual(labels[0].height, 0.075, accuracy: 1e-12, "1.5 mm on paper at 1:50")
        // Visually centred: the baseline is half a cap height below the centre.
        XCTAssertEqual(labels[0].at.x, 2, accuracy: 1e-9)
        XCTAssertEqual(labels[0].at.y, 1.5 - 0.075 / 2, accuracy: 1e-9)
    }

    func testRotatedFurnitureLabelFollowsTheLongSideButStaysUpright() {
        var room = Room.rectangle(name: "R", width: 6, depth: 6)
        // 2.0 wide x 0.5 deep turned 90 degrees: the long side now runs north-south.
        room.objects = [RoomObject(kind: .table, center: Point2(3, 3), yaw: Double.pi / 2, width: 2.0, depth: 0.5, height: 0.7)]
        let label = plan(room).texts(.furniture)[0]
        XCTAssertEqual(label.rotation, 90, accuracy: 1e-9)
        // Yaw of -90 degrees is the same line; the label must not flip to -90.
        room.objects[0].yaw = -Double.pi / 2
        XCTAssertEqual(plan(room).texts(.furniture)[0].rotation, 90, accuracy: 1e-9)
    }

    func testTinyFurnitureKeepsItsFootprintButDropsItsLabel() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.objects = [RoomObject(kind: .television, center: Point2(2, 1.5), yaw: 0, width: 0.12, depth: 0.12, height: 0.5)]
        let d = plan(room)
        guard d.polylines(.furniture).count == 1 else { return XCTFail("expected 1, got \(d.polylines(.furniture).count)") }
        XCTAssertTrue(d.texts(.furniture).isEmpty)
    }

    func testFurnitureNameStepsOffDimensionTextButTheFootprintStays() {
        // A 1.2 x 0.4 storage unit against the south wall of a 4 x 3 room sits where "4000 mm" is printed
        // (centred at x = 2, just above the dimension line at y = 0.25).
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.objects = [RoomObject(kind: .storage, center: Point2(2, 0.3), yaw: 0, width: 1.2, depth: 0.4, height: 2)]
        let withDims = plan(room)
        XCTAssertEqual(withDims.polylines(.furniture).count, 1)
        XCTAssertTrue(withDims.texts(.furniture).isEmpty, "the label would sit on the dimension text")
        var o = PlanOptions(); o.showDimensions = false
        XCTAssertEqual(plan(room, o).texts(.furniture).map(\.string), ["Storage"], "with no dimensions there is nothing to avoid")
        // Away from the dimension text the label stays.
        room.objects[0].center = Point2(2, 1.5)
        XCTAssertEqual(plan(room).texts(.furniture).map(\.string), ["Storage"])
    }

    func testFurnitureCanBeSwitchedOffAndInvalidObjectsAreSkipped() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.objects = [
            RoomObject(kind: .sofa, center: Point2(2, 1.5), yaw: 0, width: 1.0, depth: 0.5, height: 0.8),
            RoomObject(kind: .bed, center: Point2(.nan, 1), yaw: 0, width: 1.0, depth: 0.5, height: 0.8),
            RoomObject(kind: .bed, center: Point2(1, 1), yaw: 0, width: 0, depth: 0.5, height: 0.8),
        ]
        guard plan(room).polylines(.furniture).count == 1 else { return XCTFail("expected 1, got \(plan(room).polylines(.furniture).count)") }
        var options = PlanOptions(); options.showFurniture = false
        XCTAssertTrue(plan(room, options).items(.furniture).isEmpty)
    }

    // MARK: Dimensions

    func testDimensionLinesSitQuarterOfAMetreInsideEachWallWithTicksAndCentredUprightText() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3)
        var options = wallsOnly; options.showDimensions = true
        let d = plan(room, options)

        // Long dimension lines (ticks are 0.17 m, far shorter).
        let longLines = d.lines(.dimensions).filter { $0.a.distance(to: $0.b) > 1 }
        guard longLines.count == 4 else { return XCTFail("expected 4, got \(longLines.count)") }
        assertPoint(longLines[0].a, 0, 0.25); assertPoint(longLines[0].b, 4, 0.25)     // south
        assertPoint(longLines[1].a, 3.75, 0); assertPoint(longLines[1].b, 3.75, 3)     // east
        assertPoint(longLines[2].a, 4, 2.75); assertPoint(longLines[2].b, 0, 2.75)     // north
        assertPoint(longLines[3].a, 0.25, 3); assertPoint(longLines[3].b, 0.25, 0)     // west
        XCTAssertTrue(longLines.allSatisfy { abs($0.style.weight - 0.13) < 1e-12 }, "dimension lines are 0.13 mm")

        // Two end ticks per line, at 45 degrees to it.
        let ticks = d.lines(.dimensions).filter { $0.a.distance(to: $0.b) < 1 }
        guard ticks.count == 8 else { return XCTFail("expected 8, got \(ticks.count)") }
        for t in ticks {
            XCTAssertEqual(t.a.distance(to: t.b), 0.12, accuracy: 1e-9, "tick is 2 x 1.2 mm on paper = 0.12 m")
            let v = (t.b - t.a).normalized
            XCTAssertEqual(abs(v.x), abs(v.y), accuracy: 1e-9, "45 degrees")
        }
        // The first tick of the south line is centred on the line's start.
        let southTicks = ticks.filter { abs(($0.a.y + $0.b.y) / 2 - 0.25) < 1e-9 }
        guard southTicks.count == 2 else { return XCTFail("expected 2, got \(southTicks.count)") }

        // Text: "4000 mm" above the south line (y greater), centred; "3000 mm" along vertical walls.
        let texts = d.texts(.dimensions)
        XCTAssertEqual(texts.map(\.string), ["4000 mm", "3000 mm", "4000 mm", "3000 mm"])
        XCTAssertEqual(texts[0].rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(texts[0].anchor, .center)
        XCTAssertEqual(texts[0].at.x, 2, accuracy: 1e-9)
        XCTAssertEqual(texts[0].at.y, 0.25 + 0.3 * 0.1, accuracy: 1e-9, "above the line by 0.3 of the text height")
        XCTAssertEqual(texts[0].height, 0.1, accuracy: 1e-12, "2.0 mm on paper at 1:50")
        // East wall runs north: text reads bottom-to-top (90), "above" means toward -x in the text's frame.
        XCTAssertEqual(texts[1].rotation, 90, accuracy: 1e-9)
        XCTAssertEqual(texts[1].at.x, 3.75 - 0.03, accuracy: 1e-9)
        XCTAssertEqual(texts[1].at.y, 1.5, accuracy: 1e-9)
        // North wall runs west (180 degrees): flipped to 0 so it is not upside-down.
        XCTAssertEqual(texts[2].rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(texts[2].at.y, 2.75 + 0.03, accuracy: 1e-9)
        // West wall runs south (-90 degrees): flipped to +90.
        XCTAssertEqual(texts[3].rotation, 90, accuracy: 1e-9)
    }

    func testDimensionTextIsNeverUpsideDownForAnyWallDirection() {
        // A 17-gon with walls in every direction, plus its mirror.
        let n = 17
        let pts = (0..<n).map { i -> Point2 in
            let a = 2 * Double.pi * Double(i) / Double(n)
            return Point2(4 * cos(a), 4 * sin(a))
        }
        for corners in [pts, pts.reversed()] {
            let room = Room.polygon(name: "Poly", corners: Array(corners))
            let d = plan(room)
            let dims = d.texts(.dimensions)
            XCTAssertEqual(dims.count, n)
            for t in dims {
                XCTAssertGreaterThan(t.rotation, -90, "never upside-down: \(t.rotation)")
                XCTAssertLessThanOrEqual(t.rotation, 90)
            }
        }
    }

    func testDimensionTextUsesTheVerifiedValueAndMarksItWithLowercaseV() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.walls[0].length.verify(4.045, source: .laser)       // scan said 4.000
        let texts = plan(room).texts(.dimensions)
        XCTAssertEqual(texts[0].string, "4045 mm v")               // effective value, marked
        XCTAssertEqual(texts[0].color, PlanDrawingBuilder.Palette.verified)
        XCTAssertEqual(texts[1].string, "3000 mm")                 // scanned: never marked
        XCTAssertFalse(texts[1].string.contains("v"))
        XCTAssertEqual(texts[1].color, PlanDrawingBuilder.Palette.ink)
        XCTAssertFalse(texts[0].string.contains("4000"), "the scanned 4000 is never shown for a verified wall")

        var off = PlanOptions(); off.markVerified = false
        let unmarked = plan(room, off).texts(.dimensions)
        XCTAssertEqual(unmarked[0].string, "4045 mm", "markVerified off: value still effective, no marker")
    }

    func testDimensionTextFollowsTheChosenUnits() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.walls[0].length.verify(4.0)
        func first(_ length: LengthUnit) -> String {
            var o = PlanOptions(); o.units = DisplayUnits(length: length, area: .squareMetres)
            return plan(room, o).texts(.dimensions)[0].string
        }
        // Every unit prints a checked value to at least a millimetre (feet and inches: a sixteenth of an inch).
        XCTAssertEqual(first(.millimetres), "4000 mm v")
        XCTAssertEqual(first(.centimetres), "400.0 cm v")
        XCTAssertEqual(first(.metres), "4.000 m v")
        XCTAssertEqual(first(.inches), "157.48 in v")        // 4 / 0.0254 = 157.4803
        XCTAssertEqual(first(.feetAndInches), "13' 1 1/2\" v")   // 157.4803 in = 13 ft 1.4803 in = 1 1/2 in to a sixteenth
    }

    func testWallsShorterThanFortyCentimetresGetNoDimensionLine() {
        // 4 x 0.39 and 4 x 0.4 rooms.
        let thin = Room.rectangle(name: "T", width: 4, depth: 0.39)
        let exact = Room.rectangle(name: "E", width: 4, depth: 0.4)
        XCTAssertEqual(plan(thin).texts(.dimensions).map(\.string), ["4000 mm", "4000 mm"], "the 390 mm ends are skipped")
        guard plan(exact).texts(.dimensions).count == 4 else { return XCTFail("400 mm is long enough: expected 4, got \(plan(exact).texts(.dimensions).count)") }
    }

    func testDimensionOffsetGrowsWithTextAtSmallScales() {
        let room = Room.rectangle(name: "R", width: 20, depth: 15)
        var o = wallsOnly; o.showDimensions = true; o.scale = 200
        let d = plan(room, o)
        // 2.0 mm text at 1:200 is 0.4 m tall, so the offset is 2.5 x 0.4 = 1.0 m instead of 0.25 m.
        XCTAssertEqual(d.texts(.dimensions)[0].height, 0.4, accuracy: 1e-12)
        let south = d.lines(.dimensions).first { $0.a.distance(to: $0.b) > 5 }!
        XCTAssertEqual(south.a.y, 1.0, accuracy: 1e-9)
    }

    func testDimensionsCanBeSwitchedOff() {
        var o = PlanOptions(); o.showDimensions = false
        XCTAssertTrue(plan(Room.rectangle(name: "R", width: 4, depth: 3), o).items(.dimensions).isEmpty)
    }

    // MARK: Angles

    func testRightAnglesPrintAsSmallSquaresWithNoText() {
        let d = plan(Room.rectangle(name: "R", width: 4, depth: 3))
        let marks = d.polylines(.angles)
        guard marks.count == 4 else { return XCTFail("expected 4, got \(marks.count)") }
        XCTAssertTrue(d.arcs(.angles).isEmpty)
        XCTAssertTrue(d.texts(.angles).isEmpty)
        // Corner (0,0): leg along the south wall, leg up the west wall, 2 mm = 0.1 m each.
        let m0 = marks[0]
        XCTAssertFalse(m0.closed)
        XCTAssertNil(m0.fill)
        guard m0.points.count == 3 else { return XCTFail("expected 3, got \(m0.points.count)") }
        assertPoint(m0.points[0], 0.1, 0); assertPoint(m0.points[1], 0.1, 0.1); assertPoint(m0.points[2], 0, 0.1)
    }

    func testAngleMarksCanBeSwitchedOff() {
        var o = PlanOptions(); o.showAngles = false
        XCTAssertTrue(plan(Room.rectangle(name: "R", width: 4, depth: 3), o).items(.angles).isEmpty)
    }

    /// Independent interior angle at vertex i of a counter-clockwise polygon, from the dot product.
    private func interior(_ p: [Point2], _ i: Int) -> Double {
        let n = p.count
        let a = (p[(i + 1) % n] - p[i]).normalized
        let b = (p[(i + n - 1) % n] - p[i]).normalized
        var degrees = acos(max(-1, min(1, a.dot(b)))) * 180 / Double.pi
        // Reflex when the next edge is to the right of the previous one.
        if a.cross(b) < 0 { degrees = 360 - degrees }
        return degrees
    }

    func testOutOfSquareCornersAreRedAndSquareOnesAreNot() {
        // Quadrilateral from the foundation tests: the corners at (5,0) and (5,4) stay 90, the far-left two skew.
        let room = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-0.21, 4)])
        let p = room.outline
        let angles = p.indices.map { interior(p, $0) }
        let expectedBad = Set(p.indices.filter { abs(angles[$0] - 90) > 1 })
        XCTAssertFalse(expectedBad.isEmpty)

        let d = plan(room)
        let red = PlanDrawingBuilder.Palette.warning
        let redArcs = d.arcs(.angles).filter { $0.style.color == red }
        guard redArcs.count == expectedBad.count else { return XCTFail("expected expectedBad.count, got \(redArcs.count)") }
        for i in expectedBad {
            let arc = redArcs.first { $0.center.distance(to: p[i]) < 1e-9 }
            XCTAssertNotNil(arc, "red arc at corner \(i)")
            // Sweep equals the interior angle.
            if let arc {
                var sweep = arc.end - arc.start
                if sweep < 0 { sweep += 360 }
                XCTAssertEqual(sweep, angles[i], accuracy: 1e-6)
            }
        }
        // Text per red corner, in the warning colour, showing the angle with one decimal.
        let redTexts = d.texts(.angles).filter { $0.color == red }
        guard redTexts.count == expectedBad.count else { return XCTFail("expected expectedBad.count, got \(redTexts.count)") }
        for i in expectedBad {
            XCTAssertTrue(redTexts.contains { $0.string == UnitFormatter.angle(angles[i]) }, "text for corner \(i)")
        }
        // Corners that are not out of square have no red.
        guard d.polylines(.angles).count == p.count - expectedBad.count else { return XCTFail("the square corners show the right-angle mark: expected p.count - expectedBad.count, got \(d.polylines(.angles).count)") }
        // Each number sits inside the room.
        for t in redTexts { XCTAssertTrue(Polygon.contains(room.outline, t.at)) }
    }

    /// A pentagon with interior angles of 90, 90, 90, `interiorAtP3` and `180 - (interiorAtP3 - 90)`
    /// (the last is a near-straight corner on the left wall), walking counter-clockwise.
    private func pentagon(interiorAtP3 a: Double) -> Room {
        let turn = 180 - a                       // left turn at P3
        let direction = (180 + turn) * Double.pi / 180
        let l3 = 2.5
        let p3x = 0 - l3 * cos(direction)       // so that P4 lands on x = 0
        let p3 = Point2(p3x, 4)
        let p4 = p3 + Point2(cos(direction), sin(direction)) * l3
        XCTAssertEqual(p4.x, 0, accuracy: 1e-9)
        return Room.polygon(name: "Pent", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), p3, p4])
    }

    func testCornerWithinHalfADegreeOfSquareIsAMarkNotNumbers() {
        let room = pentagon(interiorAtP3: 90.4)
        let angles = room.outline.indices.map { interior(room.outline, $0) }
        XCTAssertEqual(angles[3], 90.4, accuracy: 1e-6)
        XCTAssertEqual(angles[4], 179.6, accuracy: 1e-6)
        let d = plan(room)
        XCTAssertTrue(d.texts(.angles).isEmpty)
        XCTAssertTrue(d.arcs(.angles).isEmpty)
        guard d.polylines(.angles).count == 4 else { return XCTFail("four right-angle marks; the 179.6 corner is straight: expected 4, got \(d.polylines(.angles).count)") }
    }

    func testSlightlyOffSquareCornerShowsItsAngleInMutedInkNotRed() {
        // 90.7 degrees: more than 0.5 from square (so a number) but within the 1 degree tolerance (so not red).
        let room = pentagon(interiorAtP3: 90.7)
        let angles = room.outline.indices.map { interior(room.outline, $0) }
        XCTAssertEqual(angles[3], 90.7, accuracy: 1e-6)
        XCTAssertTrue(room.metrics.outOfSquareCorners.isEmpty)
        let d = plan(room)
        let texts = d.texts(.angles)
        XCTAssertEqual(texts.map(\.string), ["90.7\u{00B0}"])
        XCTAssertEqual(texts[0].color, PlanDrawingBuilder.Palette.muted)
        XCTAssertFalse(texts[0].bold)
        XCTAssertTrue(d.arcs(.angles).allSatisfy { $0.style.color == PlanDrawingBuilder.Palette.muted })
        guard d.arcs(.angles).count == 1 else { return XCTFail("expected 1, got \(d.arcs(.angles).count)") }
    }

    func testReflexCornerOfAnLShapeShowsItsAngleAboveOneEighty() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        let d = plan(l)
        let texts = d.texts(.angles)
        XCTAssertEqual(texts.map(\.string), ["270.0\u{00B0}"])
        XCTAssertEqual(texts[0].color, PlanDrawingBuilder.Palette.muted, "reflex corners of an L are expected, not warnings")
        guard d.polylines(.angles).count == 5 else { return XCTFail("five right-angle marks: expected 5, got \(d.polylines(.angles).count)") }
        let arc = d.arcs(.angles)[0]
        assertPoint(arc.center, 4, 2)
        // Interior is the 270 degree wedge from the wall going north (90 degrees) round through west,
        // south and east to the wall coming in from the east (0 degrees).
        XCTAssertEqual(arc.start, 90, accuracy: 1e-9)
        XCTAssertEqual(arc.end, 0, accuracy: 1e-9)
        XCTAssertTrue(Polygon.contains(l.outline, texts[0].at), "the number is inside the room, not in the notch")
    }

    func testStraightContinuationCornersAreNotAnnotated() {
        let split = Room.polygon(name: "Split", corners: [Point2(0, 0), Point2(3, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)])
        let d = plan(split)
        guard d.polylines(.angles).count == 4 else { return XCTFail("corner at (3,0) is straight: expected 4, got \(d.polylines(.angles).count)") }
        XCTAssertTrue(d.texts(.angles).isEmpty)
    }

    // MARK: Room labels

    func testRoomLabelHasNameAreaAndCeilingInsideTheRoom() {
        let room = Room.rectangle(name: "Living Room", kind: .livingRoom, width: 6.2, depth: 4.5)
        let d = plan(room)
        let labels = d.texts(.roomLabels)
        XCTAssertEqual(labels.map(\.string), ["Living Room", "27.9 m\u{00B2}", "Ceiling 2800 mm"])
        XCTAssertTrue(labels[0].bold)
        XCTAssertFalse(labels[1].bold)
        XCTAssertEqual(labels[0].height, 0.15, accuracy: 1e-9, "3.0 mm at 1:50")
        XCTAssertEqual(labels[1].height, 0.11, accuracy: 1e-9, "2.2 mm at 1:50")
        // Centred on the room, in a column.
        for l in labels {
            XCTAssertEqual(l.anchor, .center)
            XCTAssertEqual(l.at.x, 3.1, accuracy: 0.8)
            XCTAssertTrue(Polygon.contains(room.outline, l.at))
        }
        XCTAssertGreaterThan(labels[0].at.y, labels[1].at.y)
        XCTAssertGreaterThan(labels[1].at.y, labels[2].at.y)
    }

    func testRoomLabelAreaUsesTheChosenAreaUnitAndVerifiedLengthsFlowIntoIt() {
        var room = Room.rectangle(name: "Bed", kind: .bedroom, width: 4, depth: 3)
        room.walls[0].length.verify(4.04); room.walls[2].length.verify(4.04)
        room.ceilingHeight.verify(2.75)
        var o = PlanOptions(); o.units = DisplayUnits(length: .metres, area: .squareFeet)
        let labels = plan(room, o).texts(.roomLabels)
        // Effective area 4.04 x 3.00 = 12.12 m2 = 130.5 sq ft (12.12 / 0.09290304 = 130.46).
        XCTAssertEqual(labels[1].string, "130 sq ft")
        XCTAssertEqual(labels[2].string, "Ceiling 2.750 m v")
        XCTAssertEqual(labels[2].color, PlanDrawingBuilder.Palette.verified)
    }

    func testRoomLabelFallsBackToTheKindNameAndCanBeSwitchedOff() {
        let room = Room.rectangle(name: "  ", kind: .bathroom, width: 3, depth: 2.5)
        XCTAssertEqual(plan(room).texts(.roomLabels).first?.string, "Bathroom")
        var o = PlanOptions(); o.showRoomLabels = false
        XCTAssertTrue(plan(room, o).items(.roomLabels).isEmpty)
    }

    /// The text box of each label line must lie inside the polygon: all four corners inside.
    private func assertLabelsInside(_ d: PlanDrawing, _ outline: [Point2], file: StaticString = #filePath, line: UInt = #line) {
        for t in d.texts(.roomLabels) {
            let w = PlanDrawingBuilder.textWidth(t.string, height: t.height, bold: t.bold)
            for dx in [-w / 2, w / 2] {
                for dy in [0.0, t.height] {
                    XCTAssertTrue(Polygon.contains(outline, Point2(t.at.x + dx, t.at.y + dy)),
                                  "\(t.string) corner outside the room", file: file, line: line)
                }
            }
        }
    }

    func testLabelOfAnLShapeIsInsideThePolygon() {
        let l = Room.polygon(name: "L Room", corners: [Point2(0, 0), Point2(8, 0), Point2(8, 2.5), Point2(3, 2.5), Point2(3, 7), Point2(0, 7)])
        assertLabelsInside(plan(l), l.outline)
    }

    func testLabelOfACShapeWhoseCentroidIsOutsideIsStillInside() {
        // C opening to the east: the centroid (2.375, 3) is in the void.
        let c = Room.polygon(name: "C Room", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 1), Point2(1, 1),
                                                       Point2(1, 5), Point2(6, 5), Point2(6, 6), Point2(0, 6)])
        XCTAssertFalse(Polygon.contains(c.outline, Polygon.centroid(c.outline)), "precondition: centroid outside")
        let d = plan(c)
        XCTAssertEqual(d.texts(.roomLabels).first?.string, "C Room")
        assertLabelsInside(d, c.outline)
    }

    func testLargestInscribedRectangleOfRectangleAndLShape() {
        let rect = [Point2(0, 0), Point2(5, 0), Point2(5, 3), Point2(0, 3)]
        let r = PlanDrawingBuilder.largestInscribedRectangle(of: rect)!
        XCTAssertEqual(r.width, 5, accuracy: 1e-6)
        XCTAssertEqual(r.height, 3, accuracy: 1e-6)
        XCTAssertEqual(r.centre.x, 2.5, accuracy: 1e-6)
        XCTAssertEqual(r.centre.y, 1.5, accuracy: 1e-6)

        // 6x4 L-shape with the top-right 2x2 removed: the biggest rectangle is the 4x4 left block
        // (area 16) or the 6x2 bottom strip (area 12): the answer is the 4x4 block, within a grid cell.
        let l = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        let lr = PlanDrawingBuilder.largestInscribedRectangle(of: l)!
        XCTAssertGreaterThan(lr.width * lr.height, 15)
        XCTAssertLessThanOrEqual(lr.width * lr.height, 16 + 1e-6)
        for corner in [Point2(-1, -1), Point2(1, -1), Point2(1, 1), Point2(-1, 1)] {
            XCTAssertTrue(Polygon.contains(l, lr.centre + Point2(corner.x * lr.width / 2 * 0.999, corner.y * lr.height / 2 * 0.999)))
        }
        XCTAssertNil(PlanDrawingBuilder.largestInscribedRectangle(of: [Point2(0, 0), Point2(1, 0), Point2(2, 0)]))
    }

    func testRoomLabelAvoidsFurnitureWhenThereIsClearFloor() {
        var room = Room.rectangle(name: "Bedroom", kind: .bedroom, width: 6, depth: 5)
        // A big bed right over the centroid (3, 2.5).
        room.objects = [RoomObject(kind: .bed, center: Point2(3, 2.5), yaw: 0, width: 2.0, depth: 2.2, height: 0.5)]
        let d = plan(room)
        let name = d.texts(.roomLabels)[0]
        let w = PlanDrawingBuilder.textWidth(name.string, height: name.height, bold: true)
        let bed = Bounds2(min: Point2(2, 1.4), max: Point2(4, 3.6))
        let overlapsBed = name.at.x + w / 2 > bed.min.x && name.at.x - w / 2 < bed.max.x
            && name.at.y + name.height > bed.min.y && name.at.y < bed.max.y
        XCTAssertFalse(overlapsBed, "label moved off the bed")
        assertLabelsInside(d, room.outline)
    }

    func testLabelShrinksInATinyRoomRatherThanOverflowing() {
        let tiny = Room.rectangle(name: "Maid's Room Extension", kind: .maidsRoom, width: 1.6, depth: 1.4)
        let d = plan(tiny)
        let name = d.texts(.roomLabels)[0]
        XCTAssertLessThan(name.height, 0.15, "shrunk below the 3.0 mm size")
        XCTAssertGreaterThanOrEqual(name.height, 0.15 * 0.55 - 1e-9, "but not below 55 %")
    }

    // MARK: Opening tags

    func testOpeningTagsShowEffectiveSizesInTheChosenUnit() {
        let room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [
            .door(wall: 0, offset: 0.5, width: 0.9, height: 2.1),
            .window(wall: 2, offset: 1, width: 1.5, height: 1.4, sill: 0.9),
            OpeningSpec(wall: 1, kind: .opening, offset: 1, width: 1.2, height: 2.4),
        ])
        func tags(_ unit: LengthUnit) -> Set<String> {
            var o = PlanOptions(); o.units = DisplayUnits(length: unit, area: .squareMetres)
            let d = plan(room, o)
            return Set(d.texts(.doors).map(\.string) + d.texts(.windows).map(\.string) + d.texts(.openings).map(\.string))
        }
        XCTAssertEqual(tags(.millimetres), ["D 900x2100", "W 1500x1400 H900", "O 1200x2400"])
        XCTAssertEqual(tags(.centimetres), ["D 90x210 cm", "W 150x140 H90 cm", "O 120x240 cm"])
        XCTAssertEqual(tags(.metres), ["D 0.9x2.1 m", "W 1.5x1.4 H0.9 m", "O 1.2x2.4 m"])
        // 0.9 m = 35.433 in, 2.1 m = 82.677 in: two decimals in tags, so a checked size is good to 0.13 mm.
        XCTAssertEqual(tags(.inches), ["D 35.43x82.68 in", "W 59.06x55.12 H35.43 in", "O 47.24x94.49 in"])
        XCTAssertEqual(tags(.feetAndInches), tags(.inches), "feet-and-inches fall back to decimal inches in tags")
    }

    func testOpeningTagsMarkOnlyVerifiedNumbers() {
        var room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [
            .door(wall: 0, offset: 0.5), .door(wall: 2, offset: 0.5), .window(wall: 1, offset: 1, width: 1.5, height: 1.4, sill: 0.9)])
        // Door 1: width verified only. Door 2: width and height verified. Window: nothing verified.
        room.openings[0].width.verify(0.915)
        room.openings[1].width.verify(0.92); room.openings[1].height.verify(2.11)
        let d = plan(room)
        let door = Set(d.texts(.doors).map(\.string))
        XCTAssertEqual(door, ["D 915v x 2100", "D 920x2110 v"])
        XCTAssertEqual(d.texts(.windows).map(\.string), ["W 1500x1400 H900"], "scanned values carry no mark")

        var off = PlanOptions(); off.markVerified = false
        XCTAssertEqual(Set(plan(room, off).texts(.doors).map(\.string)), ["D 915x2100", "D 920x2110"])
    }

    func testOpeningTagSitsInsideTheWallStripAndCanBeSwitchedOff() {
        let room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.window(wall: 0, offset: 1, width: 2, height: 1.4, sill: 0.9)])
        let d = plan(room)
        let tag = d.texts(.windows)[0]
        XCTAssertEqual(tag.at.x, 2.0, accuracy: 1e-9, "centred on the window (x = 1..3)")
        XCTAssertGreaterThan(tag.at.y, 0)
        XCTAssertLessThan(tag.at.y, 0.25, "between the wall and the dimension line")
        XCTAssertEqual(tag.rotation, 0, accuracy: 1e-9)
        var o = PlanOptions(); o.showOpeningSizes = false
        XCTAssertTrue(plan(room, o).texts(.windows).isEmpty)
    }

    // MARK: Scale, bounds, determinism

    func testTextHeightsComeFromPaperMillimetresAndTheScale() {
        let room = Room.rectangle(name: "R", width: 10, depth: 8)
        for scale in [20.0, 50, 100, 200] {
            var o = PlanOptions(); o.scale = scale
            let d = plan(room, o)
            XCTAssertEqual(d.texts(.dimensions)[0].height, 2.0 * scale / 1000, accuracy: 1e-12, "1:\(scale)")
            XCTAssertEqual(d.texts(.roomLabels)[0].height, 3.0 * scale / 1000, accuracy: 1e-9)
        }
        // 2.5 mm at 1:50 is the contract's 0.125 m example; our dimension text is 2.0 mm = 0.1 m.
        var o = PlanOptions(); o.scale = 50
        XCTAssertEqual(plan(room, o).texts(.dimensions)[0].height, 0.1, accuracy: 1e-12)
    }

    func testTextWidthEstimateFollowsHelveticaMetricsWithTwoPercentAllowance() {
        // "6200 mm" is 4168 units of 1000 per em; a 0.1 m cap height means a font size of 0.1 / 0.718 m.
        let expected = 4.168 * (0.1 / 0.718) * 1.02
        XCTAssertEqual(PlanDrawingBuilder.textWidth("6200 mm", height: 0.1), expected, accuracy: 1e-9)
        XCTAssertEqual(expected, 0.5922, accuracy: 1e-4)
        // Bold is wider: "Kitchen" 722+278+333+... ; just check it is strictly wider and scales linearly with height.
        XCTAssertGreaterThan(PlanDrawingBuilder.textWidth("Kitchen", height: 0.1, bold: true),
                             PlanDrawingBuilder.textWidth("Kitchen", height: 0.1))
        XCTAssertEqual(PlanDrawingBuilder.textWidth("Kitchen", height: 0.2), 2 * PlanDrawingBuilder.textWidth("Kitchen", height: 0.1), accuracy: 1e-12)
        XCTAssertEqual(PlanDrawingBuilder.textWidth("", height: 0.1), 0)
        XCTAssertEqual(PlanDrawingBuilder.textWidth("x", height: 0), 0)
        XCTAssertEqual(PlanDrawingBuilder.textWidth("x", height: .nan), 0)
    }

    func testNonsenseScaleFallsBackToFifty() {
        let room = Room.rectangle(name: "R", width: 4, depth: 3)
        for bad in [0.0, -10, .nan, .infinity] {
            var o = PlanOptions(); o.scale = bad
            let d = plan(room, o)
            XCTAssertEqual(d.texts(.dimensions)[0].height, 0.1, accuracy: 1e-12)
            XCTAssertTrue(d.bounds.width.isFinite)
        }
    }

    func testBoundsOfAWallsOnlyRoomAreTheOuterWallCorners() {
        let d = plan(Room.rectangle(name: "R", width: 4, depth: 3), wallsOnly)
        assertPoint(d.bounds.min, -0.12, -0.12)
        assertPoint(d.bounds.max, 4.12, 3.12)
    }

    func testBoundsCoverEveryPointAndEveryTextBox() {
        let rooms = PlanPDFFixture.demoRooms()
        let d = PlanDrawingBuilder.build(rooms: rooms, title: "", subtitle: "", options: PlanOptions())
        let eps = 1e-9
        for item in d.primitives {
            switch item.primitive {
            case let .line(a, b, _):
                for p in [a, b] { XCTAssertTrue(p.x >= d.bounds.min.x - eps && p.x <= d.bounds.max.x + eps && p.y >= d.bounds.min.y - eps && p.y <= d.bounds.max.y + eps) }
            case let .polyline(pts, _, _, _):
                for p in pts { XCTAssertTrue(p.x >= d.bounds.min.x - eps && p.x <= d.bounds.max.x + eps && p.y >= d.bounds.min.y - eps && p.y <= d.bounds.max.y + eps) }
            case let .arc(c, r, _, _, _):
                // An arc never leaves its circle's bounding square.
                XCTAssertTrue(c.x - r <= d.bounds.max.x + eps && c.x + r >= d.bounds.min.x - eps)
            case let .text(s, at, h, rot, anchor, _, bold):
                // Text boxes: width from the shared estimate, rotations in this fixture are 0 or 90 degrees.
                let w = PlanDrawingBuilder.textWidth(s, height: h, bold: bold)
                let left: Double = anchor == .left ? 0 : (anchor == .center ? -w / 2 : -w)
                if abs(rot) < 1e-9 {
                    XCTAssertGreaterThanOrEqual(at.x + left, d.bounds.min.x - eps, s)
                    XCTAssertLessThanOrEqual(at.x + left + w, d.bounds.max.x + eps, s)
                    XCTAssertLessThanOrEqual(at.y + h, d.bounds.max.y + eps, s)
                } else if abs(rot - 90) < 1e-9 {
                    XCTAssertGreaterThanOrEqual(at.y + left, d.bounds.min.y - eps, s)
                    XCTAssertLessThanOrEqual(at.y + left + w, d.bounds.max.y + eps, s)
                    XCTAssertGreaterThanOrEqual(at.x - h, d.bounds.min.x - eps, s)
                }
            case .circle:
                break
            }
        }
    }

    func testBoundsGrowToHoldTextWiderThanItsWall() {
        // At 1:100 a 2 mm dimension is 0.2 m tall and "450 mm" is 1.1 m long, far wider than the 0.45 m end
        // wall it belongs to, so the bounds must stretch well past the wall band to hold it.
        let room = Room.rectangle(name: "Slot", width: 3, depth: 0.45)
        let d = plan(room, PlanOptions(scale: 100, showAngles: false, showFurniture: false, showRoomLabels: false,
                                       showOpeningSizes: false))
        let texts = d.texts(.dimensions)
        guard let end = texts.first(where: { $0.string == "450 mm" }) else {
            return XCTFail("no 450 mm dimension: \(texts.map(\.string))")
        }
        XCTAssertGreaterThan(PlanDrawingBuilder.textWidth(end.string, height: end.height), 0.45 + 0.5)
        var overhang = 0.0
        for t in texts {
            for c in PlanDrawingBuilder.textCorners(t.string, at: t.at, height: t.height, rotation: t.rotation,
                                                    anchor: t.anchor, bold: t.bold) {
                XCTAssertGreaterThanOrEqual(c.x, d.bounds.min.x - 1e-9); XCTAssertLessThanOrEqual(c.x, d.bounds.max.x + 1e-9)
                XCTAssertGreaterThanOrEqual(c.y, d.bounds.min.y - 1e-9); XCTAssertLessThanOrEqual(c.y, d.bounds.max.y + 1e-9)
                overhang = max(overhang, -0.12 - c.y, c.y - 0.57)
            }
        }
        XCTAssertGreaterThan(overhang, 0.15, "some text reaches well past the wall bands")
        // Hand check: cap 0.2 m gives a 0.2786 m font; "450 mm" is 3.612 em = 1.0062 m, +2 % = 1.0263 m, centred
        // on the wall's middle (y = 0.225): its lower end is at 0.225 - 0.5132 = -0.2881.
        XCTAssertEqual(d.bounds.min.y, 0.225 - 0.5132, accuracy: 1e-3)
    }

    func testALabelWiderThanTheRoomIsCutShortInsteadOfSpillingAcrossTheNeighbours() {
        // A 0.8 m wide room with a long name: at the smallest size the name still does not fit, so it is
        // shortened with an ellipsis and stays inside the room.
        let room = Room.rectangle(name: "An Extremely Long Room Name", width: 0.8, depth: 3)
        let d = plan(room)
        let name = d.texts(.roomLabels)[0]
        XCTAssertTrue(name.string.hasSuffix("..."), name.string)
        XCTAssertTrue(name.string.count < "An Extremely Long Room Name".count)
        XCTAssertTrue("An Extremely Long Room Name".hasPrefix(String(name.string.dropLast(3))))
        let w = PlanDrawingBuilder.textWidth(name.string, height: name.height, bold: true)
        XCTAssertGreaterThanOrEqual(name.at.x - w / 2, 0, "inside the room's west wall")
        XCTAssertLessThanOrEqual(name.at.x + w / 2, 0.8, "inside the room's east wall")
        // A name that fits is left alone.
        XCTAssertEqual(plan(Room.rectangle(name: "Kitchen", width: 4, depth: 3)).texts(.roomLabels)[0].string, "Kitchen")
    }

    func testBuildIsDeterministic() {
        let rooms = PlanPDFFixture.demoRooms()
        let a = PlanDrawingBuilder.build(rooms: rooms, title: "x", subtitle: "y", options: PlanOptions())
        let b = PlanDrawingBuilder.build(rooms: rooms, title: "x", subtitle: "y", options: PlanOptions())
        XCTAssertEqual(a.primitives, b.primitives)
        XCTAssertEqual(a.bounds, b.bounds)
    }

    func testLayersAreUsedForTheirOwnContent() {
        let d = PlanDrawingBuilder.build(rooms: PlanPDFFixture.demoRooms(), title: "", subtitle: "", options: PlanOptions())
        for item in d.primitives {
            switch item.layer {
            case .walls:
                guard case .polyline = item.primitive else { return XCTFail("walls are polygons") }
            case .wallsOpen:
                guard case let .line(_, _, s) = item.primitive, s.dashed else { return XCTFail("open walls are dashed lines") }
            case .doors:
                switch item.primitive {
                case .line, .arc, .text: break
                default: XCTFail("doors: leaf, swing, tag")
                }
            case .windows:
                switch item.primitive {
                case .line, .text: break
                default: XCTFail("windows: lines, tag")
                }
            case .furniture:
                switch item.primitive {
                case .polyline, .text: break
                default: XCTFail("furniture: footprint, label")
                }
            case .roomLabels:
                guard case .text = item.primitive else { return XCTFail("labels are text") }
            case .dimensions, .angles, .openings, .notes:
                break
            }
        }
        XCTAssertFalse(d.items(.dimensions).isEmpty)
        XCTAssertFalse(d.items(.windows).isEmpty)
        XCTAssertTrue(d.items(.notes).isEmpty)
    }

    func testPaintingOrderPutsFurnitureBelowWallsAndLabelsOnTop() {
        let d = PlanDrawingBuilder.build(rooms: PlanPDFFixture.demoRooms(), title: "", subtitle: "", options: PlanOptions())
        let layers = d.primitives.map(\.layer)
        let lastFurniture = layers.lastIndex(of: .furniture)!
        let firstWall = layers.firstIndex(of: .walls)!
        let lastWall = layers.lastIndex(of: .walls)!
        let firstDoor = layers.firstIndex(of: .doors)!
        let firstLabel = layers.firstIndex(of: .roomLabels)!
        XCTAssertLessThan(lastFurniture, firstWall)
        XCTAssertLessThan(lastWall, firstDoor)
        XCTAssertLessThan(layers.lastIndex(of: .dimensions)!, firstLabel)
    }

    // MARK: Entry points

    func testFloorAndRoomEntryPointsSetTitleAndSubtitle() {
        let property = PlanPDFFixture.demoProperty()
        let floor = property.floors[0]
        let withProperty = PlanDrawingBuilder.build(floor: floor, property: property, options: PlanOptions())
        XCTAssertEqual(withProperty.title, "Marina Gate 2304")
        XCTAssertEqual(withProperty.subtitle, "Level 23")
        let without = PlanDrawingBuilder.build(floor: floor, property: nil, options: PlanOptions())
        XCTAssertEqual(without.title, "Level 23")
        XCTAssertEqual(without.subtitle, "")
        XCTAssertEqual(withProperty.primitives, without.primitives)

        let single = PlanDrawingBuilder.build(room: floor.rooms[0], options: PlanOptions())
        XCTAssertEqual(single.title, "Living Room")
        XCTAssertEqual(single.subtitle, "Living Room")   // RoomKind.livingRoom.displayName
        XCTAssertLessThan(single.primitives.count, withProperty.primitives.count)
    }

    func testOptionsAreCarriedOnTheDrawing() {
        var o = PlanOptions(); o.scale = 75; o.markVerified = false
        let d = PlanDrawingBuilder.build(rooms: [], title: "", subtitle: "", options: o)
        XCTAssertEqual(d.options, o)
    }

    // MARK: Robustness

    func testFuzzedRoomsNeverProduceNonFiniteNumbers() {
        var rng = LCG(state: 0xC0FFEE)
        for trial in 0..<150 {
            let n = 3 + Int(rng.next() * 7)
            var pts: [Point2] = []
            for _ in 0..<n { pts.append(Point2(rng.range(-8, 8), rng.range(-8, 8))) }
            if trial % 10 == 0 { pts.append(pts[0]) }                                  // repeated vertex
            if trial % 13 == 0 { pts[pts.count / 2] = pts[pts.count / 2 - 1] }          // zero-length wall
            var specs: [OpeningSpec] = []
            for _ in 0..<Int(rng.next() * 4) {
                let kind: OpeningKind = [.door, .window, .opening][Int(rng.next() * 3)]
                specs.append(OpeningSpec(wall: Int(rng.next() * Double(pts.count)), kind: kind,
                                         offset: rng.range(-2, 6), width: rng.range(-0.5, 5), height: 2))
            }
            var room = Room.polygon(name: "Fuzz \(trial)", corners: pts, openings: specs)
            room.objects = [RoomObject(kind: .storage, center: Point2(rng.range(-5, 5), rng.range(-5, 5)),
                                       yaw: rng.range(-7, 7), width: rng.range(0, 3), depth: rng.range(0, 3), height: 1)]
            var o = PlanOptions()
            o.scale = [20.0, 50, 100, 500][trial % 4]
            let d = PlanDrawingBuilder.build(rooms: [room], title: "", subtitle: "", options: o)
            for item in d.primitives {
                XCTAssertTrue(numbers(of: item.primitive).allSatisfy(\.isFinite), "trial \(trial): \(item.primitive)")
            }
            XCTAssertTrue(d.bounds.min.x.isFinite && d.bounds.max.x.isFinite && d.bounds.min.y.isFinite && d.bounds.max.y.isFinite)
            XCTAssertGreaterThan(d.bounds.width, 0)
            for t in d.texts(.dimensions) {
                XCTAssertGreaterThan(t.rotation, -90)
                XCTAssertLessThanOrEqual(t.rotation, 90)
            }
        }
    }

    func testNonFiniteMeasuredValuesPrintNothingInsteadOfNaN() {
        var room = Room.rectangle(name: "R", width: 4, depth: 3, openings: [.door(wall: 0, offset: 1), .window(wall: 2, offset: 1, width: 1.5)])
        room.walls[0].length = Measured(scanned: .nan)
        room.ceilingHeight = Measured(scanned: .infinity)
        room.openings[0].width = Measured(scanned: 0.9, verification: Verification(value: .nan))
        room.openings[1].sillHeight = Measured(scanned: .nan)
        let d = plan(room)
        for t in d.allTexts() {
            XCTAssertFalse(t.string.lowercased().contains("nan"), t.string)
            XCTAssertFalse(t.string.lowercased().contains("inf"), t.string)
        }
        guard d.texts(.dimensions).count == 3 else { return XCTFail("the wall with no usable length gets its line but no text: expected 3, got \(d.texts(.dimensions).count)") }
        guard d.texts(.roomLabels).count == 2 else { return XCTFail("no ceiling line: expected 2, got \(d.texts(.roomLabels).count)") }
        XCTAssertEqual(d.texts(.doors).count, 0, "no tag for a door with no usable width")
        XCTAssertEqual(d.texts(.windows).map(\.string), ["W 1500x1400"], "window sill with no value is left out of the tag")
    }

    func testHugeRoomStaysFinite() {
        let room = Room.rectangle(name: "Warehouse", width: 5000, depth: 3000)
        let d = plan(room)
        XCTAssertTrue(d.bounds.width.isFinite)
        XCTAssertGreaterThan(d.bounds.width, 5000)
        XCTAssertTrue(d.primitives.allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
    }

    func testVeryAcuteCornerKeepsTheMitreFromShootingOff() {
        // A thin wedge: 10 degrees at the tip (0,0). An unlimited mitre would reach 0.12 / sin(5 deg) = 1.38 m
        // from the tip; the limit is three times the wall thickness, 0.36 m.
        let wedge = Room.polygon(name: "Wedge", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 1.05)])
        let d = plan(wedge, wallsOnly)
        let nearTip = d.polylines(.walls).flatMap(\.points).filter { $0.distance(to: .zero) < 1.0 }
        XCTAssertFalse(nearTip.isEmpty)
        for p in nearTip { XCTAssertLessThanOrEqual(p.distance(to: .zero), 0.36 + 1e-9, "no spike: \(p)") }
        XCTAssertTrue(nearTip.contains { abs($0.distance(to: .zero) - 0.36) < 1e-9 }, "the limit is actually applied")
    }
}

// MARK: - Text that must not overprint other text

/// The rectangle each text primitive really occupies, worked out here from the AFM widths and the
/// cap height (not from the builder's own estimate): baseline to cap height, and down to the
/// descender only when the string has letters that hang below the baseline.
private func trueTextBoxes(_ d: PlanDrawing) -> [(string: String, corners: [Point2])] {
    d.primitives.compactMap { item -> (String, [Point2])? in
        guard case let .text(string, at, height, rotation, anchor, _, bold) = item.primitive else { return nil }
        let fontSize = height / 0.718
        let width = HelveticaMetrics.width(of: string, bold: bold, fontSize: fontSize)
        let left: Double
        switch anchor {
        case .left: left = 0
        case .center: left = -width / 2
        case .right: left = -width
        }
        let hangs = string.contains { "gjpqy,;()[]{}|/_@Q$".contains($0) }
        let bottom = hangs ? -0.207 * fontSize : 0
        let r = rotation * Double.pi / 180
        let u = Point2(cos(r), sin(r)), v = Point2(-sin(r), cos(r))
        func p(_ x: Double, _ y: Double) -> Point2 { at + u * x + v * y }
        return (string, [p(left, bottom), p(left + width, bottom), p(left + width, height), p(left, height)])
    }
}

/// Pairs of text lines whose rectangles overlap with positive area (separating-axis test).
private func overprintedPairs(_ d: PlanDrawing) -> [(String, String)] {
    let boxes = trueTextBoxes(d)
    func overlap(_ p: [Point2], _ q: [Point2]) -> Bool {
        for poly in [p, q] {
            for i in 0..<poly.count {
                let e = poly[(i + 1) % poly.count] - poly[i]
                let n = Point2(-e.y, e.x)
                let pr = p.map { $0.dot(n) }, qr = q.map { $0.dot(n) }
                if pr.max()! <= qr.min()! + 1e-9 || qr.max()! <= pr.min()! + 1e-9 { return false }
            }
        }
        return true
    }
    var pairs: [(String, String)] = []
    for i in boxes.indices {
        for j in boxes.indices where j > i && overlap(boxes[i].corners, boxes[j].corners) {
            pairs.append((boxes[i].string, boxes[j].string))
        }
    }
    return pairs
}

private func describe(_ pairs: [(String, String)]) -> String { pairs.map { "\($0.0) / \($0.1)" }.joined(separator: "; ") }

/// A grid of identical rooms 0.15 m apart.
private func roomGrid(columns: Int, rows: Int, width: Double = 4.0, depth: Double = 3.5, kind: RoomKind = .bedroom,
                      withDoor: Bool = true) -> [Room] {
    var rooms: [Room] = []
    for row in 0..<rows {
        for col in 0..<columns {
            rooms.append(Room.rectangle(name: "R\(row)\(col)", kind: kind,
                                        origin: Point2(Double(col) * (width + 0.15), Double(row) * (depth + 0.15)),
                                        width: width, depth: depth,
                                        openings: withDoor ? [.door(wall: 0, offset: 0.5)] : []))
        }
    }
    return rooms
}

/// The spatial index behind overprint checks and label placement.
final class BoxIndexTests: XCTestCase {

    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> (Bounds2, [Point2]) {
        (Bounds2(min: Point2(x, y), max: Point2(x + w, y + h)),
         [Point2(x, y), Point2(x + w, y), Point2(x + w, y + h), Point2(x, y + h)])
    }

    /// A w x h rectangle centred on (cx, cy), turned by `degrees`.
    private func turned(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, degrees: Double) -> [Point2] {
        let r = degrees * Double.pi / 180
        let u = Point2(cos(r), sin(r)), v = Point2(-sin(r), cos(r))
        let c = Point2(cx, cy)
        return [c - u * (w / 2) - v * (h / 2), c + u * (w / 2) - v * (h / 2), c + u * (w / 2) + v * (h / 2), c - u * (w / 2) + v * (h / 2)]
    }

    func testSeparatingAxisTestCountsOverlapButNotTouching() {
        let a = box(0, 0, 2, 1).1
        XCTAssertTrue(BoxIndex.convexOverlap(a, box(1.9, 0.5, 2, 1).1), "a corner of overlap")
        XCTAssertFalse(BoxIndex.convexOverlap(a, box(2, 0, 2, 1).1), "edges that only touch")
        XCTAssertFalse(BoxIndex.convexOverlap(a, box(2.001, 0, 2, 1).1), "a hair apart")
        XCTAssertTrue(BoxIndex.convexOverlap(a, box(0.5, 0.25, 0.5, 0.5).1), "one inside the other")
        XCTAssertTrue(BoxIndex.convexOverlap(box(0.5, 0.25, 0.5, 0.5).1, a), "and the other way round")
        // Turned boxes: a long thin box at 45 degrees whose bounding box overlaps a neighbour that it clears.
        let diagonal = turned(0, 0, 4, 0.2, degrees: 45)
        XCTAssertFalse(BoxIndex.convexOverlap(diagonal, box(1.0, -1.6, 0.5, 0.5).1),
                       "the bounding boxes overlap but the rotated rectangle does not reach")
        XCTAssertTrue(BoxIndex.convexOverlap(diagonal, box(1.0, 0.8, 0.5, 0.5).1), "this one sits on the diagonal")
        XCTAssertTrue(BoxIndex.convexOverlap(diagonal, turned(0, 0, 4, 0.2, degrees: -45)), "a cross")
        XCTAssertFalse(BoxIndex.convexOverlap(turned(0, 0, 4, 0.2, degrees: 45), turned(0, 0.8, 4, 0.2, degrees: 45)), "parallel, 0.8 m apart")
    }

    func testIndexFindsOverlapsAmongManyBoxesAndOnlyThose() {
        var index = BoxIndex()
        // A 30 x 30 lattice of 0.6 x 0.3 boxes on a 1 m pitch, inserted far from the origin and across cell borders.
        for i in 0..<30 {
            for j in 0..<30 {
                let b = box(Double(i) - 10.3, Double(j) - 10.2, 0.6, 0.3)
                index.insert(b.0, quad: b.1)
            }
        }
        XCTAssertEqual(index.bounds.count, 900)
        XCTAssertTrue(index.overlaps(quad: box(-10.1, -10.1, 0.2, 0.2).1), "inside the first box")
        XCTAssertTrue(index.overlaps(quad: box(5.8, 5.0, 0.2, 0.2).1), "inside the box at x 5.7-6.3, y 4.8-5.1")
        XCTAssertFalse(index.overlaps(quad: box(-9.6, -10.1, 0.2, 0.2).1), "in the gap between two boxes")
        XCTAssertFalse(index.overlaps(quad: box(100, 100, 1, 1).1), "far away")
        XCTAssertFalse(index.overlaps(quad: box(-10.3 + 0.6, -10.2, 0.4, 0.3).1), "touching the first box's edge only")
        // Brute force agrees on 400 random probes.
        var rng = LCG(state: 11)
        for _ in 0..<400 {
            let p = box(rng.range(-12, 20), rng.range(-12, 20), rng.range(0.05, 1.5), rng.range(0.05, 1.5))
            var expected = false
            for i in 0..<30 { for j in 0..<30 where BoxIndex.convexOverlap(p.1, box(Double(i) - 10.3, Double(j) - 10.2, 0.6, 0.3).1) { expected = true } }
            XCTAssertEqual(index.overlaps(quad: p.1), expected)
        }
    }

    func testBoxesTooBigForTheGridAreStillFoundAndRectsComeBackInAStableOrder() {
        var index = BoxIndex()
        let huge = box(-1000, -1000, 2000, 2000)
        index.insert(huge.0, quad: huge.1)
        for i in 0..<5 { let b = box(Double(i) * 3, 0, 1, 1); index.insert(b.0, quad: b.1) }
        XCTAssertTrue(index.overlaps(quad: box(500, 500, 1, 1).1), "inside the huge box, a long way from the others")
        XCTAssertEqual(index.rects(intersecting: Bounds2(min: Point2(2.5, -1), max: Point2(7.5, 2))).count, 3, "huge, and the boxes at 3 and 6")
        let first = index.rects(intersecting: Bounds2(min: Point2(-5, -5), max: Point2(20, 5)))
        let second = index.rects(intersecting: Bounds2(min: Point2(-5, -5), max: Point2(20, 5)))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.min.x), first.map(\.min.x).sorted(), "sorted, so results never depend on insertion or hashing order")
        // Absurd coordinates must not trap the cell arithmetic.
        let far = box(1e30, -1e30, 1e25, 1e25)
        index.insert(far.0, quad: far.1)
        XCTAssertTrue(index.overlaps(quad: far.1))
        XCTAssertFalse(BoxIndex().overlaps(quad: far.1), "an empty index overlaps nothing")
        let absurd = box(1e300, -1e300, 1e290, 1e290)
        index.insert(absurd.0, quad: absurd.1)
        _ = index.overlaps(quad: absurd.1)      // the products overflow to infinity: no answer worth having, but no trap
    }
}

final class PlanLayoutTests: XCTestCase {

    private func build(_ rooms: [Room], scale: Double = 50, _ tweak: (inout PlanOptions) -> Void = { _ in }) -> PlanBuildResult {
        var o = PlanOptions(scale: scale)
        tweak(&o)
        return PlanDrawingBuilder.buildDetailed(rooms: rooms, title: "", subtitle: "", options: o)
    }

    // MARK: Overprinting

    func testSmallRoomsDoNotOverprintTheirOwnDimensionsAtTheCommonScales() {
        // A 2.4 x 1.6 m bathroom is where vanities are cut. Its label used to land on its own dimensions.
        let bath = Room.rectangle(name: "Bathroom", kind: .bathroom, width: 2.4, depth: 1.6,
                                  openings: [.door(wall: 0, offset: 0.4, width: 0.8)])
        for scale in [50.0, 75, 100, 150] {
            let r = build([bath], scale: scale)
            XCTAssertTrue(overprintedPairs(r.drawing).isEmpty, "1:\(Int(scale)): \(describe(overprintedPairs(r.drawing)))")
            XCTAssertTrue(r.drawing.allTexts().contains { $0.string == "Bathroom" }, "the name is never dropped (1:\(Int(scale)))")
        }
        // At 1:50 nothing needs to give way: the full label is there.
        let full = build([bath], scale: 50)
        XCTAssertEqual(full.drawing.texts(.roomLabels).count, 3)
        XCTAssertEqual(full.report.droppedRoomLabelLines, 0)
        XCTAssertEqual(full.report.omittedDimensionTexts, 0)
        XCTAssertTrue(full.report.isLegible)
    }

    func testTheDemoFlatNeverOverprintsTextAtAnyScale() {
        // The review counted 2 / 14 / 42 overlapping pairs at 1:75 / 1:100 / 1:150 on the demo flat.
        let rooms = PlanPDFFixture.demoRooms()
        for scale in [20.0, 25, 50, 75, 100, 150, 200] {
            let r = build(rooms, scale: scale)
            XCTAssertTrue(overprintedPairs(r.drawing).isEmpty, "1:\(Int(scale)): \(describe(overprintedPairs(r.drawing)))")
        }
        XCTAssertTrue(build(rooms, scale: 50).report.isLegible, "everything is printed at 1:50")
    }

    func testTwentyRoomsAtOneToOneFiftyAreDenseButNeverOverprinted() {
        let rooms = roomGrid(columns: 5, rows: 4)
        for scale in [50.0, 100, 150, 200] {
            let r = build(rooms, scale: scale)
            XCTAssertTrue(overprintedPairs(r.drawing).isEmpty, "1:\(Int(scale)): \(describe(overprintedPairs(r.drawing)))")
            XCTAssertEqual(r.drawing.allTexts().filter { $0.string.hasPrefix("R") }.count, 20, "every room keeps its name at 1:\(Int(scale))")
        }
        // 4.0 x 3.5 m rooms: all printed at 1:100; at 1:150 and 1:200 the dimensions give way and the report says so.
        XCTAssertTrue(build(rooms, scale: 100).report.isLegible)
        XCTAssertGreaterThan(build(rooms, scale: 150).report.omittedDimensionTexts, 0)
        XCTAssertGreaterThan(build(rooms, scale: 200).report.omittedDimensionTexts,
                             build(rooms, scale: 150).report.omittedDimensionTexts)
    }

    func testTheOutOfSquareAngleIsNeverCoveredByAnotherLabel() {
        // Bedroom 2 of the demo flat has a 92.5 degree corner. At 1:75 its number sat under the room name.
        for scale in [50.0, 75, 100, 150, 200] {
            let r = build(PlanPDFFixture.demoRooms(), scale: scale)
            let red = r.drawing.texts(.angles).filter { $0.color == PlanDrawingBuilder.Palette.warning }
            XCTAssertEqual(red.map(\.string), ["92.5\u{B0}"], "1:\(Int(scale))")
            let boxes = trueTextBoxes(r.drawing)
            let others = overprintedPairs(r.drawing).filter { $0.0 == "92.5\u{B0}" || $0.1 == "92.5\u{B0}" }
            XCTAssertTrue(others.isEmpty && boxes.count > 1, "1:\(Int(scale)): \(describe(others))")
        }
    }

    func testWhenTwoDimensionsCollideTheCheckedOneIsKept() {
        // 4 x 1.5 m at 1:150: the texts of the two long walls are 0.3 m tall and sit exactly on top of
        // each other. Scanned walls: the first wall's text wins. If the north wall is laser-checked, it wins.
        var room = Room.rectangle(name: "Strip", width: 4, depth: 1.5)
        let plain = build([room], scale: 150) { $0.showRoomLabels = false; $0.showAngles = false }
        XCTAssertEqual(plain.drawing.texts(.dimensions).filter { $0.string == "4000 mm" }.count, 1, "one of the two is left out")
        // A dimension left out takes its line and ticks with it: every dimension line has its number.
        let longLines = plain.drawing.lines(.dimensions).filter { $0.a.distance(to: $0.b) > 0.5 }
        XCTAssertEqual(longLines.count, plain.drawing.texts(.dimensions).count, "no bare dimension lines")
        XCTAssertEqual(plain.drawing.lines(.dimensions).count, 3 * plain.drawing.texts(.dimensions).count, "a line and two ticks each")
        XCTAssertGreaterThanOrEqual(plain.report.omittedDimensionTexts, 1)
        room.walls[2].length.verify(4.001)
        let checked = build([room], scale: 150) { $0.showRoomLabels = false; $0.showAngles = false }
        let strings = checked.drawing.texts(.dimensions).map(\.string)
        XCTAssertTrue(strings.contains("4001 mm v"), "\(strings)")
        XCTAssertFalse(strings.contains("4000 mm"), "the scanned wall gives way: \(strings)")
        XCTAssertTrue(overprintedPairs(checked.drawing).isEmpty)
    }

    func testRoomLabelsShedLinesBeforeTheyTouchTextAndKeepTheName() {
        // At 1:75 a 2.4 x 1.6 m bathroom is 32 x 21 mm on paper: name, area and ceiling cannot all sit clear
        // of its four dimensions, so the ceiling line goes. The dimensions themselves all print.
        let bath = Room.rectangle(name: "Bathroom", kind: .bathroom, width: 2.4, depth: 1.6)
        let r = build([bath], scale: 75)
        XCTAssertEqual(r.drawing.texts(.roomLabels).map(\.string), ["Bathroom", "3.8 m\u{B2}"])
        XCTAssertEqual(r.report.droppedRoomLabelLines, 1)
        XCTAssertEqual(r.report.roomLabelsWithOverlap, 0)
        XCTAssertEqual(r.report.omittedDimensionTexts, 0)
        XCTAssertTrue(overprintedPairs(r.drawing).isEmpty)
        // A roomy kitchen keeps all three lines at the same scale.
        let kitchen = Room.rectangle(name: "Kitchen", kind: .kitchen, width: 5, depth: 4)
        XCTAssertEqual(build([kitchen], scale: 75).drawing.texts(.roomLabels).count, 3)
        // Whatever the scale, the name is the last thing to go and the label never touches text.
        for scale in [50.0, 75, 100, 125, 150] {
            let lines = build([bath], scale: scale).drawing.texts(.roomLabels).map(\.string)
            XCTAssertEqual(lines.first, "Bathroom", "1:\(Int(scale))")
        }
    }

    func testOpeningTagsAndFurnitureNamesGiveWayToMoreImportantText() {
        // Two doors 1.2 m apart on one wall. At 1:150 a tag is 1.7 m long, so the two overlap and the second is
        // left out; at 1:50 (0.6 m long) both print.
        let hall = Room.rectangle(name: "Hall", width: 8, depth: 4,
                                  openings: [.door(wall: 0, offset: 1.0), .door(wall: 0, offset: 2.2)])
        let far = build([hall], scale: 150) { $0.showRoomLabels = false }
        XCTAssertEqual(far.drawing.texts(.doors).count, 1)
        XCTAssertEqual(far.report.omittedOpeningTags, 1)
        XCTAssertTrue(overprintedPairs(far.drawing).isEmpty, describe(overprintedPairs(far.drawing)))
        let near = build([hall], scale: 50) { $0.showRoomLabels = false }
        XCTAssertEqual(near.drawing.texts(.doors).count, 2)
        XCTAssertEqual(near.report.omittedOpeningTags, 0)

        // A table whose name would land on the dimension text of the south wall at 1:150 loses its name (the
        // footprint stays); at 1:50 the text is 0.6 m away and the name prints.
        var room = Room.rectangle(name: "R", width: 4, depth: 3)
        room.objects = [RoomObject(kind: .table, center: Point2(2.0, 0.95), yaw: 0, width: 1.5, depth: 0.4, height: 0.75)]
        let crowded = build([room], scale: 150) { $0.showRoomLabels = false }
        XCTAssertEqual(crowded.drawing.polylines(.furniture).count, 1)
        XCTAssertTrue(crowded.drawing.texts(.furniture).isEmpty)
        XCTAssertEqual(crowded.report.omittedFurnitureLabels, 1)
        let roomy = build([room], scale: 50) { $0.showRoomLabels = false }
        XCTAssertEqual(roomy.drawing.texts(.furniture).map(\.string), ["Table"])
        XCTAssertEqual(roomy.report.omittedFurnitureLabels, 0)
    }

    func testLayoutIsLinearEnoughForABigFloor() {
        // The label placement used to scan every primitive for every room (quadratic): 500 rooms took
        // 22.8 s in a debug build. 500 rooms must now take a small fraction of that.
        let rooms = roomGrid(columns: 25, rows: 20)
        XCTAssertEqual(rooms.count, 500)
        let start = Date()
        let r = build(rooms, scale: 100)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(r.drawing.texts(.roomLabels).filter { $0.bold }.count, 500)
        XCTAssertLessThan(seconds, 12, "500 rooms took \(seconds) s")
    }

    func testAnOutlineOfTwoThousandEdgesIsLaidOutQuickly() {
        // A round room of 2000 short walls: the largest-inscribed-rectangle search tests every grid cell against
        // every edge, which took 8 s in a debug build before the grid was thinned for outlines like this.
        let corners = (0..<2000).map { i -> Point2 in
            let angle = Double(i) / 2000 * 2 * Double.pi
            return Point2(15 * cos(angle), 15 * sin(angle))
        }
        let round = Room.polygon(name: "Rotunda", corners: corners)
        let start = Date()
        let r = build([round])
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        guard let name = r.drawing.texts(.roomLabels).first else { return XCTFail("no label") }
        XCTAssertEqual(name.string, "Rotunda")
        XCTAssertTrue(Polygon.contains(round.outline, name.at), "the label is inside the circle")
        // The rectangle found is inside the circle and a fair share of its inscribed square (side 15 x sqrt 2 = 21.2 m).
        let rect = PlanDrawingBuilder.largestInscribedRectangle(of: round.outline)
        XCTAssertNotNil(rect)
        XCTAssertGreaterThan((rect?.width ?? 0) * (rect?.height ?? 0), 0.7 * 2 * 15 * 15, "the best rectangle in a circle of radius 15 is 450 m2")
        XCTAssertLessThanOrEqual((rect?.width ?? 99) * (rect?.height ?? 99), 450.0 + 1e-6)
    }

    func testTheReportListsRoomsThatCouldNotBeDrawn() {
        let lone = Room(name: "Broken room", walls: [Wall(start: .zero, end: Point2(1, 0), height: Measured(scanned: 2.8))],
                        ceilingHeight: Measured(scanned: 2.8))
        let nan = Room.polygon(name: "", kind: .storage, corners: [Point2(0, 0), Point2(.nan, 0), Point2(1, 1)])
        let good = Room.rectangle(name: "Good", width: 3, depth: 3)
        let r = build([lone, good, nan])
        XCTAssertEqual(r.report.undrawableRooms, ["Broken room", "Storage"], "in order, unnamed rooms by their kind")
        XCTAssertEqual(r.drawing.texts(.roomLabels).first?.string, "Good")
        XCTAssertTrue(build([good]).report.undrawableRooms.isEmpty)
    }

    func testHugeFiniteCoordinatesDoNotTrap() {
        // 1e30 m used to overflow an Int conversion in the label placement.
        let huge = Room.rectangle(name: "Huge", width: 1e30, depth: 1e30)
        let d = PlanDrawingBuilder.build(room: huge, options: PlanOptions())
        XCTAssertTrue(d.primitives.allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
        XCTAssertNotNil(PlanDrawingBuilder.largestInscribedRectangle(of: huge.outline))
        // Two huge neighbours go through the shared-wall search as well.
        let twin = Room.rectangle(name: "Twin", origin: Point2(1e30 + 1, 0), width: 1e30, depth: 1e30,
                                  openings: [.door(wall: 3, offset: 1)])
        let pair = PlanDrawingBuilder.build(rooms: [Room.rectangle(name: "A", width: 1e30, depth: 1e30,
                                                                    openings: [.door(wall: 1, offset: 1)]), twin],
                                            title: "", subtitle: "", options: PlanOptions())
        XCTAssertTrue(pair.primitives.allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
        let far = Room.rectangle(name: "Far", origin: Point2(1e300, -1e300), width: 4, depth: 3)
        XCTAssertTrue(PlanDrawingBuilder.build(room: far, options: PlanOptions()).primitives
            .allSatisfy { numbers(of: $0.primitive).allSatisfy(\.isFinite) })
    }

    // MARK: Provenance marks

    func testSiteChecksAreVAndDrawingsAreDAndScansAreUnmarked() {
        var room = Room.rectangle(name: "R", width: 6, depth: 4, openings: [
            .door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5, height: 1.4, sill: 0.9)])
        room.walls[0].length.verify(6.02, source: .laser)
        room.walls[1].length.verify(4.01, source: .tape)
        room.walls[2].length.verify(6.03, source: .drawing, note: "architect drawing rev B")
        room.ceilingHeight.verify(2.75, source: .drawing)
        let d = PlanDrawingBuilder.build(room: room, options: PlanOptions())
        let dims = d.texts(.dimensions)
        XCTAssertEqual(dims.map(\.string), ["6020 mm v", "4010 mm v", "6030 mm d", "4000 mm"])
        let p = PlanDrawingBuilder.Palette.self
        XCTAssertEqual(dims.map(\.color), [p.verified, p.verified, p.ink, p.ink], "green only for site checks")
        XCTAssertEqual(d.texts(.roomLabels).last?.string, "Ceiling 2750 mm d")
        XCTAssertNotEqual(d.texts(.roomLabels).last?.color, PlanDrawingBuilder.Palette.verified, "not green: not checked on site")
        // The report tells the renderer to explain the "d" in the legend.
        XCTAssertTrue(PlanDrawingBuilder.buildDetailed(room: room, options: PlanOptions()).report.hasDrawingSourcedValues)
        var plainRoom = room
        plainRoom.walls[2].length.clearVerification(); plainRoom.ceilingHeight.clearVerification()
        XCTAssertFalse(PlanDrawingBuilder.buildDetailed(room: plainRoom, options: PlanOptions()).report.hasDrawingSourcedValues)
        // With the marks switched off nothing is marked, whatever its source.
        var off = PlanOptions(); off.markVerified = false
        XCTAssertEqual(PlanDrawingBuilder.build(room: room, options: off).texts(.dimensions).map(\.string),
                       ["6020 mm", "4010 mm", "6030 mm", "4000 mm"])
        XCTAssertFalse(PlanDrawingBuilder.buildDetailed(room: room, options: off).report.hasDrawingSourcedValues)
    }

    func testOpeningTagsMarkEachNumberWithItsOwnSource() {
        var room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 0, offset: 0.5), .door(wall: 2, offset: 0.5)])
        room.openings[0].width.verify(0.91, source: .laser)
        room.openings[0].height.verify(2.12, source: .drawing)
        room.openings[1].width.verify(0.9, source: .drawing)
        room.openings[1].height.verify(2.1, source: .drawing)
        let tags = Set(PlanDrawingBuilder.build(room: room, options: PlanOptions()).texts(.doors).map(\.string))
        XCTAssertEqual(tags, ["D 910v x 2120d", "D 900x2100 d"])
    }

    func testEveryUnitPrintsACheckedLengthToAtLeastAMillimetre() {
        // For 60 random checked lengths and every unit, read the printed number back and compare it with the
        // value that was checked: it must be within a millimetre.
        func metres(from text: String, unit: LengthUnit) -> Double? {
            let body = text.hasSuffix(" v") ? String(text.dropLast(2)) : text
            switch unit {
            case .millimetres: return Double(body.dropLast(3)).map { $0 / 1000 }
            case .centimetres: return Double(body.dropLast(3)).map { $0 / 100 }
            case .metres: return Double(body.dropLast(2))
            case .inches: return Double(body.dropLast(3)).map { $0 * 0.0254 }
            case .feetAndInches:
                // 13' 1 1/2"
                var rest = Substring(body)
                var inches = 0.0
                if let tick = rest.firstIndex(of: "'") {
                    guard let feet = Double(rest[rest.startIndex..<tick]) else { return nil }
                    inches += feet * 12
                    rest = rest[rest.index(after: tick)...].drop(while: { $0 == " " })
                }
                rest = rest.dropLast()      // the closing "
                for part in rest.split(separator: " ") {
                    if let slash = part.firstIndex(of: "/") {
                        guard let n = Double(part[part.startIndex..<slash]), let d = Double(part[part.index(after: slash)...]) else { return nil }
                        inches += n / d
                    } else {
                        guard let whole = Double(part) else { return nil }
                        inches += whole
                    }
                }
                return inches * 0.0254
            }
        }
        var rng = LCG(state: 77)
        for _ in 0..<60 {
            let value = (1000 * rng.range(0.6, 9.5)).rounded() / 1000 + rng.range(-0.0004, 0.0004)
            var room = Room.rectangle(name: "R", width: 6, depth: 4)
            room.walls[0].length.verify(value)
            for unit in LengthUnit.allCases {
                var o = PlanOptions(); o.units = DisplayUnits(length: unit, area: .squareMetres)
                let text = PlanDrawingBuilder.build(room: room, options: o).texts(.dimensions)[0].string
                XCTAssertTrue(text.hasSuffix(" v"), text)
                guard let back = metres(from: text, unit: unit) else { XCTFail("cannot read \(text)"); continue }
                XCTAssertEqual(back, value, accuracy: 0.001, "\(unit): \(text) for \(value) m")
            }
        }
        // The case from the review: 6204.4 mm in centimetres used to print 620 cm (a 4 mm loss under a "v").
        var room = Room.rectangle(name: "R", width: 6.2, depth: 4.5)
        room.walls[0].length.verify(6.2044)
        var o = PlanOptions(); o.units = DisplayUnits(length: .centimetres, area: .squareMetres)
        XCTAssertEqual(PlanDrawingBuilder.build(room: room, options: o).texts(.dimensions)[0].string, "620.4 cm v")
        o.units = DisplayUnits(length: .metres, area: .squareMetres)
        XCTAssertEqual(PlanDrawingBuilder.build(room: room, options: o).texts(.dimensions)[0].string, "6.204 m v")
    }

    // MARK: Shared walls

    /// Two rooms side by side with a 0.15 m partition. The door is 0.9 m wide, y from 1.0 to 1.9.
    private func neighbours(a: Room? = nil, b: Room? = nil, gap: Double = 0.15) -> [Room] {
        let first = a ?? Room.rectangle(name: "A", kind: .bedroom, width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0)])
        let second = b ?? Room.rectangle(name: "B", kind: .livingRoom, origin: Point2(4 + gap, 0), width: 3, depth: 3)
        return [first, second]
    }

    private func isInked(_ d: PlanDrawing, _ p: Point2) -> Bool {
        d.polylines(.walls).contains { Polygon.contains($0.points, p) }
    }

    func testADoorIsOpenThroughTheWholePartitionNotJustThroughItsOwnRoomsBand() {
        // A's door in its east wall. B (0.15 m further east) did not record it, so B's west wall band used to
        // fill the doorway: only 0.03 m of the 0.15 m partition read as open.
        let d = PlanDrawingBuilder.build(rooms: neighbours(), title: "", subtitle: "", options: wallsOnly)
        for x in [4.01, 4.04, 4.07, 4.10, 4.13] {
            XCTAssertFalse(isInked(d, Point2(x, 1.45)), "the doorway at x = \(x) is open")
            XCTAssertFalse(isInked(d, Point2(x, 1.02)), "just inside the near edge of the span (x = \(x))")
            XCTAssertFalse(isInked(d, Point2(x, 1.88)), "just inside the far edge (x = \(x))")
        }
        // Beside the door the partition is solid: both bands overlap there.
        for x in [4.01, 4.07, 4.13] {
            XCTAssertTrue(isInked(d, Point2(x, 0.97)), "solid just before the door (x = \(x))")
            XCTAssertTrue(isInked(d, Point2(x, 1.93)), "solid just after the door (x = \(x))")
            XCTAssertTrue(isInked(d, Point2(x, 0.5)))
            XCTAssertTrue(isInked(d, Point2(x, 2.5)))
        }
        // B's west wall (y runs 3 -> 0) is cut at exactly the door's span: pieces cover y 1.9 ... 3 and 0 ... 1.
        let west = d.polylines(.walls).filter { $0.points.allSatisfy { $0.x > 4.0 && $0.x < 4.3 } && $0.points.contains { abs($0.x - 4.15) < 1e-9 } }
        let spans = west.map { piece in (piece.points.map(\.y).min()!, piece.points.map(\.y).max()!) }.sorted { $0.0 < $1.0 }
        guard spans.count == 2 else { return XCTFail("B's west wall should be cut into two pieces: \(spans)") }
        XCTAssertEqual(spans[0].0, 0, accuracy: 0.2); XCTAssertEqual(spans[0].1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(spans[1].0, 1.9, accuracy: 1e-9)
    }

    func testAWindowOfOneRoomIsAlsoOpenThroughTheNeighbouringBand() {
        let a = Room.rectangle(name: "A", width: 4, depth: 3, openings: [.window(wall: 1, offset: 1.0, width: 1.5, height: 1.2, sill: 1.0)])
        let d = PlanDrawingBuilder.build(rooms: neighbours(a: a), title: "", subtitle: "", options: wallsOnly)
        XCTAssertFalse(isInked(d, Point2(4.09, 1.75)))
        XCTAssertTrue(isInked(d, Point2(4.09, 0.9)))
        XCTAssertTrue(isInked(d, Point2(4.09, 2.6)))
    }

    func testAFacingWallFurtherThanAPartitionIsLeftAlone() {
        // 0.6 m apart is a corridor, not a partition: the door cuts only its own room's band.
        let d = PlanDrawingBuilder.build(rooms: neighbours(gap: 0.6), title: "", subtitle: "", options: wallsOnly)
        XCTAssertFalse(isInked(d, Point2(4.06, 1.45)), "A's own band is cut")
        XCTAssertTrue(isInked(d, Point2(4.6 - 0.06, 1.45)), "B's band is whole")
        // And just inside the limit it is cut (0.4 m).
        let near = PlanDrawingBuilder.build(rooms: neighbours(gap: 0.4), title: "", subtitle: "", options: wallsOnly)
        XCTAssertFalse(isInked(near, Point2(4.4 - 0.06, 1.45)))
    }

    func testADoorRecordedByBothRoomsIsDrawnOnceFromTheRoomItOpensInto() {
        // B recorded the same door 8 cm lower in its own wall (y from 1.08 ... wall 3 runs 3 -> 0, so its
        // offset from the wall start is 3 - 1.98 = 1.02).
        let a = Room.rectangle(name: "A", kind: .bedroom, width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0)])
        let b = Room.rectangle(name: "Corridor", kind: .corridor, origin: Point2(4.15, 0), width: 3, depth: 3,
                               openings: [.door(wall: 3, offset: 1.02)])
        let r = PlanDrawingBuilder.buildDetailed(rooms: [a, b], title: "", subtitle: "", options: PlanOptions())
        let d = r.drawing
        XCTAssertEqual(r.report.sharedOpenings, 1)
        XCTAssertEqual(d.arcs(.doors).count, 1, "one swing for one door")
        XCTAssertEqual(d.lines(.doors).count, 1, "one leaf")
        // The bedroom takes the swing (a door opens into the room, not into the corridor): hinge on A's east
        // wall at (4, 1.0), leaf into A, i.e. towards -x.
        let leaf = d.lines(.doors)[0]
        assertPoint(leaf.a, 4.0, 1.0)
        XCTAssertLessThan(leaf.b.x, leaf.a.x)
        XCTAssertEqual(d.texts(.doors).map(\.string), ["D 900x2100"], "one tag")
        // The doorway in both bands is the drawn door's span, 1.0 ... 1.9, not the narrower overlap of the two records.
        var o = wallsOnly; o.showOpeningSizes = false
        let bands = PlanDrawingBuilder.build(rooms: [a, b], title: "", subtitle: "", options: o)
        for y in [1.01, 1.45, 1.89] { XCTAssertFalse(isInked(bands, Point2(4.07, y)), "y = \(y)") }
        for y in [0.99, 1.91] { XCTAssertTrue(isInked(bands, Point2(4.07, y)), "y = \(y)") }
    }

    func testTheSwingGoesToTheRoomTheDoorOpensInto() {
        func leafX(_ a: Room, _ b: Room) -> (hinge: Double, tip: Double)? {
            let d = PlanDrawingBuilder.build(rooms: [a, b], title: "", subtitle: "", options: wallsOnly)
            guard let leaf = d.lines(.doors).first, d.lines(.doors).count == 1 else { return nil }
            return (leaf.a.x, leaf.b.x)
        }
        func pair(_ kindA: RoomKind, _ widthA: Double, _ kindB: RoomKind, _ widthB: Double) -> (Room, Room) {
            (Room.rectangle(name: "A", kind: kindA, width: widthA, depth: 3, openings: [.door(wall: 1, offset: 1.0)]),
             Room.rectangle(name: "B", kind: kindB, origin: Point2(widthA + 0.15, 0), width: widthB, depth: 3,
                            openings: [.door(wall: 3, offset: 1.0)]))
        }
        // Corridor on either side never takes the swing, however small it is.
        var (a, b) = pair(.corridor, 2, .bedroom, 6)
        var x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 2.15, accuracy: 1e-9, "hinge on B's west wall (the bedroom)"); XCTAssertGreaterThan(x?.tip ?? 0, 2.15)
        (a, b) = pair(.bedroom, 6, .corridor, 2)
        x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 6, accuracy: 1e-9, "hinge on A's east wall (the bedroom)"); XCTAssertLessThan(x?.tip ?? 9, 6)
        // Entrance behaves like a corridor.
        (a, b) = pair(.entrance, 3, .livingRoom, 5)
        x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 3.15, accuracy: 1e-9)
        // Otherwise the smaller room takes it: a bathroom off a big living room.
        (a, b) = pair(.livingRoom, 6, .bathroom, 2)
        x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 6.15, accuracy: 1e-9, "B (bathroom) is smaller"); XCTAssertGreaterThan(x?.tip ?? 0, 6.15)
        (a, b) = pair(.bathroom, 2, .livingRoom, 6)
        x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 2, accuracy: 1e-9, "A (bathroom) is smaller"); XCTAssertLessThan(x?.tip ?? 9, 2)
        // Two rooms of the same kind and size: the first takes it.
        (a, b) = pair(.bedroom, 4, .bedroom, 4)
        x = leafX(a, b)
        XCTAssertEqual(x?.hinge ?? 0, 4, accuracy: 1e-9)
    }

    func testTheTagKeepsTheLaserCheckedSizeEvenWhenTheOtherRoomDrawsTheSwing() {
        // Both rooms recorded the door. The bedroom (scanned) draws the swing, but the corridor's record is
        // the one a laser was used on, so its size is the one printed: a checked number is never hidden.
        let a = Room.rectangle(name: "A", kind: .bedroom, width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0)])
        var b = Room.rectangle(name: "C", kind: .corridor, origin: Point2(4.15, 0), width: 3, depth: 3,
                               openings: [.door(wall: 3, offset: 1.0)])
        b.openings[0].width.verify(0.915)
        b.openings[0].height.verify(2.11)
        let d = PlanDrawingBuilder.build(rooms: [a, b], title: "", subtitle: "", options: PlanOptions())
        XCTAssertEqual(d.arcs(.doors).count, 1)
        XCTAssertEqual(d.texts(.doors).map(\.string), ["D 915x2110 v"])
        XCTAssertEqual(d.texts(.doors)[0].color, PlanDrawingBuilder.Palette.verified)
        // The tag sits on the corridor side (its own wall), x > 4.15.
        XCTAssertGreaterThan(d.texts(.doors)[0].at.x, 4.15)
    }

    func testOpeningsThatMerelyLookAlikeAreNotMerged() {
        func swings(_ a: Room, _ b: Room) -> Int {
            PlanDrawingBuilder.build(rooms: [a, b], title: "", subtitle: "", options: PlanOptions()).arcs(.doors).count
        }
        let a = Room.rectangle(name: "A", kind: .bedroom, width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0)])
        // Different place along the wall: no overlap.
        let far = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 3, depth: 3, openings: [.door(wall: 3, offset: 0.2)])
        XCTAssertEqual(swings(a, far), 2)
        // A wide opening against a narrow door (0.9 m vs 2.0 m): not the same opening.
        // (A's door is one swing; B's 1.5 m door is a pair of leaves: three swings in all.)
        let wide = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 3, depth: 3, openings: [.door(wall: 3, offset: 0.5, width: 1.5)])
        XCTAssertEqual(swings(a, wide), 3)
        // A window against a door.
        let window = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 3, depth: 3,
                                    openings: [.window(wall: 3, offset: 1.1, width: 0.9, height: 1.2, sill: 0.9)])
        let r = PlanDrawingBuilder.buildDetailed(rooms: [a, window], title: "", subtitle: "", options: PlanOptions())
        XCTAssertEqual(r.report.sharedOpenings, 0)
        XCTAssertEqual(r.drawing.arcs(.doors).count, 1)
        XCTAssertEqual(r.drawing.lines(.windows).count, 3)
        // Two walls 0.6 m apart are not one partition.
        let distant = Room.rectangle(name: "B", origin: Point2(4.6, 0), width: 3, depth: 3, openings: [.door(wall: 3, offset: 1.0)])
        XCTAssertEqual(swings(a, distant), 2)
        // The same door in the same place is one door.
        let same = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 3, depth: 3, openings: [.door(wall: 3, offset: 1.1)])
        XCTAssertEqual(swings(a, same), 1)
    }

    func testASharedWindowIsDrawnOnce() {
        let a = Room.rectangle(name: "A", width: 4, depth: 3, openings: [.window(wall: 1, offset: 1.0, width: 1.5, height: 1.2, sill: 1.0)])
        let b = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 3, depth: 3,
                               openings: [.window(wall: 3, offset: 0.5, width: 1.5, height: 1.2, sill: 1.0)])
        let d = PlanDrawingBuilder.build(rooms: [a, b], title: "", subtitle: "", options: PlanOptions())
        XCTAssertEqual(d.lines(.windows).count, 3, "one set of glazing lines")
        XCTAssertEqual(d.texts(.windows).count, 1)
    }

    func testSharedOpeningsHaveNoEffectWhenOnlyOneRoomIsDrawn() {
        let a = Room.rectangle(name: "A", width: 4, depth: 3, openings: [.door(wall: 1, offset: 1.0)])
        let d = PlanDrawingBuilder.build(room: a, options: PlanOptions())
        XCTAssertEqual(d.arcs(.doors).count, 1)
        XCTAssertEqual(d.texts(.doors).count, 1)
    }

    func testTheFiveRoomFlatDrawsEachPhysicalOpeningOnce() {
        // The fixture flat has 15 recorded openings. Four of them are the far side of one recorded by the next room,
        // worked out by hand from the coordinates in `PlanPDFFixture`:
        //  - Living Room east door (y 0.5-1.4) = Master Bedroom west door;
        //  - Living Room north doorless opening (x 1.8-3.0) = Kitchen south opening;
        //  - Master Bedroom north door (x 7.5-8.4) = Bedroom 2 south door;
        //  - Kitchen east door (y 5.3-6.1) = Bathroom west door.
        let rooms = PlanPDFFixture.demoRooms()
        XCTAssertEqual(rooms.reduce(0) { $0 + $1.openings.count }, 15)
        let r = PlanDrawingBuilder.buildDetailed(rooms: rooms, title: "", subtitle: "", options: PlanOptions())
        XCTAssertEqual(r.report.sharedOpenings, 4)
        XCTAssertEqual(r.report.omittedOpeningTags, 0)
        XCTAssertEqual(r.drawing.texts(.doors).count, 4, "7 recorded doors, 3 of them seen from both rooms")
        XCTAssertEqual(r.drawing.texts(.windows).count, 6, "six windows, none of them shared")
        XCTAssertEqual(r.drawing.texts(.openings).count, 1, "the doorless opening between the living room and the kitchen")
        // One swing per swung door: 4 doors, none of them wider than 1.3 m.
        XCTAssertEqual(r.drawing.arcs(.doors).count, 4)
        XCTAssertTrue(overprintedPairs(r.drawing).isEmpty, describe(overprintedPairs(r.drawing)))
        // Hand check on one pair: the Living Room east door (x = 6.2) and the Master Bedroom west door (x = 6.4) are 0.2 m
        // apart; the doorway is open at x = 6.3, y = 0.95, and the partition is solid either side of it.
        let bands = PlanDrawingBuilder.build(rooms: rooms, title: "", subtitle: "", options: wallsOnly)
        XCTAssertFalse(isInked(bands, Point2(6.3, 0.95)))
        XCTAssertTrue(isInked(bands, Point2(6.3, 0.3)))
        XCTAssertTrue(isInked(bands, Point2(6.3, 2.5)))
    }

    func testTheDemoPropertyDrawsEachDoorOnceWhateverItsExactLayout() {
        // `DemoProperty` is shared with other modules and may be re-laid-out; only invariants are asserted here.
        let rooms = DemoProperty.make().allRooms
        let recorded = rooms.reduce(0) { $0 + $1.openings.count }
        let r = PlanDrawingBuilder.buildDetailed(rooms: rooms, title: "", subtitle: "", options: PlanOptions())
        XCTAssertGreaterThan(r.report.sharedOpenings, 0, "rooms recorded the doors between them from both sides")
        XCTAssertEqual(r.report.omittedOpeningTags, 0)
        let tags = r.drawing.texts(.doors).count + r.drawing.texts(.windows).count + r.drawing.texts(.openings).count
        XCTAssertEqual(tags, recorded - r.report.sharedOpenings, "one tag per physical opening")
        XCTAssertTrue(overprintedPairs(r.drawing).isEmpty, describe(overprintedPairs(r.drawing)))
    }
}
