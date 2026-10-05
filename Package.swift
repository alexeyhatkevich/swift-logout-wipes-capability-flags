// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogoutWipe",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LogoutWipe", targets: ["LogoutWipe"]),
    ],
    targets: [
        .target(name: "LogoutWipe"),
        .testTarget(name: "LogoutWipeTests", dependencies: ["LogoutWipe"]),
    ]
)
