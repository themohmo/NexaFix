import Foundation

// Screen-space label declutter for the AR overlay. It knows nothing about ARKit: the app projects each
// label anchor to the screen, measures the label, and hands the candidates here. The result says which
// labels to draw, where, and how opaque. Pure and deterministic, so it is unit-tested off-device.

/// One label the app would like to draw this frame. `x` and `y` are the CENTRE of the label in screen
/// points (the projected anchor); `width` and `height` are its size in points.
public struct LabelCandidate: Hashable, Sendable {
    public var id: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Higher wins when labels overlap.
    public var priority: Int
    /// Metres from the camera to the anchor.
    public var distance: Double

    public init(id: String, x: Double, y: Double, width: Double, height: Double, priority: Int, distance: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.priority = priority
        self.distance = distance
    }
}

/// Where a label ended up. `x` and `y` are the centre in screen points; `opacity` is 0...1.
public struct PlacedLabel: Hashable, Sendable {
    public var id: String
    public var x: Double
    public var y: Double
    public var opacity: Double

    public init(id: String, x: Double, y: Double, opacity: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.opacity = opacity
    }
}

public struct LabelViewport: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct LabelLayoutOptions: Hashable, Sendable {
    /// Full opacity up to this distance, metres.
    public var fullOpacityDistance: Double
    /// Opacity reaches zero at this distance, metres.
    public var zeroOpacityDistance: Double
    /// A label is dropped when more than this fraction of its own area is covered by higher-priority labels.
    public var overlapLimit: Double
    /// How many label-heights a label may be moved up or down before it is dropped.
    public var maxNudgeSteps: Int
    /// Space left between a nudged label and the one it avoided, points.
    public var nudgeGap: Double
    /// A label hanging this far past the screen edge is fully faded out, points.
    public var edgeFadeMargin: Double

    public init(fullOpacityDistance: Double = 4, zeroOpacityDistance: Double = 12, overlapLimit: Double = 0.15,
                maxNudgeSteps: Int = 2, nudgeGap: Double = 2, edgeFadeMargin: Double = 40) {
        self.fullOpacityDistance = fullOpacityDistance
        self.zeroOpacityDistance = zeroOpacityDistance
        self.overlapLimit = overlapLimit
        self.maxNudgeSteps = maxNudgeSteps
        self.nudgeGap = nudgeGap
        self.edgeFadeMargin = edgeFadeMargin
    }

    public static let standard = LabelLayoutOptions()
}

public enum LabelLayout {

    /// Decide which candidates to draw. Greedy by priority (high first), then distance (near first),
    /// then id, so equal inputs always give equal output. The result is ordered best label first.
    ///
    /// - A label overlapping already-placed labels by more than `overlapLimit` of its own area is moved
    ///   vertically (at most `maxNudgeSteps` steps each way, alternating up then down) and dropped if
    ///   it still collides.
    /// - Opacity fades with distance (1 up to `fullOpacityDistance`, 0 at `zeroOpacityDistance`) and
    ///   near the screen edge. Labels that are fully faded are not returned.
    public static func place(_ candidates: [LabelCandidate], viewport: LabelViewport,
                             options: LabelLayoutOptions = .standard) -> [PlacedLabel] {
        guard viewport.width > 0, viewport.height > 0 else { return [] }

        let usable = candidates.filter { c in
            c.x.isFinite && c.y.isFinite && c.width.isFinite && c.height.isFinite && c.distance.isFinite
                && c.width > 0 && c.height > 0 && distanceOpacity(c.distance, options) > 0.001
        }
        let ordered = usable.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.distance != b.distance { return a.distance < b.distance }
            return a.id < b.id
        }

        var placedRects: [Rect] = []
        var result: [PlacedLabel] = []
        result.reserveCapacity(ordered.count)

