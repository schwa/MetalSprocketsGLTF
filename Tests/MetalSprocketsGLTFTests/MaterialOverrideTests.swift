import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

@Suite(.metalValidation)
struct MaterialOverrideTests {
    func render(_ asset: GLTFAsset, overrides: PBRModel.MaterialOverrides = [:], merging: Bool = true) throws -> [UInt8] {
        let size = 96
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let lighting = PBRLighting(lights: [.directional(direction: [-1, -1, -1], intensity: 2)], environment: try PBREnvironment(source: .uniform([0.5, 0.5, 0.5]), specularSize: 16, irradianceSize: 4))
        var renderer = PBRRenderer(model: asset.model, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting)
        renderer.materialOverrides = overrides
        renderer.usesMergedGeometry = merging
        let image = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(try RenderPass { renderer }).cgImage
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pixels, count: size * size * 4))
    }

    // A variant drawn through overrides on the default model matches the model rebuilt with that variant.
    @Test func overridesMatchRebuiltVariants() throws {
        let url = try makeVariantsTriangleFile()
        let asset = try GLTFAsset(url: url)
        let blue = try #require(try asset.materialOverrides(variant: 0))
        #expect(blue.count == 1)
        #expect(try asset.materialOverrides(variant: 1)?.isEmpty == true)
        #expect(try asset.materialOverrides(variant: nil)?.isEmpty == true)
        #expect(throws: (any Error).self) { try asset.materialOverrides(variant: 2) }
        #expect(try render(asset, overrides: blue) == render(asset.variant(0)))
        #expect(try render(asset, overrides: blue) != render(asset))
    }

    // Merged geometry applies overrides per record, the same as per-batch drawing.
    @Test func mergedGeometryAppliesOverrides() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        #expect(asset.merged != nil)
        let batches = asset.opaqueBatches
        #expect(batches.count >= 2)
        // Draw the first batch's primitive with the second batch's material.
        let overrides = [batches[0].primitive.key: batches[1].material]
        let merged = try render(asset, overrides: overrides, merging: true)
        #expect(try merged == render(asset, overrides: overrides, merging: false))
        #expect(try merged != render(asset, merging: true))
    }

    // With textures and merged geometry: every variant of the shoe, through overrides, both merged and per batch.
    @Test(.enabled(if: SampleAssets.isAvailable)) func overridesMatchRebuiltShoeVariants() throws {
        let url = SampleAssets.modelsDirectory.appending(path: "MaterialsVariantsShoe/glTF-Binary/MaterialsVariantsShoe.glb")
        let asset = try GLTFAsset(url: url)
        #expect(asset.variantNames.count >= 2)
        let defaultImage = try render(asset)
        var differs = false
        for variant in asset.variantNames.indices {
            let overrides = try #require(try asset.materialOverrides(variant: variant))
            let rebuilt = try asset.variant(variant)
            for merging in [true, false] {
                let image = try render(asset, overrides: overrides, merging: merging)
                #expect(try image == render(rebuilt, merging: merging), "variant \(variant), merging \(merging)")
                differs = differs || image != defaultImage
            }
        }
        #expect(differs, "No variant changed the image, so the test checks nothing")
    }
}
