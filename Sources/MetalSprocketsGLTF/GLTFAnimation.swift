import GeometryLite3D
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
        /// A material property below `/materials/N/` (KHR_animation_pointer).
        case material(Int, GLTFAnimationPointer.MaterialPointer)
        /// A node's KHR_node_visibility `visible` (KHR_animation_pointer).
        case visibility(Int)
        /// A KHR_lights_punctual light property (KHR_animation_pointer).
        case light(Int, GLTFAnimationPointer.LightProperty)
        /// A camera projection property (KHR_animation_pointer).
        case camera(Int, GLTFAnimationPointer.CameraProperty)
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

extension Node {
    /// An identity `matrix` counts as absent, so such nodes keep their translation, rotation and scale.
    var usesMatrix: Bool {
        matrix.map { $0 != matrix_identity_float4x4 } ?? false
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
        guard rest.indices.contains(node) else { return nil }
        let transform = rest[node]
        if path != .weights, case .matrix = transform.storage { return nil }
        switch path {
        case .translation:
            return [transform.translation.x, transform.translation.y, transform.translation.z]

        case .rotation:
            let vector = transform.rotation.quaternion.vector
            return [vector.x, vector.y, vector.z, vector.w]

        case .scale:
            return [transform.scale.x, transform.scale.y, transform.scale.z]

        case .weights: return restMorphWeights.indices.contains(node) ? restMorphWeights[node] : nil
        }
    }
}

/// Rest transforms and parent links for the nodes of a scene. The rest build and every pose use the same walk of the node tree.
struct GLTFNodeHierarchy: Sendable {
    /// Nodes that use `matrix` have `.matrix` storage; glTF does not allow those to be animated.
    var rest: [Transform3D]
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
            if node.usesMatrix, let matrix = node.matrix {
                return Transform3D(storing: matrix)
            }
            return Transform3D(
                translation: node.translation ?? .zero,
                rotation: node.rotation.map { simd_quatf(vector: $0) } ?? .identity,
                scale: node.scale ?? [1, 1, 1]
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
    func walk(_ transforms: [Transform3D], visible: [Bool]? = nil, _ body: (_ node: Int, _ world: simd_float4x4, _ visible: Bool) throws -> Void) rethrows {
        let ownVisible = visible ?? restVisible
        func visit(_ node: Int, parent: simd_float4x4, parentVisible: Bool) throws {
            let world = parent * transforms[node].matrix
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
    func pose(_ transforms: [Transform3D], morphWeights: [[Float]], visible: [Bool]? = nil) -> PBRPose {
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

extension GLTFNodeHierarchy {
    /// The nodes of scene `sceneIndex`, or every root node when the document has no such scene.
    init(document: Document, sceneIndex: Int) throws {
        let roots: [Int]
        if sceneIndex < document.scenes.count {
            roots = document.scenes[sceneIndex].nodes.map(\.index)
        } else {
            let children = Set(document.nodes.flatMap { $0.children.map(\.index) })
            roots = document.nodes.indices.filter { !children.contains($0) }
        }
        try self.init(document: document, roots: roots)
    }
}

extension GLTFAnimationClip {
    /// Every animation of the document, with warnings for channels that cannot be used.
    static func load(container: Container) throws -> (clips: [Self], warnings: [String]) {
        let document = container.document
        var warnings: [String] = []
        var clips = try document.animations.enumerated().map { index, animation in
            try GLTFAnimationClip(animation, index: index, container: container)
        }
        // glTF forbids animating translation, rotation or scale of a node that uses `matrix`.
        for index in clips.indices {
            let name = clips[index].name
            clips[index].channels.removeAll { channel in
                guard case let .node(node, property) = channel.target, property != .weights,
                      document.nodes.indices.contains(node), document.nodes[node].usesMatrix else {
                    return false
                }
                warnings.append("Skipped \(name) channel: node \(node) uses matrix, so its \(property.rawValue) cannot be animated")
                return true
            }
        }
        warnings += Set(clips.flatMap(\.unsupportedPointers)).sorted().map { "Animation pointer not supported: \($0)" }
        return (clips, warnings)
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
        poser.pose(layers: layers, rootMotionNode: rootMotionNode)
    }

    /// The translation the override layers give `node`, before root motion is removed: what a controller follows to
    /// move a character by its animation.
    func rootTranslation(layers: [GLTFAnimationLayer], node: Int) -> SIMD3<Float> {
        poser.rootTranslation(layers: layers, node: node)
    }
}
