import Foundation
import NexaFixCore

// Regression checks for the launch-time scan recovery: the wording (ScanRecoveryPrompt), the coordinator
// (ScanRecoveryCoordinator) against a real AppModel, PropertyStore and ScanRecoveryStore in temporary folders,
// and the privacy note. Foundation and NexaFixCore only (Linux or macOS). See README.md in this folder's parent.
//
// What matters most here is the rule for deleting a safety copy of a scan: only once the rooms are on disk in
// their property, or when the person discards it. Never because the copy is old, never before the save worked.

setvbuf(stdout, nil, _IONBF, 0)
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0
/// The test that is running, named in every failure line (mutation-check.py looks for it).
nonisolated(unsafe) var currentTest = ""
func check(_ ok: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !ok() { failures += 1; print("FAIL [\(currentTest)] line \(line): \(message)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ message: String = "", line: Int = #line) {
    checks += 1
    if a != b { failures += 1; print("FAIL [\(currentTest)] line \(line): \(message) got \(a), expected \(b)") }
}

// MARK: Fixtures

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-harness-\(UUID().uuidString)")
func folder(_ name: String) -> URL {
    let url = tmp.appendingPathComponent(name + "-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func rectangle(_ w: Double, _ d: Double) -> RawCapture {
    func wall(_ cx: Double, _ cz: Double, _ width: Double, yaw: Double) -> RawSurface {
        RawSurface(kind: .wall, transform: .yawTranslation(yaw: yaw, Point3(cx, 1.4, cz)), dimensions: Point3(width, 2.8, 0))
    }
    var capture = RawCapture(walls: [
        wall(w / 2, 0, w, yaw: 0), wall(w, -d / 2, d, yaw: Double.pi / 2),
        wall(w / 2, -d, w, yaw: 0), wall(0, -d / 2, d, yaw: Double.pi / 2),
    ])
    capture.doors = [RawSurface(kind: .door, transform: .identity, dimensions: Point3(0.9, 2.1, 0))]
    return capture
}

/// A scan copy on disk, written through the real store (so the manifest and file names are the real ones).
struct Seeded {
    var scanID: UUID
    var rawIDs: [UUID]
}

@discardableResult
func seed(root: URL, scanID: UUID = UUID(), propertyID: UUID?, propertyName: String, story: Int = 1,
          rooms: [(name: String?, kind: RoomKind)], delivered: Bool = false, at date: Date = Date(),
          rawIDs: [UUID]? = nil, existingNames: [String] = []) -> Seeded {
    let store = ScanRecoveryStore(root: root, scanID: scanID, propertyID: propertyID, propertyName: propertyName,
                                  story: story, existingRoomNames: existingNames, now: date)
    var ids: [UUID] = []
    for (index, entry) in rooms.enumerated() {
        let id = rawIDs?[index] ?? UUID()
        ids.append(id)
        store.addRoom(id: id, raw: rectangle(4 + Double(index), 3), capturedJSON: Data("captured-\(index)".utf8), now: date)
        if let name = entry.name { store.setName(id: id, name: name, kind: entry.kind, now: date) }
    }
    if delivered { store.markDelivered(now: date) }
    store.flush()
    return Seeded(scanID: scanID, rawIDs: ids)
}

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, tz: TimeZone) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = tz
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@MainActor func makeModel(_ storeRoot: URL) -> AppModel {
    let defaults = UserDefaults(suiteName: "recovery-harness-\(UUID().uuidString)") ?? .standard
    return AppModel(store: PropertyStore(rootURL: storeRoot), defaults: defaults)
}

@MainActor func makeProperty(_ model: AppModel, name: String) -> Property {
    model.createProperty(name: name, client: "", address: "", reference: "", kind: .apartment)
}

@MainActor func onDisk(_ model: AppModel, _ id: UUID) -> Property? {
    try? model.store.load(id: id)
}

let dubai = TimeZone(identifier: "Asia/Dubai")!
let day: TimeInterval = 24 * 3600

func copyExists(_ root: URL, _ seeded: Seeded) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(seeded.scanID.uuidString).path)
}

/// What the app does after a scan: the files, then the property with the new level (`ScanIntake.commit`), from a
/// result rebuilt out of the copy. Returns whether the property reached disk.
@MainActor func saveLikeTheNormalPath(_ seeded: Seeded, root: URL, into propertyID: UUID, model: AppModel,
                                      only rooms: Int? = nil) async -> Bool {
    guard var result = try? ScanRecoveryStore.recoveredResult(scanID: seeded.scanID, root: root) else { return false }
    if let rooms { result.rooms = Array(result.rooms.prefix(rooms)) }
    return await ScanIntake.commit(result, to: propertyID, model: model).saved
}

@MainActor func mustSave(_ seeded: Seeded, root: URL, into propertyID: UUID, model: AppModel, only rooms: Int? = nil,
                         line: Int = #line) async {
    let saved = await saveLikeTheNormalPath(seeded, root: root, into: propertyID, model: model, only: rooms)
    check(saved, "the scan could not be saved to the property", line: line)
}

/// The app starting again: a new model on the same property folder, a new coordinator, and its one look.
@MainActor func relaunch(storeRoot: URL, copies: URL) async -> (model: AppModel, coordinator: ScanRecoveryCoordinator) {
    let model = makeModel(storeRoot)
    let coordinator = ScanRecoveryCoordinator(root: copies)
    await coordinator.look(model: model)
    return (model, coordinator)
}

/// Storage stops working for one property: its folder becomes a plain file, so nothing can be written under it.
struct BrokenFolder {
    let folder: URL
    let aside: URL
    init(_ model: AppModel, _ propertyID: UUID, storeRoot: URL) {
        folder = model.store.folderURL(for: propertyID)
        aside = storeRoot.appendingPathComponent("aside-" + UUID().uuidString)
        try? FileManager.default.moveItem(at: folder, to: aside)
        try? Data("x".utf8).write(to: folder)
    }
    func repair() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.moveItem(at: aside, to: folder)
    }
}

let recoveredWarning = "no joined 3D model and no AR map"

// MARK: Wording

