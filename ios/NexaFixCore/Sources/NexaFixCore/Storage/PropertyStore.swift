import Foundation

// On-disk storage for properties.
//
// Layout (one folder per property, named by its id):
//
//   <root>/<PROPERTY-UUID>/property.json          the envelope {"schemaVersion": 1, "property": {...}}
//   <root>/<PROPERTY-UUID>/property.json.bak      the previous good property.json (one generation)
//   <root>/<PROPERTY-UUID>/property.json.corrupt  a property.json that failed to decode, set aside
//   <root>/<PROPERTY-UUID>/...                    assets: USDZ, RoomPlan JSON, world maps, photos
//
// Guarantees:
//  - Atomic writes: a save writes a temporary file next to the target and swaps it in, so a crash
//    or power loss leaves either the old file or the new one, never half of each.
//  - One backup generation: before a save replaces a property.json that still decodes, its bytes
//    become property.json.bak. A property.json that does NOT decode is never promoted to backup.
//  - Recovery: when property.json is unreadable, `load` falls back to the backup and says so.
//  - No silent edits: `save` stores exactly what it is given. `updatedAt` only changes when the
//    caller passes a date to stamp it with.
//  - Dates survive a round trip bit for bit (fractional-second ISO 8601); unknown JSON keys are
//    ignored on read; schema changes go through `Migration`s.
//  - Damaged bytes never crash the app: the file is checked with a strict parser before Foundation's
//    JSONDecoder sees it (see `requireStrictJSON`), so a bad object key is damage like any other.
//  - Recovery stays visible: a damaged file that was set aside is kept as property.json.corrupt and
//    reported by `PropertySummary.damagedFileKept` until `clearDamagedFile(id:)` is called, even after
//    later saves have made the property healthy again.
//  - Asset paths are checked against path traversal (`..`, absolute paths, symlinks that leave the
//    property folder). Paths are split on Unicode scalars, never on Characters: "/" followed by a
//    combining mark is one Character but still a path separator to the file system.
//  - Thread safety: one store serialises its own operations with a lock. Share one instance per
//    root folder; several instances on one folder never see a torn file, but can interleave.

// MARK: - Errors

public enum PropertyStoreError: Error, Equatable, LocalizedError, Sendable {
    /// No property with this id on disk.
    case notFound(UUID)
    /// property.json and its backup are both unreadable.
    case corrupt(UUID, reason: String)
    /// The file was written by a newer version of the app.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The file is older than the current format and no migration is registered for this step.
    case missingMigration(from: Int)
    /// The relative path is empty, absolute, contains `..`, or leaves the property folder.
    case unsafePath(String)
    /// The relative path names one of the store's own files.
    case reservedPath(String)
    /// The target of an asset write is a folder, or a parent is a file.
    case invalidAssetTarget(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "This property could not be found on the device."
        case .corrupt(_, let reason):
            return "This property's file is damaged and its backup could not be read (\(reason))."
        case .unsupportedSchemaVersion(let found, let supported):
            return "This property was saved by a newer version of NexaFix Scan (file format \(found); this version reads up to \(supported)). Update the app to open it."
        case .missingMigration(let from):
            return "This property uses an old file format (\(from)) that this version cannot upgrade."
        case .unsafePath(let path):
            return "The file path \"\(path)\" is not allowed."
        case .reservedPath(let path):
            return "The file name \"\(path)\" is reserved."
        case .invalidAssetTarget(let path):
            return "Cannot write a file at \"\(path)\"."
        }
    }
}

// MARK: - Summaries and load results

/// One row of the property list.
public struct PropertySummary: Codable, Hashable, Identifiable, Sendable {

    public enum Health: String, Codable, Sendable {
        /// property.json read fine.
        case ok
        /// property.json was damaged; the values come from the backup.
        case recoveredFromBackup
        /// Neither file could be read. Name and counts are placeholders.
        case unreadable
    }

