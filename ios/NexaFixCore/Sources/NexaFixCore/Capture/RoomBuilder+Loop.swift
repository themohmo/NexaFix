import Foundation

// Boundary-loop reconstruction for `RoomBuilder`: merge collinear pieces, build a graph of wall
// ends, search for the closed loop that explains the most wall with the least repair, and fall
// back to the floor polygon / convex hull when no loop exists.
//
// Model. Every wall segment gives two DIRECTED nodes (a -> b and b -> a). A directed edge u -> v
// means "walking along wall u, you can turn onto wall v": either the two wall LINES meet at a
// point close to u's end and v's start (gap up to `snapTolerance`, overshoot up to
// `maxCornerOvershoot`), or the two ends are within `snapTolerance` (midpoint corner), or both
// ends are "free" (nothing touches them) and a virtual wall can bridge them. A room boundary is a
// simple cycle in this graph. The search (`LoopSearch`) enumerates cycles with a bounded
// depth-first search, scores each as
//
//     cost = 4 * (corner gaps healed) + 3 * (overshoot trimmed) + 3 * (bridged length)
//          + 1 * (length of wall left out)
//
// and keeps the cheapest; equal-cost loops are separated by the larger enclosed area (so an
// interior partition never shrinks the room). Cycles must be simple polygons.

extension RoomBuilder {

    // MARK: Types

    /// One edge of the reconstructed loop before it becomes a `Wall`.
    struct LoopWall {
        var start: Point2
        var end: Point2
        /// Index into the merged segment array; nil for a virtual (bridge) wall.
        var segment: Int?
    }

    struct LoopOutcome {
        var walls: [LoopWall]
        var droppedSegments: [Int]
        var gapsClosed: Int
        var maxGap: Double
        var wallsTrimmed: Int
        var maxTrim: Double
    }

    /// What `findLoop` found, and whether it had to stop early.
    struct LoopSearchResult {
        var outcome: LoopOutcome?
        var budgetExhausted: Bool
    }

    struct DirectedNode {
        var segment: Int
        var p0: Point2
        var p1: Point2
        /// Unit vector p0 -> p1.
        var dir: Point2
    }

    struct LoopEdge {
        var to: Int
        /// Corner point shared by the two walls; nil for a bridge (virtual wall) edge.
        var corner: Point2?
        var cost: Double
        /// Largest gap healed at this corner (metres).
        var shortfall: Double
        /// Largest overshoot trimmed at this corner (metres).
        var overshoot: Double
        var isBridge: Bool { corner == nil }
    }

    static let gapCostPerMetre = 4.0
    static let overshootCostPerMetre = 3.0
    static let bridgeCostPerMetre = 3.0
    static let dropCostPerMetre = 1.0
    /// Equal-cost band inside which the larger enclosed area wins.
    static let costTieBand = 0.01
    static let searchSegmentCap = 400
    /// A free wall end may bridge to its nearest few free ends only.
    static let maxBridgeCandidates = 3
    /// A loop may need a bridge at every corner of a badly scanned room, but not at every wall of a big one.
    static let maxBridgesPerLoop = 8
    /// Slack on tolerance comparisons so a gap of exactly `snapTolerance` is not lost to rounding.
    static let epsilon = 1e-9

    // MARK: Collinear merge

    struct MergeResult {
        var segments: [Segment]
        var piecesMerged: Int
        var wallsFormed: Int
    }