        for c in ordered {
            let fade = distanceOpacity(c.distance, options)
            let step = c.height + options.nudgeGap
            for offset in nudgeOffsets(maxSteps: options.maxNudgeSteps) {
                let y = c.y + Double(offset) * step
                let rect = Rect(midX: c.x, midY: y, width: c.width, height: c.height)
                let edge = edgeOpacity(rect, viewport: viewport, margin: options.edgeFadeMargin)
                guard edge > 0.001 else { continue }
                if overlapFraction(of: rect, with: placedRects) > options.overlapLimit { continue }
                placedRects.append(rect)
                result.append(PlacedLabel(id: c.id, x: c.x, y: y, opacity: fade * edge))
                break
            }
        }
        return result
    }

    /// 1 up to `fullOpacityDistance`, falling linearly to 0 at `zeroOpacityDistance`.
    public static func distanceOpacity(_ distance: Double, _ options: LabelLayoutOptions = .standard) -> Double {
        guard distance.isFinite else { return 0 }
        if distance <= options.fullOpacityDistance { return 1 }
        if distance >= options.zeroOpacityDistance { return 0 }
        let span = options.zeroOpacityDistance - options.fullOpacityDistance
        guard span > 0 else { return 0 }
        return 1 - (distance - options.fullOpacityDistance) / span
    }

    // MARK: Internals

    private struct Rect {
        var minX: Double, minY: Double, maxX: Double, maxY: Double
        init(midX: Double, midY: Double, width: Double, height: Double) {
            minX = midX - width / 2
            maxX = midX + width / 2
            minY = midY - height / 2
            maxY = midY + height / 2
        }
        var area: Double { (maxX - minX) * (maxY - minY) }
        func intersectionArea(_ o: Rect) -> Double {
            let w = min(maxX, o.maxX) - max(minX, o.minX)
            let h = min(maxY, o.maxY) - max(minY, o.minY)
            return (w > 0 && h > 0) ? w * h : 0
        }
    }

    /// 0, then up one, down one, up two, down two ... (screen up is negative y).
    private static func nudgeOffsets(maxSteps: Int) -> [Int] {
        var offsets = [0]
        if maxSteps > 0 {
            for k in 1...maxSteps { offsets.append(-k); offsets.append(k) }
        }
        return offsets
    }

    private static func overlapFraction(of rect: Rect, with others: [Rect]) -> Double {
        let area = rect.area
        guard area > 0 else { return 1 }
        var covered = 0.0
        for o in others { covered += rect.intersectionArea(o) }
        return covered / area
    }

    private static func edgeOpacity(_ r: Rect, viewport: LabelViewport, margin: Double) -> Double {
        let overhang = max(0 - r.minX, r.maxX - viewport.width, 0 - r.minY, r.maxY - viewport.height)
        if overhang <= 0 { return 1 }
        guard margin > 0 else { return 0 }
        return max(0, 1 - overhang / margin)
    }
}

// MARK: - Hysteresis

/// Stops labels flickering when a declutter decision flips back and forth between frames.
/// The shown/hidden state of a label changes only after the new decision has held for
/// `requiredFrames` consecutive frames. Pure state: keep one in the canvas and call `stabilise` each frame.
public struct LabelHysteresis: Sendable {
    private struct Entry: Sendable {
        var shown: Bool
        var disagreeing: Int
        var last: PlacedLabel
    }

    public let requiredFrames: Int
    private var entries: [String: Entry] = [:]

    public init(requiredFrames: Int = 3) {
        self.requiredFrames = max(1, requiredFrames)
    }

    /// Ids currently tracked (for tests).
    public var trackedCount: Int { entries.count }

    public mutating func reset() { entries.removeAll(keepingCapacity: true) }

    /// - Parameters:
    ///   - placed: this frame's raw output of `LabelLayout.place`.
    ///   - candidates: everything that was offered to the layout this frame. A label that is no longer
    ///     offered (off screen, behind the camera) disappears at once; only declutter decisions are smoothed.
    /// - Returns: the labels to draw, best first. A label the layout just dropped stays visible at its
    ///   current projected position until the drop has lasted `requiredFrames` frames.
    public mutating func stabilise(_ placed: [PlacedLabel], candidates: [LabelCandidate]) -> [PlacedLabel] {
        var placedByID: [String: PlacedLabel] = [:]
        placedByID.reserveCapacity(placed.count)
        for p in placed { placedByID[p.id] = p }

        var offered = Set<String>()
        offered.reserveCapacity(candidates.count)
        for c in candidates { offered.insert(c.id) }

        // Forget labels that are no longer offered.
        for id in Array(entries.keys) where !offered.contains(id) { entries[id] = nil }

        var output: [PlacedLabel] = []
        output.reserveCapacity(placed.count)

        // First pass: update every offered label's state.
        for c in candidates {
            let raw = placedByID[c.id]
            if var entry = entries[c.id] {
                if (raw != nil) == entry.shown {
                    entry.disagreeing = 0
                } else {
                    entry.disagreeing += 1
                    if entry.disagreeing >= requiredFrames {
                        entry.shown = (raw != nil)
                        entry.disagreeing = 0
                    }
                }
                if let raw = raw { entry.last = raw }
                entries[c.id] = entry
            } else {
                // First sight: adopt the layout's decision straight away.
                entries[c.id] = Entry(shown: raw != nil, disagreeing: 0,
                                      last: raw ?? PlacedLabel(id: c.id, x: c.x, y: c.y, opacity: 0))
            }
        }

        // Second pass: emit in the layout's order, then held labels.
        for p in placed {
            if let entry = entries[p.id], entry.shown { output.append(p) }
        }
        for c in candidates where placedByID[c.id] == nil {
            if let entry = entries[c.id], entry.shown {
                // Held over a dropped frame: keep its last opacity, follow the world position.
                output.append(PlacedLabel(id: c.id, x: c.x, y: c.y, opacity: entry.last.opacity))
            }
        }
        return output
    }
}
