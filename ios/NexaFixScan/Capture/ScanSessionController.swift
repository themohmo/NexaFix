#if canImport(RoomPlan)
import Foundation
import Observation
import ARKit
import RoomPlan
import UIKit
import NexaFixCore

// Two builders are involved. Apple's `RoomPlan.RoomBuilder` turns raw scan data into a `CapturedRoom`;
// Core's `RoomReconstructor` turns a `RawCapture` (a copy of that `CapturedRoom`) into a parametric `Room`.
// Core's type was named `RoomReconstructor` so it can never be confused with Apple's `RoomBuilder`.

/// An alert for the scan screen: what happened and what to do, in plain words.
struct ScanAlert: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    /// True when nothing has been kept yet and scanning the room again is the sensible next step.
    var offersRescan: Bool
}

/// What the name sheet's two buttons do after the room is named.
enum AfterNaming {
    case scanNextRoom
    case finishProperty
}

/// Owns the scan: one `ARSession` and one `RoomCaptureView` shared by every room, so the rooms live in one
/// coordinate space and can be merged into one model. It is a thin executor: `ScanFlow` (Core) decides what
/// happens, this class does it and feeds the outcome back as events.
///
/// Rules it keeps:
/// - Rooms are scanned in ONE continuous AR session. Finishing a room stops the capture with
///   `stop(pauseARSession: false)`, never pauses AR, and the next room calls `run(configuration:)` again.
/// - A finished room is never lost to a failure or a Cancel. Errors end the room being scanned and keep
///   the others; a merge that cannot produce a 3D model still returns every room.
/// - Anything that did not work out (no 3D model, no AR map, rooms from before a tracking restart) is
///   written into `ScanResult.warnings`, because the result would otherwise look more complete than it is.
/// - `teardown()` pauses and releases the AR session. It runs when the screen goes away, when the
///   result is delivered and when the person leaves.
///
/// Create the controller only when the scan screen is about to appear. Its initializer starts the camera,
/// because RoomPlan wants an AR session that is already running (see `init`).
@MainActor
@Observable
final class ScanSessionController {

    // MARK: What the interface reads

    /// The state machine. Read `flow.state`, `flow.rooms` and the `can...` questions.
    private(set) var flow: ScanFlow
    /// Counts and rough area of the room being scanned.
    private(set) var stats: LiveScanStats = .empty
    /// What RoomPlan last asked the person to do.
    private(set) var instruction: ScanInstruction = .normal
    /// What ARKit says about tracking.
    private(set) var tracking: ScanTrackingIssue = .initializing
    /// The line for the pill at the top. RoomPlan's capture view prints RoomPlan's own instructions ("Move
    /// closer to the wall"), so this line never repeats them: it says when tracking is lost and what to do next.
    private(set) var coach: ScanCoachMessage
    /// Labels and lines for the wall being detected. Empty when there is nothing honest to show.
    private(set) var liveScene: OverlayScene = .empty
    /// Which step of the merge is running.
    private(set) var mergeStep: ScanMergeStep = .joiningRooms
    /// True when tracking has been lost for long enough that the person needs another way out.
    private(set) var needsRelocalizationHelp = false
    /// False after AR failed in a way that cannot be recovered: only finishing is offered. That is the case
    /// when rooms were already finished (a restarted session is another coordinate space, so a new room could
    /// not be joined to them) or when the failure cannot be fixed by trying again (the camera is not allowed).
    /// With no finished room, a failed session can simply be started again, so the flag stays true.
    private(set) var canContinueScanning = true
    /// An alert to show now. Setting it to nil dismisses it.
    var alert: ScanAlert?

    let configuration: ScanConfiguration
    /// True in the Simulator: no camera, no RoomPlan; rooms come from `CaptureFixtures`.
    let isSimulated: Bool

    // MARK: Apple objects

    /// The session shared by every room. The AR overlay canvas reads frames from it.
    @ObservationIgnored let arSession: ARSession
    /// The framework's capture view. nil in the Simulator.
    @ObservationIgnored private(set) var captureView: RoomCaptureView?

    // MARK: Internals

    /// What is kept for one scanned room until the property is finished.
    private struct Record {
        var raw: RawCapture
        var captured: CapturedRoom?
        var json: Data?
        /// Which AR coordinate space the room was scanned in (see `spaceEpoch`).
        var epoch: Int
    }

    /// The raw output of one stopped capture.
    private struct RoomEnd {
        var data: CapturedRoomData
        var error: Error?
    }

    private enum EndMode { case build, discard }

    @ObservationIgnored private let onFinish: (ScanResult) -> Void
    @ObservationIgnored private let onCancel: () -> Void
    @ObservationIgnored private var bridge: ScanCaptureBridge?
    @ObservationIgnored private var lease: SessionLease?

    @ObservationIgnored private var records: [UUID: Record] = [:]
    @ObservationIgnored private var pendingResult: ScanResult?
    /// A copy of every built room on disk, so an app that is ended between rooms does not take the scan with it.
    /// nil in the Simulator, whose practice rooms are not worth recovering.
    @ObservationIgnored private let recovery: ScanRecoveryStore?
    /// Whether the app is in the foreground. The timeouts only count time spent there (see `ForegroundClock`).
    @ObservationIgnored private let foreground = ForegroundClock()
    /// True when the AR session was stopped by an error or paused by this controller, so the next capture has
    /// to run it again first.
    @ObservationIgnored private var arSessionNeedsRestart = false

    @ObservationIgnored private var isCaptureRunning = false
    @ObservationIgnored private var endMode: EndMode?
    @ObservationIgnored private var bufferedEnd: RoomEnd?
    @ObservationIgnored private var isWaitingForEnd = false
    /// True from the moment a capture was stopped for building until its raw data has arrived.
    @ObservationIgnored private var isAwaitingEndData = false
    /// Counts captures, so a live build that finishes after the next room started is thrown away.
    @ObservationIgnored private var captureGeneration = 0
    @ObservationIgnored private var isInterrupted = false
    /// When this controller last stopped a capture itself, so the second end callback RoomPlan sends for the
    /// same stop is not mistaken for RoomPlan stopping on its own.
    @ObservationIgnored private var lastStopAt: TimeInterval = -100
    @ObservationIgnored private var relocalizingSince: TimeInterval?
    /// When the AR session was first seen without any camera frame during this capture.
    @ObservationIgnored private var noFrameSince: TimeInterval?
    @ObservationIgnored private var isTornDown = false
    @ObservationIgnored private var didAnnounceFloorSize = false
    @ObservationIgnored private var didLeave = false
    @ObservationIgnored private var didStart = false
    /// Bumps when AR tracking is known to have restarted, which starts a new coordinate space. Rooms from
    /// different epochs cannot be merged or shown in the same AR overlay.
    @ObservationIgnored private var spaceEpoch = 0

