import XCTest
@testable import NexaFixCore

final class SceneGeometryTests: XCTestCase {

    // MARK: Helpers

    private let t = 0.12
    private var withCeiling: SceneOptions { SceneOptions(includeCeiling: true) }
    private var wallsOnly: SceneOptions {
        SceneOptions(wallThickness: 0.12, includeCeiling: false, includeObjects: false, includeOpeningFrames: false)
    }

    private func rect(_ w: Double = 6, _ d: Double = 4, height: Double = 2.8, openings: [OpeningSpec] = [],
                      floor: Double = 0) -> Room {
        var room = Room.rectangle(name: "Living", kind: .livingRoom, width: w, depth: d, ceilingHeight: height,
                                  openings: openings)
        room.floorElevation = floor
        return room
    }

    /// 6 x 4 with a 2 x 2 notch cut from the north-east corner.
    private func lShape(openings: [OpeningSpec] = [], floor: Double = 0) -> Room {
        var room = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2),
                                                     Point2(4, 4), Point2(0, 4)], openings: openings)
        room.floorElevation = floor
        return room
    }

    private func uShape() -> Room {
        Room.polygon(name: "U", corners: [Point2(0, 0), Point2(9, 0), Point2(9, 5), Point2(6, 5), Point2(6, 2),
                                          Point2(3, 2), Point2(3, 5), Point2(0, 5)])
    }

    private func scene(_ rooms: [Room], _ options: SceneOptions = SceneOptions()) -> RoomScene {
        RoomSceneBuilder.scene(for: rooms, options: options)
    }

    private func triangles(_ meshes: [SceneMesh]) -> [(Point3, Point3, Point3)] {
        var out: [(Point3, Point3, Point3)] = []
        for mesh in meshes {
            for i in 0..<mesh.buffer.triangleCount {
                if let tri = mesh.buffer.triangle(i) { out.append(tri) }
            }
        }
        return out
    }

    private func cross(_ a: Point3, _ b: Point3) -> Point3 { SceneVector.cross(a, b) }

    private func area(_ tri: (Point3, Point3, Point3)) -> Double {
        cross(tri.1 - tri.0, tri.2 - tri.0).length / 2
    }

    /// Volume enclosed by the triangles (divergence theorem), measured from the plane y = `floorY`. Walls leave
    /// their bottom open at the floor; that face lies in the reference plane and adds nothing.
    private func signedVolume(_ meshes: [SceneMesh], floorY: Double = 0) -> Double {
        var total = 0.0
        for tri in triangles(meshes) {
            let a = Point3(tri.0.x, tri.0.y - floorY, tri.0.z)
            let b = Point3(tri.1.x, tri.1.y - floorY, tri.1.z)
            let c = Point3(tri.2.x, tri.2.y - floorY, tri.2.z)
            total += a.dot(cross(b, c)) / 6
        }
        return total
    }

    private func wallMeshes(_ s: RoomScene) -> [SceneMesh] {
        s.meshes.filter { $0.material == .wall || $0.material == .wallReveal }
    }

    /// The volume the walls of a room should enclose, worked out independently of the builder: each solid wall
    /// is a prism over the quad between its clear edge and the offset edge (corners at the intersection of the
    /// two neighbouring offset lines), minus the openings cut through it.
    ///
    /// `thicknesses` gives each wall its own thickness (by index); a missing entry means `t`. An opening's hole
    /// is the trapezoid between the clear edge and the outer edge, whose ends are the pieces' outer corners: the
    /// outer end of a piece on the first or last stretch of a wall is the mitred corner, and one that falls
    /// inside an inside corner's shift is held at that corner (the solid there is the neighbour's).
    private func expectedWallVolume(_ room: Room, thickness t: Double, thicknesses: [Double] = []) -> Double {
        let n = room.walls.count
        let ccw = Polygon.isCounterClockwise(room.outline)
        func inward(_ w: Wall) -> Point2 { ccw ? w.direction.perpendicularCCW : -w.direction.perpendicularCCW }
        func thick(_ i: Int) -> Double { i < thicknesses.count ? thicknesses[i] : t }
        /// The point where the offset lines of two walls meet at their shared corner.
        func corner(_ at: Point2, _ a: Int, _ b: Int) -> Point2 {
            let n1 = inward(room.walls[a]), n2 = inward(room.walls[b])
            let ta = thick(a), tb = thick(b)
            let det = n1.x * n2.y - n1.y * n2.x
            if abs(det) < 1e-9 { return at - n2 * Swift.min(ta, tb) }
            // Solve n1 . x = -ta, n2 . x = -tb.
            let x = (-ta * n2.y + tb * n1.y) / det
            let y = (-tb * n1.x + ta * n2.x) / det
            return at + Point2(x, y)
        }
        var volume = 0.0
        var outerAlong: [UUID: (lo: Double, hi: Double)] = [:]
        for i in 0..<n where room.walls[i].kind == .solid {
            let w = room.walls[i]
            let prev = (i + n - 1) % n, next = (i + 1) % n
            let outerStart = room.walls[prev].kind == .solid ? corner(w.start, prev, i) : w.start - inward(w) * thick(i)
            let outerEnd = room.walls[next].kind == .solid ? corner(w.end, i, next) : w.end - inward(w) * thick(i)
            let quad = [w.start, w.end, outerEnd, outerStart]
            volume += Polygon.area(quad) * w.height.scanned
            outerAlong[w.id] = ((outerStart - w.start).dot(w.direction), (outerEnd - w.start).dot(w.direction))
        }
        for opening in room.openings {
            guard let id = opening.wallID, let wall = room.wall(withID: id), wall.kind == .solid,
                  let index = room.walls.firstIndex(where: { $0.id == id }), let along = outerAlong[id],
                  let hole = RoomSceneBuilder.clip(opening, to: wall) else { continue }
            let length = wall.geometricLength
            /// Where the outer edge of a piece that ends at `s` ends.
            func g(_ s: Double) -> Double {
                if s <= 1e-9 { return along.lo }
                if s >= length - 1e-9 { return along.hi }
                return along.lo <= along.hi ? Swift.min(Swift.max(s, along.lo), along.hi) : s
            }
            let footprint = ((hole.x1 - hole.x0) + (g(hole.x1) - g(hole.x0))) / 2 * thick(index)
            volume -= footprint * (hole.y1 - hole.y0)
        }
        return volume
    }

    private func assertInvariants(_ s: RoomScene, file: StaticString = #filePath, line: UInt = #line) {
        var ids = Set<String>()
        for mesh in s.meshes {
            XCTAssertTrue(ids.insert(mesh.id).inserted, "duplicate id \(mesh.id)", file: file, line: line)
            let b = mesh.buffer
            XCTAssertEqual(b.positions.count, b.normals.count, mesh.id, file: file, line: line)
            XCTAssertEqual(b.positions.count % 3, 0, mesh.id, file: file, line: line)
            XCTAssertEqual(b.indices.count % 3, 0, mesh.id, file: file, line: line)
            XCTAssertFalse(b.isEmpty, "empty mesh \(mesh.id)", file: file, line: line)
            XCTAssertTrue(b.positions.allSatisfy { $0.isFinite } && b.normals.allSatisfy { $0.isFinite }, mesh.id,
                          file: file, line: line)
            XCTAssertTrue(b.indices.allSatisfy { Int($0) < b.vertexCount }, "index out of range in \(mesh.id)",
                          file: file, line: line)
            for i in 0..<b.vertexCount {
                XCTAssertEqual(b.normal(i).length, 1, accuracy: 1e-4, "normal length in \(mesh.id)", file: file, line: line)
            }
            for ti in 0..<b.triangleCount {
                guard let tri = b.triangle(ti) else {
                    XCTFail("bad triangle \(ti) in \(mesh.id)", file: file, line: line)
                    continue
                }
                let n = cross(tri.1 - tri.0, tri.2 - tri.0)
                XCTAssertGreaterThan(n.length / 2, 1e-9, "degenerate triangle \(ti) in \(mesh.id)", file: file, line: line)
                // Winding agrees with the stored normal: they point the same way.
                let stored = b.normal(Int(b.indices[3 * ti]))
                XCTAssertGreaterThan(n.dot(stored) / n.length, 0.999, "winding vs normal, \(mesh.id) #\(ti)",
                                     file: file, line: line)
                // Bounds contain every vertex of the mesh and the scene.
                for p in [tri.0, tri.1, tri.2] {
                    for (lo, hi) in [(mesh.boundsMin, mesh.boundsMax), (s.boundsMin, s.boundsMax)] {
                        XCTAssertTrue(p.x >= lo.x - 1e-9 && p.x <= hi.x + 1e-9 && p.y >= lo.y - 1e-9 && p.y <= hi.y + 1e-9
                                      && p.z >= lo.z - 1e-9 && p.z <= hi.z + 1e-9, "vertex outside bounds in \(mesh.id)",
                                      file: file, line: line)
                    }
                }
            }
        }
    }

    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFFFFFF) / Double(0x100000000)
        }
        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    }

    // MARK: Empty and degenerate input

    func testNoRoomsGivesAnEmptyScene() {
        let s = scene([])
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.boundsMin, .zero)
        XCTAssertEqual(s.boundsMax, .zero)
        XCTAssertEqual(s.suggestedCamera.distance, 6)
    }

    func testRoomsThatCannotBeBuiltGiveNothing() {
        let twoWalls = Room(name: "Two", walls: [
            Wall(start: Point2(0, 0), end: Point2(1, 0), height: Measured(scanned: 2.5)),
            Wall(start: Point2(1, 0), end: Point2(0, 0), height: Measured(scanned: 2.5)),
        ], ceilingHeight: Measured(scanned: 2.5))
        XCTAssertTrue(scene([twoWalls]).isEmpty)

        var nan = rect()
        nan.walls[1].end = Point2(.nan, 0)
        XCTAssertTrue(scene([nan]).isEmpty)

        let flat = Room.polygon(name: "Flat", corners: [Point2(0, 0), Point2(2, 0), Point2(4, 0)])
        XCTAssertTrue(scene([flat]).isEmpty)
    }

    func testOneBadRoomDoesNotSpoilTheOthers() {
        var bad = rect()
        bad.walls[0].start = Point2(.infinity, 0)
        let good = rect()
        let s = scene([bad, good])
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.meshes.allSatisfy { $0.roomID == good.id })
    }

    // MARK: Ids

    func testIdsAreDeterministicAndFollowThePattern() {
        let room = rect(openings: [.door(wall: 0, offset: 1), .window(wall: 2, offset: 1, width: 1.5)])
        let a = scene([room], withCeiling)
        let b = scene([room], withCeiling)
        XCTAssertEqual(a.meshes.map(\.id), b.meshes.map(\.id))
        XCTAssertEqual(Set(a.meshes.map(\.id)).count, a.meshes.count)

        let uuid = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
        let prefix = "^room:\(room.id.uuidString):"
        let patterns = [
            prefix + "wall:\(uuid):piece:[0-9]+(:shell|:reveal)?$",
            prefix + "floor$",
            prefix + "ceiling(:slab)?$",
            prefix + "opening:\(uuid):(frame|glass)$",
        ]
        for mesh in a.meshes {
            XCTAssertTrue(patterns.contains { mesh.id.range(of: $0, options: .regularExpression) != nil },
                          "unexpected id \(mesh.id)")
        }
        XCTAssertTrue(a.meshes.contains { $0.id == "room:\(room.id.uuidString):floor" })
    }

    func testRoomsAreBuiltInTheOrderGiven() {
        let r1 = rect(), r2 = rect()
        let s = scene([r1, r2], wallsOnly)
        let order = s.meshes.map(\.roomID)
        let firstOfSecond = order.firstIndex(of: r2.id)!
        XCTAssertTrue(order[..<firstOfSecond].allSatisfy { $0 == r1.id })
        XCTAssertTrue(order[firstOfSecond...].allSatisfy { $0 == r2.id })
    }

    // MARK: Winding, degeneracy, bounds

    func testInvariantsHoldForSimpleAndComplexRooms() {
        let door = OpeningSpec.door(wall: 0, offset: 1.2)
        let window = OpeningSpec.window(wall: 2, offset: 1.0, width: 2.0)
        let stacked = [OpeningSpec.window(wall: 1, offset: 0.5, width: 1.0, height: 0.6, sill: 0.3),
                       OpeningSpec.window(wall: 1, offset: 0.5, width: 1.0, height: 0.6, sill: 1.5)]
        for room in [rect(), rect(openings: [door, window]), rect(openings: stacked), lShape(openings: [door]),
                     uShape(), rect(floor: -1.3)] {
            assertInvariants(scene([room], withCeiling))
        }
    }

    func testClockwiseOutlineBuildsTheSameSolid() {
        let ccw = rect(openings: [.door(wall: 0, offset: 1)])
        var cw = ccw
        cw.walls = ccw.walls.reversed().map { w in
            var flipped = w
            flipped.start = w.end
            flipped.end = w.start
            return flipped
        }
        // Openings measure along the old direction; remove them so only the shell is compared.
        cw.openings = []
        var plain = ccw
        plain.openings = []
        let a = signedVolume(wallMeshes(scene([plain], wallsOnly)))
        let b = signedVolume(wallMeshes(scene([cw], wallsOnly)))
        XCTAssertEqual(a, b, accuracy: 1e-3)
        XCTAssertGreaterThan(b, 0)
        assertInvariants(scene([cw], withCeiling))
    }

    func testDemoApartmentSatisfiesEveryInvariant() {
        let rooms = DemoProperty.make().allRooms
        XCTAssertEqual(rooms.count, 8)
        let s = scene(rooms, withCeiling)
        assertInvariants(s)
        XCTAssertTrue(Set(s.meshes.map(\.roomID)) == Set(rooms.map(\.id)))
        // Floors add up to the polygons' areas.
        let floorArea = s.meshes.filter { $0.material == .floor }.reduce(0.0) { $0 + triangles([$1]).reduce(0.0) { $0 + area($1) } }
        XCTAssertEqual(floorArea, rooms.reduce(0.0) { $0 + Polygon.area($1.outline) }, accuracy: 1e-2)
        // The demo's floor sits at -1.30 in the session frame.
        XCTAssertEqual(s.boundsMin.y, -1.30, accuracy: 1e-4)
    }

    // MARK: Floors and ceilings

    func testFloorAreaEqualsPolygonAreaForConcaveShapes() {
        for room in [rect(), lShape(), uShape()] {
            let s = scene([room], wallsOnly)
            let floor = s.meshes.filter { $0.material == .floor }
            XCTAssertEqual(floor.count, 1)
            let sum = triangles(floor).reduce(0.0) { $0 + area($1) }
            XCTAssertEqual(sum, Polygon.area(room.outline), accuracy: 1e-4, room.name)
            // Faces up, at the floor's height.
            for mesh in floor {
                for i in 0..<mesh.buffer.vertexCount {
                    XCTAssertEqual(mesh.buffer.normal(i).y, 1, accuracy: 1e-6)
                    XCTAssertEqual(mesh.buffer.vertex(i).y, 0, accuracy: 1e-6)
                }
            }
        }
    }

    func testFloorTrianglesStayInsideAnLShape() {
        let room = lShape()
        let s = scene([room], wallsOnly)
        for tri in triangles(s.meshes.filter { $0.material == .floor }) {
            let centroid = Point2((tri.0.x + tri.1.x + tri.2.x) / 3, -(tri.0.z + tri.1.z + tri.2.z) / 3)
            XCTAssertTrue(Polygon.contains(room.outline, centroid), "triangle centroid \(centroid) is in the notch")
        }
    }

    func testFloorElevationIsIncluded() {
        let s = scene([rect(floor: -1.3)], withCeiling)
        XCTAssertEqual(s.boundsMin.y, -1.3, accuracy: 1e-5)
        let ceiling = s.meshes.first { $0.id.hasSuffix(":ceiling") }!
        XCTAssertEqual(ceiling.buffer.vertex(0).y, -1.3 + 2.8, accuracy: 1e-5)
        // The ceiling slab rises above that.
        XCTAssertEqual(s.boundsMax.y, -1.3 + 2.8 + 0.05, accuracy: 1e-5)
    }

    func testCeilingIsOptionalAndFacesDown() {
        XCTAssertFalse(scene([rect()]).meshes.contains { $0.material == .ceiling })
        let s = scene([lShape()], withCeiling)
        let under = s.meshes.first { $0.id.hasSuffix(":ceiling") }!
        XCTAssertTrue(under.isMeasurable)
        XCTAssertEqual(triangles([under]).reduce(0.0) { $0 + area($1) }, 20, accuracy: 1e-4)
        for i in 0..<under.buffer.vertexCount { XCTAssertEqual(under.buffer.normal(i).y, -1, accuracy: 1e-6) }
        let slab = s.meshes.first { $0.id.hasSuffix(":ceiling:slab") }!
        XCTAssertFalse(slab.isMeasurable)
        // Slab: top (20 m2) plus the sides (perimeter 20 x 0.05).
        XCTAssertEqual(triangles([slab]).reduce(0.0) { $0 + area($1) }, 20 + 20 * 0.05, accuracy: 1e-4)

        let thin = scene([rect()], SceneOptions(includeCeiling: true, ceilingSlabThickness: 0))
        XCTAssertFalse(thin.meshes.contains { $0.id.hasSuffix(":ceiling:slab") })
    }

    // MARK: Walls

    func testClearDimensionsArePreservedAndWallsGrowOutward() {
        let s = scene([rect(6, 4)], wallsOnly)
        let clear = s.meshes.filter { $0.material == .wall && $0.isMeasurable }
        XCTAssertEqual(clear.count, 4)
        let merged = SceneMeshBuffer.merging(clear.map(\.buffer)).bounds!
        // Plan x 0...6, plan y 0...4 (world z -4...0): exactly what was scanned.
        XCTAssertEqual(merged.min.x, 0, accuracy: 1e-5)
        XCTAssertEqual(merged.max.x, 6, accuracy: 1e-5)
        XCTAssertEqual(merged.min.z, -4, accuracy: 1e-5)
        XCTAssertEqual(merged.max.z, 0, accuracy: 1e-5)
        XCTAssertEqual(merged.max.y, 2.8, accuracy: 1e-5)
        // The whole model is the clear room plus the wall thickness on every side.
        XCTAssertEqual(s.boundsMin.x, -t, accuracy: 1e-5)
        XCTAssertEqual(s.boundsMax.x, 6 + t, accuracy: 1e-5)
        XCTAssertEqual(s.boundsMin.z, -4 - t, accuracy: 1e-5)
        XCTAssertEqual(s.boundsMax.z, t, accuracy: 1e-5)
    }

    func testWallThicknessIsHeldInRange() {
        func width(_ thickness: Double) -> Double {
            let s = scene([rect(6, 4)], SceneOptions(wallThickness: thickness, includeObjects: false, includeOpeningFrames: false))
            return s.boundsMax.x - 6
        }
        XCTAssertEqual(width(0.25), 0.25, accuracy: 1e-5)
        XCTAssertEqual(width(0), 0.01, accuracy: 1e-5)
        XCTAssertEqual(width(-3), 0.01, accuracy: 1e-5)
        XCTAssertEqual(width(5), 1, accuracy: 1e-5)
        XCTAssertEqual(width(.nan), 0.12, accuracy: 1e-5)
    }

    func testClearFacesPointIntoTheRoomAndShellFacesPointOut() {
        let room = rect(openings: [.door(wall: 0, offset: 1.0), .window(wall: 1, offset: 1.0, width: 1.5)])
        let s = scene([room], wallsOnly)
        for mesh in s.meshes {
            guard let range = mesh.id.range(of: ":wall:") else { continue }
            let rest = mesh.id[range.upperBound...]
            let wallID = UUID(uuidString: String(rest.prefix(36)))!
            let index = room.walls.firstIndex { $0.id == wallID }!
            let w = room.walls[index]
            let inward = Point3(w.inwardNormal.x, 0, -w.inwardNormal.y)
            let isShell = mesh.id.hasSuffix(":shell"), isReveal = mesh.id.hasSuffix(":reveal")
            for i in 0..<mesh.buffer.vertexCount {
                let n = mesh.buffer.normal(i)
                if !isShell && !isReveal {
                    XCTAssertEqual(n.dot(inward), 1, accuracy: 1e-5, "clear face of \(mesh.id)")
                    XCTAssertTrue(mesh.isMeasurable)
                } else {
                    XCTAssertLessThanOrEqual(n.dot(inward), 1e-5, "\(mesh.id) must not face into the room")
                    XCTAssertFalse(mesh.isMeasurable)
                }
            }
        }
    }

    func testWallsEncloseExactlyTheExpectedVolume() {
        let door = OpeningSpec.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1)
        let window = OpeningSpec.window(wall: 2, offset: 1.0, width: 1.5, height: 1.2, sill: 0.9)
        let bigWindow = OpeningSpec.window(wall: 1, offset: 0.5, width: 2.0, height: 2.4, sill: 0.3)
        let cases: [(String, Room)] = [
            ("plain rectangle", rect()),
            ("rectangle with openings", rect(openings: [door, window, bigWindow])),
            ("raised floor", rect(openings: [door], floor: -1.3)),
            ("L-shape", lShape()),
            ("L-shape with openings", lShape(openings: [.door(wall: 0, offset: 1.0), .window(wall: 5, offset: 1.0, width: 2.0)])),
            ("U-shape", uShape()),
        ]
        for (name, room) in cases {
            let s = scene([room], wallsOnly)
            let volume = signedVolume(wallMeshes(s), floorY: room.floorElevation)
            let expected = expectedWallVolume(room, thickness: t)
            XCTAssertEqual(volume, expected, accuracy: 2e-3 + 1e-4 * expected, name)
            XCTAssertGreaterThan(volume, 0, "\(name): normals must point out of the solid")
        }
    }

    func testNoHiddenFacesAreBuilt() {
        // A plain room: per wall a clear face, an outer face and a top, two triangles each. Nothing at the
        // corners, where neighbouring walls meet along the same mitre plane and hide each other's end.
        let plain = scene([rect(6, 4)], wallsOnly)
        XCTAssertEqual(wallMeshes(plain).reduce(0) { $0 + $1.buffer.triangleCount }, 4 * 3 * 2)

        // A door adds two pieces: three clear faces, three outer faces and three tops on that wall, plus the
        // two jambs and the underside of the lintel (the wall ends meeting the door are hidden by the pieces).
        let door = scene([rect(6, 4, openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1)])], wallsOnly)
        let expected = 3 * 3 * 2 + (3 * 3 * 2 + 3 * 2)
        XCTAssertEqual(wallMeshes(door).reduce(0) { $0 + $1.buffer.triangleCount }, expected)
        // Material split: only the reveals are wallReveal.
        XCTAssertEqual(door.meshes.filter { $0.material == .wallReveal }.reduce(0) { $0 + $1.buffer.triangleCount }, 6)
    }

    func testVolumeMatchesTheSumOfPieceVolumesPlusCornerWedges() {
        // Without openings: the pieces' face area times thickness, plus the 4 square corners.
        let room = rect(6, 4)
        let sumOfPieces = room.wallPieces().reduce(0.0) { $0 + $1.area } * t
        let s = scene([room], wallsOnly)
        let volume = signedVolume(wallMeshes(s))
        XCTAssertEqual(volume, sumOfPieces + 4 * t * t * 2.8, accuracy: 2e-3)
    }

    func testWallsOfDifferentHeightsKeepTheirOwnHeights() {
        var room = rect(6, 4)
        room.walls[0].height = Measured(scanned: 3.4)
        let s = scene([room], wallsOnly)
        XCTAssertEqual(signedVolume(wallMeshes(s)), expectedWallVolume(room, thickness: t), accuracy: 3e-3)
        XCTAssertEqual(s.boundsMax.y, 3.4, accuracy: 1e-5)
    }

    func testVirtualWallsProduceNothingAndNeighboursEndSquare() {
        var room = rect(6, 4)
        room.walls[1].kind = .virtual
        let s = scene([room], wallsOnly)
        let virtualID = room.walls[1].id.uuidString
        XCTAssertFalse(s.meshes.contains { $0.id.contains(virtualID) })
        XCTAssertEqual(signedVolume(wallMeshes(s)), expectedWallVolume(room, thickness: t), accuracy: 3e-3)
        assertInvariants(s)
        // The open boundary has no wall: a ray across it from outside goes straight into the room and lands on
        // the clear face of the opposite wall.
        let ray = Ray3(origin: Point3(10, 1.4, -2), direction: Point3(-1, 0, 0))
        let hit = ScenePicker.pick(ray: ray, in: s, snapPoints: [])
        XCTAssertEqual(hit?.point.x ?? .nan, 0, accuracy: 1e-4)
        XCTAssertEqual(hit?.isMeasurable, true)
    }

    func testOpeningsAreRealHoles() {
        let room = rect(6, 4, openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1),
                                         .window(wall: 2, offset: 1.0, width: 1.5, height: 1.2, sill: 0.9)])
        let s = scene([room], wallsOnly)
        // South wall: plan y 0 = world z 0. A ray from the room's centre at the door's middle height.
        func shoot(x: Double, y: Double, towardsZ dz: Double) -> PickResult? {
            ScenePicker.pick(ray: Ray3(origin: Point3(x, y, -2), direction: Point3(0, 0, dz)), in: s, snapPoints: [])
        }
        // Through the door: nothing there to hit.
        XCTAssertNil(shoot(x: 1.45, y: 1.0, towardsZ: 1))
        // Beside the door: the clear face of the wall at z = 0.
        let wall = shoot(x: 0.5, y: 1.0, towardsZ: 1)
        XCTAssertEqual(wall?.point.z ?? .nan, 0, accuracy: 1e-5)
        XCTAssertEqual(wall?.isMeasurable, true)
        // Above the door: the lintel.
        XCTAssertEqual(shoot(x: 1.45, y: 2.4, towardsZ: 1)?.point.z ?? .nan, 0, accuracy: 1e-5)
        // North wall (plan y 4 = world z -4): below the window sill is wall, in the window is a hole.
        XCTAssertEqual(shoot(x: 4.25, y: 0.5, towardsZ: -1)?.point.z ?? .nan, -4, accuracy: 1e-5)
        XCTAssertNil(shoot(x: 4.25, y: 1.5, towardsZ: -1))
    }

    func testStackedOpeningsLeaveAWallBetweenThem() {
        let room = rect(6, 4, openings: [.window(wall: 0, offset: 1, width: 1, height: 0.6, sill: 0.3),
                                         .window(wall: 0, offset: 1, width: 1, height: 0.6, sill: 1.5)])
        let s = scene([room], wallsOnly)
        func z(_ y: Double) -> Double? {
            ScenePicker.pick(ray: Ray3(origin: Point3(1.5, y, -2), direction: Point3(0, 0, 1)), in: s, snapPoints: [])?.point.z
        }
        XCTAssertNil(z(0.6))              // first opening
        XCTAssertEqual(z(1.2) ?? .nan, 0, accuracy: 1e-5)   // the wall between
        XCTAssertNil(z(1.8))              // second opening
        XCTAssertEqual(z(0.1) ?? .nan, 0, accuracy: 1e-5)   // below the lower one
    }

    func testNoGapsAtCornersOrOpeningsSeenFromAbove() {
        let rooms = [rect(6, 4, openings: [.door(wall: 0, offset: 1.0), .window(wall: 2, offset: 1.0, width: 1.5)]),
                     lShape(openings: [.door(wall: 3, offset: 0.4)]), uShape()]
        for room in rooms {
            let s = scene([room], wallsOnly)
            // The ring: between the clear outline and the outline pushed outwards by the thickness.
            let outer = room.walls.indices.map { i -> Point2 in
                let n = room.walls.count
                let prev = room.walls[(i + n - 1) % n], cur = room.walls[i]
                let n1 = prev.inwardNormal, n2 = cur.inwardNormal
                let det = n1.x * n2.y - n1.y * n2.x
                if abs(det) < 1e-9 { return cur.start - n2 * t }
                let x = (-t * n2.y + t * n1.y) / det, y = (-t * n1.x + t * n2.x) / det
                return cur.start + Point2(x, y)
            }
            let box = Bounds2(points: outer)!
            var rings = 0, inside = 0, outside = 0
            var y = box.min.y - 0.3
            while y <= box.max.y + 0.3 {
                var x = box.min.x - 0.3
                while x <= box.max.x + 0.3 {
                    let p = Point2(x, y)
                    let nearEdge = min(PlanHitTester.distance(from: p, toPolygon: room.outline),
                                       PlanHitTester.distance(from: p, toPolygon: outer)) < 2e-3
                    if !nearEdge {
                        let ray = Ray3(origin: Point3(p.x, 10, -p.y), direction: Point3(0, -1, 0))
                        let hit = ScenePicker.firstHit(origin: ray.origin, direction: Point3(0, -1, 0), in: s,
                                                       maxDistance: .infinity, mode: .opaque, cull: true)
                        if Polygon.contains(room.outline, p) {
                            inside += 1
                            XCTAssertEqual(hit?.point.y ?? .nan, 0, accuracy: 1e-5, "floor missing at \(p) in \(room.name)")
                        } else if Polygon.contains(outer, p) {
                            rings += 1
                            XCTAssertEqual(hit?.point.y ?? .nan, 2.8, accuracy: 1e-5, "gap in the wall top at \(p) in \(room.name)")
                        } else {
                            outside += 1
                            XCTAssertNil(hit, "something outside the walls at \(p) in \(room.name)")
                        }
                    }
                    x += 0.037
                }
                y += 0.037
            }
            XCTAssertGreaterThan(rings, 200)
            XCTAssertGreaterThan(inside, 200)
            XCTAssertGreaterThan(outside, 50)
        }
    }

    func testPropertyBasedRandomRooms() {
        var rng = LCG(state: 20260509)
        for round in 0..<40 {
            // A random orthogonal room: a rectangle, or an L made by notching one corner.
            let w = rng.range(2.5, 12), d = rng.range(2.5, 10)
            let height = rng.range(2.2, 4.0)
            let floorY = rng.range(-3, 3)
            var corners = [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(0, d)]
            if rng.next() < 0.5 {
                let nw = rng.range(0.8, w - 0.8), nd = rng.range(0.8, d - 0.8)
                corners = [Point2(0, 0), Point2(w, 0), Point2(w, d - nd), Point2(w - nw, d - nd),
                           Point2(w - nw, d), Point2(0, d)]
            }
            var specs: [OpeningSpec] = []
            for wallIndex in corners.indices where rng.next() < 0.5 {
                let a = corners[wallIndex], b = corners[(wallIndex + 1) % corners.count]
                let length = a.distance(to: b)
                guard length > 1.6 else { continue }
                let width = rng.range(0.5, min(1.6, length - 0.6))
                let offset = rng.range(0.3, length - width - 0.3)
                let kind: OpeningKind = rng.next() < 0.5 ? .door : .window
                specs.append(kind == .door
                    ? OpeningSpec.door(wall: wallIndex, offset: offset, width: width, height: min(2.1, height - 0.2))
                    : OpeningSpec.window(wall: wallIndex, offset: offset, width: width, height: 1.0, sill: 0.8))
            }
            var room = Room.polygon(name: "R\(round)", corners: corners, ceilingHeight: height, openings: specs)
            room.floorElevation = floorY
            room.objects = [RoomObject(kind: .table, center: Point2(w / 2, d / 3), yaw: rng.range(0, 3), width: 1,
                                       depth: 0.6, height: 0.75)]
            let s = scene([room], SceneOptions(includeCeiling: true))
            assertInvariants(s)
            let wallsScene = scene([room], wallsOnly)
            let expected = expectedWallVolume(room, thickness: t)
            XCTAssertEqual(signedVolume(wallMeshes(wallsScene), floorY: floorY), expected,
                           accuracy: 3e-3 + 2e-4 * expected, "round \(round)")
            let floorSum = triangles(s.meshes.filter { $0.material == .floor }).reduce(0.0) { $0 + area($1) }
            XCTAssertEqual(floorSum, Polygon.area(room.outline), accuracy: 1e-3, "round \(round)")
        }
    }

    // MARK: Rooms close together

    /// Two 4 x 3 rooms side by side with `gap` metres between the clear faces of their facing walls.
    private func neighbours(gap: Double) -> (a: Room, b: Room) {
        (Room.rectangle(name: "A", width: 4, depth: 3),
         Room.rectangle(name: "B", origin: Point2(4 + gap, 0), width: 4, depth: 3))
    }

    private func isStrictlyInside(_ room: Room, _ p: Point2) -> Bool {
        Polygon.contains(room.outline, p) && PlanHitTester.distance(from: p, toPolygon: room.outline) > 1e-3
    }

    func testWallsNeverReachIntoTheNextRoom() {
        for gap in [0.25, 0.15, 0.12, 0.10, 0.08, 0.05, 0.02, 0.011, 0.0] {
            let (a, b) = neighbours(gap: gap)
            let s = scene([a, b], withCeiling)
            assertInvariants(s)
            for (mine, other) in [(a, b), (b, a)] {
                for mesh in s.meshes where mesh.roomID == mine.id {
                    for i in 0..<mesh.buffer.vertexCount {
                        let v = mesh.buffer.vertex(i)
                        XCTAssertFalse(isStrictlyInside(other, Point2(v.x, -v.z)),
                                       "gap \(gap): \(mesh.id) reaches into the next room at \(v)")
                    }
                }
            }
        }
    }

    func testTapeTapsInsideARoomMeetTheScannedFaceWhateverTheGapToTheNextRoom() throws {
        for gap in [0.25, 0.15, 0.12, 0.10, 0.08, 0.05, 0.02, 0.0] {
            let (a, b) = neighbours(gap: gap)
            let s = scene([a, b], wallsOnly)
            for mode in [PickMode.opaque, .seeThrough] {
                let fromA = ScenePicker.pick(ray: Ray3(origin: Point3(2, 1.4, -1.5), direction: Point3(1, 0, 0)),
                                             in: s, snapPoints: [], mode: mode)
                let hitA = try XCTUnwrap(fromA, "gap \(gap)")
                XCTAssertEqual(hitA.point.x, 4, accuracy: 1e-5, "gap \(gap), \(mode)")
                XCTAssertTrue(hitA.isMeasurable, "gap \(gap), \(mode): a tap on the scanned wall must be allowed")
                XCTAssertTrue(hitA.meshID?.hasPrefix("room:\(a.id.uuidString):") == true, "gap \(gap), \(mode)")

                let fromB = ScenePicker.pick(ray: Ray3(origin: Point3(6 + gap, 1.4, -1.5), direction: Point3(-1, 0, 0)),
                                             in: s, snapPoints: [], mode: mode)
                let hitB = try XCTUnwrap(fromB, "gap \(gap)")
                XCTAssertEqual(hitB.point.x, 4 + gap, accuracy: 1e-5, "gap \(gap), \(mode)")
                XCTAssertTrue(hitB.isMeasurable, "gap \(gap), \(mode)")
                XCTAssertTrue(hitB.meshID?.hasPrefix("room:\(b.id.uuidString):") == true, "gap \(gap), \(mode)")
            }
        }
    }

    func testAWallIsOnlyAsThickAsTheGapLeaves() {
        // (gap, thickness the party wall of each room gets)
        let cases: [(Double, Double)] = [(0.30, 0.12), (0.15, 0.12), (0.10, 0.098), (0.05, 0.048), (0.02, 0.018),
                                        (0.011, 0), (0.005, 0), (0, 0), (-0.01, 0), (-0.05, 0), (-0.1, 0), (-0.2, 0)]
        for (gap, built) in cases {
            let (a, b) = neighbours(gap: gap)
            let s = scene([a, b], wallsOnly)
            XCTAssertEqual(s.bounds(forRoom: a.id)!.max.x, 4 + built, accuracy: 1e-5, "A, gap \(gap)")
            XCTAssertEqual(s.bounds(forRoom: b.id)!.min.x, 4 + gap - built, accuracy: 1e-5, "B, gap \(gap)")
            // The other walls keep the full thickness.
            XCTAssertEqual(s.bounds(forRoom: a.id)!.min.x, -t, accuracy: 1e-5)
            XCTAssertEqual(s.bounds(forRoom: b.id)!.max.x, 8 + gap + t, accuracy: 1e-5)
            // A wall squeezed out has only its clear face.
            if built == 0 {
                let east = a.walls[1].id.uuidString
                let ids = s.meshes.filter { $0.id.contains(east) }.map(\.id)
                XCTAssertEqual(ids.count, 1, "gap \(gap)")
                XCTAssertFalse(ids.contains { $0.hasSuffix(":shell") })
            }
            // Each room's walls enclose what the per-wall thicknesses say, corners included. (A wall with no body
            // is a single sheet, which encloses nothing; leave it out of the sum.)
            for (room, party, thicknesses) in [(a, 1, [t, built, t, t]), (b, 3, [t, t, t, built])] {
                let sheet = room.walls[party].id.uuidString
                let solids = wallMeshes(RoomScene(meshes: s.meshes.filter { $0.roomID == room.id }))
                    .filter { built > 0 || !$0.id.contains(sheet) }
                let volume = signedVolume(solids)
                let expected = expectedWallVolume(room, thickness: t, thicknesses: thicknesses)
                XCTAssertEqual(volume, expected, accuracy: 2e-3 + 1e-4 * expected, "\(room.name), gap \(gap)")
                XCTAssertGreaterThan(volume, 0)
            }
        }
    }

    func testRoomsThatOverlapALittleKeepTheirMadeUpWallsOutOfEachOther() throws {
        // Two scans of one thin partition can disagree by a centimetre or two, so the rooms overlap. The clear
        // faces and floors are scan data and stay as scanned; nothing made up may land inside the other room.
        for overlap in [0.01, 0.03, 0.08, 0.12, 0.2] {
            let (a, b) = neighbours(gap: -overlap)
            let s = scene([a, b], withCeiling)
            assertInvariants(s)
            for (mine, other) in [(a, b), (b, a)] {
                for mesh in s.meshes where mesh.roomID == mine.id && !mesh.isMeasurable {
                    for i in 0..<mesh.buffer.vertexCount {
                        let v = mesh.buffer.vertex(i)
                        XCTAssertFalse(isStrictlyInside(other, Point2(v.x, -v.z)),
                                       "overlap \(overlap): \(mesh.id) reaches into the other room at \(v)")
                    }
                }
            }
            // A tap inside either room still lands on that room's own scanned wall.
            for mode in [PickMode.opaque, .seeThrough] {
                let fromA = try XCTUnwrap(ScenePicker.pick(ray: Ray3(origin: Point3(2, 1.4, -1.5), direction: Point3(1, 0, 0)),
                                                           in: s, snapPoints: [], mode: mode))
                XCTAssertEqual(fromA.point.x, 4, accuracy: 1e-5, "overlap \(overlap), \(mode)")
                XCTAssertTrue(fromA.isMeasurable)
                let fromB = try XCTUnwrap(ScenePicker.pick(ray: Ray3(origin: Point3(6, 1.4, -1.5), direction: Point3(-1, 0, 0)),
                                                           in: s, snapPoints: [], mode: mode))
                XCTAssertEqual(fromB.point.x, 4 - overlap, accuracy: 1e-5, "overlap \(overlap), \(mode)")
                XCTAssertTrue(fromB.isMeasurable)
            }
        }
    }

    func testARoomAroundAnotherDoesNotSquashTheInnerWalls() {
        // A closet drawn inside a bigger room (its floor well inside the other's outline) is not a neighbour
        // behind its walls: the closet keeps its full walls.
        let big = Room.rectangle(name: "Big", width: 8, depth: 6)
        let closet = Room.rectangle(name: "Closet", origin: Point2(1, 1), width: 2, depth: 2)
        let s = scene([big, closet], wallsOnly)
        XCTAssertEqual(s.bounds(forRoom: closet.id)!.max.x, 3 + t, accuracy: 1e-5)
        XCTAssertEqual(s.bounds(forRoom: closet.id)!.min.x, 1 - t, accuracy: 1e-5)
    }

    func testThinnedWallsStillCoverTheGapSeenFromAbove() {
        for gap in [0.15, 0.10, 0.05] {
            let (a, b) = neighbours(gap: gap)
            let s = scene([a, b], wallsOnly)
            var x = 4.004
            while x < 4 + gap - 0.004 {
                for y in [0.3, 1.5, 2.7] {
                    let hit = ScenePicker.firstHit(origin: Point3(x, 10, -y), direction: Point3(0, -1, 0), in: s,
                                                   maxDistance: .infinity, mode: .opaque, cull: true)
                    XCTAssertEqual(hit?.point.y ?? .nan, 2.8, accuracy: 1e-5, "gap \(gap): no wall top at x \(x), y \(y)")
                }
                x += 0.007
            }
        }
    }

    func testOnlyWallsThatFaceAnotherRoomAreThinned() {
        // B sits beyond A's corner: nothing is behind A's east wall, so it keeps its full thickness.
        let a = Room.rectangle(name: "A", width: 4, depth: 3)
        let b = Room.rectangle(name: "B", origin: Point2(4.05, 3.5), width: 4, depth: 3)
        let s = scene([a, b], wallsOnly)
        XCTAssertEqual(s.bounds(forRoom: a.id)!.max.x, 4 + t, accuracy: 1e-5)
        XCTAssertEqual(s.bounds(forRoom: b.id)!.min.x, 4.05 - t, accuracy: 1e-5)
        // The same room alone, and with itself in the list, is built the same.
        XCTAssertEqual(RoomSceneBuilder.meshes(for: a, among: [a, b], options: wallsOnly),
                       RoomSceneBuilder.meshes(for: a, options: wallsOnly))
    }

    func testRoomsOnOtherStoreysDoNotThinWalls() {
        let a = Room.rectangle(name: "A", width: 4, depth: 3)
        var above = Room.rectangle(name: "Above", origin: Point2(4.05, 0), width: 4, depth: 3)
        above.floorElevation = 3.0
        let s = scene([a, above], wallsOnly)
        XCTAssertEqual(s.bounds(forRoom: a.id)!.max.x, 4 + t, accuracy: 1e-5)
        XCTAssertEqual(s.bounds(forRoom: above.id)!.min.x, 4.05 - t, accuracy: 1e-5)
        // At the same height the same two rooms would squeeze each other.
        var level = above
        level.floorElevation = 0
        let flat = scene([a, level], wallsOnly)
        XCTAssertEqual(flat.bounds(forRoom: a.id)!.max.x, 4 + 0.048, accuracy: 1e-5)
    }

    func testDemoApartmentWallsStayOutOfTheOtherRooms() {
        // The scanned demo has two bedrooms whose facing walls are only about 10 cm apart at their closest
        // (Bedroom 2's west wall is a little skewed), so the 12 cm default would have reached into the next room.
        let rooms = DemoProperty.make().allRooms
        let together = scene(rooms, wallsOnly)
        assertInvariants(together)
        for mine in rooms {
            for other in rooms where other.id != mine.id {
                for mesh in together.meshes where mesh.roomID == mine.id {
                    for i in 0..<mesh.buffer.vertexCount {
                        let v = mesh.buffer.vertex(i)
                        XCTAssertFalse(isStrictlyInside(other, Point2(v.x, -v.z)),
                                       "\(mine.name) reaches into \(other.name) at \(v) (\(mesh.id))")
                    }
                }
            }
        }
        // Only the two bedrooms are affected: every other room is built exactly as it is on its own.
        let thinned = Set(rooms.filter { $0.name == "Master Bedroom" || $0.name == "Bedroom 2" }.map(\.id))
        XCTAssertEqual(thinned.count, 2)
        for room in rooms {
            let alone = RoomSceneBuilder.meshes(for: room, options: wallsOnly)
            let withOthers = together.meshes.filter { $0.roomID == room.id }
            XCTAssertEqual(withOthers == alone, !thinned.contains(room.id), room.name)
        }
    }

    // MARK: Inside corners and short pieces

    /// The L-shape's inside corner is (4, 2): wall 2 arrives at it, wall 3 leaves it. A door or window that
    /// starts within a wall thickness of it gives a first piece shorter than the corner's shift.
    func testOpeningsWithinAWallThicknessOfAnInsideCornerKeepTheSolidValid() {
        for thickness in [0.05, 0.12, 0.3] {
            let options = SceneOptions(wallThickness: thickness, includeCeiling: true)
            let wallsOnly = SceneOptions(wallThickness: thickness, includeCeiling: false, includeObjects: false,
                                         includeOpeningFrames: false)
            for offset in [0.0, 0.01, 0.05, 0.11, 0.12, 0.2, 0.31] {
                for kind in [OpeningKind.door, .window] {
                    func spec(wall: Int, offset: Double) -> OpeningSpec {
                        kind == .door ? .door(wall: wall, offset: offset)
                                      : .window(wall: wall, offset: offset, width: 0.9, height: 1.2, sill: 0.4)
                    }
                    // Leaving the inside corner, arriving at it, and both at once.
                    let variants: [[OpeningSpec]] = [
                        [spec(wall: 3, offset: offset)],
                        [spec(wall: 2, offset: 2 - 0.9 - offset)],
                        [spec(wall: 3, offset: offset), spec(wall: 2, offset: 2 - 0.9 - offset)],
                    ]
                    for openings in variants {
                        let room = lShape(openings: openings)
                        let label = "thickness \(thickness), offset \(offset), \(kind)"
                        assertInvariants(scene([room], options))
                        let s = scene([room], wallsOnly)
                        let volume = signedVolume(wallMeshes(s))
                        let expected = expectedWallVolume(room, thickness: thickness)
                        XCTAssertEqual(volume, expected, accuracy: 2e-3 + 1e-4 * expected, label)
                        XCTAssertGreaterThan(volume, 0, label)
                    }
                }
            }
        }
    }

    func testEveryTopFacePointsUpEvenOnTheShortestPieces() {
        // The case the review found: a door 5 cm from the inside corner of an L, default thickness.
        let room = lShape(openings: [.door(wall: 3, offset: 0.05)])
        let s = scene([room], wallsOnly)
        var tops = 0
        for mesh in wallMeshes(s) {
            for i in 0..<mesh.buffer.triangleCount {
                guard let tri = mesh.buffer.triangle(i) else { continue }
                let n = cross(tri.1 - tri.0, tri.2 - tri.0)
                guard n.length > 0, abs(n.y) / n.length > 0.999 else { continue }
                tops += 1
                // A top faces up, an underside (lintel, sill) faces down, and the stored normal says the same.
                XCTAssertGreaterThan(n.dot(mesh.buffer.normal(Int(mesh.buffer.indices[3 * i]))), 0, mesh.id)
            }
        }
        XCTAssertGreaterThan(tops, 8)
        // Seen from above: wall top all round the inside corner (4, 2), including over the short first piece
        // (4.02, 2.04), floor inside the room, and nothing in the notch beyond the walls.
        func top(_ x: Double, _ y: Double) -> Double? {
            ScenePicker.firstHit(origin: Point3(x, 10, -y), direction: Point3(0, -1, 0), in: s, maxDistance: .infinity,
                                 mode: .opaque, cull: true)?.point.y
        }
        for (x, y) in [(4.02, 2.04), (4.06, 2.06), (4.06, 2.5), (4.06, 3.5), (5.0, 2.06), (4.1, 2.1)] {
            XCTAssertEqual(top(x, y) ?? .nan, 2.8, accuracy: 1e-5, "wall top at (\(x), \(y))")
        }
        for (x, y) in [(3.9, 2.5), (3.9, 1.9), (3.97, 1.97)] {
            XCTAssertEqual(top(x, y) ?? .nan, 0, accuracy: 1e-5, "floor at (\(x), \(y))")
        }
        XCTAssertNil(top(4.5, 3.0))
    }

    func testOpeningsNearCornersOfRandomRoomsKeepTheSolidValid() {
        var rng = LCG(state: 777_001)
        for round in 0..<60 {
            let w = rng.range(2.5, 10), d = rng.range(2.5, 8)
            var corners = [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(0, d)]
            if rng.next() < 0.7 {
                let nw = rng.range(0.8, w - 0.8), nd = rng.range(0.8, d - 0.8)
                corners = [Point2(0, 0), Point2(w, 0), Point2(w, d - nd), Point2(w - nw, d - nd),
                           Point2(w - nw, d), Point2(0, d)]
            }
            let thickness = [0.05, 0.12, 0.2, 0.3][Int(rng.range(0, 4)) % 4]
            var specs: [OpeningSpec] = []
            for wallIndex in corners.indices where rng.next() < 0.8 {
                let a = corners[wallIndex], b = corners[(wallIndex + 1) % corners.count]
                let length = a.distance(to: b)
                let width = rng.range(0.3, Swift.min(1.2, length - 0.05))
                guard length > width + 0.01 else { continue }
                // Hard against the start, hard against the end, or anywhere.
                let spare = length - width
                let offset: Double
                switch Int(rng.range(0, 3)) % 3 {
                case 0: offset = Swift.min(rng.range(0, 0.4), spare)
                case 1: offset = Swift.max(spare - rng.range(0, 0.4), 0)
                default: offset = rng.range(0, spare)
                }
                specs.append(rng.next() < 0.5 ? .door(wall: wallIndex, offset: offset, width: width)
                                              : .window(wall: wallIndex, offset: offset, width: width))
            }
            let room = Room.polygon(name: "R\(round)", corners: corners, openings: specs)
            let options = SceneOptions(wallThickness: thickness, includeCeiling: true)
            assertInvariants(scene([room], options))
            let walls = scene([room], SceneOptions(wallThickness: thickness, includeCeiling: false, includeObjects: false,
                                                   includeOpeningFrames: false))
            let expected = expectedWallVolume(room, thickness: thickness)
            XCTAssertEqual(signedVolume(wallMeshes(walls)), expected, accuracy: 3e-3 + 2e-4 * expected,
                           "round \(round), thickness \(thickness)")
        }
    }

    func testCornerOffsetMeetsBothOuterFacesAndFallsBackForStraightRuns() {
        // 90 degrees, different thicknesses: the point is 0.12 outside one face and 0.05 outside the other.
        let np = Point2(0, 1), nc = Point2(-1, 0)     // east wall arriving, north wall leaving... any perpendicular pair
        let x = RoomSceneBuilder.cornerOffset(previous: np, current: nc, previousThickness: 0.12, currentThickness: 0.05)
        XCTAssertEqual(np.dot(x), 0.12, accuracy: 1e-12)
        XCTAssertEqual(nc.dot(x), 0.05, accuracy: 1e-12)
        // Equal thicknesses are the plain mitre.
        let m = RoomSceneBuilder.cornerOffset(previous: np, current: nc, previousThickness: 0.1, currentThickness: 0.1)
        XCTAssertEqual(m.x, RoomSceneBuilder.mitre(previous: np, current: nc).x * 0.1, accuracy: 1e-12)
        // A wall with no body: the other wall ends flush with its clear face.
        let flush = RoomSceneBuilder.cornerOffset(previous: np, current: nc, previousThickness: 0, currentThickness: 0.12)
        XCTAssertEqual(np.dot(flush), 0, accuracy: 1e-12)
        XCTAssertEqual(nc.dot(flush), 0.12, accuracy: 1e-12)
        // Walls in line have no corner: use the thinner thickness, the same from both sides.
        let straight = RoomSceneBuilder.cornerOffset(previous: np, current: np, previousThickness: 0.12, currentThickness: 0.05)
        XCTAssertEqual(straight.x, 0, accuracy: 1e-12)
        XCTAssertEqual(straight.y, 0.05, accuracy: 1e-12)
        // A needle-sharp corner is capped at three times the thicker wall.
        let sharp = RoomSceneBuilder.cornerOffset(previous: Point2(0, 1), current: Point2(0.0087, 0.99996),
                                                  previousThickness: 0.12, currentThickness: 0.05)
        XCTAssertLessThanOrEqual(sharp.length, 3 * 0.12 + 1e-12)
    }

    // MARK: Objects, frames, glass

    func testObjectsAreBoxesFromTheirFootprint() {
        var room = rect()
        let sofa = RoomObject(kind: .sofa, center: Point2(3, 2), yaw: 0.6, width: 2.0, depth: 0.9, height: 0.85,
                              elevation: 0.2)
        room.objects = [sofa, RoomObject(kind: .sofa, center: Point2(1, 1), yaw: 0, width: 1, depth: 1, height: 1)]
        room.floorElevation = -1
        let s = scene([room])
        let boxes = s.meshes.filter { $0.material == .object }
        XCTAssertEqual(boxes.map(\.label), ["Sofa 1", "Sofa 2"])
        let box = boxes[0]
        XCTAssertEqual(box.id, "room:\(room.id.uuidString):object:\(sofa.id.uuidString)")
        XCTAssertTrue(box.isMeasurable)
        XCTAssertEqual(box.buffer.triangleCount, 12)
        XCTAssertEqual(box.boundsMin.y, -1 + 0.2, accuracy: 1e-5)
        XCTAssertEqual(box.boundsMax.y, -1 + 0.2 + 0.85, accuracy: 1e-5)
        XCTAssertEqual(signedVolume([box]), 2.0 * 0.9 * 0.85, accuracy: 1e-3)
        // Footprint corners are the object's four corners.
        let footprint = sofa.footprint.map { Point3($0.x, 0, -$0.y) }
        for corner in footprint {
            XCTAssertTrue((0..<box.buffer.vertexCount).contains {
                let v = box.buffer.vertex($0)
                return abs(v.x - corner.x) < 1e-5 && abs(v.z - corner.z) < 1e-5
            })
        }
        XCTAssertFalse(scene([room], SceneOptions(includeObjects: false)).meshes.contains { $0.material == .object })
    }

    func testObjectsWithBadSizesAreSkipped() {
        var room = rect()
        room.objects = [RoomObject(kind: .chair, center: Point2(1, 1), yaw: 0, width: 0, depth: 0.5, height: 1),
                        RoomObject(kind: .chair, center: Point2(.nan, 1), yaw: 0, width: 1, depth: 0.5, height: 1),
                        RoomObject(kind: .chair, center: Point2(2, 1), yaw: 0, width: 0.5, depth: 0.5, height: 0.9)]
        let s = scene([room])
        XCTAssertEqual(s.meshes.filter { $0.material == .object }.count, 1)
    }

    func testDoorsGetFramesAndWindowsAlsoGetGlass() {
        let room = rect(openings: [.door(wall: 0, offset: 1.0), .window(wall: 2, offset: 1.0, width: 1.5)])
        let s = scene([room])
        let frames = s.meshes.filter { $0.material == .doorFrame }
        let glass = s.meshes.filter { $0.material == .windowGlass }
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(glass.count, 1)
        XCTAssertTrue(glass[0].id.hasSuffix(":glass"))
        XCTAssertTrue(frames.allSatisfy { !$0.isMeasurable } && glass.allSatisfy { !$0.isMeasurable })
        XCTAssertEqual(Set(frames.map(\.label)), ["Door 1 frame", "Window 1 frame"])

        // The glass fills the window, inside the wall's thickness.
        let g = glass[0]
        XCTAssertEqual(g.boundsMin.y, 0.9 + 0.05, accuracy: 0.01)
        XCTAssertEqual(g.boundsMax.y, 0.9 + 1.4 - 0.05, accuracy: 0.01)
        // The window is on plan y = 4, i.e. world z -4, and the glass is inside the wall thickness beyond it.
        XCTAssertLessThan(g.boundsMax.z, -4 + 1e-6)
        XCTAssertGreaterThan(g.boundsMin.z, -4 - t)

        let bare = scene([room], SceneOptions(includeOpeningFrames: false))
        XCTAssertFalse(bare.meshes.contains { $0.material == .doorFrame || $0.material == .windowGlass })
    }

    func testFramesStayInsideTheirOpening() {
        let spec = OpeningSpec.window(wall: 0, offset: 1.0, width: 1.5, height: 1.2, sill: 0.9)
        let room = rect(openings: [spec])
        let s = scene([room])
        let frame = s.meshes.first { $0.material == .doorFrame }!
        XCTAssertGreaterThanOrEqual(frame.boundsMin.x, 1.0 - 1e-5)
        XCTAssertLessThanOrEqual(frame.boundsMax.x, 2.5 + 1e-5)
        XCTAssertGreaterThanOrEqual(frame.boundsMin.y, 0.9 - 1e-5)
        XCTAssertLessThanOrEqual(frame.boundsMax.y, 2.1 + 1e-5)
        XCTAssertGreaterThanOrEqual(frame.boundsMin.z, -0.06 - 1e-5)
        XCTAssertLessThanOrEqual(frame.boundsMax.z, 1e-5 + 0.12)
    }

    // MARK: Scene bounds and merging

    func testSceneBoundsAreTheUnionOfEveryVertex() {
        let a = rect(4, 3), b = Room.rectangle(name: "B", origin: Point2(10, 0), width: 3, depth: 3)
        let s = scene([a, b], withCeiling)
        let all = SceneMeshBuffer.merging(s.meshes.map(\.buffer)).bounds!
        XCTAssertEqual(s.boundsMin, all.min)
        XCTAssertEqual(s.boundsMax, all.max)
        let roomB = s.bounds(forRoom: b.id)!
        XCTAssertGreaterThan(roomB.min.x, 9)
        XCTAssertNil(s.bounds(forRoom: UUID()))
    }

    func testMergingBuffersShiftsIndices() {
        let s = scene([rect()], wallsOnly)
        let merged = SceneMeshBuffer.merging(s.meshes.map(\.buffer))
        XCTAssertEqual(merged.triangleCount, s.meshes.reduce(0) { $0 + $1.buffer.triangleCount })
        XCTAssertEqual(merged.vertexCount, s.meshes.reduce(0) { $0 + $1.buffer.vertexCount })
        XCTAssertTrue(merged.indices.allSatisfy { Int($0) < merged.vertexCount })
        XCTAssertTrue(SceneMeshBuffer.merging([]).isEmpty)
        XCTAssertNil(SceneMeshBuffer().bounds)
        XCTAssertNil(SceneMeshBuffer().triangle(0))
        XCTAssertNil(merged.triangle(-1))
        XCTAssertNil(merged.triangle(merged.triangleCount))
    }

    func testWithoutDropsMaterials() {
        let s = scene([rect()], withCeiling)
        let trimmed = s.without([.ceiling])
        XCTAssertFalse(trimmed.meshes.contains { $0.material == .ceiling })
        XCTAssertLessThan(trimmed.boundsMax.y, s.boundsMax.y)
        XCTAssertEqual(s.without([]), s)
    }

    // MARK: Shading and batches

    func testShadingBrightnessRangeAndOrdering() {
        let up = SceneShading.brightness(forNormal: Point3(0, 1, 0))
        let down = SceneShading.brightness(forNormal: Point3(0, -1, 0))
        XCTAssertGreaterThan(up, down)
        for n in [Point3(1, 0, 0), Point3(-1, 0, 0), Point3(0, 0, 1), Point3(0, 0, -1), Point3(0.3, 0.5, -0.8)] {
            let b = SceneShading.brightness(forNormal: n)
            XCTAssertGreaterThanOrEqual(b, SceneShading.darkest)
            XCTAssertLessThanOrEqual(b, 1)
        }
        XCTAssertEqual(SceneShading.brightness(forNormal: .zero), 0.8)
        XCTAssertEqual(SceneShading.brightness(forNormal: Point3(.nan, 0, 0)), 0.8)
        // Two walls at right angles do not share a shade.
        let sides = [Point3(1, 0, 0), Point3(-1, 0, 0), Point3(0, 0, 1), Point3(0, 0, -1)]
            .map { SceneShading.level(forBrightness: SceneShading.brightness(forNormal: $0)) }
        XCTAssertEqual(Set(sides).count, 4, "the four wall directions need four different shades: \(sides)")
    }

    func testShadingLevelsRoundTrip() {
        for level in 0..<SceneShading.levels {
            let b = SceneShading.brightness(forLevel: level)
            XCTAssertEqual(SceneShading.level(forBrightness: b), level)
        }
        XCTAssertEqual(SceneShading.level(forBrightness: -5), 0)
        XCTAssertEqual(SceneShading.level(forBrightness: 9), SceneShading.levels - 1)
        XCTAssertEqual(SceneShading.level(forBrightness: .nan), SceneShading.levels - 1)
        XCTAssertEqual(SceneShading.brightness(forLevel: 0), SceneShading.darkest)
        XCTAssertEqual(SceneShading.brightness(forLevel: SceneShading.levels - 1), 1, accuracy: 1e-12)
    }

    func testBatchesKeepEveryTriangleOnce() {
        let rooms = DemoProperty.make().allRooms
        let s = scene(rooms, withCeiling)
        let batches = s.shadedBatches()
        let totalTriangles = s.meshes.reduce(0) { $0 + $1.buffer.triangleCount }
        XCTAssertEqual(batches.reduce(0) { $0 + $1.buffer.triangleCount }, totalTriangles)
        let totalArea = triangles(s.meshes).reduce(0.0) { $0 + area($1) }
        let batchArea = batches.reduce(0.0) { sum, batch in
            sum + (0..<batch.buffer.triangleCount).reduce(0.0) { acc, i in acc + area(batch.buffer.triangle(i)!) }
        }
        XCTAssertEqual(batchArea, totalArea, accuracy: 1e-3)
        // Bounded count: at most one batch per material and shade.
        XCTAssertLessThanOrEqual(batches.count, SceneMaterialKind.allCases.count * SceneShading.levels)
        // Every triangle in a batch has the batch's shade.
        for batch in batches {
            XCTAssertFalse(batch.buffer.isEmpty)
            XCTAssertEqual(batch.brightness, SceneShading.brightness(forLevel: batch.level), accuracy: 1e-12)
            for i in 0..<batch.buffer.triangleCount {
                let n = batch.buffer.normal(Int(batch.buffer.indices[3 * i]))
                XCTAssertEqual(SceneShading.level(forBrightness: SceneShading.brightness(forNormal: n)), batch.level)
            }
        }
        // Deterministic order: material, then shade.
        let keys = batches.map { SceneMaterialKind.allCases.firstIndex(of: $0.material)! * 1000 + $0.level }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(batches, s.shadedBatches())
        XCTAssertTrue(RoomScene.empty.shadedBatches().isEmpty)
    }

    // MARK: Camera

    func testCameraBasisIsOrthonormalAndRightHanded() {
        for yaw in stride(from: -180.0, through: 180, by: 45) {
            for pitch in [5.0, 30, 50, 89] {
                let c = SceneCamera(target: Point3(1, 2, 3), distance: 7, yawDegrees: yaw, pitchDegrees: pitch)
                XCTAssertEqual(c.forward.length, 1, accuracy: 1e-9)
                XCTAssertEqual(c.right.length, 1, accuracy: 1e-9)
                XCTAssertEqual(c.up.length, 1, accuracy: 1e-9)
                XCTAssertEqual(c.forward.dot(c.right), 0, accuracy: 1e-9)
                XCTAssertEqual(c.forward.dot(c.up), 0, accuracy: 1e-9)
                XCTAssertEqual(c.right.dot(c.up), 0, accuracy: 1e-9)
                XCTAssertGreaterThan(c.up.y, 0)
                // right x up = -forward for a right-handed view looking down -forward.
                let ru = cross(c.right, c.up)
                XCTAssertEqual(ru.dot(c.forward), -1, accuracy: 1e-9)
                // The camera looks at its target from `distance`.
                let back = c.position + c.forward * c.distance
                XCTAssertEqual(back.distance(to: c.target), 0, accuracy: 1e-9)
            }
        }
    }

    func testDefaultCameraLooksFromSouthEastAbove() {
        let c = SceneCamera(target: .zero, distance: 10)
        XCTAssertGreaterThan(c.position.x, 0)
        XCTAssertGreaterThan(c.position.y, 0)
        XCTAssertGreaterThan(c.position.z, 0)   // +Z is south
    }

    func testOrbitingKeepsPitchInRangeAndYawWrapped() {
        var c = SceneCamera(target: .zero, distance: 5)
        c = c.orbited(yawDelta: 400, pitchDelta: 100)
        XCTAssertEqual(c.pitchDegrees, 89)
        XCTAssertGreaterThanOrEqual(c.yawDegrees, -180)
        XCTAssertLessThanOrEqual(c.yawDegrees, 180)
        XCTAssertEqual(c.yawDegrees, SceneCamera.wrapped(SceneCamera.defaultYawDegrees + 400), accuracy: 1e-9)
        c = c.orbited(yawDelta: 0, pitchDelta: -500)
        XCTAssertEqual(c.pitchDegrees, 5)
        XCTAssertEqual(SceneCamera.wrapped(190), -170)
        XCTAssertEqual(SceneCamera.wrapped(-190), 170)
        XCTAssertEqual(SceneCamera.wrapped(.nan), 0)
    }

    func testZoomingStaysInLimitsAndIgnoresNonsense() {
        let c = SceneCamera(target: .zero, distance: 5)
        let limits = 0.3...20.0
        XCTAssertEqual(c.zoomed(by: 2, limits: limits).distance, 2.5, accuracy: 1e-12)
        XCTAssertEqual(c.zoomed(by: 1000, limits: limits).distance, 0.3)
        XCTAssertEqual(c.zoomed(by: 0.0001, limits: limits).distance, 20)
        XCTAssertEqual(c.zoomed(by: .nan, limits: limits), c)
        XCTAssertEqual(c.zoomed(by: -2, limits: limits), c)
        XCTAssertEqual(c.zoomed(by: 0, limits: limits), c)
        XCTAssertEqual(SceneCamera.distanceLimits(forSceneDiagonal: 3).upperBound, 12)
        XCTAssertEqual(SceneCamera.distanceLimits(forSceneDiagonal: 100).upperBound, 400)
        XCTAssertEqual(SceneCamera.distanceLimits(forSceneDiagonal: .nan).lowerBound, 0.3)
    }

    func testPanningMovesAlongTheGroundOnly() {
        let c = SceneCamera(target: Point3(1, 1.4, 2), distance: 6, yawDegrees: 0, pitchDegrees: 40)
        let moved = c.panned(right: 2, forward: 3)
        XCTAssertEqual(moved.target.y, 1.4)
        // Camera at +Z looking towards -Z: right is +X, forward is -Z.
        XCTAssertEqual(moved.target.x, 3, accuracy: 1e-9)
        XCTAssertEqual(moved.target.z, -1, accuracy: 1e-9)
        XCTAssertEqual(c.panned(right: .nan, forward: 1), c)
    }

    func testDraggingMovesTheGroundWithTheFinger() {
        let c = SceneCamera(target: .zero, distance: 6, yawDegrees: 0, pitchDegrees: 90 - 1)   // limit is 89
        let mpp = c.metresPerPoint(viewHeight: 800)
        XCTAssertEqual(mpp, 2 * 6 * tan(20 * Double.pi / 180) / 800, accuracy: 1e-12)
        // Finger right: the scene follows, so the target moves left.
        let right = c.dragged(dx: 100, dy: 0, viewHeight: 800)
        XCTAssertEqual(right.target.x, -100 * mpp, accuracy: 1e-9)
        // Finger down: the ground moves down the screen, so the target moves away from the camera (-Z at yaw 0).
        let down = c.dragged(dx: 0, dy: 100, viewHeight: 800)
        XCTAssertLessThan(down.target.z, 0)
        XCTAssertEqual(c.dragged(dx: .infinity, dy: 0, viewHeight: 800), c)
        XCTAssertGreaterThan(c.metresPerPoint(viewHeight: 0), 0)
    }

    func testFramingFitsTheSceneWithMargin() {
        let lo = Point3(0, 0, -4), hi = Point3(6, 2.8, 0)
        let radius = Point3(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z).length / 2
        for aspect in [0.46, 1.0, 2.1] {
            for known in [true, false] {
                let c = SceneCamera(target: .zero, distance: 1).framing(boundsMin: lo, boundsMax: hi, aspect: aspect,
                                                                       verticalFieldOfViewKnown: known)
                XCTAssertEqual(c.target.x, 3, accuracy: 1e-9)
                XCTAssertEqual(c.target.y, 1.4, accuracy: 1e-9)
                XCTAssertEqual(c.target.z, -2, accuracy: 1e-9)
                let half = tan(SceneCamera.fieldOfViewDegrees * Double.pi / 360)
                let narrowest = min(half, half * aspect)
                // The scene's bounding sphere fits inside the narrowest half-angle, with about 10 % to spare.
                XCTAssertLessThanOrEqual(asin(radius / c.distance), atan(narrowest) / 1.05, "aspect \(aspect)")
            }
        }
        // Not knowing the field of view's axis never frames tighter than knowing it.
        let known = SceneCamera.fittingDistance(radius: 5, aspect: 0.5, verticalFieldOfViewKnown: true)
        let unknown = SceneCamera.fittingDistance(radius: 5, aspect: 0.5, verticalFieldOfViewKnown: false)
        XCTAssertGreaterThanOrEqual(unknown, known)
        XCTAssertGreaterThan(SceneCamera.fittingDistance(radius: .nan, aspect: .nan), 0)
        XCTAssertGreaterThan(SceneCamera.fittingDistance(radius: 0, aspect: 0), 0)
    }

    func testSuggestedCameraAndRoomFraming() {
        let a = rect(4, 3), b = Room.rectangle(name: "B", origin: Point2(10, 0), width: 3, depth: 3)
        let s = scene([a, b], wallsOnly)
        XCTAssertEqual(s.suggestedCamera.target.x, s.center.x, accuracy: 1e-6)
        XCTAssertGreaterThan(s.suggestedCamera.distance, s.diagonal / 2)
        XCTAssertEqual(s.suggestedCamera.yawDegrees, SceneCamera.defaultYawDegrees)
        XCTAssertEqual(s.suggestedCamera.pitchDegrees, SceneCamera.defaultPitchDegrees)
        let onB = s.camera(framingRoom: b.id, aspect: 1)
        XCTAssertGreaterThan(onB.target.x, 9)
        XCTAssertLessThan(onB.distance, s.camera(framingRoom: nil, aspect: 1).distance)
        // An unknown room frames the whole scene.
        XCTAssertEqual(s.camera(framingRoom: UUID(), aspect: 1), s.camera(framingRoom: nil, aspect: 1))
    }

    func testShortestPathTurnsTheShortWayRound() {
        let from = SceneCamera(target: .zero, distance: 5, yawDegrees: 170, pitchDegrees: 40)
        let to = SceneCamera(target: .zero, distance: 5, yawDegrees: -170, pitchDegrees: 40)
        XCTAssertEqual(from.shortestPath(to: to).yawDegrees, 190, accuracy: 1e-9)
        XCTAssertEqual(to.shortestPath(to: from).yawDegrees, -190, accuracy: 1e-9)
    }

    // MARK: Camera motion

    func testCameraAnimatorGlidesWithoutOvershoot() {
        let start = SceneCamera(target: .zero, distance: 20, yawDegrees: 0, pitchDegrees: 60)
        let goal = SceneCamera(target: Point3(4, 1, -3), distance: 8, yawDegrees: 120, pitchDegrees: 35)
        var animator = SceneCameraAnimator(camera: start)
        XCTAssertTrue(animator.isSettled)
        animator.move(to: goal)
        XCTAssertFalse(animator.isSettled)
        var last = animator.camera
        var time = 0.0
        while !animator.isSettled && time < 3 {
            animator.advance(by: 1.0 / 60)
            time += 1.0 / 60
            let c = animator.camera
            // Critically damped: every value moves monotonically towards its goal.
            XCTAssertLessThanOrEqual(c.distance, last.distance + 1e-9)
            XCTAssertGreaterThanOrEqual(c.distance, goal.distance - 1e-9)
            XCTAssertGreaterThanOrEqual(c.yawDegrees, last.yawDegrees - 1e-9)
            XCTAssertLessThanOrEqual(c.yawDegrees, goal.yawDegrees + 1e-6)
            last = c
        }
        XCTAssertTrue(animator.isSettled)
        XCTAssertLessThan(time, 1.5)
        let end = animator.camera
        XCTAssertEqual(end.yawDegrees, 120, accuracy: 0.05)
        XCTAssertEqual(end.pitchDegrees, 35, accuracy: 0.05)
        XCTAssertEqual(end.distance, 8, accuracy: 0.01)
        XCTAssertEqual(end.target.distance(to: goal.target), 0, accuracy: 0.01)
    }

    func testCameraAnimatorTakesTheShortWayAndKeepsVelocityWhenRetargeted() {
        var animator = SceneCameraAnimator(camera: SceneCamera(target: .zero, distance: 5, yawDegrees: 170, pitchDegrees: 40))
        animator.move(to: SceneCamera(target: .zero, distance: 5, yawDegrees: -170, pitchDegrees: 40))
        for _ in 0..<6 { animator.advance(by: 1.0 / 60) }
        XCTAssertGreaterThan(animator.camera.yawDegrees, 170)    // went up through 180, not down through 0
        let before = animator.camera.yawDegrees
        animator.move(to: SceneCamera(target: .zero, distance: 5, yawDegrees: 170, pitchDegrees: 40))
        animator.advance(by: 1.0 / 60)
        // Momentum is kept for a frame: no instant reversal.
        XCTAssertGreaterThan(animator.camera.yawDegrees, before - 1e-9)

        var snapped = animator
        snapped.snap(to: SceneCamera(target: Point3(1, 1, 1), distance: 3))
        XCTAssertTrue(snapped.isSettled)
        XCTAssertEqual(snapped.camera.distance, 3)
    }

    func testCameraAnimatorSurvivesLongAndInvalidFrames() {
        var animator = SceneCameraAnimator(camera: SceneCamera(target: .zero, distance: 5))
        animator.move(to: SceneCamera(target: Point3(2, 0, 0), distance: 9, yawDegrees: 10, pitchDegrees: 200))
        animator.advance(by: 100)    // a stalled frame is clamped
        animator.advance(by: .nan)
        animator.advance(by: -1)
        XCTAssertTrue(animator.camera.distance.isFinite)
        for _ in 0..<200 { animator.advance(by: 0.05) }
        XCTAssertTrue(animator.isSettled)
        XCTAssertLessThanOrEqual(animator.camera.pitchDegrees, 89)   // pitch target was clamped
    }

    func testOrbitInertiaCoastsAndStops() {
        var inertia = OrbitInertia(yawVelocity: 300, pitchVelocity: -40)
        XCTAssertTrue(inertia.isMoving)
        var camera = SceneCamera(target: .zero, distance: 5, yawDegrees: 0, pitchDegrees: 50)
        var travelled = 0.0
        var frames = 0
        while inertia.isMoving && frames < 600 {
            let next = inertia.advance(camera, by: 1.0 / 60)
            travelled += SceneCamera.wrapped(next.yawDegrees - camera.yawDegrees)
            camera = next
            frames += 1
        }
        XCTAssertFalse(inertia.isMoving)
        XCTAssertLessThan(frames, 600)
        // Coasts about as far as a scroll view would: v / ln(1/rate)/1000... within 15 %.
        let expected = 300 / (-log(GestureMath.decelerationRate) * 1000)
        XCTAssertEqual(travelled, expected, accuracy: expected * 0.15)
        XCTAssertLessThan(camera.pitchDegrees, 50)

        var atLimit = OrbitInertia(yawVelocity: 0, pitchVelocity: 400)
        let top = atLimit.advance(SceneCamera(target: .zero, distance: 5, yawDegrees: 0, pitchDegrees: 88.5), by: 0.1)
        XCTAssertEqual(top.pitchDegrees, 89)
        XCTAssertEqual(atLimit.pitchVelocity, 0)
        XCTAssertFalse(OrbitInertia(yawVelocity: .nan, pitchVelocity: .infinity).isMoving)
    }

    // MARK: Picking

    private func pick(_ s: RoomScene, from o: Point3, towards d: Point3, snap: [SnapPoint] = [],
                      angle: Double = 2.5, radius: Double = 0.08, snapEdges: [SnapEdge] = [],
                      mode: PickMode = .opaque, cull: Bool = true) -> PickResult? {
        ScenePicker.pick(ray: Ray3(origin: o, direction: d), in: s, snapPoints: snap, snapAngle: angle,
                         snapRadius: radius, snapEdges: snapEdges, mode: mode, cullBackFaces: cull)
    }

    func testRayHitsTheClearFaceOfAWall() throws {
        let s = scene([rect(6, 4)], wallsOnly)
        let hit = try XCTUnwrap(pick(s, from: Point3(3, 1.2, -2), towards: Point3(1, 0, 0)))
        XCTAssertEqual(hit.point.x, 6, accuracy: 1e-5)
        XCTAssertEqual(hit.point.y, 1.2, accuracy: 1e-5)
        XCTAssertEqual(hit.normal.x, -1, accuracy: 1e-6)   // faces back at the ray
        XCTAssertEqual(hit.distance, 3, accuracy: 1e-5)
        XCTAssertTrue(hit.isMeasurable)
        XCTAssertNil(hit.snapped)
        XCTAssertTrue(hit.meshID?.contains(":wall:") == true)
        XCTAssertEqual(hit.surfacePoint, hit.point)
    }

    func testDirectionNeedNotBeAUnitVector() throws {
        let s = scene([rect(6, 4)], wallsOnly)
        let a = try XCTUnwrap(pick(s, from: Point3(3, 1, -2), towards: Point3(1, 0, 0)))
        let b = try XCTUnwrap(pick(s, from: Point3(3, 1, -2), towards: Point3(250, 0, 0)))
        XCTAssertEqual(a.point, b.point)
        XCTAssertEqual(a.distance, b.distance, accuracy: 1e-9)
    }

    func testInvalidRaysPickNothing() {
        let s = scene([rect()], wallsOnly)
        XCTAssertNil(pick(s, from: Point3(3, 1, -2), towards: .zero))
        XCTAssertNil(pick(s, from: Point3(.nan, 1, -2), towards: Point3(1, 0, 0)))
        XCTAssertNil(pick(s, from: Point3(3, 1, -2), towards: Point3(.infinity, 0, 0)))
        XCTAssertNil(pick(.empty, from: .zero, towards: Point3(1, 0, 0)))
        XCTAssertNil(pick(s, from: Point3(3, 1, -2), towards: Point3(0, 1, 0)))   // straight up, no ceiling
    }

    func testFacesTurnedAwayAreSkippedUnlessAsked() throws {
        let s = scene([rect(6, 4)], wallsOnly)
        // From below the floor, looking up: the floor is seen from behind.
        XCTAssertNil(pick(s, from: Point3(3, -2, -2), towards: Point3(0, 1, 0)))
        let through = try XCTUnwrap(pick(s, from: Point3(3, -2, -2), towards: Point3(0, 1, 0), cull: false))
        XCTAssertEqual(through.point.y, 0, accuracy: 1e-5)
        XCTAssertEqual(through.normal.y, -1, accuracy: 1e-6)   // reported facing the ray
        // From inside the room looking down: the floor.
        let down = try XCTUnwrap(pick(s, from: Point3(3, 2, -2), towards: Point3(0, -1, 0)))
        XCTAssertEqual(down.point.y, 0, accuracy: 1e-5)
        XCTAssertEqual(down.normal.y, 1, accuracy: 1e-6)
    }

    func testFromOutsideTheRayMeetsTheOuterShellWhichCannotBeMeasured() throws {
        let s = scene([rect(6, 4)], wallsOnly)
        let hit = try XCTUnwrap(pick(s, from: Point3(10, 1.2, -2), towards: Point3(-1, 0, 0)))
        XCTAssertEqual(hit.point.x, 6 + t, accuracy: 1e-5)
        XCTAssertFalse(hit.isMeasurable)
        XCTAssertTrue(hit.meshID?.hasSuffix(":shell") == true)
        XCTAssertEqual(hit.placement, .notScanned)
        // See-through mode ignores the made-up shell, and the east wall's clear face is seen from behind, so the
        // ray travels through the room and lands on the west wall's clear face.
        let seeThrough = try XCTUnwrap(pick(s, from: Point3(10, 1.2, -2), towards: Point3(-1, 0, 0), mode: .seeThrough))
        XCTAssertEqual(seeThrough.point.x, 0, accuracy: 1e-5)
        XCTAssertTrue(seeThrough.isMeasurable)
        // The top of a wall is made up too.
        let top = try XCTUnwrap(pick(s, from: Point3(6 + t / 2, 5, -2), towards: Point3(0, -1, 0)))
        XCTAssertEqual(top.point.y, 2.8, accuracy: 1e-5)
        XCTAssertFalse(top.isMeasurable)
    }

    func testRayThroughAnOpeningSeesWhatIsBeyond() throws {
        // Two rooms with a door in the shared wall; the ray goes through the doorway into the next room.
        // B's west wall runs from plan y 4 down to 0, so a door at offset 2 with width 1 is at plan y 1...2.
        let a = Room.rectangle(name: "A", width: 4, depth: 4, openings: [.door(wall: 1, offset: 1.0, width: 1.0, height: 2.1)])
        let b = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 4, depth: 4,
                               openings: [.door(wall: 3, offset: 2.0, width: 1.0, height: 2.1)])
        let s = scene([a, b], wallsOnly)
        // Door at plan y 1...2 (world z -2...-1), 1 m wide. Ray at z = -1.5, height 1.
        let through = try XCTUnwrap(pick(s, from: Point3(1, 1, -1.5), towards: Point3(1, 0, 0)))
        XCTAssertEqual(through.point.x, 4.15 + 4, accuracy: 1e-4, "passes the doorway and lands on room B's far wall")
        XCTAssertTrue(through.isMeasurable)
        // The same ray beside the door stops at the shared wall.
        let beside = try XCTUnwrap(pick(s, from: Point3(1, 1, -3.5), towards: Point3(1, 0, 0)))
        XCTAssertEqual(beside.point.x, 4, accuracy: 1e-5)
    }

    func testGlassBlocksOpaqueRaysButNotSeeThroughOnes() throws {
        let room = rect(6, 4, openings: [.window(wall: 1, offset: 1.0, width: 1.5, height: 1.4, sill: 0.9)])
        let s = scene([room])
        // East wall x = 6; window at plan y 1...2.5 (z -2.5...-1), height 0.9...2.3.
        let ray = Ray3(origin: Point3(3, 1.6, -1.75), direction: Point3(1, 0, 0))
        let opaque = try XCTUnwrap(ScenePicker.pick(ray: ray, in: s, snapPoints: []))
        XCTAssertEqual(opaque.point.x, 6 + t / 2 - 0.0, accuracy: t)   // somewhere in the wall thickness: the glass
        XCTAssertFalse(opaque.isMeasurable)
        XCTAssertNil(ScenePicker.pick(ray: ray, in: s, snapPoints: [], mode: .seeThrough))
    }

    func testTinyAndHugeRooms() throws {
        let tiny = rect(0.3, 0.25, height: 0.4)
        let ts = scene([tiny], wallsOnly)
        let th = try XCTUnwrap(pick(ts, from: Point3(0.15, 0.2, -0.125), towards: Point3(1, 0, 0)))
        XCTAssertEqual(th.point.x, 0.3, accuracy: 1e-5)

        let huge = rect(200, 100, height: 12)
        let hs = scene([huge], wallsOnly)
        let hh = try XCTUnwrap(pick(hs, from: Point3(100, 6, -50), towards: Point3(0.0, 0, -1)))
        XCTAssertEqual(hh.point.z, -100, accuracy: 1e-3)
        let far = try XCTUnwrap(pick(hs, from: Point3(100, 80, -50), towards: Point3(0.3, -1, 0.1)))
        XCTAssertEqual(far.point.y, 0, accuracy: 1e-3)
    }

    func testCoincidentSurfacesResolveDeterministically() throws {
        // Two identical rooms on top of each other: every hit is a tie. The answer must not depend on order.
        let room = rect(4, 4)
        var twin = room
        twin.id = UUID()
        twin.walls = room.walls.map { w in
            var copy = w
            copy.id = UUID()
            return copy
        }
        let ab = scene([room, twin], wallsOnly)
        let ba = scene([twin, room], wallsOnly)
        let ray = Ray3(origin: Point3(2, 1, -2), direction: Point3(1, 0, 0))
        let r1 = try XCTUnwrap(ScenePicker.pick(ray: ray, in: ab, snapPoints: []))
        let r2 = try XCTUnwrap(ScenePicker.pick(ray: ray, in: ba, snapPoints: []))
        XCTAssertEqual(r1.meshID, r2.meshID)
        XCTAssertEqual(r1.point, r2.point)
    }

    // MARK: Snapping

    func testSnapsToACornerNearTheRayAndReturnsItsExactPosition() throws {
        let room = rect(6, 4)
        let s = scene([room], wallsOnly)
        let snaps = room.snapPoints()
        let corner = try XCTUnwrap(snaps.first { $0.id == "fc:\(room.walls[1].id.uuidString)" })   // (6, 0, 0)
        XCTAssertEqual(corner.position, Point3(6, 0, 0))
        // Aim at the wall 3 cm off the corner, from 4 m away: well inside 2.5 degrees.
        let eye = Point3(2, 1.5, -2)
        let aim = Point3(5.97, 0.03, -0.04)
        let hit = try XCTUnwrap(pick(s, from: eye, towards: aim - eye, snap: snaps))
        XCTAssertEqual(hit.snapped?.id, corner.id)
        XCTAssertEqual(hit.point, corner.position)
        XCTAssertNotNil(hit.surfacePoint)
        XCTAssertNotEqual(hit.surfacePoint, hit.point)
        XCTAssertTrue(hit.isSnapped)
        XCTAssertEqual(hit.snapLabel, "Floor corner B")
        XCTAssertEqual(hit.placement, .place(corner.position, snapLabel: "Floor corner B"))
    }

    func testStillReturnsTheRawHitWhenNothingSnaps() throws {
        let room = rect(6, 4)
        let s = scene([room], wallsOnly)
        let snaps = room.snapPoints()
        let hit = try XCTUnwrap(pick(s, from: Point3(3, 1.4, -2), towards: Point3(1, 0, 0), snap: snaps))
        XCTAssertNil(hit.snapped)
        XCTAssertNil(hit.snappedEdge)
        XCTAssertEqual(hit.point.x, 6, accuracy: 1e-5)
        XCTAssertEqual(hit.placement, .place(hit.point, snapLabel: nil))
    }

    func testSnapAngleAndRadiusDecideWhatIsCloseEnough() throws {
        let room = rect(6, 4)
        let s = scene([room], wallsOnly)
        let snaps = room.snapPoints()
        let corner = Point3(6, 0, 0)
        let eye = Point3(1, 1.5, -2)
        func aimed(offBy m: Double) -> Point3 { Point3(6, 0, 0) + Point3(0, m, 0) - eye }
        // 5 m away: 2.5 degrees is 0.22 m; 0.15 m off snaps, 0.3 m off does not.
        XCTAssertEqual(pick(s, from: eye, towards: aimed(offBy: 0.15), snap: snaps)?.point, corner)
        XCTAssertNil(pick(s, from: eye, towards: aimed(offBy: 0.3), snap: snaps)?.snapped)
        // A wider angle catches the second.
        XCTAssertEqual(pick(s, from: eye, towards: aimed(offBy: 0.3), snap: snaps, angle: 8)?.point, corner)
        // A zero angle leaves only the radius.
        XCTAssertNil(pick(s, from: eye, towards: aimed(offBy: 0.15), snap: snaps, angle: 0, radius: 0.08)?.snapped)
        XCTAssertEqual(pick(s, from: eye, towards: aimed(offBy: 0.05), snap: snaps, angle: 0, radius: 0.08)?.point, corner)
    }

    func testTheCornerNearestTheRayWinsAndTiesGoToTheSmallerId() throws {
        let s = scene([rect(6, 4)], wallsOnly)
        let a = SnapPoint(id: "b", kind: .floorCorner, position: Point3(6, 1.0, -1.9), label: "B")
        let b = SnapPoint(id: "a", kind: .floorCorner, position: Point3(6, 1.0, -2.1), label: "A")
        let eye = Point3(1, 1, -2)
        // Dead centre between the two: a tie, the smaller id wins, whatever order they come in.
        XCTAssertEqual(pick(s, from: eye, towards: Point3(1, 0, 0), snap: [a, b])?.snapped?.id, "a")
        XCTAssertEqual(pick(s, from: eye, towards: Point3(1, 0, 0), snap: [b, a])?.snapped?.id, "a")
        // Nearer to one of them: that one.
        let aim = Point3(6, 1.0, -1.95) - eye
        XCTAssertEqual(pick(s, from: eye, towards: aim, snap: [a, b])?.snapped?.id, "b")
    }

    func testHiddenCornersDoNotSnap() throws {
        let room = rect(6, 4)
        let s = scene([room], wallsOnly)
        // Seen from outside the south-east corner, the north-west corner is behind the walls.
        let behind = SnapPoint(id: "x", kind: .floorCorner, position: Point3(0, 1, -4), label: "Hidden")
        let eye = Point3(9, 1, 3)
        let hit = try XCTUnwrap(pick(s, from: eye, towards: behind.position - eye, snap: [behind]))
        XCTAssertNil(hit.snapped)
        XCTAssertFalse(hit.isMeasurable)   // it hit the outside of a wall instead
        // With no wall in between it would snap.
        XCTAssertEqual(pick(.empty, from: eye, towards: behind.position - eye, snap: [behind])?.snapped?.id, "x")
        // A point behind the ray never snaps.
        XCTAssertNil(pick(.empty, from: eye, towards: eye - behind.position, snap: [behind]))
    }

    func testEdgesSnapWhenNoCornerIsNear() throws {
        let room = rect(6, 4)
        let s = scene([room], wallsOnly)
        let edges = ScenePicker.cornerEdges(for: [room])
        XCTAssertEqual(edges.count, 4 + 4 + 4)    // corner edges, bases, tops
        XCTAssertEqual(Set(edges.map(\.id)).count, edges.count)
        let corner = try XCTUnwrap(edges.first { $0.id == "ec:\(room.walls[1].id.uuidString)" })
        XCTAssertEqual(corner.a, Point3(6, 0, 0))
        XCTAssertEqual(corner.b, Point3(6, 2.8, 0))
        // Aim 2 cm from the vertical edge at mid height, from 4 m away.
        let eye = Point3(2, 1.4, -2)
        let aim = Point3(5.98, 1.4, -0.02) - eye
        let hit = try XCTUnwrap(pick(s, from: eye, towards: aim, snap: [], snapEdges: edges))
        XCTAssertNotNil(hit.snappedEdge)
        XCTAssertNil(hit.snapped)
        XCTAssertEqual(hit.point.x, 6, accuracy: 1e-6)
        XCTAssertEqual(hit.point.z, 0, accuracy: 1e-6)
        XCTAssertEqual(hit.point.y, 1.4, accuracy: 0.05)
        XCTAssertEqual(hit.snapLabel?.hasSuffix("edge"), true)
        // A corner near the same ray wins over the edge.
        let snaps = room.snapPoints()
        let both = try XCTUnwrap(pick(s, from: eye, towards: Point3(5.98, 0.02, -0.02) - eye, snap: snaps, snapEdges: edges))
        XCTAssertNotNil(both.snapped)
        XCTAssertNil(both.snappedEdge)
    }

    func testOpeningCornersSnapThroughTheDoorFrame() throws {
        let room = rect(6, 4, openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1)])
        let s = scene([room])
        let snaps = room.snapPoints()
        let topNear = try XCTUnwrap(snaps.first { $0.label.contains("top near") })
        XCTAssertEqual(topNear.position.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(topNear.position.y, 2.1, accuracy: 1e-9)
        let eye = Point3(1.5, 1.5, -3)
        let hit = try XCTUnwrap(pick(s, from: eye, towards: topNear.position + Point3(0.02, -0.02, 0) - eye, snap: snaps))
        XCTAssertEqual(hit.snapped?.id, topNear.id)
    }

    // MARK: Visibility

    func testVisibilityIsBlockedByWallsButNotByTheirOwnSurface() {
        let s = scene([rect(6, 4)], wallsOnly)
        let label = Point3(3, 1.4, -2)
        XCTAssertTrue(ScenePicker.isVisible(label, from: Point3(1, 2, -1), in: s))
        XCTAssertFalse(ScenePicker.isVisible(label, from: Point3(12, 1.4, -2), in: s))   // outside, a wall between
        XCTAssertTrue(ScenePicker.isVisible(label, from: Point3(12, 1.4, -2), in: s, mode: .seeThrough))
        // A point sitting on the wall's clear face is visible from inside.
        XCTAssertTrue(ScenePicker.isVisible(Point3(6, 1.4, -2), from: Point3(1, 2, -1), in: s))
        // Looking down on a label inside from above, with no ceiling.
        XCTAssertTrue(ScenePicker.isVisible(label, from: Point3(3, 10, -2), in: s))
        // A ceiling hides it.
        let closed = scene([rect(6, 4)], SceneOptions(includeCeiling: true))
        XCTAssertFalse(ScenePicker.isVisible(label, from: Point3(3, 10, -2), in: closed))
        XCTAssertTrue(ScenePicker.isVisible(label, from: label, in: closed))
    }

    // MARK: Which room does a measurement belong to

    func testMeasurementGoesToTheRoomThatContainsIt() {
        let a = Room.rectangle(name: "A", width: 4, depth: 4)
        let b = Room.rectangle(name: "B", origin: Point2(4.15, 0), width: 4, depth: 4)
        let rooms = [a, b]
        func locate(_ p: Point3, _ q: Point3, focus: UUID? = nil) -> UUID? {
            MeasurementRoomLocator.roomID(forPointA: p, pointB: q, in: rooms, focusRoomID: focus)
        }
        XCTAssertEqual(locate(Point3(1, 0, -1), Point3(3, 2, -3)), a.id)
        XCTAssertEqual(locate(Point3(5, 0, -1), Point3(7, 2, -3)), b.id)
        // Across the wall: the midpoint is in the 0.15 m gap, within tolerance of room A's wall line.
        XCTAssertNotNil(locate(Point3(3, 0, -2), Point3(5, 0, -2)))
        // Both points beyond the building: the nearest room.
        XCTAssertEqual(locate(Point3(20, 0, -2), Point3(21, 0, -2)), b.id)
        XCTAssertEqual(locate(Point3(-20, 0, -2), Point3(-21, 0, -2)), a.id)
        // Points on the outline count as inside.
        XCTAssertEqual(locate(Point3(0, 0, 0), Point3(4, 0, 0)), a.id)
        // A point that is not a number does not crash.
        XCTAssertNotNil(locate(Point3(.nan, 0, 0), Point3(1, 0, -1)))
        XCTAssertNil(MeasurementRoomLocator.roomID(forPointA: .zero, pointB: .zero, in: [], focusRoomID: nil))
    }

    func testOverlappingRoomsPreferTheFocusThenTheSmaller() {
        let big = Room.rectangle(name: "Big", width: 10, depth: 10)
        let small = Room.rectangle(name: "Small", origin: Point2(2, 2), width: 3, depth: 3)
        let p = Point3(3, 0, -3), q = Point3(4, 0, -4)
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: p, pointB: q, in: [big, small], focusRoomID: nil), small.id)
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: p, pointB: q, in: [small, big], focusRoomID: nil), small.id)
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: p, pointB: q, in: [big, small], focusRoomID: big.id), big.id)
        // A focus room that does not contain the points is not forced on them.
        let far = Point3(9, 0, -9)
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: far, pointB: far, in: [big, small], focusRoomID: small.id), big.id)
    }

    func testRoomsThatCannotBeUsedFallBackToTheFocusOrTheFirst() {
        let broken = Room(name: "Broken", walls: [], ceilingHeight: Measured(scanned: 2.5))
        let other = Room(name: "Other", walls: [], ceilingHeight: Measured(scanned: 2.5))
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: .zero, pointB: .zero, in: [broken, other], focusRoomID: other.id), other.id)
        XCTAssertEqual(MeasurementRoomLocator.roomID(forPointA: .zero, pointB: .zero, in: [broken, other], focusRoomID: nil), broken.id)
    }

    // MARK: Tape placement and naming

    func testPlacementFollowsWhatWasPicked() {
        let p = Point3(1, 2, 3)
        let solid = PickResult(point: p, surfacePoint: p, normal: Point3(0, 1, 0), meshID: "m", distance: 1,
                               snapped: nil, snappedEdge: nil, isMeasurable: true)
        XCTAssertEqual(solid.placement, .place(p, snapLabel: nil))
        var madeUp = solid
        madeUp.isMeasurable = false
        XCTAssertEqual(madeUp.placement, .notScanned)
        let corner = SnapPoint(id: "fc", kind: .floorCorner, position: Point3(0, 0, 0), label: "Floor corner A")
        madeUp.snapped = corner
        XCTAssertEqual(madeUp.placement, .place(madeUp.point, snapLabel: "Floor corner A"))
        let none: PickResult? = nil
        XCTAssertEqual(none.placement, .missed)
        XCTAssertEqual(Optional(solid).placement, .place(p, snapLabel: nil))
    }

    func testDefaultMeasurementNames() {
        XCTAssertEqual(MeasurementNaming.defaultLabel(existing: []), "Measurement 1")
        XCTAssertEqual(MeasurementNaming.defaultLabel(existing: ["Measurement 1", "Wardrobe wall"]), "Measurement 3")
        XCTAssertEqual(MeasurementNaming.defaultLabel(existing: ["Measurement 2"]), "Measurement 3" )
        XCTAssertEqual(MeasurementNaming.defaultLabel(existing: ["measurement 2", "Counter"]), "Measurement 3")
        XCTAssertEqual(MeasurementNaming.defaultLabel(existing: ["Measurement 3", "Measurement 1"]), "Measurement 4")
        XCTAssertEqual(MeasurementNaming.label(typed: "  Wardrobe wall \n", existing: []), "Wardrobe wall")
        XCTAssertEqual(MeasurementNaming.label(typed: "   ", existing: ["Measurement 1"]), "Measurement 2")
        XCTAssertEqual(MeasurementNaming.label(typed: String(repeating: "x", count: 100), existing: []).count, 60)
    }
}
