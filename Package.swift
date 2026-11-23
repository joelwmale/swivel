// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmdTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CmdTabCore"),
        .executableTarget(
            name: "CmdTab",
            dependencies: ["CmdTabCore"],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
            ]
        ),
        .testTarget(name: "CmdTabCoreTests", dependencies: ["CmdTabCore"]),
    ],
    swiftLanguageModes: [.v5]
)
