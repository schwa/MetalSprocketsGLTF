import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

/// A glTF animation with its keyframes decoded: node translation, rotation, scale and morph weights.
public struct GLTFAnimationClip: Sendable {
    /// A node property that glTF animation channels target directly.
    public enum NodeProperty: String, Sendable, Hashable, CaseIterable {
        case translation
        case rotation
        case scale
        /// Morph target weights.
        case weights
    }

    /// How values change between keyframes.
    public enum Interpolation: Sendable, Hashable {
        case step
        case linear
        /// Each keyframe stores in-tangent, value and out-tangent, in that order.
        case cubicSpline
    }

    /// What a channel animates. Indices are into the glTF document's nodes, materials, lights and cameras.
    public enum Target: Sendable, Hashable {
        /// A node's translation, rotation, scale or morph weights.
        case node(Int, NodeProperty)
        /// A material property, named by its JSON pointer below `/materials/N/` (KHR_animation_pointer).
        case material(Int, String)
        /// A node's KHR_node_visibility `visible` (KHR_animation_pointer).
        case visibility(Int)
        /// A KHR_lights_punctual light property below `/extensions/KHR_lights_punctual/lights/N/` (`color`,
        /// `intensity`, `range`, `spot/innerConeAngle`, `spot/outerConeAngle`).
        case light(Int, String)
        /// A camera property below `/cameras/N/` (`perspective/yfov`, `perspective/znear`, `perspective/zfar`,
        /// `perspective/aspectRatio`, `orthographic/xmag`, `orthographic/ymag`, `orthographic/znear`,
        /// `orthographic/zfar`).
        case camera(Int, String)
    }

    /// One animated property and its keyframes.
    public struct Channel: Sendable {
        public let target: Target
        let keyframes: AnimationKeyframes

        /// Keyframe times in seconds, ascending.
        public var times: [Float] { keyframes.times }
        /// Keyframe values, flattened: `componentsPerValue` floats per value, and three values (in-tangent, value,
        /// out-tangent) per keyframe for ``Interpolation/cubicSpline``. Rotations are quaternions (x, y, z, w).
        public var values: [Float] { keyframes.values }
        /// Floats per value: 3 for translation and scale, 4 for rotation, the morph target count for weights, and the
        /// property's size for pointer targets.
        public var componentsPerValue: Int { keyframes.componentsPerValue }
        public var interpolation: Interpolation {
            switch keyframes.interpolation {
            case .STEP: .step
            case .CUBICSPLINE: .cubicSpline
            default: .linear
            }
        }

        /// The value at `time` (clamped to the keyframes), with rotations interpolated on the sphere.
        public func sample(at time: Float) -> [Float] {
            keyframes.sample(at: time, isRotation: target.isRotation)
        }
    }

    public var name: String
    /// Seconds from the start to the last keyframe of any channel.
    public var duration: Float
    /// The channels this renderer can animate; see ``unsupportedPointers`` for the rest.
    public internal(set) var channels: [Channel]
    /// KHR_animation_pointer targets this renderer cannot animate.
    public var unsupportedPointers: [String]

    init(_ animation: Animation, index: Int, container: Container) throws {
        name = animation.name ?? "Animation \(index)"
        var unsupported: [String] = []
        channels = try animation.channels.compactMap { channel in
            guard animation.samplers.indices.contains(channel.sampler) else {
                return nil
            }
            let target: Target
            if let node = channel.target.node?.index {
                guard let property = NodeProperty(rawValue: channel.target.path.rawValue) else {
                    return nil
                }
                target = .node(node, property)
            } else if let pointer = channel.target.animationPointer {
                guard let parsed = GLTFAnimationPointer.target(pointer) else {
                    unsupported.append(pointer)
                    return nil
                }
                target = parsed
            } else {
                return nil
            }
            return Channel(target: target, keyframes: try container.keyframes(for: animation.samplers[channel.sampler]))
        }
        unsupportedPointers = unsupported
        duration = channels.map(\.keyframes.duration).max() ?? 0
    }
}

extension Animation.Channel.Target {
    /// The KHR_animation_pointer JSON pointer, when the channel targets a property by pointer.
    var animationPointer: String? {
        guard case .object(let object)? = extensions?.values["KHR_animation_pointer"], case .string(let pointer)? = object["pointer"] else {
            return nil
        }
        return pointer
    }
}

