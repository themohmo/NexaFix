import SwiftUI
import UIKit
import NexaFixCore

/// Check one dimension against a laser, a tape or a drawing.
///
/// The scanned value sits on top, muted. Below it a big numeric field takes what the person read off the
/// meter, in any unit the parser understands ("3245", "3.245 m", `10' 7 3/4"`). The sheet says at once how far
/// the scan was, warns calmly about a number that looks like a typo, and never saves in silence. All the
/// rules live in `VerifyModel`; this view only draws it and hands the check to `PropertyActions`.
@MainActor
struct VerifySheet: View {
    private let propertyID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: VerifyModel
    @State private var problem: String?
    @FocusState private var fieldFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var fieldSize: CGFloat = 40

    /// - Parameters:
    ///   - propertyID: The property the room belongs to, so the check is saved into it.
    ///   - room: The room as it is now.
    ///   - target: The dimension to check.
    ///   - units: The person's units; the field starts in the length unit.
    init(propertyID: UUID, room: Room, target: MeasureTarget, units: DisplayUnits) {
        self.propertyID = propertyID
        _model = State(initialValue: VerifyModel(room: room, target: target, units: units))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header
                    scannedBlock
                    fieldBlock
                    feedbackBlock
                    sourceBlock
                    noteBlock
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // Save and Clear stay in view with the number pad up; in the medium detent they would otherwise
            // sit below the source and the note, out of sight until the keyboard is put away.
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .screenBackground()
            .navigationTitle("Check dimension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        model.cycleUnit()
                    } label: {
                        Text(verbatim: "Unit: \(VerifySheet.shortName(model.inputUnit))")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Change unit")
                    .accessibilityValue(model.inputUnit.displayName)
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { @MainActor in
            // After the sheet has finished rising, so the keyboard does not fight the animation.
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled { fieldFocused = true }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: model.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: model.roomName)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder
    private var scannedBlock: some View {
        if let scanned = model.scannedValue {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: "Scanned")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(verbatim: model.scannedText)
                        .font(.title2.weight(.regular))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                    Text(verbatim: model.toleranceText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scanned value")
            .accessibilityValue(SpokenMeasurement.length(scanned, unit: model.inputUnit) + ", "
                + SpokenMeasurement.tolerance(forLength: scanned, unit: model.inputUnit))
        } else {
            Text(verbatim: "This dimension is no longer in the room.")
                .font(.body)
                .foregroundStyle(Palette.caution)
        }
    }

    private var fieldBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: "Measured")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
            HStack(alignment: .center, spacing: Spacing.m) {
                TextField(model.placeholder, text: $model.text)
                    .font(.system(size: fieldSize, weight: .light))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Palette.ink)
                    .keyboardType(model.inputUnit == .feetAndInches ? .numbersAndPunctuation : .decimalPad)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .accessibilityLabel("Measured value")
                    .accessibilityHint("Type what the meter shows. The unit is \(model.inputUnit.displayName).")
                unitButton
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .frame(minHeight: 44)
            .background { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.surface) }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(fieldFocused ? Palette.accent : Palette.line, lineWidth: fieldFocused ? 1.5 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }
        }
    }

    /// The unit beside the number, always visible, so it can be changed after the keyboard is put away. Tapping
    /// it cycles through mm, cm, m, in, ft in.
    private var unitButton: some View {
        Button {
            model.cycleUnit()
        } label: {
            Text(verbatim: VerifySheet.shortName(model.inputUnit))
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, Spacing.m)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Change unit")
        .accessibilityValue(model.inputUnit.displayName)
    }

    @ViewBuilder
    private var feedbackBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch model.check {
            case .empty:
                EmptyView()
            case .unreadable(let text):
                FeedbackLine(systemImage: "info.circle", text: text, tint: Palette.muted)
            case .farFromScan(let text):
                FeedbackLine(systemImage: "exclamationmark.triangle.fill", text: text, tint: Palette.caution)
            case .ok:
                EmptyView()
            }
            if let deviation = model.deviationText, !isFarFromScan {
                FeedbackLine(systemImage: deviation == "Matches the scan" ? "checkmark.circle" : "ruler",
                             text: deviation, tint: Palette.ink)
            }
            if let hint = model.contradiction {
                FeedbackLine(systemImage: "exclamationmark.triangle.fill", text: hint, tint: Palette.caution)
            }
            if let problem {
                FeedbackLine(systemImage: "exclamationmark.triangle.fill", text: problem, tint: Palette.critical)
            }
        }
        .motion(value: model.text)
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: "Checked with")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Picker("Checked with", selection: $model.source) {
                ForEach(VerificationSource.allCases, id: \.self) { source in
                    Text(verbatim: source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: "Note")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
            TextField("Optional, for example: measured at 1 m height", text: $model.note, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .frame(minHeight: 44, alignment: .topLeading)
                .background { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.surface) }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
        }
    }

    private var actionBar: some View {
        VStack(spacing: Spacing.s) {
            Button(action: save) {
                Text(verbatim: model.needsConfirmation ? "Save anyway" : "Save")
            }
            .buttonStyle(.primaryFullWidth)
            // Only an empty field has nothing to save; anything else answers when tapped.
            .disabled(model.check == .empty || !model.targetExists)
            .accessibilityHint(model.check == .empty ? "Type the measured value first." : "")

            if model.canClear {
                Button(action: clear) {
                    Text(verbatim: "Clear check")
                }
                .buttonStyle(.secondaryFullWidth)
                .accessibilityHint("Goes back to the scanned value.")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        // Opaque, not glass: the bar sits on a plain screen, and nothing translucent stacks on the sheet.
        .background { Palette.background.ignoresSafeArea() }
    }

    // MARK: Actions

    private var isFarFromScan: Bool {
        if case .farFromScan = model.check { return true }
        return false
    }

    private func save() {
        var current = model
        // "Save anyway" is the person's confirmation of a number far from the scan.
        if current.needsConfirmation { current.confirmOverride() }
        guard let check = current.verification(date: Date()) else {
            // The text is not a length. The reason is already on screen; say it aloud too.
            if let reason = current.message {
                UIAccessibility.post(notification: .announcement, argument: reason)
            }
            return
        }
        let actions = PropertyActions(model: app)
        let roomID = current.room.id
        guard actions.targetExists(propertyID: propertyID, roomID: roomID, target: current.target) else {
            problem = "This dimension is no longer in the room."
            UIAccessibility.post(notification: .announcement, argument: "This dimension is no longer in the room.")
            return
        }
        let saved = actions.saveVerification(propertyID: propertyID, roomID: roomID, target: current.target,
                                             verification: check)
        // A failed write has its own alert and banner; the check is kept in the app either way.
        if saved { Haptics.success() }
        dismiss()
    }

    private func clear() {
        let actions = PropertyActions(model: app)
        actions.saveVerification(propertyID: propertyID, roomID: model.room.id, target: model.target,
                                 verification: nil)
        dismiss()
    }

    /// "mm", "cm", "m", "in", "ft in".
    static func shortName(_ unit: LengthUnit) -> String {
        switch unit {
        case .millimetres: return "mm"
        case .centimetres: return "cm"
        case .metres: return "m"
        case .inches: return "in"
        case .feetAndInches: return "ft in"
        }
    }
}

// MARK: - Feedback line

/// A glyph and one calm sentence. The glyph is never the only signal: the sentence says it all.
private struct FeedbackLine: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Verify a wall") {
    let demo = DemoProperty.make()
    let room = demo.allRooms[0]
    return VerifySheet(propertyID: demo.id, room: room, target: .wallLength(room.walls[0].id),
                       units: .default)
        .environment(AppModel.preview())
}
#endif
