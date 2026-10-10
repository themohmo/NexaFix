import Foundation

// The logic behind the Verify sheet: a person reads a number off a laser measure (or a tape, or a
// drawing), types it, and the app says how far the scan was, warns about typos, and records the
// check. Everything here is a plain value type so it is tested on Linux; the sheet only draws it.

// MARK: - Lengths in sentences

/// Lengths for sentences on screen: thousands are grouped with a no-break space, so a number never
/// splits across two lines ("3 245 mm"). Drawings and exports keep using `UnitFormatter`, which never groups.
public enum GroupedLength {

    /// U+00A0, between digit groups and before the unit.
    public static let separator = "\u{00A0}"

    /// "3 245 mm", "324.5 cm", "3.245 m", "127.76 in", `10' 7 3/4"`.
    public static func text(_ metres: Double, unit: LengthUnit, precision: UnitPrecision = .precise) -> String {
        guard metres.isFinite else { return "no value" }
        if unit == .feetAndInches {
            return UnitFormatter.length(metres, unit: unit, precision: precision)
        }
        return number(metres, unit: unit, precision: precision) + separator + unit.symbol
    }

    /// The digits alone, grouped: "3 245" for millimetres. Feet and inches have no separate number part,
    /// so they come back complete (`10' 7 3/4"`).
    public static func number(_ metres: Double, unit: LengthUnit, precision: UnitPrecision = .precise) -> String {
        guard metres.isFinite else { return "no value" }
        if unit == .feetAndInches { return UnitFormatter.length(metres, unit: unit, precision: precision) }
        return group(UnitFormatter.length(metres, unit: unit, precision: precision, includeUnit: false))
    }

    /// Two lengths with one unit at the end: "6 240 × 4 500 mm". Feet and inches repeat their marks:
    /// `20' 5" × 14' 9"`.
    public static func dimensions(_ first: Double, _ second: Double, unit: LengthUnit,
                                  precision: UnitPrecision = .precise) -> String {
        if unit == .feetAndInches {
            return text(first, unit: unit, precision: precision) + " \u{00D7} " + text(second, unit: unit, precision: precision)
        }
        return number(first, unit: unit, precision: precision) + " \u{00D7} "
            + number(second, unit: unit, precision: precision) + separator + unit.symbol
    }

    /// Inserts `separator` between groups of three digits of the whole part: "3245.5" becomes "3 245.5".
    static func group(_ digits: String) -> String {
        var body = Substring(digits)
        var sign = ""
        if body.hasPrefix("-") {
            sign = "-"
            body = body.dropFirst()
        }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = parts.first, whole.count > 3, whole.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return digits
        }
        var grouped = ""
        for (offset, character) in whole.enumerated() {
            if offset > 0, (whole.count - offset) % 3 == 0 { grouped += separator }
            grouped.append(character)
        }
        let fraction = parts.count > 1 ? "." + String(parts[1]) : ""
        return sign + grouped + fraction
    }
}

// MARK: - The model

/// The state of one Verify sheet: what is typed, what it means, and what saving it would do.
///
/// ```
/// var model = VerifyModel(room: room, target: .wallLength(wall.id), units: settings.units)
/// model.text = "3.233 m"                  // a person typing
/// model.deviationText                    // "Scan read 12 mm short (0.4 %)"
/// let updated = model.commit(date: now)  // the room with the check recorded, or nil
/// ```
///
/// Rules:
/// - **Parsing** is `UnitParser.parseLength(_:defaultUnit:)` with the field's unit as the default, so a bare
///   `3245` is millimetres for a millimetre user and feet for a feet-and-inches user, who types `10'7"`.
///   A door sill may be zero; nothing else may.
/// - **Typos are caught, not forbidden.** A value under 1 mm, more than three times the scan or less than a
///   third of it is held back with a calm message until the person confirms it (`confirmOverride()`),
///   because real rooms differ from scans. Typing again withdraws the confirmation.
/// - **Nothing is saved silently:** `commit` returns nil unless `canSave`, and the sheet shows why.
public struct VerifyModel: Equatable, Sendable {

