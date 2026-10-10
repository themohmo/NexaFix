import Foundation

// One vector description of a floor plan, drawn by three renderers: the in-app SwiftUI Canvas,
// the PDF writer and the DXF writer. All geometry is in plan space, METRES at model scale
// (1:1 real-world size). Renderers apply their own scale. Text heights are also in model-space
// metres: the builder converts "2.5 mm on paper at 1:50" into 0.125 m.

public struct DrawColor: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    public static let black = DrawColor(0, 0, 0)
    public static let white = DrawColor(1, 1, 1)
}

/// Stroke style. `weight` is the line width ON PAPER in millimetres.
public struct DrawStroke: Codable, Hashable, Sendable {
    public var weight: Double
    public var color: DrawColor
    public var dashed: Bool
    public init(weight: Double = 0.25, color: DrawColor = .black, dashed: Bool = false) {
        self.weight = weight
        self.color = color
        self.dashed = dashed
    }
}

public enum TextAnchor: String, Codable, Sendable {
    case left, center, right
}

public enum PlanLayer: String, Codable, CaseIterable, Sendable {
    case walls = "NF-WALLS"
    case wallsOpen = "NF-WALLS-OPEN"
    case doors = "NF-DOORS"
    case windows = "NF-WINDOWS"
    case openings = "NF-OPENINGS"
    case furniture = "NF-FURNITURE"
    case dimensions = "NF-DIMENSIONS"
    case angles = "NF-ANGLES"
    case roomLabels = "NF-ROOM-LABELS"
    case notes = "NF-NOTES"
}

public enum DrawingPrimitive: Hashable, Sendable {
    case line(Point2, Point2, DrawStroke)
    /// Optionally closed and filled. `fill` nil = outline only.
    case polyline([Point2], closed: Bool, stroke: DrawStroke?, fill: DrawColor?)
    /// Counter-clockwise arc from `startAngle` to `endAngle`, degrees from plan +x.
    case arc(center: Point2, radius: Double, startAngle: Double, endAngle: Double, DrawStroke)
    case circle(center: Point2, radius: Double, DrawStroke)
    /// `height` is the cap height in model-space metres; `rotation` is degrees counter-clockwise.
    /// `bold` asks for the bold face where the renderer has one.
    case text(String, at: Point2, height: Double, rotation: Double, anchor: TextAnchor, color: DrawColor, bold: Bool)
}

public struct LayeredPrimitive: Hashable, Sendable {
    public var layer: PlanLayer
    public var primitive: DrawingPrimitive
    public init(_ layer: PlanLayer, _ primitive: DrawingPrimitive) {
        self.layer = layer
        self.primitive = primitive
    }
}

/// Options that decide what a plan shows. `scale` is the denominator (50 = 1:50).
public struct PlanOptions: Codable, Hashable, Sendable {
    public var scale: Double
    public var units: DisplayUnits
    public var showDimensions: Bool
    public var showAngles: Bool
    public var showFurniture: Bool
    public var showRoomLabels: Bool
    public var showOpeningSizes: Bool
    /// Mark dimensions that were laser-verified (e.g. a trailing "v") so a printed plan shows what is checked.
    public var markVerified: Bool

    public init(scale: Double = 50, units: DisplayUnits = .default, showDimensions: Bool = true,
                showAngles: Bool = true, showFurniture: Bool = true, showRoomLabels: Bool = true,
                showOpeningSizes: Bool = true, markVerified: Bool = true) {
        self.scale = scale
        self.units = units
        self.showDimensions = showDimensions
        self.showAngles = showAngles
        self.showFurniture = showFurniture
        self.showRoomLabels = showRoomLabels
        self.showOpeningSizes = showOpeningSizes
        self.markVerified = markVerified
    }
}

/// A finished plan: primitives in model-space metres plus the extent they cover.
public struct PlanDrawing: Sendable {
    public var primitives: [LayeredPrimitive]
    /// Extent of everything drawn, plan space metres.
    public var bounds: Bounds2
    public var options: PlanOptions
    public var title: String
    public var subtitle: String

    public init(primitives: [LayeredPrimitive], bounds: Bounds2, options: PlanOptions,
                title: String = "", subtitle: String = "") {
        self.primitives = primitives
        self.bounds = bounds
        self.options = options
        self.title = title
        self.subtitle = subtitle
    }
}
