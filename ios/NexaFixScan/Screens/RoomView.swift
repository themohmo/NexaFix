import SwiftUI
import NexaFixCore

/// One room: its floor area, sizes and how much of it has been checked, then every dimension with where its
/// value came from. Tapping a dimension opens the Verify sheet. Corners, openings, furniture, measurements
/// taken in AR or 3D, and notes follow.
@MainActor
struct RoomView: View {
    let propertyID: UUID
    let roomID: UUID

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    @State private var verifyRequest: VerifyRequest?
    @State private var notes = ""
    @State private var notesSeeded = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmingDelete = false

    private struct VerifyRequest: Identifiable {
        let target: MeasureTarget
        var id: MeasureTarget { target }
    }

    // MARK: Body

    var body: some View {
        Group {
            if let property = model.property(propertyID), let room = property.findRoom(roomID) {
                screen(property: property, room: room)
            } else {
                gone
            }
        }
        .screenBackground()
    }

    private var gone: some View {
        VStack(spacing: Spacing.l) {
            Text(verbatim: "This room is no longer in the property.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button { popRoom() } label: { Text(verbatim: "Back") }
                .buttonStyle(.secondary)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBanners()
    }

    @MainActor @ViewBuilder
    private func screen(property: Property, room: Room) -> some View {
        let overview = RoomOverview(room: room)
        let units = model.settings.units
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                hero(overview, units: units)
                dimensionsSection(overview, units: units)
                cornersSection(overview)
                openingsSection(overview, units: units)
                objectsSection(room, units: units)
                measurementsSection(overview, units: units)
                notesSection
                Text(verbatim: ScanAccuracy.joineryDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.l)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .statusBanners()
        .navigationTitle(overview.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu(room) }
        .sheet(item: $verifyRequest) { request in
            if let current = model.property(propertyID)?.findRoom(roomID) {
                VerifySheet(propertyID: propertyID, room: current, target: request.target, units: units)
            }
        }
        .confirmationDialog("Delete \u{201C}\(overview.title)\u{201D}?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete room", role: .destructive) { deleteRoom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "The room and its checks are removed from this level. It can\u{2019}t be undone.")
        }
        .alert("Rename room", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                PropertyActions(model: model).renameRoom(propertyID: propertyID, roomID: roomID, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "Room names are unique on a level.")
        }
        .onAppear { seedNotes(from: room) }
        // Notes are saved a moment after typing stops, and when the screen goes away.
        .task(id: notes) { @MainActor in
            guard notesSeeded else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { commitNotes() }
        }
        .onDisappear { commitNotes() }
    }

    // MARK: Hero

    private func hero(_ overview: RoomOverview, units: DisplayUnits) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Says how much of the figure rests on the scan, so a mostly scanned area never reads as checked.
                Text(verbatim: overview.areaBasis.caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                MeasurementText(area: overview.areaM2, units: units, style: .hero)
                Text(verbatim: overview.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.l, alignment: .topLeading)],
                      alignment: .leading, spacing: Spacing.m) {
                if let size = overview.sizeText(units: units) {
                    Stat(label: "Length \u{00D7} width", spoken: overview.sizeSpoken(units: units) ?? size) {
                        Text(verbatim: size)
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Stat(label: "Shape", spoken: "Irregular shape") {
                        Text(verbatim: "Irregular")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
                Stat(label: "Perimeter", spoken: SpokenMeasurement.length(overview.perimeter, unit: units.length)) {
                    MeasurementText(length: overview.perimeter, units: units, style: .body)
                }
                Stat(label: "Ceiling height",
                     spoken: SpokenMeasurement.length(overview.ceiling.value, unit: units.length) + ", "
                        + SpokenMeasurement.midSentence(
                            ProvenanceDescription(overview.ceiling, units: units, compact: false).spoken)) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        MeasurementText(length: overview.ceiling.value, units: units, style: .body)
                        ProvenanceBadge(overview.ceiling, units: units, compact: true)
                    }
                }
                let volume = VolumeText(cubicMetres: overview.volumeM3, units: units)
                Stat(label: "Volume", spoken: volume.spoken) {
                    Text(verbatim: volume.visible)
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                }
            }

            // The size, perimeter and volume above are worked out from the wall lengths; say how far those
            // rest on the scan, the way the area does.
            Text(verbatim: overview.areaBasis.derivedCaption(hasSize: overview.sizeText(units: units) != nil))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            VerificationProgress(verified: overview.summary.verified, total: overview.summary.total)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    @ViewBuilder
    private func dimensionsSection(_ overview: RoomOverview, units: DisplayUnits) -> some View {
        let items = overview.items(in: .structure)
        if !items.isEmpty {
            SectionCard("Dimensions") {
                dimensionRows(items, units: units)
            }
        }
    }

    @ViewBuilder
    private func openingsSection(_ overview: RoomOverview, units: DisplayUnits) -> some View {
        let items = overview.items(in: .openings)
        if !items.isEmpty {
            SectionCard("Openings") {
                dimensionRows(items, units: units)
            }
        }
    }

    @ViewBuilder
    private func measurementsSection(_ overview: RoomOverview, units: DisplayUnits) -> some View {
        let items = overview.items(in: .custom)
        if !items.isEmpty {
            SectionCard("Measurements") {
                dimensionRows(items, units: units)
            }
        }
    }

    @ViewBuilder
    private func dimensionRows(_ items: [VerificationChecklist.Item], units: DisplayUnits) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { RowDivider() }
            DimensionRow(item: item, units: units) { verifyRequest = VerifyRequest(target: item.target) }
        }
    }

    @ViewBuilder
    private func cornersSection(_ overview: RoomOverview) -> some View {
        if !overview.corners.isEmpty {
            SectionCard("Corners") {
                ForEach(Array(overview.corners.enumerated()), id: \.element.id) { index, reading in
                    if index > 0 { RowDivider() }
                    CornerRow(reading: reading)
                }
            }
        }
    }

    @ViewBuilder
    private func objectsSection(_ room: Room, units: DisplayUnits) -> some View {
        if !room.objects.isEmpty {
            let tester = PlanHitTester(rooms: [room])
            SectionCard("Objects") {
                ForEach(Array(room.objects.enumerated()), id: \.element.id) { index, object in
                    if index > 0 { RowDivider() }
                    ObjectRow(
                        title: tester.selectionTitle(for: .object(room: room.id, object: object.id)) ?? object.kind.displayName,
                        object: object, units: units)
                }
            }
        }
    }

    private var notesSection: some View {
        SectionCard("Notes") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .accessibilityLabel("Notes")
                if notes.isEmpty {
                    Text(verbatim: "Add a note for this room")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, Spacing.s)
                        .padding(.leading, Spacing.xs)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarMenu(_ room: Room) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    renameText = room.name
                    renaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Menu {
                    ForEach(RoomKind.allCases, id: \.self) { kind in
                        Button {
                            PropertyActions(model: model).setRoomKind(propertyID: propertyID, roomID: roomID, to: kind)
                        } label: {
                            if room.kind == kind {
                                Label(kind.displayName, systemImage: "checkmark")
                            } else {
                                Text(verbatim: kind.displayName)
                            }
                        }
                    }
                } label: {
                    Label("Change type", systemImage: "square.grid.2x2")
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete room", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: Actions

    private func seedNotes(from room: Room) {
        guard !notesSeeded else { return }
        notes = room.notes
        notesSeeded = true
    }

    /// Writes the notes if they differ from what is saved.
    private func commitNotes() {
        guard notesSeeded, let saved = model.property(propertyID)?.findRoom(roomID)?.notes, saved != notes else { return }
        PropertyActions(model: model).setNotes(propertyID: propertyID, roomID: roomID, to: notes)
    }

    private func deleteRoom() {
        notesSeeded = false
        PropertyActions(model: model).deleteRoom(propertyID: propertyID, roomID: roomID)
        popRoom()
    }

    private func popRoom() {
        if !router.path.isEmpty { router.path.removeLast() }
    }
}

// MARK: - Rows

/// A label above a value, in the grid at the top of the screen.
private struct Stat<Value: View>: View {
    private let label: String
    private let spoken: String
    private let value: Value

    init(label: String, spoken: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.spoken = spoken
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: label)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }
}

