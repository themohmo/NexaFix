import XCTest
@testable import NexaFixCore

// Tests for the laser-verification workflow and the 3D viewer helpers:
// UnitParser, MeasureTarget, Room verification API, VerificationChecklist, AccuracyReport,
// SnapPoints, WallSolids and Polygon.triangulate.
//
// Expected numbers are worked out by hand in the comments or recomputed with different code
// than the implementation uses. Random inputs come from a seeded generator so runs are repeatable.

/// SplitMix64: tiny, seedable, identical on every platform.
private struct MeasRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func measSampleLeaf(_ rng: inout MeasRNG, _ range: ClosedRange<Double>) -> Double {
    Double.random(in: range, using: &rng)
}

final class MeasureTests: XCTestCase {

    // MARK: - UnitParser: accepted input

    private func len(_ text: String, _ unit: LengthUnit = .millimetres,
                      file: StaticString = #filePath, line: UInt = #line) -> Double? {
        UnitParser.parseLength(text, defaultUnit: unit)
    }

    private func assertLength(_ text: String, _ unit: LengthUnit, equals expected: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let got = UnitParser.parseLength(text, defaultUnit: unit) else {
            XCTFail("expected \"\(text)\" (default \(unit)) to parse as \(expected) m, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(got, expected, accuracy: 1e-9, "\"\(text)\" (default \(unit))", file: file, line: line)
    }

    func testBareNumbersUseTheDefaultUnit() {
        assertLength("3245", .millimetres, equals: 3.245)
        assertLength("324.5", .centimetres, equals: 3.245)
        assertLength("3.245", .metres, equals: 3.245)
        assertLength("127", .inches, equals: 127 * 0.0254)            // 3.2258 m
        assertLength("10", .feetAndInches, equals: 10 * 0.3048)       // a bare number is feet: 3.048 m
        assertLength("10", .inches, equals: 0.254)
        assertLength("10", .centimetres, equals: 0.1)
        assertLength("1/2", .metres, equals: 0.5)
        assertLength("1/2", .millimetres, equals: 0.0005)
        assertLength("1/2", .inches, equals: 0.0127)
        assertLength("1/2", .feetAndInches, equals: 0.1524)
    }

    func testMetricInputWithUnits() {
        assertLength("3245mm", .metres, equals: 3.245)
        assertLength("3245 mm", .inches, equals: 3.245)
        assertLength("3.245 m", .millimetres, equals: 3.245)
        assertLength("3.245m", .millimetres, equals: 3.245)
        assertLength("324.5cm", .millimetres, equals: 3.245)
        assertLength("324.5 CM", .millimetres, equals: 3.245)
        assertLength("3.245 M", .millimetres, equals: 3.245)
        assertLength("3 metres", .millimetres, equals: 3)
        assertLength("3 meters", .millimetres, equals: 3)
        assertLength("3 mtr", .millimetres, equals: 3)
        assertLength("45 millimetres", .metres, equals: 0.045)
        assertLength("45 centimeters", .metres, equals: 0.45)
        assertLength("0.5 mm", .metres, equals: 0.0005)
        assertLength(".5 m", .millimetres, equals: 0.5)
        assertLength("  3245 mm  ", .metres, equals: 3.245)
        assertLength("3 m.", .millimetres, equals: 3)                   // trailing abbreviation dot
    }

    func testCommaIsAlwaysTheDecimalSeparator() {
        assertLength("3,245", .metres, equals: 3.245)
        assertLength("3,245 m", .millimetres, equals: 3.245)
        assertLength("324,5 cm", .metres, equals: 3.245)
        // Documented sharp edge: in a millimetre field "3,245" is 3.245 mm, not 3245 mm.
        assertLength("3,245", .millimetres, equals: 0.003245)
        XCTAssertLessThan(UnitParser.parseLength("3,245", defaultUnit: .millimetres)!,
                          UnitParser.suspiciouslySmallMetres)
        // Two separators are ambiguous and are refused rather than guessed.
        XCTAssertNil(len("3,245.5"))
        XCTAssertNil(len("3.245,5"))
        XCTAssertNil(len("1,000,000"))
        XCTAssertNil(len("1.2.3"))
        XCTAssertNil(len("3,245,5 m"))
    }

    func testSpacesAreThousandsSeparators() {
        assertLength("3 245", .millimetres, equals: 3.245)
        assertLength("3 245 mm", .metres, equals: 3.245)
        assertLength("1 000", .millimetres, equals: 1.0)
        assertLength("12 345 mm", .metres, equals: 12.345)
        assertLength("123 456 mm", .metres, equals: 123.456)
        XCTAssertNil(len("12 345 678 mm"))              // groups parse (12 345.678 m) but it is over the 200 m cap
        XCTAssertNil(len("1 000 000"))                  // 1000 m
    }

    func testThousandsGroupingCornerCases() {
        assertLength("12 345 mm", .metres, equals: 12.345)
        assertLength("3 245,5 mm", .metres, equals: 3.2455)
        assertLength("3\u{00A0}245 mm", .metres, equals: 3.245)        // no-break space
        assertLength("3\u{2009}245 mm", .metres, equals: 3.245)        // thin space
        assertLength("3   245 mm", .metres, equals: 3.245)
        // A group that is not exactly three digits is not a thousands group.
        XCTAssertNil(len("3 24 mm"))
        XCTAssertNil(len("3 2450"))
        XCTAssertNil(len("1234 567"))
        XCTAssertNil(len("12 34 mm"))
        XCTAssertNil(len("10 7"))
    }

    func testImperialInput() {
        let inch = 0.0254, foot = 0.3048
        assertLength("127 in", .millimetres, equals: 127 * inch)
        assertLength("127\"", .millimetres, equals: 127 * inch)
        assertLength("127''", .millimetres, equals: 127 * inch)
        assertLength("127 inches", .millimetres, equals: 127 * inch)
        assertLength("127 inch", .millimetres, equals: 127 * inch)
        assertLength("10'", .millimetres, equals: 10 * foot)
        assertLength("10ft", .millimetres, equals: 10 * foot)
        assertLength("10 ft", .millimetres, equals: 10 * foot)
        assertLength("10 feet", .millimetres, equals: 10 * foot)
        assertLength("10 foot", .millimetres, equals: 10 * foot)
        assertLength("10 ft.", .millimetres, equals: 10 * foot)
        assertLength("7 in.", .millimetres, equals: 7 * inch)
        assertLength("10' 7\"", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10'7\"", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10 ft 7 in", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10ft7in", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10 FT 7 IN", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10 feet 7 inches", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10'7 3/4\"", .millimetres, equals: 10 * foot + 7.75 * inch)
        assertLength("10' 7 3/4\"", .millimetres, equals: 10 * foot + 7.75 * inch)
        assertLength("7 3/4\"", .millimetres, equals: 7.75 * inch)
        assertLength("3/4\"", .millimetres, equals: 0.75 * inch)
        assertLength("7-3/4\"", .millimetres, equals: 7.75 * inch)
        assertLength("10'-7\"", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10' - 7 3/4\"", .millimetres, equals: 10 * foot + 7.75 * inch)
        assertLength("10.5 ft", .millimetres, equals: 10.5 * foot)
        assertLength("10 ft 7.5 in", .millimetres, equals: 10 * foot + 7.5 * inch)
        assertLength("0' 7\"", .millimetres, equals: 7 * inch)
        assertLength("10' 0\"", .millimetres, equals: 10 * foot)
        // A bare number straight after a feet part is inches ("10' 7").
        assertLength("10' 7", .millimetres, equals: 10 * foot + 7 * inch)
        assertLength("10 ft 7", .metres, equals: 10 * foot + 7 * inch)
        assertLength("10' 7 3/4", .metres, equals: 10 * foot + 7.75 * inch)
    }

    func testPhoneKeyboardPunctuationAndVulgarFractions() {
        let inch = 0.0254, foot = 0.3048
        assertLength("10\u{2019} 7\u{201D}", .millimetres, equals: 10 * foot + 7 * inch)    // curly ' and "
        assertLength("10\u{2032}7\u{2033}", .millimetres, equals: 10 * foot + 7 * inch)     // primes
        assertLength("10\u{2018}7 3/4\u{201C}", .millimetres, equals: 10 * foot + 7.75 * inch)
        assertLength("7\u{00BD}\"", .millimetres, equals: 7.5 * inch)
        assertLength("7 \u{00BE} in", .millimetres, equals: 7.75 * inch)
        assertLength("\u{00BD}\"", .millimetres, equals: 0.5 * inch)
        assertLength("7\u{215C}\"", .millimetres, equals: 7.375 * inch)
        assertLength("10'7\u{215E}\"", .millimetres, equals: 10 * foot + 7.875 * inch)
    }

    func testArabicIndicDigits() {
        assertLength("\u{0663}\u{0662}\u{0664}\u{0665}", .millimetres, equals: 3.245)                  // 3245
        assertLength("\u{0663}\u{066B}\u{0662}\u{0664}\u{0665} m", .millimetres, equals: 3.245)        // 3.245 m
        assertLength("\u{06F3}\u{06F2}\u{06F4}\u{06F5} mm", .metres, equals: 3.245)                    // extended digits
    }

    func testCompoundLengths() {
        assertLength("3 m 24 cm 5 mm", .millimetres, equals: 3.245)
        assertLength("3m 20cm", .millimetres, equals: 3.2)
        assertLength("2 m 5 cm", .millimetres, equals: 2.05)
        assertLength("3 m 245 mm", .millimetres, equals: 3.245)
        assertLength("1 m 50 cm 5 mm", .millimetres, equals: 1.505)
        assertLength("24 cm 5 mm", .millimetres, equals: 0.245)
        // Mixed systems, repeated or ascending units, and unitless tails after metric parts are refused.
        XCTAssertNil(len("3m 2cm 4in"))
        XCTAssertNil(len("3 m 2 m"))
        XCTAssertNil(len("3 mm 2 cm"))
        XCTAssertNil(len("7 in 2 ft"))
        XCTAssertNil(len("10 ft 7 in 3 mm"))
        XCTAssertNil(len("3 m 245"))
        XCTAssertNil(len("3 ft 2 cm"))
        XCTAssertNil(len("10 ft 7 in 2 in"))
        XCTAssertNil(len("1 m 2 cm 3 cm"))
        XCTAssertNil(len("1 ft 2 3"))
    }

    func testLimits() {
        assertLength("200 m", .millimetres, equals: 200)
        assertLength("200000", .millimetres, equals: 200)
        assertLength("199.999 m", .millimetres, equals: 199.999)
        XCTAssertNil(len("200.001 m"))
        XCTAssertNil(len("200001"))
        XCTAssertNil(len("1000 m"))
        XCTAssertNil(len("700 ft"))                                       // 213 m
        XCTAssertNil(len("99999999999999999999999999 mm"))
        XCTAssertNil(len(String(repeating: "9", count: 400)))             // over-long input
        XCTAssertNil(len("1" + String(repeating: "0", count: 120) + " mm"))
        assertLength("0.0001", .metres, equals: 0.0001)                   // tiny but positive is legal
    }

    // MARK: - UnitParser: rejected input

    func testRejectsEmptyZeroAndNegative() {
        for unit in LengthUnit.allCases {
            for text in ["", " ", "   \t ", "0", "0.0", "0 mm", "0,0", "0'", "0\"", "0' 0\"", "0 ft 0 in", "0/5",
                         "-5", "-5 mm", "- 5", "-0", "-0.5 m", "+5", "+5 mm", "--5"] {
                XCTAssertNil(UnitParser.parseLength(text, defaultUnit: unit), "\"\(text)\" with \(unit)")
            }
        }
    }

    func testRejectsGarbageAndUnitlessText() {
        let garbage = ["abc", "mm", "m", "in", "ft", "'", "\"", "''", "3 xyz", "3 meters long", "mm 3",
                       "3 m m", "3 mm mm", "three", "1e3", "1E3 mm", "2e-2", "inf", "-inf", "nan", "NaN",
                       "infinity", "\u{221E}", "3 \u{00B0}", "3 #", "3;4", "3/4/5", "3 / 4", "3 4 5",
                       "10 7", "3-4", "3 - 4", "3--4", "10'-", "10' -", "-", ".", ",", "3.", "3,", "5.m",
                       "1/0", "1/2/3", "3/", "/2", "1.5/2", "7 3/4/5", "7 3/0\"", "7 1/ 2", "7 -3/4 5",
                       "3m-2cm", "3 ,5", "3 .5 m", "0x10", "3\u{0301}", "$100", "3 m\u{20AC}",
                       "10 ft 7 in.5", "(3 m)", "3 m, 20 cm", "3 mm + 2 mm"]
        for text in garbage {
            for unit in LengthUnit.allCases {
                XCTAssertNil(UnitParser.parseLength(text, defaultUnit: unit), "\"\(text)\" with \(unit)")
            }
        }
    }

    func testAllowZeroOverload() {
        XCTAssertEqual(UnitParser.parseLength("0", defaultUnit: .millimetres, allowZero: true), 0)
        XCTAssertEqual(UnitParser.parseLength("0 mm", defaultUnit: .metres, allowZero: true), 0)
        XCTAssertEqual(UnitParser.parseLength("0' 0\"", defaultUnit: .metres, allowZero: true), 0)
        XCTAssertEqual(UnitParser.parseLength("0.0 m", defaultUnit: .metres, allowZero: true), 0)
        XCTAssertNil(UnitParser.parseLength("0", defaultUnit: .millimetres, allowZero: false))
        // Everything else is still refused.
        XCTAssertNil(UnitParser.parseLength("-0", defaultUnit: .millimetres, allowZero: true))
        XCTAssertNil(UnitParser.parseLength("-1", defaultUnit: .millimetres, allowZero: true))
        XCTAssertNil(UnitParser.parseLength("", defaultUnit: .millimetres, allowZero: true))
        XCTAssertNil(UnitParser.parseLength("abc", defaultUnit: .millimetres, allowZero: true))
        XCTAssertNil(UnitParser.parseLength("1000 m", defaultUnit: .millimetres, allowZero: true))
        XCTAssertEqual(UnitParser.parseLength("12", defaultUnit: .millimetres, allowZero: true)!, 0.012, accuracy: 1e-12)
    }

    func testAngleParsing() {
        func angle(_ s: String) -> Double? { UnitParser.parseAngle(s) }
        XCTAssertEqual(angle("90")!, 90, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90,5")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5 deg")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5deg")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5 DEG.")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5\u{00B0}")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("90.5 \u{00B0}")!, 90.5, accuracy: 1e-12)
        XCTAssertEqual(angle("  90 degrees ")!, 90, accuracy: 1e-12)
        XCTAssertEqual(angle("1 degree")!, 1, accuracy: 1e-12)
        XCTAssertEqual(angle("90\u{00BA}")!, 90, accuracy: 1e-12)            // masculine ordinal sometimes typed
        XCTAssertEqual(angle("\u{0669}\u{0660}")!, 90, accuracy: 1e-12)      // Arabic-Indic digits
        XCTAssertEqual(angle("359.99")!, 359.99, accuracy: 1e-12)
        XCTAssertEqual(angle("0.5")!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(angle(".5")!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(angle("270")!, 270, accuracy: 1e-12)
        for bad in ["", " ", "0", "0.0", "-90", "-0.1", "360", "360.0", "361", "1000", "abc", "90 m", "90 deg deg",
                    "9 0", "90.", "90.5.5", "90,5,5", "nan", "inf", "1e2", "1/2", "90 xyz", "\u{00B0}", "deg",
                    "90\u{00B0}\u{00B0}", "90\"", "+90"] {
            XCTAssertNil(angle(bad), "\"\(bad)\"")
        }
    }

    // MARK: - UnitParser: round trip with UnitFormatter

    func testParseOfFormattedLengthIsWithinFormatterRounding() {
        // Half of the smallest step the formatter shows, in metres.
        func halfStep(_ unit: LengthUnit) -> Double {
            switch unit {
            case .millimetres: return 0.0005            // whole millimetres
            case .centimetres: return 0.0005            // 0.1 cm
            case .metres: return 0.0005                 // 0.001 m
            case .inches: return 0.005 * 0.0254         // 0.01 in
            case .feetAndInches: return 0.0254 / 32     // 1/16 in
            }
        }
        var rng = MeasRNG(seed: 20_261_009)
        for unit in LengthUnit.allCases {
            for _ in 0..<2000 {
                // log-uniform from 1 cm to 199 m so short and long values are both well covered
                let x = exp(measSampleLeaf(&rng, log(0.01)...log(199)))
                let text = UnitFormatter.length(x, unit: unit, precision: .precise)
                // Whatever the field's default unit, the unit written in the text wins.
                for fieldDefault in [unit, LengthUnit.millimetres, LengthUnit.feetAndInches] {
                    guard let parsed = UnitParser.parseLength(text, defaultUnit: fieldDefault) else {
                        XCTFail("\"\(text)\" (from \(x) m as \(unit)) did not parse with default \(fieldDefault)")
                        continue
                    }
                    XCTAssertEqual(parsed, x, accuracy: halfStep(unit) + 1e-9,
                                   "\"\(text)\" from \(x) m as \(unit)")
                }
            }
        }
    }

    func testRoundTripWithoutUnitSuffixUsesFieldUnit() {
        var rng = MeasRNG(seed: 77)
        for unit in [LengthUnit.millimetres, .centimetres, .metres, .inches] {
            for _ in 0..<500 {
                let x = measSampleLeaf(&rng, 0.05...150)
                let text = UnitFormatter.length(x, unit: unit, precision: .precise, includeUnit: false)
                let parsed = UnitParser.parseLength(text, defaultUnit: unit)
                XCTAssertNotNil(parsed, "\"\(text)\"")
                let half = unit == .inches ? 0.005 * 0.0254 : 0.0005
                XCTAssertEqual(parsed ?? -1, x, accuracy: half + 1e-9, "\"\(text)\" as \(unit)")
            }
        }
    }

    func testRoundTripOfExactValuesIsTight() {
        // Values that are exact in the display unit must come back to rounding noise.
        XCTAssertEqual(UnitParser.parseLength(UnitFormatter.length(3.245, unit: .millimetres), defaultUnit: .metres)!,
                       3.245, accuracy: 1e-12)
        XCTAssertEqual(UnitParser.parseLength(UnitFormatter.length(3.245, unit: .metres), defaultUnit: .metres)!,
                       3.245, accuracy: 1e-12)
        XCTAssertEqual(UnitParser.parseLength(UnitFormatter.length(3.245, unit: .centimetres), defaultUnit: .metres)!,
                       3.245, accuracy: 1e-12)
        let tenFeetSeven = 10 * 0.3048 + 7.75 * 0.0254
        let text = UnitFormatter.length(tenFeetSeven, unit: .feetAndInches)
        XCTAssertEqual(text, "10' 7 3/4\"")
        XCTAssertEqual(UnitParser.parseLength(text, defaultUnit: .feetAndInches)!, tenFeetSeven, accuracy: 1e-12)
    }

    // MARK: - MeasureTarget

    func testMeasureTargetCodableAndHashable() throws {
        let a = UUID(), b = UUID()
        let targets: [MeasureTarget] = [.wallLength(a), .wallHeight(a), .openingWidth(b), .openingHeight(b),
                                        .openingSill(b), .ceilingHeight, .customLength(a)]
        let data = try JSONEncoder().encode(targets)
        let back = try JSONDecoder().decode([MeasureTarget].self, from: data)
        XCTAssertEqual(back, targets)
        XCTAssertEqual(Set(targets).count, 7)                              // all distinct
        XCTAssertNotEqual(MeasureTarget.wallLength(a), MeasureTarget.wallHeight(a))
        XCTAssertNotEqual(MeasureTarget.wallLength(a), MeasureTarget.wallLength(b))
        XCTAssertEqual(MeasureTarget.wallLength(a).entityID, a)
        XCTAssertNil(MeasureTarget.ceilingHeight.entityID)
        // A target used as a dictionary key survives an encode/decode of the dictionary of its values.
        let dict: [MeasureTarget: Int] = [.ceilingHeight: 1, .wallLength(a): 2]
        XCTAssertEqual(dict[.wallLength(a)], 2)
    }

    // MARK: - Fixtures

    /// 5 m x 4 m room. Walls: 0 south, 1 east, 2 north, 3 west. Openings are deliberately listed
    /// out of order so the numbering has to sort them.
    private func numberedRoom() -> Room {
        Room.rectangle(name: "Living", kind: .livingRoom, width: 5, depth: 4, ceilingHeight: 2.8, openings: [
            .window(wall: 2, offset: 1.0, width: 2.0, height: 1.4, sill: 0.9),   // listed 0: becomes Window 2
            .door(wall: 1, offset: 0.3),                                          // 1: Door 2
            .window(wall: 0, offset: 2.0, width: 1.5, height: 1.2, sill: 1.0),   // 2: Window 1
            .door(wall: 0, offset: 0.5),                                          // 3: Door 1
            .door(wall: 2, offset: 4.0),                                          // 4: Door 3
        ])
    }

    // MARK: - Room verification API

    func testWallLetters() {
        XCTAssertEqual(Room.wallLetters(forIndex: 0), "A")
        XCTAssertEqual(Room.wallLetters(forIndex: 1), "B")
        XCTAssertEqual(Room.wallLetters(forIndex: 25), "Z")
        XCTAssertEqual(Room.wallLetters(forIndex: 26), "AA")
        XCTAssertEqual(Room.wallLetters(forIndex: 27), "AB")
        XCTAssertEqual(Room.wallLetters(forIndex: 51), "AZ")
        XCTAssertEqual(Room.wallLetters(forIndex: 52), "BA")
        XCTAssertEqual(Room.wallLetters(forIndex: 701), "ZZ")
        XCTAssertEqual(Room.wallLetters(forIndex: 702), "AAA")
        XCTAssertEqual(Room.wallLetters(forIndex: -1), "?")
        // Distinct for the first 2000 walls.
        XCTAssertEqual(Set((0..<2000).map { Room.wallLetters(forIndex: $0) }).count, 2000)
    }

    func testWallTitlesFollowLoopIndex() {
        let r = numberedRoom()
        XCTAssertEqual(r.walls.map { r.title(for: .wallLength($0.id)) }, ["Wall A", "Wall B", "Wall C", "Wall D"])
        XCTAssertEqual(r.title(for: .wallHeight(r.walls[2].id)), "Wall C")
        XCTAssertEqual(r.detail(for: .wallLength(r.walls[0].id)), "Length")
        XCTAssertEqual(r.detail(for: .wallHeight(r.walls[0].id)), "Height")
        XCTAssertEqual(r.fullTitle(for: .wallLength(r.walls[1].id)), "Wall B length")
        XCTAssertEqual(r.fullTitle(for: .wallHeight(r.walls[3].id)), "Wall D height")

        // 30 corners: wall index 26 is "AA".
        let ring = (0..<30).map { i -> Point2 in
            let a = Double(i) / 30 * 2 * Double.pi
            return Point2(cos(a) * 3, sin(a) * 3)
        }
        let big = Room.polygon(name: "Round", corners: ring)
        XCTAssertEqual(big.walls.count, 30)
        XCTAssertEqual(big.title(for: .wallLength(big.walls[25].id)), "Wall Z")
        XCTAssertEqual(big.title(for: .wallLength(big.walls[26].id)), "Wall AA")
        XCTAssertEqual(big.title(for: .wallLength(big.walls[29].id)), "Wall AD")
    }

    func testOpeningTitlesAreNumberedPerKindByWallThenOffset() {
        let r = numberedRoom()
        let titles = r.openings.map { r.title(for: .openingWidth($0.id)) }
        // Array order was: window(c), door(b), window(a), door(a), door(c)
        XCTAssertEqual(titles, ["Window 2", "Door 2", "Window 1", "Door 1", "Door 3"])
        XCTAssertEqual(r.detail(for: .openingWidth(r.openings[0].id)), "Width \u{00B7} Wall C")
        XCTAssertEqual(r.detail(for: .openingHeight(r.openings[3].id)), "Height \u{00B7} Wall A")
        XCTAssertEqual(r.detail(for: .openingSill(r.openings[2].id)), "Sill height \u{00B7} Wall A")
        XCTAssertEqual(r.fullTitle(for: .openingSill(r.openings[0].id)), "Window 2 sill height")
        XCTAssertEqual(r.fullTitle(for: .openingWidth(r.openings[1].id)), "Door 2 width")
        // Same title for the three quantities of one opening.
        for o in r.openings {
            XCTAssertEqual(r.title(for: .openingWidth(o.id)), r.title(for: .openingHeight(o.id)))
            XCTAssertEqual(r.title(for: .openingWidth(o.id)), r.title(for: .openingSill(o.id)))
        }
    }

    func testOpeningNumberingUsesOffsetThenArrayOrderOnTies() {
        var r = Room.rectangle(name: "R", width: 6, depth: 3)
        let wallID = r.walls[0].id
        let mk = { (offset: Double) in
            Opening(kind: .door, wallID: wallID, offsetFromWallStart: offset,
                    width: Measured(scanned: 0.9), height: Measured(scanned: 2.1))
        }
        let late = mk(4.0), early = mk(1.0), tieA = mk(2.5), tieB = mk(2.5)
        r.openings = [late, tieB, early, tieA]
        XCTAssertEqual(r.title(for: .openingWidth(early.id)), "Door 1")
        XCTAssertEqual(r.title(for: .openingWidth(tieB.id)), "Door 2")    // tie: earlier in the array first
        XCTAssertEqual(r.title(for: .openingWidth(tieA.id)), "Door 3")
        XCTAssertEqual(r.title(for: .openingWidth(late.id)), "Door 4")
    }

    func testOrphanOpeningsAreNumberedLastAndHaveNoWallInDetail() {
        var r = Room.rectangle(name: "R", width: 5, depth: 4, openings: [.door(wall: 3, offset: 1.0)])
        let orphanNil = Opening(kind: .door, wallID: nil, offsetFromWallStart: 0.1,
                                width: Measured(scanned: 0.9), height: Measured(scanned: 2.1))
        let orphanStale = Opening(kind: .door, wallID: UUID(), offsetFromWallStart: 0.2,
                                  width: Measured(scanned: 0.9), height: Measured(scanned: 2.1))
        r.openings.insert(orphanNil, at: 0)
        r.openings.append(orphanStale)
        XCTAssertEqual(r.title(for: .openingWidth(r.openings[1].id)), "Door 1")      // the one on a wall
        XCTAssertEqual(r.title(for: .openingWidth(orphanNil.id)), "Door 2")
        XCTAssertEqual(r.title(for: .openingWidth(orphanStale.id)), "Door 3")
        XCTAssertEqual(r.detail(for: .openingWidth(orphanNil.id)), "Width")
        XCTAssertEqual(r.detail(for: .openingWidth(orphanStale.id)), "Width")
        XCTAssertEqual(r.measureTargets().count, 4 * 2 + 1 + 3 * 3)
    }

    func testCeilingAndCustomTitles() {
        var r = numberedRoom()
        let custom = CustomMeasurement(label: "Wardrobe wall", a: Point3(0, 0, 0), b: Point3(3, 0, 0),
                                       note: "behind the curtain")
        let blank = CustomMeasurement(label: "  ", a: Point3(0, 0, 0), b: Point3(1, 0, 0))
        r.customMeasurements = [custom, blank]
        XCTAssertEqual(r.title(for: .ceilingHeight), "Ceiling height")
        XCTAssertNil(r.detail(for: .ceilingHeight))
        XCTAssertEqual(r.fullTitle(for: .ceilingHeight), "Ceiling height")
        XCTAssertEqual(r.title(for: .customLength(custom.id)), "Wardrobe wall")
        XCTAssertEqual(r.detail(for: .customLength(custom.id)), "behind the curtain")
        XCTAssertEqual(r.fullTitle(for: .customLength(custom.id)), "Wardrobe wall")
        XCTAssertEqual(r.title(for: .customLength(blank.id)), "Custom measurement")
        XCTAssertNil(r.detail(for: .customLength(blank.id)))
    }

    func testLabelsForMissingTargets() {
        let r = numberedRoom()
        let ghost = UUID()
        XCTAssertEqual(r.title(for: .wallLength(ghost)), "Unknown measurement")
        XCTAssertEqual(r.title(for: .openingWidth(ghost)), "Unknown measurement")
        XCTAssertEqual(r.title(for: .customLength(ghost)), "Unknown measurement")
        XCTAssertNil(r.detail(for: .wallLength(ghost)))
        XCTAssertNil(r.detail(for: .wallHeight(ghost)))
        XCTAssertNil(r.detail(for: .openingSill(ghost)))
        XCTAssertNil(r.detail(for: .customLength(ghost)))
    }

    func testVirtualWallDetail() {
        var r = Room.rectangle(name: "R", width: 5, depth: 4)
        r.walls[1].kind = .virtual
        XCTAssertEqual(r.detail(for: .wallLength(r.walls[1].id)), "Length \u{00B7} open boundary")
        XCTAssertEqual(r.detail(for: .wallLength(r.walls[0].id)), "Length")
    }

    func testMeasuredLookupForEveryTarget() {
        var r = numberedRoom()
        r.customMeasurements = [CustomMeasurement(label: "Run", a: Point3(0, 0, 0), b: Point3(2, 0, 0))]
        let wall = r.walls[2], opening = r.openings[0], custom = r.customMeasurements[0]
        XCTAssertEqual(r.measured(.wallLength(wall.id)), wall.length)
        XCTAssertEqual(r.measured(.wallLength(wall.id))!.scanned, 5, accuracy: 1e-12)   // north wall of the 5 x 4 room
        XCTAssertEqual(r.measured(.wallHeight(wall.id))!.scanned, 2.8, accuracy: 1e-12)
        XCTAssertEqual(r.measured(.openingWidth(opening.id))!.scanned, 2.0, accuracy: 1e-12)
        XCTAssertEqual(r.measured(.openingHeight(opening.id))!.scanned, 1.4, accuracy: 1e-12)
        XCTAssertEqual(r.measured(.openingSill(opening.id))!.scanned, 0.9, accuracy: 1e-12)
        XCTAssertEqual(r.measured(.ceilingHeight)!.scanned, 2.8, accuracy: 1e-12)
        XCTAssertEqual(r.measured(.customLength(custom.id))!.scanned, 2, accuracy: 1e-12)
        XCTAssertNil(r.measured(.wallLength(UUID())))
        XCTAssertNil(r.measured(.openingSill(UUID())))
        XCTAssertNil(r.measured(.customLength(UUID())))
        // An id of the wrong kind of thing is not found either.
        XCTAssertNil(r.measured(.wallLength(opening.id)))
        XCTAssertNil(r.measured(.openingWidth(wall.id)))
        XCTAssertEqual(r.measureTargets().count, 4 * 2 + 1 + 5 * 3 + 1)
        XCTAssertTrue(r.measureTargets().allSatisfy { r.measured($0) != nil })
        XCTAssertEqual(Set(r.measureTargets()).count, r.measureTargets().count)
    }

    func testSetVerificationReachesEveryTarget() {
        var r = numberedRoom()
        r.customMeasurements = [CustomMeasurement(label: "Run", a: Point3(0, 0, 0), b: Point3(2, 0, 0))]
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        for target in r.measureTargets() {
            let scanned = r.measured(target)!.scanned
            let v = Verification(value: scanned + 0.011, source: .laser, date: when, note: "n")
            XCTAssertTrue(r.setVerification(v, for: target), "\(target)")
            let m = r.measured(target)!
            XCTAssertEqual(m.verification, v, "\(target)")
            XCTAssertEqual(m.scanned, scanned)                    // the scan never changes
            XCTAssertEqual(m.value, scanned + 0.011, accuracy: 1e-12)
        }
        // Clearing with nil.
        for target in r.measureTargets() {
            XCTAssertTrue(r.setVerification(nil, for: target))
            XCTAssertFalse(r.measured(target)!.isVerified, "\(target)")
        }
    }

    func testSetVerificationTouchesOnlyItsOwnTarget() {
        var r = numberedRoom()
        let before = r
        let target = MeasureTarget.openingWidth(r.openings[2].id)
        XCTAssertTrue(r.setVerification(Verification(value: 1.52), for: target))
        for other in r.measureTargets() where other != target {
            XCTAssertEqual(r.measured(other), before.measured(other), "\(other)")
        }
        XCTAssertEqual(r.measured(target)!.value, 1.52, accuracy: 1e-12)
    }

    func testSetVerificationRejectsMissingTargetsAndBadValues() {
        var r = numberedRoom()
        let snapshot = r
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .wallLength(UUID())))
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .wallHeight(UUID())))
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .openingWidth(UUID())))
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .openingHeight(UUID())))
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .openingSill(UUID())))
        XCTAssertFalse(r.setVerification(Verification(value: 1), for: .customLength(UUID())))
        XCTAssertFalse(r.setVerification(nil, for: .wallLength(UUID())))
        // Values that must never be stored.
        let wall = MeasureTarget.wallLength(r.walls[0].id)
        for bad in [Double.nan, .infinity, -.infinity, -0.001, -5, 0] {
            XCTAssertFalse(r.setVerification(Verification(value: bad), for: wall), "\(bad)")
            XCTAssertFalse(r.setVerification(Verification(value: bad), for: .ceilingHeight), "\(bad)")
        }
        XCTAssertEqual(r, snapshot)                                // nothing changed
        // A sill of exactly zero is legitimate; a negative or NaN one is not.
        let sill = MeasureTarget.openingSill(r.openings[1].id)    // a door
        XCTAssertTrue(r.setVerification(Verification(value: 0), for: sill))
        XCTAssertTrue(r.measured(sill)!.isVerified)
        XCTAssertFalse(r.setVerification(Verification(value: -0.01), for: sill))
        XCTAssertFalse(r.setVerification(Verification(value: .nan), for: sill))
        XCTAssertEqual(r.measured(sill)!.value, 0)
    }

    func testVerificationNeverModifiesGeometry() {
        var r = numberedRoom()
        let wallsBefore = r.walls.map { ($0.start, $0.end, $0.length.scanned, $0.height.scanned) }
        let openingsBefore = r.openings.map { ($0.offsetFromWallStart, $0.width.scanned, $0.height.scanned,
                                                $0.sillHeight.scanned, $0.wallID) }
        let outlineBefore = r.outline
        let areaBefore = r.metrics.floorArea
        let snapBefore = r.snapPoints()
        let piecesBefore = r.wallPieces()

        for target in r.measureTargets() {
            let scanned = r.measured(target)!.scanned
            XCTAssertTrue(r.setVerification(Verification(value: scanned * 1.05 + 0.02), for: target))
        }
        XCTAssertEqual(r.outline, outlineBefore)
        XCTAssertEqual(r.metrics.floorArea, areaBefore, accuracy: 1e-12)
        XCTAssertEqual(r.snapPoints(), snapBefore)
        XCTAssertEqual(r.wallPieces(), piecesBefore)
        for (i, w) in r.walls.enumerated() {
            XCTAssertEqual(w.start, wallsBefore[i].0)
            XCTAssertEqual(w.end, wallsBefore[i].1)
            XCTAssertEqual(w.length.scanned, wallsBefore[i].2)
            XCTAssertEqual(w.height.scanned, wallsBefore[i].3)
        }
        for (i, o) in r.openings.enumerated() {
            XCTAssertEqual(o.offsetFromWallStart, openingsBefore[i].0)
            XCTAssertEqual(o.width.scanned, openingsBefore[i].1)
            XCTAssertEqual(o.height.scanned, openingsBefore[i].2)
            XCTAssertEqual(o.sillHeight.scanned, openingsBefore[i].3)
            XCTAssertEqual(o.wallID, openingsBefore[i].4)
        }
        // ... while the effective numbers moved: wall perimeter is the sum of 1.05 x + 0.02 per wall.
        let expectedPerimeter = (5.0 * 1.05 + 0.02) * 2 + (4.0 * 1.05 + 0.02) * 2
        XCTAssertEqual(r.metrics.perimeter, expectedPerimeter, accuracy: 1e-9)
    }

    // MARK: - Checklist

    private func checklistRoom() -> (room: Room, door: Opening, window: Opening, custom: CustomMeasurement) {
        var r = Room.rectangle(name: "Master", kind: .masterBedroom, width: 4.0, depth: 3.0, ceilingHeight: 2.8, openings: [
            .door(wall: 0, offset: 0.5),                                              // sill 0
            .window(wall: 2, offset: 1.0, width: 2.0, height: 1.4, sill: 0.9),
        ])
        let custom = CustomMeasurement(label: "Wardrobe run", a: Point3(0, 0, 0), b: Point3(2.4, 0, 0))
        r.customMeasurements = [custom]
        return (r, r.openings[0], r.openings[1], custom)
    }

    func testChecklistContentAndOrder() {
        let (r, door, window, custom) = checklistRoom()
        let list = VerificationChecklist(room: r)
        // 4 wall lengths + 4 wall heights + ceiling + door w,h (sill on the floor is skipped)
        // + window w,h,sill + 1 custom = 15.
        XCTAssertEqual(list.totalCount, 15)
        XCTAssertEqual(list.items.map(\.target), [
            .wallLength(r.walls[0].id), .wallHeight(r.walls[0].id),
            .wallLength(r.walls[1].id), .wallHeight(r.walls[1].id),
            .wallLength(r.walls[2].id), .wallHeight(r.walls[2].id),
            .wallLength(r.walls[3].id), .wallHeight(r.walls[3].id),
            .ceilingHeight,
            .openingWidth(door.id), .openingHeight(door.id),
            .openingWidth(window.id), .openingHeight(window.id), .openingSill(window.id),
            .customLength(custom.id),
        ])
        XCTAssertFalse(list.items.contains { $0.target == .openingSill(door.id) })
        XCTAssertEqual(list.verifiedCount, 0)
        XCTAssertEqual(list.fraction, 0)
        XCTAssertFalse(list.isComplete)
    }

    func testChecklistItemFields() {
        let (r, door, window, custom) = checklistRoom()
        let list = VerificationChecklist(room: r)
        func item(_ t: MeasureTarget) -> VerificationChecklist.Item { list.items.first { $0.target == t }! }

        let wallA = item(.wallLength(r.walls[0].id))
        XCTAssertEqual(wallA.title, "Wall A")
        XCTAssertEqual(wallA.detail, "Length")
        XCTAssertEqual(wallA.fullTitle, "Wall A length")
        XCTAssertEqual(wallA.group, .structure)
        XCTAssertEqual(wallA.importance, .joinery)
        XCTAssertEqual(wallA.measured.scanned, 4.0, accuracy: 1e-12)
        XCTAssertEqual(wallA.id, wallA.target)
        // 1.5 % of 4 m = 0.06 m, above the 10 mm floor.
        XCTAssertEqual(wallA.typicalTolerance, 0.06, accuracy: 1e-12)

        XCTAssertEqual(item(.wallHeight(r.walls[0].id)).importance, .normal)
        XCTAssertEqual(item(.wallHeight(r.walls[0].id)).group, .structure)
        XCTAssertEqual(item(.ceilingHeight).importance, .joinery)
        XCTAssertEqual(item(.ceilingHeight).group, .structure)
        XCTAssertEqual(item(.ceilingHeight).typicalTolerance, 0.042, accuracy: 1e-12)   // 1.5 % of 2.8
        XCTAssertEqual(item(.openingWidth(door.id)).importance, .joinery)
        XCTAssertEqual(item(.openingWidth(door.id)).group, .openings)
        XCTAssertEqual(item(.openingHeight(window.id)).importance, .joinery)
        XCTAssertEqual(item(.openingSill(window.id)).importance, .normal)
        XCTAssertEqual(item(.openingSill(window.id)).title, "Window 1")
        XCTAssertEqual(item(.openingSill(window.id)).detail, "Sill height \u{00B7} Wall C")
        XCTAssertEqual(item(.openingWidth(door.id)).typicalTolerance, 0.0135, accuracy: 1e-12)   // 0.9 m -> 13.5 mm
        XCTAssertEqual(item(.openingSill(window.id)).typicalTolerance, 0.0135, accuracy: 1e-12)  // 0.9 m
        XCTAssertEqual(item(.customLength(custom.id)).importance, .joinery)
        XCTAssertEqual(item(.customLength(custom.id)).group, .custom)
        XCTAssertEqual(item(.customLength(custom.id)).title, "Wardrobe run")
        XCTAssertEqual(item(.customLength(custom.id)).typicalTolerance, 0.036, accuracy: 1e-12)  // 1.5 % of 2.4
        // The 10 mm floor applies to short values.
        var tiny = r
        tiny.walls[0].length = Measured(scanned: 0.4)
        let t = VerificationChecklist(room: tiny).items[0]
        XCTAssertEqual(t.typicalTolerance, 0.010, accuracy: 1e-12)
    }

    func testChecklistToleranceUsesTheScanNotTheVerifiedValue() {
        var (r, _, _, _) = checklistRoom()
        r.setVerification(Verification(value: 5.0), for: .wallLength(r.walls[0].id))   // scan said 4.0
        let item = VerificationChecklist(room: r).items[0]
        XCTAssertEqual(item.typicalTolerance, 0.06, accuracy: 1e-12)                   // 1.5 % of 4.0, not of 5.0
        XCTAssertTrue(item.isVerified)
    }

    func testChecklistImportanceCounts() {
        let (r, _, _, _) = checklistRoom()
        let list = VerificationChecklist(room: r)
        // joinery: 4 wall lengths + ceiling + door w,h + window w,h + custom = 10
        XCTAssertEqual(list.joineryTotalCount, 10)
        XCTAssertEqual(list.joineryItems.count, 10)
        // normal: 4 wall heights + window sill = 5
        XCTAssertEqual(list.items.filter { $0.importance == .normal }.count, 5)
        XCTAssertTrue(VerificationChecklist.Importance.joinery > VerificationChecklist.Importance.normal)
        XCTAssertEqual(list.items(in: .structure).count, 9)
        XCTAssertEqual(list.items(in: .openings).count, 5)
        XCTAssertEqual(list.items(in: .custom).count, 1)
        XCTAssertEqual(list.items(in: .structure).count + list.items(in: .openings).count
                       + list.items(in: .custom).count, list.totalCount)
        for g in VerificationChecklist.Group.allCases { XCTAssertFalse(g.displayName.isEmpty) }
    }

    func testChecklistProgressFollowsVerification() {
        var (r, door, _, _) = checklistRoom()
        XCTAssertTrue(r.setVerification(Verification(value: 4.01), for: .wallLength(r.walls[0].id)))
        XCTAssertTrue(r.setVerification(Verification(value: 2.81), for: .ceilingHeight))
        XCTAssertTrue(r.setVerification(Verification(value: 0.91), for: .openingWidth(door.id)))
        let list = VerificationChecklist(room: r)
        XCTAssertEqual(list.verifiedCount, 3)
        XCTAssertEqual(list.totalCount, 15)
        XCTAssertEqual(list.fraction, 3.0 / 15.0, accuracy: 1e-12)
        XCTAssertEqual(list.joineryVerifiedCount, 3)
        XCTAssertEqual(list.joineryFraction, 3.0 / 10.0, accuracy: 1e-12)
        XCTAssertEqual(list.unverifiedItems.count, 12)
        XCTAssertEqual(list.items.filter(\.isVerified).count, 3)
        // Clearing goes back down.
        r.setVerification(nil, for: .ceilingHeight)
        XCTAssertEqual(VerificationChecklist(room: r).verifiedCount, 2)
    }

    func testChecklistCompletionAndNextToVerify() {
        var (r, _, _, _) = checklistRoom()
        var list = VerificationChecklist(room: r)
        XCTAssertEqual(list.nextToVerify?.target, .wallLength(r.walls[0].id))
        // Verify every joinery item; the next suggestion is then the first normal item.
        for item in list.joineryItems { r.setVerification(Verification(value: item.measured.scanned + 0.002), for: item.target) }
        list = VerificationChecklist(room: r)
        XCTAssertTrue(list.isJoineryComplete)
        XCTAssertEqual(list.joineryFraction, 1, accuracy: 1e-12)
        XCTAssertFalse(list.isComplete)
        XCTAssertEqual(list.nextToVerify?.target, .wallHeight(r.walls[0].id))
        for item in list.unverifiedItems { r.setVerification(Verification(value: item.measured.scanned), for: item.target) }
        list = VerificationChecklist(room: r)
        XCTAssertTrue(list.isComplete)
        XCTAssertEqual(list.fraction, 1, accuracy: 1e-12)
        XCTAssertNil(list.nextToVerify)
        XCTAssertTrue(list.unverifiedItems.isEmpty)
    }

    func testChecklistSkipsNothingToCheck() {
        var r = Room.rectangle(name: "Open", width: 5, depth: 4, openings: [.door(wall: 0, offset: 1)])
        r.walls[1].kind = .virtual
        let list = VerificationChecklist(room: r)
        // virtual wall B: length listed (normal), height not listed.
        XCTAssertTrue(list.items.contains { $0.target == .wallLength(r.walls[1].id) })
        XCTAssertFalse(list.items.contains { $0.target == .wallHeight(r.walls[1].id) })
        XCTAssertEqual(list.items.first { $0.target == .wallLength(r.walls[1].id) }?.importance, .normal)
        XCTAssertEqual(list.items.first { $0.target == .wallLength(r.walls[0].id) }?.importance, .joinery)
        // 4 lengths + 3 heights + ceiling + door w,h = 10
        XCTAssertEqual(list.totalCount, 10)
        // A door sill someone has verified is shown (and counts).
        let door = r.openings[0]
        XCTAssertTrue(r.setVerification(Verification(value: 0.015), for: .openingSill(door.id)))
        let after = VerificationChecklist(room: r)
        XCTAssertEqual(after.totalCount, 11)
        XCTAssertEqual(after.verifiedCount, 1)
        XCTAssertEqual(after.items.first { $0.target == .openingSill(door.id) }?.importance, .normal)
        // A raised "opening" (serving hatch) has a sill to check.
        var hatch = Room.rectangle(name: "Kitchen", width: 3, depth: 3)
        hatch.openings = [Opening(kind: .opening, wallID: hatch.walls[0].id, offsetFromWallStart: 1,
                                  width: Measured(scanned: 1), height: Measured(scanned: 0.6),
                                  sillHeight: Measured(scanned: 1.0))]
        XCTAssertTrue(VerificationChecklist(room: hatch).items.contains { $0.target == .openingSill(hatch.openings[0].id) })
    }

    func testEmptyishRoomChecklist() {
        let r = Room(name: "Nothing", walls: [], ceilingHeight: Measured(scanned: 2.7))
        let list = VerificationChecklist(room: r)
        XCTAssertEqual(list.totalCount, 1)                          // the ceiling is always there
        XCTAssertEqual(list.items[0].target, .ceilingHeight)
        XCTAssertFalse(list.isComplete)
        XCTAssertEqual(list.fraction, 0)
    }

    func testPropertyProgressRollUp() {
        let (a, _, _, _) = checklistRoom()                           // 15 items
        var b = Room.rectangle(name: "Bath", kind: .bathroom, width: 2, depth: 2.5)   // 4 + 4 + 1 = 9 items
        var a2 = a
        a2.setVerification(Verification(value: 4.02), for: .wallLength(a2.walls[0].id))
        a2.setVerification(Verification(value: 2.81), for: .ceilingHeight)
        b.setVerification(Verification(value: 2.0), for: .wallLength(b.walls[1].id))
        let prop = Property(name: "Marina", floors: [
            Floor(name: "L1", level: 1, rooms: [a2]),
            Floor(name: "L2", level: 2, rooms: [b, Room.rectangle(name: "Store", width: 1, depth: 1)]),   // + 9 more
        ])
        let progress = VerificationChecklist.propertyProgress(prop)
        XCTAssertEqual(progress.total, 15 + 9 + 9)
        XCTAssertEqual(progress.verified, 3)
        XCTAssertEqual(VerificationChecklist.roomsProgress([a2]).verified, 2)
        XCTAssertEqual(VerificationChecklist.roomsProgress([a2]).total, 15)
        let empty = VerificationChecklist.propertyProgress(Property(name: "Empty"))
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.verified, 0)
        let noRooms = VerificationChecklist.propertyProgress(Property(name: "P", floors: [Floor(name: "G")]))
        XCTAssertEqual(noRooms.total, 0)
    }

    // MARK: - Accuracy report

    /// Five checks with hand-worked errors (metres):
    ///   Living / Wall A length   3.000 -> 3.030   +0.030
    ///   Living / Wall B length   4.000 -> 3.990   -0.010
    ///   Living / Ceiling height  2.800 -> 2.810   +0.010
    ///   Study  / Window 1 width  1.200 -> 1.206   +0.006
    ///   Study  / Door 1 height   2.100 -> 2.100    0.000
    private func accuracyProperty(source: VerificationSource = .laser) -> Property {
        var living = Room.rectangle(name: "Living", width: 3.0, depth: 4.0)
        var study = Room.rectangle(name: "Study", width: 5, depth: 5, openings: [
            .window(wall: 0, offset: 0.5, width: 1.2, height: 1.4, sill: 0.9),
            .door(wall: 1, offset: 0.3),
        ])
        func v(_ x: Double) -> Verification { Verification(value: x, source: source) }
        living.setVerification(v(3.030), for: .wallLength(living.walls[0].id))
        living.setVerification(v(3.990), for: .wallLength(living.walls[1].id))
        living.setVerification(v(2.810), for: .ceilingHeight)
        study.setVerification(v(1.206), for: .openingWidth(study.openings[0].id))
        study.setVerification(v(2.100), for: .openingHeight(study.openings[1].id))
        return Property(name: "P", floors: [Floor(name: "G", rooms: [living]), Floor(name: "L1", level: 1, rooms: [study])])
    }

    func testAccuracyReportMatchesHandComputation() {
        let report = AccuracyReport(property: accuracyProperty())
        XCTAssertEqual(report.sampleCount, 5)
        // |errors| = 0.030, 0.010, 0.010, 0.006, 0.000 -> sum 0.056
        XCTAssertEqual(report.meanAbsoluteError, 0.056 / 5, accuracy: 1e-9)
        // signed (verified - scanned): +0.030 - 0.010 + 0.010 + 0.006 + 0 = +0.036
        XCTAssertEqual(report.meanSignedError, 0.036 / 5, accuracy: 1e-9)
        XCTAssertEqual(report.maxAbsoluteError, 0.030, accuracy: 1e-9)
        // nearest rank: ceil(0.9 x 5) = 5th smallest = 0.030
        XCTAssertEqual(report.p90AbsoluteError, 0.030, accuracy: 1e-9)
        // percent of the verified value, then averaged
        let p1: Double = 0.030 / 3.030, p2: Double = 0.010 / 3.990, p3: Double = 0.010 / 2.810
        let p4: Double = 0.006 / 1.206, p5: Double = 0.0 / 2.1
        let percent: Double = (p1 + p2 + p3 + p4 + p5) / 5 * 100
        XCTAssertEqual(report.meanAbsolutePercent, percent, accuracy: 1e-9)
        XCTAssertEqual(percent, 0.41882, accuracy: 1e-4)                      // sanity check on the hand number
        XCTAssertEqual(report.samples.count, 5)
    }

    func testAccuracyReportSizeBands() {
        let report = AccuracyReport(property: accuracyProperty())
        // Verified under 2 m: only the window width (1.206, error 0.006).
        XCTAssertEqual(report.shortBand.sampleCount, 1)
        XCTAssertEqual(report.shortBand.meanAbsoluteError, 0.006, accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.meanSignedError, 0.006, accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.meanAbsolutePercent, 0.006 / 1.206 * 100, accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.maxAbsoluteError, 0.006, accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.p90AbsoluteError, 0.006, accuracy: 1e-9)
        // 2 m and over: 3.030, 3.990, 2.810, 2.100 with |errors| 0.030, 0.010, 0.010, 0.000
        XCTAssertEqual(report.longBand.sampleCount, 4)
        XCTAssertEqual(report.longBand.meanAbsoluteError, 0.050 / 4, accuracy: 1e-9)
        XCTAssertEqual(report.longBand.meanSignedError, 0.030 / 4, accuracy: 1e-9)          // +.03 -.01 +.01 +0
        XCTAssertEqual(report.longBand.maxAbsoluteError, 0.030, accuracy: 1e-9)
        XCTAssertEqual(report.longBand.p90AbsoluteError, 0.030, accuracy: 1e-9)             // rank ceil(3.6) = 4
        let p1: Double = 0.030 / 3.030, p2: Double = 0.010 / 3.990, p3: Double = 0.010 / 2.810
        let longPercent: Double = (p1 + p2 + p3 + 0) / 4 * 100
        XCTAssertEqual(report.longBand.meanAbsolutePercent, longPercent, accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.sampleCount + report.longBand.sampleCount, report.sampleCount)
    }

    func testSizeBandBoundaryIsInclusiveUpwardAndUsesTheVerifiedValue() {
        var r = Room.rectangle(name: "R", width: 2.0, depth: 1.9)
        // Wall lengths: 2.0 (S), 1.9 (E), 2.0 (N), 1.9 (W).
        // Scanned 2.0 verified exactly 2.0 -> long band. Scanned 1.9 verified 1.999 -> short band.
        r.setVerification(Verification(value: 2.0), for: .wallLength(r.walls[0].id))
        r.setVerification(Verification(value: 1.999), for: .wallLength(r.walls[1].id))
        // Scanned 1.9 but verified 2.05: the verified size decides -> long band.
        r.setVerification(Verification(value: 2.05), for: .wallLength(r.walls[3].id))
        let report = AccuracyReport(rooms: [r])
        XCTAssertEqual(report.sampleCount, 3)
        XCTAssertEqual(report.shortBand.sampleCount, 1)
        XCTAssertEqual(report.longBand.sampleCount, 2)
        XCTAssertEqual(report.shortBand.meanAbsoluteError, 0.099, accuracy: 1e-9)
        XCTAssertEqual(AccuracyReport.sizeBandBoundary, 2.0)
    }

    func testEmptyAccuracyReport() {
        let none = AccuracyReport(property: Property(name: "Empty"))
        XCTAssertEqual(none.sampleCount, 0)
        XCTAssertEqual(none.summary, "No laser checks yet")
        XCTAssertEqual(none.meanAbsoluteError, 0)
        XCTAssertEqual(none.meanSignedError, 0)
        XCTAssertEqual(none.meanAbsolutePercent, 0)
        XCTAssertEqual(none.maxAbsoluteError, 0)
        XCTAssertEqual(none.p90AbsoluteError, 0)
        XCTAssertEqual(none.shortBand, AccuracyReport.Stats.empty)
        XCTAssertEqual(none.longBand, AccuracyReport.Stats.empty)
        XCTAssertTrue(none.samples.isEmpty)
        XCTAssertEqual(none.biasDescription(), "")
        // Rooms exist but nothing is verified yet.
        let unverified = Property(name: "P", floors: [Floor(name: "G", rooms: [Room.rectangle(name: "R", width: 3, depth: 3)])])
        let report = AccuracyReport(property: unverified)
        XCTAssertEqual(report.sampleCount, 0)
        XCTAssertEqual(report.summary, "No laser checks yet")
        XCTAssertEqual(AccuracyReport(rooms: []).sampleCount, 0)
    }

    func testAccuracySummaryText() {
        let report = AccuracyReport(property: accuracyProperty())
        // mean 11.2 mm -> "11 mm"; mean 0.419 % -> "0.4"; max 30 mm
        XCTAssertEqual(report.summary, "5 checks: typically 11 mm (0.4 %), worst 30 mm")
        XCTAssertEqual(report.summary(unit: .millimetres), report.summary)
        XCTAssertEqual(report.summary(unit: .metres), "5 checks: typically 0.011 m (0.4 %), worst 0.030 m")

        // Single check, singular noun.
        var r = Room.rectangle(name: "R", width: 3, depth: 4)
        r.setVerification(Verification(value: 3.030), for: .wallLength(r.walls[0].id))
        XCTAssertEqual(AccuracyReport(rooms: [r]).summary, "1 check: typically 30 mm (1.0 %), worst 30 mm")

        // Twelve checks of exactly 6 mm on 2 m values (0.3 %) and one 21 mm outlier -> the shape of the brief's example.
        var rooms: [Room] = []
        for i in 0..<12 {
            var q = Room.rectangle(name: "Q\(i)", width: 2, depth: 2)
            q.setVerification(Verification(value: i == 11 ? 2.021 : 2.006), for: .wallLength(q.walls[0].id))
            rooms.append(q)
        }
        let twelve = AccuracyReport(rooms: rooms)
        XCTAssertEqual(twelve.sampleCount, 12)
        // mean |e| = (11 x 0.006 + 0.021) / 12 = 0.087 / 12 = 7.25 mm -> "7 mm"
        XCTAssertEqual(twelve.meanAbsoluteError, 0.087 / 12, accuracy: 1e-9)
        XCTAssertEqual(twelve.summary, "12 checks: typically 7 mm (0.4 %), worst 21 mm")
    }

    func testP90UsesNearestRank() {
        func p90(of errorsMM: [Double]) -> Double {
            let samples = errorsMM.map { e in
                AccuracyReport.Sample(roomID: UUID(), roomName: "R", target: .ceilingHeight, label: "x",
                                      scanned: 3.0, verified: 3.0 + e / 1000, source: .laser, date: Date(timeIntervalSince1970: 0))
            }
            return AccuracyReport.Stats(samples: samples).p90AbsoluteError * 1000
        }
        XCTAssertEqual(p90(of: [7]), 7, accuracy: 1e-9)
        XCTAssertEqual(p90(of: [1, 2]), 2, accuracy: 1e-9)                         // ceil(1.8) = 2
        XCTAssertEqual(p90(of: Array(stride(from: 1.0, through: 10.0, by: 1.0))), 9, accuracy: 1e-9)      // ceil(9.0) = 9
        XCTAssertEqual(p90(of: Array(stride(from: 1.0, through: 11.0, by: 1.0))), 10, accuracy: 1e-9)     // ceil(9.9) = 10
        XCTAssertEqual(p90(of: Array(stride(from: 1.0, through: 20.0, by: 1.0))), 18, accuracy: 1e-9)     // 18.0
        XCTAssertEqual(p90(of: Array(stride(from: 1.0, through: 100.0, by: 1.0))), 90, accuracy: 1e-9)
        XCTAssertEqual(p90(of: Array(stride(from: 1.0, through: 101.0, by: 1.0))), 91, accuracy: 1e-9)    // ceil(90.9)
        // Order of input does not matter and the sign of the error does not either.
        XCTAssertEqual(p90(of: [10, -3, 9, -8, 1, 2, -7, 4, 5, 6]), 9, accuracy: 1e-9)   // |.| sorted 1,2,3,4,5,6,7,8,9,10
    }

    func testBiasSignAndDescription() {
        // Scan under-reads: verified is larger -> positive bias, "short".
        var r = Room.rectangle(name: "R", width: 3, depth: 4)
        r.setVerification(Verification(value: 3.004), for: .wallLength(r.walls[0].id))
        r.setVerification(Verification(value: 4.006), for: .wallLength(r.walls[1].id))
        let short = AccuracyReport(rooms: [r])
        XCTAssertEqual(short.meanSignedError, 0.005, accuracy: 1e-9)
        XCTAssertEqual(short.biasDescription(), "Scans read about 5 mm short on average")
        // Scan over-reads: negative bias, "long".
        var s = Room.rectangle(name: "S", width: 3, depth: 4)
        s.setVerification(Verification(value: 2.990), for: .wallLength(s.walls[0].id))
        s.setVerification(Verification(value: 3.990), for: .wallLength(s.walls[1].id))
        let long = AccuracyReport(rooms: [s])
        XCTAssertEqual(long.meanSignedError, -0.010, accuracy: 1e-9)
        XCTAssertEqual(long.meanAbsoluteError, 0.010, accuracy: 1e-9)
        XCTAssertEqual(long.biasDescription(), "Scans read about 10 mm long on average")
        // Errors that cancel: no bias, but the absolute error shows the scatter.
        var t = Room.rectangle(name: "T", width: 3, depth: 4)
        t.setVerification(Verification(value: 3.010), for: .wallLength(t.walls[0].id))
        t.setVerification(Verification(value: 3.990), for: .wallLength(t.walls[1].id))
        let cancel = AccuracyReport(rooms: [t])
        XCTAssertEqual(cancel.meanSignedError, 0, accuracy: 1e-9)
        XCTAssertEqual(cancel.meanAbsoluteError, 0.010, accuracy: 1e-9)
        XCTAssertEqual(cancel.biasDescription(), "No consistent bias")
        // Same sign as Measured.deviation.
        XCTAssertEqual(r.measured(.wallLength(r.walls[0].id))!.deviation!, short.samples[0].error, accuracy: 1e-12)
    }

    func testZeroVerifiedValueHasNoPercentButStillCounts() {
        var r = Room.rectangle(name: "R", width: 3, depth: 4, openings: [.door(wall: 0, offset: 0.5)])
        // Door sill scanned 0, laser says 0: error 0, no percentage possible.
        r.setVerification(Verification(value: 0), for: .openingSill(r.openings[0].id))
        r.setVerification(Verification(value: 3.03), for: .wallLength(r.walls[0].id))
        let report = AccuracyReport(rooms: [r])
        XCTAssertEqual(report.sampleCount, 2)
        let sillSample = report.samples.first { $0.target == .openingSill(r.openings[0].id) }
        XCTAssertNotNil(sillSample)
        XCTAssertNil(sillSample?.absolutePercent)                                  // no percentage for a verified 0
        XCTAssertEqual(report.meanAbsolutePercent, 0.03 / 3.03 * 100, accuracy: 1e-9)   // only the wall counts
        XCTAssertEqual(report.meanAbsoluteError, 0.015, accuracy: 1e-9)            // both count here
        XCTAssertEqual(report.shortBand.sampleCount, 1)                            // verified 0 m is under 2 m
        XCTAssertEqual(report.longBand.sampleCount, 1)
        // Alone, a zero-verified sample gives a 0 % mean, not NaN.
        var only = Room.rectangle(name: "O", width: 3, depth: 4, openings: [.door(wall: 0, offset: 0.5)])
        only.setVerification(Verification(value: 0), for: .openingSill(only.openings[0].id))
        let alone = AccuracyReport(rooms: [only])
        XCTAssertEqual(alone.meanAbsolutePercent, 0)
        XCTAssertFalse(alone.meanAbsolutePercent.isNaN)
    }

    func testAccuracyReportSourceFilterAndSampleDetails() {
        var r = Room.rectangle(name: "Hall", width: 3, depth: 4)
        r.setVerification(Verification(value: 3.010, source: .laser), for: .wallLength(r.walls[0].id))
        r.setVerification(Verification(value: 3.990, source: .tape), for: .wallLength(r.walls[1].id))
        r.setVerification(Verification(value: 2.9, source: .drawing), for: .ceilingHeight)
        let all = AccuracyReport(rooms: [r])
        XCTAssertEqual(all.sampleCount, 3)
        XCTAssertEqual(AccuracyReport(rooms: [r], sources: [.laser]).sampleCount, 1)
        XCTAssertEqual(AccuracyReport(rooms: [r], sources: [.laser, .tape]).sampleCount, 2)
        XCTAssertEqual(AccuracyReport(rooms: [r], sources: []).sampleCount, 0)
        XCTAssertEqual(AccuracyReport(rooms: [r], sources: [.laser]).maxAbsoluteError, 0.010, accuracy: 1e-9)
        let s = all.samples[0]
        XCTAssertEqual(s.label, "Hall: Wall A length")
        XCTAssertEqual(s.roomName, "Hall")
        XCTAssertEqual(s.roomID, r.id)
        XCTAssertEqual(s.target, .wallLength(r.walls[0].id))
        XCTAssertEqual(s.scanned, 3.0, accuracy: 1e-12)
        XCTAssertEqual(s.verified, 3.010, accuracy: 1e-12)
        XCTAssertEqual(s.source, .laser)
        XCTAssertEqual(s.error, 0.010, accuracy: 1e-12)
        XCTAssertEqual(all.samples.map(\.source), [.laser, .tape, .drawing])
    }

    func testAccuracyReportIgnoresNonFiniteValuesAndKeepsGoing() {
        var r = Room.rectangle(name: "R", width: 3, depth: 4)
        r.walls[0].length.verification = Verification(value: .nan)                  // bypass the guarded setter
        r.walls[1].length.verification = Verification(value: .infinity)
        r.setVerification(Verification(value: 3.005), for: .wallLength(r.walls[2].id))
        let report = AccuracyReport(rooms: [r])
        XCTAssertEqual(report.sampleCount, 1)
        XCTAssertEqual(report.meanAbsoluteError, 0.005, accuracy: 1e-9)
        XCTAssertFalse(report.meanAbsolutePercent.isNaN)
    }

    func testWorstSamples() {
        let report = AccuracyReport(property: accuracyProperty())
        let worst = report.worstSamples(3)
        XCTAssertEqual(worst.map(\.absoluteError).map { ($0 * 1000).rounded() }, [30, 10, 10])
        XCTAssertEqual(worst[0].label, "Living: Wall A length")
        XCTAssertEqual(report.worstSamples(0), [])
        XCTAssertEqual(report.worstSamples(100).count, 5)
        // The two 10 mm errors come next, in whichever order floating point leaves them
        // (3.99 - 4.0 and 2.81 - 2.8 are not bit-identical), never out of descending order.
        XCTAssertEqual(Set(worst[1...].map(\.label)), ["Living: Wall B length", "Living: Ceiling height"])
        XCTAssertGreaterThanOrEqual(worst[0].absoluteError, worst[1].absoluteError)
        XCTAssertGreaterThanOrEqual(worst[1].absoluteError, worst[2].absoluteError)
    }

    func testWorstSamplesTiesKeepPropertyOrder() {
        // 2.0 -> 2.5 is an error of exactly 0.5 m in binary floating point, so these tie exactly.
        var rooms: [Room] = []
        for name in ["First", "Second", "Third"] {
            var r = Room.rectangle(name: name, width: 2, depth: 3)
            r.setVerification(Verification(value: 2.5), for: .wallLength(r.walls[0].id))
            rooms.append(r)
        }
        var small = Room.rectangle(name: "Small", width: 2, depth: 3)
        small.setVerification(Verification(value: 2.25), for: .wallLength(small.walls[0].id))
        let report = AccuracyReport(rooms: [small, rooms[0], rooms[1], rooms[2]])
        XCTAssertEqual(report.worstSamples(4).map(\.roomName), ["First", "Second", "Third", "Small"])
    }

    func testAccuracyOverManySyntheticChecks() {
        // Independent recomputation over a seeded random property: rebuild the statistics from the
        // raw (scanned, verified) pairs with plain loops.
        var rng = MeasRNG(seed: 99)
        var rooms: [Room] = []
        var pairs: [(scanned: Double, verified: Double)] = []
        for i in 0..<30 {
            var r = Room.rectangle(name: "R\(i)", width: measSampleLeaf(&rng, 1.0...8.0), depth: measSampleLeaf(&rng, 1.0...8.0))
            for wall in r.walls.prefix(Int.random(in: 1...4, using: &rng)) {
                let scanned = wall.length.scanned
                let verified = scanned + measSampleLeaf(&rng, -0.03...0.03)
                r.setVerification(Verification(value: verified), for: .wallLength(wall.id))
                pairs.append((scanned, verified))
            }
            rooms.append(r)
        }
        let report = AccuracyReport(rooms: rooms)
        XCTAssertEqual(report.sampleCount, pairs.count)
        let absErrors = pairs.map { abs($0.verified - $0.scanned) }
        XCTAssertEqual(report.meanAbsoluteError, absErrors.reduce(0, +) / Double(pairs.count), accuracy: 1e-12)
        XCTAssertEqual(report.meanSignedError, pairs.map { $0.verified - $0.scanned }.reduce(0, +) / Double(pairs.count), accuracy: 1e-12)
        XCTAssertEqual(report.maxAbsoluteError, absErrors.max()!, accuracy: 1e-12)
        let sorted = absErrors.sorted()
        let rank = Int((Double(9 * sorted.count) / 10).rounded(.up))     // ceil(0.9 n), exact for whole-number ratios
        XCTAssertEqual(report.p90AbsoluteError, sorted[rank - 1], accuracy: 1e-12)
        XCTAssertEqual(report.meanAbsolutePercent,
                       pairs.map { abs($0.verified - $0.scanned) / $0.verified * 100 }.reduce(0, +) / Double(pairs.count),
                       accuracy: 1e-9)
        XCTAssertEqual(report.shortBand.sampleCount, pairs.filter { $0.verified < 2 }.count)
        XCTAssertEqual(report.longBand.sampleCount, pairs.filter { $0.verified >= 2 }.count)
        XCTAssertLessThanOrEqual(report.p90AbsoluteError, report.maxAbsoluteError)
        XCTAssertLessThanOrEqual(report.meanAbsoluteError, report.maxAbsoluteError)
        XCTAssertGreaterThanOrEqual(report.meanAbsoluteError, abs(report.meanSignedError))
    }

    // MARK: - Snap points

    /// 5 x 4 room whose floor is 0.5 m above the session origin, with a door, a window and a cupboard.
    private func snapRoom() -> Room {
        var r = Room.rectangle(name: "Snap", width: 5, depth: 4, ceilingHeight: 2.8, openings: [
            .door(wall: 0, offset: 1.0, width: 0.9, height: 2.1),
            .window(wall: 2, offset: 1.0, width: 2.0, height: 1.4, sill: 0.9),
        ])
        r.floorElevation = 0.5
        r.objects = [RoomObject(kind: .storage, center: Point2(1, 1), yaw: 0, width: 1.0, depth: 0.6, height: 2.0)]
        return r
    }

    private func assertPoint(_ p: Point3, _ x: Double, _ y: Double, _ z: Double, _ msg: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: 1e-9, msg, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 1e-9, msg, file: file, line: line)
        XCTAssertEqual(p.z, z, accuracy: 1e-9, msg, file: file, line: line)
    }

    func testSnapPointCountsAndKinds() {
        let pts = snapRoom().snapPoints()
        XCTAssertEqual(pts.count, 4 + 4 + 4 + 8 + 8)
        func count(_ k: SnapPoint.Kind) -> Int { pts.filter { $0.kind == k }.count }
        XCTAssertEqual(count(.floorCorner), 4)
        XCTAssertEqual(count(.ceilingCorner), 4)
        XCTAssertEqual(count(.wallMidFloor), 4)
        XCTAssertEqual(count(.openingCorner), 8)
        XCTAssertEqual(count(.objectCorner), 8)
        XCTAssertEqual(Set(pts.map(\.id)).count, pts.count)                 // unique ids
        XCTAssertTrue(pts.allSatisfy { !$0.label.isEmpty })
        // fixed order: floor, ceiling, mid, opening, object
        XCTAssertEqual(pts.map(\.kind).prefix(4), [.floorCorner, .floorCorner, .floorCorner, .floorCorner])
        XCTAssertEqual(pts.last?.kind, .objectCorner)
        XCTAssertEqual(snapRoom().snapPoints().count, pts.count)
    }

    func testSnapPointIDsAreStableAcrossCalls() {
        let r = snapRoom()
        XCTAssertEqual(r.snapPoints(), r.snapPoints())
        XCTAssertEqual(r.snapPoints().map(\.id), r.snapPoints().map(\.id))
    }

    func testFloorAndCeilingCornersInWorldSpace() {
        let r = snapRoom()
        let pts = r.snapPoints()
        // Plan (x, y) -> world (x, elevation, -y); floor is 0.5 m up, ceiling 2.8 m above that.
        let floor = pts.filter { $0.kind == .floorCorner }
        assertPoint(floor[0].position, 0, 0.5, 0)
        assertPoint(floor[1].position, 5, 0.5, 0)
        assertPoint(floor[2].position, 5, 0.5, -4)
        assertPoint(floor[3].position, 0, 0.5, -4)
        let ceiling = pts.filter { $0.kind == .ceilingCorner }
        assertPoint(ceiling[0].position, 0, 3.3, 0)
        assertPoint(ceiling[1].position, 5, 3.3, 0)
        assertPoint(ceiling[2].position, 5, 3.3, -4)
        assertPoint(ceiling[3].position, 0, 3.3, -4)
        XCTAssertEqual(floor[0].label, "Floor corner A")
        XCTAssertEqual(ceiling[3].label, "Ceiling corner D")
        // They agree with Point2.world(elevation:) on the outline.
        for (i, c) in r.outline.enumerated() {
            XCTAssertEqual(floor[i].position, c.world(elevation: 0.5))
        }
    }

    func testWallMidpointsOnTheFloor() {
        let r = snapRoom()
        let mids = r.snapPoints().filter { $0.kind == .wallMidFloor }
        assertPoint(mids[0].position, 2.5, 0.5, 0)
        assertPoint(mids[1].position, 5, 0.5, -2)
        assertPoint(mids[2].position, 2.5, 0.5, -4)
        assertPoint(mids[3].position, 0, 0.5, -2)
        XCTAssertEqual(mids[0].label, "Wall A middle")
        // Open-plan boundaries have no wall to snap to.
        var open = r
        open.walls[1].kind = .virtual
        let openMids = open.snapPoints().filter { $0.kind == .wallMidFloor }
        XCTAssertEqual(openMids.count, 3)
        XCTAssertEqual(open.snapPoints().filter { $0.kind == .floorCorner }.count, 4)   // corners stay
    }

    func testOpeningCornersUseSillAndHead() {
        let r = snapRoom()
        let corners = r.snapPoints().filter { $0.kind == .openingCorner }
        // Door on the south wall, direction +x: x 1.0 ... 1.9, floor 0.5 ... head 0.5 + 2.1.
        assertPoint(corners[0].position, 1.0, 0.5, 0, corners[0].label)
        assertPoint(corners[1].position, 1.9, 0.5, 0, corners[1].label)
        assertPoint(corners[2].position, 1.9, 2.6, 0, corners[2].label)
        assertPoint(corners[3].position, 1.0, 2.6, 0, corners[3].label)
        XCTAssertEqual(corners[0].label, "Door 1 bottom near")
        XCTAssertEqual(corners[2].label, "Door 1 top far")
        // Window on the north wall (runs (5,4) -> (0,4), direction -x): offset 1 => x 4 ... 2.
        // Sill 0.9 => 0.5 + 0.9 = 1.4; head 0.9 + 1.4 above the floor => 0.5 + 2.3 = 2.8.
        assertPoint(corners[4].position, 4, 1.4, -4, corners[4].label)
        assertPoint(corners[5].position, 2, 1.4, -4, corners[5].label)
        assertPoint(corners[6].position, 2, 2.8, -4, corners[6].label)
        assertPoint(corners[7].position, 4, 2.8, -4, corners[7].label)
        XCTAssertEqual(corners[4].label, "Window 1 bottom near")
        XCTAssertEqual(corners[7].label, "Window 1 top near")
        // Every opening corner lies in the plane of its wall.
        XCTAssertTrue(corners[0...3].allSatisfy { abs($0.position.z) < 1e-9 })
    }

    func testOpeningCornersFollowTheWallNotTheAxis() {
        // A diagonal wall: opening corners must stay on the line through the wall, not on an axis.
        let r = Room.polygon(name: "Tri", corners: [Point2(0, 0), Point2(4, 0), Point2(0, 3)],
                             openings: [.window(wall: 1, offset: 1.0, width: 2.0, height: 1.0, sill: 1.0)])
        // Wall 1 runs (4,0) -> (0,3), length 5, direction (-0.8, 0.6).
        let corners = r.snapPoints().filter { $0.kind == .openingCorner }
        XCTAssertEqual(corners.count, 4)
        assertPoint(corners[0].position, 4 - 0.8, 1.0, -0.6)           // offset 1.0
        assertPoint(corners[1].position, 4 - 2.4, 1.0, -1.8)           // offset 3.0
        assertPoint(corners[2].position, 4 - 2.4, 2.0, -1.8)
        assertPoint(corners[3].position, 4 - 0.8, 2.0, -0.6)
    }

    func testObjectCornersAreFootprintBottomAndTop() {
        let r = snapRoom()
        let corners = r.snapPoints().filter { $0.kind == .objectCorner }
        XCTAssertEqual(corners.count, 8)
        // Footprint of a 1.0 x 0.6 box centred on plan (1, 1): x 0.5...1.5, y 0.7...1.3. World z = -y.
        let bottom = corners[0..<4].map(\.position)
        let top = corners[4..<8].map(\.position)
        let expectedXZ: [(Double, Double)] = [(0.5, -0.7), (1.5, -0.7), (1.5, -1.3), (0.5, -1.3)]
        for (i, e) in expectedXZ.enumerated() {
            assertPoint(bottom[i], e.0, 0.5, e.1)           // bottom face on the floor (0.5)
            assertPoint(top[i], e.0, 2.5, e.1)              // top face 2.0 m higher
        }
        XCTAssertEqual(corners[0].label, "Storage 1 bottom corner 1")
        XCTAssertEqual(corners[7].label, "Storage 1 top corner 4")
        // A raised, rotated object.
        var raised = Room.rectangle(name: "R", width: 4, depth: 4)
        raised.objects = [RoomObject(kind: .television, center: Point2(2, 2), yaw: Double.pi / 2, width: 1.0, depth: 0.2,
                                     height: 0.6, elevation: 1.0)]
        let rc = raised.snapPoints().filter { $0.kind == .objectCorner }
        XCTAssertEqual(rc.count, 8)
        // Yawed a quarter turn, the 1.0 m width runs along plan y: footprint x 1.9...2.1, y 1.5...2.5.
        XCTAssertEqual(rc.map(\.position.y).filter { abs($0 - 1.0) < 1e-9 }.count, 4)
        XCTAssertEqual(rc.map(\.position.y).filter { abs($0 - 1.6) < 1e-9 }.count, 4)
        let xs = rc.map(\.position.x), zs = rc.map(\.position.z)
        XCTAssertEqual(xs.min()!, 1.9, accuracy: 1e-9)
        XCTAssertEqual(xs.max()!, 2.1, accuracy: 1e-9)
        XCTAssertEqual(zs.min()!, -2.5, accuracy: 1e-9)
        XCTAssertEqual(zs.max()!, -1.5, accuracy: 1e-9)
    }

    func testObjectLabelsAreNumberedPerKind() {
        var r = Room.rectangle(name: "R", width: 4, depth: 4)
        r.objects = [
            RoomObject(kind: .sofa, center: Point2(1, 1), yaw: 0, width: 2, depth: 1, height: 0.8),
            RoomObject(kind: .storage, center: Point2(3, 3), yaw: 0, width: 1, depth: 1, height: 2),
            RoomObject(kind: .sofa, center: Point2(3, 1), yaw: 0, width: 2, depth: 1, height: 0.8),
        ]
        let labels = r.snapPoints().filter { $0.kind == .objectCorner }.map(\.label)
        XCTAssertTrue(labels.contains("Sofa 1 bottom corner 1"))
        XCTAssertTrue(labels.contains("Storage 1 top corner 3"))
        XCTAssertTrue(labels.contains("Sofa 2 bottom corner 4"))
    }

    func testSnapPointsSkipOrphanOpeningsAndBadNumbers() {
        var r = snapRoom()
        r.openings.append(Opening(kind: .door, wallID: nil, offsetFromWallStart: 0,
                                  width: Measured(scanned: 1), height: Measured(scanned: 2)))
        r.openings.append(Opening(kind: .window, wallID: UUID(), offsetFromWallStart: 0,
                                  width: Measured(scanned: 1), height: Measured(scanned: 2)))
        XCTAssertEqual(r.snapPoints().filter { $0.kind == .openingCorner }.count, 8)    // only the two real ones
        r.openings[0].height = Measured(scanned: .nan)
        let pts = r.snapPoints()
        XCTAssertTrue(pts.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite })
        // The door with a NaN height keeps its two bottom corners; the window keeps all four.
        XCTAssertEqual(pts.filter { $0.kind == .openingCorner }.count, 2 + 4)
    }

    func testSnapPointsOfAnLShapeAndEmptyRoom() {
        let l = Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        let pts = l.snapPoints()
        XCTAssertEqual(pts.filter { $0.kind == .floorCorner }.count, 6)
        XCTAssertEqual(pts.filter { $0.kind == .ceilingCorner }.count, 6)
        XCTAssertEqual(pts.filter { $0.kind == .wallMidFloor }.count, 6)
        XCTAssertEqual(pts.count, 18)
        let none = Room(name: "Empty", walls: [], ceilingHeight: Measured(scanned: 2.7))
        XCTAssertTrue(none.snapPoints().isEmpty)
    }

    func testNearestSnapPoint() {
        let pts = snapRoom().snapPoints()
        // Slightly off the NE ceiling corner (5, 3.3, -4): nearest is that corner, not the floor corner below it.
        let p = Point3(4.97, 3.25, -3.96)
        let hit = SnapPoint.nearest(to: p, in: pts, within: 0.1)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.kind, .ceilingCorner)
        assertPoint(hit!.position, 5, 3.3, -4)
        // Same query with too small a radius: nothing.
        XCTAssertNil(SnapPoint.nearest(to: p, in: pts, within: 0.01))
        // The distance is 3D: a point 1 m above a floor corner is not within 0.5 of it.
        XCTAssertNil(SnapPoint.nearest(to: Point3(0, 1.5, 0), in: pts.filter { $0.kind == .floorCorner }, within: 0.5))
        XCTAssertNotNil(SnapPoint.nearest(to: Point3(0, 0.8, 0), in: pts.filter { $0.kind == .floorCorner }, within: 0.5))
        // Far from everything.
        XCTAssertNil(SnapPoint.nearest(to: Point3(50, 50, 50), in: pts, within: 1.0))
        // Picks the closer of two candidates.
        let a = SnapPoint(id: "a", kind: .floorCorner, position: Point3(0, 0, 0), label: "a")
        let b = SnapPoint(id: "b", kind: .floorCorner, position: Point3(1, 0, 0), label: "b")
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.6, 0, 0), in: [a, b], within: 2)?.id, "b")
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.4, 0, 0), in: [a, b], within: 2)?.id, "a")
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.4, 0, 0), in: [b, a], within: 2)?.id, "a")
    }

    func testNearestSnapPointEdgeCases() {
        let a = SnapPoint(id: "a", kind: .floorCorner, position: Point3(0, 0, 0), label: "a")
        let b = SnapPoint(id: "b", kind: .ceilingCorner, position: Point3(1, 0, 0), label: "b")
        // Radius is inclusive.
        XCTAssertEqual(SnapPoint.nearest(to: Point3(1.5, 0, 0), in: [a, b], within: 0.5)?.id, "b")
        XCTAssertNil(SnapPoint.nearest(to: Point3(1.5001, 0, 0), in: [a, b], within: 0.5))
        // Exact tie: the earlier point wins, in either order.
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.5, 0, 0), in: [a, b], within: 1)?.id, "a")
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.5, 0, 0), in: [b, a], within: 1)?.id, "b")
        // Zero radius only matches an exact hit.
        XCTAssertEqual(SnapPoint.nearest(to: Point3(1, 0, 0), in: [a, b], within: 0)?.id, "b")
        XCTAssertNil(SnapPoint.nearest(to: Point3(1, 0.0001, 0), in: [a, b], within: 0))
        // Garbage in, nil out.
        XCTAssertNil(SnapPoint.nearest(to: Point3(0, 0, 0), in: [], within: 1))
        XCTAssertNil(SnapPoint.nearest(to: Point3(0, 0, 0), in: [a, b], within: -1))
        XCTAssertNil(SnapPoint.nearest(to: Point3(0, 0, 0), in: [a, b], within: .nan))
        XCTAssertNil(SnapPoint.nearest(to: Point3(.nan, 0, 0), in: [a, b], within: 1))
        XCTAssertNil(SnapPoint.nearest(to: Point3(0, .infinity, 0), in: [a, b], within: .infinity))
        let nanPoint = SnapPoint(id: "n", kind: .floorCorner, position: Point3(.nan, 0, 0), label: "n")
        XCTAssertEqual(SnapPoint.nearest(to: Point3(0.1, 0, 0), in: [nanPoint, a], within: 1)?.id, "a")
    }

    // MARK: - Wall solids

    private func assertPiece(_ p: WallPiece, along: ClosedRange<Double>, bottom: Double, top: Double,
                             role: WallPieceRole, opening: UUID?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.along.lowerBound, along.lowerBound, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(p.along.upperBound, along.upperBound, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(p.bottom, bottom, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(p.top, top, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(p.role, role, file: file, line: line)
        XCTAssertEqual(p.openingID, opening, file: file, line: line)
    }

    func testWallWithoutOpeningsIsOneFullPiece() {
        let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8)
        let pieces = r.wallPieces()
        XCTAssertEqual(pieces.count, 4)
        XCTAssertEqual(pieces.map(\.wallID), r.walls.map(\.id))
        assertPiece(pieces[0], along: 0...5, bottom: 0, top: 2.8, role: .full, opening: nil)
        assertPiece(pieces[1], along: 0...4, bottom: 0, top: 2.8, role: .full, opening: nil)
        XCTAssertEqual(pieces[0].area, 14, accuracy: 1e-12)
        XCTAssertEqual(pieces[0].width, 5, accuracy: 1e-12)
        XCTAssertEqual(pieces[0].height, 2.8, accuracy: 1e-12)
    }

    func testDoorCutsLintelAndSplitsWall() {
        let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                               openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1)])
        let door = r.openings[0].id
        let south = r.wallPieces(on: r.walls[0])
        XCTAssertEqual(south.count, 3)
        assertPiece(south[0], along: 0...1.0, bottom: 0, top: 2.8, role: .full, opening: nil)
        assertPiece(south[1], along: 1.0...1.9, bottom: 2.1, top: 2.8, role: .aboveOpening, opening: door)
        assertPiece(south[2], along: 1.9...5.0, bottom: 0, top: 2.8, role: .full, opening: nil)
        // hand check: 5 x 2.8 = 14 = 1x2.8 + 0.9x0.7 + 3.1x2.8 + door 0.9x2.1 -> 2.8 + 0.63 + 8.68 + 1.89 = 14.0
        XCTAssertEqual(south.reduce(0) { $0 + $1.area } + 0.9 * 2.1, 14.0, accuracy: 1e-12)
        XCTAssertEqual(r.wallPieces().count, 3 + 3)                       // the three other walls give one each
    }

    func testWindowGetsLintelAndSillPanel() {
        let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                               openings: [.window(wall: 2, offset: 1.0, width: 2.0, height: 1.4, sill: 0.9)])
        let window = r.openings[0].id
        let north = r.wallPieces(on: r.walls[2])
        XCTAssertEqual(north.count, 4)
        assertPiece(north[0], along: 0...1.0, bottom: 0, top: 2.8, role: .full, opening: nil)
        assertPiece(north[1], along: 1.0...3.0, bottom: 0, top: 0.9, role: .belowWindow, opening: window)
        assertPiece(north[2], along: 1.0...3.0, bottom: 2.3, top: 2.8, role: .aboveOpening, opening: window)
        assertPiece(north[3], along: 3.0...5.0, bottom: 0, top: 2.8, role: .full, opening: nil)
        // 1 x 2.8 + 2 x 0.9 + 2 x 0.5 + 2 x 2.8 = 2.8 + 1.8 + 1.0 + 5.6 = 11.2; window 2 x 1.4 = 2.8; total 14.
        XCTAssertEqual(north.reduce(0) { $0 + $1.area }, 11.2, accuracy: 1e-12)
    }

    func testOpeningReachingTheTopOrTheFloorLeavesNoSliver() {
        // Door exactly as tall as the wall: no lintel.
        let full = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                  openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.8)])
        let a = full.wallPieces(on: full.walls[0])
        XCTAssertEqual(a.count, 2)
        XCTAssertTrue(a.allSatisfy { $0.role == .full })
        // Window from the floor up (sill 0): no panel.
        let down = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                  openings: [.window(wall: 0, offset: 1.0, width: 2.0, height: 1.0, sill: 0)])
        XCTAssertFalse(down.wallPieces(on: down.walls[0]).contains { $0.role == .belowWindow })
        // Door a hair taller than the wall: clipped, still no lintel and no negative piece.
        let over = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                  openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 3.5)])
        XCTAssertEqual(over.wallPieces(on: over.walls[0]).count, 2)
        // Wall edge cases: opening spanning the whole wall leaves only a lintel / panel.
        let whole = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                   openings: [.window(wall: 0, offset: 0, width: 5, height: 1.0, sill: 1.0)])
        let w = whole.wallPieces(on: whole.walls[0])
        XCTAssertEqual(w.count, 2)
        assertPiece(w[0], along: 0...5, bottom: 0, top: 1.0, role: .belowWindow, opening: whole.openings[0].id)
        assertPiece(w[1], along: 0...5, bottom: 2.0, top: 2.8, role: .aboveOpening, opening: whole.openings[0].id)
        // An opening that covers the wall completely removes it.
        let gone = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                  openings: [.window(wall: 0, offset: -1, width: 8, height: 4, sill: 0)])
        XCTAssertTrue(gone.wallPieces(on: gone.walls[0]).isEmpty)
    }

    func testOpeningsAreClippedToTheirWall() {
        func pieces(offset: Double, width: Double) -> [WallPiece] {
            let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                                   openings: [.door(wall: 0, offset: offset, width: width, height: 2.1)])
            return r.wallPieces(on: r.walls[0])
        }
        // Overhangs the end of the wall: [4.5, 5].
        var p = pieces(offset: 4.5, width: 1.0)
        XCTAssertEqual(p.count, 2)
        assertPiece(p[0], along: 0...4.5, bottom: 0, top: 2.8, role: .full, opening: nil)
        XCTAssertEqual(p[1].along.upperBound, 5, accuracy: 1e-12)
        // Starts before the wall: [0, 0.8].
        p = pieces(offset: -0.2, width: 1.0)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[0].along.lowerBound, 0, accuracy: 1e-12)
        XCTAssertEqual(p[0].along.upperBound, 0.8, accuracy: 1e-12)
        XCTAssertEqual(p[0].role, .aboveOpening)
        assertPiece(p[1], along: 0.8...5, bottom: 0, top: 2.8, role: .full, opening: nil)
        // Entirely off either end, zero width, negative width, NaN: ignored.
        for (o, w) in [(5.0, 1.0), (6.0, 1.0), (-3.0, 1.0), (1.0, 0.0), (1.0, -0.9), (.nan, 1.0), (1.0, .nan), (.infinity, 1.0)] {
            let q = pieces(offset: o, width: w)
            XCTAssertEqual(q.count, 1, "offset \(o) width \(w)")
            assertPiece(q[0], along: 0...5, bottom: 0, top: 2.8, role: .full, opening: nil)
        }
    }

    func testTouchingOpeningsLeaveNoCrumb() {
        // Door [1.0, 1.9] then window [1.9, 3.5]: nothing between them.
        var r = Room.rectangle(name: "R", width: 6, depth: 4, ceilingHeight: 2.8,
                               openings: [.door(wall: 0, offset: 1.0, width: 0.9, height: 2.1),
                                          .window(wall: 0, offset: 1.9, width: 1.6, height: 1.0, sill: 1.0)])
        var south = r.wallPieces(on: r.walls[0])
        XCTAssertTrue(south.allSatisfy { $0.width > 1e-9 && $0.height > 1e-9 })
        XCTAssertEqual(south.filter { $0.role == .full }.count, 2)           // before and after only
        // Floating point noise between the edges (0.1 + 0.2 vs 0.3) must not create a sliver.
        r.openings[0].offsetFromWallStart = 0.1
        r.openings[0].width = Measured(scanned: 0.2)
        r.openings[1].offsetFromWallStart = 0.3
        south = r.wallPieces(on: r.walls[0])
        XCTAssertTrue(south.allSatisfy { $0.width > 1e-9 && $0.height > 1e-9 })
        XCTAssertEqual(south.filter { $0.role == .full }.count, 2)
    }

    func testOverlappingWindowsMergeWithoutDoubleCounting() {
        // Two identical-height windows overlapping on [2, 3].
        let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8, openings: [
            .window(wall: 0, offset: 1.0, width: 2.0, height: 1.4, sill: 0.9),   // x 1...3
            .window(wall: 0, offset: 2.0, width: 2.0, height: 1.4, sill: 0.9),   // x 2...4
        ])
        let a = r.openings[0].id, b = r.openings[1].id
        let pieces = r.wallPieces(on: r.walls[0])
        // Union of the two windows is x 1...4 (3 m) x 1.4 m = 4.2 m2; the wall is 5 x 2.8 = 14.
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.area }, 14 - 4.2, accuracy: 1e-12)
        XCTAssertEqual(pieces.count, 6)
        assertPiece(pieces[0], along: 0...1, bottom: 0, top: 2.8, role: .full, opening: nil)
        // Panels and lintels follow the opening that defines them: A until x = 3, then B.
        let below = pieces.filter { $0.role == .belowWindow }
        let above = pieces.filter { $0.role == .aboveOpening }
        XCTAssertEqual(below.count, 2)
        XCTAssertEqual(above.count, 2)
        assertPiece(below[0], along: 1...3, bottom: 0, top: 0.9, role: .belowWindow, opening: a)
        assertPiece(below[1], along: 3...4, bottom: 0, top: 0.9, role: .belowWindow, opening: b)
        assertPiece(above[0], along: 1...3, bottom: 2.3, top: 2.8, role: .aboveOpening, opening: a)
        assertPiece(above[1], along: 3...4, bottom: 2.3, top: 2.8, role: .aboveOpening, opening: b)
        assertPiece(pieces[5], along: 4...5, bottom: 0, top: 2.8, role: .full, opening: nil)
    }

    func testDoorOverlappedByWindowOfDifferentHeight() {
        // Door x 1...2, y 0...2.1. Window x 1.5...3, y 0.9...2.3. They overlap on x 1.5...2, y 0.9...2.1.
        let r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8, openings: [
            .door(wall: 0, offset: 1.0, width: 1.0, height: 2.1),
            .window(wall: 0, offset: 1.5, width: 1.5, height: 1.4, sill: 0.9),
        ])
        let pieces = r.wallPieces(on: r.walls[0])
        // union = 1 x 2.1 + 1.5 x 1.4 - 0.5 x 1.2 = 2.1 + 2.1 - 0.6 = 3.6; solid = 14 - 3.6 = 10.4
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.area }, 10.4, accuracy: 1e-12)
        // Strip 1...1.5 is the door alone (lintel 2.1...2.8); 1.5...2 has door+window merged 0...2.3
        // (lintel 2.3...2.8, defined by the window); 2...3 is the window alone (panel 0...0.9, lintel 2.3...2.8).
        let door = r.openings[0].id, window = r.openings[1].id
        let lintels = pieces.filter { $0.role == .aboveOpening }
        XCTAssertEqual(lintels.count, 2)                          // [1, 1.5] over the door, [1.5, 3] over door+window
        assertPiece(lintels[0], along: 1...1.5, bottom: 2.1, top: 2.8, role: .aboveOpening, opening: door)
        assertPiece(lintels[1], along: 1.5...3, bottom: 2.3, top: 2.8, role: .aboveOpening, opening: window)
        let panels = pieces.filter { $0.role == .belowWindow }
        XCTAssertEqual(panels.count, 1)
        assertPiece(panels[0], along: 2...3, bottom: 0, top: 0.9, role: .belowWindow, opening: window)
    }

    func testStackedOpeningsKeepTheSolidBetweenThem() {
        // A cat flap low down and a high window above it in the same strip.
        var room = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8)
        let low = Opening(kind: .opening, wallID: room.walls[0].id, offsetFromWallStart: 1, width: Measured(scanned: 1),
                          height: Measured(scanned: 1.0), sillHeight: Measured(scanned: 0))
        let high = Opening(kind: .window, wallID: room.walls[0].id, offsetFromWallStart: 1, width: Measured(scanned: 1),
                           height: Measured(scanned: 0.3), sillHeight: Measured(scanned: 1.5))
        room.openings = [low, high]
        let pieces = room.wallPieces(on: room.walls[0])
        // Strip x 1...2: solid y 1.0...1.5 (between) and 1.8...2.8 (above). Area: 0.5 + 1.0 = 1.5.
        let strip = pieces.filter { $0.along.lowerBound >= 1 - 1e-9 && $0.along.upperBound <= 2 + 1e-9 }
        XCTAssertEqual(strip.count, 2)
        assertPiece(strip[0], along: 1...2, bottom: 1.0, top: 1.5, role: .aboveOpening, opening: low.id)
        assertPiece(strip[1], along: 1...2, bottom: 1.8, top: 2.8, role: .aboveOpening, opening: high.id)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.area }, 14 - 1.0 - 0.3, accuracy: 1e-12)
    }

    func testIdenticalDuplicateOpeningsDoNotDuplicatePieces() {
        var r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                               openings: [.window(wall: 0, offset: 1, width: 2, height: 1.4, sill: 0.9)])
        var twin = r.openings[0]
        twin.id = UUID()
        r.openings.append(twin)
        let pieces = r.wallPieces(on: r.walls[0])
        XCTAssertEqual(pieces.count, 4)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.area }, 14 - 2.8, accuracy: 1e-12)
        XCTAssertTrue(pieces.filter { $0.openingID != nil }.allSatisfy { $0.openingID == r.openings[0].id })   // earliest wins
    }

    func testVirtualAndDegenerateWallsGiveNoPieces() {
        var r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                               openings: [.door(wall: 1, offset: 1.0)])
        r.walls[1].kind = .virtual
        let pieces = r.wallPieces()
        XCTAssertEqual(pieces.count, 3)
        XCTAssertFalse(pieces.contains { $0.wallID == r.walls[1].id })
        // Zero-height and zero-length walls, NaN heights.
        r.walls[0].height = Measured(scanned: 0)
        r.walls[2].height = Measured(scanned: .nan)
        r.walls[3].end = r.walls[3].start
        XCTAssertTrue(r.wallPieces().isEmpty)
        XCTAssertTrue(Room(name: "E", walls: [], ceilingHeight: Measured(scanned: 2.7)).wallPieces().isEmpty)
    }

    func testWallPiecesIgnoreVerifiedValues() {
        var r = Room.rectangle(name: "R", width: 5, depth: 4, ceilingHeight: 2.8,
                               openings: [.window(wall: 0, offset: 1, width: 2, height: 1.4, sill: 0.9)])
        let before = r.wallPieces()
        for t in r.measureTargets() { r.setVerification(Verification(value: r.measured(t)!.scanned + 0.1), for: t) }
        XCTAssertEqual(r.wallPieces(), before)
    }

    func testWallPieceOrderingIsDeterministic() {
        let r = Room.rectangle(name: "R", width: 6, depth: 4, ceilingHeight: 2.8, openings: [
            .window(wall: 0, offset: 3.5, width: 1.0, height: 1.0, sill: 1.0),
            .door(wall: 0, offset: 0.5),
        ])
        let pieces = r.wallPieces(on: r.walls[0])
        for i in 1..<pieces.count {
            let a = pieces[i - 1], b = pieces[i]
            XCTAssertTrue(a.along.lowerBound < b.along.lowerBound
                          || (a.along.lowerBound == b.along.lowerBound && a.bottom <= b.bottom))
        }
        XCTAssertEqual(r.wallPieces(), r.wallPieces())
    }

    // Random layouts: pieces + openings must account for every square centimetre of every solid wall.

    private func randomRoom(_ rng: inout MeasRNG, index: Int) -> Room {
        let shape = Int.random(in: 0...2, using: &rng)
        var room: Room
        switch shape {
        case 0:
            room = Room.rectangle(name: "R\(index)", width: measSampleLeaf(&rng, 1.5...12), depth: measSampleLeaf(&rng, 1.5...9),
                                  ceilingHeight: measSampleLeaf(&rng, 2.2...3.4))
        case 1:
            let w = measSampleLeaf(&rng, 4...10), d = measSampleLeaf(&rng, 4...9)
            let nw = measSampleLeaf(&rng, 1.0...(w - 1.5)), nd = measSampleLeaf(&rng, 1.0...(d - 1.5))
            room = Room.polygon(name: "L\(index)", corners: [Point2(0, 0), Point2(w, 0), Point2(w, nd), Point2(nw, nd),
                                                              Point2(nw, d), Point2(0, d)],
                                ceilingHeight: measSampleLeaf(&rng, 2.2...3.4))
        default:
            let n = Int.random(in: 3...9, using: &rng)
            var pts: [Point2] = []
            for i in 0..<n {
                let a = 2 * Double.pi * (Double(i) + measSampleLeaf(&rng, 0.1...0.9)) / Double(n)
                let rad = measSampleLeaf(&rng, 1.5...5)
                pts.append(Point2(cos(a) * rad, sin(a) * rad))
            }
            room = Room.polygon(name: "S\(index)", corners: pts, ceilingHeight: measSampleLeaf(&rng, 2.2...3.4))
        }
        // Walls get their own heights so heights are not all equal to the ceiling.
        for i in room.walls.indices where Bool.random(using: &rng) {
            room.walls[i].height = Measured(scanned: measSampleLeaf(&rng, 2.0...3.6))
        }
        return room
    }

    private func makeOpening(wall: Wall, x0: Double, x1: Double, sill: Double, height: Double) -> Opening {
        Opening(kind: sill < 0.05 ? .door : .window, wallID: wall.id, offsetFromWallStart: x0,
                width: Measured(scanned: x1 - x0), height: Measured(scanned: height),
                sillHeight: Measured(scanned: sill))
    }

    /// Area of the union of rectangles by coordinate compression: unrelated to the code under test.
    private func unionArea(_ rects: [(x0: Double, x1: Double, y0: Double, y1: Double)]) -> Double {
        guard !rects.isEmpty else { return 0 }
        let xs = Set(rects.flatMap { [$0.x0, $0.x1] }).sorted()
        let ys = Set(rects.flatMap { [$0.y0, $0.y1] }).sorted()
        var area = 0.0
        for i in 0..<(xs.count - 1) {
            for j in 0..<(ys.count - 1) {
                let cx = (xs[i] + xs[i + 1]) / 2, cy = (ys[j] + ys[j + 1]) / 2
                if rects.contains(where: { $0.x0 < cx && cx < $0.x1 && $0.y0 < cy && cy < $0.y1 }) {
                    area += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j])
                }
            }
        }
        return area
    }

    /// Structural checks every set of pieces must pass, plus a point-sampling check against the openings.
    private func checkPieces(_ pieces: [WallPiece], wall: Wall, rects: [(x0: Double, x1: Double, y0: Double, y1: Double)],
                             rng: inout MeasRNG, context: String, file: StaticString = #filePath, line: UInt = #line) {
        let length = wall.geometricLength, height = wall.height.scanned
        for p in pieces {
            XCTAssertEqual(p.wallID, wall.id, context, file: file, line: line)
            XCTAssertLessThan(p.along.lowerBound, p.along.upperBound, context, file: file, line: line)
            XCTAssertLessThan(p.bottom, p.top, context, file: file, line: line)
            XCTAssertGreaterThan(p.width, 1e-9, context, file: file, line: line)
            XCTAssertGreaterThan(p.height, 1e-9, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.along.lowerBound, 0, context, file: file, line: line)
            XCTAssertLessThanOrEqual(p.along.upperBound, length + 1e-12, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.bottom, 0, context, file: file, line: line)
            XCTAssertLessThanOrEqual(p.top, height + 1e-12, context, file: file, line: line)
            XCTAssertEqual(p.role == .full, p.openingID == nil, context, file: file, line: line)
        }
        // No two pieces overlap.
        for i in 0..<pieces.count {
            for j in (i + 1)..<max(pieces.count, i + 1) {
                let ox = min(pieces[i].along.upperBound, pieces[j].along.upperBound) - max(pieces[i].along.lowerBound, pieces[j].along.lowerBound)
                let oy = min(pieces[i].top, pieces[j].top) - max(pieces[i].bottom, pieces[j].bottom)
                if ox > 0 && oy > 0 { XCTFail("pieces \(i) and \(j) overlap by \(ox) x \(oy). \(context)", file: file, line: line) }
            }
        }
        // Area balance.
        let solid = pieces.reduce(0) { $0 + $1.area }
        XCTAssertEqual(solid + unionArea(rects), length * height, accuracy: 1e-9, context, file: file, line: line)
        // Points: inside an opening -> in no piece; elsewhere -> in exactly one.
        for _ in 0..<60 {
            let x = measSampleLeaf(&rng, 0...length), y = measSampleLeaf(&rng, 0...height)
            let margin = 1e-7
            let nearEdge = rects.contains { r in
                (abs(x - r.x0) < margin || abs(x - r.x1) < margin) && y > r.y0 - margin && y < r.y1 + margin
                || (abs(y - r.y0) < margin || abs(y - r.y1) < margin) && x > r.x0 - margin && x < r.x1 + margin
            }
            if nearEdge { continue }
            let inOpening = rects.contains { $0.x0 < x && x < $0.x1 && $0.y0 < y && y < $0.y1 }
            let hits = pieces.filter { $0.along.lowerBound < x && x < $0.along.upperBound && $0.bottom < y && y < $0.top }.count
            XCTAssertEqual(hits, inOpening ? 0 : 1, "point (\(x), \(y)). \(context)", file: file, line: line)
        }
    }

    func testPropertyAreaBalanceWithNonOverlappingOpenings() {
        var rng = MeasRNG(seed: 4242)
        for trial in 0..<150 {
            var room = randomRoom(&rng, index: trial)
            var openings: [Opening] = []
            var rectsByWall: [UUID: [(x0: Double, x1: Double, y0: Double, y1: Double)]] = [:]
            for wall in room.walls {
                let length = wall.geometricLength, height = wall.height.scanned
                let k = Int.random(in: 0...4, using: &rng)
                let cuts = (0..<(2 * k)).map { _ in measSampleLeaf(&rng, 0...length) }.sorted()
                for i in 0..<k {
                    let x0 = cuts[2 * i], x1 = cuts[2 * i + 1]
                    guard x1 - x0 > 0.05 else { continue }
                    let sill = Bool.random(using: &rng) ? 0 : measSampleLeaf(&rng, 0.3...1.2)
                    let h = measSampleLeaf(&rng, 0.3...(max(0.31, height - sill)))
                    let top = min(height, sill + h)
                    openings.append(makeOpening(wall: wall, x0: x0, x1: x1, sill: sill, height: top - sill))
                    rectsByWall[wall.id, default: []].append((x0, x1, sill, top))
                }
            }
            room.openings = openings
            let pieces = room.wallPieces()
            var sum = 0.0
            for wall in room.walls {
                let mine = pieces.filter { $0.wallID == wall.id }
                checkPieces(mine, wall: wall, rects: rectsByWall[wall.id] ?? [], rng: &rng, context: "trial \(trial) wall \(wall.id)")
                sum += mine.reduce(0) { $0 + $1.area }
            }
            // Whole room: summed piece area + opening area = sum of wall length x height (the spec's property).
            let openingArea = openings.reduce(0) { $0 + $1.width.scanned * $1.height.scanned }
            let wallArea = room.walls.reduce(0) { $0 + $1.geometricLength * $1.height.scanned }
            XCTAssertEqual(sum + openingArea, wallArea, accuracy: 1e-9, "trial \(trial)")
            // The room metrics agree when no wall height differs from the others' sum.
            XCTAssertEqual(room.metrics.grossWallArea, wallArea, accuracy: 1e-9)
        }
    }

    func testPropertyAreaBalanceWithOverlappingAndClippedOpenings() {
        var rng = MeasRNG(seed: 777)
        for trial in 0..<150 {
            var room = randomRoom(&rng, index: trial)
            var openings: [Opening] = []
            var rectsByWall: [UUID: [(x0: Double, x1: Double, y0: Double, y1: Double)]] = [:]
            for wall in room.walls {
                let length = wall.geometricLength, height = wall.height.scanned
                for _ in 0..<Int.random(in: 0...5, using: &rng) {
                    let x0 = measSampleLeaf(&rng, -0.5...(length + 0.5))
                    let w = measSampleLeaf(&rng, 0.1...max(0.2, length / 2))
                    let sill = Bool.random(using: &rng) ? 0 : measSampleLeaf(&rng, -0.1...(height))
                    let h = measSampleLeaf(&rng, 0.2...2.5)
                    openings.append(Opening(kind: .window, wallID: wall.id, offsetFromWallStart: x0,
                                            width: Measured(scanned: w), height: Measured(scanned: h),
                                            sillHeight: Measured(scanned: max(0, sill))))
                    // What the clipped opening covers, computed here independently.
                    let cx0 = max(0, x0), cx1 = min(length, x0 + w)
                    let cy0 = max(0, sill), cy1 = min(height, max(0, sill) + h)
                    if cx1 > cx0 && cy1 > cy0 { rectsByWall[wall.id, default: []].append((cx0, cx1, cy0, cy1)) }
                }
            }
            room.openings = openings
            for wall in room.walls {
                let mine = room.wallPieces(on: wall)
                checkPieces(mine, wall: wall, rects: rectsByWall[wall.id] ?? [], rng: &rng, context: "trial \(trial) wall \(wall.id)")
            }
        }
    }

    // MARK: - Triangulation

    private func triangleArea(_ p: [Point2], _ t: [Int]) -> Double {
        0.5 * (p[t[1]] - p[t[0]]).cross(p[t[2]] - p[t[0]])
    }

    private func checkTriangulation(_ poly: [Point2], expectedTriangles: Int? = nil, context: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        let tris = Polygon.triangulate(poly)
        XCTAssertFalse(tris.isEmpty, "no triangles. \(context)", file: file, line: line)
        var total = 0.0
        for t in tris {
            XCTAssertEqual(t.count, 3, context, file: file, line: line)
            XCTAssertTrue(t.allSatisfy { $0 >= 0 && $0 < poly.count }, "index out of range. \(context)", file: file, line: line)
            XCTAssertEqual(Set(t).count, 3, "repeated index. \(context)", file: file, line: line)
            let a = triangleArea(poly, t)
            XCTAssertGreaterThan(a, 0, "triangle \(t) is not counter-clockwise. \(context)", file: file, line: line)
            total += a
        }
        let scale = max(1, Polygon.area(poly))
        XCTAssertEqual(total, Polygon.area(poly), accuracy: 1e-9 * scale, "area. \(context)", file: file, line: line)
        if let n = expectedTriangles { XCTAssertEqual(tris.count, n, context, file: file, line: line) }
    }

    private func pointToSegmentDistance(_ p: Point2, _ a: Point2, _ b: Point2) -> Double {
        let ab = b - a
        let t = ab.length < 1e-15 ? 0 : max(0, min(1, (p - a).dot(ab) / ab.dot(ab)))
        return p.distance(to: a + ab * t)
    }

    /// Every sample point inside the polygon must be in exactly one triangle; every point outside, in none.
    private func checkCoverage(_ poly: [Point2], rng: inout MeasRNG, context: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let tris = Polygon.triangulate(poly)
        guard let b = Bounds2(points: poly) else { return }
        func inside(_ t: [Int], _ q: Point2) -> Bool {
            let a = poly[t[0]], bb = poly[t[1]], c = poly[t[2]]
            return (bb - a).cross(q - a) > 0 && (c - bb).cross(q - bb) > 0 && (a - c).cross(q - c) > 0
        }
        for _ in 0..<80 {
            let q = Point2(measSampleLeaf(&rng, b.min.x...b.max.x), measSampleLeaf(&rng, b.min.y...b.max.y))
            var nearest = Double.infinity
            for i in poly.indices { nearest = min(nearest, pointToSegmentDistance(q, poly[i], poly[(i + 1) % poly.count])) }
            if nearest < 1e-6 * max(1, b.width) { continue }
            let hits = tris.filter { inside($0, q) }.count
            XCTAssertEqual(hits, Polygon.contains(poly, q) ? 1 : 0, "point \(q). \(context)", file: file, line: line)
        }
    }

    func testTriangulateTriangleAndSquare() {
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(4, 0), Point2(0, 3)]), [[0, 1, 2]])
        // Clockwise triangle: still counter-clockwise output.
        let cw = Polygon.triangulate([Point2(0, 0), Point2(0, 3), Point2(4, 0)])
        XCTAssertEqual(cw.count, 1)
        XCTAssertGreaterThan(triangleArea([Point2(0, 0), Point2(0, 3), Point2(4, 0)], cw[0]), 0)
        let square = [Point2(0, 0), Point2(2, 0), Point2(2, 2), Point2(0, 2)]
        checkTriangulation(square, expectedTriangles: 2)
        checkTriangulation(square.reversed(), expectedTriangles: 2)
        XCTAssertEqual(Polygon.triangulate(square).reduce(0) { $0 + triangleArea(square, $1) }, 4, accuracy: 1e-12)
    }

    func testTriangulateConcaveShapes() {
        let lShape = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]    // area 20
        checkTriangulation(lShape, expectedTriangles: 4)
        checkTriangulation(lShape.reversed(), expectedTriangles: 4)
        // U shape: 6 wide, 4 tall, 2 x 3 notch from the top. Area 24 - 6 = 18.
        let u = [Point2(0, 0), Point2(6, 0), Point2(6, 4), Point2(4, 4), Point2(4, 1), Point2(2, 1), Point2(2, 4), Point2(0, 4)]
        XCTAssertEqual(Polygon.area(u), 18, accuracy: 1e-12)
        checkTriangulation(u, expectedTriangles: 6)
        checkTriangulation(u.reversed(), expectedTriangles: 6)
        // T shape.
        let t = [Point2(0, 3), Point2(0, 4), Point2(6, 4), Point2(6, 3), Point2(4, 3), Point2(4, 0), Point2(2, 0), Point2(2, 3)]
        checkTriangulation(t, expectedTriangles: 6)
        // Arrow head (concave quad).
        let dart = [Point2(0, 0), Point2(4, 2), Point2(0, 4), Point2(1, 2)]
        XCTAssertEqual(Polygon.area(dart), 6, accuracy: 1e-12)          // triangle 8 minus the notch triangle 2
        checkTriangulation(dart, expectedTriangles: 2)
        checkTriangulation(dart.reversed(), expectedTriangles: 2)
        // Comb with 8 teeth.
        var comb: [Point2] = [Point2(0, 0), Point2(16, 0)]
        for i in stride(from: 7, through: 0, by: -1) {
            let x = Double(i) * 2
            comb.append(Point2(x + 2, 5)); comb.append(Point2(x + 1, 5)); comb.append(Point2(x + 1, 1)); comb.append(Point2(x, 1))
            if i > 0 { comb.append(Point2(x, 5)) }
        }
        checkTriangulation(comb, context: "comb")
    }

    func testTriangulateStartIndexAndWindingDoNotMatter() {
        let l = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        for shift in 0..<l.count {
            let rotated = Array(l[shift...] + l[..<shift])
            checkTriangulation(rotated, expectedTriangles: 4, context: "shift \(shift)")
            checkTriangulation(Array(rotated.reversed()), expectedTriangles: 4, context: "reversed shift \(shift)")
        }
    }

    func testTriangulateWithCollinearVertices() {
        // Rectangle 4 x 3 with a vertex in the middle of every edge (eight vertices, 12 m2).
        let r = [Point2(0, 0), Point2(2, 0), Point2(4, 0), Point2(4, 1.5), Point2(4, 3), Point2(2, 3), Point2(0, 3), Point2(0, 1.5)]
        checkTriangulation(r, context: "midpoints")
        checkTriangulation(r.reversed(), context: "midpoints reversed")
        // Eight vertices, all of them used: six triangles, no T-junctions.
        let tris = Polygon.triangulate(r)
        XCTAssertEqual(tris.count, 6)
        XCTAssertEqual(Set(tris.flatMap { $0 }), Set(0..<8))
        XCTAssertEqual(Polygon.triangulate(r.reversed()).count, 6)
        // Many collinear points along one edge of an L.
        var l: [Point2] = []
        for i in 0...6 { l.append(Point2(Double(i), 0)) }
        l.append(contentsOf: [Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)])
        checkTriangulation(l, context: "dense edge")
        // Collinear vertex on a reflex-adjacent edge.
        let c = [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(5, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]
        checkTriangulation(c, context: "collinear before the notch")
        // Walls split in two by a door frame: what Room.polygon gives for a rectangle with an extra corner.
        let split = Room.polygon(name: "S", corners: [Point2(0, 0), Point2(3, 0), Point2(6, 0), Point2(6, 4), Point2(0, 4)])
        checkTriangulation(split.outline, context: "room with a straight corner")
    }

    func testTriangulateRepeatedVertices() {
        // A duplicated corner is an edge of length zero.
        let dup = [Point2(0, 0), Point2(3, 0), Point2(3, 0), Point2(3, 2), Point2(0, 2)]
        checkTriangulation(dup, context: "duplicate")
        let tail = [Point2(0, 0), Point2(3, 0), Point2(3, 2), Point2(0, 2), Point2(0, 0)]    // closed ring: first == last
        checkTriangulation(tail, context: "closing vertex repeated")
        // A zero-width spike sticking out of a square.
        let spike = [Point2(0, 0), Point2(2, 0), Point2(5, 0), Point2(2, 0), Point2(2, 2), Point2(0, 2)]
        checkTriangulation(spike, context: "spike")
    }

    func testTriangulateDegenerateInputReturnsEmpty() {
        XCTAssertEqual(Polygon.triangulate([]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(1, 1)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(1, 1), Point2(1, 1), Point2(1, 1)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(1, 1), Point2(2, 2)]), [])                // collinear
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(1, 0), Point2(2, 0), Point2(3, 0)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(4, 0), Point2(4, 0), Point2(0, 0)]), [])  // zero area
        XCTAssertEqual(Polygon.triangulate([Point2(.nan, 0), Point2(1, 0), Point2(1, 1)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(.infinity, 0), Point2(1, 1)]), [])
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(1, 0), Point2(1, -.infinity)]), [])
        // Bow tie: the edges cross.
        XCTAssertEqual(Polygon.triangulate([Point2(0, 0), Point2(2, 2), Point2(2, 0), Point2(0, 2)]), [])
        // Pentagram drawn in one stroke.
        let star = (0..<5).map { i -> Point2 in
            let a = Double(i * 2) * 2 * Double.pi / 5
            return Point2(cos(a), sin(a))
        }
        XCTAssertEqual(Polygon.triangulate(star), [])
        // Tiny but valid polygons still work, huge coordinates too.
        checkTriangulation([Point2(0, 0), Point2(1e-6, 0), Point2(1e-6, 1e-6), Point2(0, 1e-6)], expectedTriangles: 2)
        // Far from the origin the shoelace sum in Polygon.area loses digits, so compare with the known 12 m2 instead.
        let far = [Point2(1e6, 1e6), Point2(1e6 + 4, 1e6), Point2(1e6 + 4, 1e6 + 3), Point2(1e6, 1e6 + 3)]
        let farTris = Polygon.triangulate(far)
        XCTAssertEqual(farTris.count, 2)
        XCTAssertEqual(farTris.reduce(0) { $0 + triangleArea(far, $1) }, 12, accuracy: 1e-6)
    }

    func testTriangulateRoomOutlinesMatchRoomArea() {
        let rooms = [
            Room.rectangle(name: "R", width: 6.2, depth: 4.5),
            Room.polygon(name: "L", corners: [Point2(0, 0), Point2(6, 0), Point2(6, 2), Point2(4, 2), Point2(4, 4), Point2(0, 4)]),
            Room.polygon(name: "CW", corners: [Point2(0, 0), Point2(0, 3), Point2(4, 3), Point2(4, 0)]),
        ]
        for room in rooms {
            let tris = Polygon.triangulate(room.outline)
            XCTAssertEqual(tris.reduce(0) { $0 + triangleArea(room.outline, $1) }, room.metrics.floorArea, accuracy: 1e-9, room.name)
        }
    }

    func testPropertyStarPolygonsAllSizes() {
        var rng = MeasRNG(seed: 31337)
        for n in 3...60 {
            for rep in 0..<8 {
                var pts: [Point2] = []
                if n == 3 {
                    repeat {
                        pts = (0..<3).map { _ in Point2(measSampleLeaf(&rng, -5...5), measSampleLeaf(&rng, -5...5)) }
                    } while Polygon.area(pts) < 0.5
                } else {
                    for i in 0..<n {
                        let a = 2 * Double.pi * (Double(i) + 0.5 + (measSampleLeaf(&rng, 0...1) - 0.5) * 0.9) / Double(n)
                        let rad = measSampleLeaf(&rng, 0.5...5)
                        pts.append(Point2(cos(a) * rad, sin(a) * rad))
                    }
                }
                if rep % 2 == 1 { pts.reverse() }
                let shift = Int.random(in: 0..<n, using: &rng)
                pts = Array(pts[shift...] + pts[..<shift])
                checkTriangulation(pts, expectedTriangles: n - 2, context: "n=\(n) rep=\(rep)")
                if rep < 2 { checkCoverage(pts, rng: &rng, context: "coverage n=\(n) rep=\(rep)") }
            }
        }
    }

    func testPropertyStaircasePolygonsWithCollinearAndRepeatedVertices() {
        // Histogram polygons: axis-aligned, equal bar heights give duplicated and collinear vertices.
        var rng = MeasRNG(seed: 2026)
        for trial in 0..<300 {
            let bars = Int.random(in: 1...12, using: &rng)
            let widths = (0..<bars).map { _ in Double(Int.random(in: 1...3, using: &rng)) }
            let heights = (0..<bars).map { _ in Double(Int.random(in: 1...4, using: &rng)) }   // few distinct values: many ties
            var xs: [Double] = [0]
            for w in widths { xs.append(xs.last! + w) }
            var pts: [Point2] = [Point2(0, 0), Point2(xs[bars], 0), Point2(xs[bars], heights[bars - 1])]
            for i in stride(from: bars - 1, through: 0, by: -1) {
                pts.append(Point2(xs[i], heights[i]))
                if i > 0 { pts.append(Point2(xs[i], heights[i - 1])) }
            }
            let expectedArea = zip(widths, heights).reduce(0) { $0 + $1.0 * $1.1 }
            XCTAssertEqual(Polygon.area(pts), expectedArea, accuracy: 1e-9)
            if Bool.random(using: &rng) { pts.reverse() }
            let shift = Int.random(in: 0..<pts.count, using: &rng)
            pts = Array(pts[shift...] + pts[..<shift])
            let tris = Polygon.triangulate(pts)
            XCTAssertFalse(tris.isEmpty, "trial \(trial)")
            let total = tris.reduce(0) { $0 + triangleArea(pts, $1) }
            XCTAssertEqual(total, expectedArea, accuracy: 1e-9, "trial \(trial) bars \(bars)")
            XCTAssertTrue(tris.allSatisfy { triangleArea(pts, $0) > 0 }, "trial \(trial)")
            checkCoverage(pts, rng: &rng, context: "staircase trial \(trial)")
        }
    }

    func testPropertyRandomLayoutsOfRoomsTriangulate() {
        // L, U and T made of randomly sized rectangles, rotated by a random angle.
        var rng = MeasRNG(seed: 555)
        for trial in 0..<120 {
            let w = measSampleLeaf(&rng, 4...12), d = measSampleLeaf(&rng, 4...10)
            let nw = measSampleLeaf(&rng, 1...(w / 2 - 0.5)), nd = measSampleLeaf(&rng, 1...(d - 1))
            let base: [Point2]
            switch trial % 3 {
            case 0: base = [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(w - nw, d), Point2(w - nw, nd), Point2(0, nd)]
            case 1: base = [Point2(0, 0), Point2(w, 0), Point2(w, d), Point2(w - nw, d), Point2(w - nw, nd), Point2(nw, nd), Point2(nw, d), Point2(0, d)]
            default: base = [Point2(0, d - nd), Point2(0, d), Point2(w, d), Point2(w, d - nd), Point2(w / 2 + nw / 2, d - nd),
                             Point2(w / 2 + nw / 2, 0), Point2(w / 2 - nw / 2, 0), Point2(w / 2 - nw / 2, d - nd)]
            }
            let angle = measSampleLeaf(&rng, 0...(2 * Double.pi))
            var pts = base.map { $0.rotated(by: angle) }
            if trial % 2 == 0 { pts.reverse() }
            checkTriangulation(pts, expectedTriangles: base.count - 2, context: "trial \(trial)")
        }
    }

    // General simple polygons: random points joined into a closed path, then untangled with 2-opt
    // moves until no two edges cross. Unlike star shapes these are arbitrary concave outlines;
    // on a small integer grid they also have collinear vertices and shared coordinates.

    private func turn(_ a: Point2, _ b: Point2, _ c: Point2) -> Int {
        let s = (b - a).cross(c - a)
        return s > 1e-12 ? 1 : (s < -1e-12 ? -1 : 0)
    }

    private func edgesCross(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Bool {
        turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0
    }

    private func untangled(_ points: [Point2]) -> [Point2] {
        var p = points
        let n = p.count
        var changed = true
        var rounds = 0
        while changed && rounds < 2000 {
            changed = false
            rounds += 1
            search: for i in 0..<n {
                for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                    if edgesCross(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) {
                        p[(i + 1)...j].reverse()
                        changed = true
                        break search
                    }
                }
            }
        }
        return p
    }

    /// No repeated point, no vertex touching a non-incident edge, no crossing edges, positive area.
    private func isStrictlySimple(_ p: [Point2]) -> Bool {
        let n = p.count
        for i in 0..<n {
            for j in (i + 1)..<n where p[i] == p[j] { return false }
        }
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n]
            for j in 0..<n where j != i && j != (i + 1) % n {
                let q = p[j]
                let onEdge = turn(a, b, q) == 0 && q.x >= min(a.x, b.x) && q.x <= max(a.x, b.x)
                    && q.y >= min(a.y, b.y) && q.y <= max(a.y, b.y)
                if onEdge { return false }
            }
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                if edgesCross(a, b, p[j], p[(j + 1) % n]) { return false }
            }
        }
        return Polygon.area(p) > 1e-9
    }

    func testPropertyRandomSimplePolygonsAfterUntangling() {
        var rng = MeasRNG(seed: 8)
        var floatCases = 0, gridCases = 0
        for trial in 0..<150 {
            let n = Int.random(in: 3...40, using: &rng)
            let pts = (0..<n).map { _ in Point2(measSampleLeaf(&rng, 0...10), measSampleLeaf(&rng, 0...10)) }
            let poly = untangled(pts)
            guard isStrictlySimple(poly) else { continue }
            floatCases += 1
            checkTriangulation(poly, expectedTriangles: n - 2, context: "float trial \(trial) n=\(n)")
            if trial % 5 == 0 { checkCoverage(poly, rng: &rng, context: "float coverage trial \(trial)") }
        }
        for trial in 0..<3000 {
            let n = Int.random(in: 4...12, using: &rng)
            let pts = (0..<n).map { _ in Point2(Double(Int.random(in: 0...5, using: &rng)), Double(Int.random(in: 0...5, using: &rng))) }
            let poly = untangled(pts)
            guard isStrictlySimple(poly) else { continue }
            gridCases += 1
            // Straight vertices are kept, so every vertex is used: n - 2 triangles.
            checkTriangulation(poly, expectedTriangles: n - 2, context: "grid trial \(trial) poly \(poly)")
            if trial % 25 == 0 { checkCoverage(poly, rng: &rng, context: "grid coverage trial \(trial)") }
        }
        XCTAssertGreaterThan(floatCases, 100)       // the generators really produced simple polygons
        XCTAssertGreaterThan(gridCases, 300)
    }

    func testFuzzedPolygonsNeverCrash() {
        // Random point soups are mostly self-intersecting. Whatever comes back must be sane.
        var rng = MeasRNG(seed: 13)
        var nonEmpty = 0
        for _ in 0..<3000 {
            let n = Int.random(in: 0...12, using: &rng)
            var pts = (0..<n).map { _ in Point2(Double(Int.random(in: -3...3, using: &rng)), Double(Int.random(in: -3...3, using: &rng))) }
            if n > 0 && Int.random(in: 0..<5, using: &rng) == 0 { pts[n - 1] = pts[0] }
            let tris = Polygon.triangulate(pts)
            if !tris.isEmpty {
                nonEmpty += 1
                XCTAssertTrue(tris.allSatisfy { $0.count == 3 && $0.allSatisfy { $0 >= 0 && $0 < n } })
                XCTAssertTrue(tris.allSatisfy { triangleArea(pts, $0) > 0 })
                XCTAssertLessThanOrEqual(tris.count, n - 2)
                // Anything returned for a polygon that does not cross itself must cover it exactly.
                if !TriangulationMath.hasProperCrossing(pts, tolerance: 1e-12) {
                    XCTAssertEqual(tris.reduce(0) { $0 + triangleArea(pts, $1) }, Polygon.area(pts), accuracy: 1e-9)
                }
            }
        }
        XCTAssertGreaterThan(nonEmpty, 100)           // the fuzz did exercise the success path
    }

    func testLargePolygonFinishesQuickly() {
        var pts: [Point2] = []
        let n = 240
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let rad = i % 2 == 0 ? 5.0 : 3.0                       // a 120-point star
            pts.append(Point2(cos(a) * rad, sin(a) * rad))
        }
        checkTriangulation(pts, expectedTriangles: n - 2, context: "240-point star")
    }

    // MARK: - Cross-module sanity

    func testVerificationFlowsIntoMetricsButNotIntoGeometryHelpers() {
        var r = Room.rectangle(name: "Bed", kind: .bedroom, width: 4.0, depth: 3.0,
                               openings: [.window(wall: 0, offset: 1, width: 2, height: 1.2, sill: 1.0)])
        let piecesBefore = r.wallPieces()
        let snapBefore = r.snapPoints()
        XCTAssertTrue(r.setVerification(Verification(value: 4.04), for: .wallLength(r.walls[0].id)))
        XCTAssertTrue(r.setVerification(Verification(value: 4.04), for: .wallLength(r.walls[2].id)))
        XCTAssertEqual(r.metrics.length!, 4.04, accuracy: 1e-9)                     // effective value used by metrics
        XCTAssertEqual(r.metrics.floorArea, 12.0, accuracy: 1e-9)                   // outline untouched
        XCTAssertEqual(r.wallPieces(), piecesBefore)
        XCTAssertEqual(r.snapPoints(), snapBefore)
        let report = AccuracyReport(rooms: [r])
        XCTAssertEqual(report.sampleCount, 2)
        XCTAssertEqual(report.meanSignedError, 0.04, accuracy: 1e-9)
        let list = VerificationChecklist(room: r)
        XCTAssertEqual(list.verifiedCount, 2)
    }
}
