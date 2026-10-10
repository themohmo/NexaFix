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
    /// Wall dimensions left out of this plan page because the rooms are too small at this scale to
    /// hold them without printing over other text. Not zero is the cue to use a larger sheet.
    public let omittedDimensionCount: Int
    /// Opening tags, furniture names and corner numbers left out for the same reason.
    public let omittedLabelCount: Int
    /// Names of the rooms of this floor that could not be drawn (fewer than three walls, or a corner
    /// that is not a number). They are missing from the plan and from the schedule totals.
    public let undrawableRoomNames: [String]

    init(kind: Kind, title: String, paper: PDFPaper, isLandscape: Bool, scale: Double?,
         omittedDimensionCount: Int = 0, omittedLabelCount: Int = 0, undrawableRoomNames: [String] = []) {
        self.kind = kind
        self.title = title
        self.paper = paper
        self.isLandscape = isLandscape
        self.scale = scale
        self.omittedDimensionCount = omittedDimensionCount
        self.omittedLabelCount = omittedLabelCount
        self.undrawableRoomNames = undrawableRoomNames
    }

    public var widthMM: Double { isLandscape ? paper.longSideMM : paper.shortSideMM }
    public var heightMM: Double { isLandscape ? paper.shortSideMM : paper.longSideMM }
    /// "1:50" for a plan, "NTS" (not to scale) for the schedule.
    public var scaleLabel: String { scale.map(PlanPDFRenderer.scaleLabel) ?? "NTS" }
    /// Every wall dimension of this page is printed.
    public var isLegible: Bool { omittedDimensionCount == 0 }
}

/// A rendered document and everything the person exporting it should be told about.
public struct PlanPDFResult: Sendable {
    public let data: Data
    /// Plain sentences, in reading order: text the PDF cannot print, rooms it could not draw,
    /// dimensions it had to leave out. Empty when the document is exactly what was asked for.
    public let warnings: [String]
}

// MARK: - Renderer

public enum PlanPDFRenderer {

    /// Standard scale denominators, largest drawing first.
    public static let standardScales: [Double] = [20, 25, 50, 75, 100, 150, 200, 250, 500]
    /// Used only when a plan is too large even for 1:500 on the chosen sheet.
    static let fallbackScales: [Double] = [750, 1000, 1500, 2000, 5000, 10000]

    /// "1:50", "1:37.5" for a scale between the integers (the plan is drawn at exactly that scale, so
    /// it is labelled with exactly that scale), "1:?" when there is no usable scale.
    public static func scaleLabel(_ denominator: Double) -> String {
        guard denominator.isFinite, denominator > 0 else { return "1:?" }
        if abs(denominator - denominator.rounded()) < 0.005 {
            return "1:" + String(format: "%.0f", denominator.rounded())
        }
        var text = String(format: "%.2f", denominator)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "1:" + text
    }

    /// Render the property: a plan page per floor, then the room schedule if requested. A property
    /// with no floors still yields a one-page document. `now` is the creation date and the date in
    /// the title block; nothing here reads the clock.
    public static func render(property: Property, options: PlanPDFOptions, now: Date) -> Data {
        renderWithReport(property: property, options: options, now: now).data
    }

    /// `render`, plus the warnings the export should show: names with characters this PDF cannot
    /// print (Arabic, for example, prints as "?"), rooms that could not be drawn, and dimensions that
    /// had to be left out because the plan is too small for them.
    public static func renderWithReport(property: Property, options: PlanPDFOptions, now: Date) -> PlanPDFResult {
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
        return PlanPDFResult(data: writer.data(), warnings: warnings(property: property, pages: pages, options: options))
    }

