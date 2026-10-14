@testable import MetalSprocketsGLTF
import Testing

// An indexed quad: one node, mesh and primitive; two triangles from four stored vertices; no textures.
@Test(.requiresMetal4, .requiresMetal4) func statisticsCountAQuad() throws {
    let statistics = try GLTFAsset(url: makeIndexedQuadWithoutNormalsFile()).statistics
    #expect(statistics.version == "2.0")
    #expect(statistics.nodes == 1)
    #expect(statistics.meshes == 1)
    #expect(statistics.primitives == 1)
    #expect(statistics.instances == 1)
    #expect(statistics.triangles == 2)
    #expect(statistics.vertices == 4)
    #expect(statistics.materials == 1)
    #expect(statistics.textures == 0)
    #expect(statistics.textureBytes == 0)
    #expect(statistics.animations == 0)
}

// Instanced copies count as drawn triangles, but their vertices are stored once.
@Test(.requiresMetal4, .enabled(if: SampleAssets.isAvailable)) func statisticsCountInstancedCopies() throws {
    let asset = try GLTFAsset(url: SampleAssets.modelsDirectory.appending(path: "SimpleInstancing/glTF-Binary/SimpleInstancing.glb"))
    let statistics = asset.statistics
    #expect(statistics.primitives == 1)
    #expect(statistics.instances == 125)
    #expect(statistics.triangles == 125 * 12)
    #expect(statistics.vertices == 24)
    #expect(statistics.extensionsUsed == ["EXT_mesh_gpu_instancing"])
}
