import Foundation
import NexaFixCore

// A safety copy of a scan that has not been handed over yet.
//
// The scan screen keeps every finished room in memory until "Finish property". If iOS ends the app in
// between (a long call or message between rooms, the phone running low on memory), those rooms are gone and
// the person has to walk the floor again. This store writes each room to disk the moment it is built, so a
// scan interrupted that way can be put back.
//
// What is kept, per room: the `RawCapture` (what the parametric room is rebuilt from) and the `CapturedRoom`
// JSON (the detailed scan data that belongs next to the room). Apple documents `CapturedRoom` as Codable and
// says to keep scan results "for processing at a later date".
// What cannot be kept: the AR session (so no AR map, and no joined 3D model, because that is made from the
// live session while the property is finished). A recovered scan says so in its warnings.
//
// Foundation and NexaFixCore only, so this file is type-checked on Linux with the rest of the pure code.
//
// Where it lives: `Application Support/ScanRecovery/<scan id>/`, not in Documents, so it is not offered
// in the Files app, and excluded from backups. Ages (for `prune`) are read from the manifest, never from file
// attributes: the privacy manifest declares no file-timestamp API, so none may be used.

final class ScanRecoveryStore: @unchecked Sendable {

    // MARK: What is written

    /// `manifest.json`: which rooms belong to the scan and what they were named.
    struct Manifest: Codable, Equatable {
        struct RoomEntry: Codable, Equatable {
            /// The controller's id for the room; the file names are built from it.
            var id: UUID
            /// nil until the person has named the room.
            var name: String?
            var kind: RoomKind?
        }

        var version: Int
        var scanID: UUID
        /// The property the scan was started for, when the caller said (see `ScanConfiguration.propertyID`).
        var propertyID: UUID?
        var propertyName: String
        var story: Int
        /// Names the property already had, so unnamed rooms never take one of them.
        var existingRoomNames: [String]
        var createdAt: Date
        var updatedAt: Date
        /// True once the finished scan was handed to the app to save. The copy stays until the save is
        /// confirmed (`discard(scanID:)`) or it is old enough to be dropped (`prune`).
        var delivered: Bool
        /// In scan order.
        var rooms: [RoomEntry]
    }

    static let currentVersion = 1
    static let folderName = "ScanRecovery"
    static let manifestFileName = "manifest.json"

    /// A delivered scan that nobody confirmed is dropped after this long, seconds.
    static let deliveredLifetime: TimeInterval = 7 * 24 * 3600
    /// A scan that was never delivered is kept this long, seconds.
    static let abandonedLifetime: TimeInterval = 30 * 24 * 3600

    /// `Application Support/ScanRecovery`, falling back to the temporary directory if that cannot be found.
    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: State

    let scanID: UUID
    private let root: URL
    private let folder: URL
    private let queue = DispatchQueue(label: "com.nexafix.scan-recovery", qos: .utility)

    // Everything below is touched only on `queue`.
    private var manifest: Manifest
    private var isFolderReady = false
    private var isDiscarded = false

    /// - Parameters:
    ///   - root: The folder that holds every scan's folder. Nothing is written until the first room is added.
    init(root: URL = ScanRecoveryStore.defaultRoot,
         scanID: UUID = UUID(),
         propertyID: UUID? = nil,
         propertyName: String,
         story: Int,
         existingRoomNames: [String] = [],
         now: Date = Date()) {
        self.scanID = scanID
        self.root = root
        self.folder = root.appendingPathComponent(scanID.uuidString, isDirectory: true)
        self.manifest = Manifest(version: Self.currentVersion, scanID: scanID, propertyID: propertyID,
                                 propertyName: propertyName, story: story, existingRoomNames: existingRoomNames,
                                 createdAt: now, updatedAt: now, delivered: false, rooms: [])
    }

    // MARK: Writing (never blocks the caller)

    /// A room was built. Its files are written first and the manifest second, so the manifest never names a
    /// file that is not there.
    func addRoom(id: UUID, raw: RawCapture, capturedJSON: Data?, now: Date = Date()) {
        queue.async { [self] in
            guard !isDiscarded, prepareFolder() else { return }
            guard write(Self.encode(raw), to: Self.rawFileName(id)) else { return }
            if let capturedJSON, !capturedJSON.isEmpty {
                _ = write(capturedJSON, to: Self.capturedFileName(id))
            }
            if !manifest.rooms.contains(where: { $0.id == id }) {
                manifest.rooms.append(Manifest.RoomEntry(id: id, name: nil, kind: nil))
            }
            saveManifest(now: now)
        }
    }

    /// The person named the room.
    func setName(id: UUID, name: String, kind: RoomKind, now: Date = Date()) {
        queue.async { [self] in
            guard !isDiscarded, let index = manifest.rooms.firstIndex(where: { $0.id == id }) else { return }
            manifest.rooms[index].name = name
            manifest.rooms[index].kind = kind
            saveManifest(now: now)
        }
    }

