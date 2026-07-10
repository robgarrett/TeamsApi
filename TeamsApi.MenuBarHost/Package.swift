// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TeamsApiMenuBarHost",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "TeamsApiMenuBarHost"
        ),
        .testTarget(
            name: "TeamsApiMenuBarHostTests",
            dependencies: ["TeamsApiMenuBarHost"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
