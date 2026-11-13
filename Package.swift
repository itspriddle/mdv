// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "peep",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PeepCore", targets: ["PeepCore"]),
        // The CLI's logic, so the Xcode `peep-cli` target and the tests share it.
        .library(name: "PeepCLIKit", targets: ["PeepCLIKit"]),
        .executable(name: "peep", targets: ["PeepCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "PeepCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "Yams", package: "Yams"),
            ],
            // Syntax highlighting runs highlight.js in-process (system framework).
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .target(
            name: "PeepCLIKit",
            dependencies: [
                "PeepCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CLI/PeepCLIKit"
        ),
        .executableTarget(
            name: "PeepCLI",
            dependencies: ["PeepCLIKit"],
            path: "CLI/Main"
        ),
        // Build tool, not shipped: `make cli-docs` finishes generate-manual's page with it (#71).
        .executableTarget(
            name: "PeepManualTool",
            dependencies: [
                "PeepCLIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CLI/ManualTool"
        ),
        .testTarget(
            name: "PeepCoreTests",
            dependencies: [
                "PeepCore",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                // AcknowledgementsTests reads project.yml's packages.
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PeepCLITests",
            // PeepCLI so `swift test` builds the binary the end-to-end tests run.
            dependencies: ["PeepCLIKit", "PeepCLI", "PeepCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
