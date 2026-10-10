import Foundation

/// Turns a `RawCapture` (what RoomPlan's `CapturedRoom` reports) into a `Room`.
///
/// This is the hardest geometry in the app: real LiDAR data has gaps and overshoots at corners,
/// walls split in two, interior half-walls, open-plan sides RoomPlan never saw a wall on, and no
/// guarantee about wall order or orientation. The pipeline is:
///
///  1. **Wall segments.** Each wall surface becomes a plan-space segment (centre = translation,
///     along-vector = local X projected to the ground, half-length = `dimensions.x / 2`). Noise
///     (too short, nearly vertical along-vector, non-finite) is dropped.
///  2. **Collinear merge.** Pieces of one physical wall (same line, overlapping or separated by
///     no more than `snapTolerance`) are merged into ONE segment, and ONE `Wall` is emitted for
///     it. (Decision: merge, never keep two walls with a straight shared corner. A genuine hole
///     bigger than `snapTolerance` between collinear pieces is bridged by a `.virtual` wall, whose
///     corners ARE straight; `Room.metrics.sides` merges those correctly. A collinear piece that
///     continues PAST a corner is merged too: the loop then trims the wall at the corner like any other
///     overshoot, however far it runs, and reports the trim.)
///  3. **Boundary loop.** A search over wall ends finds the closed loop that explains the most wall
///     length with the least repair. Adjacent wall LINES are intersected to get corner points (so
///     gaps and overshoots vanish and T-junctions are trimmed, at a cost that grows with the trim but
///     has no cliff); near-parallel neighbours meet at the midpoint of the gap. Gaps wider than `snapTolerance` (up to `maxBridgeableGap`) between wall
///     ends nothing else touches are bridged with a `.virtual` wall. Interior partial walls that
///     cannot belong to the loop are dropped with a warning. Angles are never snapped, so an
///     out-of-square corner stays out of square. The exact floor polygon, when the capture has one,
///     is the arbiter: loops that disagree with it are penalised, and a loop that had to be repaired
///     (bridged, or leaving real wall outside it) and still covers less than `minFloorOverlap` of
///     the floor is rejected. Loops that leave most of the scanned wall outside them are rejected
///     too (`maxOutsideWallFraction`).
///  4. **Fallbacks.** If no acceptable loop exists: the floor surface polygon, else the convex hull
///     of wall end points, always with a loud `.noClosedLoop` warning (critical).
///  5. **Openings and objects**, see `RoomReconstructor+Openings.swift`.
///
/// Curved walls: a surface with `isCurved` set must describe its straight CHORD (transform centre and
/// `dimensions.x` = chord length). The builder stores the chord and flags `Wall.isCurved`; the arc
/// length is never used. (The app's `CapturedRoom` converter is responsible for providing the chord.)
///
/// Merged walls: when several surfaces become one wall, the wall takes the id of its longest piece
/// and the length-weighted mean of the pieces' heights.
///
/// Determinism: the result does not depend on the order or orientation of the input surfaces.
/// Wall, opening and object identifiers are the RoomPlan surface identifiers (a merged wall takes
/// the identifier of its longest piece; virtual walls get an identifier derived from their
/// neighbours), the room identifier is the capture identifier, and the loop starts at its
/// lowest-then-leftmost corner. Time is injected via `now`; nothing ambient is read.
///
/// Honesty: the builder may be uncertain but it is never silently wrong. A result whose outline is a
/// fallback guess, or whose area disagrees grossly with the scanned floor, carries a CRITICAL warning;
/// `Result.isReliable` is false for it, and caution-or-worse warnings are copied into `Room.notes` so
/// the exports carry them.
///
/// All lengths are metres. The result never contains NaN or infinity, whatever the input.
public enum RoomReconstructor {

    // MARK: Options

