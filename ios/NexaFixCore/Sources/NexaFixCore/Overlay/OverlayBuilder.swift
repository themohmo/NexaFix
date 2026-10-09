import Foundation

// Turns saved rooms into the pure-data `OverlayScene` the AR view draws on top of the camera image.
//
// Everything here is deterministic and free of Apple frameworks, so which number appears where (and
// in which state) is unit-tested off-device. Geometry uses the SCANNED coordinates, because those are
// what live in the scan session's coordinate frame; label text uses the EFFECTIVE value (the verified
// number when there is one) so a laser-checked dimension never shows its LiDAR twin.

/// How important a label is when labels fight for screen space. Higher wins.
/// Order from the brief: angles out of square > opening sizes > wall lengths > heights > area.
public enum OverlayPriority {
    public static let angleCritical = 100
    public static let angleCaution = 90
    public static let opening = 70
    public static let measurement = 60
    public static let wallLength = 50
    public static let angleSquare = 40
    public static let height = 30
    public static let area = 20
    /// Added to every label of the room the user is looking at, so it beats neighbouring rooms.
    public static let highlightBonus = 200
}

public enum OverlayBuilder {

    /// Build the overlay for `rooms`. Empty rooms give an empty scene; non-finite geometry is skipped.
    /// `highlightRoomID` changes nothing visually: it only raises the priority of that room's labels.
    public static func scene(for rooms: [Room], options: OverlayOptions, units: DisplayUnits,
                             highlightRoomID: UUID? = nil) -> OverlayScene {
        var scene = OverlayScene()
        for room in rooms {
            let writer = RoomWriter(room: room, options: options, units: units,
                                    priorityBonus: room.id == highlightRoomID ? OverlayPriority.highlightBonus : 0)
            writer.write(into: &scene)
        }
        return scene
    }

    // MARK: Shared rules (also used by tests and the UI)

    /// Colour state for a corner with the given interior angle (degrees, 0..<360).
    /// Within 1 degree of 90 is neutral, 1-3 degrees off is caution, more is critical.
    /// Reflex corners (the inside of an L-shape) and straight continuations are never flagged.
    public static func angleState(forInteriorAngle angle: Double) -> OverlayState {
        guard angle.isFinite else { return .neutral }
        if abs(angle - 180) <= RoomMetrics.straightTolerance { return .neutral }
        if angle > 180 { return .neutral }
        let off = abs(angle - 90)
        if off <= 1.0 { return .neutral }
        if off <= 3.0 { return .caution }
        return .critical
    }

    /// Length precision used on labels: compact for metres and inches, precise otherwise.
    public static func labelPrecision(for unit: LengthUnit) -> UnitPrecision {
        switch unit {
        case .metres, .inches: return .compact
        case .millimetres, .centimetres, .feetAndInches: return .precise
        }
    }

    /// A point well inside the polygon, suitable for a label. Unlike the centroid it stays inside
    /// concave outlines such as an L-shape. Returns nil for fewer than three finite vertices.
    public static func labelPoint(in polygon: [Point2]) -> Point2? {
        guard polygon.count >= 3,
              polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let bounds = Bounds2(points: polygon) else { return nil }

        func clearance(_ p: Point2) -> Double {
            guard Polygon.contains(polygon, p) else { return -1 }
            var best = Double.greatestFiniteMagnitude
            for i in polygon.indices {
                best = min(best, distance(from: p, toSegment: polygon[i], polygon[(i + 1) % polygon.count]))
            }
            return best
        }

        let centroid = Polygon.centroid(polygon)
        let centroidClearance = clearance(centroid)

        // Coarse grid, then a few halving hill-climb steps around the best cell.
        let n = 24
        var best = centroid
        var bestClearance = centroidClearance
        for iy in 0..<n {
            for ix in 0..<n {
                let p = Point2(bounds.min.x + bounds.width * (Double(ix) + 0.5) / Double(n),
                               bounds.min.y + bounds.height * (Double(iy) + 0.5) / Double(n))
                let c = clearance(p)
                if c > bestClearance + 1e-9 { best = p; bestClearance = c }
            }
        }
        var step = max(bounds.width, bounds.height) / Double(n)
        for _ in 0..<8 {
            var moved = best
            var movedClearance = bestClearance
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let p = Point2(best.x + Double(dx) * step, best.y + Double(dy) * step)
                    let c = clearance(p)
                    if c > movedClearance + 1e-9 { moved = p; movedClearance = c }
                }
            }
            best = moved
            bestClearance = movedClearance
            step /= 2
        }

        // Prefer the centroid whenever it is nearly as roomy: rectangles then label at their exact centre.
        if centroidClearance >= 0, centroidClearance >= 0.7 * bestClearance { return centroid }
        return bestClearance >= 0 ? best : centroid
    }

    static func distance(from p: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        if len2 < 1e-18 { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(ab) / len2))
        return p.distance(to: a + ab * t)
    }
}