@MainActor func testPromptWording() {
    let when = date(2026, 10, 9, 14, 32, tz: dubai)
    // "now" is fixed: a date from an earlier year carries its year, so the wording must not depend on the real clock
    let today = date(2026, 10, 10, 9, 0, tz: dubai)
    let propertyID = UUID()
    let scan = ScanRecoveryStore.RecoverableScan(scanID: UUID(), propertyID: propertyID, propertyName: "Marina Gate 2", story: 1,
                                                 roomCount: 3, createdAt: when, updatedAt: when, delivered: false)
    let prompt = ScanRecoveryPrompt.prompts(for: [scan]) { $0 == propertyID ? "Marina Gate 2" : nil }[0]
    eq(prompt.headline(timeZone: dubai, now: today), "Unfinished scan found: 3 rooms from 9 Oct, 14:32 (Marina Gate 2).")
    eq(prompt.dateText(timeZone: dubai, now: today), "9 Oct, 14:32")
    check(!prompt.willCreateProperty && prompt.propertyID == propertyID, "property exists")
    eq(prompt.explanation, "The app closed before this level was finished, so its rooms were never added to \u{201C}Marina Gate 2\u{201D}. Recover rooms adds them as Level 1.")
    eq(prompt.discardConfirmationButton, "Discard 3 rooms")
    check(prompt.discardConfirmationMessage.contains("3 rooms from ") && prompt.discardConfirmationMessage.hasSuffix("This cannot be undone."), prompt.discardConfirmationMessage)
    eq(prompt.discardConfirmationTitle, "Discard this scan?")

    // the evening in Dubai is still the same day in the morning UTC; the formatter follows the zone it is given
    eq(prompt.dateText(timeZone: TimeZone(identifier: "UTC")!, now: today), "9 Oct, 10:32")

    // one room, no name
    var one = scan; one.roomCount = 1; one.propertyID = nil; one.propertyName = "  "
    let lonely = ScanRecoveryPrompt.prompts(for: [one]) { _ in nil }[0]
    eq(lonely.headline(timeZone: dubai, now: today), "Unfinished scan found: 1 room from 9 Oct, 14:32.")
    check(lonely.willCreateProperty, "no property id means a new one")
    eq(lonely.explanation, "The property this scan belonged to is no longer on this iPhone. Recover rooms makes a new property and adds the rooms to it as Level 1.")
    eq(lonely.discardConfirmationButton, "Discard 1 room")

    // the property is gone but the old name is known
    var gone = scan; gone.propertyName = "  Marina Gate 2 "
    let missing = ScanRecoveryPrompt.prompts(for: [gone]) { _ in nil }[0]
    check(missing.willCreateProperty && missing.propertyID == nil, "gone property")
    eq(missing.propertyName, "Marina Gate 2")
    eq(missing.explanation, "\u{201C}Marina Gate 2\u{201D} is no longer on this iPhone. Recover rooms makes a new property with that name and adds the rooms to it as Level 1.")

    // renamed since: the name it has now
    let renamed = ScanRecoveryPrompt.prompts(for: [scan]) { _ in "Marina Gate 2B" }[0]
    check(renamed.headline(timeZone: dubai, now: today).hasSuffix("(Marina Gate 2B)."), renamed.headline(timeZone: dubai, now: today))
    // unreadable property: it exists, the name falls back to the one in the copy
    let unreadable = ScanRecoveryPrompt.prompts(for: [scan]) { _ in "" }[0]
    check(!unreadable.willCreateProperty && unreadable.propertyName == "Marina Gate 2", "unreadable property keeps the old name")

    // delivered
    var sent = scan; sent.delivered = true
    let delivered = ScanRecoveryPrompt.prompts(for: [sent]) { _ in "Marina Gate 2" }[0]
    check(delivered.explanation.contains("may be saved already") && delivered.explanation.contains("not added twice"), delivered.explanation)

    // basement level
    var basement = scan; basement.story = -1
    eq(ScanRecoveryPrompt.prompts(for: [basement]) { _ in "X" }[0].levelName, "Level -1")

    // newest first
    var older = scan; older.scanID = UUID(); older.updatedAt = when.addingTimeInterval(-3600)
    var newer = scan; newer.scanID = UUID(); newer.updatedAt = when.addingTimeInterval(3600)
    let ordered = ScanRecoveryPrompt.prompts(for: [older, scan, newer]) { _ in "X" }
    eq(ordered.map(\.scan.scanID), [newer.scanID, scan.scanID, older.scanID], "newest first")

    // A scan is offered however old it is, so the date must stay true: this year's carries no year, an earlier one does
    // (the year is the one in the time zone the text is written for)
    let september = date(2026, 9, 2, 14, 32, tz: dubai)
    let lastSeptember = date(2025, 9, 2, 14, 32, tz: dubai)
    eq(ScanRecoveryPrompt.dateText(september, timeZone: dubai, now: today), "2 Sep, 14:32")
    eq(ScanRecoveryPrompt.dateText(lastSeptember, timeZone: dubai, now: today), "2 Sep 2025, 14:32")
    var ancient = scan; ancient.roomCount = 2; ancient.updatedAt = lastSeptember; ancient.createdAt = lastSeptember
    let old = ScanRecoveryPrompt.prompts(for: [ancient]) { _ in "Marina Gate 2" }[0]
    eq(old.headline(timeZone: dubai, now: today), "Unfinished scan found: 2 rooms from 2 Sep 2025, 14:32 (Marina Gate 2).")
    let newYear = date(2026, 1, 1, 2, 30, tz: dubai)   // 31 Dec 22:30 in UTC
    eq(ScanRecoveryPrompt.dateText(newYear, timeZone: dubai, now: today), "1 Jan, 02:30")
    eq(ScanRecoveryPrompt.dateText(newYear, timeZone: TimeZone(identifier: "UTC")!, now: today), "31 Dec 2025, 22:30")

    // words
    eq(ScanRecoveryPrompt.recoverTitle, "Recover rooms")
    eq(ScanRecoveryPrompt.discardTitle, "Discard")
    eq(ScanRecoveryPrompt.notNowTitle, "Not now")
    check(ScanRecoveryPrompt.limits.contains("3D model") && ScanRecoveryPrompt.limits.contains("AR map"), "limits are stated")
}

