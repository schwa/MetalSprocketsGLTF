import CoreGraphics
import Foundation
import GeometryLite3D
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

// The Swift list mirrors the shader's kPBRToneMapping* values; PBR Neutral is 0, the default of zeroed uniforms.
@Test(.requiresMetal4, .requiresMetal4) func toneMappingsMatchTheShaderValues() {
    #expect(Int32(PBRToneMapping.allCases.count) == PBRShaderToneMapping.toneMappingCount.rawValue)
    #expect(PBRToneMapping.pbrNeutral.rawValue == 0)
    #expect(PBRToneMapping.agx.shaderValue == .toneMappingAgX)
}

/// The red channel (sRGB byte) of an unlit quad with linear base color 0.5, seen head-on with `toneMapping`.
@MainActor
private func unlitRed(_ toneMapping: PBRToneMapping) throws -> Int {
    let file = try makeExtensionMaterialFile(#"{"KHR_materials_unlit": {}}"#, extensionsUsed: ["KHR_materials_unlit"])
    // makeExtensionMaterialFile's material has no base color factor; patch one in.
    let json = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: #"{"emissiveFactor""#, with: #"{"pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.5, 0.5, 1]}, "emissiveFactor""#)
    try json.write(to: file, atomically: true, encoding: .utf8)
    let asset = try GLTFAsset(url: file)
    let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
    var lighting = PBRLighting()
    lighting.toneMapping = toneMapping
    let scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 32, height: 32))
    let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(scene).cgImage
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    return Int(try #require(context.data).assumingMemoryBound(to: UInt8.self)[(16 * 32 + 16) * 4])
}

/// sRGB encoding of a linear value, as a byte.
private func sRGBByte(_ linear: Double) -> Int {
    Int((linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055) * 255 + 0.5)
}

// Each operator applies its own curve (ACES and AgX are checked against three.js in the reference comparisons).
@Test(.requiresMetal4, .metalValidation) @MainActor func toneMappingAppliesTheChosenOperator() throws {
    #expect(abs(try unlitRed(.linear) - sRGBByte(0.5)) <= 2)
    #expect(abs(try unlitRed(.reinhard) - sRGBByte(0.5 / 1.5)) <= 2)
    #expect(abs(try unlitRed(.pbrNeutral) - sRGBByte(0.5 - 0.04)) <= 2)
    #expect(try unlitRed(.acesFilmic) != unlitRed(.agx))
}

// Into an rgba16Float target without tone mapping, a surface brighter than white keeps its value above 1 (HDR).
@Test(.requiresMetal4, .metalValidation) @MainActor func floatTargetKeepsValuesAboveOne() throws {
    let asset = try GLTFAsset(url: makeExtensionMaterialFile(#"{"KHR_materials_unlit": {}}"#, extensionsUsed: ["KHR_materials_unlit"]))
    let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
    var lighting = PBRLighting()
    lighting.toneMapping = .none
    lighting.exposure = 4
    let scene = GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 32, height: 32))
    let texture = try OffscreenRenderer.hdr(size: CGSize(width: 32, height: 32)).render(scene).texture
    #expect(texture.pixelFormat == .rgba16Float)
    let pixels = try texture.float16Pixels()
    // The base color is white (1) times exposure 4.
    #expect(abs(Float(pixels[(16 * 32 + 16) * 4]) - 4) < 0.01, "\(pixels[(16 * 32 + 16) * 4])")
}