// MARK: - Per-room writer

private enum Tuning {
    /// How far labels and dimension lines sit in front of the wall, into the room (metres).
    static let wallInset = 0.04
    static let dimensionHeight = 1.0
    static let tickHalfLength = 0.06
    static let arcRadius = 0.35
    static let arcMaxFractionOfWall = 0.4
    static let minArcRadius = 0.05
    static let arcLabelGap = 0.12
    static let arcFloorLift = 0.01
    static let angleLabelLift = 0.05
    static let areaLabelLift = 0.02
    static let fallbackHeight = 2.4
    static let minUsableWall = 1e-4
    static let minUsableOpening = 0.05
    /// A wall is only labelled with its own height when it differs from the ceiling by more than this.
    static let wallHeightDifference = 0.05
    static let minSill = 0.05
}

/// A wall whose geometry is safe to draw, with the vectors the writer needs.
private struct WallFrame {
    let wall: Wall
    let index: Int
    let start: Point2
    let direction: Point2
    let inward: Point2
    let length: Double
    /// Scanned height, validated.
    let height: Double

    /// World-space point `s` metres along the wall, `inset` metres into the room, at `elevation`.
    func point(at s: Double, inset: Double = 0, elevation: Double) -> Point3 {
        let p = start + direction * s + inward * inset
        return p.world(elevation: elevation)
    }
}

private struct RoomWriter {
    let room: Room
    let options: OverlayOptions
    let units: DisplayUnits
    let priorityBonus: Int

    private var floor: Double { room.floorElevation.isFinite ? room.floorElevation : 0 }
    private var roomID: String { room.id.uuidString }

    private var precision: UnitPrecision { OverlayBuilder.labelPrecision(for: units.length) }

    init(room: Room, options: OverlayOptions, units: DisplayUnits, priorityBonus: Int) {
        self.room = room
        self.options = options
        self.units = units
        self.priorityBonus = priorityBonus
    }

    func write(into scene: inout OverlayScene) {
        guard !room.walls.isEmpty else { return }
        let metrics = room.metrics
        let frames = makeFrames()

        for frame in frames.compactMap({ $0 }) {
            writeWall(frame, into: &scene)
        }
        if options.showWireframe { writeCornerEdges(frames, into: &scene) }
        if options.showAngles { writeAngles(metrics, into: &scene) }
        writeOpenings(frames.compactMap { $0 }, into: &scene)

        if room.walls.count >= 3, let centre = OverlayBuilder.labelPoint(in: room.outline) {
            if options.showHeights { writeCeiling(at: centre, into: &scene) }
            if options.showArea { writeArea(at: centre, metrics: metrics, into: &scene) }
        }
        if options.showDimensions { writeCustomMeasurements(into: &scene) }
    }

    // MARK: Walls

    private func makeFrames() -> [WallFrame?] {
        let ceiling = room.ceilingHeight.scanned
        let fallback = (ceiling.isFinite && ceiling > 0.05) ? ceiling : Tuning.fallbackHeight
        let counterClockwise = Polygon.isCounterClockwise(room.outline)
        return room.walls.enumerated().map { index, wall -> WallFrame? in
            guard wall.start.x.isFinite, wall.start.y.isFinite, wall.end.x.isFinite, wall.end.y.isFinite else { return nil }
            let length = wall.start.distance(to: wall.end)
            guard length.isFinite, length > Tuning.minUsableWall else { return nil }
            let direction = wall.direction
            let normal = counterClockwise ? wall.inwardNormal : -wall.inwardNormal
            let h = wall.height.scanned
            let height = (h.isFinite && h > 0.05) ? h : fallback
            return WallFrame(wall: wall, index: index, start: wall.start, direction: direction,
                             inward: normal, length: length, height: height)
        }
    }