    /// The sentences behind `PlanPDFResult.warnings`.
    static func warnings(property: Property, pages: [PagePlan], options: PlanPDFOptions) -> [String] {
        var result: [String] = []

        // Text the standard fonts cannot print.
        var labels: [(String, String)] = [("property name", property.name), ("client", property.client),
                                          ("address", property.address), ("reference", property.reference)]
        for floor in property.floors {
            labels.append(("floor name", floor.name))
            for room in floor.rooms { labels.append(("room name", room.name)) }
        }
        let affected = labels.filter { !WinAnsiEncoding.unencodableCharacters(in: $0.1).isEmpty }
        if !affected.isEmpty {
            let examples = affected.prefix(3).map { "\($0.0) \"\(HelveticaMetrics.truncated($0.1, toWidth: 120, fontSize: 4))\"" }
            result.append("\(affected.count) text value\(affected.count == 1 ? " contains" : "s contain") characters this PDF cannot print "
                + "(for example Arabic or other non-Latin script) and show as '?': "
                + examples.joined(separator: ", ") + (affected.count > 3 ? ", ..." : "") + ".")
        }

        for page in pages where page.info.kind == .plan {
            let info = page.info
            if !info.undrawableRoomNames.isEmpty {
                let n = info.undrawableRoomNames.count
                result.append("\(info.title): \(n) room\(n == 1 ? "" : "s") could not be drawn and \(n == 1 ? "is" : "are") "
                    + "missing from the plan and the schedule totals: \(info.undrawableRoomNames.joined(separator: ", ")).")
            }
            if info.omittedDimensionCount > 0 {
                let n = info.omittedDimensionCount
                result.append("\(info.title): \(n) wall dimension\(n == 1 ? " was" : "s were") left out because the rooms are too small "
                    + "at \(info.scaleLabel) on \(info.paper.displayName) to print them without overlap. "
                    + "Use a larger sheet or a larger scale.")
            }
        }
        return result
    }

    /// The pages `render` produces, with the orientation and scale chosen for each.
    public static func pageInfos(property: Property, options: PlanPDFOptions) -> [PlanPDFPageInfo] {
        makePages(property: property, options: options).map(\.info)
    }

    // MARK: Page planning

    /// Which marks the legend of a page explains, beyond the always-present "v", "red angle" and "dashed".
    struct LegendFlags: Hashable, Sendable {
        /// Some number comes from a drawing and is marked "d".
        var drawing = false
        /// Some wall is curved and its straight length is flagged "chord".
        var chord = false
    }

    struct PagePlan {
        enum Content {
            case plan(PlanDrawing, message: String?, report: PlanLayoutReport)
            case schedule(rows: [ScheduleRow], continued: Bool, isLast: Bool, notes: [String])
        }
        var info: PlanPDFPageInfo
        var content: Content
        var legend = LegendFlags()
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

    private static func legend(for report: PlanLayoutReport) -> LegendFlags {
        LegendFlags(drawing: report.hasDrawingSourcedValues, chord: report.chordLabels > 0)
    }

