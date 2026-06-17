// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Wisp",
            targets: ["Wisp"]
        )
    ],
    targets: [
        .target(
            name: "WispCore"
        ),
        .executableTarget(
            name: "Wisp",
            dependencies: ["WispCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WispCoreTests",
            dependencies: ["WispCore"]
        )
    ]
)