    private func lengthText(_ metres: Double) -> String {
        UnitFormatter.length(metres, unit: units.length, precision: precision)
    }

    /// The line under a number: who verified it, or how far a scan can be out.
    private func provenance(of value: Measured) -> String {
        if let v = value.verification { return v.source.displayName }
        return UnitFormatter.tolerance(forLength: value.scanned, unit: units.length)
    }

    private func verificationState(_ value: Measured) -> OverlayState { value.isVerified ? .verified : .scanned }

    private func writeWall(_ f: WallFrame, into scene: inout OverlayScene) {
        let w = f.wall
        let wid = w.id.uuidString
        let isSolid = w.kind == .solid
        let a = f.point(at: 0, elevation: floor)
        let b = f.point(at: f.length, elevation: floor)

        if options.showWireframe {
            scene.segments.append(OverlaySegment(id: "wall:\(wid):base", kind: .wallBase, a: a, b: b))
            if isSolid {
                scene.segments.append(OverlaySegment(id: "wall:\(wid):top", kind: .wallTop,
                                                     a: f.point(at: 0, elevation: floor + f.height),
                                                     b: f.point(at: f.length, elevation: floor + f.height)))
            }
        }

        if options.showDimensions {
            let y = floor + min(Tuning.dimensionHeight, f.height * 0.5)
            let tick = Tuning.tickHalfLength
            let state = verificationState(w.length)
            let p0 = f.point(at: 0, inset: Tuning.wallInset, elevation: y)
            let p1 = f.point(at: f.length, inset: Tuning.wallInset, elevation: y)
            scene.segments.append(OverlaySegment(id: "wall:\(wid):dim", kind: .dimension, a: p0, b: p1, state: state))
            scene.segments.append(OverlaySegment(id: "wall:\(wid):dim:t0", kind: .dimension,
                                                 a: f.point(at: 0, inset: Tuning.wallInset, elevation: y - tick),
                                                 b: f.point(at: 0, inset: Tuning.wallInset, elevation: y + tick), state: state))
            scene.segments.append(OverlaySegment(id: "wall:\(wid):dim:t1", kind: .dimension,
                                                 a: f.point(at: f.length, inset: Tuning.wallInset, elevation: y - tick),
                                                 b: f.point(at: f.length, inset: Tuning.wallInset, elevation: y + tick), state: state))

            let value = w.length.value
            if value.isFinite {
                scene.labels.append(OverlayLabel(
                    id: "wall:\(wid):length", kind: .wallLength,
                    position: f.point(at: f.length / 2, inset: Tuning.wallInset, elevation: floor + f.height / 2),
                    title: lengthText(value), subtitle: provenance(of: w.length), state: state,
                    priority: OverlayPriority.wallLength + priorityBonus, roomID: room.id, targetID: wid))
            }
        }

        if options.showHeights, isSolid {
            let effective = w.height.value
            let ceiling = room.ceilingHeight.value
            if effective.isFinite, ceiling.isFinite, abs(effective - ceiling) > Tuning.wallHeightDifference {
                scene.labels.append(OverlayLabel(
                    id: "wall:\(wid):height", kind: .wallHeight,
                    position: f.point(at: f.length / 2, inset: Tuning.wallInset, elevation: floor + f.height * 0.85),
                    title: "Height " + lengthText(effective), subtitle: provenance(of: w.height),
                    state: verificationState(w.height), priority: OverlayPriority.height + priorityBonus,
                    roomID: room.id, targetID: wid))
            }
        }
    }

    /// Vertical edge at each corner, as tall as the shorter of the two walls that meet there.
    private func writeCornerEdges(_ frames: [WallFrame?], into scene: inout OverlayScene) {
        let n = frames.count
        for i in 0..<n {
            let current = frames[i]
            let previous = frames[(i + n - 1) % n]
            guard let corner = current ?? previous else { continue }
            let solidHere = current?.wall.kind == .solid
            let solidBefore = previous?.wall.kind == .solid
            guard solidHere || solidBefore else { continue }
            var heights: [Double] = []
            if let c = current, solidHere { heights.append(c.height) }
            if let p = previous, solidBefore { heights.append(p.height) }
            guard let top = heights.min() else { continue }
            let at = current != nil ? corner.start : corner.start + corner.direction * corner.length
            scene.segments.append(OverlaySegment(
                id: "corner:\(roomID):\(i):edge", kind: .wallCorner,
                a: at.world(elevation: floor), b: at.world(elevation: floor + top)))
        }
    }

