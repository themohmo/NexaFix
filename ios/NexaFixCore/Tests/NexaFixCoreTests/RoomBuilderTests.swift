import XCTest
@testable import NexaFixCore

/// Tests for `RoomBuilder`, `CaptureFixtures` and the RoomPlan conventions they rely on.
///
/// Expected numbers are derived by hand or recomputed from the raw geometry (never copied from the
/// builder's own output). Helpers are `private` so they cannot clash with other test files.
final class RoomBuilderTests: XCTestCase {
    typealias Fixtures = CaptureFixtures
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Helpers

    private func build(_ f: Fixtures.Fixture, options: RoomBuilder.Options = .standard) -> RoomBuilder.Result {
        RoomBuilder.build(from: f.capture, name: "Test", kind: .livingRoom, options: options, now: now)
    }

    private func build(_ c: RawCapture, options: RoomBuilder.Options = .standard) -> RoomBuilder.Result {
        RoomBuilder.build(from: c, name: "Test", kind: .livingRoom, options: options, now: now)
    }

    private func extras(_ configure: (inout Fixtures.Extras) -> Void) -> Fixtures.Extras {
        var e = Fixtures.Extras()
        configure(&e)
        return e
    }

    /// Interior angles of the outline in loop order.
    private func angles(_ room: Room) -> [Double] {
        let o = room.outline
        return o.indices.map { Polygon.interiorAngle(o, at: $0) }
    }

