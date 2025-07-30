// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "bitchat",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "bitchat",
            targets: ["bitchat"]
        ),
    ],
    dependencies: [
        .package(path: "../react-native-mls/SwiftMLS")
    ],
    targets: [
        .executableTarget(
            name: "bitchat",
            dependencies: [
                .product(name: "SwiftMLS", package: "SwiftMLS")
            ],
            path: "bitchat",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "bitchat.entitlements",
                "bitchat-macOS.entitlements",
                "LaunchScreen.storyboard"
            ],
            linkerSettings: [
                .linkedLibrary("react_native_mls_rust"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("resolv"),
                .unsafeFlags([
                    "-L../react-native-mls/rust/target/aarch64-apple-darwin/release"
                ])
            ]
        ),
    ]
)