    private static func info(for floor: Floor, options: PlanPDFOptions, landscape: Bool, scale: Double?,
                             report: PlanLayoutReport) -> PlanPDFPageInfo {
        PlanPDFPageInfo(kind: .plan, title: floor.name, paper: options.paper, isLandscape: landscape, scale: scale,
                        omittedDimensionCount: report.omittedDimensionTexts,
                        omittedLabelCount: report.omittedAngleTexts + report.omittedOpeningTags
                            + report.omittedFurnitureLabels,
                        undrawableRoomNames: report.undrawableRooms)
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
        let drawable = floor.rooms.filter(PlanDrawingBuilder.isDrawable)
        let outlineBounds = drawable.compactMap { Bounds2(points: $0.outline) }
            .reduce(nil) { (acc: Bounds2?, b: Bounds2) -> Bounds2? in acc.map { $0.union(b) } ?? b }
        guard let minimum = outlineBounds else {
            var scale = 50.0
            if case .fixed(let s) = options.scale, s.isFinite, s > 0 { scale = s }
            let result = PlanDrawingBuilder.buildDetailed(floor: floor, property: property,
                                                          options: planOptions(scale: scale, from: options))
            let message: String
            if floor.rooms.isEmpty {
                message = emptyMessage
            } else {
                let n = floor.rooms.count
                message = "None of the \(n) room\(n == 1 ? "" : "s") on this floor could be drawn: a room needs three or more walls "
                    + "with valid corners. Check the scan data of \(result.report.undrawableRooms.joined(separator: ", "))."
            }
            return PagePlan(info: info(for: floor, options: options, landscape: orientations[0], scale: scale,
                                       report: result.report),
                            content: .plan(result.drawing, message: message, report: result.report),
                            legend: legend(for: result.report))
        }

        // A plan depends on the scale only, not on the sheet, so each scale is built at most once.
        var built: [Double: PlanBuildResult] = [:]
        func plan(at scale: Double) -> PlanBuildResult {
            if let cached = built[scale] { return cached }
            let result = PlanDrawingBuilder.buildDetailed(floor: floor, property: property,
                                                          options: planOptions(scale: scale, from: options))
            built[scale] = result
            return result
        }

        typealias Candidate = (landscape: Bool, scale: Double, result: PlanBuildResult, fill: Double, fits: Bool)
        var best: Candidate?
        for landscape in orientations {
            let sheet = Sheet(paper: options.paper, isLandscape: landscape)
            let area = sheet.fitArea
            var chosen: (Double, PlanBuildResult, Double, Bool)?
            for scale in candidateScales(options.scale) {
                // The drawing always covers the room outlines, so a scale that cannot hold them is skipped unbuilt.
                if minimum.width * 1000 / scale > area.width + 1e-6 || minimum.height * 1000 / scale > area.height + 1e-6 {
                    continue
                }
                let result = plan(at: scale)
                let w = result.drawing.bounds.width * 1000 / scale
                let h = result.drawing.bounds.height * 1000 / scale
                if w <= area.width + 1e-6, h <= area.height + 1e-6 {
                    chosen = (scale, result, (w * h) / (area.width * area.height), true)
                    break
                }
            }
            if chosen == nil {
                // Does not fit anywhere: smallest scale, clipped to the sheet.
                let scale = candidateScales(options.scale).last ?? 10000
                chosen = (scale, plan(at: scale), 1, false)
            }
            guard let c = chosen else { continue }
            let candidate: Candidate = (landscape: landscape, scale: c.0, result: c.1, fill: c.2, fits: c.3)
            if let current = best {
                // Fits first, then the larger drawing, then the sheet that leaves out fewer labels, then the fuller one.
                let better: Bool
                if candidate.fits != current.fits {
                    better = candidate.fits
                } else if candidate.scale != current.scale {
                    better = candidate.scale < current.scale
                } else if candidate.result.report.omittedDimensionTexts != current.result.report.omittedDimensionTexts {
                    better = candidate.result.report.omittedDimensionTexts < current.result.report.omittedDimensionTexts
                } else {
                    better = candidate.fill > current.fill + 1e-9
                }
                if better { best = candidate }
            } else {
                best = candidate
            }
        }
        // `orientations` is never empty and `chosen` is always set, so `best` is non-nil; the guard is belt and braces.
        guard let result = best else {
            let fallback = plan(at: 50)
            return PagePlan(info: info(for: floor, options: options, landscape: true, scale: nil, report: fallback.report),
                            content: .plan(fallback.drawing, message: emptyMessage, report: fallback.report),
                            legend: legend(for: fallback.report))
        }
        let report = result.result.report
        return PagePlan(info: info(for: floor, options: options, landscape: result.landscape, scale: result.scale,
                                   report: report),
                        content: .plan(result.result.drawing,
                                       message: result.result.drawing.primitives.isEmpty ? emptyMessage : nil,
                                       report: report),
                        legend: legend(for: report))
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
        private var stroke: DrawStroke?
        private var fillColor: DrawColor?
        private var dashOn = false

        static let k = PDFUnits.pointsPerMillimetre
        /// Dash pattern on paper for `DrawStroke.dashed`, millimetres.
        static let dashPattern: [Double] = [2.2, 1.1]

        init(sheet: Sheet) {
            page = PDFPage(widthMM: sheet.width, heightMM: sheet.height)
        }

        mutating func setStroke(_ style: DrawStroke) {
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
            setStroke(DrawStroke(weight: weight, color: color))
            page.strokeRect(x: r.x * Canvas.k, y: r.y * Canvas.k, width: r.width * Canvas.k, height: r.height * Canvas.k)
        }

        mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, color: DrawColor,
                           weight: Double, dashed: Bool = false) {
            setStroke(DrawStroke(weight: weight, color: color, dashed: dashed))
            page.strokeLine(fromX: x0 * Canvas.k, y0 * Canvas.k, toX: x1 * Canvas.k, y1 * Canvas.k)
        }