    /// Tolerances for the builder. All lengths in metres.
    public struct Options: Hashable, Sendable {
        /// Largest corner gap healed by extending wall lines to meet (and largest gap between
        /// collinear pieces merged into one wall). Larger gaps become `.virtual` bridge walls.
        public var snapTolerance: Double
        /// Largest open-plan gap (between two wall ends nothing else touches) that is bridged with
        /// a `.virtual` wall.
        public var maxBridgeableGap: Double
        /// A wall that continues past the corner (walls crossing, or a T-junction) is trimmed at
        /// the intersection of the two wall lines. Up to this much of the overshoot is charged at
        /// the full repair rate; the excess is charged like any other wall left out. (It is a cost
        /// threshold, not a cliff: a wall running 3 m past a corner is still trimmed.)
        public var maxCornerOvershoot: Double
        /// Wall surfaces shorter than this (in plan) are noise and ignored.
        public var minWallLength: Double
        /// Walls whose directions differ by less than this are parallel: merged when they lie on
        /// one line, joined at the midpoint of the gap when they only meet end to end.
        public var collinearToleranceDegrees: Double
        /// Largest perpendicular offset between two pieces that still count as one wall.
        public var collinearOffsetTolerance: Double
        /// A wall surface whose along-vector has a horizontal component smaller than this
        /// (fraction of its length) is nearly vertical and ignored.
        public var minHorizontalComponent: Double
        /// An opening farther than this from every wall is left unattached (`wallID == nil`).
        public var openingMatchDistance: Double
        /// A `parentID` is trusted only while the opening is within this distance of that wall AND that wall
        /// is (within 5 cm) also the nearest wall: RoomPlan's parent is a hint, the geometry has the last word.
        public var openingParentTrustDistance: Double
        /// Floor polygon area and outline area may differ by this fraction before a warning.
        public var floorAreaTolerance: Double
        /// Outline areas outside `[minPlausibleArea, maxPlausibleArea]` m² get a warning.
        public var minPlausibleArea: Double
        public var maxPlausibleArea: Double
        /// Upper bound on loop-search steps (edges examined; keeps hostile input from running away).
        public var searchBudget: Int
        /// A loop that needed repair (a bridge, or real wall left outside it) must cover at least this
        /// fraction (intersection over union) of the exact floor polygon, else it is rejected.
        public var minFloorOverlap: Double
        /// A loop is rejected when more than this fraction of all scanned wall length lies outside it.
        public var maxOutsideWallFraction: Double
        /// Without an exact floor polygon, an outline that bridges an open side while at least this much wall
        /// (metres) lies outside it is flagged critical: part of the room is probably missing.
        public var unverifiedOutsideWallLength: Double

        public init(snapTolerance: Double = 0.15, maxBridgeableGap: Double = 6.5,
                    maxCornerOvershoot: Double = 1.0, minWallLength: Double = 0.10,
                    collinearToleranceDegrees: Double = 2.0, collinearOffsetTolerance: Double = 0.05,
                    minHorizontalComponent: Double = 0.15, openingMatchDistance: Double = 0.4,
                    openingParentTrustDistance: Double = 1.0, floorAreaTolerance: Double = 0.15,
                    minPlausibleArea: Double = 1.0, maxPlausibleArea: Double = 400.0,
                    searchBudget: Int = 100_000, minFloorOverlap: Double = 0.70,
                    maxOutsideWallFraction: Double = 0.5, unverifiedOutsideWallLength: Double = 1.0) {
            self.snapTolerance = snapTolerance
            self.maxBridgeableGap = maxBridgeableGap
            self.maxCornerOvershoot = maxCornerOvershoot
            self.minWallLength = minWallLength
            self.collinearToleranceDegrees = collinearToleranceDegrees
            self.collinearOffsetTolerance = collinearOffsetTolerance
            self.minHorizontalComponent = minHorizontalComponent
            self.openingMatchDistance = openingMatchDistance
            self.openingParentTrustDistance = openingParentTrustDistance
            self.floorAreaTolerance = floorAreaTolerance
            self.minPlausibleArea = minPlausibleArea
            self.maxPlausibleArea = maxPlausibleArea
            self.searchBudget = searchBudget
            self.minFloorOverlap = minFloorOverlap
            self.maxOutsideWallFraction = maxOutsideWallFraction
            self.unverifiedOutsideWallLength = unverifiedOutsideWallLength
        }

        public static let standard = Options()
    }

    // MARK: Warnings

    /// What the builder had to do that a person should know about.
    public enum BuildWarning: Hashable, Sendable {
        public enum Severity: Int, Comparable, Sendable {
            /// Routine clean-up, nothing to act on.
            case info = 0
            /// Something was assumed, repaired or dropped: worth a look.
            case caution = 1
            /// The result is a guess or unusable: tell the user loudly.
            case critical = 2
            public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        }

        public enum LoopFallback: String, Hashable, Sendable {
            case floorPolygon, convexHull
        }