    public var id: UUID
    public var name: String
    public var client: String
    public var kind: PropertyKind
    public var roomCount: Int
    /// Sum of the rooms' effective floor areas, m².
    public var floorAreaM2: Double
    public var updatedAt: Date
    /// Dimensions with a site check divided by dimensions that can be checked, 0...1 (0 when none).
    public var verifiedFraction: Double
    public var health: Health
    /// A sentence for the user when `health` is not `.ok`.
    public var problem: String?
    /// A damaged property.json was set aside as property.json.corrupt by an earlier save and has not been
    /// cleared yet. Unlike `health`, this stays true after the next successful save, so the app can keep
    /// telling the user that changes may have been lost. See `PropertyStore.clearDamagedFile(id:)`.
    public var damagedFileKept: Bool

    public init(id: UUID, name: String, client: String, kind: PropertyKind, roomCount: Int, floorAreaM2: Double,
                updatedAt: Date, verifiedFraction: Double, health: Health = .ok, problem: String? = nil,
                damagedFileKept: Bool = false) {
        self.id = id
        self.name = name
        self.client = client
        self.kind = kind
        self.roomCount = roomCount
        self.floorAreaM2 = floorAreaM2
        self.updatedAt = updatedAt
        self.verifiedFraction = verifiedFraction
        self.health = health
        self.problem = problem
        self.damagedFileKept = damagedFileKept
    }
}

/// A property read from disk together with how the read went.
public struct LoadedProperty: Sendable {
    public var property: Property
    /// property.json was unreadable and this is the previous save from property.json.bak.
    /// Saving again keeps the damaged file aside as property.json.corrupt.
    public var recoveredFromBackup: Bool
    /// Why property.json was rejected, when `recoveredFromBackup`.
    public var recoveryReason: String?
    /// Schema version the file declared (0 for a bare, unversioned property).
    public var schemaVersionOnDisk: Int
    /// The data went through at least one migration on its way in.
    public var migrated: Bool
}

// MARK: - Store

public final class PropertyStore: @unchecked Sendable {

    /// The schema version this build writes and reads natively.
    public static let currentSchemaVersion = 1

    public static let propertyFileName = "property.json"
    public static let backupFileName = "property.json.bak"
    public static let corruptFileName = "property.json.corrupt"

    /// An upgrade step from one schema version to the next.
    ///
    /// `transform` receives the whole decoded JSON document (for version 0 that is the bare
    /// property object; from version 1 on it is the envelope `{"schemaVersion", "property"}`) and
    /// edits it in place into the shape of version `from + 1`. The store then stamps
    /// `schemaVersion = from + 1`.
    public struct Migration: Sendable {
        public let from: Int
        public let transform: @Sendable (_ document: inout [String: Any]) throws -> Void

        public init(from: Int, transform: @escaping @Sendable (_ document: inout [String: Any]) throws -> Void) {
            self.from = from
            self.transform = transform
        }

        /// Version 0 files were a bare property with no envelope.
        static let wrapBareProperty = Migration(from: 0) { doc in
            doc = ["schemaVersion": 1, "property": doc]
        }
    }

    public let rootURL: URL

    private let migrations: [Int: Migration]
    private let lock = NSLock()

    public init(rootURL: URL, migrations: [Migration] = []) {
        self.rootURL = rootURL
        var table: [Int: Migration] = [Migration.wrapBareProperty.from: Migration.wrapBareProperty]
        for m in migrations { table[m.from] = m }
        self.migrations = table
    }

    private var fileManager: FileManager { .default }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Locations

    /// `<root>/<UUID>/`
    public func folderURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func propertyFileURL(_ id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent(Self.propertyFileName, isDirectory: false)
    }

    private func backupFileURL(_ id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent(Self.backupFileName, isDirectory: false)
    }

    private func corruptFileURL(_ id: UUID) -> URL {
        folderURL(for: id).appendingPathComponent(Self.corruptFileName, isDirectory: false)
    }

    // MARK: List

