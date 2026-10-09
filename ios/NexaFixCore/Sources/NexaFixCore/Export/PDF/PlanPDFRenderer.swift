import Foundation

// The floor-plan PDF: one page per floor with the plan at a standard scale, then a room schedule.
// Pure Swift on top of `PDFWriter`; the plans come from `PlanDrawingBuilder`, the same vector
// description the DXF writer and the in-app plan view use.

// MARK: - Options

public enum PDFPaper: String, Codable, CaseIterable, Sendable {
    case a4, a3

    public var displayName: String { self == .a4 ? "A4" : "A3" }
    /// Short side of the sheet, millimetres.
    public var shortSideMM: Double { self == .a4 ? 210 : 297 }
    /// Long side of the sheet, millimetres.
    public var longSideMM: Double { self == .a4 ? 297 : 420 }
}

public enum PDFOrientation: String, Codable, CaseIterable, Sendable {
    /// Plans: whichever orientation allows the larger scale. The schedule: portrait.
    case auto
    case portrait
    case landscape
}

public enum PlanPDFScale: Hashable, Codable, Sendable {
    /// The largest standard scale (1:20 ... 1:500) at which the plan still fits the drawing area.
    case auto
    /// This scale denominator (50 = 1:50). When the plan does not fit, the renderer steps down to
    /// the next smaller standard scale rather than clip the drawing; the title block always shows
    /// the scale actually used.
    case fixed(Double)
}

public struct PlanPDFOptions: Codable, Hashable, Sendable {
    public var paper: PDFPaper
    public var orientation: PDFOrientation
    public var scale: PlanPDFScale
    public var units: DisplayUnits
    public var showDimensions: Bool
    public var showAngles: Bool
    public var showFurniture: Bool
    /// Add the final "Room schedule" page(s).
    public var includeSchedule: Bool
    /// Offset from UTC used to print the date in the title block (default +04:00, Gulf Standard Time).
    public var utcOffsetMinutes: Int

    public init(paper: PDFPaper = .a3, orientation: PDFOrientation = .auto, scale: PlanPDFScale = .auto,
                units: DisplayUnits = .default, showDimensions: Bool = true, showAngles: Bool = true,
                showFurniture: Bool = true, includeSchedule: Bool = true, utcOffsetMinutes: Int = 240) {
        self.paper = paper
        self.orientation = orientation
        self.scale = scale
        self.units = units
        self.showDimensions = showDimensions
        self.showAngles = showAngles
        self.showFurniture = showFurniture
        self.includeSchedule = includeSchedule
        self.utcOffsetMinutes = utcOffsetMinutes
    }
}

/// What one page of the PDF will contain, without rendering it. The export sheet uses this to say
/// "Level 1: 1:50 on A3 landscape".
public struct PlanPDFPageInfo: Hashable, Sendable {
    public enum Kind: String, Sendable { case plan, schedule }

    public let kind: Kind
    /// Floor name for a plan page, "Room schedule" for a schedule page.
    public let title: String
    public let paper: PDFPaper
    public let isLandscape: Bool
    /// Scale denominator actually used (plans only).
    public let scale: Double?

    public var widthMM: Double { isLandscape ? paper.longSideMM : paper.shortSideMM }
    public var heightMM: Double { isLandscape ? paper.shortSideMM : paper.longSideMM }
    /// "1:50" for a plan, "NTS" (not to scale) for the schedule.
    public var scaleLabel: String { scale.map(PlanPDFRenderer.scaleLabel) ?? "NTS" }
}

// MARK: - Renderer

public enum PlanPDFRenderer {

    /// Standard scale denominators, largest drawing first.
    public static let standardScales: [Double] = [20, 25, 50, 75, 100, 150, 200, 250, 500]
    /// Used only when a plan is too large even for 1:500 on the chosen sheet.
    static let fallbackScales: [Double] = [750, 1000, 1500, 2000, 5000, 10000]

    /// "1:50".
    public static func scaleLabel(_ denominator: Double) -> String {
        "1:\(Int(denominator.rounded()))"
    }

    /// Render the property: a plan page per floor, then the room schedule if requested. A property
    /// with no floors still yields a one-page document. `now` is the creation date and the date in
    /// the title block; nothing here reads the clock.
    public static func render(property: Property, options: PlanPDFOptions, now: Date) -> Data {
        let pages = makePages(property: property, options: options)
        var writer = PDFWriter(
            title: property.name.isEmpty ? "NexaFix site survey" : "\(property.name) - floor plans",
            author: "",
            subject: "Site survey floor plans and room schedule",
            keywords: "NexaFix, site survey, floor plan, LiDAR",
            creationDate: now)
        for (index, page) in pages.enumerated() {
            writer.addPage(drawPage(page, index: index, count: pages.count, property: property,
                                    options: options, now: now))
        }
        return writer.data()
    }

    /// The pages `render` produces, with the orientation and scale chosen for each.
    public static func pageInfos(property: Property, options: PlanPDFOptions) -> [PlanPDFPageInfo] {
        makePages(property: property, options: options).map(\.info)
    }

    // MARK: Page planning

    struct PagePlan {
        enum Content {
            case plan(PlanDrawing, message: String?)
            case schedule(rows: [ScheduleRow], continued: Bool, isLast: Bool)
        }
        var info: PlanPDFPageInfo
        var content: Content
    }

