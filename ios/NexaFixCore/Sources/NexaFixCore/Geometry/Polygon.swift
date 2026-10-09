import Foundation

/// Basic polygon maths in plan space. Polygons are arrays of vertices without a repeated closing vertex.
public enum Polygon {
    /// Shoelace area, positive when the vertices run counter-clockwise (plan space, +y up).
    public static func signedArea(_ p: [Point2]) -> Double {
        guard p.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    public static func area(_ p: [Point2]) -> Double { abs(signedArea(p)) }

    public static func perimeter(_ p: [Point2]) -> Double {
        guard p.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 0..<p.count { sum += p[i].distance(to: p[(i + 1) % p.count]) }
        return sum
    }

    public static func isCounterClockwise(_ p: [Point2]) -> Bool { signedArea(p) > 0 }

    /// The same polygon wound counter-clockwise.
    public static func counterClockwise(_ p: [Point2]) -> [Point2] {
        isCounterClockwise(p) ? p : Array(p.reversed())
    }

    /// Area centroid. Falls back to the vertex average for degenerate polygons.
    public static func centroid(_ p: [Point2]) -> Point2 {
        guard !p.isEmpty else { return .zero }
        let a = signedArea(p)
        if abs(a) < 1e-9 {
            let s = p.reduce(Point2.zero, +)
            return s / Double(p.count)
        }
        var cx = 0.0, cy = 0.0
        for i in 0..<p.count {
            let q = p[i], r = p[(i + 1) % p.count]
            let f = q.x * r.y - r.x * q.y
            cx += (q.x + r.x) * f
            cy += (q.y + r.y) * f
        }
        return Point2(cx / (6 * a), cy / (6 * a))
    }

    /// Interior angle in degrees (0..<360) at vertex `i` of a COUNTER-CLOCKWISE polygon.
    /// A square gives 90 everywhere; the inner corner of an L-shape gives 270.
    public static func interiorAngle(_ p: [Point2], at i: Int) -> Double {
        let n = p.count
        guard n >= 3 else { return 0 }
        let cur = p[i]
        let toPrev = p[(i + n - 1) % n] - cur
        let toNext = p[(i + 1) % n] - cur
        var theta = atan2(toNext.cross(toPrev), toNext.dot(toPrev))
        if theta < 0 { theta += 2 * Double.pi }
        return theta * 180 / Double.pi
    }

    /// Is the point inside the polygon (even-odd rule)?
    public static func contains(_ p: [Point2], _ pt: Point2) -> Bool {
        var inside = false
        var j = p.count - 1
        for i in 0..<p.count {
            let a = p[i], b = p[j]
            if (a.y > pt.y) != (b.y > pt.y),
               pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
