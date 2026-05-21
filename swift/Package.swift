// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let voxdInfoPlistPath = packageDirectory
    .appendingPathComponent("Sources/voxd/Info.plist")
    .path

let package = Package(
    name: "Vox",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
        .library(name: "VoxEngine", targets: ["VoxEngine"]),
        .library(name: "VoxService", targets: ["VoxService"]),
        .library(name: "VoxBridge", targets: ["VoxBridge"]),
        .executable(name: "voxbridge", targets: ["VoxBridgeRunner"]),
        .executable(name: "voxttsd", targets: ["VoxTTSRunner"]),
        .executable(name: "voxd", targets: ["voxd"])
    ],
    dependencies: [],
    targets: [
        .target(name: "VoxCore"),
        .target(
            name: "VoxEngine",
            dependencies: [
                "VoxCore"
            ],
            resources: [
                .copy("Resources/mlx_audio_provider.py")
            ]
        ),
        .target(
            name: "VoxService",
            dependencies: ["VoxCore", "VoxEngine"]
        ),
        .target(
            name: "VoxBridge",
            dependencies: ["VoxCore"]
        ),
        .executableTarget(
            name: "VoxBridgeRunner",
            dependencies: ["VoxCore", "VoxBridge"]
        ),
        .executableTarget(
            name: "VoxTTSRunner",
            dependencies: ["VoxCore", "VoxEngine"]
        ),
        .executableTarget(
            name: "voxd",
            dependencies: ["VoxCore", "VoxEngine", "VoxService"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", voxdInfoPlistPath
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "VoxCoreTests",
            dependencies: ["VoxCore"]
        ),
        .testTarget(
            name: "VoxServiceTests",
            dependencies: ["VoxCore", "VoxEngine", "VoxService"]
        ),
        .testTarget(
            name: "VoxEngineTests",
            dependencies: ["VoxEngine"]
        ),
        .testTarget(
            name: "VoxBridgeTests",
            dependencies: ["VoxBridge"]
        )
    ]
)
