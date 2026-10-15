import CoreGraphics
import Foundation
import GoldenImage
import GeometryLite3D
import ImageIO
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing
import UniformTypeIdentifiers

/// A 1×1 white PNG.
func makePNG() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A triangle whose material has a normal texture and an occlusion texture with the given scale and strength.
func makeMaterialTriangleFile(normalScale: Float, occlusionStrength: Float) throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let png = try makePNG().base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0,
      "scenes": [{"nodes": [0]}],
      "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{
        "normalTexture": {"index": 0, "scale": \(normalScale)},
        "occlusionTexture": {"index": 0, "strength": \(occlusionStrength)}
      }],
      "textures": [{"source": 0}],
      "images": [{"uri": "data:image/png;base64,\(png)"}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A camera-facing quad (two triangles) with a dielectric, smooth, fully transmissive material whose volume
/// absorbs everything but red.
func makeTransmissiveQuadFile() throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
    let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    let buffer = (positions + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_transmission", "KHR_materials_volume"],
      "scene": 0,
      "scenes": [{"nodes": [0]}],
      "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "material": 0}]}],
      "materials": [{
        "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0},
        "extensions": {
          "KHR_materials_transmission": {"transmissionFactor": 1},
          "KHR_materials_volume": {"thicknessFactor": 1, "attenuationDistance": 0.05, "attenuationColor": [1, 0, 0]}
        }
      }],
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

/// A triangle whose material carries the given material extensions JSON.
func makeExtensionMaterialFile(_ extensions: String, extensionsUsed: [String], textures: String = "[]", images: String = "[]") throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let used = extensionsUsed.map { "\"\($0)\"" }.joined(separator: ", ")
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": [\(used)],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"emissiveFactor": [1, 1, 1], "extensions": \(extensions)}],
      "textures": \(textures),
      "images": \(images),
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A clear, thin transmissive quad at z = 0 in front of a larger red quad at z = -1.
///
/// By default the red quad is unlit and faces the camera. With `backIsTransmissiveBackFace`, it is instead a
/// double-sided transmissive surface with red emission that faces away, so only its back face is toward the camera.
func makeGlassInFrontOfRedFile(backIsTransmissiveBackFace: Bool = false) throws -> URL {
    let front: [Float] = [-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]
    let facingBack: [Float] = [-2, -2, -1, 2, -2, -1, 2, 2, -1, -2, -2, -1, 2, 2, -1, -2, 2, -1]
    let facingAway: [Float] = [-2, -2, -1, 2, 2, -1, 2, -2, -1, -2, -2, -1, -2, 2, -1, 2, 2, -1]
    let back = backIsTransmissiveBackFace ? facingAway : facingBack
    let backMaterial = backIsTransmissiveBackFace
        ? #"{"doubleSided": true, "emissiveFactor": [1, 0, 0], "pbrMetallicRoughness": {"baseColorFactor": [0, 0, 0, 1], "metallicFactor": 0}, "extensions": {"KHR_materials_transmission": {"transmissionFactor": 1}}}"#
        : #"{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}"#
    let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    let buffer = (front + back + normals).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_transmission", "KHR_materials_unlit"],
      "scene": 0, "scenes": [{"nodes": [0, 1]}], "nodes": [{"mesh": 0}, {"mesh": 1}],
      "meshes": [
        {"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 2}, "material": 0}]},
        {"primitives": [{"attributes": {"POSITION": 1, "NORMAL": 2}, "material": 1}]}
      ],
      "materials": [
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0}, "extensions": {"KHR_materials_transmission": {"transmissionFactor": 1}}},
        \(backMaterial)
      ],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3", "min": [-2, -2, -1], "max": [2, 2, -1]},
        {"bufferView": 2, "componentType": 5126, "count": 6, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 72},
        {"buffer": 0, "byteOffset": 72, "byteLength": 72},
        {"buffer": 0, "byteOffset": 144, "byteLength": 72}
      ],
      "buffers": [{"byteLength": 216, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A triangle whose default material is red, with KHR_materials_variants "Blue" (material 1) and "Plain" (no mapping).
func makeVariantsTriangleFile() throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = positions.withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_variants"],
      "extensions": {"KHR_materials_variants": {"variants": [{"name": "Blue"}, {"name": "Plain"}]}},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0,
        "extensions": {"KHR_materials_variants": {"mappings": [{"material": 1, "variants": [0]}]}}}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}}, {"pbrMetallicRoughness": {"baseColorFactor": [0, 0, 1, 1]}}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Suite(.requiresMetal4, .metalValidation)
