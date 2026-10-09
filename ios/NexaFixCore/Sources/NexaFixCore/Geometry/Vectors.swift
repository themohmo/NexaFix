import Foundation

// MARK: - Coordinate conventions
//
// World (ARKit / RoomPlan): right-handed, Y up, units metres.
// Plan (floor plans, DXF, PDF): x = world X, y = -world Z, so the plan reads like a
// top-down view with +y "up the page" and counter-clockwise polygons have positive area.
// Elevation is world Y relative to the room's floor.
//
// Every length stored in the model is in METRES and every angle in DEGREES unless the
// name says otherwise (`yaw` is radians). Display units are a presentation concern only.

/// A point or vector in plan space (metres).
public struct Point2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = Point2(0, 0)

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(a.x * s, a.y * s) }
    public static func / (a: Point2, s: Double) -> Point2 { Point2(a.x / s, a.y / s) }
    public static prefix func - (a: Point2) -> Point2 { Point2(-a.x, -a.y) }

    public var length: Double { (x * x + y * y).squareRoot() }
    public func dot(_ o: Point2) -> Double { x * o.x + y * o.y }
    /// z component of the 3D cross product; positive when `o` is counter-clockwise from `self`.
    public func cross(_ o: Point2) -> Double { x * o.y - y * o.x }
    public func distance(to o: Point2) -> Double { (self - o).length }
    public var normalized: Point2 { let l = length; return l > 1e-12 ? self / l : .zero }
    /// This vector rotated 90 degrees counter-clockwise.
    public var perpendicularCCW: Point2 { Point2(-y, x) }
    /// Direction of the vector in radians, counter-clockwise from +x.
    public var angle: Double { atan2(y, x) }

    public func rotated(by radians: Double) -> Point2 {
        let c = cos(radians), s = sin(radians)
        return Point2(x * c - y * s, x * s + y * c)
    }

    public func lerp(to o: Point2, t: Double) -> Point2 { self + (o - self) * t }

    /// Lift to world space at the given elevation (world Y).
    public func world(elevation: Double = 0) -> Point3 { Point3(x, elevation, -y) }
}

/// A point or vector in world space (metres, Y up).
public struct Point3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }

    public static let zero = Point3(0, 0, 0)

    public static func + (a: Point3, b: Point3) -> Point3 { Point3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Point3, b: Point3) -> Point3 { Point3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Point3, s: Double) -> Point3 { Point3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: Point3, s: Double) -> Point3 { Point3(a.x / s, a.y / s, a.z / s) }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public func dot(_ o: Point3) -> Double { x * o.x + y * o.y + z * o.z }
    public func distance(to o: Point3) -> Double { (self - o).length }

    /// Projection onto the floor plan (drops elevation).
    public var plan: Point2 { Point2(x, -z) }
}

/// Axis-aligned bounds in plan space.
public struct Bounds2: Codable, Hashable, Sendable {
    public var min: Point2
    public var max: Point2

    public init(min: Point2, max: Point2) { self.min = min; self.max = max }

    public init?(points: [Point2]) {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = Point2(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y))
            hi = Point2(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y))
        }
        self.min = lo
        self.max = hi
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var center: Point2 { Point2((min.x + max.x) / 2, (min.y + max.y) / 2) }

    public func union(_ o: Bounds2) -> Bounds2 {
        Bounds2(min: Point2(Swift.min(min.x, o.min.x), Swift.min(min.y, o.min.y)),
                max: Point2(Swift.max(max.x, o.max.x), Swift.max(max.y, o.max.y)))
    }

    public func inset(by d: Double) -> Bounds2 {
        Bounds2(min: Point2(min.x + d, min.y + d), max: Point2(max.x - d, max.y - d))
    }
}
