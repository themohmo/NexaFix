import SwiftUI
import UIKit
import NexaFixCore

// The touch layer of the floor plan: a transparent UIKit view laid over the drawing.
//
// Pan and pinch are read from the touches themselves (`touchesBegan` / `Moved` / `Ended` / `Cancelled`), not
// from gesture recognisers, for one reason: UIKit ends or cancels every touch exactly once, so "the last finger
// is gone" is always reported, however the touch ended (lifted, a second finger, Control Center, a sheet coming
// up, the view leaving the window). Recognisers only report that when they had recognised something. The maths
// (`PlanTouchTracker`, `PlanInteraction`) is plain Swift in PlanTouchInput.swift.
//
// A tap and a double tap are ordinary `UITapGestureRecognizer`s, which know best what a tap is. They are set up
// not to hold anything back from the touches:
//   - `cancelsTouchesInView = false`: otherwise recognising a tap would send the view `touchesCancelled` in
//     place of `touchesEnded` (Apple: "previously delivered touches are canceled").
//   - `delaysTouchesEnded = false`: otherwise, while the double-tap recogniser waits for a second tap, the
//     window would hold back the first tap's `touchesEnded` (Apple: it is delivered only once the recogniser
//     fails).
// and the view's `isMultipleTouchEnabled` is true: without it the view is sent only the first finger of a
// multi-touch sequence and a pinch never reaches it.

/// What the plan's touch layer reports. All calls arrive on the main thread.
struct PlanTouchHandlers {
    /// The first finger came down.
    var began: () -> Void
    /// The fingers moved, and the time of the touches that moved (seconds on the clock of `UITouch.timestamp`).
    var moved: (PlanTouchStep, TimeInterval) -> Void
    /// The last finger is gone: when it lifted, or nil when the system took the touches.
    var ended: (TimeInterval?) -> Void
    /// A single tap, in the layer's own coordinates (the same as the drawing's).
    var tapped: (CGPoint) -> Void
    /// A double tap.
    var doubleTapped: () -> Void
}

/// Puts the touch layer over a view. It takes the size it is offered, like the drawing under it.
struct PlanTouchHost: UIViewRepresentable {
    let handlers: PlanTouchHandlers

    func makeUIView(context: Context) -> PlanTouchView {
        PlanTouchView(frame: .zero)
    }

    func updateUIView(_ view: PlanTouchView, context: Context) {
        // The handlers capture the plan's current layout; they are replaced on every update.
        view.handlers = handlers
    }
}

@MainActor
final class PlanTouchView: UIView, UIGestureRecognizerDelegate {
    var handlers: PlanTouchHandlers?

    private var tracker = PlanTouchTracker<ObjectIdentifier>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // The picture underneath is described to VoiceOver by the room elements laid over it; this layer says nothing.
        isAccessibilityElement = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        for recognizer in [tap, doubleTap] {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var first = false
        for touch in touches {
            if tracker.add(ObjectIdentifier(touch), at: point(of: touch)) { first = true }
        }
        if first { handlers?.began() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Where the fingers were when they lifted may be a little past the last move.
        report(touches)
        if tracker.remove(touches.map { ObjectIdentifier($0) }) {
            handlers?.ended(timestamp(of: touches))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if tracker.remove(touches.map { ObjectIdentifier($0) }) {
            handlers?.ended(nil)
        }
    }

    /// Off the screen mid-touch (a sheet, another tab): UIKit cancels the touches, and this makes sure of it.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window == nil else { return }
        if tracker.removeAll() { handlers?.ended(nil) }
    }

    private func report(_ touches: Set<UITouch>) {
        let moved = touches.map { (id: ObjectIdentifier($0), point: point(of: $0)) }
        guard let step = tracker.move(moved) else { return }
        handlers?.moved(step, timestamp(of: touches))
    }

    private func point(of touch: UITouch) -> Point2 {
        let p = touch.location(in: self)
        return Point2(Double(p.x), Double(p.y))
    }

    private func timestamp(of touches: Set<UITouch>) -> TimeInterval {
        touches.map { $0.timestamp }.max() ?? 0
    }

    // MARK: Taps

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        handlers?.tapped(recognizer.location(in: self))
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        handlers?.doubleTapped()
    }

    /// A tap and a double tap are both wanted for the second tap of a double tap; neither waits for the other.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
