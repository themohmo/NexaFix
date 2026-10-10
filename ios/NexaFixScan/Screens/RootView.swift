import SwiftUI
import Accessibility
import Observation
import NexaFixCore

// The app's one navigation stack, and the things that sit above it: the new-property and settings
// sheets, the full-screen scan, the banner for work that is not saved, and the error alert.
//
// Screens below ask the `AppRouter` to do things ("scan this level", "open this property") instead of
// presenting each other, so a sheet can finish dismissing before the camera comes up. Each screen adds
// `.statusBanners()` so the unsaved-work banner and the scan notice sit under its own navigation bar.
//
// When the app opens it also looks for a scan that was cut short (the app was closed between rooms) and offers
// to put its rooms back: `ScanRecoveryCoordinator` decides, `ScanRecoverySheet` shows.

// MARK: - Routes

/// Where a pushed screen goes.
enum PropertyRoute: Hashable {
    case property(UUID)
    case room(property: UUID, room: UUID)
}

/// A scan the person asked for: which property and which level.
struct ScanRequest: Identifiable, Equatable {
    let id = UUID()
    let propertyID: UUID
    let story: Int
}

/// The sheets that belong to the home screen.
enum RootSheet: String, Identifiable {
    case newProperty, settings, recovery
    var id: String { rawValue }
}

/// What the person is told after a scan was added: a sentence, and anything that went wrong.
struct ScanNotice: Identifiable, Equatable {
    let id = UUID()
    var summary: String
    var warnings: [String]
    var saved: Bool
    /// The scan is still being written. Shown with a spinner and no dismiss button.
    var inProgress = false
}

// MARK: - Router

@MainActor
@Observable
final class AppRouter {
    var path: [PropertyRoute] = []
    var sheet: RootSheet?
    var scan: ScanRequest?
    var notice: ScanNotice?

    private enum AfterSheet {
        case scan(ScanRequest)
        case open(UUID)
    }

    /// What to do once the sheet that is closing has finished closing.
    @ObservationIgnored private var afterSheet: AfterSheet?

    func showNewProperty() { sheet = .newProperty }
    func showSettings() { sheet = .settings }

    /// Pushes a property, replacing whatever was open.
    func open(_ propertyID: UUID) {
        path = [.property(propertyID)]
    }

    /// Opens the camera for one level of a property.
    func startScan(propertyID: UUID, story: Int) {
        scan = ScanRequest(propertyID: propertyID, story: story)
    }

    /// Closes the sheet on screen, then opens the camera. A cover cannot appear while a sheet is leaving.
    func scanAfterSheet(propertyID: UUID, story: Int) {
        afterSheet = .scan(ScanRequest(propertyID: propertyID, story: story))
        sheet = nil
    }

    /// Closes the sheet on screen, then opens a property.
    func openAfterSheet(_ propertyID: UUID) {
        afterSheet = .open(propertyID)
        sheet = nil
    }

    /// Called by the root when a sheet has finished dismissing.
    func sheetDidDismiss() {
        guard let action = afterSheet else { return }
        afterSheet = nil
        switch action {
        case .scan(let request):
            open(request.propertyID)
            scan = request
        case .open(let id):
            open(id)
        }
    }
}

