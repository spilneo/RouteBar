// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RouteBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RouteBar", targets: ["RouteBar"]),
        .library(name: "RouteBarKit", targets: ["RouteBarKit"])
    ],
    targets: [
        .target(name: "RouteBarKit"),
        .executableTarget(name: "RouteBar", dependencies: ["RouteBarKit"]),
        .testTarget(name: "RouteBarTests", dependencies: ["RouteBarKit"])
    ]
)
