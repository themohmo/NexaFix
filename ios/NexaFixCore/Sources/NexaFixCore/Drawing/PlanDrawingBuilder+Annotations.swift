import Foundation

// Plan annotations: dimension lines, corner angles, opening size tags and room labels.
//
// Every printed number says where it comes from: a value checked on site (laser or tape) is
// followed by " v", a value taken from an approved drawing by " d", and a scanned value carries no
// mark. A marked number is printed to at least millimetre resolution in every display unit, so
// the mark never sits on a number that was rounded away from the value that was checked.
//
// Text never lands on other text. The text that matters most is placed first (out-of-square angles,
// then wall dimensions with the checked ones before the scanned ones, then the other angle numbers
// and the opening tags); a later label that would overprint an earlier one is left out and counted
// in the `PlanLayoutReport`. Room labels shrink and shed their area and ceiling lines before they
// are allowed to touch anything.

extension PlanDrawingBuilder {

    /// Walls shorter than this (metres) get no dimension line.
    static let minimumDimensionedWall = 0.4

    /// Corners within this many degrees of 90 print as a small square instead of a number.
    static let rightAngleMarkTolerance = 0.5

    // MARK: Provenance

    /// Where a printed number comes from, weakest first.
    enum Provenance: Int, Comparable {
        /// LiDAR only.
        case scanned = 0
        /// Replaced by a value from an approved drawing: not measured on site.
        case drawing = 1
        /// Checked on site with a laser or a tape.
        case site = 2

        init(_ measured: Measured) {
            guard let verification = measured.verification else { self = .scanned; return }
            self = verification.source == .drawing ? .drawing : .site
        }

        /// "v", "d" or nothing.
        var mark: String? {
            switch self {
            case .scanned: return nil
            case .drawing: return "d"
            case .site: return "v"
            }
        }

        static func < (a: Provenance, b: Provenance) -> Bool { a.rawValue < b.rawValue }
    }

    /// Whether any number the plan prints for `room` comes from a drawing.
    static func hasDrawingSource(_ room: Room) -> Bool {
        func fromDrawing(_ m: Measured) -> Bool { Provenance(m) == .drawing }
        return room.walls.contains { fromDrawing($0.length) } || fromDrawing(room.ceilingHeight)
            || room.openings.contains { fromDrawing($0.width) || fromDrawing($0.height) || fromDrawing($0.sillHeight) }
    }

    // MARK: Text for measured values

    /// "4200 mm", "4200 mm v" for a value checked on site, "4200 mm d" for one from a drawing (the
    /// marks need `markVerified`), plus " chord" for a curved wall, whose straight length this is.
    /// Always to the precision the schedule uses (a millimetre, or finer). nil when the value is not
    /// a finite number: nothing is printed rather than "nan mm".
    static func dimensionText(_ measured: Measured, options: PlanOptions, curved: Bool = false) -> String? {
        guard measured.value.isFinite else { return nil }
        var text = UnitFormatter.length(measured.value, unit: options.units.length, precision: .precise)
        if options.markVerified, let mark = Provenance(measured).mark { text += " " + mark }
        if curved { text += " chord" }
        return text
    }

    // MARK: Dimensions

    /// Where one wall's dimension line, ticks and text go.
    struct DimensionLayout {
        let wall: WallGeometry
        /// Ends of the dimension line, inside the room.
        let a: Point2
        let b: Point2
        /// The length text; nil when the length is not a finite number or the text was left out
        /// because it would overprint a more important label.
        var text: TextPlacement?
        /// The whole dimension (line, ticks and text) was left out for lack of room: a dimension line
        /// without its number would only be clutter.
        var isOmitted = false
    }

