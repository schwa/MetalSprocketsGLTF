import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsGLTFMeshopt
import MetalSprocketsPBR
import simd
import UniformTypeIdentifiers

extension GLTFLoadOptions {
    /// Every optional extension this tool links.
    static var commandLine: GLTFLoadOptions {
        GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder(), GLTFASTCTextureDecoder()], bufferViewDecoders: [GLTFMeshoptDecoder()])
    }
}

extension PBRToneMapping: @retroactive ExpressibleByArgument {
    /// The case name in kebab case, e.g. aces-filmic.
    var argumentName: String {
        String(describing: self).replacing(/([a-z0-9])([A-Z])/) { "\($0.1)-\($0.2)" }.lowercased()
    }

    public init?(argument: String) {
        guard let value = Self.allCases.first(where: { $0.argumentName == argument }) else { return nil }
        self = value
    }
}

extension PBRDebugView: @retroactive ExpressibleByArgument {
    /// The case name in kebab case, e.g. shading-normal.
    var argumentName: String {
        String(describing: self).replacing(/([a-z0-9])([A-Z])/) { "\($0.1)-\($0.2)" }.lowercased()
    }

    public init?(argument: String) {
        guard let view = Self.allCases.first(where: { $0.argumentName == argument }) else { return nil }
        self = view
    }
}

@main
struct MSGLTFRender: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ms-gltf-render",
        abstract: "Render glTF files and benchmark the renderer.",
        subcommands: [GLTFRenderCommand.self, GLTFBenchCommand.self],
        defaultSubcommand: GLTFRenderCommand.self
    )
}