@MainActor func testPrivacyNote() {
    eq(DeviceCapability.privacyNote, "Your scans stay on this iPhone, and in its backup if you back it up. Nothing is sent anywhere unless you export it.")
}

// MARK: Coordinator

@MainActor func testLookOffersNewestFirstAndOnlyOnce() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "Marina Gate 2")
    let now = Date()
    let older = seed(root: root, propertyID: property.id, propertyName: "Marina Gate 2",
                     rooms: [("Hall", .entrance)], at: now.addingTimeInterval(-7200))
    let newer = seed(root: root, propertyID: property.id, propertyName: "Marina Gate 2", story: 2,
                     rooms: [("Living Room", .livingRoom), ("Kitchen", .kitchen), (nil, .other)], at: now.addingTimeInterval(-60))
    let coordinator = ScanRecoveryCoordinator(root: root)
    check(coordinator.phase == .idle, "idle before looking")
    await coordinator.look(model: model)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking, got \(coordinator.phase)"); return }
    eq(prompt.scan.scanID, newer.scanID, "newest first")
    eq(prompt.scan.roomCount, 3)
    eq(prompt.propertyName, "Marina Gate 2")
    eq(coordinator.waiting.map(\.scan.scanID), [older.scanID], "the older one waits")
    // a second look does nothing, even after the phase went back to idle
    coordinator.notNow()
    await coordinator.look(model: model)
    check(coordinator.phase == .idle, "looks once per launch")
    check(ScanRecoveryStore.recoverableScans(root: root).count == 2, "Not now keeps both copies")
}

@MainActor func testNothingToOffer() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    check(coordinator.phase == .idle, "nothing on disk")
    // a folder that is not a scan copy, and a copy with no manifest, are neither offered nor deleted
    let stray = root.appendingPathComponent("not-a-scan")
    let noManifest = root.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
    let coordinator2 = ScanRecoveryCoordinator(root: root)
    await coordinator2.look(model: model)
    check(coordinator2.phase == .idle, "nothing readable")
    check(FileManager.default.fileExists(atPath: stray.path) && FileManager.default.fileExists(atPath: noManifest.path),
          "what cannot be read is left alone")
}

// Fix 1. A copy is the only record of a scan whose property save failed, however old it is.
@MainActor func testOldCopiesAreOfferedNotDropped() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")           // on disk, with no rooms
    let now = Date()
    let delivered8 = seed(root: root, propertyID: property.id, propertyName: "P", story: 1,
                          rooms: [("Hall", .entrance)], delivered: true, at: now - 8 * day)
    let abandoned31 = seed(root: root, propertyID: property.id, propertyName: "P", story: 2,
                           rooms: [("Study", .office), ("Bath", .bathroom)], at: now - 31 * day)
    let ancient = seed(root: root, propertyID: property.id, propertyName: "P", story: 3,
                       rooms: [("Attic", .other)], delivered: true, at: now - 400 * day)

    // the store's own prune() deletes nothing on its own: the scan screen still calls it when a scan starts
    check(ScanRecoveryStore.prune(root: root).isEmpty, "prune with no proof deletes nothing")
    check(copyExists(root, delivered8) && copyExists(root, abandoned31) && copyExists(root, ancient), "all three kept by prune")

    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking, got \(coordinator.phase)"); return }
    eq(prompt.scan.scanID, delivered8.scanID, "newest first")
    check(prompt.scan.delivered && prompt.explanation.contains("may be saved already"), "a delivered copy is told so")
    eq(coordinator.waiting.map(\.scan.scanID), [abandoned31.scanID, ancient.scanID], "the older ones wait")
    check(copyExists(root, delivered8) && copyExists(root, abandoned31) && copyExists(root, ancient),
          "no copy was deleted because of its age (7 days delivered, 30 days abandoned were the old limits)")
    eq(model.summaries.count, 1, "no property was made")

    // the date says how old: the year appears once it is not this year's
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = dubai
    let thisYear = calendar.component(.year, from: now)
    let ancientYear = calendar.component(.year, from: now - 400 * day)
    let recentYear = calendar.component(.year, from: now - 8 * day)
    let ancientPrompt = coordinator.waiting[1]
    check(ancientYear != thisYear && ancientPrompt.headline(timeZone: dubai, now: now).contains(" \(ancientYear), "),
          "a scan from an earlier year says the year: \(ancientPrompt.headline(timeZone: dubai, now: now))")
    eq(prompt.headline(timeZone: dubai, now: now).contains(" \(recentYear), "), recentYear != thisYear,
       "the year appears only when it is not this year's: \(prompt.headline(timeZone: dubai, now: now))")

    // and the old one can still be put back
    await coordinator.recover(model: model)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "Added 1 room to Level 1.")
    check(!copyExists(root, delivered8), "the recovered copy is removed")
    check(copyExists(root, abandoned31) && copyExists(root, ancient), "the others stay")
}

// Fix 1, the reported case end to end: the property save failed, the copy was kept, the app was closed and opened
// again more than 7 days later.
@MainActor func testFailedSaveThenRelaunchWeeksLaterStillOffersTheScan() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "Marina Gate 2")
    let weeksAgo = Date() - 9 * day
    let seeded = seed(root: root, propertyID: property.id, propertyName: "Marina Gate 2", story: 4,
                      rooms: [("Living Room", .livingRoom), ("Kitchen", .kitchen)], delivered: true, at: weeksAgo)
    // the scan was handed over and the save failed (disk full): the rooms exist only in memory and in the copy
    let broken = BrokenFolder(model, property.id, storeRoot: storeRoot)
    guard let result = try? ScanRecoveryStore.recoveredResult(scanID: seeded.scanID, root: root) else { check(false, "result"); return }
    let outcome = await ScanIntake.commit(result, to: property.id, model: model)
    check(!outcome.saved, "the save failed")
    check(model.unsavedPropertyIDs.contains(property.id), "and the model says so")
    check(copyExists(root, seeded), "the copy is kept after a failed save")
    // the app is closed: memory is gone. Opened again, storage works.
    broken.repair()
    check(onDisk(model, property.id)?.roomCount == 0, "nothing of the scan reached the disk")
    let (model2, coordinator) = await relaunch(storeRoot: storeRoot, copies: root)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking, got \(coordinator.phase)"); return }
    eq(prompt.scan.scanID, seeded.scanID)
    check(copyExists(root, seeded), "the copy is still there")
    await coordinator.recover(model: model2)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "Added 2 rooms to Level 4.")
    eq(onDisk(model2, property.id)?.roomCount ?? 0, 2, "the rooms are back")
    check(!copyExists(root, seeded), "removed once saved")
}

