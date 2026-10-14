import CoreGraphics
import Foundation
import GoldenImage
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import Testing
import WebReference

// Compares GLTFRenderer with the three.js reference for every binary Khronos sample model.
//
// The renderers legitimately differ, so there is no fixed threshold. Each scene's PSNR is recorded in
// ReferencePSNR.json, and a scene fails only if it gets noticeably worse. Run with RECORD_REFERENCE_PSNR=1 to
// record new values (for new scenes, or after an improvement). Skipped when three.js is neither cached nor
// downloadable (the first run downloads it from a CDN).

enum ReferencePSNR {
    static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "ReferencePSNR.json")
    static let isRecording = ProcessInfo.processInfo.environment["RECORD_REFERENCE_PSNR"] == "1"
    /// How far below its recorded PSNR a scene may fall before it counts as a regression.
    static let tolerance = 0.5

    static func load() -> [String: Double] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    static func record(_ name: String, _ psnr: Double) throws {
        var values = load()
        values[name] = (psnr * 10).rounded() / 10
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: url)
    }
}

@Suite(.serialized, .metalValidation, .enabled(if: SampleAssets.isAvailable && GLTFWebReference.isAvailable))
@MainActor
struct ReferenceComparisonTests {
    static let size = 128
    /// One web view for every scene; loading the page and three.js once keeps the suite fast.
    static var reference: GLTFWebReference?

    @Test(arguments: SampleAssets.preferredModels())
    func matchesReference(_ model: SampleAssets.Model) async throws {
        let url = try #require(model.preferredURL)
        let asset = try GLTFAsset(url: url)
        guard !asset.opaqueInstances.isEmpty || !asset.blendedInstances.isEmpty else {
            return
        }
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let lighting = PBRLighting(asset: asset)

        let renderer = try OffscreenRenderer(size: CGSize(width: Self.size, height: Self.size), clearDepth: 0)
        let metalImage = try renderer.render(
            GLTFScene(asset: asset, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, viewportSize: CGSize(width: Self.size, height: Self.size))
        ).cgImage

        let reference: GLTFWebReference
        if let existing = Self.reference {
            reference = existing
        } else {
            reference = GLTFWebReference()
            try await reference.setFixedSize(width: Self.size, height: Self.size)
            try await reference.setBackground(.zero)
            Self.reference = reference
        }
        func renderReference() async throws -> CGImage {
            try await reference.load(url)
            try await reference.setLighting(lighting, mode: .matched)
            try await reference.setAnimation(nil, time: 0)
            try await reference.setView(viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
            return try await reference.snapshot()
        }
        // WebKit occasionally kills the page's process; the reference reloads, so try this scene once more.
        let terminations = reference.terminationCount
        let webImage: CGImage
        do {
            webImage = try await renderReference()
        } catch {
            // The termination notice can arrive just after the failed call.
            if reference.terminationCount == terminations {
                try await Task.sleep(for: .seconds(1))
            }
            guard reference.terminationCount > terminations else { throw error }
            webImage = try await renderReference()
        }

        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let psnr = try ImageComparison().compare(try #require(metalImage.copy(colorSpace: space)), try #require(webImage.copy(colorSpace: space))).psnr

        if ReferencePSNR.isRecording {
            try ReferencePSNR.record(model.name, psnr)
            return
        }
        guard let baseline = ReferencePSNR.load()[model.name] else {
            Issue.record("No recorded reference PSNR for \(model.name) (now \(String(format: "%.1f", psnr)) dB). Run with RECORD_REFERENCE_PSNR=1.")
            return
        }
        #expect(psnr >= baseline - ReferencePSNR.tolerance, "\(model.name) PSNR against three.js fell to \(String(format: "%.1f", psnr)) dB from \(baseline) dB")
    }
}
