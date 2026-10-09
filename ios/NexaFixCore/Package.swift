// swift-tools-version:5.9
import PackageDescription

// NexaFixCore holds everything that is not an Apple-framework call: the data
// model, geometry, units, exporters (PDF, DXF, CSV, JSON, costing spec) and
// storage. It has no dependency on SwiftUI, ARKit, RoomPlan or simd, so it
// builds and is unit-tested on Linux as well as in Xcode.
let package = Package(
    name: "NexaFixCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NexaFixCore", targets: ["NexaFixCore"]),
    ],
    targets: [
        .target(name: "NexaFixCore"),
        .testTarget(name: "NexaFixCoreTests", dependencies: ["NexaFixCore"]),
    ]
)