@MainActor func testRecoverIntoTheExistingProperty() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "Marina Gate 2")
    let seeded = seed(root: root, propertyID: property.id, propertyName: "Marina Gate 2", story: 1,
                      rooms: [("Living Room", .livingRoom), ("Kitchen", .kitchen), (nil, .other)])
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    await coordinator.recover(model: model)
    guard case .done(let prompt, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.propertyID, property.id)
    eq(report.summary, "Added 3 rooms to Level 1.")
    check(report.warnings.contains { $0.contains("recovered") && $0.contains("no joined 3D model and no AR map") },
          "the no 3D model, no AR map warning is shown: \(report.warnings)")
    check(report.warnings.contains { $0.contains("had not been named") }, "an unnamed room is flagged: \(report.warnings)")
    check(!prompt.willCreateProperty, "no new property")

    let saved = onDisk(model, property.id)
    let floor = saved?.floors.first { $0.name == "Level 1" }
    eq(floor?.rooms.map(\.name) ?? [], ["Living Room", "Kitchen", "Room"].map { $0 }, "rooms on disk")
    check(floor?.assets.worldMap == nil && floor?.assets.structureUSDZ == nil, "no map and no model recorded")
    check(floor?.rooms.allSatisfy { $0.capturedRoomFile != nil } == true, "detailed scan data kept")
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "the copy is gone after the save")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent(seeded.scanID.uuidString).path), "folder removed")
    check(model.unsavedPropertyIDs.isEmpty, "nothing unsaved")
    check(coordinator.acknowledge() == property.id && coordinator.phase == .idle, "acknowledge returns the property to open")
}

@MainActor func testRecoverMakesANewPropertyWhenTheOldOneIsGone() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let gone = UUID()
    seed(root: root, propertyID: gone, propertyName: "Marina Gate 2", story: 3, rooms: [("Majlis", .livingRoom), ("Hall", .entrance)])
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking"); return }
    check(prompt.willCreateProperty && prompt.propertyName == "Marina Gate 2", "offered as a new property")
    check(model.summaries.isEmpty, "nothing created before the person agrees")
    await coordinator.recover(model: model)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "Added 2 rooms to Level 3.")
    check(report.propertyID != gone, "a new property")
    let created = onDisk(model, report.propertyID)
    eq(created?.name ?? "", "Marina Gate 2", "named from the copy")
    eq(created?.floors.map(\.name) ?? [], ["Level 3"], "the empty starter level is replaced")
    eq(created?.roomCount ?? 0, 2)
    eq(model.summaries.count, 1, "exactly one property")
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "copy removed")
}

@MainActor func testUnreadableCopyKeepsItAndSaysWhatToDo() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")
    let seeded = seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("Hall", .entrance)])
    // the room file is damaged
    let file = root.appendingPathComponent(seeded.scanID.uuidString).appendingPathComponent(ScanRecoveryStore.rawFileName(seeded.rawIDs[0]))
    try? Data("not json".utf8).write(to: file)
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    await coordinator.recover(model: model)
    guard case .failed(_, let failure) = coordinator.phase else { check(false, "failed, got \(coordinator.phase)"); return }
    eq(failure.message, "The saved rooms could not be read back.")
    check(failure.recovery.contains("still on this iPhone") && failure.recovery.contains("discard"), failure.recovery)
    check(ScanRecoveryStore.recoverableScans(root: root).count == 1, "the copy is kept")
    check(onDisk(model, property.id)?.roomCount == 0, "nothing was added")
    check(model.summaries.count == 1, "and no property was made for it")
}

@MainActor func testFailedSaveKeepsTheCopyAndRetryDoesNotDuplicate() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "P")
    seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("Hall", .entrance), ("Study", .office)])

    // storage breaks: the property's folder becomes a plain file, so nothing can be written under it
    let broken = BrokenFolder(model, property.id, storeRoot: storeRoot)

    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    await coordinator.recover(model: model)
    guard case .failed(let prompt, let failure) = coordinator.phase else { check(false, "failed, got \(coordinator.phase)"); return }
    eq(failure.message, "The rooms could not be saved to the property.")
    check(failure.recovery.contains("still on this iPhone") && failure.recovery.contains("free space"), failure.recovery)
    check(ScanRecoveryStore.recoverableScans(root: root).count == 1, "a failed save keeps the copy")
    check(model.unsavedPropertyIDs.contains(property.id), "the model knows the property is unsaved")

    // a second try while storage is still broken must not call the rooms saved because they are in memory
    await coordinator.recover(model: model)
    guard case .failed = coordinator.phase else { check(false, "still failed, got \(coordinator.phase)"); return }
    check(ScanRecoveryStore.recoverableScans(root: root).count == 1, "still kept after the second failure")

    // storage works again
    broken.repair()
    await coordinator.recover(model: model)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done after the fix, got \(coordinator.phase)"); return }
    // Fix 2: the retry finds the rooms already in the property (the first try put them there in memory). They are
    // there because of this recovery, so it says what it added, and what a recovered level lacks.
    eq(report.summary, "Added 2 rooms to Level 1.", "a retry after a failed save says what was added")
    check(report.warnings.contains { $0.contains("recovered") && $0.contains(recoveredWarning) },
          "and the recovered-level warning stays: \(report.warnings)")
    check(!report.summary.contains("already saved") && !report.summary.contains("nothing was added"), report.summary)
    let saved = onDisk(model, property.id)
    eq(saved?.roomCount ?? -1, 2, "the rooms reached the disk exactly once")
    eq(saved?.floors.filter { $0.name.hasPrefix("Level 1") }.count ?? 0, 1, "one new level")
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "copy removed once it is really saved")
    check(model.unsavedPropertyIDs.isEmpty, "nothing unsaved")
    check(!prompt.willCreateProperty, "the failed try was into the existing property")
}

