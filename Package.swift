// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macBDMV",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "macBDMV", path: "Sources/macBDMV"),
        .testTarget(name: "macBDMVTests", dependencies: ["macBDMV"], path: "Tests/macBDMVTests"),
    ]
)
