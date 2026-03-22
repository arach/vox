// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
        .library(name: "VoxEngine", targets: ["VoxEngine"]),
        .library(name: "VoxService", targets: ["VoxService"]),
        .library(name: "VoxBridge", targets: ["VoxBridge"]),
        .executable(name: "voxd", targets: ["voxd"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", revision: "b80d364")
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
            name: "voxd",
            dependencies: ["VoxCore", "VoxService"]
        ),
        .testTarget(
            name: "VoxCoreTests",
            dependencies: ["VoxCore"]
        ),
        .testTarget(
            name: "VoxServiceTests",
            dependencies: ["VoxCore", "VoxService"]
        ),
        .testTarget(
            name: "VoxEngineTests",
            dependencies: ["VoxEngine"]
        )
    ]
)
