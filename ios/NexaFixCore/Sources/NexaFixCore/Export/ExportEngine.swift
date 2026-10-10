import Foundation

// One call that turns a property into every file the Export sheet can hand out: the floor-plan PDF,
// one DXF per floor, the USDZ models the scan saved, the scan JSON, the CSV tables and the costing
// spec. The exporters themselves live next to this file; this one chooses options, names the files
// and says how much of the data was checked on site (`ExportReadiness`).
//
// Nothing here reads the clock or touches the disk: `ExportRequest.now` is the date in every file name
// and title block, and USDZ models arrive as `Data` or a file URL the caller names. The same request
// always gives the same bytes.

// MARK: - Formats

/// What can be exported. The raw values are stable identifiers (they are stored in preferences).
public enum ExportFormat: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case planPDF, cadDXF, model3D, dataJSON, csv, costingSpec

    public var id: String { rawValue }

    /// The row title in the Export sheet.
    public var displayName: String {
        switch self {
        case .planPDF: return "Floor plan PDF"
        case .cadDXF: return "CAD drawing DXF"
        case .model3D: return "3D model USDZ"
        case .dataJSON: return "Data JSON"
        case .csv: return "Spreadsheets CSV"
        case .costingSpec: return "Costing spec"
        }
    }

    /// One plain sentence under the title.
    public var detail: String {
        switch self {
        case .planPDF:
            return "Scaled plans with dimensions, one page per level, then a room schedule."
        case .cadDXF:
            return "An editable drawing for AutoCAD and other CAD programs, one file per level, in millimetres."
        case .model3D:
            return "The scanned 3D model of each level. Opens in AR Quick Look and most 3D tools."
        case .dataJSON:
            return "Every room, wall, opening and check in one file, for other software."
        case .csv:
            return "Rooms, walls, openings and objects as tables that open in Excel or Numbers."
        case .costingSpec:
            return "Room sizes and openings in the form the NexaFix costing engine reads, with the unchecked dimensions listed."
        }
    }

    /// File name extension, lower case, no dot.
    public var fileExtension: String {
        switch self {
        case .planPDF: return "pdf"
        case .cadDXF: return "dxf"
        case .model3D: return "usdz"
        case .dataJSON, .costingSpec: return "json"
        case .csv: return "csv"
        }
    }

    /// The uniform type identifier of the files, as plain text (Core does not import UniformTypeIdentifiers).
    ///
    /// DXF has no system-declared identifier: Apple's list of system-declared types has none for it, and
    /// the identifiers CAD apps declare for themselves exist only while that app is installed. DXF files
    /// therefore use the generic `public.data` and rely on the `.dxf` extension.
    public var contentTypeIdentifier: String {
        switch self {
        case .planPDF: return "com.adobe.pdf"
        case .cadDXF: return "public.data"
        case .model3D: return "com.pixar.universal-scene-description-mobile"
        case .dataJSON, .costingSpec: return "public.json"
        case .csv: return "public.comma-separated-values-text"
        }
    }
}

// MARK: - Request, artifacts, errors

/// Where a floor's USDZ model comes from.
public enum USDZSource: Equatable, Sendable {
    case data(Data)
    /// Read when the export runs.
    case file(URL)
}

/// Everything `ExportEngine.run` needs.
public struct ExportRequest: Sendable {
    public var property: Property
    public var formats: Set<ExportFormat>
    /// How lengths and areas are written in the PDF, DXF text and CSV.
    public var units: DisplayUnits
    /// "auto" (A4 when every plan fits at 1:50 or larger, otherwise A3), "a4" or "a3". Anything else is "auto".
    public var paper: String
    /// Plan scale denominator for the PDF (50 means 1:50). nil picks the largest standard scale that fits.
    public var scale: Double?
    /// Add the room schedule pages to the PDF.
    public var includeSchedule: Bool
    /// The saved USDZ model of each floor, by floor id. A floor without one is left out with a note.
    public var usdzSources: [UUID: USDZSource]
    /// The date in file names and title blocks.
    public var now: Date

    public init(property: Property,
                formats: Set<ExportFormat> = Set(ExportFormat.allCases),
                units: DisplayUnits = .default,
                paper: String = "auto",
                scale: Double? = nil,
                includeSchedule: Bool = true,
                usdzSources: [UUID: USDZSource] = [:],
                now: Date = Date()) {
        self.property = property
        self.formats = formats
        self.units = units
        self.paper = paper
        self.scale = scale
        self.includeSchedule = includeSchedule
        self.usdzSources = usdzSources
        self.now = now
    }
}

/// One file ready to write or share.
public struct ExportArtifact: Equatable, Sendable, Identifiable {
    /// `NexaFix_Marina-Gate-2-Unit-2304_2026-10-09_floor-plan.pdf`
    public var filename: String
    public var data: Data
    public var formatKind: ExportFormat
    public var contentTypeIdentifier: String
    /// Something the person should know about this file, if anything.
    public var note: String?

