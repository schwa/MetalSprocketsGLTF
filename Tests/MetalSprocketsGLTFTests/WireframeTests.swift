import CoreGraphics
import MetalSprockets
@testable import MetalSprocketsGLTF
import simd
import Testing

/// A 64 x 64 head-on render of a two-triangle quad (sRGB RGBA bytes).
@MainActor
private func renderQuad(wireframe: Bool) throws -> [UInt8] {
    let asset = try GLTFAsset(url: makeIndexedQuadWithoutNormalsFile())
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    var scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, viewportSize: CGSize(width: 64, height: 64))
    scene.showsWireframe = wireframe
    let image = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: pixels, count: 64 * 64 * 4))
}

private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> SIMD3<Int> {
    let offset = (y * 64 + x) * 4
    return SIMD3(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

// The two triangles share the quad's diagonal, which runs along y = 63 - x in the image (y points down): wireframe
// turns it cyan. A point well inside one triangle, away from every edge, is unchanged.
@Test(.metalValidation) @MainActor func wireframeDrawsTriangleEdgesOnly() throws {
    let plain = try renderQuad(wireframe: false)
    let wired = try renderQuad(wireframe: true)
    let edge = pixel(wired, x: 31, y: 32)
    #expect(edge.z > 200 && edge.y > 150 && edge.x < edge.z - 80, "edge \(edge), plain \(pixel(plain, x: 31, y: 32))")
    // About 11 pixels from the diagonal and from the quad's border.
    #expect(pixel(wired, x: 26, y: 26) == pixel(plain, x: 26, y: 26))
}
