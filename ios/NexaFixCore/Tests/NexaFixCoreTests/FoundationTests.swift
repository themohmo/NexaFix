import XCTest
@testable import NexaFixCore

final class FoundationTests: XCTestCase {

    // MARK: Polygon

    func testSquareAreaAndAngles() {
        let sq = [Point2(0, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)]
        XCTAssertEqual(Polygon.signedArea(sq), 12, accuracy: 1e-9)
        XCTAssertEqual(Polygon.perimeter(sq), 14, accuracy: 1e-9)
        XCTAssertTrue(Polygon.isCounterClockwise(sq))
        for i in 0..<4 { XCTAssertEqual(Polygon.interiorAngle(sq, at: i), 90, accuracy: 1e-9) }
        XCTAssertEqual(Polygon.centroid(sq).x, 2, accuracy: 1e-9)
        XCTAssertEqual(Polygon.centroid(sq).y, 1.5, accuracy: 1e-9)
    }

    func testClockwiseIsRewound() {
        let cw = [Point2(0, 0), Point2(0, 3), Point2(4, 3), Point2(4, 0)]
        XCTAssertFalse(Polygon.isCounterClockwise(cw))
        XCTAssertTrue(Polygon.isCounterClockwise(Polygon.counterClockwise(cw)))
        XCTAssertEqual(Polygon.area(cw), 12, accuracy: 1e-9)
    }

    func testLShapeHasOneReflexCorner() {
        // 6x4 rectangle with a 2x2 notch cut from the top-right.
        let l = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        XCTAssertEqual(Polygon.area(l), 20, accuracy: 1e-9)
        let angles = l.indices.map { Polygon.interiorAngle(l, at: $0) }
        XCTAssertEqual(angles.filter { $0 > 180 }.count, 1)
        XCTAssertEqual(angles[3], 270, accuracy: 1e-9)
        XCTAssertEqual(angles.reduce(0, +), Double(l.count - 2) * 180, accuracy: 1e-6)
    }

    func testObtuseAngleAndPointInPolygon() {
        let tri = [Point2(0, 0), Point2(4, 0), Point2(1, 3)]
        let sum = tri.indices.map { Polygon.interiorAngle(tri, at: $0) }.reduce(0, +)
        XCTAssertEqual(sum, 180, accuracy: 1e-6)
        XCTAssertTrue(Polygon.contains(tri, Point2(1.5, 1)))
        XCTAssertFalse(Polygon.contains(tri, Point2(3.5, 2.5)))
    }

    // MARK: Coordinates

    func testPlanWorldRoundTrip() {
        let p = Point2(2.5, -1.25)
        let w = p.world(elevation: 1.2)
        XCTAssertEqual(w.x, 2.5, accuracy: 1e-12)
        XCTAssertEqual(w.y, 1.2, accuracy: 1e-12)
        XCTAssertEqual(w.z, 1.25, accuracy: 1e-12)
        XCTAssertEqual(w.plan, p)
    }

    func testMatrixTransform() {
        let m = Matrix4.yawTranslation(yaw: .pi / 2, Point3(1, 2, 3))
        let p = m.transform(Point3(1, 0, 0))   // local +x
        XCTAssertEqual(p.x, 1, accuracy: 1e-9)
        XCTAssertEqual(p.y, 2, accuracy: 1e-9)
        XCTAssertEqual(p.z, 2, accuracy: 1e-9)   // X' = (cos, 0, -sin) = (0,0,-1): z = 3 - 1
    }

    // MARK: Measured

    func testMeasuredVerificationOverridesScan() {
        var m = Measured(scanned: 3.000)
        XCTAssertEqual(m.value, 3.000)
        XCTAssertFalse(m.isVerified)
        XCTAssertNil(m.deviation)
        m.verify(3.030, source: .laser)
        XCTAssertEqual(m.value, 3.030)
        XCTAssertTrue(m.isVerified)
        XCTAssertEqual(m.scanned, 3.000)
        XCTAssertEqual(m.deviation!, 0.030, accuracy: 1e-12)
        XCTAssertEqual(m.deviationPercent!, 0.99, accuracy: 0.01)
        m.clearVerification()
        XCTAssertEqual(m.value, 3.000)
    }

