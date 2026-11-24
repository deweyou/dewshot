// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "dewShot",
    // The bundle requires macOS 26. The capture path still compiles against the legacy Core Graphics API.
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "dewShot",
            targets: ["dewShot"]
        ),
        .library(
            name: "FrameCore",
            targets: ["FrameCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "13.2.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.35.0"),
    ],
    targets: [
        .executableTarget(
            name: "dewShot",
            dependencies: ["FrameApp"]
        ),
        .target(
            name: "FrameApp",
            dependencies: [
                "FrameCore",
                .product(name: "FirebaseAnalyticsCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
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
