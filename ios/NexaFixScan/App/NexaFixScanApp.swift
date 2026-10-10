import SwiftUI

/// App entry point. Creates the one `AppModel`, hands it to the whole view tree through the
/// environment, and sets the bronze accent. `RootView` (written separately) owns navigation and
/// reads the model with `@Environment(AppModel.self)`.
@main
@MainActor
struct NexaFixScanApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        // UI tests only: `-UITestResetData` empties the saved data first, so a test starts as on a first launch.
        // Before the model exists, because the model reads the store and the settings when it is created.
        UITestSupport.resetIfRequested()
        #endif
        // The haptics switch lives in a UIKit file; the model reaches it through this closure so the
        // model itself stays free of UIKit.
        _model = State(initialValue: AppModel(hapticsSink: { Haptics.isEnabled = $0 }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
                .preferredColorScheme(nil)
        }
    }
}
