import ArgumentParser
import Foundation
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd

/// Times a fixed set of sample scenes, one per draw path, and compares them with this machine's recorded baseline.
struct GLTFBenchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Benchmark a fixed set of sample scenes against this machine's baseline.",
        discussion: "Run a Release build from the repository root. Baselines are per machine (Benchmarks/<model>.json); record one with --record. Exits with status 1 when a scene's median CPU or GPU time is slower than its baseline by more than the margin."
    )

    struct Scene {
        var name: String
        /// Relative to the models directory.
        var path: String
        var animation: Int?
        var orbit = true
    }

    static let scenes: [Scene] = [
        Scene(name: "ABeautifulGame", path: "ABeautifulGame/glTF-Binary/ABeautifulGame.glb"),
        Scene(name: "Sponza", path: "Sponza/glTF/Sponza.gltf"),
        Scene(name: "NodePerformanceTest", path: "NodePerformanceTest/glTF-Binary/NodePerformanceTest.glb"),
        Scene(name: "SimpleInstancing", path: "SimpleInstancing/glTF-Binary/SimpleInstancing.glb"),
        Scene(name: "BrainStem", path: "BrainStem/glTF-Binary/BrainStem.glb", animation: 0),
        Scene(name: "RecursiveSkeletons", path: "RecursiveSkeletons/glTF-Binary/RecursiveSkeletons.glb", animation: 0),
        Scene(name: "Fox", path: "Fox/glTF-Binary/Fox.glb", animation: 0),
        Scene(name: "AnimationPointerUVs", path: "AnimationPointerUVs/glTF-Binary/AnimationPointerUVs.glb", animation: 0),
        Scene(name: "AlphaBlendModeTest", path: "AlphaBlendModeTest/glTF-Binary/AlphaBlendModeTest.glb"),
        Scene(name: "TransmissionTest", path: "TransmissionTest/glTF-Binary/TransmissionTest.glb"),
        Scene(name: "CarConcept", path: "CarConcept/glTF-Binary/CarConcept.glb"),
    ]

    struct Baseline: Codable {
        var machine: String
        var chip: String
        var recorded: Date
        var frames: Int
        var width: Int
        var height: Int
        var scenes: [String: FrameTimings]
    }

    @Option(help: "glTF-Sample-Assets Models directory.")
    var models = ".sample-assets/Models"

    @Option(help: "Directory holding per-machine baselines.")
    var baselines = "Benchmarks"

    @Flag(help: "Write this machine's baseline instead of comparing.")
    var record = false

    @Option(help: "Frames timed per run, after 30 warm-up frames.")
    var frames = 60

    @Option(help: "Rounds over all scenes; each scene keeps its fastest round, which filters out clock and power-state noise.")
    var repeats = 3

    @Option var width = 1024
    @Option var height = 1024

    @Option(help: "Allowed CPU slowdown as a fraction of the baseline median.")
    var margin = 0.15

    @Option(help: "Allowed GPU slowdown as a fraction of the baseline median. GPU times vary more between runs (clock states).")
    var gpuMargin = 0.5

    @Option(help: "Slowdowns smaller than this many milliseconds are noise, whatever the fraction.")
    var noiseFloor = 0.3

    @Argument(help: "Only these scenes (default: all).")
    var only: [String] = []

    func run() throws {
        try MainActor.assumeIsolated {
            try bench()
        }
    }

    @MainActor
    func bench() throws {
        #if DEBUG
        guard !record else {
            throw ValidationError("Refusing to record a baseline from a Debug build; build with -c release.")
        }
        print("warning: Debug build; timings are several times slower than Release and not comparable with a baseline.")
        #endif
        let unknown = Set(only).subtracting(Self.scenes.map(\.name))
        guard unknown.isEmpty else {
            throw ValidationError("Unknown scenes: \(unknown.sorted().joined(separator: ", ")). Known: \(Self.scenes.map(\.name).joined(separator: ", "))")
        }
        let selected = Self.scenes.filter { only.isEmpty || only.contains($0.name) }
        let machine = Self.sysctl("hw.model") ?? "unknown"
        let baselineURL = URL(fileURLWithPath: baselines).appending(path: "\(machine).json")
        let existing = try? JSONDecoder.iso.decode(Baseline.self, from: Data(contentsOf: baselineURL))
        if !record, existing == nil {
            print("No baseline for \(machine) at \(baselineURL.path); run with --record to make one.")
        }

        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), clearDepth: 0)
        var results: [String: FrameTimings] = [:]
        var regressions: [String] = []
        var loaded: [(scene: Scene, asset: GLTFAsset)] = []
        for scene in selected {
            let url = URL(fileURLWithPath: models).appending(path: scene.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("\(scene.name): missing \(url.path); run `just download-sample-assets`.")
                continue
            }
            let asset = try GLTFAsset(url: url, options: .commandLine)
            if let animation = scene.animation, !asset.animations.indices.contains(animation) {
                throw ValidationError("\(scene.name) has no animation \(animation)")
            }
            loaded.append((scene, asset))
        }
        // Run every scene once per round, not one scene many times. A cold start then affects only the first round.
        // Each scene keeps its fastest round.
        var rounds: [[FrameTimings]] = []
        for _ in 0 ..< max(repeats, 1) {
            rounds.append(try loaded.map { try measure($0.scene, asset: $0.asset, renderer: renderer) })
        }
        print("scene".padding(toLength: 22, withPad: " ", startingAt: 0) + "     cpu ms     gpu ms   vs baseline (median)")
        for (index, (scene, _)) in loaded.enumerated() {
            let runs = rounds.map { $0[index] }
            // CPU and GPU are judged separately, so each takes its own fastest run.
            var timings = runs.min { $0.frame.median < $1.frame.median }!
            timings.cpu = runs.map(\.cpu).min { $0.median < $1.median }!
            timings.gpu = runs.map(\.gpu).min { $0.median < $1.median }!
            results[scene.name] = timings
            var comparison = ""
            if let old = existing?.scenes[scene.name] {
                let cpu = change(timings.cpu.median, from: old.cpu.median, margin: margin)
                let gpu = change(timings.gpu.median, from: old.gpu.median, margin: gpuMargin)
                comparison = "cpu \(cpu.text)  gpu \(gpu.text)"
                if !record, cpu.isRegression || gpu.isRegression {
                    regressions.append(scene.name)
                    comparison += "  REGRESSION"
                }
            }
            print(scene.name.padding(toLength: 22, withPad: " ", startingAt: 0) + String(format: " %10.3f %10.3f   ", timings.cpu.median, timings.gpu.median) + comparison)
        }

        if record {
            // Keep baselines of scenes not run this time.
            var scenes = existing?.scenes ?? [:]
            scenes.merge(results) { $1 }
            let baseline = Baseline(machine: machine, chip: Self.sysctl("machdep.cpu.brand_string") ?? "unknown", recorded: Date(), frames: frames, width: width, height: height, scenes: scenes)
            try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.iso.encode(baseline).write(to: baselineURL)
            print("Wrote \(baselineURL.path)")
        } else if !regressions.isEmpty {
            print("Slower than baseline by more than \(Int(margin * 100))% CPU or \(Int(gpuMargin * 100))% GPU, and \(noiseFloor) ms: \(regressions.joined(separator: ", "))")
            throw ExitCode(1)
        }
    }

    @MainActor
    func measure(_ scene: Scene, asset: GLTFAsset, renderer: OffscreenRenderer) throws -> FrameTimings {
        let camera = PBRCamera.framing(asset.bounds, aspectRatio: Float(width) / Float(height))
        let lighting = PBRLighting(asset: asset)
        let viewportSize = CGSize(width: width, height: height)
        return try measureFrames(frames: frames, warmUpFrames: 30, renderer: renderer) { frame in
            GLTFScene(
                asset: asset,
                viewMatrix: camera.viewMatrix,
                projectionMatrix: camera.projectionMatrix,
                modelMatrix: scene.orbit ? orbitMatrix(center: asset.bounds.center, frame: frame) : matrix_identity_float4x4,
                lighting: lighting,
                pose: scene.animation.map { asset.pose(animation: $0, time: Float(frame) / 60) },
                viewportSize: viewportSize
            )
        }
    }

    func change(_ new: Double, from old: Double, margin: Double) -> (text: String, isRegression: Bool) {
        let fraction = old > 0 ? (new - old) / old : 0
        let text = String(format: "%+6.1f%%", fraction * 100)
        return (text, new - old > noiseFloor && fraction > margin)
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