    static func makePages(property: Property, options: PlanPDFOptions) -> [PagePlan] {
        var pages: [PagePlan] = []
        if property.floors.isEmpty {
            pages.append(planPage(floor: Floor(name: "No floors"), property: property, options: options,
                                  emptyMessage: "No floors have been scanned yet."))
        }
        for floor in property.floors {
            pages.append(planPage(floor: floor, property: property, options: options,
                                  emptyMessage: "No rooms have been scanned on this floor."))
        }
        if options.includeSchedule {
            pages += schedulePages(property: property, options: options)
        }
        return pages
    }

    /// Candidate denominators in the order they are tried (largest drawing first).
    static func candidateScales(_ choice: PlanPDFScale) -> [Double] {
        let all = standardScales + fallbackScales
        if case .fixed(let s) = choice, s.isFinite, s > 0 {
            return [s] + all.filter { $0 > s }
        }
        return all
    }

    static func planOptions(scale: Double, from options: PlanPDFOptions) -> PlanOptions {
        PlanOptions(scale: scale, units: options.units, showDimensions: options.showDimensions,
                    showAngles: options.showAngles, showFurniture: options.showFurniture,
                    showRoomLabels: true, showOpeningSizes: options.showDimensions, markVerified: true)
    }

    private static func planPage(floor: Floor, property: Property, options: PlanPDFOptions,
                                 emptyMessage: String) -> PagePlan {
        let orientations: [Bool]   // isLandscape candidates
        switch options.orientation {
        case .auto: orientations = [true, false]
        case .landscape: orientations = [true]
        case .portrait: orientations = [false]
        }

        // Nothing to draw: a calm empty sheet at the requested (or default) scale. Only rooms the
        // builder will draw (three or more walls, all corners finite) count.
        let drawable = floor.rooms.filter { room in
            room.walls.count >= 3 && room.walls.allSatisfy {
                $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite
            }
        }
        let outlineBounds = drawable.compactMap { Bounds2(points: $0.outline) }
            .reduce(nil) { (acc: Bounds2?, b: Bounds2) -> Bounds2? in acc.map { $0.union(b) } ?? b }
        guard let minimum = outlineBounds else {
            var scale = 50.0
            if case .fixed(let s) = options.scale, s.isFinite, s > 0 { scale = s }
            let drawing = PlanDrawingBuilder.build(floor: floor, property: property,
                                                   options: planOptions(scale: scale, from: options))
            let landscape = orientations[0]
            return PagePlan(info: PlanPDFPageInfo(kind: .plan, title: floor.name, paper: options.paper,
                                                  isLandscape: landscape, scale: scale),
                            content: .plan(drawing, message: emptyMessage))
        }

        var best: (landscape: Bool, scale: Double, drawing: PlanDrawing, fill: Double, fits: Bool)?
        for landscape in orientations {
            let sheet = Sheet(paper: options.paper, isLandscape: landscape)
            let area = sheet.fitArea
            var chosen: (Double, PlanDrawing, Double, Bool)?
            for scale in candidateScales(options.scale) {
                // The drawing always covers the room outlines, so a scale that cannot hold them is skipped unbuilt.
                if minimum.width * 1000 / scale > area.width + 1e-6 || minimum.height * 1000 / scale > area.height + 1e-6 {
                    continue
                }
                let drawing = PlanDrawingBuilder.build(floor: floor, property: property,
                                                       options: planOptions(scale: scale, from: options))
                let w = drawing.bounds.width * 1000 / scale
                let h = drawing.bounds.height * 1000 / scale
                if w <= area.width + 1e-6, h <= area.height + 1e-6 {
                    chosen = (scale, drawing, (w * h) / (area.width * area.height), true)
                    break
                }
            }
            if chosen == nil {
                // Does not fit anywhere: smallest scale, clipped to the sheet.
                let scale = candidateScales(options.scale).last ?? 10000
                let drawing = PlanDrawingBuilder.build(floor: floor, property: property,
                                                       options: planOptions(scale: scale, from: options))
                chosen = (scale, drawing, 1, false)
            }
            guard let c = chosen else { continue }
            let candidate = (landscape: landscape, scale: c.0, drawing: c.1, fill: c.2, fits: c.3)
            if let current = best {
                let better = candidate.fits != current.fits ? candidate.fits
                    : candidate.scale != current.scale ? candidate.scale < current.scale
                    : candidate.fill > current.fill + 1e-9
                if better { best = candidate }
            } else {
                best = candidate
            }
        }
        // `orientations` is never empty and `chosen` is always set, so `best` is non-nil; the guard is belt and braces.
        guard let result = best else {
            return PagePlan(info: PlanPDFPageInfo(kind: .plan, title: floor.name, paper: options.paper,
                                                  isLandscape: true, scale: nil),
                            content: .plan(PlanDrawingBuilder.build(floor: floor, property: property,
                                                                    options: planOptions(scale: 50, from: options)),
                                           message: emptyMessage))
        }
        return PagePlan(info: PlanPDFPageInfo(kind: .plan, title: floor.name, paper: options.paper,
                                              isLandscape: result.landscape, scale: result.scale),
                        content: .plan(result.drawing, message: result.drawing.primitives.isEmpty ? emptyMessage : nil))
    }

    // MARK: Sheet geometry (millimetres, origin bottom-left)

    struct Rect {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
        func inset(left: Double, bottom: Double, right: Double, top: Double) -> Rect {
            Rect(x: x + left, y: y + bottom, width: Swift.max(0, width - left - right),
                 height: Swift.max(0, height - bottom - top))
        }
    }

