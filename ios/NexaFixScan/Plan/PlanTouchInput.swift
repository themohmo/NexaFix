import Foundation
import NexaFixCore

// What the fingers on the floor plan ask for, as plain maths: no SwiftUI and no UIKit here, so the whole of it
// compiles and is checked off-device (Foundation and NexaFixCore only).
//
// The plan used to read its fingers through SwiftUI's `DragGesture` and `MagnifyGesture` and count their
// `onEnded` callbacks. SwiftUI calls no `onEnded` for a gesture it cancels. Apple's forum answers say a second
// finger cancels a one-finger `DragGesture` (every pinch lands one), and the system taking the touches (Control
// Center, a notification pull) cancels any gesture, so the count could stay above zero and the plan was then
// never settled back inside its limits. This version is driven by the touches themselves (`PlanTouchHost`):
// UIKit ends or cancels every touch, and the plan settles when the last one is gone, whichever way it went.

// MARK: - Fingers

/// How the fingers moved since the last report: one pan and one zoom that together carry the plan point that
/// was under the fingers' centre to where their centre is now.
struct PlanTouchStep: Equatable {
    /// How far the fingers' centre moved, screen points.
    var pan: Point2
    /// How much the fingers spread apart (above 1) or closed (below 1). Exactly 1 for a single finger.
    var zoom: Double
    /// The fingers' centre before this step, screen points. The zoom is about this point.
    var from: Point2
    /// The fingers' centre now.
    var to: Point2
}

/// Follows the fingers down on the plan. It knows where each one is and reports, for every move, the pan of
/// their centre and the change in their spread, so a one finger drag and a two finger pinch-and-pan are the same
/// calculation, and the plan really pans while it zooms. When a finger comes down or lifts the centre jumps; the
/// baseline moves with it, so the plan never does.
struct PlanTouchTracker<ID: Hashable> {
    private struct Frame {
        var centre: Point2
        /// Mean distance of the fingers from their centre; 0 for one finger.
        var spread: Double
    }

    private var points: [ID: Point2] = [:]
    private var reported: Frame?

    /// Fingers whose mean distance from their centre is under this many points (two fingers about 4 points
    /// apart) give no zoom: a ratio of two tiny numbers is noise.
    private static func minimumSpread() -> Double { 2 }

    /// How many fingers are down.
    var count: Int { points.count }

    /// A finger came down at `point` (screen points). True when it is the first of the touch.
    @discardableResult
    mutating func add(_ id: ID, at point: Point2) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let wasEmpty = points.isEmpty
        points[id] = point
        reported = frame()
        return wasEmpty
    }

    /// Fingers are now at these points. Returns what changed since the last report, nil when nothing did.
    /// Fingers it does not know are ignored.
    mutating func move(_ moved: [(id: ID, point: Point2)]) -> PlanTouchStep? {
        for item in moved where points[item.id] != nil && item.point.x.isFinite && item.point.y.isFinite {
            points[item.id] = item.point
        }
        guard let before = reported, let now = frame() else { return nil }
        reported = now
        var zoom = 1.0
        let minimum = PlanTouchTracker.minimumSpread()
        if points.count >= 2, before.spread >= minimum, now.spread >= minimum {
            zoom = now.spread / before.spread
        }
        let pan = now.centre - before.centre
        if zoom == 1 && pan.x == 0 && pan.y == 0 { return nil }
        return PlanTouchStep(pan: pan, zoom: zoom, from: before.centre, to: now.centre)
    }

    /// These fingers lifted (or were taken by the system). True when that was the last one.
    @discardableResult
    mutating func remove(_ ids: [ID]) -> Bool {
        let hadTouches = !points.isEmpty
        for id in ids { points[id] = nil }
        reported = frame()
        return hadTouches && points.isEmpty
    }

    /// Forgets every finger. True when there was one.
    @discardableResult
    mutating func removeAll() -> Bool {
        let hadTouches = !points.isEmpty
        points.removeAll()
        reported = nil
        return hadTouches
    }

    private func frame() -> Frame? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        var sumX = 0.0, sumY = 0.0
        for p in points.values {
            sumX += p.x
            sumY += p.y
        }
        let centre = Point2(sumX / n, sumY / n)
        var spread = 0.0
        for p in points.values { spread += p.distance(to: centre) }
        return Frame(centre: centre, spread: spread / n)
    }
}

// MARK: - The plan under the fingers