// Fix 2 and fix 3: the save is mended by Try again on the app's "not saved" banner, which knows nothing about the
// copy. The sheet's own Try again must still say Added; and if the sheet is never used again, the next launch clears
// the copy without a word.
@MainActor func testBannerRetryThenTheSheetsTryAgainSaysAdded() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "P")
    let seeded = seed(root: root, propertyID: property.id, propertyName: "P", story: 2,
                      rooms: [("Hall", .entrance), ("Study", .office), ("Bath", .bathroom)], delivered: true)
    let broken = BrokenFolder(model, property.id, storeRoot: storeRoot)
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    await coordinator.recover(model: model)
    guard case .failed = coordinator.phase else { check(false, "failed, got \(coordinator.phase)"); return }

    broken.repair()
    model.retryUnsavedSaves()                                   // the banner
    check(model.unsavedPropertyIDs.isEmpty, "the banner's retry saved the property")
    eq(onDisk(model, property.id)?.roomCount ?? -1, 3, "the rooms are on disk")
    check(copyExists(root, seeded), "the banner does not know about the copy, so it is still there")

    await coordinator.recover(model: model)                     // the sheet's Try again
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "Added 3 rooms to Level 2.")
    check(report.warnings.contains { $0.contains(recoveredWarning) }, "recovered-level warning kept: \(report.warnings)")
    eq(onDisk(model, property.id)?.roomCount ?? -1, 3, "still three rooms: nothing added twice")
    check(!copyExists(root, seeded), "copy removed")
}

@MainActor func testBannerRetryThenNextLaunchClearsTheCopySilently() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "P")
    let seeded = seed(root: root, propertyID: property.id, propertyName: "P", story: 1,
                      rooms: [("Hall", .entrance), ("Study", .office)], delivered: true, at: Date() - 20 * day)
    let broken = BrokenFolder(model, property.id, storeRoot: storeRoot)
    guard let result = try? ScanRecoveryStore.recoveredResult(scanID: seeded.scanID, root: root) else { check(false, "result"); return }
    // what RootView.finishScan does: the save fails, so the copy is kept
    let outcome = await ScanIntake.commit(result, to: property.id, model: model)
    check(!outcome.saved, "the save failed")
    broken.repair()
    model.retryUnsavedSaves()                                   // Try again on the "not saved" banner
    check(model.unsavedPropertyIDs.isEmpty && onDisk(model, property.id)?.roomCount == 2, "saved by the banner")
    check(copyExists(root, seeded), "the copy outlives the banner's retry")

    // the next launch: the rooms are on disk, so the copy is redundant and goes without a prompt
    let (model2, coordinator) = await relaunch(storeRoot: storeRoot, copies: root)
    check(coordinator.phase == .idle, "no 'Unfinished scan found' for a scan that is saved: \(coordinator.phase)")
    check(!copyExists(root, seeded), "the redundant copy was deleted")
    eq(onDisk(model2, property.id)?.roomCount ?? -1, 2, "the rooms are untouched")
    eq(onDisk(model2, property.id)?.floors.count ?? -1, 1, "one level")
    check(model2.presentedError == nil, "and nothing was said")
}

@MainActor func testFailedNewPropertyIsRememberedForTheRetry() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    seed(root: root, propertyID: UUID(), propertyName: "Gone", rooms: [("Hall", .entrance)])
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    // the whole store folder is replaced by a file: a new property cannot be saved
    let aside = tmp.appendingPathComponent("aside-" + UUID().uuidString)
    try? FileManager.default.moveItem(at: storeRoot, to: aside)
    try? Data("x".utf8).write(to: storeRoot)
    await coordinator.recover(model: model)
    guard case .failed(let prompt, _) = coordinator.phase else { check(false, "failed, got \(coordinator.phase)"); return }
    check(!prompt.willCreateProperty, "the property made for it is remembered, so a retry does not make another")
    check(ScanRecoveryStore.recoverableScans(root: root).count == 1, "copy kept")
    let madeID = prompt.propertyID
    try? FileManager.default.removeItem(at: storeRoot)
    try? FileManager.default.moveItem(at: aside, to: storeRoot)
    await coordinator.recover(model: model)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "Added 1 room to Level 1.", "the retry says what the recovery added")
    check(report.warnings.contains { $0.contains(recoveredWarning) }, "recovered-level warning kept: \(report.warnings)")
    eq(report.propertyID, madeID ?? UUID(), "same property")
    model.refresh()
    eq(model.summaries.count, 1, "exactly one property in the end")
    eq(onDisk(model, report.propertyID)?.roomCount ?? 0, 1)
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "copy removed")
}

// The scan's own save landed after the copy was offered (so the launch check could not delete it): Recover rooms
// finds every room already in the property and adds nothing. Nothing was recovered, so there is no
// "no 3D model" warning: the scan's own save decided what the level has.
@MainActor func testScanSavedWhileTheCopyWasOfferedIsNotAddedTwice() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")
    let seeded = seed(root: root, propertyID: property.id, propertyName: "P",
                      rooms: [("Hall", .entrance), ("Study", .office)], delivered: true)
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking"); return }
    check(prompt.scan.delivered && prompt.explanation.contains("may be saved already"), "told it may be saved already")

    // the normal path finishes saving while the prompt is on screen
    await mustSave(seeded, root: root, into: property.id, model: model)
    let before = onDisk(model, property.id)

    await coordinator.recover(model: model)
    guard case .done(_, let report) = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    eq(report.summary, "These rooms are already saved in \u{201C}P\u{201D}, so nothing was added.")
    check(report.warnings.isEmpty, "no 'recovered, no model' warning for rooms that were saved by the scan itself")
    let after = onDisk(model, property.id)
    eq(after?.roomCount ?? -1, before?.roomCount ?? -2, "no room added twice")
    eq(after?.floors.count ?? -1, before?.floors.count ?? -2, "no second level")
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "the stale copy is removed")
}

