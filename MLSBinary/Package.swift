// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "MLSBinary",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MLS",
            targets: ["MLS"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "MLS",
            path: "./MLS.xcframework"
        )
    ]
)