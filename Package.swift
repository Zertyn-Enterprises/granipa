// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Granipa",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // Exact pin: FluidAudio has shipped breaking renames in minor releases.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Granipa",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
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