// Fix 1: at launch the same situation needs no question at all.
@MainActor func testRedundantCopyIsDeletedSilentlyAtLaunch() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "P")
    let now = Date()

    // delivered, saved by the normal path, the app ended before the copy was deleted
    let fresh = seed(root: root, propertyID: property.id, propertyName: "P", story: 1,
                     rooms: [("Hall", .entrance), ("Study", .office)], delivered: true, at: now - 60)
    await mustSave(fresh, root: root, into: property.id, model: model)
    // not delivered, and old: the rooms are in the property all the same (a recovery that was cut short before the delete)
    let stale = seed(root: root, propertyID: property.id, propertyName: "P", story: 2,
                     rooms: [("Bath", .bathroom)], delivered: false, at: now - 45 * day)
    await mustSave(stale, root: root, into: property.id, model: model)
    let before = onDisk(model, property.id)
    eq(before?.roomCount ?? -1, 3)

    // the cheap test the launch check uses agrees with the real save: applying the copy again adds nothing
    for copy in [fresh, stale] {
        guard let result = try? ScanRecoveryStore.recoveredResult(scanID: copy.scanID, root: root), let saved = before else {
            check(false, "result"); continue
        }
        eq(ScanRecoveryStore.roomIDs(scanID: copy.scanID, root: root) ?? [], result.rooms.map(\.id), "room ids of the copy = ids of the rooms it rebuilds")
        let plan = ScanCommit.apply(rooms: result.rooms, story: result.story, scannedAt: now, to: saved)
        check(plan.isNoOp && Set(plan.skippedRoomIDs) == Set(result.rooms.map(\.id)), "ScanCommit skips every room of the copy")
    }

    let (model2, coordinator) = await relaunch(storeRoot: storeRoot, copies: root)
    check(coordinator.phase == .idle, "nothing offered: \(coordinator.phase)")
    check(!copyExists(root, fresh) && !copyExists(root, stale), "both redundant copies were deleted")
    check(model2.presentedError == nil, "silently")
    eq(onDisk(model2, property.id)?.roomCount ?? -1, 3, "the property is untouched")
    eq(onDisk(model2, property.id)?.floors.count ?? -1, before?.floors.count ?? -2, "no new level")
}

// Fix 1: a copy is only deleted when everything about the proof holds. Each of these keeps the copy and offers it.
@MainActor func testACopyThatIsNotProvenRedundantIsKeptAndOffered() async {
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let now = Date()
    let old = now - 30 * day

    // A: only some of the rooms are in the property
    let a = makeProperty(model, name: "A")
    let partly = seed(root: root, propertyID: a.id, propertyName: "A", rooms: [("Hall", .entrance), ("Study", .office)],
                      delivered: true, at: old)
    await mustSave(partly, root: root, into: a.id, model: model, only: 1)

    // B: the rooms are in another property, not the one the copy belongs to
    let b = makeProperty(model, name: "B")
    let elsewhere = makeProperty(model, name: "Elsewhere")
    let wrongProperty = seed(root: root, propertyID: b.id, propertyName: "B", rooms: [("Hall", .entrance)], delivered: true, at: old)
    await mustSave(wrongProperty, root: root, into: elsewhere.id, model: model)

    // C: every room is in the property, but one capture of the copy cannot be read back
    let c = makeProperty(model, name: "C")
    let damaged = seed(root: root, propertyID: c.id, propertyName: "C", rooms: [("Hall", .entrance), ("Study", .office)],
                       delivered: true, at: old)
    await mustSave(damaged, root: root, into: c.id, model: model)
    try? Data("not json".utf8).write(to: root.appendingPathComponent(damaged.scanID.uuidString)
        .appendingPathComponent(ScanRecoveryStore.rawFileName(damaged.rawIDs[1])))
    check(ScanRecoveryStore.roomIDs(scanID: damaged.scanID, root: root) == nil, "a copy that cannot be read completely proves nothing")

    // D: the copy has no property id
    let d = makeProperty(model, name: "D")
    let anonymous = seed(root: root, propertyID: nil, propertyName: "D", rooms: [("Hall", .entrance)], delivered: true, at: old)
    await mustSave(anonymous, root: root, into: d.id, model: model)

    // E: the property is gone
    let missing = seed(root: root, propertyID: UUID(), propertyName: "Gone", rooms: [("Hall", .entrance)], delivered: true, at: old)

    // F: the rooms are in the property's backup only (property.json is damaged)
    let f = makeProperty(model, name: "F")
    let fromBackup = seed(root: root, propertyID: f.id, propertyName: "F", rooms: [("Hall", .entrance)], delivered: true, at: old)
    await mustSave(fromBackup, root: root, into: f.id, model: model)
    model.update(propertyID: f.id) { $0.notes = "a later edit" }     // the backup now holds the version with the rooms
    try? Data("broken".utf8).write(to: model.store.folderURL(for: f.id).appendingPathComponent(PropertyStore.propertyFileName))

    let (model2, coordinator) = await relaunch(storeRoot: storeRoot, copies: root)
    check(model2.summaries.first { $0.id == f.id }?.health == .recoveredFromBackup, "F reads from its backup")
    let kept: [(label: String, copy: Seeded)] = [
        ("only some rooms in the property", partly), ("rooms are in another property", wrongProperty),
        ("a capture of the copy cannot be read", damaged), ("no property id", anonymous),
        ("property is gone", missing), ("rooms only in the backup", fromBackup),
    ]
    for (label, copy) in kept { check(copyExists(root, copy), "copy kept: \(label)") }
    var offered = [coordinator.phase.promptID].compactMap { $0 }
    offered += coordinator.waiting.map(\.id)
    eq(Set(offered), Set(kept.map(\.copy.scanID)), "every one of them is offered")
}

@MainActor func testDiscardAndNotNow() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")
    let now = Date()
    let a = seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("A", .other)], at: now)
    let b = seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("B", .other)], at: now.addingTimeInterval(-10))
    let c = seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("C", .other)], at: now.addingTimeInterval(-20))
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    eq(coordinator.phase.promptID, a.scanID)

    // two quick taps on Discard must not skip a scan
    async let first: Void = coordinator.discard()
    async let second: Void = coordinator.discard()
    _ = await (first, second)
    eq(coordinator.phase.promptID, b.scanID, "moved on exactly once")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent(a.scanID.uuidString).path), "discarded copy is gone")
    check(ScanRecoveryStore.recoverableScans(root: root).count == 2, "the others stay")
    check(onDisk(model, property.id)?.roomCount == 0, "discarding adds nothing")

    // Not now keeps the rest
    coordinator.notNow()
    check(coordinator.phase == .idle && coordinator.waiting.isEmpty, "idle")
    check(ScanRecoveryStore.recoverableScans(root: root).count == 2, "Not now deletes nothing")
    _ = c
    // the sheet going away while idle is harmless
    coordinator.sheetClosed()
    check(coordinator.phase == .idle, "still idle")

    // discarding the last one ends
    let coordinator2 = ScanRecoveryCoordinator(root: root)
    await coordinator2.look(model: model)
    await coordinator2.discard()
    await coordinator2.discard()
    check(coordinator2.phase == .idle, "idle after the last discard")
    check(ScanRecoveryStore.recoverableScans(root: root).isEmpty, "all gone")
}

