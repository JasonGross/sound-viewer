// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SoundViewer",
    platforms: [.macOS("14.4")],
    targets: [
        // Pure logic (no Core Audio, no UI) so it can be tested with Command Line Tools alone.
        .target(name: "SoundCore"),
        .executableTarget(
            name: "SoundViewer",
            dependencies: ["SoundCore"],
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox")]
        ),
        // Plain executable test runner: `swift run SoundCoreTests`.
        // (XCTest / Swift Testing need a full Xcode install with its license accepted.)
        .executableTarget(name: "SoundCoreTests", dependencies: ["SoundCore"]),
    ],
    swiftLanguageModes: [.v5]
)
