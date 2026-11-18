import Foundation
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

// KHR_animation_pointer: which JSON pointers this renderer can animate, and how each animated value is applied.
// A pointer is parsed once, into a typed target that knows how to apply its value.

public enum GLTFAnimationPointer {
    typealias Target = GLTFAnimationClip.Target

    /// Parses a JSON pointer into a node, material, visibility, light or camera target; nil when unsupported.
    static func target(_ pointer: String) -> Target? {
        let parts = pointer.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 5, parts[0] == "extensions", parts[1] == "KHR_lights_punctual", parts[2] == "lights", let index = Int(parts[3]) {
            return LightProperty(rawValue: parts.dropFirst(4).joined(separator: "/")).map { .light(index, $0) }
        }
        guard parts.count >= 3, let index = Int(parts[1]) else {
            return nil
        }
        let property = parts.dropFirst(2).joined(separator: "/")
        switch parts[0] {
        case "nodes" where property == "extensions/KHR_node_visibility/visible":
            return .visibility(index)

        case "nodes" where parts.count == 3:
            return GLTFAnimationClip.NodeProperty(rawValue: parts[2]).map { .node(index, $0) }

        case "materials":
            return MaterialPointer(property).map { .material(index, $0) }

        case "cameras":
            return CameraProperty(rawValue: property).map { .camera(index, $0) }

        default:
            return nil
        }
    }

    // MARK: Lights

    /// A KHR_lights_punctual light property; the raw value is its path below `/extensions/KHR_lights_punctual/lights/N/`.
    public enum LightProperty: String, CaseIterable, Sendable, Hashable {
        case color
        case intensity
        case range
        case innerConeAngle = "spot/innerConeAngle"
        case outerConeAngle = "spot/outerConeAngle"

        func apply(_ value: [Float], to light: inout LightingLight) {
            switch self {
            case .color: if value.count == 3 { light.color = SIMD3(value[0], value[1], value[2]) }
            case .intensity: if let value = value.first { light.intensity = value }
            case .range: if let value = value.first { light.range = value }
            case .innerConeAngle: if let value = value.first { light.innerConeCos = cos(value) }
            case .outerConeAngle: if let value = value.first { light.outerConeCos = cos(value) }
            }
        }
    }

    static func apply(_ properties: [LightProperty: [Float]], to light: inout LightingLight) {
        for (property, value) in properties {
            property.apply(value, to: &light)
        }
    }

    // MARK: Cameras

    /// A camera property; the raw value is its path below `/cameras/N/`, which is also its key in
    /// ``PBRPose/cameraParameters``.
    public enum CameraProperty: String, CaseIterable, Sendable, Hashable {
        case perspectiveYfov = "perspective/yfov"
        case perspectiveZnear = "perspective/znear"
        case perspectiveZfar = "perspective/zfar"
        case perspectiveAspectRatio = "perspective/aspectRatio"
        case orthographicXmag = "orthographic/xmag"
        case orthographicYmag = "orthographic/ymag"
        case orthographicZnear = "orthographic/znear"
        case orthographicZfar = "orthographic/zfar"
    }

    /// `camera` with animated properties applied. Properties of a projection the camera lacks are ignored.
    static func apply(_ parameters: [CameraProperty: Float], to camera: SwiftGLTF.Camera) -> SwiftGLTF.Camera {
        guard !parameters.isEmpty else {
            return camera
        }
        var perspective = camera.perspective
        if let old = perspective {
            var (aspectRatio, yfov, zfar, znear) = (old.aspectRatio, old.yfov, old.zfar, old.znear)
            for (property, value) in parameters {
                switch property {
                case .perspectiveAspectRatio: aspectRatio = value
                case .perspectiveYfov: yfov = value
                case .perspectiveZfar: zfar = value
                case .perspectiveZnear: znear = value
                default: break
                }
            }
            perspective = .init(aspectRatio: aspectRatio, yfov: yfov, zfar: zfar, znear: znear, extensions: old.extensions, extras: old.extras)
        }
        var orthographic = camera.orthographic
        if let old = orthographic {
            var (xmag, ymag, zfar, znear) = (old.xmag, old.ymag, old.zfar, old.znear)
            for (property, value) in parameters {
                switch property {
                case .orthographicXmag: xmag = value
                case .orthographicYmag: ymag = value
                case .orthographicZfar: zfar = value
                case .orthographicZnear: znear = value
                default: break
                }
            }
            orthographic = .init(xmag: xmag, ymag: ymag, zfar: zfar, znear: znear, extensions: old.extensions, extras: old.extras)
        }
        return SwiftGLTF.Camera(type: camera.type, perspective: perspective, orthographic: orthographic, name: camera.name, extensions: camera.extensions, extras: camera.extras)
    }

    /// `camera` with ``PBRPose/cameraParameters`` applied (keyed by ``CameraProperty`` raw values).
    static func apply(_ parameters: [String: Float], to camera: SwiftGLTF.Camera) -> SwiftGLTF.Camera {
        apply(Dictionary(uniqueKeysWithValues: parameters.compactMap { key, value in CameraProperty(rawValue: key).map { ($0, value) } }), to: camera)
    }

    // MARK: Materials

    /// A material property target: its path below `/materials/N/` (its identity) and the parsed property that applies
    /// its value.
    public struct MaterialPointer: Sendable, Hashable, CustomStringConvertible {
        public let path: String
        public let property: MaterialProperty

        public init?(_ path: String) {
            guard let property = MaterialProperty(path) else { return nil }
            self.path = path
            self.property = property
        }

        public var description: String { path }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.path == rhs.path }

        public func hash(into hasher: inout Hasher) { hasher.combine(path) }
    }

    /// A property below `/materials/N/`: a factor in the uniforms, or a KHR_texture_transform component of a texture.
    public enum MaterialProperty: Sendable {
        case factor(Factor)
        /// `texturePath` is the texture's path below `/materials/N/`, as in ``GLTFMaterialTextureSlot/pointerPaths``.
        case textureTransform(texturePath: String, component: TextureTransformComponent)

        /// Reads and writes one factor in the uniforms as a flat `[Float]`.
        public struct Factor: Sendable {
            public var get: @Sendable (PBRMaterialUniforms) -> [Float]
            public var set: @Sendable (inout PBRMaterialUniforms, [Float]) -> Void

            @preconcurrency
            public init(get: @escaping @Sendable (PBRMaterialUniforms) -> [Float], set: @escaping @Sendable (inout PBRMaterialUniforms, [Float]) -> Void) {
                self.get = get
                self.set = set
            }
        }

        public enum TextureTransformComponent: String, CaseIterable, Sendable {
            case offset
            case rotation
            case scale
        }

        /// `property` is the pointer below `/materials/N/`.
        public init?(_ property: String) {
            if let factor = GLTFMaterialFeature.animatableFactors[property] {
                self = .factor(factor)
                return
            }
            for component in TextureTransformComponent.allCases {
                let suffix = "/extensions/KHR_texture_transform/\(component.rawValue)"
                let texturePath = String(property.dropLast(suffix.count))
                if property.hasSuffix(suffix), GLTFMaterialTextureSlot.byPointerPath[texturePath] != nil {
                    self = .textureTransform(texturePath: texturePath, component: component)
                    return
                }
            }
            return nil
        }
    }
}
