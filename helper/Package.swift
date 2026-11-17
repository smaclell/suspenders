// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuspendersHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SuspendersCore"),
        .executableTarget(name: "SuspendersHelper", dependencies: ["SuspendersCore"]),
        .testTarget(name: "SuspendersCoreTests", dependencies: ["SuspendersCore"]),
    ]
)
