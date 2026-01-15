// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HomeKitMenu",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HomeKitMenu",
            path: "HomeKitMenu"
        )
    ]
)
