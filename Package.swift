// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceStudio",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VoiceStudioCore", targets: ["VoiceStudioCore"]),
        .executable(name: "VoiceStudio", targets: ["VoiceStudioApp"])
    ],
    targets: [
        .target(
            name: "VoiceStudioCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Accelerate")
            ]
        ),
        .executableTarget(
            name: "VoiceStudioApp",
            dependencies: ["VoiceStudioCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "VoiceStudioTests",
            dependencies: ["VoiceStudioCore"]
        )
    ]
)
