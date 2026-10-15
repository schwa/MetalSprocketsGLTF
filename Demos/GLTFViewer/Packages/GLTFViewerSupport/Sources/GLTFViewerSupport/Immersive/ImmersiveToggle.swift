#if os(visionOS)
import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsUI
import simd
import SwiftUI
import Synchronization

/// Opens or closes ``GLTFImmersiveSpace``, and while it is open shows `asset` in it.
struct ImmersiveToggle: View {
    var asset: GLTFAsset
    var lighting: PBRLighting
    var materialVariant: Int?
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("GLTFViewer.immersiveRoomLighting") private var usesRoomLighting = true
    private let controller = ImmersiveController.shared

    private var shown: ImmersiveModelBox.Shown {
        .init(asset: asset, lighting: lighting, materialVariant: materialVariant, usesRoomLighting: usesRoomLighting)
    }

    var body: some View {
        HStack {
            immersiveButton
            if controller.isOpen {
                Toggle("Room Lighting", systemImage: "lightbulb.max", isOn: $usesRoomLighting)
                    .toggleStyle(.button)
                    .help("Light the model with the room around you (ARKit environment probes) instead of the chosen environment")
            }
        }
        // When the model, variant or lighting changes, the open space shows the new one.
        .onAppear { update() }
        .onChange(of: ObjectIdentifier(asset)) { update() }
        .onChange(of: materialVariant) { update() }
        .onChange(of: usesRoomLighting) { update() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                controller.startRoomLighting()
            } else {
                controller.stopRoomLighting()
            }
        }
    }

    private var immersiveButton: some View {
        Button(controller.isOpen ? "Exit Immersive" : "View Immersive", systemImage: controller.isOpen ? "xmark.circle" : "visionpro") {
            controller.isTransitioning = true
            Task {
                if controller.isOpen {
                    await dismissImmersiveSpace()
                    controller.closed()
                } else {
                    // Place the model in front of the viewer again when the space has a head position.
                    ImmersiveModelBox.shared.resetPlacement()
                    ImmersiveModelBox.shared.show(shown)
                    var result = await openImmersiveSpace(id: GLTFImmersiveSpace.id)
                    if case .opened = result {} else {
                        // A space the system kept open (e.g. across taking the headset off) blocks opening another:
                        // close it and try once more.
                        await dismissImmersiveSpace()
                        result = await openImmersiveSpace(id: GLTFImmersiveSpace.id)
                    }
                    if case .opened = result {
                        controller.opened()
                    }
                }
                controller.isTransitioning = false
            }
        }
        .disabled(controller.isTransitioning)
    }

    private func update() {
        if controller.isOpen {
            ImmersiveModelBox.shared.show(shown)
        }
    }
}
#endif