    /// Merge pieces of one physical wall. Input must be sorted by id (as `extractSegments` returns).
    static func mergeCollinear(_ input: [Segment], options: Options) -> MergeResult {
        let n = input.count
        guard n > 1 else { return MergeResult(segments: input, piecesMerged: 0, wallsFormed: 0) }
        let sinTol = sin(options.collinearToleranceDegrees * Double.pi / 180)

        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            var c = i
            while parent[c] != r { let nx = parent[c]; parent[c] = r; c = nx }
            return r
        }
        for i in 0..<n {
            for j in (i + 1)..<n where canMerge(input[i], input[j], sinTol: sinTol, options: options) {
                let ri = find(i), rj = find(j)
                if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for i in 0..<n { clusters[find(i), default: []].append(i) }
        var merged: [Segment] = []
        var piecesMerged = 0, wallsFormed = 0
        for root in clusters.keys.sorted() {
            let members = (clusters[root] ?? []).map { input[$0] }
            if members.count > 1 { piecesMerged += members.count; wallsFormed += 1 }
            merged.append(combine(members))
        }
        merged.sort { $0.id.uuidString < $1.id.uuidString }
        return MergeResult(segments: merged, piecesMerged: piecesMerged, wallsFormed: wallsFormed)
    }

    private static func canMerge(_ s: Segment, _ t: Segment, sinTol: Double, options: Options) -> Bool {
        guard abs(s.direction.cross(t.direction)) <= sinTol else { return false }
        let (long, short) = s.length >= t.length ? (s, t) : (t, s)
        let u = long.direction
        let off1 = abs((short.a - long.a).cross(u)), off2 = abs((short.b - long.a).cross(u))
        guard max(off1, off2) <= options.collinearOffsetTolerance else { return false }
        let s0 = (short.a - long.a).dot(u), s1 = (short.b - long.a).dot(u)
        // Along-line intervals: long = [0, L], short = [lo, hi]. The gap between them is positive
        // only when they are disjoint.
        let gap = max(0, min(s0, s1)) - min(long.length, max(s0, s1))
        return gap <= options.snapTolerance
    }

    private static func combine(_ pieces: [Segment]) -> Segment {
        guard pieces.count > 1 else { return pieces[0] }
        var longest = pieces[0]
        for p in pieces.dropFirst() where p.length > longest.length + 1e-9 { longest = p }
        let u0 = longest.direction
        var sumDir = Point2.zero, centroid = Point2.zero
        var totalLength = 0.0
        for p in pieces {
            let d = p.direction
            let aligned = d.dot(u0) >= 0 ? d : -d
            sumDir = sumDir + aligned * p.length
            centroid = centroid + (p.a + p.b) * 0.5 * p.length
            totalLength += p.length
        }
        let dir = sumDir.normalized
        let u = dir.length > 0.5 ? dir : u0
        let anchor = centroid / totalLength
        var lo = Double.infinity, hi = -Double.infinity
        for p in pieces {
            for q in [p.a, p.b] {
                let t = (q - anchor).dot(u)
                lo = min(lo, t); hi = max(hi, t)
            }
        }
        let (a, b) = canonicalOrder(anchor + u * lo, anchor + u * hi)
        func weighted(_ f: (Segment) -> Double) -> Double {
            pieces.reduce(0.0) { $0 + f($1) * $1.length } / totalLength
        }
        return Segment(id: longest.id, surfaceIDs: pieces.flatMap(\.surfaceIDs).sorted { $0.uuidString < $1.uuidString },
                       a: a, b: b, bottom: weighted(\.bottom), top: weighted(\.top), height: weighted(\.height),
                       isCurved: pieces.contains { $0.isCurved }, lowConfidence: pieces.contains { $0.lowConfidence })
    }

    // MARK: Graph

    static func buildNodes(_ segs: [Segment]) -> [DirectedNode] {
        var nodes: [DirectedNode] = []
        nodes.reserveCapacity(segs.count * 2)
        for (i, s) in segs.enumerated() {
            let d = s.direction
            nodes.append(DirectedNode(segment: i, p0: s.a, p1: s.b, dir: d))
            nodes.append(DirectedNode(segment: i, p0: s.b, p1: s.a, dir: -d))
        }
        return nodes
    }

    /// Can you turn from the end of `u` onto the start of `v`?
    private static func directEdge(_ u: DirectedNode, _ v: DirectedNode, to: Int, sinTol: Double,
                                   options: Options) -> LoopEdge? {
        let cross = u.dir.cross(v.dir)
        let w = v.p0 - u.p1
        let endGap = w.length
        let snap = options.snapTolerance + epsilon
        func midpointEdge() -> LoopEdge? {
            guard endGap <= snap else { return nil }
            return LoopEdge(to: to, corner: u.p1.lerp(to: v.p0, t: 0.5), cost: gapCostPerMetre * endGap,
                            shortfall: endGap, overshoot: 0)
        }
        if abs(cross) <= sinTol {
            // Near-parallel: only a straight-through joint makes sense, meeting at the gap midpoint.
            guard u.dir.dot(v.dir) > 0 else { return nil }
            return midpointEdge()
        }
        // Intersection of the two lines. X = u.p1 + t * u.dir = v.p0 + s * v.dir.
        let t = w.cross(v.dir) / cross
        let s = w.cross(u.dir) / cross
        let shortU = max(0, t), overU = max(0, -t)
        let shortV = max(0, -s), overV = max(0, s)
        if shortU <= snap, shortV <= snap,
           overU <= options.maxCornerOvershoot + epsilon, overV <= options.maxCornerOvershoot + epsilon {
            let x = u.p1 + u.dir * t
            guard x.x.isFinite, x.y.isFinite else { return nil }
            return LoopEdge(to: to, corner: x,
                            cost: gapCostPerMetre * (shortU + shortV) + overshootCostPerMetre * (overU + overV),
                            shortfall: max(shortU, shortV), overshoot: max(overU, overV))
        }
        return midpointEdge()
    }

    /// The wall-end graph. It is symmetric under reversal: u -> v exists exactly when (v reversed) -> (u reversed)
    /// does, with the same corner and cost. The loop search relies on that to start every wall forwards only.
    static func buildEdges(_ nodes: [DirectedNode], options: Options) -> [[LoopEdge]] {
        let n = nodes.count
        let sinTol = sin(options.collinearToleranceDegrees * Double.pi / 180)
        var adj = [[LoopEdge]](repeating: [], count: n)
        for u in 0..<n {
            for v in 0..<n where nodes[u].segment != nodes[v].segment {
                if let e = directEdge(nodes[u], nodes[v], to: v, sinTol: sinTol, options: options) {
                    adj[u].append(e)
                }
            }
        }
        // Bridges join wall ends that nothing else touches ("free" ends).
        let directCount = adj.map(\.count)
        var bridges = Set<[Int]>()      // (from, to) pairs, kept symmetric under reversal
        var distances: [[Int]: Double] = [:]
        for u in 0..<n where directCount[u] == 0 {
            var candidates: [(to: Int, distance: Double)] = []
            for v in 0..<n where nodes[u].segment != nodes[v].segment && directCount[v ^ 1] == 0 {
                let d = nodes[u].p1.distance(to: nodes[v].p0)
                if d > options.snapTolerance + epsilon, d <= options.maxBridgeableGap + epsilon {
                    candidates.append((v, d))
                }
            }
            candidates.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.to < $1.to }
            for c in candidates.prefix(maxBridgeCandidates) {
                bridges.insert([u, c.to])
                bridges.insert([c.to ^ 1, u ^ 1])
                distances[[u, c.to]] = c.distance
                distances[[c.to ^ 1, u ^ 1]] = c.distance
            }
        }
        for pair in bridges.sorted(by: { $0[0] != $1[0] ? $0[0] < $1[0] : $0[1] < $1[1] }) {
            let d = distances[pair] ?? 0
            adj[pair[0]].append(LoopEdge(to: pair[1], corner: nil, cost: bridgeCostPerMetre * d, shortfall: 0, overshoot: 0))
        }
        for u in 0..<n {
            adj[u].sort { $0.cost != $1.cost ? $0.cost < $1.cost : $0.to < $1.to }
        }
        return adj
    }

