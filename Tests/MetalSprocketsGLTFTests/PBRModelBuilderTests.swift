import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftMesh
import Testing

extension PBRGeometryBuilder {
    /// Adds a unit quad in the XY plane, facing +Z.
    @discardableResult
    mutating func addQuad() throws -> Int {
        let corners: [SIMD2<Float>] = [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]]
        return try add(
            attributes: [
                .positions(corners.map { SIMD3($0, 0) }),
                .normals(Array(repeating: [0, 0, 1], count: 4)),
                .textureCoordinates(corners.map { $0 + 0.5 })
            ],
            indices: [0, 1, 2, 0, 2, 3],
            label: "Quad"
        )
    }
}

func makeColorMaterial(_ color: SIMD4<Float>, device: MTLDevice) throws -> PBRMaterial {
    var uniforms = PBRMaterialUniforms.defaults(baseColor: color, metallic: 0, roughness: 0.5)
    if color.w < 1 {
        uniforms.alphaMode = .blend
    }
    return try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
}

struct PBRModelBuilderTests {
    // The PBR defaults are exactly what a glTF material without any properties loads as.
    @Test func defaultUniformsMatchGLTF() throws {
        // The material a glTF primitive without one gets.
        let loaded = try GLTFAsset(url: makeTriangleFile()).resources.defaultMaterial.uniforms
        // Field by field: padding bytes need not match.
        let fields = { (uniforms: PBRMaterialUniforms) in Mirror(reflecting: uniforms).children.map { "\($0.label ?? "?") = \($0.value)" } }
        let expected = fields(PBRMaterialUniforms.defaults())
        let actual = fields(loaded)
        #expect(expected.count > 40)
        for (expectedField, actualField) in zip(expected, actual) {
            #expect(expectedField == actualField)
        }
    }

    // Each primitive's mesh is a view into the shared buffers: the second quad sits after the first, with no copies.
    @Test func primitiveMeshesViewSharedBuffers() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.addQuad()
        try geometry.addQuad()
        let primitives = try geometry.build()
        let first = primitives[0].mesh
        let second = primitives[1].mesh
        #expect(first.vertexBuffers[0] === primitives[0].geometry.vertexBuffer)
        #expect(second.vertexBuffers[0] === first.vertexBuffers[0])
        #expect(second.submeshes[0].indexBuffer === first.submeshes[0].indexBuffer)
        #expect(second.vertexBufferOffsets[0] == 4 * MemoryLayout<PBRVertex>.stride)
        #expect(second.submeshes[0].indexBufferOffset == 6 * MemoryLayout<UInt32>.stride)
        #expect(primitives[1].baseVertex == 4)
        #expect(primitives[1].indexStart == 6)
        #expect(second.vertexCount == 4)
        #expect(second.submeshes[0].indexCount == 6)
        #expect(second.vertexDescriptor == PBRModel.meshVertexDescriptor)
        #expect(second.vertexDescriptor.attributes.map(\.semantic) == [.position, .normal, .tangent, .texcoord(0), .texcoord(1), .color(0)])
        #expect(second.bounds?.min == [-0.5, -0.5, 0])
        #expect(second.bounds?.max == [0.5, 0.5, 0])
    }

    // A MetalMesh goes in as one primitive per submesh, each with only the vertices it uses, its own primitive type,
    // and the mesh's morph targets for those vertices.
    @Test func addsMetalMeshSubmeshes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [5, 5, 5], [6, 5, 5]]
        var mesh = MetalMesh(
            device: device,
            attributes: [.positions(positions), .normals(Array(repeating: [0, 0, 1], count: 5))],
            submeshes: [.init(label: "tri", indices: [0, 1, 2]), .init(label: "line", indices: [3, 4], primitiveType: .line)],
            label: "Mixed"
        )
        mesh.morphTargets = MetalMesh.MorphTargets(targets: [.init(positionOffsets: positions.map { $0 * 0 + [0, 0, 1] })], defaultWeights: [0.5])
        var geometry = PBRGeometryBuilder(device: device)
        let indices = try geometry.add(mesh)
        let primitives = try geometry.build()
        let triangle = primitives[indices[0]]
        let line = primitives[indices[1]]
        #expect(triangle.vertexCount == 3 && triangle.indexCount == 3 && triangle.primitiveType == .triangle)
        #expect(line.vertexCount == 2 && line.indexCount == 2 && line.primitiveType == .line)
        #expect(triangle.hasNormals && !triangle.hasTangents)
        // Bounds grow by the morph target (weights in 0...1).
        #expect(line.bounds == PBRBounds(min: [5, 5, 5], max: [6, 5, 6]))
        #expect(line.morphTargetCount == 1)
        #expect(line.mesh.morphTargets?.targets.first?.positionOffsets?.count == 2)
        #expect(line.mesh.morphTargets?.defaultWeights == [0.5])
        #expect(line.mesh.label == "line")
    }

    // Two nodes placing the same quad with the same material share one instanced batch; bounds follow the nodes.
    @Test func buildsAModelWithoutGLTF() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var geometry = PBRGeometryBuilder(device: device)
        let quadIndex = try geometry.addQuad()
        let quad = try geometry.build()[quadIndex]
        #expect(quad.bounds == PBRBounds(min: [-0.5, -0.5, 0], max: [0.5, 0.5, 0]))

        let red = try makeColorMaterial([1, 0, 0, 1], device: device)
        let glass = try makeColorMaterial([1, 1, 1, 0.5], device: device)
        let pose = PBRPose(worldMatrices: [
            simd_float4x4(translation: [-1, 0, 0]),
            simd_float4x4(translation: [1, 0, 0]),
            simd_float4x4(translation: [0, 2, 0])
        ])
        var builder = PBRModelBuilder(device: device, restPose: pose)
        builder.addInstance(quad, material: red, node: 0)
        builder.addInstance(quad, material: red, node: 1)
        builder.addInstance(quad, material: glass, node: 2)
        let model = try builder.build()

        #expect(model.opaqueBatches.count == 1)
        #expect(model.opaqueBatches.first?.instanceCount == 2)
        #expect(model.blendedBatches.count == 1)
        #expect(model.bounds == PBRBounds(min: [-1.5, -0.5, 0], max: [1.5, 2.5, 0]))
        // Moving a node in a pose moves its instances' bounds.
        var moved = pose
        moved.worldMatrices[2] = simd_float4x4(translation: [0, 5, 0])
        #expect(model.bounds(for: moved).max.y == 5.5)
    }

    // A model built in code renders with PBRScene: a red quad, lit by a white environment, fills the center.
    @Test func rendersAModelWithoutGLTF() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.addQuad()
        let quad = try geometry.build()[0]
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: [matrix_identity_float4x4]))
        builder.addInstance(quad, material: try makeColorMaterial([1, 0, 0, 1], device: device), node: 0)
        let model = try builder.build()

        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 16, irradianceSize: 4))
        let view = simd_float4x4.lookAt(eye: [0, 0, 2], target: .zero, up: [0, 1, 0])
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
        let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(
            PBRScene(model: model, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 32, height: 32))
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let center = (16 * 32 + 16) * 4
        let pixel = (red: Int(pixels[center]), green: Int(pixels[center + 1]), blue: Int(pixels[center + 2]))
        #expect(pixel.red > 100 && pixel.green < 40 && pixel.blue < 40, "Expected the red quad, got \(pixel)")
    }
}

extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
