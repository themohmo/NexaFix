import Foundation

// Doors, windows, openings and objects for `RoomBuilder`.

extension RoomBuilder {

    struct OpeningResult {
        var openings: [Opening]
        var warnings: [BuildWarning]
    }

    struct ObjectResult {
        var objects: [RoomObject]
        var warnings: [BuildWarning]
    }

    /// Distance from `p` to the closed segment of `wall`, metres.
    static func distance(from p: Point2, to wall: Wall) -> Double {
        let d = wall.end - wall.start
        let l2 = d.dot(d)
        guard l2 > 1e-18 else { return p.distance(to: wall.start) }
        let t = min(1, max(0, (p - wall.start).dot(d) / l2))
        return p.distance(to: wall.start + d * t)
    }

    // MARK: Openings

    /// Attach doors, windows and openings to the final walls.
    ///
    /// * `wallID`: the wall `parentID` points at (through `surfaceToWall`, so merged walls work)
    ///   while the opening is within `openingParentTrustDistance` of it; otherwise the nearest solid
    ///   wall by distance from the opening centre; farther than `openingMatchDistance` from every
    ///   wall -> nil and a warning.
    /// * `offsetFromWallStart`: along the FINAL (counter-clockwise) wall from `wall.start` to the
    ///   opening's near edge, clamped so the opening stays on the wall.
    /// * `width = dimensions.x` (clamped to the wall length), `height = dimensions.y`,
    ///   `sillHeight = (centre.y - height/2) - floorElevation`, floored at 0 and snapped to 0 below 3 cm.
    static func buildOpenings(capture: RawCapture, walls: [Wall], surfaceToWall: [UUID: UUID],
                              floorElevation: Double, options: Options) -> OpeningResult {
        struct Item {
            var opening: Opening
            var wallIndex: Int?
        }
        var items: [Item] = []
        var warnings: [BuildWarning] = []
        var invalid = 0
        var taken = Set<UUID>()
        let groups: [(OpeningKind, [RawSurface])] = [(.door, capture.doors), (.window, capture.windows),
                                                      (.opening, capture.openings)]
        for (kind, surfaces) in groups {
            for s in surfaces.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                guard isValidSurface(s), s.dimensions.x >= 0.05, s.dimensions.y >= 0.05 else { invalid += 1; continue }
                var id = s.id
                var salt = 0
                while taken.contains(id) { salt += 1; id = stableUUID("opening|\(s.id.uuidString)|\(salt)") }
                taken.insert(id)

                let c = s.transform.translation
                let p = Point2(c.x, -c.z)
                let height = s.dimensions.y
                var sill = (c.y - height / 2) - floorElevation
                if !(sill >= 0.03) { sill = 0 }

                // Which wall?
                var wallIndex: Int?
                if let pid = s.parentID, let wid = surfaceToWall[pid],
                   let idx = walls.firstIndex(where: { $0.id == wid }),
                   distance(from: p, to: walls[idx]) <= options.openingParentTrustDistance {
                    wallIndex = idx
                }
                var nearest: Double?
                if wallIndex == nil {
                    for solidPass in [true, false] {
                        var bestIdx: Int?
                        var bestD = Double.infinity
                        for (i, w) in walls.enumerated() where (w.kind == .solid) == solidPass {
                            let d = distance(from: p, to: w)
                            if d < bestD - 1e-9 { bestD = d; bestIdx = i }
                        }
                        if let bi = bestIdx {
                            nearest = min(nearest ?? .infinity, bestD)
                            if bestD <= options.openingMatchDistance { wallIndex = bi; break }
                        }
                    }
                }

                guard let wi = wallIndex else {
                    warnings.append(.openingUnmatched(id: id, kind: kind, nearestDistance: nearest))
                    items.append(Item(opening: Opening(id: id, kind: kind, wallID: nil, offsetFromWallStart: 0,
                                                       width: Measured(scanned: s.dimensions.x),
                                                       height: Measured(scanned: height),
                                                       sillHeight: Measured(scanned: sill)),
                                      wallIndex: nil))
                    continue
                }

                let wall = walls[wi]
                let len = wall.geometricLength
                let dir = wall.direction
                let along = (p - wall.start).dot(dir)
                let width = min(s.dimensions.x, len)
                let wanted = along - width / 2
                let near = min(max(0, wanted), max(0, len - width))
                if width < s.dimensions.x - 0.01 || abs(near - wanted) > 0.01 {
                    warnings.append(.openingAdjusted(id: id, kind: kind))
                }
                items.append(Item(opening: Opening(id: id, kind: kind, wallID: wall.id, offsetFromWallStart: near,
                                                   width: Measured(scanned: width), height: Measured(scanned: height),
                                                   sillHeight: Measured(scanned: sill)),
                                  wallIndex: wi))
            }
        }
        if invalid > 0 { warnings.insert(.invalidOpeningsIgnored(count: invalid), at: 0) }

