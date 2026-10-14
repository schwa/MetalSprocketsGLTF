import CoreGraphics
import Foundation
import GoldenImage
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsPBR
import simd
import Testing

// <repo>/Tests/MetalSprocketsGLTFBasisUTests/BasisUTests.swift -> <repo>/.sample-assets/Models
private let modelsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: ".sample-assets/Models", directoryHint: .isDirectory)
private let samplesAvailable = FileManager.default.fileExists(atPath: modelsDirectory.appending(path: "model-index.json").path)

private let options = GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder()])

/// Each KTX2 sample variant and the PNG/JPEG variant of the same model.
private let pairs: [(name: String, ktx: String, plain: String)] = [
    ("FlightHelmet", "glTF-KTX-BasisU/FlightHelmet.gltf", "glTF/FlightHelmet.gltf"),
    ("StainedGlassLamp", "glTF-KTX-BasisU/StainedGlassLamp.gltf", "glTF/StainedGlassLamp.gltf"),
    ("AnisotropyBarnLamp", "glTF-KTX-BasisU/AnisotropyBarnLamp.gltf", "glTF-Binary/AnisotropyBarnLamp.glb"),
    ("ChronographWatch", "glTF-KTX-BasisU/ChronographWatch.gltf", "glTF-Binary/ChronographWatch.glb")
]

// Without the decoder, a file that requires KHR_texture_basisu is rejected; with it, it loads without warnings.
@Test(.enabled(if: samplesAvailable)) func ktxVariantNeedsTheDecoder() throws {
    let url = modelsDirectory.appending(path: "FlightHelmet/glTF-KTX-BasisU/FlightHelmet.gltf")
    #expect(throws: GLTFUnsupportedExtensionsError.self) { try GLTFAsset(url: url) }
    let asset = try GLTFAsset(url: url, options: options)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
    #expect(asset.statistics.textures > 0)
}

// The KTX2 variant renders like the PNG/JPEG one. Transcoding is lossy, so they are close but not equal; a wrong
// color space (sRGB vs linear) would brighten or darken every textured surface and fail this.
@Test(.enabled(if: samplesAvailable), arguments: pairs.map(\.name))
func ktxVariantMatchesThePlainVariant(_ name: String) throws {
    let pair = try #require(pairs.first { $0.name == name })
    let directory = modelsDirectory.appending(path: name)
    let ktx = try GLTFAsset(url: directory.appending(path: pair.ktx), options: options)
    let plain = try GLTFAsset(url: directory.appending(path: pair.plain))
    #expect(ktx.warnings.isEmpty, "\(ktx.warnings)")
    let camera = PBRCamera.framing(plain.bounds, aspectRatio: 1)
    func render(_ asset: GLTFAsset) throws -> CGImage {
        try OffscreenRenderer(size: CGSize(width: 256, height: 256), clearDepth: 0).render(
            GLTFScene(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, viewportSize: CGSize(width: 256, height: 256))
        ).cgImage
    }
    let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let psnr = try ImageComparison().compare(try #require(render(ktx).copy(colorSpace: space)), try #require(render(plain).copy(colorSpace: space))).psnr
    #expect(psnr > 30, "\(name): KTX2 and plain renders differ (\(psnr) dB)")
}
