// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShieldStatCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShieldStatCore", targets: ["ShieldStatCore"])
    ],
    targets: [
        .target(name: "ShieldStatCore"),
        .testTarget(name: "ShieldStatCoreTests", dependencies: ["ShieldStatCore"]),
    ]
)
