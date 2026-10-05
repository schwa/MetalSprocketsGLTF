import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// A red, unlit, double-sided triangle mesh, placed once at the origin unless `nodes` and `sceneNodes` say otherwise.
/// `scenes` replaces the single scene with a JSON array of scenes.
func makeTriangleFile(nodes: String = #"[{"mesh": 0}]"#, sceneNodes: String = "[0]", scenes: String? = nil) throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0,
      "scenes": \(scenes ?? "[{\"nodes\": \(sceneNodes)}]"),
      "nodes": \(nodes),
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Test(.metalValidation) func loadsTriangle() throws {
    let asset = try GLTFAsset(url: makeTriangleFile())
    #expect(asset.opaqueInstances.count == 1)
    #expect(asset.blendedInstances.isEmpty)
    #expect(asset.bounds.min == [-1, -1, 0])
    #expect(asset.bounds.max == [1, 1, 0])
    #expect(asset.warnings.isEmpty)
}

/// A red primitive in `mode` (glTF primitive mode) from these positions, without normals.
func makeModePrimitiveFile(mode: Int, positions: [Float]) throws -> URL {
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "mode": \(mode), "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": \(positions.count / 3), "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": \(positions.count * 4)}],
      "buffers": [{"byteLength": \(positions.count * 4), "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

// Point and line primitives are drawn, unlit in their base color as three.js does. Each file draws an
// "X" through the centre, so the centre pixel is covered whatever the primitive type.
@Test(.metalValidation, arguments: [
    (0, [Float](arrayLiteral: 0, 0, 0)), // POINTS
    (1, [Float](arrayLiteral: -1, -1, 0, 1, 1, 0, -1, 1, 0, 1, -1, 0)), // LINES
    (2, [Float](arrayLiteral: -1, -1, 0, 1, 1, 0, 1, -1, 0, -1, 1, 0)), // LINE_LOOP
    (3, [Float](arrayLiteral: -1, -1, 0, 1, 1, 0, 1, -1, 0, -1, 1, 0)), // LINE_STRIP
])
func drawsPointsAndLines(mode: Int, positions: [Float]) throws {
    let asset = try GLTFAsset(url: makeModePrimitiveFile(mode: mode, positions: positions))
    #expect(asset.opaqueInstances.count == 1, "\(asset.warnings)")
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    let renderer = try OffscreenRenderer(size: CGSize(width: 33, height: 33), clearDepth: 0)
    let image = try renderer.render(
        try RenderPass {
            GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection)
        }
    ).cgImage
    let context = try #require(CGContext(data: nil, width: 33, height: 33, bitsPerComponent: 8, bytesPerRow: 33 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 33, height: 33))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let center = (16 * 33 + 16) * 4
    #expect(pixels[center] > 200 && pixels[center + 1] < 60, "Mode \(mode): centre pixel is (\(pixels[center]), \(pixels[center + 1]), \(pixels[center + 2]))")
}

// KHR_node_visibility: a node with visible false hides its own mesh and every descendant's.
@Test func hidesInvisibleNodes() throws {
    let nodes = #"""
    [
      {"children": [1], "extensions": {"KHR_node_visibility": {"visible": false}}},
      {"mesh": 0},
      {"mesh": 0, "translation": [5, 0, 0], "extensions": {"KHR_node_visibility": {"visible": true}}}
    ]
    """#
    let asset = try GLTFAsset(url: makeTriangleFile(nodes: nodes, sceneNodes: "[0, 2]"))
    #expect(asset.opaqueInstances.map(\.nodeIndex) == [2])
}

// Another scene of a loaded asset is built without loading its meshes and materials again.
@Test func switchesScenes() throws {
    let nodes = #"[{"mesh": 0}, {"mesh": 0, "translation": [5, 0, 0]}]"#
    let asset = try GLTFAsset(url: makeTriangleFile(nodes: nodes, scenes: #"[{"nodes": [0]}, {"nodes": [1]}]"#))
    #expect(asset.sceneCount == 2)
    #expect(asset.sceneIndex == 0)
    #expect(abs(asset.bounds.center.x) < 1e-5)

    let second = try asset.scene(1)
    #expect(second.sceneIndex == 1)
    #expect(abs(second.bounds.center.x - 5) < 1e-5)
    #expect(second.meshes.first?.first?.geometry === asset.meshes.first?.first?.geometry, "Meshes were loaded again")
    #expect(second.materials.first === asset.materials.first)
    #expect(throws: (any Error).self) { try asset.scene(2) }
}

// The frustum keeps boxes inside or crossing the view and rejects ones wholly outside any plane.
@Test func frustumCullsBoundsOutsideTheView() {
    let view = simd_float4x4.lookAt(eye: [0, 0, 10], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 1, far: 20)
    let frustum = PBRFrustum(viewProjection: projection * view)
    func box(_ center: SIMD3<Float>) -> PBRBounds { PBRBounds(min: center - 0.5, max: center + 0.5) }
    #expect(frustum.intersects(box([0, 0, 0])))
    #expect(frustum.intersects(box([0, 0, 9.4])), "Crosses the near plane")
    #expect(!frustum.intersects(box([0, 0, 12])), "Behind the camera")
    #expect(!frustum.intersects(box([0, 0, -15])), "Beyond the far plane")
    #expect(!frustum.intersects(box([20, 0, 0])), "Right of the view")
    #expect(!frustum.intersects(box([0, -20, 0])), "Below the view")
    #expect(!frustum.intersects(.empty))
}

/// An indexed quad (4 vertices, 2 triangles) without normals, unlit off, facing +z.
func makeIndexedQuadWithoutNormalsFile() throws -> URL {
    var data = Data()
    [Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0).withUnsafeBytes { data.append(contentsOf: $0) }
    [UInt16](arrayLiteral: 0, 1, 2, 0, 2, 3).withUnsafeBytes { data.append(contentsOf: $0) }
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5123, "count": 6, "type": "SCALAR"}
      ],
      "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 48}, {"buffer": 0, "byteOffset": 48, "byteLength": 12}],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

// Primitives without normals keep their shared vertices (flat normals come from the shader), and are lit as flat
// surfaces facing their winding: a quad facing +z, lit from +z, is bright.
@Test(.metalValidation) func primitivesWithoutNormalsKeepTheirVertices() throws {
    let asset = try GLTFAsset(url: makeIndexedQuadWithoutNormalsFile())
    let primitive = try #require(asset.opaqueInstances.first?.primitive)
    #expect(primitive.vertexCount == 4, "Unwelded to \(primitive.vertexCount) vertices")
    #expect(!primitive.hasNormals)

    let lighting = PBRLighting(lights: [.directional(direction: [0, 0, -1], intensity: 3)], environmentIntensity: 0)
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(try RenderPass {
        GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting)
    }).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    #expect(pixels[(16 * 32 + 16) * 4] > 190, "Expected a brightly lit quad, got \(pixels[(16 * 32 + 16) * 4])")
}

// A node hierarchy with a cycle fails to load instead of recursing forever.
@Test func rejectsCyclicNodeHierarchy() throws {
    let url = try makeTriangleFile(nodes: #"[{"mesh": 0, "children": [1]}, {"children": [0]}]"#, sceneNodes: "[0]")
    #expect(throws: (any Error).self) {
        try GLTFAsset(url: url)
    }
}

// Nodes sharing a mesh and material become one instanced draw, and every instance is drawn.
@Test(.metalValidation) func instancesSharedMeshes() throws {
    let nodes = #"[{"mesh": 0, "translation": [-3, 0, 0]}, {"mesh": 0}, {"mesh": 0, "translation": [3, 0, 0]}]"#
    let asset = try GLTFAsset(url: makeTriangleFile(nodes: nodes, sceneNodes: "[0, 1, 2]"))
    #expect(asset.opaqueInstances.count == 3)
    #expect(asset.opaqueBatches.count == 1)
    #expect(asset.opaqueBatches.first?.instanceCount == 3)

    let width = 192
    let height = 64
    let camera = PBRCamera.framing(asset.bounds, aspectRatio: Float(width) / Float(height), yaw: 0, pitch: 0)
    let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), clearDepth: 0)
    let image = try renderer.render(
        try RenderPass {
            GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        }
    ).cgImage
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    for x: Float in [-3, 0, 3] {
        // A point inside each triangle, projected to a pixel (row 0 at the top).
        let clip = camera.projectionMatrix * camera.viewMatrix * SIMD4<Float>(x, -0.3, 0, 1)
        let column = Int((clip.x / clip.w * 0.5 + 0.5) * Float(width))
        let row = Int((0.5 - clip.y / clip.w * 0.5) * Float(height))
        #expect(pixels[(row * width + column) * 4] > 200, "No red at the instance at x = \(x)")
    }
}

@Test(.metalValidation) func rendersTriangle() throws {
    let asset = try GLTFAsset(url: makeTriangleFile())
    let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
    let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0)
    let image = try renderer.render(
        try RenderPass {
            GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        }
    ).cgImage

    let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let center = (32 * 64 + 32) * 4
    #expect(pixels[center] > 200)
    #expect(pixels[center + 1] < 50)
    #expect(pixels[center + 2] < 50)
    #expect(pixels[0] < 30) // Corner stays background.
}

// Like three.js, unlit colors are tone mapped: PBR Neutral maps pure red (1, 0, 0) to about (0.88, 0.016, 0.016),
// which is (241, 34, 34) in sRGB.
@Test(.metalValidation) func unlitColorsAreToneMapped() throws {
    let asset = try GLTFAsset(url: makeTriangleFile())
    let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
    let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), clearDepth: 0)
    let image = try renderer.render(
        try RenderPass {
            GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        }
    ).cgImage
    let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let center = (32 * 64 + 32) * 4
    let pixel = (Int(pixels[center]), Int(pixels[center + 1]), Int(pixels[center + 2]))
    #expect(abs(pixel.0 - 241) <= 3 && abs(pixel.1 - 34) <= 3 && abs(pixel.2 - 34) <= 3, "Expected tone-mapped red, got \(pixel)")
}

@Test func triangleStripAndFanConversion() {
    #expect(GLTFGeometry.triangleList(fromStrip: [0, 1, 2, 3]) == [0, 1, 2, 2, 1, 3])
    #expect(GLTFGeometry.triangleList(fromFan: [0, 1, 2, 3]) == [0, 1, 2, 0, 2, 3])
}
