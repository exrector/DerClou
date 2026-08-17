// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HeistEngine",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0")
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
            // RealityKit's main-actor model still fights Swift 6 strict
            // concurrency in places; revisit once the SDK settles.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HeistCoreTests",
            dependencies: ["HeistCore"]
        )
    ]
)
