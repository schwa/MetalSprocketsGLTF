import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import simd
import Testing

/// The distinct red values in a 64 x 64 render of an unlit triangle on black.
@MainActor
private func distinctRedValues(sampleCount: Int) throws -> Set<UInt8> {
    let asset = try GLTFAsset(url: makeExtensionMaterialFile(#"{"KHR_materials_unlit": {}}"#, extensionsUsed: ["KHR_materials_unlit"]))
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    var scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, viewportSize: CGSize(width: 64, height: 64))
    scene.sampleCount = sampleCount
    let image = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return Set((0 ..< 64 * 64).map { pixels[$0 * 4] })
}

// Single-sampled, a flat triangle's edges are hard: only the background and the triangle's color appear.
@Test(.metalValidation) @MainActor func singleSampledEdgesAreHard() throws {
    let values = try distinctRedValues(sampleCount: 1)
    #expect(values.count == 2, "\(values.sorted())")
}

// With 4x MSAA, edge pixels blend the two colors.
@Test(.metalValidation) @MainActor func multisampledEdgesAreBlended() throws {
    let values = try distinctRedValues(sampleCount: 4)
    #expect(values.count > 2, "\(values.sorted())")
}