struct MaterialTests {
    // KHR_materials_variants: a variant swaps in its mapped material; unmapped primitives keep their default.
    @Test func appliesMaterialVariants() throws {
        let url = try makeVariantsTriangleFile()
        let defaultAsset = try GLTFAsset(url: url)
        #expect(defaultAsset.variantNames == ["Blue", "Plain"])
        #expect(defaultAsset.opaqueInstances.first?.material.uniforms.baseColorFactor == [1, 0, 0, 1])
        #expect(try GLTFAsset(url: url, variant: 0).opaqueInstances.first?.material.uniforms.baseColorFactor == [0, 0, 1, 1])
        #expect(try GLTFAsset(url: url, variant: 1).opaqueInstances.first?.material.uniforms.baseColorFactor == [1, 0, 0, 1])
    }

    // Switching variant on a loaded asset shares its materials instead of reloading, and can switch back.
    @Test func switchesVariantWithoutReloading() throws {
        let defaultAsset = try GLTFAsset(url: makeVariantsTriangleFile())
        let blue = try defaultAsset.variant(0)
        #expect(blue.variant == 0)
        #expect(blue.opaqueInstances.first?.material.uniforms.baseColorFactor == [0, 0, 1, 1])
        #expect(blue.opaqueInstances.first?.material === defaultAsset.materials[1])
        #expect(try blue.variant(nil).opaqueInstances.first?.material.uniforms.baseColorFactor == [1, 0, 0, 1])
        #expect(throws: (any Error).self) { try defaultAsset.variant(2) }
    }

