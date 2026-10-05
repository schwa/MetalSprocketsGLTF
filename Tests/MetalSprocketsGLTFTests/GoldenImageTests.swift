import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import Testing
import UniformTypeIdentifiers

// Renders a curated set of Khronos sample models and compares them against stored golden images.
//
// To add or update a golden: delete it (or add the model to `models`), run the tests, and copy the image named in the
// failure from the output directory into Tests/MetalSprocketsGLTFTests/GoldenImages.

@Suite(.serialized, .metalValidation, .enabled(if: SampleAssets.isAvailable))
struct GoldenImageTests {
    static let models = [
        "AlphaBlendModeTest",
        "BoxVertexColors",
        "DamagedHelmet",
        "LightsPunctualLamp",
        "MetalRoughSpheres",
        "NormalTangentMirrorTest",
        "OrientationTest",
        "TextureCoordinateTest",
        "TextureEncodingTest",
        "TextureSettingsTest",
        "TextureTransformTest",
        "UnlitTest",
        "VertexColorTest",
    ]

    /// Yaw and pitch in degrees; models not listed are viewed head-on.
    static let cameraAngles: [String: SIMD2<Float>] = [
        // Matches the Khronos screenshot so all three arrows are visible.
        "OrientationTest": [45, -30],
    ]

    static let size = 256
    // Exact match: renders are bit-identical across runs on the machine that recorded the goldens (Apple silicon).
    // Other GPUs or driver versions may need the goldens re-recorded.
    static let psnrThreshold = 120.0
    static let outputDirectory = FileManager.default.temporaryDirectory.appending(path: "MetalSprocketsGLTF-GoldenImages")

    @Test(arguments: models)
    func matchesGolden(_ name: String) throws {
        let image = try render(name)
        let goldens = try #require(Bundle.module.url(forResource: "GoldenImages", withExtension: nil))
        let comparison = GoldenImageComparison(imageDirectory: goldens, psnrThreshold: Self.psnrThreshold, failureOutputDirectory: Self.outputDirectory)
        do {
            let matches = try comparison.image(image: image, matchesGoldenImageNamed: name)
            if !matches {
                Issue.record("\(name) does not match its golden image. \(try saveFailure(name, image: image, goldens: goldens))")
            }
        } catch GoldenImageError.noGoldenImage(let savedTo) {
            Issue.record("No golden image for \(name). Rendered image saved to \(savedTo?.path ?? "nowhere").")
        }
    }

    func render(_ name: String) throws -> CGImage {
        let directory = SampleAssets.modelsDirectory.appending(path: name)
        // Prefer the self-contained binary; some test models only ship as .gltf.
        let candidates = [directory.appending(path: "glTF-Binary/\(name).glb"), directory.appending(path: "glTF/\(name).gltf")]
        let url = try #require(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, "No sample file for \(name)")
        let asset = try GLTFAsset(url: url)
        let angles = Self.cameraAngles[name] ?? .zero
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: angles.x * .pi / 180, pitch: angles.y * .pi / 180)
        let renderer = try OffscreenRenderer(size: CGSize(width: Self.size, height: Self.size), clearDepth: 0)
        return try renderer.render(
            try RenderPass {
                GLTFRenderer(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
            }
        ).cgImage
    }

    /// Writes the actual render and a difference image next to each other for inspection.
    func saveFailure(_ name: String, image: CGImage, goldens: URL) throws -> String {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let goldenURL = goldens.appending(path: "\(name).png")
        // GoldenImage stores goldens in extended linear sRGB and refuses to compare across color spaces.
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let actualURL = Self.outputDirectory.appending(path: "\(name)-actual.png")
        try writePNG(try #require(image.copy(colorSpace: space)), to: actualURL)
        let differenceURL = Self.outputDirectory.appending(path: "\(name)-difference.png")
        try writePNG(try ImageComparison().differenceImage(actualURL, goldenURL, gain: 8), to: differenceURL)
        let psnr = try ImageComparison().compare(actualURL, goldenURL).psnr
        return "PSNR \(String(format: "%.1f", psnr)) dB. Actual: \(actualURL.path). Difference (8×): \(differenceURL.path)."
    }

    func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
    }
}
