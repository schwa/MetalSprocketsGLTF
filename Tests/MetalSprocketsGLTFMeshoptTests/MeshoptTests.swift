import CoreGraphics
import Foundation
import GoldenImage
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsGLTFMeshopt
import MetalSprocketsPBR
import simd
import Testing

// <repo>/Tests/MetalSprocketsGLTFMeshoptTests/MeshoptTests.swift -> <repo>/.sample-assets/Models
private let modelsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: ".sample-assets/Models", directoryHint: .isDirectory)
private let samplesAvailable = FileManager.default.fileExists(atPath: modelsDirectory.appending(path: "model-index.json").path)

private let options = GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()])

/// Each meshopt sample variant (KHR_ and EXT_ names) and the uncompressed variant of the same model.
private let pairs: [(id: String, compressed: String, plain: String)] = [
    ("BrainStem KHR", "BrainStem/glTF-Meshopt/BrainStem.gltf", "BrainStem/glTF-Binary/BrainStem.glb"),
    ("BrainStem EXT", "BrainStem/glTF-Meshopt-EXT/BrainStem.gltf", "BrainStem/glTF-Binary/BrainStem.glb"),
    ("DragonAttenuation KHR", "DragonAttenuation/glTF-Meshopt/DragonAttenuation.gltf", "DragonAttenuation/glTF-Binary/DragonAttenuation.glb"),
    ("DragonAttenuation EXT", "DragonAttenuation/glTF-Meshopt-EXT/DragonAttenuation.gltf", "DragonAttenuation/glTF-Binary/DragonAttenuation.glb"),
    ("MeshoptCubeTest", "MeshoptCubeTest/glTF-Meshopt/MeshoptCubeTest.gltf", "MeshoptCubeTest/glTF/MeshoptCubeTest.gltf"),
]

// Without the decoder, files requiring meshopt are rejected; with it they load without warnings.
@Test(.enabled(if: samplesAvailable), arguments: ["BrainStem/glTF-Meshopt/BrainStem.gltf", "BrainStem/glTF-Meshopt-EXT/BrainStem.gltf"])
func meshoptVariantNeedsTheDecoder(_ path: String) throws {
    let url = modelsDirectory.appending(path: path)
    #expect(throws: GLTFUnsupportedExtensionsError.self) { try GLTFAsset(url: url) }
    let asset = try GLTFAsset(url: url, options: options)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
}

// The compressed variant renders like the uncompressed one (meshopt variants are also quantized, so close, not equal).
// Animated models are compared mid-animation, which exercises compressed animation data too.
@Test(.enabled(if: samplesAvailable), arguments: pairs.map(\.id))
func meshoptVariantMatchesThePlainVariant(_ id: String) throws {
    let pair = try #require(pairs.first { $0.id == id })
    let compressed = try GLTFAsset(url: modelsDirectory.appending(path: pair.compressed), options: options)
    let plain = try GLTFAsset(url: modelsDirectory.appending(path: pair.plain))
    #expect(compressed.warnings.isEmpty, "\(compressed.warnings)")
    #expect(compressed.statistics.triangles == plain.statistics.triangles)
    let camera = PBRCamera.framing(plain.bounds, aspectRatio: 1)
    func render(_ asset: GLTFAsset) throws -> CGImage {
        let pose = asset.animations.isEmpty ? nil : asset.pose(animation: 0, time: 0.6)
        return try OffscreenRenderer(size: CGSize(width: 256, height: 256), clearDepth: 0).render(
            GLTFScene(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, pose: pose, viewportSize: CGSize(width: 256, height: 256))
        ).cgImage
    }
    let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let psnr = try ImageComparison().compare(try #require(render(compressed).copy(colorSpace: space)), try #require(render(plain).copy(colorSpace: space))).psnr
    #expect(psnr > 30, "\(id): compressed and plain renders differ (\(psnr) dB)")
}
