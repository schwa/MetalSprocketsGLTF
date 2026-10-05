import Foundation
import SwiftGLTF

// KHR_materials_anisotropy: stretches specular highlights along a direction in the tangent plane.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_anisotropy
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsAnisotropy: GLTFExtension {
    public static let extensionName = "KHR_materials_anisotropy"

    public let anisotropyStrength: Float
    /// Radians, counter-clockwise from the tangent.
    public let anisotropyRotation: Float
    /// Direction in red and green (mapped from [0, 1] to [-1, 1]), strength in blue.
    public let anisotropyTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case anisotropyStrength
        case anisotropyRotation
        case anisotropyTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anisotropyStrength = try container.decodeIfPresent(Float.self, forKey: .anisotropyStrength) ?? 0
        anisotropyRotation = try container.decodeIfPresent(Float.self, forKey: .anisotropyRotation) ?? 0
        anisotropyTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .anisotropyTexture)
    }
}

public extension Material {
    var anisotropy: KHRMaterialsAnisotropy? {
        try? extensionValue(KHRMaterialsAnisotropy.self)
    }
}