    // MARK: Corner angles

    private func writeAngles(_ metrics: RoomMetrics, into scene: inout OverlayScene) {
        let outline = room.outline
        let n = outline.count
        guard n >= 3 else { return }
        let counterClockwise = Polygon.isCounterClockwise(outline)

        for corner in metrics.corners where !corner.isStraight {
            let i = corner.index
            let here = outline[i]
            let toNext = outline[(i + 1) % n] - here
            let toPrev = outline[(i + n - 1) % n] - here
            let lenNext = toNext.length, lenPrev = toPrev.length
            guard here.x.isFinite, here.y.isFinite, lenNext.isFinite, lenPrev.isFinite,
                  lenNext > Tuning.minUsableWall, lenPrev > Tuning.minUsableWall,
                  corner.interiorAngle.isFinite else { continue }

            let radius = min(Tuning.arcRadius, Tuning.arcMaxFractionOfWall * min(lenNext, lenPrev))
            guard radius >= Tuning.minArcRadius else { continue }

            // The interior wedge opens counter-clockwise from the first wall direction.
            let startVector = counterClockwise ? toNext : toPrev
            var start = startVector.angle * 180 / Double.pi
            start = start.truncatingRemainder(dividingBy: 360)
            if start < 0 { start += 360 }
            let sweep = corner.interiorAngle
            let state = OverlayBuilder.angleState(forInteriorAngle: sweep)

            scene.arcs.append(OverlayArc(
                id: "corner:\(roomID):\(i):arc", center: here.world(elevation: floor + Tuning.arcFloorLift),
                radius: radius, startAngle: start, sweep: sweep, state: state))

            let mid = (start + sweep / 2) * Double.pi / 180
            let labelRadius = radius + Tuning.arcLabelGap
            let labelPlan = here + Point2(cos(mid), sin(mid)) * labelRadius
            let priority: Int
            switch state {
            case .critical: priority = OverlayPriority.angleCritical
            case .caution: priority = OverlayPriority.angleCaution
            default: priority = OverlayPriority.angleSquare
            }
            scene.labels.append(OverlayLabel(
                id: "corner:\(roomID):\(i):angle", kind: .angle,
                position: labelPlan.world(elevation: floor + Tuning.angleLabelLift),
                title: UnitFormatter.angle(sweep), subtitle: state == .neutral ? nil : "out of square",
                state: state, priority: priority + priorityBonus, roomID: room.id,
                targetID: "\(roomID):\(i)"))
        }
    }

    // MARK: Openings

    private func writeOpenings(_ frames: [WallFrame], into scene: inout OverlayScene) {
        guard options.showOpenings else { return }
        for opening in room.openings {
            guard let wallID = opening.wallID,
                  let frame = frames.first(where: { $0.wall.id == wallID }) else { continue }
            let width = opening.width.scanned, height = opening.height.scanned
            let offset = opening.offsetFromWallStart, sill = opening.sillHeight.scanned
            guard width.isFinite, height.isFinite, offset.isFinite, sill.isFinite,
                  width >= Tuning.minUsableOpening, height >= Tuning.minUsableOpening else { continue }

            let oid = opening.id.uuidString
            if options.showWireframe {
                let y0 = floor + max(0, sill), y1 = floor + max(0, sill) + height
                let p0 = frame.point(at: offset, elevation: 0)
                let p1 = frame.point(at: offset + width, elevation: 0)
                func edge(_ suffix: String, _ a: Point3, _ b: Point3) {
                    scene.segments.append(OverlaySegment(id: "opening:\(oid):\(suffix)", kind: .openingEdge, a: a, b: b))
                }
                func at(_ p: Point3, _ y: Double) -> Point3 { Point3(p.x, y, p.z) }
                if sill >= 0.01 { edge("bottom", at(p0, y0), at(p1, y0)) }
                edge("top", at(p0, y1), at(p1, y1))
                edge("left", at(p0, y0), at(p0, y1))
                edge("right", at(p1, y0), at(p1, y1))
            }

            let effectiveWidth = opening.width.value, effectiveHeight = opening.height.value
            let effectiveSill = opening.sillHeight.value
            guard effectiveWidth.isFinite, effectiveHeight.isFinite, effectiveSill.isFinite else { continue }
            scene.labels.append(OverlayLabel(
                id: "opening:\(oid):size", kind: .opening,
                position: frame.point(at: offset + width / 2, inset: Tuning.wallInset,
                                      elevation: floor + max(0, sill) + height / 2),
                title: openingTitle(opening, width: effectiveWidth, height: effectiveHeight, sill: effectiveSill),
                subtitle: openingSubtitle(opening), state: openingState(opening),
                priority: OverlayPriority.opening + priorityBonus, roomID: room.id, targetID: oid))
        }
    }

