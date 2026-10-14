import Foundation
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsGLTFMeshopt
import MetalSprocketsPBR
import Observation
import simd

/// One model shown in the viewer: loading it (file variant, turned-off extensions), and what the viewer and the
/// inspector share about it (camera, animation, material variant). ModelDetailView owns it and puts it in the
/// environment.
@MainActor
@Observable
final class ViewerModel {
    enum Phase {
        case loading
        case loaded(LoadedAsset)
        case failed(String)
    }

    struct LoadedAsset {
        var asset: GLTFAsset
        var url: URL
        var loadTime: Duration
    }

    /// What loading depends on; the load task restarts when it changes.
    struct LoadKey: Equatable {
        var fileVariant: String?
        var disabledExtensions: Set<String>
    }

    let title: String
    /// File variants to choose between (sample models); empty hides the picker.
    let fileVariants: [SampleModel.VariantChoice]
    /// Produces the local file to load for a variant (nil for the default), e.g. by downloading it.
    @ObservationIgnored private let fileURL: (String?) async throws -> URL

    var fileVariant: String? {
        didSet {
            // Extension toggles belong to the file they were made on.
            if fileVariant != oldValue {
                disabledExtensions = []
            }
        }
    }
    /// Extensions turned off in the Model tab; the model reloads without them.
    var disabledExtensions: Set<String> = []
    private(set) var phase: Phase = .loading
    @ObservationIgnored private var loadedVariant: String?

    var loaded: LoadedAsset? {
        if case .loaded(let model) = phase { model } else { nil }
    }

    var loadKey: LoadKey {
        LoadKey(fileVariant: fileVariant, disabledExtensions: disabledExtensions)
    }

    init(title: String, fileVariants: [SampleModel.VariantChoice] = [], fileURL: @escaping (String?) async throws -> URL) {
        self.title = title
        self.fileVariants = fileVariants
        self.fileURL = fileURL
        fileVariant = fileVariants.first?.folder
    }

    convenience init(model: SampleModel, library: SampleLibrary) {
        self.init(title: model.label, fileVariants: model.variantChoices) { variant in
            try await library.fileURL(for: model, variant: variant)
        }
    }