// MARK: - Root

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var router = AppRouter()
    @State private var recovery = ScanRecoveryCoordinator()

    var body: some View {
        NavigationStack(path: $router.path) {
            PropertiesListView()
                .navigationDestination(for: PropertyRoute.self) { route in
                    switch route {
                    case .property(let id):
                        PropertyView(propertyID: id)
                    case .room(let propertyID, let roomID):
                        RoomView(propertyID: propertyID, roomID: roomID)
                    }
                }
        }
        .sheet(item: $router.sheet, onDismiss: { sheetDidDismiss() }) { sheet in
            switch sheet {
            case .newProperty:
                NewPropertySheet(mode: .create)
            case .settings:
                SettingsView()
            case .recovery:
                ScanRecoverySheet(coordinator: recovery)
            }
        }
        .fullScreenCover(item: $router.scan, onDismiss: { showRecoveryIfReady() }) { request in
            scanScreen(request)
        }
        // Once per launch, after the home screen is up. The folders are read off the main thread.
        .task { await recovery.look(model: model) }
        .onChange(of: recovery.phase) { _, phase in
            if phase == .idle {
                if router.sheet == .recovery { router.sheet = nil }
            } else {
                showRecoveryIfReady()
            }
        }
        .alert(model.presentedError?.title ?? "", isPresented: errorIsPresented, presenting: model.presentedError) { error in
            if error.severity == .dataAtRisk {
                // After the alert has closed, so a second failure is not cleared by the alert closing.
                Button("Try again") { Task { @MainActor in model.retryUnsavedSaves() } }
                Button("OK", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { error in
            Text(verbatim: RootView.alertMessage(for: error))
        }
        // Outermost, after every presentation above: a sheet or cover gets the environment of the view that
        // presents it, so a value written further in (on the stack alone) would never reach them and the first
        // read of the router in a sheet would stop the app.
        .environment(router)
    }

    // MARK: Scan

    @MainActor @ViewBuilder
    private func scanScreen(_ request: ScanRequest) -> some View {
        if let property = model.property(request.propertyID) {
            ScanFlowView(
                configuration: ScanConfiguration(
                    propertyName: property.name,
                    propertyID: request.propertyID,
                    existingRoomNames: property.allRooms.map(\.name),
                    units: model.settings.units,
                    hapticsEnabled: model.settings.hapticsEnabled,
                    story: request.story),
                onFinish: { result in finishScan(result, request: request) },
                onCancel: { router.scan = nil })
        } else {
            // The property went away while the camera was opening; there is nothing to scan into.
            Color.clear.onAppear { router.scan = nil }
        }
    }

    /// The camera has handed back its rooms: write the files, save the property, show it.
    ///
    /// The cover closes at once and a "Saving" notice stands in for the result. Writing a whole level's model
    /// takes a moment, and it happens off the main thread so neither the cover nor the plan stutters.
    @MainActor
    private func finishScan(_ result: ScanResult, request: ScanRequest) {
        router.scan = nil
        router.open(request.propertyID)
        router.notice = ScanNotice(summary: "Saving the scan", warnings: [], saved: true, inProgress: true)
        Task { @MainActor in
            let outcome = await ScanIntake.commit(result, to: request.propertyID, model: model)
            if outcome.saved {
                Haptics.success()
                // The safety copy has done its job. Only now: a scan whose save failed keeps it, and the app
                // offers it again the next time it opens.
                if let scanID = result.recoveryID {
                    Task.detached(priority: .utility) { ScanRecoveryStore.discard(scanID: scanID) }
                }
            }
            router.notice = ScanNotice(summary: outcome.summary, warnings: outcome.warnings, saved: outcome.saved)
        }
    }

    // MARK: Unfinished scans

    /// A sheet has finished closing: do what it queued, then see whether an unfinished scan is waiting.
    @MainActor
    private func sheetDidDismiss() {
        router.sheetDidDismiss()
        showRecoveryIfReady()
    }

    /// Offers an unfinished scan when nothing else is on screen. Called whenever something that was in the way
    /// goes (a sheet, the camera) and when a scan is found.
    @MainActor
    private func showRecoveryIfReady() {
        guard recovery.phase != .idle, router.sheet == nil, router.scan == nil else { return }
        router.sheet = .recovery
    }

    // MARK: Errors

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { model.presentedError != nil },
                set: { shown in if !shown { model.presentedError = nil } })
    }

    /// What happened, then what to do.
    static func alertMessage(for error: UserFacingError) -> String {
        guard let recovery = error.recovery, !recovery.isEmpty else { return error.message }
        return error.message + "\n\n" + recovery
    }
}

// MARK: - Status banners

/// The persistent bar for work that is only in memory, and the one-line result of the last scan.
/// Add it to the root view of every screen in the stack: `.statusBanners()`.
private struct StatusBanners: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) { banners }
    }

    @MainActor @ViewBuilder
    private var banners: some View {
        VStack(spacing: Spacing.s) {
            if !model.unsavedPropertyIDs.isEmpty {
                UnsavedBanner(count: model.unsavedPropertyIDs.count) { model.retryUnsavedSaves() }
                    .transition(.sheetRise)
            }
            if let notice = router.notice {
                ScanNoticeBanner(notice: notice) { router.notice = nil }
                    .transition(.sheetRise)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, model.unsavedPropertyIDs.isEmpty && router.notice == nil ? 0 : Spacing.s)
        .motion(value: model.unsavedPropertyIDs.isEmpty)
        .motion(value: router.notice?.id)
    }
}

extension View {
    /// Shows the unsaved-work bar and the scan notice under this screen's navigation bar.
    func statusBanners() -> some View {
        modifier(StatusBanners())
    }
}

