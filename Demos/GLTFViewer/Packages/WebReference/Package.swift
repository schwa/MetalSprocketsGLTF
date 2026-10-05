// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WebReference",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "WebReference", targets: ["WebReference"]),
    ],
    dependencies: [
        .package(path: "../../../.."),
        .package(path: "../../../../../MetalSprocketsPBR"),
        .package(url: "https://github.com/schwa/MetalSprockets", from: "0.2.2"),
        .package(url: "https://github.com/schwa/MetalSupport", from: "1.0.7"),
        .package(url: "https://github.com/schwa/GoldenImage", from: "0.1.5"),
    ],
    targets: [
        .target(
            name: "WebReference",
            dependencies: [
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
            ],
            resources: [.copy("Web")]
        ),
        .testTarget(
            name: "WebReferenceTests",
            dependencies: [
                "WebReference",
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "GoldenImage", package: "GoldenImage"),
            ],
            // Read and written in place through #filePath, not bundled.
            exclude: ["ReferencePSNR.json"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
