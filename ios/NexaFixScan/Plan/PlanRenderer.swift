import SwiftUI
import NexaFixCore

/// Draws a `PlanDrawing` into a SwiftUI `Canvas` at a `PlanViewport`.
///
/// The drawing's colours are print colours (ink on white paper). Each one is classified by
/// `PlanColorRole` and drawn with the matching palette token, so ink becomes ink-on-background in dark mode
/// while verified green and out-of-square red keep their meaning. Weights, text sizes and fades come from
/// `PlanRenderMetrics`, which is unit-tested in NexaFixCore.
///
/// One renderer is built per drawing (it prepares culling boxes and room labels once) and drawn many times.
/// It is a class so views that hold it compare by identity instead of walking hundreds of primitives.
final class PlanRenderer {

    /// What to draw.
    struct Options {
        /// Only these layers; nil draws all of them.
        var layers: Set<PlanLayer>?
        /// Draw room names and areas as screen-sized labels (needs `rooms`).
        var drawsRoomLabels = true

        static let standard = Options()
        /// For the small plan on a property card: structure only. Text would be too small to read anyway.
        static let thumbnail = Options(layers: [.walls, .wallsOpen, .doors, .windows, .openings],
                                       drawsRoomLabels: false)
    }

    private struct Item {
        let layer: PlanLayer
        let primitive: DrawingPrimitive
        /// A plan-space box that certainly contains the primitive, for culling.
        let bounds: Bounds2
    }

    /// A room's name and area, drawn at a fixed screen size where the room is big enough to hold them.
    private struct RoomLabel {
        let name: String
        let area: String
        let centre: Point2
        let bounds: Bounds2
    }

    let drawing: PlanDrawing
    private let items: [Item]
    private let roomLabels: [RoomLabel]

    /// - Parameters:
    ///   - rooms: When not empty, room names and areas are drawn from these at a readable fixed size, and the
    ///     drawing's own room-label text (paper-sized, so unreadable when zoomed out) is skipped.
    ///   - units: How the area in a room label is written.
    init(drawing: PlanDrawing, rooms: [Room] = [], units: DisplayUnits = .default, options: Options = .standard) {
        self.drawing = drawing
        let useRoomLabels = options.drawsRoomLabels && !rooms.isEmpty

        var prepared: [Item] = []
        prepared.reserveCapacity(drawing.primitives.count)
        for entry in drawing.primitives {
            if let layers = options.layers, !layers.contains(entry.layer) { continue }
            if useRoomLabels, entry.layer == .roomLabels, case .text = entry.primitive { continue }
            guard let box = PlanRenderer.bounds(of: entry.primitive) else { continue }
            prepared.append(Item(layer: entry.layer, primitive: entry.primitive, bounds: box))
        }
        self.items = prepared

        var labels: [RoomLabel] = []
        if useRoomLabels {
            for room in rooms where room.walls.count >= 3 {
                guard let box = Bounds2(points: room.outline),
                      let centre = OverlayBuilder.labelPoint(in: room.outline) else { continue }
                let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                labels.append(RoomLabel(
                    name: trimmed.isEmpty ? room.kind.displayName : trimmed,
                    area: UnitFormatter.area(room.metrics.effectiveFloorArea, unit: units.area, precision: .compact),
                    centre: centre, bounds: box))
            }
        }
        self.roomLabels = labels
    }

    // MARK: Drawing

    /// Draws the plan.
    /// - Parameters:
    ///   - size: The canvas size, points.
    ///   - highlight: The selection outline, drawn in the accent colour on top of the plan.
    ///   - increasedContrast: Thickens lines a little (Increased Contrast).
    func draw(_ context: inout GraphicsContext, size: CGSize, viewport: PlanViewport, highlight: PlanHighlight?,
              increasedContrast: Bool) {
        guard size.width > 0, size.height > 0, viewport.scale.isFinite, viewport.scale > 0 else { return }
        let screen = ScreenSize(width: Double(size.width), height: Double(size.height))
        let visible = viewport.visiblePlanBounds(in: screen, margin: 40)
        let boost: CGFloat = increasedContrast ? 0.5 : 0

        for item in items where PlanRenderer.intersects(item.bounds, visible) {
            switch item.primitive {
            case let .line(a, b, style):
                var path = Path()
                path.move(to: point(viewport.screen(a)))
                path.addLine(to: point(viewport.screen(b)))
                stroke(&context, path, style: style, boost: boost)

            case let .polyline(points, closed, strokeStyle, fill):
                guard points.count >= 2 else { continue }
                var path = Path()
                path.move(to: point(viewport.screen(points[0])))
                for p in points.dropFirst() { path.addLine(to: point(viewport.screen(p))) }
                if closed || fill != nil { path.closeSubpath() }
                if let fill { context.fill(path, with: .color(PlanRenderer.color(fill))) }
                if let strokeStyle { stroke(&context, path, style: strokeStyle, boost: boost) }

            case let .arc(center, radius, startAngle, endAngle, style):
                let sweep = PlanRenderer.sweep(from: startAngle, to: endAngle)
                let segments = PlanRenderMetrics.arcSegments(radiusPoints: radius * viewport.scale, sweepDegrees: sweep)
                var path = Path()
                for k in 0...segments {
                    let degrees = startAngle + sweep * Double(k) / Double(segments)
                    let radians = degrees * Double.pi / 180
                    let p = center + Point2(cos(radians), sin(radians)) * radius
                    let s = point(viewport.screen(p))
                    if k == 0 { path.move(to: s) } else { path.addLine(to: s) }
                }
                stroke(&context, path, style: style, boost: boost)

            case let .circle(center, radius, style):
                let c = viewport.screen(center)
                let r = radius * viewport.scale
                guard r > 0.2 else { continue }
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                stroke(&context, Path(ellipseIn: rect), style: style, boost: boost)

            case let .text(string, at, height, rotation, anchor, color, bold):
                drawText(&context, string, at: at, height: height, rotation: rotation, anchor: anchor,
                         color: color, bold: bold, viewport: viewport)
            }
        }

        if let highlight { drawHighlight(&context, highlight, viewport: viewport) }
        drawRoomLabels(&context, viewport: viewport)
    }