        /// No usable wall surface (and no floor polygon) in the capture.
        case noWallSurfaces
        /// Wall surfaces exist but too few to form any outline.
        case tooFewWalls(count: Int)
        /// Surfaces with non-finite numbers or non-positive size were ignored.
        case invalidSurfacesIgnored(count: Int)
        /// Wall surfaces shorter than `minLength` were treated as noise.
        case shortWallsIgnored(count: Int, minLength: Double)
        /// Wall surfaces with a (nearly) vertical along-vector were ignored.
        case steepWallsIgnored(count: Int)
        /// `pieces` surfaces that lie on one line were merged into `walls` walls.
        case collinearWallsMerged(pieces: Int, walls: Int)
        /// Walls inside the room that do not belong to the boundary loop (partitions, bulkheads, half walls).
        case interiorWallsDropped(count: Int, totalLength: Double)
        /// Wall pieces that lie outside the room outline (a neighbour's wall seen through a window or door,
        /// an exterior stub) and were ignored.
        case wallsOutsideRoomIgnored(count: Int, totalLength: Double)
        /// An open side was closed with a virtual wall while `length` metres of scanned wall lie outside the
        /// resulting outline, and no floor shape exists to check it: part of the room is probably missing.
        case bridgedOutlineLeavesWallOutside(length: Double)
        /// An open-plan boundary with no wall was closed with a virtual wall.
        case openBoundaryBridged(length: Double, at: Point2)
        /// A hole between two collinear pieces of one scanned wall was closed with a straight virtual wall.
        case scannedWallHoleBridged(length: Double, at: Point2)
        /// Corners needed noteworthy repair: gaps closed by extending walls, overshoots trimmed.
        case cornersAdjusted(gapsClosed: Int, maxGap: Double, wallsTrimmed: Int, maxTrim: Double)
        /// Curved wall surfaces are stored as their chord.
        case curvedWallsStoredAsChords(count: Int)
        /// RoomPlan itself was unsure about these boundary walls; verify them with a laser first.
        case lowConfidenceWalls(count: Int)
        /// The loop search hit its step budget; the best loop found so far was used.
        case searchBudgetExhausted
        /// No closed boundary loop could be formed; the outline is a fallback guess.
        case noClosedLoop(fallback: LoopFallback)
        /// The floor surface polygon and the wall outline disagree on the room area.
        case floorAreaMismatch(floorArea: Double, outlineArea: Double)
        /// The outline crosses itself.
        case selfIntersectingOutline
        /// The outline area is implausible for a room.
        case roomAreaOutOfRange(area: Double)
        /// The capture has no floor surface.
        case missingFloorSurface
        /// An opening could not be attached to any wall.
        case openingUnmatched(id: UUID, kind: OpeningKind, nearestDistance: Double?)
        /// An opening was moved along its wall by `movedBy` metres and/or narrowed by `narrowedBy` metres to fit
        /// inside it (routine below 5 cm, a caution above).
        case openingAdjusted(id: UUID, kind: OpeningKind, movedBy: Double = 0, narrowedBy: Double = 0)
        /// Door / window / opening surfaces with bad numbers were ignored.
        case invalidOpeningsIgnored(count: Int)
        /// Objects with bad numbers were ignored.
        case invalidObjectsIgnored(count: Int)

        /// A floor/outline area disagreement beyond this fraction is critical (between `floorAreaTolerance`
        /// and this it is a caution).
        public static let criticalFloorMismatch = 0.40
        /// An opening moved or narrowed by more than this (metres) is a caution rather than routine clean-up.
        public static let notableOpeningAdjustment = 0.10

        public var severity: Severity {
            switch self {
            case .noWallSurfaces, .tooFewWalls, .noClosedLoop, .selfIntersectingOutline,
                 .bridgedOutlineLeavesWallOutside: return .critical
            case .floorAreaMismatch(let floor, let outline):
                guard outline > 1e-9 else { return .critical }
                return abs(floor - outline) / outline > BuildWarning.criticalFloorMismatch ? .critical : .caution
            case .openingAdjusted(_, _, let moved, let narrowed):
                return max(moved, narrowed) > BuildWarning.notableOpeningAdjustment ? .caution : .info
            case .invalidSurfacesIgnored, .interiorWallsDropped, .wallsOutsideRoomIgnored, .openBoundaryBridged,
                 .scannedWallHoleBridged, .cornersAdjusted, .searchBudgetExhausted, .roomAreaOutOfRange,
                 .openingUnmatched, .lowConfidenceWalls:
                return .caution
            case .shortWallsIgnored, .steepWallsIgnored, .collinearWallsMerged, .curvedWallsStoredAsChords,
                 .missingFloorSurface, .invalidOpeningsIgnored, .invalidObjectsIgnored:
                return .info
            }
        }

