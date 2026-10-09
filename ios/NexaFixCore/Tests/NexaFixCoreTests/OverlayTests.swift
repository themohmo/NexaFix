import XCTest
@testable import NexaFixCore

final class OverlayTests: XCTestCase {

    // MARK: Helpers

    private let mm = DisplayUnits(length: .millimetres, area: .squareMetres)

    private func scene(_ rooms: [Room], _ options: OverlayOptions = .review, units: DisplayUnits? = nil,
                       highlight: UUID? = nil) -> OverlayScene {
        OverlayBuilder.scene(for: rooms, options: options, units: units ?? mm, highlightRoomID: highlight)
    }

    private func label(_ s: OverlayScene, _ id: String, file: StaticString = #filePath, line: UInt = #line) -> OverlayLabel {
        guard let l = s.labels.first(where: { $0.id == id }) else {
            XCTFail("missing label \(id)", file: file, line: line)
            return OverlayLabel(id: id, kind: .live, position: .zero, title: "")
        }
        return l
    }

    private func assertAllFinite(_ s: OverlayScene, file: StaticString = #filePath, line: UInt = #line) {
        func ok(_ p: Point3) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
        for l in s.labels { XCTAssertTrue(ok(l.position), "label \(l.id)", file: file, line: line) }
        for g in s.segments { XCTAssertTrue(ok(g.a) && ok(g.b), "segment \(g.id)", file: file, line: line) }
        for a in s.arcs {
            XCTAssertTrue(ok(a.center) && a.radius.isFinite && a.startAngle.isFinite && a.sweep.isFinite, "arc \(a.id)", file: file, line: line)
        }
    }

    private func rect(_ w: Double = 6, _ d: Double = 4, openings: [OpeningSpec] = []) -> Room {
        Room.rectangle(name: "Living", kind: .livingRoom, width: w, depth: d, ceilingHeight: 2.8, openings: openings)
    }

    // MARK: Scene content

    func testEmptyInputGivesEmptyScene() {
        XCTAssertTrue(scene([]).isEmpty)
        let hollow = Room(name: "Empty", walls: [], ceilingHeight: Measured(scanned: 2.8))
        XCTAssertTrue(scene([hollow]).isEmpty)
    }

