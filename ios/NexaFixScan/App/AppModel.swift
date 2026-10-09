import Foundation
import Observation
import NexaFixCore

/// The one object the whole app shares: it owns the property store, keeps the property list fresh,
/// holds the user's settings and turns every failure into a `UserFacingError` the interface can show.
///
/// Rules this type keeps:
/// - A failed save is never silent. The property stays in memory (`property(_:)` keeps returning the
///   edited copy), its id is listed in `unsavedPropertyIDs` until a save succeeds, and `presentedError`
///   carries a `.dataAtRisk` error. A lesser error never replaces that alert.
/// - A change handed to `update` is never dropped. If the property cannot be read at that moment, the
///   change is held in memory (and its id listed in `unsavedPropertyIDs`) and applied by
///   `retryUnsavedSaves()`; the error is shown on every such call, not just the first.
/// - Everything goes through `save`, `update` and `delete`, so `summaries` and `revision` stay current.
///
/// What the home screen must draw: `summaries` comes from storage, so a property whose first save
/// failed is not in it. Draw a row for every item of `memoryOnlyProperties` above the list, and show a
/// persistent banner with a Retry button (`retryUnsavedSaves()`) while `unsavedPropertyIDs` is not empty.
///
/// Foundation, Observation and NexaFixCore only, so it is type-checked on Linux. The app's `Haptics`
/// type lives in a UIKit file; `hapticsSink` is how the settings reach it.
@MainActor
@Observable
final class AppModel {
    /// Where properties live on disk.
    let store: PropertyStore

    /// One row per saved property, newest first. Refreshed after every save and delete.
    private(set) var summaries: [PropertySummary] = []

