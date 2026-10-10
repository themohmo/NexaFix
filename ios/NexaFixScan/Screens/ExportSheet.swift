import Foundation
import Observation
import NexaFixCore

// The Export sheet: what to send, how it is set up, how much of it was checked on site, and the system
// share sheet. The plain-Swift part comes first (the choices, the temporary files, the controller that runs
// the export off the main thread); it is type-checked on Linux. The view is below `#if canImport(SwiftUI)`.

// MARK: - The choices

/// What the Export sheet has chosen: the formats and the options behind the disclosure.
struct ExportDraft: Equatable {
    var formats: Set<ExportFormat>
    var units: DisplayUnits
    /// "auto", "a4" or "a3".
    var paper: String
    /// Plan scale denominator; nil for automatic.
    var scale: Double?
    var includeSchedule = true

    /// Where the last choice of formats is remembered.
    static let storageKey = "com.nexafix.scan.export.formats.v1"
    /// Formats offered the first time: the plan, which is what most people send.
    static let defaultFormats: Set<ExportFormat> = [.planPDF]

    /// - Parameters:
    ///   - settings: The person's units, scale and paper become the starting options.
    ///   - storedFormats: What `formatsString(_:)` saved last time, if anything.
    init(settings: AppSettings, storedFormats: String? = nil) {
        formats = storedFormats.flatMap { ExportDraft.parseFormats($0) } ?? ExportDraft.defaultFormats
        units = settings.units
        paper = settings.paper
        scale = settings.planScale
    }

