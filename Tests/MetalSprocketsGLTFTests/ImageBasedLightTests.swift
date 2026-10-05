import CoreGraphics
import Foundation
import ImageIO
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing
import UniformTypeIdentifiers

/// A 4 x 4 PNG of one color, non-premultiplied RGBA.
private func facePNG(_ color: SIMD4<UInt8>) throws -> Data {
    let pixels = (0 ..< 16).flatMap { _ in [color.x, color.y, color.z, color.w] }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A triangle whose scene uses an EXT_lights_image_based light with one flat color per cube face.
private func makeImageBasedLightFile(faces: [SIMD4<UInt8>], rotation: SIMD4<Float> = [0, 0, 0, 1], intensity: Float = 1) throws -> URL {
    let images = try faces.map { #"{"uri": "data:image/png;base64,\#(try facePNG($0).base64EncodedString())"}"# }.joined(separator: ", ")
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let coefficients = Array(repeating: "[0, 0, 0]", count: 9).joined(separator: ", ")
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["EXT_lights_image_based"],
      "extensions": {"EXT_lights_image_based": {"lights": [{"rotation": [\(rotation.x), \(rotation.y), \(rotation.z), \(rotation.w)], "intensity": \(intensity),
        "irradianceCoefficients": [\(coefficients)], "specularImageSize": 4, "specularImages": [[0, 1, 2, 3, 4, 5]]}]}},
      "scene": 0, "scenes": [{"nodes": [0], "extensions": {"EXT_lights_image_based": {"light": 0}}}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
      "images": [\(images)],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// The equirectangular texel a world direction samples (as the shaders' equirectUV).
private func texel(_ light: GLTFImageBasedLight, _ direction: SIMD3<Float>) -> SIMD3<Float> {
    let d = simd_normalize(direction)
    let u = atan2(d.z, d.x) / (2 * .pi) + 0.5
    let v = 0.5 - asin(d.y) / .pi
    let column = min(Int(u * Float(light.width)), light.width - 1)
    let row = min(Int(v * Float(light.height)), light.height - 1)
    let base = (row * light.width + column) * 4
    return SIMD3(Float(light.rgba[base]), Float(light.rgba[base + 1]), Float(light.rgba[base + 2]))
}

struct ImageBasedLightTests {
    // Opaque gray levels: a face's value is (level / 255)^2.2 (RGBD with D = 1).
    let levels: [UInt8] = [40, 80, 120, 160, 200, 240]
    let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]

    func expected(_ level: UInt8, alpha: Float = 1) -> Float {
        pow(Float(level) / 255, 2.2) / alpha
    }

    // Each axis direction sees its own face, +X -X +Y -Y +Z -Z.
    @Test func facesLandOnTheirAxes() throws {
        let asset = try GLTFAsset(url: makeImageBasedLightFile(faces: levels.map { SIMD4($0, $0, $0, 255) }))
        let light = try #require(asset.imageBasedLight)
        #expect(light.width == 16 && light.height == 8)
        for (axis, level) in zip(axes, levels) {
            #expect(abs(texel(light, axis).x - expected(level)) < 0.01, "\(axis)")
        }
    }

    // A four-channel PNG is RGBD: alpha divides the color, so alpha 0.5 doubles it (beyond 1, i.e. HDR).
    @Test func unpacksRGBD() throws {
        let asset = try GLTFAsset(url: makeImageBasedLightFile(faces: Array(repeating: SIMD4(255, 255, 255, 128), count: 6)))
        let light = try #require(asset.imageBasedLight)
        #expect(abs(texel(light, [1, 0, 0]).x - 255 / 128) < 0.01)
    }

    // The light's rotation turns the environment: rotated 90° about +Y, +X sees what was at +Z... and intensity scales.
    @Test func appliesRotationAndIntensity() throws {
        let half = Float(0.5).squareRoot()
        let asset = try GLTFAsset(url: makeImageBasedLightFile(faces: levels.map { SIMD4($0, $0, $0, 255) }, rotation: [0, half, 0, half], intensity: 2))
        let light = try #require(asset.imageBasedLight)
        let rotation = simd_quatf(ix: 0, iy: half, iz: 0, r: half)
        for (axis, level) in zip(axes, levels) {
            #expect(abs(texel(light, rotation.act(axis)).x - 2 * expected(level)) < 0.02, "\(axis)")
        }
    }

    // Default lighting uses the file's environment; a scene without one gets nil.
    @Test func defaultLightingUsesTheFilesEnvironment() throws {
        let asset = try GLTFAsset(url: makeImageBasedLightFile(faces: levels.map { SIMD4($0, $0, $0, 255) }))
        let environment = try #require(try asset.environment())
        #expect(PBRLighting(asset: asset).environment === environment)
        #expect(try asset.environment() === environment)
        #expect(try GLTFAsset(url: makeTriangleFile()).environment() == nil)
    }

    // The Khronos sample decodes to HDR radiance without warnings.
    @Test(.enabled(if: SampleAssets.isAvailable)) func loadsTheSample() throws {
        let url = SampleAssets.modelsDirectory.appending(path: "EnvironmentTest/glTF-IBL/EnvironmentTest.gltf")
        let asset = try GLTFAsset(url: url)
        #expect(asset.warnings.isEmpty, "\(asset.warnings)")
        let light = try #require(asset.imageBasedLight)
        #expect(light.width == 1024 && light.height == 512)
        #expect(light.rgba.contains { $0 > 1 })
    }
}