/// One checkable dimension: what it is, its number, where the number came from, and a chevron to check it.
private struct DimensionRow: View {
    let item: VerificationChecklist.Item
    let units: DisplayUnits
    let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onTap) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
            layout {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: item.title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = item.detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProvenanceBadge(item.measured, units: units)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
                HStack(spacing: Spacing.s) {
                    MeasurementText(length: item.measured.value, units: units, style: .body)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityMeasurement(
            item.fullTitle,
            value: MeasurementParts.length(item.measured.value, units: units).spoken,
            provenance: ProvenanceDescription(item.measured, units: units, compact: false).spoken)
        .accessibilityHint("Opens the check for this dimension.")
        .accessibilityAddTraits(.isButton)
        // For UI tests: which rows are checked is otherwise only in the spoken text.
        .accessibilityIdentifier(item.measured.isVerified ? "room.dimension.verified" : "room.dimension.scanned")
    }
}

/// One corner: which walls meet, the angle, and how far from square. Off square is shown with a glyph and the
/// number, never colour alone.
private struct CornerRow: View {
    let reading: CornerReading
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        layout {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: reading.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    if reading.level != .square {
                        Image(systemName: glyph)
                            .font(.footnote)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: reading.note)
                        .font(.footnote.weight(reading.isOffSquare ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(reading.isOffSquare ? tint : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            MeasurementText(angle: reading.angle, style: .body)
                .numberColor(reading.isOffSquare ? tint : Palette.ink)
        }
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.spoken)
    }

    private var tint: Color {
        switch reading.level {
        case .outOfSquare: return Palette.critical
        case .slightlyOff: return Palette.caution
        case .square, .reflex, .straight: return Palette.muted
        }
    }

    private var glyph: String {
        switch reading.level {
        case .outOfSquare, .slightlyOff: return "exclamationmark.triangle.fill"
        case .reflex, .straight: return "info.circle"
        case .square: return "checkmark.circle"
        }
    }
}

/// A piece of furniture or a fixture the scan recognised. Sizes are scanned and cannot be checked here.
private struct ObjectRow: View {
    let title: String
    let object: RoomObject
    let units: DisplayUnits
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        layout {
            Text(verbatim: title)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            Text(verbatim: GroupedLength.dimensions(object.width, object.depth, unit: units.length, precision: .compact)
                 + " \u{00B7} " + GroupedLength.text(object.height, unit: units.length, precision: .compact) + " high")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(SpokenMeasurement.length(object.width, unit: units.length) + " by "
                            + SpokenMeasurement.length(object.depth, unit: units.length) + ", "
                            + SpokenMeasurement.length(object.height, unit: units.length) + " high, scanned")
    }
}

#if DEBUG
#Preview("Room") {
    let demo = DemoProperty.make()
    NavigationStack { RoomView(propertyID: demo.id, roomID: demo.allRooms[0].id) }
        .environment(AppModel.preview())
        .environment(AppRouter())
}
#endif
