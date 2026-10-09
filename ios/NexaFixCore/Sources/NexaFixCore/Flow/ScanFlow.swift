import Foundation

// The multi-room scan flow as a value type. The SwiftUI controller owns a `ScanFlow`, feeds it
// events (a button was tapped, the capture finished, the merge finished) and executes the effects
// it returns. Nothing in here touches RoomPlan or ARKit, so every transition, including the illegal
// ones, is unit-tested off-device.
//
// The happy path for a three-room apartment:
//
//   idle -start-> scanning(0) -finishRoom-> processingRoom(0) -roomFinished-> awaitingName
//        -named-> betweenRooms -scanNext-> scanning(1) ... -finishProperty-> merging
//        -mergeCompleted-> finished
//
// Rules the reducer keeps:
//  - An event that does not make sense in the current state is ignored: the state and the effect list
//    stay as they were. Double taps and late callbacks therefore cannot start a second capture or
//    finish a room twice.
//  - Finished rooms are never dropped by `cancelRoom`, `mergeFailed` or a failure. Only `reset` clears them.
//  - A room needs a name that is not empty and not already used (by this scan or by the property).

// MARK: - Draft

/// What the flow knows about a room that was just scanned and is waiting for its name.
/// The controller keeps the heavy data (the captured room, the parametric room) under `id`.
public struct RoomDraft: Equatable, Sendable, Identifiable {
    /// Identifies this scan in the controller's stores, and later the finished room.
    public var id: UUID
    public var wallCount: Int
    public var doorCount: Int
    public var windowCount: Int
    public var openingCount: Int
    /// Rough floor area, square metres. nil when too little was scanned to tell.
    public var floorAreaM2: Double?
    /// Plain-language notes from building the room, shown under the name field.
    public var warnings: [String]

    /// A draft from plain counts.
    public init(id: UUID = UUID(), wallCount: Int = 0, doorCount: Int = 0, windowCount: Int = 0,
                openingCount: Int = 0, floorAreaM2: Double? = nil, warnings: [String] = []) {
        self.id = id
        self.wallCount = wallCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.openingCount = openingCount
        self.floorAreaM2 = floorAreaM2
        self.warnings = warnings
    }

    /// A draft from the live statistics of the finished capture. `floorAreaM2` overrides the rough estimate.
    public init(id: UUID = UUID(), stats: LiveScanStats, floorAreaM2: Double? = nil, warnings: [String] = []) {
        self.init(id: id, wallCount: stats.walls, doorCount: stats.doors, windowCount: stats.windows,
                  openingCount: stats.openings, floorAreaM2: floorAreaM2 ?? stats.roughFloorAreaM2,
                  warnings: warnings)
    }
}

// MARK: - States, events, effects

/// Where the multi-room flow is.
public enum ScanState: Equatable, Sendable {
    /// Nothing running.
    case idle
    /// The capture session is running for the room at this zero-based index.
    case scanning(roomIndex: Int)
    /// "Finish room" was tapped; the capture is stopping and the room is being built.
    case processingRoom(roomIndex: Int)
    /// A room was scanned and needs a name.
    case awaitingName(RoomDraft)
    /// At least one room is finished; the person chooses between another room and finishing.
    case betweenRooms
    /// Joining the rooms into one 3D model, exporting it, saving the AR map.
    case merging
    /// The result was handed on.
    case finished
    /// Something that cannot be recovered by waiting went wrong. Finished rooms are kept.
    case failed(String)
}

/// Everything that can happen to the flow: a tap, a callback from the capture, a result from the merge.
public enum ScanEvent: Equatable, Sendable {
    /// Begin scanning the first room.
    case start
    /// The person tapped "Finish room".
    case finishRoom
    /// The room was processed (captured room built, parametric room built). Carries what the name sheet shows.
    case roomFinished(RoomDraft)
    /// The person named the room.
    case named(name: String, kind: RoomKind)
    /// "Scan next room".
    case scanNext
    /// "Finish property": merge and hand over the result.
    case finishProperty
    /// Abandon the room being scanned or processed, or discard the one waiting for a name.
    case cancelRoom
    /// Throw the waiting room away and scan it again.
    case rescanRoom
    /// The merge, export and map are done (with whatever warnings) and the result is ready.
    case mergeCompleted
    /// The merge cannot produce a result at all.
    case mergeFailed(message: String)
    /// Back to the start. Clears finished rooms.
    case reset
}

