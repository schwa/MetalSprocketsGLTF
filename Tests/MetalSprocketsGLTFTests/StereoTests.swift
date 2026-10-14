import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

@Suite(.metalValidation)
struct StereoTests {
    let size = 64

    /// BGRA bytes of one slice of `texture`.
    func bytes(_ texture: MTLTexture, slice: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&bytes, bytesPerRow: size * 4, bytesPerImage: size * size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice)
        return bytes
    }

    func texture(_ format: MTLPixelFormat, slices: Int, device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
        if slices > 1 {
            descriptor.textureType = .type2DArray
            descriptor.arrayLength = slices
        }
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = format == .depth32Float ? .private : .shared
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    // Two views drawn at once (vertex amplification into a two-slice target) give each slice exactly what drawing
    // that view alone gives: per-view matrices, camera positions (specular), culling and the background all follow.
    @Test func stereoSlicesMatchMonoRenders() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let lighting = PBRLighting(lights: [.directional(direction: [-1, -1, -1], intensity: 2)], environment: try PBREnvironment(source: .uniform([0.3, 0.4, 0.5]), specularSize: 16, irradianceSize: 4))
        let projection = simd_float4x4.perspective(fovY: .pi / 3, aspectRatio: 1, near: 0.1, far: 50)
        let center = asset.bounds.center
        let views = [
            simd_float4x4.lookAt(eye: center + [-0.4, 0.3, 4], target: center, up: [0, 1, 0]),
            simd_float4x4.lookAt(eye: center + [0.4, 0.3, 4], target: center, up: [0, 1, 0])
        ]
        func pbrRenderer(view: simd_float4x4) -> PBRRenderer {
            PBRRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, lighting: lighting)
        }
        func background(view: simd_float4x4) -> PBREnvironmentBackground {
            PBREnvironmentBackground(lighting: lighting, viewMatrix: view, projectionMatrix: projection)
        }

        var monos: [[UInt8]] = []
        for view in views {
            let color = try texture(.bgra8Unorm_srgb, slices: 1, device: device)
            let offscreen = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: texture(.depth32Float, slices: 1, device: device), clearDepth: 0)
            _ = try offscreen.render(try RenderPass {
                background(view: view)
                pbrRenderer(view: view)
            })
            monos.append(bytes(color, slice: 0))
        }
        #expect(monos[0] != monos[1], "The two views should differ")

        let stereo = PBRStereoViews(viewMatrices: views, projectionMatrices: [projection, projection], viewports: Array(repeating: MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1), count: 2))
        let color = try texture(.bgra8Unorm_srgb, slices: 2, device: device)
        var offscreen = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: texture(.depth32Float, slices: 2, device: device), clearDepth: 0)
        offscreen.renderPassDescriptor.renderTargetArrayLength = 2
        var stereoRenderer = pbrRenderer(view: views[0])
        stereoRenderer.stereo = stereo
        var stereoBackground = background(view: views[0])
        stereoBackground.stereo = stereo
        // Inside the pass: RenderPass starts each pass with a fresh pipeline descriptor.
        _ = try offscreen.render(try RenderPass {
            try Group {
                stereoBackground
                stereoRenderer
            }
            .renderPipelineDescriptorTransformer { $0.maxVertexAmplificationCount = 2 }
        })
        #expect(bytes(color, slice: 0) == monos[0])
        #expect(bytes(color, slice: 1) == monos[1])
    }

    // A stereo transmission pre-pass (a slice per eye) refracts each eye's own view: each slice matches a one-view
    // render for that eye, and the glass shows the red quad behind it.
    @Test func stereoTransmissionMatchesSingleViewRenders() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let asset = try GLTFAsset(url: makeGlassInFrontOfRedFile())
        let lighting = PBRLighting(lights: [], environment: try PBREnvironment(source: .uniform([0.05, 0.05, 0.05]), specularSize: 16, irradianceSize: 4))
        let projection = simd_float4x4.perspective(fovY: .pi / 3, aspectRatio: 1, near: 0.1, far: 50)
        // Far apart and close, so each eye sees the red quad's edge behind a different part of the glass: sampling
        // the other eye's slice would show the wrong side of it.
        let views = [
            simd_float4x4.lookAt(eye: [-3, 0, 2], target: .zero, up: [0, 1, 0]),
            simd_float4x4.lookAt(eye: [3, 0, 2], target: .zero, up: [0, 1, 0])
        ]

        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)
        /// Each slice of a render of `views` together, with a stereo pre-pass.
        func render(_ views: [simd_float4x4], prePass usesPrePass: Bool = true) throws -> [[UInt8]] {
            let count = views.count
            let stereo = PBRStereoViews(viewMatrices: views, projectionMatrices: Array(repeating: projection, count: count), viewports: Array(repeating: viewport, count: count))
            let target = try PBRTransmissionTarget(width: size, height: size, viewCount: count)
            let color = try texture(.bgra8Unorm_srgb, slices: count, device: device)
            var offscreen = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: texture(.depth32Float, slices: count, device: device), clearDepth: 0)
            offscreen.renderPassDescriptor.renderTargetArrayLength = count
            var prePass = PBRTransmissionPass(model: asset.model, viewMatrix: views[0], projectionMatrix: projection, lighting: lighting, target: target)
            prePass.renderer.stereo = stereo
            var renderer = PBRRenderer(model: asset.model, viewMatrix: views[0], projectionMatrix: projection, lighting: lighting, transmissionTarget: usesPrePass ? target : nil)
            renderer.stereo = stereo
            _ = try offscreen.render(try Group {
                if usesPrePass {
                    prePass
                }
                try RenderPass {
                    try Group {
                        renderer
                    }
                    .renderPipelineDescriptorTransformer { $0.maxVertexAmplificationCount = count }
                }
            })
            return (0 ..< count).map { bytes(color, slice: $0) }
        }
        let singles = try views.map { try render([$0])[0] }
        #expect(singles[0] != singles[1], "The two views should differ")
        // BGRA: the glass in the middle shows the red quad behind it, refracted (not just blended over black).
        let center = (size / 2 * size + size / 2) * 4
        #expect(singles[0][center + 2] > 100 && singles[0][center] < 60, "\(singles[0][center ..< center + 4])")
        let both = try render(views)
        #expect(both[0] == singles[0])
        #expect(both[1] == singles[1])
        // Without the pre-pass the glass is only blended over what is behind it (#140): no refraction.
        #expect(try render(views, prePass: false) != both)
    }
}
