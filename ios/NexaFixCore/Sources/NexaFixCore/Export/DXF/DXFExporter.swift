import Foundation

// DXF export of a `PlanDrawing` for CAD (AutoCAD, BricsCAD, Fusion 360, Rhino, SketchUp, LibreCAD).
//
// Format: DXF release 2000 (AC1015), ASCII. R2000 was chosen over R12 (AC1009) because it carries
// lightweight polylines, per-entity lineweights, handles and layouts that CAD users expect, and
// every current CAD program reads it. The file follows the structure AutoCAD itself writes:
// HEADER, CLASSES, TABLES (VPORT, LTYPE, LAYER, STYLE, VIEW, UCS, APPID, DIMSTYLE, BLOCK_RECORD),
// BLOCKS (model and paper space), ENTITIES, OBJECTS (named object dictionary, layouts, plot style
// placeholder), EOF. Every record has a unique handle and an owner; every entity has the AcDb
// subclass markers.
//
// Units: model space is the plan in millimetres (default) or metres. Plan y is up the page, the
// same as DXF y, so no flip is applied. Angles are degrees counter-clockwise.

/// Drawing unit of the exported file (`$INSUNITS`).
public enum DXFUnits: String, Codable, CaseIterable, Sendable {
    case millimetres
    case metres

    /// Value of the `$INSUNITS` header variable: 4 millimetres, 6 metres.
    public var insunitsCode: Int { self == .millimetres ? 4 : 6 }

    /// Drawing units per metre of plan space.
    public var unitsPerMetre: Double { self == .millimetres ? 1000 : 1 }
}

/// How entity colours are written.
public enum DXFColorMode: String, Codable, CaseIterable, Sendable {
    /// No colour on strokes and text: they follow their layer (NF-WALLS ...), so CAD users restyle by layer.
    case byLayer
    /// Each stroke and text carries the nearest AutoCAD Color Index number (group 62).
    case nearestACI
    /// As `nearestACI`, plus the exact 24-bit colour (group 420) for programs that read it.
    case trueColor
}

public enum DXFExporter {

    /// What the file contains. The defaults suit a CAD hand-off.
    public struct Options: Codable, Hashable, Sendable {
        /// Drawing unit: millimetres (default) or metres.
        public var units: DXFUnits
        /// Write TEXT entities (dimension values, angles, room labels, notes). Switch off to get geometry only,
        /// for example when the file goes into a modelling program where annotation text is clutter.
        public var includeTextLayers: Bool
        /// Write filled polylines as solid HATCH entities. Fills always carry an explicit colour (group 62 and,
        /// for exact tints, group 420) because a fill that followed its layer colour would hide the strokes on top.
        public var includeFills: Bool
        /// Colour policy for strokes and text; see `DXFColorMode`.
        public var colorMode: DXFColorMode
        /// Write a lineweight (group 370) on a stroke whose weight differs from its layer's. Layer lineweights
        /// are always defined in the LAYER table.
        public var entityLineweights: Bool
        /// Use CRLF line endings (what AutoCAD writes on Windows) instead of LF. Every reader accepts both.
        public var windowsLineEndings: Bool

        public init(units: DXFUnits = .millimetres, includeTextLayers: Bool = true, includeFills: Bool = true,
                    colorMode: DXFColorMode = .byLayer, entityLineweights: Bool = true,
                    windowsLineEndings: Bool = false) {
            self.units = units
            self.includeTextLayers = includeTextLayers
            self.includeFills = includeFills
            self.colorMode = colorMode
            self.entityLineweights = entityLineweights
            self.windowsLineEndings = windowsLineEndings
        }
    }

    /// The DXF text for a drawing. Pure ASCII, deterministic (no dates, no random ids): the same drawing and
    /// options always give the same bytes. Entities that cannot be drawn (non-finite or absurd coordinates,
    /// zero-length lines, empty text, zero radius) are skipped.
    public static func export(_ drawing: PlanDrawing, options: Options = Options()) -> String {
        DXFDocument(drawing: drawing, options: options).build()
    }

    /// The same text as ASCII bytes, ready to write to a `.dxf` file.
    public static func data(_ drawing: PlanDrawing, options: Options = Options()) -> Data {
        Data(export(drawing, options: options).utf8)
    }
}

// MARK: - Layer table

/// How a plan layer looks in CAD: distinct ACI colour and a lineweight in hundredths of a millimetre.
struct DXFLayerStyle {
    let layer: PlanLayer
    let aci: Int
    let lineweight: Int

    static let all: [DXFLayerStyle] = [
        DXFLayerStyle(layer: .walls, aci: 7, lineweight: 50),        // black / white
        DXFLayerStyle(layer: .wallsOpen, aci: 150, lineweight: 25),  // blue
        DXFLayerStyle(layer: .doors, aci: 30, lineweight: 25),       // orange
        DXFLayerStyle(layer: .windows, aci: 4, lineweight: 25),      // cyan
        DXFLayerStyle(layer: .openings, aci: 6, lineweight: 25),     // magenta
        DXFLayerStyle(layer: .furniture, aci: 8, lineweight: 13),    // grey
        DXFLayerStyle(layer: .dimensions, aci: 3, lineweight: 13),   // green
        DXFLayerStyle(layer: .angles, aci: 1, lineweight: 13),       // red
        DXFLayerStyle(layer: .roomLabels, aci: 5, lineweight: 18),   // blue
        DXFLayerStyle(layer: .notes, aci: 32, lineweight: 18),       // brown
    ]

