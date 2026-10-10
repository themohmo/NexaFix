import Foundation

// The maths behind the interactive floor plan: where the plan is on the screen, how a pinch zooms about the
// fingers, how far a drag may go past the drawing, and where a flick comes to rest. None of it knows about
// SwiftUI, so every function here is unit-tested off-device, and the 3D viewer reuses the gesture maths.
//
// Conventions: plan space is metres with +y UP; screen space is points with +y DOWN, x to the right.
// A `Point2` in a screen-space role is documented as such.

// MARK: - Gesture maths

/// The formulas behind fluid gestures: progressive resistance past an edge, momentum, springs.
public enum GestureMath {
    /// UIKit's rubber-band constant.
    public static let rubberBandConstant = 0.55
    /// `UIScrollView.DecelerationRate.normal`: the fraction of speed kept every millisecond.
    public static let decelerationRate = 0.998

    /// Progressive resistance: how far the content follows a drag that has gone `overshoot` points past its
    /// limit, inside a view `dimension` points across. At first it follows at `constant` of the finger's speed
    /// (0.55), then yields more and more, and never reaches `dimension`. Keeps the sign of `overshoot`; zero
    /// gives zero.
    public static func rubberband(_ overshoot: Double, dimension: Double,
                                  constant: Double = rubberBandConstant) -> Double {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// Where a flick at `velocity` (points per second) comes to rest, measured from where the finger lifted:
    /// the distance a scroll view would coast.
    public static func project(_ velocity: Double, decelerationRate: Double = decelerationRate) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// The speed left after `dt` seconds of coasting at the given per-millisecond deceleration rate.
    public static func decayed(_ velocity: Double, over dt: Double, decelerationRate: Double = decelerationRate) -> Double {
        guard velocity.isFinite, dt.isFinite, dt > 0 else { return velocity.isFinite ? velocity : 0 }
        return velocity * pow(decelerationRate, dt * 1000)
    }
}

/// One number on a damped spring, advanced exactly (not by numerical integration), so any frame length is
/// stable. `response` and `dampingFraction` mean what they mean in SwiftUI's `.spring(response:dampingFraction:)`:
/// response is the period of the undamped oscillation in seconds; 1 is critically damped (no overshoot).
public struct Spring1D: Hashable, Sendable {
    public var value: Double
    public var velocity: Double
    public var target: Double

    public init(value: Double, velocity: Double = 0, target: Double? = nil) {
        self.value = value
        self.velocity = velocity
        self.target = target ?? value
    }

    /// Runs the spring for `dt` seconds. Damping above 1 behaves like 1.
    public mutating func advance(by dt: Double, response: Double, dampingFraction: Double) {
        guard dt.isFinite, dt > 0, value.isFinite, velocity.isFinite, target.isFinite else { return }
        guard response.isFinite, response > 0.001 else {
            value = target
            velocity = 0
            return
        }
        let omega = 2 * Double.pi / response
        let zeta = Swift.min(Swift.max(dampingFraction.isFinite ? dampingFraction : 1, 0.01), 1)
        let x0 = value - target
        let v0 = velocity
        let decay = exp(-zeta * omega * dt)
        var x: Double
        var v: Double
        if zeta >= 1 - 1e-9 {
            let b = v0 + omega * x0
            x = (x0 + b * dt) * decay
            v = (b - omega * (x0 + b * dt)) * decay
        } else {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            let c = cos(wd * dt), s = sin(wd * dt)
            x = decay * (x0 * c + ((v0 + zeta * omega * x0) / wd) * s)
            v = decay * (v0 * c - ((omega * omega * x0 + zeta * omega * v0) / wd) * s)
        }
        if !x.isFinite || !v.isFinite {
            x = 0
            v = 0
        }
        value = target + x
        velocity = v
    }

    /// Close enough to the target, and slow enough, to stop animating.
    public func isSettled(tolerance: Double, velocityTolerance: Double? = nil) -> Bool {
        abs(value - target) <= tolerance && abs(velocity) <= (velocityTolerance ?? tolerance * 10)
    }
}

/// Estimates how fast a finger was moving when it lifted, from the last few samples.
public struct PanVelocityTracker: Hashable, Sendable {
    private struct Sample: Hashable, Sendable {
        var time: Double
        var x: Double
        var y: Double
    }