    /// Layout of every dimension line of a room: one per wall that is long enough, parallel to the
    /// wall, with the effective length centred above it, rotated along the wall and kept upright.
    static func dimensionLayouts(_ g: RoomGeometry, _ context: Context) -> [DimensionLayout] {
        let textHeight = context.paper(TextSize.dimension)
        let offset = dimensionOffset(textHeight: textHeight)
        let gap = 0.3 * textHeight
        var layouts: [DimensionLayout] = []
        for w in g.walls where w.isUsable && w.length >= minimumDimensionedWall {
            let a = w.start + w.inward * offset
            let b = w.end + w.inward * offset
            let rotation = uprightRotation(of: w.direction)
            let radians = rotation * Double.pi / 180
            let up = Point2(-sin(radians), cos(radians))
            var placement: TextPlacement?
            if let text = dimensionText(w.wall.length, options: context.options, curved: w.wall.isCurved) {
                let provenance = context.options.markVerified ? Provenance(w.wall.length) : .scanned
                let color: DrawColor = provenance == .site ? Palette.verified
                    : (w.wall.isCurved ? Palette.bronze : Palette.ink)
                placement = TextPlacement(layer: .dimensions, string: text, at: (a + b) / 2 + up * gap,
                                          paperHeight: TextSize.dimension, rotation: rotation, anchor: .center,
                                          color: color, bold: false)
            }
            layouts.append(DimensionLayout(wall: w, a: a, b: b, text: placement))
        }
        return layouts
    }

    /// One dimension line per wall, inside the room, parallel to the wall, with end ticks and the
    /// effective length centred above it. Text is rotated along the wall and kept upright.
    static func emitDimensions(_ layouts: [DimensionLayout], _ context: inout Context) {
        let tick = context.paper(1.2)
        for layout in layouts where !layout.isOmitted {
            let w = layout.wall
            context.line(.dimensions, layout.a, layout.b, weight: Weight.dimension, color: Palette.muted)
            addTick(at: layout.a, lineDirection: w.direction, halfLength: tick, &context)
            addTick(at: layout.b, lineDirection: w.direction, halfLength: tick, &context)
            guard let text = layout.text else { continue }
            if w.wall.isCurved { context.report.chordLabels += 1 }
            context.emit(text)
        }
    }

    /// Distance of a dimension line from its wall: 0.25 m, or 2.5 text heights where the text is
    /// taller than that (small scales), so the text never touches the wall.
    static func dimensionOffset(textHeight: Double) -> Double {
        Swift.max(0.25, 2.5 * textHeight)
    }

    // MARK: Angles

    /// The arc or square mark of one corner and the angle number beside it.
    struct AngleLayout {
        let primitive: DrawingPrimitive
        /// nil for a right angle (a small square, no number) or when the number was left out.
        var text: TextPlacement?
        /// More than the square tolerance from 90 degrees and not reflex: the safety signal.
        let isOutOfSquare: Bool
    }

