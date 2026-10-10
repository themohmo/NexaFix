import Foundation

/// Turns the room model into the vector `PlanDrawing` that the PDF, DXF and in-app renderers draw.
///
/// Everything is in plan space, metres at model scale. Line weights are paper millimetres and text
/// heights are model-space cap heights computed from paper millimetres and `PlanOptions.scale`
/// (2.5 mm on paper at 1:50 is 0.125 m), so a plan looks the same on paper at every scale.
///
/// Conventions of the output:
/// - Primitives are in painting order: furniture, wall bands, openings, dimensions, angles, labels.
/// - `.text` positions are the BASELINE anchor point (left, centre or right of the string).
/// - `.arc` angles are normalised to 0..<360 and run counter-clockwise from start to end, so an arc
///   may wrap past 360 (end < start).
/// - Dimension text always reads left-to-right or bottom-to-top, never upside-down.
/// - Output is deterministic and contains no NaN or infinity, whatever the input.
/// - Text never overprints other text. When a plan is too small to hold every label, the less
///   important ones are left out (opening tags and furniture names first, then wall dimensions that
///   collide with a more important one, and the area and ceiling lines of a room label); what was
///   left out is counted in `PlanLayoutReport`, returned by `buildDetailed`.
/// - A door or window that two rooms both recorded in their shared wall is drawn once, and the
///   wall bands of both rooms are open where it passes through the partition.
public enum PlanDrawingBuilder {

    // MARK: Public API

    /// Build a plan of `rooms`, which share one coordinate frame.
    public static func build(rooms: [Room], title: String, subtitle: String, options: PlanOptions) -> PlanDrawing {
        buildDetailed(rooms: rooms, title: title, subtitle: subtitle, options: options).drawing
    }

    /// Like `build`, and also reports what could not be drawn or printed: rooms the builder had to
    /// skip, labels left out for lack of room, and which kinds of mark the plan uses.
    public static func buildDetailed(rooms: [Room], title: String, subtitle: String,
                                     options: PlanOptions) -> PlanBuildResult {
        var context = Context(options: options)
        var geometries: [RoomGeometry] = []
        for room in rooms {
            if var g = RoomGeometry(room: room) {
                g.index = geometries.count
                geometries.append(g)
            } else {
                context.report.undrawableRooms.append(displayName(of: room))
            }
        }
        context.report.hasDrawingSourcedValues = options.markVerified && geometries.contains { hasDrawingSource($0.room) }
        context.links = OpeningLinks(geometries)
        context.report.sharedOpenings = context.links.sharedCount

        // Decide first which text is printed, most important first, so that nothing is printed on
        // top of anything else; then draw in painting order.
        var angles = options.showAngles ? geometries.map { angleLayouts($0, context) } : []
        var dimensions = options.showDimensions ? geometries.map { dimensionLayouts($0, context) } : []
        var tags = options.showOpeningSizes ? geometries.map { openingTagLayouts($0, context) } : []
        reserveText(angles: &angles, dimensions: &dimensions, tags: &tags, &context)

        if options.showFurniture {
            for g in geometries { addFurniture(g, &context) }
        }
        for g in geometries { addWalls(g, &context) }
        for g in geometries { addOpenings(g, &context) }
        for layouts in dimensions { emitDimensions(layouts, &context) }
        for layouts in angles { emitAngles(layouts, &context) }
        for layouts in tags { emitOpeningTags(layouts, &context) }
        if options.showRoomLabels {
            for g in geometries { addRoomLabel(g, &context) }
        }

        let primitives = context.primitives.filter { isAllFinite($0.primitive) }
        let bounds = PlanDrawingBuilder.bounds(of: primitives) ?? Bounds2(min: .zero, max: Point2(1, 1))
        let drawing = PlanDrawing(primitives: primitives, bounds: bounds, options: options,
                                  title: title, subtitle: subtitle)
        return PlanBuildResult(drawing: drawing, report: context.report)
    }