    struct Sheet {
        static let margin = 10.0
        static let titleBlockHeight = 34.0
        let paper: PDFPaper
        let isLandscape: Bool

        var width: Double { isLandscape ? paper.longSideMM : paper.shortSideMM }
        var height: Double { isLandscape ? paper.shortSideMM : paper.longSideMM }
        /// The ruled frame that holds the drawing area and the title block.
        var frame: Rect { Rect(x: Sheet.margin, y: Sheet.margin, width: width - 2 * Sheet.margin, height: height - 2 * Sheet.margin) }
        var titleBlock: Rect { Rect(x: frame.x, y: frame.y, width: frame.width, height: Sheet.titleBlockHeight) }
        var drawingArea: Rect {
            Rect(x: frame.x, y: frame.y + Sheet.titleBlockHeight, width: frame.width,
                 height: frame.height - Sheet.titleBlockHeight)
        }
        /// Where the plan itself must fit: the drawing area less a margin (more at the top for the caption).
        var fitArea: Rect { drawingArea.inset(left: 6, bottom: 6, right: 6, top: 11) }
    }

    // MARK: Colours

    private enum Ink {
        static let ink = PlanDrawingBuilder.Palette.ink
        static let bronze = PlanDrawingBuilder.Palette.bronze
        static let paper = PlanDrawingBuilder.Palette.paper
        static let hairline = PlanDrawingBuilder.Palette.hairline
        static let muted = PlanDrawingBuilder.Palette.muted
        static let verified = PlanDrawingBuilder.Palette.verified
        static let warning = PlanDrawingBuilder.Palette.warning
        static let tint = DrawColor(hex: 0xF3EEE6)
    }

    // MARK: Canvas (millimetre drawing on a PDFPage)

    struct Canvas {
        var page: PDFPage
        private var stroke: StrokeStyle?
        private var fillColor: DrawColor?
        private var dashOn = false

        static let k = PDFUnits.pointsPerMillimetre
        /// Dash pattern on paper for `StrokeStyle.dashed`, millimetres.
        static let dashPattern: [Double] = [2.2, 1.1]

        init(sheet: Sheet) {
            page = PDFPage(widthMM: sheet.width, heightMM: sheet.height)
        }

        mutating func setStroke(_ style: StrokeStyle) {
            if stroke != style {
                if stroke?.color != style.color { page.setStrokeColor(style.color) }
                if stroke?.weight != style.weight { page.setLineWidth(Swift.max(0.05, style.weight) * Canvas.k) }
                stroke = style
            }
            if style.dashed != dashOn {
                page.setDash(style.dashed ? Canvas.dashPattern.map { $0 * Canvas.k } : [])
                dashOn = style.dashed
            }
        }

        mutating func setFill(_ color: DrawColor) {
            if fillColor != color { page.setFillColor(color); fillColor = color }
        }

        mutating func fill(_ r: Rect, _ color: DrawColor) {
            setFill(color)
            page.fillRect(x: r.x * Canvas.k, y: r.y * Canvas.k, width: r.width * Canvas.k, height: r.height * Canvas.k)
        }

        mutating func stroke(_ r: Rect, color: DrawColor, weight: Double) {
            setStroke(StrokeStyle(weight: weight, color: color))
            page.strokeRect(x: r.x * Canvas.k, y: r.y * Canvas.k, width: r.width * Canvas.k, height: r.height * Canvas.k)
        }

        mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, color: DrawColor,
                           weight: Double, dashed: Bool = false) {
            setStroke(StrokeStyle(weight: weight, color: color, dashed: dashed))
            page.strokeLine(fromX: x0 * Canvas.k, y0 * Canvas.k, toX: x1 * Canvas.k, y1 * Canvas.k)
        }

        mutating func arc(cx: Double, cy: Double, radius: Double, from: Double, to: Double, color: DrawColor,
                          weight: Double) {
            setStroke(StrokeStyle(weight: weight, color: color))
            page.arc(centerX: cx * Canvas.k, centerY: cy * Canvas.k, radius: radius * Canvas.k,
                     startDegrees: from, endDegrees: to)
            page.stroke()
        }

        /// Text at (x, y) millimetres on the baseline. `size` is the font size in points.
        mutating func text(_ string: String, x: Double, y: Double, size: Double, bold: Bool = false,
                           color: DrawColor = Ink.ink, anchor: TextAnchor = .left, tracking: Double = 0,
                           rotation: Double = 0) {
            guard !string.isEmpty else { return }
            let width = HelveticaMetrics.width(of: string, bold: bold, fontSize: size, characterSpacing: tracking) - tracking
            let shift: Double
            switch anchor {
            case .left: shift = 0
            case .center: shift = -width / 2
            case .right: shift = -width
            }
            let radians = rotation * Double.pi / 180
            setFill(color)
            page.text(string, x: x * Canvas.k + cos(radians) * shift, y: y * Canvas.k + sin(radians) * shift,
                      font: bold ? .helveticaBold : .helvetica, size: size, rotationDegrees: rotation,
                      characterSpacing: tracking)
        }

        /// Width in millimetres.
        static func textWidthMM(_ string: String, size: Double, bold: Bool = false, tracking: Double = 0) -> Double {
            HelveticaMetrics.width(of: string, bold: bold, fontSize: size, characterSpacing: tracking) / k
        }

