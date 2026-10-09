// Checks for the plain-Swift app logic that needs no Apple framework: how measurements are worded and
// spoken (MeasurementFormatting), the saved settings (AppSettings) and the wording of errors
// (UserFacingError). Run with ./run.sh; it works on Linux and macOS and prints "checks: N, failures: M".
//
// AppModel is not covered here because it needs the real PropertyStore; its behaviour is checked in the
// app's own tests once a test target exists.
import Foundation
import NexaFixCore

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() { failures += 1; print("FAIL line \(line): \(message)") }
}

func eq<T: Equatable>(_ actual: T, _ expected: T, line: Int = #line) {
    checks += 1
    if actual != expected { failures += 1; print("FAIL line \(line): got \(actual), expected \(expected)") }
}

// ---------- MeasurementFormatting ----------
let mm = DisplayUnits(length: .millimetres, area: .squareMetres)
let m = DisplayUnits(length: .metres, area: .squareMetres)
let cm = DisplayUnits(length: .centimetres, area: .squareFeet)
let inch = DisplayUnits(length: .inches, area: .squareMetres)
let ft = DisplayUnits(length: .feetAndInches, area: .squareFeet)

// parts
eq(MeasurementParts.length(3.245, units: mm), MeasurementParts(number: "3245", unit: "mm", spoken: "3245 millimetres"))
eq(MeasurementParts.length(3.2, units: m), MeasurementParts(number: "3.200", unit: "m", spoken: "3.2 metres"))
eq(MeasurementParts.length(0.001, units: mm).spoken, "1 millimetre")
eq(MeasurementParts.length(1.0, units: m).spoken, "1 metre")
eq(MeasurementParts.length(3.245, units: cm), MeasurementParts(number: "324.5", unit: "cm", spoken: "324.5 centimetres"))
eq(MeasurementParts.length(0.0254, units: inch).spoken, "1 inch")
eq(MeasurementParts.length(3.245, units: inch).number, "127.76")
eq(MeasurementParts.length(3.245, units: inch).spoken, "127.76 inches")
eq(MeasurementParts.length(.nan, units: mm), .unavailable)
eq(MeasurementParts.length(.infinity, units: mm).spoken, "No value")

// feet and inches: 3.245 m = 127.756 in = 10' 7 3/4"
let f = MeasurementParts.length(3.245, units: ft)
eq(f.number, "10' 7 3/4\"")
eq(f.unit, nil)
eq(f.spoken, "10 feet 7 and three quarters inches")
eq(SpokenMeasurement.feetAndInches(0.3048), "1 foot")
eq(SpokenMeasurement.feetAndInches(0.0), "0 inches")
eq(SpokenMeasurement.feetAndInches(0.0254), "1 inch")
eq(SpokenMeasurement.feetAndInches(0.3048 + 0.0254 * 0.5), "1 foot and one half of an inch")
eq(SpokenMeasurement.feetAndInches(0.0127), "one half of an inch")
eq(SpokenMeasurement.feetAndInches(0.0254 * 1.5), "1 and one half inches")
eq(SpokenMeasurement.feetAndInches(0.0254 * 5.0625), "5 and one sixteenth inches")
eq(SpokenMeasurement.feetAndInches(0.0254 * 5.3125), "5 and five sixteenths inches")
eq(SpokenMeasurement.feetAndInches(-0.3048), "minus 1 foot")
eq(SpokenMeasurement.feetAndInches(1e12).isEmpty, false)

// area
eq(MeasurementParts.area(12.5, units: mm), MeasurementParts(number: "12.50", unit: "m\u{00B2}", spoken: "12.5 square metres"))
eq(MeasurementParts.area(1.0, units: mm).spoken, "1 square metre")
eq(MeasurementParts.area(12.5, units: cm).number, "134.5")
eq(MeasurementParts.area(12.5, units: cm).unit, "sq ft")
eq(MeasurementParts.area(12.5, units: cm).spoken, "134.5 square feet")
eq(MeasurementParts.area(0.09290304, units: cm).spoken, "1 square foot")

// angle
eq(MeasurementParts.angle(90), MeasurementParts(number: "90.0", unit: "\u{00B0}", spoken: "90 degrees"))
eq(MeasurementParts.angle(89.64).spoken, "89.6 degrees")
eq(MeasurementParts.angle(1).spoken, "1 degree")
eq(MeasurementParts.angle(.nan), .unavailable)

// tolerance
eq(SpokenMeasurement.tolerance(forLength: 3.245, unit: .millimetres), "plus or minus 49 millimetres")   // 1.5 % of 3.245 m
eq(SpokenMeasurement.tolerance(forLength: 0.5, unit: .millimetres), "plus or minus 10 millimetres")     // floor of 10 mm
eq(SpokenMeasurement.tolerance(forLength: 0.5, unit: .metres), "plus or minus 0.01 metres")
eq(SpokenMeasurement.tolerance(forLength: 0.5, unit: .inches).hasPrefix("plus or minus 0.4"), true)