    /// Style of a layer; a layer added to the contract later gets a neutral default until it is listed above.
    static func style(for layer: PlanLayer) -> DXFLayerStyle {
        all.first(where: { $0.layer == layer }) ?? DXFLayerStyle(layer: layer, aci: 7, lineweight: 25)
    }
}

// MARK: - Handles of the fixed structure

/// Handles for every record that is always present, allocated in a fixed order so the output is deterministic.
private struct DXFHandles {
    // Tables
    let vportTable, ltypeTable, layerTable, styleTable, viewTable, ucsTable, appidTable, dimstyleTable,
        blockRecordTable: String
    // Table records
    let vportActive: String
    let ltypeByBlock, ltypeByLayer, ltypeContinuous, ltypeDashed: String
    let layerZero: String
    let planLayers: [String]
    let styleStandard, styleBold: String
    let appidAcad: String
    let dimstyleStandard: String
    let blockRecordModel, blockRecordPaper: String
    // Blocks
    let modelBegin, modelEnd, paperBegin, paperEnd: String
    // Objects
    let rootDictionary, groupDictionary, layoutDictionary, mlineStyleDictionary, plotSettingsDictionary,
        plotStyleDictionary, plotStylePlaceholder, mlineStyleStandard, layoutModel, layoutPaper: String

    init(_ a: inout DXFHandleAllocator) {
        vportTable = a.allocate(); ltypeTable = a.allocate(); layerTable = a.allocate()
        styleTable = a.allocate(); viewTable = a.allocate(); ucsTable = a.allocate()
        appidTable = a.allocate(); dimstyleTable = a.allocate(); blockRecordTable = a.allocate()
        vportActive = a.allocate()
        ltypeByBlock = a.allocate(); ltypeByLayer = a.allocate(); ltypeContinuous = a.allocate()
        ltypeDashed = a.allocate()
        layerZero = a.allocate()
        var layers: [String] = []
        for _ in PlanLayer.allCases { layers.append(a.allocate()) }
        planLayers = layers
        styleStandard = a.allocate(); styleBold = a.allocate()
        appidAcad = a.allocate()
        dimstyleStandard = a.allocate()
        blockRecordModel = a.allocate(); blockRecordPaper = a.allocate()
        modelBegin = a.allocate(); modelEnd = a.allocate(); paperBegin = a.allocate(); paperEnd = a.allocate()
        rootDictionary = a.allocate(); groupDictionary = a.allocate(); layoutDictionary = a.allocate()
        mlineStyleDictionary = a.allocate(); plotSettingsDictionary = a.allocate()
        plotStyleDictionary = a.allocate(); plotStylePlaceholder = a.allocate()
        mlineStyleStandard = a.allocate(); layoutModel = a.allocate(); layoutPaper = a.allocate()
    }
}

// MARK: - Extents

/// Running bounding box in drawing units.
private struct DXFExtents {
    var minX = Double.infinity, minY = Double.infinity
    var maxX = -Double.infinity, maxY = -Double.infinity

    var isEmpty: Bool { minX > maxX || minY > maxY }

    mutating func include(_ x: Double, _ y: Double) {
        minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
        minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
    }
}

// MARK: - Document

/// Builds the whole file. A value type that is created, asked to `build()` once and discarded.
private struct DXFDocument {
    let drawing: PlanDrawing
    let options: DXFExporter.Options
    /// Drawing units per metre (1000 or 1) and per paper millimetre of the plan scale.
    let unitsPerMetre: Double
    let unitsPerMillimetre: Double
    /// Plan scale denominator (50 for 1:50), sanitised.
    let plotScale: Double

    init(drawing: PlanDrawing, options: DXFExporter.Options) {
        self.drawing = drawing
        self.options = options
        unitsPerMetre = options.units.unitsPerMetre
        unitsPerMillimetre = options.units == .millimetres ? 1 : 0.001
        let scale = drawing.options.scale
        plotScale = scale.isFinite && scale > 0 ? Swift.min(Swift.max(scale, 1), 10_000) : 50
    }

    func build() -> String {
        var allocator = DXFHandleAllocator(first: 1)
        let handles = DXFHandles(&allocator)

        var entities = DXFEntityWriter(options: options, unitsPerMetre: unitsPerMetre,
                                       owner: handles.blockRecordModel, allocator: allocator)
        for item in drawing.primitives { entities.add(item) }
        let handleSeed = entities.allocator.seed

        // Extents: what was actually written, widened by the drawing's own bounds (which also cover text).
        var extents = entities.extents
        if entities.entityCount > 0 {
            let b = drawing.bounds
            let values = [b.min.x, b.min.y, b.max.x, b.max.y]
            if values.allSatisfy({ $0.isFinite }), b.min.x <= b.max.x, b.min.y <= b.max.y {
                let lo = (b.min.x * unitsPerMetre, b.min.y * unitsPerMetre)
                let hi = (b.max.x * unitsPerMetre, b.max.y * unitsPerMetre)
                if abs(lo.0) <= DXFFormat.maxCoordinate, abs(lo.1) <= DXFFormat.maxCoordinate,
                   abs(hi.0) <= DXFFormat.maxCoordinate, abs(hi.1) <= DXFFormat.maxCoordinate {
                    extents.include(lo.0, lo.1)
                    extents.include(hi.0, hi.1)
                }
            }
        }

        var w = DXFWriter(windowsLineEndings: options.windowsLineEndings)
        writeHeader(&w, extents: extents, handleSeed: handleSeed)
        writeClasses(&w)
        writeTables(&w, handles: handles, extents: extents)
        writeBlocks(&w, handles: handles)
        w.beginSection("ENTITIES")
        w.append(entities.writer)
        w.endSection()
        writeObjects(&w, handles: handles, extents: extents)
        w.tag(0, "EOF")
        return w.output
    }

