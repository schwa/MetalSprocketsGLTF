#if os(visionOS)
import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsUI
import simd
import SwiftUI
import Synchronization

/// What the immersive space shows: the model a window sent it, read by the render loop off the main actor.
public final class ImmersiveModelBox: Sendable {
    public static let shared = ImmersiveModelBox()

    /// Lighting from the room, running while the immersive space is open.
    let roomLighting = PBRRoomLighting()

    struct Shown: Sendable {
        var asset: GLTFAsset
        var lighting: PBRLighting
        /// KHR_materials_variants variant. Material overrides are not Sendable, so the render loop makes them from
        /// this index.
        var materialVariant: Int?
        /// Light with the room (``PBRRoomLighting``) once it has an environment, instead of `lighting`'s.
        var usesRoomLighting: Bool
    }

    private let shown = Mutex<Shown?>(nil)

    func show(_ value: Shown?) {
        shown.withLock { $0 = value }
    }

    var current: Shown? {
        shown.withLock { $0 }
    }

    /// Where models stand while the space is open: fixed from the viewer's head on the first frame that has it.
    private let placement = Mutex<simd_float4x4?>(nil)

    /// Forgets the placement, so the next frame with a head position places models in front of the viewer again.
    func resetPlacement() {
        placement.withLock { $0 = nil }
    }

    /// The placement, deriving it from `headTransform` (the device's transform in the space) the first time.
    func placement(headTransform: simd_float4x4?) -> simd_float4x4? {
        placement.withLock { placement in
            if placement == nil, let headTransform {
                placement = ImmersivePlacement.inFront(of: headTransform)
            }
            return placement
        }
    }
}

/// An immersive space drawing the model a window sent to ``ImmersiveModelBox``: about 30 cm in radius, 60 cm in front
/// of the viewer's head when the space opened (facing them), a little below eye height, playing its first animation.
/// Add it to the app's scenes.
public struct GLTFImmersiveSpace: Scene {
    public static let id = "GLTFModel"

    public init() {}

    public var body: some Scene {
        ImmersiveSpace(id: Self.id) {
            ImmersiveRenderContent { context in
                if let shown = ImmersiveModelBox.shared.current {
                    Self.scene(shown, context: context)
                } else {
                    ImmersiveRenderPass(context: context) {
                        EmptyElement()
                    }
                }
            }
            .onRenderLoopChange { isRunning in
                Task { @MainActor in
                    ImmersiveController.shared.renderLoopChanged(isRunning: isRunning)
                }
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    /// Runs on the immersive render loop, off the main actor.
    nonisolated static func scene(_ shown: ImmersiveModelBox.Shown, context: ImmersiveContext) -> PBRImmersiveScene {
        let asset = shown.asset
        let bounds = asset.bounds
        let scale = 0.3 / max(bounds.radius, 1e-4)
        // In front of the viewer (fixed on the first frame with a head position); a default spot until then.
        let placement = ImmersiveModelBox.shared.placement(headTransform: context.deviceAnchor?.originFromAnchorTransform) ?? {
            var fallback = matrix_identity_float4x4
            fallback.columns.3 = [0, 1.1, -0.6, 1]
            return fallback
        }()
        var scaling = matrix_identity_float4x4
        scaling.columns.0.x = scale
        scaling.columns.1.y = scale
        scaling.columns.2.z = scale
        var centering = matrix_identity_float4x4
        centering.columns.3 = SIMD4(-bounds.center, 1)
        var pose: PBRPose?
        if let clip = asset.animations.first, clip.duration > 0 {
            pose = asset.pose(animation: 0, time: Float(context.time.truncatingRemainder(dividingBy: Double(clip.duration))))
        }
        var lighting = shown.lighting
        if shown.usesRoomLighting, let room = ImmersiveModelBox.shared.roomLighting.environment {
            lighting.environment = room
        }
        var scene = PBRImmersiveScene(model: asset.model, context: context, modelMatrix: placement * scaling * centering, lighting: lighting, pose: pose)
        scene.items[0].materialOverrides = (try? asset.materialOverrides(variant: shown.materialVariant)) ?? [:]
        return scene
    }
}
#endif
