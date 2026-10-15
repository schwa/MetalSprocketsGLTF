import CoreGraphics
import Foundation
import GeometryLite3D
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing

/// The center pixel (sRGB, 0...255) of a white, fully diffuse-transmitting quad in a dense volume, lit from the front,
/// with KHR_materials_volume_scatter's multiscatter color teal when `scatters`.
@MainActor
private func frontLitCenter(scatters: Bool) throws -> SIMD3<Int> {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
    let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    let buffer = (positions + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
    let scatter = scatters ? #", "KHR_materials_volume_scatter": {"multiscatterColorFactor": [0.2, 0.5, 0.6]}"# : ""
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_diffuse_transmission", "KHR_materials_volume", "KHR_materials_volume_scatter"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1},
        "extensions": {"KHR_materials_diffuse_transmission": {"diffuseTransmissionFactor": 1},
          "KHR_materials_volume": {"thicknessFactor": 1, "attenuationDistance": 0.01, "attenuationColor": [0.5, 0.5, 0.5]}\(scatter)}}],
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
    let asset = try GLTFAsset(url: url)
    let lighting = PBRLighting(lights: [.directional(direction: [0, 0, -1], intensity: 3)], environmentIntensity: 0)
    let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
    let scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 32, height: 32))
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (16 * 32 + 16) * 4
    return SIMD3(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

// Without scattering, a fully diffuse-transmitting dense volume returns almost nothing toward a front light; with
// scattering, light comes back out in the multiscatter color.
@Test(.requiresMetal4, .metalValidation) @MainActor func volumeScatterReturnsTintedLight() throws {
    let plain = try frontLitCenter(scatters: false)
    let scattered = try frontLitCenter(scatters: true)
    #expect(plain.x < 30 && plain.y < 30 && plain.z < 30, "\(plain)")
    #expect(scattered.z > 60 && scattered.z > scattered.x + 30, "\(scattered)")
}
