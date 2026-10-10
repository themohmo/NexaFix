import Foundation
import Observation
import NexaFixCore

/// Everything the 3D viewer needs that is not drawing: the model, the orbit camera, picking, the tape measure
/// and saving.
///
/// The thinking lives in NexaFixCore and is unit-tested there: `RoomSceneBuilder` (the model with real door and
/// window openings), `SceneCamera` / `SceneCameraAnimator` / `OrbitInertia` (the camera), `ScenePicker`
/// (what is under a tap, snapped to corners and edges), `TapeMeasureSession` (the two points) and
/// `MeasurementRoomLocator` (which room a measurement is kept in). This class connects them to the screen.
///
/// Honesty rule: a tape measurement is read off the scanned model, so it is always a SCANNED number. It is
/// saved without a verification and shown with the scanned badge; it only becomes verified when a person
/// checks it with a laser afterwards. Points can only be placed on scan-derived surfaces or on corners and
/// edges of the scan, never on the outside of a wall or a frame the model made up.
///
/// Threading: the controller lives on the main actor, like the gestures, the display link and the views that
/// drive it. It imports no UI framework, so the whole class is checked on Linux against the real NexaFixCore;
/// everything it needs from the screen (the camera, a projection, a ray, the VoiceOver announcement) is a closure
/// the host supplies.
@MainActor @Observable
final class Viewer3DController {

    /// How the walls are drawn and how taps treat them.
    enum WallStyle: Equatable {
        case solid
        /// Walls are drawn faint and taps pass through the made-up outer faces to the room behind.
        case seeThrough
    }

    // MARK: Observed state

    private(set) var rooms: [Room]
    private(set) var units: DisplayUnits
    /// Bumped whenever the model has to be rebuilt in the renderer.
    private(set) var sceneVersion = 0
    private(set) var showsCeiling = false
    private(set) var wallStyle: WallStyle = .solid
    private(set) var showsLabels = true
    private(set) var isMeasuring = false
    /// The two tape points.
    private(set) var tape = TapeMeasureSession()
    /// The "name this measurement" alert is open.
    private(set) var isNaming = false
    /// A short message that clears itself, such as "That surface was not scanned."
    private(set) var notice: String?
    /// The labels and saved tape lines of the floor.
    private(set) var overlay: OverlayScene = .empty
    /// Bumped whenever the label layer has to redraw: the camera moved, or a switch changed what can be seen.
    private(set) var drawRevision = 0
    /// There is nothing to show: the floor has no rooms that could be built.
    private(set) var hasNoModel = false
    /// The renderer could not turn some or all of the model into something it can draw.
    private(set) var drawProblem: DrawProblem?

    /// How much of the model the renderer failed to draw.
    enum DrawProblem: Equatable {
        /// Some parts are missing.
        case partial
        /// Nothing could be drawn.
        case whole
    }

    // MARK: Plumbing (never triggers a redraw)

    @ObservationIgnored var hapticsEnabled: Bool
    /// The Reduce Motion setting: no inertia and no gliding between views.
    @ObservationIgnored var reduceMotion = false
    /// On iOS 18 and later the renderer's field of view is applied vertically (the renderer sets that
    /// explicitly), so framing can be exact. Before that it is not known, and framing leaves more room.
    @ObservationIgnored var verticalFieldOfViewKnown = false

    @ObservationIgnored private let focusRoomID: UUID?
    @ObservationIgnored private let saveHandler: (CustomMeasurement, UUID) -> Void
    @ObservationIgnored private let closeHandler: () -> Void

    /// Set by the renderer's host: puts the camera on screen.
    @ObservationIgnored var cameraSink: (@MainActor (SceneCamera) -> Void)?
    /// Set by the renderer's host: a world point to a point in the view, nil when it is behind the camera.
    @ObservationIgnored var projector: (@MainActor (Point3) -> CGPoint?)?
    /// Set by the renderer's host: the ray through a point in the view.
    @ObservationIgnored var rayFactory: (@MainActor (CGPoint) -> Ray3?)?
    /// Set by the renderer's host: start the per-frame ticker (inertia or a glide is about to run).
    @ObservationIgnored var motionStarted: (@MainActor () -> Void)?
    /// Set by the view: says something to VoiceOver ("First point set.").
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?

    @ObservationIgnored private(set) var camera = SceneCamera(target: .zero, distance: 6)
    @ObservationIgnored private(set) var viewSize = CGSize.zero
    /// The whole model, ceiling included. The renderer builds from this.
    @ObservationIgnored private(set) var fullScene = RoomScene.empty
    /// What taps and framing see: `fullScene` without the ceiling while it is switched off.
    @ObservationIgnored private(set) var pickScene = RoomScene.empty

