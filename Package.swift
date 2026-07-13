// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeResourceIndicator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeResourceIndicator",
            path: "Sources/ClaudeResourceIndicator"
        ),
        .testTarget(
            name: "ClaudeResourceIndicatorTests",
            dependencies: ["ClaudeResourceIndicator"],
            path: "Tests/ClaudeResourceIndicatorTests"
        )
    ]
)
