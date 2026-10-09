import Foundation

// Pure maths for the AR tape measure: the numbers between two points, snapping a raycast hit to the
// nearest known corner, and the little state machine that turns taps into a measurement. The app layer
// supplies world-space points (from an ARKit raycast) and draws the result; nothing here touches ARKit.

/// The numbers between two world-space points. World space is metres, Y up.
public struct TapeReading: Hashable, Sendable {
    /// Straight-line distance, metres.
    public var lengthM: Double
    /// Signed differences b - a along world X, Y (up) and Z, metres.
    public var deltaX: Double
    public var deltaY: Double
    public var deltaZ: Double
    /// Distance in the horizontal plane, metres.
    public var horizontalM: Double
    /// Height difference, metres, always positive.
    public var verticalM: Double
    /// Angle of the line above or below horizontal, degrees, 0...90.
    public var slopeDegrees: Double

    public init(lengthM: Double, deltaX: Double, deltaY: Double, deltaZ: Double,
                horizontalM: Double, verticalM: Double, slopeDegrees: Double) {
        self.lengthM = lengthM
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.deltaZ = deltaZ
        self.horizontalM = horizontalM
        self.verticalM = verticalM
        self.slopeDegrees = slopeDegrees
    }
}

/// A point the tape can snap to. This is the tape's own type so Core's snapping helper does not depend on
/// how rooms describe their snap points; the app maps whatever it has onto this.
public struct TapeSnapCandidate: Hashable, Sendable {
    public var id: String
    /// World-space position, metres.
    public var position: Point3
    /// Plain-language name, e.g. "Corner of Wall A".
    public var label: String

    public init(id: String, position: Point3, label: String = "") {
        self.id = id
        self.position = position
        self.label = label
    }
}

/// The outcome of trying to snap a point.
public struct TapeSnap: Hashable, Sendable {
    /// Where the measurement point should go: the candidate's position when snapped, else the input.
    public var point: Point3
    /// The candidate snapped to, if any.
    public var candidate: TapeSnapCandidate?
    /// Distance from the input to the candidate, metres (nil when not snapped).
    public var distance: Double?

    public var didSnap: Bool { candidate != nil }

    public init(point: Point3, candidate: TapeSnapCandidate? = nil, distance: Double? = nil) {
        self.point = point
        self.candidate = candidate
        self.distance = distance
    }
}

public enum TapeMeasure {
    /// Default reach of snapping, metres.
    public static let defaultSnapRadius = 0.06

    /// Distances and angle between two points. Non-finite input gives an all-zero reading.
    public static func reading(from a: Point3, to b: Point3) -> TapeReading {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        guard dx.isFinite, dy.isFinite, dz.isFinite else {
            return TapeReading(lengthM: 0, deltaX: 0, deltaY: 0, deltaZ: 0, horizontalM: 0, verticalM: 0, slopeDegrees: 0)
        }
        let horizontal = (dx * dx + dz * dz).squareRoot()
        let length = (dx * dx + dy * dy + dz * dz).squareRoot()
        let vertical = abs(dy)
        let slope = (horizontal > 0 || vertical > 0) ? atan2(vertical, horizontal) * 180 / Double.pi : 0
        return TapeReading(lengthM: length, deltaX: dx, deltaY: dy, deltaZ: dz,
                           horizontalM: horizontal, verticalM: vertical, slopeDegrees: slope)
    }

    /// Round to the nearest millimetre. For display only: keep full precision for storage and maths.
    public static func quantise(_ metres: Double) -> Double {
        guard metres.isFinite else { return 0 }
        let mm = (metres * 1000).rounded()
        return (mm == 0 ? 0 : mm) / 1000
    }

    /// The nearest candidate within `radius` metres of `point` (ties go to the smaller id).
    public static func snap(_ point: Point3, to candidates: [TapeSnapCandidate],
                            radius: Double = defaultSnapRadius) -> TapeSnap {
        guard radius > 0, point.x.isFinite, point.y.isFinite, point.z.isFinite else { return TapeSnap(point: point) }
        var best: TapeSnapCandidate?
        var bestDistance = Double.greatestFiniteMagnitude
        for c in candidates {
            let d = point.distance(to: c.position)
            guard d.isFinite, d <= radius else { continue }
            if d < bestDistance - 1e-12 || (abs(d - bestDistance) <= 1e-12 && c.id < (best?.id ?? "")) {
                best = c
                bestDistance = d
            }
        }
        guard let hit = best else { return TapeSnap(point: point) }
        return TapeSnap(point: hit.position, candidate: hit, distance: bestDistance)
    }

