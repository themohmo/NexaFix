import SwiftUI
import NexaFixCore

/// Walk into a saved room, open AR, and see its measurements on the real walls.
///
/// The camera fills the screen. Wall lengths, ceiling height, door and window sizes, corner angles and the
/// floor area float where they belong, and a LiDAR-snapped tape measure is one tap away. The overlay is
/// drawn only after ARKit has relocalised against the room's saved world map (see `ARStatusSummary`);
/// until then a status pill says what is happening, and if it cannot line up the screen says so plainly
/// instead of drawing numbers in the wrong place.
struct ARReviewView: View {
    private let rooms: [Room]
    private let units: DisplayUnits
    private let hapticsEnabled: Bool

    @State private var controller: ARReviewController
    @State private var measurementName = ""
    @FocusState private var isNameFocused: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - rooms: The saved rooms of the floor being walked. Their coordinates belong to the scan session.
    ///   - focusRoomID: The room to show first; the first room when nil.
    ///   - worldMapURL: The archived `ARWorldMap` saved with the scan. Without it the overlay cannot line up.
    ///   - units: How lengths are written.
    ///   - hapticsEnabled: The Settings switch.
    ///   - onSaveMeasurement: Called with a tape measurement and the room it belongs to.
    ///   - onClose: The person left the screen.
    init(rooms: [Room], focusRoomID: UUID?, worldMapURL: URL?, units: DisplayUnits, hapticsEnabled: Bool,
         onSaveMeasurement: @escaping (CustomMeasurement, UUID) -> Void, onClose: @escaping () -> Void) {
        self.rooms = rooms
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        _controller = State(initialValue: ARReviewController(
            rooms: rooms, focusRoomID: focusRoomID, worldMapURL: worldMapURL, units: units,
            hapticsEnabled: hapticsEnabled, onSaveMeasurement: onSaveMeasurement, onClose: onClose))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .onAppear {
            controller.hapticsEnabled = hapticsEnabled
            controller.prepare()
        }
        .onDisappear { controller.stop() }
        .onChange(of: rooms) { _, new in controller.update(rooms: new) }
        .onChange(of: units) { _, new in controller.update(units: new) }
        .onChange(of: hapticsEnabled) { _, new in controller.hapticsEnabled = new }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings with the camera switched on, or from the background.
            if phase == .active { controller.prepare() }
        }
        .onChange(of: controller.isNaming) { _, naming in
            if naming {
                measurementName = ""
                isNameFocused = true
            } else {
                isNameFocused = false
            }
        }
        .sensoryFeedback(.selection, trigger: controller.options) { _, _ in hapticsEnabled }
    }

    // MARK: Screens

    // The helpers that use `.fadeScale` and `.sheetRise` are marked `@MainActor`: those transitions are
    // main-actor isolated, and before iOS 18's SDK only `body` itself was.
    @MainActor @ViewBuilder
    private var content: some View {
        switch controller.access {
        case .checking:
            Color.clear
        case .ready:
            arLayer
        case .needsExplanation:
            ARInfoCard(symbol: "camera.viewfinder", title: "Allow the camera",
                       message: "NexaFix Scan uses the camera to line the measurements up with the room. Your scans stay on this iPhone, and in its backup if you back it up. Nothing is sent anywhere unless you export it.",
                       primaryTitle: "Allow camera", primaryAction: { controller.requestCameraAccess() },
                       closeAction: { controller.close() })
        case .denied:
            ARInfoCard(symbol: "camera.fill", title: "Camera access is off",
                       message: "Switch on the camera for NexaFix Scan in Settings to see measurements on the walls.",
                       primaryTitle: "Open Settings", primaryAction: { controller.openSettings() },
                       closeAction: { controller.close() })
        case .unsupported:
            ARInfoCard(symbol: "viewfinder", title: "AR isn't available here",
                       message: "This device can't track a room in AR. Open the room in the 3D viewer instead.",
                       primaryTitle: nil, primaryAction: nil, closeAction: { controller.close() })
        case .failed(let message):
            ARInfoCard(symbol: "exclamationmark.triangle.fill", title: "AR stopped", message: message,
                       primaryTitle: "Try again", primaryAction: { controller.retry() },
                       closeAction: { controller.close() })
        }
    }

    @MainActor
    private var arLayer: some View {
        ZStack {
            ARViewContainer(controller: controller)
                .ignoresSafeArea()

            overlays

            if controller.isMeasuring {
                ARReticleLayer(controller: controller)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.addPoint() }
                    .accessibilityHidden(true)
            }

            VStack(spacing: Spacing.m) {
                topBar
                if let message = controller.status.message {
                    unalignedCard(message: message, offersKeepTrying: controller.status.offersKeepTrying)
                        .transition(.fadeScale)
                }
                Spacer(minLength: 0)
                bottomStack
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
        }
        .motion(value: uiState)
    }

    /// The values whose changes animate (appearance and disappearance of cards and the overlay).
    private struct UIState: Equatable {
        var overlay: Bool
        var message: Bool
        var measuring: Bool
        var complete: Bool
        var naming: Bool
        var notice: Bool
    }

    private var uiState: UIState {
        UIState(overlay: controller.status.overlayAllowed, message: controller.status.message != nil,
                measuring: controller.isMeasuring, complete: controller.measure.isComplete,
                naming: controller.isNaming, notice: controller.notice != nil)
    }

    // MARK: Overlay layers

    @ViewBuilder
    private var overlays: some View {
        if let session = controller.session {
            if controller.status.overlayAllowed {
                AROverlayCanvas(session: session, scene: controller.baseScene,
                                accessibilityName: "Room measurements")
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            // The person's own tape measurement belongs to the current session, so it is always honest to draw.
            if !controller.measure.isEmpty {
                AROverlayCanvas(session: session, scene: controller.measureScene,
                                accessibilityName: "Tape measure")
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            GlassIconButton(systemImage: "xmark", label: "Close AR view") { controller.close() }
            ARTrackingStatusPill(summary: controller.status)
            Spacer(minLength: 0)
        }
    }

    private func unalignedCard(message: String, offersKeepTrying: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            actionRow {
                if offersKeepTrying {
                    Button("Keep trying") { controller.keepTrying() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Close") { controller.close() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Spacing.l)
        .arPanelWidth(alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .accessibilityElement(children: .contain)
    }

    // MARK: Bottom

    @MainActor
    private var bottomStack: some View {
        VStack(spacing: Spacing.s) {
            if let notice = controller.notice {
                Pill(notice, systemImage: "info.circle")
                    .transition(.fadeScale)
            } else if controller.isMeasuring, !controller.measure.isComplete {
                Pill(controller.measure.isEmpty ? "Aim at the first point, then tap Add point."
                                                : "Now aim at the second point.",
                     systemImage: "scope", tint: Palette.accent)
                    .transition(.fadeScale)
            } else if controller.rooms.isEmpty, !controller.isMeasuring {
                // Nothing to draw: say so instead of showing a bare camera.
                Pill("No saved rooms to show. You can still measure.", systemImage: "info.circle")
                    .transition(.fadeScale)
            }

            if controller.isMeasuring, controller.measure.isComplete {
                readoutCard
                    .transition(.sheetRise)
            }

            if controller.rooms.count > 1, !controller.isMeasuring {
                roomChips
            }

            if controller.isMeasuring {
                measureBar
            } else {
                reviewBar
            }
        }
    }

    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(controller.rooms) { room in
                    ARRoomChip(name: room.name.isEmpty ? room.kind.displayName : room.name,
                             isSelected: room.id == controller.selectedRoomID) {
                        controller.selectRoom(room.id)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
        }
        .arPanelWidth()
    }

    private var reviewBar: some View {
        barLayout {
            AROverlayToggle(title: "Dimensions", systemImage: "ruler", isOn: optionBinding(\.showDimensions))
            AROverlayToggle(title: "Angles", systemImage: "angle", isOn: optionBinding(\.showAngles))
            AROverlayToggle(title: "Openings", systemImage: "door.left.hand.open", isOn: optionBinding(\.showOpenings))
            ARAccentActionButton(title: "Measure", systemImage: "scope") { controller.setMeasuring(true) }
        }
        .padding(Spacing.s)
        .arPanelWidth()
        .glass(cornerRadius: Radius.card, prominence: .regular)
    }

    private var measureBar: some View {
        barLayout {
            Button("Done") { controller.setMeasuring(false) }
                .buttonStyle(ARBarTextButtonStyle())
            ARAccentActionButton(title: "Add point", systemImage: "plus") { controller.addPoint() }
                .accessibilityHint("Places a point where the circle in the middle of the screen is.")
            Button("Clear") { controller.clearMeasurement() }
                .buttonStyle(ARBarTextButtonStyle())
                .disabled(controller.measure.isEmpty)
        }
        .padding(Spacing.s)
        .arPanelWidth()
        .glass(cornerRadius: Radius.card, prominence: .regular)
    }

    /// A row of controls that stacks vertically at accessibility text sizes.
    private func barLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))
        return layout { content() }
    }

    private func actionRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(spacing: Spacing.s))
        return layout { content() }
    }

    private func optionBinding(_ keyPath: WritableKeyPath<OverlayOptions, Bool>) -> Binding<Bool> {
        Binding(get: { controller.options[keyPath: keyPath] },
                set: { controller.setOption(keyPath, to: $0) })
    }

    // MARK: Readout

    private var readoutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if controller.isNaming {
                namingContent
            } else if let reading = controller.reading, let readout = controller.readout {
                readoutContent(reading: reading, readout: readout)
            }
        }
        .padding(Spacing.l)
        .arPanelWidth(alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func readoutContent(reading: TapeReading, readout: TapeReadout) -> some View {
        MeasurementText(length: TapeMeasure.quantise(reading.lengthM), units: units, style: .hero)

        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.l))
        layout {
            ARAxisValue(name: "\u{0394}X", spokenName: "Delta X", text: readout.deltaX,
                      spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaX), unit: units.length))
            ARAxisValue(name: "\u{0394}Y", spokenName: "Delta Y, up", text: readout.deltaY,
                      spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaY), unit: units.length))
            ARAxisValue(name: "\u{0394}Z", spokenName: "Delta Z", text: readout.deltaZ,
                      spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaZ), unit: units.length))
        }

        // A tape reading is a LiDAR value: never present it as laser-checked. What the note says about saving
        // depends on whether this room can ever line up (a room with no saved AR map never does).
        Label {
            Text(verbatim: controller.status.tapeSaveNote)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.caution)
        }

        actionRow {
            Button("Save") { controller.beginNaming() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!controller.canSaveMeasurement)
            Button("Clear") { controller.clearMeasurement() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var namingContent: some View {
        Text("Name this measurement")
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
        // Say where it goes before it goes there: the room is worked out from the points, and a measurement
        // filed on the wrong room would end up in that room's exports and costing.
        if let room = controller.measurementRoom {
            Text(verbatim: "Saving to \(ARReviewController.title(of: room)). It is kept as a scanned value until you check it with a laser.")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        TextField("For example, wardrobe wall", text: $measurementName)
            .focused($isNameFocused)
            .submitLabel(.done)
            .textInputAutocapitalization(.sentences)
            .foregroundStyle(Palette.ink)
            .padding(Spacing.m)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Palette.ink.opacity(0.08))
            }
            .onSubmit { saveMeasurement() }
        actionRow {
            Button("Save") { saveMeasurement() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Cancel") { controller.cancelNaming() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func saveMeasurement() {
        controller.commitMeasurement(named: measurementName)
        measurementName = ""
    }
}

// MARK: - Pieces

/// Widest the bottom bars and cards grow. On a phone they fill the width; on an iPad or a phone held
/// sideways they stay a comfortable size and sit in the middle instead of spanning the screen.
private let arPanelMaxWidth: CGFloat = 560

private extension View {
    /// Fills the available width up to `arPanelMaxWidth`, centred in what is left.
    func arPanelWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment).frame(maxWidth: arPanelMaxWidth)
    }
}

