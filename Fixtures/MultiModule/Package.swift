// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiModule",
    targets: [
        .target(name: "Core"),
        .target(name: "Feature", dependencies: ["Core"])
    ]
)
