import Foundation
import Metal
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import SwiftGLTF
import Testing

struct AssetLoadingTests {
    func contents(_ url: URL, sceneIndex: Int = 0) throws -> GLTFSceneContents {
        let container = try Container(url: url)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try GLTFAsset.Resources.load(container: container, device: device)
        return try GLTFSceneContents(document: container.document, resources: resources, sceneIndex: sceneIndex, variant: nil)
    }

    // A document without scenes draws every root node.
    @Test func flattensRootNodesWithoutScenes() throws {
        let nodes = #"[{"mesh": 0, "children": [1]}, {"mesh": 0, "translation": [3, 0, 0]}, {"mesh": 0, "translation": [6, 0, 0]}]"#
        let flattened = try contents(makeTriangleFile(nodes: nodes, scenes: "[]"))
        #expect(flattened.hierarchy.roots == [0, 2])
        #expect(flattened.model.opaqueInstances.map(\.nodeIndex).sorted() == [0, 1, 2])
    }

    // Flattening collects lights and cameras with the nodes that place them.
    @Test func flattensLightsAndCameras() throws {
        let flattened = try contents(makeAnimatedTriangleFile())
        #expect(flattened.model.opaqueInstances.count + flattened.model.blendedInstances.count == 1)
        #expect(flattened.lightSources.map(\.node) == [2])
        #expect(flattened.cameraSources.map(\.node) == [3])
        #expect(flattened.cameraSources.map(\.index) == [0])
        #expect(flattened.model.lights.count == 1)
    }

    // The rest build and the rest pose come from one walk: every instance sits at its node's rest world matrix.
    @Test func restBuildMatchesRestPose() throws {
        let nodes = #"[{"mesh": 0, "translation": [1, 0, 0], "children": [1]}, {"mesh": 0, "translation": [0, 2, 0], "rotation": [0, 0, 0.7071068, 0.7071068]}]"#
        let flattened = try contents(makeTriangleFile(nodes: nodes))
        let pose = flattened.model.restPose
        for instance in flattened.model.opaqueInstances + flattened.model.blendedInstances {
            #expect(instance.worldMatrix == pose.worldMatrices[instance.nodeIndex])
        }
        #expect(simd_distance(pose.worldMatrices[1].columns.3.xyz, [1, 2, 0]) < 1e-6)
    }

    // Cycles and out-of-range children are rejected before any walk.
    @Test func rejectsBrokenHierarchies() throws {
        #expect(throws: GLTFError.self) { try contents(makeTriangleFile(nodes: #"[{"mesh": 0, "children": [1]}, {"children": [0]}]"#, scenes: #"[{"nodes": [0]}]"#)) }
        #expect(throws: GLTFError.self) { try contents(makeTriangleFile(nodes: #"[{"mesh": 0, "children": [5]}]"#)) }
    }

    // Residency covers every long-lived allocation exactly once (normal and occlusion share one texture here).
    @Test func residencyListsEachAllocationOnce() throws {
        let asset = try GLTFAsset(url: makeMaterialTriangleFile(normalScale: 1, occlusionStrength: 1))
        let allocations = PBRModelBuilder.residencyAllocations(materials: asset.materials + [asset.resources.defaultMaterial], primitives: asset.meshes.flatMap(\.self), batches: asset.opaqueBatches + asset.blendedBatches, merged: [asset.merged, asset.mergedSkinned, asset.mergedTransmissive])
        let identifiers = allocations.map { ObjectIdentifier($0) }
        #expect(Set(identifiers).count == identifiers.count)
        for material in asset.materials + [asset.resources.defaultMaterial] {
            #expect(identifiers.contains(ObjectIdentifier(material.resourceBuffer)))
            for binding in material.textureBindings {
                #expect(identifiers.contains(ObjectIdentifier(binding.texture)))
            }
        }
        for batch in asset.opaqueBatches + asset.blendedBatches {
            #expect(identifiers.contains(ObjectIdentifier(batch.instanceBuffer)))
        }
    }
}