    public var id: String { filename }

    public init(filename: String, data: Data, formatKind: ExportFormat, contentTypeIdentifier: String,
                note: String? = nil) {
        self.filename = filename
        self.data = data
        self.formatKind = formatKind
        self.contentTypeIdentifier = contentTypeIdentifier
        self.note = note
    }
}

/// The files and what was left out.
public struct ExportResult: Equatable, Sendable {
    public var artifacts: [ExportArtifact]
    /// Plain sentences about anything asked for but not produced ("Level 23 has no 3D model").
    public var notes: [String]

    public init(artifacts: [ExportArtifact], notes: [String] = []) {
        self.artifacts = artifacts
        self.notes = notes
    }
}

public enum ExportError: Error, Equatable, LocalizedError, Sendable {
    case noFormatSelected
    case noRooms
    /// Every chosen format was left out; the reasons are the notes.
    case nothingProduced(reasons: [String])
    case failed(format: ExportFormat, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noFormatSelected:
            return "No format is selected. Choose at least one."
        case .noRooms:
            return "This property has no rooms yet. Scan a room, then export."
        case .nothingProduced(let reasons):
            return reasons.isEmpty ? "None of the chosen formats had anything to export."
                : "Nothing was exported. " + reasons.joined(separator: " ")
        case .failed(let format, let reason):
            return "The \(format.displayName) could not be made (\(reason))."
        }
    }
}

// MARK: - Engine

public enum ExportEngine {

    /// Largest scale a plan must reach for "auto" paper to choose A4 (1:50 or larger).
    static let autoPaperScale = 50.0

    /// The files for a request. See `runDetailed` for what was left out.
    public static func run(_ request: ExportRequest) throws -> [ExportArtifact] {
        try runDetailed(request).artifacts
    }

    /// The files for a request, in a fixed order (PDF, DXF per floor, USDZ per floor, JSON, CSV, costing
    /// spec), and the notes for anything that was asked for but could not be made.
    ///
    /// Throws when no format is chosen, the property has no rooms, an exporter fails, or nothing at all
    /// could be produced.
    public static func runDetailed(_ request: ExportRequest) throws -> ExportResult {
        guard !request.formats.isEmpty else { throw ExportError.noFormatSelected }
        guard request.property.roomCount > 0 else { throw ExportError.noRooms }

        var artifacts: [ExportArtifact] = []
        var notes: [String] = []
        var taken: Set<String> = []

        func add(_ data: Data, format: ExportFormat, kind: String, ext: String? = nil, note: String? = nil) {
            let wanted = ExportNaming.fileName(for: request.property, date: request.now, kind: kind,
                                               ext: ext ?? format.fileExtension)
            let name = ExportNaming.uniqueName(wanted, existing: taken)
            taken.insert(name)
            artifacts.append(ExportArtifact(filename: name, data: data, formatKind: format,
                                            contentTypeIdentifier: format.contentTypeIdentifier, note: note))
        }

        let pdfOptions = pdfOptions(for: request)

        for format in ExportFormat.allCases where request.formats.contains(format) {
            switch format {
            case .planPDF:
                let data = PlanPDFRenderer.render(property: request.property, options: pdfOptions, now: request.now)
                add(data, format: format, kind: "floor-plan")

            case .cadDXF:
                let scales = planScales(for: request.property, options: pdfOptions)
                for (index, floor) in request.property.floors.enumerated() {
                    guard !floor.rooms.isEmpty else {
                        notes.append("\(floor.name) has no rooms, so it has no DXF drawing.")
                        continue
                    }
                    let drawing = cadDrawing(for: floor, in: request.property, scale: scales[index] ?? 50,
                                             units: request.units)
                    let data = DXFExporter.data(drawing, options: DXFExporter.Options(units: .millimetres))
                    add(data, format: format, kind: "plan-" + floorToken(floor))
                }

            case .model3D:
                for floor in request.property.floors {
                    if let data = usdzData(for: floor, in: request) {
                        add(data, format: format, kind: "model-" + floorToken(floor))
                    } else if floor.assets.structureUSDZ != nil {
                        notes.append("The saved 3D model of \(floor.name) could not be read.")
                    } else {
                        notes.append("\(floor.name) has no 3D model. Scan the level again to create one.")
                    }
                }

            case .dataJSON:
                do {
                    add(try ScanExport.json(property: request.property, generatedAt: request.now),
                        format: format, kind: "scan")
                } catch {
                    throw ExportError.failed(format: format, reason: describe(error))
                }

            case .csv:
                for file in CSVExport.files(for: request.property, units: request.units) {
                    var stem = file.name
                    if stem.hasSuffix(".csv") { stem.removeLast(4) }
                    add(Data(file.content.utf8), format: format, kind: stem)
                }

            case .costingSpec:
                do {
                    add(try CostingSpecExport.json(property: request.property), format: format, kind: "costing-spec")
                } catch {
                    throw ExportError.failed(format: format, reason: describe(error))
                }
            }
        }

        guard !artifacts.isEmpty else { throw ExportError.nothingProduced(reasons: notes) }
        return ExportResult(artifacts: artifacts, notes: notes)
    }