    /// Samples older than this (seconds) before the newest one are ignored.
    public let window: Double
    private var samples: [Sample] = []

    public init(window: Double = 0.1) {
        self.window = window > 0 ? window : 0.1
    }

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }

    /// Records where the finger was at `time` (seconds, any steady clock).
    public mutating func add(time: Double, x: Double, y: Double) {
        guard time.isFinite, x.isFinite, y.isFinite else { return }
        if let last = samples.last, time < last.time { samples.removeAll(keepingCapacity: true) }
        samples.append(Sample(time: time, x: x, y: y))
        // Keep a little more than the window.
        while samples.count > 2, let first = samples.first, time - first.time > window * 3 {
            samples.removeFirst()
        }
    }

    /// Points per second at `time`. Zero when the finger had been still for longer than the window before
    /// `time` (a person who pauses before lifting is not flicking), or when there is too little to go on.
    public func velocity(at time: Double) -> Point2 {
        guard let last = samples.last, time.isFinite, time - last.time <= window else { return .zero }
        let recent = samples.filter { last.time - $0.time <= window }
        guard let first = recent.first, last.time - first.time > 0.004 else { return .zero }
        let dt = last.time - first.time
        return Point2((last.x - first.x) / dt, (last.y - first.y) / dt)
    }
}

// MARK: - Screen size and the content

/// A view's size in points.
public struct ScreenSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var isUsable: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 }
    public var center: Point2 { Point2(width / 2, height / 2) }
}

/// What the viewport has to keep on screen: the drawing's extent, the view it is shown in, and a margin.
public struct PlanContent: Hashable, Sendable {
    /// Extent of the drawing, plan space metres.
    public var bounds: Bounds2
    public var size: ScreenSize
    /// Space kept clear around the drawing, screen points (so it never sits under a floating control).
    public var padding: Double

    public init(bounds: Bounds2, size: ScreenSize, padding: Double = 24) {
        self.bounds = bounds
        self.size = size
        self.padding = padding.isFinite ? Swift.max(padding, 0) : 0
    }

    /// The view has a size and the drawing a finite extent.
    public var isUsable: Bool {
        size.isUsable && bounds.min.x.isFinite && bounds.min.y.isFinite && bounds.max.x.isFinite && bounds.max.y.isFinite
    }
}

/// The zoom range of a plan: from half the scale that fits the drawing to forty times it.
public struct PlanZoomLimits: Hashable, Sendable {
    public static let minimumFactor = 0.5
    public static let maximumFactor = 40.0

    public var fitScale: Double
    public var minScale: Double { fitScale * PlanZoomLimits.minimumFactor }
    public var maxScale: Double { fitScale * PlanZoomLimits.maximumFactor }

    public init(fitScale: Double) {
        self.fitScale = fitScale.isFinite && fitScale > 0 ? fitScale : 1
    }

    /// `scale` held inside the range.
    public func clamp(_ scale: Double) -> Double {
        guard scale.isFinite else { return fitScale }
        return Swift.min(Swift.max(scale, minScale), maxScale)
    }

    /// `scale` with progressive resistance outside the range: in the range it is unchanged; beyond it the
    /// scale follows the pinch at a shrinking rate, measured in octaves (doublings), and never goes more than one
    /// octave (a factor of two) past the limit.
    public func rubberBanded(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else { return fitScale }
        if scale > maxScale {
            let octaves = log2(scale / maxScale)
            return maxScale * pow(2, GestureMath.rubberband(octaves, dimension: 1))
        }
        if scale < minScale {
            let octaves = log2(minScale / scale)
            return minScale / pow(2, GestureMath.rubberband(octaves, dimension: 1))
        }
        return scale
    }
}

// MARK: - The viewport

/// Where the plan sits in the view: `scale` screen points per metre, and `offset`, the screen position
/// (points) of the plan origin. A plan point `p` is at `(offset.x + p.x * scale, offset.y - p.y * scale)`.
public struct PlanViewport: Hashable, Sendable {
    public var scale: Double
    public var offset: Point2

    public init(scale: Double, offset: Point2) {
        self.scale = scale
        self.offset = offset
    }

    // MARK: Fitting