    // MARK: HEADER

    private func writeHeader(_ w: inout DXFWriter, extents: DXFExtents, handleSeed: String) {
        let u = unitsPerMillimetre
        let textHeight = 2.5 * plotScale * u
        let isMM = options.units == .millimetres

        w.beginSection("HEADER")
        w.tag(9, "$ACADVER"); w.tag(1, "AC1015")
        w.tag(9, "$ACADMAINTVER"); w.tag(70, 6)
        w.tag(9, "$DWGCODEPAGE"); w.tag(3, "ANSI_1252")
        w.tag(9, "$INSBASE"); w.point(0, 0, 0)

        // Extents of the drawing; AutoCAD's own marker for "nothing drawn" is +/-1E20.
        let limits: (min: (Double, Double), max: (Double, Double))
        if extents.isEmpty {
            w.tag(9, "$EXTMIN"); w.tag(10, "1.000000000000000E+20"); w.tag(20, "1.000000000000000E+20")
            w.tag(30, "1.000000000000000E+20")
            w.tag(9, "$EXTMAX"); w.tag(10, "-1.000000000000000E+20"); w.tag(20, "-1.000000000000000E+20")
            w.tag(30, "-1.000000000000000E+20")
            limits = ((0, 0), (420 * u, 297 * u))
        } else {
            w.tag(9, "$EXTMIN"); w.point(extents.minX, extents.minY, 0)
            w.tag(9, "$EXTMAX"); w.point(extents.maxX, extents.maxY, 0)
            limits = ((extents.minX, extents.minY), (extents.maxX, extents.maxY))
        }
        w.tag(9, "$LIMMIN"); w.point(limits.min.0, limits.min.1)
        w.tag(9, "$LIMMAX"); w.point(limits.max.0, limits.max.1)
        // Paper space limits: an A3 sheet in drawing units. AutoCAD takes the real sheet from the layout; LibreCAD
        // sizes its page from here and would otherwise print a 420 m wide page when the drawing is in metres.
        w.tag(9, "$PLIMCHECK"); w.tag(70, 0)
        w.tag(9, "$PLIMMIN"); w.point(0, 0)
        w.tag(9, "$PLIMMAX"); w.point(420 * u, 297 * u)

        w.tag(9, "$ORTHOMODE"); w.tag(70, 0)
        w.tag(9, "$REGENMODE"); w.tag(70, 1)
        w.tag(9, "$FILLMODE"); w.tag(70, 1)
        w.tag(9, "$QTEXTMODE"); w.tag(70, 0)
        w.tag(9, "$MIRRTEXT"); w.tag(70, 0)
        w.tag(9, "$LTSCALE"); w.tag(40, 1.0)
        w.tag(9, "$ATTMODE"); w.tag(70, 1)
        w.tag(9, "$TEXTSIZE"); w.tag(40, textHeight)
        w.tag(9, "$TRACEWID"); w.tag(40, 0.05 * plotScale * u)
        w.tag(9, "$TEXTSTYLE"); w.tag(7, "Standard")
        w.tag(9, "$CLAYER"); w.tag(8, "0")
        w.tag(9, "$CELTYPE"); w.tag(6, "ByLayer")
        w.tag(9, "$CECOLOR"); w.tag(62, 256)
        w.tag(9, "$CELTSCALE"); w.tag(40, 1.0)
        w.tag(9, "$DISPSILH"); w.tag(70, 0)

        // Dimension variables, matching the Standard dimension style in the DIMSTYLE table: text 2.5 mm
        // on paper, scaled by the plan scale, so a dimension added in CAD looks like the plan's own.
        w.tag(9, "$DIMSCALE"); w.tag(40, plotScale)
        w.tag(9, "$DIMASZ"); w.tag(40, 2.5 * u)
        w.tag(9, "$DIMEXO"); w.tag(40, 0.625 * u)
        w.tag(9, "$DIMDLI"); w.tag(40, 3.75 * u)
        w.tag(9, "$DIMEXE"); w.tag(40, 1.25 * u)
        w.tag(9, "$DIMTXT"); w.tag(40, 2.5 * u)
        w.tag(9, "$DIMCEN"); w.tag(40, 2.5 * u)
        w.tag(9, "$DIMTAD"); w.tag(70, 1)
        w.tag(9, "$DIMGAP"); w.tag(40, 0.625 * u)
        w.tag(9, "$DIMSTYLE"); w.tag(2, "Standard")
        w.tag(9, "$DIMDEC"); w.tag(70, isMM ? 0 : 3)
        w.tag(9, "$DIMTDEC"); w.tag(70, isMM ? 0 : 3)
        w.tag(9, "$DIMTXSTY"); w.tag(7, "Standard")
        w.tag(9, "$DIMLUNIT"); w.tag(70, 2)

        w.tag(9, "$LUNITS"); w.tag(70, 2)
        w.tag(9, "$LUPREC"); w.tag(70, isMM ? 1 : 4)
        w.tag(9, "$AUNITS"); w.tag(70, 0)
        w.tag(9, "$AUPREC"); w.tag(70, 1)
        w.tag(9, "$ELEVATION"); w.tag(40, 0.0)
        w.tag(9, "$PELEVATION"); w.tag(40, 0.0)
        w.tag(9, "$THICKNESS"); w.tag(40, 0.0)
        w.tag(9, "$LIMCHECK"); w.tag(70, 0)
        w.tag(9, "$ANGBASE"); w.tag(50, 0.0)
        w.tag(9, "$ANGDIR"); w.tag(70, 0)
        w.tag(9, "$PDMODE"); w.tag(70, 0)
        w.tag(9, "$PDSIZE"); w.tag(40, 0.0)
        w.tag(9, "$PLINEWID"); w.tag(40, 0.0)
        w.tag(9, "$HANDSEED"); w.tag(5, handleSeed)
        w.tag(9, "$WORLDVIEW"); w.tag(70, 1)
        w.tag(9, "$TILEMODE"); w.tag(70, 1)
        w.tag(9, "$MAXACTVP"); w.tag(70, 64)
        w.tag(9, "$UNITMODE"); w.tag(70, 0)
        w.tag(9, "$VISRETAIN"); w.tag(70, 1)
        w.tag(9, "$PLINEGEN"); w.tag(70, 0)
        w.tag(9, "$PSLTSCALE"); w.tag(70, 1)
        w.tag(9, "$CMLSTYLE"); w.tag(2, "Standard")
        w.tag(9, "$CMLJUST"); w.tag(70, 0)
        w.tag(9, "$CMLSCALE"); w.tag(40, 20.0 * u)
        w.tag(9, "$MEASUREMENT"); w.tag(70, 1)
        w.tag(9, "$CELWEIGHT"); w.tag(370, -1)
        w.tag(9, "$ENDCAPS"); w.tag(280, 0)
        w.tag(9, "$JOINSTYLE"); w.tag(280, 0)
        w.tag(9, "$LWDISPLAY"); w.tag(290, 1)
        w.tag(9, "$INSUNITS"); w.tag(70, options.units.insunitsCode)
        w.tag(9, "$PSTYLEMODE"); w.tag(290, 1)
        w.tag(9, "$EXTNAMES"); w.tag(290, 1)
        w.endSection()
    }

