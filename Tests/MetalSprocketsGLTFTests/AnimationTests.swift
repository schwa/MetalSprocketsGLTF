import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// A parent node (rest translation x = 5) animated linearly from x = -2 to x = 2 over one second, with a child at
/// y = 1 holding a red unlit triangle, a point light child (node 2) at y = 2 and a camera child (node 3) at z = 3.
func makeAnimatedTriangleFile() throws -> URL {
    let floats: [Float] = [
        -1, -1, 0, 1, -1, 0, 0, 1, 0, // positions, offset 0
        0, 1, // keyframe times, offset 36
        -2, 0, 0, 2, 0, 0, // translations, offset 44
    ]
    let buffer = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit", "KHR_lights_punctual"],
      "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "intensity": 1}]}},
      "scene": 0,
      "scenes": [{"nodes": [0]}],
      "nodes": [
        {"children": [1, 2, 3], "translation": [5, 0, 0]},
        {"mesh": 0, "translation": [0, 1, 0]},
        {"translation": [0, 2, 0], "extensions": {"KHR_lights_punctual": {"light": 0}}},
        {"camera": 0, "translation": [0, 0, 3]}
      ],
      "cameras": [{"type": "perspective", "perspective": {"yfov": 0.8, "znear": 0.1}}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "animations": [{"name": "Slide", "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}], "samplers": [{"input": 1, "output": 2, "interpolation": "LINEAR"}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 24}
      ],
      "buffers": [{"byteLength": 68, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A single-sided red unlit triangle facing +z whose node's x scale animates from 1 to -1 over one second.
func makeMirroringTriangleFile() throws -> URL {
    let floats: [Float] = [
        -1, -1, 0, 1, -1, 0, 0, 1, 0, // positions, offset 0
        0, 1, // keyframe times, offset 36
        1, 1, 1, -1, 1, 1, // scales, offset 44
    ]
    let buffer = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "animations": [{"channels": [{"sampler": 0, "target": {"node": 0, "path": "scale"}}], "samplers": [{"input": 1, "output": 2, "interpolation": "STEP"}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 24}
      ],
      "buffers": [{"byteLength": 68, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A textured unlit triangle animated over one second only through KHR_animation_pointer: node 0's translation
/// (x 0 → 4), material 0's baseColorFactor (red → blue), its base color texture's offset ((0, 0) → (0.5, 0)),
/// and an unsupported pointer (mesh weights).
func makePointerAnimatedFile() throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([0, 0, 1, 0, 0.5, 1]) // texCoords, 24 bytes at 36
    append([0, 1]) // times, 8 bytes at 60
    append([0, 0, 0, 4, 0, 0]) // translations, 24 bytes at 68
    append([1, 0, 0, 1, 0, 0, 1, 1]) // base color factors, 32 bytes at 92
    append([0, 0, 0.5, 0]) // texture offsets, 16 bytes at 124
    append([1, 2]) // mesh weights, 8 bytes at 140
    let png = try makePNG().base64EncodedString()
    func channel(_ sampler: Int, _ pointer: String) -> String {
        #"{"sampler": \#(sampler), "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "\#(pointer)"}}}}"#
    }
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_animation_pointer", "KHR_materials_unlit", "KHR_texture_transform"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1],
        "baseColorTexture": {"index": 0, "extensions": {"KHR_texture_transform": {"scale": [2, 2]}}}},
        "extensions": {"KHR_materials_unlit": {}}}],
      "textures": [{"source": 0}],
      "images": [{"uri": "data:image/png;base64,\(png)"}],
      "animations": [{
        "channels": [
          \(channel(0, "/nodes/0/translation")),
          \(channel(1, "/materials/0/pbrMetallicRoughness/baseColorFactor")),
          \(channel(2, "/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/offset")),
          \(channel(3, "/meshes/0/weights"))
        ],
        "samplers": [{"input": 2, "output": 3}, {"input": 2, "output": 4}, {"input": 2, "output": 5}, {"input": 2, "output": 6}]
      }],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC2"},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"},
        {"bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC4"},
        {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC2"},
        {"bufferView": 6, "componentType": 5126, "count": 2, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 24},
        {"buffer": 0, "byteOffset": 60, "byteLength": 8},
        {"buffer": 0, "byteOffset": 68, "byteLength": 24},
        {"buffer": 0, "byteOffset": 92, "byteLength": 32},
        {"buffer": 0, "byteOffset": 124, "byteLength": 16},
        {"buffer": 0, "byteOffset": 140, "byteLength": 8}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// Two unlit triangles with different materials (red at x = -2, green at x = 2), so they are separate batches.
/// Animation 0 moves the red one to y = 2 at t = 1; animation 1 mirrors it (x scale -1) at t = 1.
func makeTwoMaterialAnimatedFile() throws -> URL {
    let floats: [Float] = [
        -0.5, -0.5, 0, 0.5, -0.5, 0, 0, 0.5, 0, // positions, offset 0
        0, 1, // times, offset 36
        -2, 0, 0, -2, 2, 0, // translations, offset 44
        1, 1, 1, -1, 1, 1, // scales, offset 68
    ]
    let buffer = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0, "scenes": [{"nodes": [0, 1]}],
      "nodes": [{"mesh": 0, "translation": [-2, 0, 0]}, {"mesh": 1, "translation": [2, 0, 0]}],
      "meshes": [
        {"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]},
        {"primitives": [{"attributes": {"POSITION": 0}, "material": 1}]}
      ],
      "materials": [
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}},
        {"pbrMetallicRoughness": {"baseColorFactor": [0, 1, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}
      ],
      "animations": [
        {"channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}], "samplers": [{"input": 1, "output": 2}]},
        {"channels": [{"sampler": 0, "target": {"node": 0, "path": "scale"}}], "samplers": [{"input": 1, "output": 3, "interpolation": "STEP"}]}
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-0.5, -0.5, 0], "max": [0.5, 0.5, 0]},
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
      "buffers": [{"byteLength": 92, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Suite(.metalValidation)
struct AnimationTests {
    /// Red and green bytes at world points after rendering `asset` with `pose`, viewed head-on.
    func colors(_ asset: GLTFAsset, pose: PBRPose?, at points: [SIMD3<Float>]) throws -> [(red: UInt8, green: UInt8)] {
        let view = simd_float4x4.lookAt(eye: [0, 1, 10], target: [0, 1, 0], up: [0, 1, 0])
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 100)
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, pose: pose)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return points.map { point in
            let clip = projection * view * SIMD4(point, 1)
            let column = Int((clip.x / clip.w * 0.5 + 0.5) * 64)
            let row = Int((0.5 - clip.y / clip.w * 0.5) * 64)
            let index = (row * 64 + column) * 4
            return (pixels[index], pixels[index + 1])
        }
    }

    // Static opaque primitives with different materials are merged and drawn by one element, at rest and posed.
    @Test func mergedGeometryFollowsThePose() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let merged = try #require(asset.merged)
        #expect(merged.records.count == 2)

        let rest = try colors(asset, pose: nil, at: [[-2, -0.1, 0], [2, -0.1, 0]])
        #expect(rest[0].red > 200 && rest[1].green > 200, "Rest: \(rest)")

        let moved = asset.pose(animation: 0, time: 1)
        #expect(merged.instances(pose: moved) != nil)
        let posed = try colors(asset, pose: moved, at: [[-2, -0.1, 0], [-2, 1.9, 0], [2, -0.1, 0]])
        #expect(posed[0].red < 30, "Red triangle still at rest: \(posed)")
        #expect(posed[1].red > 200 && posed[2].green > 200, "Posed: \(posed)")
    }

    // A pose that mirrors an instance away from its rest winding falls back to per-batch drawing, which handles it.
    @Test func mergedGeometryFallsBackWhenMirrored() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let mirrored = asset.pose(animation: 1, time: 1)
        #expect(try #require(asset.merged).instances(pose: mirrored) == nil)
        let colors = try colors(asset, pose: mirrored, at: [[-2, -0.1, 0], [2, -0.1, 0]])
        #expect(colors[0].red > 200 && colors[1].green > 200, "Mirrored: \(colors)")
    }

    // KHR_animation_pointer: node and material properties animate; unsupported targets are reported.
    @Test func animatesThroughPointers() throws {
        let asset = try GLTFAsset(url: makePointerAnimatedFile())
        let material = try #require(asset.materials.first)
        let pose = asset.pose(animation: 0, time: 0.5)
        #expect(simd_distance(pose.worldMatrices[0].columns.3.xyz, [2, 0, 0]) < 1e-5)
        let uniforms = try #require(pose.materialUniforms[ObjectIdentifier(material)])
        #expect(simd_distance(uniforms.baseColorFactor, [0.5, 0, 0.5, 1]) < 1e-5)
        // Offset (0.25, 0) with the file's unanimated scale 2 kept: the matrix's translation column is the offset.
        #expect(simd_distance(uniforms.baseColor.transform.columns.2, [0.25, 0, 1]) < 1e-5)
        #expect(uniforms.baseColor.transform.columns.0.x == 2)
        #expect(asset.warnings.contains { $0.contains("/meshes/0/weights") }, "\(asset.warnings)")
        #expect(asset.restPose.materialUniforms.isEmpty)
    }

    // An animation that mirrors a node flips its winding too, so its front faces stay visible.
    @Test func mirroringAnimationKeepsFrontFaces() throws {
        let asset = try GLTFAsset(url: makeMirroringTriangleFile())
        let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
        for time: Float in [0, 1] {
            let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
            let image = try renderer.render(
                try RenderPass {
                    GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, pose: asset.pose(animation: 0, time: time))
                }
            ).cgImage
            let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            #expect(pixels[(16 * 32 + 16) * 4] > 200, "Triangle culled at time \(time)")
        }
    }

    func translation(_ pose: PBRPose, node: Int) -> SIMD3<Float> {
        let column = pose.worldMatrices[node].columns.3
        return SIMD3(column.x, column.y, column.z)
    }

    // Lights and cameras on animated nodes follow the pose.
    @Test func lightsAndCamerasFollowThePose() throws {
        let asset = try GLTFAsset(url: makeAnimatedTriangleFile())
        let pose = asset.pose(animation: 0, time: 1)
        #expect(simd_distance(try #require(asset.lights(pose: asset.restPose).first).position, [5, 2, 0]) < 1e-5)
        #expect(simd_distance(try #require(asset.lights(pose: pose).first).position, [2, 2, 0]) < 1e-5)
        #expect(simd_distance(try #require(asset.cameras(pose: pose).first).worldMatrix.columns.3.xyz, [2, 0, 3]) < 1e-5)
        #expect(simd_distance(try #require(PBRLighting(asset: asset, pose: pose).lights.first).position, [2, 2, 0]) < 1e-5)
    }

    @Test func samplesNodeTranslation() throws {
        let asset = try GLTFAsset(url: makeAnimatedTriangleFile())
        #expect(asset.animations.count == 1)
        #expect(asset.animations.first?.name == "Slide")
        #expect(asset.animations.first?.duration == 1)

        // The child inherits its parent's animated transform; past the end the clip clamps.
        #expect(simd_distance(translation(asset.restPose, node: 1), [5, 1, 0]) < 1e-5)
        #expect(simd_distance(translation(asset.pose(animation: 0, time: 0), node: 1), [-2, 1, 0]) < 1e-5)
        #expect(simd_distance(translation(asset.pose(animation: 0, time: 0.5), node: 1), [0, 1, 0]) < 1e-5)
        #expect(simd_distance(translation(asset.pose(animation: 0, time: 1), node: 1), [2, 1, 0]) < 1e-5)
        #expect(simd_distance(translation(asset.pose(animation: 0, time: 3), node: 1), [2, 1, 0]) < 1e-5)
    }

    @Test func posedBoundsFollowAnimation() throws {
        let asset = try GLTFAsset(url: makeAnimatedTriangleFile())
        #expect(abs(asset.bounds.center.x - 5) < 1e-4)
        let bounds = asset.bounds(for: asset.pose(animation: 0, time: 1))
        #expect(abs(bounds.center.x - 2) < 1e-4, "Bounds centred at x = \(bounds.center.x)")
    }

    @Test func rendersPose() throws {
        let asset = try GLTFAsset(url: makeAnimatedTriangleFile())
        let width = 128
        let height = 64
        let view = simd_float4x4.lookAt(eye: [0, 1, 12], target: [0, 1, 0], up: [0, 1, 0])
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: Float(width) / Float(height), near: 0.1, far: 100)
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, pose: asset.pose(animation: 0, time: 1))
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func red(atWorld point: SIMD3<Float>) -> UInt8 {
            let clip = projection * view * SIMD4(point, 1)
            let column = Int((clip.x / clip.w * 0.5 + 0.5) * Float(width))
            let row = Int((0.5 - clip.y / clip.w * 0.5) * Float(height))
            return pixels[(row * width + column) * 4]
        }
        // Posed at x = 2; nothing at the starting position or the rest position.
        #expect(red(atWorld: [2, 0.7, 0]) > 200)
        #expect(red(atWorld: [-2, 0.7, 0]) < 30)
        #expect(red(atWorld: [5, 0.7, 0]) < 30)
    }
}