    /// Build the plan of one floor. The title is the property name (the floor name when there is
    /// no property) and the subtitle is the floor name.
    public static func build(floor: Floor, property: Property?, options: PlanOptions) -> PlanDrawing {
        let title = property?.name ?? floor.name
        let subtitle = property == nil ? "" : floor.name
        return build(rooms: floor.rooms, title: title, subtitle: subtitle, options: options)
    }

    /// Build the plan of a single room: title is the room name, subtitle its kind.
    public static func build(room: Room, options: PlanOptions) -> PlanDrawing {
        build(rooms: [room], title: room.name, subtitle: room.kind.displayName, options: options)
    }

    /// `buildDetailed` for a single room.
    public static func buildDetailed(room: Room, options: PlanOptions) -> PlanBuildResult {
        buildDetailed(rooms: [room], title: room.name, subtitle: room.kind.displayName, options: options)
    }

    /// `buildDetailed` for one floor.
    public static func buildDetailed(floor: Floor, property: Property?, options: PlanOptions) -> PlanBuildResult {
        let title = property?.name ?? floor.name
        let subtitle = property == nil ? "" : floor.name
        return buildDetailed(rooms: floor.rooms, title: title, subtitle: subtitle, options: options)
    }

    /// Width in model-space metres of `text` set with the given cap height, using Helvetica metrics
    /// plus a 2 % allowance. Renderers use the same estimate to size the drawing's `bounds`.
    public static func textWidth(_ text: String, height: Double, bold: Bool = false) -> Double {
        guard height.isFinite, height > 0 else { return 0 }
        let fontSize = height / HelveticaMetrics.capHeight
        return HelveticaMetrics.width(of: text, bold: bold, fontSize: fontSize) * 1.02
    }

    // MARK: Palette and weights

    /// The NexaFix plan colours, shared with the PDF title block.
    public enum Palette {
        public static let ink = DrawColor(hex: 0x1F1D1A)
        public static let bronze = DrawColor(hex: 0x9C7B52)
        public static let paper = DrawColor(hex: 0xFBF8F3)
        public static let hairline = DrawColor(hex: 0xDDD3C4)
        public static let muted = DrawColor(hex: 0x7A7268)
        /// Laser-verified numbers.
        public static let verified = DrawColor(hex: 0x2F7A4B)
        /// Out-of-square corners.
        public static let warning = DrawColor(hex: 0xC62828)
        public static let furnitureFill = DrawColor(hex: 0xE6E1D9)
    }

    /// Line weights on paper, millimetres.
    enum Weight {
        static let wall = 0.5
        static let open = 0.35
        static let doorLeaf = 0.25
        static let doorArc = 0.13
        static let window = 0.18
        static let opening = 0.18
        static let furniture = 0.13
        static let dimension = 0.13
        static let tick = 0.18
        static let angleArc = 0.18
        static let squareMark = 0.13
    }

    /// Text cap heights on paper, millimetres.
    enum TextSize {
        static let dimension = 2.0
        static let angle = 1.8
        static let openingTag = 1.5
        static let furniture = 1.5
        static let roomName = 3.0
        static let roomDetail = 2.2
    }

    /// Thickness of the wall bands drawn outward of the clear outline, metres.
    static let wallThickness = 0.12

    // MARK: Build context

    struct Context {
        let options: PlanOptions
        /// Scale denominator, sanitised (a plan is never built at a zero, negative or NaN scale).
        let scale: Double
        var primitives: [LayeredPrimitive] = []
        /// Doors and windows two rooms share (see `OpeningLinks`).
        var links = OpeningLinks()
        /// Oriented boxes of the text that is already placed: nothing else may be printed over it.
        var textBoxes = BoxIndex()
        /// Everything a room label should keep clear of: text, door swings, furniture footprints.
        var obstacles = BoxIndex()
        var report = PlanLayoutReport()

        init(options: PlanOptions) {
            self.options = options
            self.scale = options.scale.isFinite && options.scale > 0 ? options.scale : 50
        }

        /// Paper millimetres to model-space metres at this scale.
        func paper(_ millimetres: Double) -> Double { millimetres * scale / 1000 }