    /// Turn a cycle of directed nodes and the edges between them into loop walls. nil when a wall
    /// would collapse or reverse (inconsistent corners).
    static func assembleCycle(path: [Int], edges: [LoopEdge], nodes: [DirectedNode],
                              minEdgeLength: Double) -> [LoopWall]? {
        let m = path.count
        guard m >= 2, edges.count == m else { return nil }
        var out: [LoopWall] = []
        for j in 0..<m {
            let n = nodes[path[j]]
            let prev = edges[(j + m - 1) % m], next = edges[j]
            let s = prev.corner ?? n.p0
            let e = next.corner ?? n.p1
            let d = e - s
            guard d.length >= minEdgeLength, d.dot(n.dir) > 0 else { return nil }
            out.append(LoopWall(start: s, end: e, segment: n.segment))
            if next.isBridge {
                out.append(LoopWall(start: e, end: nodes[path[(j + 1) % m]].p0, segment: nil))
            }
        }
        return out
    }

    // MARK: Search

    private final class LoopSearch {
        struct Best {
            var path: [Int]
            var edges: [LoopEdge]
            var total: Double
            var area: Double
        }

        let nodes: [DirectedNode]
        let adj: [[LoopEdge]]
        let radj: [[Int]]
        let segLength: [Double]
        let totalLength: Double
        let minEdgeLength: Double
        var budget: Int
        var exhausted = false
        var best: Best?

