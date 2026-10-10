// swift-tools-version:5.9
import PackageDescription
// Test harness only (never part of the app): stub Apple modules (signatures copied from Apple's docs) so
// ScanSessionController, the code that writes and ends a scan's safety copy, can run on Linux. controller/run.sh
// copies this file, the stubs, a snapshot of NexaFixCore's sources (-> core/) and the app's real files (-> app/)
// into one directory and builds that.
let package = Package(
    name: "ScanStubs",
    products: [.executable(name: "ScanApp", targets: ["ScanApp"])],
    targets: [
        .target(name: "simd", path: "stubs/simd"),
        .target(name: "UIKit", path: "stubs/UIKit"),
        .target(name: "ARKit", dependencies: ["simd"], path: "stubs/ARKit"),
        .target(name: "AVFoundation", path: "stubs/AVFoundation"),
        .target(name: "RoomPlan", dependencies: ["simd", "ARKit", "UIKit"], path: "stubs/RoomPlan"),
        .target(name: "NexaFixCore", path: "core"),
        .executableTarget(name: "ScanApp",
                          dependencies: ["simd", "UIKit", "ARKit", "AVFoundation", "RoomPlan", "NexaFixCore"],
                          path: "app"),
    ],
    swiftLanguageVersions: [.v5]
)