        mutating func add(_ layer: PlanLayer, _ primitive: DrawingPrimitive) {
            primitives.append(LayeredPrimitive(layer, primitive))
        }

        mutating func line(_ layer: PlanLayer, _ a: Point2, _ b: Point2, weight: Double, color: DrawColor,
                           dashed: Bool = false) {
            add(layer, .line(a, b, DrawStroke(weight: weight, color: color, dashed: dashed)))
        }

        /// `paperHeight` is the cap height on paper in millimetres. `at` is the baseline anchor.
        mutating func text(_ layer: PlanLayer, _ string: String, at: Point2, paperHeight: Double,
                           rotation: Double = 0, anchor: TextAnchor = .center,
                           color: DrawColor = Palette.ink, bold: Bool = false) {
            guard !string.isEmpty else { return }
            add(layer, .text(string, at: at, height: paper(paperHeight), rotation: rotation,
                             anchor: anchor, color: color, bold: bold))
        }

        // MARK: Text reservation

        /// Whether `placement` would print over text that is already reserved.
        func collides(_ placement: TextPlacement) -> Bool {
            textBoxes.overlaps(quad: placement.corners(scale: scale))
        }

        /// Claim the space of `placement`: later text avoids it and room labels keep clear of it.
        mutating func reserve(_ placement: TextPlacement) {
            let corners = placement.corners(scale: scale)
            guard let box = Bounds2(points: corners), box.width > 0, box.height > 0 else { return }
            textBoxes.insert(box, quad: corners)
            obstacles.insert(box)
        }

        /// Draw reserved text.
        mutating func emit(_ placement: TextPlacement) {
            guard !placement.string.isEmpty else { return }
            add(placement.layer, .text(placement.string, at: placement.at, height: paper(placement.paperHeight),
                                       rotation: placement.rotation, anchor: placement.anchor,
                                       color: placement.color, bold: placement.bold))
        }
    }

    /// One line of text before it is drawn: where it goes and how it looks.
    struct TextPlacement {
        let layer: PlanLayer
        let string: String
        /// Baseline anchor point.
        let at: Point2
        /// Cap height on paper, millimetres.
        let paperHeight: Double
        let rotation: Double
        let anchor: TextAnchor
        let color: DrawColor
        let bold: Bool

        /// The rectangle the line occupies for the purpose of keeping other text off it, plan space:
        /// from the baseline (or the descender, when the text has letters that hang below it) to the
        /// cap height.
        func corners(scale: Double) -> [Point2] {
            PlanDrawingBuilder.textCorners(string, at: at, height: paperHeight * scale / 1000, rotation: rotation,
                                           anchor: anchor, bold: bold,
                                           includeDescender: PlanDrawingBuilder.hasDescender(string))
        }
    }

    // MARK: Room geometry

    /// Whether the builder can draw `room`: three or more walls with finite corner coordinates.
    /// The PDF renderer asks the same question to decide which rooms the plan will hold.
    static func isDrawable(_ room: Room) -> Bool {
        guard room.walls.count >= 3 else { return false }
        return room.walls.allSatisfy {
            $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite
        }
    }

    /// The name printed for a room: its own name, or its kind when it has none.
    static func displayName(of room: Room) -> String {
        let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? room.kind.displayName : name
    }

    /// One wall with the vectors the drawing code needs.
    struct WallGeometry {
        let index: Int
        let wall: Wall
        let start: Point2
        let end: Point2
        /// Distance between the stored corners, metres.
        let length: Double
        /// Unit vector start -> end (zero when the wall is degenerate).
        let direction: Point2
        /// Unit normal pointing into the room.
        let inward: Point2
        /// Long enough to draw (not a zero-length wall).
        let isUsable: Bool
        /// Outer corner of the wall band at the start and at the end (mitred with the solid neighbour).
        var outerStart: Point2
        var outerEnd: Point2

        /// A point `s` metres along the wall, `inset` metres towards the room interior
        /// (negative = towards the outside of the wall).
        func point(at s: Double, inset: Double = 0) -> Point2 {
            start + direction * s + inward * inset
        }
    }

