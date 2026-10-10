import SwiftUI
import UIKit
import ARKit
import NexaFixCore

/// The scan screen. Present it full-screen.
///
/// The person taps Scan, walks room to room, names each room and ends with one merged 3D model of the floor
/// plus parametric rooms. Everything in one continuous AR session, so the rooms join.
///
///  - Camera full-bleed (Apple's capture view), with live labels on the walls being detected.
///  - A glass pill at the top says what to do next, or that tracking was lost; RoomPlan's capture view prints its
///    own instructions ("Move closer to the wall"), which the pill does not repeat. A second pill shows the
///    live counts and rough area.
///  - Bottom: Finish room (accent) and Cancel while scanning; after a room, a sheet to name it, then
///    Scan next room or Finish property.
///  - Joining the rooms shows what is happening ("Building the 3D model"), never a bare spinner.
///
/// Before that, a device without LiDAR gets a calm explanation, and the camera permission is explained
/// before the system asks for it (`PermissionPrimer`).
///
/// This view never shows results. It calls `onFinish` with a `ScanResult` or `onCancel`, and has released
/// the camera by then.
struct ScanFlowView: View {
    private let configuration: ScanConfiguration
    private let onFinish: (ScanResult) -> Void
    private let onCancel: () -> Void

    @State private var capability: DeviceCapability
    @State private var controller: ScanSessionController?
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - configuration: Property name, existing room names, units, haptics and floor.
    ///   - onFinish: The scan is done. Save the result.
    ///   - onCancel: The person left without a result.
    init(configuration: ScanConfiguration,
         onFinish: @escaping (ScanResult) -> Void,
         onCancel: @escaping () -> Void) {
        self.configuration = configuration
        self.onFinish = onFinish
        self.onCancel = onCancel
        _capability = State(initialValue: DeviceCapability.current)
    }

    var body: some View {
        ZStack {
            if let controller {
                ScanStage(controller: controller)
            } else {
                gate
            }
        }
        // The permission, no-LiDAR and denied screens follow the person's appearance setting. Only the camera
        // stage is dark (see `ScanStage`).
        .onAppear { prepare() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                // Away from the app: the merge timeouts stop counting until it is back.
                controller?.sceneBecameInactive()
                return
            }
            if let controller {
                // Back from another app: the time away does not count as tracking that failed to return.
                controller.sceneBecameActive()
            } else {
                // Back from Settings with the camera switched on.
                prepare()
            }
        }
        // The camera must never keep running behind a screen that has gone.
        .onDisappear { controller?.teardown() }
    }

    // MARK: Before scanning

    @MainActor @ViewBuilder
    private var gate: some View {
        if capability == .supported {
            ZStack {
                Palette.background.ignoresSafeArea()
                ProgressView()
            }
        } else {
            PermissionPrimer(capability: capability,
                             onUpdate: { updated in
                                 capability = updated
                                 if updated == .supported { startController(simulated: false) }
                             },
                             onClose: onCancel,
                             onSimulate: simulateAction)
        }
    }

    /// Only the Simulator offers a practice scan.
    @MainActor
    private var simulateAction: (() -> Void)? {
        #if targetEnvironment(simulator)
        return { startController(simulated: true) }
        #else
        return nil
        #endif
    }

    @MainActor
    private func prepare() {
        guard controller == nil else { return }
        capability = DeviceCapability.current
        if capability == .supported { startController(simulated: false) }
    }

    @MainActor
    private func startController(simulated: Bool) {
        guard controller == nil else { return }
        let created = ScanSessionController(configuration: configuration, isSimulated: simulated,
                                            onFinish: onFinish, onCancel: onCancel)
        controller = created
    }
}

// MARK: - The scanning stage

/// Everything on screen once a controller exists. It only reads the controller and calls its actions.
@MainActor
private struct ScanStage: View {
    let controller: ScanSessionController

    @State private var showsLiveLabels = true
    @State private var isConfirmingLeave = false