    /// The viewport that shows all of `bounds` centred in a view of `size`, with `padding` points kept clear on
    /// every side. A drawing with no extent on one axis fits by the other; with none at all, one point per metre.
    public static func fit(bounds: Bounds2, in size: ScreenSize, padding: Double = 24) -> PlanViewport {
        guard size.isUsable else { return PlanViewport(scale: 1, offset: .zero) }
        let pad = padding.isFinite ? Swift.max(padding, 0) : 0
        let usableW = Swift.max(size.width - 2 * pad, 1)
        let usableH = Swift.max(size.height - 2 * pad, 1)
        let w = bounds.width, h = bounds.height
        var scale = 1.0
        if w.isFinite, h.isFinite, w > 1e-9 || h > 1e-9 {
            let sx = w > 1e-9 ? usableW / w : Double.infinity
            let sy = h > 1e-9 ? usableH / h : Double.infinity
            scale = Swift.min(sx, sy)
        }
        let c = bounds.center
        let centre = (c.x.isFinite && c.y.isFinite) ? c : .zero
        return PlanViewport(scale: scale,
                            offset: Point2(size.width / 2 - centre.x * scale, size.height / 2 + centre.y * scale))
    }

    /// `fit(bounds:in:padding:)` for a `PlanContent`.
    public static func fit(_ content: PlanContent) -> PlanViewport {
        fit(bounds: content.bounds, in: content.size, padding: content.padding)
    }

    // MARK: Transforms

    /// Plan metres to screen points.
    public func screen(_ plan: Point2) -> Point2 {
        Point2(offset.x + plan.x * scale, offset.y - plan.y * scale)
    }

    /// Screen points to plan metres.
    public func plan(_ screen: Point2) -> Point2 {
        guard scale != 0 else { return .zero }
        return Point2((screen.x - offset.x) / scale, (offset.y - screen.y) / scale)
    }

    /// A length in metres as points on screen.
    public func points(forMetres metres: Double) -> Double { metres * scale }

    /// A length in points as metres on the plan. A 22 point finger is `metres(forPoints: 22)`.
    public func metres(forPoints points: Double) -> Double { scale > 0 ? points / scale : 0 }

    /// The part of the plan visible in a view of `size`, grown by `margin` points on every side (for culling).
    public func visiblePlanBounds(in size: ScreenSize, margin: Double = 0) -> Bounds2 {
        let a = plan(Point2(-margin, size.height + margin))
        let b = plan(Point2(size.width + margin, -margin))
        return Bounds2(min: Point2(Swift.min(a.x, b.x), Swift.min(a.y, b.y)),
                       max: Point2(Swift.max(a.x, b.x), Swift.max(a.y, b.y)))
    }

    // MARK: Moving and zooming

    /// Moved by a drag of `delta` screen points. The plan follows the finger one to one.
    public func translated(by delta: Point2) -> PlanViewport {
        PlanViewport(scale: scale, offset: offset + delta)
    }

    /// Scaled by `factor` about the screen point `anchor`: the plan point under `anchor` stays under it.
    /// A factor that is not a positive finite number changes nothing.
    public func zoomed(by factor: Double, about anchor: Point2) -> PlanViewport {
        guard factor.isFinite, factor > 0, anchor.x.isFinite, anchor.y.isFinite else { return self }
        return PlanViewport(scale: scale * factor, offset: anchor - (anchor - offset) * factor)
    }

    /// The same view at exactly `newScale`, zoomed about `anchor`.
    public func zoomed(toScale newScale: Double, about anchor: Point2) -> PlanViewport {
        guard scale > 0, newScale.isFinite, newScale > 0 else { return self }
        return zoomed(by: newScale / scale, about: anchor)
    }

    // MARK: Limits

    /// The zoom range for `content`.
    public static func zoomLimits(for content: PlanContent) -> PlanZoomLimits {
        PlanZoomLimits(fitScale: fit(content).scale)
    }

    /// The offsets the drawing may be panned to at the current scale, per axis.
    ///
    /// Where the drawing (plus padding) is larger than the view, the view must stay inside the drawing: the
    /// range has some width. Where the drawing is smaller, it stays centred: the range is a single value.
    public func offsetRanges(for content: PlanContent) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        guard content.isUsable, scale.isFinite else { return (0...0, 0...0) }
        let b = content.bounds, pad = content.padding
        let w = content.size.width, h = content.size.height

