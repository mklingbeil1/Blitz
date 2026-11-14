// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Blitz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Blitz", path: "Sources/Blitz")
    ]
)
