import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

/// Everything this package does with one material extension (or with core glTF materials): the uniforms it sets, with
/// the spec defaults when a material lacks it, its texture slots, and the factors KHR_animation_pointer may animate.
///
/// ``all`` is the single list. Material building, ``GLTFMaterialTextureSlot/all``, the animatable material factors and
/// ``GLTFAsset/builtInExtensions`` come from it, so adding an extension means adding one entry here.
// Immutable; @unchecked only because the texture slots hold key paths, which are not Sendable.
struct GLTFMaterialFeature: @unchecked Sendable {
    typealias Factor = GLTFAnimationPointer.MaterialProperty.Factor

    /// Nil for core glTF.
    var extensionName: String?
    /// Writes this feature's uniforms for `material` (nil for the default material).
    var uniforms: @Sendable (Material?, inout PBRMaterialUniforms) -> Void
    var textureSlots: [GLTFMaterialTextureSlot] = []
    /// By path below `/materials/N/`.
    var animatableFactors: [String: Factor] = [:]

    /// `factors` keyed by their name below `/materials/N/extensions/<extensionName>/`.
    init(extensionName: String?, uniforms: @escaping @Sendable (Material?, inout PBRMaterialUniforms) -> Void, textureSlots: [GLTFMaterialTextureSlot] = [], factors: [String: Factor] = [:]) {
        self.extensionName = extensionName
        self.uniforms = uniforms
        self.textureSlots = textureSlots
        let prefix = extensionName.map { "extensions/\($0)/" } ?? ""
        animatableFactors = Dictionary(uniqueKeysWithValues: factors.map { (prefix + $0.key, $0.value) })
    }

    /// Writes every feature's uniforms, in order, for `material`.
    static func uniforms(for material: Material?) -> PBRMaterialUniforms {
        var uniforms = PBRMaterialUniforms()
        for feature in all {
            feature.uniforms(material, &uniforms)
        }
        return uniforms
    }

    static let animatableFactors: [String: Factor] = all.reduce(into: [:]) { $0.merge($1.animatableFactors) { first, _ in first } }

    static let extensionNames: Set<String> = Set(all.compactMap(\.extensionName))

    static func scalar(_ keyPath: WritableKeyPath<PBRMaterialUniforms, Float> & Sendable) -> Factor {
        Factor(get: { [$0[keyPath: keyPath]] }, set: { if let value = $1.first { $0[keyPath: keyPath] = value } })
    }

    static func vector3(_ keyPath: WritableKeyPath<PBRMaterialUniforms, SIMD3<Float>> & Sendable) -> Factor {
        Factor(get: { let value = $0[keyPath: keyPath]; return [value.x, value.y, value.z] }, set: { if $1.count == 3 { $0[keyPath: keyPath] = SIMD3($1[0], $1[1], $1[2]) } })
    }

    static func vector4(_ keyPath: WritableKeyPath<PBRMaterialUniforms, SIMD4<Float>> & Sendable) -> Factor {
        Factor(get: { let value = $0[keyPath: keyPath]; return [value.x, value.y, value.z, value.w] }, set: { if $1.count == 4 { $0[keyPath: keyPath] = SIMD4($1[0], $1[1], $1[2], $1[3]) } })
    }