    @ObservationIgnored private var snapPoints: [SnapPoint] = []
    @ObservationIgnored private var snapEdges: [SnapEdge] = []
    @ObservationIgnored private var snapNotes: [String?] = []
    @ObservationIgnored private var localSaved: [LocalSave] = []
    @ObservationIgnored private var animator = SceneCameraAnimator(camera: SceneCamera(target: .zero, distance: 6))
    @ObservationIgnored private var isGliding = false
    /// Where the running glide is heading, so a second request while it runs starts from the destination.
    @ObservationIgnored private var glideTarget: SceneCamera?
    @ObservationIgnored private var inertia: OrbitInertia?
    @ObservationIgnored private var cameraIsDefault = true
    @ObservationIgnored private var hasFramed = false
    @ObservationIgnored private var didPrepare = false
    @ObservationIgnored private var noticeToken = 0
    @ObservationIgnored private var overlayVersion = 0
    @ObservationIgnored private var labelKey: LabelKey?
    @ObservationIgnored private var cachedLabels: [OverlayLabel] = []

    private struct LocalSave {
        let measurement: CustomMeasurement
        let roomID: UUID
    }

    /// What the visible-label list was computed for. Labels are re-tested only when one of these changes.
    private struct LabelKey: Equatable {
        var x: Int
        var y: Int
        var z: Int
        var seeThrough: Bool
        var ceiling: Bool
        var overlay: Int
        var scene: Int
    }

    /// Orbit speed: degrees of turn per point of finger travel.
    private static let degreesPerPoint = 0.35

    // MARK: Init

    /// Cheap on purpose: SwiftUI may build and discard several of these. The model is built in `prepare()`.
    init(floor: Floor, units: DisplayUnits, hapticsEnabled: Bool, focusRoomID: UUID?,
         onSaveMeasurement: @escaping (CustomMeasurement, UUID) -> Void, onClose: @escaping () -> Void) {
        self.rooms = floor.rooms
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self.focusRoomID = focusRoomID
        self.saveHandler = onSaveMeasurement
        self.closeHandler = onClose
    }

    // MARK: Lifecycle

