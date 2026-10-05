@testable import MetalSprocketsGLTF
import simd
import Testing

// Quad in the xy plane facing +z, as two triangles sharing the 0-2 diagonal.
private let quadPositions: [SIMD3<Float>] = [[-1, -1, 0], [1, -1, 0], [1, 1, 0], [-1, 1, 0]]
private let quadNormals = [SIMD3<Float>](repeating: [0, 0, 1], count: 4)
private let quadIndices: [UInt32] = [0, 1, 2, 0, 2, 3]

private func isClose(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> Bool {
    simd_length(lhs - rhs) < 1e-4
}

// u along +x, v along +y: tangent +x, bitangent +y, so w = +1, on every corner.
@Test func tangentsFollowTheUDirection() {
    let texCoords: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
    let tangents = GLTFTangents.cornerTangents(positions: quadPositions, normals: quadNormals, texCoords: texCoords, indices: quadIndices)
    #expect(tangents.allSatisfy { isClose($0, [1, 0, 0, 1]) }, "\(tangents)")
}

// u mirrored (along -x): tangent -x; the bitangent stays +y, so the sign flips to -1.
@Test func mirroredTexCoordsFlipTheTangentAndSign() {
    let texCoords: [SIMD2<Float>] = [[1, 0], [0, 0], [0, 1], [1, 1]]
    let tangents = GLTFTangents.cornerTangents(positions: quadPositions, normals: quadNormals, texCoords: texCoords, indices: quadIndices)
    #expect(tangents.allSatisfy { isClose($0, [-1, 0, 0, -1]) }, "\(tangents)")
}

// Corners of one vertex with equal tangents stay one vertex; differing tangents split it.
@Test func weldingSplitsOnlyDifferingTangents() {
    let shared = GLTFTangents.weld(cornerTangents: Array(repeating: [1, 0, 0, 1], count: 6), indices: quadIndices)
    #expect(shared.sources == [0, 1, 2, 3])
    #expect(shared.indices == quadIndices)

    let seam: [SIMD4<Float>] = [[1, 0, 0, 1], [1, 0, 0, 1], [1, 0, 0, 1], [-1, 0, 0, -1], [-1, 0, 0, -1], [-1, 0, 0, -1]]
    let split = GLTFTangents.weld(cornerTangents: seam, indices: quadIndices)
    #expect(split.sources == [0, 1, 2, 0, 2, 3])
    #expect(split.indices == [0, 1, 2, 3, 4, 5])
}
