import SwiftUI
import NexaFixCore

/// The details of a property: name (the only required field), client, address, reference and kind.
///
/// - `.create` is the sheet behind "New scan" on the home screen. **Start scanning** saves the property and
///   opens the camera once the sheet has closed; **Save without scanning** saves it and opens it.
/// - `.edit` changes the details of a property that exists, from its screen.
@MainActor
struct NewPropertySheet: View {
    enum Mode {
        case create
        case edit(Property)
    }

    private let mode: Mode

    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NewPropertyDraft
    /// Set by the first tap on a create button. The sheet takes a moment to leave, and a second tap in that
    /// time must not save a second property.
    @State private var didStartCreating = false
    @FocusState private var focus: PropertyFormField?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create: _draft = State(initialValue: NewPropertyDraft())
        case .edit(let property): _draft = State(initialValue: NewPropertyDraft(editing: property))
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    fields
                    if isCreating {
                        levelRow
                        createButtons
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(isCreating ? "New property" : "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !isCreating {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveDetails() }
                            .disabled(!draft.canCreate)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { @MainActor in
            guard isCreating else { return }
            // After the sheet has finished rising, so the keyboard does not fight the animation.
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled { focus = .name }
        }
    }

    // MARK: Fields

    private var fields: some View {
        SectionCard {
            FormField("Name", prompt: "Required", text: $draft.name, focus: $focus, field: .name) {
                focus = .client
            }
            RowDivider()
            FormField("Client", prompt: "Optional", text: $draft.client, focus: $focus, field: .client) {
                focus = .address
            }
            RowDivider()
            FormField("Address", prompt: "Optional", text: $draft.address, focus: $focus, field: .address) {
                focus = .reference
            }
            RowDivider()
            FormField("Reference", prompt: "For example NF-2026-1009-01", text: $draft.reference,
                      focus: $focus, field: .reference, isCode: true) {
                focus = nil
            }
            RowDivider()
            SettingRow("Kind") {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(PropertyKind.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var levelRow: some View {
        LevelStepper(story: $draft.story,
                     caption: "The level you are about to scan. Each scan becomes its own level, so floors never mix.")
    }

    private var createButtons: some View {
        VStack(spacing: Spacing.s) {
            Button { create(thenScan: true) } label: { Text(verbatim: "Start scanning") }
                .buttonStyle(.primaryFullWidth)
                .disabled(!draft.canCreate || didStartCreating)
                .accessibilityHint(draft.canCreate ? "" : "Add a name first.")
            Button { create(thenScan: false) } label: { Text(verbatim: "Save without scanning") }
                .buttonStyle(.secondaryFullWidth)
                .disabled(!draft.canCreate || didStartCreating)
        }
    }

    // MARK: Actions

    private func create(thenScan: Bool) {
        // Both buttons are disabled without a name and after the first tap; this is the second line of defence.
        guard draft.canCreate, !didStartCreating else { return }
        didStartCreating = true
        let property = app.createProperty(name: draft.name, client: draft.client, address: draft.address,
                                          reference: draft.reference, kind: draft.kind)
        // A save that failed has its own alert and banner; the property stays open in the app.
        if !app.unsavedPropertyIDs.contains(property.id) { Haptics.success() }
        if thenScan {
            router.scanAfterSheet(propertyID: property.id, story: draft.story)
        } else {
            router.openAfterSheet(property.id)
        }
    }

    private func saveDetails() {
        guard case .edit(let property) = mode, draft.canCreate else { return }
        PropertyActions(model: app).updateDetails(property.id, name: draft.name, client: draft.client,
                                                  address: draft.address, reference: draft.reference,
                                                  kind: draft.kind)
        dismiss()
    }
}

// MARK: - Add a scan to a property

/// Which level is about to be scanned. Shown before the camera opens on a property that already exists.
@MainActor
struct AddScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var story: Int
    private let propertyName: String
    private let onStart: (Int) -> Void

    /// - Parameters:
    ///   - propertyName: Shown as the heading.
    ///   - initialStory: The level to start from.
    ///   - onStart: The person chose a level. Called after the sheet has asked to close.
    init(propertyName: String, initialStory: Int, onStart: @escaping (Int) -> Void) {
        self.propertyName = propertyName
        self.onStart = onStart
        _story = State(initialValue: PropertyDefaults.clampedStory(initialStory))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(verbatim: "Scan \(propertyName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                LevelStepper(story: $story,
                             caption: "Each scan becomes its own level, so floors never mix. Choose the level you are about to scan.")
                Spacer(minLength: 0)
                Button {
                    onStart(story)
                    dismiss()
                } label: {
                    Text(verbatim: "Start scanning")
                }
                .buttonStyle(.primaryFullWidth)
            }
            .padding(Spacing.l)
            .frame(maxWidth: 560, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .screenBackground()
            .navigationTitle("Add a scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Pieces

/// "Level 23" with a stepper. Level 0 is the ground floor and negative levels are basements.
private struct LevelStepper: View {
    @Binding var story: Int
    let caption: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Stepper(value: $story, in: PropertyDefaults.storyRange) {
                Text(verbatim: ScanCommit.levelName(story))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Level to scan")
            .accessibilityValue(ScanCommit.levelName(story))
            Text(verbatim: caption)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
    }
}

/// The fields of the details form, so Return can move from one to the next.
private enum PropertyFormField: Hashable {
    case name, client, address, reference
}

/// A label above a text field, for use inside a `SectionCard`.
private struct FormField: View {
    private let title: String
    private let prompt: String
    private let text: Binding<String>
    private let focus: FocusState<PropertyFormField?>.Binding
    private let field: PropertyFormField
    private let isCode: Bool
    private let advance: () -> Void

    /// - Parameters:
    ///   - isCode: A reference or code: capital letters, no autocorrect. Otherwise words are capitalised.
    ///   - advance: Called when the person presses Return.
    init(_ title: String, prompt: String, text: Binding<String>, focus: FocusState<PropertyFormField?>.Binding,
         field: PropertyFormField, isCode: Bool = false, advance: @escaping () -> Void) {
        self.title = title
        self.prompt = prompt
        self.text = text
        self.focus = focus
        self.field = field
        self.isCode = isCode
        self.advance = advance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
            TextField(prompt, text: text)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(isCode ? .characters : .words)
                .autocorrectionDisabled(isCode)
                .focused(focus, equals: field)
                .submitLabel(.next)
                .onSubmit(advance)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
        }
        .padding(.vertical, Spacing.xs)
    }
}

#if DEBUG
#Preview("New property") {
    NewPropertySheet(mode: .create)
        .environment(AppModel.preview(withDemo: false))
        .environment(AppRouter())
}

#Preview("Add a scan") {
    AddScanSheet(propertyName: "Marina Gate 2 - Unit 2304", initialStory: 23, onStart: { _ in })
}
#endif
