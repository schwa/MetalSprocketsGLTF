import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

/// Poses one scene of a document: samples and blends its animation clips into node transforms, morph weights,
/// visibility, material uniforms, lights and camera parameters. Needs no GPU, so it can be built from a `Container`
/// alone; ``GLTFAsset`` builds one per scene and forwards its posing calls here.
// Immutable; @unchecked only because material rest states hold texture-slot key paths, which are not Sendable.
struct GLTFPoser: @unchecked Sendable {
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

    /// A material that channels may animate, by glTF material index: the key for ``PBRPose/materialUniforms`` and
    /// its state at rest.
    struct Material {
        var id: ObjectIdentifier
        var rest: PBRMaterial.AnimatedState
    }

    let hierarchy: GLTFNodeHierarchy
    let animations: [GLTFAnimationClip]
    let materials: [Material]
    /// Every light and camera of the scene. Includes lights hidden at rest that animation can show.
    let lightSources: [LightSource]
    let cameraSources: [CameraSource]
    let restPose: PBRPose

    /// `materials` are indexed like the document's materials; channels for materials not listed are ignored.
    init(document: Document, hierarchy: GLTFNodeHierarchy, animations: [GLTFAnimationClip], materials: [Material] = []) throws {
        let animatesVisibility = animations.contains { clip in
            clip.channels.contains { if case .visibility = $0.target { true } else { false } }
        }
        var lightSources: [LightSource] = []
        var cameraSources: [CameraSource] = []
        try hierarchy.walk(hierarchy.rest) { nodeIndex, world, visible in
            let node = document.nodes[nodeIndex]
            if let camera = node.camera {
                cameraSources.append(CameraSource(camera: try camera.resolve(in: document), index: camera.index, node: nodeIndex, worldMatrix: world))
            }
            // Hidden lights are kept only when animation can show them; the rest pose hides them.
            if visible || animatesVisibility, let light = node.punctualLight(in: document), let lightIndex = (try? node.extensionValue(KHRLightsPunctualNodeRef.self))?.light {
                lightSources.append(LightSource(light: light, index: lightIndex, node: nodeIndex))
            }
        }
        self.hierarchy = hierarchy
        self.animations = animations
        self.materials = materials
        self.lightSources = lightSources
        self.cameraSources = cameraSources
        self.restPose = hierarchy.pose(hierarchy.rest, morphWeights: hierarchy.restMorphWeights)
    }

    /// Scene `sceneIndex` of `container` (or every root node when the document has no scenes), with all its clips.
    init(container: Container, sceneIndex: Int, materials: [Material] = []) throws {
        let document = container.document
        let hierarchy = try GLTFNodeHierarchy(document: document, sceneIndex: sceneIndex)
        try self.init(document: document, hierarchy: hierarchy, animations: try GLTFAnimationClip.load(container: container).clips, materials: materials)
    }

    // MARK: Posing

    /// See ``GLTFAsset/pose(layers:rootMotionNode:)``.
    func pose(layers: [GLTFAnimationLayer], rootMotionNode: Int? = nil) -> PBRPose {
        let active = layers.filter { animations.indices.contains($0.animation) && $0.weight > 0 }
        let overrides = active.filter { $0.mode == .override }
        let additives = active.filter { $0.mode == .additive }
        guard !active.isEmpty else {
            return restPose
        }
        // One clip (the common case): apply its channels in order, without blending.
        if overrides.count == 1, additives.isEmpty, rootMotionNode == nil {
            let layer = overrides[0]
            return pose(values: animations[layer.animation].channels.lazy.map { ($0.target, $0.keyframes.sample(at: layer.time, isRotation: $0.target.isRotation)) })
        }
        var values = blendedValues(overrides)
        for layer in additives {
            addDeltas(of: layer, to: &values)
        }
        if let node = rootMotionNode, let rest = hierarchy.restValue(node: node, path: .translation), rest.count == 3 {
            var translation = values[.node(node, .translation)] ?? rest
            translation[0] = rest[0]
            translation[2] = rest[2]
            values[.node(node, .translation)] = translation
        }
        return pose(values: values.lazy.map { ($0.key, $0.value) })
    }

