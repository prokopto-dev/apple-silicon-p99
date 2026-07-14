// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "P99Installer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "P99Installer", path: "Sources/P99Installer")
    ]
)