    /// An arc and the angle in degrees inside every corner that is not a straight continuation.
    ///
    /// - Within 0.5 degrees of 90: a small square mark, no text.
    /// - Out of square (`RoomMetrics.outOfSquareCorners`: more than `squareTolerance` from 90, not
    ///   reflex): arc and text in the warning colour.
    /// - Anything else (slightly off square, obtuse reflex corners of L-shapes): arc and text in muted ink.
    static func angleLayouts(_ g: RoomGeometry, _ context: Context) -> [AngleLayout] {
        let outline = g.outline
        let n = outline.count
        guard n >= 3 else { return [] }
        let outOfSquare = Set(g.metrics.outOfSquareCorners.map(\.index))
        let textHeight = context.paper(TextSize.angle)
        let dimensionHeight = context.paper(TextSize.dimension)
        // Keep the number clear of the dimension lines and their text along both walls.
        let clearance = context.options.showDimensions
            ? dimensionOffset(textHeight: dimensionHeight) + 1.6 * dimensionHeight
            : context.paper(2.0)
        var layouts: [AngleLayout] = []

        for corner in g.metrics.corners where !corner.isStraight {
            let i = corner.index
            let p = corner.point
            let toNext = outline[(i + 1) % n] - p
            let toPrevious = outline[(i + n - 1) % n] - p
            let nextLength = toNext.length
            let previousLength = toPrevious.length
            guard nextLength > 1e-6, previousLength > 1e-6 else { continue }
            let nextDirection = toNext / nextLength
            let previousDirection = toPrevious / previousLength
            let angle = corner.interiorAngle
            let shortest = Swift.min(nextLength, previousLength)

            if abs(angle - 90) <= rightAngleMarkTolerance {
                let mark = rightAngleMark(corner: p, towardsNext: nextDirection, towardsPrevious: previousDirection,
                                          size: Swift.min(context.paper(2.0), 0.3 * shortest))
                layouts.append(AngleLayout(primitive: mark, text: nil, isOutOfSquare: false))
                continue
            }

            let outOfSquareCorner = outOfSquare.contains(i)
            let color = outOfSquareCorner ? Palette.warning : Palette.muted
            let radius = Swift.min(context.paper(3.0), 0.4 * shortest)

            // The interior wedge runs counter-clockwise from the next wall to the previous one in a
            // counter-clockwise outline (and from the previous wall to the next in a clockwise one).
            let nextAngle = atan2(nextDirection.y, nextDirection.x) * 180 / Double.pi
            let previousAngle = atan2(previousDirection.y, previousDirection.x) * 180 / Double.pi
            let start = g.isCounterClockwise ? nextAngle : previousAngle
            let arc = DrawingPrimitive.arc(center: p, radius: radius,
                                           startAngle: normalizedDegrees(start),
                                           endAngle: normalizedDegrees(start + angle),
                                           StrokeStyle(weight: Weight.angleArc, color: color))

            // Number on the bisector, pushed out until its box clears both walls' dimension lines.
            let text = UnitFormatter.angle(angle)
            let bisectorAngle = (start + angle / 2) * Double.pi / 180
            let bisector = Point2(cos(bisectorAngle), sin(bisectorAngle))
            let halfWidth = textWidth(text, height: textHeight, bold: outOfSquareCorner) / 2
            let halfHeight = textHeight / 2
            let support = halfWidth * abs(bisector.x) + halfHeight * abs(bisector.y)
            let nearest = radius + 0.4 * textHeight + support
            let previousWall = g.walls[(i + n - 1) % n]
            let ownWall = g.walls[i]

            func clearOfWalls(_ centre: Point2) -> Bool {
                let corners = [Point2(-halfWidth, -halfHeight), Point2(halfWidth, -halfHeight),
                               Point2(halfWidth, halfHeight), Point2(-halfWidth, halfHeight)].map { centre + $0 }
                for wall in [previousWall, ownWall] {
                    for c in corners where (c - wall.start).dot(wall.inward) < clearance { return false }
                }
                return Polygon.contains(outline, centre)
            }

            var distance = nearest
            for step in 0...48 {
                let candidate = nearest + 0.05 * Double(step)
                if clearOfWalls(p + bisector * candidate) { distance = candidate; break }
            }
            let centre = p + bisector * distance
            let placement = TextPlacement(layer: .angles, string: text,
                                          at: baselineCentre(of: centre, height: textHeight, rotation: 0),
                                          paperHeight: TextSize.angle, rotation: 0, anchor: .center, color: color,
                                          bold: outOfSquareCorner)
            layouts.append(AngleLayout(primitive: arc, text: placement, isOutOfSquare: outOfSquareCorner))
        }
        return layouts
    }

    static func emitAngles(_ layouts: [AngleLayout], _ context: inout Context) {
        for layout in layouts {
            context.add(.angles, layout.primitive)
            if let text = layout.text { context.emit(text) }
        }
    }

    // MARK: Opening tags

    /// The size tag of one opening, once placed.
    struct OpeningTagLayout {
        var text: TextPlacement?
    }