    /// True once `didUpdate` has delivered a full snapshot of the room being scanned.
    @ObservationIgnored private var hasSnapshot = false
    /// Wall identifiers announced by `didAdd` and `didChange` and dropped by `didRemove`. Those three carry only
    /// what changed, never the whole room, so they cannot replace the live statistics; they only stop "Finish
    /// room" depending on `didUpdate` alone.
    @ObservationIgnored private var announcedWallIDs: Set<UUID> = []

    /// Makes the practice rooms of this scan differ from those of every other scan: Core derives every room
    /// and wall id from the fixture label, so two scans must never share a label.
    @ObservationIgnored private let practiceToken = UUID().uuidString

    @ObservationIgnored private var latestRaw = RawCapture()
    @ObservationIgnored private var liveThrottle = LiveRebuildThrottle(minInterval: 0.5)
    @ObservationIgnored private var announcer = ScanCoach.Announcer()

    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var mergeTask: Task<Void, Never>?
    @ObservationIgnored private var liveBuildTask: Task<Void, Never>?
    @ObservationIgnored private var liveWaitTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?

    // MARK: Creating

    /// - Parameter recoveryRoot: Where the safety copy of the scan is written (see `ScanRecoveryStore`). Only
    ///   tests pass something else.
    init(configuration: ScanConfiguration,
         isSimulated: Bool,
         recoveryRoot: URL = ScanRecoveryStore.defaultRoot,
         onFinish: @escaping (ScanResult) -> Void,
         onCancel: @escaping () -> Void) {
        self.configuration = configuration
        self.isSimulated = isSimulated
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.flow = ScanFlow(existingRoomNames: configuration.existingRoomNames)
        self.coach = ScanCoach.progress(.empty)
        self.recovery = isSimulated ? nil : ScanRecoveryStore(root: recoveryRoot,
                                                              propertyID: configuration.propertyID,
                                                              propertyName: configuration.propertyName,
                                                              story: configuration.story,
                                                              existingRoomNames: configuration.existingRoomNames)
        // The Simulator has no tracking to report.
        self.tracking = isSimulated ? .none : .initializing

        let session = ARSession()
        self.arSession = session
        self.lease = SessionLease(session)

        if !isSimulated {
            // Apple: the session passed to `RoomCaptureView(frame:arSession:)` is "a world-tracking session that
            // your app creates and runs with an ARWorldTrackingConfiguration before calling this function". So
            // it is run first. Running it again later, as RoomPlan does for every room, keeps its tracking: by
            // default `run` resumes from the last known position.
            session.run(Self.worldTrackingConfiguration())

            let view = RoomCaptureView(frame: .zero, arSession: session)
            // Hide RoomPlan's live miniature of the room at the bottom of the view. It would sit under our bottom
            // bar and compete with the live labels. This does not touch the preview after a scan: that one is
            // skipped by returning false from `captureView(shouldPresent:error:)` in the bridge.
            view.isModelEnabled = false
            self.captureView = view

            let bridge = ScanCaptureBridge()
            self.bridge = bridge
            bridge.controller = self
            view.captureSession.delegate = bridge
            view.delegate = bridge
            claimSessionDelegate()

            // Old safety copies nobody came back for. Off the main thread: it lists a folder.
            DispatchQueue.global(qos: .utility).async { ScanRecoveryStore.prune(root: recoveryRoot) }
        }
    }

    /// The configuration RoomPlan's AR session runs with: a plain `ARWorldTrackingConfiguration`, nothing added.
    ///
    /// Apple's one stated contract for the session handed to RoomPlan is "a world-tracking session that your app
    /// creates and runs with an ARWorldTrackingConfiguration"; every Apple example (WWDC23 session 10192) runs
    /// an unmodified one, and `RoomCaptureSession.CaptureError.invalidARConfiguration` ("the ARKit session runs
    /// an unsupported configuration") is documented without saying which settings it means. Scene
    /// reconstruction and scene depth were switched on here before, but nothing in the scan reads this
    /// session's mesh or depth (the AR review session has its own configuration), so they only risked that
    /// error and added thermal load. Add a feature only if a device test shows RoomPlan needs it.
    static func worldTrackingConfiguration() -> ARWorldTrackingConfiguration {
        ARWorldTrackingConfiguration()
    }

    /// Puts the bridge in front of whatever the AR session's delegate is. RoomPlan owns this session and may
    /// be its delegate, so the bridge passes every ARKit callback on to it instead of replacing it. It runs
    /// again after every `run` and on every tracking poll, because RoomPlan may set its own delegate again.
    private func claimSessionDelegate() {
        guard let bridge else { return }
        let current = arSession.delegate
        guard current !== bridge else { return }
        bridge.previous = current
        arSession.delegate = bridge
    }

    // MARK: Interface questions

    var statsSummary: String { stats.summary(units: configuration.units) }
    var statsSpoken: String { stats.spokenSummary(units: configuration.units) }

    /// "Finish room" can be tapped. A Simulator room is generated, so it needs no walls first.
    var canFinishRoom: Bool { flow.canFinishRoom && (isSimulated || stats.hasEnoughToFinish) }

    /// Live labels are drawn only while the session is tracking normally and there is something to draw.
    var canShowLiveLabels: Bool {
        !isSimulated && flow.isCapturing && tracking == .none && !liveScene.isEmpty
    }

    /// True once the first room has been started. Before that the screen shows no buttons at all, so a bar
    /// for the idle state never flashes while the camera view is still arriving.
    var hasStarted: Bool { didStart }

    /// Rooms that would be thrown away by leaving now.
    var roomsAtRisk: Int { flow.rooms.count + (flow.draftAwaitingName == nil ? 0 : 1) }

    /// Apple's recommended largest total area for joining rooms into one model is "2,000 square feet or around
    /// 186 square meters", with good lighting of 50 lux or more (WWDC23 session 10192, "Merge limits"). Beyond it
    /// the join may fail with `exceedSceneSizeLimit`; the rooms are kept either way. The warning appears at this
    /// area, a little under the limit, so the person hears about it while there is still a choice (scan the
    /// rest of the floor as its own level).
    static let sizeCautionAreaM2 = 150.0

    /// Floor area scanned so far on this level: the finished rooms plus a rough figure for the one in progress.
    /// A progress hint, never a measurement.
    var scannedFloorAreaM2: Double {
        let finished = flow.rooms.reduce(0.0) { $0 + ($1.draft.floorAreaM2 ?? 0) }
        let current = flow.isCapturing ? (stats.roughFloorAreaM2 ?? 0) : 0
        return finished + current
    }