    private func assertPoint(_ p: Point2, _ x: Double, _ y: Double, tol: Double = 1e-9,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: tol, "x \(message)", file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: tol, "y \(message)", file: file, line: line)
    }

    /// Every point of `expected` has a partner in `actual` within `tol`, and the counts agree.
    private func assertSamePoints(_ actual: [Point2], _ expected: [Point2], tol: Double,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "vertex count", file: file, line: line)
        for e in expected {
            XCTAssertTrue(actual.contains { $0.distance(to: e) <= tol },
                          "no vertex within \(tol) of (\(e.x), \(e.y))", file: file, line: line)
        }
    }

    private func assertAllFinite(_ r: RoomBuilder.Result, file: StaticString = #filePath, line: UInt = #line) {
        func ok(_ v: Double, _ what: String) {
            XCTAssertTrue(v.isFinite, "\(what) is not finite: \(v)", file: file, line: line)
        }
        let room = r.room
        ok(room.ceilingHeight.scanned, "ceiling"); ok(room.floorElevation, "floor elevation")
        for w in room.walls {
            ok(w.start.x, "wall start x"); ok(w.start.y, "wall start y"); ok(w.end.x, "wall end x"); ok(w.end.y, "wall end y")
            ok(w.length.scanned, "wall length"); ok(w.height.scanned, "wall height")
        }
        for o in room.openings {
            ok(o.offsetFromWallStart, "offset"); ok(o.width.scanned, "width"); ok(o.height.scanned, "height")
            ok(o.sillHeight.scanned, "sill")
        }
        for o in room.objects {
            ok(o.center.x, "object x"); ok(o.center.y, "object y"); ok(o.yaw, "yaw"); ok(o.width, "w"); ok(o.depth, "d")
            ok(o.height, "h"); ok(o.elevation, "elevation")
        }
        for w in r.warnings {
            XCTAssertFalse(w.message.lowercased().contains("nan"), "warning mentions nan: \(w.message)", file: file, line: line)
            XCTAssertFalse(w.message.isEmpty, file: file, line: line)
        }
    }

    /// A wall surface built by hand (independent of `CaptureFixtures`).
    private func rawWall(_ a: Point2, _ b: Point2, height: Double = 2.8, bottom: Double = 0,
                         id: UUID = UUID(), curved: Bool = false) -> RawSurface {
        let c = (a + b) * 0.5, d = b - a
        return RawSurface(id: id, kind: .wall,
                          transform: Matrix4.yawTranslation(yaw: atan2(d.y, d.x), Point3(c.x, bottom + height / 2, -c.y)),
                          dimensions: Point3(d.length, height, 0), isCurved: curved)
    }

    private func rawBox(_ corners: [Point2], height: Double = 2.8) -> [RawSurface] {
        corners.indices.map { rawWall(corners[$0], corners[($0 + 1) % corners.count], height: height) }
    }

    private func setY(_ s: inout RawSurface, _ y: Double) {
        var m = s.transform.columnMajor
        m[13] = y
        s.transform = Matrix4(columnMajor: m)
    }

    private func virtualCount(_ room: Room) -> Int { room.walls.filter { $0.kind == .virtual }.count }

    private func has(_ r: RoomBuilder.Result, _ predicate: (RoomBuilder.BuildWarning) -> Bool) -> Bool {
        r.warnings.contains(where: predicate)
    }

    private var allShapes: [Fixtures.Fixture] {
        [Fixtures.rectangle(width: 4, depth: 3, seed: 1),
         Fixtures.lShape(seed: 2),
         Fixtures.tShape(seed: 3),
         Fixtures.uShape(seed: 4),
         Fixtures.trapezoid(seed: 5),
         Fixtures.chamfered(seed: 6),
         Fixtures.alcove(seed: 7),
         Fixtures.openPlan(seed: 8),
         Fixtures.splitWall(seed: 9),
         Fixtures.curvedWall(seed: 10),
         Fixtures.overshootingWall(seed: 11),
         Fixtures.rectangle(width: 3.3, depth: 2.7, seed: 12, extras: extras { $0.rotationDegrees = 37; $0.origin = Point2(12.5, -8) })]
    }

    // MARK: Rectangle, exact

    func testRectangleExactGeometry() {
        let f = Fixtures.rectangle(width: 4, depth: 3, height: 2.8, seed: 5)
        let r = build(f)
        let room = r.room
        XCTAssertEqual(r.warnings, [], "a clean rectangle needs no warnings")
        XCTAssertEqual(room.walls.count, 4)
        XCTAssertEqual(room.name, "Test")
        XCTAssertEqual(room.kind, .livingRoom)
        XCTAssertEqual(room.scannedAt, now)
        XCTAssertEqual(room.id, f.capture.id)
        // Counter-clockwise from the lowest-then-leftmost corner: south, east, north, west.
        let starts = [Point2(0, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)]
        for (i, p) in starts.enumerated() {
            assertPoint(room.walls[i].start, p.x, p.y, "wall \(i) start")
            XCTAssertEqual(room.walls[i].kind, .solid)
        }
        XCTAssertEqual(room.walls.map { $0.length.scanned }.map { ($0 * 1e6).rounded() / 1e6 }, [4, 3, 4, 3])
        XCTAssertTrue(room.walls.allSatisfy { abs($0.height.scanned - 2.8) < 1e-12 })
        XCTAssertEqual(room.ceilingHeight.scanned, 2.8, accuracy: 1e-12)
        XCTAssertEqual(room.floorElevation, 0, accuracy: 1e-12)
        XCTAssertFalse(room.ceilingHeight.isVerified)
        XCTAssertTrue(room.walls.allSatisfy { !$0.length.isVerified && !$0.height.isVerified })

        let m = room.metrics
        XCTAssertEqual(m.floorArea, 12, accuracy: 1e-9)
        XCTAssertEqual(m.perimeter, 14, accuracy: 1e-9)
        XCTAssertEqual(m.volume, 33.6, accuracy: 1e-9)
        XCTAssertTrue(m.isRectangular)
        XCTAssertEqual(m.length ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(m.width ?? 0, 3, accuracy: 1e-9)
        for c in m.corners { XCTAssertEqual(c.interiorAngle, 90, accuracy: 1e-9) }
        // Wall length is the chord between the corners.
        for w in room.walls { XCTAssertEqual(w.length.scanned, w.geometricLength, accuracy: 1e-12) }
        // Wall ids are the RoomPlan surface ids; the map is the identity for unmerged walls.
        let wallIDs = Set(f.capture.walls.map(\.id))
        XCTAssertEqual(Set(room.walls.map(\.id)), wallIDs)
        for id in wallIDs { XCTAssertEqual(r.surfaceToWall[id], id) }
        assertAllFinite(r)
    }

    func testEveryFixtureShapeRoundTripsToExpectedArea() {
        for f in allShapes {
            let r = build(f)
            let area = Polygon.area(r.room.outline)
            XCTAssertEqual(area, f.expectedArea, accuracy: f.expectedArea * 0.01, "\(f.name) area")
            XCTAssertEqual(area, f.expectedArea, accuracy: 1e-9, "\(f.name) noise-free area is exact")
            XCTAssertEqual(r.room.walls.count, f.expectedWallCount, "\(f.name) wall count")
            XCTAssertEqual(virtualCount(r.room), f.expectedVirtualWallCount, "\(f.name) virtual walls")
            XCTAssertTrue(Polygon.isCounterClockwise(r.room.outline), "\(f.name) winding")
            assertSamePoints(r.room.outline, f.corners, tol: 1e-9)
            XCTAssertEqual(Polygon.perimeter(r.room.outline), f.expectedPerimeter, accuracy: 1e-9, "\(f.name) perimeter")
            XCTAssertNotEqual(r.worstSeverity, .critical, "\(f.name)")
            assertAllFinite(r)
        }
    }

    // MARK: Shapes and corner angles

    func testLShapeCornerAngles() {
        let r = build(Fixtures.lShape(width: 6, depth: 4, notchWidth: 2, notchDepth: 2, seed: 3))
        // L: (0,0) (6,0) (6,2) (4,2) (4,4) (0,4). Five right angles and one reflex 270.
        let a = angles(r.room)
        XCTAssertEqual(a.count, 6)
        let expected: [Double] = [90, 90, 90, 270, 90, 90]
        for (x, y) in zip(a, expected) { XCTAssertEqual(x, y, accuracy: 1e-9) }
        XCTAssertEqual(a.reduce(0, +), Double(6 - 2) * 180, accuracy: 1e-9)
        let m = r.room.metrics
        XCTAssertEqual(m.corners.filter(\.isReflex).count, 1)
        XCTAssertTrue(m.outOfSquareCorners.isEmpty)
        XCTAssertFalse(m.isRectangular)
        XCTAssertEqual(m.sides.count, 6)
        XCTAssertEqual(r.room.walls.map { $0.length.scanned }.map { ($0 * 1e6).rounded() / 1e6 }, [6, 2, 2, 2, 4, 4])
        XCTAssertEqual(m.floorArea, 20, accuracy: 1e-9)
        // The reflex corner is the notch corner (4, 2).
        assertPoint(m.corners.first(where: \.isReflex)!.point, 4, 2)
    }

    func testTrapezoidHasNonRightAngles() {
        // Bottom 5, top 3, depth 4: each slanted side rises 4 over a run of 1.
        let r = build(Fixtures.trapezoid(bottom: 5, top: 3, depth: 4, seed: 4))
        let alpha = atan2(4.0, 1.0) * 180 / Double.pi   // 75.9638 degrees
        let a = angles(r.room)
        XCTAssertEqual(a[0], alpha, accuracy: 1e-9)
        XCTAssertEqual(a[1], alpha, accuracy: 1e-9)
        XCTAssertEqual(a[2], 180 - alpha, accuracy: 1e-9)
        XCTAssertEqual(a[3], 180 - alpha, accuracy: 1e-9)
        XCTAssertEqual(r.room.walls[1].length.scanned, 17.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(r.room.metrics.floorArea, (5 + 3) / 2 * 4, accuracy: 1e-9)
        XCTAssertFalse(r.room.metrics.isRectangular)
    }

    func testChamferGives135DegreeCorners() {
        let r = build(Fixtures.chamfered(width: 5, depth: 4, chamfer: 1, seed: 6))
        let a = angles(r.room)
        XCTAssertEqual(a.count, 5)
        for (x, y) in zip(a, [90.0, 90, 135, 135, 90]) { XCTAssertEqual(x, y, accuracy: 1e-9) }
        XCTAssertEqual(r.room.walls[2].length.scanned, 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(r.room.metrics.floorArea, 20 - 0.5, accuracy: 1e-9)
    }

    func testAlcoveAndNicheKeepAllEightWalls() {
        let f = Fixtures.alcove(width: 5, depth: 3.5, nicheWidth: 1.2, nicheDepth: 0.4, nicheOffset: 1.5, seed: 7)
        let r = build(f)
        XCTAssertEqual(r.room.walls.count, 8)
        XCTAssertEqual(r.room.metrics.floorArea, 5 * 3.5 + 1.2 * 0.4, accuracy: 1e-9)
        for (x, y) in zip(angles(r.room), [90.0, 90, 90, 270, 90, 90, 270, 90]) { XCTAssertEqual(x, y, accuracy: 1e-9) }
        let lengths = r.room.walls.map { ($0.length.scanned * 1e6).rounded() / 1e6 }
        XCTAssertEqual(lengths, [5, 3.5, 2.3, 0.4, 1.2, 0.4, 1.5, 3.5])
        XCTAssertEqual(r.warnings, [])
    }

    func testTAndUShapesAreComplete() {
        let t = build(Fixtures.tShape(barWidth: 6, barDepth: 2.5, stemWidth: 2.5, stemDepth: 3, seed: 1))
        XCTAssertEqual(t.room.walls.count, 8)
        XCTAssertEqual(Polygon.area(t.room.outline), 6 * 2.5 + 2.5 * 3, accuracy: 1e-9)
        XCTAssertEqual(angles(t.room).filter { $0 > 180 }.count, 2)
        let u = build(Fixtures.uShape(width: 6, depth: 5, cutWidth: 2, cutDepth: 3, seed: 2))
        XCTAssertEqual(u.room.walls.count, 8)
        XCTAssertEqual(Polygon.area(u.room.outline), 6 * 5 - 2 * 3, accuracy: 1e-9)
        XCTAssertEqual(angles(u.room).filter { $0 > 180 }.count, 2)
        XCTAssertEqual(t.warnings, []); XCTAssertEqual(u.warnings, [])
    }

    func testRotatedAndTranslatedRoomIsInvariant() {
        let f = Fixtures.rectangle(width: 4, depth: 3, seed: 9, extras: extras { $0.rotationDegrees = 37; $0.origin = Point2(12.5, -8) })
        let r = build(f)
        XCTAssertEqual(r.room.walls.map { $0.length.scanned }.sorted().map { ($0 * 1e6).rounded() / 1e6 }, [3, 3, 4, 4])
        for a in angles(r.room) { XCTAssertEqual(a, 90, accuracy: 1e-7) }
        XCTAssertEqual(Polygon.area(r.room.outline), 12, accuracy: 1e-9)
        // Hand-computed corner: origin + R(37 deg) * (4, 0).
        let c = Double.pi * 37 / 180
        let corner = Point2(12.5 + 4 * cos(c), -8 + 4 * sin(c))
        XCTAssertTrue(r.room.outline.contains { $0.distance(to: corner) < 1e-9 })
    }

    func testOutOfSquareCornerIsNotSnapped() {
        // West wall leans: SW corner is exactly 91.5 degrees, NW 88.5.
        let lean = 3.4 * tan(1.5 * Double.pi / 180) / 2
        let f = Fixtures.polygon(name: "skew", corners: [Point2(lean, 0), Point2(3.8, 0), Point2(3.8, 3.4), Point2(-lean, 3.4)], seed: 3)
        let r = build(f)
        let a = angles(r.room)
        XCTAssertEqual(a[0], 91.5, accuracy: 1e-9)
        XCTAssertEqual(a[3], 88.5, accuracy: 1e-9)
        XCTAssertEqual(a[1], 90, accuracy: 1e-9)
        XCTAssertEqual(r.room.metrics.outOfSquareCorners.count, 2)
        XCTAssertEqual(r.room.metrics.floorArea, 3.8 * 3.4, accuracy: 1e-9)
    }

    // MARK: Order and orientation independence

    func testShuffledAndFlippedInputsGiveIdenticalOutput() {
        let doors = [OpeningSpec.door(wall: 0, offset: 1.0), OpeningSpec.door(wall: 4, offset: 0.5, width: 0.8)]
        let windows = [OpeningSpec.window(wall: 5, offset: 1.0, width: 1.6), OpeningSpec.window(wall: 1, offset: 0.4, width: 1.0)]
        let objs = [Fixtures.FixtureObject(category: "sofa", center: Point2(2, 2), yaw: 0.4, width: 2, depth: 0.9, height: 0.8),
                    Fixtures.FixtureObject(category: "storage", center: Point2(5.5, 1), width: 0.8, depth: 0.5, height: 2.2),
                    Fixtures.FixtureObject(category: "fridge-unknown", center: Point2(1, 3.5), width: 0.7, depth: 0.7, height: 1.8)]
        for noise in [Fixtures.Noise.none, .realistic] {
            let base = Fixtures.lShape(doors: doors, windows: windows, noise: noise, seed: 21, extras: extras { $0.objects = objs; $0.floorY = -1.3 })
            let reference = build(base)
            var sawFlip = false, sawReorder = false
            for seed in UInt64(100)..<UInt64(130) {
                let shuffled = base.reshuffled(seed: seed)
                let cap = build(shuffled)
                sawFlip = sawFlip || zip(shuffled.walls, base.canonical.walls).contains { _, _ in false }
                    || shuffled.walls.contains { w in
                        guard let orig = base.canonical.walls.first(where: { $0.id == w.id }) else { return false }
                        return w.transform.xAxis.x * orig.transform.xAxis.x + w.transform.xAxis.z * orig.transform.xAxis.z < 0
                    }
                sawReorder = sawReorder || shuffled.walls.map(\.id) != base.canonical.walls.map(\.id)
                assertSameResult(reference, cap, tol: 1e-9)
            }
            XCTAssertTrue(sawFlip, "the test must really flip walls")
            XCTAssertTrue(sawReorder, "the test must really reorder walls")
        }
    }

    private func assertSameResult(_ a: RoomBuilder.Result, _ b: RoomBuilder.Result, tol: Double,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.room.walls.count, b.room.walls.count, file: file, line: line)
        guard a.room.walls.count == b.room.walls.count else { return }
        for (x, y) in zip(a.room.walls, b.room.walls) {
            XCTAssertEqual(x.id, y.id, file: file, line: line)
            XCTAssertEqual(x.kind, y.kind, file: file, line: line)
            XCTAssertEqual(x.isCurved, y.isCurved, file: file, line: line)
            XCTAssertLessThan(x.start.distance(to: y.start), tol, file: file, line: line)
            XCTAssertLessThan(x.end.distance(to: y.end), tol, file: file, line: line)
            XCTAssertEqual(x.length.scanned, y.length.scanned, accuracy: tol, file: file, line: line)
            XCTAssertEqual(x.height.scanned, y.height.scanned, accuracy: tol, file: file, line: line)
        }
        XCTAssertEqual(a.room.ceilingHeight.scanned, b.room.ceilingHeight.scanned, accuracy: tol, file: file, line: line)
        XCTAssertEqual(a.room.floorElevation, b.room.floorElevation, accuracy: tol, file: file, line: line)
        XCTAssertEqual(a.room.id, b.room.id, file: file, line: line)
        XCTAssertEqual(a.room.openings.count, b.room.openings.count, file: file, line: line)
        if a.room.openings.count == b.room.openings.count {
            for (x, y) in zip(a.room.openings, b.room.openings) {
                XCTAssertEqual(x.id, y.id, file: file, line: line)
                XCTAssertEqual(x.kind, y.kind, file: file, line: line)
                XCTAssertEqual(x.wallID, y.wallID, file: file, line: line)
                XCTAssertEqual(x.offsetFromWallStart, y.offsetFromWallStart, accuracy: tol, file: file, line: line)
                XCTAssertEqual(x.width.scanned, y.width.scanned, accuracy: tol, file: file, line: line)
                XCTAssertEqual(x.height.scanned, y.height.scanned, accuracy: tol, file: file, line: line)
                XCTAssertEqual(x.sillHeight.scanned, y.sillHeight.scanned, accuracy: tol, file: file, line: line)
            }
        }
        XCTAssertEqual(a.room.objects.count, b.room.objects.count, file: file, line: line)
        if a.room.objects.count == b.room.objects.count {
            for (x, y) in zip(a.room.objects, b.room.objects) {
                XCTAssertEqual(x.id, y.id, file: file, line: line)
                XCTAssertEqual(x.kind, y.kind, file: file, line: line)
                XCTAssertLessThan(x.center.distance(to: y.center), tol, file: file, line: line)
                XCTAssertEqual(x.yaw, y.yaw, accuracy: tol, file: file, line: line)
                XCTAssertEqual(x.elevation, y.elevation, accuracy: tol, file: file, line: line)
            }
        }
        XCTAssertEqual(a.warnings.map(\.message), b.warnings.map(\.message), file: file, line: line)
        XCTAssertEqual(a.surfaceToWall, b.surfaceToWall, file: file, line: line)
    }

    func testBuildIsRepeatable() {
        let f = Fixtures.uShape(doors: [.door(wall: 0, offset: 1)], noise: .realistic, seed: 77)
        XCTAssertEqual(build(f), build(f), "same input, same output, bit for bit")
    }

    func testFlippedSurfaceDescribesTheSamePlanSegment() {
        // Flipping a wall 180 degrees must not change the room.
        var f = Fixtures.rectangle(width: 5, depth: 4, seed: 1)
        let plain = build(f.canonical)
        f.canonical.walls = f.canonical.walls.map { Fixtures.flipped($0) }
        let flipped = build(f.canonical)
        assertSameResult(plain, flipped, tol: 1e-9)
        // And the flip really changed the raw data.
        XCTAssertLessThan(f.canonical.walls[0].transform.xAxis.x, 0)
    }

    // MARK: Noise

    func testRealisticNoiseKeepsAreaAnglesAndWallCount() {
        let noise = Fixtures.Noise.realistic
        let tanA = tan(noise.angleDegrees * Double.pi / 180)
        for seed in UInt64(1)...UInt64(40) {
            let fixtures: [Fixtures.Fixture] = [
                Fixtures.rectangle(width: 5, depth: 4, noise: noise, seed: seed),
                Fixtures.lShape(noise: noise, seed: seed),
                Fixtures.tShape(noise: noise, seed: seed),
                Fixtures.uShape(noise: noise, seed: seed),
                Fixtures.trapezoid(noise: noise, seed: seed),
                Fixtures.chamfered(noise: noise, seed: seed),
                Fixtures.alcove(noise: noise, seed: seed)]
            for f in fixtures {
                let r = build(f)
                let tag = "\(f.name) seed \(seed)"
                XCTAssertEqual(r.room.walls.count, f.expectedWallCount, tag)
                XCTAssertEqual(virtualCount(r.room), 0, tag)
                XCTAssertNotEqual(r.worstSeverity, .critical, tag)
                let area = Polygon.area(r.room.outline)
                XCTAssertEqual(area, f.expectedArea, accuracy: f.expectedArea * 0.015, "\(tag) area")

                // Analytic bound on every corner: lines i and j are each displaced by at most
                // offset + (L/2 + end error) * tan(angle noise); the intersection moves at most the
                // sum of those over sin(corner angle).
                let n = f.corners.count
                for i in 0..<n {
                    let prev = f.corners[(i + n - 1) % n], cur = f.corners[i], next = f.corners[(i + 1) % n]
                    func shift(_ len: Double) -> Double { noise.offset + (len / 2 + noise.endError) * tanA }
                    let theta = Polygon.interiorAngle(f.corners, at: i) * Double.pi / 180
                    let bound = 1.1 * (shift(prev.distance(to: cur)) + shift(cur.distance(to: next))) / abs(sin(theta))
                    let nearest = r.room.outline.map { $0.distance(to: cur) }.min() ?? .infinity
                    XCTAssertLessThanOrEqual(nearest, bound, "\(tag) corner \(i)")
                    // Interior angle moves by at most the two direction errors.
                    let measured = r.room.outline.min { $0.distance(to: cur) < $1.distance(to: cur) }
                        .flatMap { p in r.room.outline.firstIndex(of: p) }
                        .map { Polygon.interiorAngle(r.room.outline, at: $0) }
                    if let m = measured {
                        XCTAssertEqual(m, Polygon.interiorAngle(f.corners, at: i), accuracy: 2 * noise.angleDegrees + 1e-6, "\(tag) angle \(i)")
                    }
                }
            }
        }
    }

    func testCornerGapsAndOvershootsAreHealedExactly() {
        for over in [-0.14, -0.1, -0.05, -0.02, 0.0, 0.03, 0.1, 0.4, 0.9] {
            let f = Fixtures.rectangle(width: 4, depth: 3, seed: 8, extras: extras { $0.overshoot = over })
            let r = build(f)
            let tag = "overshoot \(over)"
            XCTAssertEqual(r.room.walls.count, 4, tag)
            XCTAssertEqual(virtualCount(r.room), 0, tag)
            XCTAssertEqual(Polygon.area(r.room.outline), 12, accuracy: 1e-9, tag)
            XCTAssertEqual(r.room.walls.map { $0.length.scanned }.sorted().map { ($0 * 1e6).rounded() / 1e6 }, [3, 3, 4, 4], tag)
            for a in angles(r.room) { XCTAssertEqual(a, 90, accuracy: 1e-9, tag) }
        }
        // Noteworthy repairs are reported; tiny ones are not.
        let big = build(Fixtures.rectangle(seed: 1, extras: extras { $0.overshoot = -0.13 }))
        XCTAssertTrue(has(big) { if case .cornersAdjusted(let g, let m, _, _) = $0 { return g == 4 && abs(m - 0.13) < 1e-9 } else { return false } })
        let small = build(Fixtures.rectangle(seed: 1, extras: extras { $0.overshoot = -0.02 }))
        XCTAssertEqual(small.warnings, [])
        let trimmed = build(Fixtures.rectangle(seed: 1, extras: extras { $0.overshoot = 0.4 }))
        XCTAssertTrue(has(trimmed) { if case .cornersAdjusted(_, _, let t, let m) = $0 { return t == 4 && abs(m - 0.4) < 1e-9 } else { return false } })
    }

    func testOneWallRunningPastTwoCornersIsTrimmed() {
        for wall in 0..<4 {
            let f = Fixtures.overshootingWall(width: 5, depth: 4, wall: wall, by: 0.5, seed: UInt64(wall + 1))
            let r = build(f)
            XCTAssertEqual(r.room.walls.count, 4, "wall \(wall)")
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9, "wall \(wall)")
            // The trimmed wall is exactly as long as the room side, not side + 1.0.
            let lengths = r.room.walls.map { ($0.length.scanned * 1e6).rounded() / 1e6 }.sorted()
            XCTAssertEqual(lengths, [4, 4, 5, 5], "wall \(wall)")
        }
    }

    func testSnapToleranceOptionIsRespected() {
        // Every wall falls 0.1 short of both corners.
        let f = Fixtures.rectangle(width: 4, depth: 3, seed: 2, extras: extras { $0.overshoot = -0.1 })
        XCTAssertEqual(build(f).room.walls.count, 4)
        var strict = RoomBuilder.Options.standard
        strict.snapTolerance = 0.05
        let r = build(f, options: strict)
        // Gaps are now too big to heal: every corner is bridged by a short virtual wall.
        XCTAssertEqual(r.room.walls.count, 8)
        XCTAssertEqual(virtualCount(r.room), 4)
        // Each bridge cuts a corner diagonally: sqrt(0.1^2 + 0.1^2) long.
        let diagonal = 0.1 * 2.0.squareRoot()
        for v in r.room.walls where v.kind == .virtual {
            XCTAssertEqual(v.length.scanned, diagonal, accuracy: 1e-9)
        }
        let cutOff = 4.0 * (0.1 * 0.1 / 2.0)
        XCTAssertEqual(Polygon.area(r.room.outline), 12.0 - cutOff, accuracy: 1e-9)
    }

    // MARK: Open plan, bridging and fallbacks

    func testMissingWallIsBridgedWithAVirtualWall() {
        for missing in 0..<4 {
            let f = Fixtures.openPlan(width: 5, depth: 4, missingWall: missing, seed: UInt64(missing + 3))
            let r = build(f)
            let tag = "missing wall \(missing)"
            XCTAssertEqual(r.room.walls.count, 4, tag)
            XCTAssertEqual(virtualCount(r.room), 1, tag)
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9, tag)
            let v = r.room.walls.first { $0.kind == .virtual }!
            XCTAssertEqual(v.length.scanned, missing % 2 == 0 ? 5 : 4, accuracy: 1e-9, tag)
            XCTAssertEqual(v.height.scanned, r.room.ceilingHeight.scanned, accuracy: 1e-12, "virtual wall height = ceiling")
            XCTAssertFalse(v.isCurved)
            XCTAssertTrue(has(r) { if case .openBoundaryBridged(let l, _) = $0 { return abs(l - v.length.scanned) < 1e-9 } else { return false } }, tag)
            XCTAssertEqual(r.worstSeverity, .caution, tag)
            // The virtual wall runs where the missing wall was: its midpoint is the midpoint of that side.
            let a = f.corners[missing], b = f.corners[(missing + 1) % 4]
            assertPoint(v.midpoint, (a.x + b.x) / 2, (a.y + b.y) / 2, tag)
            // Metrics: virtual walls count in the perimeter but not in the wall area.
            let m = r.room.metrics
            XCTAssertEqual(m.perimeter, 18, accuracy: 1e-9, tag)
            XCTAssertEqual(m.wallPerimeter, 18 - v.length.scanned, accuracy: 1e-9, tag)
            XCTAssertEqual(m.grossWallArea, (18 - v.length.scanned) * 2.8, accuracy: 1e-9, tag)
            // The virtual wall id is deterministic.
            XCTAssertEqual(build(f).room.walls.map(\.id), r.room.walls.map(\.id), tag)
            XCTAssertEqual(Set(r.room.walls.map(\.id)).count, 4, tag)
        }
    }

    func testOpenPlanWithNoiseStaysAccurate() {
        for seed in UInt64(1)...UInt64(25) {
            let f = Fixtures.openPlan(width: 5, depth: 4, missingWall: Int(seed % 4), noise: .realistic, seed: seed)
            let r = build(f)
            XCTAssertEqual(r.room.walls.count, 4, "seed \(seed)")
            XCTAssertEqual(virtualCount(r.room), 1, "seed \(seed)")
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 0.3, "seed \(seed)")
        }
    }

    func testGapBeyondMaxBridgeableFallsBackToTheFloorPolygon() {
        let f = Fixtures.openPlan(width: 7.5, depth: 4, missingWall: 2, seed: 1)    // 7.5 m side missing
        let r = build(f)
        XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: .floorPolygon) })
        XCTAssertEqual(r.worstSeverity, .critical)
        XCTAssertEqual(Polygon.area(r.room.outline), 30, accuracy: 1e-9)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(virtualCount(r.room), 1, "the side with no scanned wall is virtual")
        XCTAssertEqual(r.surfaceToWall.count, 3)
        XCTAssertTrue(Polygon.isCounterClockwise(r.room.outline))
        assertAllFinite(r)
        // Raising the limit bridges it instead, with no critical warning.
        var wide = RoomBuilder.Options.standard
        wide.maxBridgeableGap = 8
        let ok = build(f, options: wide)
        XCTAssertFalse(has(ok) { if case .noClosedLoop = $0 { return true } else { return false } })
        XCTAssertEqual(ok.worstSeverity, .caution)
        XCTAssertEqual(Polygon.area(ok.room.outline), 30, accuracy: 1e-9)
        XCTAssertEqual(virtualCount(ok.room), 1)
    }

    func testNoLoopAndNoFloorFallsBackToTheConvexHull() {
        let f = Fixtures.openPlan(width: 8, depth: 4, missingWall: 2, seed: 2, extras: extras { $0.includeFloor = false })
        let r = build(f)
        XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: .convexHull) })
        XCTAssertTrue(has(r) { $0 == .missingFloorSurface })
        XCTAssertEqual(r.worstSeverity, .critical)
        XCTAssertEqual(Polygon.area(r.room.outline), 32, accuracy: 1e-9)
        XCTAssertEqual(virtualCount(r.room), 1)
        XCTAssertEqual(r.room.walls.count, 4)
        assertAllFinite(r)
    }

    func testTwoAdjacentMissingWallsAreBridgedHonestlyAndFlagged() {
        // South and east walls only. The only free ends are 6.4 m apart: a diagonal virtual wall would give a 10 m2
        // triangle, but the floor polygon shows the room is twice that big. The builder used to accept the triangle
        // with a caution; it now refuses it and says so loudly (critical), using the floor shape as the outline.
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 2, omit: true), .init(wall: 3, omit: true)]
        let corners = [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(0, 4)]
        let f = Fixtures.polygon(name: "L-open", corners: corners, seed: 3, extras: e)
        let r = build(f)
        XCTAssertEqual(r.worstSeverity, .critical)
        XCTAssertEqual(r.outlineSource, .floorPolygon)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(virtualCount(r.room), 2, "the two sides nobody scanned")
        XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9)
        XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: .floorPolygon) })
        XCTAssertFalse(has(r) { if case .openBoundaryBridged = $0 { return true } else { return false } }, "no diagonal bridge")
        // Without a floor surface there is nothing to compare with: the diagonal is bridged, as a caution.
        var noFloor = e
        noFloor.includeFloor = false
        let g = build(Fixtures.polygon(name: "L-open", corners: corners, seed: 3, extras: noFloor))
        XCTAssertEqual(g.room.walls.count, 3)
        XCTAssertEqual(virtualCount(g.room), 1)
        XCTAssertEqual(Polygon.area(g.room.outline), 10, accuracy: 1e-9)
        XCTAssertEqual(g.worstSeverity, .caution)
    }

    // MARK: Split walls

    func testSplitWallMergesIntoOneWall() {
        for gap in [0.03, 0.0, -0.2, 0.14] {
            let f = Fixtures.splitWall(width: 5, depth: 4, wall: 0, at: 0.4, gap: gap, seed: 4)
            XCTAssertEqual(f.capture.walls.count, 5, "five surfaces go in")
            let r = build(f)
            let tag = "gap \(gap)"
            XCTAssertEqual(r.room.walls.count, 4, tag)
            XCTAssertEqual(virtualCount(r.room), 0, tag)
            XCTAssertEqual(r.room.walls[0].length.scanned, 5, accuracy: 1e-9, tag)
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9, tag)
            // Both pieces map to the single wall; the wall takes the longer piece's id.
            let ids = f.wallSurfaceIDs[0]
            XCTAssertEqual(ids.count, 2)
            XCTAssertEqual(r.surfaceToWall[ids[0]], r.surfaceToWall[ids[1]], tag)
            XCTAssertNotNil(r.surfaceToWall[ids[0]], tag)
            XCTAssertEqual(r.room.walls[0].id, r.surfaceToWall[ids[0]], tag)
            XCTAssertTrue(has(r) { $0 == .collinearWallsMerged(pieces: 2, walls: 1) }, tag)
            XCTAssertEqual(r.room.metrics.sides.count, 4, tag)
            XCTAssertTrue(r.room.metrics.isRectangular, tag)
        }
    }

    func testSplitWallWithAGapBeyondSnapKeepsAStraightVirtualJoint() {
        let f = Fixtures.splitWall(width: 5, depth: 4, wall: 0, at: 0.4, gap: 0.4, seed: 5)   // pieces [0,1.8] and [2.2,5]
        let r = build(f)
        XCTAssertEqual(r.room.walls.count, 6, "south side = solid + virtual + solid, plus east, north, west")
        XCTAssertEqual(virtualCount(r.room), 1)
        let lengths = r.room.walls.prefix(3).map { ($0.length.scanned * 1e6).rounded() / 1e6 }
        XCTAssertEqual(Array(lengths), [1.8, 0.4, 2.8])
        XCTAssertEqual(r.room.walls[1].kind, .virtual)
        // Room.metrics merges straight corners into one side, so the room is still a rectangle.
        let m = r.room.metrics
        XCTAssertEqual(m.corners.filter(\.isStraight).count, 2)
        XCTAssertEqual(m.sides.count, 4)
        XCTAssertTrue(m.isRectangular)
        XCTAssertEqual(m.sides[0].length, 5, accuracy: 1e-9)
        XCTAssertFalse(m.sides[0].isSolid, "that side contains an unscanned stretch")
        XCTAssertEqual(m.floorArea, 20, accuracy: 1e-9)
    }

    func testTwoSplitWallsAndOpeningsOnMergedPieces() {
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 0, splitAt: 0.5, splitGap: 0.02), .init(wall: 2, splitAt: 0.3, splitGap: -0.1)]
        let f = Fixtures.polygon(name: "twoSplits", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)],
                                 doors: [.door(wall: 0, offset: 0.5), .door(wall: 0, offset: 4.0)],
                                 windows: [.window(wall: 2, offset: 3.0, width: 1.2)], seed: 6, extras: e)
        XCTAssertEqual(f.capture.walls.count, 6)
        let r = build(f)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(r.room.walls.map { $0.length.scanned }.sorted().map { ($0 * 1e6).rounded() / 1e6 }, [4, 4, 6, 6])
        // Doors on different pieces of the south wall both attach to it, with offsets along the whole wall.
        let south = r.room.walls[0]
        let doors = r.room.openings(on: south)
        XCTAssertEqual(doors.map { ($0.offsetFromWallStart * 1e6).rounded() / 1e6 }, [0.5, 4.0])
        let north = r.room.walls[2]
        XCTAssertEqual(r.room.openings(on: north).count, 1)
        // North wall runs east to west; window starts 3.0 from its start (x = 6 -> x = 3.0 ... 1.8).
        let w = r.room.openings(on: north)[0]
        XCTAssertEqual(w.offsetFromWallStart, 3.0, accuracy: 1e-9)
        let seg = w.planSegment(on: north)
        assertPoint(seg.0, 3.0, 4.0); assertPoint(seg.1, 1.8, 4.0)
    }

    // MARK: Curved walls

    func testCurvedWallIsStoredAsItsChord() {
        let f = Fixtures.curvedWall(width: 5, depth: 4, wall: 1, sagitta: 0.3, seed: 6)
        let r = build(f)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(r.room.walls.filter(\.isCurved).count, 1)
        let curved = r.room.walls.first(where: \.isCurved)!
        assertPoint(curved.start, 5, 0); assertPoint(curved.end, 5, 4)
        XCTAssertEqual(curved.length.scanned, 4, accuracy: 1e-9, "the chord")
        XCTAssertEqual(r.room.metrics.floorArea, 20, accuracy: 1e-9)
        XCTAssertTrue(has(r) { $0 == .curvedWallsStoredAsChords(count: 1) })
        XCTAssertEqual(r.worstSeverity, .info)
        // The scanned floor includes the bulge (circular segment, about 2/3 * chord * sagitta).
        let bulge = (f.floorArea ?? 0) - 20
        XCTAssertEqual(bulge, 2.0 / 3.0 * 4 * 0.3, accuracy: 0.05)
        XCTAssertFalse(has(r) { if case .floorAreaMismatch = $0 { return true } else { return false } }, "4 % is within tolerance")
    }

    func testHeavilyCurvedWallTriggersFloorMismatch() {
        let f = Fixtures.curvedWall(width: 5, depth: 4, wall: 1, sagitta: 1.6, seed: 7)    // big bulge: > 15 % extra floor
        let r = build(f)
        XCTAssertTrue(has(r) { if case .floorAreaMismatch = $0 { return true } else { return false } })
    }

    // MARK: Interior walls

    func testInteriorWallsAreDroppedWithAWarning() {
        let cases: [(String, [Fixtures.InteriorWall], Int, Double)] = [
            ("stub from the west wall", [.init(from: Point2(0, 1.5), to: Point2(1.5, 1.5))], 1, 1.5),
            ("half wall from the south wall", [.init(from: Point2(2, 0), to: Point2(2, 1.2))], 1, 1.2),
            ("floating bulkhead", [.init(from: Point2(1, 1), to: Point2(2.5, 1))], 1, 1.5),
            ("bulkhead near a corner", [.init(from: Point2(0.4, 2.7), to: Point2(1.6, 2.7))], 1, 1.2),
            ("full partition touching both side walls", [.init(from: Point2(0, 2.5), to: Point2(4, 2.5))], 1, 4.0),
            ("partition 0.2 m from the north wall", [.init(from: Point2(0, 2.8), to: Point2(4, 2.8))], 1, 4.0),
            ("bulkhead parallel to the north wall", [.init(from: Point2(0, 2.7), to: Point2(4, 2.7))], 1, 4.0),
            ("diagonal into a corner", [.init(from: Point2(0, 0), to: Point2(1.5, 1.5))], 1, 1.5 * 2.0.squareRoot()),
            ("two stubs", [.init(from: Point2(0, 1), to: Point2(1, 1)), .init(from: Point2(4, 2), to: Point2(3, 2))], 2, 2.0),
        ]
        for (name, interior, count, total) in cases {
            let f = Fixtures.rectangle(width: 4, depth: 3, seed: 3, extras: extras { $0.interiorWalls = interior })
            let r = build(f)
            XCTAssertEqual(r.room.walls.count, 4, name)
            XCTAssertEqual(Polygon.area(r.room.outline), 12, accuracy: 1e-9, name)
            XCTAssertEqual(r.room.walls.map { $0.length.scanned }.sorted().map { ($0 * 1e6).rounded() / 1e6 }, [3, 3, 4, 4], name)
            XCTAssertEqual(virtualCount(r.room), 0, name)
            XCTAssertTrue(has(r) { if case .interiorWallsDropped(let c, let t) = $0 { return c == count && abs(t - total) < 1e-9 } else { return false } }, name)
            for id in f.interiorSurfaceIDs { XCTAssertNil(r.surfaceToWall[id], name) }
            XCTAssertEqual(r.surfaceToWall.count, 4, name)
            XCTAssertEqual(r.worstSeverity, .caution, name)
        }
    }

    func testInteriorWallsInsideAnLShapeAndWithNoise() {
        for seed in UInt64(1)...UInt64(15) {
            let f = Fixtures.lShape(noise: .realistic, seed: seed, extras: extras {
                $0.interiorWalls = [.init(from: Point2(0, 2), to: Point2(2, 2)), .init(from: Point2(3, 0), to: Point2(3, 1.2))]
            })
            let r = build(f)
            XCTAssertEqual(r.room.walls.count, 6, "seed \(seed)")
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 0.3, "seed \(seed)")
            XCTAssertTrue(has(r) { if case .interiorWallsDropped(let c, _) = $0 { return c == 2 } else { return false } }, "seed \(seed)")
        }
    }

    // MARK: Openings

    func testOpeningWallOffsetWidthHeightAndSill() {
        // 5 x 4 room. Hand-computed expectations.
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3,
                                   extras: extras { $0.floorY = -1.3 })
        var capture = f.canonical
        // South-wall door, 0.9 x 2.1, near edge 1.0 m from the south wall's start (0,0): centre x = 1.45.
        let door = RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(1.45, -1.3 + 1.05, 0)),
                              dimensions: Point3(0.9, 2.1, 0), parentID: f.wallSurfaceIDs[0][0])
        // West-wall window 1.0 x 1.4, sill 0.9. West wall runs (0,4) -> (0,0), start at the north end.
        // Near edge 0.5 m from the start -> spans y 3.5 ... 2.5, centre (0, 3.0).
        let window = RawSurface(kind: .window, transform: Matrix4.yawTranslation(yaw: Double.pi / 2, Point3(0, -1.3 + 0.9 + 0.7, -3.0)),
                                dimensions: Point3(1.0, 1.4, 0), parentID: f.wallSurfaceIDs[3][0])
        // East-wall doorless opening 1.2 x 2.2 centred at y = 2.0 (east wall runs (5,0) -> (5,4)): offset 1.4.
        let opening = RawSurface(kind: .opening, transform: Matrix4.yawTranslation(yaw: Double.pi / 2, Point3(5, -1.3 + 1.1, -2.0)),
                                 dimensions: Point3(1.2, 2.2, 0), parentID: f.wallSurfaceIDs[1][0])
        capture.doors = [door]; capture.windows = [window]; capture.openings = [opening]
        let r = build(capture)
        XCTAssertEqual(r.room.openings.count, 3)
        let walls = r.room.walls
        let south = walls.first { abs($0.start.y) < 1e-9 && abs($0.end.y) < 1e-9 }!
        let west = walls.first { abs($0.start.x) < 1e-9 && abs($0.end.x) < 1e-9 }!
        let east = walls.first { abs($0.start.x - 5) < 1e-9 && abs($0.end.x - 5) < 1e-9 }!

        let d = r.room.openings.first { $0.kind == .door }!
        XCTAssertEqual(d.wallID, south.id)
        XCTAssertEqual(d.offsetFromWallStart, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.width.scanned, 0.9, accuracy: 1e-9)
        XCTAssertEqual(d.height.scanned, 2.1, accuracy: 1e-9)
        XCTAssertEqual(d.sillHeight.scanned, 0, accuracy: 1e-9)

        let w = r.room.openings.first { $0.kind == .window }!
        XCTAssertEqual(w.wallID, west.id)
        XCTAssertEqual(w.offsetFromWallStart, 0.5, accuracy: 1e-9, "measured from the west wall's start at the NORTH end")
        XCTAssertEqual(w.width.scanned, 1.0, accuracy: 1e-9)
        XCTAssertEqual(w.height.scanned, 1.4, accuracy: 1e-9)
        XCTAssertEqual(w.sillHeight.scanned, 0.9, accuracy: 1e-9)
        let seg = w.planSegment(on: west)
        assertPoint(seg.0, 0, 3.5); assertPoint(seg.1, 0, 2.5)

        let o = r.room.openings.first { $0.kind == .opening }!
        XCTAssertEqual(o.wallID, east.id)
        XCTAssertEqual(o.offsetFromWallStart, 1.4, accuracy: 1e-9)
        XCTAssertEqual(o.sillHeight.scanned, 0, accuracy: 1e-9)
        XCTAssertFalse(o.width.isVerified); XCTAssertFalse(w.height.isVerified)
        XCTAssertEqual(r.warnings.filter { if case .openingUnmatched = $0 { return true } else { return false } }.count, 0)
    }

    func testOpeningsFromFixturesLandWhereTheRawSurfaceIs() {
        let doors = [OpeningSpec.door(wall: 0, offset: 1.0), OpeningSpec.door(wall: 3, offset: 0.4, width: 0.8)]
        let windows = [OpeningSpec.window(wall: 1, offset: 0.5, width: 1.6), OpeningSpec.window(wall: 2, offset: 1.0, width: 2.0, height: 1.2, sill: 1.0)]
        for rotation in [0.0, 29, 200] {
            let f = Fixtures.rectangle(width: 5, depth: 4, doors: doors, windows: windows, seed: UInt64(rotation) + 2,
                                       extras: extras { $0.floorY = -0.7; $0.rotationDegrees = rotation; $0.origin = Point2(3, 4) })
            let r = build(f)
            XCTAssertEqual(r.room.openings.count, 4)
            let raw = (f.capture.doors + f.capture.windows).reduce(into: [UUID: RawSurface]()) { $0[$1.id] = $1 }
            for o in r.room.openings {
                guard let s = raw[o.id], let wid = o.wallID, let wall = r.room.wall(withID: wid) else { XCTFail("opening not attached"); continue }
                let (a, b) = o.planSegment(on: wall)
                let mid = (a + b) * 0.5
                let want = Point2(s.transform.translation.x, -s.transform.translation.z)
                XCTAssertLessThan(mid.distance(to: want), 1e-9, "\(o.kind) midpoint matches the raw surface (rotation \(rotation))")
                XCTAssertEqual(o.width.scanned, s.dimensions.x, accuracy: 1e-12)
                XCTAssertEqual(o.height.scanned, s.dimensions.y, accuracy: 1e-12)
                XCTAssertEqual(o.sillHeight.scanned, s.transform.translation.y - s.dimensions.y / 2 - (-0.7), accuracy: 1e-9)
                // On the right wall: the parent wall surface maps to it.
                XCTAssertEqual(r.surfaceToWall[s.parentID!], wid)
                XCTAssertGreaterThanOrEqual(o.offsetFromWallStart, -1e-12)
                XCTAssertLessThanOrEqual(o.offsetFromWallStart + o.width.scanned, wall.geometricLength + 1e-9)
            }
        }
    }

    func testSillHeightRules() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3, extras: extras { $0.floorY = -1.3 })
        let parent = f.wallSurfaceIDs[0][0]
        func door(sill: Double) -> RawSurface {
            RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(2.5, -1.3 + sill + 1.05, 0)),
                       dimensions: Point3(0.9, 2.1, 0), parentID: parent)
        }
        // (centre-derived sill, expected)
        let cases: [(Double, Double)] = [(0.0, 0.0), (0.02, 0.0), (0.029, 0.0), (0.05, 0.05), (0.9, 0.9), (-0.05, 0.0), (-0.5, 0.0)]
        for (sill, expected) in cases {
            var c = f.canonical
            c.doors = [door(sill: sill)]
            let r = build(c)
            XCTAssertEqual(r.room.openings.first?.sillHeight.scanned ?? -1, expected, accuracy: 1e-9, "sill \(sill)")
        }
        // Without a floor surface the floor level is the lowest wall bottom (-1.3 here), same answer.
        var noFloor = f.canonical
        noFloor.floors = []
        noFloor.doors = [door(sill: 0.4)]
        let r = build(noFloor)
        XCTAssertEqual(r.room.floorElevation, -1.3, accuracy: 1e-12)
        XCTAssertEqual(r.room.openings.first?.sillHeight.scanned ?? -1, 0.4, accuracy: 1e-9)
    }

    func testUnmatchedAndMisparentedOpenings() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3,
                                   extras: extras { $0.interiorWalls = [.init(from: Point2(1, 1.5), to: Point2(3, 1.5))] })
        func door(at p: Point2, parent: UUID?) -> RawSurface {
            RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(p.x, 1.05, -p.y)),
                       dimensions: Point3(0.9, 2.1, 0), parentID: parent)
        }
        var c = f.canonical
        // 1. Unknown parent, 0.1 m off the south wall -> nearest wall, no warning.
        // 2. Parent is the dropped interior wall -> nearest wall.
        // 3. Parent says north wall but the door sits on the south wall -> trust geometry.
        // 4. 0.5 m from every wall -> unattached + warning.
        // 5. In the middle of the room (2 m from the nearest wall) -> unattached.
        // 6. Exactly 0.35 m from the west wall -> attached.
        c.doors = [door(at: Point2(2.5, 0.1), parent: UUID()),
                   door(at: Point2(4.0, 0.2), parent: f.interiorSurfaceIDs[0]),
                   door(at: Point2(1.5, 0.05), parent: f.wallSurfaceIDs[2][0]),
                   door(at: Point2(0.5, 0.5), parent: nil),
                   door(at: Point2(2.5, 2.0), parent: nil),
                   door(at: Point2(0.35, 2.0), parent: nil)]
        let r = build(c)
        XCTAssertEqual(r.room.openings.count, 6)
        let south = r.room.walls.first { abs($0.start.y) < 1e-9 && abs($0.end.y) < 1e-9 }!
        let west = r.room.walls.first { abs($0.start.x) < 1e-9 && abs($0.end.x) < 1e-9 }!
        let byID = Dictionary(uniqueKeysWithValues: r.room.openings.map { ($0.id, $0) })
        XCTAssertEqual(byID[c.doors[0].id]?.wallID, south.id)
        XCTAssertEqual(byID[c.doors[1].id]?.wallID, south.id)
        XCTAssertEqual(byID[c.doors[2].id]?.wallID, south.id, "a parent that is nowhere near is not trusted")
        XCTAssertNil(byID[c.doors[3].id]?.wallID)
        XCTAssertNil(byID[c.doors[4].id]?.wallID)
        XCTAssertEqual(byID[c.doors[5].id]?.wallID, west.id)
        let unmatched = r.warnings.compactMap { w -> (UUID, Double?)? in
            if case .openingUnmatched(let id, .door, let d) = w { return (id, d) } else { return nil }
        }
        XCTAssertEqual(Set(unmatched.map(\.0)), [c.doors[3].id, c.doors[4].id])
        let d3 = unmatched.first { $0.0 == c.doors[3].id }?.1 ?? -1
        XCTAssertEqual(d3, 0.5, accuracy: 1e-9)
        XCTAssertEqual(unmatched.first { $0.0 == c.doors[4].id }?.1 ?? -1, 2.0, accuracy: 1e-9, "centre of a 4 m deep room: 2 m from north and south")
        // Unattached openings keep their size, with offset 0.
        XCTAssertEqual(byID[c.doors[3].id]?.width.scanned ?? 0, 0.9, accuracy: 1e-12)
        XCTAssertEqual(byID[c.doors[3].id]?.offsetFromWallStart ?? 1, 0, accuracy: 1e-12)
    }

    func testOpeningOverhangingItsWallIsClampedAndReported() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3)
        let parent = f.wallSurfaceIDs[0][0]
        var c = f.canonical
        // 0.9 wide door centred 0.2 m from the south wall's start: would start at -0.25.
        c.doors = [RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(0.2, 1.05, 0)),
                              dimensions: Point3(0.9, 2.1, 0), parentID: parent)]
        // A 6 m wide window on the 5 m wall.
        c.windows = [RawSurface(kind: .window, transform: Matrix4.yawTranslation(yaw: 0, Point3(2.5, 1.5, 0)),
                                dimensions: Point3(6, 1.0, 0), parentID: parent)]
        let r = build(c)
        let door = r.room.openings.first { $0.kind == .door }!
        XCTAssertEqual(door.offsetFromWallStart, 0, accuracy: 1e-12)
        XCTAssertEqual(door.width.scanned, 0.9, accuracy: 1e-12)
        let win = r.room.openings.first { $0.kind == .window }!
        XCTAssertEqual(win.width.scanned, 5, accuracy: 1e-9, "clamped to the wall length")
        XCTAssertEqual(win.offsetFromWallStart, 0, accuracy: 1e-9)
        XCTAssertEqual(r.warnings.filter { if case .openingAdjusted = $0 { return true } else { return false } }.count, 2)
    }

    func testOpeningOnAVirtualWallIsAttachedToIt() {
        // A 1.0 m full-height gap in the south wall: two wall pieces 1.0 m apart, a doorless opening between them.
        let f = Fixtures.splitWall(width: 5, depth: 4, wall: 0, at: 0.5, gap: 1.0, seed: 3)
        var c = f.canonical
        c.openings = [RawSurface(kind: .opening, transform: Matrix4.yawTranslation(yaw: 0, Point3(2.5, 1.0, 0)),
                                 dimensions: Point3(1.0, 2.0, 0), parentID: nil)]
        let r = build(c)
        XCTAssertEqual(r.room.walls.count, 6, "south wall = solid + virtual + solid")
        let v = r.room.walls.first { $0.kind == .virtual }!
        XCTAssertEqual(r.room.openings.first?.wallID, v.id)
        XCTAssertEqual(r.room.openings.first?.offsetFromWallStart ?? -1, 0, accuracy: 1e-9)
    }

    func testOpeningOrderIsCanonical() {
        let doors = [OpeningSpec.door(wall: 2, offset: 0.5), OpeningSpec.door(wall: 0, offset: 3.0), OpeningSpec.door(wall: 0, offset: 0.5)]
        let f = Fixtures.rectangle(width: 5, depth: 4, doors: doors, windows: [.window(wall: 0, offset: 1.6, width: 1.0)], seed: 1)
        for seed in UInt64(1)...UInt64(8) {
            let r = build(f.reshuffled(seed: seed))
            let keys = r.room.openings.map { o -> String in
                "\(r.room.walls.firstIndex { $0.id == o.wallID } ?? -1)@\(String(format: "%.2f", o.offsetFromWallStart))"
            }
            XCTAssertEqual(keys, ["0@0.50", "0@1.60", "0@3.00", "2@0.50"], "seed \(seed)")
        }
    }

    // MARK: Objects

    func testObjectCategoryMapping() {
        let names = ["storage", "refrigerator", "stove", "bed", "sink", "washerDryer", "toilet", "bathtub",
                     "oven", "dishwasher", "table", "sofa", "chair", "fireplace", "television", "stairs"]
        XCTAssertEqual(names.count, 16)
        for n in names {
            XCTAssertEqual(RoomBuilder.objectKind(forCategory: n).rawValue, n, n)
        }
        for n in ["", "unknown", "Storage", "SOFA", "washer_dryer", "lamp", " storage"] {
            XCTAssertEqual(RoomBuilder.objectKind(forCategory: n), .other, "'\(n)'")
        }
        // All 16 are distinct cases and cover every non-.other kind.
        XCTAssertEqual(Set(names.map { RoomBuilder.objectKind(forCategory: $0) }).count, 16)
        XCTAssertEqual(Set(names.map { RoomBuilder.objectKind(forCategory: $0) }), Set(ObjectKind.allCases).subtracting([.other]))
    }

    func testObjectGeometryFromTheTransform() {
        // A sofa whose local X axis points along plan direction 30 degrees, 2.0 wide (x), 0.9 high (y), 0.95 deep (z),
        // centred at world (3, -0.35, -2) i.e. plan (3, 2); the floor is at y = -1.3 so its bottom is 0.5 above the floor.
        let c30 = cos(30 * Double.pi / 180), s30 = sin(30 * Double.pi / 180)
        // World X axis of the object: plan (cos, sin) -> world (cos, 0, -sin).
        let m = Matrix4(columnMajor: [c30, 0, -s30, 0,   0, 1, 0, 0,   s30, 0, c30, 0,   3, -0.35, -2, 1])
        let sofa = RawObject(category: "sofa", transform: m, dimensions: Point3(2.0, 0.9, 0.95))
        // Another resting 0.2 below the floor (scan noise): elevation clamps to 0.
        let low = RawObject(category: "chair", transform: Matrix4.yawTranslation(yaw: 0, Point3(1, -1.3 + 0.45 - 0.2, -1)),
                            dimensions: Point3(0.5, 0.9, 0.5))
        var capture = RawCapture(walls: rawBox([Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(0, 4)], height: 2.8).map { s -> RawSurface in
            var s = s; setY(&s, -1.3 + 1.4); return s })
        capture.floors = [RawSurface(kind: .floor, transform: Matrix4(columnMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 2.5, -1.3, -2, 1]),
                                     dimensions: Point3(5, 4, 0),
                                     polygonCorners: [Point3(-2.5, -2, 0), Point3(2.5, -2, 0), Point3(2.5, 2, 0), Point3(-2.5, 2, 0)])]
        capture.objects = [sofa, low]
        let r = build(capture)
        XCTAssertEqual(r.room.floorElevation, -1.3, accuracy: 1e-12)
        XCTAssertEqual(r.room.objects.count, 2)
        let s = r.room.objects.first { $0.kind == .sofa }!
        assertPoint(s.center, 3, 2)
        XCTAssertEqual(s.yaw, 30 * Double.pi / 180, accuracy: 1e-12)
        XCTAssertEqual(s.width, 2.0, accuracy: 1e-12)
        XCTAssertEqual(s.depth, 0.95, accuracy: 1e-12)
        XCTAssertEqual(s.height, 0.9, accuracy: 1e-12)
        XCTAssertEqual(s.elevation, 0.5, accuracy: 1e-9)          // -0.35 - 0.45 + 1.3
        // Footprint corner check: the local +x edge points along (cos30, sin30).
        let fp = s.footprint
        let dir = (fp[1] - fp[0]).normalized
        XCTAssertEqual(dir.x, c30, accuracy: 1e-9); XCTAssertEqual(dir.y, s30, accuracy: 1e-9)
        let ch = r.room.objects.first { $0.kind == .chair }!
        XCTAssertEqual(ch.elevation, 0, accuracy: 1e-12)
        XCTAssertEqual(ch.yaw, 0, accuracy: 1e-12)
        assertPoint(ch.center, 1, 1)
    }

    func testObjectsFromFixturesAreRecovered() {
        let objs = [Fixtures.FixtureObject(category: "bed", center: Point2(1.5, 1.0), yaw: Double.pi / 2, width: 1.6, depth: 2.0, height: 0.5),
                    Fixtures.FixtureObject(category: "storage", center: Point2(4, 3), yaw: -0.7, width: 2.4, depth: 0.6, height: 2.4, elevation: 0.1),
                    Fixtures.FixtureObject(category: "lamp", center: Point2(0.5, 0.5), width: 0.3, depth: 0.3, height: 1.5)]
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 9, extras: extras { $0.objects = objs; $0.floorY = -1.3; $0.origin = Point2(2, 1) })
        let r = build(f)
        XCTAssertEqual(r.room.objects.count, 3)
        let bed = r.room.objects.first { $0.kind == .bed }!
        assertPoint(bed.center, 3.5, 2.0)
        XCTAssertEqual(bed.yaw, Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(bed.width, 1.6, accuracy: 1e-12); XCTAssertEqual(bed.depth, 2.0, accuracy: 1e-12)
        XCTAssertEqual(bed.elevation, 0, accuracy: 1e-9)
        let st = r.room.objects.first { $0.kind == .storage }!
        XCTAssertEqual(st.yaw, -0.7, accuracy: 1e-12)
        XCTAssertEqual(st.elevation, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.room.objects.filter { $0.kind == .other }.count, 1)
    }

    func testInvalidObjectsAreIgnored() {
        var c = Fixtures.rectangle(seed: 1).canonical
        let good = RawObject(category: "sofa", transform: .identity, dimensions: Point3(1, 1, 1))
        c.objects = [good,
                     RawObject(category: "sofa", transform: .identity, dimensions: Point3(0, 1, 1)),
                     RawObject(category: "sofa", transform: .identity, dimensions: Point3(-1, 1, 1)),
                     RawObject(category: "sofa", transform: .identity, dimensions: Point3(.nan, 1, 1)),
                     RawObject(category: "sofa", transform: Matrix4(columnMajor: [Double](repeating: .infinity, count: 16)), dimensions: Point3(1, 1, 1))]
        let r = build(c)
        XCTAssertEqual(r.room.objects.count, 1)
        XCTAssertEqual(r.room.objects.first?.id, good.id)
        XCTAssertTrue(has(r) { $0 == .invalidObjectsIgnored(count: 4) })
    }

    // MARK: Heights and floor level

    func testCeilingHeightIsTheMedianWallHeight() {
        func room(_ heights: [Double]) -> Room {
            var e = Fixtures.Extras()
            e.tweaks = heights.indices.map { Fixtures.WallTweak(wall: $0, height: heights[$0]) }
            let f = Fixtures.polygon(name: "h", corners: [Point2(0, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)], seed: 3, extras: e)
            return build(f).room
        }
        let a = room([2.7, 2.8, 2.8, 3.1])
        XCTAssertEqual(a.ceilingHeight.scanned, 2.8, accuracy: 1e-12, "median, not the mean (2.85) and not the max")
        let b = room([2.6, 2.8, 2.9, 3.1])
        XCTAssertEqual(b.ceilingHeight.scanned, 2.85, accuracy: 1e-12, "even count: mean of the middle two")
        let c = room([2.4, 2.4, 2.4, 3.0])
        XCTAssertEqual(c.ceilingHeight.scanned, 2.4, accuracy: 1e-12)
        // Each wall keeps its own scanned height.
        XCTAssertEqual(a.walls.map { $0.height.scanned }.sorted(), [2.7, 2.8, 2.8, 3.1])
        // Five walls: the middle one.
        let five = build(Fixtures.chamfered(seed: 1)).room
        XCTAssertEqual(five.ceilingHeight.scanned, 2.8, accuracy: 1e-12)
        // A virtual wall takes the ceiling height, and does not vote.
        let open = build(Fixtures.openPlan(seed: 1)).room
        XCTAssertEqual(open.walls.first { $0.kind == .virtual }?.height.scanned ?? 0, 2.8, accuracy: 1e-12)
    }

    func testFloorElevationFromFloorSurfaceOrLowestWallBottom() {
        let f = Fixtures.rectangle(width: 4, depth: 3, seed: 1, extras: extras { $0.floorY = 0.4 })
        XCTAssertEqual(build(f).room.floorElevation, 0.4, accuracy: 1e-12)
        // The floor surface wins over the walls.
        var c = f.canonical
        setY(&c.floors[0], 0.35)
        XCTAssertEqual(build(c).room.floorElevation, 0.35, accuracy: 1e-12)
        // Without a floor: the lowest wall bottom. Drop one wall's centre by 0.07.
        c.floors = []
        setY(&c.walls[2], c.walls[2].transform.translation.y - 0.07)
        XCTAssertEqual(build(c).room.floorElevation, 0.4 - 0.07, accuracy: 1e-12)
        // Two floor pieces: the lowest.
        var two = f.canonical
        var second = two.floors[0]
        second.id = UUID()
        setY(&second, 0.3)
        two.floors.append(second)
        XCTAssertEqual(build(two).room.floorElevation, 0.3, accuracy: 1e-12)
    }

    // MARK: Sanity warnings

    func testFloorAreaMismatchWarning() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 1)     // 20 m2
        func scaleFloor(_ k: Double) -> RawCapture {
            var c = f.canonical
            c.floors[0].polygonCorners = c.floors[0].polygonCorners!.map { Point3($0.x * k, $0.y * k, $0.z) }
            return c
        }
        XCTAssertFalse(has(build(scaleFloor(1.0))) { if case .floorAreaMismatch = $0 { return true } else { return false } })
        // Linear 1.05 -> area x1.1025: inside 15 %.
        XCTAssertFalse(has(build(scaleFloor(1.05))) { if case .floorAreaMismatch = $0 { return true } else { return false } })
        // Linear 1.1 -> area x1.21: outside.
        let r = build(scaleFloor(1.1))
        XCTAssertTrue(has(r) { if case .floorAreaMismatch(let fa, let oa) = $0 { return abs(fa - 24.2) < 1e-9 && abs(oa - 20) < 1e-9 } else { return false } })
        XCTAssertEqual(r.worstSeverity, .caution)
        // Too small is flagged too.
        XCTAssertTrue(has(build(scaleFloor(0.8))) { if case .floorAreaMismatch(let fa, _) = $0 { return abs(fa - 12.8) < 1e-9 } else { return false } })
        // The wall outline stays the source of truth.
        XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9)
    }

    func testMissingFloorSurfaceWarning() {
        let f = Fixtures.rectangle(seed: 1, extras: extras { $0.includeFloor = false })
        let r = build(f)
        XCTAssertTrue(has(r) { $0 == .missingFloorSurface })
        XCTAssertEqual(r.worstSeverity, .info)
        XCTAssertFalse(has(build(Fixtures.rectangle(seed: 1))) { $0 == .missingFloorSurface })
        // A floor with no polygon is still a floor: no warning, and no area comparison.
        var c = Fixtures.rectangle(width: 4, depth: 3, seed: 1).canonical
        c.floors[0].polygonCorners = nil
        let r2 = build(c)
        XCTAssertEqual(r2.warnings, [])
    }

    func testImplausibleAreasAreFlagged() {
        let tiny = build(Fixtures.rectangle(width: 0.8, depth: 0.9, seed: 1))     // 0.72 m2
        XCTAssertTrue(has(tiny) { if case .roomAreaOutOfRange(let a) = $0 { return abs(a - 0.72) < 1e-9 } else { return false } })
        let huge = build(Fixtures.rectangle(width: 25, depth: 20, seed: 1))       // 500 m2
        XCTAssertTrue(has(huge) { if case .roomAreaOutOfRange(let a) = $0 { return abs(a - 500) < 1e-9 } else { return false } })
        let edgeLow = build(Fixtures.rectangle(width: 1, depth: 1, seed: 1))
        XCTAssertFalse(has(edgeLow) { if case .roomAreaOutOfRange = $0 { return true } else { return false } }, "exactly 1 m2 is allowed")
        let ok = build(Fixtures.rectangle(width: 20, depth: 20, seed: 1))
        XCTAssertFalse(has(ok) { if case .roomAreaOutOfRange = $0 { return true } else { return false } }, "exactly 400 m2 is allowed")
        XCTAssertEqual(tiny.room.walls.count, 4)
        XCTAssertEqual(huge.room.walls.count, 4)
    }

    func testSelfIntersectingFallbackOutlineIsReported() {
        // Three wall pieces that cannot form a loop, and a floor polygon that is a bow-tie.
        var c = RawCapture()
        c.walls = [rawWall(Point2(0, 0), Point2(5, 0)), rawWall(Point2(0, 10), Point2(5, 10)), rawWall(Point2(20, 0), Point2(25, 0))]
        c.floors = [RawSurface(kind: .floor, transform: Matrix4(columnMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1]),
                               dimensions: Point3(4, 4, 0),
                               polygonCorners: [Point3(0, 0, 0), Point3(4, 3, 0), Point3(4, 0, 0), Point3(0, 4, 0)])]
        let r = build(c)
        XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: .floorPolygon) })
        XCTAssertTrue(has(r) { $0 == .selfIntersectingOutline })
        XCTAssertEqual(r.worstSeverity, .critical)
        assertAllFinite(r)
    }

    // MARK: Garbage

    func testEmptyCaptureGivesAnEmptyRoomAndAWarning() {
        let r = build(RawCapture())
        XCTAssertEqual(r.room.walls.count, 0)
        XCTAssertTrue(has(r) { $0 == .noWallSurfaces })
        XCTAssertEqual(r.worstSeverity, .critical)
        XCTAssertEqual(r.room.openings.count, 0)
        XCTAssertEqual(r.room.objects.count, 0)
        XCTAssertEqual(r.room.ceilingHeight.scanned, 0)
        XCTAssertEqual(r.room.floorElevation, 0)
        XCTAssertTrue(r.surfaceToWall.isEmpty)
        assertAllFinite(r)
        // Metrics on the empty room do not trap.
        XCTAssertEqual(r.room.metrics.floorArea, 0)
    }

    func testTooFewWallsGiveNoOutline() {
        let one = build(RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0))]))
        XCTAssertEqual(one.room.walls.count, 0)
        XCTAssertTrue(has(one) { $0 == .tooFewWalls(count: 1) })
        // Two walls meeting at a corner: the two free ends are bridged (5 m), giving a triangle.
        let two = build(RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0)), rawWall(Point2(4, 0), Point2(4, 3))]))
        XCTAssertTrue(has(two) { if case .openBoundaryBridged(let l, _) = $0 { return abs(l - 5) < 1e-9 } else { return false } })
        XCTAssertEqual(Polygon.area(two.room.outline), 6, accuracy: 1e-9)
        XCTAssertEqual(two.room.walls.filter { $0.kind == .solid }.count, 2)
        XCTAssertEqual(two.room.walls.filter { $0.kind == .virtual }.count, 1)
        // Two collinear walls: no area at all, so no outline.
        let line = build(RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0)), rawWall(Point2(6, 0), Point2(9, 0))]))
        XCTAssertEqual(line.room.walls.count, 0)
        XCTAssertFalse(line.warnings.isEmpty)
        // Two parallel walls: both open ends are bridged, giving the rectangle between them.
        let parallel = build(RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0)), rawWall(Point2(0, 3), Point2(4, 3))]))
        XCTAssertEqual(parallel.warnings.filter { if case .openBoundaryBridged = $0 { return true } else { return false } }.count, 2)
        XCTAssertEqual(Polygon.area(parallel.room.outline), 12, accuracy: 1e-9)
        XCTAssertEqual(parallel.room.walls.filter { $0.kind == .solid }.count, 2)
        XCTAssertEqual(parallel.room.walls.filter { $0.kind == .virtual }.count, 2)
    }

    func testGarbageSurfacesNeverCrash() {
        let good = Fixtures.rectangle(width: 4, depth: 3, seed: 1).canonical
        var c = good
        let nan = Double.nan, inf = Double.infinity
        func matrix(_ v: Double) -> Matrix4 { Matrix4(columnMajor: [Double](repeating: v, count: 16)) }
        c.walls += [
            RawSurface(kind: .wall, transform: matrix(nan), dimensions: Point3(2, 2.8, 0)),
            RawSurface(kind: .wall, transform: .identity, dimensions: Point3(inf, 2.8, 0)),
            RawSurface(kind: .wall, transform: .identity, dimensions: Point3(0, 2.8, 0)),
            RawSurface(kind: .wall, transform: .identity, dimensions: Point3(-3, 2.8, 0)),
            RawSurface(kind: .wall, transform: .identity, dimensions: Point3(2, 0, 0)),
            RawSurface(kind: .wall, transform: .identity, dimensions: Point3(2, nan, 0)),
        ]
        // Too short, and nearly vertical (local X mostly up).
        c.walls.append(rawWall(Point2(1, 1), Point2(1.05, 1)))
        c.walls.append(RawSurface(kind: .wall, transform: Matrix4(columnMajor: [0.05, 0.9987, 0, 0,  -0.9987, 0.05, 0, 0,  0, 0, 1, 0,  2, 1.4, -1.5, 1]),
                                   dimensions: Point3(2.8, 0.1, 0)))
        c.doors = [RawSurface(kind: .door, transform: matrix(inf), dimensions: Point3(1, 2, 0)),
                   RawSurface(kind: .door, transform: .identity, dimensions: Point3(0, 2, 0)),
                   RawSurface(kind: .door, transform: .identity, dimensions: Point3(0.01, 2, 0))]
        c.windows = [RawSurface(kind: .window, transform: .identity, dimensions: Point3(nan, nan, nan))]
        c.floors += [RawSurface(kind: .floor, transform: matrix(nan), dimensions: Point3(1, 1, 0), polygonCorners: [Point3(nan, 0, 0)])]
        let r = build(c)
        // The valid rectangle comes through untouched.
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(Polygon.area(r.room.outline), 12, accuracy: 1e-9)
        XCTAssertTrue(has(r) { $0 == .invalidSurfacesIgnored(count: 6) })
        XCTAssertTrue(has(r) { if case .shortWallsIgnored(let n, _) = $0 { return n == 1 } else { return false } })
        XCTAssertTrue(has(r) { $0 == .steepWallsIgnored(count: 1) })
        // Three doors (infinite transform, zero width, 1 cm wide) and one NaN window.
        XCTAssertTrue(has(r) { $0 == .invalidOpeningsIgnored(count: 4) })
        assertAllFinite(r)
        // All garbage, no good walls at all.
        var allBad = RawCapture()
        allBad.walls = Array(c.walls.dropFirst(4).prefix(6))
        let r2 = build(allBad)
        XCTAssertEqual(r2.room.walls.count, 0)
        assertAllFinite(r2)
    }

    func testMatrixOfTheWrongSizeDoesNotTrap() throws {
        // A hand-edited / corrupt JSON capture: Codable bypasses Matrix4's precondition.
        let id = UUID().uuidString
        let json = """
        {"id":"\(id)","kind":"wall","transform":{"columnMajor":[1,0,0]},"dimensions":{"x":3,"y":2.8,"z":0},
         "isCurved":false,"story":0,"confidence":"high"}
        """
        let surface = try JSONDecoder().decode(RawSurface.self, from: Data(json.utf8))
        XCTAssertEqual(surface.transform.columnMajor.count, 3)
        var c = Fixtures.rectangle(seed: 1).canonical
        c.walls.append(surface)
        c.doors.append(surface)
        c.windows.append(surface)
        c.floors.append(surface)
        c.objects.append(RawObject(category: "sofa", transform: surface.transform, dimensions: Point3(1, 1, 1)))
        let r = build(c)
        XCTAssertEqual(r.room.walls.count, 4)
        assertAllFinite(r)
    }

    func testDuplicateIdentifiersStillGiveUniqueWalls() {
        var c = Fixtures.lShape(seed: 1).canonical
        let shared = c.walls[0].id
        for i in c.walls.indices { c.walls[i].id = shared }
        for i in c.doors.indices { c.doors[i].id = shared }
        let r = build(c)
        XCTAssertEqual(r.room.walls.count, 6)
        XCTAssertEqual(Set(r.room.walls.map(\.id)).count, 6)
        XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9)
    }

    func testHugeAndTinyNumbersStayFinite() {
        for scale in [1e-3, 1e3, 5e4] {
            let f = Fixtures.rectangle(width: 4 * scale, depth: 3 * scale, height: 2.8, seed: 1)
            let r = build(f)
            assertAllFinite(r)
            if scale >= 1 { XCTAssertEqual(r.room.walls.count, 4, "scale \(scale)") }
            if scale < 0.1 { XCTAssertFalse(r.warnings.isEmpty, "4 mm walls are noise") }
            if scale >= 1 { XCTAssertEqual(Polygon.area(r.room.outline), 12 * scale * scale, accuracy: 12 * scale * scale * 1e-9) }
        }
    }

    func testRandomGarbageNeverCrashesAndStaysFinite() {
        for seed in UInt64(1)...UInt64(60) {
            var rng = Fixtures.SeededGenerator(seed: seed)
            let n = Int(rng.nextUnit() * 40) + 1
            var c = RawCapture()
            for _ in 0..<n {
                let yaw = rng.symmetric(Double.pi)
                let t = Point3(rng.symmetric(8), rng.symmetric(2), rng.symmetric(8))
                let dims = Point3(rng.nextUnit() * 6, 0.1 + rng.nextUnit() * 3, 0)
                c.walls.append(RawSurface(kind: .wall, transform: Matrix4.yawTranslation(yaw: yaw, t), dimensions: dims,
                                          isCurved: rng.nextBool()))
                if rng.nextBool() {
                    c.doors.append(RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: yaw, t), dimensions: dims,
                                              parentID: c.walls.randomElementDeterministic(&rng)?.id))
                }
                if rng.nextBool() {
                    c.objects.append(RawObject(category: ["sofa", "bed", "??"][Int(rng.next() % 3)],
                                               transform: Matrix4.yawTranslation(yaw: yaw, t), dimensions: Point3(1, 1, 1)))
                }
            }
            if rng.nextBool() {
                c.floors = [RawSurface(kind: .floor, transform: .identity, dimensions: Point3(4, 4, 0),
                                       polygonCorners: (0..<5).map { _ in Point3(rng.symmetric(5), rng.symmetric(5), 0) })]
            }
            let r = build(c)
            assertAllFinite(r)
            XCTAssertTrue(r.room.walls.isEmpty || r.room.walls.count >= 3, "seed \(seed): a loop has at least 3 sides")
            if r.room.walls.count >= 3 { XCTAssertTrue(Polygon.isCounterClockwise(r.room.outline) || Polygon.area(r.room.outline) < 1e-9, "seed \(seed)") }
            XCTAssertEqual(Set(r.room.walls.map(\.id)).count, r.room.walls.count, "seed \(seed): unique wall ids")
        }
    }

    func testHostileInputIsBoundedInTime() {
        // 600 random walls in a small area: a dense graph. The search budget keeps it quick.
        var rng = Fixtures.SeededGenerator(seed: 99)
        var c = RawCapture()
        for _ in 0..<600 {
            c.walls.append(RawSurface(kind: .wall, transform: Matrix4.yawTranslation(yaw: rng.symmetric(Double.pi), Point3(rng.symmetric(6), 1.4, rng.symmetric(6))),
                                      dimensions: Point3(0.5 + rng.nextUnit() * 4, 2.8, 0)))
        }
        let start = Date()
        let r = build(c)
        XCTAssertLessThan(Date().timeIntervalSince(start), 20, "debug build, dense garbage")
        assertAllFinite(r)
        // A 12 x 12 grid of 2 m cells (312 collinear-heavy walls): the outer boundary wins, interior walls dropped.
        var grid = RawCapture()
        let cells = 12
        for i in 0...cells {
            for j in 0..<cells {
                let a = Double(i) * 2, b = (Double(j) + 0.5) * 2
                grid.walls.append(rawWall(Point2(a, b - 1), Point2(a, b + 1)))
                grid.walls.append(rawWall(Point2(b - 1, a), Point2(b + 1, a)))
            }
        }
        let g = build(grid)
        XCTAssertEqual(Polygon.area(g.room.outline), 24 * 24, accuracy: 1e-6)
        XCTAssertEqual(g.room.walls.count, 4)
    }

    // MARK: Options

    func testMinWallLengthFiltersNoise() {
        var c = Fixtures.rectangle(width: 4, depth: 3, seed: 2).canonical
        c.walls.append(rawWall(Point2(1, 1), Point2(1.05, 1)))
        c.walls.append(rawWall(Point2(2, 2), Point2(2, 2.09)))
        c.walls.append(rawWall(Point2(3, 1), Point2(3.03, 1.02)))
        let r = build(c)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertTrue(has(r) { if case .shortWallsIgnored(let n, let m) = $0 { return n == 3 && m == 0.10 } else { return false } })
        // A longer minimum drops the 0.9 m ... nothing here; but shrinking it to zero keeps them as (ignored interior) walls.
        var tiny = RoomBuilder.Options.standard
        tiny.minWallLength = 0.01
        let r2 = build(c, options: tiny)
        XCTAssertEqual(r2.room.walls.count, 4)
        XCTAssertFalse(has(r2) { if case .shortWallsIgnored = $0 { return true } else { return false } })
        XCTAssertTrue(has(r2) { if case .interiorWallsDropped(let n, _) = $0 { return n == 3 } else { return false } })
    }

    func testCollinearToleranceOption() {
        // A wall in two 2.5 m pieces meeting at a 0.5 degree bend (22 mm off the line at the far end):
        // one wall at the default 2 degrees, two walls with a 179.5 degree corner at 0.4.
        let bend = 0.5 * Double.pi / 180
        let a = Point2(0, 0), kink = Point2(2.5, 0), b = kink + Point2(cos(bend), sin(bend)) * 2.5
        let top = Point2(b.x, 3)
        var c = RawCapture()
        c.walls = [rawWall(a, kink), rawWall(kink, b), rawWall(b, top), rawWall(top, Point2(0, 3)), rawWall(Point2(0, 3), a)]
        XCTAssertEqual(build(c).room.walls.count, 4)
        var tight = RoomBuilder.Options.standard
        tight.collinearToleranceDegrees = 0.4
        let r = build(c, options: tight)
        XCTAssertEqual(r.room.walls.count, 5)
        XCTAssertEqual(angles(r.room).filter { abs($0 - 179.5) < 1e-6 || abs($0 - 180.5) < 1e-6 }.count, 1)
        XCTAssertEqual(r.room.metrics.corners.filter(\.isStraight).count, 1, "RoomMetrics treats it as a straight continuation")
        XCTAssertEqual(r.room.metrics.sides.count, 4)
    }

    func testLowConfidenceWallsAreFlagged() {
        var c = Fixtures.lShape(seed: 3).canonical
        XCTAssertFalse(has(build(c)) { if case .lowConfidenceWalls = $0 { return true } else { return false } })
        c.walls[0].confidence = .low
        c.walls[3].confidence = .low
        c.walls[4].confidence = .medium
        let r = build(c)
        XCTAssertTrue(has(r) { $0 == .lowConfidenceWalls(count: 2) })
        XCTAssertEqual(r.worstSeverity, .caution)
        // A low-confidence interior wall that is dropped is not the room's problem.
        var d = Fixtures.rectangle(seed: 3, extras: extras { $0.interiorWalls = [.init(from: Point2(0, 1), to: Point2(1.2, 1))] }).canonical
        d.walls[d.walls.count - 1].confidence = .low
        XCTAssertFalse(has(build(d)) { if case .lowConfidenceWalls = $0 { return true } else { return false } })
        // Merged pieces: one low piece makes the wall low.
        var e = Fixtures.splitWall(wall: 0, seed: 3).canonical
        e.walls[1].confidence = .low
        XCTAssertTrue(has(build(e)) { $0 == .lowConfidenceWalls(count: 1) })
    }

    func testWallEndGraphIsSymmetricUnderReversal() {
        // u -> v exists iff (v reversed) -> (u reversed) does, with the same corner and cost. The loop
        // search starts every wall forwards only, which is exhaustive only for a symmetric graph.
        var rng = Fixtures.SeededGenerator(seed: 5)
        var captures: [RawCapture] = [Fixtures.lShape(noise: .realistic, seed: 4).capture,
                                      Fixtures.openPlan(noise: .realistic, seed: 4).capture,
                                      Fixtures.splitWall(gap: 0.4, seed: 4).capture]
        for _ in 0..<20 {      // dense random walls: many free ends, many bridge candidates
            var c = RawCapture()
            for _ in 0..<25 {
                c.walls.append(RawSurface(kind: .wall, transform: Matrix4.yawTranslation(yaw: rng.symmetric(Double.pi), Point3(rng.symmetric(4), 1.4, rng.symmetric(4))),
                                          dimensions: Point3(0.4 + rng.nextUnit() * 3, 2.8, 0)))
            }
            captures.append(c)
        }
        for c in captures {
            let ex = RoomBuilder.extractSegments(from: c.walls, options: .standard)
            let merged = RoomBuilder.mergeCollinear(ex.segments, options: .standard).segments
            let nodes = RoomBuilder.buildNodes(merged)
            let adj = RoomBuilder.buildEdges(nodes, options: .standard)
            var edgeCount = 0
            for (u, list) in adj.enumerated() {
                for e in list {
                    edgeCount += 1
                    let back = adj[e.to ^ 1].first { $0.to == u ^ 1 }
                    XCTAssertNotNil(back, "edge \(u) -> \(e.to) has no reverse")
                    if let b = back {
                        XCTAssertEqual(b.isBridge, e.isBridge)
                        XCTAssertEqual(b.cost, e.cost, accuracy: 1e-9)
                        if let c1 = b.corner, let c2 = e.corner { XCTAssertLessThan(c1.distance(to: c2), 1e-9) }
                    }
                }
            }
            XCTAssertGreaterThan(edgeCount, 0)
        }
    }

    func testSearchBudgetExhaustionIsReportedAndSurvivable() {
        let f = Fixtures.rectangle(width: 4, depth: 3, seed: 1)
        for budget in [0, 1, 2, Int.min, -7] {
            var o = RoomBuilder.Options.standard
            o.searchBudget = budget
            let r = build(f, options: o)
            XCTAssertTrue(has(r) { $0 == .searchBudgetExhausted }, "budget \(budget)")
            // No loop was found in time, so the (loudly flagged) floor polygon outline is used.
            XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: .floorPolygon) }, "budget \(budget)")
            XCTAssertEqual(r.room.walls.count, 4, "budget \(budget)")
            XCTAssertEqual(Polygon.area(r.room.outline), 12, accuracy: 1e-9, "budget \(budget)")
            XCTAssertTrue(r.room.walls.allSatisfy { $0.kind == .solid }, "walls lie along the scanned surfaces")
            assertAllFinite(r)
        }
        // A generous budget never trips on a normal room.
        XCTAssertFalse(has(build(f)) { $0 == .searchBudgetExhausted })
        XCTAssertEqual(RoomBuilder.Options(), RoomBuilder.Options.standard)
    }

    // MARK: Warnings API

    func testWarningMessagesAndSeverities() {
        let id = UUID()
        let all: [RoomBuilder.BuildWarning] = [
            .noWallSurfaces, .tooFewWalls(count: 1), .tooFewWalls(count: 2), .invalidSurfacesIgnored(count: 1), .invalidSurfacesIgnored(count: 3),
            .shortWallsIgnored(count: 2, minLength: 0.1), .steepWallsIgnored(count: 1),
            .collinearWallsMerged(pieces: 2, walls: 1), .interiorWallsDropped(count: 2, totalLength: 3.5),
            .openBoundaryBridged(length: 3.2, at: Point2(1, 2)),
            .cornersAdjusted(gapsClosed: 2, maxGap: 0.11, wallsTrimmed: 0, maxTrim: 0),
            .cornersAdjusted(gapsClosed: 0, maxGap: 0, wallsTrimmed: 1, maxTrim: 0.3),
            .curvedWallsStoredAsChords(count: 1), .lowConfidenceWalls(count: 1), .lowConfidenceWalls(count: 3), .searchBudgetExhausted,
            .noClosedLoop(fallback: .floorPolygon), .noClosedLoop(fallback: .convexHull),
            .floorAreaMismatch(floorArea: 24.2, outlineArea: 20), .selfIntersectingOutline, .roomAreaOutOfRange(area: 0.5),
            .missingFloorSurface, .openingUnmatched(id: id, kind: .door, nearestDistance: 0.8),
            .openingUnmatched(id: id, kind: .window, nearestDistance: nil), .openingAdjusted(id: id, kind: .opening),
            .invalidOpeningsIgnored(count: 1), .invalidObjectsIgnored(count: 4)]
        XCTAssertEqual(Set(all).count, all.count, "every case is Hashable and distinct")
        for w in all {
            XCTAssertFalse(w.message.isEmpty)
            XCTAssertFalse(w.message.contains("Optional"), w.message)
            XCTAssertFalse(w.message.contains("NexaFixCore") || w.message.contains("Point2"), "no debug formatting: \(w.message)")
        }
        XCTAssertEqual(RoomBuilder.BuildWarning.noClosedLoop(fallback: .floorPolygon).severity, .critical)
        XCTAssertEqual(RoomBuilder.BuildWarning.openBoundaryBridged(length: 1, at: .zero).severity, .caution)
        XCTAssertEqual(RoomBuilder.BuildWarning.missingFloorSurface.severity, .info)
        XCTAssertTrue(RoomBuilder.BuildWarning.Severity.info < .caution && RoomBuilder.BuildWarning.Severity.caution < .critical)
        XCTAssertTrue(RoomBuilder.BuildWarning.interiorWallsDropped(count: 1, totalLength: 1).message.contains("1 interior wall "))
        XCTAssertTrue(RoomBuilder.BuildWarning.openBoundaryBridged(length: 3.2, at: Point2(1, 2)).message.contains("3.20 m"))
        XCTAssertTrue(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 24.2, outlineArea: 20).message.contains("24.20"))
    }

    // MARK: Integration

    func testRawCaptureAndRoomSurviveJSONAndRebuildIdentically() throws {
        let f = Fixtures.tShape(doors: [.door(wall: 0, offset: 0.5)], windows: [.window(wall: 4, offset: 1, width: 1.5)],
                                noise: .light, seed: 5,
                                extras: extras { $0.objects = [.init(category: "bed", center: Point2(3, 4), width: 1.6, depth: 2, height: 0.5)] })
        let direct = build(f)
        // The capture survives JSON (the app stores RawCapture) and rebuilds the identical room.
        let data = try JSONEncoder().encode(f.capture)
        let decoded = try JSONDecoder().decode(RawCapture.self, from: data)
        XCTAssertEqual(decoded, f.capture)
        XCTAssertEqual(build(decoded), direct)
        // And the room survives JSON.
        let roomData = try JSONEncoder().encode(direct.room)
        XCTAssertEqual(try JSONDecoder().decode(Room.self, from: roomData), direct.room)
    }

    func testVerificationFlowsThroughBuiltRooms() {
        // The builder only ever produces scanned values; verifying a built wall changes `value`, never `scanned`.
        var room = build(Fixtures.rectangle(width: 4, depth: 3, seed: 1)).room
        let before = room.walls[0].length.scanned
        room.walls[0].length.verify(4.012, source: .laser, date: now)
        XCTAssertEqual(room.walls[0].length.scanned, before)
        XCTAssertEqual(room.walls[0].length.value, 4.012)
        XCTAssertEqual(room.metrics.sides[0].length, 4.012, accuracy: 1e-12)
        XCTAssertFalse(room.metrics.sides[0].isVerified == false)
        XCTAssertTrue(build(Fixtures.rectangle(seed: 1)).room.walls.allSatisfy { !$0.length.isVerified })
    }

    // MARK: Fixtures themselves

    func testFixturesAreDeterministicAndLookLikeRoomPlan() {
        let a = Fixtures.lShape(doors: [.door(wall: 0, offset: 1)], noise: .realistic, seed: 42)
        let b = Fixtures.lShape(doors: [.door(wall: 0, offset: 1)], noise: .realistic, seed: 42)
        XCTAssertEqual(a.capture, b.capture)
        XCTAssertEqual(a.canonical, b.canonical)
        XCTAssertNotEqual(a.capture, Fixtures.lShape(doors: [.door(wall: 0, offset: 1)], noise: .realistic, seed: 43).capture)
        // Ids come from the fixture, not the seed.
        XCTAssertEqual(Set(a.capture.walls.map(\.id)), Set(Fixtures.lShape(seed: 7).capture.walls.map(\.id)))
        // Surfaces: wall dimensions = (length, height, 0); the Y axis is vertical; doors have a parent that exists.
        for w in a.capture.walls {
            XCTAssertEqual(w.kind, .wall)
            XCTAssertEqual(w.transform.yAxis.y, 1, accuracy: 1e-12)
            XCTAssertEqual(w.dimensions.z, 0)
            XCTAssertEqual(w.transform.xAxis.length, 1, accuracy: 1e-9)
        }
        let ids = Set(a.capture.walls.map(\.id))
        for d in a.capture.doors { XCTAssertTrue(ids.contains(d.parentID!)) }
        // The floor polygon is in the floor's local frame and maps back onto the outline.
        let floor = a.capture.floors[0]
        let plan = floor.polygonCorners!.map { floor.transform.transform($0).plan }
        assertSamePoints(plan, a.corners, tol: 1e-9)
        XCTAssertEqual(a.floorArea ?? 0, a.expectedArea, accuracy: 1e-9)
        // Shuffle and flip: seeds change the order and flips, never the geometry.
        let orders = Set((1...10).map { a.reshuffled(seed: UInt64($0)).walls.map(\.id) })
        XCTAssertGreaterThan(orders.count, 5)
        let r1 = Fixtures.SeededGenerator(seed: 5), r2 = Fixtures.SeededGenerator(seed: 5)
        var g1 = r1, g2 = r2
        XCTAssertEqual((0..<5).map { _ in g1.next() }, (0..<5).map { _ in g2.next() })
        var items = Array(0..<20)
        var g3 = Fixtures.SeededGenerator(seed: 1)
        g3.shuffle(&items)
        XCTAssertEqual(items.sorted(), Array(0..<20))
        XCTAssertNotEqual(items, Array(0..<20))
        // Known SplitMix64 vector (seed 0): first output 0xE220A8397B1DCDAF.
        var z = Fixtures.SeededGenerator(seed: 0)
        XCTAssertEqual(z.next(), 0xE220A8397B1DCDAF)
    }

    func testSampleObjectsFitAndComeBackAsObjects() {
        let objs = Fixtures.sampleObjects(width: 4, depth: 3)
        XCTAssertEqual(objs.map(\.category), ["sofa", "table", "storage", "chair"])
        let f = Fixtures.rectangle(width: 4, depth: 3, seed: 2, extras: extras { $0.objects = objs; $0.origin = Point2(1, 1) })
        XCTAssertEqual(f.capture.objects.count, 4)
        let r = build(f)
        XCTAssertEqual(r.room.objects.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.chair, .sofa, .storage, .table])
        for o in r.room.objects {
            XCTAssertTrue(o.footprint.allSatisfy { Polygon.contains(r.room.outline, $0) }, "\(o.kind) fits inside the room")
            XCTAssertGreaterThanOrEqual(o.elevation, 0)
        }
        // Shifted by the origin (1, 1): the sofa centre is (3, 1.5).
        assertPoint(r.room.objects.first { $0.kind == .sofa }!.center, 3, 1.5)
        XCTAssertEqual(r.warnings, [])
    }

    func testNoiseAmplitudesAreRespectedByTheGenerator() {
        let truth = Fixtures.rectangle(width: 6, depth: 5, seed: 1)
        for seed in UInt64(1)...UInt64(30) {
            let f = Fixtures.rectangle(width: 6, depth: 5, noise: .realistic, seed: seed)
            for (n, t) in zip(f.canonical.walls, truth.canonical.walls) {
                XCTAssertEqual(n.id, t.id)
                // Length changes by the two end errors (each at most 0.04) plus nothing else.
                XCTAssertLessThanOrEqual(abs(n.dimensions.x - t.dimensions.x), 2 * 0.04 + 1e-12)
                XCTAssertLessThanOrEqual(abs(n.dimensions.y - t.dimensions.y), 0.010 + 1e-12)
                let d = n.transform.translation - t.transform.translation
                XCTAssertLessThanOrEqual(abs(d.x) + abs(d.z), 2 * (0.04 + 0.010) + 1e-9)
            }
        }
    }

    // =====================================================================================================
    // MARK: Review fixes
    //
    // The builder may be uncertain, but it must never be silently wrong: an outline that is far from the
    // truth has to carry a critical warning. These tests reproduce the findings of the independent review
    // (open-plan bridging through free-standing walls, garbage loops beating the floor polygon, the
    // 1 m overshoot cliff, collinear continuations, closed pods) with numbers worked out by hand.
    // =====================================================================================================

    /// A rectangle with the west wall never scanned (open plan) plus extra wall surfaces.
    private func openWest(width: Double = 5, depth: Double = 4, interior: [Fixtures.InteriorWall] = [],
                          noise: Fixtures.Noise = .none, seed: UInt64 = 1, floor: Bool = true,
                          rotation: Double = 0, origin: Point2 = .zero) -> Fixtures.Fixture {
        Fixtures.openPlan(width: width, depth: depth, missingWall: 3, noise: noise, seed: seed,
                          extras: extras { $0.interiorWalls = interior; $0.includeFloor = floor
                                           $0.rotationDegrees = rotation; $0.origin = origin })
    }

    private func wall(_ a: Point2, _ b: Point2) -> Fixtures.InteriorWall { .init(from: a, to: b) }

    /// The room is recovered exactly: area, wall count and number of virtual walls.
    private func assertRecovered(_ r: RoomBuilder.Result, area: Double, walls: Int, virtual: Int, tolerance: Double = 1e-6,
                                 _ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Polygon.area(r.room.outline), area, accuracy: tolerance, "\(tag): area", file: file, line: line)
        XCTAssertEqual(r.room.walls.count, walls, "\(tag): wall count", file: file, line: line)
        XCTAssertEqual(virtualCount(r.room), virtual, "\(tag): virtual walls", file: file, line: line)
        XCTAssertNotEqual(r.worstSeverity, .critical, "\(tag): a correct room is not critical", file: file, line: line)
    }

    /// Wrong is allowed, silent is not: an outline more than 10 % off the truth must be critical.
    private func assertNeverSilentlyWrong(_ r: RoomBuilder.Result, truth: Double, _ tag: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let area = Polygon.area(r.room.outline)
        if abs(area - truth) / truth > 0.10 {
            XCTAssertEqual(r.worstSeverity, .critical,
                           "\(tag): outline \(area) m2 vs truth \(truth) m2 was shipped without a critical warning: \(r.warnings.map(\.message))",
                           file: file, line: line)
            XCTAssertFalse(r.isReliable, "\(tag)", file: file, line: line)
        }
    }

    // MARK: Overlap area (the floor-polygon arbiter)

    func testOverlapAreaOfPolygonsMatchesHandComputedValues() {
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2] {
            [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]
        }
        func overlap(_ a: [Point2], _ b: [Point2]) -> Double { RoomBuilder.overlapArea(a, b) }
        // Offset unit squares overlap in a 0.5 x 0.5 square.
        XCTAssertEqual(overlap(rect(0, 0, 1, 1), rect(0.5, 0.5, 1.5, 1.5)), 0.25, accuracy: 1e-12)
        // Identical, contained, disjoint, touching.
        XCTAssertEqual(overlap(rect(0, 0, 4, 3), rect(0, 0, 4, 3)), 12, accuracy: 1e-12)
        XCTAssertEqual(overlap(rect(0, 0, 4, 3), rect(1, 1, 2, 2)), 1, accuracy: 1e-12)
        XCTAssertEqual(overlap(rect(0, 0, 1, 1), rect(2, 2, 3, 3)), 0, accuracy: 1e-12)
        XCTAssertEqual(overlap(rect(0, 0, 1, 1), rect(1, 0, 2, 1)), 0, accuracy: 1e-12)
        // 6 x 4 rectangle against the L (6 x 4 with the 2 x 2 notch at the top right): the L is inside, area 20.
        let l = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        XCTAssertEqual(overlap(rect(0, 0, 6, 4), l), 20, accuracy: 1e-12)
        XCTAssertEqual(overlap(l, rect(0, 0, 6, 4)), 20, accuracy: 1e-12, "symmetric")
        // The notch square [4,6] x [2,4] has nothing in common with the L.
        XCTAssertEqual(overlap(l, rect(4, 2, 6, 4)), 0, accuracy: 1e-12)
        // Half of a 4 x 4 square lies in the L's lower strip: [0,6] x [0,2] is inside the L; with [2,6] x [1,3]
        // the common part is [2,6] x [1,2] (4) plus [2,4] x [2,3] (2) = 6.
        XCTAssertEqual(overlap(l, rect(2, 1, 6, 3)), 6, accuracy: 1e-12)
        // Diamond |x| + |y| <= 1 (area 2) against [0,1] x [0,1]: the triangle of area 1/2; against [-1,1]^2: all of it.
        let diamond = [Point2(1, 0), Point2(0, 1), Point2(-1, 0), Point2(0, -1)]
        XCTAssertEqual(overlap(diamond, rect(0, 0, 1, 1)), 0.5, accuracy: 1e-12)
        XCTAssertEqual(overlap(diamond, rect(-1, -1, 1, 1)), 2, accuracy: 1e-12)
        // Triangle (0,0) (4,0) (0,4) against the square [0,2]^2 (its corner touches the hypotenuse): the square.
        let tri = [Point2(0, 0), Point2(4, 0), Point2(0, 4)]
        XCTAssertEqual(overlap(tri, rect(0, 0, 2, 2)), 4, accuracy: 1e-12)
        XCTAssertEqual(overlap(tri, rect(0, 0, 4, 4)), 8, accuracy: 1e-12)
        // Winding does not matter; degenerate input gives 0.
        XCTAssertEqual(overlap(rect(0, 0, 1, 1).reversed(), rect(0.5, 0.5, 1.5, 1.5)), 0.25, accuracy: 1e-12)
        XCTAssertEqual(overlap([], rect(0, 0, 1, 1)), 0)
        XCTAssertEqual(overlap([Point2(0, 0), Point2(1, 1)], rect(0, 0, 1, 1)), 0)
    }

    // MARK: Open plan with free-ended walls near the open side

    func testFreeEndedWallsNearTheOpenSideDoNotBecomeTheBoundary() {
        let cases: [(String, [Fixtures.InteriorWall])] = [
            ("stray 0.5 m from the open side", [wall(Point2(0.5, 1.7), Point2(0.5, 2.3))]),
            ("stub off the south wall", [wall(Point2(1.0, 0), Point2(1.0, 1.2))]),
            ("stub off the north wall", [wall(Point2(1.0, 4), Point2(1.0, 2.9))]),
            ("two floating walls", [wall(Point2(2, 1), Point2(2, 2)), wall(Point2(3, 2), Point2(3, 3))]),
            ("four strays", [wall(Point2(0.4, 1.0), Point2(0.4, 1.8)), wall(Point2(0.6, 2.4), Point2(0.6, 3.2)),
                             wall(Point2(2, 0), Point2(2, 0.9)), wall(Point2(3.5, 3.1), Point2(3.5, 4))]),
        ]
        for (name, interior) in cases {
            for floor in [true, false] {
                let tag = "\(name), floor \(floor)"
                let f = openWest(interior: interior, floor: floor)
                let r = build(f)
                assertRecovered(r, area: 20, walls: 4, virtual: 1, tag)
                let v = r.room.walls.first { $0.kind == .virtual }
                if let v { assertPoint(v.midpoint, 0, 2, tol: 1e-9, tag) }
                XCTAssertTrue(has(r) { if case .interiorWallsDropped(let n, _) = $0 { return n == interior.count } else { return false } }, tag)
                // Reliable open-plan result: caution at most, and it says it bridged.
                XCTAssertEqual(r.worstSeverity, .caution, tag)
            }
        }
    }

    func testFloatingWallSweepAcrossTheOpenSide() {
        // A free-standing vertical wall centred at y = 2, of every length from 0.4 to 3 m, at every distance from
        // the open side up to the middle of the room: the open side is always the one 4 m virtual wall.
        for length in [0.4, 0.8, 1.5, 2.2, 3.0] {
            for x in [0.1, 0.3, 0.5, 0.8, 1.2, 1.8, 2.5, 3.5, 4.4] {
                let f = openWest(interior: [wall(Point2(x, 2 - length / 2), Point2(x, 2 + length / 2))])
                let r = build(f)
                assertRecovered(r, area: 20, walls: 4, virtual: 1, "wall \(length) m at x \(x)")
            }
        }
        // Same with scan noise.
        for seed in UInt64(1)...UInt64(12) {
            let f = openWest(interior: [wall(Point2(0.6, 1.5), Point2(0.6, 2.7)), wall(Point2(1.5, 0), Point2(1.5, 1.0))],
                             noise: .realistic, seed: seed, rotation: Double(seed) * 29)
            let r = build(f)
            XCTAssertEqual(r.room.walls.count, 4, "seed \(seed)")
            XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 0.4, "seed \(seed)")
            XCTAssertEqual(virtualCount(r.room), 1, "seed \(seed)")
        }
    }

    func testTwoNonAdjacentMissingWallsAreBridgedByTheFloorPolygon() {
        func lWithout(_ omitted: [Int], floor: Bool = true) -> RoomBuilder.Result {
            var e = Fixtures.Extras()
            e.tweaks = omitted.map { Fixtures.WallTweak(wall: $0, omit: true) }
            e.includeFloor = floor
            let f = Fixtures.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)],
                                     seed: 5, extras: e)
            return build(f)
        }
        // From the review: these three used to come out as 2 m2, 12 m2 and 8 m2.
        for omitted in [[0, 3], [0, 2], [3, 5], [1, 3], [2, 4], [2, 5], [1, 4], [1, 5], [0, 4]] {
            let r = lWithout(omitted)
            assertRecovered(r, area: 20, walls: 6, virtual: 2, "L without \(omitted)")
        }
    }

    func testEveryPairOfNonAdjacentMissingWallsIsRecoveredOrFlaggedCritical() {
        let shapes: [(String, (Fixtures.Extras) -> Fixtures.Fixture)] = [
            ("L", { Fixtures.lShape(noise: .light, seed: 3, extras: $0) }),
            ("U", { Fixtures.uShape(noise: .light, seed: 4, extras: $0) }),
            ("T", { Fixtures.tShape(noise: .light, seed: 5, extras: $0) }),
            ("chamfer", { Fixtures.chamfered(noise: .light, seed: 6, extras: $0) }),
            ("trapezoid", { Fixtures.trapezoid(noise: .light, seed: 7, extras: $0) }),
            ("rectangle", { Fixtures.rectangle(width: 5, depth: 4, noise: .light, seed: 8, extras: $0) }),
        ]
        var exact = 0, flagged = 0
        for (name, make) in shapes {
            let n = make(Fixtures.Extras()).corners.count
            for i in 0..<n {
                for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                    var e = Fixtures.Extras()
                    e.tweaks = [.init(wall: i, omit: true), .init(wall: j, omit: true)]
                    let f = make(e)
                    let r = build(f)
                    let tag = "\(name) without walls \(i) and \(j)"
                    assertNeverSilentlyWrong(r, truth: f.expectedArea, tag)
                    if abs(Polygon.area(r.room.outline) - f.expectedArea) / f.expectedArea < 0.03 { exact += 1 } else { flagged += 1 }
                    assertAllFinite(r)
                }
            }
        }
        // Most of them are genuinely recoverable from the walls plus the floor polygon.
        XCTAssertGreaterThan(exact, flagged, "recovered \(exact), flagged \(flagged)")
    }

    // MARK: Gross failures are escalated

    func testOutsideStubsAndACollinearContinuationDoNotReplaceTheRoom() {
        // 7 x 8 closed room; outside the building: a 1.2 m collinear continuation of the south wall (over the
        // 1 m overshoot limit) and two perpendicular stubs. Used to come out as a 3.45 m2 "room" of the stubs
        // with all four real walls dropped and no critical warning.
        let outside = [wall(Point2(7.004, 0), Point2(8.2, 0)), wall(Point2(7, 4.7), Point2(8.8, 4.7)),
                       wall(Point2(7, 6.7), Point2(8.65, 6.7))]
        for floor in [true, false] {
            var e = Fixtures.Extras()
            e.interiorWalls = outside
            e.includeFloor = floor
            let f = Fixtures.rectangle(width: 7, depth: 8, seed: 4, extras: e)
            let r = build(f)
            assertRecovered(r, area: 56, walls: 4, virtual: 0, "floor \(floor)")
            XCTAssertEqual(r.worstSeverity, .caution, "floor \(floor)")
            XCTAssertTrue(has(r) { if case .wallsOutsideRoomIgnored(let c, _) = $0 { return c >= 2 } else { return false } }, "the stubs are reported as outside the room")
        }
        // Whatever the rotation and noise: right, or loudly wrong.
        for seed in UInt64(1)...UInt64(30) {
            var e = Fixtures.Extras()
            e.rotationDegrees = Double(seed) * 37
            e.interiorWalls = outside
            let f = Fixtures.rectangle(width: 7, depth: 8, noise: .realistic, seed: seed, extras: e)
            let r = build(f)
            assertNeverSilentlyWrong(r, truth: 56, "seed \(seed)")
            XCTAssertEqual(Polygon.area(r.room.outline), 56, accuracy: 1.0, "seed \(seed): this one is recoverable")
        }
    }

    func testAClosedPodIsNotTheRoomWhenTheRealBoundaryCannotBeClosed() {
        // Open-plan 10 x 6 room whose 10 m north side was never scanned (over the 6.5 m bridging limit), three
        // real walls and a closed 2.0 x 1.6 pod made of four interior wall surfaces.
        let pod = [wall(Point2(4, 2), Point2(6, 2)), wall(Point2(6, 2), Point2(6, 3.6)),
                   wall(Point2(6, 3.6), Point2(4, 3.6)), wall(Point2(4, 3.6), Point2(4, 2))]
        for floor in [true, false] {
            var e = Fixtures.Extras()
            e.tweaks = [.init(wall: 2, omit: true)]
            e.interiorWalls = pod
            e.includeFloor = floor
            let f = Fixtures.rectangle(width: 10, depth: 6, seed: 2, extras: e)
            let r = build(f)
            let tag = "floor \(floor)"
            XCTAssertEqual(r.worstSeverity, .critical, tag)
            XCTAssertFalse(r.isReliable, tag)
            XCTAssertGreaterThan(Polygon.area(r.room.outline), 50, "\(tag): the pod (3.2 m2) is not the room")
            XCTAssertEqual(r.outlineSource, floor ? .floorPolygon : .convexHull, tag)
            XCTAssertTrue(has(r) { $0 == .noClosedLoop(fallback: floor ? .floorPolygon : .convexHull) }, tag)
        }
        // 12 x 9 villa room with the 9 m side missing.
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 3, omit: true)]
        e.interiorWalls = [wall(Point2(5, 4), Point2(6.2, 4)), wall(Point2(6.2, 4), Point2(6.2, 4.9)),
                           wall(Point2(6.2, 4.9), Point2(5, 4.9)), wall(Point2(5, 4.9), Point2(5, 4))]
        let villa = build(Fixtures.rectangle(width: 12, depth: 9, seed: 3, extras: e))
        XCTAssertEqual(villa.worstSeverity, .critical)
        XCTAssertGreaterThan(Polygon.area(villa.room.outline), 80)
    }

    func testAPodInsideAnOpenPlanRoomIsDroppedWhenTheRoomCanBeBridged() {
        // 6 x 4 with the west wall missing plus a closed pod: the room is the 24 m2, the pod is furniture.
        for (w, h) in [(1.8, 1.5), (3.0, 2.0)] {
            let x0 = 2.0, y0 = 1.0
            let pod = [wall(Point2(x0, y0), Point2(x0 + w, y0)), wall(Point2(x0 + w, y0), Point2(x0 + w, y0 + h)),
                       wall(Point2(x0 + w, y0 + h), Point2(x0, y0 + h)), wall(Point2(x0, y0 + h), Point2(x0, y0))]
            for floor in [true, false] {
                let r = build(openWest(width: 6, depth: 4, interior: pod, floor: floor))
                assertRecovered(r, area: 24, walls: 4, virtual: 1, "pod \(w) x \(h), floor \(floor)")
            }
        }
    }

    func testTwoAdjacentMissingSidesWithAFloorFallBackToTheFloorPolygonLoudly() {
        // South and east walls only: the 6.4 m diagonal used to be accepted as a 10 m2 triangle with a caution
        // (and a 6 x 4 room, 7.2 m diagonal, fell back loudly: severity depended on 0.1 m). The floor polygon
        // proves the triangle is half the room, so both ways give the floor polygon with a critical warning.
        for (w, d) in [(5.0, 4.0), (6.0, 4.0), (4.0, 4.0)] {
            var e = Fixtures.Extras()
            e.tweaks = [.init(wall: 2, omit: true), .init(wall: 3, omit: true)]
            let f = Fixtures.rectangle(width: w, depth: d, seed: 3, extras: e)
            let r = build(f)
            XCTAssertEqual(r.worstSeverity, .critical, "\(w) x \(d)")
            XCTAssertEqual(r.outlineSource, .floorPolygon)
            XCTAssertEqual(Polygon.area(r.room.outline), w * d, accuracy: 1e-9, "\(w) x \(d)")
            XCTAssertEqual(r.room.walls.filter { $0.kind == .solid }.count, 2)
        }
        // Without a floor surface there is nothing to compare with: the bridged triangle stays a caution.
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 2, omit: true), .init(wall: 3, omit: true)]
        e.includeFloor = false
        let r = build(Fixtures.rectangle(width: 5, depth: 4, seed: 3, extras: e))
        XCTAssertEqual(Polygon.area(r.room.outline), 10, accuracy: 1e-9)
        XCTAssertEqual(r.worstSeverity, .caution)
    }

    // MARK: Overshoot past a corner and collinear continuations

    func testWallsRunningFarPastTheirCornersAreTrimmedNotDropped() {
        // The old 1.0 m limit was a cliff: by 1.0 trimmed, by 1.1 the real 7.2 m wall was dropped for a virtual one.
        for by in [0.9, 1.0, 1.1, 1.5, 2.5, 4.0] {
            for wall in 0..<4 {
                let f = Fixtures.overshootingWall(width: 5, depth: 4, wall: wall, by: by, seed: UInt64(wall + 3))
                let r = build(f)
                let tag = "wall \(wall) by \(by)"
                assertRecovered(r, area: 20, walls: 4, virtual: 0, tag)
                XCTAssertEqual(r.room.walls.map { ($0.length.scanned * 1e6).rounded() / 1e6 }.sorted(), [4, 4, 5, 5], tag)
                XCTAssertTrue(r.room.walls.allSatisfy { $0.kind == .solid }, tag)
                // The trim is reported, not hidden.
                XCTAssertTrue(has(r) { if case .cornersAdjusted(_, _, let t, let m) = $0 { return t >= 1 && abs(m - by) < 1e-9 } else { return false } }, tag)
            }
        }
        // Every wall overshooting 1.5 m (was 32 m2 with two virtual walls).
        let all = build(Fixtures.rectangle(width: 5, depth: 4, seed: 9, extras: extras { $0.overshoot = 1.5 }))
        assertRecovered(all, area: 20, walls: 4, virtual: 0, "all walls +1.5")
        XCTAssertEqual(all.room.walls.map { ($0.length.scanned * 1e6).rounded() / 1e6 }.sorted(), [4, 4, 5, 5])
    }

    func testACollinearPieceOutsideTheRoomDoesNotLengthenTheBoundaryWall() {
        // Literal repro from the review: rotated room, light noise, a 2.5 m piece continuing the south wall
        // 5 cm past the corner. Used to give a 6.4 m "solid" wall and a bogus virtual wall.
        var e = CaptureFixtures.Extras()
        e.rotationDegrees = 240.30554172628985
        e.interiorWalls = [.init(from: Point2(3.889932881187837, 0), to: Point2(6.412974386359851, 0))]
        let f = CaptureFixtures.rectangle(width: 3.839932881187837, depth: 6.328963773621832, noise: .light, seed: 6, extras: e)
        let r = build(f)
        XCTAssertEqual(r.room.walls.count, 4)
        XCTAssertEqual(virtualCount(r.room), 0)
        XCTAssertEqual(Polygon.area(r.room.outline), 3.839932881187837 * 6.328963773621832, accuracy: 0.15)
        let lengths = r.room.walls.map { $0.length.scanned }.sorted()
        XCTAssertEqual(lengths[0], 3.84, accuracy: 0.1); XCTAssertEqual(lengths[2], 6.33, accuracy: 0.1)
        XCTAssertLessThan(lengths[3], 6.5, "no wall is 6.4 m of south wall plus continuation")
        XCTAssertNotEqual(r.worstSeverity, .critical)
    }

    func testCollinearNeighbourBeyondACornerGapDoesNotSwallowTheCorner() {
        // 5 x 4 room, perfect walls. An extra wall continues the EAST wall beyond the north-east corner after a
        // gap about as wide as a wall is thick (merging them used to make the east wall 6.5 m, over the
        // overshoot limit: critical "rescan" or a convex hull of 26.25 m2).
        for gap in [0.04, 0.10, 0.12, 0.14, 0.17, 0.30] {
            for length in [0.3, 0.8, 2.0, 2.4] {
                for floor in [true, false] {
                    var e = Fixtures.Extras()
                    e.interiorWalls = [wall(Point2(5, 4 + gap), Point2(5, 4 + gap + length))]
                    e.includeFloor = floor
                    let r = build(Fixtures.rectangle(width: 5, depth: 4, seed: 5, extras: e))
                    assertRecovered(r, area: 20, walls: 4, virtual: 0, "gap \(gap) length \(length) floor \(floor)")
                    XCTAssertEqual(r.room.walls.map { ($0.length.scanned * 1e6).rounded() / 1e6 }.sorted(), [4, 4, 5, 5],
                                   "gap \(gap) length \(length) floor \(floor)")
                }
            }
        }
        // An L-shape (6 x 4, notch 2 x 2) with a partition (4,2)-(4,0) that continues the notch-side wall x = 4
        // down to the south wall: critical fallback before.
        for length in [0.5, 1.0, 2.0] {
            var e = Fixtures.Extras()
            e.interiorWalls = [wall(Point2(4, 2 - 0.03), Point2(4, 2 - length))]
            let f = Fixtures.lShape(width: 6, depth: 4, notchWidth: 2, notchDepth: 2, seed: 6, extras: e)
            let r = build(f)
            assertRecovered(r, area: 20, walls: 6, virtual: 0, "partition \(length)")
        }
    }

    // MARK: Openings

    func testOpeningCentredOnAVirtualWallIsNotStolenByANearbySolidCornerWall() {
        let f = openWest(seed: 3)
        let west = build(f).room.walls.first { $0.kind == .virtual }!
        // Window centred exactly on the missing west wall line, at every height from the corner upwards.
        for cy in [0.2, 0.3, 0.35, 0.39, 0.45, 0.6, 1.0, 2.0, 3.0] {
            var c = f.canonical
            c.windows = [RawSurface(kind: .window, transform: Matrix4.yawTranslation(yaw: Double.pi / 2, Point3(0, 1.4, -cy)),
                                    dimensions: Point3(0.4, 1.0, 0))]
            let r = build(c)
            XCTAssertEqual(r.room.openings.first?.wallID, west.id, "centre at y = \(cy)")
        }
        // A window clearly nearest to a solid wall still goes to that wall.
        var c = f.canonical
        c.windows = [RawSurface(kind: .window, transform: Matrix4.yawTranslation(yaw: 0, Point3(2.5, 1.4, -0.1)),
                                dimensions: Point3(1.0, 1.0, 0))]
        let south = build(c).room.walls.first { abs($0.start.y) < 1e-9 && abs($0.end.y) < 1e-9 }!
        XCTAssertEqual(build(c).room.openings.first?.wallID, south.id)
    }

    func testParentIdIsTrustedOnlyWhileItIsTheNearestWall() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3)
        let southID = f.wallSurfaceIDs[0][0], eastID = f.wallSurfaceIDs[1][0]
        let base = build(f.canonical).room
        let south = base.walls.first { abs($0.start.y) < 1e-9 && abs($0.end.y) < 1e-9 }!
        let east = base.walls.first { abs($0.start.x - 5) < 1e-9 && abs($0.end.x - 5) < 1e-9 }!
        // A 0.9 m door centred on the south wall at x = 4.5 whose parent says "east wall" (0.5 m away):
        // it used to be attached to the east wall, flush to its start, 0.9 m from where it is.
        var c = f.canonical
        c.doors = [RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(4.5, 1.05, 0)),
                              dimensions: Point3(0.9, 2.1, 0), parentID: eastID)]
        let r = build(c)
        XCTAssertEqual(r.room.openings.first?.wallID, south.id)
        XCTAssertEqual(r.room.openings.first?.offsetFromWallStart ?? -1, 4.05, accuracy: 1e-9)
        XCTAssertFalse(has(r) { if case .openingAdjusted = $0 { return true } else { return false } })
        // The parent still wins when both walls are equally near (a door at the corner): clamped, and reported loudly.
        for past in [0.05, 0.2, 0.5, 0.9] {
            var d = f.canonical
            d.doors = [RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(5 + past, 1.05, 0)),
                                  dimensions: Point3(0.9, 2.1, 0), parentID: southID)]
            let rr = build(d)
            XCTAssertEqual(rr.room.openings.first?.wallID, south.id, "past \(past)")
            XCTAssertEqual(rr.room.openings.first?.offsetFromWallStart ?? -1, 4.1, accuracy: 1e-9, "past \(past)")
            let moved = rr.warnings.compactMap { w -> Double? in
                if case .openingAdjusted(_, _, let m, _) = w { return m } else { return nil }
            }
            XCTAssertEqual(moved.count, 1, "past \(past)")
            XCTAssertEqual(moved.first ?? 0, past + 0.45, accuracy: 1e-9, "wanted offset \(5 + past - 0.45), placed at 4.1")
            XCTAssertEqual(rr.worstSeverity, .caution, "a door moved by more than 10 cm is a caution")
            XCTAssertTrue(rr.warnings.contains { $0.message.contains(String(format: "%.2f", past + 0.45)) }, "the message carries the distance")
        }
        // A tiny shift stays routine (info).
        var tiny = f.canonical
        tiny.doors = [RawSurface(kind: .door, transform: Matrix4.yawTranslation(yaw: 0, Point3(0.5, 1.05, 0)),
                                 dimensions: Point3(0.9, 2.1, 0), parentID: southID)]      // wants offset 0.05: fine
        XCTAssertTrue(build(tiny).warnings.isEmpty)
        tiny.doors[0].transform = Matrix4.yawTranslation(yaw: 0, Point3(0.42, 1.05, 0))   // wants -0.03: 3 cm shift
        let t = build(tiny)
        XCTAssertEqual(t.worstSeverity, .info)
        XCTAssertEqual(t.room.openings.first?.wallID, south.id)
        _ = east
    }

    func testNarrowingAnOpeningToItsWallIsACautionWithTheAmount() {
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 3)
        var c = f.canonical
        c.windows = [RawSurface(kind: .window, transform: Matrix4.yawTranslation(yaw: 0, Point3(2.5, 1.5, 0)),
                                dimensions: Point3(6, 1.0, 0), parentID: f.wallSurfaceIDs[0][0])]
        let r = build(c)
        XCTAssertEqual(r.room.openings.first?.width.scanned ?? 0, 5, accuracy: 1e-9)
        let narrowed = r.warnings.compactMap { w -> Double? in
            if case .openingAdjusted(_, _, _, let n) = w { return n } else { return nil }
        }
        XCTAssertEqual(narrowed.first ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(r.worstSeverity, .caution)
        XCTAssertTrue(r.warnings.contains { $0.message.contains("narrowed") && $0.message.contains("1.00 m") })
        XCTAssertEqual(RoomBuilder.BuildWarning.openingAdjusted(id: UUID(), kind: .window).severity, .info, "defaults: no shift")
    }

    // MARK: Reliability signals

    func testResultSaysWhereTheOutlineCameFromAndWhetherToTrustIt() {
        let clean = build(Fixtures.rectangle(width: 4, depth: 3, seed: 1))
        XCTAssertEqual(clean.outlineSource, .walls)
        XCTAssertTrue(clean.isUsable); XCTAssertTrue(clean.isReliable)
        XCTAssertEqual(clean.room.notes, "", "nothing to note on a clean scan")
        XCTAssertTrue(clean.reviewMessages.isEmpty)

        // Caution: still reliable, but the room carries the note into the exports.
        let open = build(openWest())
        XCTAssertEqual(open.outlineSource, .walls)
        XCTAssertTrue(open.isUsable); XCTAssertTrue(open.isReliable)
        XCTAssertEqual(open.worstSeverity, .caution)
        XCTAssertTrue(open.room.notes.contains("SCAN CHECK (caution)"), open.room.notes)
        XCTAssertTrue(open.room.notes.contains("virtual wall"), open.room.notes)
        XCTAssertEqual(open.reviewMessages.count, 1)

        // Critical: usable outline, but a guess. Warnings are listed most severe first, and so are the notes.
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 2, omit: true), .init(wall: 3, omit: true)]
        let bad = build(Fixtures.rectangle(width: 6, depth: 4, seed: 3, extras: e))
        XCTAssertEqual(bad.outlineSource, .floorPolygon)
        XCTAssertTrue(bad.isUsable); XCTAssertFalse(bad.isReliable)
        XCTAssertEqual(bad.warnings.first?.severity, .critical)
        let severities = bad.warnings.map { $0.severity.rawValue }
        XCTAssertEqual(severities, severities.sorted(by: >), "most severe first")
        XCTAssertTrue(bad.room.notes.hasPrefix("SCAN CHECK (critical)"), bad.room.notes)
        XCTAssertEqual(bad.reviewMessages.first, bad.warnings.first?.message)

        // Hull fallback.
        let hull = build(Fixtures.openPlan(width: 8, depth: 4, missingWall: 2, seed: 2, extras: extras { $0.includeFloor = false }))
        XCTAssertEqual(hull.outlineSource, .convexHull)
        XCTAssertFalse(hull.isReliable)

        // Nothing usable.
        let empty = build(RawCapture())
        XCTAssertEqual(empty.outlineSource, .none)
        XCTAssertFalse(empty.isUsable); XCTAssertFalse(empty.isReliable)
        XCTAssertTrue(empty.room.notes.contains("SCAN CHECK (critical)"))
        let one = build(RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0))]))
        XCTAssertFalse(one.isUsable)
        XCTAssertEqual(one.outlineSource, .none)
        // Notes are deterministic.
        XCTAssertEqual(build(openWest()).room.notes, open.room.notes)
    }

    // MARK: Non-finite input

    func testAbsurdFloorPolygonsNeverProduceNonFiniteWalls() throws {
        func floor(_ corners: [Point3], dims: Point3 = Point3(4, 4, 0)) -> RawSurface {
            RawSurface(kind: .floor, transform: Matrix4(columnMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1]),
                       dimensions: dims, polygonCorners: corners)
        }
        let huge = 1e200
        let cases: [RawCapture] = [
            RawCapture(floors: [floor([Point3(0, 0, 0), Point3(huge, 0, 0), Point3(huge, huge, 0), Point3(0, huge, 0)])]),
            RawCapture(floors: [floor([Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 4, 0), Point3(0, 4, 0)], dims: Point3(1e300, 1e300, 0))]),
            RawCapture(floors: [floor([], dims: Point3(1e300, 1e300, 0))]),
            RawCapture(floors: [floor([Point3(0, 0, 0), Point3(2e6, 0, 0), Point3(2e6, 2e6, 0), Point3(0, 2e6, 0)])]),
            RawCapture(walls: [rawWall(Point2(0, 0), Point2(4, 0))],
                       floors: [floor([Point3(0, 0, 0), Point3(huge, 0, 0), Point3(huge, huge, 0), Point3(0, huge, 0)])]),
        ]
        for (i, c) in cases.enumerated() {
            let r = build(c)
            assertAllFinite(r)
            XCTAssertNoThrow(try JSONEncoder().encode(r.room), "case \(i) must be storable")
            XCTAssertNoThrow(try JSONEncoder().encode(r.warnings.map(\.message)))
        }
        // The absurd shapes are refused up front: never an exact polygon, and no coordinate beyond sanity (a floor whose
        // corners are absurd but whose size field is sane degrades to its bounding rectangle, which is never exact).
        for (i, c) in cases.enumerated() where i != 1 {      // case 1 has sane corners: its size field is simply not used
            for info in RoomBuilder.extractFloors(c.floors) {
                XCTAssertFalse(info.isExact, "case \(i)")
                XCTAssertTrue((info.polygon ?? []).allSatisfy { abs($0.x) < 1e7 && abs($0.y) < 1e7 }, "case \(i)")
            }
        }
        XCTAssertNil(RoomBuilder.extractFloors(cases[2].floors).first?.polygon, "huge size field and no corners: no shape at all")
        XCTAssertEqual(RoomBuilder.extractFloors(cases[1].floors).first?.polygon.map(Polygon.area) ?? 0, 16, accuracy: 1e-9)
        // A merely large (but sane) floor still works as a fallback outline.
        let big = build(RawCapture(floors: [floor([Point3(0, 0, 0), Point3(200, 0, 0), Point3(200, 100, 0), Point3(0, 100, 0)])]))
        XCTAssertEqual(Polygon.area(big.room.outline), 20_000, accuracy: 1e-6)
    }

    // MARK: Message polish

    func testMessagesAreAccurate() {
        // The percentage comes from the data, not a hard-coded 15 %.
        let m1 = RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 24.2, outlineArea: 20).message
        XCTAssertTrue(m1.contains("21 %"), m1)
        XCTAssertFalse(m1.contains("15 %"), m1)
        let m2 = RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 12.8, outlineArea: 20).message
        XCTAssertTrue(m2.contains("36 %"), m2)
        // Severity: caution up to 40 %, critical beyond.
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 24.2, outlineArea: 20).severity, .caution)
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 12.8, outlineArea: 20).severity, .caution)
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 28, outlineArea: 20).severity, .caution, "exactly 40 %")
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 28.1, outlineArea: 20).severity, .critical)
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 12, outlineArea: 20).severity, .caution, "exactly 40 %")
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 11.9, outlineArea: 20).severity, .critical)
        XCTAssertEqual(RoomBuilder.BuildWarning.floorAreaMismatch(floorArea: 5, outlineArea: 0).severity, .critical, "no division by zero")
        // Negative zero never prints.
        let m3 = RoomBuilder.BuildWarning.openBoundaryBridged(length: 1, at: Point2(-0.002, -0.0004)).message
        XCTAssertTrue(m3.contains("(0.00, 0.00)"), m3)
        XCTAssertFalse(m3.contains("-0.00"), m3)
        XCTAssertTrue(RoomBuilder.BuildWarning.openBoundaryBridged(length: 1, at: Point2(-1.5, 2)).message.contains("(-1.50, 2.00)"))
    }

    func testAHoleInOneScannedWallHasItsOwnMessage() {
        // Two collinear pieces 0.4 m apart: a hole in a scanned wall, not an open-plan side.
        let r = build(Fixtures.splitWall(width: 5, depth: 4, wall: 0, at: 0.4, gap: 0.4, seed: 5))
        XCTAssertEqual(virtualCount(r.room), 1)
        XCTAssertFalse(has(r) { if case .openBoundaryBridged = $0 { return true } else { return false } })
        let hole = r.warnings.compactMap { w -> (Double, Point2)? in
            if case .scannedWallHoleBridged(let l, let p) = w { return (l, p) } else { return nil }
        }
        XCTAssertEqual(hole.count, 1)
        XCTAssertEqual(hole.first?.0 ?? 0, 0.4, accuracy: 1e-9)
        assertPoint(hole.first?.1 ?? .zero, 2.0, 0)
        let msg = r.warnings.first { if case .scannedWallHoleBridged = $0 { return true } else { return false } }!.message
        XCTAssertTrue(msg.contains("hole") && msg.contains("0.40 m"), msg)
        XCTAssertFalse(msg.contains("open-plan"), msg)
        XCTAssertEqual(RoomBuilder.BuildWarning.scannedWallHoleBridged(length: 0.4, at: .zero).severity, .caution)
        // A genuinely missing side is still an open-plan boundary.
        XCTAssertTrue(has(build(openWest())) { if case .openBoundaryBridged = $0 { return true } else { return false } })
    }

    // MARK: Fuzz: never silently wrong

    /// Random rooms damaged in the ways real scans are: missing sides (never two neighbours), free-standing and
    /// attached stray walls, a corner gap, noise, rotation. With a floor surface the answer must be right
    /// whenever nothing is ambiguous, and an outline that is far off must always be critical.
    func testFuzzedDamagedRoomsAreRightOrCritical() {
        typealias Make = (Fixtures.Noise, UInt64, Fixtures.Extras) -> Fixtures.Fixture
        let shapes: [(String, Make)] = [
            ("rectangle", { Fixtures.rectangle(width: 5.5, depth: 4.2, noise: $0, seed: $1, extras: $2) }),
            ("L", { Fixtures.lShape(noise: $0, seed: $1, extras: $2) }),
            ("U", { Fixtures.uShape(noise: $0, seed: $1, extras: $2) }),
            ("T", { Fixtures.tShape(noise: $0, seed: $1, extras: $2) }),
            ("chamfer", { Fixtures.chamfered(noise: $0, seed: $1, extras: $2) }),
            ("trapezoid", { Fixtures.trapezoid(noise: $0, seed: $1, extras: $2) }),
            ("alcove", { Fixtures.alcove(noise: $0, seed: $1, extras: $2) }),
        ]
        var rng = Fixtures.SeededGenerator(seed: 20_260_509)
        var total = 0, exact = 0, critical = 0
        for caseIndex in 0..<420 {
            let (name, make) = shapes[Int(rng.next() % UInt64(shapes.count))]
            let probe = make(.none, 1, Fixtures.Extras())
            let poly = probe.corners
            let n = poly.count
            var e = Fixtures.Extras()
            e.rotationDegrees = rng.nextUnit() * 360
            e.origin = Point2(rng.symmetric(20), rng.symmetric(20))
            let noise: Fixtures.Noise = rng.nextBool() ? .light : .realistic

            // Missing sides: none, one, or two that are not neighbours.
            var omitted: [Int] = []
            let k = Int(rng.next() % 3)
            if k >= 1 { omitted.append(Int(rng.next() % UInt64(n))) }
            if k == 2 {
                let candidates = (0..<n).filter { j in
                    let d = abs(j - omitted[0]); return d >= 2 && d <= n - 2
                }
                if let j = candidates.isEmpty ? nil : candidates[Int(rng.next() % UInt64(candidates.count))] { omitted.append(j) }
            }
            e.tweaks = omitted.map { Fixtures.WallTweak(wall: $0, omit: true) }

            // A corner gap on one surviving wall.
            var gapped = false
            if rng.nextUnit() < 0.25 {
                let i = Int(rng.next() % UInt64(n))
                if !omitted.contains(i), poly[i].distance(to: poly[(i + 1) % n]) > 1.5 {
                    e.tweaks.append(Fixtures.WallTweak(wall: i, extendEnd: -(0.25 + rng.nextUnit() * 0.35)))
                    gapped = true
                }
            }

            // Stray walls, all inside the room (local frame), some attached to a wall, some floating.
            func distanceToBoundary(_ p: Point2) -> Double {
                var best = Double.infinity
                for i in 0..<n {
                    let a = poly[i], b = poly[(i + 1) % n]
                    let d = b - a
                    let t = max(0, min(1, (p - a).dot(d) / d.dot(d)))
                    best = min(best, p.distance(to: a + d * t))
                }
                return best
            }
            /// Every sample along the stray (apart from an attached start) lies well inside the room.
            func staysInside(_ a: Point2, _ b: Point2, attached: Bool) -> Bool {
                for k in 0...10 {
                    let t = Double(k) / 10
                    if attached && k == 0 { continue }
                    let p = a.lerp(to: b, t: t)
                    if !Polygon.contains(poly, p) || distanceToBoundary(p) < (attached && k <= 2 ? 0.05 : 0.3) { return false }
                }
                return true
            }
            var strays: [Fixtures.InteriorWall] = []
            let wanted = Int(rng.next() % 5)
            var attempts = 0
            while strays.count < wanted && attempts < 80 {
                attempts += 1
                let len = 0.4 + rng.nextUnit() * 1.6
                if rng.nextUnit() < 0.4 {
                    // Stub off a boundary wall, going inwards.
                    let i = Int(rng.next() % UInt64(n))
                    let a = poly[i], b = poly[(i + 1) % n]
                    let start = a.lerp(to: b, t: 0.2 + rng.nextUnit() * 0.6)
                    let end = start + (b - a).normalized.perpendicularCCW * len
                    if staysInside(start, end, attached: true) { strays.append(wall(start, end)) }
                } else {
                    let bounds = Bounds2(points: poly)!
                    let p = Point2(bounds.min.x + rng.nextUnit() * bounds.width, bounds.min.y + rng.nextUnit() * bounds.height)
                    let angle = rng.nextUnit() * Double.pi
                    let q = p + Point2(cos(angle), sin(angle)) * len
                    if staysInside(p, q, attached: false) { strays.append(wall(p, q)) }
                }
            }
            e.interiorWalls = strays
            let f = make(noise, UInt64(caseIndex + 1), e)
            let r = build(f)
            let tag = "case \(caseIndex) \(name) omitted \(omitted) strays \(strays.count) gap \(gapped) rot \(Int(e.rotationDegrees)): \(r.warnings.map(\.message))"
            total += 1
            assertNeverSilentlyWrong(r, truth: f.expectedArea, tag)
            assertAllFinite(r)
            let area = Polygon.area(r.room.outline)
            if abs(area - f.expectedArea) / f.expectedArea < 0.03 { exact += 1 }
            if r.worstSeverity == .critical { critical += 1 }
            if omitted.isEmpty {
                // Nothing missing: strays and one corner gap never change the room.
                XCTAssertEqual(area, f.expectedArea, accuracy: f.expectedArea * 0.03, tag)
                XCTAssertEqual(r.room.walls.count, f.expectedWallCount + (gapped ? 1 : 0), "\(tag): wall count")
                XCTAssertNotEqual(r.worstSeverity, .critical, tag)
            }
        }
        XCTAssertGreaterThan(Double(exact) / Double(total), 0.85, "exact \(exact) of \(total), critical \(critical)")
    }

    // MARK: Search internals

    func testLeftOutWallIsClassifiedInsideOutsideAndTail() {
        // Loop: the square (0,0) (4,0) (4,4) (0,4). Segments (a, b) and whether the loop uses them:
        //   0 south wall (-1,0)-(4,0), used from x = 0: 1 m tail outside the loop
        //   1 east, 2 north, 3 west: used in full
        //   4 stub inside (1,1)-(2,1), 5 stub outside (5,1)-(7,1), 6 a duplicate of the west wall 5 cm inside it
        let a = [Point2(-1, 0), Point2(4, 0), Point2(4, 4), Point2(0, 4), Point2(1, 1), Point2(5, 1), Point2(0.05, 1)]
        let b = [Point2(4, 0), Point2(4, 4), Point2(0, 4), Point2(0, 0), Point2(2, 1), Point2(7, 1), Point2(0.05, 3)]
        let used = [true, true, true, true, false, false, false]
        let walls = [RoomBuilder.LoopWall(start: Point2(0, 0), end: Point2(4, 0), segment: 0),
                     RoomBuilder.LoopWall(start: Point2(4, 0), end: Point2(4, 4), segment: 1),
                     RoomBuilder.LoopWall(start: Point2(4, 4), end: Point2(0, 4), segment: 2),
                     RoomBuilder.LoopWall(start: Point2(0, 4), end: Point2(0, 0), segment: 3)]
        let left = RoomBuilder.evaluateLeftOut(polygon: walls.map(\.start), walls: walls, a: a, b: b, used: used, tolerance: 0.15)
        XCTAssertEqual(left.insideLength, 1.0 + 2.0, accuracy: 1e-9, "stub inside (1 m) + duplicate within 15 cm of the wall (2 m)")
        XCTAssertEqual(left.outsideLength, 2.0, accuracy: 1e-9)
        XCTAssertEqual(left.outsideTailLength, 1.0, accuracy: 1e-9)
        XCTAssertEqual(left.droppedOutside, [5])
        // Extra cost of the outside stub: 2 m, long-wall factor (2 - 1.5) / 1.5 = 1/3 -> 2 * (3 + 3/3).
        XCTAssertEqual(left.outsideExtraCost, 2.0 * (RoomBuilder.outsideExtraCostPerMetre + RoomBuilder.longWallExtraCostPerMetre / 3), accuracy: 1e-9)
        // A tail INSIDE the loop is not penalised: in the L (6 x 4 with the 2 x 2 notch) the notch floor, scanned from x = 6
        // to x = 2, is used only from x = 6 to the reflex corner at x = 4; its remaining 2 m run on across the room.
        let l = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        let notchFloor = RoomBuilder.LoopWall(start: Point2(6, 2), end: Point2(4, 2), segment: 0)
        let inward = RoomBuilder.evaluateLeftOut(polygon: l, walls: [notchFloor], a: [Point2(6, 2)], b: [Point2(2, 2)],
                                                 used: [true], tolerance: 0.15)
        XCTAssertEqual(inward.outsideTailLength, 0, accuracy: 1e-9)
        // The same wall running on out of the room instead (scanned from x = 6 to x = 8, used from 6 to 4... i.e. reversed
        // direction) puts the tail outside: a segment (3,5)-(6,5) used only from x = 3 to 4.5 leaves 1.5 m above the room.
        let above = RoomBuilder.evaluateLeftOut(polygon: l, walls: [RoomBuilder.LoopWall(start: Point2(3, 5), end: Point2(4.5, 5), segment: 0)],
                                                a: [Point2(3, 5)], b: [Point2(6, 5)], used: [true], tolerance: 0.15)
        XCTAssertEqual(above.outsideTailLength, 1.5, accuracy: 1e-9)
    }

    func testUnmatchedBoundaryLengthAndBridgeFollowing() {
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2] {
            [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]
        }
        let a = rect(0, 0, 4, 4)
        XCTAssertEqual(RoomBuilder.unmatchedBoundaryLength(a, against: [a], tolerance: 0.3), 0, accuracy: 1e-9)
        // The same square shifted 1 m east: A's west edge (4 m) is 1 m from B's, A's south and north edges lose their first
        // 0.7 m (more than 0.3 m from B's corner), A's east edge (x = 4) runs through B's interior and matches only the
        // 0.3 m next to B's south and north edges: 4 + 0.7 + 0.7 + (4 - 0.6) = 8.8 m (sampled every 0.2 m).
        let b = rect(1, 0, 5, 4)
        XCTAssertEqual(RoomBuilder.unmatchedBoundaryLength(a, against: [b], tolerance: 0.3), 8.8, accuracy: 0.45)
        // Several reference polygons: matched if near ANY of them.
        XCTAssertEqual(RoomBuilder.unmatchedBoundaryLength(a, against: [b, a], tolerance: 0.3), 0, accuracy: 1e-9)
        // A bridge follows the floor boundary only when it lies along it.
        let floor = rect(0, 0, 5, 4)
        XCTAssertTrue(RoomBuilder.bridgeFollowsFloor(Point2(0, 4), Point2(0, 0), floors: [floor]), "along the west edge")
        XCTAssertTrue(RoomBuilder.bridgeFollowsFloor(Point2(0.1, 3.9), Point2(0.15, 0.1), floors: [floor]), "within the slack")
        XCTAssertFalse(RoomBuilder.bridgeFollowsFloor(Point2(0, 4), Point2(5, 0), floors: [floor]), "a diagonal through the room")
        XCTAssertFalse(RoomBuilder.bridgeFollowsFloor(Point2(1, 1), Point2(1, 3), floors: [floor]), "a chord inside the room")
    }

    func testDenseGraphsKeepABoundedSymmetricDegree() {
        // 25 walls through one point: every node could turn onto 48 others. The graph keeps at most 40 per node,
        // and an edge only together with its reverse.
        var c = RawCapture()
        for k in 0..<25 {
            let angle = Double(k) * Double.pi / 25
            c.walls.append(rawWall(Point2(-2 * cos(angle), -2 * sin(angle)), Point2(2 * cos(angle), 2 * sin(angle))))
        }
        let ex = RoomBuilder.extractSegments(from: c.walls, options: .standard)
        let nodes = RoomBuilder.buildNodes(RoomBuilder.mergeCollinear(ex.segments, options: .standard).segments)
        XCTAssertEqual(nodes.count, 50)
        let adj = RoomBuilder.buildEdges(nodes, options: .standard)
        var total = 0
        for (u, list) in adj.enumerated() {
            XCTAssertLessThanOrEqual(list.count, RoomBuilder.maxEdgesPerNode)
            total += list.count
            for e in list {
                XCTAssertTrue(adj[e.to ^ 1].contains { $0.to == u ^ 1 }, "edge \(u) -> \(e.to) lost its reverse")
            }
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(total, 50 * 48, "the unbounded graph has 2400 edges")
        // A normal room is untouched.
        let room = Fixtures.lShape(noise: .light, seed: 3)
        let ex2 = RoomBuilder.extractSegments(from: room.capture.walls, options: .standard)
        let nodes2 = RoomBuilder.buildNodes(RoomBuilder.mergeCollinear(ex2.segments, options: .standard).segments)
        XCTAssertTrue(RoomBuilder.buildEdges(nodes2, options: .standard).allSatisfy { $0.count < 10 })
    }

    func testTheGatesAndTheirOptions() {
        // The pod case: three real walls of a 10 x 6 room (the 10 m north side is over the bridging limit) and a
        // closed pod. Two independent gates keep the pod from being the room: too much scanned wall outside the
        // loop, and too little of the floor covered by a loop that left real wall outside.
        let pod = [wall(Point2(4, 2), Point2(6, 2)), wall(Point2(6, 2), Point2(6, 3.6)),
                   wall(Point2(6, 3.6), Point2(4, 3.6)), wall(Point2(4, 3.6), Point2(4, 2))]
        var e = Fixtures.Extras()
        e.tweaks = [.init(wall: 2, omit: true)]
        e.interiorWalls = pod
        let f = Fixtures.rectangle(width: 10, depth: 6, seed: 2, extras: e)
        func podArea(_ configure: (inout RoomBuilder.Options) -> Void) -> Double {
            var o = RoomBuilder.Options.standard
            configure(&o)
            return Polygon.area(build(f, options: o).room.outline)
        }
        XCTAssertEqual(podArea { _ in }, 60, accuracy: 1e-9, "default: floor polygon")
        XCTAssertEqual(podArea { $0.maxOutsideWallFraction = 1.0 }, 60, accuracy: 1e-9, "the floor-overlap gate alone still rejects the pod")
        XCTAssertEqual(podArea { $0.minFloorOverlap = 0 }, 60, accuracy: 1e-9, "the outside-wall gate alone still rejects the pod")
        XCTAssertEqual(podArea { $0.maxOutsideWallFraction = 1.0; $0.minFloorOverlap = 0 }, 3.2, accuracy: 1e-9, "with both gates off the pod is the room")

        // Tier B: without a floor, an outline that bridges a side while wall lies outside it is flagged critical.
        var noFloor = Fixtures.Extras()
        noFloor.includeFloor = false
        noFloor.tweaks = [.init(wall: 1, omit: true), .init(wall: 3, omit: true)]
        let chamfer = Fixtures.chamfered(seed: 3, extras: noFloor)      // east and north walls never scanned
        let r = build(chamfer)
        XCTAssertTrue(has(r) { if case .bridgedOutlineLeavesWallOutside(let l) = $0 { return abs(l - 2.0.squareRoot()) < 1e-9 } else { return false } }, "\(r.warnings.map(\.message))")
        XCTAssertEqual(r.worstSeverity, .critical)
        XCTAssertFalse(r.isReliable)
        var lenient = RoomBuilder.Options.standard
        lenient.unverifiedOutsideWallLength = 2.0        // the 1.41 m chamfer wall is below this
        XCTAssertFalse(has(build(chamfer, options: lenient)) { if case .bridgedOutlineLeavesWallOutside = $0 { return true } else { return false } })
        // ...and with the floor it is not a guess at all: the floor polygon is used.
        noFloor.includeFloor = true
        let withFloor = build(Fixtures.chamfered(seed: 3, extras: noFloor))
        XCTAssertFalse(has(withFloor) { if case .bridgedOutlineLeavesWallOutside = $0 { return true } else { return false } })
        XCTAssertEqual(Polygon.area(withFloor.room.outline), 19.5, accuracy: 1e-6)
        // New options have sensible defaults and take part in equality.
        XCTAssertEqual(RoomBuilder.Options.standard.minFloorOverlap, 0.70)
        XCTAssertEqual(RoomBuilder.Options.standard.maxOutsideWallFraction, 0.5)
        XCTAssertEqual(RoomBuilder.Options.standard.unverifiedOutsideWallLength, 1.0)
        XCTAssertNotEqual(RoomBuilder.Options(), lenient)
    }

    func testManyStrayWallsStayFastAndHonest() {
        var rng = Fixtures.SeededGenerator(seed: 5)
        for count in [20, 60, 150] {
            var e = Fixtures.Extras()
            e.interiorWalls = (0..<count).map { _ in
                let p = Point2(0.3 + rng.nextUnit() * 4.4, 0.3 + rng.nextUnit() * 3.4)
                let angle = rng.nextUnit() * Double.pi
                return wall(p, p + Point2(cos(angle), sin(angle)) * (0.3 + rng.nextUnit() * 1.2))
            }
            let f = Fixtures.openPlan(width: 5, depth: 4, missingWall: 3, noise: .light, seed: 4, extras: e)
            let start = Date()
            let r = build(f)
            XCTAssertLessThan(Date().timeIntervalSince(start), 15, "\(count) strays (debug build)")
            assertAllFinite(r)
            assertNeverSilentlyWrong(r, truth: 20, "\(count) strays")
        }
    }

    func testReviewNotesListEveryCautionAndCriticalWarningMostSevereFirst() {
        let id = UUID()
        let warnings: [RoomBuilder.BuildWarning] = [
            .missingFloorSurface, .openBoundaryBridged(length: 4, at: Point2(0, 2)), .noClosedLoop(fallback: .floorPolygon),
            .openingAdjusted(id: id, kind: .door, movedBy: 0.02, narrowedBy: 0)]
        let sorted = warnings.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
        let notes = RoomBuilder.reviewNotes(for: sorted)
        let lines = notes.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, "info warnings are routine and stay out of the notes")
        XCTAssertTrue(lines[0].hasPrefix("SCAN CHECK (critical): "))
        XCTAssertTrue(lines[1].hasPrefix("SCAN CHECK (caution): "))
        XCTAssertEqual(RoomBuilder.reviewNotes(for: []), "")
    }

    func testTheFloorPolygonTermsRewardAMatchingFloorAndPunishADisagreeingOne() {
        // The same walls searched with no floor, the right floor, and floors that disagree: the loop is the same
        // (this room is unambiguous) but its cost is not. The right floor adds nothing; a wrong one adds at least
        // 50 per unit of (1 - IoU) plus 3 per metre of boundary that does not follow the other.
        let f = Fixtures.rectangle(width: 5, depth: 4, seed: 2)
        let segments = RoomBuilder.mergeCollinear(RoomBuilder.extractSegments(from: f.capture.walls, options: .standard).segments,
                                                  options: .standard).segments
        func cost(_ floors: [[Point2]]) -> Double {
            RoomBuilder.findLoop(segments: segments, floors: floors, options: .standard).outcome?.cost ?? -1
        }
        func rect(_ w: Double, _ h: Double, at o: Point2 = .zero) -> [Point2] {
            [o, o + Point2(w, 0), o + Point2(w, h), o + Point2(0, h)]
        }
        let none = cost([])
        XCTAssertEqual(none, 0, accuracy: 1e-9, "a perfect rectangle costs nothing")
        XCTAssertEqual(cost([rect(5, 4)]), none, accuracy: 1e-9, "the matching floor adds nothing")
        // A floor 1.2 times too big: IoU = 20 / 28.8.
        let big = cost([rect(6, 4.8)])
        XCTAssertGreaterThan(big - none, 50 * (1 - 20.0 / 28.8))
        // A floor shifted 2 m sideways: IoU = 12 / 28 and most of both boundaries unmatched.
        let shifted = cost([rect(5, 4, at: Point2(2, 0))])
        XCTAssertGreaterThan(shifted - none, 50 * (1 - 12.0 / 28.0) + 3 * 8)
        XCTAssertGreaterThan(shifted, big, "the worse the agreement, the dearer")
        // Two floor pieces that together are the room agree as well as one (their shared edge is not boundary).
        XCTAssertEqual(cost([rect(2.5, 4), rect(2.5, 4, at: Point2(2.5, 0))]), 0, accuracy: 1e-9)
    }

    func testAGiantFloorPolygonCannotStallTheSearch() {
        // A floor 100 km on a side (below the 1000 km sanity bound) next to a normal 5 x 4 room's walls.
        var c = Fixtures.rectangle(width: 5, depth: 4, seed: 2).canonical
        c.floors = [RawSurface(kind: .floor, transform: Matrix4(columnMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1]),
                               dimensions: Point3(1e5, 1e5, 0),
                               polygonCorners: [Point3(0, 0, 0), Point3(1e5, 0, 0), Point3(1e5, 1e5, 0), Point3(0, 1e5, 0)])]
        let start = Date()
        let r = build(c)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        assertAllFinite(r)
        // The walls are a clean loop, so they win, and the absurd floor is reported as the mismatch it is.
        XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9)
        XCTAssertTrue(has(r) { if case .floorAreaMismatch = $0 { return true } else { return false } })
        // With a gap to bridge the sampling is capped too.
        let open = build(Fixtures.openPlan(width: 5, depth: 4, missingWall: 3, seed: 2, extras: extras {
            $0.floorPolygon = [Point2(0, 0), Point2(1e5, 0), Point2(1e5, 1e5), Point2(0, 1e5)]
        }))
        assertAllFinite(open)
    }

    func testACriticalWarningRaisedLastStillComesFirst() {
        // The interior wall is dropped first (caution); the absurd floor is noticed at the very end (critical).
        var c = Fixtures.rectangle(width: 5, depth: 4, seed: 3,
                                   extras: extras { $0.interiorWalls = [wall(Point2(1, 1), Point2(2.5, 1))] }).canonical
        c.floors[0].polygonCorners = c.floors[0].polygonCorners!.map { Point3($0.x * 1.5, $0.y * 1.5, $0.z) }
        let r = build(c)
        let severities = r.warnings.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >), "\(r.warnings.map(\.message))")
        guard case .floorAreaMismatch = r.warnings[0] else { return XCTFail("\(r.warnings.map(\.message))") }
        XCTAssertEqual(r.warnings[0].severity, .critical, "125 % off")
        XCTAssertTrue(r.warnings.dropFirst().contains { if case .interiorWallsDropped = $0 { return true } else { return false } })
        XCTAssertTrue(r.room.notes.hasPrefix("SCAN CHECK (critical): The scanned floor area"), r.room.notes)
        XCTAssertEqual(r.room.notes.split(separator: "\n").count, 2)
        XCTAssertFalse(r.isReliable)
        XCTAssertEqual(r.outlineSource, .walls, "the walls are fine; it is the floor that is odd")
        XCTAssertEqual(Polygon.area(r.room.outline), 20, accuracy: 1e-9)
    }
}

private extension Array {
    /// Deterministic pick that does not touch the system generator.
    func randomElementDeterministic(_ rng: inout CaptureFixtures.SeededGenerator) -> Element? {
        isEmpty ? nil : self[Int(rng.next() % UInt64(count))]
    }
}
