// swift-tools-version:5.9
import PackageDescription

// Force Swift 5 language mode to avoid strict-concurrency churn on newer toolchains.
// (swiftLanguageMode() needs tools-version 6.0; the unsafe flag works under 5.9.)
let swift5: [SwiftSetting] = [.unsafeFlags(["-swift-version", "5"])]

let package = Package(
    name: "ClaudeUsageWatcher",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure-Foundation port of the C# Core library. No AppKit so it can be
        // unit-tested headlessly.
        .target(
            name: "UsageCore",
            swiftSettings: swift5
        ),
        // The AppKit menu-bar app.
        .executableTarget(
            name: "ClaudeUsageWatcher",
            dependencies: ["UsageCore"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            swiftSettings: swift5
        )
    ]
)