    /// What the typed text amounts to.
    public enum Check: Equatable, Sendable {
        /// Nothing typed yet.
        case empty
        /// The text is not a length. The message says how to write one.
        case unreadable(String)
        /// A length, but far from the scan. Needs `confirmOverride()` before it can be saved.
        case farFromScan(String)
        /// A plausible length.
        case ok
    }

    /// A difference between two sides of a rectangle larger than this is worth a hint, metres.
    public static let oppositeWallTolerance = 0.03
    /// A deviation under this reads as "Matches the scan", metres (half a millimetre).
    public static let matchTolerance = 0.0005

    public let room: Room
    public let target: MeasureTarget
    /// The user's display units (used for nothing but the starting `inputUnit`).
    public let units: DisplayUnits
    /// The unit a bare number means. Starts as `units.length`; the unit switcher changes it.
    public private(set) var inputUnit: LengthUnit

    /// What the person typed. Changing it withdraws an earlier `confirmOverride()`.
    public var text: String {
        didSet { if text != oldValue { overrideConfirmed = false } }
    }
    public var source: VerificationSource
    public var note: String
    /// The person accepted a value far from the scan.
    public private(set) var overrideConfirmed = false

    /// A number together with the text that was written for it. While the field still holds exactly that
    /// text, the number is used as it is, so display rounding never changes a value: a saved 3.2456 m shown
    /// as "3246" stays 3.2456 until the person edits the field, and cycling through units does not drift.
    private struct ExactText: Equatable, Sendable {
        var text: String
        var value: Double
    }

    private let existing: Verification?
    private let measured: Measured?
    private var exact: ExactText?
    /// The verified length of the wall opposite this one, when this is a wall of a rectangular room.
    private let oppositeVerified: Double?

    public init(room: Room, target: MeasureTarget, units: DisplayUnits) {
        self.room = room
        self.target = target
        self.units = units
        self.inputUnit = units.length

        let measured = room.measured(target)
        self.measured = measured
        self.existing = measured?.verification
        self.source = measured?.verification?.source ?? .laser
        self.note = measured?.verification?.note ?? ""

        if let value = measured?.verification?.value {
            let filled = VerifyModel.fieldText(value, unit: units.length)
            self.text = filled
            self.exact = ExactText(text: filled, value: value)
        } else {
            self.text = ""
            self.exact = nil
        }

        self.oppositeVerified = VerifyModel.oppositeVerifiedLength(room: room, target: target)
    }

    // MARK: What is being checked

    /// "Wall A length", "Door 1 width", "Ceiling height", or a custom measurement's label.
    public var title: String { room.fullTitle(for: target) }
    /// "Living Room".
    public var roomName: String { room.name }
    /// Whether the target still exists in the room.
    public var targetExists: Bool { measured != nil }
    /// What LiDAR read, metres.
    public var scannedValue: Double? { measured?.scanned }
    /// "3 245 mm", in the unit being typed.
    public var scannedText: String {
        guard let scanned = measured?.scanned else { return "" }
        return GroupedLength.text(scanned, unit: inputUnit)
    }
    /// "\u{00B1}22 mm": the typical LiDAR error for the scanned number.
    public var toleranceText: String {
        guard let scanned = measured?.scanned else { return "" }
        return UnitFormatter.tolerance(forLength: scanned, unit: inputUnit)
    }
    /// The check already on record, if any.
    public var currentVerification: Verification? { existing }
    public var isVerified: Bool { existing != nil }
    /// Clear is offered only when there is something to clear.
    public var canClear: Bool { existing != nil }

    // MARK: Typing

