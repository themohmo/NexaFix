import SwiftUI
import Observation
import NexaFixCore

// The app's one navigation stack, and the things that sit above it: the new-property and settings
// sheets, the full-screen scan, the banner for work that is not saved, and the error alert.
//
// Screens below ask the `AppRouter` to do things ("scan this level", "open this property") instead of
// presenting each other, so a sheet can finish dismissing before the camera comes up. Each screen adds
// `.statusBanners()` so the unsaved-work banner and the scan notice sit under its own navigation bar.

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
    case newProperty, settings
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
        .sheet(item: $router.sheet, onDismiss: { router.sheetDidDismiss() }) { sheet in
            switch sheet {
            case .newProperty:
                NewPropertySheet(mode: .create)
            case .settings:
                SettingsView()
            }
        }
        .fullScreenCover(item: $router.scan) { request in
            scanScreen(request)
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
            if outcome.saved { Haptics.success() }
            router.notice = ScanNotice(summary: outcome.summary, warnings: outcome.warnings, saved: outcome.saved)
        }
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

#if DEBUG
#Preview("Home with the demo apartment") {
    RootView().environment(AppModel.preview())
}

#Preview("Home, nothing yet") {
    RootView().environment(AppModel.preview(withDemo: false))
}
#endif