/// The centre of the screen while measuring. It reads `controller.reticle` itself, so the reticle changing
/// (up to a few times a second) redraws only this view, not the whole AR screen.
private struct ARReticleLayer: View {
    let controller: ARReviewController

    var body: some View {
        let state = controller.reticle
        ZStack {
            ARMeasureReticle(state: state)
            if case .snapped(let name) = state, !name.isEmpty {
                Pill(name, systemImage: "scope", tint: Palette.accent)
                    .offset(y: 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// The centre reticle for measuring: a ring that fills with the accent when it snaps to a corner.
private struct ARMeasureReticle: View {
    let state: ARReviewController.Reticle

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ring, lineWidth: 2)
                .frame(width: 30, height: 30)
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
        }
        .scaleEffect(isSnapped ? 1.25 : 1)
        .shadow(color: Color.black.opacity(0.45), radius: 2)
        .motion(Motion.quick, value: state)
        .accessibilityHidden(true)
    }

    private var isSnapped: Bool {
        if case .snapped = state { return true }
        return false
    }

    private var ring: Color {
        switch state {
        case .noSurface: return Color.white.opacity(0.45)
        case .surface: return Color.white
        case .snapped: return Palette.accent
        }
    }

    private var dot: Color {
        switch state {
        case .noSurface: return Color.white.opacity(0.45)
        case .surface: return Color.white
        case .snapped: return Palette.accent
        }
    }
}

/// One of the Dimensions / Angles / Openings switches in the bottom bar. Selection is shown by a filled tile
/// and a stronger label, not by colour alone.
private struct AROverlayToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(verbatim: title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Palette.ink.opacity(isOn ? 1 : 0.7))
            .frame(minWidth: 52, maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Palette.ink.opacity(isOn ? 0.16 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The accent capsule for the one thing to do next in a bar: Measure, then Add point.
private struct ARAccentActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accentContrast)
                // Never squeezed by the toggles beside it (same fix as the 3D viewer's bar).
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 44)
                .background { Capsule(style: .continuous).fill(Palette.accent) }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A quiet text button for the bar ("Done", "Clear"): 44 pt tall, ink text, dims while pressed.
private struct ARBarTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.m)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
    }
}

private struct ARRoomChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            chip
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var chip: some View {
        let label = Text(verbatim: name)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? Palette.accentContrast : Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 44)
            .contentShape(Capsule(style: .continuous))
        if isSelected {
            label.background { Capsule(style: .continuous).fill(Palette.accent) }
        } else {
            label.glass(in: Capsule(style: .continuous), prominence: .thin)
        }
    }
}

/// "ΔX +1200 mm": a small caption over a monospaced number.
private struct ARAxisValue: View {
    let name: String
    let spokenName: String
    let text: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(verbatim: text)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName)
        .accessibilityValue(spoken)
    }
}

/// Full-screen explanation for permission, unsupported devices and failures. Always has a way out.
private struct ARInfoCard: View {
    let symbol: String
    let title: String
    let message: String
    let primaryTitle: String?
    let primaryAction: (() -> Void)?
    let closeAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: message)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                VStack(spacing: Spacing.s) {
                    if let primaryTitle, let primaryAction {
                        Button(primaryTitle, action: primaryAction)
                            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    }
                    Button(action: closeAction) {
                        Text("Close")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .frame(maxWidth: 360)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
        }
    }
}
