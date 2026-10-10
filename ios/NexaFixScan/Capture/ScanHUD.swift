import SwiftUI
import UIKit
import NexaFixCore

// The pieces that float over the camera on the scan screen. Each one is a thin view over values the
// controller already computed (the words come from Core's `ScanCoach`, `LiveScanStats` and `ScanMergeStep`).
// Floating controls are glass; nothing here sits on another glass surface.

// MARK: - Top: coaching and numbers

/// The line at the top: the next step ("Go all the way round, then tap Finish room") or, in red, that tracking
/// was lost. RoomPlan's capture view prints RoomPlan's own instructions, so this pill never says them again.
/// Colour is never the only signal: each level has its own symbol.
struct ScanCoachPill: View {
    let message: ScanCoachMessage

    var body: some View {
        Pill(message.text, systemImage: message.symbol, tint: tint)
            .id(message.text)
            .transition(.opacity)
    }

    private var tint: Color {
        switch message.level {
        case .info: return Palette.ink
        case .caution: return Palette.caution
        case .critical: return Palette.critical
        }
    }
}

/// "6 walls · 1 door · 2 windows · about 14.2 m²". Tabular figures, so the pill does not jitter as counts change.
struct ScanMetricsPill: View {
    let summary: String
    let spoken: String

    @ScaledMetric(relativeTo: .footnote) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var verticalPadding: CGFloat = 7

    var body: some View {
        Text(verbatim: summary)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .glass(in: Capsule(style: .continuous), prominence: .thin)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Bottom bar

/// The buttons for the current moment: Finish room and Cancel while scanning, Scan next room and
/// Finish property between rooms. The accent button is always the one thing to do next.
@MainActor
struct ScanBottomBar: View {
    let controller: ScanSessionController

    var body: some View {
        content
            .frame(maxWidth: 480)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.flow.state {
        case .scanning:
            buttons {
                Button("Cancel") { controller.cancelCurrentRoom() }
                    .buttonStyle(.secondaryOnGlass)
                    .accessibilityHint(controller.flow.rooms.isEmpty
                                       ? "Closes the scanner."
                                       : "Stops this room. Your finished rooms are kept.")
                    .accessibilityIdentifier("scan.cancel")
                Button(controller.isSimulated ? "Simulate a scan" : "Finish room") { controller.finishRoom() }
                    .buttonStyle(.primary)
                    .disabled(!controller.canFinishRoom)
                    .accessibilityHint(controller.canFinishRoom ? "" : "Scan at least three walls first.")
                    .accessibilityIdentifier(controller.isSimulated ? "scan.simulate" : "scan.finishRoom")
            }

        case .processingRoom:
            BusyPill(text: "Building the room")

        case .betweenRooms:
            buttons {
                if controller.canContinueScanning {
                    Button("Finish property") { controller.finishProperty() }
                        .buttonStyle(.secondaryOnGlass)
                    Button("Scan next room") { controller.scanNextRoom() }
                        .buttonStyle(.primary)
                } else {
                    Button("Finish property") { controller.finishProperty() }
                        .buttonStyle(.primary)
                }
            }

        case .idle:
            // Before the first room starts there is nothing to offer: the scan begins by itself the moment
            // the camera view is on screen. Idle after that means a first room failed and can be tried again.
            if controller.hasStarted {
                buttons {
                    Button("Close") { controller.leave() }
                        .buttonStyle(.secondaryOnGlass)
                    if controller.canContinueScanning {
                        Button("Start scanning") { controller.scanAgain() }
                            .buttonStyle(.primary)
                    }
                }
            }

        case .awaitingName, .merging, .finished, .failed:
            EmptyView()
        }
    }

    /// Side by side, or stacked when the text is too big to fit.
    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let built = content()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.m) { built }
            VStack(spacing: Spacing.s) { built }
        }
    }
}

/// A glass pill with a spinner and words, for work that takes a moment.
struct BusyPill: View {
    let text: String

    @ScaledMetric(relativeTo: .footnote) private var horizontalPadding: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var verticalPadding: CGFloat = 12

