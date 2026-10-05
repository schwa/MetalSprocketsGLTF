#if os(visionOS)
import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsUI
import simd
import SwiftUI
import Synchronization

/// Whether the immersive space is open, and its room lighting: one for the app, so switching models keeps the space
/// open and shows the new model in it.
@MainActor
@Observable
final class ImmersiveController {
    static let shared = ImmersiveController()

    private(set) var isOpen = false
    var isTransitioning = false
    private var roomLightingTask: Task<Void, Never>?
    private var runningLoops = 0

    func opened() {
        isOpen = true
        startRoomLighting()
    }

    func closed() {
        isOpen = false
        ImmersiveModelBox.shared.show(nil)
        ImmersiveModelBox.shared.resetPlacement()
        stopRoomLighting()
    }

    /// Follows the immersive render loop, so `isOpen` is correct however the space opens or closes (button, Digital
    /// Crown, or headset removal). It changes only the open state and room lighting. When the space reopens, the old
    /// loop can end after the new loop starts, so loops are counted.
    func renderLoopChanged(isRunning: Bool) {
        runningLoops = max(runningLoops + (isRunning ? 1 : -1), 0)
        isOpen = runningLoops > 0
        if isOpen {
            startRoomLighting()
        } else {
            stopRoomLighting()
        }
    }

    /// ARKit runs only while an immersive space is open, and background apps may not use the GPU (taking the headset
    /// off backgrounds the app), so room lighting runs only while open and active.
    func startRoomLighting() {
        guard isOpen, roomLightingTask == nil else { return }
        let room = ImmersiveModelBox.shared.roomLighting
        roomLightingTask = Task { await room.run() }
    }

    func stopRoomLighting() {
        roomLightingTask?.cancel()
        roomLightingTask = nil
    }
}
#endif