    /// A warning for the top of the scan screen once the floor is getting too big for one joined 3D model. nil
    /// before that, and in the Simulator.
    var floorSizeCaution: String? {
        guard !isSimulated, scannedFloorAreaM2 >= Self.sizeCautionAreaM2 else { return nil }
        return "Large floor. RoomPlan recommends joining no more than about 186 m\u{00B2} (2,000 sq ft) into one 3D model. The plans are still saved."
    }

    // MARK: Actions from the interface

    /// Starts scanning the first room. Call it once the capture view is in a window; a second call does nothing.
    func start() {
        guard !didStart, flow.state == .idle, !isTornDown else { return }
        didStart = true
        keepScreenAwake(true)
        send(.start)
    }

    func finishRoom() {
        guard canFinishRoom else { return }
        haptic { Haptics.impact(.medium) }
        send(.finishRoom)
    }

    /// Cancel on the scan screen. With no finished rooms there is nothing to keep, so it closes the
    /// scanner. With finished rooms it only stops THIS room and keeps the others.
    func cancelCurrentRoom() {
        if flow.rooms.isEmpty {
            leave()
        } else {
            send(.cancelRoom)
        }
    }

    /// Checks the name and, when it is fine, names the room and moves on.
    /// - Returns: the verdict, so the sheet can show why a name was refused.
    @discardableResult
    func nameRoom(_ name: String, kind: RoomKind, then next: AfterNaming) -> ScanFlow.NameCheck {
        let check = flow.validate(name: name)
        guard case .valid(let cleaned) = check, let id = flow.draftAwaitingName?.id else { return check }
        send(.named(name: name, kind: kind))
        recovery?.setName(id: id, name: cleaned, kind: kind)
        switch next {
        case .scanNextRoom:
            // After an AR failure only finishing is offered (see `canContinueScanning`); the name sheet hides
            // "Scan next room" then, and this keeps a stray call from starting a capture on a dead session.
            if canContinueScanning { send(.scanNext) }
        case .finishProperty:
            send(.finishProperty)
        }
        return check
    }

    /// Throws the room waiting for a name away and scans it again.
    func rescanRoom() {
        forgetWaitingRoom()
        send(.rescanRoom)
    }

    /// Throws the room waiting for a name away. Earlier rooms are kept.
    func discardWaitingRoom() {
        forgetWaitingRoom()
        send(.cancelRoom)
    }

    /// The room waiting for a name is being thrown away: its kept data goes too, in memory and on disk, so it
    /// cannot come back after a restart.
    private func forgetWaitingRoom() {
        guard let id = flow.draftAwaitingName?.id else { return }
        records[id] = nil
        recovery?.removeRoom(id: id)
    }

    func scanNextRoom() { send(.scanNext) }

    func finishProperty() { send(.finishProperty) }

    /// After an alert that offered to try again.
    func scanAgain() {
        alert = nil
        // The person chose to try again, and with no finished room a restarted session costs nothing. (The AR
        // session itself is run again by `beginCapture`.) A new ARKit failure clears this again.
        if flow.rooms.isEmpty { canContinueScanning = true }
        switch flow.state {
        case .idle:
            keepScreenAwake(true)
            send(.start)
        case .betweenRooms, .failed:
            send(.scanNext)
        default:
            break
        }
    }

    /// "Finish with the rooms I have": for when tracking will not come back. Stops the room being scanned
    /// (it is dropped) and finishes the property with the rooms that are done.
    func finishWithRoomsSoFar() {
        guard !flow.rooms.isEmpty else {
            leave()
            return
        }
        if flow.isCapturing || flow.isProcessingRoom { send(.cancelRoom) }
        if flow.canFinishProperty { send(.finishProperty) }
    }

    /// The app came back to the foreground. Time spent away is not time spent failing to find the place again,
    /// so the "tracking hasn't come back" clock starts over.
    func sceneBecameActive() {
        foreground.setActive(true)
        guard !isTornDown else { return }
        pollTracking()
        restartRelocalizationClock()
    }

    /// The app is no longer in the foreground (another app, the lock screen, the app switcher). The merge and
    /// map timeouts stop counting: iOS may suspend the app for any length of time, and the work that was
    /// running would then be reported as failed although it only had no time to finish.
    func sceneBecameInactive() {
        foreground.setActive(false)
    }

    /// Leave the scanner without a result. Whatever was scanned is discarded.
    func leave() {
        guard !didLeave else { return }
        didLeave = true
        send(.reset)
        // The person chose to drop the scan: its safety copy goes with it.
        recovery?.discard()
        teardown()
        onCancel()
    }

    /// Stops everything and gives the AR session back. Safe to call any number of times.
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        for task in [processingTask, mergeTask, liveBuildTask, liveWaitTask, monitorTask, watchdogTask] {
            task?.cancel()
        }
        processingTask = nil
        mergeTask = nil
        liveBuildTask = nil
        liveWaitTask = nil
        monitorTask = nil
        watchdogTask = nil

