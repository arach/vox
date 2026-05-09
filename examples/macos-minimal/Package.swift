// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoxMinimalExample",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../swift")
    ],
    targets: [
        .executableTarget(
            name: "VoxMinimalExample",
            dependencies: [
                .product(name: "VoxCore", package: "swift"),
                .product(name: "VoxEngine", package: "swift"),
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