    // MARK: CLASSES

    /// Only the classes the OBJECTS section uses; the entities written (LINE, LWPOLYLINE, ARC, CIRCLE,
    /// TEXT, HATCH) are built into every reader and need no class entry.
    private func writeClasses(_ w: inout DXFWriter) {
        w.beginSection("CLASSES")
        let classes: [(String, String, String)] = [
            ("ACDBDICTIONARYWDFLT", "AcDbDictionaryWithDefault", "ObjectDBX Classes"),
            ("ACDBPLACEHOLDER", "AcDbPlaceHolder", "ObjectDBX Classes"),
            ("LAYOUT", "AcDbLayout", "ObjectDBX Classes"),
        ]
        for (name, cppName, application) in classes {
            w.tag(0, "CLASS")
            w.tag(1, name)
            w.tag(2, cppName)
            w.tag(3, application)
            w.tag(90, 0)
            w.tag(280, 0)
            w.tag(281, 0)
        }
        w.endSection()
    }

    // MARK: TABLES

    private func writeTables(_ w: inout DXFWriter, handles h: DXFHandles, extents: DXFExtents) {
        w.beginSection("TABLES")
        let u = unitsPerMillimetre

        func beginTable(_ name: String, handle: String, count: Int, dimstyle: Bool = false) {
            w.tag(0, "TABLE")
            w.tag(2, name)
            w.tag(5, handle)
            w.tag(330, "0")
            w.tag(100, "AcDbSymbolTable")
            w.tag(70, count)
            if dimstyle { w.tag(100, "AcDbDimStyleTable") }
        }
        func record(_ type: String, handle: String, owner: String, marker: String, handleCode: Int = 5) {
            w.tag(0, type)
            w.tag(handleCode, handle)
            w.tag(330, owner)
            w.tag(100, "AcDbSymbolTableRecord")
            w.tag(100, marker)
        }
        func endTable() { w.tag(0, "ENDTAB") }

        // VPORT: one active viewport, framed on the drawing so CAD opens zoomed to the plan.
        let aspect = 1.5
        let centre: (Double, Double)
        let viewHeight: Double
        if extents.isEmpty {
            centre = (2500 * u, 1500 * u)
            viewHeight = 5000 * u
        } else {
            centre = ((extents.minX + extents.maxX) / 2, (extents.minY + extents.maxY) / 2)
            let height = Swift.max(extents.maxY - extents.minY, (extents.maxX - extents.minX) / aspect, 100 * u)
            viewHeight = height * 1.1
        }
        beginTable("VPORT", handle: h.vportTable, count: 1)
        record("VPORT", handle: h.vportActive, owner: h.vportTable, marker: "AcDbViewportTableRecord")
        w.tags([(2, "*Active"), (70, 0), (10, 0.0), (20, 0.0), (11, 1.0), (21, 1.0)])
        w.tag(12, centre.0); w.tag(22, centre.1)
        w.tags([(13, 0.0), (23, 0.0)])
        let grid = 100 * u
        w.tag(14, grid); w.tag(24, grid); w.tag(15, grid); w.tag(25, grid)
        w.tags([(16, 0.0), (26, 0.0), (36, 1.0), (17, 0.0), (27, 0.0), (37, 0.0)])
        w.tag(40, viewHeight); w.tag(41, aspect)
        w.tags([(42, 50.0), (43, 0.0), (44, 0.0), (50, 0.0), (51, 0.0), (71, 0), (72, 1000), (73, 1), (74, 3),
                (75, 0), (76, 0), (77, 0), (78, 0), (281, 0), (65, 0), (146, 0.0)])
        endTable()

        // LTYPE: ByBlock, ByLayer, Continuous and DASHED. The dashed pattern is sized for the plan scale
        // (3 mm dash and 1.5 mm gap on paper), so $LTSCALE stays 1.
        beginTable("LTYPE", handle: h.ltypeTable, count: 4)
        for (name, handle) in [("ByBlock", h.ltypeByBlock), ("ByLayer", h.ltypeByLayer),
                               ("Continuous", h.ltypeContinuous)] {
            record("LTYPE", handle: handle, owner: h.ltypeTable, marker: "AcDbLinetypeTableRecord")
            w.tags([(2, .text(name)), (70, 0), (3, name == "Continuous" ? "Solid line" : ""), (72, 65), (73, 0),
                    (40, 0.0)])
        }
        let dash = 3.0 * plotScale * u
        let gap = 1.5 * plotScale * u
        record("LTYPE", handle: h.ltypeDashed, owner: h.ltypeTable, marker: "AcDbLinetypeTableRecord")
        w.tags([(2, "DASHED"), (70, 0), (3, "Dashed __ __ __ __ __ __ __ __ __ __ __ __ __ _"), (72, 65), (73, 2)])
        w.tag(40, dash + gap)
        w.tag(49, dash); w.tag(74, 0)
        w.tag(49, -gap); w.tag(74, 0)
        endTable()

        // LAYER: "0" plus every plan layer with its own ACI colour and lineweight.
        beginTable("LAYER", handle: h.layerTable, count: 1 + PlanLayer.allCases.count)
        record("LAYER", handle: h.layerZero, owner: h.layerTable, marker: "AcDbLayerTableRecord")
        w.tags([(2, "0"), (70, 0), (62, 7), (6, "Continuous"), (370, -3)])
        w.tag(390, h.plotStylePlaceholder)
        for (index, layer) in PlanLayer.allCases.enumerated() {
            let style = DXFLayerStyle.style(for: layer)
            record("LAYER", handle: h.planLayers[index], owner: h.layerTable, marker: "AcDbLayerTableRecord")
            w.tag(2, layer.rawValue); w.tag(70, 0); w.tag(62, style.aci); w.tag(6, "Continuous")
            w.tag(370, style.lineweight)
            w.tag(390, h.plotStylePlaceholder)
        }
        endTable()

        // STYLE: Standard (Arial) and a bold twin for text marked `bold`.
        beginTable("STYLE", handle: h.styleTable, count: 2)
        let textHeight = 2.5 * plotScale * u
        for (name, handle, file, family, flags) in [
            ("Standard", h.styleStandard, "arial.ttf", "Arial", 34),
            ("NF-BOLD", h.styleBold, "arialbd.ttf", "Arial", 33_554_466),
        ] {
            record("STYLE", handle: handle, owner: h.styleTable, marker: "AcDbTextStyleTableRecord")
            w.tags([(2, .text(name)), (70, 0), (40, 0.0), (41, 1.0), (50, 0.0), (71, 0)])
            w.tag(42, textHeight)
            w.tags([(3, .text(file)), (4, ""), (1001, "ACAD"), (1000, .text(family)), (1071, .integer(flags))])
        }
        endTable()

        beginTable("VIEW", handle: h.viewTable, count: 0)
        endTable()
        beginTable("UCS", handle: h.ucsTable, count: 0)
        endTable()

        beginTable("APPID", handle: h.appidTable, count: 1)
        record("APPID", handle: h.appidAcad, owner: h.appidTable, marker: "AcDbRegAppTableRecord")
        w.tags([(2, "ACAD"), (70, 0)])
        endTable()

        // DIMSTYLE: Standard, in drawing units and scaled by the plan scale.
        beginTable("DIMSTYLE", handle: h.dimstyleTable, count: 1, dimstyle: true)
        record("DIMSTYLE", handle: h.dimstyleStandard, owner: h.dimstyleTable, marker: "AcDbDimStyleTableRecord",
               handleCode: 105)
        let isMM = options.units == .millimetres
        w.tags([(2, "Standard"), (70, 0), (3, ""), (4, "")])
        w.tag(40, plotScale)
        w.tag(41, 2.5 * u); w.tag(42, 0.625 * u); w.tag(43, 3.75 * u); w.tag(44, 1.25 * u)
        w.tags([(45, 0.0), (46, 0.0), (47, 0.0), (48, 0.0)])
        w.tag(140, 2.5 * u); w.tag(141, 2.5 * u)
        w.tags([(142, 0.0), (143, 0.03937007874), (144, 1.0), (145, 0.0), (146, 1.0)])
        w.tag(147, 0.625 * u)
        w.tags([(148, 0.0), (71, 0), (72, 0), (73, 0), (74, 0), (75, 0), (76, 0), (77, 1), (78, 8), (79, 0),
                (170, 0), (171, 3), (172, 1), (173, 0), (174, 0), (175, 0), (176, 0), (177, 0), (178, 0),
                (179, 0)])
        w.tag(271, isMM ? 0 : 3); w.tag(272, isMM ? 0 : 3)
        w.tags([(273, 2), (274, 3), (275, 0), (276, 0), (277, 2), (278, 46), (279, 0), (280, 0), (281, 0),
                (282, 0), (283, 0), (284, 8), (285, 0), (286, 0), (288, 0), (289, 3), (371, -2), (372, -2)])
        endTable()

        beginTable("BLOCK_RECORD", handle: h.blockRecordTable, count: 2)
        record("BLOCK_RECORD", handle: h.blockRecordModel, owner: h.blockRecordTable,
               marker: "AcDbBlockTableRecord")
        w.tag(2, "*Model_Space"); w.tag(340, h.layoutModel)
        record("BLOCK_RECORD", handle: h.blockRecordPaper, owner: h.blockRecordTable,
               marker: "AcDbBlockTableRecord")
        w.tag(2, "*Paper_Space"); w.tag(340, h.layoutPaper)
        endTable()

        w.endSection()
    }

