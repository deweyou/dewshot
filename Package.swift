// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Frame",
    // The bundle requires macOS 26. The capture path still compiles against the legacy Core Graphics API.
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "Frame",
            targets: ["Frame"]
        ),
        .library(
            name: "FrameCore",
            targets: ["FrameCore"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Frame",
            dependencies: ["FrameApp"]
        ),
        .target(
            name: "FrameApp",
            dependencies: ["FrameCore"],
            exclude: ["Resources"]
        ),
        .target(
            name: "FrameCore"
        ),
        .testTarget(
            name: "FrameCoreTests",
            dependencies: ["FrameCore"]
        ),
        .testTarget(
            name: "FrameAppTests",
            dependencies: ["FrameApp"]
        ),
    ]
)
