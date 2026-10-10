import XCTest
@testable import NexaFixCore

/// Tests for the export orchestration: which files come out, what they are called, that the same request
/// gives the same bytes, how paper and scale are chosen, and the readiness numbers behind the banner.
final class ExportEngineTests: XCTestCase {

    // MARK: Fixtures

    /// 2026-10-09T10:00:00Z, which is 14:00 in Dubai: still 9 October.
    private let now = Date(timeIntervalSince1970: 1_791_540_000)
    private let later = Date(timeIntervalSince1970: 1_791_540_000 + 86_400 * 3)
    private let day = "2026-10-09"

    private func id(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-" + padded) ?? UUID()
    }

    private func demo() -> Property { DemoProperty.make(now: now) }

    private func small(name: String = "Hall") -> Room {
        Room.rectangle(name: name, kind: .corridor, width: 3.0, depth: 2.4, ceilingHeight: 2.6,
                       openings: [.door(wall: 0, offset: 0.4)])
    }

    private func property(floors: [Floor], name: String = "Marina Gate 2 - Unit 2304") -> Property {
        Property(id: id(1), name: name, client: "Mr. Khan", address: "Dubai Marina", reference: "NF-2026-1009-01",
                 kind: .apartment, createdAt: now, updatedAt: now, floors: floors)
    }

    private func oneRoom(name: String = "Marina Gate 2 - Unit 2304") -> Property {
        property(floors: [Floor(id: id(10), name: "Level 23", level: 23, rooms: [small()])], name: name)
    }

    private func request(_ p: Property, _ formats: Set<ExportFormat> = Set(ExportFormat.allCases),
                         usdz: [UUID: USDZSource] = [:]) -> ExportRequest {
        ExportRequest(property: p, formats: formats, usdzSources: usdz, now: now)
    }

    private func names(_ artifacts: [ExportArtifact]) -> [String] { artifacts.map(\.filename) }

    // MARK: Formats

    func testFormatCatalogue() {
        XCTAssertEqual(ExportFormat.allCases, [.planPDF, .cadDXF, .model3D, .dataJSON, .csv, .costingSpec])
        XCTAssertEqual(ExportFormat.allCases.map(\.displayName), [
            "Floor plan PDF", "CAD drawing DXF", "3D model USDZ", "Data JSON", "Spreadsheets CSV", "Costing spec"])
        XCTAssertEqual(ExportFormat.allCases.map(\.fileExtension), ["pdf", "dxf", "usdz", "json", "csv", "json"])
        XCTAssertEqual(Set(ExportFormat.allCases.map(\.id)).count, 6)
        for format in ExportFormat.allCases {
            XCTAssertFalse(format.detail.isEmpty)
            XCTAssertTrue(format.detail.hasSuffix("."), "\(format) detail reads as a sentence")
        }
        XCTAssertEqual(Set(ExportFormat.allCases.map(\.detail)).count, 6)
    }

