// swift-tools-version:5.9
// Coaching logic shared with the iOS app target. The app compiles these same source files directly;
// this package exists so the rules can be unit-tested on any machine (including Linux) with `swift test`.
import PackageDescription

let package = Package(
    name: "FrameCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FrameCore", targets: ["FrameCore"])],
    targets: [
        .target(name: "FrameCore"),
        .testTarget(name: "FrameCoreTests", dependencies: ["FrameCore"])
    ]
)
