import Foundation

public extension Polygon {
    /// Split a simple polygon into triangles by ear clipping, for floor and ceiling meshes in the 3D viewer.
    ///
    /// Returns index triples into `p`. Every triple is counter-clockwise in plan space (positive
    /// area) whichever way `p` winds, the triangles do not overlap, and their areas add up to
    /// `Polygon.area(p)`. Concave shapes (L, U, T, combs) work.
    ///
    /// - A simple polygon with `n` vertices gives `n - 2` triangles that use every vertex, so
    ///   the mesh has no T-junctions. That includes vertices on a straight edge (180 degrees).
    ///   Only vertices that carry no area at all (repeated points and zero-width spikes) can be
    ///   left out, which gives fewer triangles.
    /// - Returns `[]`, without trapping, for fewer than 3 vertices, non-finite coordinates,
    ///   zero area, edges that cross each other, or anything the clipper cannot finish.
    ///
    /// Cost is roughly quadratic in the vertex count for ordinary outlines (a 2000-vertex polygon
    /// takes about half a second in a debug build) and cubic only for contrived shapes; room
    /// outlines have tens of vertices.
    static func triangulate(_ p: [Point2]) -> [[Int]] {
        let n = p.count
        guard n >= 3 else { return [] }
        for q in p where !(q.x.isFinite && q.y.isFinite) { return [] }

        guard let bounds = Bounds2(points: p) else { return [] }
        let extent = max(bounds.width, bounds.height)
        guard extent > 0 else { return [] }
        // Shoelace relative to the first vertex, so far-from-origin coordinates do not lose digits.
        var area = 0.0
        for i in 1..<(n - 1) { area += (p[i] - p[0]).cross(p[i + 1] - p[0]) }
        area /= 2
        let areaTolerance = 1e-12 * extent * extent
        guard abs(area) > areaTolerance else { return [] }
        if TriangulationMath.hasProperCrossing(p, tolerance: areaTolerance) { return [] }

        // Work counter-clockwise; indices always refer to the caller's array.
        var work = Array(0..<n)
        if area < 0 { work.reverse() }
        // Repeated points and zero-width spikes carry no area and only confuse the ear test.
        work = TriangulationMath.removingZeroAreaSlivers(p, work, tolerance: 1e-12 * extent)
        guard work.count >= 3 else { return [] }

        var triangles: [[Int]] = []
        triangles.reserveCapacity(n - 2)

        while work.count > 3 {
            // First look for an ear with nothing on or inside its triangle; accept a vertex that
            // only touches the triangle's edge if none exists.
            var ear: Int?
            search: for strict in [true, false] {
                for k in work.indices where TriangulationMath.isEar(p, work, k, strict: strict,
                                                                     tolerance: areaTolerance) {
                    ear = k
                    break search
                }
            }
            if let k = ear {
                let m = work.count
                triangles.append([work[(k + m - 1) % m], work[k], work[(k + 1) % m]])
                work.remove(at: k)
                continue
            }
            // No ear: what is left may be only zero-area slivers (repeated points, spikes).
            guard let k = work.indices.first(where: { TriangulationMath.isDegenerate(p, work, $0) }) else {
                return []
            }
            work.remove(at: k)
        }
        if work.count == 3 {
            let a = p[work[0]], b = p[work[1]], c = p[work[2]]
            if (b - a).cross(c - a) > areaTolerance { triangles.append(work) }
        }

        // Last line of defence for inputs that are not simple polygons (touching or overlapping
        // edges): the pieces must add up to the polygon, otherwise report failure.
        var covered = 0.0
        for t in triangles { covered += 0.5 * (p[t[1]] - p[t[0]]).cross(p[t[2]] - p[t[0]]) }
        guard abs(covered - abs(area)) <= 1e-9 * extent * extent else { return [] }
        return triangles
    }
}

/// Helpers for `Polygon.triangulate`.
enum TriangulationMath {
    /// The loop without vertices that repeat their predecessor's position and without spike tips
    /// (the polygon turns back along the edge it arrived by). Neither carries any area.
    static func removingZeroAreaSlivers(_ p: [Point2], _ loop: [Int], tolerance: Double) -> [Int] {
        var out = loop
        var changed = true
        while changed && out.count > 3 {
            changed = false
            var i = 0
            while i < out.count && out.count > 3 {
                let m = out.count
                let a = p[out[(i + m - 1) % m]], b = p[out[i]], c = p[out[(i + 1) % m]]
                let u = b - a, v = c - b
                let repeated = u.length <= tolerance
                let spike = abs(u.cross(v)) <= 1e-9 * u.length * v.length && u.dot(v) < 0
                if repeated || spike {
                    out.remove(at: i)
                    changed = true
                } else {
                    i += 1
                }
            }
        }
        return out
    }

    /// Vertex `k` of the working loop sits on the straight line through its neighbours
    /// (or repeats one of them): its triangle has no area.
    static func isDegenerate(_ p: [Point2], _ loop: [Int], _ k: Int) -> Bool {
        let m = loop.count
        let a = p[loop[(k + m - 1) % m]], b = p[loop[k]], c = p[loop[(k + 1) % m]]
        let u = b - a, v = c - b
        return abs(u.cross(v)) <= 1e-9 * u.length * v.length
    }

    /// Is vertex `k` of the counter-clockwise working loop an ear? It must turn left by more than
    /// rounding noise, and no other vertex may lie inside the triangle with its neighbours
    /// (strict: or on its edges).
    static func isEar(_ p: [Point2], _ loop: [Int], _ k: Int, strict: Bool, tolerance t: Double) -> Bool {
        let m = loop.count
        let ia = (k + m - 1) % m, ic = (k + 1) % m
        let a = p[loop[ia]], b = p[loop[k]], c = p[loop[ic]]
        let u = b - a, w = c - b
        guard u.cross(w) > 1e-9 * u.length * w.length else { return false }
        for j in 0..<m where j != ia && j != k && j != ic {
            let v = p[loop[j]]
            if v == a || v == b || v == c { continue }   // a pinched or repeated vertex, not an intruder
            let d1 = (b - a).cross(v - a)
            let d2 = (c - b).cross(v - b)
            let d3 = (a - c).cross(v - c)
            let blocked = strict ? (d1 >= -t && d2 >= -t && d3 >= -t) : (d1 > t && d2 > t && d3 > t)
            if blocked { return false }
        }
        return true
    }

    /// Do two non-adjacent edges cross at a point interior to both? (Touching is allowed.)
    static func hasProperCrossing(_ p: [Point2], tolerance t: Double) -> Bool {
        let n = p.count
        func side(_ a: Point2, _ b: Point2, _ c: Point2) -> Int {
            let s = (b - a).cross(c - a)
            return s > t ? 1 : (s < -t ? -1 : 0)
        }
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n]
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                let c = p[j], d = p[(j + 1) % n]
                let s1 = side(a, b, c), s2 = side(a, b, d)
                let s3 = side(c, d, a), s4 = side(c, d, b)
                if s1 * s2 < 0 && s3 * s4 < 0 { return true }
            }
        }
        return false
    }
}
