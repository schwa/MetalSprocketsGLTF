import Foundation
import SwiftGLTF

// KHR_materials_clearcoat: a clear, glossy layer over the base material, like car paint or varnish.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_clearcoat
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsClearcoat: GLTFExtension {
    public static let extensionName = "KHR_materials_clearcoat"

    public let clearcoatFactor: Float
    /// Factor in red.
    public let clearcoatTexture: TextureInfo?
    public let clearcoatRoughnessFactor: Float
    /// Roughness in green.
    public let clearcoatRoughnessTexture: TextureInfo?
    /// Its `normalScale` scales the normal like the base normal texture's.
    public let clearcoatNormalTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case clearcoatFactor
        case clearcoatTexture
        case clearcoatRoughnessFactor
        case clearcoatRoughnessTexture
        case clearcoatNormalTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clearcoatFactor = try container.decodeIfPresent(Float.self, forKey: .clearcoatFactor) ?? 0
        clearcoatTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .clearcoatTexture)
        clearcoatRoughnessFactor = try container.decodeIfPresent(Float.self, forKey: .clearcoatRoughnessFactor) ?? 0
        clearcoatRoughnessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .clearcoatRoughnessTexture)
        clearcoatNormalTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .clearcoatNormalTexture)
    }
}

public extension Material {
    var clearcoat: KHRMaterialsClearcoat? {
        try? extensionValue(KHRMaterialsClearcoat.self)
    }
}