    /// Every property on disk, newest `updatedAt` first (ties by name, then id). Properties whose
    /// files cannot be read are listed too, as `.unreadable`, so a damaged survey never silently
    /// disappears from the list. Folders that are not property folders are ignored.
    ///
    /// Cost: every property.json is read and fingerprinted, but only files whose bytes changed since the
    /// last call (or that this store instance has not seen yet) are decoded. A list of 100 unchanged
    /// 40 KB properties is a few milliseconds; the first call, or one after many outside edits, costs a
    /// full decode of each changed file. The call blocks while it holds the store's lock, so run it off
    /// the main actor when the list is large.
    public func list() throws -> [PropertySummary] {
        try locked {
            guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
            let names = try fileManager.contentsOfDirectory(atPath: rootURL.path)
            var out: [PropertySummary] = []
            var seen: Set<UUID> = []
            for name in names {
                guard let id = UUID(uuidString: name) else { continue }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path,
                                             isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                let hasData = fileManager.fileExists(atPath: propertyFileURL(id).path)
                    || fileManager.fileExists(atPath: backupFileURL(id).path)
                guard hasData else { continue }   // e.g. assets written before the first save
                seen.insert(id)
                var row = summaryLocked(id: id)
                row.damagedFileKept = fileManager.fileExists(atPath: corruptFileURL(id).path)
                out.append(row)
            }
            // Forget properties that are gone, so the cache cannot outgrow the store.
            for id in summaryCache.keys where !seen.contains(id) { summaryCache[id] = nil }
            out.sort { a, b in
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                let an = a.name.lowercased(), bn = b.name.lowercased()
                if an != bn { return an < bn }
                return a.id.uuidString < b.id.uuidString
            }
            return out
        }
    }

    /// What the cache remembers about one property: the bytes it was computed from and the result.
    /// `backup` is set only for a summary that came from property.json.bak.
    private struct CachedSummary {
        var primary: Fingerprint?
        var backup: Fingerprint?
        var summary: PropertySummary
    }

    /// Length and a 64-bit hash over every byte, eight bytes at a time (a 1.5 MB file takes well under a
    /// millisecond in a release build). Not cryptographic: it only has to notice that a file changed, and
    /// a change is a different length or a different multiply-xorshift chain over all of its bytes.
    /// (`Data.hashValue` is not used: some Foundation versions hash only the first bytes of a Data.)
    private struct Fingerprint: Equatable {
        let count: Int
        let hash: UInt64

