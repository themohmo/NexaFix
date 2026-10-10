import SwiftUI
import NexaFixCore

/// The floor plan you can pan, pinch, double-tap and tap.
///
/// - Direct manipulation: a drag moves the plan exactly with the finger; a pinch zooms about the fingers, and
///   pans with them while it does. The fingers are read from the touches by `PlanTouchHost` (UIKit ends or
///   cancels every touch exactly once, so the plan always settles when the last finger is gone, however the touch
///   ended); the maths of the fingers is `PlanTouchTracker` and `PlanInteraction` in PlanTouchInput.swift. The
///   viewport maths (zoom about an anchor, rubber band past the drawing and the zoom limits, where a flick comes
///   to rest) is `PlanViewport` in NexaFixCore, with its own tests.
/// - Interruptible: the plan is drawn by `PlanLayerView`, an `Animatable` view that reports the viewport actually
///   on screen. A new touch while the plan is still gliding freezes it exactly there and carries on from that
///   value, so nothing ever jumps or blocks a gesture.
/// - Springs: `Motion.interactive` while a finger is down, `Motion.momentum` after a flick, `Motion.standard`
///   otherwise. With Reduce Motion there is no momentum and no spring.
/// - A tap selects the corner, door or window, wall, piece of furniture or room under it, within 22 points of
///   finger (converted to metres at the current zoom); a tap on nothing clears the selection.
/// - A double tap, or the Fit control that appears once the plan has been moved or zoomed, brings the whole plan
///   back into view.
struct PlanCanvasView: View {
    private let rooms: [Room]
    private let drawing: PlanDrawing
    private let units: DisplayUnits
    private let hapticsEnabled: Bool
    private let bottomInset: CGFloat
    @Binding private var selection: PlanSelection?

    @State private var cache = PlanSceneCache()
    @State private var viewport = PlanViewport(scale: 1, offset: .zero)
    @State private var hasLayout = false
    @State private var followsFit = true
    @State private var lastContent: PlanContent?
    @State private var interaction = PlanInteraction()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// How far a fingertip reaches on the plan, points.
    private static let touchRadius = 22.0

    /// - Parameters:
    ///   - rooms: The rooms of the level, for selecting and for the room names and areas on the plan.
    ///   - drawing: The plan to draw (`PlanDrawingBuilder`), in metres.
    ///   - units: How lengths and areas are written on the plan and in the selection's description.
    ///   - selection: What is selected; the plan sets it on a tap, the caller may set it too.
    ///   - hapticsEnabled: The Settings switch. The only haptic here is the tick when a tap snaps to a corner.
    ///   - bottomInset: Height of whatever floats over the bottom of the view (the selection card), points. The
    ///     plan is fitted, panned and zoomed within the part of the view above it, so nothing on the plan can be
    ///     hidden under it and everything can be moved clear of it. Never more than half the view. 0 for none.
    init(rooms: [Room], drawing: PlanDrawing, units: DisplayUnits, selection: Binding<PlanSelection?>,
         hapticsEnabled: Bool, bottomInset: CGFloat = 0) {
        self.rooms = rooms
        self.drawing = drawing
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self.bottomInset = bottomInset
        self._selection = selection
    }

    var body: some View {
        GeometryReader { proxy in
            // The plan lives in the part of the view above whatever floats over its bottom.
            let height = Double(proxy.size.height)
            let reserved = PlanCanvasView.reservedHeight(bottomInset, in: height)
            let size = ScreenSize(width: Double(proxy.size.width), height: height - reserved)
            let content = PlanContent(bounds: drawing.bounds, size: size, padding: Double(Spacing.xl))
            let scene = cache.scene(rooms: rooms, drawing: drawing, units: units)
            // Until the first layout has been committed to state, show the fitted plan directly.
            let shown = hasLayout ? viewport : PlanViewport.fit(content)

            ZStack(alignment: .topTrailing) {
                PlanLayerView(scene: scene, viewport: shown, highlight: scene.highlight(for: selection),
                              increasedContrast: contrast == .increased, interaction: interaction)
                    .overlay { PlanTouchHost(handlers: touchHandlers(content: content, scene: scene)) }
                    .accessibilityHidden(true)

                roomElements(scene, shown: shown)

                fitControl(content)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Floor plan")
            .accessibilityIdentifier("plan.canvas")
            .onAppear { layoutChanged(content) }
            // The view turning, or the card rising over the bottom of it.
            .onChange(of: size) { _, _ in layoutChanged(content) }
            // A new drawing (other units, a verified value) can change the extent of the labels.
            .onChange(of: drawing.bounds) { _, _ in layoutChanged(content) }
        }
    }

    /// How much of a view `height` points tall is given to what floats over its bottom: `inset`, but never more
    /// than half the view, so the plan always keeps room.
    private static func reservedHeight(_ inset: CGFloat, in height: Double) -> Double {
        guard inset.isFinite, height.isFinite, height > 0 else { return 0 }
        return Swift.min(Swift.max(Double(inset), 0), height / 2)
    }

    // MARK: Fit control

    /// "Fit plan to screen" shows only once the plan has been moved or zoomed away from the fitted view, as the
    /// recentre control does in Maps. While the plan is fitted it would only sit over the plan's top corner, and
    /// there is nothing for it to do. Double-tapping the plan also fits it.
    private func fitControl(_ content: PlanContent) -> some View {
        Group {
            if !followsFit {
                GlassIconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Fit plan to screen") {
                    fit(content, animated: true)
                }
                .padding(Spacing.m)
                .transition(.fadeScale)
            }
        }
        // On the control alone: an animation on the whole plan would take over the flick's own spring.
        .motion(value: followsFit)
    }

