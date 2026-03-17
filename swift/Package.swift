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
        .executable(name: "voxd", targets: ["voxd"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", revision: "47552dde26f79b880efff2f23ad4dab55aa914ca")
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
