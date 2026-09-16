// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeckCore"),
        .executableTarget(name: "ClaudeDeck", dependencies: ["DeckCore"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
    ]
)