    private func openingState(_ o: Opening) -> OverlayState {
        o.width.isVerified && o.height.isVerified ? .verified : .scanned
    }

    private func openingSubtitle(_ o: Opening) -> String? {
        switch (o.width.verification, o.height.verification) {
        case let (w?, h?): return w.source == h.source ? w.source.displayName : "Checked"
        case (.some, nil): return "Width checked"
        case (nil, .some): return "Height checked"
        case (nil, nil): return nil
        }
    }

    private func openingTitle(_ o: Opening, width: Double, height: Double, sill: Double) -> String {
        let letter: String
        switch o.kind {
        case .door: letter = "D"
        case .window: letter = "W"
        case .opening: letter = "O"
        }
        func number(_ m: Double) -> String {
            UnitFormatter.length(m, unit: units.length, precision: precision, includeUnit: false)
        }
        let suffix: String
        switch units.length {
        case .millimetres, .feetAndInches: suffix = ""
        default: suffix = " " + units.length.symbol
        }
        var text = "\(letter) \(number(width)) x \(number(height))"
        if sill >= Tuning.minSill { text += " / sill \(number(sill))" }
        return text + suffix
    }

    // MARK: Room-level labels

    private func writeCeiling(at centre: Point2, into scene: inout OverlayScene) {
        let scanned = room.ceilingHeight.scanned
        let value = room.ceilingHeight.value
        guard scanned.isFinite, scanned > 0.05, value.isFinite else { return }
        let state = verificationState(room.ceilingHeight)
        let top = floor + scanned
        let base = centre.world(elevation: floor)
        let apex = centre.world(elevation: top)
        let tick = Tuning.tickHalfLength
        scene.segments.append(OverlaySegment(id: "room:\(roomID):ceiling:dim", kind: .dimension, a: base, b: apex, state: state))
        scene.segments.append(OverlaySegment(id: "room:\(roomID):ceiling:dim:t0", kind: .dimension,
                                             a: Point3(base.x - tick, base.y, base.z), b: Point3(base.x + tick, base.y, base.z), state: state))
        scene.segments.append(OverlaySegment(id: "room:\(roomID):ceiling:dim:t1", kind: .dimension,
                                             a: Point3(apex.x - tick, apex.y, apex.z), b: Point3(apex.x + tick, apex.y, apex.z), state: state))
        scene.labels.append(OverlayLabel(
            id: "room:\(roomID):ceiling", kind: .ceiling,
            position: centre.world(elevation: floor + scanned / 2),
            title: "Ceiling " + lengthText(value), subtitle: provenance(of: room.ceilingHeight), state: state,
            priority: OverlayPriority.height + priorityBonus, roomID: room.id, targetID: roomID))
    }

    private func writeArea(at centre: Point2, metrics: RoomMetrics, into scene: inout OverlayScene) {
        let area = metrics.effectiveFloorArea
        guard area.isFinite else { return }
        scene.labels.append(OverlayLabel(
            id: "room:\(roomID):area", kind: .area,
            position: centre.world(elevation: floor + Tuning.areaLabelLift),
            title: UnitFormatter.area(area, unit: units.area, precision: .compact),
            subtitle: room.name.isEmpty ? room.kind.displayName : room.name, state: .neutral,
            priority: OverlayPriority.area + priorityBonus, roomID: room.id, targetID: roomID))
    }

    // MARK: Saved tape measurements