        items.sort { a, b in
            let ai = a.wallIndex ?? Int.max, bi = b.wallIndex ?? Int.max
            if ai != bi { return ai < bi }
            let ao = a.opening.offsetFromWallStart, bo = b.opening.offsetFromWallStart
            if abs(ao - bo) > 1e-6 { return ao < bo }
            if a.opening.kind != b.opening.kind { return a.opening.kind.rawValue < b.opening.kind.rawValue }
            return a.opening.id.uuidString < b.opening.id.uuidString
        }
        return OpeningResult(openings: items.map(\.opening), warnings: warnings)
    }

    // MARK: Objects

    /// Map a RoomPlan category name to an `ObjectKind`; unknown names become `.other`.
    public static func objectKind(forCategory category: String) -> ObjectKind {
        switch category {
        case "storage": return .storage
        case "refrigerator": return .refrigerator
        case "stove": return .stove
        case "bed": return .bed
        case "sink": return .sink
        case "washerDryer": return .washerDryer
        case "toilet": return .toilet
        case "bathtub": return .bathtub
        case "oven": return .oven
        case "dishwasher": return .dishwasher
        case "table": return .table
        case "sofa": return .sofa
        case "chair": return .chair
        case "fireplace": return .fireplace
        case "television": return .television
        case "stairs": return .stairs
        default: return .other
        }
    }

    /// Convert scanned objects: footprint centre in plan space, `yaw` = direction of the object's
    /// local X axis in plan, width = dimensions.x, depth = dimensions.z, height = dimensions.y,
    /// elevation = centre.y - height/2 - floorElevation (never negative).
    static func buildObjects(_ raw: [RawObject], floorElevation: Double) -> ObjectResult {
        var objects: [RoomObject] = []
        var invalid = 0
        var taken = Set<UUID>()
        for o in raw.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let m = o.transform.columnMajor
            guard m.count == 16, m.allSatisfy({ $0.isFinite && abs($0) < 1e7 }),
                  o.dimensions.x.isFinite, o.dimensions.y.isFinite, o.dimensions.z.isFinite,
                  o.dimensions.x > 0, o.dimensions.y > 0, o.dimensions.z > 0,
                  o.dimensions.x < 1e3, o.dimensions.y < 1e3, o.dimensions.z < 1e3 else { invalid += 1; continue }
            var id = o.id
            var salt = 0
            while taken.contains(id) { salt += 1; id = stableUUID("object|\(o.id.uuidString)|\(salt)") }
            taken.insert(id)

            let c = o.transform.translation
            let xa = o.transform.xAxis
            let yaw = (xa.x * xa.x + xa.z * xa.z) > 1e-12 ? atan2(-xa.z, xa.x) : 0
            let elevation = max(0, c.y - o.dimensions.y / 2 - floorElevation)
            objects.append(RoomObject(id: id, kind: objectKind(forCategory: o.category), center: Point2(c.x, -c.z),
                                      yaw: yaw, width: o.dimensions.x, depth: o.dimensions.z,
                                      height: o.dimensions.y, elevation: elevation))
        }
        let warnings: [BuildWarning] = invalid > 0 ? [.invalidObjectsIgnored(count: invalid)] : []
        return ObjectResult(objects: objects, warnings: warnings)
    }
}
