import Metal
@testable import MetalSprocketsPBR
import simd
import Testing

@Suite(.requiresMetal4)
struct CubeEnvironmentTests {
    let values: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
    let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]

    /// A 4 x 4 rgba16Float cube with one gray value per face, +X -X +Y -Y +Z -Z.
    func cube(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: 4, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        for (face, value) in values.enumerated() {
            let pixels = [Float16](repeating: Float16(value), count: 16 * 4)
            texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, slice: face, withBytes: pixels, bytesPerRow: 32, bytesPerImage: 128)
        }
        return texture
    }

    /// The source texel an equirectangular direction maps to (as the shaders' equirectUV).
    func sourceTexel(_ environment: PBREnvironment, _ direction: SIMD3<Float>) -> SIMD4<Float> {
        let source = environment.source
        let u = atan2(direction.z, direction.x) / (2 * .pi) + 0.5
        let v = 0.5 - asin(direction.y) / .pi
        let x = min(Int(u * Float(source.width)), source.width - 1)
        let y = min(Int(v * Float(source.height)), source.height - 1)
        var pixel = [Float16](repeating: 0, count: 4)
        source.getBytes(&pixel, bytesPerRow: 8, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return SIMD4(pixel.map(Float.init))
    }

    // Each face lands on its axis in the equirectangular source, scaled and color-converted.
    @Test func cubeFacesLandOnTheirAxes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let environment = try PBREnvironment(cube: cube(device: device), scale: 2, device: device, specularSize: 16, irradianceSize: 4)
        #expect(environment.source.width == 16 && environment.source.height == 8)
        for (axis, value) in zip(axes, values) {
            #expect(abs(sourceTexel(environment, axis).x - 2 * value) < 0.01, "\(axis)")
        }
        // Display P3 gray stays gray in sRGB: the conversion's rows each sum to 1.
        let converted = try PBREnvironment(cube: cube(device: device), colorMatrix: PBREnvironment.displayP3ToLinearSRGB, device: device, specularSize: 16, irradianceSize: 4)
        let texel = sourceTexel(converted, [1, 0, 0])
        #expect(abs(texel.x - 0.1) < 0.005 && abs(texel.y - 0.1) < 0.005 && abs(texel.z - 0.1) < 0.005)
    }
}