    // MARK: BLOCKS

    private func writeBlocks(_ w: inout DXFWriter, handles h: DXFHandles) {
        w.beginSection("BLOCKS")
        for (name, begin, end, record, paperSpace) in [
            ("*Model_Space", h.modelBegin, h.modelEnd, h.blockRecordModel, false),
            ("*Paper_Space", h.paperBegin, h.paperEnd, h.blockRecordPaper, true),
        ] {
            w.tag(0, "BLOCK")
            w.tag(5, begin); w.tag(330, record); w.tag(100, "AcDbEntity")
            if paperSpace { w.tag(67, 1) }
            w.tag(8, "0"); w.tag(100, "AcDbBlockBegin")
            w.tag(2, name); w.tag(70, 0); w.point(0, 0, 0)
            w.tag(3, name); w.tag(1, "")
            w.tag(0, "ENDBLK")
            w.tag(5, end); w.tag(330, record); w.tag(100, "AcDbEntity")
            if paperSpace { w.tag(67, 1) }
            w.tag(8, "0"); w.tag(100, "AcDbBlockEnd")
        }
        w.endSection()
    }

    // MARK: OBJECTS

    private func writeObjects(_ w: inout DXFWriter, handles h: DXFHandles, extents: DXFExtents) {
        w.beginSection("OBJECTS")
        let paper = (width: 420.0, height: 297.0)

        func dictionary(_ handle: String, owner: String, entries: [(String, String)], type: String = "DICTIONARY") {
            w.tag(0, type)
            w.tag(5, handle); w.tag(330, owner); w.tag(100, "AcDbDictionary"); w.tag(281, 1)
            for (name, target) in entries {
                w.tag(3, name); w.tag(350, target)
            }
        }

        dictionary(h.rootDictionary, owner: "0", entries: [
            ("ACAD_GROUP", h.groupDictionary), ("ACAD_LAYOUT", h.layoutDictionary),
            ("ACAD_MLINESTYLE", h.mlineStyleDictionary), ("ACAD_PLOTSETTINGS", h.plotSettingsDictionary),
            ("ACAD_PLOTSTYLENAME", h.plotStyleDictionary),
        ])
        dictionary(h.groupDictionary, owner: h.rootDictionary, entries: [])
        dictionary(h.layoutDictionary, owner: h.rootDictionary,
                   entries: [("Layout1", h.layoutPaper), ("Model", h.layoutModel)])
        dictionary(h.mlineStyleDictionary, owner: h.rootDictionary, entries: [("Standard", h.mlineStyleStandard)])
        dictionary(h.plotSettingsDictionary, owner: h.rootDictionary, entries: [])

        // Plot style names: the dictionary-with-default holding the "Normal" placeholder that layers point to.
        w.tag(0, "ACDBDICTIONARYWDFLT")
        w.tag(5, h.plotStyleDictionary); w.tag(330, h.rootDictionary); w.tag(100, "AcDbDictionary"); w.tag(281, 1)
        w.tag(3, "Normal"); w.tag(350, h.plotStylePlaceholder)
        w.tag(100, "AcDbDictionaryWithDefault"); w.tag(340, h.plotStylePlaceholder)
        w.tag(0, "ACDBPLACEHOLDER")
        w.tag(5, h.plotStylePlaceholder); w.tag(330, h.plotStyleDictionary)

        w.tag(0, "MLINESTYLE")
        w.tag(5, h.mlineStyleStandard); w.tag(102, "{ACAD_REACTORS"); w.tag(330, h.mlineStyleDictionary)
        w.tag(102, "}"); w.tag(330, h.mlineStyleDictionary); w.tag(100, "AcDbMlineStyle")
        w.tags([(2, "Standard"), (70, 0), (3, ""), (62, 256), (51, 90.0), (52, 90.0), (71, 2), (49, 0.5),
                (62, 256), (6, "BYLAYER"), (49, -0.5), (62, 256), (6, "BYLAYER")])

        for (name, handle, record, isModel, tabOrder) in [
            ("Model", h.layoutModel, h.blockRecordModel, true, 0),
            ("Layout1", h.layoutPaper, h.blockRecordPaper, false, 1),
        ] {
            w.tag(0, "LAYOUT")
            w.tag(5, handle); w.tag(330, h.layoutDictionary); w.tag(100, "AcDbPlotSettings")
            w.tags([(1, ""), (4, "A3"), (6, ""), (40, 7.5), (41, 20.0), (42, 7.5), (43, 20.0)])
            w.tag(44, paper.width); w.tag(45, paper.height)
            w.tags([(46, 0.0), (47, 0.0), (48, 0.0), (49, 0.0), (140, 0.0), (141, 0.0), (142, 1.0), (143, 1.0)])
            w.tag(70, isModel ? 1024 : 0)
            w.tags([(72, 1), (73, 0), (74, 5), (7, ""), (75, 16), (76, 0), (77, 2), (78, 300), (147, 1.0),
                    (148, 0.0), (149, 0.0)])
            w.tag(100, "AcDbLayout")
            w.tags([(1, .text(name)), (70, 1), (71, .integer(tabOrder)), (10, 0.0), (20, 0.0)])
            w.tag(11, paper.width); w.tag(21, paper.height)
            w.tags([(12, 0.0), (22, 0.0), (32, 0.0)])
            for (code, value) in [(14, "1.000000000000000E+20"), (24, "1.000000000000000E+20"),
                                  (34, "1.000000000000000E+20"), (15, "-1.000000000000000E+20"),
                                  (25, "-1.000000000000000E+20"), (35, "-1.000000000000000E+20")] {
                w.tag(code, value)
            }
            w.tags([(146, 0.0), (13, 0.0), (23, 0.0), (33, 0.0), (16, 1.0), (26, 0.0), (36, 0.0), (17, 0.0),
                    (27, 1.0), (37, 0.0), (76, 1)])
            w.tag(330, record)
        }
        w.endSection()
    }
}

