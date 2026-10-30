// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrowserKit", targets: ["BrowserKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(name: "BrowserKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
                resources: [.copy("Extensions/compat.js"), .copy("DevTools/Scripts"), .copy("Fonts")]),
        .testTarget(name: "BrowserKitTests", dependencies: ["BrowserKit"]),
    ]
)