        if let view = captureView {
            view.captureSession.delegate = nil
            view.delegate = nil
            if isCaptureRunning { view.captureSession.stop(pauseARSession: true) }
        }
        isCaptureRunning = false
        arSession.delegate = nil
        bridge?.previous = nil
        arSession.pause()
        liveScene = .empty
        keepScreenAwake(false)
    }

    // MARK: Executing effects

    private func send(_ event: ScanEvent) {
        perform(flow.send(event))
        refreshCoach()
    }

    private func perform(_ effects: [ScanEffect]) {
        let expectingData = effects.contains(.buildRoom)
        for effect in effects {
            switch effect {
            case .startCapture: beginCapture()
            case .stopCapture(let keep): endCapture(keepARSession: keep, expectingData: expectingData)
            case .buildRoom: awaitRoomData()
            case .mergeStructure: beginMerge()
            case .saveResult: deliverResult()
            }
        }
    }

    // MARK: Capture

    private func beginCapture() {
        latestRaw = RawCapture()
        stats = .empty
        liveScene = .empty
        instruction = .normal
        liveThrottle.reset()
        liveWaitTask?.cancel()
        liveWaitTask = nil
        bufferedEnd = nil
        endMode = nil
        isWaitingForEnd = false
        isAwaitingEndData = false
        captureGeneration += 1
        needsRelocalizationHelp = false
        hasSnapshot = false
        announcedWallIDs = []
        noFrameSince = nil

        if let view = captureView {
            restartARSessionIfStopped()
            var configuration = RoomCaptureSession.Configuration()
            // Coaching on means RoomPlan's view prints its instructions and also hands each one to
            // `captureSession(_:didProvide:)`. The view's text is hidden from VoiceOver with the camera, so the
            // controller reads the instruction out itself (see `refreshCoach`).
            configuration.isCoachingEnabled = true
            view.captureSession.run(configuration: configuration)
            // RoomPlan may take the AR session's delegate again when a capture starts.
            claimSessionDelegate()
        }
        isCaptureRunning = true
        if !isSimulated { startMonitor() }
    }

    /// Runs the AR session again when it is not running: ARKit says a session that failed "has stopped running
    /// due to an error", and a session this controller paused (`stop(pauseARSession: true)`) is paused too.
    /// Apple's contract is that the session handed to RoomPlan is already running with a world-tracking
    /// configuration; `RoomCaptureSession.run(configuration:)` is not documented to start a stopped one.
    ///
    /// With no finished room the new session starts from scratch (`resetTracking`): there is no earlier space to
    /// keep. With finished rooms it only resumes; `sessionFailed` already counted the restart as a new
    /// coordinate space, so the merge reports rooms from before it honestly.
    private func restartARSessionIfStopped() {
        guard arSessionNeedsRestart else { return }
        arSessionNeedsRestart = false
        let options: ARSession.RunOptions = flow.rooms.isEmpty ? [.resetTracking, .removeExistingAnchors] : []
        arSession.run(Self.worldTrackingConfiguration(), options: options)
        claimSessionDelegate()
        if flow.rooms.isEmpty { canContinueScanning = true }
    }

    /// Stops the capture. `keepARSession` is true while more rooms may follow.
    private func endCapture(keepARSession: Bool, expectingData: Bool) {
        if !keepARSession { arSessionNeedsRestart = true }
        if isCaptureRunning {
            isCaptureRunning = false
            if let view = captureView {
                endMode = expectingData ? .build : .discard
                isAwaitingEndData = expectingData
                lastStopAt = Self.now()
                view.captureSession.stop(pauseARSession: !keepARSession)
                if expectingData { startWatchdog() }
            }
        } else {
            if !expectingData {
                // Already stopped and not wanted: a cancel while the room was being processed. Whatever
                // data is still on its way is thrown away. (With `expectingData`, RoomPlan stopped by
                // itself and its data is already waiting in `bufferedEnd`.)
                if endMode == .build { endMode = .discard }
                bufferedEnd = nil
                isWaitingForEnd = false
                isAwaitingEndData = false
            }
            if !keepARSession { arSession.pause() }
        }
        if !keepARSession {
            monitorTask?.cancel()
            monitorTask = nil
        }
    }

    /// The `buildRoom` effect: turn what the stopped capture produced into a room.
    private func awaitRoomData() {
        if isSimulated {
            processingTask?.cancel()
            processingTask = Task { [weak self] in await self?.processSimulatedRoom() }
            return
        }
        if let end = bufferedEnd {
            bufferedEnd = nil
            startProcessing(end)
        } else {
            isWaitingForEnd = true
        }
    }

    /// RoomPlan reports the end of a capture twice, through the view's delegate and through the session's.
    /// Whichever arrives first is used; `endMode` makes the second one a no-op.
    fileprivate func receivedEnd(data: CapturedRoomData, error: Error?) {
        guard !isTornDown else { return }
        let end = RoomEnd(data: data, error: error)
        switch endMode {
        case .discard:
            endMode = nil
        case .build:
            endMode = nil
            isAwaitingEndData = false
            watchdogTask?.cancel()
            deliver(end)
        case nil:
            // Nobody asked for this: RoomPlan stopped by itself, which it does on errors such as the
            // device overheating. Treat it as the person finishing the room. A callback that follows
            // our own stop within a moment is the second report of that stop, not a new event.
            guard flow.isCapturing, Self.now() - lastStopAt > 1.5 else { return }
            isCaptureRunning = false
            bufferedEnd = end
            send(.finishRoom)
        }
    }

    private func deliver(_ end: RoomEnd) {
        if isWaitingForEnd {
            isWaitingForEnd = false
            startProcessing(end)
        } else {
            bufferedEnd = end
        }
    }

    private func startProcessing(_ end: RoomEnd) {
        processingTask?.cancel()
        processingTask = Task { [weak self] in await self?.process(end) }
    }

    /// How long to wait for RoomPlan to report the end of a stopped capture, seconds of time in the foreground.
    static var endTimeout: TimeInterval = 15

    /// If RoomPlan never reports the end of a capture, say so instead of waiting for ever. Time spent in
    /// another app does not count: a report that arrives late because the app was suspended is not a failure.
    private func startWatchdog() {
        watchdogTask?.cancel()
        let timeout = Self.endTimeout
        let clock = foreground
        watchdogTask = Task { [weak self] in
            guard await clock.wait(seconds: timeout) else { return }
            guard !Task.isCancelled, let self, self.isAwaitingEndData, self.flow.isProcessingRoom else { return }
            self.failRoom(.internalError)
        }
    }

    // MARK: Building a room

    private func process(_ end: RoomEnd) async {
        let failure = end.error.map(Self.failure(for:))
        if let failure, !failure.mayKeepPartialRoom {
            failRoom(failure)
            return
        }
        do {
            let builder = RoomPlan.RoomBuilder(options: [.beautifyObjects])
            let captured = try await builder.capturedRoom(from: end.data)
            guard flow.isProcessingRoom, !Task.isCancelled else { return }

            // Copying the room and encoding its JSON are the heavy parts of a big room: off the main actor, so the
            // "Building the room" state keeps animating. `CapturedRoom` is documented as Sendable.
            let story = configuration.story
            let (raw, encoded) = await Task.detached(priority: .userInitiated) { () -> (RawCapture, Swift.Result<Data, Error>) in
                (CapturedRoomMapper.rawCapture(from: captured, story: story),
                 Swift.Result { try JSONEncoder().encode(captured) })
            }.value
            guard flow.isProcessingRoom, !Task.isCancelled else { return }

            var notes: [String] = []
            if let failure {
                let text = failure.text(hasFinishedRooms: false)
                notes.append("\(text.title). This room may be incomplete.")
            }
            var json: Data?
            switch encoded {
            case .success(let data): json = data
            case .failure:
                notes.append("The raw scan of this room could not be kept, so it is missing from the saved scan data.")
            }
            await finishProcessing(raw: raw, captured: captured, json: json, notes: notes)
        } catch {
            guard flow.isProcessingRoom else { return }
            failRoom(Self.failure(for: error))
        }
    }

    /// Simulator rooms skip RoomPlan and the mapper: a `RawCapture` from the fixtures goes straight in.
    private func processSimulatedRoom() async {
        let raw = SimulatedRoom.capture(forIndex: flow.currentRoomIndex, story: configuration.story, token: practiceToken)
        // A short pause so the "Building the room" state is seen rather than flashing past.
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard flow.isProcessingRoom, !Task.isCancelled else { return }
        await finishProcessing(raw: raw, captured: nil, json: nil, notes: [])
    }

    /// Shared by real and simulated rooms: build the parametric room, make the draft, ask for a name.
    private func finishProcessing(raw: RawCapture, captured: CapturedRoom?, json: Data?, notes: [String]) async {
        guard !raw.walls.isEmpty else {
            failRoom(.notEnoughScanned)
            return
        }
        let built = await Task.detached(priority: .userInitiated) {
            RoomReconstructor.build(from: raw, name: "Room", kind: .other)
        }.value
        guard flow.isProcessingRoom, !Task.isCancelled else { return }

        let id = UUID()
        records[id] = Record(raw: raw, captured: captured, json: json, epoch: spaceEpoch)
        // On disk straight away, before the room is even named: if the app is ended from here on, the scan
        // can be put back (`ScanRecoveryStore`).
        recovery?.addRoom(id: id, raw: raw, capturedJSON: json)
        let live = LiveScanStats(capture: raw)
        stats = live
        // Routine clean-up (merged wall pieces, an estimated floor level) is not worth a person's attention.
        let warnings = built.warnings.filter { $0.severity >= .caution }.map { $0.message } + notes
        let draft = RoomDraft(id: id, stats: live, floorAreaM2: built.room.metrics.floorArea, warnings: warnings)
        liveScene = .empty
        send(.roomFinished(draft))
    }

    /// A room that could not be used. The earlier rooms stay; the person is told what to do.
    private func failRoom(_ failure: ScanFailure) {
        watchdogTask?.cancel()
        endMode = nil
        bufferedEnd = nil
        isWaitingForEnd = false
        isAwaitingEndData = false
        if failure == .trackingFailed { spaceEpoch += 1 }

        let hadRooms = !flow.rooms.isEmpty
        let text = failure.text(hasFinishedRooms: hadRooms)
        alert = ScanAlert(title: text.title, message: text.message + " " + text.recovery,
                          offersRescan: !hadRooms && !Self.isUnrecoverable(failure))
        haptic { Haptics.warning() }
        if flow.isCapturing || flow.isProcessingRoom { send(.cancelRoom) }
    }

    // MARK: Live updates (called by the bridge)

    /// `didUpdate`: a snapshot of the whole room as scanned so far.
    fileprivate func handleUpdate(_ room: CapturedRoom) {
        guard flow.isCapturing, !isTornDown else { return }
        hasSnapshot = true
        let raw = CapturedRoomMapper.rawCapture(from: room, story: configuration.story)
        latestRaw = raw
        let live = LiveScanStats(capture: raw)
        if live != stats { stats = live }
        refreshCoach()
        liveThrottle.markDirty()
        pumpLiveBuild()
    }

    /// `didAdd`, `didChange` and `didRemove`: only the walls that were added, changed or removed (Apple: "the
    /// newest surfaces", "only the surfaces that experience recent changes"). They cannot stand in for a
    /// snapshot, so they count wall identifiers, and only until the first snapshot arrives. That keeps
    /// "Finish room" from depending on one callback.
    fileprivate func handleWallDelta(added: [UUID] = [], removed: [UUID] = []) {
        guard flow.isCapturing, !isTornDown, !hasSnapshot else { return }
        announcedWallIDs.formUnion(added)
        announcedWallIDs.subtract(removed)
        guard announcedWallIDs.count != stats.walls else { return }
        var live = stats
        live.walls = announcedWallIDs.count
        stats = live
        refreshCoach()
    }

    fileprivate func handleInstruction(_ value: RoomCaptureSession.Instruction) {
        guard flow.isCapturing, !isTornDown else { return }
        let mapped: ScanInstruction
        switch value {
        case .normal: mapped = .normal
        case .moveCloseToWall: mapped = .moveCloseToWall
        case .moveAwayFromWall: mapped = .moveAwayFromWall
        case .slowDown: mapped = .slowDown
        case .turnOnLight: mapped = .turnOnLight
        case .lowTexture: mapped = .lowTexture
        @unknown default: mapped = .normal
        }
        if mapped != instruction { instruction = mapped }
        refreshCoach()
    }

    /// Builds the live room from the latest capture at most every half second, off the main thread.
    private func pumpLiveBuild() {
        switch liveThrottle.next(now: Self.now()) {
        case .none:
            return
        case .wait(let delay):
            guard liveWaitTask == nil else { return }
            liveWaitTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.liveWaitTask = nil
                self.pumpLiveBuild()
            }
        case .start:
            let raw = latestRaw
            let units = configuration.units
            let generation = captureGeneration
            liveBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
                var scene = OverlayScene.empty
                if raw.walls.count >= 2 {
                    let built = RoomReconstructor.build(from: raw, name: "Live", kind: .other)
                    scene = OverlayBuilder.scene(for: [built.room], options: .live, units: units)
                }
                await self?.liveBuildFinished(scene, generation: generation)
            }
        }
    }

    private func liveBuildFinished(_ scene: OverlayScene, generation: Int) {
        // A build that started for an earlier room says nothing about this one.
        guard generation == captureGeneration else { return }
        liveThrottle.finished()
        guard flow.isCapturing, !isTornDown else { return }
        liveScene = scene
        pumpLiveBuild()
    }

    // MARK: Tracking

    fileprivate func sessionInterrupted() {
        isInterrupted = true
        setTracking(.interrupted)
    }

    fileprivate func sessionInterruptionEnded() {
        isInterrupted = false
        pollTracking()
        // Finding the place again starts now. The time spent away does not count as time lost.
        restartRelocalizationClock()
    }

    /// ARKit says the camera's tracking changed. A pause for an interruption stays until it ends.
    fileprivate func cameraTrackingChanged(_ issue: ScanTrackingIssue) {
        guard !isTornDown, !isInterrupted else { return }
        setTracking(issue)
    }

    /// ARKit says the session "has stopped running due to an error". It has to be run again before anything
    /// can be scanned (`restartARSessionIfStopped`), and what comes after depends on the rooms already finished:
    /// a restarted session is another coordinate space, so a new room could not be joined to them and only
    /// finishing is offered. With no finished room the person can scan again.
    fileprivate func sessionFailed(_ error: Error) {
        spaceEpoch += 1
        arSessionNeedsRestart = true
        let failure = Self.failure(for: error)
        canContinueScanning = flow.rooms.isEmpty && !Self.isUnrecoverable(failure)
        if flow.isCapturing || flow.isProcessingRoom {
            failRoom(failure)
        } else {
            let text = failure.text(hasFinishedRooms: !flow.rooms.isEmpty)
            alert = ScanAlert(title: text.title, message: text.message + " " + text.recovery, offersRescan: false)
            haptic { Haptics.warning() }
        }
    }

    /// Failures that trying again cannot fix.
    private static func isUnrecoverable(_ failure: ScanFailure) -> Bool {
        failure == .deviceNotSupported || failure == .cameraNotAllowed
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.pollTracking()
            }
        }
    }

    /// How long the AR session may deliver no camera frame at all during a capture before the person is told,
    /// seconds. A running session delivers its first frame within a moment.
    static var noCameraTimeout: TimeInterval = 15

    /// How long tracking may stay lost before the person is offered a way out, seconds.
    static var relocalizationHelpDelay: TimeInterval = 20

    /// Reads ARKit's tracking state. The delegate says the same, but RoomPlan may own the session's delegate,
    /// so the state is also read on a timer. The same tick checks that the AR session is delivering frames at
    /// all, which is what a capture view that never got a running session would not do.
    private func pollTracking() {
        guard !isTornDown else { return }
        claimSessionDelegate()
        let now = Self.now()
        if isInterrupted {
            setTracking(.interrupted)
        } else if let frame = arSession.currentFrame {
            setTracking(Self.issue(for: frame.camera.trackingState))
        } else {
            setTracking(.initializing)
        }
        if let since = relocalizingSince, now - since > Self.relocalizationHelpDelay, !needsRelocalizationHelp {
            needsRelocalizationHelp = true
        }

        if flow.isCapturing, !isInterrupted, arSession.currentFrame == nil {
            if let since = noFrameSince {
                if now - since > Self.noCameraTimeout { failRoom(.cameraUnavailable) }
            } else {
                noFrameSince = now
            }
        } else {
            noFrameSince = nil
        }
    }

    private func setTracking(_ issue: ScanTrackingIssue) {
        guard issue != tracking else { return }
        let wasFine = tracking == .none || tracking == .initializing || tracking == .excessiveMotion
            || tracking == .insufficientFeatures
        tracking = issue
        switch issue {
        case .relocalizing, .notAvailable:
            if relocalizingSince == nil { relocalizingSince = Self.now() }
            if wasFine { haptic { Haptics.warning() } }
        case .interrupted:
            // Away from the app is not "tracking hasn't come back": the clock starts when the interruption ends.
            relocalizingSince = nil
            needsRelocalizationHelp = false
            if wasFine { haptic { Haptics.warning() } }
        case .none, .initializing, .excessiveMotion, .insufficientFeatures:
            relocalizingSince = nil
            needsRelocalizationHelp = false
        }
        refreshCoach()
    }

    /// Starts counting the time tracking has been lost from now, or stops counting when it is fine.
    private func restartRelocalizationClock() {
        needsRelocalizationHelp = false
        relocalizingSince = (tracking == .relocalizing || tracking == .notAvailable) ? Self.now() : nil
    }

    private func refreshCoach() {
        let shown = ScanCoach.companionMessage(tracking: tracking, stats: stats)
        if shown != coach { coach = shown }
        // The size warning is a pill VoiceOver would not reach by itself: say it once, when it first appears.
        if !didAnnounceFloorSize, let caution = floorSizeCaution {
            didAnnounceFloorSize = true
            if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: caution) }
        }
        // VoiceOver hears RoomPlan's instructions too: the capture view, with its printed text, is hidden from it.
        let spoken = ScanCoach.message(instruction: instruction, tracking: tracking, stats: stats)
        guard flow.isCapturing || (flow.state == .betweenRooms && spoken.level == .critical) else { return }
        if announcer.shouldAnnounce(spoken, at: Self.now()), UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: spoken.text)
        }
    }

    // MARK: Merging

    private func beginMerge() {
        mergeStep = .joiningRooms
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in await self?.runMerge() }
    }

    private func runMerge() async {
        let entries = flow.rooms
        var warnings: [String] = []
        if isSimulated {
            warnings.append("This was a practice scan from the Simulator. It has no 3D model and no AR map.")
        }

        // The parametric rooms, built again with their final names and kinds.
        let inputs: [(name: String, kind: RoomKind, raw: RawCapture)] = entries.compactMap { entry in
            records[entry.id].map { (entry.name, entry.kind, $0.raw) }
        }
        let rooms: [Room] = await Task.detached(priority: .userInitiated) {
            inputs.map { RoomReconstructor.build(from: $0.raw, name: $0.name, kind: $0.kind).room }
        }.value
        guard !Task.isCancelled, flow.state == .merging else { return }
        guard !rooms.isEmpty, inputs.count == entries.count else {
            send(.mergeFailed(message: "The scanned rooms could not be read back. Scan the property again."))
            return
        }

        var capturedJSON: [UUID: Data] = [:]
        for (entry, room) in zip(entries, rooms) {
            if let json = records[entry.id]?.json { capturedJSON[room.id] = json }
            for note in entry.draft.warnings { warnings.append("\(entry.name): \(note)") }
        }

        // One 3D model of the floor.
        var usdz: Data?
        if !isSimulated {
            let epochs = Set(entries.compactMap { records[$0.id]?.epoch })
            if epochs.count > 1 {
                warnings.append("Tracking restarted partway through, so the rooms scanned before it are in a different space. No joined 3D model was made. The plans and measurements are saved.")
            } else {
                let captured = entries.compactMap { records[$0.id]?.captured }
                if captured.count != entries.count {
                    warnings.append("Some rooms have no 3D scan data, so no joined 3D model was made. The plans and measurements are saved.")
                } else {
                    do {
                        usdz = try await exportModel(from: captured)
                    } catch {
                        // Scan-time advice ("walk along the walls") makes no sense now that scanning is over.
                        warnings.append(Self.failure(for: error).mergeWarning)
                    }
                }
            }
        }
        guard !Task.isCancelled, flow.state == .merging else { return }

        // The AR map, so AR review can line up with this scan later.
        var worldMap: Data?
        if !isSimulated {
            mergeStep = .savingMap
            let status = arSession.currentFrame?.worldMappingStatus
            do {
                worldMap = try await archivedWorldMap(timeout: 8)
                if status == .limited || status == .notAvailable {
                    warnings.append("ARKit had only a thin map of this floor, so AR labels may drift when you review it later. Next time, walk the whole floor slowly before you finish.")
                }
            } catch {
                warnings.append("The AR map could not be saved, so AR labels may not line up when you review this floor later. Scan the floor again on site to fix this.")
            }
            let latest = spaceEpoch
            let stale = entries.filter { (records[$0.id]?.epoch ?? latest) != latest }.map(\.name)
            if !stale.isEmpty {
                warnings.append("AR review will only line up for the rooms scanned after tracking restarted. These were scanned before it: \(stale.joined(separator: ", ")).")
            }
        }
        guard !Task.isCancelled, flow.state == .merging else { return }

        pendingResult = ScanResult(rooms: rooms, capturedRoomJSON: capturedJSON, structureUSDZ: usdz,
                                   worldMapData: worldMap, story: configuration.story, warnings: warnings,
                                   recoveryID: recovery?.scanID)
        send(.mergeCompleted)
    }

    /// Joins the rooms (a single room is exported as it is) and writes the USDZ. The export runs off the
    /// main thread and each slow step gives up after `modelTimeout`, so a stuck merge cannot trap the person
    /// on the progress screen. `.mesh` is used because it has polygonal walls with the doors and windows cut
    /// out, and RoomPlan's documentation does not say what combining it with `.parametric` produces.
    private func exportModel(from rooms: [CapturedRoom]) async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexafix-scan-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = foreground

        if rooms.count == 1, let only = rooms.first {
            mergeStep = .writingModel
            return try await Self.withTimeout(seconds: Self.modelTimeout, clock: clock) {
                try only.export(to: url, exportOptions: .mesh)
                return try Data(contentsOf: url)
            }
        }

        let structure = try await Self.withTimeout(seconds: Self.modelTimeout, clock: clock) {
            try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
        }
        mergeStep = .writingModel
        return try await Self.withTimeout(seconds: Self.modelTimeout, clock: clock) {
            try structure.export(to: url, exportOptions: .mesh)
            return try Data(contentsOf: url)
        }
    }

    /// How long joining the rooms or writing the file may take before it is given up, seconds in the foreground.
    private static let modelTimeout: TimeInterval = 90

    /// Runs `work` off the main thread and stops waiting for it after `seconds` of time in the foreground (see
    /// `ForegroundClock`). The work itself cannot be cancelled, so a late result is simply dropped.
    private static func withTimeout<T: Sendable>(seconds: TimeInterval,
                                                 clock: ForegroundClock,
                                                 _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = ResumeOnce<T>(continuation)
            let timer = Task.detached(priority: .utility) {
                if await clock.wait(seconds: seconds) { gate.resume(throwing: TimeoutError()) }
            }
            Task.detached(priority: .userInitiated) {
                do {
                    gate.resume(returning: try await work())
                } catch {
                    gate.resume(throwing: error)
                }
                timer.cancel()
            }
        }
    }

    /// The current `ARWorldMap` as archived data. Gives up after `timeout` seconds in the foreground, because
    /// ARKit may never call back when the session is interrupted.
    private func archivedWorldMap(timeout: TimeInterval) async throws -> Data {
        let clock = foreground
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let gate = ResumeOnce<Data>(continuation)
            let timer = Task.detached(priority: .utility) {
                if await clock.wait(seconds: timeout) { gate.resume(throwing: TimeoutError()) }
            }
            arSession.getCurrentWorldMap { map, error in
                guard let map else {
                    gate.resume(throwing: error ?? WorldMapError.unavailable)
                    timer.cancel()
                    return
                }
                // ARKit calls this on the main queue (the session has no `delegateQueue`), and archiving a big
                // map there would stall the progress screen. Apple: "do so on an appropriate dispatch queue".
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                        gate.resume(returning: data)
                    } catch {
                        gate.resume(throwing: error)
                    }
                    timer.cancel()
                }
            }
        }
    }

    private func deliverResult() {
        guard let result = pendingResult else { return }
        pendingResult = nil
        // Handed over: the safety copy stays until the app confirms the scan is saved (`ScanResult.recoveryID`).
        recovery?.markDelivered()
        haptic { Haptics.success() }
        teardown()
        onFinish(result)
    }

    // MARK: Helpers

    private func haptic(_ play: () -> Void) {
        if configuration.hapticsEnabled { play() }
    }

    private func keepScreenAwake(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    /// A monotonic clock in seconds.
    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    nonisolated static func issue(for state: ARCamera.TrackingState) -> ScanTrackingIssue {
        switch state {
        case .normal:
            return .none
        case .notAvailable:
            return .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing: return .initializing
            case .excessiveMotion: return .excessiveMotion
            case .insufficientFeatures: return .insufficientFeatures
            case .relocalizing: return .relocalizing
            @unknown default: return .insufficientFeatures
            }
        }
    }

    /// Maps every error the scan can meet onto the words in `ScanFailure`.
    static func failure(for error: Error) -> ScanFailure {
        if let e = error as? RoomCaptureSession.CaptureError {
            switch e {
            case .deviceNotSupported: return .deviceNotSupported
            case .deviceTooHot: return .deviceTooHot
            case .exceedSceneSizeLimit: return .sceneTooLarge
            case .invalidARConfiguration, .worldTrackingFailure: return .trackingFailed
            case .internalError: return .internalError
            @unknown default: return .unknown
            }
        }
        if let e = error as? RoomPlan.RoomBuilder.BuildError {
            switch e {
            case .insufficientInput: return .notEnoughScanned
            case .invalidInput: return .invalidScanData
            case .exceedSceneSizeLimit: return .sceneTooLarge
            case .internalError: return .internalError
            case .deviceNotSupported: return .deviceNotSupported
            @unknown default: return .unknown
            }
        }
        if let e = error as? StructureBuilder.BuildError {
            switch e {
            case .invalidRoomLocation: return .roomsNotConnected
            case .insufficientInput: return .notEnoughScanned
            case .invalidInput: return .invalidScanData
            case .exceedSceneSizeLimit: return .sceneTooLarge
            case .internalError: return .internalError
            case .deviceNotSupported: return .deviceNotSupported
            @unknown default: return .unknown
            }
        }
        if error is CapturedRoom.Error || error is TimeoutError { return .exportFailed }
        // `ARError.Code` is documented as RawRepresentable, so the code is read from the bridged `NSError`.
        if error is ARError, let code = ARError.Code(rawValue: (error as NSError).code) {
            switch code {
            case .cameraUnauthorized: return .cameraNotAllowed
            case .sensorUnavailable, .sensorFailed: return .cameraUnavailable
            case .worldTrackingFailed: return .trackingFailed
            default: return .unknown
            }
        }
        return .unknown
    }
}

