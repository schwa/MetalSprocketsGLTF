import CoreGraphics
import Foundation
import ImageIO
import Metal
@testable import MetalSprocketsGLTF
import MetalSprocketsPBRShaders
import MetalSupport
import Testing

// Base color textures must reach the GPU as sRGB texels whose stored bytes equal the PNG's sRGB pixel values,
// whatever the PNG's pixel layout (palette, RGB, grey + alpha, RGBA).
@Suite(.serialized, .metalValidation, .enabled(if: SampleAssets.isAvailable))
struct TextureDecodingTests {
    /// RGBA8 bytes of `texture`'s first mip, copied to shared memory.
    func texels(_ texture: MTLTexture) throws -> [UInt8] {
        let device = texture.device
        let bytesPerRow = texture.width * 4
        let buffer = try #require(device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * texture.height)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: buffer.length))
    }

    /// The PNG's pixels as 8-bit sRGB RGBA, decoded by ImageIO.
    func expectedPixels(_ data: Data, width: Int, height: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    @Test(arguments: ["BoxTextured", "TextureLinearInterpolationTest", "DamagedHelmet"])
    func baseColorTexelsMatchPNG(_ name: String) throws {
        let url = SampleAssets.modelsDirectory.appending(path: "\(name)/glTF-Binary/\(name).glb")
        let asset = try GLTFAsset(url: url)
        let material = try #require(asset.materials.first { $0.uniforms.baseColor.enabled != 0 })
        let texture = material[texture: kPBRTextureBaseColor].texture
        #expect(texture.pixelFormat == .rgba8Unorm_srgb || texture.pixelFormat == .bgra8Unorm_srgb, "\(name): \(texture.pixelFormat.rawValue)")

        let cache = GLTFTextureCache(container: asset.container, device: texture.device)
        let textureIndex = try #require(asset.container.document.materials.first { $0.pbrMetallicRoughness?.baseColorTexture != nil }?.pbrMetallicRoughness?.baseColorTexture?.index.index)
        let imageIndex = try #require(GLTFTextureCache.imageIndex(of: asset.container.document.textures[textureIndex]))
        let expected = try expectedPixels(cache.imageData(imageIndex), width: texture.width, height: texture.height)
        var actual = try texels(texture)
        if texture.pixelFormat == .bgra8Unorm_srgb {
            for index in stride(from: 0, to: actual.count, by: 4) {
                actual.swapAt(index, index + 2)
            }
        }
        // Compare opaque texels only; premultiplication makes translucent ones differ by design.
        var worst = 0
        var total = 0
        var count = 0
        for index in stride(from: 0, to: expected.count, by: 4) where expected[index + 3] == 255 {
            for channel in 0 ..< 3 {
                let difference = abs(Int(expected[index + channel]) - Int(actual[index + channel]))
                worst = max(worst, difference)
                total += difference
                count += 1
            }
        }
        let mean = Double(total) / Double(max(count, 1))
        #expect(mean <= 1, "\(name): texels differ from the image by \(String(format: "%.2f", mean)) on average, up to \(worst)")
    }
}
