// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tamp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TampKit", targets: ["TampKit"]),
        .executable(name: "tamp", targets: ["tamp"]),
        .executable(name: "TampBar", targets: ["TampBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "TampKit"),
        .executableTarget(
            name: "tamp",
            dependencies: [
                "TampKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "TampBar",
            dependencies: ["TampKit"],
            resources: [.copy("Icons")]
        ),
        // Standalone test runner: XCTest/Swift Testing need full Xcode, which
        // isn't present here, so checks run as a plain executable. `swift run
        // TampKitChecks` exits non-zero on failure.
        .executableTarget(
            name: "TampKitChecks",
            dependencies: ["TampKit"]
        ),
    ]
)