    func testContentTypeIdentifiers() {
        XCTAssertEqual(ExportFormat.planPDF.contentTypeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(ExportFormat.model3D.contentTypeIdentifier, "com.pixar.universal-scene-description-mobile")
        XCTAssertEqual(ExportFormat.dataJSON.contentTypeIdentifier, "public.json")
        XCTAssertEqual(ExportFormat.costingSpec.contentTypeIdentifier, "public.json")
        XCTAssertEqual(ExportFormat.csv.contentTypeIdentifier, "public.comma-separated-values-text")
        // DXF has no system-declared identifier: it is generic data with a .dxf extension.
        XCTAssertEqual(ExportFormat.cadDXF.contentTypeIdentifier, "public.data")
        XCTAssertEqual(ExportFormat.cadDXF.fileExtension, "dxf")
    }

    func testFormatsRoundTripThroughRawValues() {
        for format in ExportFormat.allCases {
            XCTAssertEqual(ExportFormat(rawValue: format.rawValue), format)
        }
        XCTAssertEqual(ExportFormat.allCases.map(\.rawValue),
                       ["planPDF", "cadDXF", "model3D", "dataJSON", "csv", "costingSpec"])
    }

    // MARK: Artifacts

    func testEverythingForTheDemoApartment() throws {
        let result = try ExportEngine.runDetailed(request(demo()))
        let base = "NexaFix_Marina-Gate-2-Unit-2304_\(day)_"
        XCTAssertEqual(names(result.artifacts), [
            base + "floor-plan.pdf",
            base + "plan-Level-23.dxf",
            base + "scan.json",
            base + "rooms.csv",
            base + "walls.csv",
            base + "openings.csv",
            base + "objects.csv",
            base + "custom-measurements.csv",   // the demo has a measurement taken in AR
            base + "costing-spec.json",
        ])
        XCTAssertEqual(result.artifacts.map(\.formatKind), [
            .planPDF, .cadDXF, .dataJSON, .csv, .csv, .csv, .csv, .csv, .costingSpec])
        let csv = "public.comma-separated-values-text"
        XCTAssertEqual(result.artifacts.map(\.contentTypeIdentifier), [
            "com.adobe.pdf", "public.data", "public.json", csv, csv, csv, csv, csv, "public.json"])
        XCTAssertTrue(result.artifacts.allSatisfy { !$0.data.isEmpty })
        XCTAssertEqual(result.notes, ["Level 23 has no 3D model. Scan the level again to create one."])
    }

    func testRunReturnsTheSameArtifactsAsRunDetailed() throws {
        let r = request(demo())
        XCTAssertEqual(try ExportEngine.run(r), try ExportEngine.runDetailed(r).artifacts)
    }

    func testOutputIsDeterministic() throws {
        let r = request(demo())
        let first = try ExportEngine.runDetailed(r)
        let second = try ExportEngine.runDetailed(r)
        XCTAssertEqual(first, second)
    }

    func testNowChangesOnlyDatesAndNames() throws {
        let p = demo()
        let a = try ExportEngine.run(ExportRequest(property: p, formats: [.dataJSON, .costingSpec], now: now))
        let b = try ExportEngine.run(ExportRequest(property: p, formats: [.dataJSON, .costingSpec], now: later))
        XCTAssertEqual(names(a), ["NexaFix_Marina-Gate-2-Unit-2304_2026-10-09_scan.json",
                                  "NexaFix_Marina-Gate-2-Unit-2304_2026-10-09_costing-spec.json"])
        XCTAssertEqual(names(b), ["NexaFix_Marina-Gate-2-Unit-2304_2026-10-12_scan.json",
                                  "NexaFix_Marina-Gate-2-Unit-2304_2026-10-12_costing-spec.json"])
        // The costing spec carries no generation time, so it is byte for byte the same.
        XCTAssertEqual(a[1].data, b[1].data)
        // The scan file records when it was generated.
        XCTAssertNotEqual(a[0].data, b[0].data)
    }

    func testFileNamesFollowTheDateInDubai() throws {
        // 22:30 UTC on the 9th is 02:30 on the 10th in Dubai.
        let lateEvening = Date(timeIntervalSince1970: 1_791_540_000 + 12.5 * 3600)
        let out = try ExportEngine.run(ExportRequest(property: oneRoom(), formats: [.dataJSON], now: lateEvening))
        XCTAssertEqual(out[0].filename, "NexaFix_Marina-Gate-2-Unit-2304_2026-10-10_scan.json")
    }

    func testOnlyTheChosenFormatsAreMadeInAFixedOrder() throws {
        let p = oneRoom()
        XCTAssertEqual(names(try ExportEngine.run(request(p, [.dataJSON]))).count, 1)
        let two = try ExportEngine.run(request(p, [.costingSpec, .planPDF]))
        XCTAssertEqual(two.map(\.formatKind), [.planPDF, .costingSpec])
        XCTAssertEqual(names(two), ["NexaFix_Marina-Gate-2-Unit-2304_\(day)_floor-plan.pdf",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_costing-spec.json"])
    }

    func testFilenamesAreSafeEverywhere() throws {
        let p = oneRoom(name: "Villa \u{201C}Al Barari\u{201D} / Plot 5: Mr. O\u{2019}Neil & Sons")
        for artifact in try ExportEngine.run(request(p)) {
            XCTAssertTrue(artifact.filename.unicodeScalars.allSatisfy {
                ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A)
                    || ($0.value >= 0x61 && $0.value <= 0x7A) || "-_.".unicodeScalars.contains($0)
            }, artifact.filename)
            XCTAssertTrue(artifact.filename.hasPrefix("NexaFix_"))
        }
    }

    func testAnEmptyNameStillGivesAUsableFilename() throws {
        let out = try ExportEngine.run(request(oneRoom(name: "   "), [.dataJSON]))
        XCTAssertEqual(out[0].filename, "NexaFix_Property_\(day)_scan.json")
    }

    // MARK: PDF

    func testPDFHasPagesForEveryFloorAndTheSchedule() throws {
        let p = demo()
        var r = request(p, [.planPDF])
        let pdf = try ExportEngine.run(r)[0].data
        XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertTrue(String(decoding: pdf.suffix(8), as: UTF8.self).contains("%%EOF"))

        let options = ExportEngine.pdfOptions(for: r)
        XCTAssertTrue(options.includeSchedule)
        XCTAssertTrue(PlanPDFRenderer.pageInfos(property: p, options: options).contains { $0.kind == .schedule })

        r.includeSchedule = false
        let without = ExportEngine.pdfOptions(for: r)
        XCTAssertFalse(without.includeSchedule)
        XCTAssertTrue(PlanPDFRenderer.pageInfos(property: p, options: without).allSatisfy { $0.kind == .plan })
        XCTAssertLessThan(try ExportEngine.run(r)[0].data.count, pdf.count)
    }

    func testPaperChoices() {
        let p = oneRoom()
        var r = request(p)
        r.paper = "a4"
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a4)
        r.paper = "A3"
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a3)
        r.paper = " a4 "
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a4)
    }

    func testAutoPaperIsA4ForASmallPlanAndA3ForABigOne() {
        // 3 m x 2.4 m fits A4 at 1:50 or better.
        var r = request(oneRoom())
        r.paper = "auto"
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a4)
        r.paper = "something odd"
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a4, "an unknown choice means auto")

        // 30 m x 14 m does not fit A4 at 1:50 (it needs 1:150).
        let big = Room.rectangle(name: "Warehouse", width: 30, depth: 14)
        var bigRequest = request(property(floors: [Floor(name: "Level 1", level: 1, rooms: [big])]))
        bigRequest.paper = "auto"
        XCTAssertEqual(ExportEngine.pdfOptions(for: bigRequest).paper, .a3)
    }

    func testAutoPaperAccountsForTheRequestedScale() {
        // The demo apartment is about 12 m wide: at a fixed 1:20 nothing fits A4, at 1:100 it does.
        var r = request(demo())
        r.paper = "auto"
        r.scale = 100
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a4)
        r.scale = 20
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).paper, .a3)
    }

    func testScaleOption() {
        var r = request(oneRoom())
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).scale, .auto)
        r.scale = 75
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).scale, .fixed(75))
        for bad in [0.0, -50.0, .nan, .infinity] {
            r.scale = bad
            XCTAssertEqual(ExportEngine.pdfOptions(for: r).scale, .auto, "scale \(bad)")
        }
    }

    func testPDFCarriesTheUnits() {
        var r = request(oneRoom())
        r.units = DisplayUnits(length: .feetAndInches, area: .squareFeet)
        XCTAssertEqual(ExportEngine.pdfOptions(for: r).units, r.units)
    }

    // MARK: DXF

    func testDXFPerFloorUsesThePDFScale() throws {
        let level1 = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small(name: "Hall")])
        let level2 = Floor(id: id(11), name: "Level 2", level: 2,
                           rooms: [Room.rectangle(name: "Loft", width: 14, depth: 9)])
        let p = property(floors: [level1, level2])
        let r = request(p, [.cadDXF])
        let out = try ExportEngine.run(r)
        XCTAssertEqual(names(out), ["NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-1.dxf",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-2.dxf"])

        // Each DXF is the drawing of its own floor at the scale the PDF uses for that page.
        let pages = PlanPDFRenderer.pageInfos(property: p, options: ExportEngine.pdfOptions(for: r)).filter { $0.kind == .plan }
        XCTAssertEqual(pages.count, 2)
        for (index, floor) in p.floors.enumerated() {
            let scale = pages[index].scale ?? 50
            let drawing = ExportEngine.cadDrawing(for: floor, in: p, scale: scale, units: r.units)
            XCTAssertEqual(out[index].data, DXFExporter.data(drawing, options: .init(units: .millimetres)),
                           "floor \(index)")
            // The plan itself is the floor's plan at the PDF's scale; the file only adds a caption under it.
            let plain = PlanDrawingBuilder.build(floor: floor, property: p,
                                                 options: PlanOptions(scale: scale, units: r.units))
            XCTAssertEqual(Array(drawing.primitives.dropLast()), plain.primitives, "floor \(index)")
        }
        XCTAssertNotEqual(pages[0].scale, pages[1].scale, "the small and the large floor are drawn at different scales")
    }

    func testDXFTextIsADXFFile() throws {
        let out = try ExportEngine.run(request(oneRoom(), [.cadDXF]))
        let text = String(decoding: out[0].data, as: UTF8.self)
        XCTAssertTrue(text.contains("AC1015"))
        XCTAssertTrue(text.contains("NF-WALLS"))
        XCTAssertTrue(text.hasSuffix("EOF\n") || text.hasSuffix("EOF\r\n"))
    }

    func testABasementIsNotMistakenForTheLevelAbove() throws {
        // "Level -1" used to be named like "Level 1" because the file name drops dashes.
        let ground = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small(name: "Hall One")])
        let basement = Floor(id: id(11), name: "Level -1", level: -1, rooms: [small(name: "Store")])
        let out = try ExportEngine.run(request(property(floors: [ground, basement]), [.cadDXF, .model3D],
                                               usdz: [id(10): .data(Data("a".utf8)), id(11): .data(Data("b".utf8))]))
        XCTAssertEqual(names(out), ["NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-1.dxf",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-minus-1.dxf",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_model-Level-1.usdz",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_model-Level-minus-1.usdz"])
    }

    func testTheMinusSignIsOnlySpelledOutInFrontOfANumber() {
        func token(_ name: String) -> String {
            ExportEngine.floorToken(Floor(id: id(10), name: name, level: 0, rooms: []))
        }
        XCTAssertEqual(token("Level -1"), "Level-minus-1")
        XCTAssertEqual(token("-2"), "minus-2")
        XCTAssertEqual(token("Basement (-1)"), "Basement-minus-1")
        XCTAssertEqual(token("Level \u{2212}3"), "Level-minus-3")
        XCTAssertEqual(token("Level 1"), "Level-1")
        XCTAssertEqual(token("Unit-2"), "Unit-2", "a dash inside a word stays a dash")
        XCTAssertEqual(token("Floors 1-3"), "Floors-1-3")
        XCTAssertEqual(token("Level - A"), "Level-A")
        XCTAssertEqual(token(""), "level")
    }

    func testTheDXFSaysWhichPropertyAndLevelItIs() throws {
        let ground = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small(name: "Hall One")])
        let basement = Floor(id: id(11), name: "Level -1", level: -1, rooms: [small(name: "Store")])
        let out = try ExportEngine.run(request(property(floors: [ground, basement]), [.cadDXF]))
        let first = String(decoding: out[0].data, as: UTF8.self)
        let second = String(decoding: out[1].data, as: UTF8.self)
        XCTAssertTrue(first.contains("Marina Gate 2 - Unit 2304 - Level 1"))
        XCTAssertTrue(second.contains("Marina Gate 2 - Unit 2304 - Level -1"))
        XCTAssertFalse(first.contains("Level -1"))
        XCTAssertFalse(second.contains("Unit 2304 - Level 1"))
    }

    func testTheDXFCaptionSitsBelowThePlanAndInsideItsExtent() {
        let floor = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small()])
        let p = property(floors: [floor])
        let plain = PlanDrawingBuilder.build(floor: floor, property: p, options: PlanOptions(scale: 50))
        let drawing = ExportEngine.cadDrawing(for: floor, in: p, scale: 50, units: .default)
        XCTAssertEqual(drawing.primitives.count, plain.primitives.count + 1)
        guard case let .text(text, at, height, _, _, _, _) = drawing.primitives.last?.primitive else {
            return XCTFail("the caption is the last thing drawn")
        }
        XCTAssertEqual(drawing.primitives.last?.layer, .notes)
        XCTAssertEqual(text, "Marina Gate 2 - Unit 2304 - Level 1")
        XCTAssertEqual(height, 0.175, accuracy: 1e-12, "3.5 mm on paper at 1:50")
        XCTAssertLessThan(at.y, plain.bounds.min.y)
        XCTAssertEqual(drawing.bounds.min.y, at.y, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(drawing.bounds.max.x, plain.bounds.max.x)
    }

    func testFloorsDoNotShareADrawing() throws {
        // Two sessions are two frames: a room of Level 2 never appears in Level 1's file.
        let level1 = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small(name: "Hall One")])
        let level2 = Floor(id: id(11), name: "Level 2", level: 2, rooms: [small(name: "Hall Two")])
        let out = try ExportEngine.run(request(property(floors: [level1, level2]), [.cadDXF]))
        let first = String(decoding: out[0].data, as: UTF8.self)
        let second = String(decoding: out[1].data, as: UTF8.self)
        XCTAssertTrue(first.contains("Hall One"))
        XCTAssertFalse(first.contains("Hall Two"))
        XCTAssertTrue(second.contains("Hall Two"))
        XCTAssertFalse(second.contains("Hall One"))
    }

    func testAFloorWithoutRoomsHasNoDXF() throws {
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [small()]),
                                  Floor(id: id(11), name: "Level 2", level: 2, rooms: [])])
        let result = try ExportEngine.runDetailed(request(p, [.cadDXF]))
        XCTAssertEqual(result.artifacts.count, 1)
        XCTAssertEqual(result.notes, ["Level 2 has no rooms, so it has no DXF drawing."])
    }

    func testFloorsWhoseNamesMatchStillGetDifferentFiles() throws {
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [small()]),
                                  Floor(id: id(11), name: "Level-1", level: 1, rooms: [small(name: "Other")])])
        let out = try ExportEngine.run(request(p, [.cadDXF]))
        XCTAssertEqual(names(out), ["NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-1.dxf",
                                    "NexaFix_Marina-Gate-2-Unit-2304_\(day)_plan-Level-1-2.dxf"])
    }

    // MARK: USDZ

    func testUSDZComesFromTheSuppliedData() throws {
        let p = oneRoom()
        let model = Data("usdz bytes".utf8)
        let out = try ExportEngine.run(request(p, [.model3D], usdz: [id(10): .data(model)]))
        XCTAssertEqual(names(out), ["NexaFix_Marina-Gate-2-Unit-2304_\(day)_model-Level-23.usdz"])
        XCTAssertEqual(out[0].data, model)
        XCTAssertEqual(out[0].formatKind, .model3D)
        XCTAssertEqual(out[0].contentTypeIdentifier, "com.pixar.universal-scene-description-mobile")
    }

    func testUSDZCanBeReadFromAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExportEngineTests-\(UUID().uuidString).usdz")
        try Data("from disk".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let out = try ExportEngine.run(request(oneRoom(), [.model3D], usdz: [id(10): .file(url)]))
        XCTAssertEqual(out[0].data, Data("from disk".utf8))
    }

    func testUSDZIsSkippedWithANoteWhenAbsent() throws {
        let level1 = Floor(id: id(10), name: "Level 1", level: 1, rooms: [small()],
                           assets: FloorAssets(structureUSDZ: "floors/a/model.usdz"))
        let level2 = Floor(id: id(11), name: "Level 2", level: 2, rooms: [small(name: "Other")])
        let level3 = Floor(id: id(12), name: "Level 3", level: 3, rooms: [small(name: "Third")])
        let p = property(floors: [level1, level2, level3])
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).usdz")

        let result = try ExportEngine.runDetailed(request(p, [.model3D, .dataJSON], usdz: [
            id(10): .file(missing),            // saved but unreadable
            id(11): .data(Data("ok".utf8)),    // fine
            // level 3: nothing
        ]))
        XCTAssertEqual(result.artifacts.map(\.formatKind), [.model3D, .dataJSON])
        XCTAssertEqual(result.artifacts[0].filename, "NexaFix_Marina-Gate-2-Unit-2304_\(day)_model-Level-2.usdz")
        XCTAssertEqual(result.notes, ["The saved 3D model of Level 1 could not be read.",
                                      "Level 3 has no 3D model. Scan the level again to create one."])
    }

    func testEmptyUSDZDataCountsAsAbsent() throws {
        let result = try ExportEngine.runDetailed(request(oneRoom(), [.model3D, .csv], usdz: [id(10): .data(Data())]))
        XCTAssertFalse(result.artifacts.contains { $0.formatKind == .model3D })
        XCTAssertEqual(result.notes.count, 1)
    }

    func testOnlyUSDZRequestedAndNoneAvailableIsAnError() {
        XCTAssertThrowsError(try ExportEngine.run(request(oneRoom(), [.model3D]))) { error in
            XCTAssertEqual(error as? ExportError,
                           .nothingProduced(reasons: ["Level 23 has no 3D model. Scan the level again to create one."]))
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "Nothing was exported. Level 23 has no 3D model. Scan the level again to create one.")
        }
    }

    func testUSDZSourcesForOtherFloorsAreIgnored() throws {
        let result = try ExportEngine.runDetailed(request(oneRoom(), [.model3D, .dataJSON],
                                                          usdz: [id(777): .data(Data("stray".utf8))]))
        XCTAssertEqual(result.artifacts.map(\.formatKind), [.dataJSON])
    }

    // MARK: Data files

    func testScanJSONDecodesAndCarriesTheDate() throws {
        let out = try ExportEngine.run(request(demo(), [.dataJSON]))
        let file = try JSONDecoder().decode(ScanFile.self, from: out[0].data)
        XCTAssertEqual(file.schema, ScanFile.schemaName)
        XCTAssertEqual(file.generatedAt, "2026-10-09T10:00:00.000Z")
        XCTAssertEqual(file.property.name, "Marina Gate 2 - Unit 2304")
        XCTAssertEqual(file.summary.roomCount, 8)
        XCTAssertEqual(out[0].data, try ScanExport.json(property: demo(), generatedAt: now))
    }

    func testCostingSpecIsTheCostingExporterOutput() throws {
        let p = demo()
        let out = try ExportEngine.run(request(p, [.costingSpec]))
        XCTAssertEqual(out[0].data, try CostingSpecExport.json(property: p))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: out[0].data) as? [String: Any])
        XCTAssertNotNil(object["x_nexafix_scan"])
    }

    func testCSVFilesStartWithTheByteOrderMark() throws {
        let out = try ExportEngine.run(request(demo(), [.csv]))
        XCTAssertEqual(out.count, 5)
        for artifact in out {
            XCTAssertEqual(Array(artifact.data.prefix(3)), [0xEF, 0xBB, 0xBF], artifact.filename)
            XCTAssertTrue(artifact.filename.hasSuffix(".csv"))
        }
        XCTAssertEqual(out.map { String($0.filename.split(separator: "_").last ?? "") },
                       ["rooms.csv", "walls.csv", "openings.csv", "objects.csv", "custom-measurements.csv"])
    }

    func testCustomMeasurementsGetTheirOwnCSV() throws {
        var room = small()
        room.customMeasurements = [CustomMeasurement(label: "Counter run", a: Point3(0, 0, 0), b: Point3(2, 0, 0),
                                                     createdAt: now)]
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [room])])
        let out = try ExportEngine.run(request(p, [.csv]))
        XCTAssertEqual(out.count, 5)
        XCTAssertEqual(out[4].filename, "NexaFix_Marina-Gate-2-Unit-2304_\(day)_custom-measurements.csv")
    }

    func testCSVFollowsTheUnits() throws {
        let p = demo()
        let metric = try ExportEngine.run(ExportRequest(property: p, formats: [.csv], units: .default, now: now))
        let imperial = try ExportEngine.run(ExportRequest(property: p, formats: [.csv],
                                                          units: DisplayUnits(length: .feetAndInches, area: .squareFeet),
                                                          now: now))
        XCTAssertNotEqual(metric[0].data, imperial[0].data)
        XCTAssertEqual(metric.map(\.filename), imperial.map(\.filename))
    }

    // MARK: Errors

    func testNoFormatIsAnError() {
        XCTAssertThrowsError(try ExportEngine.run(request(oneRoom(), []))) { error in
            XCTAssertEqual(error as? ExportError, .noFormatSelected)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "No format is selected. Choose at least one.")
        }
    }

    func testAPropertyWithoutRoomsIsAnError() {
        for p in [property(floors: []), property(floors: [Floor(name: "Main level", level: 0)])] {
            XCTAssertThrowsError(try ExportEngine.run(request(p))) { error in
                XCTAssertEqual(error as? ExportError, .noRooms)
                XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                               "This property has no rooms yet. Scan a room, then export.")
            }
        }
    }

    func testFailureMessageNamesTheFormat() {
        let error = ExportError.failed(format: .dataJSON, reason: "disk full")
        XCTAssertEqual(error.errorDescription, "The Data JSON could not be made (disk full).")
        XCTAssertEqual(ExportError.nothingProduced(reasons: []).errorDescription,
                       "None of the chosen formats had anything to export.")
    }

    // MARK: Readiness

    /// Rectangle 6.2 x 4.5 with a door (sill on the floor) and a window (sill 0.9): 14 dimensions can be
    /// checked, 9 of them joinery-critical (4 wall lengths, the ceiling, 2 door and 2 window sizes).
    private func apartment() -> Property {
        let room = Room.rectangle(name: "Living Room", kind: .livingRoom, width: 6.2, depth: 4.5, ceilingHeight: 2.8,
                                  openings: [.door(wall: 0, offset: 0.5), .window(wall: 2, offset: 1.0, width: 3.0)])
        return property(floors: [Floor(id: id(10), name: "Level 23", level: 23, rooms: [room])])
    }

    func testReadinessCountsMatchTheChecklistAndTheScanFile() throws {
        for p in [demo(), apartment()] {
            let readiness = ExportReadiness(property: p)
            let checklist = VerificationChecklist.propertyProgress(p)
            XCTAssertEqual(readiness.verified, checklist.verified)
            XCTAssertEqual(readiness.total, checklist.total)
            let file = ScanExport.make(property: p, generatedAt: now)
            XCTAssertEqual(readiness.verified, file.summary.verifiedCount)
            XCTAssertEqual(readiness.total, file.summary.measurementCount)
            XCTAssertEqual(readiness.joineryVerified, file.summary.joineryVerifiedCount)
            XCTAssertEqual(readiness.joineryTotal, file.summary.joineryMeasurementCount)
            let joineryFromChecklist = p.allRooms.reduce(0) { $0 + VerificationChecklist(room: $1).joineryTotalCount }
            XCTAssertEqual(readiness.joineryTotal, joineryFromChecklist)
            XCTAssertEqual(readiness.unverifiedJoinery.count, readiness.joineryTotal - readiness.joineryVerified)
        }
    }

    func testReadinessNumbersForAHandBuiltApartment() {
        var p = apartment()
        var room = p.floors[0].rooms[0]
        room.walls[0].length.verify(6.24, source: .laser, date: now)
        room.ceilingHeight.verify(2.85, source: .laser, date: now)
        p.floors[0].rooms[0] = room

        let readiness = ExportReadiness(property: p)
        XCTAssertEqual(readiness.total, 14)
        XCTAssertEqual(readiness.verified, 2)
        XCTAssertEqual(readiness.laserVerified, 2)
        XCTAssertEqual(readiness.joineryTotal, 9)
        XCTAssertEqual(readiness.joineryVerified, 2)
        XCTAssertEqual(readiness.unverifiedJoinery.count, 7)
        XCTAssertTrue(readiness.hasUnverifiedJoinery)
        XCTAssertFalse(readiness.isEmpty)
        XCTAssertEqual(readiness.fraction, 2.0 / 14.0, accuracy: 1e-12)
        XCTAssertEqual(readiness.banner,
                       "2 of 14 dimensions checked with a laser. Unchecked dimensions are LiDAR estimates (typically 1-2 %).")
        XCTAssertEqual(readiness.unverifiedJoinery.map(\.label), [
            "Wall B length", "Wall C length", "Wall D length",
            "Door 1 width", "Door 1 height", "Window 1 width", "Window 1 height"])
    }

    func testUnverifiedItemsDescribeTheDimension() throws {
        let readiness = ExportReadiness(property: apartment())
        let first = try XCTUnwrap(readiness.unverifiedJoinery.first)
        XCTAssertEqual(first.label, "Wall A length")
        XCTAssertEqual(first.roomName, "Living Room")
        XCTAssertEqual(first.floorName, "Level 23")
        XCTAssertEqual(first.title, "Living Room: Wall A length")
        XCTAssertEqual(first.scannedM, 6.2, accuracy: 1e-9)
        XCTAssertEqual(first.toleranceM, 0.093, accuracy: 1e-9)
        XCTAssertEqual(Set(readiness.unverifiedJoinery.map(\.id)).count, readiness.unverifiedJoinery.count)
    }

    func testTwoMeasurementsWithTheSameLabelGetDifferentIds() {
        // Free-text labels repeat ("Measurement" is what a blank name becomes); a list needs unique ids.
        var p = apartment()
        var room = p.floors[0].rooms[0]
        for length in [1.2, 1.2, 2.4] {
            room.customMeasurements.append(CustomMeasurement(
                label: "Measurement", a: Point3(0, 0, 0), b: Point3(length, 0, 0)))
        }
        p.floors[0].rooms[0] = room
        let items = ExportReadiness(property: p).unverifiedJoinery
        XCTAssertEqual(items.filter { $0.label == "Measurement" }.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        // The ids belong to the dimensions, not to the order of the list: checking a wall keeps the others' ids.
        let before = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.label) })
        var checked = p
        checked.floors[0].rooms[0].walls[0].length.verify(6.24, source: .laser, date: now)
        for item in ExportReadiness(property: checked).unverifiedJoinery {
            XCTAssertEqual(before[item.id], item.label)
        }
    }

    func testIdsAreUniqueAcrossRoomsWithTheSameNameAndAcrossFloors() {
        let twin = small(name: "Hall")
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [twin]),
                                  Floor(id: id(11), name: "Level 1", level: 1, rooms: [small(name: "Hall")])])
        let items = ExportReadiness(property: p).unverifiedJoinery
        XCTAssertGreaterThan(items.count, 4)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    func testOnlyJoineryCriticalDimensionsAreListed() {
        let labels = ExportReadiness(property: apartment()).unverifiedJoinery.map(\.label)
        XCTAssertFalse(labels.contains { $0.contains("sill") })
        XCTAssertEqual(labels.filter { $0.hasSuffix("height") && $0.hasPrefix("Wall") }.count, 0,
                       "wall heights are worth checking but joinery is not cut from them")
        XCTAssertTrue(labels.contains("Ceiling height"))
    }

    func testBannerSaysOnSiteWhenSomeChecksWereNotLaser() {
        var p = apartment()
        p.floors[0].rooms[0].walls[0].length.verify(6.24, source: .laser, date: now)
        p.floors[0].rooms[0].walls[1].length.verify(4.51, source: .tape, date: now)
        let readiness = ExportReadiness(property: p)
        XCTAssertEqual(readiness.verified, 2)
        XCTAssertEqual(readiness.laserVerified, 1)
        XCTAssertTrue(readiness.banner.hasPrefix("2 of 14 dimensions checked on site."), readiness.banner)
    }

    func testNothingCheckedYet() {
        let readiness = ExportReadiness(property: apartment())
        XCTAssertEqual(readiness.verified, 0)
        XCTAssertEqual(readiness.banner,
                       "0 of 14 dimensions checked with a laser. Unchecked dimensions are LiDAR estimates (typically 1-2 %).")
    }

    func testEverythingCheckedHasNoUnverifiedJoinery() {
        var p = apartment()
        var room = p.floors[0].rooms[0]
        for item in VerificationChecklist(room: room).items {
            room.setVerification(Verification(value: item.measured.scanned + 0.005, source: .laser, date: now),
                                 for: item.target)
        }
        p.floors[0].rooms[0] = room
        let readiness = ExportReadiness(property: p)
        XCTAssertEqual(readiness.verified, readiness.total)
        XCTAssertEqual(readiness.total, 14)
        XCTAssertFalse(readiness.hasUnverifiedJoinery)
        XCTAssertTrue(readiness.unverifiedJoinery.isEmpty)
        XCTAssertEqual(readiness.banner, "All 14 dimensions checked with a laser.")
        XCTAssertEqual(readiness.fraction, 1)
    }

    func testOpenPlanBoundariesAreNotJoineryCritical() {
        var room = Room.rectangle(name: "Open Plan", width: 6, depth: 4)
        room.walls[1].kind = .virtual     // an edge with no wall
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [room])])
        let readiness = ExportReadiness(property: p)
        // 4 lengths + 3 heights (no wall, no height) + ceiling = 8; joinery: 3 solid lengths + ceiling.
        XCTAssertEqual(readiness.total, 8)
        XCTAssertEqual(readiness.joineryTotal, 4)
        XCTAssertFalse(readiness.unverifiedJoinery.map(\.label).contains("Wall B length"))
        XCTAssertEqual(readiness.total, VerificationChecklist.propertyProgress(p).total)
    }

    func testReadinessOfAnEmptyProperty() {
        let readiness = ExportReadiness(property: property(floors: []))
        XCTAssertTrue(readiness.isEmpty)
        XCTAssertEqual(readiness.total, 0)
        XCTAssertEqual(readiness.fraction, 0)
        XCTAssertFalse(readiness.hasUnverifiedJoinery)
        XCTAssertEqual(readiness.banner, "There are no dimensions to check yet.")
    }

    func testSingularDimensionWording() {
        let hollow = Room(id: id(5), name: "Odd", walls: [], ceilingHeight: Measured(scanned: 2.8))
        var p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [hollow])])
        XCTAssertEqual(ExportReadiness(property: p).banner,
                       "0 of 1 dimension checked with a laser. Unchecked dimensions are LiDAR estimates (typically 1-2 %).")
        p.floors[0].rooms[0].ceilingHeight.verify(2.8, date: now)
        XCTAssertEqual(ExportReadiness(property: p).banner, "All 1 dimension checked with a laser.")
    }

    func testReadinessUsesTheKindWhenARoomHasNoName() {
        var room = small(name: "  ")
        room.kind = .corridor
        let p = property(floors: [Floor(id: id(10), name: "Level 1", level: 1, rooms: [room])])
        XCTAssertEqual(ExportReadiness(property: p).unverifiedJoinery.first?.roomName, "Corridor")
    }

    func testCheckingAValueRemovesItFromTheListAndRaisesTheCount() {
        var p = apartment()
        let before = ExportReadiness(property: p)
        let wall = p.floors[0].rooms[0].walls[0].id
        p.floors[0].rooms[0].setVerification(Verification(value: 6.21, source: .laser, date: now), for: .wallLength(wall))
        let after = ExportReadiness(property: p)
        XCTAssertEqual(after.verified, before.verified + 1)
        XCTAssertEqual(after.unverifiedJoinery.count, before.unverifiedJoinery.count - 1)
        XCTAssertFalse(after.unverifiedJoinery.contains { $0.label == "Wall A length" })
    }
}
