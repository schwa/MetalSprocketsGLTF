import CoreGraphics
import Foundation
@testable import GLTFViewerSupport
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

private func render(_ scene: PBRScene, size: Int) throws -> [UInt8] {
    let image = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: pixels, count: size * size * 4))
}

// A second producer of PBRModel: each shape built directly renders exactly as the same mesh written as glTF and
// loaded through MetalSprocketsGLTF.
@Test(arguments: BasicShape.allCases)
func shapeBuiltWithoutGLTFMatchesGLTF(_ shape: BasicShape) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let direct = try shape.model(device: device)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).glb")
    try shape.mesh.glb(name: shape.name).write(to: url)
    let loaded = try GLTFAsset(url: url, device: device).model
    #expect(direct.bounds == loaded.bounds)

    let size = 64
    let camera = PBRCamera.framing(direct.bounds, aspectRatio: 1)
    let lighting = PBRLighting(lights: [.directional(direction: [-1, -1, -1], intensity: 2)], environment: try PBREnvironment(source: .uniform([0.4, 0.4, 0.4]), specularSize: 16, irradianceSize: 4))
    func scene(_ model: PBRModel) -> PBRScene {
        PBRScene(model: model, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, viewportSize: CGSize(width: size, height: size))
    }
    let directImage = try render(scene(direct), size: size)
    #expect(try directImage == render(scene(loaded), size: size))
    // Something was drawn.
    #expect(Set(directImage).count > 2)
}
