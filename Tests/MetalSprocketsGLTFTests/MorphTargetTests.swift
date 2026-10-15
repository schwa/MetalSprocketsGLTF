import CoreGraphics
import Foundation
import GeometryLite3D
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

/// A red unlit triangle with one morph target that moves it +5 in x. Mesh weight 0; animated to 1 over one second.
func makeMorphTriangleFile(nodeWeights: String? = nil) throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([5, 0, 0, 5, 0, 0, 5, 0, 0]) // target position deltas, 36 bytes at 36
    append([0, 1]) // times, 8 bytes at 72
    append([0, 1]) // weights per keyframe, 8 bytes at 80
    let node = nodeWeights.map { #"{"mesh": 0, "weights": \#($0)}"# } ?? #"{"mesh": 0}"#
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0,
      "scenes": [{"nodes": [0]}],
      "nodes": [\(node)],
      "meshes": [{"weights": [0], "primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 1}], "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "animations": [{"channels": [{"sampler": 0, "target": {"node": 0, "path": "weights"}}], "samplers": [{"input": 2, "output": 3}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3", "min": [5, 0, 0], "max": [5, 0, 0]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 36},
        {"buffer": 0, "byteOffset": 72, "byteLength": 8},
        {"buffer": 0, "byteOffset": 80, "byteLength": 8}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A triangle with normals and tangents and one morph target that offsets each tangent by (0, 0.5, 0).
func makeMorphTangentTriangleFile() throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([0, 0, 1, 0, 0, 1, 0, 0, 1]) // normals, 36 bytes at 36
    append([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1]) // tangents, 48 bytes at 72
    append([0, 0.5, 0, 0, 0.5, 0, 0, 0.5, 0]) // target tangent deltas, 36 bytes at 120
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"weights": [1], "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TANGENT": 2}, "targets": [{"TANGENT": 3}]}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 36},
        {"buffer": 0, "byteOffset": 72, "byteLength": 48},
        {"buffer": 0, "byteOffset": 120, "byteLength": 36}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Suite(.requiresMetal4, .metalValidation)
struct MorphTargetTests {
    // TANGENT morph targets are read, so morphed normal-mapped meshes keep a correct tangent frame.
    @Test func readsTangentDeltas() throws {
        let asset = try GLTFAsset(url: makeMorphTangentTriangleFile())
        let primitive = try #require(asset.opaqueInstances.first?.primitive)
        let buffer = try #require(primitive.morphBuffer)
        let deltas = buffer.contents().bindMemory(to: PBRMorphDelta.self, capacity: buffer.length / MemoryLayout<PBRMorphDelta>.stride)
        #expect(simd_distance(deltas[0].tangent, [0, 0.5, 0]) < 1e-6)
        // The primitive's MetalMesh carries the targets and the glTF mesh's weights.
        let morphTargets = try #require(primitive.mesh.morphTargets)
        #expect(morphTargets.defaultWeights == [1])
        #expect(morphTargets.targets.first?.tangentOffsets?.first.map { simd_distance($0, [0, 0.5, 0]) < 1e-6 } == true)
    }

    func redValues(_ asset: GLTFAsset, pose: PBRPose?, at points: [SIMD3<Float>]) throws -> [UInt8] {
        let width = 160
        let height = 64
        let view = LookAt(position: [2.5, 0, 20], target: [2.5, 0, 0], up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: Float(width) / Float(height))
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, pose: pose)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return points.map { point in
            let clip = projection * view * SIMD4(point, 1)
            let column = Int((clip.x / clip.w * 0.5 + 0.5) * Float(width))
            let row = Int((0.5 - clip.y / clip.w * 0.5) * Float(height))
            return pixels[(row * width + column) * 4]
        }
    }

    // Bounds cover every weight in 0...1: the base triangle and the triangle moved +5.
    @Test func boundsCoverMorphTargets() throws {
        let asset = try GLTFAsset(url: makeMorphTriangleFile())
        #expect(asset.bounds.min.x <= -1)
        #expect(asset.bounds.max.x >= 6)
    }

    @Test func restUsesMeshWeights() throws {
        let asset = try GLTFAsset(url: makeMorphTriangleFile())
        let red = try redValues(asset, pose: nil, at: [[0, -0.3, 0], [5, -0.3, 0]])
        #expect(red[0] > 200, "Triangle missing at its base position")
        #expect(red[1] < 30)
    }

    @Test func nodeWeightsOverrideMeshWeights() throws {
        let asset = try GLTFAsset(url: makeMorphTriangleFile(nodeWeights: "[1]"))
        let red = try redValues(asset, pose: nil, at: [[0, -0.3, 0], [5, -0.3, 0]])
        #expect(red[0] < 30)
        #expect(red[1] > 200, "Triangle not moved by node weights")
    }

    @Test func animatesWeights() throws {
        let asset = try GLTFAsset(url: makeMorphTriangleFile())
        let red = try redValues(asset, pose: asset.pose(animation: 0, time: 1), at: [[0, -0.3, 0], [5, -0.3, 0]])
        #expect(red[0] < 30)
        #expect(red[1] > 200, "Triangle not moved by animated weights")
    }
}
