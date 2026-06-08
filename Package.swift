// swift-tools-version: 5.9
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
            path: "RightClickAssistant/Core"
        ),
        .testTarget(
            name: "RightClickAssistantTests",
            dependencies: ["RightClickAssistantCore"],
            path: "RightClickAssistantTests"
        )
    ]
)