extension GLTFAnimationClip.Target {
    var isRotation: Bool {
        if case .node(_, .rotation) = self { true } else { false }
    }
}

extension GLTFNodeHierarchy {
    /// A node's rest value for `path`, as an animation sampler would give it; nil for nodes that use `matrix`.
    func restValue(node: Int, path: GLTFAnimationClip.NodeProperty) -> [Float]? {
        guard rest.indices.contains(node), rest[node].matrix == nil else { return nil }
        let transform = rest[node]
        switch path {
        case .translation: return [transform.translation.x, transform.translation.y, transform.translation.z]
        case .rotation: return [transform.rotation.vector.x, transform.rotation.vector.y, transform.rotation.vector.z, transform.rotation.vector.w]
        case .scale: return [transform.scale.x, transform.scale.y, transform.scale.z]
        case .weights: return restMorphWeights.indices.contains(node) ? restMorphWeights[node] : nil
        }
    }
}

/// Rest transforms and parent links for the nodes of a scene. The rest build and every pose use the same walk of the node tree.
struct GLTFNodeHierarchy: Sendable {
    struct Transform: Sendable {
        var translation: SIMD3<Float>
        var rotation: simd_quatf
        var scale: SIMD3<Float>
        /// Set when the node uses `matrix`, which glTF does not allow to be animated.
        var matrix: simd_float4x4?

        var localMatrix: simd_float4x4 {
            if let matrix {
                return matrix
            }
            var result = simd_float4x4(rotation)
            result.columns.0 *= scale.x
            result.columns.1 *= scale.y
            result.columns.2 *= scale.z
            result.columns.3 = SIMD4(translation, 1)
            return result
        }
    }

    var rest: [Transform]
    var restMorphWeights: [[Float]]
    /// Each node's own KHR_node_visibility `visible` at rest (not inherited).
    var restVisible: [Bool]
    var children: [[Int]]
    var roots: [Int]

    /// Throws when a node reachable from `roots` is out of range or is its own ancestor; the walks below rely on this.
    init(document: Document, roots: [Int]) throws {
        // Nodes on the path from the root to the current node; meeting one again means the hierarchy has a cycle.
        var path = Set<Int>()
        func validate(_ node: Int) throws {
            guard document.nodes.indices.contains(node) else {
                throw GLTFError.invalidDocument("Node index \(node) is out of range")
            }
            guard path.insert(node).inserted else {
                throw GLTFError.invalidDocument("Node \(node) is its own ancestor")
            }
            defer { path.remove(node) }
            for child in document.nodes[node].children {
                try validate(child.index)
            }
        }
        for root in roots {
            try validate(root)
        }
        rest = document.nodes.map { node in
            let matrix = node.matrix.flatMap { $0 == matrix_identity_float4x4 ? nil : $0 }
            return Transform(
                translation: node.translation ?? .zero,
                rotation: node.rotation.map { simd_quatf(vector: $0) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                scale: node.scale ?? [1, 1, 1],
                matrix: matrix
            )
        }
        restMorphWeights = document.nodes.map { (try? $0.morphWeights(in: document)) ?? [] }
        restVisible = document.nodes.map(\.isVisible)
        children = document.nodes.map { node in node.children.map(\.index).filter { document.nodes.indices.contains($0) } }
        self.roots = roots
    }

    /// Visits every node reachable from the roots, depth first and parents before children, with its world matrix
    /// for `transforms` and its visibility (each node's own `visible`, inherited down the hierarchy). A node reached
    /// through two parents is visited twice.
    func walk(_ transforms: [Transform], visible: [Bool]? = nil, _ body: (_ node: Int, _ world: simd_float4x4, _ visible: Bool) throws -> Void) rethrows {
        let ownVisible = visible ?? restVisible
        func visit(_ node: Int, parent: simd_float4x4, parentVisible: Bool) throws {
            let world = parent * transforms[node].localMatrix
            let visible = parentVisible && (ownVisible.indices.contains(node) ? ownVisible[node] : true)
            try body(node, world, visible)
            for child in children[node] {
                try visit(child, parent: world, parentVisible: visible)
            }
        }
        for root in roots where transforms.indices.contains(root) {
            try visit(root, parent: matrix_identity_float4x4, parentVisible: true)
        }
    }

    /// World matrices and visibility for `transforms`; see ``walk(_:visible:_:)``.
    func pose(_ transforms: [Transform], morphWeights: [[Float]], visible: [Bool]? = nil) -> PBRPose {
        var world = [simd_float4x4](repeating: matrix_identity_float4x4, count: transforms.count)
        var effective = [Bool](repeating: true, count: transforms.count)
        walk(transforms, visible: visible) { node, nodeWorld, nodeVisible in
            world[node] = nodeWorld
            effective[node] = nodeVisible
        }
        // Empty when every node is visible, so poses of models without hidden nodes cost nothing extra to draw.
        return PBRPose(worldMatrices: world, morphWeights: morphWeights, visibility: effective.contains(false) ? effective : [])
    }
}

public extension GLTFAsset {
    /// The scene with `animations[animation]` applied at `time` seconds (clamped to the clip).
    func pose(animation: Int, time: Float) -> PBRPose {
        pose(layers: [GLTFAnimationLayer(animation: animation, time: time)])
    }

