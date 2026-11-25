// swift-tools-version:5.9
// Core logic shared with the iOS app and share extension. The app compiles these same source files directly;
// this package exists so the rules can be unit-tested on any machine (including Linux) with `swift test`.
import PackageDescription

let package = Package(
    name: "RoamCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "RoamCore", targets: ["RoamCore"])],
    targets: [
        .target(name: "RoamCore"),
        .testTarget(name: "RoamCoreTests", dependencies: ["RoamCore"], resources: [.copy("Fixtures")])
    ]
)
