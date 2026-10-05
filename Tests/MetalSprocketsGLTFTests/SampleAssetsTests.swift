import CoreGraphics
import Foundation
import GoldenImage
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

// Loads and renders every binary model from a local checkout of KhronosGroup/glTF-Sample-Assets.
// The assets are not downloaded by the tests. Run `just download-sample-assets` first.

enum SampleAssets {
    // <repo>/Tests/MetalSprocketsGLTFTests/SampleAssetsTests.swift -> <repo>
    static let modelsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: ".sample-assets/Models", directoryHint: .isDirectory)

    static var indexURL: URL { modelsDirectory.appending(path: "model-index.json") }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: indexURL.path) }

    struct Model: Decodable, CustomTestStringConvertible, Sendable {
        var name: String
        var variants: [String: String]
        var testDescription: String { name }

        var binaryURL: URL? {
            variants["glTF-Binary"].map { SampleAssets.modelsDirectory.appending(path: "\(name)/glTF-Binary/\($0)") }
        }

        /// The .glb, else the plain .gltf with its external files.
        var preferredURL: URL? {
            binaryURL ?? variants["glTF"].map { SampleAssets.modelsDirectory.appending(path: "\(name)/glTF/\($0)") }
        }
    }

    static func binaryModels() -> [Model] {
        guard let data = try? Data(contentsOf: indexURL), let models = try? JSONDecoder().decode([Model].self, from: data) else {
            return []
        }
        return models.filter { $0.binaryURL != nil }.sorted { $0.name < $1.name }
    }

    /// Models with a .glb or a plain .gltf variant.
    static func preferredModels() -> [Model] {
        guard let data = try? Data(contentsOf: indexURL), let models = try? JSONDecoder().decode([Model].self, from: data) else {
            return []
        }
        return models.filter { $0.preferredURL != nil }.sorted { $0.name < $1.name }
    }
}

@Suite(.serialized, .metalValidation)
struct SampleAssetsTests {
    // EXT_texture_webp: textures whose only source is a WebP image.
    @Test(.enabled(if: SampleAssets.isAvailable)) func loadsWebPTextures() throws {
        let url = SampleAssets.modelsDirectory.appending(path: "SheenWoodLeatherSofa/glTF-Binary/SheenWoodLeatherSofa.glb")
        let asset = try GLTFAsset(url: url)
        #expect(asset.warnings.isEmpty, "\(asset.warnings)")
        let enabledBaseColors = asset.materials.filter { $0.uniforms.baseColor.enabled != 0 }
        #expect(!enabledBaseColors.isEmpty)
    }

    // KHR_mesh_quantization: each glTF-Quantized sample renders like its unquantized .glb. Quantization rounds positions,
    // normals and texture coordinates, so the renders differ slightly at edges. AnimatedMorphCube also has quantized
    // morph targets, so it is compared mid-animation.
    @Test(.enabled(if: SampleAssets.isAvailable), arguments: ["Avocado", "Duck", "Lantern", "AnimatedMorphCube"])
    func quantizedMatchesUnquantized(_ name: String) throws {
        let directory = SampleAssets.modelsDirectory.appending(path: name)
        let quantized = try GLTFAsset(url: directory.appending(path: "glTF-Quantized/\(name).gltf"))
        let original = try GLTFAsset(url: directory.appending(path: "glTF-Binary/\(name).glb"))
        #expect(quantized.warnings.isEmpty, "\(quantized.warnings)")
        // Primitive counts can differ (the quantized Lantern combines its three meshes), so compare bounds and renders.
        let size = simd_length(original.bounds.max - original.bounds.min)
        #expect(simd_distance(quantized.bounds.min, original.bounds.min) < size * 0.01 && simd_distance(quantized.bounds.max, original.bounds.max) < size * 0.01)

        let camera = PBRCamera.framing(original.bounds, aspectRatio: 1)
        func render(_ asset: GLTFAsset) throws -> CGImage {
            let pose = asset.animations.isEmpty ? nil : asset.pose(animation: 0, time: 0.6)
            return try OffscreenRenderer(size: CGSize(width: 128, height: 128), clearDepth: 0).render(try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, pose: pose)
            }).cgImage
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let psnr = try ImageComparison().compare(try #require(render(quantized).copy(colorSpace: space)), try #require(render(original).copy(colorSpace: space))).psnr
        #expect(psnr > 35, "\(name): quantized and unquantized renders differ (\(psnr) dB)")
    }

    @Test func sampleAssetsArePresent() {
        #expect(SampleAssets.isAvailable, "glTF-Sample-Assets not found at \(SampleAssets.modelsDirectory.path). Run `just download-sample-assets` first.")
    }

    @Test(.enabled(if: SampleAssets.isAvailable), arguments: SampleAssets.binaryModels())
    func loadsAndRenders(_ model: SampleAssets.Model) throws {
        let url = try #require(model.binaryURL)
        let asset = try GLTFAsset(url: url)

        // Models made only of points or lines produce no instances; nothing to render.
        guard !asset.opaqueInstances.isEmpty || !asset.blendedInstances.isEmpty else {
            return
        }
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
            }
        ).cgImage
        #expect(try litPixelCount(image) > 0, "Rendered image is entirely background")
    }

    /// Pixels brighter than the black clear color.
    func litPixelCount(_ image: CGImage) throws -> Int {
        let width = image.width
        let height = image.height
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var count = 0
        for index in 0 ..< width * height where pixels[index * 4] > 2 || pixels[index * 4 + 1] > 2 || pixels[index * 4 + 2] > 2 {
            count += 1
        }
        return count
    }
}
