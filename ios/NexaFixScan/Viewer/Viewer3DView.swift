import SwiftUI
import Accessibility
import NexaFixCore

/// Look around a scanned level in 3D, and take new measurements from it months later.
///
/// Drag to turn the model, pinch to zoom, drag with two fingers to slide, double-tap to show the whole floor.
/// Walls have real door and window openings. **Measure** lets you tap two points (they snap to corners and
/// edges); the glass card shows the length, the change along each axis and the horizontal run, and **Save**, in
/// the bar below it, names the measurement and keeps it on the room the points are in.
///
/// A tape measurement is read off the scanned model, so it is shown and saved as a scanned number with its
/// typical tolerance, never as a checked one.
struct Viewer3DView: View {
    private let model: Floor
    private let units: DisplayUnits
    private let hapticsEnabled: Bool

    @State private var controller: Viewer3DController
    @State private var measurementName = ""
    /// Height of the picture, for keeping the readout card to a fraction of it.
    @State private var viewHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// - Parameters:
    ///   - floor: The level to show. Its rooms share one coordinate frame.
    ///   - units: How lengths are written.
    ///   - hapticsEnabled: The Settings switch.
    ///   - focusRoomID: The room to frame first, and the room a measurement is kept in when it is not inside any.
    ///   - onSaveMeasurement: Called with a named tape measurement and the room that holds it.
    ///   - onClose: The person left the screen.
    init(floor: Floor, units: DisplayUnits, hapticsEnabled: Bool, focusRoomID: UUID?,
         onSaveMeasurement: @escaping (CustomMeasurement, UUID) -> Void, onClose: @escaping () -> Void) {
        self.model = floor
        self.units = units
        self.hapticsEnabled = hapticsEnabled
        let controller = Viewer3DController(
            floor: floor, units: units, hapticsEnabled: hapticsEnabled, focusRoomID: focusRoomID,
            onSaveMeasurement: onSaveMeasurement, onClose: onClose)
        controller.announce = { text in AccessibilityNotification.Announcement(text).post() }
        _controller = State(initialValue: controller)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            sizeReader
            ModelView(controller: controller, state: renderState)
                .ignoresSafeArea()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("3D model of \(model.name)")
                .accessibilityHint("Use the actions to turn, zoom or show the whole floor.")
                .accessibilityAction(named: "Turn left") { controller.turn(byDegrees: -30) }
                .accessibilityAction(named: "Turn right") { controller.turn(byDegrees: 30) }
                .accessibilityAction(named: "Zoom in") { controller.zoom(byStep: 1.4) }
                .accessibilityAction(named: "Zoom out") { controller.zoom(byStep: 1 / 1.4) }
                .accessibilityAction(named: "Show whole floor") { controller.showWholeFloor() }
            ViewerLabelLayer(controller: controller)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            chrome
        }
        .onAppear {
            controller.hapticsEnabled = hapticsEnabled
            controller.prepare()
        }
        .onChange(of: model) { _, new in controller.update(floor: new) }
        .onChange(of: units) { _, new in controller.update(units: new) }
        .onChange(of: hapticsEnabled) { _, new in controller.hapticsEnabled = new }
        .onChange(of: reduceMotion, initial: true) { _, new in controller.reduceMotion = new }
        .sensoryFeedback(.selection, trigger: toggles) { _, _ in hapticsEnabled }
        // The alert is attached here, outside every glass surface, so its own buttons draw normally.
        .alert("Name this measurement", isPresented: namingBinding) {
            TextField(controller.defaultMeasurementName, text: $measurementName)
            Button("Save") {
                controller.commitMeasurement(named: measurementName)
                measurementName = ""
            }
            Button("Cancel", role: .cancel) {
                controller.cancelNaming()
                measurementName = ""
            }
        } message: {
            Text(verbatim: "It is kept in \(controller.targetRoomName) as a scanned value until you check it with a laser.")
        }
    }

    // MARK: State for the renderer and the haptics

    private var renderState: ModelRenderState {
        ModelRenderState(sceneVersion: controller.sceneVersion, seeThroughWalls: controller.wallStyle == .seeThrough,
                         showsCeiling: controller.showsCeiling, isMeasuring: controller.isMeasuring,
                         isDark: colorScheme == .dark)
    }

    private struct Toggles: Equatable {
        var ceiling: Bool
        var seeThrough: Bool
        var labels: Bool
    }

    private var toggles: Toggles {
        Toggles(ceiling: controller.showsCeiling, seeThrough: controller.wallStyle == .seeThrough,
                labels: controller.showsLabels)
    }

    private var namingBinding: Binding<Bool> {
        Binding(get: { controller.isNaming }, set: { if !$0 { controller.cancelNaming() } })
    }

    /// Tells the controller how big the picture is, edge to edge.
    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    viewHeight = proxy.size.height
                    controller.viewSizeChanged(proxy.size)
                }
                .onChange(of: proxy.size) { _, new in
                    viewHeight = new.height
                    controller.viewSizeChanged(new)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: Spacing.m) {
            topBar
            Spacer(minLength: 0)
            bottomStack
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
    }

    /// Close, the model's name and "show whole floor". At accessibility text sizes the buttons grow past 100 pt
    /// each, so the name drops to its own row instead of being squeezed into what is left.
    @ViewBuilder
    private var topBar: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    closeButton
                    Spacer(minLength: 0)
                    wholeFloorButton
                }
                titlePill
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.s) {
                closeButton
                titlePill
                Spacer(minLength: 0)
                wholeFloorButton
            }
        }
    }

    private var closeButton: some View {
        GlassIconButton(systemImage: "xmark", label: "Close 3D view") { controller.close() }
    }

    private var wholeFloorButton: some View {
        GlassIconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Show whole floor") {
            controller.showWholeFloor()
        }
    }

    private var titlePill: some View {
        Pill(model.name.isEmpty ? "3D model" : model.name, systemImage: "cube")
    }

    /// The values whose changes animate (cards and pills appearing and going).
    private struct UIState: Equatable {
        var measuring: Bool
        var complete: Bool
        var hint: Bool
        var notice: Bool
        var problem: Bool
    }

    private var uiState: UIState {
        UIState(measuring: controller.isMeasuring, complete: controller.tape.isComplete,
                hint: controller.hint != nil, notice: controller.notice != nil, problem: controller.drawProblem != nil)
    }

    private var bottomStack: some View {
        VStack(spacing: Spacing.s) {
            if let notice = controller.notice {
                Pill(notice, systemImage: "info.circle")
                    .transition(.fadeScale)
            } else if let problem = controller.drawProblem {
                Pill(problem == .whole ? "The model could not be drawn. Close the 3D view and open it again."
                                       : "Part of the model could not be drawn.",
                     systemImage: "exclamationmark.triangle", tint: Palette.caution)
                    .transition(.fadeScale)
            } else if let hint = controller.hint {
                Pill(hint, systemImage: "scope", tint: Palette.accent)
                    .transition(.fadeScale)
            } else if controller.hasNoModel {
                Pill("There is no model to show for this level.", systemImage: "info.circle")
                    .transition(.fadeScale)
            }

            if controller.isMeasuring, controller.tape.isComplete {
                readoutCard
                    .transition(.sheetRise)
            }

            if controller.isMeasuring {
                measureBar
            } else {
                reviewBar
            }
        }
        .motion(value: uiState)
    }

    private var reviewBar: some View {
        barLayout {
            ViewerToggle(title: "Ceiling", systemImage: "arrow.up.to.line", isOn: controller.showsCeiling) {
                controller.toggleCeiling()
            }
            wallsToggle
            ViewerToggle(title: "Labels", systemImage: "tag", isOn: controller.showsLabels) {
                controller.toggleLabels()
            }
            ViewerAccentButton(title: "Measure", systemImage: "ruler") { controller.setMeasuring(true) }
        }
        .padding(Spacing.s)
        .viewerPanelWidth()
        .glass(cornerRadius: Radius.card, prominence: .regular)
    }

    private var measureBar: some View {
        barLayout {
            Button("Done") { controller.setMeasuring(false) }
                .buttonStyle(ViewerTextButtonStyle())
            wallsToggle
            Button("Clear") { controller.clearMeasurement() }
                .buttonStyle(ViewerTextButtonStyle())
                .disabled(controller.tape.isEmpty)
            // The one thing to do next, once both points are placed.
            if controller.tape.isComplete {
                ViewerAccentButton(title: "Save", systemImage: "square.and.arrow.down") { controller.beginNaming() }
                    .disabled(!controller.canSave)
            }
        }
        .padding(Spacing.s)
        .viewerPanelWidth()
        .glass(cornerRadius: Radius.card, prominence: .regular)
    }

    private var wallsToggle: some View {
        ViewerToggle(title: "See-through", systemImage: "cube.transparent",
                     isOn: controller.wallStyle == .seeThrough, accessibilityName: "See-through walls") {
            controller.toggleWallStyle()
        }
    }

    /// A row of controls that stacks vertically at accessibility text sizes.
    private func barLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))
        return layout { content() }
    }

    // MARK: Readout

    /// The measurement in numbers. Never taller than 45 % of the picture (and never below 140 pt): what does not
    /// fit scrolls, so the card cannot cover the model it is measuring, in landscape or at large text sizes.
    private var readoutCard: some View {
        let cap = Swift.max(140, viewHeight * 0.45)
        return ViewThatFits(in: .vertical) {
            readoutContent
            ScrollView { readoutContent }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: cap)
        .padding(Spacing.l)
        .viewerPanelWidth(alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .accessibilityElement(children: .contain)
    }

    private var readoutContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let reading = controller.reading, let readout = controller.readout {
                // A landscape phone is short: the length steps down from hero to title.
                MeasurementText(length: TapeMeasure.quantise(reading.lengthM), units: units,
                                style: verticalSizeClass == .compact ? .title : .hero)

                // A tape reading comes from the scan: always the scanned badge, with its typical tolerance.
                ProvenanceBadge(Measured(scanned: reading.lengthM), units: units)

                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                    : AnyLayout(HStackLayout(spacing: Spacing.l))
                layout {
                    ViewerAxisValue(name: "\u{0394}X", spokenName: "Delta X", text: readout.deltaX,
                                    spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaX), unit: units.length))
                    ViewerAxisValue(name: "\u{0394}Y", spokenName: "Delta Y, up", text: readout.deltaY,
                                    spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaY), unit: units.length))
                    ViewerAxisValue(name: "\u{0394}Z", spokenName: "Delta Z", text: readout.deltaZ,
                                    spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.deltaZ), unit: units.length))
                    ViewerAxisValue(name: "Run", spokenName: "Horizontal run", text: readout.horizontal,
                                    spoken: SpokenMeasurement.length(TapeMeasure.quantise(reading.horizontalM), unit: units.length))
                }

                if let summary = controller.snapSummary {
                    Text(verbatim: summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }

                Text(verbatim: "Read from the scan. Check it with a laser before anything is cut to it.")
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

/// Widest the bottom bars and cards grow. On a phone they fill the width; on an iPad or a phone held sideways
/// they stay a comfortable size and sit in the middle.
private let viewerPanelMaxWidth: CGFloat = 560

private extension View {
    func viewerPanelWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment).frame(maxWidth: viewerPanelMaxWidth)
    }
}

