import Foundation
import Observation
import ARKit
import RealityKit
import AVFoundation
import UIKit
import NexaFixCore

/// Everything the AR review screen needs that is not drawing: camera permission, the AR session, whether
/// the saved room has lined up with the real one, the overlay scene, and the tape measure.
///
/// Threading: every method runs on the main thread. The session delegate is set to the main queue, and the
/// views call in from SwiftUI. (The class is not annotated `@MainActor` so a SwiftUI view can create it in
/// its `init` on every supported Xcode version.)
///
/// Honesty rule: the room's coordinates belong to the scan session. The overlay is allowed only after
/// ARKit has relocalised against the world map saved with the scan (`status.overlayAllowed`); the tape
/// measure never snaps to saved geometry until then, and a measurement is saved only if both of its points
/// were placed while lined up (`AlignedTapeMeasure`). Points on the table are dropped whenever the session
/// lines up, loses its place or restarts, because the frame they were measured in has changed.
@Observable
final class ARReviewController {

    // MARK: Types

    enum Access: Equatable {
        case checking
        /// Not asked yet: explain first, then show the system prompt.
        case needsExplanation
        case denied
        /// This device cannot run world tracking (for example the Simulator).
        case unsupported
        case ready
        case failed(String)
    }

    /// What the centre reticle sits on while measuring.
    enum Reticle: Equatable {
        case noSurface
        case surface
        /// Snapped to a known corner or edge; the text names it.
        case snapped(String)
    }

    // MARK: Observed state

    private(set) var rooms: [Room]
    private(set) var units: DisplayUnits
    private(set) var options: OverlayOptions = .review
    private(set) var selectedRoomID: UUID?
    /// The selected room's overlay, rebuilt only when rooms, options, units or the selection change.
    private(set) var baseScene: OverlayScene = .empty
    private(set) var access: Access = .checking
    private(set) var status: ARStatusSummary
    private(set) var isMeasuring = false
    /// The tape measure and the alignment rule for its points.
    private(set) var tape = AlignedTapeMeasure()
    private(set) var reticle: Reticle = .noSurface
    /// The "name this measurement" card is open.
    private(set) var isNaming = false
    /// A short message that clears itself, such as "Couldn't find a surface."
    private(set) var notice: String?

    // MARK: Plumbing (never triggers a view update)

    @ObservationIgnored var hapticsEnabled: Bool
    @ObservationIgnored private let focusRoomID: UUID?
    @ObservationIgnored private let worldMapURL: URL?
    @ObservationIgnored private let saveHandler: (CustomMeasurement, UUID) -> Void
    @ObservationIgnored private let closeHandler: () -> Void

    @ObservationIgnored private weak var arView: ARView?
    @ObservationIgnored private var proxy: ARSessionProxy?
    @ObservationIgnored private var worldMapLoad: WorldMapLoad = .none
    @ObservationIgnored private var tracker = RelocalisationTracker()
    @ObservationIgnored private var lastSnapshot: TrackingSnapshot?
    @ObservationIgnored private var isInterrupted = false
    @ObservationIgnored private var snapCandidates: [TapeSnapCandidate] = []
    @ObservationIgnored private var snapTracker = TapeSnapTracker()
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var noticeToken = 0
    @ObservationIgnored private var didPrepare = false
    @ObservationIgnored private var hasStartedSession = false
    @ObservationIgnored private var isMapResolved = false
    @ObservationIgnored private var isPaused = false

    // MARK: Init

    /// Cheap on purpose: SwiftUI may build and discard several of these while it re-creates the view.
    /// The scene and snap points are built in `prepare()`.
    init(rooms: [Room], focusRoomID: UUID?, worldMapURL: URL?, units: DisplayUnits, hapticsEnabled: Bool,
         onSaveMeasurement: @escaping (CustomMeasurement, UUID) -> Void, onClose: @escaping () -> Void) {
        self.rooms = rooms
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        self.focusRoomID = focusRoomID
        self.worldMapURL = worldMapURL
        self.saveHandler = onSaveMeasurement
        self.closeHandler = onClose
        self.selectedRoomID = ARReviewController.initialSelection(rooms: rooms, focus: focusRoomID)
        self.status = ARReviewController.initialStatus
    }

    /// What the pill says before the first frame arrives.
    private static var initialStatus: ARStatusSummary {
        ARStatusSummary.make(phase: .searching, snapshot: TrackingSnapshot(tracking: .initializing))
    }

