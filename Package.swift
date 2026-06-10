// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Granipa",
    platforms: [.macOS("26.0")],
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
