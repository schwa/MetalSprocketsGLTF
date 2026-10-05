import Foundation
import SwiftGLTF

// KHR_materials_dispersion: refraction that splits light by wavelength, as in a prism or gemstone.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_dispersion
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsDispersion: GLTFExtension {
    public static let extensionName = "KHR_materials_dispersion"

    /// 20 / Abbe number; 0 means no dispersion.
    public let dispersion: Float

    public enum CodingKeys: CodingKey {
        case dispersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dispersion = try container.decodeIfPresent(Float.self, forKey: .dispersion) ?? 0
    }
}

public extension Material {
    var dispersion: Float {
        (try? extensionValue(KHRMaterialsDispersion.self))?.dispersion ?? 0
    }
}
