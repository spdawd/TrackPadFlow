// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrackpadFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TrackpadFlow", targets: ["TrackpadFlow"])
    ],
    targets: [
        .executableTarget(
            name: "TrackpadFlow",
            path: "Sources/TrackpadFlow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
