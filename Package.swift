// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatsWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeStatsWidget", path: "Sources"),
    ]
)
