// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BeeMeadow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BeeMeadow",
            path: "Sources/BeeMeadow",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
    ],
    swiftLanguageModes: [.v5]
)
