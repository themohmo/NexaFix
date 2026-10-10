import SwiftUI
import NexaFixCore

/// What the person sees when scanning is not available yet.
///
/// - Camera not asked for yet: a one-screen explanation first (why, and what stays on the device), and only
///   then the system prompt. The system asks once; an unexplained prompt that gets refused cannot be asked again.
/// - Camera refused: why it is needed and a button that opens Settings.
/// - Camera restricted: who can change it.
/// - No LiDAR: a calm explanation that everything else still works.
///
/// The words come from `DeviceCapability`. This view only lays them out.
struct PermissionPrimer: View {
    let capability: DeviceCapability
    /// Called with the new state after the system camera prompt has been answered.
    let onUpdate: (DeviceCapability) -> Void
    let onClose: () -> Void
    /// Simulator only: scan a practice room instead. Ignored on a device.
    var onSimulate: (() -> Void)?

    @State private var isRequesting = false

    init(capability: DeviceCapability,
         onUpdate: @escaping (DeviceCapability) -> Void,
         onClose: @escaping () -> Void,
         onSimulate: (() -> Void)? = nil) {
        self.capability = capability
        self.onUpdate = onUpdate
        self.onClose = onClose
        self.onSimulate = onSimulate
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.background.ignoresSafeArea()
            content
            GlassIconButton(systemImage: "xmark", label: "Close", action: onClose)
                .padding(Spacing.l)
        }
    }

    @MainActor @ViewBuilder
    private var content: some View {
        switch capability {
        case .notDetermined:
            primer
        case .cameraDenied:
            EmptyStateView(title: capability.title, message: capability.message,
                           primaryTitle: "Open Settings", primaryAction: { DeviceCapability.openSettings() },
                           secondaryTitle: "Not now", secondaryAction: onClose)
        case .cameraRestricted:
            EmptyStateView(title: capability.title, message: capability.message,
                           primaryTitle: "Close", primaryAction: onClose)
        case .noLiDAR:
            noLiDAR
        case .supported:
            EmptyView()
        }
    }

    // MARK: The explanation before the system prompt

    private var primer: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AppMark(size: 72)

                VStack(spacing: Spacing.s) {
                    Text(verbatim: capability.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: capability.message)
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }

                SectionCard {
                    PrimerRow(symbol: "camera.viewfinder", title: "What it measures",
                              detail: "Walls, doors, windows and furniture, as you walk slowly through each room.")
                    RowDivider()
                    PrimerRow(symbol: "lightbulb", title: "For the best result",
                              detail: DeviceCapability.sizeAndLightNote)
                    RowDivider()
                    PrimerRow(symbol: "lock", title: "Private to this iPhone",
                              detail: DeviceCapability.privacyNote)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxxl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.s) {
                Button {
                    request()
                } label: {
                    Text(verbatim: "Continue")
                }
                .buttonStyle(.primaryFullWidth)
                .disabled(isRequesting)
                .accessibilityHint("Shows the system\u{2019}s camera permission request.")

                Button(action: onClose) {
                    Text(verbatim: "Not now")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.s)
            .frame(maxWidth: .infinity)
            .background { Palette.background.ignoresSafeArea() }
        }
    }

    private func request() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            let updated = await DeviceCapability.requestCameraAccess()
            isRequesting = false
            onUpdate(updated)
        }
    }

    // MARK: No LiDAR

    @ViewBuilder
    private var noLiDAR: some View {
        #if targetEnvironment(simulator)
        EmptyStateView(title: capability.title, message: capability.message,
                       primaryTitle: "Simulate a scan", primaryAction: { onSimulate?() },
                       secondaryTitle: "Close", secondaryAction: onClose)
        #else
        EmptyStateView(title: capability.title, message: capability.message,
                       primaryTitle: "Close", primaryAction: onClose)
        #endif
    }
}

/// One line of the explanation: a symbol, a short title and a sentence.
private struct PrimerRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .combine)
    }
}