// MARK: - Simulator rooms

/// The practice rooms the Simulator produces, so a demo scan has rooms that differ and sit side by side
/// on the plan. They come from Core's `CaptureFixtures`, the same synthetic RoomPlan-shaped captures the
/// tests and the demo property use, and go through exactly the path a real scan takes from `RawCapture` on.
enum SimulatedRoom {
    struct Spec {
        var width: Double
        var depth: Double
        var height: Double
        var doors: Int
        var windows: Int
    }

    private static let specs: [Spec] = [
        Spec(width: 5.2, depth: 4.4, height: 2.7, doors: 1, windows: 2),
        Spec(width: 3.6, depth: 3.2, height: 2.7, doors: 1, windows: 1),
        Spec(width: 4.1, depth: 3.5, height: 2.7, doors: 1, windows: 1),
        Spec(width: 3.0, depth: 3.0, height: 2.7, doors: 1, windows: 1),
        Spec(width: 2.4, depth: 2.2, height: 2.7, doors: 1, windows: 0),
    ]

    /// Gap between neighbouring practice rooms on the plan, metres.
    private static let gap = 0.3

    static func spec(forIndex index: Int) -> Spec {
        specs[max(0, index) % specs.count]
    }

    /// Room number `index` (zero-based): a rectangle placed to the right of the ones before it.
    ///
    /// Core derives the room id and every wall id from the fixture label, so `token` (one per scan) is part of
    /// the label. Without it a second practice scan saved into the same property would reuse the first scan's
    /// room and wall ids, and a verification made on one room would show on the other.
    static func capture(forIndex index: Int, story: Int, token: String) -> RawCapture {
        let spec = spec(forIndex: index)
        let doors = (0..<spec.doors).map { OpeningSpec.door(wall: 0, offset: 0.5 + Double($0)) }
        let windows = (0..<spec.windows).map { OpeningSpec.window(wall: 2, offset: 0.6 + Double($0) * 1.8, width: 1.2) }

        var extras = CaptureFixtures.Extras()
        extras.origin = Point2((0..<max(0, index)).reduce(0.0) { $0 + Self.spec(forIndex: $1).width + gap }, 0)
        extras.label = "practice-\(index + 1)-\(token)"

        var capture = CaptureFixtures.rectangle(width: spec.width, depth: spec.depth, height: spec.height,
                                                doors: doors, windows: windows, noise: .light,
                                                seed: UInt64(index + 1), extras: extras).capture
        capture.story = story
        return capture
    }
}

