// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HeistEngine",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Pure Swift game rules and level data. No RealityKit, no UI.
        .library(name: "HeistCore", targets: ["HeistCore"]),
        // RealityKit runtime: scene building, navigation, camera, input.
        .library(name: "HeistKit", targets: ["HeistKit"])
    ],
    targets: [
        .target(name: "HeistCore"),
        .target(
            name: "HeistKit",
            dependencies: ["HeistCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HeistCoreTests",
            dependencies: ["HeistCore"]
        )
    ]
)