    func testMeasuredCodableRoundTrip() throws {
        var m = Measured(scanned: 1.234)
        m.verify(1.25, source: .tape, note: "behind skirting", date: Date(timeIntervalSince1970: 1_700_000_000))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Measured.self, from: enc.encode(m))
        XCTAssertEqual(back, m)
    }

    // MARK: Metrics

    func testRectangleMetrics() {
        let r = Room.rectangle(name: "Living", kind: .livingRoom, width: 6.2, depth: 4.5, ceilingHeight: 2.8,
                               openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 3.0, height: 2.4, sill: 0)])
        let m = r.metrics
        XCTAssertEqual(m.floorArea, 27.9, accuracy: 1e-9)
        XCTAssertEqual(m.perimeter, 21.4, accuracy: 1e-9)
        XCTAssertTrue(m.isRectangular)
        XCTAssertEqual(m.length!, 6.2, accuracy: 1e-9)
        XCTAssertEqual(m.width!, 4.5, accuracy: 1e-9)
        XCTAssertEqual(m.grossWallArea, 21.4 * 2.8, accuracy: 1e-9)
        XCTAssertEqual(m.openingArea, 0.9 * 2.1 + 3.0 * 2.4, accuracy: 1e-9)
        XCTAssertEqual(m.netWallArea, m.grossWallArea - m.openingArea, accuracy: 1e-9)
        XCTAssertEqual(m.volume, 27.9 * 2.8, accuracy: 1e-9)
        XCTAssertEqual(m.corners.count, 4)
        XCTAssertTrue(m.outOfSquareCorners.isEmpty)
        XCTAssertEqual(m.sides.count, 4)
    }

    func testVerifiedWallLengthsFlowIntoRectangleDimensions() {
        var r = Room.rectangle(name: "Bed", kind: .bedroom, width: 4.0, depth: 3.0)
        r.walls[0].length.verify(4.04)
        r.walls[2].length.verify(4.04)
        let m = r.metrics
        XCTAssertEqual(m.length!, 4.04, accuracy: 1e-9)
        XCTAssertEqual(m.effectiveFloorArea, 4.04 * 3.0, accuracy: 1e-9)
        XCTAssertEqual(m.floorArea, 12.0, accuracy: 1e-9)   // geometry untouched
    }

    func testLShapeIsNotRectangular() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        let m = l.metrics
        XCTAssertFalse(m.isRectangular)
        XCTAssertNil(m.length)
        XCTAssertEqual(m.floorArea, 20, accuracy: 1e-9)
        XCTAssertEqual(m.effectiveFloorArea, 20, accuracy: 1e-9)
        XCTAssertEqual(m.corners.filter(\.isReflex).count, 1)
        XCTAssertTrue(m.outOfSquareCorners.isEmpty)   // reflex corners are expected, not "out of square"
    }

    func testStraightCornerIsMergedIntoOneSide() {
        // Bottom wall split in two at x = 3 (collinear): still a rectangle with 4 sides.
        let r = Room.polygon(name: "Split", corners: [Point2(0, 0), Point2(3, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)])
        let m = r.metrics
        XCTAssertEqual(r.walls.count, 5)
        XCTAssertEqual(m.sides.count, 4)
        XCTAssertTrue(m.isRectangular)
        XCTAssertEqual(m.length!, 6, accuracy: 1e-9)
    }

    func testOutOfSquareCornerIsReported() {
        // One corner pulled to ~93 degrees.
        let r = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-0.21, 4)])
        let bad = r.metrics.outOfSquareCorners
        XCTAssertFalse(bad.isEmpty)
        XCTAssertTrue(bad.allSatisfy { abs($0.deviationFrom90) > 1 })
    }

    func testClockwiseInputStillGivesCCWWalls() {
        let r = Room.polygon(name: "CW", corners: [Point2(0, 0), Point2(0, 3), Point2(4, 3), Point2(4, 0)])
        XCTAssertTrue(Polygon.isCounterClockwise(r.outline))
        // Interior is to the left of every wall.
        for w in r.walls {
            let probe = w.midpoint + w.inwardNormal * 0.1
            XCTAssertTrue(Polygon.contains(r.outline, probe))
        }
    }

    func testOpeningSegmentLiesOnItsWall() {
        let r = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.window(wall: 0, offset: 1.0, width: 2.0)])
        let (a, b) = r.openings[0].planSegment(on: r.walls[0])
        XCTAssertEqual(a.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(b.x, 3.0, accuracy: 1e-9)
        XCTAssertEqual(a.y, 0, accuracy: 1e-9)
    }

    // MARK: Units

    func testLengthFormatting() {
        XCTAssertEqual(UnitFormatter.length(3.245, unit: .millimetres), "3245 mm")
        XCTAssertEqual(UnitFormatter.length(3.245, unit: .centimetres), "324.5 cm")
        XCTAssertEqual(UnitFormatter.length(3.245, unit: .metres), "3.245 m")
        XCTAssertEqual(UnitFormatter.length(3.245, unit: .metres, precision: .compact), "3.25 m")
        XCTAssertEqual(UnitFormatter.length(1.0, unit: .inches), "39.37 in")
        XCTAssertEqual(UnitFormatter.length(0.0, unit: .millimetres), "0 mm")
    }

    func testFeetAndInches() {
        XCTAssertEqual(UnitFormatter.length(3.048, unit: .feetAndInches), "10' 0\"")
        XCTAssertEqual(UnitFormatter.length(0.3048 + 0.0254 * 7.75, unit: .feetAndInches), "1' 7 3/4\"")
        XCTAssertEqual(UnitFormatter.length(0.0254 * 11.99, unit: .feetAndInches), "1' 0\"")   // rolls over 12"
        XCTAssertEqual(UnitFormatter.length(0.0254 * 7.5, unit: .feetAndInches), "7 1/2\"")
    }

    func testAreaAngleAndSignedFormatting() {
        XCTAssertEqual(UnitFormatter.area(27.9, unit: .squareMetres), "27.90 m\u{00B2}")
        XCTAssertEqual(UnitFormatter.area(10.0, unit: .squareFeet), "107.6 sq ft")
        XCTAssertEqual(UnitFormatter.angle(90), "90.0\u{00B0}")
        XCTAssertEqual(UnitFormatter.signedLength(0.003, unit: .millimetres), "+3 mm")
        XCTAssertEqual(UnitFormatter.signedLength(-0.0124, unit: .millimetres), "-12 mm")
        XCTAssertEqual(UnitFormatter.signedLength(0.0001, unit: .millimetres), "0 mm")
        XCTAssertTrue(UnitFormatter.tolerance(forLength: 3.0, unit: .millimetres).hasPrefix("\u{00B1}"))
    }

    // MARK: Model coding

    func testPropertyCodableRoundTrip() throws {
        let room = Room.rectangle(name: "Living", kind: .livingRoom, width: 6, depth: 4,
                                  openings: [.door(wall: 0, offset: 0.4)])
        let prop = Property(name: "Marina Gate 2304", client: "Mr. Ahmed",
                            floors: [Floor(name: "Level 1", level: 1, rooms: [room])])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let data = try enc.encode(prop)
        let back = try dec.decode(Property.self, from: data)
        XCTAssertEqual(back.allRooms.count, 1)
        XCTAssertEqual(back.allRooms[0].walls.count, 4)
        XCTAssertEqual(back.allRooms[0].openings.count, 1)
        XCTAssertEqual(back.id, prop.id)
    }
}
