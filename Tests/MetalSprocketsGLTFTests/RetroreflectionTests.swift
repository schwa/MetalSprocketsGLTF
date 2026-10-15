import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

@Suite(.requiresMetal4, .metalValidation)
struct RetroreflectionTests {
    let size = 32
    let device = MTLCreateSystemDefaultDevice()!

    /// The center brightness of a gray quad (facing +Z) seen at 50° off its normal, lit only by a point light at the
    /// camera: regular specular reflects that light away from the camera; retroreflection returns it.
    func centerBrightness(retroreflection: Float) throws -> Int {
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.addQuad()
        let quad = try geometry.build()[0]
        var uniforms = PBRMaterialUniforms.defaults(baseColor: [0.2, 0.2, 0.2, 1], metallic: 0, roughness: 0.3)
        uniforms.specularColorFactor = [4, 4, 4]
        uniforms.retroreflectionFactor = retroreflection
        let material = try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: [matrix_identity_float4x4]))
        builder.addInstance(quad, material: material, node: 0)
        let model = try builder.build()

        let angle: Float = 50 * .pi / 180
        let eye = SIMD3<Float>(0, sin(angle), cos(angle)) * 2
        let lighting = PBRLighting(lights: [.point(position: eye, intensity: 8)], environmentIntensity: 0)
        let view = LookAt(position: eye, target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 6), depthMode: .reversed(zClip: 0.1 ... 10)).projectionMatrix(aspectRatio: 1)
        let image = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(
            PBRScene(model: model, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: size, height: size))
        ).cgImage
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let index = (size / 2 * size + size / 2) * 4
        return Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
    }

    // With the light at the camera, a retroreflective surface returns much more light than a regular one.
    @Test func retroreflectionReturnsLightToItsSource() throws {
        let regular = try centerBrightness(retroreflection: 0)
        let retro = try centerBrightness(retroreflection: 1)
        #expect(retro > regular + 150, "regular \(regular), retroreflective \(retro)")
    }

    // The glTF extension sets the factor and the masking texture (TrafficCone's reflective bands).
    @Test(.enabled(if: SampleAssets.isAvailable)) func loadsTrafficConeRetroreflection() throws {
        let asset = try GLTFAsset(url: SampleAssets.modelsDirectory.appending(path: "TrafficCone/glTF-Binary/TrafficCone.glb"))
        #expect(asset.warnings.isEmpty, "\(asset.warnings)")
        let retro = try #require(asset.materials.first { $0.name == "ConeMatRetro" })
        #expect(retro.uniforms.retroreflectionFactor == 1)
        #expect(retro.uniforms.retroreflection.enabled == 1)
        #expect(asset.materials.filter { $0.uniforms.retroreflectionFactor > 0 }.count == 1)
    }
}
