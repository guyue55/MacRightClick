// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RightClickAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RightClickAssistantCore",
            targets: ["RightClickAssistantCore"]
        )
    ],
    targets: [
        .target(
            name: "RightClickAssistantCore",
            path: "Sources/RightClickAssistant/Core"
        ),
        .testTarget(
            name: "RightClickAssistantTests",
            dependencies: ["RightClickAssistantCore"],
            path: "Tests"
        )
    ]
)
