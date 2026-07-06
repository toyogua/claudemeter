// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeMeter",
            path: "Sources/ClaudeMeter"
        ),
        .testTarget(
            name: "ClaudeMeterTests",
            dependencies: ["ClaudeMeter"],
            path: "Tests/ClaudeMeterTests"
        ),
    ]
)
