// swift-tools-version: 6.2
import PackageDescription

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
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", branch: "main")
    ],
    targets: [
        .target(name: "VoxCore"),
        .target(
            name: "VoxEngine",
            dependencies: [
                "VoxCore",
                .product(name: "FluidAudio", package: "fluidaudio")
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
            dependencies: ["VoxCore", "VoxEngine", "VoxService"]
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
