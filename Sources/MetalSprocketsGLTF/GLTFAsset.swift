import Foundation
import Metal
import MetalKit
import MetalSprockets
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import simd
import SwiftGLTF
import SwiftMesh
import Synchronization

/// A glTF file loaded for rendering: one scene as a ``PBRModel``, plus what only glTF has (animations, cameras,
/// material variants, other scenes). Load once, render many times with ``GLTFRenderer``.
///
/// Meshes, textures and samplers are shared between every node that references them.
/// Immutable after init, so it can be loaded on a background task and handed to the render thread.
public final class GLTFAsset: @unchecked Sendable {
    public typealias Primitive = PBRModel.Primitive
    public typealias Skin = PBRModel.Skin
    public typealias Instance = PBRModel.Instance
    public typealias Batch = PBRModel.Batch

    public let container: Container
    /// The scene, ready to draw.
    public let model: PBRModel
    public let materials: [PBRMaterial]
    public let meshes: [[Primitive]]
    /// KHR_materials_variants names; load with `variant:` set to an index to use one.
    public let variantNames: [String]
    /// Animation clips; sample one with ``pose(animation:time:)``.
    public let animations: [GLTFAnimationClip]
    /// The scene's node hierarchy at rest, used to compute animated poses.
    let hierarchy: GLTFNodeHierarchy
    /// The scene's cameras at rest.
    public let cameras: [(camera: SwiftGLTF.Camera, worldMatrix: simd_float4x4)]
    /// A light of the scene: its definition, its index in the document's lights (for KHR_animation_pointer), and the
    /// node placing it.
    struct LightSource: Sendable {
        var light: SwiftGLTF.Light
        var index: Int
        var node: Int
    }

    /// A camera of the scene: its definition, its index in the document's cameras (for KHR_animation_pointer), the
    /// node placing it, and its world matrix at rest.
    struct CameraSource: Sendable {
        var camera: SwiftGLTF.Camera
        var index: Int
        var node: Int
        var worldMatrix: simd_float4x4
    }

    /// Every light and camera of the scene, for posing. Includes lights hidden at rest that animation can show.
    let lightSources: [LightSource]
    let cameraSources: [CameraSource]
    public let warnings: [String]

    public var opaqueInstances: [Instance] { model.opaqueInstances }
    public var blendedInstances: [Instance] { model.blendedInstances }
    /// Opaque and masked instances grouped for instanced drawing.
    public var opaqueBatches: [Batch] { model.opaqueBatches }
    /// One batch per blended instance, so they can be sorted back to front.
    public var blendedBatches: [Batch] { model.blendedBatches }
    /// Whether any material uses KHR_materials_transmission, i.e. whether a ``GLTFTransmissionPass`` is worth running.
    public var hasTransmission: Bool { model.hasTransmission }
    public var lights: [PBRLight] { model.lights }
    public var skins: [Skin] { model.skins }
    public var bounds: PBRBounds { model.bounds }
    /// See ``PBRModel/resourceCollection``.
    public var resourceCollection: ResourceCollection { model.resourceCollection }
    /// The scene at rest.
    public var restPose: PBRPose { model.restPose }

    public static var vertexDescriptor: MTLVertexDescriptor { PBRModel.vertexDescriptor }
    public static var skinBufferIndex: Int { PBRModel.skinBufferIndex }
    public static var skinnedVertexDescriptor: MTLVertexDescriptor { PBRModel.skinnedVertexDescriptor }

    /// `variant` selects a KHR_materials_variants variant by index into ``variantNames``; nil uses the default materials.
    /// `options` registers extension support from other targets, such as texture decoders.
    public convenience init(url: URL, device: MTLDevice? = nil, sceneIndex: Int? = nil, variant: Int? = nil, options: GLTFLoadOptions = GLTFLoadOptions()) throws {
        try self.init(container: Container(url: url, bufferViewDecoders: options.bufferViewDecoders), device: device, sceneIndex: sceneIndex, variant: variant, options: options)
    }

    /// Everything loaded from the file that does not depend on the scene or variant, shared by ``scene(_:)``.
    struct Resources {
        var device: MTLDevice
        var materials: [PBRMaterial]
        var defaultMaterial: PBRMaterial
        var meshes: [[Primitive]]
        /// Each primitive's glTF material index (-1 for none) and KHR_materials_variants material indices, by variant.
        var primitiveMaterials: [Primitive.Key: (material: Int, variants: [Int: Int])]
        var skins: [Skin]
        var animations: [GLTFAnimationClip]
        var warnings: [String]
        /// EXT_mesh_gpu_instancing: node-relative matrices of each copy of a node's mesh, by node index.
        var nodeInstanceMatrices: [Int: [simd_float4x4]] = [:]
        /// EXT_lights_image_based lights that scenes use, by light index.
        var imageBasedLights: [Int: GLTFImageBasedLight] = [:]
        /// Every material property the animations target, parsed, so posing does not parse pointer strings.
        var materialProperties: [String: GLTFAnimationPointer.MaterialProperty] = [:]
        /// Environments built from `imageBasedLights`, on first use.
        var environments = EnvironmentCache()

