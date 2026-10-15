import Foundation
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

// KHR_animation_pointer: which JSON pointers this renderer can animate, and how each animated value is applied.
// Every supported property is listed once here, so parsing a pointer and applying its value cannot disagree.

public enum GLTFAnimationPointer {
    typealias Target = GLTFAnimationClip.Target

    /// Parses a JSON pointer into a node, material, visibility, light or camera target; nil when unsupported.
    static func target(_ pointer: String) -> Target? {
        let parts = pointer.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 5, parts[0] == "extensions", parts[1] == "KHR_lights_punctual", parts[2] == "lights", let index = Int(parts[3]) {
            let property = parts.dropFirst(4).joined(separator: "/")
            return lightSetters[property] != nil ? .light(index, property) : nil
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
            return MaterialProperty(property) != nil ? .material(index, property) : nil

        case "cameras":
            return cameraProperties.contains(property) ? .camera(index, property) : nil

        default:
            return nil
        }
    }

    // MARK: Lights

    /// Properties below `/extensions/KHR_lights_punctual/lights/N/`.
    static let lightSetters: [String: @Sendable (inout PBRLight, [Float]) -> Void] = [
        "color": { if $1.count == 3 { $0.color = SIMD3($1[0], $1[1], $1[2]) } },
        "intensity": { if let value = $1.first { $0.intensity = value } },
        "range": { if let value = $1.first { $0.range = value } },
        "spot/innerConeAngle": { if let value = $1.first { $0.innerConeCos = cos(value) } },
        "spot/outerConeAngle": { if let value = $1.first { $0.outerConeCos = cos(value) } }
    ]

    static func apply(_ properties: [String: [Float]], to light: inout PBRLight) {
        for (property, value) in properties {
            lightSetters[property]?(&light, value)
        }
    }

    // MARK: Cameras

    /// Properties below `/cameras/N/`, each `group/name` in the camera's JSON.
    static let cameraProperties: Set<String> = [
        "perspective/yfov", "perspective/znear", "perspective/zfar", "perspective/aspectRatio",
        "orthographic/xmag", "orthographic/ymag", "orthographic/znear", "orthographic/zfar"
    ]

    /// `camera` with animated properties applied. Properties of a projection the camera lacks are ignored.
    static func apply(_ parameters: [String: Float], to camera: SwiftGLTF.Camera) -> SwiftGLTF.Camera {
        guard !parameters.isEmpty else {
            return camera
        }
        var perspective = camera.perspective
        if let old = perspective {
            var (aspectRatio, yfov, zfar, znear) = (old.aspectRatio, old.yfov, old.zfar, old.znear)
            for (property, value) in parameters {
                switch property {
                case "perspective/aspectRatio": aspectRatio = value
                case "perspective/yfov": yfov = value
                case "perspective/zfar": zfar = value
                case "perspective/znear": znear = value
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
                case "orthographic/xmag": xmag = value
                case "orthographic/ymag": ymag = value
                case "orthographic/zfar": zfar = value
                case "orthographic/znear": znear = value
                default: break
                }
            }
            orthographic = .init(xmag: xmag, ymag: ymag, zfar: zfar, znear: znear, extensions: old.extensions, extras: old.extras)
        }
        return SwiftGLTF.Camera(type: camera.type, perspective: perspective, orthographic: orthographic, name: camera.name, extensions: camera.extensions, extras: camera.extras)
    }

    // MARK: Materials

    /// A property below `/materials/N/`: a factor in the uniforms, or a KHR_texture_transform component of a texture.
    public enum MaterialProperty: Sendable {
        case factor(@Sendable (inout PBRMaterialUniforms, [Float]) -> Void)
        /// `texturePath` is the texture's path below `/materials/N/`, as in ``GLTFMaterialTextureSlot/pointerPaths``.
        case textureTransform(texturePath: String, component: TextureTransformComponent)

        public enum TextureTransformComponent: String, CaseIterable, Sendable {
            case offset
            case rotation
            case scale
        }

        /// `property` is the pointer below `/materials/N/`, as in ``GLTFAnimationClip/Target/material(_:_:)``.
        public init?(_ property: String) {
            if let setter = GLTFMaterialFeature.animatableFactors[property] {
                self = .factor(setter)
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