/// What the controller must do. The reducer never does anything itself.
public enum ScanEffect: Equatable, Sendable {
    /// Start the capture session for a new room.
    case startCapture
    /// Stop the capture session. `keepARSession` is true while more rooms may follow, so the AR
    /// session keeps running and the next room shares its coordinate space.
    case stopCapture(keepARSession: Bool)
    /// Turn the raw scan data that `stopCapture` produced into the captured room and the parametric room.
    case buildRoom
    /// Join the rooms, export the USDZ, fetch the AR world map.
    case mergeStructure
    /// Hand the finished result to the caller.
    case saveResult
}

// MARK: - The flow

/// The multi-room scan flow: a state, the rooms finished so far, and the rules for moving between states.
/// Send it events; run the effects it returns.
public struct ScanFlow: Equatable, Sendable {

    /// A room that has a name and is part of this scan.
    public struct FinishedRoom: Equatable, Sendable, Identifiable {
        public var draft: RoomDraft
        /// The cleaned-up name the person gave: trimmed, single spaces, unique in the property.
        public var name: String
        public var kind: RoomKind
        /// The draft's id, which is the key for everything the controller kept for this room.
        public var id: UUID { draft.id }

        public init(draft: RoomDraft, name: String, kind: RoomKind) {
            self.draft = draft
            self.name = name
            self.kind = kind
        }
    }

    /// The verdict on a typed room name.
    public enum NameCheck: Equatable, Sendable {
        /// Fine. Carries the cleaned-up name (trimmed, single spaces) that will be used.
        case valid(String)
        case empty
        case tooLong(limit: Int)
        /// Already used. `suggestion` is the nearest free name.
        case duplicate(existing: String, suggestion: String)

        /// True for `.valid`.
        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        /// Helper text for under the name field; nil when the name is fine.
        public var message: String? {
            switch self {
            case .valid: return nil
            case .empty: return "Give this room a name."
            case .tooLong(let limit): return "Use \(limit) characters or fewer."
            case .duplicate(let existing, let suggestion):
                return "There is already a room called \u{201C}\(existing)\u{201D}. Try \u{201C}\(suggestion)\u{201D}."
            }
        }
    }

    /// Longest room name accepted.
    public static let maxNameLength = 40

    public private(set) var state: ScanState = .idle
    /// Named rooms, in scan order.
    public private(set) var rooms: [FinishedRoom] = []
    /// Names of rooms the property already has, so a new scan never repeats them.
    public let existingRoomNames: [String]
    /// Pins the suggestion order to apartments or offices. nil works it out from what has been scanned.
    public let style: RoomKindSuggester.Style?

    /// - Parameters:
    ///   - existingRoomNames: Rooms the property already has; their names are never suggested or accepted again.
    ///   - style: Pins the suggestion order. nil works it out from the rooms scanned so far.
    public init(existingRoomNames: [String] = [], style: RoomKindSuggester.Style? = nil) {
        self.existingRoomNames = existingRoomNames
        self.style = style
    }

    // MARK: Questions the interface asks

    /// Zero-based index of the room being scanned or processed; the index the next room will get otherwise.
    public var currentRoomIndex: Int {
        switch state {
        case .scanning(let index), .processingRoom(let index): return index
        default: return rooms.count
        }
    }

    /// The capture session is running.
    public var isCapturing: Bool {
        if case .scanning = state { return true }
        return false
    }

    /// "Finish room" was tapped and the room is being built.
    public var isProcessingRoom: Bool {
        if case .processingRoom = state { return true }
        return false
    }

    /// The draft waiting for a name, if any.
    public var draftAwaitingName: RoomDraft? {
        if case .awaitingName(let draft) = state { return draft }
        return nil
    }

    /// "Finish room" is only offered while the capture is running.
    public var canFinishRoom: Bool { isCapturing }

    /// "Scan next room" is offered between rooms, and after a failed merge.
    public var canScanNext: Bool {
        switch state {
        case .betweenRooms, .failed: return true
        default: return false
        }
    }

    /// "Finish property" needs at least one named room.
    public var canFinishProperty: Bool {
        switch state {
        case .betweenRooms, .failed: return !rooms.isEmpty
        default: return false
        }
    }

    /// Leaving now would throw away scanned work: named rooms, a room waiting for its name, or a room
    /// that is being processed. A room that is still being scanned does not count on its own.
    public var wouldLoseWork: Bool {
        if !rooms.isEmpty { return true }
        switch state {
        case .awaitingName, .processingRoom, .merging: return true
        default: return false
        }
    }

    /// Every name in use: the property's existing rooms plus this scan's.
    public var takenNames: [String] { existingRoomNames + rooms.map(\.name) }