        var used: [Bool]
        var allowed: [Bool]
        var canReach: [Bool]
        var startNode = 0
        var path: [Int] = []
        var pathEdges: [LoopEdge] = []
        var startVerts: [Point2] = []
        var poly: [(Point2, Point2)] = []

        init(nodes: [DirectedNode], adj: [[LoopEdge]], segLength: [Double], minEdgeLength: Double, budget: Int) {
            self.nodes = nodes
            self.adj = adj
            self.segLength = segLength
            self.totalLength = segLength.reduce(0, +)
            self.minEdgeLength = minEdgeLength
            self.budget = max(0, budget)
            var r = [[Int]](repeating: [], count: nodes.count)
            for (u, list) in adj.enumerated() { for e in list { r[e.to].append(u) } }
            self.radj = r
            self.used = [Bool](repeating: false, count: segLength.count)
            self.allowed = [Bool](repeating: false, count: segLength.count)
            self.canReach = [Bool](repeating: false, count: nodes.count)
        }

        func run() {
            // Longest walls first: a good loop is found early and prunes the rest.
            let n = segLength.count
            let order = (0..<n).sorted { segLength[$0] != segLength[$1] ? segLength[$0] > segLength[$1] : $0 < $1 }
            var rank = [Int](repeating: 0, count: n)
            for (r, s) in order.enumerated() { rank[s] = r }
            for (r, s) in order.enumerated() {
                if exhausted { return }
                for i in 0..<n { allowed[i] = rank[i] >= r }
                startNode = 2 * s
                // Which nodes can still get back to the start?
                for i in 0..<canReach.count { canReach[i] = false }
                canReach[startNode] = true
                var queue = [startNode]
                var qi = 0
                while qi < queue.count {
                    let x = queue[qi]; qi += 1
                    for y in radj[x] where allowed[nodes[y].segment] && !canReach[y] {
                        canReach[y] = true
                        queue.append(y)
                    }
                }
                guard adj[startNode].contains(where: { canReach[$0.to] }) else { continue }
                path = [startNode]
                pathEdges = []
                startVerts = [Point2.zero]
                poly = []
                used[s] = true
                dfs(cost: 0, usedLength: segLength[s], bridges: 0)
                used[s] = false
            }
        }

        /// Add an edge to the partial polygon if it neither crosses nor folds back on it.
        private func tryAppend(_ a: Point2, _ b: Point2) -> Bool {
            if let last = poly.last {
                let u = last.1 - last.0, v = b - a
                let lu = u.length, lv = v.length
                if lu > 1e-9, lv > 1e-9, abs(u.cross(v)) / (lu * lv) < 1e-9, u.dot(v) < 0 { return false }
            }
            if poly.count >= 2 {
                for i in 0..<(poly.count - 1) where RoomBuilder.segmentsTouch(poly[i].0, poly[i].1, a, b) { return false }
            }
            poly.append((a, b))
            return true
        }

