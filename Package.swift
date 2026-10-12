// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GittingToIt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GittingToIt", targets: ["GittingToIt"])
    ],
    targets: [
        .executableTarget(name: "GittingToIt"),
        .testTarget(name: "GittingToItTests", dependencies: ["GittingToIt"])
    ],
    swiftLanguageModes: [.v5]
)
