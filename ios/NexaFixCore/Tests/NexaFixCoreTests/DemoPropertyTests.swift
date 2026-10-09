import XCTest
@testable import NexaFixCore

/// Sanity tests for `DemoProperty`: a plausible, non-overlapping, deterministic two-bedroom apartment
/// whose rooms match the costing example and whose numbers come out of the real
/// `CaptureFixtures` -> `RoomBuilder` path.
final class DemoPropertyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private lazy var property: Property = DemoProperty.make(now: now)

    /// Room sizes from `skills/nexa-costing/examples/2br-marina-full-fitout.yaml` (plus the balcony).
    private let expected: [(name: String, length: Double, width: Double, kind: RoomKind)] = [
        ("Living Room", 6.2, 4.5, .livingRoom),
        ("Kitchen", 3.2, 2.8, .kitchen),
        ("Master Bedroom", 4.6, 4.0, .masterBedroom),
        ("Bedroom 2", 3.8, 3.4, .bedroom),
        ("Corridor", 5.0, 1.4, .corridor),
        ("Master Bathroom", 2.6, 2.2, .bathroom),
        ("Bathroom 2", 2.2, 1.8, .bathroom),
        ("Balcony", 4.5, 1.5, .balcony),
    ]

    private var rooms: [Room] { property.allRooms }
    private func room(_ name: String) -> Room { rooms.first { $0.name == name }! }

    // MARK: Geometry helpers (independent of the production code)

    private func crosses(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Bool {
        func orient(_ p: Point2, _ q: Point2, _ r: Point2) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = orient(a, b, c), d2 = orient(a, b, d), d3 = orient(c, d, a), d4 = orient(c, d, b)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    private func overlap(_ p: [Point2], _ q: [Point2]) -> Bool {
        for i in p.indices { for j in q.indices where crosses(p[i], p[(i + 1) % p.count], q[j], q[(j + 1) % q.count]) { return true } }
        if p.contains(where: { Polygon.contains(q, $0) }) { return true }
        if q.contains(where: { Polygon.contains(p, $0) }) { return true }
        return false
    }

    private func distance(from pt: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let d = b - a
        let t = max(0, min(1, (pt - a).dot(d) / d.dot(d)))
        return pt.distance(to: a + d * t)
    }

    /// Smallest distance between the boundaries of two disjoint polygons.
    private func gap(_ p: [Point2], _ q: [Point2]) -> Double {
        var best = Double.infinity
        for v in p { for j in q.indices { best = min(best, distance(from: v, toSegment: q[j], q[(j + 1) % q.count])) } }
        for v in q { for i in p.indices { best = min(best, distance(from: v, toSegment: p[i], p[(i + 1) % p.count])) } }
        return best
    }

    private func planMidpoint(of o: Opening, in room: Room) -> Point2? {
        guard let id = o.wallID, let wall = room.wall(withID: id) else { return nil }
        let seg = o.planSegment(on: wall)
        return (seg.0 + seg.1) * 0.5
    }

    // MARK: Identity

    func testPropertyIdentity() {
        XCTAssertEqual(property.name, "Marina Gate 2 - Unit 2304")
        XCTAssertEqual(property.client, "Mr. Ahmed Khan")
        XCTAssertEqual(property.reference, "NF-2026-1009-01")
        XCTAssertEqual(property.kind, .apartment)
        XCTAssertEqual(property.createdAt, now)
        XCTAssertEqual(property.updatedAt, now)
        XCTAssertFalse(property.address.isEmpty)
        XCTAssertEqual(property.floors.count, 1)
        XCTAssertEqual(property.floors[0].name, "Level 23")
        XCTAssertEqual(property.floors[0].level, 23)
        XCTAssertEqual(property.roomCount, 8)
        XCTAssertEqual(rooms.map(\.name), expected.map(\.name))
        XCTAssertEqual(rooms.map(\.kind), expected.map(\.kind))
        XCTAssertTrue(room("Balcony").kind.isOutdoor)
        XCTAssertTrue(room("Master Bathroom").kind.isWet && room("Bathroom 2").kind.isWet)
        XCTAssertTrue(property.notes.lowercased().contains("demo"), "marked as demo data")
    }

    // MARK: Determinism

    func testDemoIsDeterministic() {
        XCTAssertEqual(DemoProperty.make(now: now), DemoProperty.make(now: now), "same input, same property, bit for bit")
        // A different clock moves only dates.
        let later = now.addingTimeInterval(86_400)
        let other = DemoProperty.make(now: later)
        XCTAssertEqual(other.createdAt, later)
        XCTAssertNotEqual(other, property)
        XCTAssertEqual(other.id, property.id)
        for (a, b) in zip(property.allRooms, other.allRooms) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.walls.map(\.id), b.walls.map(\.id))
            XCTAssertEqual(a.walls.map(\.start), b.walls.map(\.start))
            XCTAssertEqual(a.walls.map(\.end), b.walls.map(\.end))
            XCTAssertEqual(a.walls.map { $0.length.scanned }, b.walls.map { $0.length.scanned })
            XCTAssertEqual(a.openings.map(\.id), b.openings.map(\.id))
            XCTAssertEqual(a.objects, b.objects)
            XCTAssertEqual(a.scannedAt.timeIntervalSince(now), b.scannedAt.timeIntervalSince(later), accuracy: 1e-6)
        }
    }

    func testIdentifiersAreFixedAndUnique() {
        // Fixed UUIDs derived from fixed strings: these literals must never change.
        XCTAssertEqual(property.id.uuidString, "D9F3DADE-9A00-5DE4-9E88-763C7C5856D7")
        XCTAssertEqual(room("Living Room").id.uuidString, "8C99D2CC-BA4C-5481-8AEC-765B6518D0D0")
        XCTAssertEqual(property.floors[0].id, RoomBuilder.stableUUID("NexaFix.Demo.MarinaGate2.Unit2304.floor.level23"))

        var seen = Set<UUID>()
        func take(_ id: UUID, _ what: String) { XCTAssertTrue(seen.insert(id).inserted, "duplicate id: \(what)") }
        take(property.id, "property"); take(property.floors[0].id, "floor")
        for r in rooms {
            take(r.id, r.name)
            for w in r.walls { take(w.id, "\(r.name) wall") }
            for o in r.openings { take(o.id, "\(r.name) opening") }
            for o in r.objects { take(o.id, "\(r.name) object") }
            for m in r.customMeasurements { take(m.id, "\(r.name) measurement") }
        }
        // No ambient randomness: ids are the same in a fresh call.
        XCTAssertEqual(DemoProperty.make(now: now).allRooms.map(\.id), rooms.map(\.id))
    }

    // MARK: Sizes

    func testRoomSizesMatchTheCostingExample() {
        for e in expected {
            let r = room(e.name)
            let m = r.metrics
            XCTAssertEqual(m.floorArea, e.length * e.width, accuracy: e.length * e.width * 0.01, "\(e.name) area")
            XCTAssertTrue(m.isRectangular, "\(e.name)")
            XCTAssertEqual(m.length ?? 0, e.length, accuracy: 0.03, "\(e.name) length")
            XCTAssertEqual(m.width ?? 0, e.width, accuracy: 0.03, "\(e.name) width")
            XCTAssertEqual(r.walls.count, 4, e.name)
            XCTAssertTrue(r.walls.allSatisfy { $0.kind == .solid }, "\(e.name): every wall was scanned")
            XCTAssertEqual(r.ceilingHeight.scanned, 2.8, accuracy: 0.02, "\(e.name) ceiling")
            XCTAssertEqual(r.floorElevation, DemoProperty.floorY, accuracy: 1e-12, "\(e.name): one shared floor level")
            XCTAssertNil(r.capturedRoomFile)
        }
    }

    /// If the costing yaml is reachable (it is in the full repo, not in a sandboxed copy of the package),
    /// the demo must agree with it.
    func testRoomsAgreeWithTheCostingYamlWhenAvailable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("skills/nexa-costing/examples/2br-marina-full-fitout.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("costing yaml not found at \(url.path)")
        }
        func value(_ key: String, in line: String) -> String? {
            guard let r = line.range(of: key + ":") else { return nil }
            let rest = line[r.upperBound...]
            let end = rest.firstIndex(where: { $0 == "," || $0 == "}" }) ?? rest.endIndex
            return rest[..<end].trimmingCharacters(in: .whitespaces)
        }
        var yamlRooms: [(String, Double, Double, String)] = []
        var ceiling: Double?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("ceiling_height:") { ceiling = value("ceiling_height", in: line) .flatMap(Double.init) }
            guard line.hasPrefix("- {name:"), let n = value("name", in: line),
                  let l = value("length", in: line).flatMap(Double.init),
                  let w = value("width", in: line).flatMap(Double.init) else { continue }
            yamlRooms.append((n, l, w, line))
        }
        XCTAssertEqual(yamlRooms.count, 7, "the example lists seven rooms")
        XCTAssertEqual(ceiling, 2.8)
        for (n, l, w, line) in yamlRooms {
            let r = room(n)
            XCTAssertEqual(r.metrics.floorArea, l * w, accuracy: l * w * 0.01, n)
            // Windows listed as [[w, h]] exist with those sizes.
            if let start = line.range(of: "windows: [[") {
                let body = line[start.upperBound...].prefix { $0 != "]" }
                let nums = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                XCTAssertEqual(nums.count, 2, n)
                if nums.count == 2 {
                    let win = r.openings.first { $0.kind == .window && abs($0.width.scanned - nums[0]) < 0.02 && abs($0.height.scanned - nums[1]) < 0.02 }
                    XCTAssertNotNil(win, "\(n): window \(nums) from the yaml")
                }
            }
        }
        XCTAssertEqual(Set(yamlRooms.map { $0.0 }).union(["Balcony"]), Set(expected.map(\.name)))
    }

    // MARK: Layout

    func testRoomsDoNotOverlapAndAreSeparatedByWallThickness() {
        for i in rooms.indices {
            for j in (i + 1)..<rooms.count {
                let a = rooms[i], b = rooms[j]
                XCTAssertFalse(overlap(a.outline, b.outline), "\(a.name) overlaps \(b.name)")
                let g = gap(a.outline, b.outline)
                XCTAssertGreaterThanOrEqual(g, 0.09, "\(a.name) / \(b.name) are \(g) m apart: too close for a wall")
            }
        }
        // Rooms that share a wall are 0.12-0.2 m apart (wall thickness).
        let neighbours: [(String, String)] = [("Living Room", "Kitchen"), ("Living Room", "Corridor"), ("Living Room", "Bathroom 2"),
                                               ("Living Room", "Balcony"), ("Corridor", "Master Bedroom"), ("Corridor", "Bedroom 2"),
                                               ("Master Bedroom", "Master Bathroom"), ("Master Bedroom", "Bedroom 2")]
        for (a, b) in neighbours {
            let g = gap(room(a).outline, room(b).outline)
            XCTAssertTrue(g >= 0.09 && g <= 0.21, "\(a) / \(b) wall thickness \(g)")
        }
        // Total scanned area is the sum of the parts (nothing counted twice).
        let total = rooms.reduce(0.0) { $0 + $1.metrics.floorArea }
        XCTAssertEqual(total, 27.9 + 8.96 + 18.4 + 12.92 + 7.0 + 5.72 + 3.96 + 6.75, accuracy: 0.6)
        // One shared frame: the bounding box is a sensible apartment, not a pile at the origin.
        let all = rooms.flatMap(\.outline)
        let b = Bounds2(points: all)!
        XCTAssertGreaterThan(b.width, 9); XCTAssertLessThan(b.width, 11)
        XCTAssertGreaterThan(b.height, 13); XCTAssertLessThan(b.height, 15)
        XCTAssertEqual(Set(rooms.map { ($0.outline.first!.x * 1000).rounded() }).count > 4, true, "rooms are placed, not stacked")
    }

    // MARK: Openings

    func testEveryOpeningSitsInsideItsWall() {
        for r in rooms {
            XCTAssertFalse(r.openings.isEmpty, "\(r.name) has at least a door")
            for o in r.openings {
                guard let id = o.wallID, let wall = r.wall(withID: id) else { XCTFail("\(r.name): opening without a wall"); continue }
                XCTAssertEqual(wall.kind, .solid)
                XCTAssertGreaterThanOrEqual(o.offsetFromWallStart, 0, "\(r.name) \(o.kind)")
                XCTAssertLessThanOrEqual(o.offsetFromWallStart + o.width.scanned, wall.length.scanned + 1e-9, "\(r.name) \(o.kind) overruns its wall")
                XCTAssertGreaterThan(o.width.scanned, 0.5)
                XCTAssertGreaterThan(o.height.scanned, 0.5)
                XCTAssertGreaterThanOrEqual(o.sillHeight.scanned, 0)
                XCTAssertLessThanOrEqual(o.headHeight, r.ceilingHeight.scanned + 0.02, "\(r.name) \(o.kind) taller than the ceiling")
                if o.kind == .door {
                    XCTAssertEqual(o.sillHeight.scanned, 0, accuracy: 1e-9)
                    XCTAssertTrue((0.75...2.5).contains(o.width.scanned), "door width \(o.width.scanned)")
                    XCTAssertTrue((2.0...2.3).contains(o.height.scanned))
                } else {
                    XCTAssertGreaterThan(o.sillHeight.scanned, 0, "windows have a sill")
                }
            }
            // Openings on one wall do not overlap each other.
            for w in r.walls {
                let on = r.openings(on: w)
                for (a, b) in zip(on, on.dropFirst()) {
                    XCTAssertLessThanOrEqual(a.offsetFromWallStart + a.width.scanned, b.offsetFromWallStart + 1e-9, "\(r.name): overlapping openings")
                }
            }
        }
    }

    func testWindowSillsAndSizes() {
        func window(_ room: String) -> Opening { self.room(room).openings.first { $0.kind == .window }! }
        // (room, width, height, sill) as designed; sills come from the centre height, so they are exact.
        let table: [(String, Double, Double, Double)] = [("Living Room", 3.0, 2.4, 0.3), ("Master Bedroom", 2.0, 2.2, 0.5),
                                                         ("Bedroom 2", 1.6, 2.2, 0.5), ("Kitchen", 1.2, 1.2, 1.05),
                                                         ("Master Bathroom", 0.6, 0.6, 1.5)]
        for (name, w, h, sill) in table {
            let o = window(name)
            XCTAssertEqual(o.width.scanned, w, accuracy: 1e-9, name)
            XCTAssertEqual(o.height.scanned, h, accuracy: 1e-9, name)
            XCTAssertEqual(o.sillHeight.scanned, sill, accuracy: 1e-9, name)
        }
        XCTAssertEqual(rooms.flatMap(\.openings).filter { $0.kind == .window }.count, 5)
        // The balcony sliding door is a floor-to-top-of-frame door, 2.4 wide, on both sides of the wall.
        let living = room("Living Room"), balcony = room("Balcony")
        let sliding = living.openings.first { $0.kind == .door && $0.width.scanned > 2 }!
        XCTAssertEqual(sliding.width.scanned, 2.4, accuracy: 1e-9)
        XCTAssertEqual(sliding.height.scanned, 2.2, accuracy: 1e-9)
        XCTAssertEqual(balcony.openings.count, 1)
        XCTAssertEqual(balcony.openings[0].width.scanned, 2.4, accuracy: 1e-9)
    }

    func testWindowsFaceOutsideAndDoorsLineUpBetweenRooms() {
        // A window looks out: half a metre beyond it there is no room.
        for r in rooms {
            for o in r.openings where o.kind == .window {
                let wall = r.wall(withID: o.wallID!)!
                let mid = planMidpoint(of: o, in: r)!
                let outside = mid - wall.inwardNormal * 0.5
                XCTAssertFalse(Polygon.contains(r.outline, outside), "\(r.name) window faces into its own room")
                for other in rooms where other.name != r.name {
                    XCTAssertFalse(Polygon.contains(other.outline, outside), "\(r.name) window opens into \(other.name)")
                }
            }
        }
        // Every internal door has exactly one partner in a neighbouring room (the same doorway seen from the other side);
        // the single unpaired door is the apartment entrance, on the corridor's east wall.
        struct D { var room: String; var mid: Point2; var width: Double }
        let doors: [D] = rooms.flatMap { r in
            r.openings.filter { $0.kind == .door }.map { D(room: r.name, mid: planMidpoint(of: $0, in: r)!, width: $0.width.scanned) }
        }
        XCTAssertEqual(doors.count, 15)
        var unpaired: [D] = []
        for d in doors {
            let partners = doors.filter { $0.room != d.room && $0.mid.distance(to: d.mid) < 0.25 && abs($0.width - d.width) < 0.06 }
            if partners.isEmpty { unpaired.append(d) } else { XCTAssertEqual(partners.count, 1, "\(d.room) door has \(partners.count) partners") }
            for p in partners { XCTAssertLessThan(p.mid.distance(to: d.mid), 0.25) }
        }
        XCTAssertEqual(unpaired.count, 1)
        XCTAssertEqual(unpaired.first?.room, "Corridor")
        XCTAssertGreaterThanOrEqual(unpaired.first?.width ?? 0, 0.95, "entrance door")
        let corridor = room("Corridor")
        let entrance = corridor.openings.first { $0.width.scanned >= 0.95 && $0.kind == .door }!
        let entranceWall = corridor.wall(withID: entrance.wallID!)!
        XCTAssertGreaterThan(entranceWall.midpoint.x, corridor.outline.map(\.x).max()! - 0.05, "entrance is on the corridor's east end")
        // The living room reaches the corridor, kitchen, bathroom and balcony; the corridor reaches both bedrooms.
        XCTAssertEqual(room("Living Room").openings.filter { $0.kind == .door }.count, 4)
        XCTAssertEqual(corridor.openings.count, 4)
        XCTAssertEqual(room("Master Bedroom").openings.filter { $0.kind == .door }.count, 2)
    }

    // MARK: Verification

    func testSomeDimensionsAreLaserVerifiedAndMostAreNot() {
        struct M { var room: String; var what: String; var m: Measured }
        var all: [M] = []
        for r in rooms {
            all.append(M(room: r.name, what: "ceiling", m: r.ceilingHeight))
            for w in r.walls { all.append(M(room: r.name, what: "wall length", m: w.length)); all.append(M(room: r.name, what: "wall height", m: w.height)) }
            for o in r.openings {
                all.append(M(room: r.name, what: "\(o.kind) width", m: o.width))
                all.append(M(room: r.name, what: "\(o.kind) height", m: o.height))
                all.append(M(room: r.name, what: "\(o.kind) sill", m: o.sillHeight))
            }
        }
        let verified = all.filter { $0.m.isVerified }
        XCTAssertGreaterThanOrEqual(verified.count, 5, "a handful")
        XCTAssertLessThanOrEqual(verified.count, 12)
        XCTAssertLessThan(Double(verified.count) / Double(all.count), 0.15, "most values stay unverified")
        for v in verified {
            let tag = "\(v.room) \(v.what)"
            XCTAssertEqual(v.m.verification?.source, .laser, tag)
            XCTAssertEqual(v.m.verification?.date, now, tag)
            let dev = abs(v.m.deviation ?? 0)
            XCTAssertGreaterThanOrEqual(dev, 0.0025, "\(tag): a few millimetres at least")
            XCTAssertLessThanOrEqual(dev, 0.0215, "\(tag): at most 2 cm")
            XCTAssertNotEqual(v.m.value, v.m.scanned, tag)
            // Verified values are typed in at millimetre resolution.
            XCTAssertEqual(v.m.value * 1000, (v.m.value * 1000).rounded(), accuracy: 1e-6, tag)
            XCTAssertNotNil(v.m.verification?.note, tag)
        }
        // Both signs of deviation occur: the scan sometimes reads long, sometimes short.
        XCTAssertTrue(verified.contains { ($0.m.deviation ?? 0) > 0 } && verified.contains { ($0.m.deviation ?? 0) < 0 })

        // The wardrobe walls and the living room window are among them.
        let mb = room("Master Bedroom")
        let wardrobeWall = mb.walls.min { $0.midpoint.distance(to: Point2(4.6, 8.2)) < $1.midpoint.distance(to: Point2(4.6, 8.2)) }!
        XCTAssertTrue(wardrobeWall.length.isVerified, "master bedroom wardrobe wall")
        let wardrobe = mb.objects.first { $0.kind == .storage && $0.width > 2 }!
        XCTAssertEqual(wardrobe.width, 2.4, accuracy: 1e-9)
        XCTAssertLessThan(abs((wardrobe.center - wardrobeWall.start).dot(wardrobeWall.inwardNormal)), 0.5, "the wardrobe stands against that wall")
        let b2 = room("Bedroom 2")
        let b2Wall = b2.walls.min { $0.midpoint.distance(to: Point2(4.75, 7.9)) < $1.midpoint.distance(to: Point2(4.75, 7.9)) }!
        XCTAssertTrue(b2Wall.length.isVerified, "bedroom 2 wardrobe wall")
        let window = room("Living Room").openings.first { $0.kind == .window }!
        XCTAssertTrue(window.width.isVerified && window.height.isVerified, "living room window")
        XCTAssertFalse(window.sillHeight.isVerified)
        XCTAssertEqual(window.width.value - window.width.scanned, window.width.deviation!, accuracy: 1e-12)
        XCTAssertEqual(room("Corridor").openings.filter { $0.width.isVerified }.count, 1, "entrance door")

        // Unverified values dominate every room, and the exports' "value" differs from "scanned" only where verified.
        for r in rooms {
            let unverified = r.walls.filter { !$0.length.isVerified }.count
            XCTAssertGreaterThanOrEqual(unverified, 2, "\(r.name) keeps unverified walls")
            for w in r.walls where !w.length.isVerified { XCTAssertEqual(w.length.value, w.length.scanned) }
        }
        // Verifying changes what the metrics report.
        let living = room("Living Room")
        XCTAssertEqual(living.metrics.sides.filter(\.isVerified).count, 2, "west wall and balcony wall")
        XCTAssertEqual(mb.metrics.sides.filter(\.isVerified).count, 2, "wardrobe wall and corridor wall")
        for side in living.metrics.sides + mb.metrics.sides where side.isVerified {
            XCTAssertNotEqual(side.length, side.scannedLength, "a verified side reports the laser value")
        }
    }

    func testCustomMeasurements() {
        let mb = room("Master Bedroom")
        XCTAssertEqual(mb.customMeasurements.count, 1)
        let m = mb.customMeasurements[0]
        XCTAssertEqual(m.label, "Wardrobe wall")
        XCTAssertEqual(m.length.scanned, 2.4, accuracy: 1e-9)
        XCTAssertTrue(m.length.isVerified)
        XCTAssertEqual(m.length.verification?.source, .laser)
        XCTAssertEqual(m.a.y, DemoProperty.floorY + 1.0, accuracy: 1e-12)
        XCTAssertEqual(m.createdAt, now)
        // The measurement runs along the wardrobe in the shared frame.
        let wardrobe = mb.objects.first { $0.kind == .storage && $0.width > 2 }!
        XCTAssertLessThan(m.a.plan.distance(to: wardrobe.center), 1.3)
        XCTAssertLessThan(m.b.plan.distance(to: wardrobe.center), 1.3)
        let kitchen = room("Kitchen")
        XCTAssertEqual(kitchen.customMeasurements.map(\.label), ["Counter run"])
        XCTAssertFalse(kitchen.customMeasurements[0].length.isVerified)
        XCTAssertEqual(rooms.flatMap(\.customMeasurements).count, 2)
    }

    // MARK: Corners

    func testBedroom2HasOneSlightlyOutOfSquareCorner() {
        let b2 = room("Bedroom 2")
        let corners = b2.metrics.corners
        let skew = corners.filter { abs($0.interiorAngle - 91.5) < 0.6 }
        XCTAssertEqual(skew.count, 1, "one corner close to 91.5: \(corners.map(\.interiorAngle))")
        XCTAssertFalse(skew[0].isSquare(), "reads as out of square")
        XCTAssertTrue(b2.metrics.outOfSquareCorners.contains { $0.index == skew[0].index })
        // The wall that leans also gives the 88.5 degree twin; the other two corners are square.
        XCTAssertEqual(corners.filter { abs($0.interiorAngle - 88.5) < 0.6 }.count, 1)
        XCTAssertEqual(corners.filter { $0.isSquare() }.count, 2)
        XCTAssertTrue(b2.metrics.isRectangular, "within the 5 degree rectangle tolerance")
        XCTAssertEqual(b2.metrics.floorArea, 3.8 * 3.4, accuracy: 3.8 * 3.4 * 0.01)
        // No other room has an out-of-square corner (scan noise is far below 1 degree).
        for r in rooms where r.name != "Bedroom 2" {
            XCTAssertTrue(r.metrics.outOfSquareCorners.isEmpty, "\(r.name): \(r.metrics.corners.map(\.interiorAngle))")
            for c in r.metrics.corners { XCTAssertEqual(c.interiorAngle, 90, accuracy: 0.6, r.name) }
        }
    }

    // MARK: Objects

    func testObjectsAreRealisticAndInsideTheirRooms() {
        let kinds = Dictionary(grouping: rooms.flatMap(\.objects), by: \.kind).mapValues(\.count)
        XCTAssertGreaterThanOrEqual(kinds[.storage] ?? 0, 5)
        XCTAssertEqual(kinds[.bed], 2)
        XCTAssertEqual(kinds[.sofa], 1)
        XCTAssertEqual(kinds[.toilet], 2)
        XCTAssertEqual(kinds[.sink], 3)
        XCTAssertEqual(kinds[.refrigerator], 1)
        XCTAssertEqual(kinds[.stove], 1)
        XCTAssertEqual(kinds[.bathtub], 1)
        XCTAssertNil(kinds[.other])
        for r in rooms {
            for o in r.objects {
                XCTAssertTrue(Polygon.contains(r.outline, o.center), "\(r.name) \(o.kind) centre is outside the room")
                for c in o.footprint {
                    // Footprint corners may touch the walls; allow scan noise.
                    let inside = Polygon.contains(r.outline, c)
                    let nearWall = r.walls.contains { distance(from: c, toSegment: $0.start, $0.end) < 0.04 }
                    XCTAssertTrue(inside || nearWall, "\(r.name) \(o.kind) sticks out of the room")
                }
                XCTAssertGreaterThan(o.width, 0); XCTAssertGreaterThan(o.depth, 0); XCTAssertGreaterThan(o.height, 0)
                XCTAssertGreaterThanOrEqual(o.elevation, 0)
                XCTAssertLessThanOrEqual(o.elevation + o.height, r.ceilingHeight.scanned + 0.02)
            }
        }
        // Wall cabinets float; the TV hangs on the wall.
        XCTAssertGreaterThan(room("Kitchen").objects.first { $0.kind == .storage }!.elevation, 1.0)
        XCTAssertGreaterThan(room("Living Room").objects.first { $0.kind == .television }!.elevation, 0.5)
        // The big wardrobe is a proper wardrobe.
        let wardrobe = room("Master Bedroom").objects.first { $0.kind == .storage && $0.width > 2 }!
        XCTAssertEqual(wardrobe.depth, 0.6, accuracy: 1e-9)
        XCTAssertEqual(wardrobe.height, 2.4, accuracy: 1e-9)
        // Objects within a room do not overlap (compare footprint centres against half extents, conservatively).
        for r in rooms {
            for i in r.objects.indices {
                for j in (i + 1)..<r.objects.count {
                    let a = r.objects[i], b = r.objects[j]
                    if a.elevation > 0.3 || b.elevation > 0.3 { continue }     // wall units, TV
                    XCTAssertFalse(overlap(a.footprint, b.footprint), "\(r.name): \(a.kind) overlaps \(b.kind)")
                }
            }
        }
    }

    // MARK: Time and Codable

    func testScanTimesEndAtNowAndPropertySurvivesJSON() throws {
        let times = rooms.map(\.scannedAt)
        XCTAssertEqual(times.last, now)
        for (a, b) in zip(times, times.dropFirst()) { XCTAssertLessThan(a, b) }
        XCTAssertTrue(times.allSatisfy { $0 <= now })
        let data = try JSONEncoder().encode(property)
        XCTAssertEqual(try JSONDecoder().decode(Property.self, from: data), property)
    }

    func testDemoPropertyFeedsTheRoomModelHonestly() {
        // Rooms come from the real builder: ids of walls are RoomPlan surface ids from the fixtures, heights
        // are medians of scanned values, and nothing in the model claims verification it does not have.
        for r in rooms {
            XCTAssertEqual(r.ceilingHeight.scanned, RoomBuilder.median(r.walls.map { $0.height.scanned })!, accuracy: 1e-12)
            XCTAssertFalse(r.ceilingHeight.isVerified)
            XCTAssertTrue(Polygon.isCounterClockwise(r.outline))
            XCTAssertTrue(r.metrics.corners.allSatisfy { !$0.isReflex })
            XCTAssertEqual(r.notes, "")
        }
        // Building the same room again by hand matches the demo (the demo is not hand-edited geometry).
        let fixture = CaptureFixtures.rectangle(width: 2.2, depth: 1.8, height: 2.8,
                                                doors: [.door(wall: 3, offset: 0.65, width: 0.8, height: 2.1)],
                                                noise: .light, seed: 1107, extras: {
            var e = CaptureFixtures.Extras()
            e.origin = Point2(6.35, 2.95)
            e.floorY = DemoProperty.floorY
            e.label = "Bathroom 2"
            e.objects = [.init(category: "toilet", center: Point2(1.25, 1.45), width: 0.4, depth: 0.7, height: 0.8),
                         .init(category: "sink", center: Point2(1.95, 1.1), yaw: Double.pi / 2, width: 0.55, depth: 0.45, height: 0.85)]
            return e
        }())
        let rebuilt = RoomBuilder.build(from: fixture.capture, name: "Bathroom 2", kind: .bathroom, now: now).room
        // (The demo origin is computed as 6.2 + 0.15, which differs from the literal 6.35 by one ulp.)
        for (a, b) in zip(rebuilt.walls, room("Bathroom 2").walls) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertLessThan(a.start.distance(to: b.start), 1e-12)
        }
        XCTAssertEqual(rebuilt.walls.count, 4)
    }
}
