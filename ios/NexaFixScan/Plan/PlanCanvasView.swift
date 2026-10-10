import SwiftUI
import NexaFixCore

/// The floor plan you can pan, pinch, double-tap and tap.
///
/// - Direct manipulation: a drag moves the plan exactly with the finger; a pinch zooms about the fingers. The
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
    @Binding private var selection: PlanSelection?

    @State private var cache = PlanSceneCache()
    @State private var viewport = PlanViewport(scale: 1, offset: .zero)
    @State private var hasLayout = false
    @State private var followsFit = true
    @State private var lastSize = ScreenSize(width: 0, height: 0)
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
    init(rooms: [Room], drawing: PlanDrawing, units: DisplayUnits, selection: Binding<PlanSelection?>,
         hapticsEnabled: Bool) {
        self.rooms = rooms
        self.drawing = drawing
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self._selection = selection
    }

    var body: some View {
        GeometryReader { proxy in
            let size = ScreenSize(width: Double(proxy.size.width), height: Double(proxy.size.height))
            let content = PlanContent(bounds: drawing.bounds, size: size, padding: Double(Spacing.xl))
            let scene = cache.scene(rooms: rooms, drawing: drawing, units: units)
            // Until the first layout has been committed to state, show the fitted plan directly.
            let shown = hasLayout ? viewport : PlanViewport.fit(content)

            ZStack(alignment: .topTrailing) {
                PlanLayerView(scene: scene, viewport: shown, highlight: scene.highlight(for: selection),
                              increasedContrast: contrast == .increased, interaction: interaction)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { dragChanged($0, content: content) }
                            .onEnded { _ in dragEnded(content: content) })
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { magnifyChanged($0, content: content) }
                            .onEnded { _ in magnifyEnded(content: content) })
                    .simultaneousGesture(SpatialTapGesture().onEnded { tapped(at: $0.location, scene: scene) })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in fit(content, animated: true) })
                    .accessibilityHidden(true)

                roomElements(scene, shown: shown)

                fitControl(content)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Floor plan")
            .onAppear { layoutChanged(content) }
            .onChange(of: proxy.size) { _, _ in layoutChanged(content) }
            // A new drawing (other units, a verified value) can change the extent of the labels.
            .onChange(of: drawing.bounds) { _, _ in layoutChanged(content) }
        }
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
        guard content.isUsable else { return }
        let fitted = PlanViewport.fit(content)
        if !hasLayout {
            interaction.live = fitted
            interaction.raw = fitted
            followsFit = true
            commit(fitted, animation: nil)
        } else if followsFit {
            interaction.raw = fitted
            commit(fitted, animation: nil)
        } else {
            // Keep the same part of the plan in the middle of the view (a rotation, a keyboard, a split view).
            let shift = content.size.center - lastSize.center
            let moved = interaction.live.translated(by: shift).constrained(to: content, rubberBand: false)
            interaction.raw = moved
            commit(moved, animation: nil)
        }
        lastSize = content.size
    }

    private func fit(_ content: PlanContent, animated: Bool) {
        guard content.isUsable else { return }
        let target = PlanViewport.fit(content)
        interaction.raw = target
        followsFit = true
        commit(target, animation: animated ? Motion.resolved(Motion.standard, reduceMotion: reduceMotion) : nil)
    }

    // MARK: Gestures

    private func dragChanged(_ value: DragGesture.Value, content: PlanContent) {
        if !interaction.dragActive {
            interaction.dragActive = true
            activate()
            interaction.lastTranslation = .zero
        }
        let t = value.translation
        let delta = Point2(Double(t.width - interaction.lastTranslation.width),
                           Double(t.height - interaction.lastTranslation.height))
        interaction.lastTranslation = t
        interaction.travel = max(interaction.travel, Double(hypot(t.width, t.height)))
        interaction.raw = interaction.raw.translated(by: delta)
        interaction.velocity.add(time: value.time.timeIntervalSinceReferenceDate, x: Double(t.width), y: Double(t.height))
        applyRaw(content)
    }

    private func dragEnded(content: PlanContent) {
        guard interaction.dragActive else { return }
        interaction.dragActive = false
        deactivate(content)
    }

    private func magnifyChanged(_ value: MagnifyGesture.Value, content: PlanContent) {
        if !interaction.magnifyActive {
            interaction.magnifyActive = true
            activate()
            interaction.lastMagnification = value.magnification
        }
        let last = interaction.lastMagnification
        guard last > 0, value.magnification > 0 else { return }
        let ratio = Double(value.magnification / last)
        interaction.lastMagnification = value.magnification
        let anchor = Point2(Double(value.startLocation.x), Double(value.startLocation.y))
        interaction.anchor = anchor
        interaction.didZoom = true
        interaction.raw = interaction.raw.zoomed(by: ratio, about: anchor)
        applyRaw(content)
    }

    private func magnifyEnded(content: PlanContent) {
        guard interaction.magnifyActive else { return }
        interaction.magnifyActive = false
        deactivate(content)
    }

    /// The first finger down takes over: whatever animation is running freezes at the value on screen.
    private func activate() {
        if interaction.active == 0 {
            let live = interaction.live
            interaction.raw = live
            interaction.start = live
            interaction.travel = 0
            interaction.didZoom = false
            interaction.anchor = nil
            interaction.velocity.reset()
            commit(live, animation: nil)
        }
        interaction.active += 1
    }

    private func deactivate(_ content: PlanContent) {
        interaction.active = max(0, interaction.active - 1)
        if interaction.active == 0 { settle(content) }
    }

    /// Shows the dragged or pinched plan, with rubber-banding past its limits, following the finger closely.
    private func applyRaw(_ content: PlanContent) {
        let shown = interaction.raw.constrained(to: content, rubberBand: true, anchor: interaction.anchor)
        commit(shown, animation: reduceMotion ? nil : Motion.interactive)
    }

    /// The last finger lifted: carry the flick on and bring the plan to rest inside its limits.
    private func settle(_ content: PlanContent) {
        let target: PlanViewport
        var speed = 0.0
        if interaction.travel < 3 && !interaction.didZoom {
            // A tap, not a drag: the plan stays exactly where it was (and stops, if it was gliding).
            target = interaction.start.settleTarget(velocity: .zero, content: content, momentum: false)
        } else {
            var velocity = Point2.zero
            if !interaction.didZoom {
                velocity = interaction.velocity.velocity(at: Date().timeIntervalSinceReferenceDate)
            }
            speed = velocity.length
            target = interaction.raw.settleTarget(velocity: velocity, content: content, anchor: interaction.anchor,
                                                  momentum: !reduceMotion)
        }
        interaction.raw = target
        let fitted = PlanViewport.fit(content)
        followsFit = abs(target.scale - fitted.scale) < 1e-6 * max(fitted.scale, 1)
            && target.offset.distance(to: fitted.offset) < 0.5
        // A flick gets the spring with a little life; everything else settles without bounce.
        let animation = speed > 300 ? Motion.momentum : Motion.standard
        commit(target, animation: Motion.resolved(animation, reduceMotion: reduceMotion))
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

/// What the finger is doing and the viewport on screen. A reference type held in `@State`: changing it never
/// redraws anything, it only remembers.
private final class PlanInteraction {
    /// The viewport actually drawn, written by `PlanLayerView` every frame (so it includes any animation in flight).
    var live = PlanViewport(scale: 1, offset: .zero)
    /// The viewport the fingers asked for, before rubber-banding.
    var raw = PlanViewport(scale: 1, offset: .zero)
    /// The viewport when the first finger came down.
    var start = PlanViewport(scale: 1, offset: .zero)
    var active = 0
    var dragActive = false
    var magnifyActive = false
    var lastTranslation = CGSize.zero
    var lastMagnification: CGFloat = 1
    var anchor: Point2?
    var travel = 0.0
    var didZoom = false
    var velocity = PanVelocityTracker()
}

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
