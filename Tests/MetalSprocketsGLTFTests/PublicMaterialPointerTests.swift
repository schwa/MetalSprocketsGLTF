import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

// No @testable: callers outside the module (e.g. MetalSprocketsSceneGraph) must be able to do this.
@Suite(.requiresMetal4)
struct PublicMaterialPointerTests {
    @Test func appliesMaterialPointerValues() throws {
        let asset = try GLTFAsset(url: makePointerAnimatedFile())
        var state = try #require(asset.materials.first).animatedState()

        let factor = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/baseColorFactor"))
        state.apply(factor, value: [0, 1, 0, 1])
        #expect(state.uniforms.baseColorFactor == [0, 1, 0, 1])

        let offset = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/offset"))
        state.apply(offset, value: [0.5, 0])
        #expect(state.uniforms.baseColor.transform.columns.0.x == 2)
        #expect(simd_distance(state.uniforms.baseColor.transform.columns.2, [0.5, 0, 1]) < 1e-5)

        #expect(GLTFAnimationPointer.MaterialProperty("name") == nil)
    }

    @Test func readsMaterialPointerValues() throws {
        let asset = try GLTFAsset(url: makePointerAnimatedFile())
        var state = try #require(asset.materials.first).animatedState()

        let factor = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/baseColorFactor"))
        state.apply(factor, value: [0.25, 0.5, 0.75, 1])
        #expect(state.value(of: factor) == [0.25, 0.5, 0.75, 1])

        let roughness = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/roughnessFactor"))
        state.apply(roughness, value: [0.3])
        #expect(state.value(of: roughness) == [0.3])

        let emissive = try #require(GLTFAnimationPointer.MaterialProperty("emissiveFactor"))
        state.apply(emissive, value: [1, 2, 3])
        #expect(state.value(of: emissive) == [1, 2, 3])

        let offset = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/offset"))
        state.apply(offset, value: [0.5, 0.25])
        #expect(state.value(of: offset) == [0.5, 0.25])

        let rotation = try #require(GLTFAnimationPointer.MaterialProperty("pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/rotation"))
        state.apply(rotation, value: [1.5])
        #expect(state.value(of: rotation) == [1.5])

        let missing = try #require(GLTFAnimationPointer.MaterialProperty("emissiveTexture/extensions/KHR_texture_transform/scale"))
        #expect(state.value(of: missing) == nil)
    }
}
