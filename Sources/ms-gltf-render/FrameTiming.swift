import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import simd

struct TimingSummary: Codable {
    var median: Double
    var mean: Double
    var p95: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        func percentile(_ fraction: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
        }
        median = percentile(0.5)
        mean = values.reduce(0, +) / Double(max(values.count, 1))
        p95 = percentile(0.95)
    }

    var description: String {
        String(format: "median %7.3f  mean %7.3f  p95 %7.3f ms", median, mean, p95)
    }
}

/// Milliseconds per frame: the whole frame, the GPU's part, and the rest (CPU: building, encoding, waiting).
struct FrameTimings: Codable {
    var frame: TimingSummary
    var gpu: TimingSummary
    var cpu: TimingSummary
}

/// Renders `frames` frames after `warmUpFrames` and times them. Each frame builds its element tree from scratch, as a
/// view does, and waits for the GPU.
@MainActor
func measureFrames<Content: Element>(frames: Int, warmUpFrames: Int = 10, renderer: OffscreenRenderer, scene: (Int) throws -> Content) throws -> FrameTimings {
    for frame in 0 ..< warmUpFrames {
        _ = try renderer.render(try scene(frame))
    }
    var totals: [Double] = []
    var gpus: [Double] = []
    for frame in 0 ..< frames {
        let start = ContinuousClock.now
        let rendering = try renderer.render(try scene(frame + warmUpFrames))
        let elapsed = ContinuousClock.now - start
        totals.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        gpus.append((rendering.gpuTime ?? 0) * 1000)
    }
    let cpus = zip(totals, gpus).map { max($0 - $1, 0) }
    return FrameTimings(frame: TimingSummary(totals), gpu: TimingSummary(gpus), cpu: TimingSummary(cpus))
}

/// A model matrix turning the scene about `center`, half a degree per frame, so each frame's scene differs as it does
/// while interacting.
func orbitMatrix(center: SIMD3<Float>, frame: Int) -> simd_float4x4 {
    let rotation = simd_float4x4(simd_quatf(angle: Float(frame) * .pi / 360, axis: [0, 1, 0]))
    var toCenter = matrix_identity_float4x4
    toCenter.columns.3 = SIMD4(center, 1)
    return toCenter * rotation * toCenter.inverse
}
