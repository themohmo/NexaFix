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
public enum PlanDrawingBuilder {

    // MARK: Public API

    /// Build a plan of `rooms`, which share one coordinate frame.
    public static func build(rooms: [Room], title: String, subtitle: String, options: PlanOptions) -> PlanDrawing {
        var context = Context(options: options)
        let geometries = rooms.compactMap { RoomGeometry(room: $0) }

        if options.showFurniture {
            for g in geometries { addFurniture(g, &context) }
        }
        for g in geometries { addWalls(g, &context) }
        for g in geometries { addOpenings(g, &context) }
        if options.showDimensions {
            for g in geometries { addDimensions(g, &context) }
        }
        if options.showAngles {
            for g in geometries { addAngles(g, &context) }
        }
        if options.showOpeningSizes {
            for g in geometries { addOpeningTags(g, &context) }
        }
        if options.showRoomLabels {
            for g in geometries { addRoomLabel(g, &context) }
        }

        let primitives = context.primitives.filter { isAllFinite($0.primitive) }
        let bounds = PlanDrawingBuilder.bounds(of: primitives) ?? Bounds2(min: .zero, max: Point2(1, 1))
        return PlanDrawing(primitives: primitives, bounds: bounds, options: options,
                           title: title, subtitle: subtitle)
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
            add(layer, .line(a, b, StrokeStyle(weight: weight, color: color, dashed: dashed)))
        }

        /// `paperHeight` is the cap height on paper in millimetres. `at` is the baseline anchor.
        mutating func text(_ layer: PlanLayer, _ string: String, at: Point2, paperHeight: Double,
                           rotation: Double = 0, anchor: TextAnchor = .center,
                           color: DrawColor = Palette.ink, bold: Bool = false) {
            guard !string.isEmpty else { return }
            add(layer, .text(string, at: at, height: paper(paperHeight), rotation: rotation,
                             anchor: anchor, color: color, bold: bold))
        }
    }

    // MARK: Room geometry

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
        /// The outline is wound counter-clockwise (the model's contract). Kept so a clockwise
        /// outline still draws correctly, with the bands on the outside.
        let isCounterClockwise: Bool
        var walls: [WallGeometry]
        let metrics: RoomMetrics

        var outline: [Point2] { room.outline }

        /// nil when the room has fewer than three walls or any non-finite corner.
        init?(room: Room) {
            guard room.walls.count >= 3 else { return nil }
            for w in room.walls {
                guard w.start.x.isFinite, w.start.y.isFinite, w.end.x.isFinite, w.end.y.isFinite else { return nil }
            }
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
        var gaps: [(Double, Double)] = []
        for s in spans.sorted(by: { $0.s0 < $1.s0 }) {
            if let last = gaps.last, s.s0 <= last.1 {
                gaps[gaps.count - 1].1 = Swift.max(last.1, s.s1)
            } else {
                gaps.append((s.s0, s.s1))
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
            let gaps = mergedGaps(spans(on: w, in: g.room))
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
                                              stroke: StrokeStyle(weight: Weight.wall, color: ink),
                                              fill: ink))
            }
        }
    }

    // MARK: Furniture

    /// Object footprints in light grey, each with its kind name when the name fits.
    static func addFurniture(_ g: RoomGeometry, _ context: inout Context) {
        // Dimension text is drawn later, on top; keep furniture names off it.
        let dimensionBoxes: [Bounds2] = context.options.showDimensions
            ? dimensionLayouts(g, context).compactMap { layout in
                guard let text = layout.text else { return nil }
                return Bounds2(points: textCorners(text, at: layout.textAnchor,
                                                   height: context.paper(TextSize.dimension),
                                                   rotation: layout.textRotation, anchor: .center, bold: false))
            }
            : []
        for object in g.room.objects {
            guard object.center.x.isFinite, object.center.y.isFinite, object.yaw.isFinite,
                  object.width.isFinite, object.depth.isFinite, object.width > 0.01, object.depth > 0.01 else { continue }
            context.add(.furniture, .polyline(object.footprint, closed: true,
                                              stroke: StrokeStyle(weight: Weight.furniture, color: Palette.muted),
                                              fill: Palette.furnitureFill))

            // Label along the longer side, kept upright; skipped when it would not fit the footprint.
            let label = object.kind.displayName
            let height = context.paper(TextSize.furniture)
            let labelWidth = textWidth(label, height: height)
            let alongWidth = object.width >= object.depth
            let available = alongWidth ? object.width : object.depth
            guard labelWidth <= available * 0.92, height <= (alongWidth ? object.depth : object.width) * 0.8 else { continue }
            let axis = Point2(1, 0).rotated(by: object.yaw + (alongWidth ? 0 : Double.pi / 2))
            let rotation = uprightRotation(of: axis)
            let at = baselineCentre(of: object.center, height: height, rotation: rotation)
            if let box = Bounds2(points: textCorners(label, at: at, height: height, rotation: rotation,
                                                     anchor: .center, bold: false)),
               dimensionBoxes.contains(where: { d in
                   box.max.x > d.min.x && box.min.x < d.max.x && box.max.y > d.min.y && box.min.y < d.max.y
               }) {
                continue
            }
            context.text(.furniture, label, at: at, paperHeight: TextSize.furniture, rotation: rotation,
                         anchor: .center, color: Palette.muted)
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

    /// Corners of the rectangle a text line occupies (descender to cap height), in plan space.
    static func textCorners(_ string: String, at: Point2, height: Double, rotation: Double,
                            anchor: TextAnchor, bold: Bool) -> [Point2] {
        let width = textWidth(string, height: height, bold: bold)
        let fontSize = height / HelveticaMetrics.capHeight
        let left: Double
        switch anchor {
        case .left: left = 0
        case .center: left = -width / 2
        case .right: left = -width
        }
        let bottom = -HelveticaMetrics.descender * fontSize
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
