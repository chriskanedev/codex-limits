// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexLimits",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CodexLimits", targets: ["CodexLimits"]),
    ],
    targets: [
        .executableTarget(name: "CodexLimits"),
        .testTarget(name: "CodexLimitsTests", dependencies: ["CodexLimits"]),
    ]
)
