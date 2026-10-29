// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-module-map",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "module-map-ios", targets: ["module-map-ios"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0")
    ],
    targets: [
        .target(
            name: "ModuleMapCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "module-map-ios",
            dependencies: ["ModuleMapCore"]
        ),
        .testTarget(
            name: "module-map-ios-tests",
            dependencies: ["ModuleMapCore"]
        )
    ]
)
