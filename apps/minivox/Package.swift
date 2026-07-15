// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Minivox",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../swift")
    ],
    targets: [
        .executableTarget(
            name: "Minivox",
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
