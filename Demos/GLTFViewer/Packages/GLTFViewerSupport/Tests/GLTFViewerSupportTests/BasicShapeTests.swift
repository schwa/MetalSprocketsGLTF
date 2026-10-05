import Foundation
@testable import GLTFViewerSupport
import MetalSprocketsGLTF
import MetalSprocketsGLTFMeshopt
import simd
import Testing

// Every shape fits in -0.5...0.5, has unit normals pointing away from its centre line, and front faces whose
// winding agrees with their normals.
@Test(arguments: BasicShape.allCases)
func shapeGeometryIsConsistent(_ shape: BasicShape) {
    let mesh = shape.mesh
    #expect(!mesh.indices.isEmpty && mesh.indices.count % 3 == 0)
    #expect(mesh.positions.allSatisfy { simd_reduce_max(simd_abs($0)) <= 0.5 + 1e-5 })
    #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
    for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
        let corners = (0 ..< 3).map { Int(mesh.indices[triangle + $0]) }
        let a = mesh.positions[corners[0]], b = mesh.positions[corners[1]], c = mesh.positions[corners[2]]
        let faceNormal = simd_cross(b - a, c - a)
        // Degenerate triangles (at poles and apexes) have no direction to check.
        guard simd_length(faceNormal) > 1e-7 else { continue }
        let vertexNormal = mesh.normals[corners[0]] + mesh.normals[corners[1]] + mesh.normals[corners[2]]
        #expect(simd_dot(faceNormal, vertexNormal) > 0, "\(shape) triangle \(triangle / 3) winds against its normals")
    }
}

// The bundled, packed .glb of every shape loads (it is quantized and meshopt-compressed) without warnings.
@Test(arguments: BasicShape.allCases)
func bundledShapeLoads(_ shape: BasicShape) throws {
    let url = try #require(shape.fileURL, "Missing bundled \(shape.name).glb; run `just basic-shapes`")
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()]))
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
    #expect(asset.statistics.triangles == shape.mesh.indices.count / 3)
    // Packing keeps the texture coordinates (gltfpack -kv) at their real scale (-vt 16): they span 0...1, not
    // 0...1/16 as 12-bit quantization leaves them without a texture transform to undo it.
    let document = asset.container.document
    let primitive = try #require(document.meshes.first?.primitives.first)
    let texCoordIndex = try #require(primitive.attributes[.TEXCOORD_0], "\(shape.name).glb lost TEXCOORD_0")
    let texCoords = try asset.container.floatComponents(for: texCoordIndex.resolve(in: document))
    #expect(abs((texCoords.max() ?? 0) - 1) < 0.001, "\(shape.name) UVs reach \(texCoords.max() ?? 0)")
}

// Writes the unpacked shapes for `just basic-shapes` when WRITE_BASIC_SHAPES names a directory.
@Test(.enabled(if: ProcessInfo.processInfo.environment["WRITE_BASIC_SHAPES"] != nil))
func writeBasicShapes() throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["WRITE_BASIC_SHAPES"]))
    for shape in BasicShape.allCases {
        try shape.mesh.glb(name: shape.name).write(to: directory.appending(path: "\(shape.name).glb"))
    }
}