    /// The room was thrown away (rescanned or discarded): it must not come back after a restart.
    func removeRoom(id: UUID, now: Date = Date()) {
        queue.async { [self] in
            guard !isDiscarded, manifest.rooms.contains(where: { $0.id == id }) else { return }
            manifest.rooms.removeAll { $0.id == id }
            saveManifest(now: now)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.rawFileName(id)))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.capturedFileName(id)))
        }
    }

    /// The finished scan was handed to the app to save. The copy stays until the save is confirmed.
    func markDelivered(now: Date = Date()) {
        queue.async { [self] in
            guard !isDiscarded, isFolderReady else { return }
            manifest.delivered = true
            saveManifest(now: now)
        }
    }

    /// The person left without saving, on purpose: nothing of this scan is kept.
    func discard() {
        queue.async { [self] in
            isDiscarded = true
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Waits until every write queued so far is on disk. For tests and for code that reads straight after.
    func flush() {
        queue.sync {}
    }

    // MARK: Writing, on the queue

    private func prepareFolder() -> Bool {
        if isFolderReady { return true }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }
        #if canImport(Darwin)
        // A safety copy is not worth space in an iCloud or computer backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = root
        try? excluded.setResourceValues(values)
        #endif
        isFolderReady = true
        return true
    }

    private func write(_ data: Data?, to fileName: String) -> Bool {
        guard let data else { return false }
        do {
            try data.write(to: folder.appendingPathComponent(fileName), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func saveManifest(now: Date) {
        manifest.updatedAt = now
        _ = write(Self.encode(manifest), to: Self.manifestFileName)
    }

    // MARK: File names and coding

    static func rawFileName(_ id: UUID) -> String { "room-\(id.uuidString).raw.json" }
    static func capturedFileName(_ id: UUID) -> String { "room-\(id.uuidString).captured.json" }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                      negativeInfinity: "-inf",
                                                                      nan: "nan")
        return try? encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                        negativeInfinity: "-inf",
                                                                        nan: "nan")
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - Reading back

extension ScanRecoveryStore {

    /// A scan found on disk, for a "Recover an unsaved scan" prompt.
    struct RecoverableScan: Equatable, Identifiable {
        var scanID: UUID
        var propertyID: UUID?
        var propertyName: String
        var story: Int
        /// Rooms that can still be read back.
        var roomCount: Int
        var createdAt: Date
        var updatedAt: Date
        /// True when the scan was handed over to be saved. Then the save may have worked; offer it only if the
        /// property does not have the floor.
        var delivered: Bool

        var id: UUID { scanID }
    }

    enum RecoveryError: Error, Equatable {
        /// No readable room is left in the copy.
        case nothingToRecover
    }

    /// Every scan copy on disk, newest first. Copies that cannot be read are skipped, not deleted.
    static func recoverableScans(root: URL = ScanRecoveryStore.defaultRoot) -> [RecoverableScan] {
        folders(in: root).compactMap { folder in
            guard let manifest = readManifest(in: folder) else { return nil }
            let readable = manifest.rooms.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent(rawFileName($0.id)).path) }
            guard !readable.isEmpty else { return nil }
            return RecoverableScan(scanID: manifest.scanID, propertyID: manifest.propertyID,
                                   propertyName: manifest.propertyName, story: manifest.story,
                                   roomCount: readable.count, createdAt: manifest.createdAt,
                                   updatedAt: manifest.updatedAt, delivered: manifest.delivered)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Rebuilds the scan as a `ScanResult` the app can save like a finished one. It has the rooms and their
    /// detailed scan data, and no joined 3D model and no AR map, which the warnings say. Slow for a big
    /// floor (it rebuilds every room): call it off the main thread.
    static func recoveredResult(scanID: UUID, root: URL = ScanRecoveryStore.defaultRoot) throws -> ScanResult {
        let folder = root.appendingPathComponent(scanID.uuidString, isDirectory: true)
        guard let manifest = readManifest(in: folder) else { throw RecoveryError.nothingToRecover }

        var taken = manifest.existingRoomNames
        var rooms: [Room] = []
        var captured: [UUID: Data] = [:]
        var warnings: [String] = [
            "This scan was recovered after the app closed before the property was finished. It has no joined 3D model and no AR map, so AR review will not line up on this level. Scan the level again on site to get them.",
        ]
        var unreadable = 0

        for entry in manifest.rooms {
            guard let rawData = try? Data(contentsOf: folder.appendingPathComponent(rawFileName(entry.id))),
                  let raw = decode(RawCapture.self, from: rawData) else {
                unreadable += 1
                continue
            }
            let name: String
            if let given = entry.name, !given.isEmpty {
                name = given
            } else {
                name = RoomKindSuggester.freeName(base: "Room", taken: taken)
                warnings.append("\(name) had not been named when the app closed. Check its name.")
            }
            taken.append(name)

            let built = RoomReconstructor.build(from: raw, name: name, kind: entry.kind ?? .other)
            rooms.append(built.room)
            if let json = try? Data(contentsOf: folder.appendingPathComponent(capturedFileName(entry.id))), !json.isEmpty {
                captured[built.room.id] = json
            }
            for warning in built.warnings where warning.severity >= .caution {
                warnings.append("\(name): \(warning.message)")
            }
        }

        guard !rooms.isEmpty else { throw RecoveryError.nothingToRecover }
        if unreadable > 0 {
            warnings.append(unreadable == 1
                ? "One room could not be read back and is missing."
                : "\(unreadable) rooms could not be read back and are missing.")
        }
        return ScanResult(rooms: rooms, capturedRoomJSON: captured, structureUSDZ: nil, worldMapData: nil,
                          story: manifest.story, warnings: warnings, recoveryID: scanID)
    }

    /// Deletes a scan copy. Call it once the scan is safely saved, or the person chose to drop it.
    static func discard(scanID: UUID, root: URL = ScanRecoveryStore.defaultRoot) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(scanID.uuidString, isDirectory: true))
    }

    /// Drops copies that are old enough that nobody is coming back for them.
    static func prune(root: URL = ScanRecoveryStore.defaultRoot, now: Date = Date()) {
        for folder in folders(in: root) {
            guard let manifest = readManifest(in: folder) else { continue }
            let age = now.timeIntervalSince(manifest.updatedAt)
            let limit = manifest.delivered ? deliveredLifetime : abandonedLifetime
            if age > limit { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private static func folders(in root: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    private static func readManifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestFileName)),
              let manifest = decode(Manifest.self, from: data),
              manifest.version <= currentVersion else { return nil }
        return manifest
    }
}