    /// Format names joined with commas, in the order of `ExportFormat.allCases`.
    static func formatsString(_ formats: Set<ExportFormat>) -> String {
        ExportFormat.allCases.filter { formats.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// The formats named in `text`. Names this version does not know are dropped; nil when none are left,
    /// so a damaged value falls back to the default.
    static func parseFormats(_ text: String) -> Set<ExportFormat>? {
        let found = Set(text.split(separator: ",").compactMap { ExportFormat(rawValue: String($0)) })
        return found.isEmpty ? nil : found
    }

    /// The formats that can actually be made: the 3D model only exists for levels scanned with a model.
    func effectiveFormats(modelAvailable: Bool) -> Set<ExportFormat> {
        modelAvailable ? formats : formats.subtracting([.model3D])
    }

    /// The request for the engine.
    func request(for property: Property, usdz: [UUID: USDZSource], now: Date = Date()) -> ExportRequest {
        ExportRequest(property: property, formats: effectiveFormats(modelAvailable: !usdz.isEmpty), units: units,
                      paper: paper, scale: scale, includeSchedule: includeSchedule, usdzSources: usdz, now: now)
    }
}

// MARK: - Files

/// Where export files go before they are shared, and how they get there.
enum ExportFiles {
    /// Exports older than this are removed the next time one is made.
    static let keepFor: TimeInterval = 24 * 3600

    /// `<temporary directory>/NexaFixExports`
    static func rootFolder(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent("NexaFixExports", isDirectory: true)
    }

    /// The name of one export folder: when it was made, in whole seconds since 1970, then a unique id
    /// ("1791540000-9F2C..."). The age of a folder is read from its name, so no file dates are needed.
    static func folderName(made now: Date, id: UUID = UUID()) -> String {
        let seconds = now.timeIntervalSince1970
        let whole = seconds.isFinite && seconds > 0 ? Int(min(seconds, 1e11)) : 0
        return "\(whole)-\(id.uuidString)"
    }

    /// When a folder called `name` was made, or nil if the name is not one `folderName` would write.
    static func madeAt(folderName name: String) -> Date? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let digits = name[name.startIndex..<dash]
        guard (1...11).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = TimeInterval(digits) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Writes the artifacts into a new folder under `root` and returns their URLs in order. A name that could
    /// leave the folder is reduced to its last component. If anything fails, the new folder is removed.
    static func write(_ artifacts: [ExportArtifact], under root: URL, now: Date = Date(),
                      fileManager: FileManager = .default) throws -> [URL] {
        let folder = root.appendingPathComponent(folderName(made: now), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var urls: [URL] = []
            for artifact in artifacts {
                let url = folder.appendingPathComponent(safeName(artifact.filename), isDirectory: false)
                try artifact.data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    /// Removes export folders made more than `age` seconds before `now`. Folders newer than that, which may
    /// still be on their way through AirDrop or Mail, are left alone.
    ///
    /// The age comes from the folder's name (see `folderName(made:id:)`), not from its file dates: reading file
    /// dates is a "required reason" API in the privacy manifest, and nothing here needs it. The folder holds
    /// nothing but copies made for sharing, so an entry whose name carries no date (one left by an earlier
    /// version, which named folders by id alone) is removed too instead of piling up.
    static func removeOldFolders(under root: URL, olderThan age: TimeInterval = keepFor, now: Date = Date(),
                                 fileManager: FileManager = .default) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            if let made = madeAt(folderName: name), now.timeIntervalSince(made) <= age { continue }
            try? fileManager.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// The last component of a path written with `/` or `\`, or "export" when nothing usable is left.
    static func safeName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        return last.isEmpty || last == "." || last == ".." ? "export" : last
    }
}

// MARK: - Controller

/// Runs an export without blocking the screen and keeps the result for the sheet to show.
///
/// The engine and the file writing run on a background task; only the outcome comes back to the main actor.
@MainActor
@Observable
final class ExportController {

    /// What went wrong, in two parts: what happened and what to do.
    struct Failure: Equatable {
        let message: String
        let recovery: String
    }

    struct Ready: Equatable {
        let urls: [URL]
        /// Things asked for but left out, such as "Level 23 has no 3D model."
        let notes: [String]

        var summary: String { urls.count == 1 ? "1 file is ready." : "\(urls.count) files are ready." }
    }

    enum State: Equatable {
        case idle
        case working
        case ready(Ready)
        case failed(Failure)
    }

    private(set) var state: State = .idle

    var isWorking: Bool { state == .working }

    /// Makes the files for `request`. Returns their URLs, or nil after setting `state` to the reason.
    @discardableResult
    func prepare(_ request: ExportRequest) async -> [URL]? {
        guard !isWorking else { return nil }
        state = .working
        let root = ExportFiles.rootFolder()
        do {
            let ready = try await Task.detached(priority: .userInitiated) { () -> Ready in
                ExportFiles.removeOldFolders(under: root)
                let result = try ExportEngine.runDetailed(request)
                let urls = try ExportFiles.write(result.artifacts, under: root)
                return Ready(urls: urls, notes: result.notes)
            }.value
            state = .ready(ready)
            return ready.urls
        } catch {
            state = .failed(ExportController.failure(for: error))
            return nil
        }
    }

    func reset() {
        if !isWorking { state = .idle }
    }

    /// The words for an error: specific, and always with a next step.
    nonisolated static func failure(for error: Error) -> Failure {
        if let export = error as? ExportError {
            switch export {
            case .noFormatSelected:
                return Failure(message: "No format is selected.", recovery: "Choose at least one, then share again.")
            case .noRooms:
                return Failure(message: "This property has no rooms yet.", recovery: "Scan a room first, then export.")
            case .nothingProduced(let reasons):
                let why = reasons.isEmpty ? "" : " " + reasons.joined(separator: " ")
                return Failure(message: "None of the chosen formats had anything to export." + why,
                               recovery: "Choose another format, or scan the level again.")
            case .failed(let format, let reason):
                return Failure(message: "The \(format.displayName) could not be made (\(reason)).",
                               recovery: "Try again. If it keeps failing, turn that format off and share the others.")
            }
        }
        let described = UserFacingError.describe(error)
        return Failure(message: described.message, recovery: described.recovery ?? "Try again.")
    }
}

// MARK: - The sheet

#if canImport(SwiftUI)
import SwiftUI
import UIKit

/// Export a property: choose formats, see how much of it was checked on site, and share the files through
/// the system share sheet (Files, AirDrop, Mail).
@MainActor
struct ExportSheet: View {
    private let propertyID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExportDraft
    @State private var controller = ExportController()
    @State private var optionsOpen = false
    @State private var shareItems: [URL]?

    /// - Parameters:
    ///   - propertyID: The property to export.
    ///   - settings: The person's units, scale and paper become the starting options.
    init(propertyID: UUID, settings: AppSettings) {
        self.propertyID = propertyID
        let stored = UserDefaults.standard.string(forKey: ExportDraft.storageKey)
        _draft = State(initialValue: ExportDraft(settings: settings, storedFormats: stored))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let property = app.property(propertyID) {
                    content(for: property)
                } else {
                    Text(verbatim: "This property is no longer available.")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // A failure or a note belongs to the options it was made with. Once an option changes it describes
        // something the person is no longer asking for, so it goes.
        .onChange(of: draft) { _, _ in controller.reset() }
    }

    // MARK: Content

    @MainActor @ViewBuilder
    private func content(for property: Property) -> some View {
        let readiness = ExportReadiness(property: property)
        let modelAvailable = property.floors.contains { $0.assets.structureUSDZ != nil }
        ScrollView {
            VStack(spacing: Spacing.xl) {
                ReadinessCard(readiness: readiness, units: draft.units)
                formatsCard(modelAvailable: modelAvailable)
                optionsCard
                statusArea
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shareBar(property: property, readiness: readiness, modelAvailable: modelAvailable)
        }
    }

    private func formatsCard(modelAvailable: Bool) -> some View {
        SectionCard("What to send") {
            ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element) { index, format in
                if index > 0 { RowDivider() }
                let unavailable = format == .model3D && !modelAvailable
                Toggle(isOn: binding(for: format, available: !unavailable)) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: format.displayName)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: unavailable ? "No 3D model has been saved. Scan a level to create one."
                             : format.detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(unavailable)
                .frame(minHeight: 44)
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private var optionsCard: some View {
        SectionCard {
            DisclosureGroup(isExpanded: $optionsOpen) {
                VStack(spacing: 0) {
                    RowDivider()
                    SettingRow("Paper") {
                        Picker("Paper", selection: $draft.paper) {
                            ForEach(SettingsChoices.papers) { Text(verbatim: $0.title).tag($0.value) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    RowDivider()
                    SettingRow("Scale") {
                        Picker("Scale", selection: $draft.scale) {
                            ForEach(SettingsChoices.scales(including: draft.scale)) { choice in
                                Text(verbatim: choice.title).tag(choice.value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    RowDivider()
                    SettingRow("Length") {
                        Picker("Length", selection: $draft.units.length) {
                            ForEach(LengthUnit.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    RowDivider()
                    SettingRow("Area") {
                        Picker("Area", selection: $draft.units.area) {
                            ForEach(AreaUnit.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    RowDivider()
                    Toggle(isOn: $draft.includeSchedule) {
                        Text(verbatim: "Room schedule in the PDF")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: 44)
                    .padding(.vertical, Spacing.xs)
                }
            } label: {
                Text(verbatim: "Options")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .tint(Palette.accent)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch controller.state {
        case .idle, .working:
            EmptyView()
        case .ready(let ready):
            if !ready.notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(Array(ready.notes.enumerated()), id: \.offset) { _, note in
                        StatusLine(systemImage: "info.circle", text: note, tint: Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                StatusLine(systemImage: "exclamationmark.triangle.fill", text: failure.message, tint: Palette.critical)
                Text(verbatim: failure.recovery)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Spacing.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Share

    private func shareBar(property: Property, readiness: ExportReadiness, modelAvailable: Bool) -> some View {
        let chosen = draft.effectiveFormats(modelAvailable: modelAvailable)
        let blocked = readiness.isEmpty || chosen.isEmpty
        return VStack(spacing: Spacing.xs) {
            if readiness.isEmpty {
                Text(verbatim: "Scan a room first, then export.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            } else if chosen.isEmpty {
                Text(verbatim: "Choose at least one format.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            Button {
                share(property: property)
            } label: {
                HStack(spacing: Spacing.s) {
                    if controller.isWorking {
                        ProgressView()
                        Text(verbatim: "Preparing files")
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityHidden(true)
                        Text(verbatim: "Share")
                    }
                }
            }
            .buttonStyle(.primaryFullWidth)
            .disabled(blocked || controller.isWorking)
            // The system share sheet is presented from the button, so on iPad it points at it.
            .background { ShareSheet(items: $shareItems).allowsHitTesting(false) }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .background { Palette.background.opacity(0.94).ignoresSafeArea() }
    }

    private func share(property: Property) {
        let usdz = usdzSources(for: property)
        let request = draft.request(for: property, usdz: usdz, now: Date())
        UserDefaults.standard.set(ExportDraft.formatsString(draft.formats), forKey: ExportDraft.storageKey)
        Task { @MainActor in
            if let urls = await controller.prepare(request) {
                shareItems = urls
            } else if case .failed(let failure) = controller.state {
                // The message is on screen under the formats; say it aloud as well.
                UIAccessibility.post(notification: .announcement, argument: failure.message + " " + failure.recovery)
            }
        }
    }

    /// The saved model of each level, as files to read when the export runs (off the main thread).
    private func usdzSources(for property: Property) -> [UUID: USDZSource] {
        var sources: [UUID: USDZSource] = [:]
        for floor in property.floors {
            guard let path = floor.assets.structureUSDZ,
                  let url = app.assetURL(relativePath: path, propertyID: property.id) else { continue }
            sources[floor.id] = .file(url)
        }
        return sources
    }

    /// On when the format is chosen and can be made. A format that cannot be made shows as off, whatever was
    /// chosen last time.
    private func binding(for format: ExportFormat, available: Bool) -> Binding<Bool> {
        Binding(get: { available && draft.formats.contains(format) },
                set: { isOn in
                    if isOn { draft.formats.insert(format) } else { draft.formats.remove(format) }
                })
    }
}

// MARK: - Readiness

/// How much of the property was checked on site, and the joinery disclaimer.
private struct ReadinessCard: View {
    let readiness: ExportReadiness
    let units: DisplayUnits
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: readiness.hasUnverifiedJoinery || readiness.isEmpty
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(readiness.hasUnverifiedJoinery || readiness.isEmpty
                                     ? Palette.caution : Palette.verified)
                    .accessibilityHidden(true)
                Text(verbatim: readiness.banner)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: ScanAccuracy.joineryDisclaimer)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if readiness.hasUnverifiedJoinery {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(readiness.unverifiedJoinery.prefix(ReadinessCard.listLimit)) { item in
                            Text(verbatim: "\(item.title) \u{00B7} \(GroupedLength.text(item.scannedM, unit: units.length, precision: .compact)) "
                                 + UnitFormatter.tolerance(forLength: item.scannedM, unit: units.length))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if readiness.unverifiedJoinery.count > ReadinessCard.listLimit {
                            Text(verbatim: "and \(readiness.unverifiedJoinery.count - ReadinessCard.listLimit) more")
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
                } label: {
                    Text(verbatim: "Still scanned only: \(readiness.unverifiedJoinery.count) joinery \(readiness.unverifiedJoinery.count == 1 ? "dimension" : "dimensions")")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .tint(Palette.accent)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Palette.surface) }
        .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
    }

    private static let listLimit = 8
}

/// A glyph and a sentence.
private struct StatusLine: View {
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
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Export") {
    let demo = DemoProperty.make()
    ExportSheet(propertyID: demo.id, settings: AppSettings())
        .environment(AppModel.preview())
}
#endif
#endif
