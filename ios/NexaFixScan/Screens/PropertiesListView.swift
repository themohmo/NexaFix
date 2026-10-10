import SwiftUI
import NexaFixCore

/// The home screen: every property as a card with a small plan, its name and client, how much is checked,
/// and **New scan** at the bottom. Search, swipe to duplicate or delete, and an empty state with the demo.
@MainActor
struct PropertiesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var cache = PropertyCardCache()
    @State private var pendingDelete: DeleteTarget?

    /// The widest a card gets, points; every other screen is capped between 560 and 640.
    private static let contentWidth: CGFloat = 640

    private struct DeleteTarget: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    private var sources: [PropertySource] {
        let memory = PropertyListFilter.properties(model.memoryOnlyProperties, query: query).map(PropertySource.memory)
        let saved = PropertyListFilter.summaries(model.summaries, query: query).map(PropertySource.saved)
        return memory + saved
    }

    private var hasAnyProperty: Bool {
        !model.summaries.isEmpty || !model.memoryOnlyProperties.isEmpty
    }

    var body: some View {
        Group {
            if !hasAnyProperty {
                EmptyStateView(
                    title: "No properties yet",
                    message: "Scan a room and its measurements show up here, ready to check and send.",
                    primaryTitle: "Scan a property",
                    primaryAction: { router.showNewProperty() },
                    secondaryTitle: "Try the demo apartment",
                    secondaryAction: openDemo)
            } else {
                list
            }
        }
        .screenBackground()
        .statusBanners()
        .navigationTitle("Properties")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.showSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .searchable(text: $query, prompt: "Search properties")
        .confirmationDialog(deleteTitle, isPresented: deleteIsPresented, titleVisibility: .visible,
                            presenting: pendingDelete) { target in
            Button("Delete property", role: .destructive) { delete(target) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(verbatim: "This removes its rooms, scans and files from this device. It can\u{2019}t be undone.")
        }
        .onChange(of: model.summaries.map(\.id)) { _, ids in
            cache.keep(Set(ids))
        }
    }

    // MARK: List

    private var list: some View {
        let rows = sources
        return List {
            ForEach(rows) { source in
                PropertyRow(source: source, cache: cache,
                            onOpen: { router.open(source.id) },
                            onDuplicate: { duplicate(source.id) },
                            onDelete: { askToDelete(source) })
                    // Cards stop growing on an iPad: a line of text across a whole landscape screen is unreadable.
                    .frame(maxWidth: PropertiesListView.contentWidth)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.l, bottom: Spacing.xs, trailing: Spacing.l))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { newScanBar }
    }

    private var newScanBar: some View {
        Button { router.showNewProperty() } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "viewfinder")
                    .accessibilityHidden(true)
                Text(verbatim: "New scan")
            }
        }
        .buttonStyle(.primary)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s)
        .background {
            // The cards fade out behind the button instead of running into it.
            LinearGradient(colors: [Palette.background.opacity(0), Palette.background],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: Actions

    private func openDemo() {
        let demo = model.installDemo()
        router.open(demo.id)
    }

    private func duplicate(_ id: UUID) {
        PropertyActions(model: model).duplicate(id)
    }

    private func askToDelete(_ source: PropertySource) {
        switch source {
        case .saved(let summary): pendingDelete = DeleteTarget(id: summary.id, name: summary.name)
        case .memory(let property): pendingDelete = DeleteTarget(id: property.id, name: property.name)
        }
    }

    private func delete(_ target: DeleteTarget) {
        PropertyActions(model: model).delete(target.id)
        pendingDelete = nil
    }

    private var deleteTitle: String {
        guard let name = pendingDelete?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Delete this property?"
        }
        return "Delete \u{201C}\(name)\u{201D}?"
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { shown in if !shown { pendingDelete = nil } })
    }
}

// MARK: - Row

/// A row of the list: a saved property (read when its row appears) or one that exists only in memory because
/// its first save failed.
private enum PropertySource: Identifiable {
    case saved(PropertySummary)
    case memory(Property)