    /// The scene with several clips blended by weight (see ``GLTFAnimationController``).
    ///
    /// Weights are normalized to sum to 1. Node translation, scale and morph weights are blended linearly and rotation
    /// with normalized linear interpolation; a node a layer does not animate counts as its rest transform for that
    /// layer. Other animated values (materials, lights, cameras) are blended over the layers that animate them.
    /// Visibility shows a node when layers weighing more than half show it.
    ///
    /// Additive layers (``GLTFAnimationLayer/Mode/additive``) then add, scaled by their weight, how far their clip moves
    /// each node from its rest transform (translation and morph weights add, rotation and scale compose); they do not
    /// change materials, lights or cameras. With `rootMotionNode`, that node's horizontal (x, z) translation stays at
    /// rest, so a controller can move the character instead (see ``rootTranslation(layers:node:)``).
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

    /// The translation the override layers give `node`, before root motion is removed: what a controller follows to
    /// move a character by its animation.
    func rootTranslation(layers: [GLTFAnimationLayer], node: Int) -> SIMD3<Float> {
        let overrides = layers.filter { animations.indices.contains($0.animation) && $0.weight > 0 && $0.mode == .override }
        let value = blendedValues(overrides)[.node(node, .translation)] ?? hierarchy.restValue(node: node, path: .translation) ?? [0, 0, 0]
        return value.count == 3 ? SIMD3(value[0], value[1], value[2]) : .zero
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
                let delta = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), restRotation.inverse * sampled, weight)
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
        var lightProperties: [Int: [String: [Float]]] = [:]
        var cameraParameters: [Int: [String: Float]] = [:]
        for (target, value) in values {
            switch target {
            case let .node(node, path) where transforms.indices.contains(node):
                switch path {
                case .translation where value.count == 3:
                    transforms[node].translation = SIMD3(value[0], value[1], value[2])
                case .rotation where value.count == 4:
                    transforms[node].rotation = simd_quatf(vector: SIMD4(value[0], value[1], value[2], value[3]))
                case .scale where value.count == 3:
                    transforms[node].scale = SIMD3(value[0], value[1], value[2])
                case .weights:
                    morphWeights[node] = value
                default:
                    break
                }
            case let .material(index, property) where materials.indices.contains(index):
                // Parsed once at load (Resources.materialProperties).
                guard let parsed = resources.materialProperties[property] else { break }
                var state = animatedMaterials[index] ?? materials[index].animatedState()
                state.apply(parsed, value: value)
                animatedMaterials[index] = state
            case let .visibility(node) where visible.indices.contains(node):
                // A boolean; glTF stores it as a number, normally with step interpolation.
                visible[node] = (value.first ?? 1) > 0.5
            case let .light(index, property):
                lightProperties[index, default: [:]][property] = value
            case let .camera(index, property):
                if let value = value.first {
                    cameraParameters[index, default: [:]][property] = value
                }
            default:
                break
            }
        }
        var pose = hierarchy.pose(transforms, morphWeights: morphWeights, visible: visible)
        for (index, state) in animatedMaterials {
            pose.materialUniforms[ObjectIdentifier(materials[index])] = state.uniforms
        }
        pose.cameraParameters = cameraParameters
        pose.lights = lights(pose: pose, properties: lightProperties)
        return pose
    }
}