    // MARK: Names

    /// Checks a typed name against the rules: not empty, not too long, not used already
    /// (ignoring case, accents and extra spaces).
    public func validate(name: String) -> NameCheck {
        let cleaned = ScanFlow.cleaned(name)
        if cleaned.isEmpty { return .empty }
        if cleaned.count > ScanFlow.maxNameLength { return .tooLong(limit: ScanFlow.maxNameLength) }
        let key = ScanFlow.key(cleaned)
        if let clash = takenNames.first(where: { ScanFlow.key($0) == key }) {
            return .duplicate(existing: clash, suggestion: RoomKindSuggester.freeName(base: clash, taken: takenNames))
        }
        return .valid(cleaned)
    }

    /// The default name for a room of this kind: "Living Room", then "Bedroom", "Bedroom 2", ...
    public func suggestedName(for kind: RoomKind) -> String {
        RoomKindSuggester.freeName(base: kind.displayName, taken: takenNames)
    }

    /// Every room kind, most likely next first.
    public var suggestedKinds: [RoomKind] {
        RoomKindSuggester.ordered(used: rooms.map(\.kind), existingNames: existingRoomNames, style: style)
    }

    /// The kind to preselect for the next room.
    public var suggestedKind: RoomKind { suggestedKinds.first ?? .other }

