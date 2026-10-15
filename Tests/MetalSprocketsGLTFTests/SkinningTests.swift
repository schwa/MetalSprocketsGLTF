import CoreGraphics
import Foundation
import GeometryLite3D
import GoldenImage
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

/// A red unlit triangle on a mesh node at x = 10, skinned entirely to joint node 1 (rest x = 3).
/// The joint is animated from x = 3 to x = -3 over one second.
func makeSkinnedTriangleFile() throws -> URL {
    var data = Data()
    func append<T>(_ values: [T]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0)) // positions, 36 bytes at 0
    append([UInt16](repeating: 0, count: 12)) // JOINTS_0: joint 0 of the skin, 24 bytes at 36
    append([Float](arrayLiteral: 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)) // WEIGHTS_0, 48 bytes at 60
    append([Float](arrayLiteral: 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)) // inverse bind, 64 bytes at 108
    append([Float](arrayLiteral: 0, 1)) // times, 8 bytes at 172
    append([Float](arrayLiteral: 3, 0, 0, -3, 0, 0)) // joint translations, 24 bytes at 180
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0,
      "scenes": [{"nodes": [0, 1]}],
      "nodes": [{"mesh": 0, "skin": 0, "translation": [10, 0, 0]}, {"translation": [3, 0, 0]}],
      "skins": [{"joints": [1], "inverseBindMatrices": 3}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2}, "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "animations": [{"channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}], "samplers": [{"input": 4, "output": 5}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4"},
        {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 1, "type": "MAT4"},
        {"bufferView": 4, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 24},
        {"buffer": 0, "byteOffset": 60, "byteLength": 48},
        {"buffer": 0, "byteOffset": 108, "byteLength": 64},
        {"buffer": 0, "byteOffset": 172, "byteLength": 8},
        {"buffer": 0, "byteOffset": 180, "byteLength": 24}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A white, lit triangle in the plane x + z = 0 (normal (1, 0, 1) / sqrt 2), skinned to a joint scaled 4x in x.
/// Correctly skinned, its normal is normalize(0.25, 0, 1): nearly facing +z.
func makeScaledJointTriangleFile() throws -> URL {
    var data = Data()
    func append<T>(_ values: [T]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    let n = Float(0.5).squareRoot()
    append([Float](arrayLiteral: -1, -1, 1, 1, -1, -1, 0, 1, 0)) // positions, 36 bytes at 0
    append([Float](arrayLiteral: n, 0, n, n, 0, n, n, 0, n)) // normals, 36 bytes at 36
    append([UInt16](repeating: 0, count: 12)) // JOINTS_0, 24 bytes at 72
    append([Float](arrayLiteral: 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)) // WEIGHTS_0, 48 bytes at 96
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0,
      "scenes": [{"nodes": [0, 1]}],
      "nodes": [{"mesh": 0, "skin": 0}, {"scale": [4, 1, 1]}],
      "skins": [{"joints": [1]}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "JOINTS_0": 2, "WEIGHTS_0": 3}, "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, -1], "max": [1, 1, 1]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5123, "count": 3, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC4"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 36},
        {"buffer": 0, "byteOffset": 72, "byteLength": 24},
        {"buffer": 0, "byteOffset": 96, "byteLength": 48}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// Two overlapping half-transparent unlit triangles: a skinned red one at z = -1 and a static green one at z = 0.
func makeBlendedSkinnedAndStaticFile() throws -> URL {
    var data = Data()
    func append<T>(_ values: [T]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([Float](arrayLiteral: -1, -1, -1, 1, -1, -1, 0, 1, -1)) // far positions, 36 bytes at 0
    append([Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0)) // near positions, 36 bytes at 36
    append([UInt16](repeating: 0, count: 12)) // JOINTS_0, 24 bytes at 72
    append([Float](arrayLiteral: 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)) // WEIGHTS_0, 48 bytes at 96
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0,
      "scenes": [{"nodes": [0, 1, 2]}],
      "nodes": [{"mesh": 0, "skin": 0}, {}, {"mesh": 1}],
      "skins": [{"joints": [1]}],
      "meshes": [
        {"primitives": [{"attributes": {"POSITION": 0, "JOINTS_0": 2, "WEIGHTS_0": 3}, "material": 0}]},
        {"primitives": [{"attributes": {"POSITION": 1}, "material": 1}]}
      ],
      "materials": [
        {"alphaMode": "BLEND", "doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 0.5]}, "extensions": {"KHR_materials_unlit": {}}},
        {"alphaMode": "BLEND", "doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [0, 1, 0, 0.5]}, "extensions": {"KHR_materials_unlit": {}}}
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, -1], "max": [1, 1, -1]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 2, "componentType": 5123, "count": 3, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC4"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 36},
        {"buffer": 0, "byteOffset": 72, "byteLength": 24},
        {"buffer": 0, "byteOffset": 96, "byteLength": 48}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Suite(.requiresMetal4, .metalValidation)
struct SkinningTests {
    // Merged skinned drawing (one joint palette for every skin) renders an animated frame exactly like drawing each
    // skinned primitive on its own. BrainStem has 59 skinned primitives.
    @Test(.enabled(if: SampleAssets.isAvailable)) func mergedSkinnedMatchesPerBatchDrawing() throws {
        let asset = try GLTFAsset(url: SampleAssets.modelsDirectory.appending(path: "BrainStem/glTF-Binary/BrainStem.glb"))
        let merged = try #require(asset.mergedSkinned)
        #expect(merged.records.count > 1)
        let pose = asset.pose(animation: 0, time: 1.3)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        func render(merging: Bool) throws -> CGImage {
            var renderer = GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, pose: pose)
            renderer.usesMergedGeometry = merging
            return try OffscreenRenderer(size: CGSize(width: 128, height: 128), clearDepth: 0).render(try RenderPass { renderer }).cgImage
        }
        let mergedImage = try render(merging: true)
        let separateImage = try render(merging: false)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let psnr = try ImageComparison().compare(try #require(mergedImage.copy(colorSpace: space)), try #require(separateImage.copy(colorSpace: space))).psnr
        #expect(psnr > 60, "Merged and per-batch skinned renders differ: \(psnr) dB")
    }

    // Skinned and static blended primitives share one back-to-front order: the far skinned red triangle draws
    // before the near static green one, so green dominates where they overlap.
    @Test func blendedSkinnedAndStaticShareOneSortOrder() throws {
        let asset = try GLTFAsset(url: makeBlendedSkinnedAndStaticFile())
        let view = LookAt(position: [0, 0, 4], target: [0, 0, -0.5], up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let center = (17 * 32 + 16) * 4
        let (red, green) = (Int(pixels[center]), Int(pixels[center + 1]))
        #expect(green > red + 20, "Expected the near green triangle on top, got red \(red), green \(green)")
    }

    // Normals under a non-uniformly scaled joint use the inverse transpose. Lit from +z, the correct normal
    // (z = 0.97) is bright; transforming the normal like a position (z = 0.24) would be dark.
    @Test func scaledJointNormalsUseInverseTranspose() throws {
        let asset = try GLTFAsset(url: makeScaledJointTriangleFile())
        let lighting = PBRLighting(lights: [.directional(direction: [0, 0, -1], intensity: 3)], environmentIntensity: 0)
        let view = LookAt(position: [0, 0, 12], target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let green = pixels[(17 * 32 + 16) * 4 + 1]
        #expect(green > 190, "Expected a brightly lit surface, got \(green)")
    }

    /// Red channel at each world point after rendering `asset` with `pose`.
    func redValues(_ asset: GLTFAsset, pose: PBRPose?, at points: [SIMD3<Float>]) throws -> [UInt8] {
        let width = 160
        let height = 64
        let view = LookAt(position: [3, 0, 20], target: [3, 0, 0], up: [0, 1, 0]).viewMatrix
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

    // Skinned vertices follow the joint; the mesh node's own transform is ignored, per the glTF spec.
    @Test func followsJointAtRest() throws {
        let asset = try GLTFAsset(url: makeSkinnedTriangleFile())
        let red = try redValues(asset, pose: nil, at: [[3, -0.3, 0], [10, -0.3, 0], [-3, -0.3, 0]])
        #expect(red[0] > 200, "Triangle missing at the joint (x = 3)")
        #expect(red[1] < 30, "Triangle drawn at the mesh node (x = 10)")
        #expect(red[2] < 30)
    }

    // Bounds follow the skinned geometry, not the mesh node.
    @Test func restBoundsFollowJoint() throws {
        let asset = try GLTFAsset(url: makeSkinnedTriangleFile())
        #expect(abs(asset.bounds.center.x - 3) < 0.01, "Bounds centred at x = \(asset.bounds.center.x)")
        #expect(asset.bounds.max.x < 5)
    }

    @Test func posedBoundsFollowAnimatedJoint() throws {
        let asset = try GLTFAsset(url: makeSkinnedTriangleFile())
        let bounds = asset.bounds(for: asset.pose(animation: 0, time: 1))
        #expect(abs(bounds.center.x + 3) < 0.01, "Bounds centred at x = \(bounds.center.x)")
    }

    @Test func followsAnimatedJoint() throws {
        let asset = try GLTFAsset(url: makeSkinnedTriangleFile())
        let red = try redValues(asset, pose: asset.pose(animation: 0, time: 1), at: [[-3, -0.3, 0], [3, -0.3, 0]])
        #expect(red[0] > 200, "Triangle missing at the animated joint (x = -3)")
        #expect(red[1] < 30)
    }
}
