import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsPBR
import Testing
import UniformTypeIdentifiers

/// A 2 x 2 white PNG, the fallback image.
private func whitePNG() throws -> Data {
    let pixels = [UInt8](repeating: 255, count: 2 * 2 * 4)
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A triangle whose material uses one EXT_texture_astc texture for base color (sRGB) and metallic-roughness
/// (linear); with `fallback`, the texture also has a PNG `source`; otherwise the extension is required.
private func makeASTCFile(fallback: Bool, image: String = "astc_6x6_srgb") throws -> URL {
    let ktx = try Data(contentsOf: try #require(Bundle.module.url(forResource: image, withExtension: "ktx2", subdirectory: "Resources")))
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let images = (fallback ? [#"{"uri": "data:image/png;base64,\#(try whitePNG().base64EncodedString())"}"#] : [])
        + [#"{"uri": "data:image/ktx2;base64,\#(ktx.base64EncodedString())", "mimeType": "image/ktx2"}"#]
    let astcImage = images.count - 1
    let texture = fallback ? #"{"source": 0, "extensions": {"EXT_texture_astc": {"source": \#(astcImage)}}}"# : #"{"extensions": {"EXT_texture_astc": {"source": \#(astcImage)}}}"#
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["EXT_texture_astc"]\(fallback ? "" : #", "extensionsRequired": ["EXT_texture_astc"]"#),
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 0}}}],
      "textures": [\(texture)],
      "images": [\(images.joined(separator: ", "))],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

private let astcOptions = GLTFLoadOptions(textureDecoders: [GLTFASTCTextureDecoder()])

// An ASTC image with a full mip chain (as the spec requires for mipmapped samplers) is uploaded as-is: the same block
// size and every level, sRGB in a color slot and linear in a data slot.
@Test(.requiresMetal4, .requiresMetal4) func astcWithMipsStaysASTC() throws {
    let asset = try GLTFAsset(url: makeASTCFile(fallback: true, image: "astc_8x8_srgb_zstd"), options: astcOptions)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
    let material = try #require(asset.materials.first)
    let baseColor = material[texture: kPBRTextureBaseColor].texture
    #expect(baseColor.pixelFormat == .astc_8x8_srgb)
    #expect(baseColor.mipmapLevelCount == 9)
    #expect(material[texture: kPBRTextureMetallicRoughness].texture.pixelFormat == .astc_8x8_ldr)
}

// A single-level ASTC image (256 x 256) gets a generated mip chain, stored uncompressed: Metal cannot generate mipmaps
// for compressed formats. Color space still follows the slot.
@Test(.requiresMetal4, .requiresMetal4) func singleLevelASTCIsDecodedForMipmaps() throws {
    let asset = try GLTFAsset(url: makeASTCFile(fallback: true), options: astcOptions)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
    let material = try #require(asset.materials.first)
    let baseColor = material[texture: kPBRTextureBaseColor].texture
    let metallicRoughness = material[texture: kPBRTextureMetallicRoughness].texture
    #expect(baseColor.width == 256 && baseColor.mipmapLevelCount > 1)
    #expect(baseColor.pixelFormat == .rgba8Unorm_srgb)
    #expect(metallicRoughness.pixelFormat == .rgba8Unorm)
}

// Without the decoder, the texture falls back to its PNG source.
@Test(.requiresMetal4, .requiresMetal4) func astcFallsBackWithoutTheDecoder() throws {
    let asset = try GLTFAsset(url: makeASTCFile(fallback: true))
    let material = try #require(asset.materials.first)
    #expect(material[texture: kPBRTextureBaseColor].texture.pixelFormat != .astc_6x6_srgb)
    #expect(material[texture: kPBRTextureBaseColor].texture.width == 2)
}

// A file that requires the extension (no fallback) needs the decoder.
@Test(.requiresMetal4, .requiresMetal4) func requiredASTCNeedsTheDecoder() throws {
    let url = try makeASTCFile(fallback: false)
    #expect(throws: GLTFUnsupportedExtensionsError.self) { try GLTFAsset(url: url) }
    let asset = try GLTFAsset(url: url, options: astcOptions)
    #expect(asset.materials.first?[texture: kPBRTextureBaseColor].texture.width == 256)
}
