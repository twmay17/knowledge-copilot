// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenOats",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "OpenOatsKit",
            targets: ["OpenOatsKit"]
        ),
        .library(
            name: "HospitalityDomainProfile",
            targets: ["HospitalityDomainProfile"]
        ),
        .executable(
            name: "OpenOats",
            targets: ["OpenOatsAppExecutable"]
        ),
        .executable(
            name: "Benchmark",
            targets: ["Benchmark"]
        ),
        .executable(
            name: "knowledge-pack",
            targets: ["KnowledgePackTool"]
        ),
        .executable(
            name: "audio-capture-verify",
            targets: ["AudioCaptureVerificationTool"]
        ),
    ],
    dependencies: [
        // FluidAudio has made source-breaking API changes in patch releases.
        // Pin exactly so SwiftPM and Xcode smoke builds resolve the same SDK.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "OpenOatsKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Sources/OpenOats",
            exclude: ["Info.plist", "OpenOats.entitlements", "Assets", "Resources"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "OpenOatsAppExecutable",
            dependencies: ["OpenOatsKit", "HospitalityDomainProfile"],
            path: "Sources/OpenOatsApp"
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Benchmark"
        ),
        .executableTarget(
            name: "KnowledgePackTool",
            dependencies: ["OpenOatsKit", "HospitalityDomainProfile"],
            path: "Sources/KnowledgePackTool"
        ),
        .executableTarget(
            name: "AudioCaptureVerificationTool",
            dependencies: ["OpenOatsKit"],
            path: "Sources/AudioCaptureVerificationTool"
        ),
        .target(
            name: "HospitalityDomainProfile",
            dependencies: ["OpenOatsKit"],
            path: "Sources/DomainProfiles/Hospitality"
        ),
        .testTarget(
            name: "OpenOatsTests",
            dependencies: ["OpenOatsKit", "HospitalityDomainProfile"],
            path: "Tests/OpenOatsTests"
        ),
    ]
)
