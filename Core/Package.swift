// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaktoNoDpiCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MaktoNoDpiCore", targets: ["MaktoNoDpiCore"])
    ],
    targets: [
        .target(name: "MaktoNoDpiCore"),
        .testTarget(name: "MaktoNoDpiCoreTests", dependencies: ["MaktoNoDpiCore"])
    ]
)