    private static func initialSelection(rooms: [Room], focus: UUID?) -> UUID? {
        if let focus, rooms.contains(where: { $0.id == focus }) { return focus }
        return rooms.first?.id
    }

    // MARK: Lifecycle

    /// Call when the screen appears. Decides whether the camera can be used and builds the overlay.
    func prepare() {
        if !didPrepare {
            didPrepare = true
            rebuildScene()
            rebuildSnapCandidates()
        }
        if access == .ready {
            resumeIfNeeded()
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            access = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .ready
        case .notDetermined: access = .needsExplanation
        default: access = .denied
        }
    }

    /// Shows the system camera prompt. Called from the explanation card's button.
    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            let controller = self
            DispatchQueue.main.async { controller?.access = granted ? .ready : .denied }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Pauses the AR session (the screen went away).
    func stop() {
        guard hasStartedSession, !isPaused else { return }
        arView?.session.pause()
        isPaused = true
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func close() {
        stop()
        closeHandler()
    }

    /// Called by `ARViewContainer` once the `ARView` exists (again, if SwiftUI re-creates it).
    func attach(_ view: ARView) {
        arView = view
        let proxy = ARSessionProxy(controller: self)
        self.proxy = proxy
        view.session.delegate = proxy
        view.session.delegateQueue = DispatchQueue.main
        hasStartedSession = false
        isPaused = false
        // A new view is a new session in a new coordinate frame: forget the old line-up and any tape points.
        resetAlignment()
        startSession()
    }

    /// Starts the line-up from nothing, for a new session or a restarted one: nothing seen before counts,
    /// and tape points from the old session are dropped. Observed state is written only when it differs, so
    /// the first attach (everything already at its starting value) changes nothing while the view updates.
    private func resetAlignment() {
        tracker = RelocalisationTracker()
        lastSnapshot = nil
        isInterrupted = false
        frameCount = 0
        snapTracker.reset()
        if reticle != .noSurface { reticle = .noSurface }
        if isNaming { isNaming = false }
        if tape != AlignedTapeMeasure(), let reset = tape.sessionRestarted() {
            show(notice: ARReviewController.message(for: reset))
        }
        let initial = ARReviewController.initialStatus
        if status != initial { status = initial }
    }

    private func startSession() {
        guard !hasStartedSession else { return }
        hasStartedSession = true
        if isMapResolved {
            run(resetting: true)
            return
        }
        guard let url = worldMapURL else {
            worldMapLoad = .none
            isMapResolved = true
            run(resetting: true)
            return
        }
        // Maps are large: read and decode off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ARReviewController.readWorldMap(at: url)
            let controller = self
            DispatchQueue.main.async {
                guard let controller else { return }
                controller.worldMapLoad = result
                controller.isMapResolved = true
                controller.run(resetting: true)
            }
        }
    }

    private func resumeIfNeeded() {
        guard isPaused, hasStartedSession else { return }
        // Continue where the session left off. If tracking was lost meanwhile ARKit relocalises, and the
        // tracker takes the overlay away until it has.
        run(resetting: false)
    }

    private func run(resetting: Bool) {
        guard let session = arView?.session else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        // The saved map seeds a fresh session. A session that is merely resuming already holds it.
        if resetting, case .loaded(let map) = worldMapLoad {
            configuration.initialWorldMap = map
        }
        let runOptions: ARSession.RunOptions = resetting ? [.resetTracking, .removeExistingAnchors] : []
        session.run(configuration, options: runOptions)
        isPaused = false
        // A person walking a room does not touch the screen for minutes; do not let it dim.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private enum WorldMapLoad {
        case none
        case unreadable
        case loaded(ARWorldMap)
    }