        private func dfs(cost: Double, usedLength: Double, bridges: Int) {
            if exhausted { return }
            let k = path.count - 1
            let u = path[k]
            for e in adj[u] {
                budget -= 1
                if budget <= 0 { exhausted = true; return }
                if let b = best, cost + e.cost > b.total + 1e-12 { break }
                if e.isBridge && bridges >= RoomBuilder.maxBridgesPerLoop { continue }
                let v = e.to
                if v == startNode {
                    close(with: e, cost: cost + e.cost, usedLength: usedLength)
                    if exhausted { return }
                    continue
                }
                let sv = nodes[v].segment
                if used[sv] || !allowed[sv] || !canReach[v] { continue }

                let endU = e.corner ?? nodes[u].p1
                var pushed = 0
                var ok = true
                if k >= 1 {
                    let s = startVerts[k]
                    let d = endU - s
                    if d.length < minEdgeLength || d.dot(nodes[u].dir) <= 0 || !tryAppend(s, endU) { ok = false } else { pushed += 1 }
                }
                if ok, e.isBridge {
                    if tryAppend(endU, nodes[v].p0) { pushed += 1 } else { ok = false }
                }
                if ok {
                    path.append(v)
                    pathEdges.append(e)
                    startVerts.append(e.corner ?? nodes[v].p0)
                    used[sv] = true
                    dfs(cost: cost + e.cost, usedLength: usedLength + segLength[sv],
                        bridges: bridges + (e.isBridge ? 1 : 0))
                    used[sv] = false
                    startVerts.removeLast()
                    pathEdges.removeLast()
                    path.removeLast()
                }
                if pushed > 0 { poly.removeLast(pushed) }
                if exhausted { return }
            }
        }

        private func close(with e: LoopEdge, cost: Double, usedLength: Double) {
            if e.isBridge && pathEdges.filter({ $0.isBridge }).count >= RoomBuilder.maxBridgesPerLoop { return }
            budget -= path.count * path.count / 4 + 1   // assembling and testing a loop is O(n^2)
            let edges = pathEdges + [e]
            guard let walls = RoomBuilder.assembleCycle(path: path, edges: edges, nodes: nodes,
                                                        minEdgeLength: minEdgeLength) else { return }
            let verts = walls.map(\.start)
            guard verts.count >= 3 else { return }
            let area = Polygon.area(verts)
            guard area > 0.01, RoomBuilder.isSimplePolygon(verts) else { return }
            let total = cost + RoomBuilder.dropCostPerMetre * max(0, totalLength - usedLength)
            if let b = best {
                let diff = total - b.total
                let better = diff < -RoomBuilder.costTieBand
                    || (abs(diff) <= RoomBuilder.costTieBand && area > b.area + 1e-9)
                if !better { return }
            }
            best = Best(path: path, edges: edges, total: total, area: area)
        }
    }

    // MARK: Loop