    /// See ``GLTFAsset/rootTranslation(layers:node:)``.
    func rootTranslation(layers: [GLTFAnimationLayer], node: Int) -> SIMD3<Float> {
        let overrides = layers.filter { animations.indices.contains($0.animation) && $0.weight > 0 && $0.mode == .override }
        let value = blendedValues(overrides)[.node(node, .translation)] ?? hierarchy.restValue(node: node, path: .translation) ?? [0, 0, 0]
        return value.count == 3 ? SIMD3(value[0], value[1], value[2]) : .zero
    }

    /// Lights placed by `pose`, skipping hidden ones, with `properties` (KHR_animation_pointer values by light index)
    /// applied.
    func lights(pose: PBRPose, properties: [Int: [GLTFAnimationPointer.LightProperty: [Float]]] = [:]) -> [LightingLight] {
        lightSources.compactMap { source in
            guard pose.isVisible(source.node) else { return nil }
            let world = pose.worldMatrices.indices.contains(source.node) ? pose.worldMatrices[source.node] : restPose.worldMatrices.indices.contains(source.node) ? restPose.worldMatrices[source.node] : matrix_identity_float4x4
            var light = LightingLight(source.light, worldMatrix: world)
            GLTFAnimationPointer.apply(properties[source.index] ?? [:], to: &light)
            return light
        }
    }

    /// See ``GLTFAsset/cameras(pose:)``.
    func cameras(pose: PBRPose) -> [(camera: SwiftGLTF.Camera, worldMatrix: simd_float4x4)] {
        cameraSources.map { source in
            let camera = pose.cameraParameters[source.index].map { GLTFAnimationPointer.apply($0, to: source.camera) } ?? source.camera
            return (camera, pose.worldMatrices.indices.contains(source.node) ? pose.worldMatrices[source.node] : source.worldMatrix)
        }
    }

