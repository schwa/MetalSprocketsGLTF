import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

@Suite(.requiresMetal4, .metalValidation)
struct MultiModelSceneTests {
    let size = 64
    let device = MTLCreateSystemDefaultDevice()!
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 3, aspectRatio: 1, near: 0.1, far: 20)

    var lighting: PBRLighting {
        get throws {
            PBRLighting(environment: try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 16, irradianceSize: 4))
        }
    }

    /// A model of one quad per material, each placed by its own node at the given translation.
    func model(_ quads: [(material: PBRMaterial, at: SIMD3<Float>)]) throws -> PBRModel {
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.addQuad()
        let quad = try geometry.build()[0]
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: quads.map { simd_float4x4(translation: $0.at) }))
        for (node, entry) in quads.enumerated() {
            builder.addInstance(quad, material: entry.material, node: node)
        }
        return try builder.build()
    }

    func render(_ scene: PBRScene) throws -> [UInt8] {
        let image = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(scene).cgImage
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pixels, count: size * size * 4))
    }

    func scene(_ items: [PBRScene.Item]) throws -> PBRScene {
        PBRScene(items: items, viewMatrix: view, projectionMatrix: projection, lighting: try lighting, viewportSize: CGSize(width: size, height: size))
    }

    func center(_ pixels: [UInt8]) -> SIMD3<Int> {
        let index = (size / 2 * size + size / 2) * 4
        return SIMD3(Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }

    // Two models side by side render as each does alone, in its own half of the image.
    @Test func modelsKeepTheirPlacement() throws {
        let red = try model([(try makeColorMaterial([1, 0, 0, 1], device: device), [0, 0, 0])])
        let blue = try model([(try makeColorMaterial([0, 0, 1, 1], device: device), [0, 0, 0])])
        let left = simd_float4x4(translation: [-0.8, 0, 0])
        let right = simd_float4x4(translation: [0.8, 0, 0])
        let both = try render(scene([.init(model: red, modelMatrix: left), .init(model: blue, modelMatrix: right)]))
        let redAlone = try render(scene([.init(model: red, modelMatrix: left)]))
        let blueAlone = try render(scene([.init(model: blue, modelMatrix: right)]))
        let rowBytes = size * 4
        for row in 0 ..< size {
            let leftHalf = row * rowBytes ..< row * rowBytes + rowBytes / 2
            let rightHalf = row * rowBytes + rowBytes / 2 ..< (row + 1) * rowBytes
            #expect(both[leftHalf] == redAlone[leftHalf], "row \(row), left")
            #expect(both[rightHalf] == blueAlone[rightHalf], "row \(row), right")
        }
    }

    // Blended surfaces of different models are sorted together: listing the near model first still draws it last.
    @Test func blendedSurfacesSortAcrossModels() throws {
        let farRed = try makeColorMaterial([1, 0, 0, 0.5], device: device)
        let nearBlue = try makeColorMaterial([0, 0, 1, 0.5], device: device)
        let near = try model([(nearBlue, [0, 0, 1])])
        let far = try model([(farRed, [0, 0, 0])])
        let oneModel = try model([(farRed, [0, 0, 0]), (nearBlue, [0, 0, 1])])
        let expected = center(try render(scene([.init(model: oneModel)])))
        let nearFirst = center(try render(scene([.init(model: near), .init(model: far)])))
        #expect(nearFirst == expected)
        // Blue on top: more blue than red.
        #expect(expected.z > expected.x)
    }

    // Glass in one model shows an opaque surface of another behind it.
    @Test func glassSeesOtherModels() throws {
        let red = try model([(try makeColorMaterial([1, 0, 0, 1], device: device), [0, 0, 0])])
        var glassUniforms = try makeColorMaterial([1, 1, 1, 1], device: device).uniforms
        glassUniforms.transmissionFactor = 1
        glassUniforms.roughnessFactor = 0
        let glassMaterial = try PBRMaterial(uniforms: glassUniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
        let glass = try model([(glassMaterial, [0, 0, 1])])
        let pixel = center(try render(scene([.init(model: glass), .init(model: red)])))
        #expect(pixel.x > pixel.z + 80, "Expected the red quad through the glass, got \(pixel)")
    }
}
