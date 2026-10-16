// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wabbit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WabbitCore", targets: ["WabbitCore"]),
        .executable(name: "Wabbit", targets: ["Wabbit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Platform-independent core: no Apple-only imports (ADR 0001).
        .target(name: "WabbitCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // macOS shell: UI and detection only. Bundled into Wabbit.app by scripts/build-app.sh.
        .executableTarget(name: "Wabbit", dependencies: ["WabbitCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "WabbitCoreTests", dependencies: ["WabbitCore"]),
    ]
)
