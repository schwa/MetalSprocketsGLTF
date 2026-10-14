import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

/// A white horizontal line through the origin (LINES) and a red triangle above it (TRIANGLES).
private func makeLineAndTriangleFile() throws -> URL {
    let floats: [Float] = [
        -1, 0, 0, 1, 0, 0, // line, offset 0
        -0.5, 0.3, 0, 0.5, 0.3, 0, 0, 0.9, 0 // triangle, offset 24
    ]
    let buffer = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_unlit"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [
        {"attributes": {"POSITION": 0}, "material": 0, "mode": 1},
        {"attributes": {"POSITION": 1}, "material": 1}
      ]}],
      "materials": [
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]}, "extensions": {"KHR_materials_unlit": {}}},
        {"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 2, "type": "VEC3", "min": [-1, 0, 0], "max": [1, 0, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-0.5, 0.3, 0], "max": [0.5, 0.9, 0]}
      ],
      "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 24}, {"buffer": 0, "byteOffset": 24, "byteLength": 36}],
      "buffers": [{"byteLength": 60, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

// With drawsTrianglesOnly (foveated visionOS passes allow only triangles), lines are skipped and triangles still draw.
@Test(.requiresMetal4, .metalValidation) @MainActor func trianglesOnlySkipsLines() throws {
    let asset = try GLTFAsset(url: makeLineAndTriangleFile())
    let view = simd_float4x4.lookAt(eye: [0, 0, 3], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 3, aspectRatio: 1, near: 0.1, far: 20)
    func render(trianglesOnly: Bool) throws -> (line: Int, triangle: Int) {
        var renderer = PBRRenderer(model: asset.model, viewMatrix: view, projectionMatrix: projection)
        renderer.drawsTrianglesOnly = trianglesOnly
        let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(try RenderPass { renderer }).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // The line crosses the middle rows; its green channel is bright (the triangle has none).
        let line = (14 ... 17).map { Int(pixels[($0 * 32 + 8) * 4 + 1]) }.max() ?? 0
        // The triangle is above the middle (top rows in memory).
        let triangle = (0 ..< 16).map { Int(pixels[($0 * 32 + 16) * 4]) }.max() ?? 0
        return (line, triangle)
    }
    let all = try render(trianglesOnly: false)
    #expect(all.line > 200 && all.triangle > 200, "\(all)")
    let trianglesOnly = try render(trianglesOnly: true)
    #expect(trianglesOnly.line < 20, "\(trianglesOnly)")
    #expect(trianglesOnly.triangle > 200, "\(trianglesOnly)")
}