    /// A room prepared for drawing.
    struct RoomGeometry {
        let room: Room
        /// Position among the rooms of one plan (the drawable ones only); set by `buildDetailed`.
        var index = 0
        /// The outline is wound counter-clockwise (the model's contract). Kept so a clockwise
        /// outline still draws correctly, with the bands on the outside.
        let isCounterClockwise: Bool
        var walls: [WallGeometry]
        let metrics: RoomMetrics

        var outline: [Point2] { room.outline }

        /// nil when the room has fewer than three walls or any non-finite corner.
        init?(room: Room) {
            guard PlanDrawingBuilder.isDrawable(room) else { return nil }
            self.room = room
            let ccw = Polygon.isCounterClockwise(room.outline)
            self.isCounterClockwise = ccw
            self.metrics = RoomMetrics(room: room)

            var built: [WallGeometry] = []
            for (i, w) in room.walls.enumerated() {
                let length = w.geometricLength
                let direction = w.direction
                let normal = ccw ? direction.perpendicularCCW : -direction.perpendicularCCW
                built.append(WallGeometry(index: i, wall: w, start: w.start, end: w.end, length: length,
                                          direction: direction, inward: normal, isUsable: length > 1e-6,
                                          outerStart: w.start, outerEnd: w.end))
            }
            self.walls = built
            computeBandCorners()
        }

        /// Fill in `outerStart` / `outerEnd` for every solid wall: a mitre with the neighbouring
        /// solid wall, or a square end next to an open boundary or a gap in the loop.
        private mutating func computeBandCorners() {
            let n = walls.count
            let t = PlanDrawingBuilder.wallThickness
            func neighbour(from i: Int, step: Int) -> Int? {
                var j = (i + step + n) % n
                var guardCount = 0
                while !walls[j].isUsable {
                    j = (j + step + n) % n
                    guardCount += 1
                    if guardCount > n { return nil }
                }
                return j == i ? nil : j
            }
            func isSolid(_ w: WallGeometry) -> Bool { w.isUsable && w.wall.kind == .solid }

            for i in 0..<n where isSolid(walls[i]) {
                let me = walls[i]
                if let p = neighbour(from: i, step: -1), isSolid(walls[p]),
                   walls[p].end.distance(to: me.start) < 1e-3 {
                    let m = PlanDrawingBuilder.mitreVector(previous: walls[p].inward, current: me.inward)
                    walls[i].outerStart = me.start - m * t
                } else {
                    walls[i].outerStart = me.start - me.inward * t
                }
                if let q = neighbour(from: i, step: 1), isSolid(walls[q]),
                   me.end.distance(to: walls[q].start) < 1e-3 {
                    let m = PlanDrawingBuilder.mitreVector(previous: me.inward, current: walls[q].inward)
                    walls[i].outerEnd = me.end - m * t
                } else {
                    walls[i].outerEnd = me.end - me.inward * t
                }
            }
        }
    }

    /// Displacement of the corner of the offset outline for a unit offset along the inward normals
    /// of two consecutive walls: the intersection of the two offset lines. The mitre is limited to
    /// three times the offset so a very sharp corner does not shoot a spike across the drawing.
    static func mitreVector(previous: Point2, current: Point2) -> Point2 {
        let denominator = 1 + previous.dot(current)
        if denominator < 1e-6 { return current }
        var m = (previous + current) / denominator
        let length = m.length
        if length > 3 { m = m * (3 / length) }
        return m
    }

    // MARK: Opening spans

    /// An opening clipped to the extent of its wall.
    struct OpeningSpan {
        let opening: Opening
        /// Distance from the wall start to the near and far edge of the opening, metres.
        let s0: Double
        let s1: Double
        var width: Double { s1 - s0 }
        var mid: Double { (s0 + s1) / 2 }
    }