// MARK: - Banners

/// A persistent bar while work exists only in memory. Not dismissible: it goes when the save works.
private struct UnsavedBanner: View {
    let count: Int
    let retry: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        layout {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.critical)
                    .accessibilityHidden(true)
                Text(verbatim: count == 1
                     ? "Your latest changes are not saved. Keep the app open."
                     : "\(count) properties have changes that are not saved. Keep the app open.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: retry) {
                Text(verbatim: "Try again")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 44)
                    .background { Capsule(style: .continuous).strokeBorder(Palette.critical, lineWidth: Hairline.emphasized) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
        .accessibilityElement(children: .contain)
    }
}

/// "Restored from an earlier save": shown at the top of a property until the person says they have read it. The
/// store only reports a restore while it is happening; once the person edits the property it looks healthy,
/// but the changes made just before the damage are still gone, so the notice has to outlast the next save.
struct RecoveryBanner: View {
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.caution)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: RecoveryWording.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: RecoveryWording.message)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: dismiss) {
                Text(verbatim: RecoveryWording.dismiss)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 44)
                    .background { Capsule(style: .continuous).strokeBorder(Palette.caution, lineWidth: Hairline.emphasized) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
        .accessibilityElement(children: .contain)
    }
}

/// "Added 5 rooms to Level 23." plus anything that went wrong. Clears itself after a few seconds when
/// everything went well; warnings stay until dismissed.
private struct ScanNoticeBanner: View {
    let notice: ScanNotice
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                if notice.inProgress {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: notice.saved ? "cube.transparent" : "exclamationmark.triangle.fill")
                        .foregroundStyle(notice.saved ? Palette.accent : Palette.caution)
                        .accessibilityHidden(true)
                }
                Text(verbatim: notice.summary)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !notice.inProgress {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Dismiss")
                }
            }
            ForEach(Array(notice.warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.caution)
                        .accessibilityHidden(true)
                    Text(verbatim: warning)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
        .accessibilityElement(children: .contain)
        .task(id: notice.id) {
            // A clean result goes away by itself; a warning waits to be read.
            guard notice.warnings.isEmpty, notice.saved, !notice.inProgress else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { dismiss() }
        }
    }
}

// MARK: - Unfinished scan

/// The sheet that offers the rooms of a scan the app lost, and shows what putting them back did. It only reads the
/// coordinator and calls its actions; the coordinator decides what happens and when the copy may go.
@MainActor
private struct ScanRecoverySheet: View {
    let coordinator: ScanRecoveryCoordinator
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isConfirmingDiscard = false