    /// A short size tag for each door, window and opening, on the room side of its wall, just
    /// inside the wall face and centred on the opening: "D 900x2100", "W 1500x1400 H900" (H is
    /// the sill height). Values are the effective (verified-if-present) sizes in the chosen unit;
    /// non-millimetre units add the unit symbol. The tag sits in the strip between the wall and
    /// the dimension line, so it never lands on the wall band of the room next door. An opening that
    /// two rooms recorded gets one tag, from the record with more checked values.
    static func openingTagLayouts(_ g: RoomGeometry, _ context: Context) -> [OpeningTagLayout] {
        let height = context.paper(TextSize.openingTag)
        let gap = context.paper(0.6)
        var layouts: [OpeningTagLayout] = []
        for w in g.walls where w.isUsable && w.wall.kind == .solid {
            for span in spans(on: w, in: g.room) {
                if context.links.suppressedTags.contains(OpeningRef(room: g.index, opening: span.opening.id)) { continue }
                guard let tag = openingTag(span.opening, options: context.options) else { continue }
                let rotation = uprightRotation(of: w.direction)
                let radians = rotation * Double.pi / 180
                let up = Point2(-sin(radians), cos(radians))
                // Text extends from its baseline along "up": into the room when that is the way up,
                // otherwise towards the wall, so the baseline moves out by one cap height.
                let inset = gap + (up.dot(w.inward) >= 0 ? 0 : height)
                let at = w.point(at: span.mid, inset: inset)
                let allSite = tagValues(span.opening).allSatisfy { Provenance($0) == .site }
                layouts.append(OpeningTagLayout(text: TextPlacement(
                    layer: layer(for: span.opening.kind), string: tag, at: at, paperHeight: TextSize.openingTag,
                    rotation: rotation, anchor: .center,
                    color: context.options.markVerified && allSite ? Palette.verified : Palette.muted, bold: false)))
            }
        }
        return layouts
    }

    static func emitOpeningTags(_ layouts: [OpeningTagLayout], _ context: inout Context) {
        for layout in layouts {
            if let text = layout.text { context.emit(text) }
        }
    }

    /// The measured values a tag shows: width, height and, for windows with a raised sill, the sill.
    private static func tagValues(_ o: Opening) -> [Measured] {
        var values = [o.width, o.height]
        if o.kind == .window, o.sillHeight.value.isFinite, o.sillHeight.value > 0.005 { values.append(o.sillHeight) }
        return values
    }

    private static func layer(for kind: OpeningKind) -> PlanLayer {
        switch kind {
        case .door: return .doors
        case .window: return .windows
        case .opening: return .openings
        }
    }

    /// nil when the width or height is not a finite number.
    static func openingTag(_ o: Opening, options: PlanOptions) -> String? {
        guard o.width.value.isFinite, o.height.value.isFinite else { return nil }
        let unit = options.units.length
        let prefix: String
        switch o.kind {
        case .door: prefix = "D"
        case .window: prefix = "W"
        case .opening: prefix = "O"
        }
        let values = tagValues(o)
        let marks: [String?] = values.map { options.markVerified ? Provenance($0).mark : nil }
        let anyMark = marks.contains { $0 != nil }
        let oneMark = anyMark && marks.allSatisfy { $0 == marks[0] }

        // Every number marked the same way: one mark at the end. Otherwise a mark right after each
        // number that has one.
        let perNumber = anyMark && !oneMark
        func shown(_ index: Int) -> String {
            tagNumber(values[index].value, unit: unit) + (perNumber ? (marks[index] ?? "") : "")
        }
        let separator = perNumber ? " x " : "x"
        var text = "\(prefix) \(shown(0))\(separator)\(shown(1))"
        if values.count == 3 { text += " H\(shown(2))" }
        if oneMark, let mark = marks[0] { text += " " + mark }
        if let symbol = tagUnitSymbol(unit) { text += " " + symbol }
        return text
    }

