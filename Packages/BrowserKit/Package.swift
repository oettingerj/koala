// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrowserKit", targets: ["BrowserKit"]),
    ],
    targets: [
        .target(name: "BrowserKit"),
        .testTarget(name: "BrowserKitTests", dependencies: ["BrowserKit"]),
    ]
)
