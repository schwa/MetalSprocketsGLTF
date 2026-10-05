import Foundation
import SwiftGLTF

// KHR_materials_pbrSpecularGlossiness: the archived specular-glossiness material model, still found in older files.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Archived/KHR_materials_pbrSpecularGlossiness
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsPBRSpecularGlossiness: GLTFExtension {
    public static let extensionName = "KHR_materials_pbrSpecularGlossiness"

    public let diffuseFactor: SIMD4<Float>
    /// sRGB color with alpha.
    public let diffuseTexture: TextureInfo?
    public let specularFactor: SIMD3<Float>
    public let glossinessFactor: Float
    /// sRGB specular color in RGB, glossiness in alpha.
    public let specularGlossinessTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case diffuseFactor
        case diffuseTexture
        case specularFactor
        case glossinessFactor
        case specularGlossinessTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diffuseFactor = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .diffuseFactor) ?? [1, 1, 1, 1]
        diffuseTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .diffuseTexture)
        specularFactor = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .specularFactor) ?? [1, 1, 1]
        glossinessFactor = try container.decodeIfPresent(Float.self, forKey: .glossinessFactor) ?? 1
        specularGlossinessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .specularGlossinessTexture)
    }
}

public extension Material {
    var specularGlossiness: KHRMaterialsPBRSpecularGlossiness? {
        try? extensionValue(KHRMaterialsPBRSpecularGlossiness.self)
    }
}
