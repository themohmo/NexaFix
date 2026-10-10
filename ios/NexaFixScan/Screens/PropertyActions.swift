import Foundation
import Observation
import NexaFixCore

// Everything the screens do to a property that is not drawing: duplicate, rename, delete, change a
// room, record a check, take in a finished scan (or an unfinished one found again after a restart), and the
// plain numbers and words the screens show.
// Plain Swift on Foundation, NexaFixCore and the app's own plain-Swift types, so it is type-checked on
// Linux. The views stay thin and call these.
//
// Every change to a saved property goes through `AppModel.update`, so a failed save is never silent and
// unsaved changes stay listed until they are written. Nothing derived is ever stored.

// MARK: - Actions on properties and rooms

@MainActor
struct PropertyActions {
    let model: AppModel

    // MARK: Properties

    /// Copies a property, its rooms and its files under new ids ("Marina copy"). Returns the copy, or nil
    /// after showing an error.
    @discardableResult
    func duplicate(_ id: UUID) -> Property? {
        guard let current = model.property(id) else { return nil }
        // The copy is made from what is on disk, so anything only in memory is saved first.
        if model.unsavedPropertyIDs.contains(id), !model.save(current) { return nil }
        do {
            let copy = try model.store.duplicate(id: id)
            model.refresh()
            return copy
        } catch {
            report(error, context: "duplicate \(displayName(of: current))")
            return nil
        }
    }

    /// Gives a property a new name. A blank name is ignored.
    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.update(propertyID: id) { $0.name = clean }
    }

    /// Changes the details shown on the header and in every export. Blank client, address and reference are
    /// allowed; a blank name is ignored.
    func updateDetails(_ id: UUID, name: String, client: String, address: String, reference: String,
                       kind: PropertyKind) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        model.update(propertyID: id) { property in
            if !clean.isEmpty { property.name = clean }
            property.client = client
            property.address = address
            property.reference = reference
            property.kind = kind
        }
    }

    /// Deletes a property and its files. The caller has already asked the person.
    func delete(_ id: UUID) {
        model.delete(id)
    }

    // MARK: Rooms

    func renameRoom(propertyID: UUID, roomID: UUID, to name: String) {
        model.update(propertyID: propertyID) { $0.renameRoom(id: roomID, to: name) }
    }

    func setRoomKind(propertyID: UUID, roomID: UUID, to kind: RoomKind) {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.kind = kind }
        }
    }

    /// Deletes a room (a floor left with no rooms goes with it). The caller has already asked the person.
    func deleteRoom(propertyID: UUID, roomID: UUID) {
        model.update(propertyID: propertyID) { $0.deleteRoom(id: roomID) }
    }

    func setNotes(propertyID: UUID, roomID: UUID, to notes: String) {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.notes = notes }
        }
    }

    // MARK: Checks and measurements

    /// Whether the dimension is still in the room, so a sheet that has been open a while does not save a
    /// check for something that has gone.
    func targetExists(propertyID: UUID, roomID: UUID, target: MeasureTarget) -> Bool {
        model.property(propertyID)?.findRoom(roomID)?.measured(target) != nil
    }

    /// Records a site check for one dimension, or clears it with nil. Applied to the room as it is now, so
    /// nothing else in the room changes. Returns whether the change reached storage.
    @discardableResult
    func saveVerification(propertyID: UUID, roomID: UUID, target: MeasureTarget,
                          verification: Verification?) -> Bool {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { $0.setVerification(verification, for: target) }
        }
    }

    /// Adds a measurement taken in AR or in the 3D viewer to the room it belongs to.
    @discardableResult
    func addMeasurement(_ measurement: CustomMeasurement, propertyID: UUID, roomID: UUID) -> Bool {
        model.update(propertyID: propertyID) { property in
            property.modifyRoom(id: roomID) { room in
                guard !room.customMeasurements.contains(where: { $0.id == measurement.id }) else { return }
                room.customMeasurements.append(measurement)
            }
        }
    }

    // MARK: Errors

    /// Shows a lesser error unless the person still has an unacknowledged "your work is not saved" alert.
    private func report(_ error: Error, context: String) {
        if model.presentedError?.severity == .dataAtRisk { return }
        model.presentedError = UserFacingError(error, context: context)
    }

    private func displayName(of property: Property) -> String {
        let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "this property" : "\u{201C}\(name)\u{201D}"
    }
}

// MARK: - Taking in a finished scan

/// Saves what the scan screen hands back: the files first, then the property with its new floor.
@MainActor
enum ScanIntake {

    /// What happened, in words for the person.
    struct Outcome {
        /// "Added 5 rooms to Level 23."
        var summary: String
        /// Things to tell the person: the scan screen's own warnings, and files that could not be saved.
        var warnings: [String]
        var floorID: UUID?
        /// The property with the new floor reached storage.
        var saved: Bool
        /// Nothing was added because the property already holds every room of the scan (the same scan was
        /// applied before). `saved` is false then, since nothing was written now.
        var roomsAlreadyInProperty = false
    }

    /// One file to write, with its bytes. Plain values, so the writing can happen off the main thread.
    private struct FileJob: Sendable {
        let asset: ScanCommit.PlannedAsset
        let data: Data?
    }