/// What the fingers are doing and the viewport on screen. A reference type held in `@State`: changing it never
/// redraws anything, it only remembers.
///
/// One touch is everything between the first finger coming down and the last one going (lifted, or taken by the
/// system): `begin()`, any number of `move(_:time:)`, then `finish(...)` exactly once. `begin()` always starts
/// from clean state, so nothing from an earlier touch can leak into the next.
final class PlanInteraction {
    /// The viewport actually drawn, written by the plan's layer every frame (so it includes any animation in flight).
    var live = PlanViewport(scale: 1, offset: .zero)
    /// The viewport the fingers asked for, before rubber-banding.
    var raw = PlanViewport(scale: 1, offset: .zero)
    /// The viewport when the first finger came down.
    private(set) var start = PlanViewport(scale: 1, offset: .zero)
    /// A finger is down.
    private(set) var isTouching = false
    /// The fingers' centre at the last move: what stays put while the scale is held inside its limits.
    private(set) var anchor: Point2?

    private var path = Point2.zero
    private var travel = 0.0
    private var didZoom = false
    private var velocity = PanVelocityTracker()
    private var fitRequested = false

    /// Where a touch moved the plan this little still counts as a tap, points.
    private static let tapTravel = 3.0
    /// Where a touch moved the plan this much is a drag that happens to end like a tap, points: not a selection.
    private static let dragTravel = 10.0
    /// A change of scale of this much (as a natural logarithm: 3 %) makes the touch a zoom.
    private static let zoomThreshold = 0.03

    /// The first finger came down. Whatever animation is running freezes at the value on screen: returns it, for the
    /// caller to show without animation.
    func begin() -> PlanViewport {
        isTouching = true
        raw = live
        start = live
        anchor = nil
        path = .zero
        travel = 0
        didZoom = false
        fitRequested = false
        velocity.reset()
        return live
    }

    /// The fingers moved: the viewport they ask for follows.
    func move(_ step: PlanTouchStep, time: TimeInterval) {
        guard isTouching else { return }
        raw = raw.zoomed(by: step.zoom, about: step.from).translated(by: step.pan)
        anchor = step.to
        path = path + step.pan
        travel = max(travel, path.length)
        if !didZoom, start.scale > 0, raw.scale > 0, abs(log(raw.scale / start.scale)) > PlanInteraction.zoomThreshold {
            didZoom = true
        }
        velocity.add(time: time, x: path.x, y: path.y)
    }

    /// Where the plan comes to rest, and how fast it was thrown.
    struct Settlement {
        var target: PlanViewport
        /// Points per second the plan was flicked at; 0 for a tap or a zoom.
        var speed: Double
    }

    /// The last finger is gone.
    ///
    /// - Parameters:
    ///   - time: When it lifted, on the clock of the touches' timestamps. nil when the system took the touches
    ///     (so there is no flick, only the return inside the limits).
    ///   - momentum: false with Reduce Motion: nothing is thrown, the plan only returns inside its limits.
    /// - Returns: Where to settle, or nil when a fit was asked for during this touch (a double tap lifts the finger
    ///   and asks for the fit in the same instant, and the order of the two is not documented): the fit stands.
    func finish(content: PlanContent, time: TimeInterval?, momentum: Bool) -> Settlement? {
        isTouching = false
        if fitRequested { return nil }
        let target: PlanViewport
        var speed = 0.0
        if travel < PlanInteraction.tapTravel && !didZoom {
            // A tap, not a drag: the plan stays exactly where it was (and stops, if it was gliding).
            target = start.settleTarget(velocity: .zero, content: content, momentum: false)
        } else {
            var flick = Point2.zero
            if !didZoom, let time { flick = velocity.velocity(at: time) }
            speed = flick.length
            target = raw.settleTarget(velocity: flick, content: content, anchor: anchor, momentum: momentum)
        }
        raw = target
        return Settlement(target: target, speed: speed)
    }

    /// The whole plan was brought into view (double tap, the Fit control). Until the next touch begins, the
    /// end of the current one does not settle over it.
    func fit(to target: PlanViewport) {
        raw = target
        fitRequested = true
    }

    /// This touch moved or zoomed the plan far enough to have been a drag, not a tap. A tap recogniser is lenient
    /// about a finger that moves a little; such a touch must not also select what is under the finger now.
    var wasDrag: Bool { travel >= PlanInteraction.dragTravel || didZoom }
}