// MARK: - Entities

/// Turns layered primitives into ENTITIES text. Everything is converted from plan metres to drawing units here.
private struct DXFEntityWriter {
    let options: DXFExporter.Options
    let unitsPerMetre: Double
    let owner: String
    var allocator: DXFHandleAllocator
    var writer: DXFWriter
    var extents = DXFExtents()
    var entityCount = 0

    /// Lines shorter than this (metres) are not drawn.
    private let minimumLength = 1e-9

    init(options: DXFExporter.Options, unitsPerMetre: Double, owner: String, allocator: DXFHandleAllocator) {
        self.options = options
        self.unitsPerMetre = unitsPerMetre
        self.owner = owner
        self.allocator = allocator
        writer = DXFWriter(windowsLineEndings: options.windowsLineEndings)
    }

    mutating func add(_ item: LayeredPrimitive) {
        let layer = item.layer
        switch item.primitive {
        case let .line(a, b, stroke):
            addLine(a, b, stroke, layer)
        case let .polyline(points, closed, stroke, fill):
            addPolyline(points, closed: closed, stroke: stroke, fill: fill, layer: layer)
        case let .arc(center, radius, startAngle, endAngle, stroke):
            addArc(center, radius, startAngle, endAngle, stroke, layer)
        case let .circle(center, radius, stroke):
            addCircle(center, radius, stroke, layer)
        case let .text(string, at, height, rotation, anchor, color, bold):
            guard options.includeTextLayers else { return }
            addText(string, at: at, height: height, rotation: rotation, anchor: anchor, color: color, bold: bold,
                    layer: layer)
        }
    }

