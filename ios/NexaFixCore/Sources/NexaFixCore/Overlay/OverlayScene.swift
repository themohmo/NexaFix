import Foundation

// A renderer-neutral description of what to draw on top of the camera image in AR (and in the
// live scan HUD): floating dimension labels, wireframe segments and angle arcs, all in WORLD space.
// `OverlayBuilder` (Core) turns rooms into an `OverlayScene`; the iOS app projects it to the screen
// every frame with ARKit's camera and draws it with SwiftUI. Keeping the scene pure data means the
// content (which numbers appear where) is unit-tested off-device.

/// How trustworthy a number is, which decides its colour.
public enum OverlayState: String, Codable, Hashable, Sendable {
    /// LiDAR value, not yet checked.
    case scanned
    /// Checked with a laser / tape / drawing.
    case verified
    /// Worth a look (e.g. out of square by 1-3 degrees, or a joinery dimension still unchecked).
    case caution
    /// Needs attention (e.g. out of square by more than 3 degrees).
    case critical
    /// Informational (area, room name).
    case neutral
}

public enum OverlayLabelKind: String, Codable, Hashable, Sendable {
    case wallLength, wallHeight, angle, opening, area, ceiling, measurement, live
}

public struct OverlayLabel: Identifiable, Hashable, Sendable {
    /// Stable across rebuilds so the UI can animate/keep selection ("wall:<uuid>:length").
    public var id: String
    public var kind: OverlayLabelKind
    /// Anchor in world space (metres, Y up).
    public var position: Point3
    /// Main text, already formatted in the user's units, e.g. "3245 mm".
    public var title: String
    /// Optional second line, e.g. "\u{00B1}22 mm" or "laser".
    public var subtitle: String?
    public var state: OverlayState
    /// Higher wins when labels overlap on screen.
    public var priority: Int
    public var roomID: UUID?
    /// Opaque id the UI can map back to a measurement target (e.g. a wall id).
    public var targetID: String?

    public init(id: String, kind: OverlayLabelKind, position: Point3, title: String, subtitle: String? = nil,
                state: OverlayState = .scanned, priority: Int = 0, roomID: UUID? = nil, targetID: String? = nil) {
        self.id = id
        self.kind = kind
        self.position = position
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.priority = priority
        self.roomID = roomID
        self.targetID = targetID
    }
}

public enum OverlaySegmentKind: String, Codable, Hashable, Sendable {
    case wallBase, wallTop, wallCorner, dimension, openingEdge, measurement
}

public struct OverlaySegment: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: OverlaySegmentKind
    public var a: Point3
    public var b: Point3
    public var state: OverlayState

    public init(id: String, kind: OverlaySegmentKind, a: Point3, b: Point3, state: OverlayState = .neutral) {
        self.id = id
        self.kind = kind
        self.a = a
        self.b = b
        self.state = state
    }
}

/// An interior-angle arc lying in a horizontal plane at `center.y`.
public struct OverlayArc: Identifiable, Hashable, Sendable {
    public var id: String
    public var center: Point3
    public var radius: Double
    /// Plan-space direction (degrees, counter-clockwise from plan +x) where the arc starts.
    public var startAngle: Double
    /// Counter-clockwise sweep in degrees (the interior angle).
    public var sweep: Double
    public var state: OverlayState

    public init(id: String, center: Point3, radius: Double, startAngle: Double, sweep: Double,
                state: OverlayState = .neutral) {
        self.id = id
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.sweep = sweep
        self.state = state
    }
}

public struct OverlayScene: Sendable {
    public var labels: [OverlayLabel]
    public var segments: [OverlaySegment]
    public var arcs: [OverlayArc]

    public init(labels: [OverlayLabel] = [], segments: [OverlaySegment] = [], arcs: [OverlayArc] = []) {
        self.labels = labels
        self.segments = segments
        self.arcs = arcs
    }

    public static let empty = OverlayScene()
    public var isEmpty: Bool { labels.isEmpty && segments.isEmpty && arcs.isEmpty }
}

/// What to include. `review` is for walking a saved room; `live` is the lighter set shown while scanning.
public struct OverlayOptions: Hashable, Sendable {
    public var showWireframe: Bool
    public var showDimensions: Bool
    public var showAngles: Bool
    public var showOpenings: Bool
    public var showHeights: Bool
    public var showArea: Bool

    public init(showWireframe: Bool = true, showDimensions: Bool = true, showAngles: Bool = true,
                showOpenings: Bool = true, showHeights: Bool = true, showArea: Bool = true) {
        self.showWireframe = showWireframe
        self.showDimensions = showDimensions
        self.showAngles = showAngles
        self.showOpenings = showOpenings
        self.showHeights = showHeights
        self.showArea = showArea
    }

    public static let review = OverlayOptions()
    public static let live = OverlayOptions(showWireframe: true, showDimensions: true, showAngles: false,
                                            showOpenings: false, showHeights: false, showArea: true)
}