    /// The three buttons sit under the text in a bar that does not scroll. At the medium height and an
    /// accessibility text size they would leave almost no room for the text, so the sheet opens full height.
    private var detents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.l)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle(ScanRecoveryPrompt.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .motion(value: coordinator.phase)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        // Rebuilding the rooms and saving them cannot be taken back; closing the sheet then would hide how it went.
        .interactiveDismissDisabled(coordinator.isWorking)
        // Swiping the sheet away is the same as Not now: the copy stays.
        .onDisappear { coordinator.sheetClosed() }
        .onChange(of: coordinator.phase) { _, phase in react(to: phase) }
        .confirmationDialog("Discard this scan?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button(offered?.discardConfirmationButton ?? ScanRecoveryPrompt.discardTitle, role: .destructive) {
                Task { @MainActor in await coordinator.discard() }
            }
            Button(ScanRecoveryPrompt.keepTitle, role: .cancel) {}
        } message: {
            Text(verbatim: offered?.discardConfirmationMessage ?? "")
        }
    }

    /// The scan the person is being asked about.
    private var offered: ScanRecoveryPrompt? {
        switch coordinator.phase {
        case .asking(let prompt), .failed(let prompt, _): return prompt
        case .idle, .working, .done: return nil
        }
    }

    // MARK: Content

    @MainActor @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            EmptyView()
        case .asking(let prompt):
            offer(prompt, failure: nil)
        case .failed(let prompt, let failure):
            offer(prompt, failure: failure)
        case .working:
            working
        case .done(_, let report):
            result(report)
        }
    }

    private func offer(_ prompt: ScanRecoveryPrompt, failure: ScanRecoveryCoordinator.Failure?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(verbatim: prompt.headline())
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let failure {
                RecoveryFailureCard(failure: failure)
            }
            Text(verbatim: prompt.explanation)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                RecoveryNote(systemImage: "info.circle", text: ScanRecoveryPrompt.limits)
                RecoveryNote(systemImage: "info.circle", text: ScanRecoveryPrompt.keptNote)
            }
        }
    }

    private var working: some View {
        VStack(spacing: Spacing.m) {
            ProgressView()
                .accessibilityHidden(true)
            Text(verbatim: ScanRecoveryPrompt.workingTitle)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(verbatim: ScanRecoveryPrompt.workingDetail)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
        .accessibilityElement(children: .combine)
    }

    private func result(_ report: ScanRecoveryCoordinator.Report) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                // Not a green check: that look belongs to values somebody checked with a laser.
                Image(systemName: "cube.transparent")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(verbatim: report.summary)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                RecoveryNote(systemImage: "exclamationmark.triangle.fill", tint: Palette.caution, isWarning: true,
                             text: warning)
            }
        }
    }

    // MARK: Buttons

    @MainActor @ViewBuilder
    private var actions: some View {
        switch coordinator.phase {
        case .idle, .working:
            EmptyView()
        case .asking:
            choices(primary: ScanRecoveryPrompt.recoverTitle)
        case .failed:
            choices(primary: ScanRecoveryPrompt.retryTitle)
        case .done:
            doneActions
        }
    }

    private func choices(primary: String) -> some View {
        VStack(spacing: Spacing.s) {
            Button {
                Task { @MainActor in await coordinator.recover(model: model) }
            } label: {
                Text(verbatim: primary)
            }
            .buttonStyle(.primaryFullWidth)
            .accessibilityHint("Adds the saved rooms to the property.")

            Button { isConfirmingDiscard = true } label: {
                Text(verbatim: ScanRecoveryPrompt.discardTitle)
                    .foregroundStyle(Palette.critical)
            }
            .buttonStyle(.secondaryFullWidth)
            .accessibilityHint("Asks first, then deletes the saved rooms from this iPhone.")

            Button { coordinator.notNow() } label: {
                Text(verbatim: ScanRecoveryPrompt.notNowTitle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Keeps the saved rooms. The app asks again next time it opens.")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .background { Palette.background.opacity(0.94).ignoresSafeArea() }
    }

    private var doneActions: some View {
        let nothingElseWaiting = coordinator.waiting.isEmpty
        return VStack(spacing: Spacing.s) {
            Button {
                let property = coordinator.acknowledge()
                if let property { router.openAfterSheet(property) }
            } label: {
                Text(verbatim: nothingElseWaiting ? "Open property" : "Next unfinished scan")
            }
            .buttonStyle(.primaryFullWidth)

            if nothingElseWaiting {
                Button { coordinator.acknowledge() } label: {
                    Text(verbatim: "Close")
                }
                .buttonStyle(.secondaryFullWidth)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .background { Palette.background.opacity(0.94).ignoresSafeArea() }
    }

    // MARK: Feedback

    /// Says aloud, and feels, what the buttons just did: the new text may be off screen for VoiceOver.
    private func react(to phase: ScanRecoveryCoordinator.Phase) {
        switch phase {
        case .working:
            AccessibilityNotification.Announcement(ScanRecoveryPrompt.workingTitle).post()
        case .done(_, let report):
            Haptics.success()
            AccessibilityNotification.Announcement(([report.summary] + report.warnings).joined(separator: " ")).post()
        case .failed(_, let failure):
            Haptics.warning()
            AccessibilityNotification.Announcement(failure.message + " " + failure.recovery).post()
        case .idle, .asking:
            break
        }
    }
}

/// A glyph and a sentence under the main text of the recovery sheet.
private struct RecoveryNote: View {
    let systemImage: String
    var tint: Color = Palette.muted
    /// A warning is read at full strength; an explanation is quieter.
    var isWarning = false
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(isWarning ? Palette.ink : Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// What went wrong while putting the rooms back, and what to do. The copy of the scan is still there.
private struct RecoveryFailureCard: View {
    let failure: ScanRecoveryCoordinator.Failure

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.critical)
                    .accessibilityHidden(true)
                Text(verbatim: failure.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: failure.recovery)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Spacing.xl)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.critical, lineWidth: Hairline.emphasized) }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Home with the demo apartment") {
    RootView().environment(AppModel.preview())
}

#Preview("Home, nothing yet") {
    RootView().environment(AppModel.preview(withDemo: false))
}
#endif