/// One of the switches in the bottom bar. On is shown by a filled tile and a stronger label, and spoken as
/// "On" or "Off", not by colour alone.
private struct ViewerToggle: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var accessibilityName: String?
    let action: () -> Void

    init(title: String, systemImage: String, isOn: Bool, accessibilityName: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.accessibilityName = accessibilityName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel(accessibilityName ?? title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The accent capsule for the one thing to do next: Measure, then Save. `PressableButtonStyle` dims it while
/// pressed and while disabled; dimming it here as well would draw a disabled button at 0.4 x 0.4 = 16 %.
private struct ViewerAccentButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accentContrast)
                .padding(.horizontal, Spacing.l)
                .frame(minHeight: 44)
                .background { Capsule(style: .continuous).fill(Palette.accent) }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A quiet text button for the bar ("Done", "Clear"): 44 pt tall, ink text, dims while pressed.
private struct ViewerTextButtonStyle: ButtonStyle {
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

/// "\u{0394}X +1200 mm": a small caption over a monospaced number.
private struct ViewerAxisValue: View {
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

// MARK: - Labels, tape lines and markers

/// What the label layer remembers between frames: the hysteresis that stops labels flickering. A reference
/// type held in `@State`: changing it never redraws anything.
private final class LabelScratch {
    var hysteresis = LabelHysteresis(requiredFrames: 3)
}

/// Draws, over the 3D picture, the dimension labels of the floor, the saved tape lines and the tape being
/// measured. It redraws whenever the camera moves or a switch changes (`drawRevision`). Labels hidden behind a wall are left
/// out while walls are solid, and `LabelLayout` decides which of the rest fit.
private struct ViewerLabelLayer: View {
    let controller: Viewer3DController

    @State private var scratch = LabelScratch()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Reading this is what makes the layer redraw when the camera moves or a switch changes what is visible.
        let revision = controller.drawRevision
        let labels = controller.allLabels
        let spokenLabels: [OverlayLabel] = controller.showsLabels ? labels.sorted(by: { $0.priority > $1.priority }) : []
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            _ = revision
            draw(&context, size)
        } symbols: {
            ForEach(labels) { label in
                ViewerLabelChip(label: label, reduceTransparency: reduceTransparency,
                                increasedContrast: contrast == .increased)
                    .tag(label.id)
            }
        }
        .accessibilityLabel("Measurements")
        .accessibilityChildren {
            VStack {
                ForEach(spokenLabels) { label in
                    Text(verbatim: label.title)
                        .accessibilityLabel(label.spokenDescription)
                }
            }
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        drawTapeLines(&context)
        drawLabels(&context, size)
    }

    private func drawTapeLines(_ context: inout GraphicsContext) {
        let halo = Palette.background.opacity(0.85)
        for (a, b, isLive) in controller.measurementLines {
            guard let p = controller.screenPoint(a), let q = controller.screenPoint(b) else { continue }
            var path = Path()
            path.move(to: p)
            path.addLine(to: q)
            context.stroke(path, with: .color(halo),
                           style: SwiftUI.StrokeStyle(lineWidth: isLive ? 6 : 5, lineCap: .round))
            context.stroke(path, with: .color(Palette.accent),
                           style: SwiftUI.StrokeStyle(lineWidth: isLive ? 3 : 2, lineCap: .round))
            for end in [p, q] { drawMarker(&context, at: end, radius: isLive ? 5 : 3.5) }
        }
        // A first point with no second yet.
        let points = controller.tapePoints
        if points.count == 1, let p = controller.screenPoint(points[0]) {
            drawMarker(&context, at: p, radius: 6)
        }
    }

    /// A ring with a dot: where a tape point is.
    private func drawMarker(_ context: inout GraphicsContext, at p: CGPoint, radius: CGFloat) {
        let ring = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        context.fill(ring, with: .color(Palette.surface))
        context.stroke(ring, with: .color(Palette.accent), lineWidth: 2)
        let dot = Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
        context.fill(dot, with: .color(Palette.accent))
    }

    private func drawLabels(_ context: inout GraphicsContext, _ size: CGSize) {
        let eye = controller.camera.position
        var candidates: [LabelCandidate] = []
        for label in controller.drawableLabels() {
            guard let screen = controller.screenPoint(label.position),
                  screen.x > -120, screen.x < size.width + 120, screen.y > -80, screen.y < size.height + 80,
                  let symbol = context.resolveSymbol(id: label.id) else { continue }
            candidates.append(LabelCandidate(
                id: label.id, x: Double(screen.x), y: Double(screen.y),
                width: Double(symbol.size.width), height: Double(symbol.size.height),
                priority: label.priority, distance: eye.distance(to: label.position)))
        }
        // Labels fade with distance relative to the size of the model, not a fixed few metres.
        let diagonal = max(controller.pickScene.diagonal, 1)
        let options = LabelLayoutOptions(fullOpacityDistance: max(6, diagonal * 1.5),
                                         zeroOpacityDistance: max(18, diagonal * 4))
        let placed = LabelLayout.place(candidates, viewport: LabelViewport(width: Double(size.width), height: Double(size.height)),
                                       options: options)
        let stable = scratch.hysteresis.stabilise(placed, candidates: candidates)
        // Best label last, so it is drawn on top.
        for item in stable.reversed() {
            guard let symbol = context.resolveSymbol(id: item.id) else { continue }
            let s = symbol.size
            let rect = CGRect(x: CGFloat(item.x) - s.width / 2, y: CGFloat(item.y) - s.height / 2,
                              width: s.width, height: s.height)
            context.opacity = item.opacity
            context.draw(symbol, in: rect)
        }
        context.opacity = 1
    }
}

/// One label: the number in monospaced digits, an optional line of small print ("\u{00B1}22 mm", "Laser") and a
/// glyph for verified, caution and critical. Drawn on a surface-coloured chip; a Canvas symbol is rasterised, so
/// it cannot blur what is behind it. Reduce Transparency makes the chip opaque, Increased Contrast thickens the
/// border.
private struct ViewerLabelChip: View {
    let label: OverlayLabel
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        HStack(spacing: Spacing.xs) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(glyphColor)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: label.title)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                if let subtitle = label.subtitle {
                    // The line that tells scanned from verified: ink at full strength, never a flat grey.
                    Text(verbatim: subtitle)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background { shape.fill(reduceTransparency ? Palette.surface : Palette.surface.opacity(0.88)) }
        .overlay {
            shape.strokeBorder(Palette.line, lineWidth: increasedContrast ? Hairline.emphasized : Hairline.width)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// A symbol so colour is never the only signal.
    private var glyph: String? {
        switch label.state {
        case .verified: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .scanned, .neutral: return nil
        }
    }

    private var glyphColor: Color {
        switch label.state {
        case .verified: return Palette.verified
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        case .scanned, .neutral: return Palette.ink
        }
    }

    private var titleColor: Color {
        switch label.state {
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        default: return Palette.ink
        }
    }
}