    /// Override layers blended by normalized weight; a node a layer does not animate counts as its rest transform.
    private func blendedValues(_ active: [GLTFAnimationLayer]) -> [GLTFAnimationClip.Target: [Float]] {
        let totalWeight = active.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return [:]
        }
        var contributions: [GLTFAnimationClip.Target: [(weight: Float, value: [Float])]] = [:]
        for layer in active {
            // Within one clip a later channel for the same target wins.
            var sampled: [GLTFAnimationClip.Target: [Float]] = [:]
            for channel in animations[layer.animation].channels {
                sampled[channel.target] = channel.keyframes.sample(at: layer.time, isRotation: channel.target.isRotation)
            }
            for (target, value) in sampled {
                contributions[target, default: []].append((layer.weight / totalWeight, value))
            }
        }
        var values: [GLTFAnimationClip.Target: [Float]] = [:]
        for (target, list) in contributions {
            var list = list
            let covered = list.reduce(0) { $0 + $1.weight }
            if covered < 1 - 1e-6, case let .node(node, path) = target, let rest = hierarchy.restValue(node: node, path: path) {
                list.append((1 - covered, rest))
            }
            values[target] = Self.blend(list, isRotation: target.isRotation)
        }
        return values
    }

    /// Adds `layer`'s offsets from rest, scaled by its weight, to the node values in `values`.
    private func addDeltas(of layer: GLTFAnimationLayer, to values: inout [GLTFAnimationClip.Target: [Float]]) {
        let weight = layer.weight
        for channel in animations[layer.animation].channels {
            guard case let .node(node, path) = channel.target, let rest = hierarchy.restValue(node: node, path: path) else { continue }
            let sample = channel.keyframes.sample(at: layer.time, isRotation: path == .rotation)
            let base = values[channel.target] ?? rest
            guard sample.count == rest.count, base.count == rest.count else { continue }
            switch path {
            case .rotation where rest.count == 4:
                let restRotation = simd_quatf(vector: SIMD4(rest[0], rest[1], rest[2], rest[3]))
                let sampled = simd_quatf(vector: SIMD4(sample[0], sample[1], sample[2], sample[3]))
                let baseRotation = simd_quatf(vector: SIMD4(base[0], base[1], base[2], base[3]))
                let delta = simd_slerp(simd_quatf.identity, restRotation.inverse * sampled, weight)
                let result = simd_normalize(baseRotation * delta).vector
                values[channel.target] = [result.x, result.y, result.z, result.w]

            case .scale:
                values[channel.target] = (0 ..< 3).map { index in
                    rest[index] == 0 ? base[index] : base[index] * pow(sample[index] / rest[index], weight)
                }

            default:
                values[channel.target] = (0 ..< rest.count).map { base[$0] + (sample[$0] - rest[$0]) * weight }
            }
        }
    }

    private static func blend(_ list: [(weight: Float, value: [Float])], isRotation: Bool) -> [Float] {
        guard list.count > 1 else {
            return list.first?.value ?? []
        }
        let count = list.map(\.value.count).min() ?? 0
        let reference = list[0].value
        var result = [Float](repeating: 0, count: count)
        var totalWeight: Float = 0
        for (weight, value) in list {
            // q and -q are the same rotation: blend each on the reference's side.
            var sign: Float = 1
            if isRotation {
                let dot = zip(reference.prefix(count), value.prefix(count)).reduce(0) { $0 + $1.0 * $1.1 }
                sign = dot < 0 ? -1 : 1
            }
            for index in 0 ..< count {
                result[index] += value[index] * weight * sign
            }
            totalWeight += weight
        }
        if isRotation {
            let length = sqrt(result.reduce(0) { $0 + $1 * $1 })
            return length > 0 ? result.map { $0 / length } : reference
        }
        return totalWeight > 0 ? result.map { $0 / totalWeight } : reference
    }

    private func pose(values: some Sequence<(GLTFAnimationClip.Target, [Float])>) -> PBRPose {
        var transforms = hierarchy.rest
        var morphWeights = hierarchy.restMorphWeights
        var visible = hierarchy.restVisible
        var animatedMaterials: [Int: PBRMaterial.AnimatedState] = [:]
        var lightProperties: [Int: [GLTFAnimationPointer.LightProperty: [Float]]] = [:]
        var cameraParameters: [Int: [String: Float]] = [:]
        for (target, value) in values {
            switch target {
            case let .node(node, path) where transforms.indices.contains(node):
                // Loading drops channels that animate a matrix node; this guards clips built some other way.
                let isMatrix = if case .matrix = transforms[node].storage { true } else { false }
                switch path {
                case .translation where value.count == 3 && !isMatrix:
                    transforms[node].translation = SIMD3(value[0], value[1], value[2])

                case .rotation where value.count == 4 && !isMatrix:
                    transforms[node].rotation = .quaternion(simd_quatf(vector: SIMD4(value[0], value[1], value[2], value[3])))

                case .scale where value.count == 3 && !isMatrix:
                    transforms[node].scale = SIMD3(value[0], value[1], value[2])

                case .weights:
                    morphWeights[node] = value

                default:
                    break
                }

            case let .material(index, pointer) where materials.indices.contains(index):
                var state = animatedMaterials[index] ?? materials[index].rest
                state.apply(pointer.property, value: value)
                animatedMaterials[index] = state

            case let .visibility(node) where visible.indices.contains(node):
                // A boolean; glTF stores it as a number, normally with step interpolation.
                visible[node] = (value.first ?? 1) > 0.5

            case let .light(index, property):
                lightProperties[index, default: [:]][property] = value

            case let .camera(index, property):
                if let value = value.first {
                    // PBRPose keys camera parameters by path.
                    cameraParameters[index, default: [:]][property.rawValue] = value
                }

            default:
                break
            }
        }
        var pose = hierarchy.pose(transforms, morphWeights: morphWeights, visible: visible)
        for (index, state) in animatedMaterials {
            pose.materialUniforms[materials[index].id] = state.uniforms
        }
        pose.cameraParameters = cameraParameters
        pose.lights = lights(pose: pose, properties: lightProperties)
        return pose
    }
}
