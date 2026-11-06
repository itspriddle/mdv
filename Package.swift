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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        .target(
            name: "MdvCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
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
            dependencies: ["MdvCore"]
        ),
    ]
)
