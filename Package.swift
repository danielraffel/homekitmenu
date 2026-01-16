// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Homebar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Homebar",
            path: "HomeKitMenu"
        )
    ]
)