    /// Openings that belong to `wall`, clipped to it and sorted along it. Openings with a
    /// non-finite or sub-centimetre extent are dropped.
    static func spans(on wall: WallGeometry, in room: Room) -> [OpeningSpan] {
        var result: [OpeningSpan] = []
        for o in room.openings where o.wallID == wall.wall.id {
            let a = o.offsetFromWallStart
            let b = o.offsetFromWallStart + o.width.scanned
            guard a.isFinite, b.isFinite else { continue }
            let s0 = Swift.max(0, Swift.min(a, b))
            let s1 = Swift.min(wall.length, Swift.max(a, b))
            if s1 - s0 > 0.01 { result.append(OpeningSpan(opening: o, s0: s0, s1: s1)) }
        }
        return result.sorted { $0.s0 < $1.s0 }
    }

    /// Union of the spans' extents, sorted and non-overlapping.
    static func mergedGaps(_ spans: [OpeningSpan]) -> [(Double, Double)] {
        mergedIntervals(spans.map { ($0.s0, $0.s1) })
    }

    /// Union of intervals along a wall, sorted and non-overlapping.
    static func mergedIntervals(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        var gaps: [(Double, Double)] = []
        for s in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let last = gaps.last, s.0 <= last.1 {
                gaps[gaps.count - 1].1 = Swift.max(last.1, s.1)
            } else {
                gaps.append(s)
            }
        }
        return gaps
    }

    // MARK: Walls

    /// Wall bands (filled polygons outward of the clear outline, cut at openings) and open
    /// boundaries (dashed lines on the open-walls layer).
    static func addWalls(_ g: RoomGeometry, _ context: inout Context) {
        let ink = Palette.ink
        let t = wallThickness
        for w in g.walls where w.isUsable {
            if w.wall.kind == .virtual {
                context.line(.wallsOpen, w.start, w.end, weight: Weight.open, color: ink, dashed: true)
                continue
            }
            // The openings drawn on this wall, plus the cut-outs other rooms' doors and windows
            // make through the partition when it is also their wall.
            let own = spans(on: w, in: g.room)
                .filter { !context.links.suppressedSymbols.contains(OpeningRef(room: g.index, opening: $0.opening.id)) }
                .map { ($0.s0, $0.s1) }
            let foreign = context.links.foreignGaps[WallRef(room: g.index, wall: w.index)] ?? []
            let gaps = mergedIntervals(own + foreign)
            var pieces: [(Double, Double)] = []
            var cursor = 0.0
            for gap in gaps {
                if gap.0 - cursor > 1e-4 { pieces.append((cursor, gap.0)) }
                cursor = gap.1
            }
            if w.length - cursor > 1e-4 { pieces.append((cursor, w.length)) }

            for piece in pieces {
                let startsAtCorner = piece.0 <= 1e-9
                let endsAtCorner = piece.1 >= w.length - 1e-9
                let innerA = startsAtCorner ? w.start : w.point(at: piece.0)
                let innerB = endsAtCorner ? w.end : w.point(at: piece.1)
                let outerA = startsAtCorner ? w.outerStart : innerA - w.inward * t
                let outerB = endsAtCorner ? w.outerEnd : innerB - w.inward * t
                context.add(.walls, .polyline([innerA, innerB, outerB, outerA], closed: true,
                                              stroke: DrawStroke(weight: Weight.wall, color: ink),
                                              fill: ink))
            }
        }
    }

    // MARK: Furniture

    /// Object footprints in light grey, each with its kind name when the name fits and is not in
    /// the way of a dimension, angle or opening tag.
    static func addFurniture(_ g: RoomGeometry, _ context: inout Context) {
        for object in g.room.objects {
            guard object.center.x.isFinite, object.center.y.isFinite, object.yaw.isFinite,
                  object.width.isFinite, object.depth.isFinite, object.width > 0.01, object.depth > 0.01 else { continue }
            let footprint = object.footprint
            context.add(.furniture, .polyline(footprint, closed: true,
                                              stroke: DrawStroke(weight: Weight.furniture, color: Palette.muted),
                                              fill: Palette.furnitureFill))
            if let box = Bounds2(points: footprint) { context.obstacles.insert(box) }

            // Label along the longer side, kept upright; skipped when it would not fit the footprint.
            let label = object.kind.displayName
            let height = context.paper(TextSize.furniture)
            let labelWidth = textWidth(label, height: height)
            let alongWidth = object.width >= object.depth
            let available = alongWidth ? object.width : object.depth
            guard labelWidth <= available * 0.92, height <= (alongWidth ? object.depth : object.width) * 0.8 else { continue }
            let axis = Point2(1, 0).rotated(by: object.yaw + (alongWidth ? 0 : Double.pi / 2))
            let rotation = uprightRotation(of: axis)
            let placement = TextPlacement(layer: .furniture, string: label,
                                          at: baselineCentre(of: object.center, height: height, rotation: rotation),
                                          paperHeight: TextSize.furniture, rotation: rotation, anchor: .center,
                                          color: Palette.muted, bold: false)
            if context.collides(placement) {
                context.report.omittedFurnitureLabels += 1
                continue
            }
            context.reserve(placement)
            context.emit(placement)
        }
    }

    // MARK: Text helpers

    /// Rotation in degrees, in (-90, 90], of text running along `direction` so it is never upside-down.
    static func uprightRotation(of direction: Point2) -> Double {
        var degrees = atan2(direction.y, direction.x) * 180 / Double.pi
        if degrees > 90 { degrees -= 180 }
        if degrees <= -90 { degrees += 180 }
        return degrees
    }

    /// The baseline point that puts the visual middle of a text line (half a cap height above the
    /// baseline) on `centre`, for text rotated by `rotation` degrees.
    static func baselineCentre(of centre: Point2, height: Double, rotation: Double) -> Point2 {
        let up = Point2(0, 1).rotated(by: rotation * Double.pi / 180)
        return centre - up * (height / 2)
    }

    /// Normalise an angle to 0..<360 degrees.
    static func normalizedDegrees(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d >= 360 ? 0 : d
    }

    /// Whether `string` has glyphs that hang below the baseline. Digits, capitals and most
    /// lower-case letters do not, so a line of those needs no room below its baseline.
    static func hasDescender(_ string: String) -> Bool {
        string.contains { "gjpqy,;()[]{}|/_@Q$".contains($0) }
    }

    /// Corners of the rectangle a text line occupies (descender to cap height), in plan space.
    /// Without `includeDescender` the rectangle starts at the baseline.
    static func textCorners(_ string: String, at: Point2, height: Double, rotation: Double,
                            anchor: TextAnchor, bold: Bool, includeDescender: Bool = true) -> [Point2] {
        let width = textWidth(string, height: height, bold: bold)
        let fontSize = height / HelveticaMetrics.capHeight
        let left: Double
        switch anchor {
        case .left: left = 0
        case .center: left = -width / 2
        case .right: left = -width
        }
        let bottom = includeDescender ? -HelveticaMetrics.descender * fontSize : 0
        let top = height
        let radians = rotation * Double.pi / 180
        let u = Point2(cos(radians), sin(radians))
        let v = Point2(-sin(radians), cos(radians))
        func p(_ x: Double, _ y: Double) -> Point2 { at + u * x + v * y }
        return [p(left, bottom), p(left + width, bottom), p(left + width, top), p(left, top)]
    }

    // MARK: Bounds

    /// Points that cover a primitive's extent (text by its rotated box, arcs by their end points
    /// and any axis extremes they sweep through). Stroke widths are not included.
    static func extentPoints(of primitive: DrawingPrimitive) -> [Point2] {
        switch primitive {
        case let .line(a, b, _):
            return [a, b]
        case let .polyline(points, _, _, _):
            return points
        case let .circle(center, radius, _):
            return [Point2(center.x - radius, center.y - radius), Point2(center.x + radius, center.y + radius)]
        case let .arc(center, radius, startAngle, endAngle, _):
            let start = normalizedDegrees(startAngle)
            var sweep = normalizedDegrees(endAngle) - start
            if sweep < 0 { sweep += 360 }
            func at(_ degrees: Double) -> Point2 {
                let r = degrees * Double.pi / 180
                return center + Point2(cos(r), sin(r)) * radius
            }
            var points = [at(start), at(start + sweep)]
            for axis in [0.0, 90, 180, 270, 360, 450, 540, 630] where axis > start && axis < start + sweep {
                points.append(at(axis))
            }
            return points
        case let .text(string, at, height, rotation, anchor, _, bold):
            return textCorners(string, at: at, height: height, rotation: rotation, anchor: anchor, bold: bold)
        }
    }

    /// Union of everything drawn; nil when there is nothing.
    static func bounds(of primitives: [LayeredPrimitive]) -> Bounds2? {
        var result: Bounds2?
        for p in primitives {
            guard let b = Bounds2(points: extentPoints(of: p.primitive)) else { continue }
            result = result.map { $0.union(b) } ?? b
        }
        return result
    }

    /// Every coordinate, size and angle of the primitive is finite (no NaN, no infinity).
    static func isAllFinite(_ primitive: DrawingPrimitive) -> Bool {
        func ok(_ p: Point2) -> Bool { p.x.isFinite && p.y.isFinite }
        switch primitive {
        case let .line(a, b, s): return ok(a) && ok(b) && s.weight.isFinite
        case let .polyline(points, _, s, _): return points.allSatisfy(ok) && (s?.weight.isFinite ?? true)
        case let .arc(c, r, a, b, s): return ok(c) && r.isFinite && a.isFinite && b.isFinite && s.weight.isFinite
        case let .circle(c, r, s): return ok(c) && r.isFinite && s.weight.isFinite
        case let .text(_, at, height, rotation, _, _, _): return ok(at) && height.isFinite && rotation.isFinite
        }
    }
}

