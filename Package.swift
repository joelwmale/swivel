// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swivel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwivelCore"),
        .executableTarget(
            name: "Swivel",
            dependencies: ["SwivelCore"],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
            ]
        ),
        .testTarget(name: "SwivelCoreTests", dependencies: ["SwivelCore"]),
    ],
    swiftLanguageModes: [.v5]
)
