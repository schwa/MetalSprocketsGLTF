import GeometryLite3D
import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsUI
import simd
import SwiftUI
import WebReference

/// Renders a loaded model with Interaction3D camera controls (drag to orbit, scroll or pinch to zoom, Command-drag to
/// pan), optionally next to the same view rendered by three.js. Reads ``ViewerModel`` and ``ViewerPreferences``
/// from the environment.
struct GLTFView: View {
    var model: ViewerModel.LoadedAsset

    @Environment(ViewerModel.self) private var viewer
    @Environment(ViewerPreferences.self) private var preferences

    @State private var reference: GLTFWebReference?
    @State private var isWebLoaded = false
    /// True once the web view has drawn a frame with this view's camera and lighting.
    @State private var hasWebFrame = false
    @State private var webError: String?
    /// Metal vs three.js for the settled view; nil while it changes, while animating, or when not comparable.
    @State private var comparisonPSNR: Double?
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
    private var comparison: ComparisonMode { settings.mode }

    var body: some View {
        @Bindable var viewer = viewer
        @Bindable var preferences = preferences
        GeometryReader { proxy in
            content(size: proxy.size)
                .contentShape(Rectangle())
                .interactiveCamera(
                    rotation: $viewer.orbit.rotation,
                    distance: $viewer.orbit.distance,
                    target: $viewer.orbit.target,
                    zoom: .multiplicative(),
                    distanceRange: max(asset.bounds.radius, 1e-3) * 0.01 ... max(asset.bounds.radius, 1e-3) * 100
                )
                // Outside the camera-controlled view: Interaction3D's drag is simultaneous, so it would also see
                // drags on the handle.
                .overlay {
                    if comparison == .split {
                        splitHandle(size: proxy.size)
                    }
                }
                // Keep the web side's animation in step while playing.
                .task(id: AnimationUpdate(index: viewer.animationIndex, isPlaying: viewer.isPlaying, heldTime: viewer.heldTime, isLoaded: isWebLoaded, comparison: comparison)) {
                    guard comparison != .metal, isWebLoaded, let reference, !asset.animations.isEmpty else { return }
                    repeat {
                        try? await reference.setAnimation(viewer.animationIndex, time: viewer.animationTime)
                        try? await Task.sleep(for: .milliseconds(33))
                    } while viewer.isPlaying && !Task.isCancelled
                }
                // Build the chosen environment if nothing has yet (e.g. picked before this model was shown).
                .task(id: settings.environment) {
                    EnvironmentLibrary.shared.request(settings.environment)
                }
                .task(id: WebLoad(isComparing: comparison != .metal, antialiasing: settings.antialiasing)) {
                    await loadWeb()
                }
                .task(id: webUpdate(size: viewSize(proxy.size))) {
                    await updateWeb(size: viewSize(proxy.size))
                }
                // Once the comparison has settled, measure how close the two renders are.
                .task(id: PSNRUpdate(web: webUpdate(size: viewSize(proxy.size)), hasWebFrame: hasWebFrame, isPlaying: viewer.isPlaying, animationTime: viewer.heldTime, debugView: settings.debugView, showsWireframe: settings.showsWireframe, sampleCount: settings.sampleCount, variant: viewer.materialVariant)) {
                    await measurePSNR()
                }
        }
        .overlay(alignment: .bottomTrailing) {
            if comparison != .metal, let comparisonPSNR {
                Text(comparisonPSNR.isFinite ? "PSNR \(comparisonPSNR, format: .number.precision(.fractionLength(1))) dB" : "Identical")
                    .font(.caption.monospacedDigit())
                    .padding(6)
                    .background(.thinMaterial, in: .rect(cornerRadius: 6))
                    .padding()
                    .help("How close the Metal and three.js renders are (peak signal-to-noise ratio of the whole frame; higher is closer)")
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                if comparison != .web {
                    FrameRateBadge(model: frameTiming)
                }
                Text(webError ?? "\(asset.opaqueInstances.count + asset.blendedInstances.count) primitives · \(asset.materials.count) materials")
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
            ToolbarItem(placement: Self.toolbarPlacement) {
                Picker("Compare", selection: $preferences.settings.mode) {
                    ForEach(ComparisonMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
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
    private func content(size: CGSize) -> some View {
        switch comparison {
        case .metal:
            metalView

        case .web:
            webView

        case .sideBySide:
            HStack(spacing: 1) {
                metalView
                    .overlay(alignment: .top) { rendererLabel("Metal") }
                webView
                    .overlay(alignment: .top) { rendererLabel(webLabel) }
            }
            .background(.separator)

        case .split:
            ZStack {
                metalView
                webView
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: size.width * (1 - settings.split))
                    }
            }
            .overlay(alignment: .topLeading) { rendererLabel("Metal") }
            .overlay(alignment: .topTrailing) { rendererLabel(webLabel) }
        }
    }

    private var webLabel: String {
        "three.js · \(settings.webLighting == .matched ? "Matched Lights" : "Environment")"
    }

    private func rendererLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: .capsule)
            .padding(8)
            .allowsHitTesting(false)
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

    @ViewBuilder
    private var webView: some View {
        ZStack {
            if let reference {
                // Gestures belong to the container so both renderers follow the same camera.
                GLTFWebReferenceView(reference: reference)
                    .allowsHitTesting(false)
            }
            // Cover the web view until it has a correct frame, so loading states never show.
            if !hasWebFrame {
                Color(.sRGBLinear, red: Double(Self.background.x), green: Double(Self.background.y), blue: Double(Self.background.z))
                    .overlay { ProgressView().controlSize(.small) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func splitHandle(size: CGSize) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: 2)
            .overlay {
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption).foregroundStyle(.black))
            }
            .contentShape(Rectangle().inset(by: -12))
            .position(x: size.width * settings.split, y: size.height / 2)
            .frame(height: size.height)
            .highPriorityGesture(
                DragGesture(coordinateSpace: .named("split"))
                    .onChanged { value in
                        preferences.settings.split = min(max(value.location.x / max(size.width, 1), 0), 1)
                    }
            )
            .coordinateSpace(name: "split")
            .accessibilityLabel("Split position")
            .accessibilityValue(Text(settings.split, format: .percent.precision(.fractionLength(0))))
    }

    /// Size of each renderer: side by side halves the width.
    private func viewSize(_ size: CGSize) -> CGSize {
        comparison == .sideBySide ? CGSize(width: (size.width - 1) / 2, height: size.height) : size
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

    /// Creates the web view the first time a comparison mode is chosen, and again when antialiasing changes (WebGL
    /// fixes it when the context is created).
    private func loadWeb() async {
        let antialiasing = settings.antialiasing
        if let reference, reference.antialias != antialiasing {
            self.reference = nil
            isWebLoaded = false
            hasWebFrame = false
        }
        guard comparison != .metal, reference == nil else { return }
        let reference = GLTFWebReference(antialias: antialiasing)
        self.reference = reference
        do {
            try await reference.setBackground(Self.background)
            try await reference.load(model.url)
            isWebLoaded = true
        } catch {
            webError = "three.js: \(error.localizedDescription)"
        }
    }

    /// Everything the three.js side shows; it is updated whenever this changes.
    private func webUpdate(size: CGSize) -> WebUpdate {
        WebUpdate(size: size, orbit: viewer.orbit, camera: viewer.activeCamera, comparison: comparison, lighting: settings.webLighting, toneMapping: settings.toneMapping, exposure: settings.exposure, environment: settings.environment, environmentReady: EnvironmentLibrary.shared.environment(settings.environment) != nil, environmentIntensity: settings.environmentIntensity, environmentRotation: settings.environmentRotation, showsBackground: settings.showsBackground, isLoaded: isWebLoaded)
    }

    /// After the view has been still for a moment, renders the Metal side offscreen at the three.js snapshot's size,
    /// with the same camera, lighting, pose and antialiasing, and compares the two. Skipped while animating and for
    /// debug views and wireframe, which three.js does not draw.
    private func measurePSNR() async {
        comparisonPSNR = nil
        guard comparison != .metal, hasWebFrame, let reference, !viewer.isPlaying, settings.debugView == .lit, !settings.showsWireframe else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let web = try? await reference.snapshot(), !Task.isCancelled else { return }
        let size = CGSize(width: web.width, height: web.height)
        do {
            let renderer = try OffscreenRenderer(size: size, clearDepth: 0)
            renderer.renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: Double(Self.background.x), green: Double(Self.background.y), blue: Double(Self.background.z), alpha: 1)
            var scene = scene(size: size)
            scene.sampleCount = settings.sampleCount
            // The offscreen target is 8-bit sRGB even when the view is EDR.
            scene.upscaling = settings.upscaling.map { PBRUpscaling(scale: $0.scale) }
            let metal = try renderer.render(scene).cgImage
            let psnr = await PSNR.between(metal, web)
            guard !Task.isCancelled else { return }
            comparisonPSNR = psnr
        } catch {
            comparisonPSNR = nil
        }
    }

    private func updateWeb(size: CGSize) async {
        guard comparison != .metal, isWebLoaded, let reference else { return }
        do {
            let camera = camera(size: size)
            // The asset's lighting at rest; the Metal side poses lights itself (GLTFScene).
            var lighting = PBRLighting(asset: asset)
            applyDisplaySettings(to: &lighting)
            try await reference.setLighting(lighting, mode: settings.webLighting, showsBackground: settings.showsBackground)
            try await reference.setView(viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
            webError = nil
            hasWebFrame = true
        } catch {
            webError = "three.js: \(error.localizedDescription)"
        }
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

private struct AnimationUpdate: Equatable {
    var index: Int
    var isPlaying: Bool
    var heldTime: Float
    var isLoaded: Bool
    var comparison: ComparisonMode
}

/// Everything the web reference needs to redraw.
private struct WebLoad: Equatable {
    var isComparing: Bool
    var antialiasing: Bool
}

private struct PSNRUpdate: Equatable {
    var web: WebUpdate
    var hasWebFrame: Bool
    var isPlaying: Bool
    var animationTime: Float
    var debugView: PBRDebugView
    var showsWireframe: Bool
    var sampleCount: Int
    var variant: Int?
}

private struct WebUpdate: Equatable {
    var size: CGSize
    var orbit: OrbitState
    var camera: Int?
    var comparison: ComparisonMode
    var lighting: GLTFWebReference.LightingMode
    var toneMapping: PBRToneMapping
    var exposure: Float
    var environment: ViewerEnvironment
    var environmentReady: Bool
    var environmentIntensity: Float
    var environmentRotation: Float
    var showsBackground: Bool
    var isLoaded: Bool
}
