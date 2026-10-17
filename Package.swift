// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsGLTF",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "MetalSprocketsGLTF", targets: ["MetalSprocketsGLTF"]),
        .library(name: "MetalSprocketsGLTFBasisU", targets: ["MetalSprocketsGLTFBasisU"]),
        .library(name: "MetalSprocketsGLTFMeshopt", targets: ["MetalSprocketsGLTFMeshopt"])
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/SwiftGLTF", .upToNextMinor(from: "1.0.4")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.10")),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.4")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.3")),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.6")),
        .package(url: "https://github.com/schwa/BasisUniversalMetal", .upToNextMinor(from: "0.0.3"))
    ],
    targets: [
        .target(
            name: "MetalSprocketsGLTF",
            dependencies: [
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "SwiftMeshMikkTSpace", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport")
            ]
        ),
        .executableTarget(
            name: "ms-gltf-render",
            dependencies: [
                "MetalSprocketsGLTF",
                "MetalSprocketsGLTFBasisU",
                "MetalSprocketsGLTFMeshopt",
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "MetalSprocketsGLTFBasisU",
            dependencies: [
                "MetalSprocketsGLTF",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "BasisUniversalMetal", package: "BasisUniversalMetal")
            ]
        ),
        // meshoptimizer's decoder (vendored, MIT; see Sources/CMeshoptimizer/VERSION).
        .target(
            name: "CMeshoptimizer",
            exclude: ["LICENSE.md", "VERSION"]
        ),
        .target(
            name: "MetalSprocketsGLTFMeshopt",
            dependencies: [
                "CMeshoptimizer",
                .product(name: "SwiftGLTF", package: "SwiftGLTF")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFMeshoptTests",
            dependencies: [
                "MetalSprocketsGLTFMeshopt",
                "MetalSprocketsGLTF",
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFBasisUTests",
            dependencies: [
                "MetalSprocketsGLTFBasisU",
                "MetalSprocketsGLTF",
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ],
            // Plain ASTC KTX2 images for EXT_texture_astc, from BasisUniversalMetal's tests: astc_6x6_srgb (one level)
            // and astc_8x8_srgb_zstd (full mip chain).
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFTests",
            dependencies: [
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
                "MetalSprocketsGLTF",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ],
            resources: [
                .copy("GoldenImages")
            ]
        )
    ]
)