    func testRectangleProducesTheExpectedParts() {
        let r = rect(openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5)])
        let s = scene([r])
        XCTAssertEqual(s.segments.filter { $0.kind == .wallBase }.count, 4)
        XCTAssertEqual(s.segments.filter { $0.kind == .wallTop }.count, 4)
        XCTAssertEqual(s.segments.filter { $0.kind == .wallCorner }.count, 4)
        // 4 walls x (line + 2 ticks) + the vertical ceiling dimension (line + 2 ticks)
        XCTAssertEqual(s.segments.filter { $0.kind == .dimension }.count, 4 * 3 + 3)
        // door (no bottom edge: it stands on the floor) = 3, window = 4
        XCTAssertEqual(s.segments.filter { $0.kind == .openingEdge }.count, 3 + 4)
        XCTAssertEqual(s.labels.filter { $0.kind == .wallLength }.count, 4)
        XCTAssertEqual(s.labels.filter { $0.kind == .angle }.count, 4)
        XCTAssertEqual(s.labels.filter { $0.kind == .opening }.count, 2)
        XCTAssertEqual(s.labels.filter { $0.kind == .ceiling }.count, 1)
        XCTAssertEqual(s.labels.filter { $0.kind == .area }.count, 1)
        XCTAssertEqual(s.arcs.count, 4)
        assertAllFinite(s)
    }

    func testIdsAreStableUniqueAndFollowTheConvention() {
        let r = rect(openings: [.door(wall: 0, offset: 0.5)])
        let a = scene([r]), b = scene([r])
        XCTAssertEqual(a.labels, b.labels)
        XCTAssertEqual(a.segments, b.segments)
        XCTAssertEqual(a.arcs, b.arcs)
        let ids = a.labels.map(\.id) + a.segments.map(\.id) + a.arcs.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique")
        XCTAssertNotNil(a.labels.first { $0.id == "wall:\(r.walls[0].id.uuidString):length" })
        XCTAssertNotNil(a.labels.first { $0.id == "corner:\(r.id.uuidString):0:angle" })
        XCTAssertNotNil(a.arcs.first { $0.id == "corner:\(r.id.uuidString):0:arc" })
    }

    func testWallLabelSitsOnTheInsideFaceAtMidHeight() {
        let r = rect(6, 4)
        let s = scene([r])
        let south = label(s, "wall:\(r.walls[0].id.uuidString):length")
        // South wall runs along plan y = 0 with the room above it; plan (3, 0.04) is world (3, h, -0.04).
        XCTAssertEqual(south.position.x, 3, accuracy: 1e-9)
        XCTAssertEqual(south.position.y, 1.4, accuracy: 1e-9)
        XCTAssertEqual(south.position.z, -0.04, accuracy: 1e-9)
        XCTAssertEqual(south.title, "6000 mm")
        let east = label(s, "wall:\(r.walls[1].id.uuidString):length")
        XCTAssertEqual(east.position.x, 6 - 0.04, accuracy: 1e-9)
        XCTAssertEqual(east.position.z, -2, accuracy: 1e-9)
    }

    func testFloorElevationLiftsEverything() {
        var r = rect()
        r.floorElevation = -1.5
        let s = scene([r])
        let base = s.segments.first { $0.kind == .wallBase }
        XCTAssertEqual(base?.a.y ?? 99, -1.5, accuracy: 1e-9)
        let south = label(s, "wall:\(r.walls[0].id.uuidString):length")
        XCTAssertEqual(south.position.y, -1.5 + 1.4, accuracy: 1e-9)
    }

    func testScannedAndVerifiedLengthsAreNeverConfused() {
        var r = rect(6, 4)
        r.walls[0].length.verify(6.03, source: .laser)
        let s = scene([r])
        let verified = label(s, "wall:\(r.walls[0].id.uuidString):length")
        XCTAssertEqual(verified.state, .verified)
        XCTAssertEqual(verified.title, "6030 mm")
        XCTAssertEqual(verified.subtitle, "Laser")
        let scanned = label(s, "wall:\(r.walls[1].id.uuidString):length")
        XCTAssertEqual(scanned.state, .scanned)
        XCTAssertEqual(scanned.title, "4000 mm")
        XCTAssertEqual(scanned.subtitle, UnitFormatter.tolerance(forLength: 4.0, unit: .millimetres))
        XCTAssertTrue(scanned.subtitle?.hasPrefix("\u{00B1}") ?? false)
        // Geometry is the scan, so the wireframe still matches the coordinate frame.
        let dim = s.segments.first { $0.id == "wall:\(r.walls[0].id.uuidString):dim" }
        XCTAssertEqual(dim?.state, .verified)
        let dimScanned = s.segments.first { $0.id == "wall:\(r.walls[1].id.uuidString):dim" }
        XCTAssertEqual(dimScanned?.state, .scanned)
        let base = s.segments.first { $0.id == "wall:\(r.walls[0].id.uuidString):base" }
        XCTAssertEqual(base?.a.distance(to: base?.b ?? .zero) ?? 0, 6.0, accuracy: 1e-9)
        // A scanned length is never promoted by anything else.
        XCTAssertEqual(s.labels.filter { $0.kind == .wallLength && $0.state == .verified }.count, 1)
    }

    func testDimensionLineSitsAtAboutOneMetreWithEndTicks() {
        let r = rect(6, 4)
        let s = scene([r])
        let id = r.walls[0].id.uuidString
        let line = s.segments.first { $0.id == "wall:\(id):dim" }!
        XCTAssertEqual(line.a.y, 1.0, accuracy: 1e-9)
        XCTAssertEqual(line.b.y, 1.0, accuracy: 1e-9)
        XCTAssertEqual(line.a.distance(to: line.b), 6.0, accuracy: 1e-9)
        let t0 = s.segments.first { $0.id == "wall:\(id):dim:t0" }!
        XCTAssertEqual(t0.a.x, line.a.x, accuracy: 1e-9)
        XCTAssertGreaterThan(t0.b.y, t0.a.y)
    }

    func testUnitsDriveLabelText() {
        let r = rect(6, 4)
        let id = "wall:\(r.walls[0].id.uuidString):length"
        XCTAssertEqual(label(scene([r], units: DisplayUnits(length: .metres)), id).title, "6.00 m")
        XCTAssertEqual(label(scene([r], units: DisplayUnits(length: .centimetres)), id).title, "600.0 cm")
        XCTAssertEqual(label(scene([r], units: DisplayUnits(length: .inches)), id).title, "236.2 in")
        XCTAssertEqual(label(scene([r], units: DisplayUnits(length: .feetAndInches)), id).title, "19' 8 1/4\"")
        let sqft = scene([r], units: DisplayUnits(length: .millimetres, area: .squareFeet))
        XCTAssertTrue(label(sqft, "room:\(r.id.uuidString):area").title.hasSuffix("sq ft"))
    }

    // MARK: Corners

    func testSquareRoomCornersAreNeutralWithArcsFromWallDirections() {
        let r = rect(6, 4)
        let s = scene([r])
        for l in s.labels where l.kind == .angle {
            XCTAssertEqual(l.state, .neutral)
            XCTAssertEqual(l.title, "90.0\u{00B0}")
            XCTAssertNil(l.subtitle)
        }
        let a0 = s.arcs.first { $0.id == "corner:\(r.id.uuidString):0:arc" }!
        XCTAssertEqual(a0.startAngle, 0, accuracy: 1e-9)      // along the south wall (plan +x)
        XCTAssertEqual(a0.sweep, 90, accuracy: 1e-9)
        XCTAssertEqual(a0.radius, 0.35, accuracy: 1e-9)
        XCTAssertEqual(a0.center.y, 0.01, accuracy: 1e-9)
        let a1 = s.arcs.first { $0.id == "corner:\(r.id.uuidString):1:arc" }!
        XCTAssertEqual(a1.startAngle, 90, accuracy: 1e-9)     // along the east wall (plan +y)
        XCTAssertEqual(a1.center.x, 6, accuracy: 1e-9)
        XCTAssertEqual(a1.center.z, 0, accuracy: 1e-9)
        let a2 = s.arcs.first { $0.id == "corner:\(r.id.uuidString):2:arc" }!
        XCTAssertEqual(a2.startAngle, 180, accuracy: 1e-9)
        let a3 = s.arcs.first { $0.id == "corner:\(r.id.uuidString):3:arc" }!
        XCTAssertEqual(a3.startAngle, 270, accuracy: 1e-9)
    }

    func testAngleLabelSitsAtTheArcMidAngleJustAboveTheFloor() {
        let r = rect(6, 4)
        let s = scene([r])
        let l = label(s, "corner:\(r.id.uuidString):0:angle")
        // Mid angle is 45 degrees into the room from the south-west corner.
        XCTAssertGreaterThan(l.position.x, 0)
        XCTAssertLessThan(l.position.z, 0)     // plan +y is world -z
        XCTAssertEqual(l.position.x, -l.position.z, accuracy: 1e-9)
        XCTAssertLessThan(l.position.y, 0.2)
        XCTAssertGreaterThan(l.position.y, 0)
    }

    func testAngleStateThresholds() {
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 90), .neutral)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 90.99), .neutral)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 89.2), .neutral)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 91.5), .caution)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 87.5), .caution)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 93.0), .caution)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 93.5), .critical)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 84), .critical)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 270), .neutral)   // L-shape reflex corner
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: 181), .neutral)
        XCTAssertEqual(OverlayBuilder.angleState(forInteriorAngle: .nan), .neutral)
    }

    func testOutOfSquareRoomIsFlaggedWithANumberNotJustColour() {
        let dx = 4.0 * tan(5.0 * Double.pi / 180)      // pulls two corners ~5 degrees off square
        let r = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-dx, 4)])
        let s = scene([r])
        let angles = s.labels.filter { $0.kind == .angle }
        XCTAssertEqual(angles.filter { $0.state == .critical }.count, 2)
        XCTAssertEqual(angles.filter { $0.state == .neutral }.count, 2)
        for l in angles where l.state == .critical {
            XCTAssertEqual(l.subtitle, "out of square")
            XCTAssertNotEqual(l.title, "90.0\u{00B0}")
            XCTAssertEqual(l.priority, OverlayPriority.angleCritical)
        }
        let arcStates = s.arcs.map(\.state)
        XCTAssertEqual(arcStates.filter { $0 == .critical }.count, 2)
    }

    func testCautionBand() {
        let dx = 4.0 * tan(2.0 * Double.pi / 180)
        let r = Room.polygon(name: "Slight", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-dx, 4)])
        let angles = scene([r]).labels.filter { $0.kind == .angle }
        XCTAssertEqual(angles.filter { $0.state == .caution }.count, 2)
        XCTAssertTrue(angles.filter { $0.state == .caution }.allSatisfy { $0.priority == OverlayPriority.angleCaution })
    }

    func testLShapeReflexCornerIsNotFlagged() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        let s = scene([l])
        XCTAssertEqual(s.arcs.count, 6)
        XCTAssertTrue(s.labels.filter { $0.kind == .angle }.allSatisfy { $0.state == .neutral })
        let reflex = s.arcs.first { $0.id == "corner:\(l.id.uuidString):3:arc" }!
        XCTAssertEqual(reflex.sweep, 270, accuracy: 1e-9)
        // The reflex wedge opens from the next wall (up the plan) counter-clockwise by 270 degrees.
        XCTAssertEqual(reflex.startAngle, 90, accuracy: 1e-9)
    }

    func testArcRadiusNeverExceedsFortyPercentOfTheShorterWall() {
        let r = Room.polygon(name: "Narrow", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 0.5), Point2(0, 0.5)])
        let s = scene([r])
        XCTAssertEqual(s.arcs.count, 4)
        for a in s.arcs { XCTAssertEqual(a.radius, 0.4 * 0.5, accuracy: 1e-9) }
        // A 4 cm wall is too small for an arc at all.
        let sliver = Room.polygon(name: "Sliver", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 0.04), Point2(0, 0.04)])
        XCTAssertTrue(scene([sliver]).arcs.isEmpty)
    }

    func testStraightContinuationsGetNoArc() {
        let r = Room.polygon(name: "Split", corners: [Point2(0, 0), Point2(3, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)])
        let s = scene([r])
        XCTAssertEqual(s.arcs.count, 4)
        XCTAssertEqual(s.labels.filter { $0.kind == .angle }.count, 4)
    }

    func testClockwiseStoredRoomStillGetsCorrectArcsAndInsideLabels() {
        // Deliberately wound clockwise (the model promises counter-clockwise; the overlay must not mirror).
        let pts = [Point2(0, 0), Point2(0, 4), Point2(6, 4), Point2(6, 0)]
        let h = Measured(scanned: 2.8)
        let walls = pts.indices.map { Wall(start: pts[$0], end: pts[($0 + 1) % 4], height: h) }
        let room = Room(name: "CW", walls: walls, ceilingHeight: h)
        let s = scene([room])
        // Every wall label is inside the room outline (plan space).
        for w in room.walls {
            let l = label(s, "wall:\(w.id.uuidString):length")
            XCTAssertTrue(Polygon.contains(pts, l.position.plan), "label of wall \(w.id) must be inside")
        }
        for a in s.arcs {
            XCTAssertEqual(a.sweep, 90, accuracy: 1e-6)
            // The arc's mid direction points into the room.
            let mid = (a.startAngle + a.sweep / 2) * Double.pi / 180
            let probe = a.center.plan + Point2(cos(mid), sin(mid)) * 0.1
            XCTAssertTrue(Polygon.contains(pts, probe))
        }
    }

    // MARK: Openings

    func testOpeningLabelsAreShortAndUseTheUsersUnits() {
        let r = rect(6, 4, openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1, width: 1.5, height: 1.4, sill: 0.9)])
        let s = scene([r])
        let door = label(s, "opening:\(r.openings[0].id.uuidString):size")
        let window = label(s, "opening:\(r.openings[1].id.uuidString):size")
        XCTAssertEqual(door.title, "D 900 x 2100")
        XCTAssertEqual(window.title, "W 1500 x 1400 / sill 900")
        let metres = scene([r], units: DisplayUnits(length: .metres))
        XCTAssertEqual(label(metres, "opening:\(r.openings[0].id.uuidString):size").title, "D 0.90 x 2.10 m")
        XCTAssertEqual(label(metres, "opening:\(r.openings[1].id.uuidString):size").title, "W 1.50 x 1.40 / sill 0.90 m")
        XCTAssertEqual(door.priority, OverlayPriority.opening)
        XCTAssertEqual(door.state, .scanned)
    }

    func testOpeningLabelSitsAtTheOpeningCentreOnTheWall() {
        let r = rect(6, 4, openings: [.door(wall: 0, offset: 0.5)])
        let s = scene([r])
        let door = label(s, "opening:\(r.openings[0].id.uuidString):size")
        XCTAssertEqual(door.position.x, 0.5 + 0.45, accuracy: 1e-9)
        XCTAssertEqual(door.position.y, 1.05, accuracy: 1e-9)
        XCTAssertEqual(door.position.z, -0.04, accuracy: 1e-9)
    }

    func testOpeningEdgesFormARectangleOnTheWall() {
        let r = rect(6, 4, openings: [.window(wall: 0, offset: 1, width: 2, height: 1.4, sill: 0.9)])
        let s = scene([r])
        let id = r.openings[0].id.uuidString
        let edges = s.segments.filter { $0.kind == .openingEdge }
        XCTAssertEqual(edges.count, 4)
        let top = edges.first { $0.id == "opening:\(id):top" }!
        XCTAssertEqual(top.a.y, 2.3, accuracy: 1e-9)
        XCTAssertEqual(top.a.x, 1, accuracy: 1e-9)
        XCTAssertEqual(top.b.x, 3, accuracy: 1e-9)
        let left = edges.first { $0.id == "opening:\(id):left" }!
        XCTAssertEqual(left.a.y, 0.9, accuracy: 1e-9)
        XCTAssertEqual(left.b.y, 2.3, accuracy: 1e-9)
    }

    func testVerifiedOpeningStates() {
        var r = rect(6, 4, openings: [.door(wall: 0, offset: 0.5)])
        r.openings[0].width.verify(0.91, source: .tape)
        var s = scene([r])
        var l = label(s, "opening:\(r.openings[0].id.uuidString):size")
        XCTAssertEqual(l.state, .scanned, "only half checked")
        XCTAssertEqual(l.subtitle, "Width checked")
        XCTAssertEqual(l.title, "D 910 x 2100")
        r.openings[0].height.verify(2.11, source: .tape)
        s = scene([r])
        l = label(s, "opening:\(r.openings[0].id.uuidString):size")
        XCTAssertEqual(l.state, .verified)
        XCTAssertEqual(l.subtitle, "Tape")
    }

    func testOrphanOpeningsAreSkipped() {
        var r = rect()
        r.openings.append(Opening(kind: .door, wallID: nil, offsetFromWallStart: 0, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)))
        r.openings.append(Opening(kind: .door, wallID: UUID(), offsetFromWallStart: 0, width: Measured(scanned: 0.9), height: Measured(scanned: 2.1)))
        let s = scene([r])
        XCTAssertTrue(s.labels.filter { $0.kind == .opening }.isEmpty)
        XCTAssertTrue(s.segments.filter { $0.kind == .openingEdge }.isEmpty)
    }

    // MARK: Heights, area, measurements

    func testCeilingAndAreaLabels() {
        let r = rect(6, 4)
        let s = scene([r])
        let ceiling = label(s, "room:\(r.id.uuidString):ceiling")
        XCTAssertEqual(ceiling.title, "Ceiling 2800 mm")
        XCTAssertEqual(ceiling.position.x, 3, accuracy: 1e-9)
        XCTAssertEqual(ceiling.position.z, -2, accuracy: 1e-9)
        XCTAssertEqual(ceiling.position.y, 1.4, accuracy: 1e-9)
        let area = label(s, "room:\(r.id.uuidString):area")
        XCTAssertEqual(area.title, "24.0 m\u{00B2}")
        XCTAssertEqual(area.subtitle, "Living")
        XCTAssertEqual(area.state, .neutral)
        XCTAssertLessThan(area.priority, ceiling.priority)
    }

    func testVerifiedCeilingShowsItsSource() {
        var r = rect()
        r.ceilingHeight.verify(2.83, source: .laser)
        let l = label(scene([r]), "room:\(r.id.uuidString):ceiling")
        XCTAssertEqual(l.state, .verified)
        XCTAssertEqual(l.title, "Ceiling 2830 mm")
        XCTAssertEqual(l.subtitle, "Laser")
    }

    func testLShapeLabelPointStaysInsideTheRoom() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(10, 0), Point2(10, 1), Point2(1, 1), Point2(1, 10), Point2(0, 10)])
        // The centroid of this thin L sits in the empty corner; the label point must not.
        XCTAssertFalse(Polygon.contains(l.outline, Polygon.centroid(l.outline)))
        let p = OverlayBuilder.labelPoint(in: l.outline)!
        XCTAssertTrue(Polygon.contains(l.outline, p))
        let s = scene([l])
        let area = label(s, "room:\(l.id.uuidString):area")
        XCTAssertTrue(Polygon.contains(l.outline, area.position.plan))
    }

    func testRectangleLabelPointIsTheExactCentre() {
        let r = rect(6, 4)
        let p = OverlayBuilder.labelPoint(in: r.outline)!
        XCTAssertEqual(p.x, 3, accuracy: 1e-9)
        XCTAssertEqual(p.y, 2, accuracy: 1e-9)
        XCTAssertNil(OverlayBuilder.labelPoint(in: [Point2(0, 0), Point2(1, 1)]))
    }

    func testWallHeightLabelOnlyWhenItDiffersFromTheCeiling() {
        var r = rect()
        XCTAssertTrue(scene([r]).labels.filter { $0.kind == .wallHeight }.isEmpty)
        r.walls[1].height = Measured(scanned: 2.4)
        let s = scene([r])
        let heights = s.labels.filter { $0.kind == .wallHeight }
        XCTAssertEqual(heights.count, 1)
        XCTAssertEqual(heights[0].title, "Height 2400 mm")
    }

    func testSavedMeasurementsAppearAsLineAndLabel() {
        var r = rect()
        let m = CustomMeasurement(label: "Wardrobe wall", a: Point3(1, 0.1, -1), b: Point3(3, 0.1, -1))
        r.customMeasurements = [m]
        let s = scene([r])
        let line = s.segments.first { $0.kind == .measurement }
        XCTAssertNotNil(line)
        let l = label(s, "measure:\(m.id.uuidString):label")
        XCTAssertEqual(l.title, "2000 mm")
        XCTAssertEqual(l.position.x, 2, accuracy: 1e-9)
        XCTAssertTrue(l.subtitle?.hasPrefix("Wardrobe wall") ?? false)
        XCTAssertEqual(l.state, .scanned)
        XCTAssertTrue(scene([r], OverlayOptions(showDimensions: false)).segments.filter { $0.kind == .measurement }.isEmpty)
    }

    // MARK: Options and priorities

    func testEveryOptionFlagIsHonoured() {
        let r = rect(6, 4, openings: [.door(wall: 0, offset: 0.5)])
        let none = OverlayOptions(showWireframe: false, showDimensions: false, showAngles: false,
                                  showOpenings: false, showHeights: false, showArea: false)
        XCTAssertTrue(scene([r], none).isEmpty)

        var o = none; o.showWireframe = true
        var s = scene([r], o)
        XCTAssertFalse(s.segments.isEmpty)
        XCTAssertTrue(s.labels.isEmpty)
        XCTAssertTrue(s.segments.allSatisfy { [.wallBase, .wallTop, .wallCorner].contains($0.kind) })

        o = none; o.showDimensions = true
        s = scene([r], o)
        XCTAssertEqual(Set(s.labels.map(\.kind)), [.wallLength])
        XCTAssertEqual(Set(s.segments.map(\.kind)), [.dimension])

        o = none; o.showAngles = true
        s = scene([r], o)
        XCTAssertEqual(Set(s.labels.map(\.kind)), [.angle])
        XCTAssertEqual(s.arcs.count, 4)
        XCTAssertTrue(s.segments.isEmpty)

        o = none; o.showOpenings = true
        s = scene([r], o)
        XCTAssertEqual(Set(s.labels.map(\.kind)), [.opening])
        XCTAssertTrue(s.segments.isEmpty, "opening outlines are wireframe, so they need showWireframe too")
        o.showWireframe = true
        XCTAssertEqual(Set(scene([r], o).segments.map(\.kind)).intersection([.openingEdge]), [.openingEdge])

        o = none; o.showHeights = true
        s = scene([r], o)
        XCTAssertEqual(Set(s.labels.map(\.kind)), [.ceiling])

        o = none; o.showArea = true
        s = scene([r], o)
        XCTAssertEqual(Set(s.labels.map(\.kind)), [.area])
        XCTAssertTrue(s.arcs.isEmpty)
    }

    func testLiveOptionsAreTheLighterSet() {
        let r = rect(6, 4, openings: [.door(wall: 0, offset: 0.5)])
        let s = scene([r], .live)
        let kinds = Set(s.labels.map(\.kind))
        XCTAssertEqual(kinds, [.wallLength, .area])
        XCTAssertTrue(s.arcs.isEmpty)
    }

    func testPriorityOrderFollowsTheBrief() {
        let dx = 4.0 * tan(5.0 * Double.pi / 180)
        var r = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-dx, 4)],
                             openings: [.door(wall: 0, offset: 0.5)])
        r.walls[1].height = Measured(scanned: 2.4)
        let s = scene([r])
        func p(_ k: OverlayLabelKind, _ st: OverlayState? = nil) -> Int {
            s.labels.first { $0.kind == k && (st == nil || $0.state == st) }!.priority
        }
        XCTAssertGreaterThan(p(.angle, .critical), p(.opening))
        XCTAssertGreaterThan(p(.opening), p(.wallLength))
        XCTAssertGreaterThan(p(.wallLength), p(.wallHeight))
        XCTAssertGreaterThanOrEqual(p(.wallHeight), p(.ceiling))
        XCTAssertGreaterThan(p(.ceiling), p(.area))
        XCTAssertGreaterThan(p(.angle, .neutral), p(.area))
    }

    func testHighlightedRoomOutranksTheOthersAndChangesNothingElse() {
        let a = rect(5, 4), b = Room.rectangle(name: "Bed", width: 3, depth: 3, ceilingHeight: 2.8)
        let plain = scene([a, b])
        let lit = scene([a, b], highlight: b.id)
        XCTAssertEqual(plain.segments, lit.segments)
        XCTAssertEqual(plain.arcs, lit.arcs)
        XCTAssertEqual(plain.labels.map(\.id), lit.labels.map(\.id))
        let litB = lit.labels.filter { $0.roomID == b.id }
        let litA = lit.labels.filter { $0.roomID == a.id }
        let maxA = litA.map(\.priority).max() ?? 0
        let minB = litB.map(\.priority).min() ?? 0
        XCTAssertGreaterThan(minB, maxA)
        XCTAssertEqual(plain.labels.filter { $0.roomID == a.id }.map(\.priority), litA.map(\.priority))
    }

    func testMultipleRoomsAreAllIncluded() {
        let a = rect(5, 4), b = Room.rectangle(name: "Bed", origin: Point2(6, 0), width: 3, depth: 3)
        let s = scene([a, b])
        XCTAssertEqual(Set(s.labels.compactMap(\.roomID)), [a.id, b.id])
        let ids = s.labels.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: Robustness

    func testBadGeometryNeverProducesNaN() {
        var r = rect()
        r.walls[0].start = Point2(.nan, 0)
        r.walls[2].end = Point2(.infinity, 1)
        r.walls[1].height = Measured(scanned: .nan)
        r.walls[3].length = Measured(scanned: .nan)
        r.ceilingHeight = Measured(scanned: .nan)
        r.openings.append(Opening(kind: .window, wallID: r.walls[1].id, offsetFromWallStart: .nan,
                                  width: Measured(scanned: 1), height: Measured(scanned: 1)))
        let s = scene([r])
        assertAllFinite(s)
    }

    func testZeroLengthWallsAreSkipped() {
        let h = Measured(scanned: 2.8)
        let pts = [Point2(0, 0), Point2(4, 0), Point2(4, 0), Point2(4, 3), Point2(0, 3)]
        let walls = pts.indices.map { Wall(start: pts[$0], end: pts[($0 + 1) % pts.count], height: h) }
        let room = Room(name: "Dup", walls: walls, ceilingHeight: h)
        let s = scene([room])
        assertAllFinite(s)
        XCTAssertEqual(s.labels.filter { $0.kind == .wallLength }.count, 4)
    }

    func testVirtualWallsGetNoTopEdge() {
        var r = rect()
        r.walls[1].kind = .virtual
        let s = scene([r])
        XCTAssertEqual(s.segments.filter { $0.kind == .wallBase }.count, 4)
        XCTAssertEqual(s.segments.filter { $0.kind == .wallTop }.count, 3)
    }

    // MARK: Spoken text

    func testSpokenDescriptions() {
        var r = rect(6, 4, openings: [.window(wall: 2, offset: 1, width: 1.5, height: 1.4, sill: 0.9)])
        r.walls[0].length.verify(6.03, source: .laser)
        let s = scene([r])
        let verified = label(s, "wall:\(r.walls[0].id.uuidString):length")
        XCTAssertEqual(verified.spokenDescription, "Wall length 6030 millimetres, verified with laser")
        let scanned = label(s, "wall:\(r.walls[1].id.uuidString):length")
        XCTAssertTrue(scanned.spokenDescription.hasPrefix("Wall length 4000 millimetres, scanned, not checked, plus or minus"))
        XCTAssertTrue(scanned.spokenDescription.hasSuffix("millimetres"))
        let window = label(s, "opening:\(r.openings[0].id.uuidString):size")
        XCTAssertTrue(window.spokenDescription.hasPrefix("window 1500 by 1400, sill 900"), window.spokenDescription)
        let angle = label(s, "corner:\(r.id.uuidString):0:angle")
        XCTAssertEqual(angle.spokenDescription, "Corner angle 90.0 degrees")
        let area = label(s, "room:\(r.id.uuidString):area")
        // Verified wall 0 (6.03 m) flows into the rectangle's area: 6.03 x 4 = 24.12.
        XCTAssertEqual(area.spokenDescription, "Floor area 24.1 square metres, Living")
        let imperial = scene([r], units: DisplayUnits(length: .feetAndInches))
        XCTAssertTrue(label(imperial, "wall:\(r.walls[1].id.uuidString):length").spokenDescription
            .hasPrefix("Wall length 13 feet 1 1/2 inches, scanned, not checked"))
        XCTAssertEqual(SpokenText.expand("D 900 x 2100", isOpening: true), "door 900 by 2100")
        XCTAssertEqual(SpokenText.expand("Maid's Room", isOpening: false), "Maid's Room")
    }

    func testCriticalAngleIsSpokenAsOutOfSquare() {
        let dx = 4.0 * tan(5.0 * Double.pi / 180)
        let r = Room.polygon(name: "Skew", corners: [Point2(0, 0), Point2(5, 0), Point2(5, 4), Point2(-dx, 4)])
        let l = scene([r]).labels.first { $0.kind == .angle && $0.state == .critical }!
        XCTAssertTrue(l.spokenDescription.hasSuffix("out of square"))
        XCTAssertTrue(l.spokenDescription.contains("degrees"))
    }

    // MARK: - LabelLayout

    private func cand(_ id: String, _ x: Double, _ y: Double, w: Double = 80, h: Double = 28,
                      p: Int = 50, d: Double = 2) -> LabelCandidate {
        LabelCandidate(id: id, x: x, y: y, width: w, height: h, priority: p, distance: d)
    }
    private let screen = LabelViewport(width: 400, height: 800)

    func testSeparateLabelsAreAllPlacedAtTheirAnchors() {
        let placed = LabelLayout.place([cand("a", 100, 100), cand("b", 300, 400)], viewport: screen)
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed.first { $0.id == "a" }?.x, 100)
        XCTAssertEqual(placed.first { $0.id == "a" }?.y, 100)
        XCTAssertEqual(placed.first { $0.id == "a" }?.opacity, 1)
    }

    func testHigherPriorityWinsAndTheOtherIsNudgedVertically() {
        // Same spot: the lower priority one moves up by one label height (plus the gap).
        let placed = LabelLayout.place([cand("low", 200, 400, p: 10), cand("high", 200, 400, p: 90)], viewport: screen)
        XCTAssertEqual(placed.map(\.id), ["high", "low"])
        let high = placed[0], low = placed[1]
        XCTAssertEqual(high.y, 400)
        XCTAssertEqual(low.x, 200)
        XCTAssertEqual(low.y, 400 - 30, accuracy: 1e-9)
    }

    func testLabelIsDroppedWhenNudgingCannotClearIt() {
        // One-step budget: the second goes up one, the third down one, and the fourth has nowhere left to go.
        let opts = LabelLayoutOptions(maxNudgeSteps: 1)
        let stack = [cand("a", 200, 400, p: 90), cand("b", 200, 400, p: 80),
                     cand("c", 200, 400, p: 70), cand("d", 200, 400, p: 60)]
        let placed = LabelLayout.place(stack, viewport: screen, options: opts)
        XCTAssertEqual(placed.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(placed.map(\.y), [400, 370, 430])
        // The default budget of two steps keeps a fourth.
        XCTAssertEqual(LabelLayout.place(stack, viewport: screen).map(\.id), ["a", "b", "c", "d"])
    }

    func testSmallOverlapIsTolerated() {
        // 10 % of the label's width overlapped: under the 15 % limit, stays where it is.
        let placed = LabelLayout.place([cand("a", 200, 400, p: 90), cand("b", 200 + 72, 400, p: 10)], viewport: screen)
        XCTAssertEqual(placed.first { $0.id == "b" }?.y, 400)
        // 50 % overlapped: moved.
        let moved = LabelLayout.place([cand("a", 200, 400, p: 90), cand("b", 200 + 40, 400, p: 10)], viewport: screen)
        XCTAssertNotEqual(moved.first { $0.id == "b" }?.y, 400)
    }

    func testNearerLabelWinsATiePriority() {
        let placed = LabelLayout.place([cand("far", 200, 400, p: 50, d: 6), cand("near", 200, 400, p: 50, d: 1)], viewport: screen)
        XCTAssertEqual(placed.first?.id, "near")
        XCTAssertEqual(placed.first?.y, 400)
    }

    func testResultDoesNotDependOnInputOrder() {
        let items = (0..<12).map { cand("id\($0)", 100 + Double($0 % 3) * 30, 300 + Double($0 / 3) * 10, p: 50, d: 2) }
        let a = LabelLayout.place(items, viewport: screen)
        let b = LabelLayout.place(items.reversed(), viewport: screen)
        let c = LabelLayout.place(items.shuffledDeterministically(), viewport: screen)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
    }

    func testOpacityFadesWithDistance() {
        XCTAssertEqual(LabelLayout.distanceOpacity(0), 1)
        XCTAssertEqual(LabelLayout.distanceOpacity(4), 1)
        XCTAssertEqual(LabelLayout.distanceOpacity(8), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LabelLayout.distanceOpacity(12), 0)
        XCTAssertEqual(LabelLayout.distanceOpacity(30), 0)
        XCTAssertEqual(LabelLayout.distanceOpacity(.nan), 0)
        let placed = LabelLayout.place([cand("mid", 100, 100, d: 8), cand("gone", 300, 300, d: 12.5)], viewport: screen)
        XCTAssertEqual(placed.map(\.id), ["mid"])
        XCTAssertEqual(placed[0].opacity, 0.5, accuracy: 1e-9)
    }

    func testLabelsFadeAndDisappearOffTheScreenEdge() {
        // Fully inside: opaque. Hanging 20 pt off (half of the 40 pt margin): half opacity. 40 pt off: gone.
        let inside = LabelLayout.place([cand("a", 200, 100)], viewport: screen)
        XCTAssertEqual(inside[0].opacity, 1)
        let half = LabelLayout.place([cand("a", 40 - 20, 100)], viewport: screen)   // left edge at -20
        XCTAssertEqual(half[0].opacity, 0.5, accuracy: 1e-9)
        let off = LabelLayout.place([cand("a", 40 - 45, 100)], viewport: screen)
        XCTAssertTrue(off.isEmpty)
        XCTAssertTrue(LabelLayout.place([cand("a", 5000, 100)], viewport: screen).isEmpty)
    }

    func testBadInputIsIgnored() {
        let placed = LabelLayout.place([cand("nan", .nan, 100), cand("zero", 100, 100, w: 0), cand("ok", 100, 100)], viewport: screen)
        XCTAssertEqual(placed.map(\.id), ["ok"])
        XCTAssertTrue(LabelLayout.place([cand("a", 1, 1)], viewport: LabelViewport(width: 0, height: 0)).isEmpty)
        XCTAssertTrue(LabelLayout.place([], viewport: screen).isEmpty)
    }

    // MARK: Hysteresis

    func testHysteresisHoldsAHiddenDecisionUntilItPersists() {
        var h = LabelHysteresis(requiredFrames: 3)
        let c = cand("a", 100, 100)
        let shown = PlacedLabel(id: "a", x: 100, y: 100, opacity: 1)

        // First sight adopts the layout's decision.
        XCTAssertEqual(h.stabilise([shown], candidates: [c]).map(\.id), ["a"])
        // The layout drops it for two frames: still drawn.
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), ["a"])
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), ["a"])
        // It comes back before the third: the counter resets.
        XCTAssertEqual(h.stabilise([shown], candidates: [c]).map(\.id), ["a"])
        // Dropped for three consecutive frames: now it goes.
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), ["a"])
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), ["a"])
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), [])
    }

    func testHysteresisDelaysAppearanceOfAHiddenLabel() {
        var h = LabelHysteresis(requiredFrames: 3)
        let c = cand("a", 100, 100)
        let shown = PlacedLabel(id: "a", x: 100, y: 100, opacity: 1)
        XCTAssertEqual(h.stabilise([], candidates: [c]).map(\.id), [])          // first sight: hidden
        XCTAssertEqual(h.stabilise([shown], candidates: [c]).map(\.id), [])
        XCTAssertEqual(h.stabilise([shown], candidates: [c]).map(\.id), [])
        XCTAssertEqual(h.stabilise([shown], candidates: [c]).map(\.id), ["a"])  // third frame in a row
    }

    func testHeldLabelFollowsItsProjectedPosition() {
        var h = LabelHysteresis(requiredFrames: 3)
        _ = h.stabilise([PlacedLabel(id: "a", x: 100, y: 100, opacity: 0.8)], candidates: [cand("a", 100, 100)])
        let held = h.stabilise([], candidates: [cand("a", 130, 90)])
        XCTAssertEqual(held.first?.x, 130)
        XCTAssertEqual(held.first?.y, 90)
        XCTAssertEqual(held.first?.opacity ?? 0, 0.8, accuracy: 1e-9)
    }

    func testLabelsThatLeaveTheScreenVanishImmediatelyAndAreForgotten() {
        var h = LabelHysteresis(requiredFrames: 3)
        let c = cand("a", 100, 100)
        _ = h.stabilise([PlacedLabel(id: "a", x: 100, y: 100, opacity: 1)], candidates: [c])
        XCTAssertEqual(h.trackedCount, 1)
        XCTAssertTrue(h.stabilise([], candidates: []).isEmpty)
        XCTAssertEqual(h.trackedCount, 0)
    }

    // MARK: - TapeMeasure

    func testReadingOfAKnownTriangle() {
        let r = TapeMeasure.reading(from: Point3(1, 1, 1), to: Point3(4, 1, 5))
        XCTAssertEqual(r.lengthM, 5, accuracy: 1e-12)
        XCTAssertEqual(r.horizontalM, 5, accuracy: 1e-12)
        XCTAssertEqual(r.verticalM, 0, accuracy: 1e-12)
        XCTAssertEqual(r.slopeDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(r.deltaX, 3); XCTAssertEqual(r.deltaY, 0); XCTAssertEqual(r.deltaZ, 4)
    }

    func testReadingSlopeAndSigns() {
        let up = TapeMeasure.reading(from: .zero, to: Point3(1, 1, 0))
        XCTAssertEqual(up.slopeDegrees, 45, accuracy: 1e-9)
        XCTAssertEqual(up.lengthM, 2.0.squareRoot(), accuracy: 1e-12)
        let down = TapeMeasure.reading(from: Point3(0, 2.8, 0), to: .zero)
        XCTAssertEqual(down.deltaY, -2.8, accuracy: 1e-12)
        XCTAssertEqual(down.verticalM, 2.8, accuracy: 1e-12)
        XCTAssertEqual(down.slopeDegrees, 90, accuracy: 1e-9)
        let same = TapeMeasure.reading(from: Point3(1, 2, 3), to: Point3(1, 2, 3))
        XCTAssertEqual(same.lengthM, 0)
        XCTAssertEqual(same.slopeDegrees, 0)
        let bad = TapeMeasure.reading(from: .zero, to: Point3(.nan, 0, 0))
        XCTAssertEqual(bad.lengthM, 0)
    }

    func testQuantiseRoundsToTheNearestMillimetreForDisplay() {
        XCTAssertEqual(TapeMeasure.quantise(1.23449), 1.234, accuracy: 1e-12)
        XCTAssertEqual(TapeMeasure.quantise(1.2345001), 1.235, accuracy: 1e-12)
        XCTAssertEqual(TapeMeasure.quantise(-0.0004), 0)
        XCTAssertEqual(TapeMeasure.quantise(.nan), 0)
    }

    func testSnapPicksTheNearestCandidateWithinRadius() {
        let cs = [TapeSnapCandidate(id: "far", position: Point3(0.05, 0, 0)),
                  TapeSnapCandidate(id: "near", position: Point3(0.02, 0, 0), label: "Corner A"),
                  TapeSnapCandidate(id: "out", position: Point3(1, 0, 0))]
        let hit = TapeMeasure.snap(.zero, to: cs)
        XCTAssertTrue(hit.didSnap)
        XCTAssertEqual(hit.candidate?.id, "near")
        XCTAssertEqual(hit.point, Point3(0.02, 0, 0))
        XCTAssertEqual(hit.distance ?? 0, 0.02, accuracy: 1e-12)
        let miss = TapeMeasure.snap(Point3(0.5, 0, 0), to: cs)
        XCTAssertFalse(miss.didSnap)
        XCTAssertEqual(miss.point, Point3(0.5, 0, 0))
        XCTAssertTrue(TapeMeasure.snap(.zero, to: cs, radius: 0.01).candidate == nil)
        XCTAssertEqual(TapeMeasure.snap(.zero, to: cs, radius: 0.5).candidate?.id, "near")
    }

    func testSnapTiesAreBrokenByIdAndBarePointsWork() {
        let cs = [TapeSnapCandidate(id: "b", position: Point3(0.03, 0, 0)), TapeSnapCandidate(id: "a", position: Point3(-0.03, 0, 0))]
        XCTAssertEqual(TapeMeasure.snap(.zero, to: cs).candidate?.id, "a")
        XCTAssertEqual(TapeMeasure.snap(.zero, to: cs.reversed()).candidate?.id, "a")
        let bare = TapeMeasure.snap(Point3(1, 1, 1), toPoints: [Point3(1.01, 1, 1)])
        XCTAssertEqual(bare.point, Point3(1.01, 1, 1))
        XCTAssertFalse(TapeMeasure.snap(.zero, to: []).didSnap)
        XCTAssertFalse(TapeMeasure.snap(Point3(.nan, 0, 0), to: cs).didSnap)
    }

    func testSnapTrackerFiresOnceWhenASnapEngages() {
        var t = TapeSnapTracker()
        let a = TapeSnap(point: .zero, candidate: TapeSnapCandidate(id: "a", position: .zero), distance: 0)
        let b = TapeSnap(point: .zero, candidate: TapeSnapCandidate(id: "b", position: .zero), distance: 0)
        let none = TapeSnap(point: .zero)
        XCTAssertFalse(t.update(none))
        XCTAssertTrue(t.update(a))
        XCTAssertFalse(t.update(a))
        XCTAssertFalse(t.update(a))
        XCTAssertTrue(t.update(b), "moving to a different corner is a new snap")
        XCTAssertFalse(t.update(none))
        XCTAssertTrue(t.update(b), "re-engaging after releasing ticks again")
    }

    func testMeasureSessionFlow() {
        var s = MeasureSession()
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.overlay(units: mm).isEmpty)
        s.addPoint(Point3(0, 0, 0))
        XCTAssertFalse(s.isComplete)
        XCTAssertNil(s.reading)
        XCTAssertEqual(s.overlay(units: mm).segments.count, 1)
        XCTAssertTrue(s.overlay(units: mm).labels.isEmpty)
        s.addPoint(Point3(3, 0, 4))
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.reading?.lengthM ?? 0, 5, accuracy: 1e-12)
        let o = s.overlay(units: mm)
        XCTAssertEqual(o.segments.first?.kind, .measurement)
        XCTAssertEqual(o.labels.first?.title, "5000 mm")
        XCTAssertEqual(o.labels.first?.position, Point3(1.5, 0, 2))
        // A third tap starts a new measurement.
        s.addPoint(Point3(9, 9, 9))
        XCTAssertFalse(s.isComplete)
        XCTAssertEqual(s.first, Point3(9, 9, 9))
        XCTAssertNil(s.second)
        s.addPoint(Point3(.nan, 0, 0))
        XCTAssertNil(s.second, "non-finite points are ignored")
        s.clear()
        XCTAssertTrue(s.isEmpty)
    }

    func testReadoutFormatsInTheUsersUnits() {
        let r = TapeMeasure.reading(from: .zero, to: Point3(1.2, 0.5, -0.9))
        let mmText = TapeReadout(r, units: mm)
        XCTAssertEqual(mmText.length, "1581 mm")
        XCTAssertEqual(mmText.deltaX, "+1200 mm")
        XCTAssertEqual(mmText.deltaY, "+500 mm")
        XCTAssertEqual(mmText.deltaZ, "-900 mm")
        XCTAssertEqual(mmText.horizontal, "1500 mm")
        XCTAssertEqual(mmText.vertical, "500 mm")
        XCTAssertTrue(mmText.spoken.contains("1581 millimetres"))
        XCTAssertTrue(mmText.spoken.contains("scanned, not checked"))
        let m = TapeReadout(r, units: DisplayUnits(length: .metres))
        XCTAssertEqual(m.length, "1.581 m")
    }

    func testSavedMeasurementGoesToTheRightRoom() {
        let a = Room.rectangle(name: "A", width: 4, depth: 4)
        let b = Room.rectangle(name: "B", origin: Point2(10, 0), width: 4, depth: 4)
        let inB = [Point3(11, 1, -1), Point3(13, 1, -1)]
        XCTAssertEqual(MeasureRoomLocator.roomID(forPoints: inB, in: [a, b], focusRoomID: nil), b.id)
        XCTAssertEqual(MeasureRoomLocator.roomID(forPoints: inB, in: [a, b], focusRoomID: a.id), a.id, "the focused room wins")
        let nowhere = [Point3(100, 0, 100), Point3(101, 0, 100)]
        XCTAssertEqual(MeasureRoomLocator.roomID(forPoints: nowhere, in: [a, b], focusRoomID: nil), a.id)
        XCTAssertEqual(MeasureRoomLocator.roomID(forPoints: nowhere, in: [a, b], focusRoomID: UUID()), a.id)
        XCTAssertNil(MeasureRoomLocator.roomID(forPoints: nowhere, in: [], focusRoomID: nil))
        // One end in room A, one in the open: the midpoint is outside both, so fall back to the point in A.
        let straddle = [Point3(1, 1, -1), Point3(8, 1, -1)]
        XCTAssertEqual(MeasureRoomLocator.roomID(forPoints: straddle, in: [b, a], focusRoomID: nil), a.id)
    }
}

private extension Array {
    /// A fixed, input-independent scramble so ordering tests need no random numbers.
    func shuffledDeterministically() -> [Element] {
        var out = self
        var i = out.count - 1
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        while i > 0 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((seed >> 33) % UInt64(i + 1))
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }
}
