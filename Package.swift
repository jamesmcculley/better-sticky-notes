// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "notestack",
    platforms: [.macOS(.v14)],
    targets: [
        // All the real logic lives here, as a library -- an executable-target-depends-on-
        // executable-target setup (what this used to be) doesn't reliably link; a library
        // target depended on by both the real app and the checks target is the well-supported
        // SPM shape. -enable-testing so `@testable import NotestackKit` below actually links
        // (SPM only adds that flag automatically for modules reachable from a real .testTarget,
        // which this package can't use -- see notestackChecks's own comment).
        .target(name: "NotestackKit", swiftSettings: [.unsafeFlags(["-enable-testing"])]),
        .executableTarget(name: "notestack", dependencies: ["NotestackKit"]),
        // A plain executable, not .testTarget: this CLT-only toolchain (no full Xcode) has
        // neither XCTest nor the Testing module available, so `swift test` can't run at all.
        // `@testable import` is a compiler feature, not a framework, so a plain executable can
        // still reach NotestackKit's internal types and run real assertions -- see
        // Tests/notestackChecks/main.swift and AGENTS.md trap 2 for why this exists.
        .executableTarget(name: "notestackChecks", dependencies: ["NotestackKit"], path: "Tests/notestackChecks")
    ]
)