// MARK: - Plumbing

/// Pauses the AR session when the controller goes away, even if `teardown()` was never called.
/// A plain class, so its `deinit` is not tied to the main actor.
private final class SessionLease {
    private let session: ARSession

    init(_ session: ARSession) {
        self.session = session
    }

    deinit {
        session.delegate = nil
        session.pause()
    }
}

private enum WorldMapError: Error {
    case unavailable
}

/// A step took longer than it was allowed to.
private struct TimeoutError: Error {}

/// Counts time only while the app is in the foreground.
///
/// A plain timer keeps running while iOS has suspended the app. When the person switches to another app during
/// "Building the 3D model" and comes back, every timeout has run out at once, so a 3D file that would have
/// finished a moment later, or an AR map that ARKit could not deliver while its camera was away, is reported
/// as failed. The controller tells this clock when the scene becomes active or leaves it, and a timeout waits
/// through the time away.
///
/// A tick is counted only if the app was in the foreground when it ended, so the first tick after coming back
/// (which can end before the scene reports it is active again) is not counted: the wait errs on the long side.
private final class ForegroundClock: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    /// Returns true after `seconds` of time spent in the foreground, false when the waiting task is cancelled.
    func wait(seconds: TimeInterval, tick: TimeInterval = 0.5) async -> Bool {
        var waited: TimeInterval = 0
        while waited < seconds {
            do {
                try await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            } catch {
                return false
            }
            if isActive { waited += tick }
        }
        return !Task.isCancelled
    }
}

