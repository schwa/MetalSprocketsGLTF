import MetalSprocketsPBR

/// One clip at one time, with a weight, for ``GLTFAsset/pose(layers:)``.
public struct GLTFAnimationLayer: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// Blended with the other override layers by normalized weight.
        case override
        /// Adds the clip's offsets from rest, scaled by the weight, on top of the override layers (e.g. a breathing
        /// or aiming clip over a walk).
        case additive
    }

    public var animation: Int
    public var time: Float
    public var weight: Float
    public var mode: Mode

    public init(animation: Int, time: Float, weight: Float = 1, mode: Mode = .override) {
        self.animation = animation
        self.time = time
        self.weight = weight
        self.mode = mode
    }
}

/// Plays an asset's animation clips: cross-fades between clips, per-clip speed and looping, and a one-parameter
/// blend between clips (e.g. idle, walk, run by speed) with their cycles kept in phase.
///
/// A value type: call ``advance(by:)`` each frame, then ``pose(in:)``.
public struct GLTFAnimationController: Sendable {
    public struct Track: Sendable, Equatable {
        public var animation: Int
        /// Seconds into the clip.
        public var time: Float = 0
        public var speed: Float = 1
        public var loops = true
        public internal(set) var weight: Float
        /// The weight a fade is heading to, and how fast (weight per second).
        var targetWeight: Float
        var fadeRate: Float = 0
    }

    /// Each clip's duration in seconds, by animation index.
    public let durations: [Float]
    public private(set) var tracks: [Track] = []
    /// With a phase-synced blend, the shared position in the cycle, 0 ..< 1.
    public private(set) var syncedPhase: Float?
    /// Clips added on top of the playing ones (``GLTFAnimationLayer/Mode/additive``); they loop at their own speed.
    public private(set) var additiveTracks: [Track] = []
    /// The node whose horizontal movement becomes ``rootMotion`` instead of moving it in the pose (usually the
    /// character's root or hips); nil leaves the animation's movement in the pose.
    public var rootMotionNode: Int?
    /// How far the root node moved (x, z) during the last ``advance(by:in:)``, in its parent's space.
    public private(set) var rootMotion: SIMD3<Float> = .zero

    public init(durations: [Float]) {
        self.durations = durations
    }

    public init(asset: GLTFAsset) {
        self.init(durations: asset.animations.map(\.duration))
    }

    /// Switches to `animation`, fading it in and every other track out over `fadeDuration` seconds (0 cuts).
    /// A clip already playing continues from its time unless `restarts`.
    public mutating func play(_ animation: Int, fadeDuration: Float = 0.25, speed: Float = 1, loops: Bool = true, restarts: Bool = false) {
        guard durations.indices.contains(animation) else { return }
        syncedPhase = nil
        let rate: Float = fadeDuration > 0 ? 1 / fadeDuration : .infinity
        for index in tracks.indices {
            tracks[index].targetWeight = 0
            tracks[index].fadeRate = rate
        }
        if let index = tracks.firstIndex(where: { $0.animation == animation }) {
            tracks[index].targetWeight = 1
            tracks[index].speed = speed
            tracks[index].loops = loops
            if restarts {
                tracks[index].time = 0
            }
        } else {
            tracks.append(Track(animation: animation, speed: speed, loops: loops, weight: 0, targetWeight: 1, fadeRate: rate))
        }
        if fadeDuration <= 0 {
            settleFades()
        }
    }

    /// Plays `animations` together, weighted by `parameter` along them (0 is the first, 1 the last; see
    /// ``blendWeights(parameter:count:)``). With `syncsPhase`, every clip is at the same fraction of its cycle and the
    /// cycle lasts the weighted mix of their durations, so walk and run cycles keep their feet in step.
    public mutating func blend(_ animations: [Int], parameter: Float, speed: Float = 1, syncsPhase: Bool = true) {
        let animations = animations.filter { durations.indices.contains($0) }
        let weights = Self.blendWeights(parameter: parameter, count: animations.count)
        var blended: [Track] = []
        for (animation, weight) in zip(animations, weights) {
            var track = tracks.first { $0.animation == animation } ?? Track(animation: animation, weight: weight, targetWeight: weight)
            track.weight = weight
            track.targetWeight = weight
            track.fadeRate = 0
            track.speed = speed
            track.loops = true
            blended.append(track)
        }
        tracks = blended
        if syncsPhase {
            let phase = syncedPhase ?? blended.first.map { durations[$0.animation] > 0 ? $0.time / durations[$0.animation] : 0 } ?? 0
            syncedPhase = phase
            applyPhase(phase)
        } else {
            syncedPhase = nil
        }
    }

    /// Weights for `count` clips evenly spaced along `parameter` (clamped to 0 ... 1): the two clips either side of
    /// it share the weight linearly. They always sum to 1.
    public static func blendWeights(parameter: Float, count: Int) -> [Float] {
        guard count > 1 else {
            return count == 1 ? [1] : []
        }
        let position = min(max(parameter, 0), 1) * Float(count - 1)
        let lower = min(Int(position), count - 2)
        let fraction = position - Float(lower)
        var weights = [Float](repeating: 0, count: count)
        weights[lower] = 1 - fraction
        weights[lower + 1] = fraction
        return weights
    }

