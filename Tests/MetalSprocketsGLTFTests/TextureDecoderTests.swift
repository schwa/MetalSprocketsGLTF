import Foundation
import Metal
@testable import MetalSprocketsGLTF
import MetalSprocketsPBRShaders
import SwiftGLTF
import Testing

/// TEST_texture_fake: a test-only texture extension naming its own image, like KHR_texture_basisu.
private struct FakeTextureExtension: GLTFExtension {
    static let extensionName = "TEST_texture_fake"
    let source: Int
}

/// Makes a 3 x 5 texture from any bytes (the size identifies it; the loader relabels textures with their image name).
private final class FakeDecoder: GLTFTextureDecoder, @unchecked Sendable {
    let extensionNames: Set<String> = ["TEST_texture_fake"]
    private let lock = NSLock()
    private var requests: [(bytes: Int, sRGB: Bool)] = []

    var recordedRequests: [(bytes: Int, sRGB: Bool)] {
        lock.withLock { requests }
    }

    func imageIndex(for texture: Texture) -> Int? {
        (try? texture.extensionValue(FakeTextureExtension.self))?.source
    }

    func makeTexture(data: Data, sRGB: Bool, device: MTLDevice) throws -> MTLTexture {
        lock.withLock { requests.append((data.count, sRGB)) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sRGB ? .rgba8Unorm_srgb : .rgba8Unorm, width: 3, height: 5, mipmapped: false)
        return try #require(device.makeTexture(descriptor: descriptor))
    }
}

/// Fails every image, counting attempts.
private final class FailingDecoder: GLTFTextureDecoder, @unchecked Sendable {
    let extensionNames: Set<String> = ["TEST_texture_fake"]
    private let lock = NSLock()
    private var count = 0

    var attempts: Int {
        lock.withLock { count }
    }

    func imageIndex(for texture: Texture) -> Int? {
        (try? texture.extensionValue(FakeTextureExtension.self))?.source
    }

    func makeTexture(data _: Data, sRGB _: Bool, device _: MTLDevice) throws -> MTLTexture {
        lock.withLock { count += 1 }
        throw GLTFError.unsupported("broken")
    }
}

