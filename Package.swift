// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hours",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HoursCore", targets: ["HoursCore"]),
        .executable(name: "Hours", targets: ["Hours"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Platform-independent core: no Apple-only imports (ADR 0001).
        .target(name: "HoursCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // macOS shell: UI and detection only. Bundled into Hours.app by scripts/build-app.sh.
        .executableTarget(name: "Hours", dependencies: ["HoursCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "HoursCoreTests", dependencies: ["HoursCore"]),
    ]
)
