import Foundation
import SwiftGLTF

// KHR_materials_sheen: a soft back-scattering layer for cloth such as velvet.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_sheen
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsSheen: GLTFExtension {
    public static let extensionName = "KHR_materials_sheen"

    public let sheenColorFactor: SIMD3<Float>
    public let sheenColorTexture: TextureInfo?
    public let sheenRoughnessFactor: Float
    /// Roughness in alpha.
    public let sheenRoughnessTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case sheenColorFactor
        case sheenColorTexture
        case sheenRoughnessFactor
        case sheenRoughnessTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sheenColorFactor = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .sheenColorFactor) ?? .zero
        sheenColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .sheenColorTexture)
        sheenRoughnessFactor = try container.decodeIfPresent(Float.self, forKey: .sheenRoughnessFactor) ?? 0
        sheenRoughnessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .sheenRoughnessTexture)
    }
}

public extension Material {
    var sheen: KHRMaterialsSheen? {
        try? extensionValue(KHRMaterialsSheen.self)
    }
}
