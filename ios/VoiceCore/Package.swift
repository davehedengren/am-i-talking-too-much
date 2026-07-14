// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoiceCore", targets: ["VoiceCore"]),
    ],
    targets: [
        .target(name: "VoiceCore"),
        .testTarget(
            name: "VoiceCoreTests",
            dependencies: ["VoiceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
