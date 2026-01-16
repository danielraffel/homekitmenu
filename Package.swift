// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HomeBarMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HomeBarMenuBar",
            path: "HomeKitMenu"
        )
    ]
)
