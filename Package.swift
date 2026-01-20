// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "am-i-talking-too-much-app",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "am-i-talking-too-much-app",
            targets: ["am-i-talking-too-much-app"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "am-i-talking-too-much-app",
            dependencies: [],
            path: "Sources"
        )
    ]
)
