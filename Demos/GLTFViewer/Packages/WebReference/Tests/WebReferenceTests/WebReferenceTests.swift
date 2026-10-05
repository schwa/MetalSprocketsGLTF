import CoreGraphics
import Foundation
import MetalSprocketsGLTF
import WebReference
import MetalSprocketsPBR
import Testing

// Skipped when three.js is neither cached nor downloadable (the first run downloads it from a CDN).
@Suite(.serialized, .enabled(if: SampleAssets.isAvailable && GLTFWebReference.isAvailable))
@MainActor
struct WebReferenceTests {
    // After a first run has cached three.js, the reference loads without the CDN.
    @Test(.timeLimit(.minutes(1))) func worksOfflineFromTheCache() async throws {
        let url = SampleAssets.modelsDirectory.appending(path: "Box/glTF-Binary/Box.glb")
        // Warm the cache.
        let warm = GLTFWebReference()
        try await warm.load(url)

        let cdn = GLTFWebReference.cdnBaseURL
        GLTFWebReference.cdnBaseURL = URL(string: "https://cdn.invalid")!
        defer { GLTFWebReference.cdnBaseURL = cdn }
        let reference = GLTFWebReference()
        try await reference.setFixedSize(width: 32, height: 32)
        try await reference.load(url)
        let image = try await reference.snapshot()
        #expect(image.width == 32)
    }

    // The reference must use only the lights it is given, not lights GLTFLoader reads from the file.
    @Test func ignoresLightsDefinedInTheFile() async throws {
        let url = SampleAssets.modelsDirectory.appending(path: "LightVisibility/glTF-Binary/LightVisibility.glb")
        let asset = try GLTFAsset(url: url)
        #expect(!asset.lights.isEmpty)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)

        let reference = GLTFWebReference()
        try await reference.setFixedSize(width: 64, height: 64)
        try await reference.setBackground(.zero)
        try await reference.load(url)
        try await reference.setLighting(PBRLighting(lights: [], environmentIntensity: 0), mode: .matched)
        try await reference.setView(viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        let image = try await reference.snapshot()

        #expect(try brightestChannel(image) == 0, "Unlit scene rendered with light")
    }

    // If WebKit kills the page's process, the reference reloads the page and keeps working, at the same size.
    @Test(.timeLimit(.minutes(1))) func recoversFromContentProcessTermination() async throws {
        let url = SampleAssets.modelsDirectory.appending(path: "Box/glTF-Binary/Box.glb")
        let asset = try GLTFAsset(url: url)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
        let reference = GLTFWebReference()
        try await reference.setFixedSize(width: 48, height: 48)
        try await reference.setBackground(.zero)
        try await reference.load(url)

        // Simulate a crash by killing the page's process. Its identifier is private WebKit SPI, used only here;
        // WebKit's own _killWebContentProcess does not report a termination, so it cannot stand in for one.
        let processIdentifier = try #require(reference.webView.value(forKey: "_webProcessIdentifier") as? Int32)
        // 0 or our own identifier would kill this process or its whole process group.
        try #require(processIdentifier > 0 && processIdentifier != getpid())
        kill(processIdentifier, SIGKILL)
        for _ in 0 ..< 50 where reference.terminationCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(reference.terminationCount == 1)

        try await reference.load(url)
        try await reference.setLighting(PBRLighting(asset: asset), mode: .matched)
        try await reference.setView(viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        let image = try await reference.snapshot()
        #expect(image.width == 48 && image.height == 48)
        #expect(try brightestChannel(image) > 0, "Nothing rendered after the reload")
    }

    // A .gltf's external buffers and images load from beside the model file.
    @Test(.timeLimit(.minutes(1))) func loadsExternalResources() async throws {
        let url = SampleAssets.modelsDirectory.appending(path: "AnimatedTriangle/glTF/AnimatedTriangle.gltf")
        let asset = try GLTFAsset(url: url)
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: 1, yaw: 0, pitch: 0)
        let reference = GLTFWebReference()
        try await reference.setFixedSize(width: 48, height: 48)
        try await reference.setBackground(.zero)
        try await reference.load(url)
        try await reference.setLighting(PBRLighting(asset: asset), mode: .matched)
        try await reference.setView(viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        let image = try await reference.snapshot()
        #expect(try brightestChannel(image) > 100, "Nothing rendered: the external buffers did not load")
    }

    func brightestChannel(_ image: CGImage) throws -> UInt8 {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var brightest: UInt8 = 0
        for index in 0 ..< image.width * image.height {
            brightest = max(brightest, pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2])
        }
        return brightest
    }
}