    /// Plain number for a tag: no unit text, no trailing zeros, always to the precision of a
    /// millimetre or finer (inches to two decimals). Feet-and-inches fall back to decimal inches.
    static func tagNumber(_ metres: Double, unit: LengthUnit) -> String {
        let effective = unit == .feetAndInches ? LengthUnit.inches : unit
        let text = UnitFormatter.length(metres, unit: effective, precision: .precise, includeUnit: false)
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// Millimetres are the unit of joinery drawings and tags stay bare; other units say what they are.
    private static func tagUnitSymbol(_ unit: LengthUnit) -> String? {
        switch unit {
        case .millimetres: return nil
        case .feetAndInches: return LengthUnit.inches.symbol
        default: return unit.symbol
        }
    }

    // MARK: Text reservation

    /// Decide which text is printed, most important first, and claim its space. Anything that
    /// would overprint what is already claimed is left out and counted.
    static func reserveText(angles: inout [[AngleLayout]], dimensions: inout [[DimensionLayout]],
                            tags: inout [[OpeningTagLayout]], _ context: inout Context) {
        // 1. Out-of-square angles: the signal a reader must not miss. Always printed.
        for r in angles.indices {
            for layout in angles[r] where layout.isOutOfSquare {
                if let text = layout.text { context.reserve(text) }
            }
        }

        // 2. Wall dimensions, checked values before scanned ones, long walls before short ones.
        var order: [(room: Int, index: Int, checked: Int, length: Double)] = []
        for r in dimensions.indices {
            for k in dimensions[r].indices where dimensions[r][k].text != nil {
                let wall = dimensions[r][k].wall
                order.append((r, k, wall.wall.length.isVerified ? 1 : 0, wall.length))
            }
        }
        order.sort { a, b in
            if a.checked != b.checked { return a.checked > b.checked }
            if a.length != b.length { return a.length > b.length }
            if a.room != b.room { return a.room < b.room }
            return a.index < b.index
        }
        for item in order {
            guard let text = dimensions[item.room][item.index].text else { continue }
            if context.collides(text) {
                dimensions[item.room][item.index].text = nil
                dimensions[item.room][item.index].isOmitted = true
                context.report.omittedDimensionTexts += 1
            } else {
                context.reserve(text)
            }
        }

        // 3. The other angle numbers (the arcs stay).
        for r in angles.indices {
            for k in angles[r].indices where !angles[r][k].isOutOfSquare {
                guard let text = angles[r][k].text else { continue }
                if context.collides(text) {
                    angles[r][k].text = nil
                    context.report.omittedAngleTexts += 1
                } else {
                    context.reserve(text)
                }
            }
        }

        // 4. Opening tags.
        for r in tags.indices {
            for k in tags[r].indices {
                guard let text = tags[r][k].text else { continue }
                if context.collides(text) {
                    tags[r][k].text = nil
                    context.report.omittedOpeningTags += 1
                } else {
                    context.reserve(text)
                }
            }
        }
    }

    // MARK: Room labels

    private struct LabelLine {
        var text: String
        let paperHeight: Double
        let bold: Bool
        let color: DrawColor
    }

    /// Room name (bold), floor area and ceiling height, centred on a point inside the room.
    ///
    /// Candidate centres are the centroid, the centre of the largest inscribed axis-aligned
    /// rectangle (found on a grid, so an L-shaped room is labelled in its main leg) and a 9 x 9 grid.
    /// Each is scored: it must be inside the outline, clear of door swings and furniture already
    /// drawn, away from the dimension strip along the walls, and close to the centroid; and above all
    /// it must not touch any printed text. The label shrinks (down to 55 %) in rooms too small for it;
    /// when no position clears the text it sheds the ceiling line, then the area line, then shrinks
    /// the name to half size, and only if that still touches text is it placed where it overlaps least.
    static func addRoomLabel(_ g: RoomGeometry, _ context: inout Context) {
        let outline = g.outline
        guard outline.count >= 3, Polygon.area(outline) > 1e-6 else { return }
        let options = context.options

        var lines = [LabelLine(text: displayName(of: g.room), paperHeight: TextSize.roomName, bold: true,
                               color: Palette.ink)]
        if g.metrics.effectiveFloorArea.isFinite {
            lines.append(LabelLine(
                text: UnitFormatter.area(g.metrics.effectiveFloorArea, unit: options.units.area, precision: .compact),
                paperHeight: TextSize.roomDetail, bold: false, color: Palette.ink))
        }
        if let ceiling = dimensionText(g.room.ceilingHeight, options: options) {
            let ceilingVerified = options.markVerified && Provenance(g.room.ceilingHeight) == .site
            lines.append(LabelLine(text: "Ceiling " + ceiling, paperHeight: TextSize.roomDetail, bold: false,
                                   color: ceilingVerified ? Palette.verified : Palette.muted))
        }

        let inscribed = largestInscribedRectangle(of: outline)
        let box = Bounds2(points: outline) ?? Bounds2(min: .zero, max: Point2(1, 1))
        let detailSpacing = 0.55 * context.paper(TextSize.roomDetail)

        func measure(_ lines: [LabelLine], factor: Double) -> (width: Double, height: Double) {
            var width = 0.0
            var height = 0.0
            for (k, line) in lines.enumerated() {
                let h = context.paper(line.paperHeight) * factor
                width = Swift.max(width, textWidth(line.text, height: h, bold: line.bold))
                height += h + (k > 0 ? detailSpacing * factor : 0)
            }
            return (width, height)
        }

        // Size the block: shrink to fit the inscribed rectangle, dropping the ceiling line if still too tall.
        var factor = 1.0
        var usableWidth = box.width
        var widestLine = 0.92 * box.width
        if let r = inscribed {
            widestLine = 0.92 * r.width
            let strip = options.showDimensions
                ? dimensionOffset(textHeight: context.paper(TextSize.dimension)) + 1.2 * context.paper(TextSize.dimension)
                : 0
            usableWidth = Swift.max(0.35 * r.width, r.width - 2 * strip)
            let usableHeight = Swift.max(0.35 * r.height, r.height - 2 * strip)
            var size = measure(lines, factor: 1)
            factor = Swift.max(0.55, Swift.min(1, usableWidth / Swift.max(size.width, 1e-9),
                                                usableHeight / Swift.max(size.height, 1e-9)))
            size = measure(lines, factor: factor)
            if size.height > usableHeight * 1.05, lines.count > 2 {
                lines.removeLast()
            }
        }
        // A line wider than the room at the smallest size is cut short rather than spilling across the walls.
        for k in lines.indices {
            let h = context.paper(lines[k].paperHeight) * factor
            if textWidth(lines[k].text, height: h, bold: lines[k].bold) > widestLine {
                lines[k].text = HelveticaMetrics.truncated(lines[k].text, toWidth: widestLine / 1.02,
                                                           bold: lines[k].bold, fontSize: h / HelveticaMetrics.capHeight)
            }
        }
        lines.removeAll { $0.text.isEmpty }
        guard !lines.isEmpty else { return }

        // Variants, from the full label to the name alone at half size.
        var variants: [(lines: [LabelLine], factor: Double)] = [(lines, factor)]
        if lines.count > 2 { variants.append((Array(lines.prefix(2)), factor)) }
        if lines.count > 1 { variants.append(([lines[0]], factor)) }
        let smaller = Swift.max(0.5, factor * 0.75)
        if smaller < factor - 1e-9 { variants.append(([lines[0]], smaller)) }
        if 0.5 < smaller - 1e-9 { variants.append(([lines[0]], 0.5)) }

        // Candidate centres.
        let centroid = Polygon.centroid(outline)
        var candidates = [centroid]
        if let r = inscribed { candidates.append(r.centre) }
        for ix in 1...9 {
            for iy in 1...9 {
                candidates.append(Point2(box.min.x + box.width * Double(ix) / 10, box.min.y + box.height * Double(iy) / 10))
            }
        }
        let obstacles = context.obstacles.rects(intersecting: box.inset(by: -Swift.max(box.width, box.height)))
        let printedText = context.textBoxes.orientedBoxes(intersecting: box.inset(by: -Swift.max(box.width, box.height)))
        let dimensionStrip = options.showDimensions
            ? dimensionOffset(textHeight: context.paper(TextSize.dimension)) + 1.2 * context.paper(TextSize.dimension)
            : 0
        let diagonal = Swift.max(1e-6, Point2(box.width, box.height).length)

        struct Placement {
            var lines: [LabelLine]
            var factor: Double
            var centre: Point2
            var hard: Int
            var soft: Double
        }

        func best(for variant: (lines: [LabelLine], factor: Double), air: Double) -> Placement {
            let size = measure(variant.lines, factor: variant.factor)
            let blockArea = Swift.max(1e-9, size.width * size.height)
            // Line boxes relative to the block centre: (halfWidth, bottom, top) from the block's top edge.
            var offsets: [(halfWidth: Double, bottom: Double, top: Double)] = []
            var top = size.height / 2
            for line in variant.lines {
                let h = context.paper(line.paperHeight) * variant.factor
                let fontSize = h / HelveticaMetrics.capHeight
                let w = textWidth(line.text, height: h, bold: line.bold)
                let baseline = top - h
                offsets.append((w / 2, baseline - (hasDescender(line.text) ? HelveticaMetrics.descender * fontSize : 0), baseline + h))
                top -= h + detailSpacing * variant.factor
            }

            var result = Placement(lines: variant.lines, factor: variant.factor, centre: candidates[0],
                                   hard: Int.max, soft: Double.infinity)
            for c in candidates {
                let hw = size.width / 2, hh = size.height / 2
                let samples = [Point2(-hw, -hh), Point2(hw, -hh), Point2(hw, hh), Point2(-hw, hh),
                               Point2(0, -hh), Point2(0, hh), Point2(-hw, 0), Point2(hw, 0), .zero].map { c + $0 }
                var hard = 0
                for o in offsets {
                    let lineBox = Bounds2(min: Point2(c.x - o.halfWidth - air, c.y + o.bottom - air),
                                          max: Point2(c.x + o.halfWidth + air, c.y + o.top + air))
                    if printedText.contains(where: { text in
                        text.bounds.max.x > lineBox.min.x && text.bounds.min.x < lineBox.max.x
                            && text.bounds.max.y > lineBox.min.y && text.bounds.min.y < lineBox.max.y
                            && BoxIndex.convexOverlap(text.quad, [lineBox.min, Point2(lineBox.max.x, lineBox.min.y),
                                                                  lineBox.max, Point2(lineBox.min.x, lineBox.max.y)])
                    }) { hard += 1 }
                }
                if hard > result.hard { continue }

                var score = 0.0
                for sample in samples where !Polygon.contains(outline, sample) { score += 100 }
                var overlap = 0.0
                for o in obstacles {
                    let w = Swift.min(c.x + hw, o.max.x) - Swift.max(c.x - hw, o.min.x)
                    let h = Swift.min(c.y + hh, o.max.y) - Swift.max(c.y - hh, o.min.y)
                    if w > 0, h > 0 { overlap += w * h }
                }
                score += 20 * overlap / blockArea
                if dimensionStrip > 0 {
                    for sample in samples {
                        let d = distanceToOutline(sample, outline)
                        if d < dimensionStrip { score += 3 * (dimensionStrip - d) / dimensionStrip }
                    }
                }
                score += 0.5 * c.distance(to: centroid) / diagonal
                if hard < result.hard || score < result.soft - 1e-9 {
                    result.centre = c
                    result.hard = hard
                    result.soft = score
                }
            }
            return result
        }

        // First with a little air round every line (0.35 of a detail line's cap height: two numbers set end
        // to end on one baseline read as one), then, only if nothing clears, with the lines allowed to touch.
        var chosen: Placement?
        search: for air in [0.35 * context.paper(TextSize.roomDetail), 0] {
            for variant in variants {
                let placement = best(for: variant, air: air)
                if chosen == nil || placement.hard < chosen!.hard { chosen = placement }
                if placement.hard == 0 { break search }
            }
        }
        guard let picked = chosen, picked.centre.x.isFinite, picked.centre.y.isFinite else { return }
        if picked.hard > 0 { context.report.roomLabelsWithOverlap += 1 }
        context.report.droppedRoomLabelLines += lines.count - picked.lines.count

        // Stack the lines top to bottom around the centre; each baseline is the line's own cap height down.
        let size = measure(picked.lines, factor: picked.factor)
        guard size.width.isFinite, size.height.isFinite else { return }
        var top = picked.centre.y + size.height / 2
        for line in picked.lines {
            let h = context.paper(line.paperHeight) * picked.factor
            let placement = TextPlacement(layer: .roomLabels, string: line.text, at: Point2(picked.centre.x, top - h),
                                          paperHeight: line.paperHeight * picked.factor, rotation: 0,
                                          anchor: .center, color: line.color, bold: line.bold)
            context.reserve(placement)
            context.emit(placement)
            top -= h + detailSpacing * picked.factor
        }
    }

    // MARK: Label placement helpers

    /// Distance from `p` to the nearest edge of the closed polygon.
    static func distanceToOutline(_ p: Point2, _ polygon: [Point2]) -> Double {
        var best = Double.infinity
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            let t = lengthSquared > 1e-12 ? Swift.max(0, Swift.min(1, (p - a).dot(ab) / lengthSquared)) : 0
            best = Swift.min(best, p.distance(to: a + ab * t))
        }
        return best
    }

