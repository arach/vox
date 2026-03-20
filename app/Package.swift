// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoxApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../swift")
    ],
    targets: [
        .executableTarget(
            name: "Vox",
            dependencies: [
                .product(name: "VoxCore", package: "swift"),
                .product(name: "VoxBridge", package: "swift"),
            ],
            path: "Vox",
            resources: [
                .copy("Assets.xcassets")
            ]
        )
    ]
)
