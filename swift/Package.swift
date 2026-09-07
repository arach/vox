// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let voxdInfoPlistPath = packageDirectory
    .appendingPathComponent("Sources/voxd/Info.plist")
    .path

let package = Package(
    name: "HudsonSpeechEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
        .library(name: "VoxEngine", targets: ["VoxEngine"]),
        .library(name: "HudsonSpeechEngine", targets: ["HudsonSpeechEngine"]),
        .library(name: "VoxAppleSpeech", targets: ["VoxAppleSpeech"]),
        .library(name: "VoxService", targets: ["VoxService"]),
        .library(name: "VoxBridge", targets: ["VoxBridge"]),
        .executable(name: "voxbridge", targets: ["VoxBridgeRunner"]),
        .executable(name: "voxttsd", targets: ["VoxTTSRunner"]),
        .executable(name: "voxd", targets: ["voxd"])
    ],
    dependencies: [
        .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", from: "0.1.5")
    ],
    targets: [
        .target(name: "VoxCore"),
        .target(
            name: "HudsonSpeechEngine",
            dependencies: [
                "VoxCore",
                .product(name: "MoonshineVoice", package: "moonshine-swift")
            ],
            path: "Sources/HudsonSpeechEngine",
            resources: [
                .copy("Resources/mlx_audio_provider.py"),
                .copy("Resources/models.json")
            ]
        ),
        .target(
            name: "VoxEngine",
            dependencies: ["HudsonSpeechEngine"]
        ),
        .target(
            name: "VoxAppleSpeech",
            dependencies: ["VoxCore", "VoxEngine"]
        ),
        .target(
            name: "VoxService",
            dependencies: ["VoxCore", "HudsonSpeechEngine"]
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
            dependencies: ["VoxCore", "HudsonSpeechEngine"]
        ),
        .executableTarget(
            name: "voxd",
            dependencies: ["VoxCore", "HudsonSpeechEngine", "VoxService"],
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
            dependencies: ["VoxCore", "HudsonSpeechEngine", "VoxService"]
        ),
        .testTarget(
            name: "VoxEngineTests",
            dependencies: ["HudsonSpeechEngine"]
        ),
        .testTarget(
            name: "VoxAppleSpeechTests",
            dependencies: ["VoxAppleSpeech", "VoxCore", "VoxEngine"]
        ),
        .testTarget(
            name: "VoxBridgeTests",
            dependencies: ["VoxBridge"]
        )
    ]
)
