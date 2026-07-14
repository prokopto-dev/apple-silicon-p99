// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "P99Installer",
    platforms: [.macOS(.v14)],
    targets: [
        // Testable core: script running, output parsing, status model.
        .target(name: "P99Core", path: "Sources/P99Core"),
        // The GUI shell (views + state machine).
        .executableTarget(name: "P99Installer",
                          dependencies: ["P99Core"],
                          path: "Sources/P99Installer"),
        // Tests are a plain executable (swift run p99tests): the Command Line
        // Tools ship neither XCTest nor swift-testing, and this repo builds
        // with CLT alone.
        .executableTarget(name: "p99tests",
                          dependencies: ["P99Core"],
                          path: "Sources/p99tests"),
    ]
)
