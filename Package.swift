// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nagbert",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "nag", targets: ["NagCLI"]),
        .executable(name: "nagbertd", targets: ["Nagbert"]),
    ],
    targets: [
        .target(
            name: "NagbertCore",
            path: "Sources/NagbertCore"
        ),
        .executableTarget(
            name: "NagCLI",
            dependencies: ["NagbertCore"],
            path: "Sources/NagCLI"
        ),
        .executableTarget(
            name: "Nagbert",
            dependencies: ["NagbertCore"],
            path: "Sources/Nagbert"
        ),
    ]
)
