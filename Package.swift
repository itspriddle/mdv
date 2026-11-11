// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mdv",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MdvCore", targets: ["MdvCore"]),
        // The CLI's logic, so the Xcode `mdv-cli` target and the tests share it.
        .library(name: "MdvCLIKit", targets: ["MdvCLIKit"]),
        .executable(name: "mdv", targets: ["MdvCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        .target(
            name: "MdvCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "Yams", package: "Yams"),
            ],
            // Syntax highlighting runs highlight.js in-process (system framework).
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .target(
            name: "MdvCLIKit",
            dependencies: [
                "MdvCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CLI/MdvCLIKit"
        ),
        .executableTarget(
            name: "MdvCLI",
            dependencies: ["MdvCLIKit"],
            path: "CLI/Main"
        ),
        .testTarget(
            name: "MdvCoreTests",
            dependencies: [
                "MdvCore",
                .product(name: "cmark-gfm", package: "swift-cmark"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MdvCLITests",
            // MdvCLI so `swift test` builds the binary the end-to-end tests run.
            dependencies: ["MdvCLIKit", "MdvCLI", "MdvCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
