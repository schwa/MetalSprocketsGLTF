import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd

extension PBRMaterial {
    /// A material's uniforms during posing, with the texture transforms its channels have touched.
    public struct AnimatedState {
        public var uniforms: PBRMaterialUniforms
        var textureTransforms: [String: TextureTransform]

        /// Applies a KHR_animation_pointer value for a property below `/materials/N/`.
        public mutating func apply(_ property: GLTFAnimationPointer.MaterialProperty, value: [Float]) {
            switch property {
            case .factor(let factor):
                factor.set(&uniforms, value)

            case let .textureTransform(texturePath, component):
                guard var transform = textureTransforms[texturePath] else { return }
                switch component {
                case .offset where value.count == 2: transform.offset = SIMD2(value[0], value[1])
                case .rotation where value.count == 1: transform.rotation = value[0]
                case .scale where value.count == 2: transform.scale = SIMD2(value[0], value[1])
                default: return
                }
                textureTransforms[texturePath] = transform
                uniforms[keyPath: transform.slot].transform = transform.matrix
            }
        }

        /// The current value of a property below `/materials/N/`, in the shape ``apply(_:value:)`` takes. Nil for a
        /// texture transform of a texture this material lacks.
        public func value(of property: GLTFAnimationPointer.MaterialProperty) -> [Float]? {
            switch property {
            case .factor(let factor):
                return factor.get(uniforms)

            case let .textureTransform(texturePath, component):
                guard let transform = textureTransforms[texturePath] else { return nil }
                switch component {
                case .offset: return [transform.offset.x, transform.offset.y]
                case .rotation: return [transform.rotation]
                case .scale: return [transform.scale.x, transform.scale.y]
                }
            }
        }
    }

    public func animatedState() -> AnimatedState {
        AnimatedState(uniforms: uniforms, textureTransforms: textureTransforms)
    }
}
