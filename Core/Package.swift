// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShieldStatCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShieldStatCore", targets: ["ShieldStatCore"]),
        // Separate from ShieldStatCore on purpose. Core is pure — nothing in it
        // reads a file, spawns a process, or asks the time — and everything it
        // knows arrives as an argument. Subprocess is the opposite, so it gets
        // its own module rather than being the exception that ends the rule.
        .library(name: "ShieldStatSystem", targets: ["ShieldStatSystem"]),
    ],
    targets: [
        .target(name: "ShieldStatCore"),
        .testTarget(name: "ShieldStatCoreTests", dependencies: ["ShieldStatCore"]),
        .target(name: "ShieldStatSystem"),
        .testTarget(name: "ShieldStatSystemTests", dependencies: ["ShieldStatSystem"]),
    ]
)
