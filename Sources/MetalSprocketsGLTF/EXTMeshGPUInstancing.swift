import Foundation
import GeometryLite3D
import simd
import SwiftGLTF

// EXT_mesh_gpu_instancing: draws a node's mesh many times, each copy placed by its own translation, rotation and scale
// relative to the node.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Vendor/EXT_mesh_gpu_instancing
public struct EXTMeshGPUInstancing: GLTFExtension {
    public static let extensionName = "EXT_mesh_gpu_instancing"

    /// Accessor indices by attribute name: TRANSLATION, ROTATION, SCALE (and custom `_` attributes, ignored).
    public let attributes: [String: Int]

    public enum CodingKeys: CodingKey {
        case attributes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attributes = try container.decodeIfPresent([String: Int].self, forKey: .attributes) ?? [:]
    }
}

extension Container {
    /// The node-relative matrix of each instance of `node`'s mesh, or nil when the node does not use
    /// EXT_mesh_gpu_instancing.
    func instanceMatrices(for node: Node) throws -> [simd_float4x4]? {
        guard let instancing = try? node.extensionValue(EXTMeshGPUInstancing.self) else {
            return nil
        }
        func values(_ name: String, components: Int) throws -> [Float]? {
            guard let index = instancing.attributes[name] else { return nil }
            guard document.accessors.indices.contains(index) else {
                throw GLTFError.invalidDocument("EXT_mesh_gpu_instancing \(name) accessor \(index) is out of range")
            }
            let accessor = document.accessors[index]
            guard accessor.type.componentCount == components else {
                throw GLTFError.invalidDocument("EXT_mesh_gpu_instancing \(name) must have \(components) components")
            }
            return try floatComponents(for: accessor)
        }
        let translations = try values("TRANSLATION", components: 3)
        let rotations = try values("ROTATION", components: 4)
        let scales = try values("SCALE", components: 3)
        let counts = [translations.map { $0.count / 3 }, rotations.map { $0.count / 4 }, scales.map { $0.count / 3 }].compactMap(\.self)
        guard let count = counts.first else {
            return nil
        }
        guard counts.allSatisfy({ $0 == count }) else {
            throw GLTFError.invalidDocument("EXT_mesh_gpu_instancing attributes have different counts")
        }
        return (0 ..< count).map { index in
            let translation = translations.map { SIMD3($0[index * 3], $0[index * 3 + 1], $0[index * 3 + 2]) } ?? .zero
            let rotation = rotations.map { simd_quatf(ix: $0[index * 4], iy: $0[index * 4 + 1], iz: $0[index * 4 + 2], r: $0[index * 4 + 3]) } ?? .identity
            let scale = scales.map { SIMD3($0[index * 3], $0[index * 3 + 1], $0[index * 3 + 2]) } ?? SIMD3<Float>(repeating: 1)
            return Transform3D(translation: translation, rotation: simd_normalize(rotation), scale: scale).matrix
        }
    }
}