    // MARK: conversion

    /// A plan point in drawing units, nil when it is not a usable number.
    private func convert(_ p: Point2) -> (x: Double, y: Double)? {
        let x = p.x * unitsPerMetre, y = p.y * unitsPerMetre
        guard x.isFinite, y.isFinite, abs(x) <= DXFFormat.maxCoordinate, abs(y) <= DXFFormat.maxCoordinate else {
            return nil
        }
        return (x, y)
    }

    private func convertLength(_ metres: Double) -> Double? {
        let v = metres * unitsPerMetre
        guard v.isFinite, v > 0, v <= DXFFormat.maxCoordinate else { return nil }
        return v
    }

    // MARK: common entity header

    /// Entity type, handle, owner, layer and the optional linetype / colour / lineweight overrides.
    private mutating func begin(_ type: String, layer: PlanLayer, stroke: StrokeStyle?, color: DrawColor?,
                                explicitColor: Bool = false) {
        writer.tag(0, type)
        writer.tag(5, allocator.allocate())
        writer.tag(330, owner)
        writer.tag(100, "AcDbEntity")
        writer.tag(8, layer.rawValue)
        if let stroke = stroke, stroke.dashed { writer.tag(6, "DASHED") }
        if let color = color {
            if explicitColor || options.colorMode != .byLayer {
                writer.tag(62, DXFColor.nearestACI(color))
                if explicitColor || options.colorMode == .trueColor { writer.tag(420, DXFColor.trueColor(color)) }
            }
        }
        if options.entityLineweights, let stroke = stroke,
           let lineweight = DXFLineweight.nearest(toMillimetres: stroke.weight),
           lineweight != DXFLayerStyle.style(for: layer).lineweight {
            writer.tag(370, lineweight)
        }
        entityCount += 1
    }

    // MARK: LINE

    private mutating func addLine(_ a: Point2, _ b: Point2, _ stroke: StrokeStyle, _ layer: PlanLayer) {
        guard let p = convert(a), let q = convert(b), a.distance(to: b) >= minimumLength else { return }
        begin("LINE", layer: layer, stroke: stroke, color: stroke.color)
        writer.tag(100, "AcDbLine")
        writer.point(p.x, p.y, 0)
        writer.point(q.x, q.y, 0, code: 11)
        extents.include(p.x, p.y)
        extents.include(q.x, q.y)
    }

    // MARK: polylines and fills