        mutating func arc(cx: Double, cy: Double, radius: Double, from: Double, to: Double, color: DrawColor,
                          weight: Double) {
            setStroke(DrawStroke(weight: weight, color: color))
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
        case .plan(let drawing, let message, let report):
            sheetLabel = plan.info.title
            drawPlan(drawing, message: message, report: report, info: plan.info, sheet: sheet, canvas: &canvas)
        case .schedule(let rows, let continued, let isLast, let notes):
            // The heading says "(continued)"; the title block cell is narrow, so it keeps the plain name.
            sheetLabel = "Room schedule"
            drawSchedule(rows: rows, continued: continued, isLast: isLast, notes: notes, sheet: sheet,
                         units: options.units, canvas: &canvas)
        }

        // Frame and title block.
        canvas.stroke(sheet.frame, color: Ink.hairline, weight: 0.35)
        drawTitleBlock(sheet: sheet, info: plan.info, label: sheetLabel, kind: plan.info.kind, property: property,
                       options: options, now: now, index: index, count: count, legend: plan.legend, canvas: &canvas)
        return canvas.page
    }

    // MARK: Plan

    /// The one-line warnings under the caption of a plan page.
    static func planNotes(report: PlanLayoutReport, info: PlanPDFPageInfo) -> [String] {
        var notes: [String] = []
        if !report.undrawableRooms.isEmpty {
            let n = report.undrawableRooms.count
            notes.append("\(n) room\(n == 1 ? "" : "s") not drawn: " + report.undrawableRooms.joined(separator: ", "))
        }
        if report.omittedDimensionTexts > 0 {
            let n = report.omittedDimensionTexts
            notes.append("\(n) dimension\(n == 1 ? "" : "s") left out: too small for \(info.scaleLabel) on \(info.paper.displayName)")
        }
        return notes
    }