    /// Builds the model and the labels. Safe to call more than once.
    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        rebuildScene()
        rebuildOverlay()
        frameIfReady()
    }

    func close() {
        closeHandler()
    }

    /// The floor changed (a measurement was saved, a value was checked). The model is rebuilt only if the
    /// geometry changed; saved tape lines and labels are always refreshed.
    func update(floor: Floor) {
        guard floor.rooms != rooms else { return }
        let geometryChanged = Viewer3DController.geometry(of: floor.rooms) != Viewer3DController.geometry(of: rooms)
        rooms = floor.rooms
        // Anything the floor now contains no longer needs to be remembered here.
        localSaved.removeAll { local in
            rooms.contains { $0.customMeasurements.contains { $0.id == local.measurement.id } }
        }
        if geometryChanged { rebuildScene() }
        rebuildOverlay()
    }

    func update(units newUnits: DisplayUnits) {
        guard newUnits != units else { return }
        units = newUnits
        rebuildOverlay()
    }

    /// The rooms with everything that does not change the model removed, to tell a new scan from a new note.
    private static func geometry(of rooms: [Room]) -> [Room] {
        rooms.map { room in
            var copy = room
            copy.customMeasurements = []
            copy.notes = ""
            return copy
        }
    }

    // MARK: Building

    private func rebuildScene() {
        fullScene = RoomSceneBuilder.scene(for: rooms, options: SceneOptions(includeCeiling: true))
        snapPoints = rooms.flatMap { $0.snapPoints() }
        snapEdges = ScenePicker.cornerEdges(for: rooms)
        refreshPickScene()
        hasNoModel = fullScene.isEmpty
        drawProblem = nil
        sceneVersion += 1
        // Points placed on the old model may not exist on the new one.
        clearTape()
    }

    private func refreshPickScene() {
        pickScene = showsCeiling ? fullScene : fullScene.without([.ceiling])
        labelKey = nil
    }

    private func rebuildOverlay() {
        var withSaved = rooms
        for local in localSaved {
            guard let i = withSaved.firstIndex(where: { $0.id == local.roomID }),
                  !withSaved[i].customMeasurements.contains(where: { $0.id == local.measurement.id }) else { continue }
            withSaved[i].customMeasurements.append(local.measurement)
        }
        let options = OverlayOptions(showWireframe: false, showDimensions: true, showAngles: false,
                                     showOpenings: true, showHeights: true, showArea: true)
        overlay = OverlayBuilder.scene(for: withSaved, options: options, units: units, highlightRoomID: focusRoomID)
        overlayVersion += 1
        labelKey = nil
    }

    // MARK: Toggles

    func toggleCeiling() {
        showsCeiling.toggle()
        refreshPickScene()
        // Labels hidden by the ceiling or let through it have to be sorted out again.
        drawRevision += 1
        if cameraIsDefault { frame(animated: false) }
    }

    func toggleWallStyle() {
        wallStyle = wallStyle == .solid ? .seeThrough : .solid
        labelKey = nil
        // Solid walls hide the labels behind them, see-through walls do not: redraw the labels now.
        drawRevision += 1
    }

    func toggleLabels() {
        showsLabels.toggle()
    }

    // MARK: Camera

    /// Told by the view whenever its size is known or changes.
    func viewSizeChanged(_ size: CGSize) {
        guard size.width > 1, size.height > 1, size != viewSize else { return }
        viewSize = size
        if hasFramed {
            // A rotation or a split view: keep an untouched view framed, leave a chosen view alone.
            if cameraIsDefault { frame(animated: false) }
        } else {
            frameIfReady()
        }
    }

    /// Called by the host once the renderer exists: puts the current camera on screen.
    func rendererAttached() {
        cameraSink?(camera)
    }

    /// The renderer built the model: of `batches` pieces, `failed` could not be drawn. All of them failing leaves
    /// a blank picture, and the person is told so rather than left looking at nothing.
    func rendererBuilt(batches: Int, failed: Int) {
        let problem: DrawProblem? = failed <= 0 ? nil : (failed >= batches ? .whole : .partial)
        if problem != drawProblem { drawProblem = problem }
    }

    private func frameIfReady() {
        guard !hasFramed, !fullScene.isEmpty, viewSize.width > 1, viewSize.height > 1 else { return }
        hasFramed = true
        camera = framingCamera(forRoom: focusRoomID)
        animator.snap(to: camera)
        cameraIsDefault = true
        pushCamera()
    }

    private func framingCamera(forRoom roomID: UUID?) -> SceneCamera {
        let aspect = Double(viewSize.width / max(viewSize.height, 1))
        return pickScene.camera(framingRoom: roomID, aspect: aspect, verticalFieldOfViewKnown: verticalFieldOfViewKnown)
    }

    /// Frames the whole floor (or, first time, the room that was open).
    func frame(animated: Bool) {
        let target = framingCamera(forRoom: hasFramed ? nil : focusRoomID)
        cameraIsDefault = true
        move(to: target, animated: animated)
    }

    /// Frames every room: the "show everything" button and the double tap.
    func showWholeFloor() {
        frame(animated: true)
    }

    private func move(to target: SceneCamera, animated: Bool) {
        inertia = nil
        if animated && !reduceMotion {
            // A glide already under way is re-aimed, not restarted: its speed carries over, so repeated requests
            // (VoiceOver's "Turn left" again and again) bend the motion instead of jerking it.
            if !isGliding { animator = SceneCameraAnimator(camera: camera) }
            animator.move(to: target)
            glideTarget = target
            isGliding = true
            motionStarted?()
        } else {
            isGliding = false
            glideTarget = nil
            camera = target
            animator.snap(to: target)
            pushCamera()
        }
    }

    private func pushCamera() {
        cameraSink?(camera)
        drawRevision += 1
    }

    /// A finger came down: whatever the camera was still doing stops where it is.
    func beginCameraInteraction() {
        inertia = nil
        if isGliding {
            isGliding = false
            glideTarget = nil
            camera = animator.camera
            animator.snap(to: camera)
        }
    }

    /// One finger dragging: turn the model like a turntable.
    func orbit(dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        cameraIsDefault = false
        camera = camera.orbited(yawDelta: -dx * Viewer3DController.degreesPerPoint,
                                pitchDelta: dy * Viewer3DController.degreesPerPoint)
        pushCamera()
    }

    /// The finger lifted with this speed (points per second): keep turning, slowing down.
    func endOrbit(velocityX: Double, velocityY: Double) {
        guard !reduceMotion else { return }
        let next = OrbitInertia(yawVelocity: -velocityX * Viewer3DController.degreesPerPoint,
                                pitchVelocity: velocityY * Viewer3DController.degreesPerPoint)
        guard next.isMoving else { return }
        inertia = next
        motionStarted?()
    }

    /// Two fingers dragging: slide along the floor so the floor follows the fingers.
    func panCamera(dx: Double, dy: Double) {
        cameraIsDefault = false
        var moved = camera.dragged(dx: dx, dy: dy, viewHeight: Double(viewSize.height))
        // Not far past the model: the target stays inside the model's box grown by half its size.
        let lo = pickScene.boundsMin, hi = pickScene.boundsMax
        let margin = max(pickScene.diagonal * 0.5, 1)
        moved.target = Point3(min(max(moved.target.x, lo.x - margin), hi.x + margin),
                              moved.target.y,
                              min(max(moved.target.z, lo.z - margin), hi.z + margin))
        camera = moved
        pushCamera()
    }

    /// Pinch: closer for a factor above 1, further away below.
    func zoomCamera(by factor: Double) {
        cameraIsDefault = false
        camera = camera.zoomed(by: factor, limits: SceneCamera.distanceLimits(forSceneDiagonal: pickScene.diagonal))
        pushCamera()
    }

    /// For VoiceOver and keyboards: turn by a fixed step, from where a running glide is heading.
    func turn(byDegrees degrees: Double) {
        cameraIsDefault = false
        move(to: (glideTarget ?? camera).orbited(yawDelta: degrees, pitchDelta: 0), animated: true)
    }

    /// For VoiceOver and keyboards: zoom by a fixed step, from where a running glide is heading.
    func zoom(byStep factor: Double) {
        cameraIsDefault = false
        let base = glideTarget ?? camera
        move(to: base.zoomed(by: factor, limits: SceneCamera.distanceLimits(forSceneDiagonal: pickScene.diagonal)),
             animated: true)
    }

    /// One tick of the ticker, `dt` seconds after the last. Returns true while the camera is still moving.
    func advance(by dt: Double) -> Bool {
        var moving = false
        if var running = inertia {
            camera = running.advance(camera, by: dt)
            inertia = running.isMoving ? running : nil
            moving = inertia != nil
            pushCamera()
        }
        if isGliding {
            animator.advance(by: dt)
            camera = animator.camera
            pushCamera()
            if animator.isSettled {
                isGliding = false
                glideTarget = nil
            } else {
                moving = true
            }
        }
        return moving
    }

    // MARK: Screen and world

    /// Where a world point is in the view, nil when it is behind the camera. Apple does not say when
    /// `ARView.project(_:)` returns nil, and a point behind a perspective camera that was projected anyway would
    /// land mirrored in the picture, so a point at or behind the near plane is rejected here, whatever the view says.
    func screenPoint(_ p: Point3) -> CGPoint? {
        guard (p - camera.position).dot(camera.forward) > Viewer3DController.nearPlane else { return nil }
        return projector?(p)
    }

    /// The renderer's near clipping plane, metres (`ModelRenderer` sets 0.05).
    private static let nearPlane = 0.05

    /// The labels that can be seen from where the camera is: not hidden behind a wall (while walls are solid).
    /// Re-tested only when the camera has moved a few centimetres or a setting changed.
    func visibleLabels() -> [OverlayLabel] {
        guard showsLabels else { return [] }
        let eye = camera.position
        let key = LabelKey(x: Int((eye.x * 40).rounded()), y: Int((eye.y * 40).rounded()), z: Int((eye.z * 40).rounded()),
                           seeThrough: wallStyle == .seeThrough, ceiling: showsCeiling, overlay: overlayVersion,
                           scene: sceneVersion)
        if key == labelKey { return cachedLabels }
        labelKey = key
        if wallStyle == .seeThrough {
            cachedLabels = overlay.labels
        } else {
            cachedLabels = overlay.labels.filter { ScenePicker.isVisible($0.position, from: eye, in: pickScene) }
        }
        return cachedLabels
    }

    /// Labels for the draw pass: the room labels that can be seen, then the live tape label.
    func drawableLabels() -> [OverlayLabel] {
        var labels = visibleLabels()
        labels.append(contentsOf: tape.overlay(units: units).labels)
        return labels
    }

    /// Every label the layer may have to draw, so it can prepare their chips.
    var allLabels: [OverlayLabel] {
        overlay.labels + tape.overlay(units: units).labels
    }

    /// The saved tape lines of the floor and the line being measured, as pairs of world points.
    var measurementLines: [(Point3, Point3, isLive: Bool)] {
        var lines: [(Point3, Point3, isLive: Bool)] = []
        for segment in overlay.segments where segment.kind == .measurement {
            lines.append((segment.a, segment.b, false))
        }
        if let (a, b) = tape.points { lines.append((a, b, true)) }
        return lines
    }

    /// The points placed so far, for the markers.
    var tapePoints: [Point3] {
        [tape.first, tape.second].compactMap { $0 }
    }

    // MARK: Measuring

    func setMeasuring(_ on: Bool) {
        guard on != isMeasuring else { return }
        isMeasuring = on
        clearTape()
        isNaming = false
        notice = nil
    }

    func clearMeasurement() {
        clearTape()
        isNaming = false
    }

    private func clearTape() {
        tape.clear()
        snapNotes = []
    }

    /// A tap in measure mode: put the next tape point where the tap landed, jumping to a corner or edge when
    /// one is close to the ray.
    func handleTap(at point: CGPoint) {
        guard isMeasuring else { return }
        guard let ray = rayFactory?(point) else { return }
        let result = ScenePicker.pick(ray: ray, in: pickScene, snapPoints: snapPoints, snapEdges: snapEdges,
                                      mode: wallStyle == .seeThrough ? .seeThrough : .opaque)
        switch result.placement {
        case .place(let position, let snapLabel):
            if tape.isComplete || tape.isEmpty { snapNotes = [] }
            tape.addPoint(position)
            snapNotes.append(snapLabel)
            notice = nil
            if snapLabel != nil, hapticsEnabled { Haptics.selection() }
            speak(tape.isComplete ? "Second point set. " + (readout?.spoken ?? "") : "First point set.")
        case .notScanned:
            show(notice: "That surface was not scanned. Tap the inside of a wall, the floor or an object.")
        case .missed:
            show(notice: "Nothing there. Tap a wall, the floor or an object.")
        }
    }

    /// The measurement in progress.
    var reading: TapeReading? { tape.reading }
    var readout: TapeReadout? { tape.reading.map { TapeReadout($0, units: units) } }

    /// What to tell the person to do next, nil once both points are placed.
    var hint: String? {
        guard isMeasuring, !tape.isComplete else { return nil }
        if tape.isEmpty { return "Tap the first point. It snaps to corners and edges." }
        let snapped = (snapNotes.first ?? nil).map { "First point: \($0). " } ?? ""
        return snapped + "Now tap the second point."
    }

    /// What the two points snapped to, for the readout ("Floor corner A to Floor corner B").
    var snapSummary: String? {
        guard tape.isComplete else { return nil }
        let names = snapNotes.compactMap { $0 }
        switch names.count {
        case 2: return "\(names[0]) to \(names[1])"
        case 1: return "From \(names[0])"
        default: return nil
        }
    }

    /// The room the measurement would be kept in.
    var targetRoomID: UUID? {
        guard let (a, b) = tape.points else { return nil }
        return MeasurementRoomLocator.roomID(forPointA: a, pointB: b, in: rooms, focusRoomID: focusRoomID)
    }

    var targetRoomName: String {
        guard let id = targetRoomID, let room = rooms.first(where: { $0.id == id }) else { return "the room" }
        let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? room.kind.displayName : trimmed
    }

    var canSave: Bool { tape.isComplete && targetRoomID != nil }

    /// Every label already on the floor, so the default name can step past them.
    private var existingLabels: [String] {
        rooms.flatMap { $0.customMeasurements.map(\.label) } + localSaved.map(\.measurement.label)
    }

    /// "Measurement 3": the name offered in the alert.
    var defaultMeasurementName: String {
        MeasurementNaming.defaultLabel(existing: existingLabels)
    }

    func beginNaming() {
        guard canSave else { return }
        isNaming = true
    }

    func cancelNaming() {
        isNaming = false
    }

    /// Saves the measurement under `name` (the default name when it is empty) on the room that holds it.
    func commitMeasurement(named name: String) {
        defer { isNaming = false }
        guard let (a, b) = tape.points else { return }
        guard let roomID = targetRoomID else {
            show(notice: "There is no saved room to keep this measurement in.")
            return
        }
        let label = MeasurementNaming.label(typed: name, existing: existingLabels)
        // A tape reading is a scanned number: no verification, ever, until a person checks it.
        let measurement = CustomMeasurement(label: label, a: a, b: b)
        localSaved.append(LocalSave(measurement: measurement, roomID: roomID))
        let roomName = targetRoomName
        rebuildOverlay()
        saveHandler(measurement, roomID)
        clearTape()
        if hapticsEnabled { Haptics.success() }
        show(notice: "Saved \(label) to \(roomName).")
    }

    // MARK: Notices

    private func show(notice text: String) {
        noticeToken += 1
        let token = noticeToken
        notice = text
        speak(text)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.noticeToken == token else { return }
            self.notice = nil
        }
    }

    private func speak(_ text: String) {
        announce?(text)
    }
}
