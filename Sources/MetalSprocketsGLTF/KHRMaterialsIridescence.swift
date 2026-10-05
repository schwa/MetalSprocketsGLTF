import Foundation
import SwiftGLTF

// KHR_materials_iridescence: a thin film over the surface whose interference tints reflections by angle.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_iridescence
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsIridescence: GLTFExtension {
    public static let extensionName = "KHR_materials_iridescence"

    public let iridescenceFactor: Float
    public let iridescenceTexture: TextureInfo?
    public let iridescenceIor: Float
    /// Film thickness in nanometres; the thickness texture's green channel blends from minimum to maximum.
    public let iridescenceThicknessMinimum: Float
    public let iridescenceThicknessMaximum: Float
    public let iridescenceThicknessTexture: TextureInfo?

    public enum CodingKeys: CodingKey {
        case iridescenceFactor
        case iridescenceTexture
        case iridescenceIor
        case iridescenceThicknessMinimum
        case iridescenceThicknessMaximum
        case iridescenceThicknessTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iridescenceFactor = try container.decodeIfPresent(Float.self, forKey: .iridescenceFactor) ?? 0
        iridescenceTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .iridescenceTexture)
        iridescenceIor = try container.decodeIfPresent(Float.self, forKey: .iridescenceIor) ?? 1.3
        iridescenceThicknessMinimum = try container.decodeIfPresent(Float.self, forKey: .iridescenceThicknessMinimum) ?? 100
        iridescenceThicknessMaximum = try container.decodeIfPresent(Float.self, forKey: .iridescenceThicknessMaximum) ?? 400
        iridescenceThicknessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .iridescenceThicknessTexture)
    }
}

public extension Material {
    var iridescence: KHRMaterialsIridescence? {
        try? extensionValue(KHRMaterialsIridescence.self)
    }
}
