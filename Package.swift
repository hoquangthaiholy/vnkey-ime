// swift-tools-version:5.9
import PackageDescription

// This package exists solely to run XCTest unit tests against the pure-logic
// engine files (VnEngine, Preferences). The shipping app itself is still built
// via the Makefile with `swiftc` directly — this does not participate in that
// build and only compiles when running `swift test`.
let package = Package(
    name: "VnKey",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "VnKeyCore",
            path: "Sources",
            sources: ["VnEngine.swift", "Preferences.swift"]
        ),
        .testTarget(
            name: "VnKeyCoreTests",
            dependencies: ["VnKeyCore"],
            path: "Tests/VnKeyCoreTests"
        ),
    ]
)