struct GLTFRenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "render", abstract: "Render a glTF/GLB file to a PNG.")

    @Argument(help: "Input .gltf or .glb file.")
    var input: String

    @Option(name: .shortAndLong, help: "Output PNG, or OpenEXR (.exr: rendered into a float target, linear, values above 1 kept with --tone-mapping none). Defaults to the input name with .png.")
    var output: String?

    @Option var width: Int = 1_024
    @Option var height: Int = 1_024

    @Option(help: "Use the glTF camera with this index instead of auto-framing.")
    var camera: Int?

    @Option(help: "Orbit yaw in degrees.")
    var yaw: Float = 30

    @Option(help: "Orbit pitch in degrees.")
    var pitch: Float = -20

    @Option var exposure: Float = 1

    @Option(help: "Pose the scene with this glTF animation index.")
    var animation: Int?

    @Option(help: "Animation time in seconds.")
    var time: Float = 0

    @Flag(help: "Ignore lights in the file and use the default lighting.")
    var defaultLights = false

    @Option(help: "Equirectangular HDR image (.hdr, .exr) to light the scene with. Defaults to a procedural studio.")
    var environment: String?

    @Option(help: "Environment brightness multiplier.")
    var environmentIntensity: Float = 1

    @Option(help: "Turn the environment about +Y, in degrees (counter-clockwise seen from above).")
    var environmentRotation: Float = 0

    @Flag(help: "Draw the environment behind the model.")
    var background = false

    @Option(help: "Tone mapping: \(PBRToneMapping.allCases.map(\.argumentName).joined(separator: ", ")).")
    var toneMapping: PBRToneMapping = .pbrNeutral

    @Option(name: .customLong("disable-extension"), help: "Load as if the file did not use this extension (repeatable), e.g. to compare with three.js where it lacks one.")
    var disabledExtensions: [String] = []

    @Flag(help: "Draw triangle edges over the render.")
    var wireframe = false

    @Option(help: "Multisample antialiasing samples per pixel (1, 2, 4 or 8).")
    var msaa = 1

    @Option(help: "Draw at this fraction of the output size, then upscale with MetalFX spatial scaling (1 draws at full size).")
    var renderScale: Float = 1

    @Option(help: "Show one shading input instead of the lit color: \(PBRDebugView.allCases.map(\.argumentName).joined(separator: ", ")).")
    var debugView: PBRDebugView = .lit

    @Option(help: "Render this many frames with one renderer and print per-frame times. With --animation, each frame advances 1/60 s.")
    var benchmark: Int?

    @Flag(help: "With --benchmark, turn the model a little every frame, so each frame's scene differs as it does while interacting.")
    var orbit = false

    func run() throws {
        try MainActor.assumeIsolated {
            try render()
        }
    }

    /// Times `frames` frames and prints frame, GPU and CPU (frame minus GPU) times. With --animation each frame
    /// advances 1/60 s; with --orbit the model turns.
    @MainActor
    func runBenchmark<Content: Element>(frames: Int, renderer: OffscreenRenderer, asset: GLTFAsset, makeScene: (PBRPose?, simd_float4x4) throws -> Content) throws {
        let timings = try measureFrames(frames: frames, renderer: renderer) { frame in
            try makeScene(
                animation.map { asset.pose(animation: $0, time: time + Float(frame) / 60) },
                orbit ? orbitMatrix(center: asset.bounds.center, frame: frame) : matrix_identity_float4x4
            )
        }
        print("Benchmark: \(frames) frames at \(width)\u{00d7}\(height), \(asset.opaqueBatches.count + asset.blendedBatches.count) batches")
        print("  frame  \(timings.frame.description)")
        print("  gpu    \(timings.gpu.description)")
        print("  cpu    \(timings.cpu.description)")
    }

    @MainActor
    func render() throws {
        let inputURL = URL(fileURLWithPath: input)
        let outputURL = output.map { URL(fileURLWithPath: $0) } ?? inputURL.deletingPathExtension().appendingPathExtension("png")

        let start = Date()
        var options = GLTFLoadOptions.commandLine
        options.disabledExtensions = Set(disabledExtensions)
        let asset = try GLTFAsset(url: inputURL, options: options)
        print("Loaded in \(String(format: "%.2f", Date().timeIntervalSince(start)))s: \(asset.opaqueInstances.count) opaque, \(asset.blendedInstances.count) blended, \(asset.lights.count) lights, \(asset.cameras.count) cameras")
        for warning in asset.warnings {
            print("warning: \(warning)")
        }

        if let animation, !asset.animations.indices.contains(animation) {
            throw ValidationError("Animation \(animation) out of range (\(asset.animations.count) animations)")
        }
        let pose = animation.map { asset.pose(animation: $0, time: time) }

        let aspectRatio = Float(width) / Float(height)
        let gltfCamera: PBRCamera
        if let camera {
            // Cameras on animated nodes move with the pose.
            let cameras = pose.map { asset.cameras(pose: $0) } ?? asset.cameras
            guard camera < cameras.count else {
                throw ValidationError("Camera \(camera) out of range (\(cameras.count) cameras)")
            }
            gltfCamera = PBRCamera(cameras[camera].camera, worldMatrix: cameras[camera].worldMatrix, aspectRatio: aspectRatio)
        } else {
            gltfCamera = .framing(asset.bounds, aspectRatio: aspectRatio, yaw: yaw * .pi / 180, pitch: pitch * .pi / 180)
        }

        var lighting = defaultLights ? PBRLighting.default : PBRLighting(asset: asset, pose: pose)
        lighting.exposure = exposure
        lighting.toneMapping = toneMapping
        lighting.environmentRotation = environmentRotation * .pi / 180
        lighting.environmentIntensity = environmentIntensity
        if let environment {
            lighting.environment = try PBREnvironment(source: .equirectangular(URL(fileURLWithPath: environment)))
        }

        let isHDR = outputURL.pathExtension.lowercased() == "exr"
        let renderer = isHDR ? try OffscreenRenderer.hdr(size: CGSize(width: width, height: height)) : try OffscreenRenderer(size: CGSize(width: width, height: height), clearDepth: 0)
        let background = self.background
        let viewportSize = CGSize(width: width, height: height)
        let debugView = self.debugView
        let msaa = self.msaa
        let showsWireframe = wireframe
        guard [1, 2, 4, 8].contains(msaa) else {
            throw ValidationError("--msaa must be 1, 2, 4 or 8")
        }
        func scene(pose: PBRPose?, modelMatrix: simd_float4x4 = matrix_identity_float4x4) -> GLTFScene {
            var scene = GLTFScene(asset: asset, viewMatrix: gltfCamera.viewMatrix, projectionMatrix: gltfCamera.projectionMatrix, modelMatrix: modelMatrix, lighting: lighting, pose: pose, showsBackground: background, viewportSize: viewportSize)
            scene.debugView = debugView
            scene.sampleCount = msaa
            scene.upscaling = renderScale < 1 ? PBRUpscaling(scale: renderScale, colorPixelFormat: isHDR ? .rgba16Float : .bgra8Unorm_srgb) : nil
            scene.showsWireframe = showsWireframe
            return scene
        }
        if let benchmark {
            try runBenchmark(frames: benchmark, renderer: renderer, asset: asset) { pose, modelMatrix in scene(pose: pose, modelMatrix: modelMatrix) }
        }
        let rendering = try renderer.render(scene(pose: pose))
        if isHDR {
            try rendering.texture.hdrCGImage().writeEXR(to: outputURL)
            return
        }
        try write(try rendering.cgImage, to: outputURL)
    }

    func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ValidationError("Cannot write \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ValidationError("Cannot write \(url.path)")
        }
        print("Wrote \(url.path)")
    }
}