    /// Center pixel (sRGB bytes) of a 32\u{00d7}32 head-on render, with or without a transmission pre-pass.
    func renderGlassCenter(withTransmissionPass: Bool, backIsTransmissiveBackFace: Bool = false, target givenTarget: GLTFTransmissionTarget? = nil) throws -> (red: Int, green: Int, blue: Int) {
        let asset = try GLTFAsset(url: makeGlassInFrontOfRedFile(backIsTransmissiveBackFace: backIsTransmissiveBackFace))
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([0, 0, 1]), specularSize: 16, irradianceSize: 4))
        let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
        let target = withTransmissionPass ? try givenTarget ?? GLTFTransmissionTarget(size: 64) : nil
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
        let image = try renderer.render(
            try Group {
                if let target {
                    GLTFTransmissionPass(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, target: target)
                }
                try RenderPass {
                    GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, transmissionTarget: target)
                }
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let center = (16 * 32 + 16) * 4
        return (Int(pixels[center]), Int(pixels[center + 1]), Int(pixels[center + 2]))
    }

    // Clear glass shows the red quad behind it when the opaque scene was rendered first.
    @Test func transmissionShowsSceneBehind() throws {
        let target = try GLTFTransmissionTarget(size: 64)
        let pixel = try renderGlassCenter(withTransmissionPass: true, target: target)
        #expect(pixel.red > pixel.blue + 80, "Expected the red quad through the glass, got \(pixel)")
        // Without double-sided glass the backdrop copy is never needed, so it is never allocated.
        #expect(!target.hasBackdrop)
    }

    // Like three.js, glass sees the back faces of double-sided transmissive surfaces behind it.
    @Test func transmissionShowsTransmissiveBackFacesBehind() throws {
        let target = try GLTFTransmissionTarget(size: 64)
        let pixel = try renderGlassCenter(withTransmissionPass: true, backIsTransmissiveBackFace: true, target: target)
        #expect(target.hasBackdrop, "Double-sided glass needs the backdrop")
        #expect(pixel.red > pixel.blue + 80, "Expected the red back face through the glass, got \(pixel)")
    }

    // GLTFScene runs the transmission pre-pass itself: glass shows the red quad behind it.
    @Test func sceneShowsWhatIsBehindGlass() throws {
        let asset = try GLTFAsset(url: makeGlassInFrontOfRedFile())
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([0, 0, 1]), specularSize: 16, irradianceSize: 4))
        let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
        let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(
            GLTFScene(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting, viewportSize: CGSize(width: 32, height: 32))
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let center = (16 * 32 + 16) * 4
        #expect(pixels[center] > pixels[center + 2] + 80, "Expected the red quad through the glass, got \(pixels[center]), \(pixels[center + 2])")
    }

    // The scene keeps one transmission target per viewport size.
    @Test func transmissionTargetCacheFollowsViewportSize() throws {
        let cache = PBRTransmissionTargetCache()
        let first = try cache.target(width: 64, height: 48)
        #expect(try cache.target(width: 64, height: 48) === first)
        let resized = try cache.target(width: 128, height: 48)
        #expect(resized !== first && resized.width == 128 && resized.height == 48)
    }

    // GLTFScene draws exactly what the hand-assembled pre-pass, background and renderer drew.
    @Test(.enabled(if: SampleAssets.isAvailable)) func sceneMatchesHandAssembly() throws {
        let asset = try GLTFAsset(url: SampleAssets.modelsDirectory.appending(path: "TransmissionTest/glTF-Binary/TransmissionTest.glb"))
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let lighting = PBRLighting(asset: asset)
        let size = 96
        let target = try GLTFTransmissionTarget(width: size, height: size)
        let handAssembled = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(try Group {
            GLTFTransmissionPass(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, target: target, showsBackground: true)
            try RenderPass {
                PBREnvironmentBackground(lighting: lighting, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, transmissionTarget: target)
            }
        }).cgImage
        let scene = try OffscreenRenderer(size: CGSize(width: size, height: size), clearDepth: 0).render(
            GLTFScene(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, showsBackground: true, viewportSize: CGSize(width: size, height: size))
        ).cgImage
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let psnr = try ImageComparison().compare(try #require(scene.copy(colorSpace: space)), try #require(handAssembled.copy(colorSpace: space))).psnr
        #expect(psnr > 100, "GLTFScene differs from the hand-assembled scene: \(psnr) dB")
    }

    // The transmission target can match a non-square view, so glass samples the scene behind at screen resolution.
    @Test func transmissionTargetMatchesViewSize() throws {
        let target = try GLTFTransmissionTarget(width: 640, height: 360)
        #expect(target.width == 640 && target.height == 360)
        #expect(target.color.mipmapLevelCount > 1)
        #expect(target.depth.width == 640 && target.depth.height == 360)
    }

    // Merged transmissive drawing (main pass and back-face pre-pass) renders exactly like per-batch drawing.
    @Test(.enabled(if: SampleAssets.isAvailable)) func mergedTransmissionMatchesPerBatchDrawing() throws {
        let asset = try GLTFAsset(url: SampleAssets.modelsDirectory.appending(path: "TransmissionTest/glTF-Binary/TransmissionTest.glb"))
        #expect(asset.mergedTransmissive != nil)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let lighting = PBRLighting(asset: asset)
        func render(merging: Bool) throws -> CGImage {
            let target = try GLTFTransmissionTarget(size: 256)
            var prePass = GLTFTransmissionPass(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, target: target)
            prePass.renderer.usesMergedGeometry = merging
            var renderer = GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, transmissionTarget: target)
            renderer.usesMergedGeometry = merging
            return try OffscreenRenderer(size: CGSize(width: 128, height: 128), clearDepth: 0).render(try Group {
                prePass
                try RenderPass { renderer }
            }).cgImage
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let merged = try #require(try render(merging: true).copy(colorSpace: space))
        let separate = try #require(try render(merging: false).copy(colorSpace: space))
        let psnr = try ImageComparison().compare(merged, separate).psnr
        #expect(psnr > 60, "Merged and per-batch transmission renders differ: \(psnr) dB")
    }

    // Without a pre-pass, transmission falls back to refracting the (blue) environment.
    @Test func transmissionFallsBackToEnvironment() throws {
        let pixel = try renderGlassCenter(withTransmissionPass: false)
        #expect(pixel.blue > pixel.red + 80, "Expected the blue environment through the glass, got \(pixel)")
    }

    @Test func readsEmissiveStrength() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_emissive_strength": {"emissiveStrength": 5}}"#, extensionsUsed: ["KHR_materials_emissive_strength"])
        let material = try #require(try GLTFAsset(url: url).materials.first)
        #expect(material.uniforms.emissiveStrength == 5)
    }

    @Test func readsIridescence() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_iridescence": {"iridescenceFactor": 0.75, "iridescenceIor": 1.8, "iridescenceThicknessMinimum": 200, "iridescenceThicknessMaximum": 800}}"#, extensionsUsed: ["KHR_materials_iridescence"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.iridescenceFactor == 0.75)
        #expect(uniforms.iridescenceIor == 1.8)
        #expect(uniforms.iridescenceThicknessMinimum == 200)
        #expect(uniforms.iridescenceThicknessMaximum == 800)
        #expect(uniforms.iridescence.enabled == 0)
    }

    @Test func readsAnisotropy() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_anisotropy": {"anisotropyStrength": 0.6, "anisotropyRotation": 1.5}}"#, extensionsUsed: ["KHR_materials_anisotropy"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.anisotropyStrength == 0.6)
        #expect(uniforms.anisotropyRotation == 1.5)
        #expect(uniforms.anisotropy.enabled == 0)
    }

    @Test func anisotropyDefaultsToOff() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_anisotropy": {}}"#, extensionsUsed: ["KHR_materials_anisotropy"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.anisotropyStrength == 0)
        #expect(uniforms.anisotropyRotation == 0)
    }

    // The material texture slots follow the shader's PBRMaterialTextureIndex order, with no uniform slot or
    // animation-pointer path used twice.
    @Test func materialTextureSlotsMatchTheShaderLayout() {
        let slots = GLTFMaterialTextureSlot.all
        #expect(slots.count == Int(kPBRMaterialTextureCount.rawValue))
        #expect(slots.map { Int($0.index.rawValue) } == Array(0 ..< slots.count))
        #expect(Set(slots.map(\.uniform)).count == slots.count)
        let paths = slots.flatMap(\.pointerPaths)
        #expect(Set(paths).count == paths.count)
        #expect(GLTFMaterialTextureSlot.byPointerPath.count == paths.count)
    }

    // Every material feature is listed once, is a supported extension, and its slots and factors are reachable by
    // animation pointer.
    @Test func materialFeaturesAreConsistent() {
        let names = GLTFMaterialFeature.all.compactMap(\.extensionName)
        #expect(Set(names).count == names.count)
        #expect(GLTFMaterialFeature.extensionNames.isSubset(of: GLTFAsset.builtInExtensions))
        let factorCount = GLTFMaterialFeature.all.reduce(0) { $0 + $1.animatableFactors.count }
        #expect(GLTFMaterialFeature.animatableFactors.count == factorCount)
        for path in GLTFMaterialFeature.animatableFactors.keys {
            #expect(GLTFAnimationPointer.target("/materials/0/\(path)") == .material(0, path))
        }
        // The default material: core glTF defaults and every extension absent.
        let uniforms = GLTFMaterialFeature.uniforms(for: nil)
        #expect(uniforms.baseColorFactor == [1, 1, 1, 1])
        #expect(uniforms.ior == 1.5)
        #expect(uniforms.specularFactor == 1)
        #expect(uniforms.attenuationDistance == .infinity)
        #expect(uniforms.specularGlossiness == 0)
    }

    // The argument buffer holds each slot's texture and sampler handles in slot order.
    @Test func materialResourceBufferFollowsTheSlots() throws {
        let material = try #require(try GLTFAsset(url: makeMaterialTriangleFile(normalScale: 1, occlusionStrength: 1)).materials.first)
        #expect(material.uniforms.normal.enabled != 0 && material.uniforms.baseColor.enabled == 0)
        let count = Int(kPBRMaterialTextureCount.rawValue)
        let handles = material.resourceBuffer.contents().bindMemory(to: UInt64.self, capacity: count * 2)
        for (index, binding) in material.textureBindings.enumerated() {
            #expect(handles[index] == binding.texture.gpuResourceID._impl)
            #expect(handles[count + index] == binding.sampler.gpuResourceID._impl)
        }
        #expect(material[texture: kPBRTextureNormal].texture !== material[texture: kPBRTextureBaseColor].texture, "The normal slot should hold the file's texture, not the placeholder")
    }

    // A specular-glossiness material's diffuse texture fills the base color slot, keyed by its own pointer path.
    @Test func specularGlossinessTexturesUseTheirSlots() throws {
        let png = try makePNG().base64EncodedString()
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_pbrSpecularGlossiness": {"diffuseTexture": {"index": 0}}}"#, extensionsUsed: ["KHR_materials_pbrSpecularGlossiness"], textures: "[{\"source\": 0}]", images: "[{\"uri\": \"data:image/png;base64,\(png)\"}]")
        let material = try #require(try GLTFAsset(url: url).materials.first)
        #expect(material.uniforms.baseColor.enabled != 0)
        #expect(material.textureTransforms[GLTFMaterialTextureSlot.diffusePath]?.slot == \PBRMaterialUniforms.baseColor)
        #expect(material.textureTransforms[GLTFMaterialTextureSlot.baseColorPath] == nil)
    }

    // Specular-glossiness maps onto metallic-roughness plus KHR_materials_specular: diffuse becomes the base color,
    // metallic 0, specular divided by the default dielectric F0 (0.04), and glossiness drives roughness.
    @Test func readsSpecularGlossiness() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_pbrSpecularGlossiness": {"diffuseFactor": [0.5, 0.25, 1, 1], "specularFactor": [0.02, 0.04, 0.08], "glossinessFactor": 0.75}}"#, extensionsUsed: ["KHR_materials_pbrSpecularGlossiness"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.specularGlossiness == 1)
        #expect(uniforms.baseColorFactor == [0.5, 0.25, 1, 1])
        #expect(uniforms.metallicFactor == 0)
        #expect(abs(uniforms.glossinessFactor - 0.75) < 1e-6)
        #expect(simd_distance(uniforms.specularColorFactor, [0.5, 1, 2]) < 1e-5)
    }

    @Test func readsSheen() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_sheen": {"sheenColorFactor": [0.5, 0.25, 1], "sheenRoughnessFactor": 0.4}}"#, extensionsUsed: ["KHR_materials_sheen"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.sheenColorFactor == [0.5, 0.25, 1])
        #expect(uniforms.sheenRoughnessFactor == 0.4)
        #expect(uniforms.sheenColor.enabled == 0)
    }

    @Test func readsClearcoat() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_clearcoat": {"clearcoatFactor": 0.8, "clearcoatRoughnessFactor": 0.2}}"#, extensionsUsed: ["KHR_materials_clearcoat"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.clearcoatFactor == 0.8)
        #expect(uniforms.clearcoatRoughnessFactor == 0.2)
        #expect(uniforms.clearcoatNormalScale == 1)
        #expect(uniforms.clearcoatNormal.enabled == 0)
    }

    @Test func readsDispersion() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_dispersion": {"dispersion": 2.5}}"#, extensionsUsed: ["KHR_materials_dispersion"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.dispersion == 2.5)
    }

    @Test func clearcoatDefaultsToOff() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_clearcoat": {}}"#, extensionsUsed: ["KHR_materials_clearcoat"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.clearcoatFactor == 0)
        #expect(uniforms.clearcoatRoughnessFactor == 0)
    }

    @Test func sheenDefaultsToOff() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_sheen": {}}"#, extensionsUsed: ["KHR_materials_sheen"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.sheenColorFactor == .zero)
        #expect(uniforms.sheenRoughnessFactor == 0)
    }

    @Test func iridescenceDefaultsToOff() throws {
        let url = try makeExtensionMaterialFile(#"{"KHR_materials_iridescence": {}}"#, extensionsUsed: ["KHR_materials_iridescence"])
        let uniforms = try #require(try GLTFAsset(url: url).materials.first).uniforms
        #expect(uniforms.iridescenceFactor == 0)
        #expect(uniforms.iridescenceIor == 1.3)
        #expect(uniforms.iridescenceThicknessMinimum == 100)
        #expect(uniforms.iridescenceThicknessMaximum == 400)
    }

    @Test func readsTransmissionAndVolume() throws {
        let asset = try GLTFAsset(url: makeTransmissiveQuadFile())
        let uniforms = try #require(asset.materials.first).uniforms
        #expect(uniforms.transmissionFactor == 1)
        #expect(uniforms.thicknessFactor == 1)
        #expect(uniforms.attenuationDistance == 0.05)
        #expect(uniforms.attenuationColor == [1, 0, 0])
    }

    // Light passing through the red-absorbing volume comes out red; an opaque white surface would render white.
    @Test func transmittedLightIsAttenuated() throws {
        let asset = try GLTFAsset(url: makeTransmissiveQuadFile())
        let lighting = PBRLighting(environment: try PBREnvironment(source: .uniform([1, 1, 1]), specularSize: 16, irradianceSize: 4))
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0)
        let image = try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting)
            }
        ).cgImage
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let center = (16 * 32 + 16) * 4
        let (red, green, blue) = (Int(pixels[center]), Int(pixels[center + 1]), Int(pixels[center + 2]))
        #expect(red > green + 80 && red > blue + 80, "Expected red transmitted light, got (\(red), \(green), \(blue))")
    }

    @Test func readsNormalScaleAndOcclusionStrength() throws {
        let asset = try GLTFAsset(url: makeMaterialTriangleFile(normalScale: 0.25, occlusionStrength: 0.5))
        #expect(asset.warnings.isEmpty, "\(asset.warnings)")
        let material = try #require(asset.materials.first)
        #expect(material.uniforms.normal.enabled != 0)
        #expect(material.uniforms.occlusion.enabled != 0)
        #expect(material.uniforms.normalScale == 0.25)
        #expect(material.uniforms.occlusionStrength == 0.5)
    }
}
