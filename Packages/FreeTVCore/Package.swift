// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeTVCore",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "FreeTVCore", targets: ["FreeTVCore"]),
    ],
    targets: [
        .target(name: "FreeTVCore"),
        .testTarget(name: "FreeTVCoreTests", dependencies: ["FreeTVCore"]),
    ]
)