    /// Adds `animation` on top of the playing clips at `weight` (0 removes it), e.g. breathing over a walk.
    public mutating func setAdditive(_ animation: Int, weight: Float, speed: Float = 1) {
        guard durations.indices.contains(animation) else { return }
        if weight <= 0 {
            additiveTracks.removeAll { $0.animation == animation }
        } else if let index = additiveTracks.firstIndex(where: { $0.animation == animation }) {
            additiveTracks[index].weight = weight
            additiveTracks[index].speed = speed
        } else {
            additiveTracks.append(Track(animation: animation, speed: speed, weight: weight, targetWeight: weight))
        }
    }

    /// Advances like ``advance(by:)``, and with ``rootMotionNode`` set, measures how far the clips moved the root node
    /// horizontally into ``rootMotion`` (counting each loop's wrap from its end back to its start).
    public mutating func advance(by seconds: Float, in asset: GLTFAsset) {
        let before = tracks
        advance(by: seconds)
        guard let node = rootMotionNode else {
            rootMotion = .zero
            return
        }
        func translation(_ animation: Int, _ time: Float) -> SIMD3<Float> {
            asset.rootTranslation(layers: [GLTFAnimationLayer(animation: animation, time: time)], node: node)
        }
        var motion = SIMD3<Float>.zero
        var totalWeight: Float = 0
        for track in tracks {
            guard let old = before.first(where: { $0.animation == track.animation }) else { continue }
            let duration = durations[track.animation]
            var delta = translation(track.animation, track.time) - translation(track.animation, old.time)
            // Moving forward but ending up earlier means the clip looped: add the end-to-start jump back.
            if track.loops, track.speed > 0, track.time < old.time {
                delta += translation(track.animation, duration) - translation(track.animation, 0)
            } else if track.loops, track.speed < 0, track.time > old.time {
                delta -= translation(track.animation, duration) - translation(track.animation, 0)
            }
            motion += delta * track.weight
            totalWeight += track.weight
        }
        rootMotion = totalWeight > 0 ? motion / totalWeight : .zero
        rootMotion.y = 0
    }

    /// Moves clip times and fades forward by `seconds`; fully faded-out tracks are dropped.
    public mutating func advance(by seconds: Float) {
        for index in additiveTracks.indices {
            let duration = durations[additiveTracks[index].animation]
            var time = additiveTracks[index].time + seconds * additiveTracks[index].speed
            if duration > 0 {
                time = time.truncatingRemainder(dividingBy: duration)
                if time < 0 {
                    time += duration
                }
            }
            additiveTracks[index].time = time
        }
        if let phase = syncedPhase {
            let cycle = tracks.reduce(0) { $0 + $1.weight * durations[$1.animation] }
            let speed = tracks.first?.speed ?? 1
            let next = cycle > 0 ? phase + seconds * speed / cycle : phase
            syncedPhase = next - next.rounded(.down)
            applyPhase(syncedPhase ?? 0)
        } else {
            for index in tracks.indices {
                let duration = durations[tracks[index].animation]
                var time = tracks[index].time + seconds * tracks[index].speed
                if tracks[index].loops, duration > 0 {
                    time = time.truncatingRemainder(dividingBy: duration)
                    if time < 0 {
                        time += duration
                    }
                } else {
                    time = min(max(time, 0), duration)
                }
                tracks[index].time = time
            }
        }
        for index in tracks.indices {
            let step = tracks[index].fadeRate * seconds
            let target = tracks[index].targetWeight
            let weight = tracks[index].weight
            tracks[index].weight = weight < target ? min(weight + step, target) : max(weight - step, target)
        }
        tracks.removeAll { $0.weight <= 0 && $0.targetWeight <= 0 }
    }

    /// The tracks as layers, override weights normalized to sum to 1, then the additive tracks.
    public var layers: [GLTFAnimationLayer] {
        let additive = additiveTracks.map { GLTFAnimationLayer(animation: $0.animation, time: $0.time, weight: $0.weight, mode: .additive) }
        let total = tracks.reduce(0) { $0 + $1.weight }
        guard total > 0 else {
            // Mid cut with nothing faded in yet: show the newest clip.
            return (tracks.last.map { [GLTFAnimationLayer(animation: $0.animation, time: $0.time)] } ?? []) + additive
        }
        return tracks.filter { $0.weight > 0 }.map { GLTFAnimationLayer(animation: $0.animation, time: $0.time, weight: $0.weight / total) } + additive
    }

    /// The pose; with ``rootMotionNode`` set, without the root's horizontal movement.
    public func pose(in asset: GLTFAsset) -> PBRPose {
        asset.pose(layers: layers, rootMotionNode: rootMotionNode)
    }

    private mutating func settleFades() {
        for index in tracks.indices {
            tracks[index].weight = tracks[index].targetWeight
        }
        tracks.removeAll { $0.weight <= 0 }
    }

    private mutating func applyPhase(_ phase: Float) {
        for index in tracks.indices {
            tracks[index].time = phase * durations[tracks[index].animation]
        }
    }
}