// MARK: - Layout report

/// What a plan build could not draw or print, and which marks it uses. The PDF renderer turns this
/// into the note on the plan page and the legend; the export sheet can use it to suggest a larger
/// sheet.
public struct PlanLayoutReport: Hashable, Sendable {
    /// Wall dimensions left out because they would have been printed over a more important label.
    public var omittedDimensionTexts = 0
    /// Corner angle numbers left out for the same reason (the arc stays).
    public var omittedAngleTexts = 0
    /// Door, window and opening size tags left out.
    public var omittedOpeningTags = 0
    /// Furniture names left out.
    public var omittedFurnitureLabels = 0
    /// Room labels that lost their ceiling and/or area line to make room.
    public var droppedRoomLabelLines = 0
    /// Room labels that still touch other text after shrinking and dropping lines.
    public var roomLabelsWithOverlap = 0
    /// Names of the rooms the builder had to skip (fewer than three walls, or a corner that is not a number).
    public var undrawableRooms: [String] = []
    /// Dimension labels printed with the "chord" flag for a curved wall.
    public var chordLabels = 0
    /// Some printed value comes from a drawing rather than a site check (marked "d").
    public var hasDrawingSourcedValues = false
    /// Doors, windows and openings recorded by two rooms in the same wall and drawn once.
    public var sharedOpenings = 0