    /// In application order: specular-glossiness comes last because it overrides the metallic-roughness and specular
    /// uniforms.
    static let all: [Self] = [
        Self(extensionName: nil, uniforms: { material, uniforms in
            let pbr = material?.pbrMetallicRoughness
            uniforms.baseColorFactor = pbr?.baseColorFactor ?? [1, 1, 1, 1]
            uniforms.metallicFactor = pbr?.metallicFactor ?? 1
            uniforms.roughnessFactor = pbr?.roughnessFactor ?? 1
            uniforms.emissiveFactor = material?.emissiveFactor ?? .zero
            uniforms.normalScale = material?.normalTexture?.normalScale ?? 1
            uniforms.occlusionStrength = material?.occlusionTexture?.occlusionStrength ?? 1
            uniforms.alphaCutoff = material?.alphaCutoff ?? 0.5
            switch material?.alphaMode ?? .OPAQUE {
            case .OPAQUE: uniforms.alphaMode = .opaque
            case .MASK: uniforms.alphaMode = .mask
            case .BLEND: uniforms.alphaMode = .blend
            }
        }, textureSlots: [
            GLTFMaterialTextureSlot(index: kPBRTextureBaseColor, uniform: \.baseColor, sRGB: true, pointerPaths: [GLTFMaterialTextureSlot.baseColorPath, GLTFMaterialTextureSlot.diffusePath]) { material in
                if let specularGlossiness = material.specularGlossiness {
                    return specularGlossiness.diffuseTexture.map { (GLTFMaterialTextureSlot.diffusePath, $0) }
                }
                return material.pbrMetallicRoughness?.baseColorTexture.map { (GLTFMaterialTextureSlot.baseColorPath, $0) }
            },
            GLTFMaterialTextureSlot(index: kPBRTextureMetallicRoughness, uniform: \.metallicRoughness, sRGB: false, pointerPaths: ["pbrMetallicRoughness/metallicRoughnessTexture"]) { material in
                guard material.specularGlossiness == nil else { return nil }
                return material.pbrMetallicRoughness?.metallicRoughnessTexture.map { ("pbrMetallicRoughness/metallicRoughnessTexture", $0) }
            },
            .single(kPBRTextureNormal, \.normal, sRGB: false, path: "normalTexture") { $0.normalTexture },
            .single(kPBRTextureOcclusion, \.occlusion, sRGB: false, path: "occlusionTexture") { $0.occlusionTexture },
            .single(kPBRTextureEmissive, \.emissive, sRGB: true, path: "emissiveTexture") { $0.emissiveTexture }
        ], factors: [
            "pbrMetallicRoughness/baseColorFactor": vector4(\.baseColorFactor),
            "pbrMetallicRoughness/metallicFactor": scalar(\.metallicFactor),
            "pbrMetallicRoughness/roughnessFactor": scalar(\.roughnessFactor),
            "emissiveFactor": vector3(\.emissiveFactor),
            "alphaCutoff": scalar(\.alphaCutoff),
            "normalTexture/scale": scalar(\.normalScale),
            "occlusionTexture/strength": scalar(\.occlusionStrength)
        ]),
        Self(extensionName: KHRMaterialsUnlit.extensionName) { material, uniforms in
            uniforms.unlit = (material?.isUnlit ?? false) ? 1 : 0
        },
        Self(extensionName: KHRMaterialsEmissiveStrength.extensionName, uniforms: { material, uniforms in
            uniforms.emissiveStrength = material?.emissiveStrength ?? 1
        }, factors: ["emissiveStrength": scalar(\.emissiveStrength)]),
        Self(extensionName: KHRMaterialsIOR.extensionName, uniforms: { material, uniforms in
            uniforms.ior = material?.ior ?? 1.5
        }, factors: ["ior": scalar(\.ior)]),
        // Absent: no transmission.
        Self(extensionName: KHRMaterialsTransmission.extensionName, uniforms: { material, uniforms in
            uniforms.transmissionFactor = material?.transmission?.transmissionFactor ?? 0
        }, textureSlots: [
            .single(kPBRTextureTransmission, \.transmission, sRGB: false, path: "extensions/KHR_materials_transmission/transmissionTexture") { $0.transmission?.transmissionTexture }
        ], factors: ["transmissionFactor": scalar(\.transmissionFactor)]),
        // Absent: a thin, non-absorbing volume.
        Self(extensionName: KHRMaterialsVolume.extensionName, uniforms: { material, uniforms in
            let volume = material?.volume
            uniforms.thicknessFactor = volume?.thicknessFactor ?? 0
            uniforms.attenuationDistance = volume?.attenuationDistance ?? .infinity
            uniforms.attenuationColor = volume?.attenuationColor ?? [1, 1, 1]
        }, textureSlots: [
            .single(kPBRTextureThickness, \.thickness, sRGB: false, path: "extensions/KHR_materials_volume/thicknessTexture") { $0.volume?.thicknessTexture }
        ], factors: [
            "thicknessFactor": scalar(\.thicknessFactor),
            "attenuationDistance": scalar(\.attenuationDistance),
            "attenuationColor": vector3(\.attenuationColor)
        ]),
        // Absent: full specular.
        Self(extensionName: KHRMaterialsSpecular.extensionName, uniforms: { material, uniforms in
            let specular = material?.specular
            uniforms.specularFactor = specular?.specularFactor ?? 1
            uniforms.specularColorFactor = specular?.specularColorFactor ?? [1, 1, 1]
        }, textureSlots: [
            GLTFMaterialTextureSlot(index: kPBRTextureSpecular, uniform: \.specular, sRGB: false, pointerPaths: ["extensions/KHR_materials_specular/specularTexture"]) { material in
                guard material.specularGlossiness == nil else { return nil }
                return material.specular?.specularTexture.map { ("extensions/KHR_materials_specular/specularTexture", $0) }
            },
            GLTFMaterialTextureSlot(index: kPBRTextureSpecularColor, uniform: \.specularColor, sRGB: true, pointerPaths: ["extensions/KHR_materials_specular/specularColorTexture", GLTFMaterialTextureSlot.specularGlossinessPath]) { material in
                if let specularGlossiness = material.specularGlossiness {
                    return specularGlossiness.specularGlossinessTexture.map { (GLTFMaterialTextureSlot.specularGlossinessPath, $0) }
                }
                return material.specular?.specularColorTexture.map { ("extensions/KHR_materials_specular/specularColorTexture", $0) }
            }
        ], factors: [
            "specularFactor": scalar(\.specularFactor),
            "specularColorFactor": vector3(\.specularColorFactor)
        ]),
        Self(extensionName: KHRMaterialsIridescence.extensionName, uniforms: { material, uniforms in
            let iridescence = material?.iridescence
            uniforms.iridescenceFactor = iridescence?.iridescenceFactor ?? 0
            uniforms.iridescenceIor = iridescence?.iridescenceIor ?? 1.3
            uniforms.iridescenceThicknessMinimum = iridescence?.iridescenceThicknessMinimum ?? 100
            uniforms.iridescenceThicknessMaximum = iridescence?.iridescenceThicknessMaximum ?? 400
        }, textureSlots: [
            .single(kPBRTextureIridescence, \.iridescence, sRGB: false, path: "extensions/KHR_materials_iridescence/iridescenceTexture") { $0.iridescence?.iridescenceTexture },
            .single(kPBRTextureIridescenceThickness, \.iridescenceThickness, sRGB: false, path: "extensions/KHR_materials_iridescence/iridescenceThicknessTexture") { $0.iridescence?.iridescenceThicknessTexture }
        ], factors: [
            "iridescenceFactor": scalar(\.iridescenceFactor),
            "iridescenceIor": scalar(\.iridescenceIor),
            "iridescenceThicknessMinimum": scalar(\.iridescenceThicknessMinimum),
            "iridescenceThicknessMaximum": scalar(\.iridescenceThicknessMaximum)
        ]),
        Self(extensionName: KHRMaterialsAnisotropy.extensionName, uniforms: { material, uniforms in
            let anisotropy = material?.anisotropy
            uniforms.anisotropyStrength = anisotropy?.anisotropyStrength ?? 0
            uniforms.anisotropyRotation = anisotropy?.anisotropyRotation ?? 0
        }, textureSlots: [
            .single(kPBRTextureAnisotropy, \.anisotropy, sRGB: false, path: "extensions/KHR_materials_anisotropy/anisotropyTexture") { $0.anisotropy?.anisotropyTexture }
        ], factors: [
            "anisotropyStrength": scalar(\.anisotropyStrength),
            "anisotropyRotation": scalar(\.anisotropyRotation)
        ]),
        Self(extensionName: KHRMaterialsSheen.extensionName, uniforms: { material, uniforms in
            let sheen = material?.sheen
            uniforms.sheenColorFactor = sheen?.sheenColorFactor ?? .zero
            uniforms.sheenRoughnessFactor = sheen?.sheenRoughnessFactor ?? 0
        }, textureSlots: [
            .single(kPBRTextureSheenColor, \.sheenColor, sRGB: true, path: "extensions/KHR_materials_sheen/sheenColorTexture") { $0.sheen?.sheenColorTexture },
            .single(kPBRTextureSheenRoughness, \.sheenRoughness, sRGB: false, path: "extensions/KHR_materials_sheen/sheenRoughnessTexture") { $0.sheen?.sheenRoughnessTexture }
        ], factors: [
            "sheenColorFactor": vector3(\.sheenColorFactor),
            "sheenRoughnessFactor": scalar(\.sheenRoughnessFactor)
        ]),
        Self(extensionName: KHRMaterialsDispersion.extensionName, uniforms: { material, uniforms in
            uniforms.dispersion = material?.dispersion ?? 0
        }, factors: ["dispersion": scalar(\.dispersion)]),
        Self(extensionName: KHRMaterialsRetroreflection.extensionName, uniforms: { material, uniforms in
            uniforms.retroreflectionFactor = material?.retroreflection?.retroreflectionFactor ?? 0
        }, textureSlots: [
            .single(kPBRTextureRetroreflection, \.retroreflection, sRGB: false, path: "extensions/KHR_materials_retroreflection/retroreflectionTexture") { $0.retroreflection?.retroreflectionTexture }
        ], factors: ["retroreflectionFactor": scalar(\.retroreflectionFactor)]),
        Self(extensionName: KHRMaterialsVolumeScatter.extensionName) { material, uniforms in
            if let volumeScatter = material?.volumeScatter {
                uniforms.volumeScatter = 1
                uniforms.multiscatterColorFactor = volumeScatter.multiscatterColorFactor
            }
        },
        Self(extensionName: KHRMaterialsDiffuseTransmission.extensionName, uniforms: { material, uniforms in
            let diffuseTransmission = material?.diffuseTransmission
            uniforms.diffuseTransmissionFactor = diffuseTransmission?.diffuseTransmissionFactor ?? 0
            uniforms.diffuseTransmissionColorFactor = diffuseTransmission?.diffuseTransmissionColorFactor ?? [1, 1, 1]
        }, textureSlots: [
            .single(kPBRTextureDiffuseTransmission, \.diffuseTransmission, sRGB: false, path: "extensions/KHR_materials_diffuse_transmission/diffuseTransmissionTexture") { $0.diffuseTransmission?.diffuseTransmissionTexture },
            .single(kPBRTextureDiffuseTransmissionColor, \.diffuseTransmissionColor, sRGB: true, path: "extensions/KHR_materials_diffuse_transmission/diffuseTransmissionColorTexture") { $0.diffuseTransmission?.diffuseTransmissionColorTexture }
        ], factors: [
            "diffuseTransmissionFactor": scalar(\.diffuseTransmissionFactor),
            "diffuseTransmissionColorFactor": vector3(\.diffuseTransmissionColorFactor)
        ]),
        Self(extensionName: KHRMaterialsClearcoat.extensionName, uniforms: { material, uniforms in
            let clearcoat = material?.clearcoat
            uniforms.clearcoatFactor = clearcoat?.clearcoatFactor ?? 0
            uniforms.clearcoatRoughnessFactor = clearcoat?.clearcoatRoughnessFactor ?? 0
            uniforms.clearcoatNormalScale = clearcoat?.clearcoatNormalTexture?.normalScale ?? 1
        }, textureSlots: [
            .single(kPBRTextureClearcoat, \.clearcoat, sRGB: false, path: "extensions/KHR_materials_clearcoat/clearcoatTexture") { $0.clearcoat?.clearcoatTexture },
            .single(kPBRTextureClearcoatRoughness, \.clearcoatRoughness, sRGB: false, path: "extensions/KHR_materials_clearcoat/clearcoatRoughnessTexture") { $0.clearcoat?.clearcoatRoughnessTexture },
            .single(kPBRTextureClearcoatNormal, \.clearcoatNormal, sRGB: false, path: "extensions/KHR_materials_clearcoat/clearcoatNormalTexture") { $0.clearcoat?.clearcoatNormalTexture }
        ], factors: [
            "clearcoatFactor": scalar(\.clearcoatFactor),
            "clearcoatRoughnessFactor": scalar(\.clearcoatRoughnessFactor)
        ]),
        // Specular-glossiness replaces the metallic-roughness inputs: diffuse becomes the base color with metallic 0,
        // specular becomes the specular color relative to the default dielectric F0 of 0.04, and the shader derives
        // roughness from glossiness (the specular texture's alpha). Its textures are chosen by the core and specular
        // slots above.
        Self(extensionName: KHRMaterialsPBRSpecularGlossiness.extensionName) { material, uniforms in
            guard let specularGlossiness = material?.specularGlossiness else { return }
            uniforms.specularGlossiness = 1
            uniforms.baseColorFactor = specularGlossiness.diffuseFactor
            uniforms.metallicFactor = 0
            uniforms.roughnessFactor = 1
            uniforms.glossinessFactor = specularGlossiness.glossinessFactor
            uniforms.specularFactor = 1
            uniforms.specularColorFactor = specularGlossiness.specularFactor / 0.04
        }
    ]
}
