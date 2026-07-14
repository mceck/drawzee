// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tapink",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tapink",
            dependencies: ["TapinkKit"]
        ),
        .target(
            name: "TapinkKit"
        ),
        .testTarget(
            name: "TapinkKitTests",
            dependencies: ["TapinkKit"]
        ),
    ]
)