    // MARK: PDF options

    /// The PDF options a request implies. The paper is resolved here (see `ExportRequest.paper`).
    static func pdfOptions(for request: ExportRequest) -> PlanPDFOptions {
        let fixed = validScale(request.scale)
        let scale: PlanPDFScale = fixed.map { PlanPDFScale.fixed($0) } ?? .auto
        let paper = resolvePaper(request.paper, property: request.property, scale: scale, units: request.units,
                                 target: fixed ?? autoPaperScale)
        return PlanPDFOptions(paper: paper, orientation: .auto, scale: scale, units: request.units,
                              includeSchedule: request.includeSchedule)
    }

    static func validScale(_ scale: Double?) -> Double? {
        guard let scale, scale.isFinite, scale > 0 else { return nil }
        return scale
    }

    /// "a4" and "a3" are taken as written. Anything else is "auto": A4 when every plan page reaches
    /// `target` (1:50, or the requested scale) on A4, otherwise A3.
    static func resolvePaper(_ choice: String, property: Property, scale: PlanPDFScale, units: DisplayUnits,
                             target: Double) -> PDFPaper {
        switch choice.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "a4": return .a4
        case "a3": return .a3
        default:
            let probe = PlanPDFOptions(paper: .a4, orientation: .auto, scale: scale, units: units,
                                       includeSchedule: false)
            let plans = PlanPDFRenderer.pageInfos(property: property, options: probe).filter { $0.kind == .plan }
            let fits = !plans.isEmpty && plans.allSatisfy { ($0.scale ?? .infinity) <= target }
            return fits ? .a4 : .a3
        }
    }

    /// The scale each floor's plan page gets in the PDF, by floor index, so the DXF text height matches.
    private static func planScales(for property: Property, options: PlanPDFOptions) -> [Int: Double] {
        var probe = options
        probe.includeSchedule = false
        let plans = PlanPDFRenderer.pageInfos(property: property, options: probe).filter { $0.kind == .plan }
        var scales: [Int: Double] = [:]
        for (index, page) in plans.enumerated() {
            if let scale = page.scale { scales[index] = scale }
        }
        return scales
    }

    // MARK: Helpers

    /// The part of a file name that says which level it is: "Level-1", "Level-minus-1".
    ///
    /// `ExportNaming` turns every dash into a separator, so "Level -1" would read "Level-1", the same as the
    /// first floor. A minus sign in front of a number is spelled out first, so a basement never looks like
    /// the level above it.
    static func floorToken(_ floor: Floor) -> String {
        ExportNaming.sanitizedComponent(spellingOutMinus(in: floor.name), maxLength: 16, fallback: "level")
    }

    /// "Level -1" becomes "Level minus 1". A dash inside a word or a range ("Unit-2", "1-3") is left alone.
    static func spellingOutMinus(in name: String) -> String {
        let characters = Array(name)
        var out = ""
        for (index, character) in characters.enumerated() {
            let isMinus = character == "-" || character == "\u{2212}"
            let startsWord = index == 0 || characters[index - 1].isWhitespace || characters[index - 1] == "("
            let beforeNumber = index + 1 < characters.count && characters[index + 1].isASCII
                && characters[index + 1].isNumber
            out += isMinus && startsWord && beforeNumber ? "minus " : String(character)
        }
        return out
    }

    /// The plan of one level for the DXF: the drawing of the floor at `scale`, with the property and level
    /// named under it. The file name says the same, but a drawing is passed around without its name, and a
    /// plan of the wrong storey is easy to cut from.
    static func cadDrawing(for floor: Floor, in property: Property, scale: Double, units: DisplayUnits) -> PlanDrawing {
        let drawing = PlanDrawingBuilder.build(floor: floor, property: property,
                                               options: PlanOptions(scale: scale, units: units))
        let caption = [property.name, floor.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let height = 3.5 * scale / 1000   // 3.5 mm tall on paper at the plot scale, in model metres
        guard !caption.isEmpty, height.isFinite, height > 0,
              drawing.bounds.min.x.isFinite, drawing.bounds.min.y.isFinite else { return drawing }
        let origin = Point2(drawing.bounds.min.x, drawing.bounds.min.y - 2 * height)
        var captioned = drawing
        captioned.primitives.append(LayeredPrimitive(
            .notes, .text(caption, at: origin, height: height, rotation: 0, anchor: .left, color: .black, bold: true)))
        let width = Double(caption.count) * height * 0.6
        captioned.bounds = drawing.bounds.union(Bounds2(min: origin, max: Point2(origin.x + width, origin.y + height)))
        return captioned
    }

    private static func usdzData(for floor: Floor, in request: ExportRequest) -> Data? {
        guard let source = request.usdzSources[floor.id] else { return nil }
        let data: Data?
        switch source {
        case .data(let bytes): data = bytes
        case .file(let url): data = try? Data(contentsOf: url)
        }
        guard let data, !data.isEmpty else { return nil }
        return data
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    }
}

