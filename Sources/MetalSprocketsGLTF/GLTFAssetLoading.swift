import Metal
import MetalSprockets
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

// The stages GLTFAsset is built from: load the file's resources (geometry through PBRGeometryBuilder), then flatten
// one scene into a PBRModel through PBRModelBuilder.

extension GLTFAsset.Resources {
    /// Loads everything that does not depend on the scene or variant: textures and materials, meshes, skins and
    /// animations, with warnings for what was skipped.
    static func load(container: Container, device: MTLDevice, options: GLTFLoadOptions = GLTFLoadOptions()) throws -> Self {
        let document = container.document
        var warnings: [String] = []

        let unsupported = Set(document.extensionsRequired).subtracting(options.supportedExtensions).sorted()
        if !unsupported.isEmpty {
            guard options.loadsUnsupportedRequiredExtensions else {
                throw GLTFUnsupportedExtensionsError(extensions: unsupported)
            }
            warnings.append("Required extensions not supported, loaded anyway: \(unsupported.joined(separator: ", "))")
        }

        let textures = GLTFTextureCache(container: container, device: device, decoders: options.textureDecoders)
        textures.preload(document.materials)
        let defaultMaterial = try PBRMaterial(material: nil, textures: textures)
        let materials = try document.materials.map { try PBRMaterial(material: $0, textures: textures) }

        // Every primitive's geometry goes into one set of shared buffers.
        var geometry = PBRGeometryBuilder(device: device)
        var meshPrimitiveIndices: [[Int]] = []
        var materialIndices: [Int: (material: Int, variants: [Int: Int])] = [:]
        for (meshIndex, mesh) in document.meshes.enumerated() {
            var indices: [Int] = []
            for (primitiveIndex, primitive) in mesh.primitives.enumerated() {
                let label = mesh.name ?? "mesh\(meshIndex)"
                do {
                    if let data = try GLTFGeometry.makePrimitive(primitive, container: container, defaultWeights: mesh.weights) {
                        let index = try geometry.add(attributes: data.attributes, indices: data.indices, primitiveType: data.primitiveType, morphTargets: data.morphTargets, label: "\(label)[\(primitiveIndex)]")
                        materialIndices[index] = (primitive.material?.index ?? -1, primitive.variantMaterials)
                        indices.append(index)
                    } else {
                        warnings.append("Skipped \(label)[\(primitiveIndex)]: unsupported mode \(primitive.mode)")
                    }
                } catch {
                    warnings.append("Skipped \(label)[\(primitiveIndex)]: \(error)")
                }
            }
            meshPrimitiveIndices.append(indices)
        }
        let primitives = try geometry.build()
        let meshes = meshPrimitiveIndices.map { $0.map { primitives[$0] } }
        let primitiveMaterials = Dictionary(uniqueKeysWithValues: materialIndices.map { (primitives[$0.key].key, $0.value) })
        let skins = try document.skins.map { skin in
            PBRModel.Skin(joints: skin.joints.map(\.index), inverseBindMatrices: try container.inverseBindMatrices(for: skin))
        }
        let animations = try document.animations.enumerated().map { index, animation in
            try GLTFAnimationClip(animation, index: index, container: container)
        }
        let unsupportedPointers = Set(animations.flatMap(\.unsupportedPointers)).sorted().map { "Animation pointer not supported: \($0)" }
        var nodeInstanceMatrices: [Int: [simd_float4x4]] = [:]
        for (index, node) in document.nodes.enumerated() where node.mesh != nil {
            nodeInstanceMatrices[index] = try container.instanceMatrices(for: node)
        }
        // EXT_lights_image_based: decode each light a scene uses; a broken one is skipped with a warning.
        var imageBasedLights: [Int: GLTFImageBasedLight] = [:]
        for index in Set(document.scenes.indices.compactMap { GLTFImageBasedLight.lightIndex(document: document, sceneIndex: $0) }).sorted() {
            do {
                imageBasedLights[index] = try GLTFImageBasedLight(container: container, index: index)
            } catch {
                warnings.append("Image-based light \(index) skipped: \(error)")
            }
        }
        var materialProperties: [String: GLTFAnimationPointer.MaterialProperty] = [:]
        for channel in animations.flatMap(\.channels) {
            if case let .material(_, property) = channel.target, materialProperties[property] == nil {
                materialProperties[property] = GLTFAnimationPointer.MaterialProperty(property)
            }
        }
        return Self(device: device, materials: materials, defaultMaterial: defaultMaterial, meshes: meshes, primitiveMaterials: primitiveMaterials, skins: skins, animations: animations, warnings: warnings + textures.warnings + unsupportedPointers, nodeInstanceMatrices: nodeInstanceMatrices, imageBasedLights: imageBasedLights, materialProperties: materialProperties)
    }
}

