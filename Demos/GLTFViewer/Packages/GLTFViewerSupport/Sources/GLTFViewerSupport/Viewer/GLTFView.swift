import GeometryLite3D
import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsUI
import simd
import SwiftUI

/// Renders a loaded model with Interaction3D camera controls (drag to orbit, scroll or pinch to zoom, Command-drag to
/// pan). Reads ``ViewerModel`` and ``ViewerPreferences`` from the environment.
struct GLTFView: View {
    var model: ViewerModel.LoadedAsset

    @Environment(ViewerModel.self) private var viewer
    @Environment(ViewerPreferences.self) private var preferences

    /// Written every frame; only ``FrameRateBadge`` reads it, so this view is not redrawn each frame.
    @State private var frameTiming = FrameTimingModel()

    // Linear RGB; the sRGB targets brighten it.
    static let background = SIMD3<Float>(0.01, 0.01, 0.012)

    /// The display's highest refresh rate (120 on ProMotion), instead of MTKView's default 60.
    @MainActor static var displayMaximumFramesPerSecond: Int {
        #if os(macOS)
        max(NSScreen.main?.maximumFramesPerSecond ?? 60, 60)
        #else
        60
        #endif
    }

    private var asset: GLTFAsset { model.asset }
    private var settings: ViewerSettings { preferences.settings }