    /// The usable vertices: all converted, consecutive duplicates dropped, and for closed shapes a repeated
    /// first point at the end dropped. nil when any vertex is not a number.
    private func vertices(_ points: [Point2], closed: Bool) -> [(x: Double, y: Double)]? {
        var result: [(x: Double, y: Double)] = []
        result.reserveCapacity(points.count)
        let tolerance = minimumLength * unitsPerMetre
        func same(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Bool {
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        }
        for point in points {
            guard let c = convert(point) else { return nil }
            if let last = result.last, same(last, c) { continue }
            result.append(c)
        }
        if closed, result.count > 1, let first = result.first, let last = result.last, same(first, last) {
            result.removeLast()
        }
        return result
    }

    private mutating func addPolyline(_ points: [Point2], closed: Bool, stroke: StrokeStyle?, fill: DrawColor?,
                                      layer: PlanLayer) {
        guard let verts = vertices(points, closed: closed) else { return }

        // The fill goes first so the outline is drawn on top of it. An open shape is filled as if closed.
        if let fill = fill, options.includeFills, verts.count >= 3 {
            addHatch(verts, fill: fill, layer: layer)
        }
        guard let stroke = stroke, verts.count >= 2 else { return }
        let isClosed = closed && verts.count >= 3
        begin("LWPOLYLINE", layer: layer, stroke: stroke, color: stroke.color)
        writer.tag(100, "AcDbPolyline")
        writer.tag(90, verts.count)
        writer.tag(70, isClosed ? 1 : 0)
        for v in verts {
            writer.tag(10, v.x)
            writer.tag(20, v.y)
            extents.include(v.x, v.y)
        }
    }

    private mutating func addHatch(_ outline: [(x: Double, y: Double)], fill: DrawColor, layer: PlanLayer) {
        // The boundary is implicitly closed; an open shape that returns to its start must not repeat it.
        var verts = outline
        let tolerance = minimumLength * unitsPerMetre
        if let first = verts.first, let last = verts.last, verts.count > 1,
           abs(first.x - last.x) <= tolerance, abs(first.y - last.y) <= tolerance {
            verts.removeLast()
        }
        guard verts.count >= 3 else { return }
        begin("HATCH", layer: layer, stroke: nil, color: fill, explicitColor: true)
        writer.tag(100, "AcDbHatch")
        writer.point(0, 0, 0)               // elevation point
        writer.tags([(210, 0.0), (220, 0.0), (230, 1.0)])
        writer.tags([(2, "SOLID"), (70, 1), (71, 0), (91, 1)])
        writer.tags([(92, 3), (72, 0), (73, 1)])    // external polyline path, no bulges, closed
        writer.tag(93, verts.count)
        for v in verts {
            writer.tag(10, v.x)
            writer.tag(20, v.y)
            extents.include(v.x, v.y)
        }
        writer.tags([(97, 0), (75, 0), (76, 1), (98, 0)])
    }

    // MARK: ARC and CIRCLE

    private mutating func addArc(_ center: Point2, _ radius: Double, _ startAngle: Double, _ endAngle: Double,
                                 _ stroke: StrokeStyle, _ layer: PlanLayer) {
        guard let c = convert(center), let r = convertLength(radius),
              startAngle.isFinite, endAngle.isFinite else { return }
        let sweep = endAngle - startAngle
        if abs(sweep) >= 360 {
            addCircle(center, radius, stroke, layer)
            return
        }
        let start = DXFEntityWriter.normalizedDegrees(startAngle)
        let end = DXFEntityWriter.normalizedDegrees(endAngle)
        guard abs(start - end) > 1e-9 else { return }     // zero sweep
        begin("ARC", layer: layer, stroke: stroke, color: stroke.color)
        writer.tag(100, "AcDbCircle")
        writer.point(c.x, c.y, 0)
        writer.tag(40, r)
        writer.tag(100, "AcDbArc")
        writer.tag(50, start)
        writer.tag(51, end)
        extents.include(c.x - r, c.y - r)
        extents.include(c.x + r, c.y + r)
    }

    private mutating func addCircle(_ center: Point2, _ radius: Double, _ stroke: StrokeStyle, _ layer: PlanLayer) {
        guard let c = convert(center), let r = convertLength(radius) else { return }
        begin("CIRCLE", layer: layer, stroke: stroke, color: stroke.color)
        writer.tag(100, "AcDbCircle")
        writer.point(c.x, c.y, 0)
        writer.tag(40, r)
        extents.include(c.x - r, c.y - r)
        extents.include(c.x + r, c.y + r)
    }

    /// Angle in degrees folded into [0, 360).
    static func normalizedDegrees(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d >= 360 ? 0 : d
    }

    // MARK: TEXT

    /// A single-line TEXT. `at` is the baseline anchor: with `.left` the start of the baseline, with `.center`
    /// and `.right` the middle and end of it. Groups 72 (horizontal justification) and 11 (alignment point)
    /// carry the anchor; AutoCAD ignores group 10 for justified text but it must be present and equal.
    private mutating func addText(_ string: String, at: Point2, height: Double, rotation: Double,
                                  anchor: TextAnchor, color: DrawColor, bold: Bool, layer: PlanLayer) {
        let encoded = DXFFormat.text(string)
        guard !encoded.trimmingCharacters(in: .whitespaces).isEmpty,
              let p = convert(at), let h = convertLength(height), rotation.isFinite else { return }
        begin("TEXT", layer: layer, stroke: nil, color: color)
        writer.tag(100, "AcDbText")
        writer.point(p.x, p.y, 0)
        writer.tag(40, h)
        writer.tag(1, encoded)
        let angle = DXFEntityWriter.normalizedDegrees(rotation)
        if angle != 0 { writer.tag(50, angle) }
        if bold { writer.tag(7, "NF-BOLD") }
        switch anchor {
        case .left: break
        case .center: writer.tag(72, 1)
        case .right: writer.tag(72, 2)
        }
        if anchor != .left { writer.point(p.x, p.y, 0, code: 11) }
        writer.tag(100, "AcDbText")
        writer.tag(73, 0)
        extents.include(p.x, p.y)
    }
}
