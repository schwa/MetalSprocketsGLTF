// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GLTFViewerSupport",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "GLTFViewerSupport", targets: ["GLTFViewerSupport"])
    ],
    dependencies: [
        .package(path: "../../../.."),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(path: "../WebReference"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", from: "0.1.13"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/GeometryLite3D", from: "0.2.2")
    ],
    targets: [
        .target(
            name: "GLTFViewerSupport",
            dependencies: [
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "WebReference", package: "WebReference"),
                .product(name: "MetalSprocketsGLTFBasisU", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsGLTFMeshopt", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D")
            ],
            // Built by `just basic-shapes`.
            resources: [.copy("Resources/BasicShapes")]
        ),
        .testTarget(
            name: "GLTFViewerSupportTests",
            dependencies: [
                "GLTFViewerSupport",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsGLTFMeshopt", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