    var body: some View {
        HStack(spacing: Spacing.s) {
            ProgressView()
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .glass(in: Capsule(style: .continuous), prominence: .regular)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Cards over the camera

/// Tracking has been gone for a while. Says what to do and offers a way out that keeps the finished rooms.
struct ScanTrackingHelpCard: View {
    let roomCount: Int
    let onFinishWithRooms: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "location.viewfinder")
                    .foregroundStyle(Palette.critical)
                    .accessibilityHidden(true)
                Text(verbatim: "Tracking hasn\u{2019}t come back")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(verbatim: detail)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: onFinishWithRooms)
                .buttonStyle(.secondaryOnGlass)
        }
        .padding(Spacing.l)
        .frame(maxWidth: 480, alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        roomCount == 0
            ? "Go back to where you started and look at the walls you scanned. If that doesn\u{2019}t help, stop and start again."
            : "Go back to the room you just scanned and look at its walls. If that doesn\u{2019}t help, you can finish with the rooms you have."
    }

    private var buttonTitle: String {
        switch roomCount {
        case 0: return "Stop scanning"
        case 1: return "Finish with 1 room"
        default: return "Finish with \(roomCount) rooms"
        }
    }
}

/// Shown when joining the rooms failed outright. The rooms are kept, so the person can try again.
struct ScanMergeFailedCard: View {
    let message: String
    let roomCount: Int
    let canScanMore: Bool
    let onTryAgain: () -> Void
    let onScanMore: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.caution)
                    .accessibilityHidden(true)
                Text(verbatim: "Couldn\u{2019}t finish the property")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
            }
            // Small text on glass: full-strength ink, semibold (DESIGN.md), never grey.
            Text(verbatim: message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: roomCount == 1 ? "Your room is kept." : "Your \(roomCount) rooms are kept.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
            VStack(spacing: Spacing.s) {
                Button("Try again", action: onTryAgain)
                    .buttonStyle(.primaryFullWidth)
                if canScanMore {
                    Button("Scan another room", action: onScanMore)
                        .buttonStyle(.secondaryFullWidth)
                }
                // The frame and the hit shape sit inside the label: a frame outside the Button would leave
                // only the words themselves tappable.
                Button(role: .destructive, action: onClose) {
                    Text(verbatim: "Close without saving")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.critical)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: 480, alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .thick)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Merging

/// Full-screen while the rooms are joined, the 3D file is written and the AR map is saved. Says what is
/// happening and how far along it is instead of showing a bare spinner.
struct ScanMergeCard: View {
    let step: ScanMergeStep
    let roomCount: Int

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.xl) {
                AppMark(size: 72)

                VStack(spacing: Spacing.s) {
                    Text(verbatim: ScanMergeStep.headline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: roomCount == 1 ? "1 room" : "\(roomCount) rooms")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                ProgressRing(fraction: ringFraction, lineWidth: 5, tint: Palette.accent)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(ScanMergeStep.allCases, id: \.self) { item in
                        row(item)
                    }
                }

                Text(verbatim: "Keep the app open. This takes a moment.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)
            .padding(Spacing.xl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ScanMergeStep.headline). \(step.title). \(step.position).")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Half-way through the current step, so the ring is never empty and never full while work is running.
    private var ringFraction: Double {
        (Double(step.rawValue) + 0.5) / Double(ScanMergeStep.allCases.count)
    }

    private func row(_ item: ScanMergeStep) -> some View {
        let isDone = item.rawValue < step.rawValue
        let isCurrent = item == step
        return HStack(spacing: Spacing.s) {
            // A finished step is plain ink, not the green of laser-verified values: joining rooms verifies nothing.
            Image(systemName: isDone ? "checkmark.circle" : (isCurrent ? "circle.dotted" : "circle"))
                .foregroundStyle(isDone ? Palette.ink : (isCurrent ? Palette.accent : Palette.muted))
                .accessibilityHidden(true)
            Text(verbatim: item.title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent || isDone ? Palette.ink : Palette.muted)
        }
    }
}

// MARK: - Simulator

/// Stands in for the camera in the Simulator, which has no LiDAR. The bottom bar's primary button makes
/// a practice room.
struct SimulatorScanStage: View {
    let roomIndex: Int

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                AppMark(size: 72)
                Text(verbatim: "Practice scan")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: "The Simulator has no LiDAR sensor, so NexaFix Scan makes a practice room instead. Practice room \(roomIndex + 1).")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
            .padding(Spacing.xl)
        }
    }
}
