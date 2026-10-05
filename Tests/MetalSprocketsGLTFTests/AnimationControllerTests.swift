import Foundation
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// A triangle on node 0 (rest translation (1, 0, 0)) and an empty node 1, with three one-second clips holding constant
/// values: 0 puts node 0 at the origin unrotated, 1 at (4, 0, 0) turned 90° about z, 2 moves only node 1.
private func makeBlendFile() throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    let half = sqrt(Float(0.5))
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([0, 1]) // times, 8 bytes at 36
    append([0, 0, 0, 0, 0, 0]) // clip 0 translations, 24 bytes at 44
    append([0, 0, 0, 1, 0, 0, 0, 1]) // clip 0 rotations, 32 bytes at 68
    append([4, 0, 0, 4, 0, 0]) // clip 1 translations, 24 bytes at 100
    append([0, 0, half, half, 0, 0, half, half]) // clip 1 rotations, 32 bytes at 124
    append([1, 1, 1, 1, 1, 1]) // clip 2 translations, 24 bytes at 156
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0, 1]}],
      "nodes": [{"mesh": 0, "translation": [1, 0, 0]}, {}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
      "animations": [
        {"name": "A", "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}, {"sampler": 1, "target": {"node": 0, "path": "rotation"}}],
         "samplers": [{"input": 1, "output": 2}, {"input": 1, "output": 3}]},
        {"name": "B", "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}, {"sampler": 1, "target": {"node": 0, "path": "rotation"}}],
         "samplers": [{"input": 1, "output": 4}, {"input": 1, "output": 5}]},
        {"name": "C", "channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}], "samplers": [{"input": 1, "output": 6}]}
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC4"},
        {"bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3"},
        {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC4"},
        {"bufferView": 6, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 24},
        {"buffer": 0, "byteOffset": 68, "byteLength": 32},
        {"buffer": 0, "byteOffset": 100, "byteLength": 24},
        {"buffer": 0, "byteOffset": 124, "byteLength": 32},
        {"buffer": 0, "byteOffset": 156, "byteLength": 24}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

private func position(_ pose: PBRPose, _ node: Int) -> SIMD3<Float> {
    pose.worldMatrices[node].columns.3.xyz
}

/// The angle node 0's x axis makes with world x, in degrees.
private func angle(_ pose: PBRPose) -> Float {
    let axis = pose.worldMatrices[0].columns.0
    return atan2(axis.y, axis.x) * 180 / .pi
}

struct AnimationControllerTests {
    // A 50/50 blend gives the halfway translation and rotation.
    @Test func halfBlendIsHalfway() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        let pose = asset.pose(layers: [GLTFAnimationLayer(animation: 0, time: 0.5, weight: 1), GLTFAnimationLayer(animation: 1, time: 0.5, weight: 1)])
        #expect(simd_distance(position(pose, 0), [2, 0, 0]) < 1e-5)
        #expect(abs(angle(pose) - 45) < 1e-3)
    }

    // A layer that does not animate a node counts as the node's rest transform.
    @Test func unanimatedNodesBlendWithRest() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        let pose = asset.pose(layers: [GLTFAnimationLayer(animation: 1, time: 0, weight: 0.5), GLTFAnimationLayer(animation: 2, time: 0, weight: 0.5)])
        #expect(simd_distance(position(pose, 0), [2.5, 0, 0]) < 1e-5)
        #expect(simd_distance(position(pose, 1), [0.5, 0.5, 0.5]) < 1e-5)
    }

    // One layer at full weight is exactly the single-clip pose.
    @Test func singleLayerMatchesClip() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        #expect(asset.pose(layers: [GLTFAnimationLayer(animation: 1, time: 0.3)]).worldMatrices == asset.pose(animation: 1, time: 0.3).worldMatrices)
    }

    // A cross-fade passes through a blend and finishes on the target clip alone.
    @Test func crossFadeEndsOnTarget() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        var controller = GLTFAnimationController(asset: asset)
        controller.play(0, fadeDuration: 0)
        controller.advance(by: 0.1)
        #expect(controller.layers.map(\.animation) == [0])
        controller.play(1, fadeDuration: 1)
        controller.advance(by: 0.5)
        #expect(controller.layers.map(\.weight) == [0.5, 0.5])
        #expect(simd_distance(position(controller.pose(in: asset), 0), [2, 0, 0]) < 1e-5)
        controller.advance(by: 0.6)
        #expect(controller.tracks.map(\.animation) == [1])
        #expect(controller.pose(in: asset).worldMatrices == asset.pose(animation: 1, time: controller.tracks[0].time).worldMatrices)
    }

    // Times advance by speed and loop or clamp.
    @Test func advancesLoopsAndClamps() {
        var looping = GLTFAnimationController(durations: [1])
        looping.play(0, fadeDuration: 0, speed: 2)
        looping.advance(by: 0.75)
        #expect(abs(looping.tracks[0].time - 0.5) < 1e-5)
        var once = GLTFAnimationController(durations: [1])
        once.play(0, fadeDuration: 0, loops: false)
        once.advance(by: 3)
        #expect(once.tracks[0].time == 1)
    }

    // Blend weights pick the two clips around the parameter and always sum to 1.
    @Test func blendWeightsSumToOne() {
        #expect(GLTFAnimationController.blendWeights(parameter: 0.25, count: 3) == [0.5, 0.5, 0])
        #expect(GLTFAnimationController.blendWeights(parameter: 1, count: 3) == [0, 0, 1])
        for parameter in stride(from: Float(-0.5), through: 1.5, by: 0.1) {
            let sum = GLTFAnimationController.blendWeights(parameter: parameter, count: 4).reduce(0, +)
            #expect(abs(sum - 1) < 1e-5)
        }
    }

    // A phase-synced blend keeps clips of different lengths at the same fraction of their cycles.
    @Test func phaseSyncedBlend() {
        var controller = GLTFAnimationController(durations: [1, 2])
        controller.blend([0, 1], parameter: 0.5)
        // The cycle is the weighted mix of 1 s and 2 s: 1.5 s, so 0.75 s is half a cycle.
        controller.advance(by: 0.75)
        #expect(abs((controller.syncedPhase ?? 0) - 0.5) < 1e-5)
        #expect(controller.tracks.map(\.time) == [0.5, 1])
        #expect(controller.layers.map(\.weight) == [0.5, 0.5])
    }

    // An additive layer adds its clip's offset from rest, scaled by its weight, on top of the override pose.
    @Test func additiveLayersAddOffsetsFromRest() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        // Clip 0 puts node 0 at the origin; clip 1 is 3 from its rest x of 1 and turned 90°. Half of that on top.
        let pose = asset.pose(layers: [GLTFAnimationLayer(animation: 0, time: 0), GLTFAnimationLayer(animation: 1, time: 0, weight: 0.5, mode: .additive)])
        #expect(simd_distance(position(pose, 0), [1.5, 0, 0]) < 1e-5)
        #expect(abs(angle(pose) - 45) < 1e-3)
        var controller = GLTFAnimationController(asset: asset)
        controller.play(0, fadeDuration: 0)
        controller.setAdditive(1, weight: 0.5)
        #expect(controller.layers.last?.mode == .additive)
        #expect(controller.pose(in: asset).worldMatrices == pose.worldMatrices)
    }

    // Root motion: the root's horizontal movement leaves the pose and is reported per advance, across loop wraps.
    @Test func extractsRootMotion() throws {
        // "Slide" moves node 0 (rest x 5) from x -2 to 2 over one second.
        let asset = try GLTFAsset(url: makeAnimatedTriangleFile())
        var controller = GLTFAnimationController(asset: asset)
        controller.rootMotionNode = 0
        controller.play(0, fadeDuration: 0)
        controller.advance(by: 0.5, in: asset)
        #expect(abs(controller.rootMotion.x - 2) < 1e-4, "\(controller.rootMotion)")
        #expect(abs(position(controller.pose(in: asset), 0).x - 5) < 1e-5)
        // 0.5 → 1.25 wraps to 0.25: 2 to the end, then 1 from the start.
        controller.advance(by: 0.75, in: asset)
        #expect(abs(controller.rootMotion.x - 3) < 1e-4, "\(controller.rootMotion)")
    }

    // States switch on parameter conditions with a cross-fade, and a finished one-shot clip can trigger a transition.
    @Test func stateMachineTransitions() throws {
        let asset = try GLTFAsset(url: makeBlendFile())
        var machine = GLTFAnimationStateMachine(
            controller: GLTFAnimationController(asset: asset),
            states: [.init("idle", animation: 0), .init("move", animation: 1), .init("wave", animation: 2, loops: false)],
            transitions: [
                .init(from: "idle", to: "move", fadeDuration: 1) { ($0.parameters["speed"] ?? 0) > 0.5 },
                .init(from: nil, to: "wave", fadeDuration: 0) { ($0.parameters["wave"] ?? 0) > 0 },
                .init(from: "wave", to: "idle", fadeDuration: 0) { $0.normalizedTime >= 1 },
            ],
            initial: "idle"
        )
        machine.advance(by: 0.1, in: asset)
        #expect(machine.currentState == "idle")
        machine.parameters["speed"] = 1
        machine.advance(by: 0.5, in: asset)
        #expect(machine.currentState == "move")
        #expect(machine.controller.layers.map(\.weight) == [0.5, 0.5])
        machine.parameters["wave"] = 1
        machine.advance(by: 0.1, in: asset)
        #expect(machine.currentState == "wave")
        machine.parameters["wave"] = 0
        machine.advance(by: 1.2, in: asset)
        machine.advance(by: 0.1, in: asset)
        #expect(machine.currentState == "idle")
    }
}