    /// Snap to bare points when there is nothing to name.
    public static func snap(_ point: Point3, toPoints points: [Point3], radius: Double = defaultSnapRadius) -> TapeSnap {
        let candidates = points.enumerated().map { TapeSnapCandidate(id: String(format: "%08d", $0.offset), position: $0.element) }
        return snap(point, to: candidates, radius: radius)
    }
}

/// Remembers which candidate the reticle is snapped to so a haptic fires once when a snap ENGAGES
/// (or jumps to a different corner), not on every frame it stays snapped.
public struct TapeSnapTracker: Hashable, Sendable {
    public private(set) var currentID: String?

    public init() {}

    /// Feed the latest snap. Returns true exactly when a new snap has just engaged.
    public mutating func update(_ snap: TapeSnap) -> Bool {
        let newID = snap.candidate?.id
        let engaged = newID != nil && newID != currentID
        currentID = newID
        return engaged
    }

    public mutating func reset() { currentID = nil }
}

// MARK: - Measurement session

/// Two points and what to do with a tap: first tap sets A, second sets B, a third starts over at A.
public struct TapeMeasureSession: Hashable, Sendable {
    public private(set) var first: Point3?
    public private(set) var second: Point3?

    public init() {}

    public var isEmpty: Bool { first == nil }
    public var isComplete: Bool { first != nil && second != nil }

    public var reading: TapeReading? {
        guard let a = first, let b = second else { return nil }
        return TapeMeasure.reading(from: a, to: b)
    }

    /// Both points, in order, when the measurement is complete.
    public var points: (Point3, Point3)? {
        guard let a = first, let b = second else { return nil }
        return (a, b)
    }

    public mutating func addPoint(_ p: Point3) {
        guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return }
        if first == nil || isComplete {
            first = p
            second = nil
        } else {
            second = p
        }
    }

    public mutating func clear() {
        first = nil
        second = nil
    }

    /// What to draw for the measurement in progress: a dot at A, then a line with its length once B exists.
    public func overlay(units: DisplayUnits) -> OverlayScene {
        guard let a = first else { return .empty }
        guard let b = second else {
            return OverlayScene(segments: [OverlaySegment(id: "tape:live:line", kind: .measurement, a: a, b: a, state: .scanned)])
        }
        let r = TapeMeasure.reading(from: a, to: b)
        let mid = (a + b) / 2
        let label = OverlayLabel(
            id: "tape:live:label", kind: .live, position: Point3(mid.x, mid.y, mid.z),
            title: UnitFormatter.length(TapeMeasure.quantise(r.lengthM), unit: units.length, precision: .precise),
            subtitle: nil, state: .scanned, priority: OverlayPriority.measurement + OverlayPriority.highlightBonus)
        return OverlayScene(labels: [label],
                            segments: [OverlaySegment(id: "tape:live:line", kind: .measurement, a: a, b: b, state: .scanned)])
    }
}

// MARK: - Coordinate-frame guard

/// A tape measurement that knows whether its points can be stored on a room.
///
/// A saved measurement lives in the room's coordinate frame, which is the frame of the scan session. A live AR
/// session shares that frame only after it has relocalised against the scan's world map. Before that, and
/// again after a restart, ARKit measures in a throwaway frame of its own, and the frame jumps the moment the
/// session lines up. Points from the two frames must never meet in one measurement or on one room, so one
/// invariant holds at all times: every point on the table was placed under the CURRENT alignment state.
/// - A measurement can be saved only while the session is lined up.
/// - Whenever the session lines up, loses its place or restarts, the points on the table are dropped,
///   because the world they were measured in is no longer the world the camera sees.
///
/// Pure value logic, so the rule is unit-tested off-device; the app only feeds it events.
public struct AlignedTapeMeasure: Hashable, Sendable {
    /// Why the points on the table were dropped.
    public enum Reset: Hashable, Sendable {
        /// The session just lined up with the scan, so its frame changed.
        case linedUp
        /// The session lost its place (interrupted, tracking lost).
        case lostPlace
        /// The AR session was restarted.
        case restarted
    }

