import Foundation
import Metal
import SwiftGLTF

/// Decodes the images of a texture extension that brings its own image format (e.g. KHR_texture_basisu), so the
/// extension can live in a separate target and be registered through ``GLTFLoadOptions``.
public protocol GLTFTextureDecoder: Sendable {
    /// The glTF extensions this decoder implements, e.g. "KHR_texture_basisu".
    var extensionNames: Set<String> { get }

    /// The image to decode for `texture` (usually named by the extension), or nil to leave the texture to the next
    /// decoder and then the built-in PNG / JPEG / WebP path.
    func imageIndex(for texture: Texture) -> Int?

    /// Decodes an image chosen by ``imageIndex(for:)``. `sRGB` is true for color textures (base color, emissive...)
    /// and false for data textures (normals, metallic-roughness...). Called in parallel for different images.
    func makeTexture(data: Data, sRGB: Bool, device: MTLDevice) throws -> MTLTexture
}

/// Options for loading a ``GLTFAsset``.
public struct GLTFLoadOptions: Sendable {
    /// Decoders asked, in order, before the built-in image path.
    public var textureDecoders: [any GLTFTextureDecoder]
    /// Decoders for compressed buffer views (e.g. meshopt), added to the file's Container.
    public var bufferViewDecoders: [any BufferViewDecoder]
    /// Extensions to ignore: the file loads as if it did not use them (to compare with and without an extension, or
    /// to work around a broken one). Disabling one the file requires makes it unsupported, so the load fails unless
    /// `loadsUnsupportedRequiredExtensions` is set.
    public var disabledExtensions: Set<String>
    /// A file listing an unsupported extension in `extensionsRequired` fails to load, as the glTF spec requires.
    /// Set this to load it anyway, with a warning; what the extension adds is then missing or wrong.
    public var loadsUnsupportedRequiredExtensions: Bool

    public init(textureDecoders: [any GLTFTextureDecoder] = [], bufferViewDecoders: [any BufferViewDecoder] = [], disabledExtensions: Set<String> = [], loadsUnsupportedRequiredExtensions: Bool = false) {
        self.textureDecoders = textureDecoders
        self.bufferViewDecoders = bufferViewDecoders
        self.disabledExtensions = disabledExtensions
        self.loadsUnsupportedRequiredExtensions = loadsUnsupportedRequiredExtensions
    }

    /// The extensions a load with these options supports: ``GLTFAsset/builtInExtensions`` plus the decoders', minus
    /// the disabled ones.
    public var supportedExtensions: Set<String> {
        let names = textureDecoders.map(\.extensionNames) + bufferViewDecoders.map(\.extensionNames)
        return names.reduce(GLTFAsset.builtInExtensions) { $0.union($1) }.subtracting(disabledExtensions)
    }
}

public extension GLTFAsset {
    /// Extensions this package supports without registered decoders: SwiftGLTF's (``Document/supportedExtensions``),
    /// the material extensions from `GLTFMaterialFeature`, and the ones below.
    static let builtInExtensions: Set<String> = Document.supportedExtensions.union(GLTFMaterialFeature.extensionNames).union([
        "KHR_animation_pointer",
        KHRMaterialsVariants.extensionName,
        KHRNodeVisibility.extensionName,
        EXTMeshGPUInstancing.extensionName,
        EXTLightsImageBased.extensionName,
        // Metadata only; nothing to render.
        "KHR_xmp_json_ld"
    ])
}

/// A file requires extensions this load does not support.
public struct GLTFUnsupportedExtensionsError: LocalizedError, CustomStringConvertible {
    public var extensions: [String]

    public var description: String {
        "The file requires unsupported glTF extensions: \(extensions.joined(separator: ", "))"
    }

    public var errorDescription: String? { description }
}
