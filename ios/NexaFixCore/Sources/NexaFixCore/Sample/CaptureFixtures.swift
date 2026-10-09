import Foundation

/// Synthetic `RawCapture`s that look exactly like what RoomPlan produces, for tests, previews and
/// the demo property.
///
/// Every wall is a surface with a 4x4 transform (centre = translation, local X along the wall,
/// local Y up, local Z the normal) and `dimensions = (length, height, 0)`; doors and windows carry a
/// `parentID`; the floor is a surface whose `polygonCorners` are expressed in its local frame; and
/// objects are boxes centred on their transform. Like the real thing, the surfaces arrive in
/// arbitrary order and RoomPlan does not say which way a wall's local X points, so each wall,
/// door and window is randomly flipped by 180 degrees.
///
/// Everything is deterministic: identifiers come from the fixture name and element index, and the
/// shuffle, the flips and the noise come from a seeded generator (`SeededGenerator`, SplitMix64,
/// identical on every platform).
///
/// Each `Fixture` carries the ground truth (`corners`, `expectedArea`, ...) so tests can compare the
/// builder's output with numbers computed independently of the builder.
public enum CaptureFixtures {

    // MARK: Seeded generator

    /// SplitMix64: tiny, fast, and the same sequence on every platform and Swift version.
    public struct SeededGenerator: RandomNumberGenerator, Sendable {
        public var state: UInt64
        public init(seed: UInt64) { state = seed }

        public mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        public mutating func nextUnit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
        /// Uniform in [-amplitude, +amplitude].
        public mutating func symmetric(_ amplitude: Double) -> Double { (nextUnit() * 2 - 1) * amplitude }
        public mutating func nextBool() -> Bool { next() & 1 == 1 }

        /// Fisher-Yates, written out so the permutation does not depend on the standard library version.
        public mutating func shuffle<T>(_ items: inout [T]) {
            guard items.count > 1 else { return }
            for i in stride(from: items.count - 1, to: 0, by: -1) {
                let j = Int(next() % UInt64(i + 1))
                if i != j { items.swapAt(i, j) }
            }
        }
    }

    // MARK: Noise

    /// How badly the scan misses the truth. All amplitudes are +/- uniform.
    public struct Noise: Hashable, Sendable {
        /// Wall plane position error along the wall normal, metres.
        public var offset: Double
        /// Each wall end moves along the wall by this much: a gap (shorter) or an overshoot (longer), metres.
        public var endError: Double
        /// Wall direction error, degrees.
        public var angleDegrees: Double
        /// Wall height error, metres.
        public var heightError: Double
        /// Door / window / object position error, metres.
        public var placementError: Double

        public init(offset: Double = 0, endError: Double = 0, angleDegrees: Double = 0,
                    heightError: Double = 0, placementError: Double = 0) {
            self.offset = offset
            self.endError = endError
            self.angleDegrees = angleDegrees
            self.heightError = heightError
            self.placementError = placementError
        }

        public static let none = Noise()
        /// Good scan: 5 mm planes, 2 cm corner gaps / overshoots, 0.1 degree.
        public static let light = Noise(offset: 0.005, endError: 0.02, angleDegrees: 0.1,
                                        heightError: 0.005, placementError: 0.01)
        /// Typical scan: 1 cm planes, 4 cm corner gaps / overshoots, 0.3 degree.
        public static let realistic = Noise(offset: 0.010, endError: 0.04, angleDegrees: 0.3,
                                            heightError: 0.010, placementError: 0.02)
    }

    // MARK: Inputs

    /// A furniture box to emit, in the room's local frame (before `origin` / `rotationDegrees`).
    public struct FixtureObject: Hashable, Sendable {
        /// RoomPlan category name, e.g. "storage", "sofa".
        public var category: String
        public var center: Point2
        /// Rotation of the object's local X axis in plan, counter-clockwise from +x, radians.
        public var yaw: Double
        public var width: Double
        public var depth: Double
        public var height: Double
        /// Bottom face above the floor.
        public var elevation: Double

        public init(category: String, center: Point2, yaw: Double = 0, width: Double, depth: Double,
                    height: Double, elevation: Double = 0) {
            self.category = category
            self.center = center
            self.yaw = yaw
            self.width = width
            self.depth = depth
            self.height = height
            self.elevation = elevation
        }
    }