    var id: UUID {
        switch self {
        case .saved(let summary): return summary.id
        case .memory(let property): return property.id
        }
    }

    var summary: PropertySummary? {
        if case .saved(let summary) = self { return summary }
        return nil
    }

    var memoryProperty: Property? {
        if case .memory(let property) = self { return property }
        return nil
    }
}

/// One property in the list. The property is read when the row first appears, not when the list is built.
@MainActor
private struct PropertyRow: View {
    let source: PropertySource
    let cache: PropertyCardCache
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = source.summary
        // A property whose files cannot be read has nothing to show but its problem and a way to delete it.
        let unreadable = summary?.health == .unreadable
        let property: Property? = unreadable ? nil : (model.property(source.id) ?? source.memoryProperty)
        let info = property.map { cache.info(for: $0) }
        PropertyCard(name: property?.name ?? summary?.name ?? "Property",
                     client: property?.client ?? summary?.client ?? "",
                     info: info,
                     problem: summary?.problem,
                     isUnsaved: model.unsavedPropertyIDs.contains(source.id),
                     units: model.settings.units,
                     isOpenable: !unreadable,
                     onOpen: onOpen)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !unreadable {
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(Palette.accent)
                }
            }
            .contextMenu {
                if !unreadable {
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// MARK: - Card

/// The card: a small plan, the names, one line of numbers and a thin bar of how much is checked.
private struct PropertyCard: View {
    let name: String
    let client: String
    let info: PropertyCardInfo?
    let problem: String?
    let isUnsaved: Bool
    let units: DisplayUnits
    let isOpenable: Bool
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 76

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: onOpen) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.l))
            layout {
                CardThumbnail(drawing: info?.thumbnail)
                    .frame(width: typeSize.isAccessibilitySize ? nil : thumbnailSize,
                           height: typeSize.isAccessibilitySize ? thumbnailSize * 1.6 : thumbnailSize)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                texts
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(Palette.surface) }
            .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .disabled(!isOpenable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(isOpenable ? "Opens the property." : "")
        .accessibilityAddTraits(isOpenable ? .isButton : [])
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: name)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !client.isEmpty {
                Text(verbatim: client)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let info {
                Text(verbatim: info.line(units: units))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                VerifiedBar(fraction: info.summary.fraction)
                    .padding(.top, Spacing.xxs)
            }
            if isUnsaved {
                notice("Not saved yet. Keep the app open.")
            }
            if let problem, !problem.isEmpty {
                notice(problem)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Palette.caution)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spokenLabel: String {
        var parts = [name]
        if !client.isEmpty { parts.append(client) }
        if let info { parts.append(info.spoken(units: units)) }
        if isUnsaved { parts.append("not saved yet") }
        if let problem, !problem.isEmpty { parts.append(problem) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Pieces

/// The plan of the first level on a rounded tile, drawn by the shared `PlanThumbnail`; a dashed square when
/// the property has no rooms to draw yet.
private struct CardThumbnail: View {
    let drawing: PlanDrawing?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        ZStack {
            frame.fill(Palette.background)
            if let drawing {
                PlanThumbnail(drawing: drawing)
            } else {
                Image(systemName: "square.dashed")
                    .font(.title2)
                    .foregroundStyle(Palette.muted)
            }
        }
        .overlay { frame.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
        .clipShape(frame)
        .accessibilityHidden(true)
    }
}

/// A thin bar: how much of the property is checked with a laser, tape or drawing. The card says the same in
/// words, so the bar is decoration for VoiceOver.
struct VerifiedBar: View {
    let fraction: Double

    var body: some View {
        let progress = VerificationSummary.clamp(fraction)
        Capsule(style: .continuous)
            .fill(Palette.line)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(Palette.verified)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .motion(value: progress)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Properties") {
    NavigationStack { PropertiesListView() }
        .environment(AppModel.preview())
        .environment(AppRouter())
}

#Preview("Properties, empty") {
    NavigationStack { PropertiesListView() }
        .environment(AppModel.preview(withDemo: false))
        .environment(AppRouter())
}
#endif
