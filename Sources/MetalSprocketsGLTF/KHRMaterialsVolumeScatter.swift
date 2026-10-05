import Foundation
import SwiftGLTF

// KHR_materials_volume_scatter: light scattering inside a KHR_materials_volume, for skin, wax or frosted glass.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_volume_scatter
// Approximated without a scattering pass: the multiscatter color tints the diffuse light that comes back out, half on
// the lit side and half through to the far side. The multiscatter texture and anisotropy are not used.
// SwiftGLTF has no typed version of this extension yet.
public struct KHRMaterialsVolumeScatter: GLTFExtension {
    public static let extensionName = "KHR_materials_volume_scatter"

    /// The color the volume shows after many scattering events (its albedo).
    public let multiscatterColorFactor: SIMD3<Float>
    public let multiscatterColorTexture: TextureInfo?
    /// Direction of scattering, -1 (back) to 1 (forward); 0 is even.
    public let scatterAnisotropy: Float

    public enum CodingKeys: CodingKey {
        case multiscatterColorFactor
        case multiscatterColorTexture
        case scatterAnisotropy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        multiscatterColorFactor = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .multiscatterColorFactor) ?? .zero
        multiscatterColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .multiscatterColorTexture)
        scatterAnisotropy = try container.decodeIfPresent(Float.self, forKey: .scatterAnisotropy) ?? 0
    }
}

public extension Material {
    var volumeScatter: KHRMaterialsVolumeScatter? {
        try? extensionValue(KHRMaterialsVolumeScatter.self)
    }
}
