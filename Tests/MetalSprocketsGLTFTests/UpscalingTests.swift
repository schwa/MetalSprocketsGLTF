import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// The red channel of a 64 x 64 render of an unlit red triangle on black, optionally drawn at `scale` and upscaled.
@MainActor
private func redChannel(upscaling: PBRUpscaling?) throws -> [UInt8] {
    let asset = try GLTFAsset(url: makeExtensionMaterialFile(#"{"KHR_materials_unlit": {}}"#, extensionsUsed: ["KHR_materials_unlit"]))
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    var scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, viewportSize: CGSize(width: 64, height: 64))
    scene.sampleCount = 4
    scene.upscaling = upscaling
    let image = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return (0 ..< 64 * 64).map { pixels[$0 * 4] }
}

@Suite(.requiresMetal4)
struct UpscalingTests {
    // Drawn at half size and upscaled with MetalFX, the frame matches the full-size one except near edges.
    @Test(.metalValidation) @MainActor
    func upscaledFrameMatchesFullSize() throws {
        guard PBRUpscaling.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        let full = try redChannel(upscaling: nil)
        let upscaled = try redChannel(upscaling: PBRUpscaling(scale: 0.5))
        #expect(upscaled[32 * 64 + 32] > 200, "The triangle's center is red")
        let meanDifference = zip(full, upscaled).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(full.count)
        #expect(meanDifference < 8, "Mean red difference \(meanDifference)")
        #expect(full != upscaled, "The upscaled path ran")
    }

    // Upscaling into a float (EDR) target keeps values above 1.
    @Test(.metalValidation) @MainActor
    func upscalesIntoFloatTargets() throws {
        guard PBRUpscaling.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        let asset = try GLTFAsset(url: makeExtensionMaterialFile(#"{"KHR_materials_unlit": {}}"#, extensionsUsed: ["KHR_materials_unlit"]))
        let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
        var lighting = PBRLighting()
        lighting.toneMapping = .none
        lighting.exposure = 4
        var scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 64, height: 64))
        scene.upscaling = PBRUpscaling(scale: 0.5, colorPixelFormat: .rgba16Float)
        let pixels = try OffscreenRenderer.hdr(size: CGSize(width: 64, height: 64)).render(scene).texture.float16Pixels()
        #expect(Float(pixels[(32 * 64 + 32) * 4]) > 3, "\(pixels[(32 * 64 + 32) * 4])")
    }
}