    /// An extra wall inside the room (partition, bulkhead, half wall) that is NOT part of the boundary.
    public struct InteriorWall: Hashable, Sendable {
        public var from: Point2
        public var to: Point2
        public var height: Double?
        public init(from: Point2, to: Point2, height: Double? = nil) {
            self.from = from
            self.to = to
            self.height = height
        }
    }

    /// Per-wall deviations from a clean scan. `wall` indexes the room's boundary walls (counter-clockwise).
    public struct WallTweak: Hashable, Sendable {
        public var wall: Int
        /// Extend (+) or shorten (-) the wall at its start / end corner, metres.
        public var extendStart: Double
        public var extendEnd: Double
        /// RoomPlan never saw a wall here (open-plan side): emit no surface.
        public var omit: Bool
        /// Emit the wall as a curved surface (stored by RoomBuilder as its chord).
        public var curved: Bool
        /// Emit the wall as two collinear surfaces, split at this fraction (0...1) of its length.
        public var splitAt: Double?
        /// Gap (+) or overlap (-) between the two split pieces, metres.
        public var splitGap: Double
        /// Override this wall's height.
        public var height: Double?

        public init(wall: Int, extendStart: Double = 0, extendEnd: Double = 0, omit: Bool = false,
                    curved: Bool = false, splitAt: Double? = nil, splitGap: Double = 0, height: Double? = nil) {
            self.wall = wall
            self.extendStart = extendStart
            self.extendEnd = extendEnd
            self.omit = omit
            self.curved = curved
            self.splitAt = splitAt
            self.splitGap = splitGap
            self.height = height
        }
    }

    /// Everything optional about a fixture.
    public struct Extras: Sendable {
        /// Doorless passages (`capture.openings`).
        public var passages: [OpeningSpec] = []
        public var objects: [FixtureObject] = []
        public var interiorWalls: [InteriorWall] = []
        public var tweaks: [WallTweak] = []
        /// Every wall extends this much past both its corners (+ overshoot, - gap), metres.
        public var overshoot: Double = 0
        /// South-west corner of the room in the shared floor frame.
        public var origin: Point2 = .zero
        /// Rotate the whole room about `origin`, degrees counter-clockwise.
        public var rotationDegrees: Double = 0
        /// World Y of the floor.
        public var floorY: Double = 0
        public var includeFloor: Bool = true
        /// Prefix for identifiers; defaults to the shape name. Give each room of a property its own.
        public var label: String?
        /// Override the floor polygon (room-local frame).
        public var floorPolygon: [Point2]?

        public init() {}
    }

    // MARK: Fixture

    /// A generated capture plus the ground truth it was generated from.
    public struct Fixture: Sendable {
        public var name: String
        /// The capture as RoomPlan would hand it over: shuffled, walls randomly flipped.
        public var capture: RawCapture
        /// The same surfaces in generation order and unflipped (input to `reshuffled`).
        public var canonical: RawCapture
        /// True room outline, counter-clockwise, in the shared floor frame. For an open-plan fixture
        /// this includes the side with no wall.
        public var corners: [Point2]
        /// Area of `corners`, computed independently of `RoomBuilder`.
        public var expectedArea: Double
        public var expectedPerimeter: Double
        /// Number of walls the builder should return (merged splits count once, bridged sides count once).
        public var expectedWallCount: Int
        /// Number of those that should be `.virtual`.
        public var expectedVirtualWallCount: Int
        public var ceilingHeight: Double
        public var floorY: Double
        /// Area of the emitted floor polygon, nil without a floor.
        public var floorArea: Double?
        /// Surface ids per boundary wall (index = boundary wall index; empty when omitted; two for a split wall).
        public var wallSurfaceIDs: [[UUID]]
        /// Ids of the interior (non-boundary) wall surfaces.
        public var interiorSurfaceIDs: [UUID]
        public var seed: UInt64

        /// The same surfaces with a different order and different random flips (noise is kept).
        public func reshuffled(seed: UInt64) -> RawCapture {
            CaptureFixtures.shuffleAndFlip(canonical, seed: seed)
        }
    }

    // MARK: Furniture

