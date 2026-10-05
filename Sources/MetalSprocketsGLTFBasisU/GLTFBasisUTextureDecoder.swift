import BasisUniversalMetal
import Foundation
import Metal
import MetalSprocketsGLTF
import SwiftGLTF

/// KHR_texture_basisu: a texture's image is a KTX2 file with Basis Universal data, transcoded to a format the GPU can
/// sample (ASTC on Apple GPUs, BC7 on others, uncompressed as a fallback).
/// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_basisu
public struct KHRTextureBasisu: GLTFExtension {
    public static let extensionName = "KHR_texture_basisu"

    /// The KTX2 image.
    public let source: Int
}

/// Loads KHR_texture_basisu textures. Register it to load files using the extension:
///
/// ```swift
/// let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder()]))
/// ```
public struct GLTFBasisUTextureDecoder: GLTFTextureDecoder {
    public let extensionNames: Set<String> = [KHRTextureBasisu.extensionName]

    public init() {}

    public func imageIndex(for texture: Texture) -> Int? {
        (try? texture.extensionValue(KHRTextureBasisu.self))?.source
    }

    /// The material slot decides sRGB or linear, as glTF requires, not the KTX2 file's own flag. Files without mipmaps
    /// get a generated mip chain (stored uncompressed, as Metal cannot generate mipmaps for compressed formats).
    public func makeTexture(data: Data, sRGB: Bool, device: MTLDevice) throws -> MTLTexture {
        try BasisTextureLoader(device: device).makeTexture(from: data, colorSpace: sRGB ? .sRGB : .linear, generateMipmaps: true)
    }
}