// MARK: - Readiness

/// How much of a property has been checked on site, for the banner on the Export sheet.
///
/// The counts use the same rules as the exporters and the on-site checklist (`DataMeasureList`), so the
/// numbers on screen, in the PDF schedule and in the JSON always agree.
public struct ExportReadiness: Equatable, Sendable {

    /// A joinery-critical dimension nobody has checked.
    public struct Item: Equatable, Sendable, Identifiable {
        /// Unique in one readiness: the floor and room ids plus the dimension's place in the room's list. Two
        /// measurements may carry the same label ("Measurement"), so the label alone cannot tell them apart.
        public let id: String
        public var floorName: String
        public var roomName: String
        /// "Wall A length", "Door 1 width", "Ceiling height", a custom measurement's label.
        public var label: String
        /// What LiDAR read, metres.
        public var scannedM: Double
        /// Typical LiDAR error for that value, metres.
        public var toleranceM: Double

        init(id: String, floorName: String, roomName: String, label: String, scannedM: Double, toleranceM: Double) {
            self.id = id
            self.floorName = floorName
            self.roomName = roomName
            self.label = label
            self.scannedM = scannedM
            self.toleranceM = toleranceM
        }

        /// "Living Room: Wall A length".
        public var title: String { roomName + ": " + label }
    }

    /// Dimensions with a site check, of every source.
    public let verified: Int
    /// Dimensions that can be checked.
    public let total: Int
    /// The part of `verified` that was checked with a laser.
    public let laserVerified: Int
    public let joineryVerified: Int
    public let joineryTotal: Int
    /// Wall lengths, ceiling heights, opening sizes and custom measurements still on their LiDAR value, in
    /// property order.
    public let unverifiedJoinery: [Item]

    public init(property: Property) {
        var verified = 0, total = 0, laser = 0, joineryVerified = 0, joineryTotal = 0
        var open: [Item] = []
        for floor in property.floors {
            for room in floor.rooms {
                let roomName = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                for (position, item) in DataMeasureList.items(for: room).enumerated() {
                    total += 1
                    if let check = item.measured.verification {
                        verified += 1
                        if check.source == .laser { laser += 1 }
                    }
                    guard item.isJoinery else { continue }
                    joineryTotal += 1
                    if item.measured.isVerified {
                        joineryVerified += 1
                    } else {
                        open.append(Item(id: "\(floor.id.uuidString)/\(room.id.uuidString)/\(position)",
                                         floorName: floor.name,
                                         roomName: roomName.isEmpty ? room.kind.displayName : roomName,
                                         label: item.label, scannedM: item.measured.scanned,
                                         toleranceM: ScanAccuracy.typicalTolerance(forLength: item.measured.scanned)))
                    }
                }
            }
        }
        self.verified = verified
        self.total = total
        self.laserVerified = laser
        self.joineryVerified = joineryVerified
        self.joineryTotal = joineryTotal
        self.unverifiedJoinery = open
    }

    /// Something joinery is cut from still rests on a LiDAR number.
    public var hasUnverifiedJoinery: Bool { !unverifiedJoinery.isEmpty }
    /// There is nothing to check (no rooms).
    public var isEmpty: Bool { total == 0 }
    /// verified / total, 0...1.
    public var fraction: Double { total == 0 ? 0 : Double(verified) / Double(total) }

    /// "14 of 52 dimensions checked with a laser. Unchecked dimensions are LiDAR estimates (typically 1-2 %)."
    ///
    /// Says "checked on site" instead of "with a laser" when some checks were made with a tape or taken
    /// from a drawing, so the banner never claims more than was done.
    public var banner: String {
        guard total > 0 else { return "There are no dimensions to check yet." }
        let how = verified == laserVerified ? "with a laser" : "on site"
        let noun = total == 1 ? "dimension" : "dimensions"
        if verified == total {
            return "All \(total) \(noun) checked \(how)."
        }
        return "\(verified) of \(total) \(noun) checked \(how). Unchecked dimensions are LiDAR estimates (typically 1-2 %)."
    }
}