        /// The material `primitive` is drawn with in KHR_materials_variants variant `variant` (nil for the default).
        func material(for primitive: Primitive, variant: Int?) -> PBRMaterial {
            let indices = primitiveMaterials[primitive.key]
            let materialIndex = variant.flatMap { indices?.variants[$0] } ?? indices?.material ?? -1
            return materials.indices.contains(materialIndex) ? materials[materialIndex] : defaultMaterial
        }
    }

    final class EnvironmentCache: Sendable {
        private let environments = Mutex<[Int: PBREnvironment]>([:])

        func environment(_ index: Int, light: GLTFImageBasedLight, device: MTLDevice) throws -> PBREnvironment {
            if let cached = environments.withLock({ $0[index] }) {
                return cached
            }
            let built = try light.environment(device: device)
            return environments.withLock { environments in
                if let raced = environments[index] {
                    return raced
                }
                environments[index] = built
                return built
            }
        }
    }

    let resources: Resources
    /// The scene this asset shows; ``scene(_:)`` builds another from the same loaded data.
    public let sceneIndex: Int
    public var sceneCount: Int { container.document.scenes.count }
    /// The KHR_materials_variants variant in use, or nil for the default materials.
    public let variant: Int?

    /// The EXT_lights_image_based light this scene uses, decoded; nil when it uses none.
    public var imageBasedLight: GLTFImageBasedLight? {
        GLTFImageBasedLight.lightIndex(document: container.document, sceneIndex: sceneIndex).flatMap { resources.imageBasedLights[$0] }
    }

    /// ``imageBasedLight`` as an environment, built on first use (GPU work) and shared by this file's other scenes
    /// and variants.
    public func environment() throws -> PBREnvironment? {
        guard let index = GLTFImageBasedLight.lightIndex(document: container.document, sceneIndex: sceneIndex), let light = resources.imageBasedLights[index] else {
            return nil
        }
        return try resources.environments.environment(index, light: light, device: resources.device)
    }

    public convenience init(container: Container, device: MTLDevice? = nil, sceneIndex: Int? = nil, variant: Int? = nil, options: GLTFLoadOptions = GLTFLoadOptions()) throws {
        // The options' buffer view decoders join any the container already has.
        let missing = options.bufferViewDecoders.filter { decoder in !container.bufferViewDecoders.contains { $0.extensionNames == decoder.extensionNames } }
        var container = missing.isEmpty ? container : container.withBufferViewDecoders(container.bufferViewDecoders + missing)
        if !options.disabledExtensions.isEmpty {
            // Declarations stay, so the file still reports what it uses and a disabled required extension fails the
            // required-extension check.
            container = try container.withDocument(container.document.removingExtensions(options.disabledExtensions, keepingDeclarations: true))
        }
        let resources = try Resources.load(container: container, device: device ?? _MTLCreateSystemDefaultDevice(), options: options)
        try self.init(container: container, resources: resources, sceneIndex: sceneIndex ?? container.document.scene?.index ?? 0, variant: variant)
    }

    /// The same file showing scene `index` (with the same variant), sharing this asset's meshes, materials and textures.
    public func scene(_ index: Int) throws -> GLTFAsset {
        guard container.document.scenes.indices.contains(index) else {
            throw GLTFError.invalidDocument("Scene \(index) is out of range (\(sceneCount) scenes)")
        }
        return try GLTFAsset(container: container, resources: resources, sceneIndex: index, variant: variant)
    }

    /// The same scene with KHR_materials_variants variant `index` (an index into ``variantNames``, or nil for the
    /// default materials), sharing this asset's meshes, materials and textures.
    public func variant(_ index: Int?) throws -> GLTFAsset {
        if let index, !variantNames.indices.contains(index) {
            throw GLTFError.invalidDocument("Variant \(index) is out of range (\(variantNames.count) variants)")
        }
        return try GLTFAsset(container: container, resources: resources, sceneIndex: sceneIndex, variant: index)
    }

