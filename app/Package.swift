// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoxApp",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../swift"),
        .package(path: "../../hudson"),
    ],
    targets: [
        .executableTarget(
            name: "Vox",
            dependencies: [
                .product(name: "VoxCore", package: "swift"),
                .product(name: "VoxBridge", package: "swift"),
                .product(name: "VoxEngine", package: "swift"),
                .product(name: "HudsonUI", package: "hudson"),
                .product(name: "HudsonShell", package: "hudson"),
            ],
            path: "Vox",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        )
    ]
)