        let lengthX = scale * b.width + 2 * pad
        let x: ClosedRange<Double>
        if lengthX > w {
            x = PlanViewport.ordered(w - pad - scale * b.max.x, pad - scale * b.min.x)
        } else {
            let c = w / 2 - scale * (b.min.x + b.max.x) / 2
            x = c...c
        }

        let lengthY = scale * b.height + 2 * pad
        let y: ClosedRange<Double>
        if lengthY > h {
            y = PlanViewport.ordered(h - pad + scale * b.min.y, scale * b.max.y + pad)
        } else {
            let c = h / 2 + scale * (b.min.y + b.max.y) / 2
            y = c...c
        }
        return (x, y)
    }

    /// A range from two numbers in either order (rounding can swap a nearly empty range's ends).
    private static func ordered(_ a: Double, _ b: Double) -> ClosedRange<Double> {
        Swift.min(a, b)...Swift.max(a, b)
    }

    /// The viewport held inside its limits.
    ///
    /// - Parameters:
    ///   - rubberBand: when true, a scale or offset past its limit follows the gesture with progressive
    ///     resistance (the drag feel); when false it is clamped hard (where a gesture will come to rest).
    ///   - anchor: the screen point that stays put while the scale is corrected; the view centre by default.
    public func constrained(to content: PlanContent, rubberBand: Bool, anchor: Point2? = nil) -> PlanViewport {
        guard content.isUsable, scale.isFinite, scale > 0, offset.x.isFinite, offset.y.isFinite else {
            return PlanViewport.fit(content)
        }
        let limits = PlanViewport.zoomLimits(for: content)
        let fixed = anchor ?? content.size.center
        let target = rubberBand ? limits.rubberBanded(scale) : limits.clamp(scale)
        var result = zoomed(toScale: target, about: fixed)

        let ranges = result.offsetRanges(for: content)
        result.offset = Point2(
            PlanViewport.limited(result.offset.x, to: ranges.x, dimension: content.size.width, rubberBand: rubberBand),
            PlanViewport.limited(result.offset.y, to: ranges.y, dimension: content.size.height, rubberBand: rubberBand))
        return result
    }

    private static func limited(_ value: Double, to range: ClosedRange<Double>, dimension: Double,
                                rubberBand: Bool) -> Double {
        let clamped = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
        guard rubberBand else { return clamped }
        return clamped + GestureMath.rubberband(value - clamped, dimension: dimension)
    }

    // MARK: Letting go

    /// Where a gesture that ends now comes to rest.
    ///
    /// The pan velocity (screen points per second) is projected with `GestureMath.project`, added to the offset,
    /// and the result is held inside the zoom range and the drawing's edges. With `momentum` false (Reduce Motion)
    /// nothing is projected and the viewport only returns inside its limits.
    public func settleTarget(velocity: Point2, content: PlanContent, anchor: Point2? = nil,
                             momentum: Bool = true) -> PlanViewport {
        guard content.isUsable, scale.isFinite, scale > 0, offset.x.isFinite, offset.y.isFinite else { return self }
        let limits = PlanViewport.zoomLimits(for: content)
        var result = zoomed(toScale: limits.clamp(scale), about: anchor ?? content.size.center)
        if momentum, velocity.x.isFinite, velocity.y.isFinite {
            result.offset = result.offset + Point2(GestureMath.project(velocity.x), GestureMath.project(velocity.y))
        }
        return result.constrained(to: content, rubberBand: false, anchor: anchor)
    }

    // MARK: Forwarders

    /// `GestureMath.rubberband`.
    public static func rubberband(_ overshoot: Double, dimension: Double, constant: Double = GestureMath.rubberBandConstant) -> Double {
        GestureMath.rubberband(overshoot, dimension: dimension, constant: constant)
    }

    /// `GestureMath.project`.
    public static func project(_ velocity: Double, decelerationRate: Double = GestureMath.decelerationRate) -> Double {
        GestureMath.project(velocity, decelerationRate: decelerationRate)
    }
}

// MARK: - Drawing the plan on screen

/// What kind of ink a drawing colour is. The drawing's colours are print colours (ink on white paper); the
/// screen maps each role to a token of the app palette so the plan reads in dark mode too, and keeps the
/// semantic colours (verified green, out-of-square red).
public enum PlanColorRole: Hashable, Sendable {
    case ink, paper, hairline, muted, bronze, verified, warning, furnitureFill
    /// Not one of the NexaFix print colours; draw it as it is.
    case custom(DrawColor)