    /// The points and the arithmetic on them.
    public private(set) var session = TapeMeasureSession()
    /// The AR session currently shares the scan's coordinate frame.
    public private(set) var isAligned: Bool

    public init(isAligned: Bool = false) {
        self.isAligned = isAligned
    }

    /// Both points are in the room's frame and the session still shares it: safe to store on a room.
    /// (Points placed before the session lined up never survive the line-up, see `setAligned`.)
    public var canSave: Bool { session.isComplete && isAligned }

    /// Places a point in the session's current frame. A third point starts a new measurement. Non-finite
    /// points are ignored.
    public mutating func addPoint(_ p: Point3) {
        session.addPoint(p)
    }

    /// Reports whether the session is lined up with the scan. When that changes while there are points on the
    /// table they are dropped, and the reason is returned so the screen can say so.
    @discardableResult
    public mutating func setAligned(_ aligned: Bool) -> Reset? {
        guard aligned != isAligned else { return nil }
        isAligned = aligned
        guard !session.isEmpty else { return nil }
        session.clear()
        return aligned ? .linedUp : .lostPlace
    }

    /// The AR session was restarted: it starts again in a frame of its own, not lined up.
    @discardableResult
    public mutating func sessionRestarted() -> Reset? {
        isAligned = false
        guard !session.isEmpty else { return nil }
        session.clear()
        return .restarted
    }

    /// Drops the points. The alignment state is unchanged.
    public mutating func clear() {
        session.clear()
    }
}

// MARK: - Readout text

/// The strings in the glass readout after two points are placed. Everything is formatted in the user's
/// units, so the view only lays it out.
public struct TapeReadout: Hashable, Sendable {
    public var length: String
    public var deltaX: String
    public var deltaY: String
    public var deltaZ: String
    public var horizontal: String
    public var vertical: String
    public var slope: String

    /// A sentence for VoiceOver.
    public var spoken: String

    public init(_ reading: TapeReading, units: DisplayUnits) {
        func plain(_ m: Double) -> String {
            UnitFormatter.length(TapeMeasure.quantise(m), unit: units.length, precision: .precise)
        }
        func signed(_ m: Double) -> String {
            UnitFormatter.signedLength(TapeMeasure.quantise(m), unit: units.length, precision: .precise)
        }
        length = plain(reading.lengthM)
        deltaX = signed(reading.deltaX)
        deltaY = signed(reading.deltaY)
        deltaZ = signed(reading.deltaZ)
        horizontal = plain(reading.horizontalM)
        vertical = plain(reading.verticalM)
        slope = UnitFormatter.angle(reading.slopeDegrees, decimals: 1)
        spoken = "Measured length " + OverlaySpokenText.expand(length, isOpening: false)
            + ", horizontal " + OverlaySpokenText.expand(horizontal, isOpening: false)
            + ", vertical " + OverlaySpokenText.expand(vertical, isOpening: false)
            + ", scanned, not checked"
    }
}

// MARK: - Which room does a measurement belong to?

public enum TapeRoomLocator {
    /// The room to store a saved measurement in: the focused room if there is one, else the first room
    /// whose outline contains the midpoint of the points (then any of the points), else the first room.
    public static func roomID(forPoints points: [Point3], in rooms: [Room], focusRoomID: UUID?) -> UUID? {
        if let focus = focusRoomID, rooms.contains(where: { $0.id == focus }) { return focus }
        guard !rooms.isEmpty else { return nil }
        let plan = points.map(\.plan).filter { $0.x.isFinite && $0.y.isFinite }
        if !plan.isEmpty {
            let mid = plan.reduce(Point2.zero, +) / Double(plan.count)
            if let room = rooms.first(where: { $0.walls.count >= 3 && Polygon.contains($0.outline, mid) }) { return room.id }
            for p in plan {
                if let room = rooms.first(where: { $0.walls.count >= 3 && Polygon.contains($0.outline, p) }) { return room.id }
            }
        }
        return rooms[0].id
    }
}