    /// A few plausible objects for a `width x depth` room in the room-local frame (south-west corner at the
    /// origin): a sofa against the south wall, a coffee table in front of it, a wardrobe against the west
    /// wall and a chair in the north-east corner. They fit inside any room of at least 3 x 2.5 m.
    /// Pass the result as `Extras.objects`.
    public static func sampleObjects(width: Double, depth: Double) -> [FixtureObject] {
        [FixtureObject(category: "sofa", center: Point2(width / 2, 0.5), width: 2.0, depth: 0.9, height: 0.85),
         FixtureObject(category: "table", center: Point2(width / 2, 1.5), width: 1.0, depth: 0.5, height: 0.4),
         FixtureObject(category: "storage", center: Point2(0.3, depth / 2), yaw: Double.pi / 2, width: 1.8, depth: 0.6, height: 2.2),
         FixtureObject(category: "chair", center: Point2(width - 0.6, depth - 0.6), yaw: Double.pi / 4, width: 0.5, depth: 0.5, height: 0.9)]
    }

    // MARK: Shapes

    /// Axis-aligned rectangle, south-west corner at the origin. Walls: 0 south, 1 east, 2 north, 3 west.
    public static func rectangle(width: Double = 4.0, depth: Double = 3.0, height: Double = 2.8,
                                 doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                 noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        polygon(name: "rectangle",
                corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(0, depth)],
                height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// Rectangle with a notch cut from the top-right corner. Walls: 0 south, 1 east, 2 notch floor,
    /// 3 notch side, 4 north, 5 west. Area = width * depth - notchWidth * notchDepth.
    public static func lShape(width: Double = 6.0, depth: Double = 4.0, notchWidth: Double = 2.0,
                              notchDepth: Double = 2.0, height: Double = 2.8,
                              doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                              noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        polygon(name: "lShape",
                corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth - notchDepth),
                          Point2(width - notchWidth, depth - notchDepth), Point2(width - notchWidth, depth),
                          Point2(0, depth)],
                height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// T: a bar of `barWidth x barDepth` on top of a centred stem of `stemWidth x stemDepth`.
    /// Area = barWidth * barDepth + stemWidth * stemDepth.
    public static func tShape(barWidth: Double = 6.0, barDepth: Double = 2.5, stemWidth: Double = 2.5,
                              stemDepth: Double = 3.0, height: Double = 2.8,
                              doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                              noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        let x0 = (barWidth - stemWidth) / 2, x1 = x0 + stemWidth
        return polygon(name: "tShape",
                       corners: [Point2(x0, 0), Point2(x1, 0), Point2(x1, stemDepth), Point2(barWidth, stemDepth),
                                 Point2(barWidth, stemDepth + barDepth), Point2(0, stemDepth + barDepth),
                                 Point2(0, stemDepth), Point2(x0, stemDepth)],
                       height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// U: a rectangle with a centred notch cut from the top. Area = width * depth - cutWidth * cutDepth.
    public static func uShape(width: Double = 6.0, depth: Double = 5.0, cutWidth: Double = 2.0,
                              cutDepth: Double = 3.0, height: Double = 2.8,
                              doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                              noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        let x0 = (width - cutWidth) / 2, x1 = x0 + cutWidth
        return polygon(name: "uShape",
                       corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(x1, depth),
                                 Point2(x1, depth - cutDepth), Point2(x0, depth - cutDepth), Point2(x0, depth),
                                 Point2(0, depth)],
                       height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// Symmetric trapezoid: `bottom` wide at y = 0, `top` wide at y = depth. Area = (bottom + top) / 2 * depth.
    public static func trapezoid(bottom: Double = 5.0, top: Double = 3.0, depth: Double = 4.0,
                                 height: Double = 2.8, doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                 noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        let inset = (bottom - top) / 2
        return polygon(name: "trapezoid",
                       corners: [Point2(0, 0), Point2(bottom, 0), Point2(bottom - inset, depth), Point2(inset, depth)],
                       height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// Rectangle with a 45 degree chamfer across the top-right corner. Area = width * depth - chamfer^2 / 2.
    public static func chamfered(width: Double = 5.0, depth: Double = 4.0, chamfer: Double = 1.0,
                                 height: Double = 2.8, doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                 noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        polygon(name: "chamfered",
                corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth - chamfer),
                          Point2(width - chamfer, depth), Point2(0, depth)],
                height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// Rectangle with a niche (alcove) recessed into the north wall.
    /// Area = width * depth + nicheWidth * nicheDepth.
    public static func alcove(width: Double = 5.0, depth: Double = 3.5, nicheWidth: Double = 1.2,
                              nicheDepth: Double = 0.4, nicheOffset: Double = 1.5, height: Double = 2.8,
                              doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                              noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        polygon(name: "alcove",
                corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth),
                          Point2(nicheOffset + nicheWidth, depth), Point2(nicheOffset + nicheWidth, depth + nicheDepth),
                          Point2(nicheOffset, depth + nicheDepth), Point2(nicheOffset, depth), Point2(0, depth)],
                height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: extras)
    }

    /// Rectangle with the side `missingWall` (0 south, 1 east, 2 north, 3 west) never seen by
    /// RoomPlan: an open-plan boundary. The builder should bridge it with a `.virtual` wall.
    public static func openPlan(width: Double = 5.0, depth: Double = 4.0, missingWall: Int = 3,
                                height: Double = 2.8, doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        var e = extras
        e.tweaks.append(WallTweak(wall: missingWall, omit: true))
        return polygon(name: "openPlan",
                       corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(0, depth)],
                       height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: e)
    }

    /// Rectangle whose wall `wall` arrives as two collinear surfaces, split at fraction `at` of its
    /// length with `gap` metres between them (negative = overlap). The builder should merge them.
    public static func splitWall(width: Double = 5.0, depth: Double = 4.0, wall: Int = 0, at: Double = 0.4,
                                 gap: Double = 0.03, height: Double = 2.8,
                                 doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                 noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        var e = extras
        e.tweaks.append(WallTweak(wall: wall, splitAt: at, splitGap: gap))
        return polygon(name: "splitWall",
                       corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(0, depth)],
                       height: height, doors: doors, windows: windows, noise: noise, seed: seed, extras: e)
    }

    /// Rectangle whose wall `wall` is a curved surface (chord reported, `isCurved` set). The floor
    /// polygon follows the arc, bulging `sagitta` metres outwards. `expectedArea` is the CHORD
    /// polygon (that is what RoomBuilder stores); `floorArea` includes the bulge.
    public static func curvedWall(width: Double = 5.0, depth: Double = 4.0, wall: Int = 1, sagitta: Double = 0.3,
                                  height: Double = 2.8, doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                                  noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        let corners = [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(0, depth)]
        var e = extras
        e.tweaks.append(WallTweak(wall: wall, curved: true))
        // Floor follows the arc.
        var floor: [Point2] = []
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            floor.append(a)
            if i == wall {
                let chord = a.distance(to: b)
                let dir = (b - a).normalized
                let outward = -dir.perpendicularCCW
                let radius = (chord * chord / 4 + sagitta * sagitta) / (2 * sagitta)
                for k in 1..<12 {
                    let u = (Double(k) / 12 - 0.5) * chord
                    let h = (radius * radius - u * u).squareRoot() - (radius - sagitta)
                    floor.append(a + dir * (Double(k) / 12 * chord) + outward * h)
                }
            }
        }
        e.floorPolygon = floor
        return polygon(name: "curvedWall", corners: corners, height: height, doors: doors, windows: windows,
                       noise: noise, seed: seed, extras: e)
    }

    /// Rectangle in which wall `wall` runs `by` metres past BOTH corners (walls crossing: the
    /// builder trims it at the intersection of the wall lines).
    public static func overshootingWall(width: Double = 5.0, depth: Double = 4.0, wall: Int = 0, by: Double = 0.5,
                                        height: Double = 2.8, noise: Noise = .none, seed: UInt64 = 1,
                                        extras: Extras = Extras()) -> Fixture {
        var e = extras
        e.tweaks.append(WallTweak(wall: wall, extendStart: by, extendEnd: by))
        return polygon(name: "overshootingWall",
                       corners: [Point2(0, 0), Point2(width, 0), Point2(width, depth), Point2(0, depth)],
                       height: height, noise: noise, seed: seed, extras: e)
    }

    // MARK: General generator

    /// Emit a room whose boundary is `corners` (any winding; re-wound counter-clockwise, so wall `i`
    /// runs from corner `i` to corner `i + 1` of the re-wound list, like `Room.polygon`).
    public static func polygon(name: String, corners rawCorners: [Point2], height: Double = 2.8,
                               doors: [OpeningSpec] = [], windows: [OpeningSpec] = [],
                               noise: Noise = .none, seed: UInt64 = 1, extras: Extras = Extras()) -> Fixture {
        let label = extras.label ?? name
        let local = Polygon.counterClockwise(rawCorners)
        let n = local.count
        let rot = extras.rotationDegrees * Double.pi / 180
        func place(_ p: Point2) -> Point2 { extras.origin + p.rotated(by: rot) }
        let corners = local.map(place)

        var rng = SeededGenerator(seed: seed)
        func id(_ kind: String, _ i: Int, _ piece: Int = 0) -> UUID {
            RoomBuilder.stableUUID("fixture|\(label)|\(kind)|\(i)|\(piece)")
        }

        var walls: [RawSurface] = []
        var wallSurfaceIDs: [[UUID]] = []
        var truthSegments: [(start: Point2, end: Point2, ids: [UUID], splitAt: Double?, gap: Double)] = []

        for i in 0..<n {
            let a = corners[i], b = corners[(i + 1) % n]
            let tweak = extras.tweaks.first { $0.wall == i } ?? WallTweak(wall: i)
            let dir = (b - a).normalized
            let normal = dir.perpendicularCCW
            // Noise draws happen unconditionally so a seed always produces the same sequence.
            let dOffset = rng.symmetric(noise.offset)
            let dAngle = rng.symmetric(noise.angleDegrees) * Double.pi / 180
            let dStart = rng.symmetric(noise.endError)
            let dEnd = rng.symmetric(noise.endError)
            let dHeight = rng.symmetric(noise.heightError)

            if tweak.omit {
                wallSurfaceIDs.append([])
                truthSegments.append((a, b, [], nil, 0))
                continue
            }
            let wallHeight = (tweak.height ?? height) + dHeight
            let start = a - dir * (extras.overshoot + tweak.extendStart + dStart) + normal * dOffset
            let end = b + dir * (extras.overshoot + tweak.extendEnd + dEnd) + normal * dOffset
            // Rotate about the midpoint by dAngle.
            let mid = (start + end) * 0.5
            let rs = mid + (start - mid).rotated(by: dAngle)
            let re = mid + (end - mid).rotated(by: dAngle)

            func surface(_ p: Point2, _ q: Point2, _ sid: UUID) -> RawSurface {
                let c = (p + q) * 0.5
                let d = q - p
                let yaw = atan2(d.y, d.x)
                return RawSurface(id: sid, kind: .wall,
                                  transform: Matrix4.yawTranslation(yaw: yaw, Point3(c.x, extras.floorY + wallHeight / 2, -c.y)),
                                  dimensions: Point3(d.length, wallHeight, 0), isCurved: tweak.curved)
            }
            if let f = tweak.splitAt {
                let total = rs.distance(to: re)
                let ud = (re - rs).normalized
                let cut = f * total
                let first = surface(rs, rs + ud * (cut - tweak.splitGap / 2), id("wall", i, 0))
                let second = surface(rs + ud * (cut + tweak.splitGap / 2), re, id("wall", i, 1))
                walls.append(first)
                walls.append(second)
                wallSurfaceIDs.append([first.id, second.id])
                truthSegments.append((a, b, [first.id, second.id], f, tweak.splitGap))
            } else {
                let s = surface(rs, re, id("wall", i))
                walls.append(s)
                wallSurfaceIDs.append([s.id])
                truthSegments.append((a, b, [s.id], nil, 0))
            }
        }

        // Interior walls (not part of the boundary).
        var interiorIDs: [UUID] = []
        for (k, w) in extras.interiorWalls.enumerated() {
            let p = place(w.from), q = place(w.to)
            let c = (p + q) * 0.5, d = q - p
            let h = w.height ?? height
            let sid = id("interior", k)
            walls.append(RawSurface(id: sid, kind: .wall,
                                    transform: Matrix4.yawTranslation(yaw: atan2(d.y, d.x), Point3(c.x, extras.floorY + h / 2, -c.y)),
                                    dimensions: Point3(d.length, h, 0)))
            interiorIDs.append(sid)
        }

        // Doors, windows, passages.
        func openings(_ specs: [OpeningSpec], kind: RawSurfaceKind, tag: String) -> [RawSurface] {
            var out: [RawSurface] = []
            for (k, spec) in specs.enumerated() {
                let shiftNoise = rng.symmetric(noise.placementError)
                guard spec.wall >= 0, spec.wall < n else { continue }
                let truth = truthSegments[spec.wall]
                let dir = (truth.end - truth.start).normalized
                let along = spec.offset + spec.width / 2 + shiftNoise
                let c = truth.start + dir * along
                // Parent: the piece of the wall that holds the centre.
                var parent: UUID? = truth.ids.first
                if truth.ids.count == 2, let f = truth.splitAt {
                    let cut = f * truth.start.distance(to: truth.end)
                    parent = along <= cut ? truth.ids[0] : truth.ids[1]
                }
                out.append(RawSurface(id: id(tag, k), kind: kind,
                                      transform: Matrix4.yawTranslation(yaw: atan2(dir.y, dir.x),
                                                                        Point3(c.x, extras.floorY + spec.sill + spec.height / 2, -c.y)),
                                      dimensions: Point3(spec.width, spec.height, 0), parentID: parent))
            }
            return out
        }
        let doorSurfaces = openings(doors, kind: .door, tag: "door")
        let windowSurfaces = openings(windows, kind: .window, tag: "window")
        let passageSurfaces = openings(extras.passages, kind: .opening, tag: "opening")

        // Floor.
        var floors: [RawSurface] = []
        var floorArea: Double?
        if extras.includeFloor {
            let poly = (extras.floorPolygon.map { Polygon.counterClockwise($0).map(place) }) ?? corners
            if let bounds = Bounds2(points: poly) {
                let c = bounds.center
                let local = poly.map { Point3($0.x - c.x, $0.y - c.y, 0) }
                // Rotation of -90 degrees about X: local (x, y, 0) -> world (x, 0, -y).
                let m = Matrix4(columnMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, c.x, extras.floorY, -c.y, 1])
                floors.append(RawSurface(id: id("floor", 0), kind: .floor, transform: m,
                                         dimensions: Point3(bounds.width, bounds.height, 0), polygonCorners: local))
                floorArea = Polygon.area(poly)
            }
        }

        // Objects.
        var objects: [RawObject] = []
        for (k, o) in extras.objects.enumerated() {
            let p = place(o.center)
            let jitter = Point2(rng.symmetric(noise.placementError), rng.symmetric(noise.placementError))
            let yaw = o.yaw + rot
            objects.append(RawObject(id: id("object", k), category: o.category,
                                     transform: Matrix4.yawTranslation(yaw: yaw, Point3(p.x + jitter.x, extras.floorY + o.elevation + o.height / 2, -(p.y + jitter.y))),
                                     dimensions: Point3(o.width, o.height, o.depth)))
        }

        let canonical = RawCapture(id: RoomBuilder.stableUUID("fixture|\(label)|capture"), walls: walls,
                                   doors: doorSurfaces, windows: windowSurfaces, openings: passageSurfaces,
                                   floors: floors, objects: objects)
        let omitted = extras.tweaks.filter { $0.omit }.count
        return Fixture(name: label, capture: shuffleAndFlip(canonical, seed: seed), canonical: canonical,
                       corners: corners, expectedArea: Polygon.area(corners),
                       expectedPerimeter: Polygon.perimeter(corners), expectedWallCount: n,
                       expectedVirtualWallCount: omitted, ceilingHeight: height, floorY: extras.floorY,
                       floorArea: floorArea, wallSurfaceIDs: wallSurfaceIDs, interiorSurfaceIDs: interiorIDs,
                       seed: seed)
    }

    // MARK: Shuffle and flip

    /// Random order for every list and a random 180 degree flip of every wall, door, window and
    /// opening (RoomPlan does not say which way a surface faces). Objects keep their yaw.
    public static func shuffleAndFlip(_ capture: RawCapture, seed: UInt64) -> RawCapture {
        var rng = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03)
        func process(_ list: [RawSurface]) -> [RawSurface] {
            var out = list.map { rng.nextBool() ? flipped($0) : $0 }
            rng.shuffle(&out)
            return out
        }
        var c = capture
        c.walls = process(capture.walls)
        c.doors = process(capture.doors)
        c.windows = process(capture.windows)
        c.openings = process(capture.openings)
        c.floors = capture.floors
        c.objects = capture.objects
        rng.shuffle(&c.floors)
        rng.shuffle(&c.objects)
        return c
    }

    /// The surface turned 180 degrees about its vertical axis (local X and Z negated).
    public static func flipped(_ s: RawSurface) -> RawSurface {
        var m = s.transform.columnMajor
        for i in [0, 1, 2, 8, 9, 10] { m[i] = -m[i] }
        var out = s
        out.transform = Matrix4(columnMajor: m)
        return out
    }
}