    /// "3245", "3.245", `10' 7"`: an example for the empty field.
    public var placeholder: String {
        switch inputUnit {
        case .millimetres: return "3245"
        case .centimetres: return "324.5"
        case .metres: return "3.245"
        case .inches: return "127.75"
        case .feetAndInches: return "10' 7\""
        }
    }

    /// The text trimmed of spaces.
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The typed length in metres, or nil when the field is empty or not a length.
    public var parsedValue: Double? {
        guard measured != nil else { return nil }
        if let exact, text == exact.text { return exact.value }
        let typed = trimmedText
        guard !typed.isEmpty else { return nil }
        return UnitParser.parseLength(typed, defaultUnit: inputUnit, allowZero: target.allowsZeroValue)
    }

    /// Switches what a bare number means and, when the text is a length, rewrites it in the new unit
    /// ("3245" in millimetres becomes "3.245" in metres). The number itself does not change, and a
    /// confirmed override stays confirmed.
    public mutating func setUnit(_ unit: LengthUnit) {
        guard unit != inputUnit else { return }
        let value = parsedValue
        let confirmed = overrideConfirmed
        inputUnit = unit
        if let value {
            let rewritten = VerifyModel.fieldText(value, unit: unit)
            text = rewritten
            exact = ExactText(text: rewritten, value: value)
            overrideConfirmed = confirmed
        }
    }

    /// Moves to the next unit in `LengthUnit.allCases` (the unit switcher above the keyboard).
    public mutating func cycleUnit() {
        let all = LengthUnit.allCases
        guard let index = all.firstIndex(of: inputUnit) else { return }
        setUnit(all[(index + 1) % all.count])
    }

    // MARK: Checking

    /// What the text amounts to. See `Check`.
    public var check: Check {
        if trimmedText.isEmpty { return .empty }
        guard let value = parsedValue else { return .unreadable(unreadableMessage) }
        if let message = farFromScanMessage(for: value) { return .farFromScan(message) }
        return .ok
    }

    /// The calm sentence for `unreadable` and `farFromScan`, or nil.
    public var message: String? {
        switch check {
        case .unreadable(let message), .farFromScan(let message): return message
        case .empty, .ok: return nil
        }
    }

    /// The value is a length but far from the scan, and the person has not confirmed it yet.
    public var needsConfirmation: Bool {
        if case .farFromScan = check { return !overrideConfirmed }
        return false
    }

    /// The person accepts a value far from the scan.
    public mutating func confirmOverride() {
        if case .farFromScan = check { overrideConfirmed = true }
    }

    /// Saving would work: the text is a length and, if it is far from the scan, it was confirmed.
    public var canSave: Bool {
        guard targetExists, parsedValue != nil else { return false }
        switch check {
        case .ok: return true
        case .farFromScan: return overrideConfirmed
        case .empty, .unreadable: return false
        }
    }

    // MARK: Deviation

    /// Typed minus scanned, metres. Positive means the scan read short.
    public var deviation: Double? {
        guard let value = parsedValue, let scanned = measured?.scanned else { return nil }
        return value - scanned
    }

    /// "Scan read 12 mm short (0.4 %)", "Scan read 8 mm long (0.3 %)" or "Matches the scan"; nil while
    /// there is no length to compare. The percentage is of the typed value, as in `Measured.deviationPercent`.
    public var deviationText: String? {
        guard let value = parsedValue, let difference = deviation else { return nil }
        if abs(difference) < VerifyModel.matchTolerance { return "Matches the scan" }
        let size = GroupedLength.text(abs(difference), unit: inputUnit)
        let direction = difference > 0 ? "short" : "long"
        var percent = ""
        if abs(value) > 1e-9 {
            let shown = String(format: "%.1f", abs(difference) / abs(value) * 100)
            if Double(shown) != 0 { percent = " (\(shown) %)" }
        }
        return "Scan read \(size) \(direction)\(percent)"
    }

