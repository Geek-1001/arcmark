// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Arcmark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Library for bundler to use
        .library(name: "ArcmarkCore", targets: ["ArcmarkCore"]),
        // Executable for development/testing
        .executable(name: "Arcmark", targets: ["ArcmarkApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Core library with all app logic
        .target(name: "ArcmarkCore", dependencies: ["Sparkle"]),
        // Minimal executable entry point
        .executableTarget(
            name: "ArcmarkApp",
            dependencies: ["ArcmarkCore"]
        ),
        .testTarget(
            name: "ArcmarkTests",
            dependencies: ["ArcmarkCore"]
        )
    ]
)
