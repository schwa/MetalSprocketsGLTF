import Foundation
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

@Suite(.requiresMetal4)
struct DrawPlanTests {
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 100)

    func plan(_ asset: GLTFAsset, pose: PBRPose? = nil, stage: PBRRenderer.TransmissionPrePassStage = .none, eye: SIMD3<Float> = [0, 0, 10], target: SIMD3<Float> = .zero, merging: Bool = true) -> PBRDrawPlan {
        let view = simd_float4x4.lookAt(eye: eye, target: target, up: [0, 1, 0])
        return PBRDrawPlan(model: asset.model, pose: pose, stage: stage, viewProjections: [projection * view], cameraPosition: eye, modelMatrix: matrix_identity_float4x4, usesMergedGeometry: merging)
    }

    func perBatchCount(_ plan: PBRDrawPlan) -> Int {
        plan.opaqueGroups.map(\.batches.count).reduce(0, +) + plan.blendedRuns.map(\.batches.count).reduce(0, +)
    }

    // Static opaque batches with different materials are merged; with merging off each is drawn on its own.
    @Test func mergesStaticOpaqueBatches() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let merged = plan(asset)
        #expect(merged.mergedStatic?.visible == [true, true])
        #expect(merged.mergedStatic?.instances == nil && merged.mergedStatic?.materials == nil)
        #expect(perBatchCount(merged) == 0)
        let separate = plan(asset, merging: false)
        #expect(separate.mergedStatic == nil)
        #expect(perBatchCount(separate) == 2)
    }

    // A pose supplies per-frame instances to the merged set; one that mirrors an instance falls back to per-batch.
    @Test func posesAndMirroringFallback() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let moved = plan(asset, pose: asset.pose(animation: 0, time: 1))
        #expect(moved.mergedStatic?.instances?.count == 2)
        let mirrored = plan(asset, pose: asset.pose(animation: 1, time: 1))
        #expect(mirrored.mergedStatic == nil)
        #expect(perBatchCount(mirrored) == 2)
    }

    // Batches outside the view are culled, merged or not.
    @Test func cullsOutsideTheView() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let away = plan(asset, eye: [0, 0, 10], target: [0, 0, 20])
        #expect(away.mergedStatic?.visible == [false, false])
        #expect(perBatchCount(plan(asset, eye: [0, 0, 10], target: [0, 0, 20], merging: false)) == 0)
    }

    // The transmission pre-pass stages draw only what they need: the opaque stage leaves out glass, the back-face
    // stage only draws double-sided glass, and the main pass draws everything.
    @Test func transmissionStagesSelectBatches() throws {
        let asset = try GLTFAsset(url: makeGlassInFrontOfRedFile())
        func transmissiveCount(_ plan: PBRDrawPlan) -> Int {
            plan.opaqueGroups.flatMap(\.batches).filter(\.material.isTransmissive).count
        }
        #expect(perBatchCount(plan(asset)) == 2 && transmissiveCount(plan(asset)) == 1)
        #expect(perBatchCount(plan(asset, stage: .opaque)) == 1 && transmissiveCount(plan(asset, stage: .opaque)) == 0)
        #expect(perBatchCount(plan(asset, stage: .transmissiveBackFaces)) == 0, "Single-sided glass has no back faces to draw")
    }

    // Blended batches are ordered back to front and split into runs by vertex variant.
    @Test func ordersBlendedRunsBackToFront() throws {
        let asset = try GLTFAsset(url: makeBlendedSkinnedAndStaticFile())
        let runs = plan(asset, eye: [0, 0, 4]).blendedRuns
        #expect(runs.map(\.variant.skinned) == [true, false], "The far skinned triangle comes first")
        #expect(runs.map(\.id) == [0, 1])
    }
}