    /// Find the closed boundary loop (counter-clockwise, canonical start); `outcome` is nil when none exists.
    static func findLoop(segments all: [Segment], options: Options) -> LoopSearchResult {
        guard all.count >= 2 else { return LoopSearchResult(outcome: nil, budgetExhausted: false) }
        // Keep the search tractable on hostile input: only the longest walls compete.
        var globalIndex = Array(0..<all.count)
        if all.count > searchSegmentCap {
            globalIndex = globalIndex.sorted { all[$0].length != all[$1].length ? all[$0].length > all[$1].length : $0 < $1 }
            globalIndex = Array(globalIndex.prefix(searchSegmentCap)).sorted()
        }
        let segs = globalIndex.map { all[$0] }

        let nodes = buildNodes(segs)
        let adj = buildEdges(nodes, options: options)
        let search = LoopSearch(nodes: nodes, adj: adj, segLength: segs.map(\.length),
                                minEdgeLength: options.minWallLength * 0.5, budget: options.searchBudget)
        search.run()
        guard let best = search.best,
              var walls = assembleCycle(path: best.path, edges: best.edges, nodes: nodes,
                                        minEdgeLength: options.minWallLength * 0.5) else {
            return LoopSearchResult(outcome: nil, budgetExhausted: search.exhausted)
        }

        // Map local segment indices back to the caller's indices.
        walls = walls.map { LoopWall(start: $0.start, end: $0.end, segment: $0.segment.map { globalIndex[$0] }) }
        walls = counterClockwise(walls)
        walls = rotatedToCanonicalStart(walls)

        let usedSet = Set(walls.compactMap(\.segment))
        let dropped = (0..<all.count).filter { !usedSet.contains($0) }

        let threshold = options.snapTolerance / 2
        var gaps = 0, trims = 0
        var maxGap = 0.0, maxTrim = 0.0
        for e in best.edges {
            if e.shortfall > threshold { gaps += 1; maxGap = max(maxGap, e.shortfall) }
            if e.overshoot > threshold { trims += 1; maxTrim = max(maxTrim, e.overshoot) }
        }
        return LoopSearchResult(
            outcome: LoopOutcome(walls: walls, droppedSegments: dropped, gapsClosed: gaps, maxGap: maxGap,
                                 wallsTrimmed: trims, maxTrim: maxTrim),
            budgetExhausted: search.exhausted)
    }

    static func counterClockwise(_ walls: [LoopWall]) -> [LoopWall] {
        guard Polygon.signedArea(walls.map(\.start)) < 0 else { return walls }
        return walls.reversed().map { LoopWall(start: $0.end, end: $0.start, segment: $0.segment) }
    }

    /// Start the loop at its lowest (then leftmost) corner so output is independent of where the
    /// search began.
    static func rotatedToCanonicalStart(_ walls: [LoopWall]) -> [LoopWall] {
        guard walls.count > 1 else { return walls }
        var best = 0
        for i in 1..<walls.count {
            let p = walls[i].start, q = walls[best].start
            if abs(p.y - q.y) > 1e-6 ? p.y < q.y : p.x < q.x - 1e-6 { best = i }
        }
        guard best != 0 else { return walls }
        return Array(walls[best...] + walls[..<best])
    }

    // MARK: Fallbacks

    struct FallbackOutline {
        var walls: [LoopWall]
        var kind: BuildWarning.LoopFallback
    }

    static func fallbackOutline(segments: [Segment], floors: [FloorInfo], options: Options) -> FallbackOutline? {
        let polys = floors.compactMap { f in f.polygon.map { (area: Polygon.area($0), poly: $0, exact: f.isExact) } }
        if let pick = polys.max(by: { ($0.exact ? 1 : 0, $0.area) < ($1.exact ? 1 : 0, $1.area) }) {
            let walls = rotatedToCanonicalStart(wallsAlong(Polygon.counterClockwise(pick.poly), segments: segments))
            return FallbackOutline(walls: walls, kind: .floorPolygon)
        }
        let hull = convexHull(segments.flatMap { [$0.a, $0.b] })
        if hull.count >= 3, Polygon.area(hull) > 0.01 {
            let walls = rotatedToCanonicalStart(wallsAlong(hull, segments: segments))
            return FallbackOutline(walls: walls, kind: .convexHull)
        }
        return nil
    }