    // MARK: VoiceOver

    /// One element per room, laid over the room, so VoiceOver can walk the plan room by room instead of
    /// meeting a single picture. The elements do not take touches.
    private func roomElements(_ scene: PlanScene, shown: PlanViewport) -> some View {
        ZStack {
            ForEach(scene.elements) { element in
                let frame = PlanCanvasView.frame(of: element.bounds, in: shown)
                let isSelected = selection == .room(element.id)
                // The element is described first and placed last: `position` returns a view as big as the whole
                // plan, so anything attached after it would be framed as the whole plan, not as this room.
                Color.clear
                    .frame(width: max(frame.width, 44), height: max(frame.height, 44))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(element.title)
                    .accessibilityValue(element.spoken)
                    .accessibilityHint("Selects the room")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = .room(element.id) }
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private static func frame(of bounds: Bounds2, in viewport: PlanViewport) -> CGRect {
        let topLeft = viewport.screen(Point2(bounds.min.x, bounds.max.y))
        let bottomRight = viewport.screen(Point2(bounds.max.x, bounds.min.y))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    // MARK: Layout

    private func layoutChanged(_ content: PlanContent) {
        guard content.isUsable, content != lastContent else { return }
        let fitted = PlanViewport.fit(content)
        if !hasLayout {
            interaction.live = fitted
            interaction.raw = fitted
            followsFit = true
            commit(fitted, animation: nil)
        } else {
            // Only the height changed (the card over the bottom rising or leaving): ease to the new fit. A
            // rotation or a split view changes the width too and jumps, because the old picture no longer fits.
            let easing = lastContent.map { $0.bounds == content.bounds && abs($0.size.width - content.size.width) < 0.5 }
                ?? false
            let animation = easing ? Motion.resolved(Motion.standard, reduceMotion: reduceMotion) : nil
            if followsFit {
                interaction.raw = fitted
                commit(fitted, animation: animation)
            } else {
                // Keep the same part of the plan in the middle of the view (a rotation, a keyboard, a split view).
                let previous = lastContent?.size ?? content.size
                let shift = content.size.center - previous.center
                let moved = interaction.live.translated(by: shift).constrained(to: content, rubberBand: false)
                interaction.raw = moved
                commit(moved, animation: animation)
            }
        }
        lastContent = content
    }

    private func fit(_ content: PlanContent, animated: Bool) {
        guard content.isUsable else { return }
        let target = PlanViewport.fit(content)
        interaction.fit(to: target)
        followsFit = true
        commit(target, animation: animated ? Motion.resolved(Motion.standard, reduceMotion: reduceMotion) : nil)
    }

    // MARK: Touches

    /// What the touch layer reports, tied to the layout it was made for.
    private func touchHandlers(content: PlanContent, scene: PlanScene) -> PlanTouchHandlers {
        PlanTouchHandlers(
            began: { touchBegan() },
            moved: { step, time in touchMoved(step, time: time, content: content) },
            ended: { time in touchEnded(at: time, content: content) },
            tapped: { location in tapped(at: location, scene: scene) },
            doubleTapped: { fit(content, animated: true) })
    }

    /// The first finger down takes over: whatever animation is running freezes at the value on screen.
    private func touchBegan() {
        commit(interaction.begin(), animation: nil)
    }

    private func touchMoved(_ step: PlanTouchStep, time: TimeInterval, content: PlanContent) {
        guard interaction.isTouching else { return }
        interaction.move(step, time: time)
        applyRaw(content)
    }

    /// The last finger is gone, lifted or taken by the system: carry the flick on and bring the plan to rest
    /// inside its limits.
    private func touchEnded(at time: TimeInterval?, content: PlanContent) {
        guard interaction.isTouching else { return }
        // Nothing to settle when the whole plan was brought into view while the finger was down (a double tap).
        guard let settlement = interaction.finish(content: content, time: time, momentum: !reduceMotion) else { return }
        let target = settlement.target
        let fitted = PlanViewport.fit(content)
        followsFit = abs(target.scale - fitted.scale) < 1e-6 * max(fitted.scale, 1)
            && target.offset.distance(to: fitted.offset) < 0.5
        // A flick gets the spring with a little life; everything else settles without bounce.
        let animation = settlement.speed > 300 ? Motion.momentum : Motion.standard
        commit(target, animation: Motion.resolved(animation, reduceMotion: reduceMotion))
    }

    /// Shows the dragged or pinched plan, with rubber-banding past its limits, following the fingers closely.
    private func applyRaw(_ content: PlanContent) {
        let shown = interaction.raw.constrained(to: content, rubberBand: true, anchor: interaction.anchor)
        commit(shown, animation: reduceMotion ? nil : Motion.interactive)
    }

    private func commit(_ target: PlanViewport, animation: Animation?) {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) {
            viewport = target
            hasLayout = true
        }
    }

    // MARK: Selecting

    private func tapped(at location: CGPoint, scene: PlanScene) {
        // A finger that slid a little and lifted can still count as a tap to the recogniser; it was a drag.
        guard !interaction.wasDrag else { return }
        // What the person saw when they tapped, even if the plan was still settling.
        let live = interaction.live
        let plan = live.plan(Point2(Double(location.x), Double(location.y)))
        let hit = scene.tester.hit(at: plan, toleranceMetres: live.metres(forPoints: PlanCanvasView.touchRadius))
        if hit != selection {
            // DESIGN.md allows a tick for "snaps to a corner" and nothing else on this screen: a tap that lands on
            // a corner point is that moment; selecting a wall, room, opening or object is silent.
            if case .corner? = hit, hapticsEnabled { Haptics.selection() }
            selection = hit
        }
    }
}

// MARK: - The animated layer

/// Draws the plan. Conforming to `Animatable` makes SwiftUI feed it the in-between viewport on every frame of
/// an animation, which is what lets a new touch pick the plan up exactly where it is.
private struct PlanLayerView: View, Animatable {
    let scene: PlanScene
    var viewport: PlanViewport
    let highlight: PlanHighlight?
    let increasedContrast: Bool
    let interaction: PlanInteraction

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(viewport.scale, AnimatablePair(viewport.offset.x, viewport.offset.y)) }
        set {
            viewport = PlanViewport(scale: newValue.first,
                                    offset: Point2(newValue.second.first, newValue.second.second))
        }
    }

