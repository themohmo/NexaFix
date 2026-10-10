import SwiftUI
import NexaFixCore

/// Settings, shown as a sheet from the home screen: units, haptics, plan defaults, how accurate this phone
/// has been, and About. Every change is saved the moment it is made (`AppModel.settings`).
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Counted from every property on the device; nil until the first count is done.
    @State private var accuracy: AccuracyOverview?

    private enum Route: Hashable {
        case about
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    unitsSection
                    feedbackSection
                    planSection
                    accuracySection
                    aboutSection
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { _ in AboutView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Counting reads every property once; it runs again when anything is saved while this is open.
        .task(id: model.revision) { await updateAccuracy() }
    }

    // MARK: Units

    private var unitsSection: some View {
        let units = model.settings.units
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionCard("Units") {
                SettingRow("Length") {
                    Picker("Length", selection: lengthBinding) {
                        ForEach(LengthUnit.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                RowDivider()
                SettingRow("Area") {
                    Picker("Area", selection: areaBinding) {
                        ForEach(AreaUnit.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            // A live example, so the choice can be judged without leaving the screen.
            Text(verbatim: "Example: \(SettingsChoices.lengthExample(units.length)) and \(SettingsChoices.areaExample(units.area))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, Spacing.l)
                .accessibilityLabel("Example: "
                    + SpokenMeasurement.length(3.245, unit: units.length) + " and "
                    + SpokenMeasurement.area(18.42, unit: units.area))
        }
    }

    // MARK: Haptics

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionCard("Feedback") {
                Toggle(isOn: hapticsBinding) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: "Haptics")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "A tap when a point snaps, a check is saved or a room is finished.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(minHeight: 44)
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: Plans

    private var planSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionCard("Plan defaults") {
                SettingRow("Scale") {
                    Picker("Scale", selection: scaleBinding) {
                        ForEach(SettingsChoices.scales(including: model.settings.planScale)) { choice in
                            Text(verbatim: choice.title).tag(choice.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                RowDivider()
                SettingRow("Paper") {
                    Picker("Paper", selection: paperBinding) {
                        ForEach(SettingsChoices.papers) { Text(verbatim: $0.title).tag($0.value) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            Text(verbatim: "Used for the PDF and the DXF. Automatic picks the largest standard scale that fits the paper.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, Spacing.l)
        }
    }

    // MARK: Accuracy

    private var accuracySection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionCard("Accuracy") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: accuracy?.summary ?? "Counting your checks")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let bias = accuracy?.bias, !bias.isEmpty {
                        Text(verbatim: bias)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: AccuracyOverview.footerTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: AccuracyOverview.footerText)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.l)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        SectionCard {
            NavigationLink(value: Route.about) {
                SettingRow("About NexaFix Scan") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: Bindings

    private var lengthBinding: Binding<LengthUnit> {
        Binding(get: { model.settings.units.length }, set: { model.settings.units.length = $0 })
    }

    private var areaBinding: Binding<AreaUnit> {
        Binding(get: { model.settings.units.area }, set: { model.settings.units.area = $0 })
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { model.settings.hapticsEnabled }, set: { model.settings.hapticsEnabled = $0 })
    }

    private var scaleBinding: Binding<Double?> {
        Binding(get: { model.settings.planScale }, set: { model.settings.planScale = AppSettings.sanitisedScale($0) })
    }

    private var paperBinding: Binding<String> {
        Binding(get: { model.settings.paper }, set: { model.settings.paper = AppSettings.sanitisedPaper($0) })
    }

    // MARK: Counting

    @MainActor
    private func updateAccuracy() async {
        // A property whose file cannot be read has no checks to count, and opening it would raise an error the
        // person cannot act on from here. One restored from its backup is readable and counts.
        let ids = model.summaries.filter { $0.health != .unreadable }.map(\.id)
        var properties = ids.compactMap { model.property($0) }
        // A property that exists only in memory still counts.
        let known = Set(properties.map(\.id))
        properties.append(contentsOf: model.unsavedProperties.filter { !known.contains($0.id) })
        let unit = model.settings.units.length
        let counted = properties
        accuracy = await Task.detached(priority: .utility) {
            AccuracyOverview.make(properties: counted, unit: unit)
        }.value
    }
}

// MARK: - Row

/// A title with a control at the trailing edge. At accessibility text sizes the control drops under the
/// title so neither is squeezed. Shared with the Export sheet's options.
struct SettingRow<Control: View>: View {
    private let title: String
    private let control: Control
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        layout {
            Text(verbatim: title)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            control
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, Spacing.xs)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().environment(AppModel.preview())
}
#endif
