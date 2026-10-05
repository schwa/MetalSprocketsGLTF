import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

// The Swift list mirrors the shader's kPBRDebugView* values one for one.
@Test func debugViewsMatchTheShaderValues() {
    #expect(Int32(PBRDebugView.allCases.count) == PBRShaderDebugView.debugViewCount.rawValue)
    #expect(PBRDebugView.allCases.map(\.rawValue) == Array(0 ..< Int32(PBRDebugView.allCases.count)))
    #expect(PBRDebugView.baseColor.shaderValue == .debugViewBaseColor)
    #expect(PBRDebugView.tangentHandedness.shaderValue == .debugViewTangentHandedness)
    #expect(PBRDebugView.iridescence.shaderValue == .debugViewIridescence)
}

/// A quad facing +z: base color (0.2, 0.4, 0.8), metallic 0, roughness 0.5.
private func makeQuadFile() throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
    let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    let buffer = (positions + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.2, 0.4, 0.8, 1], "metallicFactor": 0, "roughnessFactor": 0.5}}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3"}
      ],
      "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 72}, {"buffer": 0, "byteOffset": 72, "byteLength": 72}],
      "buffers": [{"byteLength": 144, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// The center pixel (sRGB bytes) of the quad seen head-on from +z with `debugView`.
@MainActor
private func center(_ debugView: PBRDebugView, asset: GLTFAsset) throws -> SIMD3<Int> {
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    var scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, viewportSize: CGSize(width: 32, height: 32))
    scene.debugView = debugView
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (16 * 32 + 16) * 4
    return SIMD3(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

private func isClose(_ pixel: SIMD3<Int>, _ expected: SIMD3<Int>, tolerance: Int = 6) -> Bool {
    let difference = pixel &- expected
    return abs(difference.x) <= tolerance && abs(difference.y) <= tolerance && abs(difference.z) <= tolerance
}

// Each view shows the input it names, unlit: data as its value, colors as the color.
@Test(.metalValidation) @MainActor func debugViewsShowTheirInputs() throws {
    let asset = try GLTFAsset(url: makeQuadFile())
    // Base color is linear, so the sRGB target shows its sRGB encoding: 0.2, 0.4, 0.8 -> 124, 170, 231.
    let baseColor = try center(.baseColor, asset: asset)
    #expect(isClose(baseColor, [124, 170, 231]), "base color \(baseColor)")
    // Data shows its value: roughness 0.5 is mid gray (about 128 after the shader's 2.2 decode and sRGB encode).
    let roughness = try center(.roughness, asset: asset)
    #expect(isClose(roughness, [128, 128, 128], tolerance: 8), "roughness \(roughness)")
    // The normal faces the camera (+z): (0, 0, 1) maps to (0.5, 0.5, 1).
    let normal = try center(.shadingNormal, asset: asset)
    #expect(isClose(normal, [128, 128, 255], tolerance: 8), "normal \(normal)")
    #expect(try center(.frontFacing, asset: asset) == [0, 255, 0])
    #expect(try center(.metallic, asset: asset) == [0, 0, 0])
    // Lit is the default and is unaffected.
    let lit = try center(.lit, asset: asset)
    #expect(lit != baseColor, "lit \(lit)")
}
