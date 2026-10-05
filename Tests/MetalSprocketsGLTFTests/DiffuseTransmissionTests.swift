import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// A white quad facing +z with the given KHR_materials_diffuse_transmission JSON (or none).
private func makeQuadFile(diffuseTransmission: String?) throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
    let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    let buffer = (positions + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
    let extensions = diffuseTransmission.map { #", "extensions": {"KHR_materials_diffuse_transmission": \#($0)}"# } ?? ""
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_diffuse_transmission"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}\(extensions)}],
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

/// The center pixel (sRGB, 0...255) of the quad seen from +z, lit only by a light behind it.
private func backlitCenter(diffuseTransmission: String?) throws -> SIMD3<Int> {
    let asset = try GLTFAsset(url: makeQuadFile(diffuseTransmission: diffuseTransmission))
    // The light travels toward +z, so it shines on the quad's back.
    let lighting = PBRLighting(lights: [.directional(direction: [0, 0, 1], intensity: 3)], environmentIntensity: 0)
    let view = simd_float4x4.lookAt(eye: [0, 0, 4], target: .zero, up: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspectRatio: 1, near: 0.1, far: 20)
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(try RenderPass {
        GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting)
    }).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (16 * 32 + 16) * 4
    return SIMD3(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

// Without the extension, light behind an opaque surface does not reach its front.
@Test(.metalValidation) func backlitSurfaceIsDarkWithoutDiffuseTransmission() throws {
    let center = try backlitCenter(diffuseTransmission: nil)
    #expect(center.x < 10 && center.y < 10 && center.z < 10, "\(center)")
}

// Diffusely transmitted light from behind shows on the front, tinted by diffuseTransmissionColorFactor.
@Test(.metalValidation) func diffuseTransmissionLetsBacklightThroughTinted() throws {
    let center = try backlitCenter(diffuseTransmission: #"{"diffuseTransmissionFactor": 1, "diffuseTransmissionColorFactor": [1, 0, 0]}"#)
    #expect(center.x > 120, "\(center)")
    // Tone mapping desaturates bright values slightly, so green and blue are small but not zero.
    #expect(center.y < center.x / 4 && center.z < center.x / 4, "\(center)")
}

// diffuseTransmissionFactor blends: half transmits half as much light as full.
@Test(.metalValidation) func diffuseTransmissionFactorScalesTransmittedLight() throws {
    let half = try backlitCenter(diffuseTransmission: #"{"diffuseTransmissionFactor": 0.5}"#)
    let full = try backlitCenter(diffuseTransmission: #"{"diffuseTransmissionFactor": 1}"#)
    #expect(half.x > 20 && half.x < full.x, "half \(half), full \(full)")
}
