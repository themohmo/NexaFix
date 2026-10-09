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

    func lines(_ layer: PlanLayer) -> [(a: Point2, b: Point2, style: StrokeStyle)] {
        items(layer).compactMap {
            if case let .line(a, b, s) = $0 { return (a, b, s) }
            return nil
        }
    }

    func polylines(_ layer: PlanLayer) -> [(points: [Point2], closed: Bool, stroke: StrokeStyle?, fill: DrawColor?)] {
        items(layer).compactMap {
            if case let .polyline(p, c, s, f) = $0 { return (p, c, s, f) }
            return nil
        }
    }

    func arcs(_ layer: PlanLayer) -> [(center: Point2, radius: Double, start: Double, end: Double, style: StrokeStyle)] {
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

    func testCurvedWallIsDrawnAsItsChord() {
        var curved = Room.rectangle(name: "C", width: 4, depth: 3)
        curved.walls[0].isCurved = true
        let straight = Room.rectangle(name: "C", width: 4, depth: 3)
        XCTAssertEqual(plan(curved).primitives, plan(straight).primitives)
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
        // 2.4 m wide on the south wall of a 5 x 4 room, from x = 0.5 to 2.9.
        let room = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 0, offset: 0.5, width: 2.4, height: 2.2)])
        let d = plan(room, wallsOnly)
        let leaves = d.lines(.doors)
        guard leaves.count == 2 else { return XCTFail("two leaves, got \(leaves.count)") }
        assertPoint(leaves[0].a, 0.5, 0); assertPoint(leaves[0].b, 0.5, 1.2)
        assertPoint(leaves[1].a, 2.9, 0); assertPoint(leaves[1].b, 2.9, 1.2)
        let arcs = d.arcs(.doors)
        guard arcs.count == 2 else { return XCTFail("two swings, got \(arcs.count)") }
        assertPoint(arcs[0].center, 0.5, 0)
        XCTAssertEqual(arcs[0].radius, 1.2, accuracy: 1e-12)
        XCTAssertEqual(arcs[0].start, 0, accuracy: 1e-9); XCTAssertEqual(arcs[0].end, 90, accuracy: 1e-9)
        // The second leaf swings from the far edge back towards the middle: 90 -> 180 degrees.
        assertPoint(arcs[1].center, 2.9, 0)
        XCTAssertEqual(arcs[1].start, 90, accuracy: 1e-9); XCTAssertEqual(arcs[1].end, 180, accuracy: 1e-9)
        // Both quarter circles meet in the middle of the opening (x = 1.7) on the wall line.
        XCTAssertEqual(arcs[0].center.x + arcs[0].radius, 1.7, accuracy: 1e-9)
        XCTAssertEqual(arcs[1].center.x - arcs[1].radius, 1.7, accuracy: 1e-9)
        // 1.3 m and narrower stay a single leaf.
        let single = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 0, offset: 0.5, width: 1.3)])
        XCTAssertEqual(plan(single, wallsOnly).lines(.doors).count, 1)
        // A pair of leaves also swings into the room on a wall that runs the other way (north wall, runs west).
        let north = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 2, offset: 0.5, width: 2.0)])
        for a in plan(north, wallsOnly).arcs(.doors) {
            var sweep = a.end - a.start
            if sweep < 0 { sweep += 360 }
            XCTAssertEqual(sweep, 90, accuracy: 1e-9)
            let mid = (a.start + 45) * Double.pi / 180
            XCTAssertTrue(Polygon.contains(north.outline, a.center + Point2(cos(mid), sin(mid)) * (a.radius * 0.8)))
        }
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
        XCTAssertEqual(first(.millimetres), "4000 mm v")
        XCTAssertEqual(first(.centimetres), "400 cm v")
        XCTAssertEqual(first(.metres), "4.00 m v")           // compact precision
        XCTAssertEqual(first(.inches), "157.5 in v")         // 4 / 0.0254 = 157.48
        XCTAssertEqual(first(.feetAndInches), "13' 1 1/2\" v")   // 157.48 in = 13 ft 1.48 in, nearest half inch
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
        XCTAssertEqual(labels[2].string, "Ceiling 2.75 m v")
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
        // 0.9 m = 35.43 in, 2.1 m = 82.68 in: one decimal in tags.
        XCTAssertEqual(tags(.inches), ["D 35.4x82.7 in", "W 59.1x55.1 H35.4 in", "O 47.2x94.5 in"])
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

    func testBoundsGrowToHoldATextLabelWiderThanTheRoom() {
        // A 0.8 m wide room with a long name: the label cannot fit, so the bounds must stretch to hold it.
        let room = Room.rectangle(name: "An Extremely Long Room Name", width: 0.8, depth: 3)
        let d = plan(room)
        XCTAssertGreaterThan(d.bounds.width, 0.8 + 0.24 + 0.2)
        let name = d.texts(.roomLabels)[0]
        let w = PlanDrawingBuilder.textWidth(name.string, height: name.height, bold: true)
        XCTAssertLessThanOrEqual(d.bounds.min.x, name.at.x - w / 2 + 1e-9)
        XCTAssertGreaterThanOrEqual(d.bounds.max.x, name.at.x + w / 2 - 1e-9)
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
