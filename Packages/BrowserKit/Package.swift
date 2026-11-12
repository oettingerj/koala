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
        .package(path: "../../../eucalyptus"),
    ],
    targets: [
        .target(name: "BrowserKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift"), .product(name: "Eucalyptus", package: "eucalyptus")],
                resources: [.copy("Extensions/compat.js"), .copy("DevTools/Scripts")]),
        .testTarget(name: "BrowserKitTests", dependencies: ["BrowserKit"]),
    ]
)
