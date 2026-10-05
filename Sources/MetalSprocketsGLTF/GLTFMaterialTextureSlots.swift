import MetalSprocketsPBRShaders
import SwiftGLTF

/// One material texture: where the shader finds it, which uniform slot describes it, and where a glTF material keeps it.
///
/// ``GLTFMaterialTextureSlot/all`` is the list of material textures, gathered from ``GLTFMaterialFeature/all``.
/// Binding, the argument buffer's order, texture preloading and KHR_animation_pointer texture paths all come from it.
// Immutable; @unchecked only because key paths are not Sendable.
struct GLTFMaterialTextureSlot: @unchecked Sendable {
    /// Index into `PBRMaterialResources` (the shader's `PBRMaterialTextureIndex`).
    var index: PBRMaterialTextureIndex
    var uniform: WritableKeyPath<PBRMaterialUniforms, PBRTextureSlot>
    var sRGB: Bool
    /// Every path below `/materials/N/` that can supply this texture (and that animation pointers may target).
    var pointerPaths: [String]
    /// The texture a material uses for this slot, with its path, or nil when it has none.
    var source: @Sendable (Material) -> (path: String, info: TextureInfo)?

    static let baseColorPath = "pbrMetallicRoughness/baseColorTexture"
    static let diffusePath = "extensions/KHR_materials_pbrSpecularGlossiness/diffuseTexture"
    static let specularGlossinessPath = "extensions/KHR_materials_pbrSpecularGlossiness/specularGlossinessTexture"

    /// A slot read from one place, unaffected by specular-glossiness.
    static func single(_ index: PBRMaterialTextureIndex, _ uniform: WritableKeyPath<PBRMaterialUniforms, PBRTextureSlot>, sRGB: Bool, path: String, _ info: @escaping @Sendable (Material) -> TextureInfo?) -> Self {
        Self(index: index, uniform: uniform, sRGB: sRGB, pointerPaths: [path]) { material in
            info(material).map { (path, $0) }
        }
    }

    /// Every feature's slots, in `PBRMaterialTextureIndex` order.
    static let all: [Self] = GLTFMaterialFeature.all.flatMap(\.textureSlots).sorted { $0.index.rawValue < $1.index.rawValue }

    /// The slot each animation-pointer texture path below `/materials/N/` refers to.
    static let byPointerPath: [String: Self] = Dictionary(uniqueKeysWithValues: all.flatMap { slot in slot.pointerPaths.map { ($0, slot) } })
}
