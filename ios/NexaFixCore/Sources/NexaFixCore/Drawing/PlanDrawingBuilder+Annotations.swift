import Foundation

// Plan annotations: dimension lines, corner angles, opening size tags and room labels.
// Verified values are the ones printed, and `markVerified` adds the " v" that shows what was
// checked on site. A scanned value is never marked.

extension PlanDrawingBuilder {

    /// Walls shorter than this (metres) get no dimension line.
    static let minimumDimensionedWall = 0.4

    /// Corners within this many degrees of 90 print as a small square instead of a number.
    static let rightAngleMarkTolerance = 0.5

    // MARK: Text for measured values

    /// "4200 mm", or "4200 mm v" when `markVerified` is on and the value was checked on site.
    /// nil when the value is not a finite number: nothing is printed rather than "nan mm".
    static func dimensionText(_ measured: Measured, options: PlanOptions) -> String? {
        guard measured.value.isFinite else { return nil }
        let text = UnitFormatter.length(measured.value, unit: options.units.length, precision: .compact)
        return options.markVerified && measured.isVerified ? text + " v" : text
    }

    // MARK: Dimensions

    /// Where one wall's dimension line, ticks and text go.
    struct DimensionLayout {
        let wall: WallGeometry
        /// Ends of the dimension line, inside the room.
        let a: Point2
        let b: Point2
        /// nil when the length is not a finite number.
        let text: String?
        let textAnchor: Point2
        let textRotation: Double
        let isVerified: Bool
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
            layouts.append(DimensionLayout(
                wall: w, a: a, b: b, text: dimensionText(w.wall.length, options: context.options),
                textAnchor: (a + b) / 2 + up * gap, textRotation: rotation,
                isVerified: context.options.markVerified && w.wall.length.isVerified))
        }
        return layouts
    }

    /// One dimension line per wall, inside the room, parallel to the wall, with end ticks and the
    /// effective length centred above it. Text is rotated along the wall and kept upright.
    static func addDimensions(_ g: RoomGeometry, _ context: inout Context) {
        let tick = context.paper(1.2)
        for layout in dimensionLayouts(g, context) {
            let w = layout.wall
            context.line(.dimensions, layout.a, layout.b, weight: Weight.dimension, color: Palette.muted)
            addTick(at: layout.a, lineDirection: w.direction, halfLength: tick, &context)
            addTick(at: layout.b, lineDirection: w.direction, halfLength: tick, &context)
            guard let text = layout.text else { continue }
            context.text(.dimensions, text, at: layout.textAnchor,
                         paperHeight: TextSize.dimension, rotation: layout.textRotation, anchor: .center,
                         color: layout.isVerified ? Palette.verified : Palette.ink)
        }
    }

    /// Distance of a dimension line from its wall: 0.25 m, or 2.5 text heights where the text is
    /// taller than that (small scales), so the text never touches the wall.
    static func dimensionOffset(textHeight: Double) -> Double {
        Swift.max(0.25, 2.5 * textHeight)
    }

    // MARK: Angles

    /// An arc and the angle in degrees inside every corner that is not a straight continuation.
    ///
    /// - Within 0.5 degrees of 90: a small square mark, no text.
    /// - Out of square (`RoomMetrics.outOfSquareCorners`: more than `squareTolerance` from 90, not
    ///   reflex): arc and text in the warning colour.
    /// - Anything else (slightly off square, obtuse reflex corners of L-shapes): arc and text in muted ink.
    static func addAngles(_ g: RoomGeometry, _ context: inout Context) {
        let outline = g.outline
        let n = outline.count
        guard n >= 3 else { return }
        let outOfSquare = Set(g.metrics.outOfSquareCorners.map(\.index))
        let textHeight = context.paper(TextSize.angle)
        let dimensionHeight = context.paper(TextSize.dimension)
        // Keep the number clear of the dimension lines and their text along both walls.
        let clearance = context.options.showDimensions
            ? dimensionOffset(textHeight: dimensionHeight) + 1.6 * dimensionHeight
            : context.paper(2.0)

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
                addRightAngleMark(corner: p, towardsNext: nextDirection, towardsPrevious: previousDirection,
                                  size: Swift.min(context.paper(2.0), 0.3 * shortest), &context)
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
            context.add(.angles, .arc(center: p, radius: radius,
                                      startAngle: normalizedDegrees(start),
                                      endAngle: normalizedDegrees(start + angle),
                                      StrokeStyle(weight: Weight.angleArc, color: color)))

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
            context.text(.angles, text, at: baselineCentre(of: centre, height: textHeight, rotation: 0),
                         paperHeight: TextSize.angle, rotation: 0, anchor: .center, color: color,
                         bold: outOfSquareCorner)
        }
    }

    // MARK: Opening tags

    /// A short size tag for each door, window and opening, on the room side of its wall, just
    /// inside the wall face and centred on the opening: "D 900x2100", "W 1500x1400 H900" (H is
    /// the sill height). Values are the effective (verified-if-present) sizes in the chosen unit;
    /// non-millimetre units add the unit symbol. The tag sits in the strip between the wall and
    /// the dimension line, so it never lands on the wall band of the room next door.
    static func addOpeningTags(_ g: RoomGeometry, _ context: inout Context) {
        let height = context.paper(TextSize.openingTag)
        let gap = context.paper(0.6)
        for w in g.walls where w.isUsable && w.wall.kind == .solid {
            for span in spans(on: w, in: g.room) {
                guard let tag = openingTag(span.opening, options: context.options) else { continue }
                let rotation = uprightRotation(of: w.direction)
                let radians = rotation * Double.pi / 180
                let up = Point2(-sin(radians), cos(radians))
                // Text extends from its baseline along "up": into the room when that is the way up,
                // otherwise towards the wall, so the baseline moves out by one cap height.
                let inset = gap + (up.dot(w.inward) >= 0 ? 0 : height)
                let at = w.point(at: span.mid, inset: inset)
                let allVerified = tagValues(span.opening).allSatisfy { $0.isVerified }
                context.text(layer(for: span.opening.kind), tag, at: at, paperHeight: TextSize.openingTag,
                             rotation: rotation, anchor: .center,
                             color: context.options.markVerified && allVerified ? Palette.verified : Palette.muted)
            }
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
        func number(_ m: Measured) -> String { tagNumber(m.value, unit: unit) }
        let prefix: String
        switch o.kind {
        case .door: prefix = "D"
        case .window: prefix = "W"
        case .opening: prefix = "O"
        }
        let values = tagValues(o)
        let verified = values.map(\.isVerified)
        let mark = options.markVerified
        let anyVerified = mark && verified.contains(true)
        let allVerified = mark && verified.allSatisfy { $0 }

        // All verified: one " v" at the end. Mixed: a "v" right after each verified number.
        func shown(_ index: Int) -> String {
            number(values[index]) + (anyVerified && !allVerified && verified[index] ? "v" : "")
        }
        let separator = anyVerified && !allVerified ? " x " : "x"
        var text = "\(prefix) \(shown(0))\(separator)\(shown(1))"
        if values.count == 3 { text += " H\(shown(2))" }
        if allVerified { text += " v" }
        if let symbol = tagUnitSymbol(unit) { text += " " + symbol }
        return text
    }

    /// Plain number for a tag: no unit text, no trailing zeros. Feet-and-inches fall back to decimal inches.
    static func tagNumber(_ metres: Double, unit: LengthUnit) -> String {
        let effective = unit == .feetAndInches ? LengthUnit.inches : unit
        // Inches to one decimal keeps imperial tags short; the other units keep full precision.
        let text = UnitFormatter.length(metres, unit: effective, precision: effective == .inches ? .compact : .precise,
                                        includeUnit: false)
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

    // MARK: Room labels

    private struct LabelLine {
        let text: String
        let paperHeight: Double
        let bold: Bool
        let color: DrawColor
    }

    /// Room name (bold), floor area and ceiling height, centred on a point inside the room.
    ///
    /// Candidate centres are the centroid, the centre of the largest inscribed axis-aligned
    /// rectangle (found on a grid, so an L-shaped room is labelled in its main leg) and a 9 x 9 grid.
    /// Each is scored: it must be inside the outline, clear of text, door swings and furniture already
    /// drawn, away from the dimension strip along the walls, and close to the centroid. The label
    /// shrinks (down to 55 %) in rooms too small for it and drops the ceiling line if still too tall.
    static func addRoomLabel(_ g: RoomGeometry, _ context: inout Context) {
        let outline = g.outline
        guard outline.count >= 3, Polygon.area(outline) > 1e-6 else { return }
        let options = context.options
        let name = g.room.name.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = [LabelLine(text: name.isEmpty ? g.room.kind.displayName : name,
                               paperHeight: TextSize.roomName, bold: true, color: Palette.ink)]
        if g.metrics.effectiveFloorArea.isFinite {
            lines.append(LabelLine(
                text: UnitFormatter.area(g.metrics.effectiveFloorArea, unit: options.units.area, precision: .compact),
                paperHeight: TextSize.roomDetail, bold: false, color: Palette.ink))
        }
        if let ceiling = dimensionText(g.room.ceilingHeight, options: options) {
            let ceilingVerified = options.markVerified && g.room.ceilingHeight.isVerified
            lines.append(LabelLine(text: "Ceiling " + ceiling, paperHeight: TextSize.roomDetail, bold: false,
                                   color: ceilingVerified ? Palette.verified : Palette.muted))
        }

        let inscribed = largestInscribedRectangle(of: outline)

        // Size the block: shrink to fit the inscribed rectangle, dropping the ceiling line if still too tall.
        func measure(_ lines: [LabelLine], factor: Double) -> (width: Double, height: Double) {
            var width = 0.0
            var height = 0.0
            for (k, line) in lines.enumerated() {
                let h = context.paper(line.paperHeight) * factor
                width = Swift.max(width, textWidth(line.text, height: h, bold: line.bold))
                height += h + (k > 0 ? 0.55 * context.paper(TextSize.roomDetail) * factor : 0)
            }
            return (width, height)
        }
        var factor = 1.0
        if let r = inscribed {
            let strip = options.showDimensions
                ? dimensionOffset(textHeight: context.paper(TextSize.dimension)) + 1.2 * context.paper(TextSize.dimension)
                : 0
            let usableWidth = Swift.max(0.35 * r.width, r.width - 2 * strip)
            let usableHeight = Swift.max(0.35 * r.height, r.height - 2 * strip)
            var size = measure(lines, factor: 1)
            factor = Swift.max(0.55, Swift.min(1, usableWidth / Swift.max(size.width, 1e-9),
                                                usableHeight / Swift.max(size.height, 1e-9)))
            size = measure(lines, factor: factor)
            if size.height > usableHeight * 1.05, lines.count > 2 {
                lines.removeLast()
            }
        }
        let size = measure(lines, factor: factor)
        guard size.width.isFinite, size.height.isFinite else { return }

        // Score candidate centres: a label must be inside the room, clear of text, door swings and
        // furniture already drawn, away from the dimension strip along the walls, and near the centroid.
        let box = Bounds2(points: outline) ?? Bounds2(min: .zero, max: Point2(1, 1))
        let centroid = Polygon.centroid(outline)
        var candidates = [centroid]
        if let r = inscribed { candidates.append(r.centre) }
        for ix in 1...9 {
            for iy in 1...9 {
                candidates.append(Point2(box.min.x + box.width * Double(ix) / 10, box.min.y + box.height * Double(iy) / 10))
            }
        }
        let obstacles = obstacleRects(in: context, near: box)
        let dimensionStrip = options.showDimensions
            ? dimensionOffset(textHeight: context.paper(TextSize.dimension)) + 1.2 * context.paper(TextSize.dimension)
            : 0
        let diagonal = Swift.max(1e-6, Point2(box.width, box.height).length)
        let blockArea = Swift.max(1e-9, size.width * size.height)

        func penalty(_ c: Point2) -> Double {
            let hw = size.width / 2, hh = size.height / 2
            let samples = [Point2(-hw, -hh), Point2(hw, -hh), Point2(hw, hh), Point2(-hw, hh),
                           Point2(0, -hh), Point2(0, hh), Point2(-hw, 0), Point2(hw, 0), .zero].map { c + $0 }
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
            return score + 0.5 * c.distance(to: centroid) / diagonal
        }
        var centre = candidates[0]
        var bestScore = Double.infinity
        for c in candidates {
            let score = penalty(c)
            if score < bestScore - 1e-9 { bestScore = score; centre = c }
        }

        // Stack the lines top to bottom around the centre; each baseline is the line's own cap height down.
        let spacing = 0.55 * context.paper(TextSize.roomDetail) * factor
        var top = centre.y + size.height / 2
        for line in lines {
            let h = context.paper(line.paperHeight) * factor
            context.add(.roomLabels, .text(line.text, at: Point2(centre.x, top - h), height: h, rotation: 0,
                                           anchor: .center, color: line.color, bold: line.bold))
            top -= h + spacing
        }
    }

    // MARK: Label placement helpers

    /// Boxes a room label should keep clear of: every text already drawn, door swings and furniture
    /// footprints, limited to those that touch `area`.
    static func obstacleRects(in context: Context, near area: Bounds2) -> [Bounds2] {
        var rects: [Bounds2] = []
        for item in context.primitives {
            let points: [Point2]
            switch item.primitive {
            case .text:
                points = extentPoints(of: item.primitive)
            case let .arc(center, _, _, _, _) where item.layer == .doors:
                points = extentPoints(of: item.primitive) + [center]
            case .polyline where item.layer == .furniture:
                points = extentPoints(of: item.primitive)
            default:
                continue
            }
            guard let r = Bounds2(points: points) else { continue }
            if r.max.x < area.min.x || r.min.x > area.max.x || r.max.y < area.min.y || r.min.y > area.max.y { continue }
            rects.append(r)
        }
        return rects
    }

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
    /// cells (cell size 0.05...0.25 m). Returns its centre and size, or nil for a degenerate polygon.
    static func largestInscribedRectangle(of polygon: [Point2]) -> (centre: Point2, width: Double, height: Double)? {
        guard let box = Bounds2(points: polygon), box.width > 1e-6, box.height > 1e-6 else { return nil }
        let cell = Swift.min(0.25, Swift.max(0.05, Swift.min(box.width, box.height) / 24))
        let nx = Swift.min(240, Swift.max(1, Int((box.width / cell).rounded(.up))))
        let ny = Swift.min(240, Swift.max(1, Int((box.height / cell).rounded(.up))))
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