@MainActor func testSeveralScansOneAfterAnother() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")
    let now = Date()
    let level1 = seed(root: root, propertyID: property.id, propertyName: "P", story: 1, rooms: [("A", .other)], at: now)
    let level2 = seed(root: root, propertyID: property.id, propertyName: "P", story: 2, rooms: [("B", .other)], at: now.addingTimeInterval(-10))
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    eq(coordinator.phase.promptID, level1.scanID)
    await coordinator.recover(model: model)
    guard case .done = coordinator.phase else { check(false, "done, got \(coordinator.phase)"); return }
    check(coordinator.acknowledge() == nil, "another scan is waiting, so nothing is opened yet")
    eq(coordinator.phase.promptID, level2.scanID, "next one offered")
    await coordinator.recover(model: model)
    check(coordinator.acknowledge() == property.id, "now the property opens")
    eq(onDisk(model, property.id)?.floors.map(\.name).sorted() ?? [], ["Level 1", "Level 2"])
    check(coordinator.acknowledge() == nil, "acknowledge outside a result does nothing")
}

@MainActor func testRecoveryIsIgnoredOutsideItsPhases() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.recover(model: model)
    await coordinator.discard()
    check(coordinator.phase == .idle, "nothing happens with nothing offered")
    check(coordinator.isWorking == false, "not working")
}

@MainActor func testUnreadablePropertyIsNotReplacedByANewOne() async {
    // an unreadable property exists: the copy is offered for it, and recovering says it could not be opened
    let root = folder("copies"), storeRoot = folder("props")
    let model = makeModel(storeRoot)
    let property = makeProperty(model, name: "P")
    seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("Hall", .entrance)])
    // damage both the file and its backup, then reload the model
    let dir = model.store.folderURL(for: property.id)
    for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".json") || name.hasSuffix(".bak") {
        try? Data("broken".utf8).write(to: dir.appendingPathComponent(name))
    }
    let fresh = makeModel(storeRoot)
    check(fresh.summaries.first?.health == .unreadable, "property unreadable: \(String(describing: fresh.summaries.first?.health))")
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: fresh)
    guard case .asking(let prompt) = coordinator.phase else { check(false, "asking"); return }
    check(!prompt.willCreateProperty, "it is the same property, not a missing one")
    await coordinator.recover(model: fresh)
    guard case .failed(_, let failure) = coordinator.phase else { check(false, "failed, got \(coordinator.phase)"); return }
    // Fix 4: a restart does not mend a damaged file, so the text no longer says to restart
    eq(failure.message, "This property could not be opened, so the rooms were not added.")
    eq(failure.recovery, "Your copy is kept. You can try again later, or ask for help.")
    eq(failure.message + " " + failure.recovery,
       "This property could not be opened, so the rooms were not added. Your copy is kept. You can try again later, or ask for help.",
       "what VoiceOver is told")
    check(!(failure.message + failure.recovery).localizedCaseInsensitiveContains("restart"), "no advice to restart")
    check(ScanRecoveryStore.recoverableScans(root: root).count == 1, "copy kept")
    check(fresh.summaries.count == 1, "and no property was made for it")
    // the person can try again later: still offered, still failing the same way
    await coordinator.recover(model: fresh)
    guard case .failed(_, let again) = coordinator.phase else { check(false, "failed again, got \(coordinator.phase)"); return }
    eq(again, failure, "same words the second time")
}

// Fix 4: the property list could not be read at launch, so every property looks missing. Offering the copy would make
// a second property next to the real one, so nothing is offered or touched this launch; the next launch offers it.
@MainActor func testUnreadablePropertyListSkipsTheOffer() async {
    let root = folder("copies"), storeRoot = folder("props")
    let seededModel = makeModel(storeRoot)
    let property = makeProperty(seededModel, name: "Marina Gate 2")
    let onDiskScan = seed(root: root, propertyID: property.id, propertyName: "Marina Gate 2", rooms: [("Hall", .entrance)], delivered: true)
    let goneScan = seed(root: root, propertyID: UUID(), propertyName: "Gone", rooms: [("Hall", .entrance)])

    // storage is unreadable when the app starts: the folder of properties is a plain file
    let aside = tmp.appendingPathComponent("aside-" + UUID().uuidString)
    try? FileManager.default.moveItem(at: storeRoot, to: aside)
    try? Data("x".utf8).write(to: storeRoot)
    let broken = makeModel(storeRoot)
    check(broken.summaries.isEmpty && broken.presentedError != nil, "the list could not be read: \(String(describing: broken.presentedError))")
    check(ScanRecoveryCoordinator.propertyListUnreadable(in: broken), "recognised")
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: broken)
    check(coordinator.phase == .idle && coordinator.waiting.isEmpty, "nothing is offered this launch: \(coordinator.phase)")
    check(copyExists(root, onDiskScan) && copyExists(root, goneScan), "and nothing is deleted")
    check(broken.summaries.isEmpty && broken.memoryOnlyProperties.isEmpty, "no extra property was made")
    await coordinator.recover(model: broken)
    check(coordinator.phase == .idle, "Recover rooms has nothing to act on")

    // the next launch, with storage working again, offers them
    try? FileManager.default.removeItem(at: storeRoot)
    try? FileManager.default.moveItem(at: aside, to: storeRoot)
    let (healthy, next) = await relaunch(storeRoot: storeRoot, copies: root)
    guard case .asking = next.phase else { check(false, "asking next time, got \(next.phase)"); return }
    eq(1 + next.waiting.count, 2, "both offered")
    check(!ScanRecoveryCoordinator.propertyListUnreadable(in: healthy), "a readable list is not mistaken for a failed one")
}