        /// Human-readable text for the scan summary screen.
        public var message: String {
            /// Two decimals, never "-0.00".
            func m(_ v: Double) -> String {
                let t = String(format: "%.2f", v)
                return t == "-0.00" ? "0.00" : t
            }
            func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }
            switch self {
            case .noWallSurfaces:
                return "No usable wall surfaces were captured, so no room outline could be built. Rescan the room."
            case .tooFewWalls(let n):
                return "Only \(n) usable wall \(plural(n, "surface was", "surfaces were")) captured; a room needs at least three walls. Rescan the room."
            case .invalidSurfacesIgnored(let n):
                return "\(n) scanned \(plural(n, "surface", "surfaces")) with invalid size or position \(plural(n, "was", "were")) ignored."
            case .shortWallsIgnored(let n, let minLength):
                return "\(n) wall \(plural(n, "piece", "pieces")) shorter than \(m(minLength)) m \(plural(n, "was", "were")) ignored as noise."
            case .steepWallsIgnored(let n):
                return "\(n) near-vertical wall \(plural(n, "surface was", "surfaces were")) ignored."
            case .collinearWallsMerged(let pieces, let walls):
                return "\(pieces) wall pieces on the same line were merged into \(walls) \(plural(walls, "wall", "walls"))."
            case .interiorWallsDropped(let n, let total):
                return "\(n) interior \(plural(n, "wall", "walls")) (\(m(total)) m in total) not part of the room boundary \(plural(n, "was", "were")) left out: partition, bulkhead or half wall."
            case .wallsOutsideRoomIgnored(let n, let total):
                return "\(n) wall \(plural(n, "piece", "pieces")) (\(m(total)) m in total) lying outside the room outline \(plural(n, "was", "were")) ignored: probably a neighbouring room or the outside seen through an opening."
            case .bridgedOutlineLeavesWallOutside(let length):
                return "An open side was closed with a virtual wall, but \(m(length)) m of scanned wall lies outside the resulting outline and there is no floor shape to check it against. Part of the room is probably missing from the outline. Rescan this room."
            case .openBoundaryBridged(let length, let p):
                return "No wall was scanned along a \(m(length)) m side near (\(m(p.x)), \(m(p.y))). It was closed with a virtual wall (open-plan boundary); check it on site."
            case .scannedWallHoleBridged(let length, let p):
                return "There is a \(m(length)) m hole in a scanned wall near (\(m(p.x)), \(m(p.y))). It was closed with a straight virtual wall; check it on site."
            case .cornersAdjusted(let gaps, let maxGap, let trimmed, let maxTrim):
                var parts: [String] = []
                if gaps > 0 { parts.append("\(gaps) corner \(plural(gaps, "gap", "gaps")) closed (up to \(m(maxGap)) m)") }
                if trimmed > 0 { parts.append("\(trimmed) \(plural(trimmed, "wall", "walls")) trimmed where \(plural(trimmed, "it", "they")) ran past a corner (up to \(m(maxTrim)) m)") }
                return "Corner repair: " + parts.joined(separator: ", ") + ". Wall lengths are measured between the repaired corners."
            case .curvedWallsStoredAsChords(let n):
                return "\(n) curved \(plural(n, "wall is", "walls are")) stored as a straight chord; arc length is not measured."
            case .lowConfidenceWalls(let n):
                return "RoomPlan was unsure about \(n) \(plural(n, "wall", "walls")) of this room. Check \(plural(n, "its", "their")) length with a laser before cutting to \(plural(n, "it", "them"))."
            case .searchBudgetExhausted:
                return "The wall layout was too complicated to analyse fully; the best outline found was used."
            case .noClosedLoop(let fallback):
                switch fallback {
                case .floorPolygon:
                    return "The walls do not form a closed room. The outline was taken from the scanned floor shape instead; wall lengths are NOT reliable. Rescan this room."
                case .convexHull:
                    return "The walls do not form a closed room and there is no floor shape. The outline is the convex hull of the wall ends, a rough guess. Rescan this room."
                }
            case .floorAreaMismatch(let floor, let outline):
                let pct = outline > 1e-9 ? String(format: "%.0f", abs(floor - outline) / outline * 100) : "100+"
                return "The scanned floor area (\(m(floor)) m\u{00B2}) and the wall outline area (\(m(outline)) m\u{00B2}) disagree by \(pct) %. Check the walls."
            case .selfIntersectingOutline:
                return "The room outline crosses itself. The walls were probably mis-detected; rescan this room."
            case .roomAreaOutOfRange(let area):
                return "The room area (\(m(area)) m\u{00B2}) is implausible for a single room. Check the scan."
            case .missingFloorSurface:
                return "No floor surface was captured; the floor level was estimated from the lowest wall edge."
            case .openingUnmatched(_, let kind, let distance):
                if let d = distance {
                    return "A \(kind.displayName.lowercased()) is \(m(d)) m from the nearest wall and was not attached to any wall."
                }
                return "A \(kind.displayName.lowercased()) could not be attached to any wall (the room has no walls)."
            case .openingAdjusted(_, let kind, let moved, let narrowed):
                let name = kind.displayName.lowercased()
                var parts: [String] = []
                if moved > 0.005 { parts.append("moved \(m(moved)) m along its wall") }
                if narrowed > 0.005 { parts.append("narrowed by \(m(narrowed)) m") }
                if parts.isEmpty { return "A \(name) overhung the end of its wall and was adjusted to fit." }
                return "A \(name) overhung the end of its wall and was " + parts.joined(separator: " and ") + " to fit. Check its size and position."
            case .invalidOpeningsIgnored(let n):
                return "\(n) door/window \(plural(n, "surface", "surfaces")) with invalid size or position \(plural(n, "was", "were")) ignored."
            case .invalidObjectsIgnored(let n):
                return "\(n) scanned \(plural(n, "object", "objects")) with invalid size or position \(plural(n, "was", "were")) ignored."
            }
        }
    }

    // MARK: Result

    /// Where the room outline came from.
    public enum OutlineSource: String, Hashable, Sendable {
        /// A closed loop of scanned walls (with virtual walls over the open sides): the normal case.
        case walls
        /// No acceptable wall loop; the outline is the scanned floor shape. Wall lengths are NOT reliable.
        case floorPolygon
        /// No wall loop and no floor shape; the outline is the convex hull of the wall ends, a rough guess.
        case convexHull
        /// There is no outline at all (`Result.room.walls` is empty).
        case none
    }

    public struct Result: Hashable, Sendable {
        public var room: Room
        /// Everything the builder repaired, dropped or doubted, most severe first (stable within a severity).
        public var warnings: [BuildWarning]
        /// RoomPlan wall surface id -> id of the `Wall` it ended up in. A merged wall has several
        /// entries pointing at one wall; dropped (interior / noise) surfaces are absent.
        public var surfaceToWall: [UUID: UUID]
        /// Where the outline came from. Only `.walls` outlines carry measured wall lengths.
        public var outlineSource: OutlineSource

        public init(room: Room, warnings: [BuildWarning], surfaceToWall: [UUID: UUID],
                    outlineSource: OutlineSource = .walls) {
            self.room = room
            self.warnings = warnings
            self.surfaceToWall = surfaceToWall
            self.outlineSource = outlineSource
        }

        /// Worst severity among the warnings, nil when there are none.
        public var worstSeverity: BuildWarning.Severity? { warnings.map(\.severity).max() }

        /// The room has an outline (at least three walls). False means there is nothing to name or save.
        public var isUsable: Bool { room.walls.count >= 3 }

        /// The outline was built from scanned walls and nothing critical was found. A reliable result can
        /// still carry cautions (an open-plan side, a repaired corner); see `reviewMessages`.
        public var isReliable: Bool { isUsable && outlineSource == .walls && worstSeverity != .critical }

        /// Messages of every caution-or-worse warning, most severe first. These are also written to
        /// `room.notes`.
        public var reviewMessages: [String] {
            warnings.filter { $0.severity >= .caution }.map(\.message)
        }
    }

    // MARK: Build

    /// Build a `Room` from a RoomPlan capture. Never traps; garbage input gives a room with no
    /// walls and a warning.
    public static func build(from capture: RawCapture, name: String, kind: RoomKind = .other,
                             options: Options = .standard, now: Date = Date()) -> Result {
        var warnings: [BuildWarning] = []

        // 1. Wall segments.
        let extraction = extractSegments(from: capture.walls, options: options)
        if extraction.invalid > 0 { warnings.append(.invalidSurfacesIgnored(count: extraction.invalid)) }
        if extraction.short > 0 {
            warnings.append(.shortWallsIgnored(count: extraction.short, minLength: options.minWallLength))
        }
        if extraction.steep > 0 { warnings.append(.steepWallsIgnored(count: extraction.steep)) }

        // 2. Merge collinear pieces.
        let merge = mergeCollinear(extraction.segments, options: options)
        let segments = merge.segments
        if merge.piecesMerged > 0 {
            warnings.append(.collinearWallsMerged(pieces: merge.piecesMerged, walls: merge.wallsFormed))
        }

        let floors = extractFloors(capture.floors)
        let exactFloors = floors.filter { $0.isExact }.compactMap { $0.polygon }

        // 3. Boundary loop, with fallbacks.
        var loopWalls: [LoopWall] = []
        var outlineSource = OutlineSource.none
        if !segments.isEmpty || floors.contains(where: { $0.polygon != nil }) {
            let search = findLoop(segments: segments, floors: exactFloors, options: options)
            if search.budgetExhausted { warnings.append(.searchBudgetExhausted) }
            if let outcome = search.outcome {
                loopWalls = outcome.walls
                outlineSource = .walls
                if outcome.gapsClosed > 0 || outcome.wallsTrimmed > 0 {
                    warnings.append(.cornersAdjusted(gapsClosed: outcome.gapsClosed, maxGap: outcome.maxGap,
                                                     wallsTrimmed: outcome.wallsTrimmed, maxTrim: outcome.maxTrim))
                }
                let outside = Set(outcome.droppedOutside)
                let inside = outcome.droppedSegments.filter { !outside.contains($0) }
                if !inside.isEmpty {
                    let total = inside.reduce(0.0) { $0 + segments[$1].length }
                    warnings.append(.interiorWallsDropped(count: inside.count, totalLength: total))
                }
                if !outside.isEmpty {
                    let total = outside.reduce(0.0) { $0 + segments[$1].length }
                    warnings.append(.wallsOutsideRoomIgnored(count: outside.count, totalLength: total))
                    // An inferred (bridged) side with real wall left outside, and no floor to arbitrate: a guess.
                    if exactFloors.isEmpty, outcome.bridges > 0, total >= options.unverifiedOutsideWallLength {
                        warnings.append(.bridgedOutlineLeavesWallOutside(length: total))
                    }
                }
                for (k, w) in loopWalls.enumerated() where w.segment == nil {
                    let length = w.start.distance(to: w.end), at = w.start.lerp(to: w.end, t: 0.5)
                    warnings.append(isHoleInOneWall(loopWalls, at: k) ? .scannedWallHoleBridged(length: length, at: at)
                                                                      : .openBoundaryBridged(length: length, at: at))
                }
            } else if let fb = fallbackOutline(segments: segments, floors: floors, options: options) {
                loopWalls = fb.walls
                outlineSource = fb.kind == .floorPolygon ? .floorPolygon : .convexHull
                warnings.append(.noClosedLoop(fallback: fb.kind))
            } else {
                warnings.append(segments.isEmpty ? .noWallSurfaces : .tooFewWalls(count: segments.count))
            }
        } else {
            warnings.append(.noWallSurfaces)
        }
        // Last line of defence: an outline with a non-finite corner can never be stored (JSON refuses it).
        if !loopWalls.allSatisfy({ $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite
                                    && abs($0.start.x) < 1e7 && abs($0.start.y) < 1e7 && abs($0.end.x) < 1e7 && abs($0.end.y) < 1e7 }) {
            loopWalls = []
            outlineSource = .none
            warnings.append(.noWallSurfaces)
        }

        // 4. Assemble walls. Ceiling height = median height of the solid boundary walls.
        let solidSegmentHeights = loopWalls.compactMap { $0.segment.map { segments[$0].height } }
        var ceiling = median(solidSegmentHeights) ?? median(segments.map(\.height)) ?? 0
        if !ceiling.isFinite || ceiling < 0 { ceiling = 0 }
        let assembled = assembleWalls(loopWalls: loopWalls, segments: segments, ceiling: ceiling,
                                      captureID: capture.id)
        let wallsWithHeights = assembled.walls

        let curvedCount = wallsWithHeights.filter { $0.isCurved }.count
        if curvedCount > 0 { warnings.append(.curvedWallsStoredAsChords(count: curvedCount)) }
        let lowConfidence = loopWalls.filter { $0.segment.map { segments[$0].lowConfidence } ?? false }.count
        if lowConfidence > 0 { warnings.append(.lowConfidenceWalls(count: lowConfidence)) }

        // Floor level: the floor surface, else the lowest wall bottom.
        let floorElevation: Double
        if let lowest = floors.map(\.elevation).min() {
            floorElevation = lowest
        } else {
            let used = loopWalls.compactMap { $0.segment.map { segments[$0].bottom } }
            floorElevation = used.min() ?? segments.map(\.bottom).min() ?? 0
        }

        // 5. Openings and objects.
        let openingResult = buildOpenings(capture: capture, walls: wallsWithHeights,
                                          surfaceToWall: assembled.surfaceToWall,
                                          floorElevation: floorElevation, options: options)
        warnings.append(contentsOf: openingResult.warnings)
        let objectResult = buildObjects(capture.objects, floorElevation: floorElevation)
        warnings.append(contentsOf: objectResult.warnings)

        var room = Room(id: capture.id, name: name, kind: kind, walls: wallsWithHeights,
                        ceilingHeight: Measured(scanned: ceiling), openings: openingResult.openings,
                        objects: objectResult.objects, floorElevation: floorElevation, scannedAt: now)

        // 6. Sanity checks.
        warnings.append(contentsOf: sanityWarnings(room: room, floors: floors, options: options))

        // Most severe first (stable), and the review messages travel with the room into every export.
        warnings = warnings.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
        room.notes = reviewNotes(for: warnings)

        return Result(room: room, warnings: warnings, surfaceToWall: assembled.surfaceToWall, outlineSource: outlineSource)
    }

    /// One line per caution-or-worse warning, most severe first.
    static func reviewNotes(for warnings: [BuildWarning]) -> String {
        warnings.filter { $0.severity >= .caution }.map { w in
            "SCAN CHECK (\(w.severity == .critical ? "critical" : "caution")): \(w.message)"
        }.joined(separator: "\n")
    }

    /// Is the virtual wall `k` a short straight hole between two collinear pieces of one scanned wall (rather
    /// than a missing side)? Both neighbours must be solid and run (within 5 degrees) along the bridge.
    static func isHoleInOneWall(_ walls: [LoopWall], at k: Int) -> Bool {
        let n = walls.count
        guard n >= 3, walls[k].segment == nil else { return false }
        let prev = walls[(k + n - 1) % n], next = walls[(k + 1) % n]
        guard prev.segment != nil, next.segment != nil else { return false }
        let b = (walls[k].end - walls[k].start).normalized
        let sinTol = sin(5 * Double.pi / 180)
        for neighbour in [prev, next] {
            let d = (neighbour.end - neighbour.start).normalized
            if d.dot(b) <= 0 || abs(d.cross(b)) > sinTol { return false }
        }
        return true
    }

    // MARK: Segments

    /// A wall as a plan-space segment (after noise filtering, possibly several merged surfaces).
    struct Segment: Sendable {
        /// Identifier of the longest contributing surface; becomes the `Wall.id`.
        var id: UUID
        /// Every contributing surface id, sorted.
        var surfaceIDs: [UUID]
        var a: Point2
        var b: Point2
        var bottom: Double
        var top: Double
        var height: Double
        var isCurved: Bool
        /// RoomPlan reported low confidence for (any of) the surface(s).
        var lowConfidence: Bool = false

        var length: Double { a.distance(to: b) }
        var direction: Point2 { (b - a).normalized }
    }

    struct Extraction {
        var segments: [Segment] = []
        var invalid = 0
        var short = 0
        var steep = 0
    }

    static func extractSegments(from surfaces: [RawSurface], options: Options) -> Extraction {
        var out = Extraction()
        var seen = Set<UUID>()
        let ordered = surfaces.sorted { $0.id.uuidString < $1.id.uuidString }
        for s in ordered {
            guard isValidSurface(s) else { out.invalid += 1; continue }
            let xa = s.transform.xAxis
            let full = xa.length
            let horizontal = (xa.x * xa.x + xa.z * xa.z).squareRoot()
            guard full > 1e-9 else { out.invalid += 1; continue }
            if horizontal / full < options.minHorizontalComponent { out.steep += 1; continue }
            let dir = Point2(xa.x / horizontal, -xa.z / horizontal)
            let half = s.dimensions.x / 2 * (horizontal / full)
            if half * 2 < options.minWallLength { out.short += 1; continue }
            let c = s.transform.translation
            let centre = Point2(c.x, -c.z)
            let (a, b) = canonicalOrder(centre - dir * half, centre + dir * half)
            var id = s.id
            var n = 0
            while seen.contains(id) {
                n += 1
                id = stableUUID("dup|\(s.id.uuidString)|\(n)")
            }
            seen.insert(id)
            out.segments.append(Segment(id: id, surfaceIDs: [id], a: a, b: b,
                                        bottom: c.y - s.dimensions.y / 2, top: c.y + s.dimensions.y / 2,
                                        height: s.dimensions.y, isCurved: s.isCurved,
                                        lowConfidence: s.confidence == .low))
        }
        return out
    }

    /// Orient a segment so the result does not depend on which way RoomPlan pointed the wall.
    static func canonicalOrder(_ a: Point2, _ b: Point2) -> (Point2, Point2) {
        let d = b - a
        let flip = abs(d.x) > 1e-6 ? d.x < 0 : d.y < 0
        return flip ? (b, a) : (a, b)
    }

    static func isValidSurface(_ s: RawSurface) -> Bool {
        s.transform.columnMajor.count == 16 && s.transform.columnMajor.allSatisfy { $0.isFinite }
            && s.dimensions.x.isFinite && s.dimensions.y.isFinite && s.dimensions.z.isFinite
            && s.dimensions.x > 0 && s.dimensions.y > 0
            && abs(s.dimensions.x) < 1e6 && abs(s.dimensions.y) < 1e6
            && s.transform.columnMajor.allSatisfy { abs($0) < 1e7 }
    }

    // MARK: Floors

    struct FloorInfo {
        /// World Y of the floor surface.
        var elevation: Double
        /// Plan-space polygon, nil when the surface has no usable shape.
        var polygon: [Point2]?
        /// True when `polygon` was read from `polygonCorners` (trusted for area comparison), false
        /// when it is only the surface's bounding rectangle.
        var isExact: Bool
        var area: Double { polygon.map(Polygon.area) ?? 0 }
    }

    static func extractFloors(_ surfaces: [RawSurface]) -> [FloorInfo] {
        var out: [FloorInfo] = []
        for s in surfaces.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard s.transform.columnMajor.count == 16,
                  s.transform.columnMajor.allSatisfy({ $0.isFinite && abs($0) < 1e7 }) else { continue }
            let elevation = s.transform.translation.y
            if let corners = s.polygonCorners, corners.count >= 3,
               corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                                    && abs($0.x) < 1e6 && abs($0.y) < 1e6 && abs($0.z) < 1e6 }) {
                let plan = cleanPolygon(corners.map { s.transform.transform($0).plan })
                if plan.count >= 3, Polygon.area(plan) > 1e-6 {
                    out.append(FloorInfo(elevation: elevation, polygon: plan, isExact: true))
                    continue
                }
            }
            // No polygon: fall back to the bounding rectangle in the surface's horizontal plane.
            var rect: [Point2]?
            if s.dimensions.x.isFinite, s.dimensions.y.isFinite, s.dimensions.z.isFinite,
               abs(s.dimensions.x) < 1e6, abs(s.dimensions.y) < 1e6, abs(s.dimensions.z) < 1e6 {
                let axes = [s.transform.xAxis, s.transform.yAxis, s.transform.zAxis]
                let dims = [s.dimensions.x, s.dimensions.y, s.dimensions.z]
                if let normalIdx = (0..<3).max(by: { abs(axes[$0].y) < abs(axes[$1].y) }), abs(axes[normalIdx].y) > 0.7 {
                    let inPlane = (0..<3).filter { $0 != normalIdx }
                    let hx = dims[inPlane[0]] / 2, hy = dims[inPlane[1]] / 2
                    if hx > 0.05, hy > 0.05 {
                        let t = s.transform.translation
                        let p: (Double, Double) -> Point2 = { u, v in
                            let w = axes[inPlane[0]] * u + axes[inPlane[1]] * v + t
                            return Point2(w.x, -w.z)
                        }
                        rect = Polygon.counterClockwise([p(-hx, -hy), p(hx, -hy), p(hx, hy), p(-hx, hy)])
                    }
                }
            }
            out.append(FloorInfo(elevation: elevation, polygon: rect, isExact: false))
        }
        return out
    }

    /// Drop repeated and collinear vertices and wind counter-clockwise.
    static func cleanPolygon(_ pts: [Point2]) -> [Point2] {
        var p: [Point2] = []
        for q in pts where q.x.isFinite && q.y.isFinite {
            if let last = p.last, last.distance(to: q) < 1e-3 { continue }
            p.append(q)
        }
        if p.count > 1, p[0].distance(to: p[p.count - 1]) < 1e-3 { p.removeLast() }
        // Remove vertices that continue straight on (collinear, same direction).
        var changed = true
        while changed, p.count > 3 {
            changed = false
            for i in 0..<p.count {
                let prev = p[(i + p.count - 1) % p.count], cur = p[i], next = p[(i + 1) % p.count]
                let a = cur - prev, b = next - cur
                let la = a.length, lb = b.length
                if la > 1e-9, lb > 1e-9, abs(a.cross(b)) / (la * lb) < 1e-4, a.dot(b) > 0 {
                    p.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return p.count >= 3 ? Polygon.counterClockwise(p) : []
    }

    // MARK: Sanity checks

    static func sanityWarnings(room: Room, floors: [FloorInfo], options: Options) -> [BuildWarning] {
        var out: [BuildWarning] = []
        if floors.isEmpty { out.append(.missingFloorSurface) }
        let outline = room.outline
        guard outline.count >= 3 else { return out }
        let outlineArea = Polygon.area(outline)
        if !isSimplePolygon(outline) { out.append(.selfIntersectingOutline) }
        if outlineArea < options.minPlausibleArea || outlineArea > options.maxPlausibleArea {
            out.append(.roomAreaOutOfRange(area: outlineArea))
        }
        let exact = floors.filter { $0.isExact }
        if !exact.isEmpty, outlineArea > 1e-9 {
            let floorArea = exact.reduce(0.0) { $0 + $1.area }
            if abs(floorArea - outlineArea) / outlineArea > options.floorAreaTolerance {
                out.append(.floorAreaMismatch(floorArea: floorArea, outlineArea: outlineArea))
            }
        }
        return out
    }

    // MARK: Small shared helpers

    /// Median; the mean of the two middle values for an even count. nil when empty.
    static func median(_ values: [Double]) -> Double? {
        let v = values.filter { $0.isFinite }.sorted()
        guard !v.isEmpty else { return nil }
        let n = v.count
        return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2
    }

    /// A deterministic identifier derived from a string (FNV-1a with a final mix). The same string
    /// gives the same UUID on every platform and run.
    static func stableUUID(_ s: String) -> UUID {
        func hash(_ seed: UInt64) -> UInt64 {
            var h = seed
            for byte in s.utf8 {
                h ^= UInt64(byte)
                h = h &* 0x100000001b3
            }
            h ^= h >> 33
            h = h &* 0xff51afd7ed558ccd
            h ^= h >> 33
            h = h &* 0xc4ceb9fe1a85ec53
            h ^= h >> 33
            return h
        }
        let hi = hash(0xcbf29ce484222325), lo = hash(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((hi >> UInt64(8 * (7 - i))) & 0xff)
            bytes[8 + i] = UInt8((lo >> UInt64(8 * (7 - i))) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Polygon tests

    /// Signed twice-area of triangle (a, b, c); positive when c is left of a->b.
    @inline(__always)
    static func orient(_ a: Point2, _ b: Point2, _ c: Point2) -> Double { (b - a).cross(c - a) }

    /// Do closed segments pq and rs share any point (touching and collinear overlap included)?
    static func segmentsTouch(_ p: Point2, _ q: Point2, _ r: Point2, _ s: Point2, eps: Double = 1e-9) -> Bool {
        func onSegment(_ a: Point2, _ b: Point2, _ c: Point2) -> Bool {
            c.x >= Swift.min(a.x, b.x) - eps && c.x <= Swift.max(a.x, b.x) + eps
                && c.y >= Swift.min(a.y, b.y) - eps && c.y <= Swift.max(a.y, b.y) + eps
        }
        func sign(_ v: Double) -> Int { v > eps ? 1 : (v < -eps ? -1 : 0) }
        let o1 = sign(orient(p, q, r)), o2 = sign(orient(p, q, s))
        let o3 = sign(orient(r, s, p)), o4 = sign(orient(r, s, q))
        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p, q, r) { return true }
        if o2 == 0 && onSegment(p, q, s) { return true }
        if o3 == 0 && onSegment(r, s, p) { return true }
        if o4 == 0 && onSegment(r, s, q) { return true }
        return false
    }

    /// True when no two non-adjacent edges touch and no adjacent pair folds back on itself.
    static func isSimplePolygon(_ p: [Point2]) -> Bool {
        let n = p.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n], c = p[(i + 2) % n]
            let u = b - a, v = c - b
            let lu = u.length, lv = v.length
            if lu < 1e-9 || lv < 1e-9 { return false }
            if abs(u.cross(v)) / (lu * lv) < 1e-9, u.dot(v) < 0 { return false }   // fold-back spike
        }
        if n == 3 { return true }
        for i in 0..<n {
            for j in (i + 1)..<n {
                if j == i + 1 || (i == 0 && j == n - 1) { continue }
                if segmentsTouch(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) { return false }
            }
        }
        return true
    }
}
