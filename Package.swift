// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SecondFactor",
    // iOS 16 is the oldest system with Swift Regex, which the URL check uses.
    // `SecondFactor.verify` itself needs iOS 17.4 and is marked so. macOS is
    // listed only so that `swift test` runs on a Mac.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SecondFactor", targets: ["SecondFactor"]),
    ],
    targets: [
        .target(name: "SecondFactor"),
        .testTarget(name: "SecondFactorTests", dependencies: ["SecondFactor"]),
    ]
)
