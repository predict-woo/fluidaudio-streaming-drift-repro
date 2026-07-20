// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "fluidaudio-streaming-drift-repro",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "repro",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