        init(_ data: Data) {
            var h: UInt64 = 0xCBF2_9CE4_8422_2325
            data.withUnsafeBytes { buffer in
                let words = buffer.count / 8
                for i in 0..<words {
                    h = (h ^ buffer.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)) &* 0x9E37_79B9_7F4A_7C15
                    h ^= h >> 29
                }
                for i in (words * 8)..<buffer.count {
                    h = (h ^ UInt64(buffer[i])) &* 0x0000_0100_0000_01B3
                }
            }
            count = data.count
            hash = h
        }
    }

    private var summaryCache: [UUID: CachedSummary] = [:]
    private var fullSummaryDecodes = 0

    /// How many times `list()` had to decode a property file. Tests use it to prove the cache works.
    var summaryDecodeCount: Int { locked { fullSummaryDecodes } }

    /// The list row for one property, from the cache when the files are byte-identical to the ones the
    /// cached row was computed from, otherwise from a full read. Unreadable rows are never cached.
    private func summaryLocked(id: UUID) -> PropertySummary {
        let primaryBytes = try? Data(contentsOf: propertyFileURL(id))
        let primaryPrint = primaryBytes.map(Fingerprint.init)
        if let cached = summaryCache[id], cached.primary == primaryPrint {
            guard let wanted = cached.backup else { return cached.summary }          // decided by the primary alone
            if let backupBytes = try? Data(contentsOf: backupFileURL(id)), Fingerprint(backupBytes) == wanted {
                return cached.summary
            }
        }
        fullSummaryDecodes += 1
        do {
            let read = try loadDetailed(id: id, primaryBytes: primaryBytes)
            let row = Self.summary(of: read.loaded)
            summaryCache[id] = CachedSummary(primary: primaryPrint, backup: read.backupBytes.map(Fingerprint.init), summary: row)
            return row
        } catch {
            summaryCache[id] = nil
            return PropertySummary(
                id: id, name: "Unreadable property", client: "", kind: .other, roomCount: 0,
                floorAreaM2: 0, updatedAt: .distantPast, verifiedFraction: 0, health: .unreadable,
                problem: (error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// The summary of ONE property, read from its own files only. Cheaper than `list()` (which reads
    /// every property) when a single property has just been saved.
    public func summary(id: UUID) throws -> PropertySummary {
        try locked { Self.summary(of: try loadLocked(id: id)) }
    }

    private static func summary(of loaded: LoadedProperty) -> PropertySummary {
        let p = loaded.property
        let counts = DataMeasureList.counts(for: p)
        let area = p.allRooms.reduce(0.0) { $0 + $1.metrics.effectiveFloorArea }
        return PropertySummary(
            id: p.id, name: p.name, client: p.client, kind: p.kind, roomCount: p.roomCount,
            floorAreaM2: DataNumber.round4(area), updatedAt: p.updatedAt,
            verifiedFraction: counts.total == 0 ? 0 : Double(counts.verified) / Double(counts.total),
            health: loaded.recoveredFromBackup ? .recoveredFromBackup : .ok,
            problem: loaded.recoveredFromBackup
                ? "The saved file was damaged; this is the previous save. Check the latest changes."
                : nil)
    }

    // MARK: Load

    /// Load a property. Falls back to the backup when property.json is damaged, and **does not tell you
    /// so**: use `loadWithStatus(id:)` wherever the user should hear about it. (`list()` reports it per
    /// row, and `PropertySummary.damagedFileKept` keeps reporting it after the next save.)
    public func load(id: UUID) throws -> Property {
        try loadWithStatus(id: id).property
    }

    public func loadWithStatus(id: UUID) throws -> LoadedProperty {
        try locked { try loadLocked(id: id) }
    }

    private func loadLocked(id: UUID) throws -> LoadedProperty {
        try loadDetailed(id: id, primaryBytes: nil).loaded
    }

    /// A load together with the exact bytes it was decoded from. `primaryBytes` may carry the bytes of
    /// property.json when the caller has already read them.
    private struct DetailedLoad {
        var loaded: LoadedProperty
        /// The bytes of property.json when it was present and readable (decoded or not).
        var primaryBytes: Data?
        /// The bytes of property.json.bak when the result came from it.
        var backupBytes: Data?
    }

    private func loadDetailed(id: UUID, primaryBytes preread: Data?) throws -> DetailedLoad {
        let primary = propertyFileURL(id), backup = backupFileURL(id)
        let hasPrimary = preread != nil || fileManager.fileExists(atPath: primary.path)
        let hasBackup = fileManager.fileExists(atPath: backup.path)
        guard hasPrimary || hasBackup else { throw PropertyStoreError.notFound(id) }

        var primaryReason = "property.json is missing"
        var primaryBytes = preread
        if hasPrimary {
            do {
                let data = try preread ?? Data(contentsOf: primary)
                primaryBytes = data
                let loaded = try read(data, expecting: id, recovered: false, reason: nil)
                return DetailedLoad(loaded: loaded, primaryBytes: data, backupBytes: nil)
            } catch let e as PropertyStoreError {
                switch e {
                case .unsupportedSchemaVersion, .missingMigration:
                    throw e   // not damage: a newer or unknown format. Never fall back and risk overwriting it.
                default:
                    primaryReason = "property.json: \(Self.describe(e))"
                }
            } catch {
                primaryReason = "property.json: \(Self.describe(error))"
            }
        }
        guard hasBackup else { throw PropertyStoreError.corrupt(id, reason: primaryReason) }
        do {
            let data = try Data(contentsOf: backup)
            let loaded = try read(data, expecting: id, recovered: true, reason: primaryReason)
            return DetailedLoad(loaded: loaded, primaryBytes: primaryBytes, backupBytes: data)
        } catch let e as PropertyStoreError {
            switch e {
            case .unsupportedSchemaVersion, .missingMigration: throw e
            default: throw PropertyStoreError.corrupt(id, reason: primaryReason + "; property.json.bak: \(Self.describe(e))")
            }
        } catch {
            throw PropertyStoreError.corrupt(id, reason: primaryReason + "; property.json.bak: \(Self.describe(error))")
        }
    }

    private func read(_ data: Data, expecting id: UUID, recovered: Bool, reason: String?) throws -> LoadedProperty {
        let decoded = try decodeFile(data)
        guard decoded.property.id == id else {
            throw PropertyStoreError.corrupt(id, reason: "the file holds property \(decoded.property.id.uuidString)")
        }
        return LoadedProperty(property: decoded.property, recoveredFromBackup: recovered, recoveryReason: reason,
                              schemaVersionOnDisk: decoded.version, migrated: decoded.migrated)
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? PropertyStoreError, case .corrupt(_, let reason) = e { return reason }
        if let e = error as? UnreadableFile { return e.reason }
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c): return "data corrupted (\(c.debugDescription))"
            case .keyNotFound(let k, _): return "missing key \"\(k.stringValue)\""
            case .typeMismatch(_, let c), .valueNotFound(_, let c): return "unexpected value at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default: return "unreadable"
            }
        }
        return (error as NSError).localizedDescription
    }

    // MARK: Set-aside files

    /// The damaged property.json that a save set aside as property.json.corrupt, if one is kept.
    public func damagedFileURL(for id: UUID) -> URL? {
        locked {
            let url = corruptFileURL(id)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Delete the kept damaged file once the user has been told about it (or it has been inspected).
    /// Returns false when there was none. The property itself is not touched.
    @discardableResult
    public func clearDamagedFile(id: UUID) throws -> Bool {
        try locked {
            let url = corruptFileURL(id)
            guard fileManager.fileExists(atPath: url.path) else { return false }
            try fileManager.removeItem(at: url)
            return true
        }
    }

    // MARK: Save

    /// Write a property atomically, keeping the previous good file as property.json.bak.
    ///
    /// The property is stored exactly as given. Pass `stampUpdatedAt` to set `updatedAt` first
    /// (the stamped copy is what gets stored and returned); with nil, nothing is changed.
    /// Refuses to write anything that could not be read back.
    @discardableResult
    public func save(_ property: Property, stampUpdatedAt now: Date? = nil) throws -> Property {
        var p = property
        if let now { p.updatedAt = now }
        let data = try Self.encode(p)
        _ = try decodeFile(data)   // never write a file we could not read back
        try locked { try writeLocked(data, for: p.id) }
        return p
    }

    private func writeLocked(_ data: Data, for id: UUID) throws {
        let folder = folderURL(for: id)
        let primary = propertyFileURL(id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        if let existing = try? Data(contentsOf: primary) {
            if existing == data { return }   // nothing changed: keep the older backup meaningful
            var existingIsGood = false
            do {
                _ = try decodeFile(existing)
                existingIsGood = true
            } catch let error as PropertyStoreError {
                switch error {
                case .unsupportedSchemaVersion, .missingMigration:
                    throw error      // not damage: never overwrite a file this version cannot interpret
                default:
                    break
                }
            } catch {
                // damaged: handled below
            }
            if existingIsGood {
                // If the backup cannot be written the save stops here, before the only good copy is replaced.
                try existing.write(to: backupFileURL(id), options: .atomic)
            } else {
                // Keep the damaged bytes for diagnosis; never let them replace a good backup.
                try? existing.write(to: corruptFileURL(id), options: .atomic)
            }
        }
        try data.write(to: primary, options: .atomic)
    }

    // MARK: Delete

    /// Remove a property and everything in its folder. Returns false when there was nothing to delete.
    @discardableResult
    public func delete(id: UUID) throws -> Bool {
        try locked {
            let folder = folderURL(for: id)
            guard fileManager.fileExists(atPath: folder.path) else { return false }
            try fileManager.removeItem(at: folder)
            return true
        }
    }

    // MARK: Duplicate

    /// Copy a property (data and asset files) under brand-new ids and save it.
    ///
    /// Blocking: the asset files (USDZ models, world maps) are copied while the store's lock is held, so
    /// call this off the main actor.
    ///
    /// Every id in the tree is new: property, floors, rooms, walls, openings, objects and custom
    /// measurements; openings keep pointing at the copies of their walls. File references stay
    /// valid because the asset files are copied to the same relative paths. The copy appears in
    /// `list()` only once it is complete.
    ///
    /// - Parameters:
    ///   - newName: name of the copy (default: "<name> copy").
    ///   - now: becomes `createdAt` and `updatedAt` of the copy.
    ///   - makeID: id source; pass a seeded one for reproducible tests.
    @discardableResult
    public func duplicate(id: UUID, newName: String? = nil, now: Date = Date(),
                          makeID: () -> UUID = { UUID() }) throws -> Property {
        try locked {
            let source = try loadLocked(id: id).property
            var copy = Self.cloneWithNewIDs(source, makeID: makeID)
            copy.name = newName ?? "\(source.name) copy"
            copy.createdAt = now
            copy.updatedAt = now

            let data = try Self.encode(copy)
            _ = try decodeFile(data)

            let staging = rootURL.appendingPathComponent(".duplicating-\(copy.id.uuidString)", isDirectory: true)
            let target = folderURL(for: copy.id)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            do {
                let sourceFolder = folderURL(for: id)
                let reserved: Set<String> = [Self.propertyFileName, Self.backupFileName, Self.corruptFileName]
                for name in (try? fileManager.contentsOfDirectory(atPath: sourceFolder.path)) ?? []
                where !reserved.contains(name) {
                    try fileManager.copyItem(at: sourceFolder.appendingPathComponent(name),
                                             to: staging.appendingPathComponent(name))
                }
                try data.write(to: staging.appendingPathComponent(Self.propertyFileName), options: .atomic)
                try fileManager.moveItem(at: staging, to: target)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
            return copy
        }
    }

    /// A copy of the property in which every id is new and wall references are remapped.
    /// Ids are drawn from `makeID` in a fixed order (property, then per floor: floor, then per
    /// room: room, walls, openings, objects, custom measurements).
    public static func cloneWithNewIDs(_ property: Property, makeID: () -> UUID = { UUID() }) -> Property {
        var p = property
        p.id = makeID()
        p.floors = property.floors.map { floor in
            var f = floor
            f.id = makeID()
            f.rooms = floor.rooms.map { room in
                var r = room
                r.id = makeID()
                var wallMap: [UUID: UUID] = [:]
                r.walls = room.walls.map { wall in
                    var w = wall
                    let new = makeID()
                    // A repeated old id (damaged data) keeps pointing at one wall.
                    w.id = wallMap[wall.id] ?? new
                    wallMap[wall.id] = w.id
                    return w
                }
                r.openings = room.openings.map { opening in
                    var o = opening
                    o.id = makeID()
                    if let old = opening.wallID, let new = wallMap[old] { o.wallID = new }
                    return o
                }
                r.objects = room.objects.map { object in
                    var o = object
                    o.id = makeID()
                    return o
                }
                r.customMeasurements = room.customMeasurements.map { custom in
                    var c = custom
                    c.id = makeID()
                    return c
                }
                return r
            }
            return f
        }
        return p
    }

    // MARK: Assets

    /// The absolute URL of `relativePath` inside a property's folder, or an error when the path is
    /// not safe: empty, absolute (`/etc/passwd`), home-relative (`~/x`), containing `..` or `.`
    /// components, a backslash or a NUL, or resolving (through symlinks) outside the folder.
    public func resolve(relativePath: String, in id: UUID) throws -> URL {
        try Self.resolve(relativePath: relativePath, in: folderURL(for: id))
    }

    public static func resolve(relativePath: String, in folder: URL, fileManager: FileManager = .default) throws -> URL {
        let bad = PropertyStoreError.unsafePath(relativePath)
        let scalars = relativePath.unicodeScalars
        guard let first = scalars.first, first != "/", first != "~", !scalars.contains("\\") else { throw bad }
        for scalar in scalars where scalar.value < 0x20 || scalar.value == 0x7F { throw bad }

        let components = pathComponents(relativePath)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else { throw bad }

        let base = folder.standardizedFileURL.path
        let lexical = (base.hasSuffix("/") ? base : base + "/") + components.joined(separator: "/")

        // Follow symlinks on the part that exists, so a link inside the folder cannot lead out of it.
        guard let realBase = realPath(base, fileManager), let realTarget = realPath(lexical, fileManager) else { throw bad }
        let prefix = realBase.hasSuffix("/") ? realBase : realBase + "/"
        guard realTarget.unicodeScalars.starts(with: prefix.unicodeScalars) else { throw bad }
        return URL(fileURLWithPath: lexical)
    }

    /// The non-empty pieces of a path, split on the "/" **scalar**. `String.split(separator: "/")` works on
    /// Characters, and "/" followed by a combining mark (U+0301), a zero width joiner (U+200D) or a variation
    /// selector forms ONE Character that is not "/": "../\u{301}x" would then look like a single harmless
    /// name while the file system reads ".." and "\u{301}x". Every path check in this file goes through here.
    static func pathComponents(_ path: String) -> [String] {
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in path.unicodeScalars {
            if scalar == "/" {
                if !current.isEmpty { parts.append(String(current)); current = String.UnicodeScalarView() }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { parts.append(String(current)) }
        return parts
    }

    /// The absolute path with every symbolic link followed, including links that dangle (point at
    /// something that does not exist yet), which `URL.resolvingSymlinksInPath()` leaves alone. Parts
    /// of the path that do not exist are kept as they are. nil after 40 link hops (a loop).
    private static func realPath(_ path: String, _ fileManager: FileManager) -> String? {
        var resolved: [String] = []                      // components of the real path so far
        var pending: [String] = Array(pathComponents(path).reversed())
        var hops = 0
        while let component = pending.popLast() {
            if component == "." { continue }
            if component == ".." { _ = resolved.popLast(); continue }
            let candidate = "/" + (resolved + [component]).joined(separator: "/")
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: candidate) {
                hops += 1
                if hops > 40 { return nil }
                if destination.unicodeScalars.first == "/" { resolved = [] }          // absolute link: start again from the root
                pending.append(contentsOf: pathComponents(destination).reversed())
                continue
            }
            resolved.append(component)
        }
        return "/" + resolved.joined(separator: "/")
    }

    /// Write a file into a property's folder (atomically, creating folders as needed).
    /// The path is checked with `resolve`, and the store's own files cannot be overwritten or turned into
    /// folders (the first path component may not be property.json, property.json.bak or property.json.corrupt).
    public func writeAsset(_ data: Data, relativePath: String, for id: UUID) throws {
        let url = try resolve(relativePath: relativePath, in: id)
        // The FIRST component decides: "property.json/x.bin" would make a folder where the store keeps
        // its file, and every later save would fail.
        if let first = Self.pathComponents(relativePath).first, Self.reservedNames.contains(Self.reservedKey(first)) {
            throw PropertyStoreError.reservedPath(relativePath)
        }
        try locked {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                throw PropertyStoreError.invalidAssetTarget(relativePath)
            }
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch {
                throw PropertyStoreError.invalidAssetTarget(relativePath)
            }
            try data.write(to: url, options: .atomic)
        }
    }

    private static let reservedNames: Set<String> = Set([propertyFileName, backupFileName, corruptFileName].map(reservedKey))

    /// Case-insensitive (default macOS and iOS volumes are) and blind to invisible format characters
    /// (zero width joiner and the like), which some file systems ignore when comparing names.
    private static func reservedKey(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in name.lowercased().unicodeScalars where scalar.properties.generalCategory != .format { out.append(scalar) }
        return String(out)
    }

    /// Read a file from a property's folder; the path gets the same checks as `writeAsset`. Blocking, like
    /// `writeAsset`: assets can be large, so call it off the main actor.
    public func readAsset(relativePath: String, for id: UUID) throws -> Data {
        let url = try resolve(relativePath: relativePath, in: id)
        return try locked { try Data(contentsOf: url) }
    }

    // MARK: Encoding

    /// The envelope as pretty-printed UTF-8 JSON with sorted keys (stable, diff-friendly).
    public static func encode(_ property: Property) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DataDates.iso8601Exact(date))
        }
        // A stray NaN must not make a whole survey unsaveable.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try encoder.encode(Envelope(schemaVersion: currentSchemaVersion, property: property))
    }

    /// Read an envelope written by `encode` (or by an older version, through the built-in
    /// migrations). Unknown keys are ignored.
    public static func decode(_ data: Data) throws -> Property {
        try decodeDocument(data, migrations: builtInMigrations).property
    }

    private static let builtInMigrations: [Int: Migration] = [Migration.wrapBareProperty.from: Migration.wrapBareProperty]

    /// The bytes are not a JSON object we can work with.
    private struct UnreadableFile: Error { let reason: String }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var property: Property
    }

    /// Looks only at the version and whether an envelope is there.
    private struct Header: Decodable {
        var schemaVersion: Int?
        var hasProperty: Bool

        private enum Keys: String, CodingKey { case schemaVersion, property }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            hasProperty = c.contains(.property)
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                if let date = DataDates.parse(text) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            // A plain JSONEncoder() writes a number: seconds since 2001-01-01.
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    private func decodeFile(_ data: Data) throws -> (property: Property, version: Int, migrated: Bool) {
        try Self.decodeDocument(data, migrations: migrations)
    }

    /// Foundation's JSONDecoder does not throw on every malformed file: on some toolchains it hits a
    /// `try!` and kills the whole process (an uncatchable trap) when an OBJECT KEY has invalid UTF-8, a raw
    /// control character, a bad escape or a lone surrogate escape. The same damage inside a string VALUE is
    /// thrown normally. `JSONSerialization` is a strict parser that throws for all of these, so every file
    /// goes through it first; whatever it accepts is well-formed JSON with well-formed keys, which the
    /// decoder handles. This also costs one extra parse per read, which is small next to the decode.
    private static func requireStrictJSON(_ data: Data) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw UnreadableFile(reason: "not valid JSON")
        }
    }

    private static func decodeDocument(_ data: Data, migrations: [Int: Migration])
        throws -> (property: Property, version: Int, migrated: Bool) {
        try requireStrictJSON(data)
        let decoder = makeDecoder()
        let header = try decoder.decode(Header.self, from: data)
        let version = header.schemaVersion ?? (header.hasProperty ? currentSchemaVersion : 0)
        if version > currentSchemaVersion {
            throw PropertyStoreError.unsupportedSchemaVersion(found: version, supported: currentSchemaVersion)
        }
        if version == currentSchemaVersion {
            return (try decoder.decode(Envelope.self, from: data).property, version, false)
        }

        // Older file: run the registered steps, one version at a time.
        guard var document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UnreadableFile(reason: "not a JSON object")
        }
        var v = version
        while v < currentSchemaVersion {
            guard let step = migrations[v] else { throw PropertyStoreError.missingMigration(from: v) }
            try step.transform(&document)
            document["schemaVersion"] = v + 1
            v += 1
        }
        let migratedData = try JSONSerialization.data(withJSONObject: document)
        return (try decoder.decode(Envelope.self, from: migratedData).property, version, true)
    }
}