    /// `unarchivedObject(ofClass:from:)` decodes with secure coding, which `ARWorldMap` supports.
    private static func readWorldMap(at url: URL) -> WorldMapLoad {
        do {
            let data = try Data(contentsOf: url)
            if let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                return .loaded(map)
            }
            return .unreadable
        } catch {
            return .unreadable
        }
    }

    // MARK: Inputs from the view

    func update(rooms newRooms: [Room]) {
        guard newRooms != rooms else { return }
        rooms = newRooms
        if let id = selectedRoomID, !newRooms.contains(where: { $0.id == id }) {
            selectedRoomID = ARReviewController.initialSelection(rooms: newRooms, focus: focusRoomID)
        } else if selectedRoomID == nil {
            selectedRoomID = ARReviewController.initialSelection(rooms: newRooms, focus: focusRoomID)
        }
        rebuildScene()
        rebuildSnapCandidates()
    }

    func update(units newUnits: DisplayUnits) {
        guard newUnits != units else { return }
        units = newUnits
        rebuildScene()
    }

    func selectRoom(_ id: UUID) {
        guard id != selectedRoomID, rooms.contains(where: { $0.id == id }) else { return }
        selectedRoomID = id
        rebuildScene()
    }

    func setOption(_ keyPath: WritableKeyPath<OverlayOptions, Bool>, to value: Bool) {
        var updated = options
        updated[keyPath: keyPath] = value
        guard updated != options else { return }
        options = updated
        rebuildScene()
    }

    private func rebuildScene() {
        let visible = rooms.filter { selectedRoomID == nil || $0.id == selectedRoomID }
        baseScene = OverlayBuilder.scene(for: visible, options: options, units: units, highlightRoomID: selectedRoomID)
    }

    private func rebuildSnapCandidates() {
        snapCandidates = rooms.flatMap { room in
            room.snapPoints().map { TapeSnapCandidate(id: String(describing: $0.id), position: $0.position, label: $0.label) }
        }
    }

    // MARK: Derived

    /// The session behind the camera view, once it exists.
    var session: ARSession? { arView?.session }

    /// The scan has lined up with the real room (even if tracking is briefly limited).
    var isAligned: Bool { tape.isAligned }

    /// The points placed so far.
    var measure: TapeMeasureSession { tape.session }

    var reading: TapeReading? { measure.reading }

    var readout: TapeReadout? { measure.reading.map { TapeReadout($0, units: units) } }

    /// The measurement in progress, as an overlay scene (drawn even when the room overlay is hidden).
    var measureScene: OverlayScene { measure.overlay(units: units) }

    /// Saving needs a finished measurement whose points were both placed while the scan was lined up, and a
    /// scan that still is. Otherwise the points are in a different coordinate frame from the room they would
    /// be saved to, and the saved line would be drawn in the wrong place on every later visit.
    var canSaveMeasurement: Bool { tape.canSave }

    /// The room a finished measurement would be saved on: the room whose outline holds the points (the same
    /// rule the 3D viewer uses, `MeasurementRoomLocator`). The room selected in the chip row is only a
    /// tie-break between rooms that both hold the points, never a destination of its own: the first room is
    /// pre-selected whenever AR opens without a focus room, and a wardrobe wall measured in the master
    /// bedroom must not end up on the living room because of that. Nil when there is no finished measurement
    /// or no saved room. Computed from the points and the rooms only, so the naming card and the save agree.
    var measurementRoom: Room? {
        guard let (a, b) = measure.points,
              let id = MeasurementRoomLocator.roomID(forPointA: a, pointB: b, in: rooms, focusRoomID: selectedRoomID)
        else { return nil }
        return rooms.first { $0.id == id }
    }

    /// What a room is called on screen: its name, else its kind ("Bedroom").
    static func title(of room: Room) -> String {
        let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? room.kind.displayName : trimmed
    }

    /// The sentence shown when a measurement was dropped because the frame of reference changed.
    private static func message(for reset: AlignedTapeMeasure.Reset) -> String {
        switch reset {
        case .linedUp: return "The scan just lined up with the room, so your measurement was cleared. Measure again."
        case .lostPlace: return "AR lost its place, so your measurement was cleared. Measure again."
        case .restarted: return "AR restarted, so your measurement was cleared."
        }
    }

    // MARK: Measuring

    func setMeasuring(_ on: Bool) {
        guard on != isMeasuring else { return }
        isMeasuring = on
        if !on {
            tape.clear()
            reticle = .noSurface
            snapTracker.reset()
            isNaming = false
        }
    }

    /// Places a measurement point where the centre reticle is.
    ///
    /// Only while ARKit is tracking normally: in any limited state the camera pose can be off, and a point
    /// placed from a bad pose would be saved to a joinery drawing as if it were as good as any other.
    func addPoint() {
        guard isMeasuring else { return }
        if let advice = placementAdvice() {
            show(notice: advice)
            return
        }
        guard let hit = raycastFromCentre() else {
            show(notice: "Couldn't find a surface. Move closer and try again.")
            return
        }
        let snap = status.overlayAllowed ? TapeMeasure.snap(hit, to: snapCandidates) : TapeSnap(point: hit)
        let wasComplete = measure.isComplete
        tape.addPoint(snap.point)
        isNaming = false
        if measure.isComplete, !wasComplete, let readout {
            announce(readout.spoken)
        }
    }

    func clearMeasurement() {
        tape.clear()
        isNaming = false
    }

    func beginNaming() {
        guard canSaveMeasurement else { return }
        isNaming = true
    }

    func cancelNaming() { isNaming = false }

    /// Stores the measurement on the room that holds it (see `measurementRoom`) and starts over.
    func commitMeasurement(named name: String) {
        guard canSaveMeasurement, let (a, b) = measure.points else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Measurement" : trimmed
        guard let room = measurementRoom else {
            // Only happens when there are no rooms at all. Say so rather than leaving the card open and silent.
            isNaming = false
            show(notice: "There is no saved room to keep this measurement in.")
            return
        }
        // Read the name before the points are cleared: the room is worked out from them.
        let roomName = ARReviewController.title(of: room)
        saveHandler(CustomMeasurement(label: label, a: a, b: b), room.id)
        if hapticsEnabled { Haptics.success() }
        tape.clear()
        isNaming = false
        show(notice: "Saved \(label) to \(roomName).")
    }

    /// Why a point cannot be placed right now, or nil when tracking is good enough. The wording follows the
    /// status pill so the two never disagree.
    private func placementAdvice() -> String? {
        guard let snapshot = lastSnapshot else {
            return "AR is still starting. Move your phone slowly, then try again."
        }
        if snapshot.isInterrupted {
            return "AR is paused while another app uses the camera."
        }
        switch snapshot.tracking {
        case .normal:
            return nil
        case .excessiveMotion:
            return "Move your phone more slowly, then try again."
        case .insufficientFeatures:
            return "Point at walls, corners or furniture, then try again."
        case .relocalizing:
            return "AR is still finding its place. Look at the walls, then try again."
        case .initializing, .notAvailable:
            return "AR is still starting. Move your phone slowly, then try again."
        }
    }

    private func raycastFromCentre() -> Point3? {
        guard let view = arView, view.bounds.width > 0 else { return nil }
        let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        // A known plane first (walls, floor and ceiling the LiDAR mesh has found), then ARKit's estimate.
        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            if let result = view.raycast(from: centre, allowing: target, alignment: .any).first {
                return ARProjection.position(of: result.worldTransform)
            }
        }
        return nil
    }

    private func updateReticle() {
        guard let hit = raycastFromCentre() else {
            if reticle != .noSurface { reticle = .noSurface }
            _ = snapTracker.update(TapeSnap(point: .zero))
            return
        }
        let snap = status.overlayAllowed ? TapeMeasure.snap(hit, to: snapCandidates) : TapeSnap(point: hit)
        if snapTracker.update(snap), hapticsEnabled { Haptics.selection() }
        let next: Reticle = snap.didSnap ? .snapped(snap.candidate?.label ?? "") : .surface
        if next != reticle { reticle = next }
    }

    // MARK: Notices and announcements

    private func show(notice text: String) {
        noticeToken += 1
        let token = noticeToken
        notice = text
        announce(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.noticeToken == token else { return }
            self.notice = nil
        }
    }

    /// `UIAccessibility.post` belongs to the main actor, and this class is not annotated with it (see the note at
    /// the top), so the call goes through the main actor explicitly. Every caller is on the main thread (the
    /// session delegate runs on the main queue, and the views call in from SwiftUI), and then it happens right
    /// away; from any other thread it waits for the next turn of the main queue instead of trapping.
    private func announce(_ text: String) {
        let post: @MainActor @Sendable () -> Void = {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(post)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(post) }
        }
    }

    // MARK: Session events (called by the delegate proxy, on the main queue)

    fileprivate func handle(frame: ARFrame) {
        apply(makeSnapshot(from: frame))
        if isMeasuring {
            frameCount += 1
            if frameCount % 3 == 0 { updateReticle() }
        }
    }

    fileprivate func refreshFromCurrentFrame() {
        guard let frame = arView?.session.currentFrame else { return }
        apply(makeSnapshot(from: frame))
    }

    fileprivate func sessionWasInterrupted() {
        isInterrupted = true
        refreshFromCurrentFrame()
    }

    fileprivate func sessionInterruptionEnded() {
        isInterrupted = false
        refreshFromCurrentFrame()
    }

    fileprivate func sessionFailed(_ error: Error) {
        if hapticsEnabled { Haptics.warning() }
        if let arError = error as? ARError {
            if arError.code == .cameraUnauthorized {
                access = .denied
                return
            }
            // The saved map decoded fine (see `readWorldMap`) but ARKit would not use it, for example after an
            // iOS update. Reopening would load the same file and fail the same way, so carry on without it,
            // exactly as for a map that could not be read: no overlay, but the tape measure still works.
            // (Only once: after this the map counts as unreadable, so this branch cannot repeat.)
            if arError.code == .invalidWorldMap, case .loaded = worldMapLoad {
                restartWithoutMap()
                return
            }
        }
        access = .failed("AR stopped working. Try again, or close this screen and open it again.")
    }

    /// Starts a fresh session with no saved map and shows the "AR map unreadable" card straight away.
    private func restartWithoutMap() {
        worldMapLoad = .unreadable
        // A restarted session measures in a frame of its own: nothing seen so far, including tape points, counts.
        resetAlignment()
        let snapshot = TrackingSnapshot(tracking: .initializing, worldMap: .unreadable)
        let phase = tracker.ingest(snapshot)
        status = ARStatusSummary.make(phase: phase, snapshot: snapshot)
        run(resetting: true)
    }

    /// "Try again" on the "AR stopped" card: back to the AR screen, which builds a new AR view and session.
    func retry() {
        guard case .failed = access else { return }
        access = .ready
    }

    private func makeSnapshot(from frame: ARFrame) -> TrackingSnapshot {
        let tracking: TrackingSnapshot.Tracking
        switch frame.camera.trackingState {
        case .normal:
            tracking = .normal
        case .notAvailable:
            tracking = .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing: tracking = .initializing
            case .relocalizing: tracking = .relocalizing
            case .excessiveMotion: tracking = .excessiveMotion
            case .insufficientFeatures: tracking = .insufficientFeatures
            @unknown default: tracking = .initializing
            }
        @unknown default:
            tracking = .notAvailable
        }

        let mapping: TrackingSnapshot.Mapping
        switch frame.worldMappingStatus {
        case .notAvailable: mapping = .notAvailable
        case .limited: mapping = .limited
        case .extending: mapping = .extending
        case .mapped: mapping = .mapped
        @unknown default: mapping = .notAvailable
        }

        let worldMap: TrackingSnapshot.WorldMap
        switch worldMapLoad {
        case .none: worldMap = .none
        case .unreadable: worldMap = .unreadable
        case .loaded: worldMap = .loaded
        }
        return TrackingSnapshot(tracking: tracking, mapping: mapping, worldMap: worldMap,
                                isInterrupted: isInterrupted, time: frame.timestamp)
    }

    private func apply(_ snapshot: TrackingSnapshot) {
        let before = tracker.phase
        let phase = tracker.ingest(snapshot)
        let unchanged = (lastSnapshot?.sameState(as: snapshot) ?? false) && phase == before
        lastSnapshot = snapshot
        guard !unchanged else { return }

        let summary = ARStatusSummary.make(phase: phase, snapshot: snapshot)
        if summary != status { status = summary }
        // The frame of reference changed (the session lined up, or lost its place): points measured in the
        // old one must go before anything can be saved or drawn.
        let aligned = phase == .aligned
        if aligned != tape.isAligned {
            if let reset = tape.setAligned(aligned) {
                isNaming = false
                show(notice: ARReviewController.message(for: reset))
            }
        }
        // Tracking lost after the overlay was up.
        if before == .aligned, phase != .aligned, hapticsEnabled { Haptics.warning() }
    }

    /// "Keep trying": give relocalisation another full window and restart the attempt from the saved map.
    func keepTrying() {
        guard case .failed(.timedOut) = tracker.phase else { return }
        // A restarted session measures in a frame of its own until it lines up again, so everything seen so
        // far, including tape points, is forgotten.
        resetAlignment()
        run(resetting: true)
        // Show "Relocalising" straight away; the next frame replaces this with what ARKit really reports.
        status = ARStatusSummary.make(phase: tracker.phase, snapshot: TrackingSnapshot(tracking: .relocalizing))
    }
}

// MARK: - Session delegate

/// Forwards ARKit's callbacks to the controller. A separate object keeps `NSObject` and the delegate
/// protocol out of the observable class.
private final class ARSessionProxy: NSObject, ARSessionDelegate {
    private weak var controller: ARReviewController?

    init(controller: ARReviewController) {
        self.controller = controller
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        controller?.handle(frame: frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        controller?.refreshFromCurrentFrame()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        controller?.sessionFailed(error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        controller?.sessionWasInterrupted()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        controller?.sessionInterruptionEnded()
    }

    /// After an interruption, try to pick the room back up instead of starting from nothing.
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }
}