    /// Edges of `polygon` as loop walls: solid where a scanned wall lies along the edge, virtual otherwise.
    static func wallsAlong(_ polygon: [Point2], segments: [Segment]) -> [LoopWall] {
        let n = polygon.count
        let sin10 = sin(10 * Double.pi / 180)
        var out: [LoopWall] = []
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            let e = b - a
            let len = e.length
            guard len > 1e-9 else { continue }
            let dir = e / len
            var bestSeg: Int?
            var bestOverlap = 0.0
            for (j, s) in segments.enumerated() {
                guard abs(dir.cross(s.direction)) <= sin10 else { continue }
                let off = max(abs((s.a - a).cross(dir)), abs((s.b - a).cross(dir)))
                guard off <= 0.30 else { continue }
                let t0 = (s.a - a).dot(dir), t1 = (s.b - a).dot(dir)
                let overlap = min(len, max(t0, t1)) - max(0, min(t0, t1))
                if overlap > bestOverlap + 1e-9 { bestOverlap = overlap; bestSeg = j }
            }
            if let j = bestSeg, bestOverlap >= 0.3 * len {
                out.append(LoopWall(start: a, end: b, segment: j))
            } else {
                out.append(LoopWall(start: a, end: b, segment: nil))
            }
        }
        return out
    }

    /// Andrew's monotone chain; counter-clockwise, collinear points dropped.
    static func convexHull(_ points: [Point2]) -> [Point2] {
        let pts = points.filter { $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        var unique: [Point2] = []
        for p in pts where unique.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { unique.append(p) }
        guard unique.count >= 3 else { return unique }
        var lower: [Point2] = []
        for p in unique {
            while lower.count >= 2, orient(lower[lower.count - 2], lower[lower.count - 1], p) <= 1e-12 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [Point2] = []
        for p in unique.reversed() {
            while upper.count >= 2, orient(upper[upper.count - 2], upper[upper.count - 1], p) <= 1e-12 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    // MARK: Walls

    struct Assembled {
        var walls: [Wall]
        var surfaceToWall: [UUID: UUID]
    }

    /// Turn loop walls into model `Wall`s with stable identifiers and the surface -> wall map.
    static func assembleWalls(loopWalls: [LoopWall], segments: [Segment], ceiling: Double,
                              captureID: UUID) -> Assembled {
        let n = loopWalls.count
        var taken = Set<UUID>()
        var wallIDs = [UUID?](repeating: nil, count: n)
        var surfaceToWall: [UUID: UUID] = [:]

        func claim(_ preferred: UUID, salt: String) -> UUID {
            var id = preferred
            var k = 0
            while taken.contains(id) {
                k += 1
                id = stableUUID("\(salt)|\(preferred.uuidString)|\(k)")
            }
            taken.insert(id)
            return id
        }

        for (k, lw) in loopWalls.enumerated() {
            guard let si = lw.segment, segments.indices.contains(si) else { continue }
            let id = claim(segments[si].id, salt: "wall")
            wallIDs[k] = id
            for sid in segments[si].surfaceIDs where surfaceToWall[sid] == nil { surfaceToWall[sid] = id }
        }
        func neighbourID(_ k: Int, step: Int) -> String {
            var i = k
            for _ in 0..<n {
                i = (i + step + n) % n
                if let id = wallIDs[i] { return id.uuidString }
            }
            return captureID.uuidString
        }
        for k in 0..<n where wallIDs[k] == nil {
            let preferred = stableUUID("virtual|\(neighbourID(k, step: -1))|\(neighbourID(k, step: 1))|\(k)")
            wallIDs[k] = claim(preferred, salt: "virtual")
        }

        var walls: [Wall] = []
        for (k, lw) in loopWalls.enumerated() {
            let id = wallIDs[k] ?? stableUUID("wall|\(captureID.uuidString)|\(k)")
            if let si = lw.segment, segments.indices.contains(si) {
                walls.append(Wall(id: id, start: lw.start, end: lw.end, kind: .solid, isCurved: segments[si].isCurved,
                                  height: Measured(scanned: segments[si].height)))
            } else {
                walls.append(Wall(id: id, start: lw.start, end: lw.end, kind: .virtual,
                                  height: Measured(scanned: ceiling)))
            }
        }
        return Assembled(walls: walls, surfaceToWall: surfaceToWall)
    }
}
