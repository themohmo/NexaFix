import Foundation

// Test-support launch hooks for the UI smoke tests in `ios/NexaFixScanUITests`.
//
// Debug builds only: the whole file is inside `#if DEBUG`, so a Release build (the scheme "NexaFixScan Release",
// archives) contains none of it. Nothing here runs unless the app is launched with the argument
// `-UITestResetData`, which only the UI tests pass; a normal launch from Xcode or from the Home Screen is unchanged.
//
// Foundation and the app's own folder names only, so this file is type-checked on Linux with the rest of the
// pure code.

#if DEBUG
@MainActor
enum UITestSupport {
    /// The launch argument that asks for a clean first-run state. The UI tests pass it as `-UITestResetData YES`
    /// (an option with a value, so Foundation's argument parser cannot take the next option for its value);
    /// `-UITestResetData NO` switches it off again.
    static let resetArgument = "-UITestResetData"

    /// Keys of `UserDefaults` that begin with this belong to the app (`AppSettings`, the export formats, the
    /// restored-property notices). The persistent domain is removed as a whole as well; this loop is the second
    /// line of defence if the system still hands a key out of its cache.
    private static let appKeyPrefix = "com.nexafix."

    static func isResetRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard let index = arguments.firstIndex(of: resetArgument) else { return false }
        if arguments.indices.contains(index + 1) {
            let value = arguments[index + 1].uppercased()
            if value == "NO" || value == "FALSE" || value == "0" { return false }
        }
        return true
    }

    /// Empties the property store (`Documents/Properties`), the safety copies of unfinished scans
    /// (`Application Support/ScanRecovery`) and every saved preference, so the app starts as on its first launch.
    /// Call it once, before the `AppModel` is created. Does nothing without `-UITestResetData`.
    static func resetIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                 fileManager: FileManager = .default,
                                 defaults: UserDefaults = .standard,
                                 bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard isResetRequested(arguments: arguments) else { return }

        removeContents(of: AppModel.defaultStoreURL(), fileManager: fileManager)
        removeContents(of: ScanRecoveryStore.defaultRoot, fileManager: fileManager)

        if let bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(appKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        NSLog("UITestSupport: cleared saved properties, scan recovery copies and preferences")
    }

    /// Deletes what is inside `folder` and keeps the folder itself. A missing folder is not a problem.
    private static func removeContents(of folder: URL, fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
#endif