// Fix 4, the other side: an error on screen with a readable list is no reason to hold the offer back.
@MainActor func testAnUnrelatedErrorDoesNotHoldBackTheOffer() async {
    let root = folder("copies"), model = makeModel(folder("props"))
    let property = makeProperty(model, name: "P")
    seed(root: root, propertyID: property.id, propertyName: "P", rooms: [("Hall", .entrance)])
    model.presentedError = UserFacingError(NSError(domain: "x", code: 1), context: "do something")
    check(!model.summaries.isEmpty && !ScanRecoveryCoordinator.propertyListUnreadable(in: model), "the list is fine")
    let coordinator = ScanRecoveryCoordinator(root: root)
    await coordinator.look(model: model)
    guard case .asking = coordinator.phase else { check(false, "asking, got \(coordinator.phase)"); return }
    // and no error at all with nothing listed (a new install) is not a failed list either
    let empty = makeModel(folder("props2"))
    check(empty.summaries.isEmpty && empty.presentedError == nil && !ScanRecoveryCoordinator.propertyListUnreadable(in: empty),
          "an empty list with no error is a new install")
}

// The store's own rules for what may be deleted.
@MainActor func testPruneNeverDeletesByAge() {
    let root = folder("copies")
    let ancient = seed(root: root, propertyID: UUID(), propertyName: "P", rooms: [("A", .other)], delivered: true,
                       at: Date() - 3650 * day)
    let abandoned = seed(root: root, propertyID: UUID(), propertyName: "P", rooms: [("B", .other)], at: Date() - 400 * day)
    let wanted = seed(root: root, propertyID: UUID(), propertyName: "P", rooms: [("C", .other), ("D", .other)], at: Date() - 1 * day)
    check(ScanRecoveryStore.prune(root: root).isEmpty, "no proof, no deletion, at any age")
    check(copyExists(root, ancient) && copyExists(root, abandoned) && copyExists(root, wanted), "all kept")
    // with proof, only what the proof names goes
    let removed = ScanRecoveryStore.prune(root: root) { $0.roomCount == 2 }
    eq(removed, [wanted.scanID])
    check(copyExists(root, ancient) && copyExists(root, abandoned) && !copyExists(root, wanted), "only the proven copy was deleted")
    // a copy that cannot be read is not even asked about
    let broken = seed(root: root, propertyID: UUID(), propertyName: "P", rooms: [("E", .other)])
    try? Data("not json".utf8).write(to: root.appendingPathComponent(broken.scanID.uuidString)
        .appendingPathComponent(ScanRecoveryStore.manifestFileName))
    var asked: [UUID] = []
    _ = ScanRecoveryStore.prune(root: root) { asked.append($0.scanID); return false }
    check(!asked.contains(broken.scanID) && copyExists(root, broken), "an unreadable copy is left alone")
}

Task { @MainActor in
    currentTest = "testPromptWording"
    testPromptWording()
    currentTest = "testPrivacyNote"
    testPrivacyNote()
    currentTest = "testPruneNeverDeletesByAge"
    testPruneNeverDeletesByAge()
    currentTest = "testLookOffersNewestFirstAndOnlyOnce"
    await testLookOffersNewestFirstAndOnlyOnce()
    currentTest = "testNothingToOffer"
    await testNothingToOffer()
    currentTest = "testOldCopiesAreOfferedNotDropped"
    await testOldCopiesAreOfferedNotDropped()
    currentTest = "testFailedSaveThenRelaunchWeeksLaterStillOffersTheScan"
    await testFailedSaveThenRelaunchWeeksLaterStillOffersTheScan()
    currentTest = "testRecoverIntoTheExistingProperty"
    await testRecoverIntoTheExistingProperty()
    currentTest = "testRecoverMakesANewPropertyWhenTheOldOneIsGone"
    await testRecoverMakesANewPropertyWhenTheOldOneIsGone()
    currentTest = "testUnreadableCopyKeepsItAndSaysWhatToDo"
    await testUnreadableCopyKeepsItAndSaysWhatToDo()
    currentTest = "testFailedSaveKeepsTheCopyAndRetryDoesNotDuplicate"
    await testFailedSaveKeepsTheCopyAndRetryDoesNotDuplicate()
    currentTest = "testBannerRetryThenTheSheetsTryAgainSaysAdded"
    await testBannerRetryThenTheSheetsTryAgainSaysAdded()
    currentTest = "testBannerRetryThenNextLaunchClearsTheCopySilently"
    await testBannerRetryThenNextLaunchClearsTheCopySilently()
    currentTest = "testFailedNewPropertyIsRememberedForTheRetry"
    await testFailedNewPropertyIsRememberedForTheRetry()
    currentTest = "testScanSavedWhileTheCopyWasOfferedIsNotAddedTwice"
    await testScanSavedWhileTheCopyWasOfferedIsNotAddedTwice()
    currentTest = "testRedundantCopyIsDeletedSilentlyAtLaunch"
    await testRedundantCopyIsDeletedSilentlyAtLaunch()
    currentTest = "testACopyThatIsNotProvenRedundantIsKeptAndOffered"
    await testACopyThatIsNotProvenRedundantIsKeptAndOffered()
    currentTest = "testDiscardAndNotNow"
    await testDiscardAndNotNow()
    currentTest = "testSeveralScansOneAfterAnother"
    await testSeveralScansOneAfterAnother()
    currentTest = "testRecoveryIsIgnoredOutsideItsPhases"
    await testRecoveryIsIgnoredOutsideItsPhases()
    currentTest = "testUnreadablePropertyIsNotReplacedByANewOne"
    await testUnreadablePropertyIsNotReplacedByANewOne()
    currentTest = "testUnreadablePropertyListSkipsTheOffer"
    await testUnreadablePropertyListSkipsTheOffer()
    currentTest = "testAnUnrelatedErrorDoesNotHoldBackTheOffer"
    await testAnUnrelatedErrorDoesNotHoldBackTheOffer()
    try? FileManager.default.removeItem(at: tmp)
    print("checks: \(checks), failures: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
