// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Verto",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Verto", path: "Sources/Verto")
    ]
)