    /// Builds scene `sceneIndex` from already-loaded resources.
    init(container: Container, resources: Resources, sceneIndex: Int, variant: Int?) throws {
        let contents = try GLTFSceneContents(document: container.document, resources: resources, sceneIndex: sceneIndex, variant: variant)
        self.container = container
        self.resources = resources
        self.sceneIndex = sceneIndex
        self.variant = variant
        self.model = contents.model
        self.materials = resources.materials
        self.meshes = resources.meshes
        self.animations = resources.animations
        self.warnings = resources.warnings
        self.variantNames = container.document.materialVariantNames
        self.lightSources = contents.lightSources
        self.cameraSources = contents.cameraSources
        self.cameras = contents.cameraSources.map { ($0.camera, $0.worldMatrix) }
        self.hierarchy = contents.hierarchy
    }
}

public extension GLTFAsset {
    /// The lights at `pose`: placed by it (lights on animated nodes move), with animated properties, without lights on
    /// hidden nodes. A pose from ``pose(animation:time:)`` carries them already.
    func lights(pose: PBRPose) -> [PBRLight] {
        pose.lights ?? lights(pose: pose, properties: [:])
    }

    /// `cameras` placed by `pose` (cameras on animated nodes move), with animated projection properties applied.
    func cameras(pose: PBRPose) -> [(camera: SwiftGLTF.Camera, worldMatrix: simd_float4x4)] {
        cameraSources.map { source in
            let camera = pose.cameraParameters[source.index].map { GLTFAnimationPointer.apply($0, to: source.camera) } ?? source.camera
            return (camera, pose.worldMatrices.indices.contains(source.node) ? pose.worldMatrices[source.node] : source.worldMatrix)
        }
    }

    /// World bounds of everything drawn with `pose`.
    func bounds(for pose: PBRPose) -> PBRBounds {
        model.bounds(for: pose)
    }

    /// World bounds of a batch's instances drawn with `pose`.
    func worldBounds(of batch: Batch, pose: PBRPose) -> PBRBounds {
        model.worldBounds(of: batch, pose: pose)
    }

    /// Morph weights for `node` at rest.
    func restMorphWeights(node: Int) -> [Float] {
        model.restMorphWeights(node: node)
    }

    /// Material overrides that draw this asset's model with KHR_materials_variants variant `index` (nil for the
    /// default materials) without rebuilding it: set them on ``PBRScene/materialOverrides``. Nil when the variant
    /// changes a primitive's alpha mode or transmission, which needs ``variant(_:)`` instead. Throws for an
    /// out-of-range index.
    func materialOverrides(variant index: Int?) throws -> PBRModel.MaterialOverrides? {
        if let index, !variantNames.indices.contains(index) {
            throw GLTFError.invalidDocument("Variant \(index) is out of range (\(variantNames.count) variants)")
        }
        var overrides: PBRModel.MaterialOverrides = [:]
        for primitive in meshes.flatMap(\.self) {
            let built = resources.material(for: primitive, variant: variant)
            let wanted = resources.material(for: primitive, variant: index)
            guard built !== wanted else { continue }
            guard built.canOverride(wanted) else { return nil }
            overrides[primitive.key] = wanted
        }
        return overrides
    }
}

extension GLTFAsset {
    var merged: PBRMergedGeometry? { model.merged }
    var mergedSkinned: PBRMergedGeometry? { model.mergedSkinned }
    var mergedTransmissive: PBRMergedGeometry? { model.mergedTransmissive }
}

extension GLTFAsset {
    /// Lights placed by `pose`, skipping hidden ones, with `properties` (KHR_animation_pointer values by light index,
    /// then property below `/extensions/KHR_lights_punctual/lights/N/`) applied.
    func lights(pose: PBRPose, properties: [Int: [String: [Float]]]) -> [PBRLight] {
        let rest = model.restPose
        return lightSources.compactMap { source in
            guard pose.isVisible(source.node) else { return nil }
            let world = pose.worldMatrices.indices.contains(source.node) ? pose.worldMatrices[source.node] : rest.worldMatrices.indices.contains(source.node) ? rest.worldMatrices[source.node] : matrix_identity_float4x4
            var light = PBRLight(source.light, worldMatrix: world)
            GLTFAnimationPointer.apply(properties[source.index] ?? [:], to: &light)
            return light
        }
    }
}

extension PBRLight {
    init(_ light: SwiftGLTF.Light, worldMatrix: simd_float4x4) {
        self.init()
        position = worldMatrix.columns.3.xyz
        // Lights point down their local -Z.
        direction = simd_normalize((worldMatrix * SIMD4<Float>(0, 0, -1, 0)).xyz)
        color = light.color
        intensity = light.intensity
        range = light.range ?? 0
        switch light.type {
        case .directional:
            type = .directional

        case .point:
            type = .point

        case .spot:
            type = .spot
            innerConeCos = cos(light.spot?.innerConeAngle ?? 0)
            outerConeCos = cos(light.spot?.outerConeAngle ?? .pi / 4)
        }
    }
}
