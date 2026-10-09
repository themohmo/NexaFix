import SwiftUI
import NexaFixCore

/// The small sheet after a room is scanned: a name, a type, then "Scan next room" or "Finish property".
///
/// The name starts as the default for the most likely next room ("Living Room", then "Kitchen", ...,
/// "Bedroom 2"), and follows the type chips until the person types their own. The rules (not empty, not
/// already used) live in `ScanFlow`; this view only shows the verdict.
struct RoomNameSheet: View {
    let flow: ScanFlow
    let draft: RoomDraft
    let units: DisplayUnits
    let onScanNext: (String, RoomKind) -> Void
    let onFinishProperty: (String, RoomKind) -> Void
    let onRescan: () -> Void
    let onDiscard: () -> Void

    @State private var name: String
    @State private var kind: RoomKind
    @State private var nameWasEdited = false
    @State private var isConfirmingDiscard = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    init(flow: ScanFlow,
         draft: RoomDraft,
         units: DisplayUnits,
         onScanNext: @escaping (String, RoomKind) -> Void,
         onFinishProperty: @escaping (String, RoomKind) -> Void,
         onRescan: @escaping () -> Void,
         onDiscard: @escaping () -> Void) {
        self.flow = flow
        self.draft = draft
        self.units = units
        self.onScanNext = onScanNext
        self.onFinishProperty = onFinishProperty
        self.onRescan = onRescan
        self.onDiscard = onDiscard
        let suggested = flow.suggestedKind
        _kind = State(initialValue: suggested)
        _name = State(initialValue: flow.suggestedName(for: suggested))
    }

    private var check: ScanFlow.NameCheck { flow.validate(name: name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                    .padding(.horizontal, Spacing.xl)
                nameField
                    .padding(.horizontal, Spacing.xl)
                kindChips
                warnings
                    .padding(.horizontal, Spacing.xl)
                actions
                    .padding(.horizontal, Spacing.xl)
            }
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card)
        .presentationBackground(Palette.background)
        // A scanned room is not saved until it has a name, so a swipe must not dismiss it by accident.
        .interactiveDismissDisabled(true)
        .confirmationDialog("Discard this room?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard room", role: .destructive, action: onDiscard)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(flow.rooms.isEmpty
                 ? "The scan of this room will be deleted."
                 : "The scan of this room will be deleted. Your other rooms are kept.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        let stats = LiveScanStats(walls: draft.wallCount, doors: draft.doorCount, windows: draft.windowCount,
                                  openings: draft.openingCount, roughFloorAreaM2: draft.floorAreaM2)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: "Name this room")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: stats.summary(units: units))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .accessibilityLabel(stats.spokenSummary(units: units))
        }
    }

    private var nameField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        let problem = check.message
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Room name", text: $name)
                .focused($isNameFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { isNameFocused = false }
                .font(.body)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 48)
                .background { shape.fill(Palette.surface) }
                .overlay {
                    shape.strokeBorder(problem == nil ? Palette.line : Palette.critical,
                                       lineWidth: problem == nil && contrast != .increased ? Hairline.width : Hairline.emphasized)
                }
                .onChange(of: name) { _, newValue in
                    if newValue != flow.suggestedName(for: kind) { nameWasEdited = true }
                }
                .accessibilityLabel("Room name")

            if let problem {
                Label {
                    Text(verbatim: problem)
                        .font(.footnote)
                        .foregroundStyle(Palette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.critical)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var kindChips: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: "Room type")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, Spacing.xl)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(flow.suggestedKinds, id: \.self) { option in
                        chip(option)
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }
        }
    }

    private func chip(_ option: RoomKind) -> some View {
        let isSelected = option == kind
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        return Button {
            guard option != kind else { return }
            kind = option
            if !nameWasEdited { name = flow.suggestedName(for: option) }
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: option.displayName)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Palette.accentContrast : Palette.ink)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 44)
            .background { shape.fill(isSelected ? Palette.accent : Palette.surface) }
            .overlay {
                if !isSelected {
                    shape.strokeBorder(Palette.line, lineWidth: contrast == .increased ? Hairline.emphasized : Hairline.width)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var warnings: some View {
        if !draft.warnings.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(draft.warnings.prefix(2).enumerated()), id: \.offset) { _, warning in
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
        }
    }

    private var actions: some View {
        let isValid = check.isValid
        return VStack(spacing: Spacing.s) {
            Button("Scan next room") { onScanNext(name, kind) }
                .buttonStyle(.primaryFullWidth)
                .disabled(!isValid)
            Button("Finish property") { onFinishProperty(name, kind) }
                .buttonStyle(.secondaryFullWidth)
                .disabled(!isValid)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xl) { quietButtons }
                VStack(spacing: 0) { quietButtons }
            }
        }
    }

    /// Quiet text buttons. The 44 pt frame and the hit shape are inside each label: a frame applied to the Button
    /// would leave only the words themselves tappable.
    @ViewBuilder
    private var quietButtons: some View {
        Button(action: onRescan) {
            Text(verbatim: "Rescan this room")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        Button(role: .destructive) {
            isConfirmingDiscard = true
        } label: {
            Text(verbatim: "Discard room")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.critical)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}
