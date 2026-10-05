import Foundation
import SwiftGLTF

// KHR_materials_diffuse_transmission: light passing diffusely through thin surfaces such as leaves, paper or skin.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_diffuse_transmission
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsDiffuseTransmission: GLTFExtension {
    public static let extensionName = "KHR_materials_diffuse_transmission"

    public let diffuseTransmissionFactor: Float
    /// Factor in alpha.
    public let diffuseTransmissionTexture: TextureInfo?
    public let diffuseTransmissionColorFactor: SIMD3<Float>
    public let diffuseTransmissionColorTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case diffuseTransmissionFactor
        case diffuseTransmissionTexture
        case diffuseTransmissionColorFactor
        case diffuseTransmissionColorTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diffuseTransmissionFactor = try container.decodeIfPresent(Float.self, forKey: .diffuseTransmissionFactor) ?? 0
        diffuseTransmissionTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .diffuseTransmissionTexture)
        diffuseTransmissionColorFactor = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .diffuseTransmissionColorFactor) ?? [1, 1, 1]
        diffuseTransmissionColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .diffuseTransmissionColorTexture)
    }
}

public extension Material {
    var diffuseTransmission: KHRMaterialsDiffuseTransmission? {
        try? extensionValue(KHRMaterialsDiffuseTransmission.self)
    }
}