/// One scene of a document, flattened into a ``PBRModel``, with the glTF-only parts beside it: the sources of lights
/// and cameras (for posing), and the node hierarchy (for animation).
struct GLTFSceneContents {
    var model: PBRModel
    /// Every light of the scene, with its index in the document's lights and its node (for posing and animating).
    var lightSources: [GLTFAsset.LightSource] = []
    var cameraSources: [GLTFAsset.CameraSource] = []
    var hierarchy: GLTFNodeHierarchy

    /// Walks scene `sceneIndex` (or every root node when the document has no scenes). Hidden nodes
    /// (KHR_node_visibility) contribute no instances or lights, unless an animation can show them: then they are
    /// loaded and the rest pose hides them. `variant` picks KHR_materials_variants materials.
    /// Throws for out-of-range nodes and cyclic hierarchies.
    init(document: Document, resources: GLTFAsset.Resources, sceneIndex: Int, variant: Int?) throws {
        let animatesVisibility = resources.animations.contains { clip in
            clip.channels.contains { if case .visibility = $0.target { true } else { false } }
        }
        let roots: [Int]
        if sceneIndex < document.scenes.count {
            roots = document.scenes[sceneIndex].nodes.map(\.index)
        } else {
            let children = Set(document.nodes.flatMap { $0.children.map(\.index) })
            roots = document.nodes.indices.filter { !children.contains($0) }
        }
        let hierarchy = try GLTFNodeHierarchy(document: document, roots: roots)
        var builder = PBRModelBuilder(device: resources.device, restPose: hierarchy.pose(hierarchy.rest, morphWeights: hierarchy.restMorphWeights))
        builder.skins = resources.skins
        // Everything loaded stays resident, so other scenes and variants of the same file reuse it.
        builder.residentMaterials = resources.materials + [resources.defaultMaterial]
        builder.residentPrimitives = resources.meshes.flatMap(\.self)

        var lights: [PBRLight] = []
        var lightSources: [GLTFAsset.LightSource] = []
        var cameraSources: [GLTFAsset.CameraSource] = []
        // `visible` is false under a node hidden by KHR_node_visibility; its meshes and its descendants' are skipped.
        try hierarchy.walk(hierarchy.rest) { nodeIndex, world, visible in
            let node = document.nodes[nodeIndex]
            if visible || animatesVisibility, let meshIndex = node.mesh?.index, meshIndex < resources.meshes.count {
                for primitive in resources.meshes[meshIndex] {
                    let material = resources.material(for: primitive, variant: variant)
                    // Only primitives with joint data can be skinned; others ignore the node's skin.
                    let skinIndex = !primitive.isSkinned ? nil : node.skin.map(\.index).flatMap { document.skins.indices.contains($0) ? $0 : nil }
                    // EXT_mesh_gpu_instancing copies; skinned meshes follow their joints, so they are drawn once.
                    let instanceMatrices = skinIndex == nil ? resources.nodeInstanceMatrices[nodeIndex] ?? [matrix_identity_float4x4] : [matrix_identity_float4x4]
                    for instanceMatrix in instanceMatrices {
                        builder.addInstance(primitive, material: material, node: nodeIndex, instanceMatrix: instanceMatrix, worldMatrix: world * instanceMatrix, skin: skinIndex)
                    }
                }
            }
            if let camera = node.camera {
                cameraSources.append(GLTFAsset.CameraSource(camera: try camera.resolve(in: document), index: camera.index, node: nodeIndex, worldMatrix: world))
            }
            if let light = node.punctualLight(in: document), let lightIndex = (try? node.extensionValue(KHRLightsPunctualNodeRef.self))?.light {
                // Hidden lights do not shine at rest; with visibility animation they are kept, for poses to show.
                if visible {
                    lights.append(PBRLight(light, worldMatrix: world))
                }
                if visible || animatesVisibility {
                    lightSources.append(GLTFAsset.LightSource(light: light, index: lightIndex, node: nodeIndex))
                }
            }
        }
        builder.lights = lights
        self.model = try builder.build()
        self.lightSources = lightSources
        self.cameraSources = cameraSources
        self.hierarchy = hierarchy
    }
}
