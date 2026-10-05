import BasisUniversalMetal
import Foundation
import Metal
import MetalSprocketsGLTF
import SwiftGLTF

/// EXT_texture_astc: a texture's image is a KTX2 file of ASTC blocks (LDR, any block size), which Apple GPUs sample
/// directly, with no transcoding.
/// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Vendor/EXT_texture_astc
public struct EXTTextureASTC: GLTFExtension {
    public static let extensionName = "EXT_texture_astc"

    /// The KTX2 image.
    public let source: Int
}

/// Loads EXT_texture_astc textures. Register it to load files using the extension:
///
/// ```swift
/// let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(textureDecoders: [GLTFASTCTextureDecoder()]))
/// ```
///
/// Without it, textures fall back to their regular `source` (if any).
public struct GLTFASTCTextureDecoder: GLTFTextureDecoder {
    public let extensionNames: Set<String> = [EXTTextureASTC.extensionName]

    public init() {}

    public func imageIndex(for texture: Texture) -> Int? {
        (try? texture.extensionValue(EXTTextureASTC.self))?.source
    }

    /// The material slot decides sRGB or linear, as glTF requires, not the KTX2 file's own flag. The spec requires a
    /// full mip chain where the sampler uses mipmaps; files without one get a generated chain (stored uncompressed).
    public func makeTexture(data: Data, sRGB: Bool, device: MTLDevice) throws -> MTLTexture {
        try BasisTextureLoader(device: device).makeTexture(from: data, colorSpace: sRGB ? .sRGB : .linear, generateMipmaps: true)
    }
}
