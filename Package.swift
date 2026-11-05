// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "notestack",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotestackKit", swiftSettings: [.unsafeFlags(["-enable-testing"])]),
        .executableTarget(name: "notestack", dependencies: ["NotestackKit"]),
        .executableTarget(name: "notestackChecks", dependencies: ["NotestackKit"], path: "Tests/notestackChecks")
    ]
)
