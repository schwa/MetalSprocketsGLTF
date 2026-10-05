import Foundation
@testable import GLTFViewerSupport
import MetalSprocketsGLTF
import simd
import Testing

/// A triangle on node 0 with two one-second clips holding it at x 0 and x 4.
private func makeTwoClipFile() throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([0, 1]) // times, 8 bytes at 36
    append([0, 0, 0, 0, 0, 0]) // clip 0, 24 bytes at 44
    append([4, 0, 0, 4, 0, 0]) // clip 1, 24 bytes at 68
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
      "animations": [
        {"channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}], "samplers": [{"input": 1, "output": 2}]},
        {"channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}], "samplers": [{"input": 1, "output": 3}]}
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 24},
        {"buffer": 0, "byteOffset": 68, "byteLength": 24}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

// Switching clips cross-fades: right after the switch the pose is still the old clip, after the fade the new one.
@MainActor
@Test func switchingClipsCrossFades() async throws {
    let url = try makeTwoClipFile()
    let viewer = ViewerModel(title: "Clips") { _ in url }
    await viewer.load()
    func x() -> Float { viewer.currentPose?.worldMatrices[0].columns.3.x ?? .nan }
    #expect(x() == 0)
    viewer.animationIndex = 1
    #expect(x() < 0.5, "\(x())")
    try await Task.sleep(for: .seconds(Double(ViewerModel.crossFadeDuration) + 0.05))
    #expect(x() == 4)
}
