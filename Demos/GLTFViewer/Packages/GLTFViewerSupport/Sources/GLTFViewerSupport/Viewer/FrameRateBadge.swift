import MetalSprocketsUI
import Observation
import SwiftUI

/// The latest frame timing from the render view.
@MainActor
@Observable
final class FrameTimingModel {
    var statistics: FrameTimingStatistics?
}

/// MetalSprockets' frame timing readout for the Metal render view.
struct FrameRateBadge: View {
    var model: FrameTimingModel

    var body: some View {
        if let statistics = model.statistics {
            FrameTimingView(statistics: statistics, options: [.fps, .frameTime, .gpuTime])
        }
    }
}