    /// The role of a drawing colour, matching the NexaFix print palette within rounding.
    public static func role(of color: DrawColor) -> PlanColorRole {
        let known: [(DrawColor, PlanColorRole)] = [
            (PlanDrawingBuilder.Palette.ink, .ink), (PlanDrawingBuilder.Palette.paper, .paper),
            (PlanDrawingBuilder.Palette.hairline, .hairline), (PlanDrawingBuilder.Palette.muted, .muted),
            (PlanDrawingBuilder.Palette.bronze, .bronze), (PlanDrawingBuilder.Palette.verified, .verified),
            (PlanDrawingBuilder.Palette.warning, .warning), (PlanDrawingBuilder.Palette.furnitureFill, .furnitureFill),
        ]
        for (candidate, role) in known where PlanColorRole.matches(color, candidate) { return role }
        if matches(color, .black) { return .ink }
        if matches(color, .white) { return .paper }
        return .custom(color)
    }

    private static func matches(_ a: DrawColor, _ b: DrawColor) -> Bool {
        abs(a.r - b.r) < 0.006 && abs(a.g - b.g) < 0.006 && abs(a.b - b.b) < 0.006
    }
}

/// The numbers that turn a drawing's paper units into screen points.
public enum PlanRenderMetrics {
    /// Text smaller than this (font size in points) is not drawn.
    public static let hiddenBelowFontSize = 7.0
    /// Text at or above this size is fully opaque; between the two it fades in.
    public static let opaqueAtFontSize = 9.0
    /// Room names are never drawn smaller than this when the room is big enough to hold them.
    public static let roomLabelMinimumFontSize = 11.0

    /// A paper line weight (millimetres) as a screen stroke width (points): `clamp(weight x 2.2, 0.5, 3)`.
    public static func strokeWidth(forPaperWeight millimetres: Double) -> Double {
        guard millimetres.isFinite else { return 0.5 }
        return Swift.min(Swift.max(millimetres * 2.2, 0.5), 3)
    }

    /// The font size (points) that gives text of the given cap height (model metres) at this scale.
    public static func fontSize(capHeightMetres: Double, scale: Double) -> Double {
        guard capHeightMetres.isFinite, scale.isFinite, capHeightMetres > 0, scale > 0 else { return 0 }
        return capHeightMetres * scale / HelveticaMetrics.capHeight
    }

    /// 0 below 7 pt, rising to 1 at 9 pt.
    public static func textOpacity(forFontSize size: Double) -> Double {
        guard size.isFinite else { return 0 }
        if size <= hiddenBelowFontSize { return 0 }
        if size >= opaqueAtFontSize { return 1 }
        return (size - hiddenBelowFontSize) / (opaqueAtFontSize - hiddenBelowFontSize)
    }

    /// The font size room names are drawn at: the natural size, raised to `roomLabelMinimumFontSize` when the
    /// text still fits inside its room (`textWidthAtMinimum` points wide against `roomWidthPoints`).
    public static func roomLabelFontSize(natural: Double, textWidthAtNatural: Double, roomWidthPoints: Double) -> Double {
        guard natural.isFinite, natural > 0, textWidthAtNatural.isFinite, roomWidthPoints.isFinite else { return natural }
        if natural >= roomLabelMinimumFontSize { return natural }
        let widthAtMinimum = textWidthAtNatural * roomLabelMinimumFontSize / natural
        return widthAtMinimum <= roomWidthPoints * 0.9 ? roomLabelMinimumFontSize : natural
    }

    /// Points of each dash and gap for a dashed paper line, scaled with the stroke so thin lines stay readable.
    public static func dashPattern(forStrokeWidth width: Double) -> [Double] {
        let w = Swift.max(width, 0.5)
        return [w * 6, w * 4]
    }

    /// How many straight segments approximate an arc of `sweepDegrees` and `radiusPoints`: about one every
    /// 3 points of arc length, between 6 and 120.
    public static func arcSegments(radiusPoints: Double, sweepDegrees: Double) -> Int {
        guard radiusPoints.isFinite, sweepDegrees.isFinite, radiusPoints > 0 else { return 6 }
        let length = abs(sweepDegrees) * Double.pi / 180 * radiusPoints
        return Swift.min(Swift.max(Int((length / 3).rounded(.up)), 6), 120)
    }
}