    var body: some View {
        Canvas { context, size in
            interaction.live = viewport
            scene.renderer.draw(&context, size: size, viewport: viewport, highlight: highlight,
                                increasedContrast: increasedContrast)
        }
    }
}

// MARK: - Prepared scene

/// A room as VoiceOver meets it.
private struct PlanRoomElement: Identifiable {
    let id: UUID
    let title: String
    let spoken: String
    let bounds: Bounds2
}

/// Everything built from the rooms and the drawing once: the renderer, the hit tester and the VoiceOver elements.
private final class PlanScene {
    let renderer: PlanRenderer
    let tester: PlanHitTester
    let elements: [PlanRoomElement]

    init(rooms: [Room], drawing: PlanDrawing, units: DisplayUnits) {
        let tester = PlanHitTester(rooms: rooms)
        self.tester = tester
        self.renderer = PlanRenderer(drawing: drawing, rooms: rooms, units: units)
        self.elements = rooms.compactMap { room in
            guard let box = Bounds2(points: room.outline),
                  let summary = tester.summary(for: .room(room.id), units: units) else { return nil }
            return PlanRoomElement(id: room.id, title: summary.title, spoken: summary.spoken, bounds: box)
        }
    }

    func highlight(for selection: PlanSelection?) -> PlanHighlight? {
        selection.flatMap { tester.highlight(for: $0) }
    }
}

/// Builds a `PlanScene` when its inputs change and hands back the same one otherwise. `init` of a view runs
/// every time its parent redraws; the scene must not.
private final class PlanSceneCache {
    private var rooms: [Room] = []
    private var primitives: [LayeredPrimitive] = []
    private var units: DisplayUnits?
    private var scene: PlanScene?

    func scene(rooms: [Room], drawing: PlanDrawing, units: DisplayUnits) -> PlanScene {
        if let scene, self.units == units, self.rooms == rooms, primitives == drawing.primitives { return scene }
        let built = PlanScene(rooms: rooms, drawing: drawing, units: units)
        self.rooms = rooms
        self.primitives = drawing.primitives
        self.units = units
        self.scene = built
        return built
    }
}