    /// Adds the scan to the property as a new floor.
    ///
    /// The order matters: files are written first, and the property only mentions files that were written.
    /// A room is never lost because a file failed (the failure is reported in `Outcome.warnings` and the room
    /// is kept without that file). Applying the same result twice adds nothing the second time.
    ///
    /// A whole-floor model is tens of megabytes, so the files are written on a background task; only the
    /// planning and the final save run on the main actor. A failed file is a warning in the outcome, never the
    /// "your work is not saved" alert: the rooms are saved, and no retry of the alert could bring the file back.
    static func commit(_ result: ScanResult, to propertyID: UUID, model: AppModel,
                       now: Date = Date()) async -> Outcome {
        guard let property = model.property(propertyID) else {
            return Outcome(summary: "The scan could not be added because the property could not be opened.",
                           warnings: result.warnings, floorID: nil, saved: false)
        }

        let available = ScanCommit.AvailableAssets(
            structureUSDZ: !(result.structureUSDZ?.isEmpty ?? true),
            worldMap: !(result.worldMapData?.isEmpty ?? true),
            capturedRoomIDs: Set(result.rooms.map(\.id).filter { !(result.capturedRoomJSON[$0]?.isEmpty ?? true) }))
        let plan = ScanCommit.apply(rooms: result.rooms, story: result.story, scannedAt: now, to: property,
                                    available: available)
        guard let floorID = plan.floorID else {
            return Outcome(summary: plan.summary, warnings: result.warnings, floorID: nil, saved: false,
                           roomsAlreadyInProperty: !plan.skippedRoomIDs.isEmpty)
        }

        // Files first, off the main thread.
        let jobs = plan.assets.map { asset -> FileJob in
            switch asset.kind {
            case .structureUSDZ: return FileJob(asset: asset, data: result.structureUSDZ)
            case .worldMap: return FileJob(asset: asset, data: result.worldMapData)
            case .capturedRoom(let roomID): return FileJob(asset: asset, data: result.capturedRoomJSON[roomID])
            }
        }
        let store = model.store
        let wrote = await Task.detached(priority: .userInitiated) { () -> [Bool] in
            jobs.map { write($0, to: store, propertyID: propertyID) }
        }.value

        var written = ScanCommit.AvailableAssets()
        var warnings = result.warnings
        for (job, ok) in zip(jobs, wrote) {
            guard ok else {
                warnings.append(failureWarning(for: job.asset.kind))
                continue
            }
            switch job.asset.kind {
            case .structureUSDZ: written.structureUSDZ = true
            case .worldMap: written.worldMap = true
            case .capturedRoom(let roomID): written.capturedRoomIDs.insert(roomID)
            }
        }

        // Then the property, applied to its latest copy so edits made meanwhile are kept. The same floor id
        // makes the result identical to the plan.
        let rooms = result.rooms
        let story = result.story
        let writtenFiles = written
        let saved = model.update(propertyID: propertyID) { live in
            live = ScanCommit.apply(rooms: rooms, story: story, scannedAt: now, to: live, available: writtenFiles,
                                    makeID: { floorID }).property
        }
        return Outcome(summary: plan.summary, warnings: warnings, floorID: floorID, saved: saved)
    }

    /// Writes one file; false when there were no bytes or the write failed.
    private nonisolated static func write(_ job: FileJob, to store: PropertyStore, propertyID: UUID) -> Bool {
        guard let data = job.data, !data.isEmpty else { return false }
        do {
            try store.writeAsset(data, relativePath: job.asset.relativePath, for: propertyID)
            return true
        } catch {
            return false
        }
    }

    private static func failureWarning(for kind: ScanCommit.PlannedAsset.Kind) -> String {
        let advice = "Free up some space on this iPhone, then scan the level again."
        switch kind {
        case .structureUSDZ:
            return "The 3D model could not be saved, so this level cannot be exported as a model. The rooms were kept. " + advice
        case .worldMap:
            return "The AR map could not be saved, so AR review will not line up on this level. The rooms were kept. " + advice
        case .capturedRoom:
            return "One room\u{2019}s detailed scan data could not be saved. The room itself was kept."
        }
    }
}

// MARK: - Unfinished scans found at launch

/// One unfinished scan found on disk (`ScanRecoveryStore`) and the words the recovery sheet uses for it. Plain
/// values, so the wording and the choices are checked on Linux.
struct ScanRecoveryPrompt: Equatable, Identifiable {
    let scan: ScanRecoveryStore.RecoverableScan
    /// The property the rooms go back into. nil when it is no longer on this iPhone: recovering then makes a new
    /// property with the old name.
    var propertyID: UUID?
    /// The property's name now, or the name it had when the scan began if it is gone or has no name.
    let propertyName: String

    var id: UUID { scan.scanID }