    /// A gentle hint when this wall disagrees with the verified wall opposite it by more than 3 cm
    /// in a rectangular room: "Opposite wall is 3 892 mm: the room may be out of square". nil otherwise.
    public var contradiction: String? {
        guard let value = parsedValue, let opposite = oppositeVerified else { return nil }
        guard abs(value - opposite) > VerifyModel.oppositeWallTolerance else { return nil }
        return "Opposite wall is \(GroupedLength.text(opposite, unit: inputUnit)): the room may be out of square"
    }

    // MARK: Result

    /// The check this sheet would record, or nil unless `canSave`. Blank notes become nil.
    public func verification(date: Date) -> Verification? {
        guard canSave, let value = parsedValue else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Verification(value: value, source: source, date: date, note: trimmedNote.isEmpty ? nil : trimmedNote)
    }

    /// The room with the check recorded through `Room.setVerification(_:for:)`. Geometry is untouched.
    /// nil unless `canSave`.
    public func commit(date: Date = Date()) -> Room? {
        guard let check = verification(date: date) else { return nil }
        var updated = room
        guard updated.setVerification(check, for: target) else { return nil }
        return updated
    }

    /// The room with the check removed, so the value is "Scanned" again. nil when the target is gone.
    public func clear() -> Room? {
        var updated = room
        guard updated.setVerification(nil, for: target) else { return nil }
        return updated
    }

    // MARK: Words

    /// How to write a length in the unit being typed.
    var unreadableMessage: String {
        let examples: String
        switch inputUnit {
        case .millimetres: examples = "3245 or 3.245 m"
        case .centimetres: examples = "324.5 or 3.245 m"
        case .metres: examples = "3.245 or 3245 mm"
        case .inches: examples = "127.75 or 10' 7 3/4\""
        case .feetAndInches: examples = "10' 7 3/4\" or 3245 mm"
        }
        return "That doesn\u{2019}t look like a length. Try \(examples)."
    }

    private func farFromScanMessage(for value: Double) -> String? {
        guard let scanned = measured?.scanned else { return nil }
        let zeroIsFine = target.allowsZeroValue && value == 0
        if value < 0.001 && !zeroIsFine {
            return "That is under 1 mm. Check the number or unit." + commaNote
        }
        if scanned >= 0.005 {
            if value > 3 * scanned || value < scanned / 3 {
                return "That is far from the scan (\(scannedText)). Check the number or unit." + commaNote
            }
        } else if value > 0.5 {
            // A scan of about nothing (a door that starts at the floor) leaves no ratio to test.
            return "That is far from the scan (\(scannedText)). Check the number or unit." + commaNote
        }
        return nil
    }

    /// Said after a warning when the text looks like "3,245": people write a comma between thousands, but a
    /// comma is read as a decimal point, so the number is not what they meant.
    private var commaNote: String {
        VerifyModel.looksLikeThousandsComma(trimmedText) ? " A comma is read as a decimal point." : ""
    }

    /// "3,245" or "1,250 mm": up to three digits, then groups of exactly three after each comma, and no
    /// decimal point after them.
    static func looksLikeThousandsComma(_ text: String) -> Bool {
        let run = text.prefix { $0.isASCII && ($0.isNumber || $0 == ",") }
        guard run.contains(","), text.dropFirst(run.count).first != "." else { return false }
        let groups = run.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    /// The number as it goes into the field: no unit text where the unit is the field's own.
    static func fieldText(_ metres: Double, unit: LengthUnit) -> String {
        switch unit {
        case .feetAndInches: return UnitFormatter.length(metres, unit: unit)
        default: return UnitFormatter.length(metres, unit: unit, includeUnit: false)
        }
    }

    private static func oppositeVerifiedLength(room: Room, target: MeasureTarget) -> Double? {
        guard case .wallLength(let id) = target, room.walls.count == 4,
              let index = room.walls.firstIndex(where: { $0.id == id }),
              room.metrics.isRectangular else { return nil }
        return room.walls[(index + 2) % 4].length.verification?.value
    }
}
