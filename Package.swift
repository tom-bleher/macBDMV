// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macBDMV",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "macBDMV",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/macBDMV",
            // The app bundle embeds Sparkle.framework in Contents/Frameworks (scripts/build_app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "macBDMVTests", dependencies: ["macBDMV"], path: "Tests/macBDMVTests"),
    ]
)