    private func writeCustomMeasurements(into scene: inout OverlayScene) {
        for m in room.customMeasurements {
            let value = m.length.value
            guard value.isFinite, m.a.length.isFinite, m.b.length.isFinite else { continue }
            let mid = (m.a + m.b) / 2
            let state = verificationState(m.length)
            let mid3 = Point3(mid.x, mid.y, mid.z)
            let name = m.label.isEmpty ? "Measurement" : m.label
            let id = m.id.uuidString
            scene.segments.append(OverlaySegment(id: "measure:\(id):line", kind: .measurement, a: m.a, b: m.b, state: state))
            scene.labels.append(OverlayLabel(
                id: "measure:\(id):label", kind: .measurement, position: mid3,
                title: lengthText(value), subtitle: "\(name) \u{00B7} \(provenance(of: m.length))", state: state,
                priority: OverlayPriority.measurement + priorityBonus, roomID: room.id, targetID: id))
        }
    }
}

// MARK: - Spoken descriptions (VoiceOver)

public extension OverlayLabel {
    /// A sentence for VoiceOver: units spelled out, provenance stated, never colour alone.
    /// For example "Wall length 3245 millimetres, verified with laser".
    var spokenDescription: String {
        let spokenTitle = SpokenText.expand(title, isOpening: kind == .opening)
        let lead: String
        switch kind {
        case .wallLength: lead = "Wall length " + spokenTitle
        case .angle: lead = "Corner angle " + spokenTitle
        case .area: lead = "Floor area " + spokenTitle
        case .measurement: lead = "Measurement " + spokenTitle
        case .live: lead = "Live measurement " + spokenTitle
        case .wallHeight, .ceiling, .opening: lead = spokenTitle
        }

        var parts = [lead]
        let provenanceKinds: [OverlayLabelKind] = [.wallLength, .wallHeight, .ceiling, .opening]
        let subtitleText = subtitle.map { SpokenText.expand($0, isOpening: false) }

        switch state {
        case .verified:
            if provenanceKinds.contains(kind), let s = subtitleText {
                parts.append("verified with " + s.lowercased())
            } else {
                parts.append("verified")
                if let s = subtitleText { parts.append(s) }
            }
        case .scanned:
            parts.append("scanned, not checked")
            if let s = subtitleText { parts.append(s) }
        case .caution:
            parts.append(kind == .angle ? "slightly out of square" : "check this value")
        case .critical:
            parts.append(kind == .angle ? "out of square" : "needs attention")
        case .neutral:
            if let s = subtitleText { parts.append(s) }
        }
        return parts.joined(separator: ", ")
    }
}

/// Expands the compact on-screen text (units, symbols) into words a screen reader says well.
enum SpokenText {
    static func expand(_ text: String, isOpening: Bool) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        for (index, token) in tokens.enumerated() {
            let previous = index > 0 ? tokens[index - 1] : ""
            let afterNumber = previous.contains { $0.isNumber }
            switch token {
            case "D" where isOpening && index == 0: out.append("door")
            case "W" where isOpening && index == 0: out.append("window")
            case "O" where isOpening && index == 0: out.append("opening")
            case "x": out.append("by")
            case "/": out.append("/")
            case "\u{00B7}": out.append("/")
            case "mm" where afterNumber: out.append("millimetres")
            case "cm" where afterNumber: out.append("centimetres")
            case "m" where afterNumber: out.append("metres")
            case "in" where afterNumber: out.append("inches")
            case "m\u{00B2}" where afterNumber: out.append("square metres")
            case "sq" where afterNumber: out.append("square")
            case "ft" where previous == "sq": out.append("feet")
            default: out.append(expandSymbols(in: token))
            }
        }
        // " / " reads as a pause.
        return out.joined(separator: " ").replacingOccurrences(of: " / ", with: ", ")
    }

    private static func expandSymbols(in token: String) -> String {
        var t = token
        if t.hasPrefix("\u{00B1}") { t = "plus or minus " + t.dropFirst() }
        if t.hasSuffix("\u{00B0}") { t = String(t.dropLast()) + " degrees" }
        if t.hasSuffix("\"") { t = String(t.dropLast()) + " inches" }
        if t.hasSuffix("'") { t = String(t.dropLast()) + " feet" }
        return t
    }
}