// provenance
let scanned = Measured(scanned: 1.5)
let laser = Measured(scanned: 3.233, verification: Verification(value: 3.245, source: .laser))
let tape = Measured(scanned: 3.233, verification: Verification(value: 3.245, source: .tape))
let drawing = Measured(scanned: 3.233, verification: Verification(value: 3.245, source: .drawing))
let ps = ProvenanceDescription(scanned, units: mm, compact: false)
eq(ps.isVerified, false)
eq(ps.visibleText, "Scanned \u{00B1}22 mm")
eq(ps.shortText, "Scanned")
eq(ps.spoken, "Scanned, not yet checked. Typically within plus or minus 22 millimetres")
eq(ProvenanceDescription(scanned, units: mm, compact: true).visibleText, "Scanned")
let pl = ProvenanceDescription(laser, units: mm, compact: false)
eq(pl.isVerified, true); eq(pl.visibleText, "Laser"); eq(pl.spoken, "Verified with laser")
eq(ProvenanceDescription(tape, units: mm, compact: true).spoken, "Verified with tape")
eq(ProvenanceDescription(drawing, units: mm, compact: true).spoken, "Verified from drawing")
eq(ProvenanceDescription.label(for: scanned), "Scanned")
eq(ProvenanceDescription.label(for: laser), "Verified (Laser)")
eq(ProvenanceDescription.label(for: tape), "Verified (Tape)")
eq(ProvenanceDescription.label(for: drawing), "Verified (Drawing)")
eq(SpokenMeasurement.midSentence("Verified with laser"), "verified with laser")
eq(SpokenMeasurement.midSentence(""), "")

// verification summary
eq(VerificationSummary(verified: 9, total: 21).text, "9 of 21 checked")
eq(VerificationSummary(verified: 9, total: 21).spoken, "9 of 21 dimensions checked")
eq(VerificationSummary(verified: 9, total: 21).fraction, 9.0 / 21.0)
eq(VerificationSummary(verified: 30, total: 21).verified, 21)
eq(VerificationSummary(verified: -3, total: 21).verified, 0)
eq(VerificationSummary(verified: 0, total: 0).text, "Nothing to check yet")
eq(VerificationSummary(verified: 0, total: 0).fraction, 0)
eq(VerificationSummary(verified: 5, total: -2).total, 0)
eq(VerificationSummary.clamp(.nan), 0); eq(VerificationSummary.clamp(1.7), 1); eq(VerificationSummary.clamp(-1), 0); eq(VerificationSummary.clamp(0.4), 0.4)
eq(SpokenMeasurement.trimmed("100"), "100"); eq(SpokenMeasurement.trimmed("0.000"), "0"); eq(SpokenMeasurement.trimmed("3.250"), "3.25")


// ---------- AppSettings ----------
let suite = UserDefaults(suiteName: "ds-test-\(UUID().uuidString)")!
check(AppSettings.load(from: suite) == AppSettings(), "defaults when empty")
var s = AppSettings(units: DisplayUnits(length: .feetAndInches, area: .squareFeet), hapticsEnabled: false, planScale: 50, paper: "A3 ")
check(s.paper == "a3", "paper normalised")
s.save(to: suite)
check(AppSettings.load(from: suite) == s, "round trip")
check(suite.data(forKey: "com.nexafix.scan.settings.v1") != nil, "versioned key")

func decode(_ json: String) -> AppSettings? { try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
check(decode("{}") == AppSettings(), "empty object -> defaults")
let partial = decode(#"{"hapticsEnabled": false}"#)
check(partial?.hapticsEnabled == false && partial?.units == .default, "missing fields default")
let futureUnit = decode(#"{"units":{"length":"furlongs","area":"squareFeet"},"paper":"a4","planScale":100}"#)
check(futureUnit?.units.length == .millimetres && futureUnit?.units.area == .squareFeet, "unknown length unit falls back, area kept")
check(futureUnit?.paper == "a4" && futureUnit?.planScale == 100, "other fields kept")
let junk = decode(#"{"hapticsEnabled":"yes","planScale":-3,"paper":"tabloid","units":5}"#)
check(junk == AppSettings(), "junk values fall back to defaults")
suite.set(Data("not json".utf8), forKey: "com.nexafix.scan.settings.v1")
check(AppSettings.load(from: suite) == AppSettings(), "corrupt blob -> defaults")
check(AppSettings(planScale: .nan).planScale == nil && AppSettings(planScale: 0).planScale == nil, "bad scale dropped")
let enc = String(data: try! JSONEncoder().encode(AppSettings(planScale: nil)), encoding: .utf8)!
check(!enc.contains("planScale"), "nil scale omitted: \(enc)")

// ---------- UserFacingError ----------
let full = UserFacingError(CocoaError(.fileWriteOutOfSpace), context: "save “Marina”", severity: .dataAtRisk)
check(full.title == "Couldn't save “Marina”", "title: \(full.title)")
check(full.message.contains("enough free storage") && full.message.contains("not saved"), "message: \(full.message)")
check(!full.message.contains("iPhone") && !full.message.contains("iPad") && full.message.contains("this device"), "device-neutral message")
check(full.recovery?.contains("Settings > General > Storage") == true && full.recovery?.contains("iPhone") == false, "device-neutral recovery: \(full.recovery ?? "nil")")
check(full.recovery?.contains("Free up space") == true && full.recovery?.contains("Don't close") == true, "recovery: \(full.recovery ?? "nil")")
check(full.severity == .dataAtRisk && full.errorDescription == full.title && full.recoverySuggestion == full.recovery, "LocalizedError")
struct Odd: Error {}
let odd = UserFacingError(Odd(), context: "")
check(odd.title == "Something went wrong" && odd.message == "Something unexpected happened.", "generic: \(odd.title) / \(odd.message)")
struct Nice: LocalizedError { var errorDescription: String? { "The folder is locked" }; var recoverySuggestion: String? { "Unlock it" } }
let nice = UserFacingError(Nice(), context: "export the plan")
check(nice.message == "The folder is locked." && nice.recovery == "Unlock it", "localized passthrough: \(nice.message)")
let dec = UserFacingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")), context: "open it")
check(dec.message.contains("damaged"), "decoding error wording")
let posix = UserFacingError(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), context: "save")
check(posix.message.contains("enough free storage"), "ENOSPC wording")
check(odd.id != UserFacingError(Odd(), context: "").id, "unique ids")


print("checks: \(checks), failures: \(failures)")
exit(failures == 0 ? 0 : 1)