    /// User preferences. Every change is saved to `UserDefaults` and pushed to the haptics switch.
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            hapticsSink(settings.hapticsEnabled)
        }
    }

    /// The error to show now, or nil. Bind an alert to it; setting it to nil dismisses it.
    var presentedError: UserFacingError?

    /// Properties whose latest changes could not be written to storage. They exist only in memory.
    /// Show a persistent banner while this is not empty, and offer `retryUnsavedSaves()`.
    private(set) var unsavedPropertyIDs: Set<UUID> = []

    /// Bumps after every save, delete and refresh. `property(_:)` reads it, so a view that calls
    /// `property(_:)` in its body is redrawn when anything changes.
    private(set) var revision = 0

    /// Properties that have changes only in memory, newest first. A property that exists only in memory
    /// (its first save failed) is here; so is one whose later edit could not be written.
    var unsavedProperties: [Property] {
        _ = revision
        return unsavedPropertyIDs.compactMap { cache[$0] }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The part of `unsavedProperties` that is not in `summaries` at all, because it never reached
    /// storage. The home list must draw a row for each, or the person cannot find their work.
    var memoryOnlyProperties: [Property] {
        let stored = Set(summaries.map(\.id))
        return unsavedProperties.filter { !stored.contains($0.id) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let hapticsSink: (Bool) -> Void
    @ObservationIgnored private var cache: [UUID: Property] = [:]
    @ObservationIgnored private var failedLoads: Set<UUID> = []
    /// Changes passed to `update` for a property that could not be read. Applied in order by the next
    /// `update` or `retryUnsavedSaves()` that can read it.
    @ObservationIgnored private var pendingChanges: [UUID: [(inout Property) -> Void]] = [:]

    /// - Parameters:
    ///   - store: Pass one in tests and previews. By default the store lives in `Documents/Properties`,
    ///     which is created if missing and shows up in the Files app.
    ///   - defaults: Where settings are saved.
    ///   - hapticsSink: Called with the haptics preference at start-up and whenever it changes.
    init(store: PropertyStore? = nil,
         defaults: UserDefaults = .standard,
         hapticsSink: @escaping (Bool) -> Void = { _ in }) {
        var startupError: UserFacingError?
        if let store {
            self.store = store
        } else {
            let root = AppModel.defaultStoreURL()
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                startupError = UserFacingError(error, context: "prepare storage for your properties")
            }
            self.store = PropertyStore(rootURL: root)
        }
        self.defaults = defaults
        self.hapticsSink = hapticsSink
        self.settings = AppSettings.load(from: defaults)
        self.presentedError = startupError

        hapticsSink(settings.hapticsEnabled)
        refresh()
    }

    /// `Documents/Properties`, falling back to the temporary directory if Documents cannot be found.
    static func defaultStoreURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Properties", isDirectory: true)
    }

    // MARK: Reading

    /// Re-reads the property list from storage.
    func refresh() {
        do {
            let list = try store.list()
            summaries = list.sorted { $0.updatedAt > $1.updatedAt }
            pruneCache(against: list)
            failedLoads.removeAll()
            revision += 1
        } catch {
            present(UserFacingError(error, context: "load your properties"))
        }
    }

    /// The current copy of a property: the in-memory one if there is one (including edits that could
    /// not be saved), otherwise read from storage. Returns nil, and reports once, if it cannot be read.
    func property(_ id: UUID) -> Property? {
        _ = revision
        switch load(id) {
        case .success(let property):
            return property
        case .failure(let error):
            // Reported once per id, and after the current view update, so a view that calls this from
            // its body cannot loop by changing state while it is being drawn.
            if failedLoads.insert(id).inserted {
                let failure = UserFacingError(error, context: "open this property")
                Task { @MainActor [weak self] in self?.present(failure) }
            }
            return nil
        }
    }

    /// The in-memory copy, or a fresh read from storage (which is then remembered).
    private func load(_ id: UUID) -> Result<Property, Error> {
        if let cached = cache[id] { return .success(cached) }
        do {
            let loaded = try store.load(id: id)
            cache[id] = loaded
            return .success(loaded)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Writing

    /// Saves a property. On failure the property stays in memory and the error is shown loudly.
    /// - Returns: true when the property reached storage.
    @discardableResult
    func save(_ property: Property) -> Bool {
        cache[property.id] = property
        do {
            try store.save(property)
            unsavedPropertyIDs.remove(property.id)
            failedLoads.remove(property.id)
            revision += 1
            refresh()
            return true
        } catch {
            unsavedPropertyIDs.insert(property.id)
            revision += 1
            let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let what = name.isEmpty ? "this property" : "“\(name)”"
            present(UserFacingError(error, context: "save \(what)", severity: .dataAtRisk))
            return false
        }
    }

    /// Tries again to save everything that is only in memory: properties whose save failed, and changes
    /// held because their property could not be read. Shows an error again if it still does not work.
    func retryUnsavedSaves() {
        for id in unsavedPropertyIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            if pendingChanges[id] != nil {
                failedLoads.remove(id)
                commit(propertyID: id, change: nil)
            } else if let property = cache[id] {
                save(property)
            }
        }
    }

    /// Creates an empty property with one floor and saves it. Blank names become "Untitled property".
    @discardableResult
    func createProperty(name: String, client: String, address: String, reference: String,
                        kind: PropertyKind) -> Property {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let property = Property(name: cleanName.isEmpty ? "Untitled property" : cleanName,
                                client: client.trimmingCharacters(in: .whitespacesAndNewlines),
                                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                                reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
                                kind: kind,
                                floors: [Floor(name: "Main level", level: 0)])
        save(property)
        return property
    }

    /// Deletes a property and its files. A property that never reached storage is simply discarded.
    func delete(_ id: UUID) {
        do {
            try store.delete(id: id)
        } catch {
            let neverSaved = unsavedPropertyIDs.contains(id) && !summaries.contains { $0.id == id }
            if !neverSaved {
                present(UserFacingError(error, context: "delete this property"))
                return
            }
        }
        cache[id] = nil
        pendingChanges[id] = nil
        unsavedPropertyIDs.remove(id)
        failedLoads.remove(id)
        revision += 1
        refresh()
    }

    /// Adds the demo apartment so people can try the app without scanning. If the demo is already there,
    /// it is returned as it is, so notes and verifications entered on it are kept. A damaged copy on
    /// disk is replaced.
    @discardableResult
    func installDemo() -> Property {
        let demo = DemoProperty.make()
        if let existing = cache[demo.id] { return existing }
        if let stored = try? store.load(id: demo.id) {
            cache[demo.id] = stored
            if !summaries.contains(where: { $0.id == stored.id }) { refresh() }
            return stored
        }
        save(demo)
        return demo
    }

    /// Loads a property, applies `mutate`, stamps `updatedAt`, saves and refreshes.
    ///
    /// If the property cannot be read, `mutate` is kept and run later by the next `update` or
    /// `retryUnsavedSaves()` that can read it, so the change is not lost. The error is shown every time.
    /// Because the closure may run later, it must not rely on state that will have gone by then.
    /// - Returns: true when the change reached storage.
    @discardableResult
    func update(propertyID: UUID, _ mutate: @escaping (inout Property) -> Void) -> Bool {
        commit(propertyID: propertyID, change: mutate)
    }

    /// Applies held changes (oldest first) and then `change`, and saves. When the property cannot be
    /// read, `change` is held and the failure is shown as data at risk.
    @discardableResult
    private func commit(propertyID: UUID, change: ((inout Property) -> Void)?) -> Bool {
        switch load(propertyID) {
        case .success(var property):
            let held = pendingChanges.removeValue(forKey: propertyID) ?? []
            for earlier in held { earlier(&property) }
            change?(&property)
            property.updatedAt = Date()
            return save(property)
        case .failure(let error):
            if let change { pendingChanges[propertyID, default: []].append(change) }
            unsavedPropertyIDs.insert(propertyID)
            revision += 1
            present(UserFacingError(error, context: "save your last change to this property",
                                    severity: .dataAtRisk))
            return false
        }
    }

    // MARK: Assets

    /// Writes a file (captured room, USDZ, world map, photo) into the property's folder.
    /// - Returns: `relativePath` on success, nil after showing an error.
    func writeAsset(_ data: Data, relativePath: String, propertyID: UUID) -> String? {
        do {
            try store.writeAsset(data, relativePath: relativePath, for: propertyID)
            return relativePath
        } catch {
            present(UserFacingError(error, context: "save a file for this property", severity: .dataAtRisk))
            return nil
        }
    }

    /// The file URL for a path stored in the model, or nil if it cannot be resolved inside the property folder.
    func assetURL(relativePath: String, propertyID: UUID) -> URL? {
        try? store.resolve(relativePath: relativePath, in: propertyID)
    }

    // MARK: Errors

    /// Shows an error. A `.notice` never replaces an unacknowledged `.dataAtRisk` alert; the unsaved
    /// state itself stays visible through `unsavedPropertyIDs`.
    private func present(_ error: UserFacingError) {
        if let current = presentedError, current.severity == .dataAtRisk, error.severity == .notice {
            return
        }
        presentedError = error
    }

    private func pruneCache(against list: [PropertySummary]) {
        let saved = Dictionary(list.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        cache = cache.filter { entry in
            if unsavedPropertyIDs.contains(entry.key) { return true }
            guard let savedAt = saved[entry.key] else { return false }
            return abs(savedAt.timeIntervalSince(entry.value.updatedAt)) < 1
        }
    }
}

#if DEBUG
extension AppModel {
    /// A model backed by a throw-away folder and private defaults, for previews and tests.
    static func preview(withDemo: Bool = true) -> AppModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexaFixPreview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "com.nexafix.scan.preview") ?? .standard
        let model = AppModel(store: PropertyStore(rootURL: root), defaults: defaults)
        if withDemo { model.installDemo() }
        return model
    }
}
#endif