    // MARK: Inscribed rectangle

    /// The largest axis-aligned rectangle inside `polygon`, found on a grid of at most 240 x 240
    /// cells (cell size 0.05...0.25 m; coarser for an outline of very many edges). Returns its centre
    /// and size, or nil for a degenerate polygon.
    static func largestInscribedRectangle(of polygon: [Point2]) -> (centre: Point2, width: Double, height: Double)? {
        guard let box = Bounds2(points: polygon), box.width > 1e-6, box.height > 1e-6,
              box.width.isFinite, box.height.isFinite else { return nil }
        let cell = Swift.min(0.25, Swift.max(0.05, Swift.min(box.width, box.height) / 24))
        // Every cell is tested against every edge, so an outline of thousands of edges gets a coarser grid
        // (about 20 million edge tests in all; 240 cells a side up to roughly 70 edges).
        let limit = Swift.max(24, Swift.min(240, (2e7 / (5 * Double(polygon.count))).squareRoot().rounded(.down)))
        // Clamp as a Double first: an extent of 1e30 metres must not overflow the Int conversion.
        func cellCount(_ extent: Double) -> Int { Int(Swift.min(limit, Swift.max(1, (extent / cell).rounded(.up)))) }
        let nx = cellCount(box.width)
        let ny = cellCount(box.height)
        let cw = box.width / Double(nx)
        let ch = box.height / Double(ny)
        let inset = 1e-3

        // A cell counts when its corners (nudged inwards so boundary cells are not lost) and centre are inside.
        var filled = [[Bool]](repeating: [Bool](repeating: false, count: nx), count: ny)
        for j in 0..<ny {
            for i in 0..<nx {
                let x0 = box.min.x + Double(i) * cw, x1 = x0 + cw
                let y0 = box.min.y + Double(j) * ch, y1 = y0 + ch
                let probes = [Point2(x0 + inset * cw, y0 + inset * ch), Point2(x1 - inset * cw, y0 + inset * ch),
                              Point2(x1 - inset * cw, y1 - inset * ch), Point2(x0 + inset * cw, y1 - inset * ch),
                              Point2((x0 + x1) / 2, (y0 + y1) / 2)]
                filled[j][i] = probes.allSatisfy { Polygon.contains(polygon, $0) }
            }
        }

        var heights = [Int](repeating: 0, count: nx)
        var bestArea = 0.0
        var best = (left: 0, bottom: 0, width: 0, height: 0)
        for j in 0..<ny {
            for i in 0..<nx { heights[i] = filled[j][i] ? heights[i] + 1 : 0 }
            var stack: [Int] = []
            for i in 0...nx {
                let h = i < nx ? heights[i] : 0
                while let top = stack.last, heights[top] >= h {
                    stack.removeLast()
                    let rectHeight = heights[top]
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let rectWidth = i - left
                    let area = Double(rectWidth) * cw * Double(rectHeight) * ch
                    if rectHeight > 0, area > bestArea + 1e-12 {
                        bestArea = area
                        best = (left, j - rectHeight + 1, rectWidth, rectHeight)
                    }
                }
                stack.append(i)
            }
        }
        guard bestArea > 0 else { return nil }
        let centre = Point2(box.min.x + (Double(best.left) + Double(best.width) / 2) * cw,
                            box.min.y + (Double(best.bottom) + Double(best.height) / 2) * ch)
        return (centre, Double(best.width) * cw, Double(best.height) * ch)
    }
}
