// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tempur",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "tempur",
            targets: ["tempur"]
        )
    ],
    targets: [
        .executableTarget(
            name: "tempur"
        )
    ]
)