    // MARK: Strokes

    private func stroke(_ context: inout GraphicsContext, _ path: Path, style: DrawStroke, boost: CGFloat) {
        let width = CGFloat(PlanRenderMetrics.strokeWidth(forPaperWeight: style.weight)) + boost
        let shading = GraphicsContext.Shading.color(PlanRenderer.color(style.color))
        if style.dashed {
            let dash = PlanRenderMetrics.dashPattern(forStrokeWidth: Double(width)).map { CGFloat($0) }
            context.stroke(path, with: shading, style: SwiftUI.StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .miter, dash: dash))
        } else {
            context.stroke(path, with: shading, style: SwiftUI.StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Text

    private func drawText(_ context: inout GraphicsContext, _ string: String, at: Point2, height: Double,
                          rotation: Double, anchor: TextAnchor, color: DrawColor, bold: Bool, viewport: PlanViewport) {
        let fontSize = PlanRenderMetrics.fontSize(capHeightMetres: height, scale: viewport.scale)
        let opacity = PlanRenderMetrics.textOpacity(forFontSize: fontSize)
        guard opacity > 0.01, !string.isEmpty else { return }

        let text = Text(verbatim: string)
            .font(.system(size: CGFloat(fontSize), weight: bold ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(PlanRenderer.color(color))
        let origin = viewport.screen(at)

        var layer = context
        layer.opacity = context.opacity * opacity
        layer.translateBy(x: origin.x, y: origin.y)
        // Plan angles run counter-clockwise with y up; on screen (y down) that is the other way round.
        layer.rotate(by: .degrees(-rotation))

        // The drawing's anchor is on the baseline: measure the text and put its baseline there.
        let resolved = layer.resolve(text)
        let measured = resolved.measure(in: CGSize(width: 10_000, height: 10_000))
        let baseline = resolved.firstBaseline(in: measured)
        let dx: CGFloat
        switch anchor {
        case .left: dx = 0
        case .center: dx = -measured.width / 2
        case .right: dx = -measured.width
        }
        layer.draw(text, at: CGPoint(x: dx, y: -baseline), anchor: .topLeading)
    }

    // MARK: Room labels

    private func drawRoomLabels(_ context: inout GraphicsContext, viewport: PlanViewport) {
        guard !roomLabels.isEmpty else { return }
        let nameSize = PlanRenderMetrics.roomLabelMinimumFontSize + 1
        let areaSize = PlanRenderMetrics.roomLabelMinimumFontSize
        for label in roomLabels {
            let widthPoints = label.bounds.width * viewport.scale
            let heightPoints = label.bounds.height * viewport.scale
            let nameWidth = PlanDrawingBuilder.textWidth(label.name, height: nameSize * HelveticaMetrics.capHeight, bold: true)
            let areaWidth = PlanDrawingBuilder.textWidth(label.area, height: areaSize * HelveticaMetrics.capHeight)
            let centre = viewport.screen(label.centre)

            // The name needs the room to be wider than the text and tall enough for a line; the area, a second line.
            let nameFit = PlanRenderer.fade(available: widthPoints * 0.9, needed: nameWidth)
                * PlanRenderer.fade(available: heightPoints, needed: nameSize * 2.2)
            guard nameFit > 0.01 else { continue }
            let areaFit = PlanRenderer.fade(available: widthPoints * 0.9, needed: areaWidth)
                * PlanRenderer.fade(available: heightPoints, needed: (nameSize + areaSize) * 2.4)

            var layer = context
            layer.opacity = context.opacity * nameFit
            let nameY = areaFit > 0.01 ? centre.y - nameSize * 0.6 : centre.y
            layer.draw(Text(verbatim: label.name)
                        .font(.system(size: CGFloat(nameSize), weight: .semibold))
                        .foregroundStyle(Palette.ink),
                       at: CGPoint(x: centre.x, y: nameY), anchor: .center)
            if areaFit > 0.01 {
                var areaLayer = context
                areaLayer.opacity = context.opacity * nameFit * areaFit
                areaLayer.draw(Text(verbatim: label.area)
                                .font(.system(size: CGFloat(areaSize), weight: .regular).monospacedDigit())
                                .foregroundStyle(Palette.muted),
                               at: CGPoint(x: centre.x, y: centre.y + areaSize * 0.9), anchor: .center)
            }
        }
    }

    /// 0 when `needed` does not fit in `available`, 1 when it fits with a quarter to spare, a ramp between.
    private static func fade(available: Double, needed: Double) -> Double {
        guard available.isFinite, needed.isFinite, needed > 0 else { return 0 }
        let t = (available - needed) / (needed * 0.25)
        return Swift.min(Swift.max(t, 0), 1)
    }

    // MARK: Selection

    private func drawHighlight(_ context: inout GraphicsContext, _ highlight: PlanHighlight, viewport: PlanViewport) {
        let points = highlight.points.map { point(viewport.screen($0)) }
        guard let first = points.first else { return }
        let accent = GraphicsContext.Shading.color(Palette.accent)

        switch highlight.kind {
        case .point:
            let ring = Path(ellipseIn: CGRect(x: first.x - 10, y: first.y - 10, width: 20, height: 20))
            context.fill(ring, with: .color(Palette.accent.opacity(0.16)))
            context.stroke(ring, with: accent, lineWidth: 2.5)
            context.fill(Path(ellipseIn: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6)), with: accent)

        case .polyline:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            // A soft wide band under a firm line: easy to see and easy to tell from the wall it sits on.
            context.stroke(path, with: .color(Palette.accent.opacity(0.28)),
                           style: SwiftUI.StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: accent, style: SwiftUI.StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

        case .polygon:
            guard points.count >= 3 else { return }
            var path = Path()
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.fill(path, with: .color(Palette.accent.opacity(0.14)))
            context.stroke(path, with: accent, style: SwiftUI.StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Helpers

    private func point(_ p: Point2) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// Counter-clockwise sweep in degrees from `start` to `end` (the drawing normalises both to 0..<360 and lets
    /// an arc wrap past 360).
    private static func sweep(from start: Double, to end: Double) -> Double {
        var s = (end - start).truncatingRemainder(dividingBy: 360)
        if s <= 0 { s += 360 }
        return s
    }

    /// The palette token for a print colour.
    static func color(_ draw: DrawColor) -> Color {
        switch PlanColorRole.role(of: draw) {
        case .ink: return Palette.ink
        case .paper: return Palette.background
        case .hairline: return Palette.line
        case .muted: return Palette.muted
        case .bronze: return Palette.accent
        case .verified: return Palette.verified
        case .warning: return Palette.critical
        // The light-grey furniture fill, as a veil of the hairline colour so it stays quiet in dark mode.
        case .furnitureFill: return Palette.line.opacity(0.55)
        case .custom(let c): return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
        }
    }

    private static func intersects(_ a: Bounds2, _ b: Bounds2) -> Bool {
        a.max.x >= b.min.x && a.min.x <= b.max.x && a.max.y >= b.min.y && a.min.y <= b.max.y
    }

    /// A box that certainly contains a primitive (text by a generous square around its anchor).
    private static func bounds(of primitive: DrawingPrimitive) -> Bounds2? {
        func finite(_ p: Point2) -> Bool { p.x.isFinite && p.y.isFinite }
        switch primitive {
        case let .line(a, b, _):
            guard finite(a), finite(b) else { return nil }
            return Bounds2(points: [a, b])
        case let .polyline(points, _, _, _):
            guard points.allSatisfy(finite) else { return nil }
            return Bounds2(points: points)
        case let .arc(center, radius, _, _, _), let .circle(center, radius, _):
            guard finite(center), radius.isFinite else { return nil }
            return Bounds2(min: Point2(center.x - radius, center.y - radius), max: Point2(center.x + radius, center.y + radius))
        case let .text(string, at, height, _, _, _, bold):
            guard finite(at), height.isFinite, height > 0 else { return nil }
            let reach = PlanDrawingBuilder.textWidth(string, height: height, bold: bold) + 2 * height
            return Bounds2(min: Point2(at.x - reach, at.y - reach), max: Point2(at.x + reach, at.y + reach))
        }
    }
}
