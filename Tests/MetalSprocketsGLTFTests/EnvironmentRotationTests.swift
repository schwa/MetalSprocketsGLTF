import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// A 32 x 32 render of the studio environment's background seen along -Z, turned by `rotation` radians.
@MainActor
private func background(rotation: Float) throws -> [UInt8] {
    var lighting = PBRLighting()
    lighting.environmentRotation = rotation
    let view = simd_float4x4.lookAt(eye: .zero, target: [0, 0, -1], up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 2, aspectRatio: 1, near: 0.1, far: 10)
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(try RenderPass {
        PBREnvironmentBackground(lighting: lighting, viewMatrix: view, projectionMatrix: projection)
    }).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    return Array(UnsafeBufferPointer(start: try #require(context.data).assumingMemoryBound(to: UInt8.self), count: 32 * 32 * 4))
}

private func maximumDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
    zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

// Rotation turns the environment: a quarter turn shows a different part of the studio, a full turn the same view.
@Test(.metalValidation) @MainActor func environmentRotationTurnsTheEnvironment() throws {
    let unrotated = try background(rotation: 0)
    #expect(maximumDifference(try background(rotation: .pi / 2), unrotated) > 20)
    #expect(maximumDifference(try background(rotation: 2 * .pi), unrotated) <= 2)
}