        /// `string` truncated with "..." to fit `widthMM`.
        static func fitted(_ string: String, widthMM: Double, size: Double, bold: Bool = false) -> String {
            HelveticaMetrics.truncated(string, toWidth: widthMM * k, bold: bold, fontSize: size)
        }

        mutating func save() { page.save(); stroke = nil; fillColor = nil; dashOn = false }
        mutating func restore() { page.restore(); stroke = nil; fillColor = nil; dashOn = false }

        mutating func clip(_ r: Rect) {
            page.clipRect(x: r.x * Canvas.k, y: r.y * Canvas.k, width: r.width * Canvas.k, height: r.height * Canvas.k)
        }
    }

    // MARK: Drawing one page

    static func drawPage(_ plan: PagePlan, index: Int, count: Int, property: Property,
                         options: PlanPDFOptions, now: Date) -> PDFPage {
        let sheet = Sheet(paper: plan.info.paper, isLandscape: plan.info.isLandscape)
        var canvas = Canvas(sheet: sheet)
        canvas.fill(Rect(x: 0, y: 0, width: sheet.width, height: sheet.height), Ink.paper)

        let sheetLabel: String
        switch plan.content {
        case .plan(let drawing, let message):
            sheetLabel = plan.info.title
            drawPlan(drawing, message: message, caption: plan.info.title, sheet: sheet, canvas: &canvas)
        case .schedule(let rows, let continued, let isLast):
            // The heading says "(continued)"; the title block cell is narrow, so it keeps the plain name.
            sheetLabel = "Room schedule"
            drawSchedule(rows: rows, continued: continued, isLast: isLast, sheet: sheet,
                         units: options.units, canvas: &canvas)
        }

        // Frame and title block.
        canvas.stroke(sheet.frame, color: Ink.hairline, weight: 0.35)
        drawTitleBlock(sheet: sheet, info: plan.info, label: sheetLabel, kind: plan.info.kind, property: property,
                       options: options, now: now, index: index, count: count, canvas: &canvas)
        return canvas.page
    }

    // MARK: Plan

    private static func drawPlan(_ drawing: PlanDrawing, message: String?, caption: String, sheet: Sheet,
                                 canvas: inout Canvas) {
        let area = sheet.drawingArea
        canvas.text(caption.uppercased() + "  -  FLOOR PLAN", x: area.x + 5, y: area.maxY - 6.5, size: 7, bold: true,
                    color: Ink.muted, tracking: 0.8)
        if let message {
            canvas.text(message, x: area.x + area.width / 2, y: area.y + area.height / 2, size: 11,
                        color: Ink.muted, anchor: .center)
            return
        }
        let scale = drawing.options.scale
        let centre = drawing.bounds.center
        let fit = sheet.fitArea
        let painter = PlanPainter(scale: scale, modelCentre: centre,
                                  sheetCentre: Point2(fit.x + fit.width / 2, fit.y + fit.height / 2))
        canvas.save()
        canvas.clip(area)
        painter.draw(drawing, on: &canvas)
        canvas.restore()
    }

    /// Maps plan space (metres) to sheet millimetres and paints primitives.
    struct PlanPainter {
        let scale: Double
        let modelCentre: Point2
        let sheetCentre: Point2

        /// Metres on the plan to millimetres on the sheet.
        func mm(_ metres: Double) -> Double { metres * 1000 / scale }

        func point(_ p: Point2) -> Point2 {
            Point2(sheetCentre.x + mm(p.x - modelCentre.x), sheetCentre.y + mm(p.y - modelCentre.y))
        }

        func draw(_ drawing: PlanDrawing, on canvas: inout Canvas) {
            let k = Canvas.k
            for item in drawing.primitives {
                switch item.primitive {
                case let .line(a, b, style):
                    let pa = point(a), pb = point(b)
                    canvas.setStroke(style)
                    canvas.page.strokeLine(fromX: pa.x * k, pa.y * k, toX: pb.x * k, pb.y * k)

                case let .polyline(points, closed, stroke, fill):
                    guard points.count >= 2, stroke != nil || fill != nil else { continue }
                    if let fill { canvas.setFill(fill) }
                    if let stroke { canvas.setStroke(stroke) }
                    let first = point(points[0])
                    canvas.page.move(to: first.x * k, first.y * k)
                    for p in points.dropFirst() {
                        let q = point(p)
                        canvas.page.line(to: q.x * k, q.y * k)
                    }
                    switch (closed, stroke != nil, fill != nil) {
                    case (true, true, true): canvas.page.closeFillAndStroke()
                    case (true, true, false): canvas.page.closeAndStroke()
                    case (true, false, _): canvas.page.closePath(); canvas.page.fill()
                    case (false, true, true): canvas.page.fillAndStroke()
                    case (false, true, false): canvas.page.stroke()
                    case (false, false, _): canvas.page.fill()
                    }

                case let .arc(center, radius, start, end, style):
                    let c = point(center)
                    canvas.setStroke(style)
                    canvas.page.arc(centerX: c.x * k, centerY: c.y * k, radius: mm(radius) * k,
                                    startDegrees: start, endDegrees: end)
                    canvas.page.stroke()

                case let .circle(center, radius, style):
                    let c = point(center)
                    canvas.setStroke(style)
                    canvas.page.circle(centerX: c.x * k, centerY: c.y * k, radius: mm(radius) * k)
                    canvas.page.stroke()

                case let .text(string, at, height, rotation, anchor, color, bold):
                    let p = point(at)
                    // `height` is the cap height; a font's size is cap height / 0.718 for Helvetica.
                    let size = mm(height) * k / HelveticaMetrics.capHeight
                    canvas.text(string, x: p.x, y: p.y, size: size, bold: bold, color: color, anchor: anchor,
                                rotation: rotation)
                }
            }
        }
    }

    // MARK: Title block

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func dateText(_ date: Date, offsetMinutes: Int) -> String {
        let c = PDFCivilDate(unixSeconds: date.timeIntervalSince1970, offsetSeconds: offsetMinutes * 60)
        return "\(c.day) \(monthNames[Swift.max(0, Swift.min(11, c.month - 1))]) \(c.year)"
    }

    private static func drawTitleBlock(sheet: Sheet, info: PlanPDFPageInfo, label: String, kind: PlanPDFPageInfo.Kind,
                                       property: Property, options: PlanPDFOptions, now: Date, index: Int,
                                       count: Int, canvas: inout Canvas) {
        let tb = sheet.titleBlock
        let top = tb.maxY
        canvas.line(tb.x, top, tb.maxX, top, color: Ink.bronze, weight: 0.5)

        // Rows, bottom to top: disclaimer (8 mm), scale bar and legend (9 mm), details (17 mm).
        let ruleDisclaimer = tb.y + 8
        let ruleLegend = tb.y + 17
        canvas.line(tb.x, ruleDisclaimer, tb.maxX, ruleDisclaimer, color: Ink.hairline, weight: 0.25)
        canvas.line(tb.x, ruleLegend, tb.maxX, ruleLegend, color: Ink.hairline, weight: 0.25)

        // Details row: five cells.
        let fractions = [0.19, 0.31, 0.21, 0.15, 0.14]
        var cellX: [Double] = [tb.x]
        for f in fractions { cellX.append(cellX.last! + f * tb.width) }
        cellX[cellX.count - 1] = tb.maxX
        for x in cellX.dropFirst().dropLast() { canvas.line(x, ruleLegend, x, top, color: Ink.hairline, weight: 0.25) }
        let pad = 3.0
        func cellWidth(_ i: Int) -> Double { cellX[i + 1] - cellX[i] - 2 * pad }
        func labelText(_ s: String, _ i: Int, _ dy: Double) {
            canvas.text(s, x: cellX[i] + pad, y: top - dy, size: 5, color: Ink.muted, tracking: 0.5)
        }
        func valueText(_ s: String, _ i: Int, _ dy: Double, size: Double, bold: Bool = false,
                       color: DrawColor = Ink.ink) {
            let fitted = Canvas.fitted(s.isEmpty ? "-" : s, widthMM: cellWidth(i), size: size, bold: bold)
            canvas.text(fitted, x: cellX[i] + pad, y: top - dy, size: size, bold: bold, color: color)
        }

        // 0: wordmark.
        canvas.text("NEXAFIX", x: cellX[0] + pad, y: top - 8.5, size: 13, bold: true, color: Ink.bronze, tracking: 3)
        canvas.text("SITE SURVEY", x: cellX[0] + pad, y: top - 13.2, size: 5, color: Ink.muted, tracking: 1.6)

        // 1: property.
        labelText("PROPERTY", 1, 3.8)
        valueText(property.name, 1, 8.6, size: 9.5, bold: true)
        valueText(property.address, 1, 13.4, size: 6.5, color: Ink.muted)

        // 2: client and reference.
        labelText("CLIENT", 2, 3.8)
        valueText(property.client, 2, 7.4, size: 8)
        labelText("REFERENCE", 2, 10.8)
        valueText(property.reference, 2, 14.2, size: 8)

        // 3: floor (or sheet) and date.
        labelText(kind == .plan ? "FLOOR" : "SHEET", 3, 3.8)
        valueText(label, 3, 7.4, size: 8, bold: true)
        labelText("DATE", 3, 10.8)
        valueText(dateText(now, offsetMinutes: options.utcOffsetMinutes), 3, 14.2, size: 8)

        // 4: scale and paper.
        labelText("SCALE", 4, 3.8)
        canvas.text(info.scaleLabel, x: cellX[4] + pad, y: top - 10.6, size: 15, bold: true, color: Ink.ink)
        valueText("\(info.paper.displayName) \(info.isLandscape ? "landscape" : "portrait")", 4, 14.4,
                  size: 6.5, color: Ink.muted)

        // Scale bar.
        let legendTop = ruleLegend
        if let scale = info.scale {
            drawScaleBar(scale: scale, units: options.units, originX: tb.x + 5, baselineY: tb.y + 8 + 2.2,
                         maxLength: 42, canvas: &canvas)
        } else {
            canvas.text("NOT TO SCALE", x: tb.x + 5, y: tb.y + 8 + 3.2, size: 5.5, color: Ink.muted, tracking: 0.8)
        }

        // Legend and sheet number.
        let sheetText = "Sheet \(index + 1) of \(count)"
        let legendSize = 6.0
        let sheetWidth = Canvas.textWidthMM(sheetText, size: legendSize)
        canvas.text(sheetText, x: tb.maxX - 4, y: tb.y + 8 + 2.7, size: legendSize, color: Ink.muted, anchor: .right)
        drawLegend(left: tb.x + Swift.max(58, 0.34 * tb.width), right: tb.maxX - 6 - sheetWidth,
                   topY: legendTop, size: legendSize, canvas: &canvas)

        // Disclaimer, always, in one line where it fits.
        let disclaimer = ScanAccuracy.joineryDisclaimer
        let available = tb.width - 8
        var size = 7.0
        while size > 5, Canvas.textWidthMM(disclaimer, size: size) > available { size -= 0.25 }
        if Canvas.textWidthMM(disclaimer, size: size) <= available {
            canvas.text(disclaimer, x: tb.x + 4, y: tb.y + 3.1, size: size, color: Ink.ink)
        } else {
            let lines = HelveticaMetrics.wrapped(disclaimer, maxWidth: available * Canvas.k, fontSize: 5.5)
            for (i, line) in lines.prefix(2).enumerated() {
                canvas.text(line, x: tb.x + 4, y: tb.y + 4.9 - Double(i) * 2.6, size: 5.5, color: Ink.ink)
            }
        }
    }

    /// Nice numbers a scale bar can span, in the bar's unit.
    private static let scaleBarLengths: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500]

    /// A two-segment bar of a round real-world length, as close to `maxLength` mm on paper as possible.
    private static func drawScaleBar(scale: Double, units: DisplayUnits, originX: Double, baselineY: Double,
                                     maxLength: Double, canvas: inout Canvas) {
        let imperial = units.length == .inches || units.length == .feetAndInches
        let metresPerUnit = imperial ? UnitFormatter.metresPerFoot : 1.0
        let symbol = imperial ? "ft" : "m"
        var chosen: Double?
        for n in scaleBarLengths {
            let paperMM = n * metresPerUnit * 1000 / scale
            if paperMM <= maxLength, paperMM >= 6 { chosen = n }
        }
        guard let n = chosen else { return }
        let length = n * metresPerUnit * 1000 / scale
        let barHeight = 1.5
        func number(_ v: Double) -> String {
            var s = String(format: "%.2f", v)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        }
        let half = length / 2
        canvas.fill(Rect(x: originX, y: baselineY, width: half, height: barHeight), Ink.ink)
        canvas.fill(Rect(x: originX + half, y: baselineY, width: half, height: barHeight), Ink.paper)
        canvas.stroke(Rect(x: originX, y: baselineY, width: length, height: barHeight), color: Ink.ink, weight: 0.25)
        let labelY = baselineY + barHeight + 1.2
        canvas.text("0", x: originX, y: labelY, size: 5.5, color: Ink.ink, anchor: .center)
        canvas.text(number(n / 2), x: originX + half, y: labelY, size: 5.5, color: Ink.ink, anchor: .center)
        canvas.text("\(number(n)) \(symbol)", x: originX + length, y: labelY, size: 5.5, color: Ink.ink, anchor: .center)
    }

    /// The legend: "v = verified on site", a red arc and "red angle = out of square", a dashed line
    /// and "dashed = open boundary". Flows onto a second line when the row is too narrow.
    private static func drawLegend(left: Double, right: Double, topY: Double, size: Double, canvas: inout Canvas) {
        enum Swatch { case none, redArc, dashed }
        let items: [(Swatch, String, DrawColor)] = [
            (.none, "v = verified on site", Ink.verified),
            (.redArc, "red angle = out of square", Ink.muted),
            (.dashed, "dashed = open boundary", Ink.muted),
        ]
        let swatchWidth = 6.5
        let gap = 4.0
        var x = left
        var line = 0
        for (swatch, text, color) in items {
            let width = (swatch == .none ? 0 : swatchWidth) + Canvas.textWidthMM(text, size: size)
            if x + width > right, x > left { x = left; line += 1 }
            let baseline = topY - (line == 0 ? 3.9 : 7.6)
            var textX = x
            switch swatch {
            case .none:
                break
            case .redArc:
                // A 90-degree corner arc in the warning colour.
                canvas.arc(cx: x, cy: baseline - 0.4, radius: 2.4, from: 0, to: 90, color: Ink.warning, weight: 0.3)
                textX = x + swatchWidth
            case .dashed:
                canvas.line(x, baseline + 0.7, x + swatchWidth - 1.5, baseline + 0.7, color: Ink.ink, weight: 0.35, dashed: true)
                textX = x + swatchWidth
            }
            canvas.text(text, x: textX, y: baseline, size: size, bold: swatch == .none, color: color)
            x += width + gap
        }
    }

    // MARK: Schedule

    enum ScheduleRow: Hashable, Sendable {
        case floorHeader(String)
        case room(RoomLine)
        case total(RoomLine)
        case empty(String)

        var height: Double {
            switch self {
            case .floorHeader: return 6.5
            case .room, .empty: return 7.2
            case .total: return 8.2
            }
        }
    }

    /// The strings of one schedule row.
    struct RoomLine: Hashable, Sendable {
        var name: String
        var area: String
        var lengthByWidth: String
        var ceiling: String
        var perimeter: String
        var verified: String
        /// Verified over total: drives the colour of the count.
        var verifiedCount: Int
        var totalCount: Int
    }

    private static let tableHeaderHeight = 8.0
    private static let headingHeight = 15.0
    private static let continuedHeadingHeight = 10.0
    private static let footnoteHeight = 11.0
    private static let tablePadding = 6.0

    static func schedulePages(property: Property, options: PlanPDFOptions) -> [PagePlan] {
        let landscape = options.orientation == .landscape
        let sheet = Sheet(paper: options.paper, isLandscape: landscape)
        let rows = scheduleRows(property: property, options: options)

        // Greedy pagination. A floor header never ends a page; the totals row never stands alone.
        var chunks: [[ScheduleRow]] = [[]]
        var used = 0.0
        func capacity(page: Int) -> Double {
            let heading = page == 0 ? headingHeight : continuedHeadingHeight
            return sheet.drawingArea.height - 2 * tablePadding - heading - tableHeaderHeight - footnoteHeight
        }
        for row in rows {
            if used + row.height > capacity(page: chunks.count - 1), !chunks[chunks.count - 1].isEmpty {
                var carried: [ScheduleRow] = []
                if case .floorHeader? = chunks[chunks.count - 1].last { carried.append(chunks[chunks.count - 1].removeLast()) }
                if case .total = row, let last = chunks[chunks.count - 1].last, case .room = last {
                    carried.insert(chunks[chunks.count - 1].removeLast(), at: 0)
                }
                chunks.append(carried)
                used = carried.reduce(0) { $0 + $1.height }
            }
            chunks[chunks.count - 1].append(row)
            used += row.height
        }

        return chunks.enumerated().map { index, chunk in
            PagePlan(info: PlanPDFPageInfo(kind: .schedule, title: "Room schedule", paper: options.paper,
                                           isLandscape: landscape, scale: nil),
                     content: .schedule(rows: chunk, continued: index > 0, isLast: index == chunks.count - 1))
        }
    }

    static func scheduleRows(property: Property, options: PlanPDFOptions) -> [ScheduleRow] {
        let unit = options.units.length
        var rows: [ScheduleRow] = []
        var totalArea = 0.0
        var totalPerimeter = 0.0
        var verified = 0
        var total = 0

        let floors = property.floors.filter { !$0.rooms.isEmpty }
        for floor in floors {
            if floors.count > 1 { rows.append(.floorHeader(floor.name)) }
            for room in floor.rooms {
                let metrics = room.metrics
                let counts = verificationCounts(of: room)
                let area = metrics.effectiveFloorArea
                // A room with an unusable outline still gets a row, with dashes, and adds nothing to the totals.
                if area.isFinite { totalArea += area }
                if metrics.perimeter.isFinite { totalPerimeter += metrics.perimeter }
                verified += counts.verified
                total += counts.total
                rows.append(.room(RoomLine(
                    name: room.name.isEmpty ? room.kind.displayName : room.name,
                    area: area.isFinite ? UnitFormatter.area(area, unit: options.units.area) : "-",
                    lengthByWidth: lengthByWidthText(room: room, metrics: metrics, unit: unit),
                    ceiling: metrics.ceilingHeight.isFinite
                        ? marked(UnitFormatter.length(metrics.ceilingHeight, unit: unit), verified: room.ceilingHeight.isVerified)
                        : "-",
                    perimeter: metrics.perimeter.isFinite ? UnitFormatter.length(metrics.perimeter, unit: unit) : "-",
                    verified: "\(counts.verified)/\(counts.total)",
                    verifiedCount: counts.verified, totalCount: counts.total)))
            }
        }
        if rows.isEmpty {
            rows.append(.empty("No rooms have been scanned yet."))
        } else {
            rows.append(.total(RoomLine(
                name: "Total (\(floors.reduce(0) { $0 + $1.rooms.count }) rooms)",
                area: UnitFormatter.area(totalArea, unit: options.units.area),
                lengthByWidth: "", ceiling: "",
                perimeter: UnitFormatter.length(totalPerimeter, unit: unit),
                verified: "\(verified)/\(total)", verifiedCount: verified, totalCount: total)))
        }
        return rows
    }

    /// "6200 x 4500 mm" for a rectangular room, "-" for any other shape. A " v" follows a side that
    /// every wall of it has been laser-checked on, or the whole text when both sides are.
    static func lengthByWidthText(room: Room, metrics: RoomMetrics, unit: LengthUnit) -> String {
        guard metrics.isRectangular, let length = metrics.length, let width = metrics.width,
              length.isFinite, width.isFinite, metrics.sides.count == 4 else { return "-" }
        // `length` and `width` average opposite sides: sides 0 and 2, sides 1 and 3.
        let sideA = metrics.sides[0].isVerified && metrics.sides[2].isVerified
        let sideB = metrics.sides[1].isVerified && metrics.sides[3].isVerified
        let aLength = (metrics.sides[0].length + metrics.sides[2].length) / 2
        let bLength = (metrics.sides[1].length + metrics.sides[3].length) / 2
        let lengthVerified = aLength >= bLength ? sideA : sideB
        let widthVerified = aLength >= bLength ? sideB : sideA

        let first = UnitFormatter.length(length, unit: unit, includeUnit: false)
        let second = UnitFormatter.length(width, unit: unit, includeUnit: true)
        switch (lengthVerified, widthVerified) {
        case (true, true): return "\(first) x \(second) v"
        case (false, false): return "\(first) x \(second)"
        case (true, false): return "\(first) v x \(second)"
        case (false, true): return "\(first) x \(second) v"
        }
    }

    private static func marked(_ text: String, verified: Bool) -> String { verified ? text + " v" : text }

    /// Verified and total checks for a room, counted the way the on-site checklist counts them:
    /// every wall length, the height of every solid wall, the ceiling, each opening's width and
    /// height, its sill unless it sits on the floor unverified, and each custom measurement.
    static func verificationCounts(of room: Room) -> (verified: Int, total: Int) {
        var verified = 0
        var total = 0
        func count(_ m: Measured) { total += 1; if m.isVerified { verified += 1 } }
        for wall in room.walls {
            count(wall.length)
            if wall.kind == .solid { count(wall.height) }
        }
        count(room.ceilingHeight)
        for opening in room.openings {
            count(opening.width)
            count(opening.height)
            if opening.sillHeight.scanned >= 0.005 || opening.sillHeight.isVerified { count(opening.sillHeight) }
        }
        for custom in room.customMeasurements { count(custom.length) }
        return (verified, total)
    }

    private static func drawSchedule(rows: [ScheduleRow], continued: Bool, isLast: Bool, sheet: Sheet,
                                     units: DisplayUnits, canvas: inout Canvas) {
        let area = sheet.drawingArea
        let left = area.x + tablePadding
        let right = area.maxX - tablePadding
        let tableWidth = right - left
        var y = area.maxY - tablePadding

        // Heading.
        if continued {
            canvas.text("Room schedule (continued)", x: left, y: y - 5, size: 11, bold: true)
            y -= continuedHeadingHeight
        } else {
            canvas.text("Room schedule", x: left, y: y - 5.5, size: 15, bold: true)
            canvas.text("Effective dimensions: laser-verified where checked on site, LiDAR-scanned otherwise. v marks a verified value.",
                        x: left, y: y - 10.5, size: 6.5, color: Ink.muted)
            y -= headingHeight
        }

        // Columns.
        let fractions = [0.27, 0.12, 0.23, 0.14, 0.13, 0.11]
        var columnX: [Double] = [left]
        for f in fractions { columnX.append(columnX.last! + f * tableWidth) }
        let columnPad = 2.0
        enum Align { case leading, trailing }
        let aligns: [Align] = [.leading, .trailing, .trailing, .trailing, .trailing, .trailing]
        func draw(_ cells: [String], at baseline: Double, size: Double, bold: Bool = false,
                  colors: [DrawColor]? = nil, tracking: Double = 0) {
            for (i, cell) in cells.enumerated() {
                let width = columnX[i + 1] - columnX[i] - 2 * columnPad
                let text = Canvas.fitted(cell, widthMM: width, size: size, bold: bold)
                let color = colors?[i] ?? Ink.ink
                switch aligns[i] {
                case .leading:
                    canvas.text(text, x: columnX[i] + columnPad, y: baseline, size: size, bold: bold, color: color,
                                tracking: tracking)
                case .trailing:
                    canvas.text(text, x: columnX[i + 1] - columnPad, y: baseline, size: size, bold: bold,
                                color: color, anchor: .right, tracking: tracking)
                }
            }
        }

        // Header row.
        draw(["ROOM", "AREA", "LENGTH X WIDTH", "CEILING", "PERIMETER", "VERIFIED"], at: y - 5.2, size: 6,
             bold: true, colors: Array(repeating: Ink.muted, count: 6), tracking: 0.4)
        y -= tableHeaderHeight
        canvas.line(left, y, right, y, color: Ink.bronze, weight: 0.5)

        // Body.
        for row in rows {
            let h = row.height
            switch row {
            case .floorHeader(let name):
                canvas.fill(Rect(x: left, y: y - h, width: tableWidth, height: h), Ink.tint)
                canvas.text(Canvas.fitted(name.uppercased(), widthMM: tableWidth - 4, size: 6.5, bold: true),
                            x: left + columnPad, y: y - 4.5, size: 6.5, bold: true, color: Ink.bronze, tracking: 0.6)
            case .empty(let message):
                canvas.text(message, x: left + columnPad, y: y - 5, size: 8, color: Ink.muted)
            case .room(let line):
                let verifiedColor: DrawColor = line.totalCount > 0 && line.verifiedCount == line.totalCount
                    ? Ink.verified : (line.verifiedCount == 0 ? Ink.muted : Ink.ink)
                draw([line.name, line.area, line.lengthByWidth, line.ceiling, line.perimeter, line.verified],
                     at: y - 4.9, size: 8,
                     colors: [Ink.ink, Ink.ink, Ink.ink, Ink.ink, Ink.ink, verifiedColor])
                canvas.line(left, y - h, right, y - h, color: Ink.hairline, weight: 0.25)
            case .total(let line):
                canvas.fill(Rect(x: left, y: y - h, width: tableWidth, height: h), Ink.tint)
                canvas.line(left, y, right, y, color: Ink.ink, weight: 0.5)
                draw([line.name, line.area, line.lengthByWidth, line.ceiling, line.perimeter, line.verified],
                     at: y - 5.4, size: 8.5, bold: true)
                canvas.line(left, y - h, right, y - h, color: Ink.ink, weight: 0.5)
            }
            y -= h
        }

        // Footnote on the last page.
        if isLast {
            let note = "Verified counts every wall length, wall height, ceiling height, opening width and height, sill and custom measurement checked on site. "
                + "Area uses length x width for rectangular rooms, so verified wall lengths flow into it."
            let lines = HelveticaMetrics.wrapped(note, maxWidth: tableWidth * Canvas.k, fontSize: 6)
            for (i, line) in lines.prefix(3).enumerated() {
                canvas.text(line, x: left, y: area.y + tablePadding + 5 - Double(i) * 2.8, size: 6, color: Ink.muted)
            }
        }
    }
}
