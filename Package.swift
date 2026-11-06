// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mdv",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MdvCore", targets: ["MdvCore"]),
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
        .executableTarget(
            name: "MdvCLI",
            dependencies: [
                "MdvCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CLI"
        ),
        .testTarget(
            name: "MdvCoreTests",
            dependencies: [
                "MdvCore",
                .product(name: "cmark-gfm", package: "swift-cmark"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
