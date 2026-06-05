// swift-tools-version: 6.2
import Foundation
import PackageDescription

let swiftPackageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("swift")
let voxdInfoPlistPath = swiftPackageDirectory
    .appendingPathComponent("Sources/voxd/Info.plist")
    .path

let package = Package(
    name: "Vox",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
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
        .target(
            name: "VoxCore",
            path: "swift/Sources/VoxCore"
        ),
        .target(
            name: "VoxEngine",
            dependencies: [
                "VoxCore"
            ],
            path: "swift/Sources/VoxEngine",
            resources: [
                .copy("Resources/mlx_audio_provider.py")
            ]
        ),
        .target(
            name: "VoxService",
            dependencies: ["VoxCore", "VoxEngine"],
            path: "swift/Sources/VoxService"
        ),
        .target(
            name: "VoxBridge",
            dependencies: ["VoxCore"],
            path: "swift/Sources/VoxBridge"
        ),
        .executableTarget(
            name: "VoxBridgeRunner",
            dependencies: ["VoxCore", "VoxBridge"],
            path: "swift/Sources/VoxBridgeRunner"
        ),
        .executableTarget(
            name: "VoxTTSRunner",
            dependencies: ["VoxCore", "VoxEngine"],
            path: "swift/Sources/VoxTTSRunner"
        ),
        .executableTarget(
            name: "voxd",
            dependencies: ["VoxCore", "VoxEngine", "VoxService"],
            path: "swift/Sources/voxd",
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
            dependencies: ["VoxCore"],
            path: "swift/Tests/VoxCoreTests"
        ),
        .testTarget(
            name: "VoxServiceTests",
            dependencies: ["VoxCore", "VoxEngine", "VoxService"],
            path: "swift/Tests/VoxServiceTests"
        ),
        .testTarget(
            name: "VoxEngineTests",
            dependencies: ["VoxEngine"],
            path: "swift/Tests/VoxEngineTests"
        ),
        .testTarget(
            name: "VoxBridgeTests",
            dependencies: ["VoxBridge"],
            path: "swift/Tests/VoxBridgeTests"
        )
    ]
)
