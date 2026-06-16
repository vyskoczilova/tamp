// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Coffee",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CoffeeKit", targets: ["CoffeeKit"]),
        .executable(name: "coffee", targets: ["coffee"]),
        .executable(name: "CoffeeBar", targets: ["CoffeeBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "CoffeeKit"),
        .executableTarget(
            name: "coffee",
            dependencies: [
                "CoffeeKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "CoffeeBar",
            dependencies: ["CoffeeKit"],
            resources: [.copy("Icons")]
        ),
        // Standalone test runner: XCTest/Swift Testing need full Xcode, which
        // isn't present here, so checks run as a plain executable. `swift run
        // CoffeeKitChecks` exits non-zero on failure.
        .executableTarget(
            name: "CoffeeKitChecks",
            dependencies: ["CoffeeKit"]
        ),
    ]
)
