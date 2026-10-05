@testable import MetalSprocketsGLTF
import simd
import Testing

// EXT_mesh_gpu_instancing: SimpleInstancing places one cube mesh 125 times (a 5 x 5 x 5 grid) from one node.
@Test(.enabled(if: SampleAssets.isAvailable)) func gpuInstancingDrawsEveryCopy() throws {
    let url = SampleAssets.modelsDirectory.appending(path: "SimpleInstancing/glTF-Binary/SimpleInstancing.glb")
    let asset = try GLTFAsset(url: url)
    #expect(asset.opaqueInstances.count == 125)
    // Same primitive and material: one instanced batch.
    #expect(asset.opaqueBatches.map(\.instanceCount) == [125])

    // Copies are spread out, not stacked on the node.
    let positions = Set(asset.opaqueInstances.map { SIMD3<Float>($0.worldMatrix.columns.3.x, $0.worldMatrix.columns.3.y, $0.worldMatrix.columns.3.z) })
    #expect(positions.count == 125)

    // Posing (as animation does) places the copies where the rest pose does.
    let batch = try #require(asset.opaqueBatches.first)
    let posed = asset.worldBounds(of: batch, pose: asset.pose(animation: -1, time: 0))
    #expect(simd_distance(posed.min, batch.worldBounds.min) < 1e-4)
    #expect(simd_distance(posed.max, batch.worldBounds.max) < 1e-4)
}
