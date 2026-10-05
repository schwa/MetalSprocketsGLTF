import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

@Suite(.metalValidation)
struct EnvironmentTests {
    /// Every texel of every face of `texture` at `level`, as RGBA.
    func cubeTexels(_ texture: MTLTexture, level: Int) -> [SIMD4<Float>] {
        let size = max(texture.width >> level, 1)
        var result: [SIMD4<Float>] = []
        for face in 0 ..< 6 {
            var halves = [Float16](repeating: 0, count: size * size * 4)
            texture.getBytes(&halves, bytesPerRow: size * 8, bytesPerImage: size * size * 8, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: level, slice: face)
            for index in 0 ..< size * size {
                result.append(SIMD4(Float(halves[index * 4]), Float(halves[index * 4 + 1]), Float(halves[index * 4 + 2]), Float(halves[index * 4 + 3])))
            }
        }
        return result
    }

    // A uniform environment must prefilter back to the same radiance; this checks the normalization of both maps.
    @Test func uniformEnvironmentPrefiltersToItself() throws {
        let color = SIMD3<Float>(0.25, 0.5, 1.0)
        let environment = try PBREnvironment(source: .uniform(color), specularSize: 32, irradianceSize: 8)
        for texel in cubeTexels(environment.irradiance, level: 0) {
            #expect(simd_distance(SIMD3(texel.x, texel.y, texel.z), color) < 0.01)
        }
        for level in 0 ..< environment.specular.mipmapLevelCount {
            for texel in cubeTexels(environment.specular, level: level) {
                #expect(simd_distance(SIMD3(texel.x, texel.y, texel.z), color) < 0.01, "specular level \(level)")
            }
        }
    }

    @Test func brdfLookupMatchesKnownValues() throws {
        let environment = try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 8, irradianceSize: 4)
        let lookup = environment.brdfLookup
        func value(NdotV: Float, roughness: Float) -> SIMD2<Float> {
            let x = min(Int(NdotV * Float(lookup.width)), lookup.width - 1)
            let y = min(Int(roughness * Float(lookup.height)), lookup.height - 1)
            var halves = [Float16](repeating: 0, count: 2)
            lookup.getBytes(&halves, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return SIMD2(Float(halves[0]), Float(halves[1]))
        }
        // Smooth, head-on: almost all energy is reflected and scaled by F0.
        let smooth = value(NdotV: 1, roughness: 0)
        #expect(smooth.x > 0.95)
        #expect(smooth.y < 0.02)
        // Rough surfaces lose energy (single-scattering GGX).
        let rough = value(NdotV: 0.5, roughness: 1)
        #expect(rough.x + rough.y < 0.8)
        #expect(rough.x + rough.y > 0.3)
    }

    /// A camera-facing quad with the given metallic-roughness material.
    func makeQuadFile(baseColor: SIMD3<Float>, metallic: Float, roughness: Float, extensions: String = "{}") throws -> URL {
        let positions: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
        let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
        let buffer = (positions + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
        let json = """
        {
          "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "material": 0}]}],
          "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [\(baseColor.x), \(baseColor.y), \(baseColor.z), 1], "metallicFactor": \(metallic), "roughnessFactor": \(roughness)}, "extensions": \(extensions)}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3"}
          ],
          "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 72}, {"buffer": 0, "byteOffset": 72, "byteLength": 72}],
          "buffers": [{"byteLength": 144, "uri": "data:application/octet-stream;base64,\(buffer)"}]
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
        try Data(json.utf8).write(to: url)
        return url
    }

    /// Linear value of the center pixel's red channel.
    func centerLinearRed(_ asset: GLTFAsset, lighting: PBRLighting) throws -> Float {
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let encoded = Float(try #require(context.data).assumingMemoryBound(to: UInt8.self)[(16 * 32 + 16) * 4]) / 255
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    // White furnace: a white, fully rough metal under a uniform environment reflects (almost) all of it. Without
    // multiple-scattering compensation single-scattering GGX loses a large share of the energy.
    @Test func roughMetalConservesEnergy() throws {
        let asset = try GLTFAsset(url: makeQuadFile(baseColor: [1, 1, 1], metallic: 1, roughness: 1))
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([0.5, 0.5, 0.5]), specularSize: 16, irradianceSize: 4))
        // Khronos PBR Neutral maps 0.5 to 0.46 (it subtracts a 0.04 offset).
        let value = try centerLinearRed(asset, lighting: lighting)
        #expect(value > 0.42, "Rough white metal reflected \(value), expected about 0.46")
    }

    // KHR_materials_ior: a dielectric with an index of refraction of 1 has F0 = 0 and reflects nothing.
    @Test func indexOfRefractionSetsReflectance() throws {
        let asset = try GLTFAsset(url: makeQuadFile(baseColor: [0, 0, 0], metallic: 0, roughness: 0, extensions: #"{"KHR_materials_ior": {"ior": 1.0}}"#))
        #expect(asset.materials.first?.uniforms.ior == 1)
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 16, irradianceSize: 4))
        let value = try centerLinearRed(asset, lighting: lighting)
        #expect(value < 0.005, "Black dielectric with IOR 1 reflected \(value)")
    }

    // KHR_materials_specular: specularFactor 0 removes dielectric specular reflection.
    @Test func specularFactorScalesReflectance() throws {
        let asset = try GLTFAsset(url: makeQuadFile(baseColor: [0, 0, 0], metallic: 0, roughness: 0, extensions: #"{"KHR_materials_specular": {"specularFactor": 0, "specularColorFactor": [0.5, 1, 1]}}"#))
        let uniforms = try #require(asset.materials.first).uniforms
        #expect(uniforms.specularFactor == 0)
        #expect(uniforms.specularColorFactor == [0.5, 1, 1])
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 16, irradianceSize: 4))
        let value = try centerLinearRed(asset, lighting: lighting)
        #expect(value < 0.005, "Black dielectric with specularFactor 0 reflected \(value)")
    }

    @Test func studioEnvironmentBuilds() {
        let studio = PBREnvironment.studio
        #expect(studio.specular.textureType == .typeCube)
        #expect(studio.specular.mipmapLevelCount > 1)
        #expect(studio.source.width == 2048)
    }
}
