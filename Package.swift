// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeProfiles",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: profile discovery, metadata, process detection. No AppKit.
        .target(name: "ClaudeProfilesCore"),
        // The menu bar app.
        .executableTarget(
            name: "ClaudeProfiles",
            dependencies: ["ClaudeProfilesCore"]
        ),
        .testTarget(
            name: "ClaudeProfilesCoreTests",
            dependencies: ["ClaudeProfilesCore"]
        ),
    ]
)
