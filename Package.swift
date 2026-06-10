// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Granipa",
    platforms: [.macOS("26.0")],
    // To enable speaker diarization, add the FluidAudio dependency (exact pin:
    // it has shipped breaking renames in minor releases) and its product below:
    //   .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2"),
    //   .product(name: "FluidAudio", package: "FluidAudio"),
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Granipa",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Granipa"
        ),
        .testTarget(
            name: "GranipaTests",
            dependencies: ["Granipa"],
            path: "Tests/GranipaTests"
        ),
    ]
)
