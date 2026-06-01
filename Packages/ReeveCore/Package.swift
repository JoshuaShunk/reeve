// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReeveCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReeveModels", targets: ["ReeveModels"]),
        .library(name: "ReeveNetworking", targets: ["ReeveNetworking"]),
        .library(name: "ReevePersistence", targets: ["ReevePersistence"]),
        .library(name: "ReeveFeatures", targets: ["ReeveFeatures"]),
        .library(name: "ReeveTerminal", targets: ["ReeveTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.1"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0"),
    ],
    targets: [
        .target(name: "ReeveModels"),
        .target(
            name: "ReeveNetworking",
            dependencies: ["ReeveModels"]
        ),
        .target(
            name: "ReevePersistence",
            dependencies: ["ReeveModels"]
        ),
        .target(
            name: "ReeveFeatures",
            dependencies: ["ReeveModels", "ReeveNetworking", "ReevePersistence"]
        ),
        .target(
            name: "ReeveTerminal",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "ReeveCoreTests",
            dependencies: ["ReeveModels", "ReeveNetworking", "ReevePersistence"]
        ),
    ]
)
