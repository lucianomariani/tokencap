// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TokenCap",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TokenCap",
            path: "Sources/TokenCap"
        )
    ]
)
