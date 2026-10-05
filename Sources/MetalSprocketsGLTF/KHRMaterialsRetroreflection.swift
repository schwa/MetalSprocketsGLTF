import Foundation
import SwiftGLTF

// KHR_materials_retroreflection: light returned toward its source, as on road signs and safety tape.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_retroreflection
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsRetroreflection: GLTFExtension {
    public static let extensionName = "KHR_materials_retroreflection"

    /// Blend from the regular (0) to the retroreflective (1) metal and dielectric BRDFs.
    public let retroreflectionFactor: Float
    /// Multiplies the factor, from its red channel.
    public let retroreflectionTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case retroreflectionFactor
        case retroreflectionTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retroreflectionFactor = try container.decodeIfPresent(Float.self, forKey: .retroreflectionFactor) ?? 0
        retroreflectionTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .retroreflectionTexture)
    }
}

public extension Material {
    var retroreflection: KHRMaterialsRetroreflection? {
        try? extensionValue(KHRMaterialsRetroreflection.self)
    }
}