    public init() {}

    /// Everything that matters was printed without overprinting and nothing important was left out.
    public var isLegible: Bool { omittedDimensionTexts == 0 && roomLabelsWithOverlap == 0 }
}

/// A finished plan with its layout report.
public struct PlanBuildResult: Sendable {
    public let drawing: PlanDrawing
    public let report: PlanLayoutReport
}

// MARK: - Spatial index

/// Boxes on a one-metre grid, for "does anything already sit here?" questions that stay fast with
/// hundreds of rooms. Text boxes are stored as their oriented rectangle so a slanted label is not
/// treated as its much larger axis-aligned bounding box.
struct BoxIndex {
    private struct Cell: Hashable { let x: Int; let y: Int }

    private(set) var bounds: [Bounds2] = []
    private var quads: [[Point2]?] = []
    private var cells: [Cell: [Int]] = [:]
    /// Boxes too big for the grid (covering more than `maxCells` cells along an axis).
    private var large: [Int] = []

    private static let cellSize = 1.0
    private static let maxCells = 32

    private static func index(_ v: Double) -> Int {
        Int(Swift.max(-1e9, Swift.min(1e9, (v / cellSize).rounded(.down))))
    }

    var isEmpty: Bool { bounds.isEmpty }

    mutating func insert(_ box: Bounds2, quad: [Point2]? = nil) {
        let id = bounds.count
        bounds.append(box)
        quads.append(quad)
        let x0 = BoxIndex.index(box.min.x), x1 = BoxIndex.index(box.max.x)
        let y0 = BoxIndex.index(box.min.y), y1 = BoxIndex.index(box.max.y)
        if x1 - x0 >= BoxIndex.maxCells || y1 - y0 >= BoxIndex.maxCells {
            large.append(id)
            return
        }
        for x in x0...x1 {
            for y in y0...y1 { cells[Cell(x: x, y: y), default: []].append(id) }
        }
    }

