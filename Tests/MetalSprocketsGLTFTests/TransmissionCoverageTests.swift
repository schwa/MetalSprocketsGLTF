import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

@Suite(.metalValidation)
struct TransmissionCoverageTests {
    let size = 32
    let device = MTLCreateSystemDefaultDevice()!
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 3, aspectRatio: 1, near: 0.1, far: 20)

    /// Clear glass at z 1 and, optionally, a red quad behind it at z 0.
    func model(withRedBehind: Bool) throws -> PBRModel {
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.addQuad()
        let quad = try geometry.build()[0]
        var glassUniforms = PBRMaterialUniforms.defaults(baseColor: [1, 1, 1, 1], metallic: 0, roughness: 0)
        glassUniforms.transmissionFactor = 1
        let glass = try PBRMaterial(uniforms: glassUniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: [simd_float4x4(translation: [0, 0, 1]), simd_float4x4(translation: .zero)]))
        builder.addInstance(quad, material: glass, node: 0)
        if withRedBehind {
            // Emissive, so it is red whatever the (blue) environment.
            var redUniforms = PBRMaterialUniforms.defaults(baseColor: [1, 0, 0, 1], metallic: 0, roughness: 1)
            redUniforms.emissiveFactor = [1, 0, 0]
            let red = try PBRMaterial(uniforms: redUniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
            builder.addInstance(quad, material: red, node: 1)
        }
        return try builder.build()
    }

    /// The center pixel (RGBA bytes) over a transparent clear, in stereo (one view, so coverage applies) or mono.
    func center(_ model: PBRModel, stereo: Bool) throws -> SIMD4<Int> {
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([0, 0, 1]), specularSize: 16, irradianceSize: 4))
        var renderer = PBRRenderer(model: model, viewMatrix: view, projectionMatrix: projection, lighting: lighting)
        if stereo {
            renderer.stereo = PBRStereoViews(viewMatrices: [view], projectionMatrices: [projection], viewports: [MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)])
        }
        let offscreen = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0)
        offscreen.renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let texture = try offscreen.render(try RenderPass { renderer }).texture
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: size * 4, from: MTLRegionMake2D(size / 2, size / 2, 1, 1), mipmapLevel: 0)
        return SIMD4(Int(pixel[2]), Int(pixel[1]), Int(pixel[0]), Int(pixel[3]))
    }

    // In stereo, glass blends over what is behind it: the model's own red quad shows through.
    @Test func stereoGlassShowsGeometryBehind() throws {
        let pixel = try center(model(withRedBehind: true), stereo: true)
        #expect(pixel.x > pixel.z + 80, "Expected red through the glass, got \(pixel)")
    }

    // Over nothing, stereo glass leaves the target mostly transparent, so passthrough shows.
    @Test func stereoGlassOverNothingIsMostlyTransparent() throws {
        let pixel = try center(model(withRedBehind: false), stereo: true)
        #expect(pixel.w < 100, "Expected low coverage, got \(pixel)")
    }

    // In mono, without a transmission target, glass refracts the (blue) environment and is opaque.
    @Test func monoGlassStillRefractsTheEnvironment() throws {
        let pixel = try center(model(withRedBehind: true), stereo: false)
        #expect(pixel.z > pixel.x && pixel.w == 255, "Expected the blue environment, got \(pixel)")
    }
}