/// Lets a continuation be resumed from whichever of two callbacks arrives first. The second is ignored.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let taken = continuation
        continuation = nil
        return taken
    }
}

/// Receives RoomPlan's and ARKit's callbacks and passes them to the controller on the main thread.
///
/// It exists because `RoomCaptureViewDelegate` inherits `NSCoding`, which would force the controller to be
/// an `NSObject` with archiving methods. The callbacks' threads are not documented, so each one hops to the
/// main actor before touching the controller.
///
/// As the AR session's delegate it does not replace what was there. RoomPlan owns the session and may be its
/// delegate, so every ARKit callback is also passed on to `previous`, on the thread ARKit used.
final class ScanCaptureBridge: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, ARSessionDelegate {
    weak var controller: ScanSessionController?
    /// The AR session delegate that was in place before the bridge took over, or nil if there was none.
    weak var previous: (any ARSessionDelegate)?

    override init() {
        super.init()
    }

    // NSCoding, required by RoomCaptureViewDelegate. The bridge is never archived.
    required init?(coder: NSCoder) {
        super.init()
    }

    func encode(with coder: NSCoder) {}

    private func onMain(_ work: @escaping @MainActor (ScanSessionController) -> Void) {
        let run: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let controller = self?.controller else { return }
                work(controller)
            }
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        onMain { $0.handleUpdate(room) }
    }

    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        let ids = room.walls.map(\.identifier)
        onMain { $0.handleWallDelta(added: ids) }
    }

    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        let ids = room.walls.map(\.identifier)
        onMain { $0.handleWallDelta(added: ids) }
    }

    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        let ids = room.walls.map(\.identifier)
        onMain { $0.handleWallDelta(removed: ids) }
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        onMain { $0.handleInstruction(instruction) }
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        onMain { $0.receivedEnd(data: data, error: error) }
    }

    // MARK: RoomCaptureViewDelegate

    /// The scan's raw data arrives here too. Returning false keeps the framework from processing it and
    /// showing its own preview: the controller builds the room and shows the name sheet instead.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        onMain { $0.receivedEnd(data: roomDataForProcessing, error: error) }
        return false
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {}

    // MARK: ARSessionDelegate and ARSessionObserver
    //
    // Each method below does its own job (if any) and then hands the call to `previous`. Apple's article on
    // scanning several rooms has the app implement `sessionShouldAttemptRelocalization(_:)` and
    // `session(_:cameraDidChangeTrackingState:)` on the AR session's delegate; forwarding the rest keeps
    // RoomPlan's own handling of frames, anchors and interruptions working.

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        previous?.session?(session, didUpdate: frame)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        previous?.session?(session, didAdd: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        previous?.session?(session, didUpdate: anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        previous?.session?(session, didRemove: anchors)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        previous?.session?(session, cameraDidChangeTrackingState: camera)
        let issue = ScanSessionController.issue(for: camera.trackingState)
        onMain { $0.cameraTrackingChanged(issue) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        previous?.sessionWasInterrupted?(session)
        onMain { $0.sessionInterrupted() }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        previous?.sessionInterruptionEnded?(session)
        onMain { $0.sessionInterruptionEnded() }
    }

    /// Lets ARKit keep looking for the place the person left, so the next room can still join the others.
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        previous?.session?(session, didFailWithError: error)
        onMain { $0.sessionFailed(error) }
    }
}
#endif