    /// Ids of boxes that may touch `box` (every box that does, possibly a few more).
    private func candidates(near box: Bounds2) -> [Int] {
        var result: [Int] = large
        let x0 = BoxIndex.index(box.min.x), x1 = BoxIndex.index(box.max.x)
        let y0 = BoxIndex.index(box.min.y), y1 = BoxIndex.index(box.max.y)
        if x1 - x0 >= BoxIndex.maxCells || y1 - y0 >= BoxIndex.maxCells {
            return Array(0..<bounds.count)
        }
        var seen = Set<Int>(large)
        for x in x0...x1 {
            for y in y0...y1 {
                guard let ids = cells[Cell(x: x, y: y)] else { continue }
                for id in ids where seen.insert(id).inserted { result.append(id) }
            }
        }
        return result
    }

    /// The stored boxes that touch `area`.
    func rects(intersecting area: Bounds2) -> [Bounds2] {
        candidates(near: area).compactMap { id in
            let r = bounds[id]
            if r.max.x < area.min.x || r.min.x > area.max.x || r.max.y < area.min.y || r.min.y > area.max.y { return nil }
            return r
        }.sorted { ($0.min.x, $0.min.y, $0.max.x, $0.max.y) < ($1.min.x, $1.min.y, $1.max.x, $1.max.y) }
    }

    /// The oriented boxes (text) whose bounding box touches `area`, with those bounding boxes.
    func orientedBoxes(intersecting area: Bounds2) -> [(bounds: Bounds2, quad: [Point2])] {
        candidates(near: area).sorted().compactMap { id in
            guard let quad = quads[id] else { return nil }
            let r = bounds[id]
            if r.max.x < area.min.x || r.min.x > area.max.x || r.max.y < area.min.y || r.min.y > area.max.y { return nil }
            return (r, quad)
        }
    }

    /// Whether the convex quadrilateral `quad` overlaps (with positive area) any stored oriented box.
    func overlaps(quad: [Point2]) -> Bool {
        guard let box = Bounds2(points: quad) else { return false }
        for id in candidates(near: box) {
            guard let other = quads[id] else { continue }
            let b = bounds[id]
            if b.max.x <= box.min.x || b.min.x >= box.max.x || b.max.y <= box.min.y || b.min.y >= box.max.y { continue }
            if BoxIndex.convexOverlap(quad, other) { return true }
        }
        return false
    }

    /// Separating-axis test for two convex polygons; touching edges do not count as overlap.
    static func convexOverlap(_ p: [Point2], _ q: [Point2]) -> Bool {
        for polygon in [p, q] {
            for i in polygon.indices {
                let edge = polygon[(i + 1) % polygon.count] - polygon[i]
                let axis = Point2(-edge.y, edge.x)
                guard axis.length > 1e-12 else { continue }
                var pMin = Double.infinity, pMax = -Double.infinity
                for v in p { let d = v.dot(axis); pMin = Swift.min(pMin, d); pMax = Swift.max(pMax, d) }
                var qMin = Double.infinity, qMax = -Double.infinity
                for v in q { let d = v.dot(axis); qMin = Swift.min(qMin, d); qMax = Swift.max(qMax, d) }
                let tolerance = 1e-9 * axis.length
                if pMax <= qMin + tolerance || qMax <= pMin + tolerance { return false }
            }
        }
        return true
    }
}