/// A triangle whose base color texture is `texture` (JSON), with image 0 holding `imageBytes` arbitrary bytes and
/// image 1 a real 1 x 1 PNG. `required` goes into extensionsRequired.
private func makeFile(texture: String, imageBytes: Int = 7, required: [String] = []) throws -> URL {
    let fake = Data(repeating: 0xAB, count: imageBytes).base64EncodedString()
    // A 1 x 1 opaque white PNG.
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["TEST_texture_fake"],
      "extensionsRequired": [\(required.map { "\"\($0)\"" }.joined(separator: ", "))],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 0}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
      "textures": [\(texture)],
      "images": [{"uri": "data:application/octet-stream;base64,\(fake)"}, {"uri": "data:image/png;base64,\(png)"}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

private func baseColorTexture(_ asset: GLTFAsset) throws -> MTLTexture {
    try #require(asset.materials.first)[texture: kPBRTextureBaseColor].texture
}

// A registered decoder gets the texture its extension names, decodes that image's bytes, and is told the slot is sRGB.
@Test(.requiresMetal4, .requiresMetal4) func registeredDecoderSuppliesItsTexture() throws {
    let decoder = FakeDecoder()
    let url = try makeFile(texture: #"{"extensions": {"TEST_texture_fake": {"source": 0}}}"#, imageBytes: 7)
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(textureDecoders: [decoder]))
    let texture = try baseColorTexture(asset)
    #expect(texture.width == 3 && texture.height == 5)
    #expect(decoder.recordedRequests.map(\.bytes) == [7])
    #expect(decoder.recordedRequests.map(\.sRGB) == [true])
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
}

// The extension's image wins over the plain source (the fallback for loaders without the extension).
@Test(.requiresMetal4, .requiresMetal4) func registeredDecoderWinsOverTheFallbackSource() throws {
    let url = try makeFile(texture: #"{"source": 1, "extensions": {"TEST_texture_fake": {"source": 0}}}"#)
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(textureDecoders: [FakeDecoder()]))
    #expect(try baseColorTexture(asset).width == 3)
}

// Without the decoder, the fallback source loads through the built-in path.
@Test(.requiresMetal4, .requiresMetal4) func withoutTheDecoderTheFallbackSourceLoads() throws {
    let asset = try GLTFAsset(url: makeFile(texture: #"{"source": 1, "extensions": {"TEST_texture_fake": {"source": 0}}}"#))
    // The 1 x 1 PNG, not the fake 3 x 5 texture. The white placeholder is also 1 x 1, but using it (texture skipped
    // or failed) would add a warning.
    #expect(try baseColorTexture(asset).width == 1)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
}

// A file requiring an extension nothing supports fails to load, naming it (the glTF spec's rule).
@Test(.requiresMetal4, .requiresMetal4) func unsupportedRequiredExtensionFailsTheLoad() throws {
    let url = try makeFile(texture: #"{"source": 1}"#, required: ["TEST_unknown"])
    #expect {
        try GLTFAsset(url: url)
    } throws: { error in
        (error as? GLTFUnsupportedExtensionsError)?.extensions == ["TEST_unknown"]
    }
}

// The option loads it anyway, with a warning.
@Test(.requiresMetal4, .requiresMetal4) func unsupportedRequiredExtensionCanBeLoadedWithAWarning() throws {
    let url = try makeFile(texture: #"{"source": 1}"#, required: ["TEST_unknown"])
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(loadsUnsupportedRequiredExtensions: true))
    #expect(asset.warnings.contains { $0.contains("TEST_unknown") }, "\(asset.warnings)")
}

// A registered decoder's extensions count as supported; built-in ones always do.
@Test(.requiresMetal4, .requiresMetal4) func registeredDecodersMakeTheirExtensionsSupported() throws {
    let url = try makeFile(texture: #"{"extensions": {"TEST_texture_fake": {"source": 0}}}"#, required: ["TEST_texture_fake", "KHR_texture_transform"])
    #expect(throws: GLTFUnsupportedExtensionsError.self) { try GLTFAsset(url: url) }
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(textureDecoders: [FakeDecoder()]))
    #expect(try baseColorTexture(asset).width == 3)
}

// The cache loads each (image, color space) once: a binding reuses the preloaded texture, and a failed image is not
// decoded again when a material asks for it; it is reported as a warning.
@Test(.requiresMetal4, .requiresMetal4) func textureCacheLoadsEachImageOnce() throws {
    let container = try Container(url: makeFile(texture: #"{"extensions": {"TEST_texture_fake": {"source": 0}}}"#))
    let device = try #require(MTLCreateSystemDefaultDevice())
    let index = try #require(container.document.materials.first?.pbrMetallicRoughness?.baseColorTexture).index
    let decoder = FakeDecoder()
    let cache = GLTFTextureCache(container: container, device: device, decoders: [decoder])
    cache.preload(container.document.materials)
    let first = try #require(cache.binding(for: index, sRGB: true)).texture
    let second = try #require(cache.binding(for: index, sRGB: true)).texture
    #expect(first === second)
    #expect(decoder.recordedRequests.count == 1)
    _ = cache.binding(for: index, sRGB: false)
    #expect(decoder.recordedRequests.map(\.sRGB) == [true, false])

    let failing = FailingDecoder()
    let failingCache = GLTFTextureCache(container: container, device: device, decoders: [failing])
    failingCache.preload(container.document.materials)
    #expect(failingCache.binding(for: index, sRGB: true) == nil)
    // A second material using the same broken image: no new decode, no duplicate warning.
    #expect(failingCache.binding(for: index, sRGB: true) == nil)
    #expect(failing.attempts == 1)
    #expect(failingCache.warnings.filter { $0.contains("Image 0 failed to load") }.count == 1, "\(failingCache.warnings)")
}

// Without the decoder and without a fallback, the texture is skipped with a warning.
@Test(.requiresMetal4, .requiresMetal4) func withoutTheDecoderOrAFallbackTheTextureIsSkipped() throws {
    let asset = try GLTFAsset(url: makeFile(texture: #"{"extensions": {"TEST_texture_fake": {"source": 0}}}"#))
    #expect(asset.warnings.contains { $0.contains("Texture 0 skipped") }, "\(asset.warnings)")
}
