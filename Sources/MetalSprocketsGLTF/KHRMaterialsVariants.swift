import Foundation
import SwiftGLTF

// KHR_materials_variants: named sets of alternative materials, such as colorways of one product.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_variants
// SwiftGLTF has no typed version of this extension yet.

/// The document-level list of variants.
public struct KHRMaterialsVariants: GLTFExtension {
    public static let extensionName = "KHR_materials_variants"

    public struct Variant: Decodable, Sendable {
        public let name: String
    }

    public let variants: [Variant]
}

/// A primitive's material for each variant that changes it.
public struct KHRMaterialsVariantsMappings: GLTFExtension {
    public static let extensionName = "KHR_materials_variants"

    public struct Mapping: Decodable, Sendable {
        public let material: Int
        public let variants: [Int]
    }

    public let mappings: [Mapping]
}

public extension Document {
    var materialVariantNames: [String] {
        (try? extensionValue(KHRMaterialsVariants.self))?.variants.map(\.name) ?? []
    }
}

extension Mesh.Primitive {
    /// The material index for each variant index that maps one.
    var variantMaterials: [Int: Int] {
        var materials: [Int: Int] = [:]
        for mapping in (try? extensionValue(KHRMaterialsVariantsMappings.self))?.mappings ?? [] {
            for variant in mapping.variants {
                materials[variant] = mapping.material
            }
        }
        return materials
    }
}
