// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ox0badf00d",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "Ox0badf00d",
            targets: ["Ox0badf00d"]
        ),
    ],
    targets: [
        // Objective-C shim that turns AVAudioEngine's uncatchable NSExceptions into Swift errors.
        .target(name: "Ox0badf00dObjC"),
        .target(
            name: "Ox0badf00d",
            dependencies: ["Ox0badf00dObjC"]
        ),
        .testTarget(
            name: "Ox0badf00dTests",
            dependencies: ["Ox0badf00d"]
        ),
    ]
)