    var body: some View {
        ZStack {
            camera

            if showsLiveLabels, controller.canShowLiveLabels {
                AROverlayCanvas(session: controller.arSession, scene: controller.liveScene,
                                accessibilityName: "Live measurements")
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if controller.flow.state == .merging {
                ScanMergeCard(step: controller.mergeStep, roomCount: controller.flow.rooms.count)
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if controller.flow.state != .merging { topBar }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if controller.flow.state != .merging { bottomArea }
        }
        .motion(value: controller.flow.state)
        .motion(value: controller.coach)
        // Dark glass and light ink over the camera, as DESIGN.md asks for the scan screen. Set here, not on the
        // whole flow, so the screens before the camera follow the person's appearance setting.
        .preferredColorScheme(.dark)
        // A real scan starts once the capture view has a window (`RoomCaptureViewContainer`). The practice
        // stage has no camera view, so it starts as soon as it appears.
        .onAppear { if controller.isSimulated { controller.start() } }
        .sheet(item: nameSheetItem) { draft in
            RoomNameSheet(flow: controller.flow,
                          draft: draft,
                          units: controller.configuration.units,
                          canScanNext: controller.canContinueScanning,
                          onScanNext: { name, kind in controller.nameRoom(name, kind: kind, then: .scanNextRoom) },
                          onFinishProperty: { name, kind in controller.nameRoom(name, kind: kind, then: .finishProperty) },
                          onRescan: { controller.rescanRoom() },
                          onDiscard: { controller.discardWaitingRoom() })
        }
        .alert(controller.alert?.title ?? "", isPresented: alertIsPresented, presenting: controller.alert) { alert in
            if alert.offersRescan {
                Button("Scan again") { controller.scanAgain() }
                Button("Close", role: .cancel) { controller.leave() }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(verbatim: alert.message)
        }
        .confirmationDialog("Discard this scan?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button(discardTitle, role: .destructive) { controller.leave() }
            Button("Keep scanning", role: .cancel) {}
        } message: {
            Text(verbatim: "These rooms have not been saved yet.")
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var camera: some View {
        if controller.isSimulated {
            SimulatorScanStage(roomIndex: controller.flow.currentRoomIndex)
        } else {
            // The camera image says nothing VoiceOver can use; the pills and buttons carry the words.
            RoomCaptureViewContainer(controller: controller)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            GlassIconButton(systemImage: "xmark", label: "Close scanner") { requestLeave() }

            Spacer(minLength: 0)

            VStack(spacing: Spacing.s) {
                pills
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 0)

            if !controller.isSimulated, controller.flow.isCapturing {
                GlassIconButton(systemImage: showsLiveLabels ? "ruler.fill" : "ruler",
                                label: showsLiveLabels ? "Hide live measurements" : "Show live measurements") {
                    showsLiveLabels.toggle()
                    if controller.configuration.hapticsEnabled { Haptics.selection() }
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
    }

    @ViewBuilder
    private var pills: some View {
        switch controller.flow.state {
        case .scanning:
            if controller.isSimulated {
                Pill("Practice room \(controller.flow.currentRoomIndex + 1)", systemImage: "cube.transparent")
            } else {
                ScanCoachPill(message: controller.coach)
                ScanMetricsPill(summary: controller.statsSummary, spoken: controller.statsSpoken)
                sizeCaution
            }
        case .betweenRooms:
            if controller.coach.level == .critical, !controller.isSimulated {
                ScanCoachPill(message: controller.coach)
            } else if let last = controller.flow.rooms.last {
                // "Scanned", not "saved": nothing is saved until the property is finished. And no green check
                // mark: that look belongs to laser-verified values, never to a LiDAR scan.
                Pill("\(last.name) scanned", systemImage: "cube.transparent")
            }
            sizeCaution
        case .idle, .processingRoom, .awaitingName, .merging, .finished, .failed:
            EmptyView()
        }
    }

    /// Shown once the floor is bigger than RoomPlan recommends joining into one 3D model.
    @ViewBuilder
    private var sizeCaution: some View {
        if let text = controller.floorSizeCaution {
            Pill(text, systemImage: "exclamationmark.triangle.fill", tint: Palette.caution)
        }
    }

    private var bottomArea: some View {
        VStack(spacing: Spacing.m) {
            if controller.needsRelocalizationHelp, controller.flow.isCapturing || controller.flow.state == .betweenRooms {
                ScanTrackingHelpCard(roomCount: controller.flow.rooms.count) {
                    controller.finishWithRoomsSoFar()
                }
            }
            if case .failed(let message) = controller.flow.state {
                ScanMergeFailedCard(message: message,
                                    roomCount: controller.flow.rooms.count,
                                    canScanMore: controller.canContinueScanning,
                                    onTryAgain: { controller.finishProperty() },
                                    onScanMore: { controller.scanNextRoom() },
                                    onClose: { controller.leave() })
            } else {
                ScanBottomBar(controller: controller)
            }
        }
    }

    // MARK: Bindings and words

    /// The name sheet is shown while a room waits for its name. Only the controller dismisses it.
    private var nameSheetItem: Binding<RoomDraft?> {
        Binding(get: { controller.flow.draftAwaitingName }, set: { _ in })
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(get: { controller.alert != nil }, set: { shown in if !shown { controller.alert = nil } })
    }

    private var discardTitle: String {
        let count = controller.roomsAtRisk
        return count == 1 ? "Discard 1 room" : "Discard \(count) rooms"
    }

    /// Leaving asks first only when rooms would be thrown away.
    private func requestLeave() {
        if controller.flow.wouldLoseWork {
            isConfirmingLeave = true
        } else {
            controller.leave()
        }
    }
}
