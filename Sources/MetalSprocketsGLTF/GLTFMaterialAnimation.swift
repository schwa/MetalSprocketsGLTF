import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd

extension PBRMaterial {
    /// A material's uniforms during posing, with the texture transforms its channels have touched.
    struct AnimatedState {
        var uniforms: PBRMaterialUniforms
        var textureTransforms: [String: TextureTransform]

        /// Applies a KHR_animation_pointer value for a property below `/materials/N/`.
        mutating func apply(_ property: GLTFAnimationPointer.MaterialProperty, value: [Float]) {
            switch property {
            case .factor(let setter):
                setter(&uniforms, value)
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
    }

    func animatedState() -> AnimatedState {
        AnimatedState(uniforms: uniforms, textureTransforms: textureTransforms)
    }
}