    private static func drawPlan(_ drawing: PlanDrawing, message: String?, report: PlanLayoutReport,
                                 info: PlanPDFPageInfo, sheet: Sheet, canvas: inout Canvas) {
        let area = sheet.drawingArea
        // A very long floor name is cut at 60 % of the width so the warnings beside it keep room.
        let suffix = "  -  FLOOR PLAN"
        let nameBudget = 0.6 * area.width - Canvas.textWidthMM(suffix, size: 7, bold: true, tracking: 0.8)
        let caption = Canvas.fitted(info.title.uppercased(), widthMM: Swift.max(10, nameBudget), size: 7, bold: true) + suffix
        canvas.text(caption, x: area.x + 5, y: area.maxY - 6.5, size: 7, bold: true, color: Ink.muted, tracking: 0.8)

        // What could not be drawn or printed, in the warning colour, on the caption line.
        let notes = planNotes(report: report, info: info)
        if !notes.isEmpty {
            let captionWidth = Canvas.textWidthMM(caption, size: 7, bold: true, tracking: 0.8)
            let available = area.width - 10 - captionWidth - 6
            if available > 20 {
                canvas.text(Canvas.fitted(notes.joined(separator: "   "), widthMM: available, size: 6.5),
                            x: area.maxX - 5, y: area.maxY - 6.5, size: 6.5, color: Ink.warning, anchor: .right)
            }
        }

        if let message {
            let lines = HelveticaMetrics.wrapped(message, maxWidth: (area.width - 24) * Canvas.k, fontSize: 11)
            let leading = 5.5
            var y = area.y + area.height / 2 + leading * Double(lines.count - 1) / 2
            for line in lines.prefix(4) {
                canvas.text(line, x: area.x + area.width / 2, y: y, size: 11, color: Ink.muted, anchor: .center)
                y -= leading
            }
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
                                       count: Int, legend: LegendFlags, canvas: inout Canvas) {
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
                   topY: legendTop, size: legendSize, flags: legend, canvas: &canvas)

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

    /// The legend: "v = verified on site" (and "d = from drawing" where the plan has such a value), a
    /// red arc and "red angle = out of square", a dashed line and "dashed = open boundary", and
    /// "chord = curved wall" where one is flagged. Flows onto a second line when the row is too
    /// narrow, and shrinks (never below 4.5 pt) before it would need a third.
    private static func drawLegend(left: Double, right: Double, topY: Double, size: Double, flags: LegendFlags,
                                   canvas: inout Canvas) {
        enum Swatch { case none, redArc, dashed }
        var items: [(Swatch, String, DrawColor, Bool)] = [(.none, "v = verified on site", Ink.verified, true)]
        if flags.drawing { items.append((.none, "d = from drawing", Ink.muted, true)) }
        items.append((.redArc, "red angle = out of square", Ink.muted, false))
        items.append((.dashed, "dashed = open boundary", Ink.muted, false))
        if flags.chord { items.append((.none, "chord = curved wall", Ink.bronze, true)) }

        let swatchWidth = 6.5
        let gap = 4.0
        func itemWidth(_ item: (Swatch, String, DrawColor, Bool), _ size: Double) -> Double {
            (item.0 == .none ? 0 : swatchWidth) + Canvas.textWidthMM(item.1, size: size, bold: item.3)
        }
        /// How many lines the items take at this size.
        func lineCount(_ size: Double) -> Int {
            var x = left
            var line = 0
            for item in items {
                let width = itemWidth(item, size)
                if x + width > right, x > left { x = left; line += 1 }
                x += width + gap
            }
            return line + 1
        }
        var fontSize = size
        while fontSize > 4.5, lineCount(fontSize) > 2 { fontSize -= 0.25 }

        var x = left
        var line = 0
        for item in items {
            let width = itemWidth(item, fontSize)
            if x + width > right, x > left { x = left; line += 1 }
            let baseline = topY - (line == 0 ? 3.9 : 7.6)
            var textX = x
            switch item.0 {
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
            canvas.text(item.1, x: textX, y: baseline, size: fontSize, bold: item.3, color: item.2)
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
        /// The longer pair of opposite walls, "6200 - 6210 v mm" (see `lengthAndWidthTexts`).
        var length: String
        /// The shorter pair of opposite walls.
        var width: String
        var ceiling: String
        var perimeter: String
        var verified: String
        /// Verified over total: drives the colour of the count.
        var verifiedCount: Int
        var totalCount: Int
        /// The room has a curved wall, measured as a straight chord (marked "*" after the name).
        var hasCurvedWall = false
        /// The room could not be drawn: no figures, and it is left out of the totals.
        var isNotDrawn = false
    }

    private static let tableHeaderHeight = 8.0
    private static let headingHeight = 19.0
    private static let continuedHeadingHeight = 10.0
    private static let footnoteHeight = 16.0
    private static let tablePadding = 6.0

    static func schedulePages(property: Property, options: PlanPDFOptions) -> [PagePlan] {
        let landscape = options.orientation == .landscape
        let sheet = Sheet(paper: options.paper, isLandscape: landscape)
        let rows = scheduleRows(property: property, options: options)

        // Greedy pagination. A floor header never ends a page; the totals row never stands alone; a
        // page that starts in the middle of a floor repeats that floor's header ("(cont.)").
        var chunks: [[ScheduleRow]] = [[]]
        var used = 0.0
        var currentFloor: String?
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
                var startsWithHeader = false
                if case .floorHeader? = carried.first { startsWithHeader = true }
                if case .floorHeader = row, carried.isEmpty { startsWithHeader = true }
                if !startsWithHeader, let floor = currentFloor {
                    carried.insert(.floorHeader(floor + " (cont.)"), at: 0)
                }
                chunks.append(carried)
                used = carried.reduce(0) { $0 + $1.height }
            }
            if case .floorHeader(let name) = row { currentFloor = name }
            chunks[chunks.count - 1].append(row)
            used += row.height
        }

        var notes: [String] = []
        let lines = rows.compactMap { row -> RoomLine? in if case .room(let line) = row { return line }; return nil }
        if lines.contains(where: \.hasCurvedWall) {
            notes.append("* Has a curved wall, measured as a straight chord: its area and perimeter are approximate.")
        }
        if lines.contains(where: \.isNotDrawn) {
            notes.append("Not drawn: the scan has fewer than three walls or a corner that is not a number. "
                + "Such a room is left out of the plan and of every total.")
        }

        return chunks.enumerated().map { index, chunk in
            PagePlan(info: PlanPDFPageInfo(kind: .schedule, title: "Room schedule", paper: options.paper,
                                           isLandscape: landscape, scale: nil),
                     content: .schedule(rows: chunk, continued: index > 0, isLast: index == chunks.count - 1,
                                        notes: notes),
                     legend: LegendFlags(drawing: property.allRooms.contains(where: PlanDrawingBuilder.hasDrawingSource),
                                         chord: false))
        }
    }

    static func scheduleRows(property: Property, options: PlanPDFOptions) -> [ScheduleRow] {
        let unit = options.units.length
        var rows: [ScheduleRow] = []
        var totalArea = 0.0
        var totalPerimeter = 0.0
        var verified = 0
        var total = 0
        var counted = 0

        let floors = property.floors.filter { !$0.rooms.isEmpty }
        for floor in floors {
            if floors.count > 1 { rows.append(.floorHeader(floor.name)) }
            for room in floor.rooms {
                let name = PlanDrawingBuilder.displayName(of: room)
                // A room the plan cannot draw gets a row that says so, and adds nothing to the totals.
                guard PlanDrawingBuilder.isDrawable(room) else {
                    rows.append(.room(RoomLine(name: name, area: "-", length: "-", width: "-", ceiling: "-",
                                               perimeter: "-", verified: "not drawn", verifiedCount: 0, totalCount: 0,
                                               isNotDrawn: true)))
                    continue
                }
                let metrics = room.metrics
                let counts = verificationCounts(of: room)
                let area = metrics.effectiveFloorArea
                // A room with an unusable outline still gets a row, with dashes, and adds nothing to the totals.
                if area.isFinite { totalArea += area }
                if metrics.perimeter.isFinite { totalPerimeter += metrics.perimeter }
                verified += counts.verified
                total += counts.total
                counted += 1
                let dimensions = lengthAndWidthTexts(room: room, metrics: metrics, unit: unit)
                rows.append(.room(RoomLine(
                    name: name,
                    area: area.isFinite ? UnitFormatter.area(area, unit: options.units.area) : "-",
                    length: dimensions?.length ?? "-",
                    width: dimensions?.width ?? "-",
                    ceiling: metrics.ceilingHeight.isFinite ? ceilingText(room.ceilingHeight, unit: unit) : "-",
                    perimeter: metrics.perimeter.isFinite ? UnitFormatter.length(metrics.perimeter, unit: unit) : "-",
                    verified: "\(counts.verified)/\(counts.total)",
                    verifiedCount: counts.verified, totalCount: counts.total,
                    hasCurvedWall: room.walls.contains { $0.isCurved })))
            }
        }
        if rows.isEmpty {
            rows.append(.empty("No rooms have been scanned yet."))
        } else {
            rows.append(.total(RoomLine(
                name: "Total (\(counted) rooms)",
                area: UnitFormatter.area(totalArea, unit: options.units.area),
                length: "", width: "", ceiling: "",
                perimeter: UnitFormatter.length(totalPerimeter, unit: unit),
                verified: "\(verified)/\(total)", verifiedCount: verified, totalCount: total)))
        }
        return rows
    }

    /// "2800 mm", with " v" when checked on site and " d" when taken from a drawing.
    private static func ceilingText(_ ceiling: Measured, unit: LengthUnit) -> String {
        var text = UnitFormatter.length(ceiling.value, unit: unit)
        if let mark = PlanDrawingBuilder.Provenance(ceiling).mark { text += " " + mark }
        return text
    }

    /// One side of a rectangular room: its effective length and where it comes from.
    struct SideValue: Equatable {
        var metres: Double
        var provenance: PlanDrawingBuilder.Provenance
    }

    /// The length and the width of a rectangular room as the walls measured them, "-" twice for any
    /// other shape. Each is a pair of opposite walls (the pair with the larger average is the length).
    ///
    /// - The two walls of a pair print as one number when they agree to the display resolution, and
    ///   as "smaller - larger" when they do not; a number nobody measured (an average) is never printed.
    /// - A number is followed by " v" when every wall behind it was checked on site, " d" when the
    ///   weakest check behind it is an approved drawing, and by nothing when any wall behind it is
    ///   LiDAR-scanned. The mark belongs to the number it follows: "6200 - 6210 v mm" has one scanned
    ///   and one verified wall.
    static func lengthAndWidthTexts(room: Room, metrics: RoomMetrics,
                                    unit: LengthUnit) -> (length: String, width: String)? {
        guard metrics.isRectangular, metrics.sides.count == 4,
              let length = metrics.length, let width = metrics.width, length.isFinite, width.isFinite else { return nil }
        let lengthsByID = Dictionary(room.walls.map { ($0.id, $0.length) }, uniquingKeysWith: { first, _ in first })
        func side(_ index: Int) -> SideValue {
            let s = metrics.sides[index]
            var weakest = PlanDrawingBuilder.Provenance.site
            for id in s.wallIDs {
                if let measured = lengthsByID[id] { weakest = Swift.min(weakest, PlanDrawingBuilder.Provenance(measured)) }
            }
            return SideValue(metres: s.length, provenance: weakest)
        }
        // Sides 0 and 2 are one pair of opposite walls, 1 and 3 the other.
        let pairA = (side(0), side(2)), pairB = (side(1), side(3))
        let meanA = (pairA.0.metres + pairA.1.metres) / 2, meanB = (pairB.0.metres + pairB.1.metres) / 2
        guard meanA.isFinite, meanB.isFinite else { return nil }
        let (long, short) = meanA >= meanB ? (pairA, pairB) : (pairB, pairA)
        return (pairText(long.0, long.1, unit: unit), pairText(short.0, short.1, unit: unit))
    }

    /// The text for two opposite walls (see `lengthAndWidthTexts`).
    static func pairText(_ a: SideValue, _ b: SideValue, unit: LengthUnit) -> String {
        func number(_ v: Double) -> String { UnitFormatter.length(v, unit: unit, precision: .precise, includeUnit: false) }
        func marked(_ text: String, _ provenance: PlanDrawingBuilder.Provenance) -> String {
            provenance.mark.map { text + " " + $0 } ?? text
        }
        let textA = number(a.metres), textB = number(b.metres)
        var text: String
        if textA == textB {
            text = marked(textA, Swift.min(a.provenance, b.provenance))
        } else {
            let (low, high) = a.metres <= b.metres ? (a, b) : (b, a)
            text = marked(number(low.metres), low.provenance) + " - " + marked(number(high.metres), high.provenance)
        }
        // Feet and inches carry their own marks; every other unit says what it is, once, at the end.
        if unit != .feetAndInches { text += " " + unit.symbol }
        return text
    }

    /// Verified and total check counts for a room, exactly as the on-site checklist counts them, so
    /// the schedule and the checklist screen can never disagree.
    static func verificationCounts(of room: Room) -> (verified: Int, total: Int) {
        let checklist = VerificationChecklist(room: room)
        return (checklist.verifiedCount, checklist.totalCount)
    }

    /// `text` at `size`, shrunk in quarter-point steps until it fits `widthMM`. Numbers are never cut
    /// short: only below `minimum` points does the last resort, an ellipsis, apply.
    static func fittedNumber(_ text: String, widthMM: Double, size: Double, bold: Bool,
                             minimum: Double = 4.0) -> (text: String, size: Double) {
        var fontSize = size
        while fontSize > minimum, Canvas.textWidthMM(text, size: fontSize, bold: bold) > widthMM { fontSize -= 0.25 }
        if Canvas.textWidthMM(text, size: fontSize, bold: bold) <= widthMM { return (text, fontSize) }
        return (Canvas.fitted(text, widthMM: widthMM, size: fontSize, bold: bold), fontSize)
    }

    private static func drawSchedule(rows: [ScheduleRow], continued: Bool, isLast: Bool, notes: [String],
                                     sheet: Sheet, units: DisplayUnits, canvas: inout Canvas) {
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
            canvas.text(Canvas.fitted("Effective dimensions: laser-verified where checked on site, LiDAR-scanned otherwise. "
                                      + "A number with no mark is LiDAR only.",
                                      widthMM: tableWidth, size: 6.5),
                        x: left, y: y - 10.5, size: 6.5, color: Ink.muted)
            canvas.text(Canvas.fitted("v = verified on site (laser or tape).  d = taken from an approved drawing, not measured on site.  "
                                      + "Two numbers = the two opposite walls differ.",
                                      widthMM: tableWidth, size: 6.5),
                        x: left, y: y - 13.8, size: 6.5, color: Ink.muted)
            y -= headingHeight
        }

        // Columns: room, area, length, width, ceiling, perimeter, verified.
        let fractions = [0.21, 0.10, 0.185, 0.185, 0.09, 0.12, 0.11]
        var columnX: [Double] = [left]
        for f in fractions { columnX.append(columnX.last! + f * tableWidth) }
        let columnPad = 2.0
        enum Align { case leading, trailing }
        let aligns: [Align] = [.leading, .trailing, .trailing, .trailing, .trailing, .trailing, .trailing]
        func draw(_ cells: [String], at baseline: Double, size: Double, bold: Bool = false,
                  colors: [DrawColor]? = nil, tracking: Double = 0, nameSuffix: String = "") {
            for (i, cell) in cells.enumerated() {
                let width = columnX[i + 1] - columnX[i] - 2 * columnPad
                let color = colors?[i] ?? Ink.ink
                var text = cell
                var cellSize = size
                if i == 0 {
                    // Names may be cut short; the curved-wall star is not.
                    let starWidth = Canvas.textWidthMM(nameSuffix, size: size, bold: bold)
                    text = Canvas.fitted(cell, widthMM: width - starWidth, size: size, bold: bold) + nameSuffix
                } else if tracking == 0 {
                    // Numbers shrink to fit; they are never truncated.
                    (text, cellSize) = fittedNumber(cell, widthMM: width, size: size, bold: bold)
                } else {
                    text = Canvas.fitted(cell, widthMM: width, size: size, bold: bold)
                }
                switch aligns[i] {
                case .leading:
                    canvas.text(text, x: columnX[i] + columnPad, y: baseline, size: cellSize, bold: bold, color: color,
                                tracking: tracking)
                case .trailing:
                    canvas.text(text, x: columnX[i + 1] - columnPad, y: baseline, size: cellSize, bold: bold,
                                color: color, anchor: .right, tracking: tracking)
                }
            }
        }

        // Header row.
        draw(["ROOM", "AREA", "LENGTH", "WIDTH", "CEILING", "PERIMETER", "VERIFIED"], at: y - 5.2, size: 6,
             bold: true, colors: Array(repeating: Ink.muted, count: 7), tracking: 0.4)
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
                let verifiedColor: DrawColor = line.isNotDrawn ? Ink.warning
                    : (line.totalCount > 0 && line.verifiedCount == line.totalCount
                        ? Ink.verified : (line.verifiedCount == 0 ? Ink.muted : Ink.ink))
                draw([line.name, line.area, line.length, line.width, line.ceiling, line.perimeter, line.verified],
                     at: y - 4.9, size: 8,
                     colors: [Ink.ink, Ink.ink, Ink.ink, Ink.ink, Ink.ink, Ink.ink, verifiedColor],
                     nameSuffix: line.hasCurvedWall ? "*" : "")
                canvas.line(left, y - h, right, y - h, color: Ink.hairline, weight: 0.25)
            case .total(let line):
                canvas.fill(Rect(x: left, y: y - h, width: tableWidth, height: h), Ink.tint)
                canvas.line(left, y, right, y, color: Ink.ink, weight: 0.5)
                draw([line.name, line.area, line.length, line.width, line.ceiling, line.perimeter, line.verified],
                     at: y - 5.4, size: 8.5, bold: true)
                canvas.line(left, y - h, right, y - h, color: Ink.ink, weight: 0.5)
            }
            y -= h
        }

        // Footnotes on the last page.
        if isLast {
            let base = "Verified counts every wall length, wall height, ceiling height, opening size, sill and custom measurement "
                + "that has a checked value (laser or tape on site, or an approved drawing). Area is length x width of a "
                + "rectangular room (each the average of two opposite walls): derived, never marked. Perimeter is the sum of the wall lengths."
            var baseline = area.y + tablePadding + footnoteHeight - 4
            for paragraph in [base] + notes {
                let wrapped = HelveticaMetrics.wrapped(paragraph, maxWidth: tableWidth * Canvas.k, fontSize: 6)
                for line in wrapped {
                    guard baseline >= area.y + tablePadding + 0.5 else { break }
                    canvas.text(line, x: left, y: baseline, size: 6, color: Ink.muted)
                    baseline -= 2.8
                }
            }
        }
    }
}