    /// Prompts for `scans`, newest first. `currentName` gives the name of a property that is on this iPhone (an
    /// empty string when it cannot be read) and nil for one that is not.
    static func prompts(for scans: [ScanRecoveryStore.RecoverableScan],
                        currentName: (UUID) -> String?) -> [ScanRecoveryPrompt] {
        scans.sorted { $0.updatedAt > $1.updatedAt }.map { scan in
            let current = scan.propertyID.flatMap(currentName)
            let name = trimmed(current ?? "")
            return ScanRecoveryPrompt(scan: scan,
                                      propertyID: current == nil ? nil : scan.propertyID,
                                      propertyName: name.isEmpty ? trimmed(scan.propertyName) : name)
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Words

    static let sheetTitle = "Recover a scan"
    static let recoverTitle = "Recover rooms"
    static let retryTitle = "Try again"
    static let discardTitle = "Discard"
    static let notNowTitle = "Not now"
    static let keepTitle = "Keep it"
    static let workingTitle = "Recovering rooms"
    static let workingDetail = "Rebuilding each room from the saved scan. This can take a moment."
    /// What a recovered level never has, said before the person chooses so nobody expects it.
    static let limits = "The 3D model and the AR map cannot be recovered. Scan the level again on site to get them."
    /// Said when the person leaves the prompt with the copy kept.
    static let keptNote = "Not now keeps it on this iPhone, and the app asks again next time it opens."

    var roomCountText: String { scan.roomCount == 1 ? "1 room" : "\(scan.roomCount) rooms" }

    /// "Level 1": the name the recovered rooms get in the property.
    var levelName: String { ScanCommit.levelName(scan.story) }

    /// True when the property is gone and Recover rooms makes a new one.
    var willCreateProperty: Bool { propertyID == nil }

    /// The property name in curly quotes, or "this property" when it has none.
    var quotedName: String { propertyName.isEmpty ? "this property" : "\u{201C}\(propertyName)\u{201D}" }

    /// "9 Oct, 14:32": when the last room of the scan was saved.
    func dateText(timeZone: TimeZone = .current) -> String {
        ScanRecoveryPrompt.dateText(scan.updatedAt, timeZone: timeZone)
    }

    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    /// "Unfinished scan found: 3 rooms from 9 Oct, 14:32 (Marina Gate 2)."
    func headline(timeZone: TimeZone = .current) -> String {
        var text = "Unfinished scan found: \(roomCountText) from \(dateText(timeZone: timeZone))"
        if !propertyName.isEmpty { text += " (\(propertyName))" }
        return text + "."
    }

    /// What happened, and what Recover rooms does with the rooms.
    var explanation: String {
        if willCreateProperty {
            let which = propertyName.isEmpty ? "The property this scan belonged to" : quotedName
            let made = propertyName.isEmpty ? "a new property" : "a new property with that name"
            return "\(which) is no longer on this iPhone. Recover rooms makes \(made) and adds the rooms to it as \(levelName)."
        }
        if scan.delivered {
            return "The app closed while this level was being saved, so it may be saved already. If its rooms are not in \(quotedName) yet, Recover rooms adds them as \(levelName). Rooms that are already saved are not added twice."
        }
        return "The app closed before this level was finished, so its rooms were never added to \(quotedName). Recover rooms adds them as \(levelName)."
    }

    var discardConfirmationTitle: String { "Discard this scan?" }

    var discardConfirmationMessage: String {
        "The \(roomCountText) from \(dateText()) will be deleted from this iPhone. This cannot be undone."
    }

    var discardConfirmationButton: String {
        scan.roomCount == 1 ? "Discard 1 room" : "Discard \(scan.roomCount) rooms"
    }
}

/// Finds unfinished scans when the app starts and puts them back when the person asks. It holds no views: the
/// recovery sheet reads `phase` and calls the actions, one scan at a time, newest first.
///
/// The copy of a scan (`ScanRecoveryStore`) is only deleted once the rooms are really in the property on disk
/// (or were already there), or the person chose to discard it. Every other end keeps it and says what to do.
@MainActor
@Observable
final class ScanRecoveryCoordinator {

    /// What went wrong, in two parts: what happened and what to do. The copy is always still there.
    struct Failure: Equatable {
        let message: String
        let recovery: String
    }

    /// What a recovery achieved.
    struct Report: Equatable {
        /// "Added 3 rooms to Level 1."
        let summary: String
        /// Including that the recovered level has no 3D model and no AR map.
        let warnings: [String]
        let propertyID: UUID
    }

    enum Phase: Equatable {
        /// Nothing to show.
        case idle
        /// Offering the scan on screen.
        case asking(ScanRecoveryPrompt)
        /// Rebuilding the rooms and saving them.
        case working(ScanRecoveryPrompt)
        /// The rooms are in the property and the copy is gone.
        case done(ScanRecoveryPrompt, Report)
        /// Something did not work; the copy is kept.
        case failed(ScanRecoveryPrompt, Failure)

        /// The scan the phase is about.
        var promptID: UUID? {
            switch self {
            case .idle: return nil
            case .asking(let prompt), .working(let prompt), .done(let prompt, _), .failed(let prompt, _):
                return prompt.id
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// Unfinished scans after the one on screen, newest first.
    private(set) var waiting: [ScanRecoveryPrompt] = []

    @ObservationIgnored private let root: URL
    @ObservationIgnored private var hasLooked = false

    /// - Parameter root: Where the scan copies are (tests pass a temporary folder).
    init(root: URL = ScanRecoveryStore.defaultRoot) {
        self.root = root
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    // MARK: Finding

    /// Looks for unfinished scans, once. Dropping copies that are too old and reading the rest happen off the
    /// main thread. If there are any, `phase` becomes `.asking` for the newest.
    func look(model: AppModel) async {
        guard !hasLooked else { return }
        hasLooked = true
        let root = self.root
        let found = await Task.detached(priority: .utility) { () -> [ScanRecoveryStore.RecoverableScan] in
            ScanRecoveryStore.prune(root: root)
            return ScanRecoveryStore.recoverableScans(root: root)
        }.value
        guard phase == .idle else { return }
        let prompts = ScanRecoveryPrompt.prompts(for: found) { ScanRecoveryCoordinator.currentName(of: $0, in: model) }
        guard let first = prompts.first else { return }
        waiting = Array(prompts.dropFirst())
        phase = .asking(first)
    }

    /// The name of a property that is on this iPhone (empty when it cannot be read), or nil when it is not.
    /// Looks at the list only: `AppModel.property(_:)` reports an error for a property that is gone.
    private static func currentName(of id: UUID, in model: AppModel) -> String? {
        if let summary = model.summaries.first(where: { $0.id == id }) {
            return summary.health == .unreadable ? "" : summary.name
        }
        return model.memoryOnlyProperties.first { $0.id == id }?.name
    }

    // MARK: Choosing

    /// Recover rooms (or Try again): rebuilds the rooms off the main thread, adds them to the property they belong
    /// to (a new one if that is gone) and, only if that reached storage, deletes the copy.
    func recover(model: AppModel, now: Date = Date()) async {
        let offered: ScanRecoveryPrompt
        switch phase {
        case .asking(let prompt), .failed(let prompt, _): offered = prompt
        case .idle, .working, .done: return
        }
        phase = .working(offered)
        let scanID = offered.scan.scanID
        let root = self.root

        // Every room is rebuilt, which takes a while on a big level.
        let result: ScanResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try ScanRecoveryStore.recoveredResult(scanID: scanID, root: root)
            }.value
        } catch {
            phase = .failed(offered, Failure(
                message: "The saved rooms could not be read back.",
                recovery: "The copy is still on this iPhone. Try again. If it keeps failing, discard it and scan the level again."))
            return
        }

        // The property it belongs to, or a new one named like it. A retry finds the new one: it is remembered.
        var target = offered
        let propertyID: UUID
        if let existing = offered.propertyID {
            propertyID = existing
            // Held back by an earlier failed save: write that first, or the rooms would only join what is in memory.
            if model.unsavedPropertyIDs.contains(existing) { model.retryUnsavedSaves() }
        } else {
            let created = model.createProperty(name: offered.propertyName, client: "", address: "", reference: "",
                                               kind: .apartment)
            propertyID = created.id
            target.propertyID = created.id
        }

        let outcome = await ScanIntake.commit(result, to: propertyID, model: model, now: now)
        let stillUnsaved = model.unsavedPropertyIDs.contains(propertyID)

        if outcome.saved {
            await removeCopy(scanID)
            phase = .done(target, Report(summary: outcome.summary, warnings: outcome.warnings, propertyID: propertyID))
        } else if outcome.roomsAlreadyInProperty, !stillUnsaved {
            // Saved by the scan itself, and only the clean-up was missed.
            await removeCopy(scanID)
            phase = .done(target, Report(
                summary: "These rooms are already saved in \(target.quotedName), so nothing was added.",
                warnings: [], propertyID: propertyID))
        } else {
            phase = .failed(target, ScanRecoveryCoordinator.failure(for: outcome, stillUnsaved: stillUnsaved))
        }
    }

    /// The words for a recovery that did not reach storage. The copy is still there.
    static func failure(for outcome: ScanIntake.Outcome, stillUnsaved: Bool) -> Failure {
        let kept = "The recovered copy is still on this iPhone."
        if outcome.floorID == nil, !outcome.roomsAlreadyInProperty, !stillUnsaved {
            return Failure(message: "The property could not be opened, so the rooms were not added.",
                           recovery: "\(kept) Restart the app, then try again.")
        }
        return Failure(message: "The rooms could not be saved to the property.",
                       recovery: "\(kept) Check that this iPhone has free space, then try again. Keep the app open until it has saved.")
    }

    /// Discard, after the person has confirmed: deletes the copy and moves on to the next scan.
    func discard() async {
        let prompt: ScanRecoveryPrompt
        switch phase {
        case .asking(let offered), .failed(let offered, _): prompt = offered
        case .idle, .working, .done: return
        }
        await removeCopy(prompt.scan.scanID)
        // A second tap while the first was deleting must not skip a scan.
        guard phase.promptID == prompt.id else { return }
        moveOn()
    }

    /// Not now: nothing is deleted, and the app asks again next time it opens.
    func notNow() {
        guard !isWorking else { return }
        phase = .idle
        waiting = []
    }

    /// The sheet went away. Same as Not now, unless a recovery is running: that carries on.
    func sheetClosed() {
        notNow()
    }

    /// The person has read the result. With another scan waiting, offers it and returns nil; otherwise ends and
    /// returns the property to open.
    @discardableResult
    func acknowledge() -> UUID? {
        guard case .done(_, let report) = phase else { return nil }
        if waiting.isEmpty {
            phase = .idle
            return report.propertyID
        }
        moveOn()
        return nil
    }

    private func moveOn() {
        if waiting.isEmpty {
            phase = .idle
        } else {
            phase = .asking(waiting.removeFirst())
        }
    }

    private func removeCopy(_ scanID: UUID) async {
        let root = self.root
        await Task.detached(priority: .utility) {
            ScanRecoveryStore.discard(scanID: scanID, root: root)
        }.value
    }
}

// MARK: - Defaults for a new property

enum PropertyDefaults {
    /// Levels the picker offers: basements to the top of a tower.
    static let storyRange = -5...200
    /// Ground level.
    static let firstStory = 0

    /// `NF-<year>-<month day>-01` for the Dubai calendar day of `date`: "NF-2026-1009-01".
    static func suggestedReference(on date: Date) -> String {
        let parts = ExportNaming.dateStamp(date).split(separator: "-")
        guard parts.count == 3 else { return "NF-" + ExportNaming.dateStamp(date) + "-01" }
        return "NF-\(parts[0])-\(parts[1])\(parts[2])-01"
    }

    /// The level to offer for the next scan of a property: the one that was last looked at, else the one
    /// most recently scanned, else ground.
    static func nextStory(in property: Property, preferring floorID: UUID? = nil) -> Int {
        if let floorID, let floor = property.floors.first(where: { $0.id == floorID }) { return floor.level }
        return property.floors.last?.level ?? firstStory
    }

    /// Keeps a level inside the range the picker offers.
    static func clampedStory(_ story: Int) -> Int {
        min(max(story, storyRange.lowerBound), storyRange.upperBound)
    }
}

/// The fields of the New property sheet, and whether they are enough to go on.
struct NewPropertyDraft: Equatable {
    var name = ""
    var client = ""
    var address = ""
    var reference: String
    var kind: PropertyKind = .apartment
    /// The level of the first scan.
    var story = PropertyDefaults.firstStory

    /// A blank form with the reference suggested for `now`.
    init(now: Date = Date()) {
        reference = PropertyDefaults.suggestedReference(on: now)
    }

    /// A form filled with what a property already has, for editing its details.
    init(editing property: Property) {
        name = property.name
        client = property.client
        address = property.address
        reference = property.reference
        kind = property.kind
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A name is the one required field.
    var canCreate: Bool { !trimmedName.isEmpty }

    /// "Level 23": what the scan will be called.
    var levelName: String { ScanCommit.levelName(story) }
}

// MARK: - Searching the list

enum PropertyListFilter {
    /// True when every word of `query` is found, ignoring case and accents, in at least one of `fields`.
    /// An empty query matches everything.
    static func matches(_ query: String, fields: [String]) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Saved properties that match. A summary carries only the name and the client, so `details` is asked for
    /// the whole property (address and job reference) when there is something to search for. It is never
    /// called for a blank query, so an unfiltered list reads nothing, and never for an unreadable property.
    static func summaries(_ list: [PropertySummary], query: String,
                          details: (UUID) -> Property? = { _ in nil }) -> [PropertySummary] {
        guard !query.allSatisfy({ $0.isWhitespace }) else { return list }
        return list.filter { summary in
            var fields = [summary.name, summary.client]
            if summary.health != .unreadable, let property = details(summary.id) {
                fields += [property.address, property.reference]
            }
            return matches(query, fields: fields)
        }
    }

    static func properties(_ list: [Property], query: String) -> [Property] {
        list.filter { matches(query, fields: [$0.name, $0.client, $0.address, $0.reference]) }
    }
}

// MARK: - What a property card shows

/// The numbers and drawing behind one card on the home screen.
struct PropertyCardInfo {
    let roomCount: Int
    let floorCount: Int
    let areaM2: Double
    let verified: Int
    let total: Int
    /// The plan of the first floor that has rooms, for the small picture on the card; nil when there is none.
    let thumbnail: PlanDrawing?

    static func make(_ property: Property) -> PropertyCardInfo {
        let progress = VerificationChecklist.propertyProgress(property)
        let area = property.allRooms.reduce(0.0) { $0 + $1.metrics.effectiveFloorArea }
        var thumbnail: PlanDrawing?
        if let floor = property.floors.first(where: { !$0.rooms.isEmpty }) {
            // Structure only: dimensions, angles, furniture and labels would be smudges at card size.
            let options = PlanOptions(scale: 100, showDimensions: false, showAngles: false, showFurniture: false,
                                      showRoomLabels: false, showOpeningSizes: false, markVerified: false)
            thumbnail = PlanDrawingBuilder.build(floor: floor, property: property, options: options)
        }
        return PropertyCardInfo(roomCount: property.roomCount, floorCount: property.floors.count,
                                areaM2: area.isFinite ? area : 0, verified: progress.verified,
                                total: progress.total, thumbnail: thumbnail)
    }

    var summary: VerificationSummary { VerificationSummary(verified: verified, total: total) }

    /// "8 rooms \u{00B7} 112 m\u{00B2} \u{00B7} 14 of 52 checked".
    func line(units: DisplayUnits) -> String {
        var parts = [roomCount == 1 ? "1 room" : "\(roomCount) rooms"]
        if roomCount > 0 { parts.append(PropertyCardInfo.areaText(areaM2, unit: units.area)) }
        parts.append(summary.text)
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The same for VoiceOver: "8 rooms, 112 square metres, 14 of 52 dimensions checked".
    func spoken(units: DisplayUnits) -> String {
        var parts = [roomCount == 1 ? "1 room" : "\(roomCount) rooms"]
        if roomCount > 0 { parts.append(PropertyCardInfo.areaSpoken(areaM2, unit: units.area)) }
        parts.append(summary.spoken)
        return parts.joined(separator: ", ")
    }

    /// Whole units, because a card is a glance: "112 m\u{00B2}", "1205 sq ft".
    static func areaText(_ squareMetres: Double, unit: AreaUnit) -> String {
        guard squareMetres.isFinite else { return "\u{2013} \(unit.symbol)" }
        return "\(wholeArea(squareMetres, unit: unit)) \(unit.symbol)"
    }

    /// The same figure for VoiceOver: "112 square metres", "1205 square feet". Rounded in the unit the card
    /// shows, so the card and the voice never disagree (rounding in square metres first read 987 sq ft as 990).
    static func areaSpoken(_ squareMetres: Double, unit: AreaUnit) -> String {
        guard squareMetres.isFinite else { return "No value" }
        let whole = String(wholeArea(squareMetres, unit: unit))
        switch unit {
        case .squareMetres: return SpokenMeasurement.withNoun(whole, "square metre", "square metres")
        case .squareFeet: return SpokenMeasurement.withNoun(whole, "square foot", "square feet")
        }
    }

    /// `squareMetres` in `unit`, rounded to a whole number (never negative).
    private static func wholeArea(_ squareMetres: Double, unit: AreaUnit) -> Int {
        let value = unit == .squareMetres ? squareMetres : squareMetres / UnitFormatter.squareMetresPerSquareFoot
        return Int(min(max(value, 0), 1e9).rounded())
    }
}

/// Remembers the card info for each property so scrolling does not rebuild drawings. An entry is reused
/// while the property's `updatedAt` is unchanged.
@MainActor
final class PropertyCardCache {
    private var entries: [UUID: (stamp: Date, info: PropertyCardInfo)] = [:]

    func info(for property: Property) -> PropertyCardInfo {
        if let entry = entries[property.id], entry.stamp == property.updatedAt { return entry.info }
        let info = PropertyCardInfo.make(property)
        entries[property.id] = (property.updatedAt, info)
        return info
    }

    /// Forgets properties that are no longer listed.
    func keep(_ ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}

// MARK: - The plan on screen

/// Builds the plan of a floor once and reuses it until the floor, the units or the property name change.
final class PlanDrawingCache {
    private struct Key: Equatable {
        var floor: Floor
        var units: DisplayUnits
        var propertyName: String
    }

    private var key: Key?
    private var drawing: PlanDrawing?

    /// Plans are drawn at 1:50 on screen; the canvas scales them to fit.
    static let onScreenScale = 50.0

    func drawing(for floor: Floor, in property: Property, units: DisplayUnits) -> PlanDrawing {
        let wanted = Key(floor: floor, units: units, propertyName: property.name)
        if let key, key == wanted, let drawing { return drawing }
        let built = PlanDrawingBuilder.build(floor: floor, property: property,
                                             options: PlanOptions(scale: PlanDrawingCache.onScreenScale, units: units))
        key = wanted
        drawing = built
        return built
    }
}

extension Property {
    /// The floor the plan shows: the preferred one if it exists, otherwise the most recent floor that has
    /// rooms, otherwise the last floor.
    func activeFloor(preferring id: UUID?) -> Floor? {
        if let id, let floor = floors.first(where: { $0.id == id }) { return floor }
        return floors.last(where: { !$0.rooms.isEmpty }) ?? floors.last
    }
}

/// One chip in the row of levels. Each level is one scan, so the chip says when it was made.
struct FloorChip: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// When the first room of the level was scanned.
    let scannedAt: Date?
    let roomCount: Int

    /// A chip for every level that has rooms. A level with none (the empty starter level of a new property)
    /// has no plan to show.
    static func chips(for property: Property) -> [FloorChip] {
        property.floors.filter { !$0.rooms.isEmpty }.map { floor in
            FloorChip(id: floor.id, title: floor.name, scannedAt: floor.rooms.map(\.scannedAt).min(),
                      roomCount: floor.rooms.count)
        }
    }
}

// MARK: - The card under the plan

/// What the card under the plan says about the thing that was tapped.
struct SelectionCardInfo: Equatable {
    enum Kind: Equatable { case room, wall, corner, opening, object }

    /// One dimension that can be checked on site.
    struct Row: Equatable, Identifiable {
        let target: MeasureTarget
        /// "Length", "Height", "Width", "Sill height", "Ceiling height".
        let label: String
        let measured: Measured
        var id: MeasureTarget { target }
    }

    struct ObjectSize: Equatable {
        let width: Double
        let depth: Double
        let height: Double
    }

    let kind: Kind
    let roomID: UUID
    /// "Wall A", "Door 1", "Living Room", "Wall D to Wall A".
    let title: String
    /// The room, and what is special about the thing.
    let subtitle: String
    /// The dimensions the person can check from here. Empty for corners and objects.
    let rows: [Row]
    let corner: CornerReading?
    let areaM2: Double?
    let objectSize: ObjectSize?
    /// Where the room's area comes from (the scan, or wall lengths somebody checked); nil for everything but a room.
    var areaBasis: AreaBasis? = nil

    /// nil when what was tapped is no longer in the property.
    static func make(selection: PlanSelection, in property: Property) -> SelectionCardInfo? {
        switch selection {
        case .room(let roomID):
            guard let room = property.findRoom(roomID) else { return nil }
            return SelectionCardInfo(
                kind: .room, roomID: roomID, title: roomTitle(room), subtitle: room.kind.displayName,
                rows: [Row(target: .ceilingHeight, label: "Ceiling height", measured: room.ceilingHeight)],
                corner: nil, areaM2: room.metrics.effectiveFloorArea, objectSize: nil,
                areaBasis: AreaBasis.of(room, metrics: room.metrics))

        case .wall(let roomID, let wallID):
            guard let room = property.findRoom(roomID), let wall = room.wall(withID: wallID) else { return nil }
            var rows = [Row(target: .wallLength(wallID), label: "Length", measured: wall.length)]
            if wall.kind == .solid {
                rows.append(Row(target: .wallHeight(wallID), label: "Height", measured: wall.height))
            }
            let place = roomTitle(room) + (wall.kind == .virtual ? " \u{00B7} Open boundary" : "")
            return SelectionCardInfo(kind: .wall, roomID: roomID, title: room.wallTitle(forID: wallID) ?? "Wall",
                                     subtitle: place, rows: rows, corner: nil, areaM2: nil, objectSize: nil)

        case .corner(let roomID, let index):
            guard let room = property.findRoom(roomID), let reading = CornerReading.reading(at: index, in: room) else {
                return nil
            }
            // "Corner B" is the corner that starts Wall B, the name the plan, the 3D view and AR all use.
            return SelectionCardInfo(kind: .corner, roomID: roomID, title: "Corner " + Room.wallLetters(forIndex: index),
                                     subtitle: roomTitle(room) + " \u{00B7} " + reading.title,
                                     rows: [], corner: reading, areaM2: nil, objectSize: nil)

        case .opening(let roomID, let openingID):
            guard let room = property.findRoom(roomID), let opening = room.openings.first(where: { $0.id == openingID })
            else { return nil }
            var rows = [Row(target: .openingWidth(openingID), label: "Width", measured: opening.width),
                        Row(target: .openingHeight(openingID), label: "Height", measured: opening.height)]
            // A sill is worth a row only when it is off the floor (every ordinary door sits on it).
            if opening.sillHeight.scanned >= 0.005 || opening.sillHeight.isVerified {
                rows.append(Row(target: .openingSill(openingID), label: "Sill height", measured: opening.sillHeight))
            }
            var place = roomTitle(room)
            if let wallID = opening.wallID, let wall = room.wallTitle(forID: wallID) { place += " \u{00B7} " + wall }
            return SelectionCardInfo(kind: .opening, roomID: roomID,
                                     title: room.title(for: .openingWidth(openingID)), subtitle: place,
                                     rows: rows, corner: nil, areaM2: nil, objectSize: nil)

        case .object(let roomID, let objectID):
            guard let room = property.findRoom(roomID), let object = room.objects.first(where: { $0.id == objectID })
            else { return nil }
            // Furniture is numbered per kind ("Sofa 1"), the way the plan labels it.
            let title = PlanHitTester(rooms: [room]).selectionTitle(for: selection) ?? object.kind.displayName
            return SelectionCardInfo(kind: .object, roomID: roomID, title: title,
                                     subtitle: roomTitle(room), rows: [], corner: nil, areaM2: nil,
                                     objectSize: ObjectSize(width: object.width, depth: object.depth,
                                                            height: object.height))
        }
    }

    /// The room's name, or its kind when it has none.
    static func roomTitle(_ room: Room) -> String {
        let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? room.kind.displayName : name
    }
}

// MARK: - Rooms

/// One row of the Rooms tab.
struct RoomRowInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: RoomKind
    /// "6 240 \u{00D7} 4 500 mm", or "Irregular" when the room is not a rectangle.
    let sizeText: String
    let sizeSpoken: String
    let areaM2: Double
    let ceilingHeight: Double
    /// The ceiling height was checked on site. A scanned ceiling carries no mark; a checked one does.
    let ceilingVerified: Bool
    let summary: VerificationSummary

    static func make(_ room: Room, units: DisplayUnits) -> RoomRowInfo {
        let metrics = room.metrics
        var sizeText = "Irregular"
        var sizeSpoken = "irregular shape"
        if metrics.isRectangular, let length = metrics.length, let width = metrics.width {
            sizeText = GroupedLength.dimensions(length, width, unit: units.length, precision: .compact)
            sizeSpoken = SpokenMeasurement.length(length, unit: units.length) + " by "
                + SpokenMeasurement.length(width, unit: units.length)
        }
        let checklist = VerificationChecklist(room: room)
        return RoomRowInfo(id: room.id, name: SelectionCardInfo.roomTitle(room), kind: room.kind,
                           sizeText: sizeText, sizeSpoken: sizeSpoken, areaM2: metrics.effectiveFloorArea,
                           ceilingHeight: metrics.ceilingHeight, ceilingVerified: room.ceilingHeight.isVerified,
                           summary: VerificationSummary(verified: checklist.verifiedCount,
                                                        total: checklist.totalCount))
    }

    /// "4 600 \u{00D7} 4 000 mm \u{00B7} 18.4 m\u{00B2} \u{00B7} Ceiling 2 800 mm", with a check mark after a ceiling that
    /// was checked on site.
    func line(units: DisplayUnits) -> String {
        [sizeText,
         UnitFormatter.area(areaM2, unit: units.area, precision: .compact),
         "Ceiling " + GroupedLength.text(ceilingHeight, unit: units.length, precision: .compact)
            + (ceilingVerified ? " \u{2713}" : "")]
            .joined(separator: " \u{00B7} ")
    }

    /// "Master Bedroom, 4 600 by 4 000 millimetres, 18.4 square metres, ceiling 2 800 millimetres, scanned,
    /// 9 of 21 dimensions checked".
    func spoken(units: DisplayUnits) -> String {
        [name, sizeSpoken, SpokenMeasurement.area(areaM2, unit: units.area),
         "ceiling " + SpokenMeasurement.length(ceilingHeight, unit: units.length)
            + (ceilingVerified ? ", checked" : ", scanned"),
         summary.spoken]
            .joined(separator: ", ")
    }
}

/// How much of a room's floor area rests on wall lengths somebody checked on site.
enum AreaBasis: Equatable {
    /// Every wall length is what LiDAR read, or the room is not a rectangle (its area is the scanned outline).
    case scan
    /// A rectangle with some wall lengths checked and some not: most of the number still rests on the scan.
    case partlyChecked
    /// A rectangle with every side checked.
    case checked

    /// The line above the area figure.
    var caption: String {
        switch self {
        case .scan: return "Floor area, from the scan"
        case .partlyChecked: return "Floor area, partly from checked wall lengths"
        case .checked: return "Floor area, from checked wall lengths"
        }
    }

    /// The line under the length x width, perimeter and volume figures, which are worked out from the same wall
    /// lengths as the area and so rest on the same ground. (Volume also uses the ceiling height, which carries
    /// its own mark.) `hasSize` is false for a room that is not a rectangle and so shows no length x width.
    func derivedCaption(hasSize: Bool = true) -> String {
        let figures = hasSize ? "Size, perimeter and volume" : "Perimeter and volume"
        switch self {
        case .scan: return "\(figures) are worked out from the scan."
        case .partlyChecked: return "\(figures) are worked out from the wall lengths: some checked, some from the scan."
        case .checked: return "Size and perimeter are worked out from checked wall lengths. Volume also uses the ceiling height."
        }
    }

    /// Only a rectangle's area is worked out from its wall lengths, so only it can be checked.
    static func of(_ room: Room, metrics: RoomMetrics) -> AreaBasis {
        guard metrics.isRectangular, !metrics.sides.isEmpty else { return .scan }
        if metrics.sides.allSatisfy(\.isVerified) { return .checked }
        return room.walls.contains { $0.length.isVerified } ? .partlyChecked : .scan
    }
}

/// The numbers at the top of the Room screen, and its dimension lists.
struct RoomOverview {
    let title: String
    let kind: RoomKind
    let areaM2: Double
    /// Whether the area figure rests on the scan or on checked wall lengths.
    let areaBasis: AreaBasis
    /// Rectangular rooms only.
    let length: Double?
    let width: Double?
    let perimeter: Double
    let ceiling: Measured
    let volumeM3: Double
    let checklist: VerificationChecklist
    let corners: [CornerReading]

    init(room: Room) {
        let metrics = room.metrics
        title = SelectionCardInfo.roomTitle(room)
        kind = room.kind
        areaM2 = metrics.effectiveFloorArea
        areaBasis = AreaBasis.of(room, metrics: metrics)
        length = metrics.isRectangular ? metrics.length : nil
        width = metrics.isRectangular ? metrics.width : nil
        perimeter = metrics.perimeter
        ceiling = room.ceilingHeight
        volumeM3 = metrics.volume
        checklist = VerificationChecklist(room: room)
        corners = CornerReading.readings(for: room)
    }

    var summary: VerificationSummary {
        VerificationSummary(verified: checklist.verifiedCount, total: checklist.totalCount)
    }

    /// Dimensions the person can check, by section of the screen.
    func items(in group: VerificationChecklist.Group) -> [VerificationChecklist.Item] {
        checklist.items(in: group)
    }

    /// "6 240 \u{00D7} 4 500 mm", or nil when the room is not a rectangle.
    func sizeText(units: DisplayUnits) -> String? {
        guard let length, let width else { return nil }
        return GroupedLength.dimensions(length, width, unit: units.length, precision: .compact)
    }

    func sizeSpoken(units: DisplayUnits) -> String? {
        guard let length, let width else { return nil }
        return SpokenMeasurement.length(length, unit: units.length) + " by "
            + SpokenMeasurement.length(width, unit: units.length)
    }
}

// MARK: - Corners

/// One corner of a room as the Room screen and the selection card describe it.
struct CornerReading: Identifiable, Equatable {
    enum Level: Equatable {
        /// Within 1 degree of a right angle.
        case square
        /// 1 to 3 degrees off: worth knowing, drawn in the caution colour.
        case slightlyOff
        /// 3 degrees or more off: drawn in the critical colour.
        case outOfSquare
        /// The inside of an L-shape; not a fault.
        case reflex
        /// Where one wall simply carries on; not a corner at all.
        case straight
    }

    /// Corner `index` is the start of wall `index` (and the end of the wall before it).
    let index: Int
    /// "Wall D to Wall A".
    let title: String
    /// Interior angle, degrees.
    let angle: Double
    /// Interior angle minus 90, degrees.
    let deviation: Double
    let level: Level

    var id: Int { index }

    /// Out of square by 1 degree or more, in either direction, and not an L-shape or a straight run.
    var isOffSquare: Bool { level == .slightlyOff || level == .outOfSquare }

    /// "Square", "2.4\u{00B0} wider than square", "Inside corner of an L-shape".
    var note: String {
        switch level {
        case .square: return "Square"
        case .slightlyOff, .outOfSquare:
            let size = UnitFormatter.angle(abs(deviation))
            return deviation > 0 ? "\(size) wider than square" : "\(size) tighter than square"
        case .reflex: return "Inside corner of an L-shape"
        case .straight: return "The wall carries on straight"
        }
    }

    /// For VoiceOver: "Wall D to Wall A, 92.4 degrees, 2.4 degrees wider than square".
    var spoken: String {
        let degrees = SpokenMeasurement.angle(angle)
        switch level {
        case .square: return "\(title), \(degrees), square"
        case .reflex: return "\(title), \(degrees), inside corner of an L-shape"
        case .straight: return "\(title), \(degrees), the wall carries on straight"
        case .slightlyOff, .outOfSquare:
            return "\(title), \(degrees), " + SpokenMeasurement.angle(abs(deviation))
                + (deviation > 0 ? " wider than square" : " tighter than square")
        }
    }

    static func level(forAngle angle: Double) -> Level {
        let deviation = angle - 90
        if abs(angle - 180) <= RoomMetrics.straightTolerance { return .straight }
        if angle > 180 + RoomMetrics.straightTolerance { return .reflex }
        if abs(deviation) <= RoomMetrics.squareTolerance { return .square }
        return abs(deviation) < 3 ? .slightlyOff : .outOfSquare
    }

    /// The corners of a room that are worth showing: straight continuations of a wall are left out.
    static func readings(for room: Room) -> [CornerReading] {
        guard room.walls.count >= 3 else { return [] }
        return room.metrics.corners.filter { !$0.isStraight }.map { reading(for: $0, in: room) }
    }

    /// One corner by index; nil when the room has no such corner.
    static func reading(at index: Int, in room: Room) -> CornerReading? {
        guard room.walls.count >= 3, index >= 0, index < room.walls.count else { return nil }
        let corners = room.metrics.corners
        guard index < corners.count else { return nil }
        return reading(for: corners[index], in: room)
    }

    private static func reading(for corner: Corner, in room: Room) -> CornerReading {
        let before = (corner.index + room.walls.count - 1) % room.walls.count
        return CornerReading(index: corner.index,
                             title: "\(room.wallTitle(at: before)) to \(room.wallTitle(at: corner.index))",
                             angle: corner.interiorAngle, deviation: corner.deviationFrom90,
                             level: level(forAngle: corner.interiorAngle))
    }
}

// MARK: - Volume

/// Room volume, which `UnitFormatter` has no word for: cubic metres, or cubic feet with square-foot users.
struct VolumeText {
    let visible: String
    let spoken: String

    init(cubicMetres: Double, units: DisplayUnits) {
        guard cubicMetres.isFinite else {
            visible = "\u{2013}"
            spoken = "No value"
            return
        }
        switch units.area {
        case .squareMetres:
            let number = String(format: "%.1f", cubicMetres)
            visible = "\(number) m\u{00B3}"
            spoken = "\(SpokenMeasurement.trimmed(number)) cubic metres"
        case .squareFeet:
            let number = String(Int(min(max(cubicMetres / 0.028316846592, -1e12), 1e12).rounded()))
            visible = "\(number) cu ft"
            spoken = "\(number) cubic feet"
        }
    }
}

// MARK: - Settings

/// The choices on the Settings screen and the examples beside them.
enum SettingsChoices {
    struct Scale: Identifiable, Hashable {
        /// The scale denominator (50 means 1:50); nil is "Automatic".
        let value: Double?
        var id: String { value.map { String($0) } ?? "auto" }
        var title: String { SettingsChoices.scaleTitle(value) }
    }

    static let standardScales: [Double] = [20, 25, 50, 75, 100, 150, 200]

    /// Automatic, then 1:20 to 1:200. A saved scale outside the list is kept as its own choice so the picker
    /// never shows nothing.
    static func scales(including current: Double?) -> [Scale] {
        var values = standardScales
        if let current, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return [Scale(value: nil)] + values.map { Scale(value: $0) }
    }

    static func scaleTitle(_ value: Double?) -> String {
        guard let value else { return "Automatic" }
        if value == value.rounded(), abs(value) < 1e9 { return "1:\(Int(value))" }
        return "1:" + String(format: "%.1f", value)
    }

    /// One paper choice: the word the export code reads, and the word on screen.
    struct Paper: Identifiable, Hashable {
        let value: String
        let title: String
        var id: String { value }
    }

    /// Paper choices as the export code spells them, with the words for the picker.
    static let papers: [Paper] = [Paper(value: "auto", title: "Automatic"), Paper(value: "a4", title: "A4"),
                                  Paper(value: "a3", title: "A3")]

    static func paperTitle(_ value: String) -> String {
        papers.first { $0.value == value }?.title ?? "Automatic"
    }

    /// "Version 1.0.0 (1)" from the app's Info.plist values; "Version not available" without them.
    static func versionText(short: String?, build: String?) -> String {
        let version = short?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let number = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if version.isEmpty { return number.isEmpty ? "Version not available" : "Build \(number)" }
        return number.isEmpty ? "Version \(version)" : "Version \(version) (\(number))"
    }

    /// A fixed length, so the person sees what their choice looks like: "3 245 mm", `10' 7 3/4"`.
    static func lengthExample(_ unit: LengthUnit) -> String {
        GroupedLength.text(3.245, unit: unit)
    }

    /// "18.42 m\u{00B2}" or "198.3 sq ft".
    static func areaExample(_ unit: AreaUnit) -> String {
        UnitFormatter.area(18.42, unit: unit)
    }
}

/// How close the scans were to the laser or tape across every real property on this device.
///
/// Two things are left out on purpose, because either would make the phone look better or worse than it is:
/// - the demo apartment (and copies of it), whose laser checks are made up (`DemoMarker`);
/// - checks copied from a drawing, which are a document and say nothing about how well the phone scans
///   (`AccuracyReport.measuredSources`).
struct AccuracyOverview: Equatable {
    let sampleCount: Int
    /// "12 checks: typically 6 mm (0.3 %), worst 21 mm", or "No laser or tape checks yet".
    let summary: String
    /// "Scans read about 4 mm short on average", or "".
    let bias: String

    static let emptySummary = "No laser or tape checks yet"

    static func make(properties: [Property], unit: LengthUnit) -> AccuracyOverview {
        let real = properties.filter { !DemoMarker.isDemo($0) }
        let report = AccuracyReport(rooms: real.flatMap(\.allRooms), sources: AccuracyReport.measuredSources)
        // The Core wording for "nothing yet" says laser only; tape checks count here too.
        let summary = report.sampleCount == 0 ? emptySummary : report.summary(unit: unit)
        return AccuracyOverview(sampleCount: report.sampleCount, summary: summary,
                                bias: report.biasDescription(unit: unit))
    }

    /// The question and the answer under the row.
    static let footerTitle = "How accurate is my phone?"
    static let footerText = "The scan reads every wall and opening with LiDAR, typically within 1\u{2013}2 %. Each time you check a dimension with a laser or tape, the app compares it with what the scan read, and this row adds up all your checks on this device. Checks copied from a drawing and the demo apartment are not counted: neither measures how well your phone scans. The more rooms you check, the better it describes your phone. Until then, treat scanned numbers as estimates and check anything joinery will be cut to."
}