    /// The optional extension targets this app links, minus `disabledExtensions`.
    static func loadOptions(disabling disabledExtensions: Set<String> = []) -> GLTFLoadOptions {
        GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder(), GLTFASTCTextureDecoder()], bufferViewDecoders: [GLTFMeshoptDecoder()], disabledExtensions: disabledExtensions)
    }

    @concurrent
    private static func load(_ url: URL, options: GLTFLoadOptions) async throws -> (GLTFAsset, Duration) {
        let start = ContinuousClock.now
        let asset = try GLTFAsset(url: url, options: options)
        return (asset, ContinuousClock.now - start)
    }

    /// Loads the file for ``loadKey``. A new file shows the loading state and starts from its default view; turning
    /// an extension off keeps the current model (and its camera) on screen until the reload is ready.
    func load() async {
        let isNewFile = fileVariant != loadedVariant || loaded == nil
        if isNewFile {
            phase = .loading
        }
        do {
            let url = try await fileURL(fileVariant)
            let (asset, loadTime) = try await Self.load(url, options: Self.loadOptions(disabling: disabledExtensions))
            // A newer load (another variant or extension toggle) replaced this one.
            guard !Task.isCancelled else { return }
            phase = .loaded(LoadedAsset(asset: asset, url: url, loadTime: loadTime))
            loadedVariant = fileVariant
            if isNewFile {
                resetView(for: asset)
            }
            updateMaterialVariant()
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func resetView(for asset: GLTFAsset) {
        // Start from the auto-framed view; Interaction3D's camera looks down its local -Z, like PBRCamera.
        let framing = PBRCamera.framing(asset.bounds, aspectRatio: 1)
        let center = asset.bounds.isEmpty ? .zero : asset.bounds.center
        defaultOrbit = OrbitState(cameraWorldMatrix: framing.viewMatrix.inverse, center: center, fieldOfView: .pi / 4)
        orbit = defaultOrbit
        selectedCamera = nil
        selectedCameraOrbit = nil
        animationIndex = 0
        animationStart = nil
        heldAnimationTime = 0
        fade = nil
        materialVariant = nil
    }

    // MARK: Material variants

    /// KHR_materials_variants: the chosen variant (nil for the default materials), drawn through material overrides,
    /// or, when the variant changes a primitive's alpha mode or transmission, through a rebuilt asset.
    var materialVariant: Int? {
        didSet {
            if materialVariant != oldValue {
                updateMaterialVariant()
            }
        }
    }
    private(set) var materialOverrides: PBRModel.MaterialOverrides = [:]
    private(set) var variantAsset: GLTFAsset?

    /// Shows the material variant instantly through overrides when it keeps every primitive's pass, else by building
    /// the variant's asset (sharing the loaded materials and meshes).
    private func updateMaterialVariant() {
        guard let asset = loaded?.asset else { return }
        if let overrides = try? asset.materialOverrides(variant: materialVariant) {
            materialOverrides = overrides
            variantAsset = nil
        } else {
            materialOverrides = [:]
            variantAsset = try? asset.variant(materialVariant)
        }
    }

    // MARK: Camera

    var orbit = OrbitState(cameraWorldMatrix: matrix_identity_float4x4, center: [0, 0, -1], fieldOfView: .pi / 4)
    /// The auto-framed orbit of the loaded model.
    private(set) var defaultOrbit = OrbitState(cameraWorldMatrix: matrix_identity_float4x4, center: [0, 0, -1], fieldOfView: .pi / 4)
    /// The file camera picked in the inspector, and the orbit it set. Moving the orbit away from that returns to the
    /// orbit camera.
    private var selectedCamera: Int?
    private var selectedCameraOrbit: OrbitState?

    /// The file camera in use: the selected one, as long as the orbit hasn't moved since it was picked. Setting it
    /// moves the orbit to that camera, so dragging continues from its view; nil returns to the orbit camera.
    var activeCamera: Int? {
        get { orbit == selectedCameraOrbit ? selectedCamera : nil }
        set {
            selectedCamera = newValue
            guard let newValue, let asset = loaded?.asset, asset.cameras.indices.contains(newValue) else {
                selectedCameraOrbit = nil
                return
            }
            let placed = asset.cameras(pose: currentPose ?? asset.pose(animation: -1, time: 0))[newValue]
            let center = asset.bounds.isEmpty ? .zero : asset.bounds.center
            orbit = OrbitState(cameraWorldMatrix: placed.worldMatrix, center: center, fieldOfView: placed.camera.perspective?.yfov ?? orbit.fieldOfView)
            selectedCameraOrbit = orbit
        }
    }

    /// The orbit camera's vertical field of view in degrees.
    var fieldOfViewDegrees: Double {
        get { Double(orbit.fieldOfView * 180 / .pi) }
        set { orbit.fieldOfView = Float(newValue) * .pi / 180 }
    }

    func resetView() {
        activeCamera = nil
        orbit = defaultOrbit
    }

    // MARK: Animation

    /// The clip that plays, an index into the asset's animations. Changing it restarts from the clip's beginning,
    /// keeping play or pause, and cross-fades from the previous clip over ``crossFadeDuration``.
    var animationIndex = 0 {
        didSet {
            guard animationIndex != oldValue else { return }
            fade = Fade(animation: oldValue, start: animationStart, heldTime: heldAnimationTime, began: Date())
            heldAnimationTime = 0
            if animationStart != nil {
                animationStart = Date()
            }
        }
    }
    /// When the animation started playing; nil when paused.
    private(set) var animationStart: Date?
    /// Where a paused animation stopped.
    private var heldAnimationTime: Float = 0

    /// The clip being faded out after a switch: how it was playing, and when the fade began.
    private struct Fade {
        var animation: Int
        var start: Date?
        var heldTime: Float
        var began: Date
    }
    private var fade: Fade?
    static let crossFadeDuration: Float = 0.3

    var isPlaying: Bool {
        animationStart != nil
    }

    var animationDuration: Float {
        guard let animations = loaded?.asset.animations, animations.indices.contains(animationIndex) else { return 0 }
        return animations[animationIndex].duration
    }

    /// Seconds into the selected clip, looping while playing. Setting it pauses there (scrubbing).
    var animationTime: Float {
        get {
            guard let animationStart, animationDuration > 0 else {
                return heldAnimationTime
            }
            return Float(Date().timeIntervalSince(animationStart)).truncatingRemainder(dividingBy: animationDuration)
        }
        set {
            animationStart = nil
            heldAnimationTime = newValue
        }
    }

    /// The time a paused animation is held at (it changes only when the clip, play state or scrubbing does).
    var heldTime: Float {
        heldAnimationTime
    }

    func togglePlayback() {
        if animationStart == nil {
            animationStart = Date().addingTimeInterval(-Double(heldAnimationTime))
        } else {
            heldAnimationTime = animationTime
            animationStart = nil
        }
    }

    /// The selected clip at the current time, or nil when the asset has no animations. Even stopped at time 0 this is
    /// the clip's first frame, not the rest pose, matching what three.js shows.
    var currentPose: PBRPose? {
        guard let asset = loaded?.asset, !asset.animations.isEmpty else { return nil }
        let current = GLTFAnimationLayer(animation: animationIndex, time: animationTime)
        guard let fade, asset.animations.indices.contains(fade.animation) else {
            return asset.pose(layers: [current])
        }
        let progress = Float(Date().timeIntervalSince(fade.began)) / Self.crossFadeDuration
        guard progress < 1 else {
            return asset.pose(layers: [current])
        }
        // The old clip keeps playing (or stays held) while it fades out.
        let duration = asset.animations[fade.animation].duration
        let fadingTime = fade.start.map { duration > 0 ? Float(Date().timeIntervalSince($0)).truncatingRemainder(dividingBy: duration) : 0 } ?? fade.heldTime
        return asset.pose(layers: [
            GLTFAnimationLayer(animation: fade.animation, time: fadingTime, weight: 1 - progress),
            GLTFAnimationLayer(animation: animationIndex, time: animationTime, weight: progress)
        ])
    }
}