    static func cleaned(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func key(_ name: String) -> String {
        cleaned(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Reducer

    /// Applies an event and returns the effects to run. An event that is not allowed in the current
    /// state changes nothing and returns no effects.
    @discardableResult
    public mutating func send(_ event: ScanEvent) -> [ScanEffect] {
        let result = reducing(event)
        self = result.flow
        return result.effects
    }

    /// The pure form of `send`: the flow after the event and the effects to run.
    public func reducing(_ event: ScanEvent) -> (flow: ScanFlow, effects: [ScanEffect]) {
        var next = self
        let effects = next.apply(event)
        return (next, effects)
    }

    private mutating func apply(_ event: ScanEvent) -> [ScanEffect] {
        if event == .reset { return applyReset() }

        switch state {
        case .idle:
            if event == .start {
                state = .scanning(roomIndex: rooms.count)
                return [.startCapture]
            }

        case .scanning(let index):
            switch event {
            case .finishRoom:
                state = .processingRoom(roomIndex: index)
                return [.stopCapture(keepARSession: true), .buildRoom]
            case .roomFinished(let draft):
                // The caller already stopped and processed the capture.
                return accept(draft)
            case .cancelRoom:
                return abandonRoom()
            default:
                break
            }

        case .processingRoom:
            switch event {
            case .roomFinished(let draft):
                return accept(draft)
            case .cancelRoom:
                return abandonRoom()
            default:
                break
            }

        case .awaitingName(let draft):
            switch event {
            case .named(let name, let kind):
                guard case .valid(let cleaned) = validate(name: name) else { return [] }
                rooms.append(FinishedRoom(draft: draft, name: cleaned, kind: kind))
                state = .betweenRooms
                return []
            case .rescanRoom:
                state = .scanning(roomIndex: rooms.count)
                return [.startCapture]
            case .cancelRoom:
                state = rooms.isEmpty ? .idle : .betweenRooms
                return [.stopCapture(keepARSession: !rooms.isEmpty)]
            default:
                break
            }

        case .betweenRooms:
            switch event {
            case .scanNext:
                state = .scanning(roomIndex: rooms.count)
                return [.startCapture]
            case .finishProperty:
                guard !rooms.isEmpty else { return [] }
                state = .merging
                return [.mergeStructure]
            default:
                break
            }

        case .merging:
            switch event {
            case .mergeCompleted:
                state = .finished
                return [.saveResult]
            case .mergeFailed(let message):
                state = .failed(message)
                return []
            default:
                break
            }

        case .finished:
            break

        case .failed:
            switch event {
            case .finishProperty:
                guard !rooms.isEmpty else { return [] }
                state = .merging
                return [.mergeStructure]
            case .scanNext:
                state = .scanning(roomIndex: rooms.count)
                return [.startCapture]
            default:
                break
            }
        }
        return []
    }

    /// A processed room is ready for its name. A draft whose id is already a finished room is ignored.
    private mutating func accept(_ draft: RoomDraft) -> [ScanEffect] {
        guard !rooms.contains(where: { $0.id == draft.id }) else { return [] }
        state = .awaitingName(draft)
        return []
    }

    /// Stop scanning the current room without keeping it. With no finished rooms the scan is over.
    private mutating func abandonRoom() -> [ScanEffect] {
        let keepGoing = !rooms.isEmpty
        state = keepGoing ? .betweenRooms : .idle
        return [.stopCapture(keepARSession: keepGoing)]
    }

    private mutating func applyReset() -> [ScanEffect] {
        let wasRunning: Bool
        switch state {
        case .idle, .finished: wasRunning = false
        default: wasRunning = true
        }
        state = .idle
        rooms = []
        return wasRunning ? [.stopCapture(keepARSession: false)] : []
    }
}

// MARK: - Room kind and name suggestions

/// Which room kind to offer next, and what to call it.
public enum RoomKindSuggester {
    /// Which kind of property decides the order rooms are suggested in.
    public enum Style: String, Equatable, Sendable {
        case apartment, office
    }

    /// The order rooms are usually walked in. A kind that appears twice is expected twice.
    static let apartmentOrder: [RoomKind] = [
        .livingRoom, .kitchen, .dining, .masterBedroom, .bathroom, .bedroom, .bathroom, .bedroom,
        .corridor, .entrance, .balcony, .maidsRoom, .laundry, .storage,
    ]

    static let officeOrder: [RoomKind] = [
        .reception, .office, .meetingRoom, .office, .kitchen, .bathroom, .corridor, .storage,
    ]

    /// Office when an office kind was already scanned, or an existing room name sounds like one.
    public static func inferStyle(used: [RoomKind], existingNames: [String]) -> Style {
        let officeKinds: Set<RoomKind> = [.office, .meetingRoom, .reception]
        if used.contains(where: { officeKinds.contains($0) }) { return .office }
        let words = ["office", "meeting", "reception"]
        let looksLikeOffice = existingNames.contains { name in
            let lowered = name.lowercased()
            return words.contains { lowered.contains($0) }
        }
        return looksLikeOffice ? .office : .apartment
    }

    /// Every kind, the most likely next ones first. Kinds already scanned, and kinds the property's
    /// existing room names point to ("Kitchen", "Bedroom 2"), are crossed off the expected order one for
    /// one, but stay available further down: a flat can have a fifth bedroom.
    public static func ordered(used: [RoomKind], existingNames: [String] = [], style: Style? = nil) -> [RoomKind] {
        let style = style ?? inferStyle(used: used, existingNames: existingNames)
        var remaining = style == .office ? officeOrder : apartmentOrder
        for kind in used + existingNames.compactMap(kind(named:)) {
            if let index = remaining.firstIndex(of: kind) { remaining.remove(at: index) }
        }
        var result: [RoomKind] = []
        for kind in remaining where !result.contains(kind) { result.append(kind) }
        for kind in RoomKind.allCases where kind != .other && !result.contains(kind) { result.append(kind) }
        result.append(.other)
        return result
    }

    /// `base` if it is free, otherwise `base 2`, `base 3`, ... A base that already ends in a number
    /// ("Bedroom 2") counts from its root ("Bedroom"). Comparison ignores case, accents and extra spaces.
    public static func freeName(base: String, taken: [String]) -> String {
        let cleanedBase = ScanFlow.cleaned(base)
        let used = Set(taken.map(ScanFlow.key))
        if !cleanedBase.isEmpty, !used.contains(ScanFlow.key(cleanedBase)) { return cleanedBase }
        let root = rootName(of: cleanedBase.isEmpty ? "Room" : cleanedBase)
        if !used.contains(ScanFlow.key(root)) { return root }
        var number = 2
        while used.contains(ScanFlow.key("\(root) \(number)")) { number += 1 }
        return "\(root) \(number)"
    }

    /// The kind a room name points to: "Kitchen" and "Kitchen 2" are kitchens. nil for any other name.
    static func kind(named name: String) -> RoomKind? {
        let key = ScanFlow.key(rootName(of: ScanFlow.cleaned(name)))
        return RoomKind.allCases.first { $0 != .other && ScanFlow.key($0.displayName) == key }
    }

    /// "Bedroom 2" becomes "Bedroom". A name that is only a number is left alone.
    static func rootName(of name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let last = parts.last, !last.isEmpty,
              last.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
        return parts.dropLast().joined(separator: " ")
    }
}

// MARK: - Live statistics

/// Counts and a rough floor area from the capture so far, for the live metrics pill.
/// Built from the same `RawCapture` the room builder gets, so what the pill says matches what is saved.
public struct LiveScanStats: Equatable, Sendable {
    public var walls: Int
    public var doors: Int
    public var windows: Int
    /// Doorless passages.
    public var openings: Int
    /// Furniture and fixtures.
    public var objects: Int
    /// Square metres; nil until enough is scanned to estimate.
    public var roughFloorAreaM2: Double?

    /// Nothing scanned yet.
    public static let empty = LiveScanStats()

    /// Statistics from plain numbers.
    public init(walls: Int = 0, doors: Int = 0, windows: Int = 0, openings: Int = 0, objects: Int = 0,
                roughFloorAreaM2: Double? = nil) {
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.objects = objects
        self.roughFloorAreaM2 = roughFloorAreaM2
    }

    /// Statistics from a capture, the same one the room builder reads.
    public init(capture: RawCapture) {
        self.init(walls: capture.walls.count, doors: capture.doors.count, windows: capture.windows.count,
                  openings: capture.openings.count, objects: capture.objects.count,
                  roughFloorAreaM2: LiveScanStats.roughArea(of: capture))
    }

    /// A room needs at least three walls.
    public var hasEnoughToFinish: Bool { walls >= 3 }

    /// "6 walls \u{00B7} 1 door \u{00B7} 2 windows \u{00B7} about 14.2 m\u{00B2}"
    public func summary(units: DisplayUnits) -> String {
        var parts = [LiveScanStats.count(walls, "wall"), LiveScanStats.count(doors, "door"),
                     LiveScanStats.count(windows, "window")]
        if let area = areaText(units: units) { parts.append("about " + area) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The same for VoiceOver: no separators, full unit names.
    public func spokenSummary(units: DisplayUnits) -> String {
        var parts = [LiveScanStats.count(walls, "wall"), LiveScanStats.count(doors, "door"),
                     LiveScanStats.count(windows, "window")]
        if let area = roughFloorAreaM2, area.isFinite {
            let digits = UnitFormatter.area(area, unit: units.area, precision: .compact, includeUnit: false)
            let noun = units.area == .squareMetres ? "square metres" : "square feet"
            parts.append("roughly \(digits) \(noun)")
        }
        return parts.joined(separator: ", ")
    }

    /// "14.2 m\u{00B2}", or nil until there is an estimate.
    public func areaText(units: DisplayUnits) -> String? {
        guard let area = roughFloorAreaM2, area.isFinite else { return nil }
        return UnitFormatter.area(area, unit: units.area, precision: .compact)
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    // MARK: Rough area

    /// Best available estimate, in order: the floor polygons RoomPlan reports, the convex hull of the
    /// wall end points, the floor's bounding box. A partial scan gives a low number; an L-shaped room
    /// seen only by its walls gives a high one. It is a progress hint, never a measurement.
    static func roughArea(of capture: RawCapture) -> Double? {
        let polygonArea = capture.floors.reduce(0.0) { sum, floor in
            guard let corners = floor.polygonCorners, corners.count >= 3 else { return sum }
            return sum + polygonArea3D(corners)
        }
        if polygonArea > 0.01, polygonArea.isFinite { return polygonArea }

        if capture.walls.count >= 3 {
            var points: [Point2] = []
            for wall in capture.walls {
                let half = wall.dimensions.x / 2
                points.append(wall.transform.transform(Point3(-half, 0, 0)).plan)
                points.append(wall.transform.transform(Point3(half, 0, 0)).plan)
            }
            let area = Polygon.area(convexHull(points))
            if area > 0.01, area.isFinite { return area }
        }

        let boxArea = capture.floors.reduce(0.0) { $0 + max(0, $1.dimensions.x) * max(0, $1.dimensions.y) }
        return boxArea > 0.01 && boxArea.isFinite ? boxArea : nil
    }

    /// Area of a planar polygon given by 3D points in any orientation (Newell's method).
    static func polygonArea3D(_ points: [Point3]) -> Double {
        guard points.count >= 3 else { return 0 }
        var nx = 0.0, ny = 0.0, nz = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            nx += (a.y - b.y) * (a.z + b.z)
            ny += (a.z - b.z) * (a.x + b.x)
            nz += (a.x - b.x) * (a.y + b.y)
        }
        return 0.5 * (nx * nx + ny * ny + nz * nz).squareRoot()
    }

    /// Convex hull, counter-clockwise (Andrew's monotone chain). Fewer than three distinct points
    /// give the points themselves.
    static func convexHull(_ input: [Point2]) -> [Point2] {
        let sorted = input.filter { $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return sorted }
        func turn(_ o: Point2, _ a: Point2, _ b: Point2) -> Double { (a - o).cross(b - o) }
        var lower: [Point2] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [Point2] = []
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}

// MARK: - Coaching

/// RoomPlan's `RoomCaptureSession.Instruction`, without the framework. The case names match Apple's.
public enum ScanInstruction: String, Equatable, Sendable, CaseIterable {
    case normal, moveCloseToWall, moveAwayFromWall, slowDown, turnOnLight, lowTexture
}

/// What ARKit says about tracking, without the framework.
public enum ScanTrackingIssue: String, Equatable, Sendable, CaseIterable {
    /// Tracking is normal.
    case none
    case initializing
    /// Trying to find the place again after an interruption.
    case relocalizing
    case excessiveMotion
    case insufficientFeatures
    case notAvailable
    /// The system took the camera away (another app, the app in the background).
    case interrupted
}

/// One line of coaching for the glass pill at the top of the scan screen.
public struct ScanCoachMessage: Equatable, Sendable {
    /// How much attention the message needs.
    public enum Level: Int, Equatable, Sendable, Comparable {
        /// Nothing is wrong.
        case info
        /// The person can fix this by changing how they scan.
        case caution
        /// Tracking is lost or paused.
        case critical

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public var text: String
    /// SF Symbol name.
    public var symbol: String
    public var level: Level

    public init(text: String, symbol: String, level: Level) {
        self.text = text
        self.symbol = symbol
        self.level = level
    }
}

/// The words for the coaching pill, as pure functions.
public enum ScanCoach {
    /// The line to show now. Tracking trouble beats RoomPlan's own instruction, which beats "getting ready"
    /// and the general progress hint.
    public static func message(instruction: ScanInstruction, tracking: ScanTrackingIssue,
                               stats: LiveScanStats) -> ScanCoachMessage {
        switch tracking {
        case .interrupted:
            return ScanCoachMessage(text: "Scanning is paused. Come back to the app to carry on.",
                                    symbol: "pause.circle.fill", level: .critical)
        case .relocalizing:
            return ScanCoachMessage(text: "Tracking was lost. Move back to where you were and look at the last wall you scanned.",
                                    symbol: "location.viewfinder", level: .critical)
        case .notAvailable:
            return ScanCoachMessage(text: "Tracking isn\u{2019}t available. Hold still and aim at a well-lit wall.",
                                    symbol: "exclamationmark.triangle.fill", level: .critical)
        case .excessiveMotion:
            return ScanCoachMessage(text: "Slow down. Move the device more slowly.",
                                    symbol: "tortoise.fill", level: .caution)
        case .insufficientFeatures:
            return ScanCoachMessage(text: "Point at walls, corners or furniture.",
                                    symbol: "viewfinder", level: .caution)
        case .initializing, .none:
            break
        }

        switch instruction {
        case .moveCloseToWall:
            return ScanCoachMessage(text: "Move a little closer to the wall", symbol: "arrow.up.left.and.arrow.down.right",
                                    level: .caution)
        case .moveAwayFromWall:
            return ScanCoachMessage(text: "Step back from the wall", symbol: "arrow.down.right.and.arrow.up.left",
                                    level: .caution)
        case .slowDown:
            return ScanCoachMessage(text: "Move slowly along the walls", symbol: "tortoise.fill", level: .caution)
        case .turnOnLight:
            return ScanCoachMessage(text: "Turn on a light", symbol: "lightbulb.fill", level: .caution)
        case .lowTexture:
            return ScanCoachMessage(text: "Aim at the corners", symbol: "viewfinder", level: .caution)
        case .normal:
            // Starting up only matters when RoomPlan has nothing more useful to say.
            if tracking == .initializing {
                return ScanCoachMessage(text: "Getting ready. Move the device slowly.",
                                        symbol: "viewfinder", level: .info)
            }
            return progress(stats)
        }
    }

    /// The line for a screen that uses RoomPlan's own capture view. That view already prints RoomPlan's
    /// instructions ("Move closer to the wall") by itself, so this pill must not say them a second time. It
    /// carries what the view does not: tracking that was lost or paused (RoomPlan's text is about how to
    /// scan, not about ARKit losing its place), and otherwise the next step in this app's own flow.
    ///
    /// Slowing down and low texture are left to RoomPlan's text too: its `slowDown`, `lowTexture` and
    /// `moveCloseToWall` instructions are what ARKit's "excessive motion" and "insufficient features" ask for.
    public static func companionMessage(tracking: ScanTrackingIssue, stats: LiveScanStats) -> ScanCoachMessage {
        switch tracking {
        case .interrupted, .relocalizing, .notAvailable:
            return message(instruction: .normal, tracking: tracking, stats: stats)
        case .initializing, .none, .excessiveMotion, .insufficientFeatures:
            return progress(stats)
        }
    }

    /// The hint when nothing is wrong: what to do next, given how much is scanned.
    public static func progress(_ stats: LiveScanStats) -> ScanCoachMessage {
        switch stats.walls {
        case 0:
            return ScanCoachMessage(text: "Point at a wall, then move slowly along the walls",
                                    symbol: "viewfinder", level: .info)
        case 1...2:
            return ScanCoachMessage(text: "Move slowly along the walls", symbol: "viewfinder", level: .info)
        default:
            return ScanCoachMessage(text: "Go all the way round, then tap Finish room",
                                    symbol: "arrow.clockwise.circle", level: .info)
        }
    }

    /// Decides whether VoiceOver should hear a message. Only trouble is spoken, only when the words
    /// change, and not more often than `minimumInterval` so a flickering instruction is not read out repeatedly.
    public struct Announcer: Equatable, Sendable {
        /// Shortest time between two announcements, seconds.
        public var minimumInterval: TimeInterval
        private var lastText: String?
        private var lastTime: TimeInterval?

        public init(minimumInterval: TimeInterval = 4) {
            self.minimumInterval = minimumInterval
        }

        /// True when `message` should be spoken now. `time` is any monotonic clock in seconds.
        public mutating func shouldAnnounce(_ message: ScanCoachMessage, at time: TimeInterval) -> Bool {
            guard message.level >= .caution else {
                // A calm message resets, so the same trouble is announced again if it comes back.
                lastText = nil
                return false
            }
            if message.text == lastText { return false }
            if let lastTime, time - lastTime < minimumInterval { return false }
            lastText = message.text
            lastTime = time
            return true
        }
    }
}

// MARK: - Throttling live rebuilds

/// Decides when the live overlay may rebuild its room: at most once per `minInterval`, never two at once,
/// and a change that arrives while a build runs (or too soon after one) is built later, not lost.
public struct LiveRebuildThrottle: Equatable, Sendable {
    /// What the caller should do next.
    public enum Decision: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// Start a build now.
        case start
        /// Ask again after this many seconds.
        case wait(TimeInterval)
    }

    /// Shortest time between two builds, seconds.
    public let minInterval: TimeInterval
    private var lastStart: TimeInterval?
    private var inFlight = false
    private var dirty = false

    public init(minInterval: TimeInterval = 0.5) {
        self.minInterval = minInterval
    }

    /// New data arrived.
    public mutating func markDirty() { dirty = true }

    /// What to do at time `now` (any monotonic clock, seconds). `.start` marks a build as running.
    public mutating func next(now: TimeInterval) -> Decision {
        guard dirty, !inFlight else { return .none }
        if let lastStart, now - lastStart < minInterval {
            return .wait(max(0, minInterval - (now - lastStart)))
        }
        inFlight = true
        dirty = false
        lastStart = now
        return .start
    }

    /// The build that `.start` announced is over.
    public mutating func finished() { inFlight = false }

    /// Forget everything, for a new room.
    public mutating func reset() {
        lastStart = nil
        inFlight = false
        dirty = false
    }
}

// MARK: - Merging

/// The steps shown while the rooms are joined into one model.
public enum ScanMergeStep: Int, Equatable, Sendable, CaseIterable {
    case joiningRooms, writingModel, savingMap

    /// The title of the progress screen.
    public static let headline = "Building the 3D model"

    /// What this step is doing, in plain words.
    public var title: String {
        switch self {
        case .joiningRooms: return "Joining the rooms"
        case .writingModel: return "Writing the 3D file"
        case .savingMap: return "Saving the AR map"
        }
    }

    /// 0...1, for a progress ring: how far along when this step starts.
    public var fraction: Double { Double(rawValue) / Double(ScanMergeStep.allCases.count) }

    /// "Step 2 of 3"
    public var position: String { "Step \(rawValue + 1) of \(ScanMergeStep.allCases.count)" }
}

// MARK: - Failures

/// Everything that can go wrong while scanning or merging, with the words to say about it.
/// The app maps RoomPlan's and ARKit's errors onto these.
public enum ScanFailure: Equatable, Sendable {
    case deviceNotSupported
    case deviceTooHot
    case sceneTooLarge
    case trackingFailed
    case notEnoughScanned
    case invalidScanData
    case roomsNotConnected
    case exportFailed
    /// Joining the rooms into one model failed because the floor is too big for RoomPlan to handle.
    case mergeTooLarge
    case cameraUnavailable
    case cameraNotAllowed
    case internalError
    case unknown

    /// The three parts of an alert about this failure.
    public struct Text: Equatable, Sendable {
        public var title: String
        public var message: String
        public var recovery: String
    }

    /// Whether the room being scanned when this happened can still be used if any data came back.
    public var mayKeepPartialRoom: Bool {
        switch self {
        case .sceneTooLarge, .deviceTooHot: return true
        default: return false
        }
    }

    /// What this failure means when it happens while the finished rooms are being joined into one model,
    /// after scanning is over. The scan-time advice ("walk along the walls", "finish this room") no longer
    /// applies then, so every failure is mapped to wording about the joined model: the rooms are saved, the
    /// model is missing. A room that is too big becomes `mergeTooLarge`; rooms from separate sessions stay
    /// `roomsNotConnected`; all else is `exportFailed`.
    public var duringMerge: ScanFailure {
        switch self {
        case .roomsNotConnected, .mergeTooLarge, .exportFailed: return self
        case .sceneTooLarge: return .mergeTooLarge
        default: return .exportFailed
        }
    }

    /// One sentence for `ScanResult.warnings` when the joined model could not be made, in the words of
    /// `duringMerge`: what happened, then that the rooms are saved.
    public var mergeWarning: String {
        let t = duringMerge.text(hasFinishedRooms: true)
        return "\(t.title). \(t.recovery)"
    }

    /// Wording for an alert. `hasFinishedRooms` adds the reassurance that earlier rooms are safe.
    public func text(hasFinishedRooms: Bool) -> Text {
        let safe = hasFinishedRooms ? " Your finished rooms are safe." : ""
        switch self {
        case .deviceNotSupported:
            return Text(title: "This device can\u{2019}t scan rooms",
                        message: "Room scanning needs an iPhone Pro or iPad Pro with a LiDAR sensor.",
                        recovery: "You can still open, check and export saved scans.")
        case .deviceTooHot:
            return Text(title: "The device is too hot",
                        message: "Scanning stopped to let it cool down.",
                        recovery: "Let it cool in the shade for a few minutes, then scan the room again." + safe)
        case .sceneTooLarge:
            return Text(title: "That room was too big to scan in one go",
                        message: "The scan grew larger than the scanner can handle.",
                        recovery: "Finish this room, then scan the rest as a separate room." + safe)
        case .trackingFailed:
            return Text(title: "Tracking failed",
                        message: "The camera lost track of where it was.",
                        recovery: "Go back to the doorway of the last room you scanned and try again." + safe)
        case .notEnoughScanned:
            return Text(title: "Not enough was scanned",
                        message: "The scanner needs to see more of the walls before it can build the room.",
                        recovery: "Walk slowly along the walls, then tap Finish room." + safe)
        case .invalidScanData:
            return Text(title: "The scan couldn\u{2019}t be used",
                        message: "The scanner returned data it could not turn into a room.",
                        recovery: "Scan the room again." + safe)
        case .roomsNotConnected:
            return Text(title: "The rooms don\u{2019}t line up",
                        message: "These rooms were scanned in separate sessions, so they can\u{2019}t be joined into one 3D model.",
                        recovery: "The plans and measurements are saved. Scan the whole floor in one go to get a joined 3D model.")
        case .exportFailed:
            return Text(title: "Couldn\u{2019}t write the 3D model",
                        message: "The 3D file could not be created.",
                        recovery: "Your rooms and measurements are saved without it.")
        case .mergeTooLarge:
            return Text(title: "The floor is too big to join",
                        message: "RoomPlan can\u{2019}t join this many rooms into one 3D model.",
                        recovery: "Your rooms and measurements are saved without a joined model.")
        case .cameraUnavailable:
            return Text(title: "The camera isn\u{2019}t available",
                        message: "Another app may be using the camera, or the sensor stopped responding.",
                        recovery: "Close other apps that use the camera, then try again." + safe)
        case .cameraNotAllowed:
            return Text(title: "Camera access is off",
                        message: "NexaFix Scan needs the camera to measure rooms.",
                        recovery: "Turn on the camera for NexaFix Scan in Settings." + safe)
        case .internalError:
            return Text(title: "The scanner hit a problem",
                        message: "Something went wrong inside the scanner.",
                        recovery: "Try scanning the room again." + safe)
        case .unknown:
            return Text(title: "Scanning stopped",
                        message: "Something unexpected happened.",
                        recovery: "Try again." + safe)
        }
    }
}
