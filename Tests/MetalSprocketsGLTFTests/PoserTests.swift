import Foundation
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import SwiftGLTF
import Testing

// Posing needs no GPU: these build a GLTFPoser from a Container alone, without .requiresMetal4.
// The file's parent node (rest x = 5) slides from x = -2 to x = 2 over one second, carrying a light (y = 2) and a
// camera (z = 3).
struct PoserTests {
    func poser() throws -> GLTFPoser {
        try GLTFPoser(container: Container(url: makeAnimatedTriangleFile()), sceneIndex: 0)
    }

    func parentX(_ pose: PBRPose) -> Float {
        pose.worldMatrices[0].columns.3.x
    }

    @Test func samplesOneClip() throws {
        let poser = try poser()
        #expect(parentX(poser.restPose) == 5)
        let pose = poser.pose(layers: [GLTFAnimationLayer(animation: 0, time: 0.5)])
        #expect(abs(parentX(pose)) < 1e-5)
        #expect(simd_distance(try #require(pose.lights?.first).position, [0, 2, 0]) < 1e-5)
        #expect(simd_distance(try #require(poser.cameras(pose: pose).first).worldMatrix.columns.3.xyz, [0, 0, 3]) < 1e-5)
    }

    @Test func noActiveLayersGiveTheRestPose() throws {
        let poser = try poser()
        #expect(parentX(poser.pose(layers: [])) == 5)
        #expect(parentX(poser.pose(layers: [GLTFAnimationLayer(animation: 7, time: 0)])) == 5)
    }

    @Test func blendsOverrideLayersByNormalizedWeight() throws {
        let pose = try poser().pose(layers: [
            GLTFAnimationLayer(animation: 0, time: 0, weight: 3),
            GLTFAnimationLayer(animation: 0, time: 1, weight: 1)
        ])
        // (-2 * 3 + 2 * 1) / 4
        #expect(abs(parentX(pose) - -1) < 1e-5)
    }

    @Test func addsAdditiveOffsetsFromRest() throws {
        let pose = try poser().pose(layers: [
            GLTFAnimationLayer(animation: 0, time: 0),
            GLTFAnimationLayer(animation: 0, time: 1, weight: 0.5, mode: .additive)
        ])
        // -2 + (2 - 5) * 0.5
        #expect(abs(parentX(pose) - -3.5) < 1e-5)
    }

    @Test func rootMotionKeepsTheNodeAtRest() throws {
        let poser = try poser()
        let layers = [GLTFAnimationLayer(animation: 0, time: 1)]
        #expect(parentX(poser.pose(layers: layers, rootMotionNode: 0)) == 5)
        #expect(poser.rootTranslation(layers: layers, node: 0) == [2, 0, 0])
    }
}