    var body: some View {
        @Bindable var viewer = viewer
        @Bindable var preferences = preferences
        metalView
        .contentShape(Rectangle())
        .interactiveCamera(
            rotation: $viewer.orbit.rotation,
            distance: $viewer.orbit.distance,
            target: $viewer.orbit.target,
            zoom: .multiplicative(),
            distanceRange: max(asset.bounds.radius, 1e-3) * 0.01 ... max(asset.bounds.radius, 1e-3) * 100
        )
        // Build the chosen environment if nothing has yet (e.g. picked before this model was shown).
        .task(id: settings.environment) {
            EnvironmentLibrary.shared.request(settings.environment)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                FrameRateBadge(model: frameTiming)
                Text("\(asset.opaqueInstances.count + asset.blendedInstances.count) primitives · \(asset.materials.count) materials")
                    .font(.caption)
                    .padding(6)
                    .background(.thinMaterial, in: .rect(cornerRadius: 6))
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if viewer.animationDuration > 0 {
                AnimationScrubber()
            }
        }
        .toolbar {
            if asset.animations.count > 1 {
                ToolbarItem(placement: Self.toolbarPlacement) {
                    Picker("Animation", selection: $viewer.animationIndex) {
                        ForEach(asset.animations.indices, id: \.self) { index in
                            Text(asset.animations[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            if !asset.animations.isEmpty {
                ToolbarItem(placement: Self.toolbarPlacement) {
                    Button(viewer.isPlaying ? "Pause" : "Play", systemImage: viewer.isPlaying ? "pause.fill" : "play.fill") {
                        viewer.togglePlayback()
                    }
                }
            }
            #if os(visionOS)
            // Elsewhere the inspector toggle sits in the inspector's own toolbar.
            ToolbarItem(placement: Self.toolbarPlacement) {
                InspectorWindowToggle()
            }
            ToolbarItem(placement: Self.toolbarPlacement) {
                // Overrides are relative to the asset's own variant, so the chosen variant is right for either asset.
                ImmersiveToggle(asset: viewer.variantAsset ?? asset, lighting: immersiveLighting, materialVariant: viewer.materialVariant)
            }
            #endif
        }
        #if os(visionOS)
        // Inspectors aren't available on visionOS; the inspector window (InspectorWindow) shows the same viewer.
        .onAppear {
            InspectorRelay.shared.viewer = viewer
            InspectorRelay.shared.preferences = preferences
        }
        #else
        .inspector(isPresented: $preferences.settings.showsInspector) {
        ViewerInspector()
        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        .toolbar {
        ToolbarItem {
        Button(settings.showsInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing") {
        preferences.settings.showsInspector.toggle()
        }
        }
        }
        }
        #endif
    }

    #if os(visionOS)
    /// The window's lighting (environment, exposure, tone mapping) for the immersive space.
    private var immersiveLighting: PBRLighting {
        var lighting = PBRLighting(asset: viewer.variantAsset ?? asset)
        applyDisplaySettings(to: &lighting)
        return lighting
    }
    #endif

    /// visionOS shows window toolbars only as an ornament below the window.
    private static var toolbarPlacement: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .principal
        #endif
    }

    @ViewBuilder
    private var metalView: some View {
        #if os(visionOS)
        // While the immersive space shows the model, the window stops rendering it (no GPU work nobody looks at).
        if ImmersiveController.shared.isOpen {
            ContentUnavailableView("Viewing in Immersive Space", systemImage: "visionpro", description: Text("Exit Immersive to see the model here again."))
        } else {
            windowRenderView
        }
        #else
        windowRenderView
        #endif
    }

    private var windowRenderView: some View {
        RenderView { _, size in
            scene(size: size)
        }
        .metalColorPixelFormat(settings.colorPixelFormat)
        #if os(macOS)
        // Float values are linear, so the drawable needs a linear, extended color space for EDR.
        // Set both ways: a nil color space would leave the previous one on the layer.
        .metalColorspace(CGColorSpace(name: settings.extendedDynamicRange ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB))
        .metalWantsExtendedDynamicRangeContent(settings.extendedDynamicRange)
        #endif
        // When upscaling, the scene antialiases its low-resolution frame instead (MetalFX wants antialiased input).
        .metalSampleCount(settings.upscaling == nil ? settings.sampleCount : 1)
        .metalFramebufferOnly(settings.framebufferOnly)
        .metalDepthStencilPixelFormat(.depth32Float)
        // The renderer uses reversed depth (near 1, far 0).
        .metalClearDepth(0)
        .metalPreferredFramesPerSecond(Self.displayMaximumFramesPerSecond)
        .onFrameTimingChange { [frameTiming] statistics in
            frameTiming.statistics = statistics
        }
        .metalClearColor(MTLClearColor(red: Double(Self.background.x), green: Double(Self.background.y), blue: Double(Self.background.z), alpha: 1))
    }

    private func camera(size: CGSize) -> PBRCamera {
        let aspectRatio = Float(max(size.width, 1) / max(size.height, 1))
        if let activeCamera = viewer.activeCamera, asset.cameras.indices.contains(activeCamera) {
            let placed = asset.cameras(pose: viewer.currentPose ?? asset.pose(animation: -1, time: 0))[activeCamera]
            return PBRCamera(placed.camera, worldMatrix: placed.worldMatrix, aspectRatio: aspectRatio)
        }
        let cameraMatrix = viewer.orbit.cameraWorldMatrix

        // Fit the depth range to the model around the current camera distance.
        let radius = max(asset.bounds.radius, 1e-3)
        let distanceToCenter = simd_distance(cameraMatrix.columns.3.xyz, asset.bounds.center)
        let far = distanceToCenter + radius * 2
        let near = max(distanceToCenter - radius * 2, far * 1e-4)
        return PBRCamera(viewMatrix: cameraMatrix.inverse, projectionMatrix: PerspectiveProjection(verticalAngleOfView: .radians(viewer.orbit.fieldOfView), depthMode: .reversed(zClip: near ... far)).projectionMatrix(aspectRatio: aspectRatio))
    }

    /// The Display tab's tone mapping and environment. The studio stands in while another environment builds.
    private func applyDisplaySettings(to lighting: inout PBRLighting) {
        lighting.toneMapping = settings.toneMapping
        lighting.exposure = pow(2, settings.exposure)
        let modelEnvironment = settings.environment == .model ? try? (viewer.variantAsset ?? asset).environment() : nil
        lighting.environment = modelEnvironment ?? EnvironmentLibrary.shared.environment(settings.environment) ?? .studio
        lighting.environmentIntensity = settings.environmentIntensity
        lighting.environmentRotation = settings.environmentRotation * .pi / 180
    }

    private func scene(size: CGSize) -> GLTFScene {
        let camera = camera(size: size)
        let shown = viewer.variantAsset ?? asset
        let pose = viewer.currentPose
        // The asset's own lights, placed by the pose, with the chosen environment and tone mapping.
        var lighting = PBRLighting(asset: shown, pose: pose)
        applyDisplaySettings(to: &lighting)
        var scene = GLTFScene(asset: shown, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix, lighting: lighting, pose: pose, showsBackground: settings.showsBackground, viewportSize: size)
        scene.debugView = settings.debugView
        scene.showsWireframe = settings.showsWireframe
        scene.materialOverrides = viewer.materialOverrides
        if let upscaling = settings.upscaling {
            scene.upscaling = upscaling
            scene.sampleCount = settings.sampleCount
        }
        return scene
    }
}

/// A slider over the selected clip. Dragging it pauses playback at the chosen time.
private struct AnimationScrubber: View {
    @Environment(ViewerModel.self) private var viewer

    var body: some View {
        @Bindable var viewer = viewer
        TimelineView(.animation(paused: !viewer.isPlaying)) { _ in
            HStack {
                Slider(value: $viewer.animationTime, in: 0 ... viewer.animationDuration)
                Text(viewer.animationTime, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .font(.caption)
            }
            .frame(maxWidth: 400)
            .padding(8)
            .background(.thinMaterial, in: .rect(cornerRadius: 8))
            .padding()
        }
    }
}
