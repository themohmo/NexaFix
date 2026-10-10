import SwiftUI
import NexaFixCore

/// One property: its plan, its rooms, its 3D model and the three things to do next (scan, review in AR,
/// export). A property can hold several levels, and each level is one scan with its own plan.
@MainActor
struct PropertyView: View {
    let propertyID: UUID

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var tab: PropertyTab = .plan
    @State private var tabBeforeModel: PropertyTab = .plan
    @State private var floorID: UUID?
    @State private var selection: PlanSelection?
    @State private var sheet: PropertySheet?
    @State private var cover: FloorViewerRequest?
    @State private var pendingScanStory: Int?
    @State private var confirmation: Confirmation?
    @State private var renaming: RoomTarget?
    @State private var renameText = ""
    @State private var drawingCache = PlanDrawingCache()
    /// The cube on the 3D tab grows with the text size, like the words under it.
    @ScaledMetric(relativeTo: .largeTitle) private var cubeSize: CGFloat = 44
    /// Set just before the property is deleted, so this screen stops reading it while it slides away.
    @State private var isRemoved = false

    // MARK: Local types

    private enum PropertyTab: String, CaseIterable, Identifiable {
        case plan, rooms, model3D
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plan: return "Plan"
            case .rooms: return "Rooms"
            case .model3D: return "3D"
            }
        }
    }

    /// A dimension to check, as asked for by the plan or the Room screen.
    private struct VerifyRequest: Equatable {
        let roomID: UUID
        let target: MeasureTarget
    }

    private enum PropertySheet: Identifiable {
        case verify(VerifyRequest)
        case export
        case addScan
        case details

        var id: String {
            switch self {
            case .verify(let request): return "verify-\(request.roomID.uuidString)-\(request.target)"
            case .export: return "export"
            case .addScan: return "addScan"
            case .details: return "details"
            }
        }
    }

    private struct RoomTarget: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    private enum Confirmation: Identifiable {
        case deleteProperty
        case deleteRoom(RoomTarget)

        var id: String {
            switch self {
            case .deleteProperty: return "property"
            case .deleteRoom(let room): return "room-\(room.id.uuidString)"
            }
        }
    }

    // MARK: Body

    var body: some View {
        Group {
            if isRemoved {
                Color.clear
            } else if let property = model.property(propertyID) {
                screen(property)
            } else {
                unavailable
            }
        }
        .screenBackground()
    }

    private var unavailable: some View {
        VStack(spacing: Spacing.l) {
            Text(verbatim: "This property is no longer available.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button { router.path.removeAll() } label: { Text(verbatim: "Back to properties") }
                .buttonStyle(.secondary)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBanners()
    }

    @MainActor @ViewBuilder
    private func screen(_ property: Property) -> some View {
        let floor = property.activeFloor(preferring: floorID)
        let units = model.settings.units
        VStack(spacing: 0) {
            if property.roomCount == 0 {
                header(property)
                EmptyStateView(
                    title: "No rooms yet",
                    message: "Scan the first room. Every scan becomes its own level, so floors never mix.",
                    primaryTitle: "Scan a room",
                    primaryAction: { sheet = .addScan })
            } else {
                header(property)
                tabPicker
                floorChips(property, active: floor)
                tabContent(property, floor: floor, units: units)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if property.roomCount > 0 { actionBar(floor: floor) }
        }
        .statusBanners()
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu(property) }
        .sheet(item: $sheet, onDismiss: sheetDidDismiss) { item in
            sheetContent(item, property: property, floor: floor, units: units)
        }
        .fullScreenCover(item: $cover, onDismiss: coverDidDismiss) { item in
            FloorCover(propertyID: propertyID, cover: item) { cover = nil }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible,
                            presenting: confirmation) { item in
            confirmationButtons(item)
        } message: { item in
            Text(verbatim: confirmationMessage(item))
        }
        .alert("Rename room", isPresented: renameBinding, presenting: renaming) { target in
            TextField("Name", text: $renameText)
            Button("Rename") { rename(target) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(verbatim: "Room names are unique on a level.")
        }
        .onChange(of: property.floors.map(\.id)) { old, new in
            // A scan that was just added shows up straight away.
            if let added = new.last(where: { !old.contains($0) }) {
                floorID = added
                selection = nil
            }
        }
        .onChange(of: tab) { old, new in
            if new == .model3D {
                tabBeforeModel = old
                openModel(floor: floor)
            } else {
                selection = nil
            }
        }
    }

    // MARK: Header

    private func header(_ property: Property) -> some View {
        let progress = VerificationChecklist.propertyProgress(property)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.m))
        return layout {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if !property.client.isEmpty {
                    Text(verbatim: property.client)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                }
                if !property.address.isEmpty {
                    Text(verbatim: property.address)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                Text(verbatim: headerDetail(property))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            VerificationProgress(verified: progress.verified, total: progress.total)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerDetail(_ property: Property) -> String {
        [property.reference, property.kind.displayName].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private var tabPicker: some View {
        Picker("View", selection: $tab) {
            ForEach(PropertyTab.allCases) { Text(verbatim: $0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
    }

    // MARK: Levels

    @ViewBuilder
    private func floorChips(_ property: Property, active: Floor?) -> some View {
        let chips = FloorChip.chips(for: property)
        if chips.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.s) {
                    ForEach(chips) { chip in
                        FloorChipButton(chip: chip, isSelected: chip.id == active?.id) {
                            floorID = chip.id
                            selection = nil
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: Tabs

    @MainActor @ViewBuilder
    private func tabContent(_ property: Property, floor: Floor?, units: DisplayUnits) -> some View {
        switch tab {
        case .plan: planTab(property, floor: floor, units: units)
        case .rooms: roomsTab(property, floor: floor, units: units)
        case .model3D: modelTab(floor: floor)
        }
    }

    // MARK: Plan

    @MainActor @ViewBuilder
    private func planTab(_ property: Property, floor: Floor?, units: DisplayUnits) -> some View {
        if let floor, !floor.rooms.isEmpty {
            ZStack(alignment: .bottom) {
                PlanCanvasView(rooms: floor.rooms,
                               drawing: drawingCache.drawing(for: floor, in: property, units: units),
                               units: units,
                               selection: $selection,
                               hapticsEnabled: model.settings.hapticsEnabled)
                    .id(floor.id)
                if let selection, let info = SelectionCardInfo.make(selection: selection, in: property) {
                    SelectionCard(info: info, units: units,
                                  onVerify: { target in sheet = .verify(VerifyRequest(roomID: info.roomID, target: target)) },
                                  onOpenRoom: { openRoom(info.roomID) },
                                  onClose: { self.selection = nil })
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.s)
                        .transition(.sheetRise)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motion(value: selection != nil)
        } else {
            noRoomsOnLevel
        }
    }

    private var noRoomsOnLevel: some View {
        Text(verbatim: "There are no rooms on this level yet.")
            .font(.body)
            .foregroundStyle(Palette.muted)
            .multilineTextAlignment(.center)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Rooms

    @MainActor @ViewBuilder
    private func roomsTab(_ property: Property, floor: Floor?, units: DisplayUnits) -> some View {
        if let floor, !floor.rooms.isEmpty {
            ScrollView {
                LazyVStack(spacing: Spacing.m) {
                    ForEach(floor.rooms) { room in
                        let info = RoomRowInfo.make(room, units: units)
                        RoomListRow(info: info, units: units, onOpen: { openRoom(room.id) })
                            .contextMenu { roomMenu(room) }
                            .accessibilityAction(named: "Rename") { startRename(room) }
                            .accessibilityAction(named: "Delete") { confirmation = .deleteRoom(RoomTarget(id: room.id, name: info.name)) }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        } else {
            noRoomsOnLevel
        }
    }

    @ViewBuilder
    private func roomMenu(_ room: Room) -> some View {
        Button { startRename(room) } label: { Label("Rename", systemImage: "pencil") }
        Menu {
            ForEach(RoomKind.allCases, id: \.self) { kind in
                Button {
                    PropertyActions(model: model).setRoomKind(propertyID: propertyID, roomID: room.id, to: kind)
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
        Button(role: .destructive) {
            confirmation = .deleteRoom(RoomTarget(id: room.id, name: SelectionCardInfo.roomTitle(room)))
        } label: {
            Label("Delete room", systemImage: "trash")
        }
    }

    // MARK: 3D

    @MainActor @ViewBuilder
    private func modelTab(floor: Floor?) -> some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "cube")
                .font(.system(size: cubeSize, weight: .light))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(verbatim: "Look around the scanned level, measure between any two points and save the result to the room.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if let floor, !floor.rooms.isEmpty {
                Button { openModel(floor: floor) } label: { Text(verbatim: "Open 3D view") }
                    .buttonStyle(.primary)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bar

    @ViewBuilder
    private func actionBar(floor: Floor?) -> some View {
        let hasRooms = !(floor?.rooms.isEmpty ?? true)
        Group {
            if typeSize.isAccessibilitySize {
                // Three stacked buttons at these sizes would cover most of the plan; one menu does not.
                Menu {
                    Button { sheet = .addScan } label: { Label("Add scan", systemImage: "viewfinder") }
                    Button { openAR(floor: floor) } label: { Label("Review in AR", systemImage: "arkit") }
                        .disabled(!hasRooms)
                    Button { sheet = .export } label: { Label("Export", systemImage: "square.and.arrow.up") }
                } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityHidden(true)
                        Text(verbatim: "Scan, AR, export")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Scan, review in AR or export")
            } else {
                HStack(spacing: Spacing.xs) {
                    BarButton(title: "Add scan", systemImage: "viewfinder") { sheet = .addScan }
                    BarButton(title: "AR", systemImage: "arkit") { openAR(floor: floor) }
                        .disabled(!hasRooms)
                    BarButton(title: "Export", systemImage: "square.and.arrow.up") { sheet = .export }
                }
            }
        }
        .padding(Spacing.xs)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .frame(maxWidth: 520)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
        .padding(.top, Spacing.xs)
        .frame(maxWidth: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarMenu(_ property: Property) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .details } label: { Label("Edit details", systemImage: "pencil") }
                Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { confirmation = .deleteProperty } label: {
                    Label("Delete property", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: Sheets and covers

    @MainActor @ViewBuilder
    private func sheetContent(_ item: PropertySheet, property: Property, floor: Floor?, units: DisplayUnits) -> some View {
        switch item {
        case .verify(let request):
            if let room = property.findRoom(request.roomID) {
                VerifySheet(propertyID: property.id, room: room, target: request.target, units: units)
            } else {
                Text(verbatim: "This room is no longer in the property.")
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .padding(Spacing.xl)
            }
        case .export:
            ExportSheet(propertyID: property.id, settings: model.settings)
        case .addScan:
            AddScanSheet(propertyName: property.name,
                         initialStory: PropertyDefaults.nextStory(in: property, preferring: floor?.id)) { story in
                pendingScanStory = story
            }
        case .details:
            NewPropertySheet(mode: .edit(property))
        }
    }

    /// The camera opens only once the sheet that asked for it has gone.
    private func sheetDidDismiss() {
        guard let story = pendingScanStory else { return }
        pendingScanStory = nil
        router.startScan(propertyID: propertyID, story: story)
    }

    private func coverDidDismiss() {
        if tab == .model3D { tab = tabBeforeModel }
    }

    private func openModel(floor: Floor?) {
        guard let floor, !floor.rooms.isEmpty else { return }
        cover = FloorViewerRequest(kind: .viewer3D, floorID: floor.id, focusRoomID: selection?.roomID)
    }

    private func openAR(floor: Floor?) {
        guard let floor, !floor.rooms.isEmpty else { return }
        cover = FloorViewerRequest(kind: .ar, floorID: floor.id, focusRoomID: selection?.roomID)
    }

    private func openRoom(_ roomID: UUID) {
        router.path.append(.room(property: propertyID, room: roomID))
    }

    // MARK: Rooms: rename, delete

    private func startRename(_ room: Room) {
        renameText = room.name
        renaming = RoomTarget(id: room.id, name: room.name)
    }

    private func rename(_ target: RoomTarget) {
        PropertyActions(model: model).renameRoom(propertyID: propertyID, roomID: target.id, to: renameText)
        renaming = nil
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { shown in if !shown { renaming = nil } })
    }

    // MARK: Property: duplicate, delete

    private func duplicate() {
        if let copy = PropertyActions(model: model).duplicate(propertyID) {
            router.open(copy.id)
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { shown in if !shown { confirmation = nil } })
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .deleteProperty?:
            let name = model.property(propertyID)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Delete this property?" : "Delete \u{201C}\(name)\u{201D}?"
        case .deleteRoom(let room)?:
            return "Delete \u{201C}\(room.name)\u{201D}?"
        case nil:
            return ""
        }
    }

    private func confirmationMessage(_ item: Confirmation) -> String {
        switch item {
        case .deleteProperty:
            return "This removes its rooms, scans and files from this device. It can\u{2019}t be undone."
        case .deleteRoom:
            return "The room and its checks are removed from this level. It can\u{2019}t be undone."
        }
    }

    @ViewBuilder
    private func confirmationButtons(_ item: Confirmation) -> some View {
        switch item {
        case .deleteProperty:
            Button("Delete property", role: .destructive) {
                // Leave first: reading a property that has just been deleted would report it as unreadable.
                isRemoved = true
                router.path.removeAll()
                PropertyActions(model: model).delete(propertyID)
            }
        case .deleteRoom(let room):
            Button("Delete room", role: .destructive) {
                PropertyActions(model: model).deleteRoom(propertyID: propertyID, roomID: room.id)
                selection = nil
            }
        }
        Button("Cancel", role: .cancel) {}
    }
}

// MARK: - Full-screen viewers

/// Which full-screen viewer to open, for which level, looking at which room first.
private struct FloorViewerRequest: Identifiable, Equatable {
    enum Kind: Equatable { case viewer3D, ar }
    let kind: Kind
    let floorID: UUID
    let focusRoomID: UUID?
    var id: String { "\(kind)-\(floorID.uuidString)" }
}

/// The 3D viewer or the AR review for one level. It reads the property itself, so a measurement that was just
/// saved reaches the screen without closing it.
@MainActor
private struct FloorCover: View {
    let propertyID: UUID
    let cover: FloorViewerRequest
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    /// A measurement that could not be written. Shown here, in the cover, because the app's own alert sits
    /// under a full-screen cover and may not appear until it closes.
    @State private var saveError: UserFacingError?

    var body: some View {
        if let property = model.property(propertyID),
           let floor = property.floors.first(where: { $0.id == cover.floorID }) {
            viewer(floor: floor)
                .alert(saveError?.title ?? "", isPresented: saveErrorBinding, presenting: saveError) { _ in
                    Button("Try again") { model.retryUnsavedSaves() }
                    Button("OK", role: .cancel) {}
                } message: { error in
                    Text(verbatim: RootView.alertMessage(for: error))
                }
        } else {
            // The level went away while the viewer was opening.
            Palette.background
                .ignoresSafeArea()
                .onAppear { onClose() }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { shown in if !shown { saveError = nil } })
    }

    @MainActor @ViewBuilder
    private func viewer(floor: Floor) -> some View {
        let settings = model.settings
        switch cover.kind {
        case .viewer3D:
            Viewer3DView(floor: floor, units: settings.units, hapticsEnabled: settings.hapticsEnabled,
                         focusRoomID: cover.focusRoomID,
                         onSaveMeasurement: { measurement, roomID in save(measurement, roomID: roomID) },
                         onClose: onClose)
        case .ar:
            ARReviewView(rooms: floor.rooms, focusRoomID: cover.focusRoomID,
                         worldMapURL: floor.assets.worldMap.flatMap {
                             model.assetURL(relativePath: $0, propertyID: propertyID)
                         },
                         units: settings.units, hapticsEnabled: settings.hapticsEnabled,
                         onSaveMeasurement: { measurement, roomID in save(measurement, roomID: roomID) },
                         onClose: onClose)
        }
    }

    private func save(_ measurement: CustomMeasurement, roomID: UUID) {
        let saved = PropertyActions(model: model).addMeasurement(measurement, propertyID: propertyID, roomID: roomID)
        // The measurement stays in the app either way. When it could not be written, the person is told here,
        // and the unsaved-work banner on the property screen stays until a save works.
        if !saved, let error = model.presentedError, error.severity == .dataAtRisk {
            model.presentedError = nil
            saveError = error
        }
    }
}

// MARK: - Pieces

/// One level in the row of levels, with the day it was scanned.
private struct FloorChipButton: View {
    let chip: FloorChip
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(verbatim: chip.title)
                    .font(.subheadline.weight(.semibold))
                if let date = chip.scannedAt {
                    Text(verbatim: date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2)
                }
            }
            .foregroundStyle(isSelected ? Palette.accentContrast : Palette.ink)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .background { Capsule(style: .continuous).fill(isSelected ? Palette.accent : Palette.surface) }
            .overlay {
                if !isSelected {
                    Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        guard let date = chip.scannedAt else { return chip.title }
        return "\(chip.title), scanned \(date.formatted(.dateTime.day().month(.wide)))"
    }
}

/// An icon above a word, inside the floating bar. Plain: the bar itself is the glass.
private struct BarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
    }
}

/// One room in the Rooms tab.
private struct RoomListRow: View {
    let info: RoomRowInfo
    let units: DisplayUnits
    let onOpen: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: info.name)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: info.line(units: units))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    VerificationProgress(verified: info.summary.verified, total: info.summary.total)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.l)
            .frame(minHeight: 44)
            .background { shape.fill(Palette.surface) }
            .overlay { shape.strokeBorder(Palette.line, lineWidth: Hairline.adaptive(contrast)) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spoken(units: units))
        .accessibilityHint("Opens the room.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Selection card

/// The card that rises from the bottom of the plan when a wall, corner, opening, object or room is tapped:
/// its value, where that value came from, and **Verify**. Glass, because it floats over the drawing.
private struct SelectionCard: View {
    let info: SelectionCardInfo
    let units: DisplayUnits
    let onVerify: (MeasureTarget) -> Void
    let onOpenRoom: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            titleRow
            content
        }
        .padding(Spacing.l)
        .frame(maxWidth: 560, alignment: .leading)
        .glass(cornerRadius: Radius.card, prominence: .regular)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: info.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: info.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch info.kind {
        case .corner:
            if let corner = info.corner { cornerContent(corner) }
        case .object:
            if let size = info.objectSize { objectContent(size) }
        case .room:
            roomContent
        case .wall, .opening:
            rowsContent
        }
    }

    private var rowsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(info.rows) { row in
                CardRow(row: row, subject: info.title, units: units) { onVerify(row.target) }
            }
        }
    }

    private var roomContent: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let area = info.areaM2 {
                MeasurementText(area: area, units: units, style: .title)
            }
            rowsContent
            Button(action: onOpenRoom) {
                Text(verbatim: "Open room")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background { Capsule(style: .continuous).fill(Palette.ink.opacity(0.08)) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.pressable)
        }
    }

    private func cornerContent(_ corner: CornerReading) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            MeasurementText(angle: corner.angle, style: .title)
                .numberColor(cornerColor(corner))
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Image(systemName: corner.isOffSquare ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(cornerColor(corner))
                    .accessibilityHidden(true)
                Text(verbatim: corner.note)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: "Angles come from the scan and are not checked on site.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(corner.spoken)
    }

    private func cornerColor(_ corner: CornerReading) -> Color {
        switch corner.level {
        case .outOfSquare: return Palette.critical
        case .slightlyOff: return Palette.caution
        case .square, .reflex, .straight: return Palette.ink
        }
    }

    private func objectContent(_ size: SelectionCardInfo.ObjectSize) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: GroupedLength.dimensions(size.width, size.depth, unit: units.length, precision: .compact)
                 + " \u{00B7} " + GroupedLength.text(size.height, unit: units.length, precision: .compact) + " high")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "Scanned. Furniture sizes are not checked on site.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One checkable value on the card: what it is, the number, where it came from, and the button.
private struct CardRow: View {
    let row: SelectionCardInfo.Row
    /// What the row belongs to: "Wall A", "Door 1", the room's name.
    let subject: String
    let units: DisplayUnits
    let onVerify: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        layout {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: row.label)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                MeasurementText(length: row.measured.value, units: units, style: .title)
                ProvenanceBadge(row.measured, units: units)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(subject) \(row.label.lowercased())")
            .accessibilityValue(spokenValue)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            Button(action: onVerify) {
                Text(verbatim: row.measured.isVerified ? "Edit" : "Verify")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accentContrast)
                    .padding(.horizontal, Spacing.l)
                    .frame(minWidth: 44, minHeight: 44)
                    .background { Capsule(style: .continuous).fill(Palette.accent) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(row.measured.isVerified ? "Edit check of \(subject) \(row.label.lowercased())"
                                : "Verify \(subject) \(row.label.lowercased())")
        }
    }

    private var spokenValue: String {
        MeasurementParts.length(row.measured.value, units: units).spoken + ", "
            + SpokenMeasurement.midSentence(ProvenanceDescription(row.measured, units: units, compact: false).spoken)
    }
}

#if DEBUG
#Preview("Property") {
    NavigationStack { PropertyView(propertyID: DemoProperty.make().id) }
        .environment(AppModel.preview())
        .environment(AppRouter())
}
#endif
