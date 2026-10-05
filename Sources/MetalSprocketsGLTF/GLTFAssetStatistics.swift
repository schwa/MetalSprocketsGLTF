import Metal
import SwiftGLTF

/// Sizes and counts describing a loaded asset, for display and comparison.
public struct GLTFAssetStatistics: Sendable {
    public var generator: String?
    public var version: String
    public var extensionsUsed: [String]
    public var extensionsRequired: [String]
    /// Paths of external buffers and images relative to the .gltf (data URIs excluded), for its size on disk.
    public var externalPaths: [String]

    public var nodes: Int
    public var meshes: Int
    /// Distinct primitives loaded (each mesh's primitives once).
    public var primitives: Int
    /// Primitives placed in the scene, counting every node and EXT_mesh_gpu_instancing copy.
    public var instances: Int
    /// Instanced draw batches before merging.
    public var batches: Int
    /// Triangles, lines and points drawn per frame (all instances).
    public var triangles: Int
    public var lines: Int
    public var points: Int
    /// Vertices stored, over distinct primitives.
    public var vertices: Int

    public var materials: Int
    /// Distinct textures, without placeholders.
    public var textures: Int
    /// GPU memory of those textures, in bytes.
    public var textureBytes: Int
    public var largestTexture: (width: Int, height: Int)?

    public var animations: Int
    public var skins: Int
    public var joints: Int
    /// Morph targets over distinct primitives.
    public var morphTargets: Int
    public var lights: Int
    public var cameras: Int
    public var scenes: Int
    public var materialVariants: Int
}

public extension GLTFAsset {
    var statistics: GLTFAssetStatistics {
        let document = container.document
        let instances = opaqueInstances + blendedInstances

        var triangles = 0
        var lines = 0
        var points = 0
        for instance in instances {
            let indexCount = instance.primitive.indexCount
            switch instance.primitive.primitiveType {
            case .triangle: triangles += indexCount / 3
            case .line: lines += indexCount / 2
            case .point: points += indexCount
            default: break
            }
        }

        let primitives = meshes.flatMap(\.self)
        var textures: [ObjectIdentifier: MTLTexture] = [:]
        for binding in materials.flatMap(\.textureBindings) where binding.texture.width > 1 || binding.texture.height > 1 {
            textures[ObjectIdentifier(binding.texture)] = binding.texture
        }
        let largest = textures.values.max { $0.width * $0.height < $1.width * $1.height }

        return GLTFAssetStatistics(
            generator: document.asset.generator,
            version: document.asset.version.rawValue,
            extensionsUsed: document.extensionsUsed.sorted(),
            extensionsRequired: document.extensionsRequired.sorted(),
            externalPaths: (document.buffers.compactMap(\.uri) + document.images.compactMap(\.uri)).filter { !$0.string.hasPrefix("data:") }.map(\.relativePath),
            nodes: document.nodes.count,
            meshes: document.meshes.count,
            primitives: primitives.count,
            instances: instances.count,
            batches: opaqueBatches.count + blendedBatches.count,
            triangles: triangles,
            lines: lines,
            points: points,
            vertices: primitives.reduce(0) { $0 + $1.vertexCount },
            materials: document.materials.count,
            textures: textures.count,
            textureBytes: textures.values.reduce(0) { $0 + $1.allocatedSize },
            largestTexture: largest.map { ($0.width, $0.height) },
            animations: animations.count,
            skins: skins.count,
            joints: skins.reduce(0) { $0 + $1.joints.count },
            morphTargets: primitives.reduce(0) { $0 + $1.morphTargetCount },
            lights: lights.count,
            cameras: cameras.count,
            scenes: sceneCount,
            materialVariants: variantNames.count
        )
    }
}
