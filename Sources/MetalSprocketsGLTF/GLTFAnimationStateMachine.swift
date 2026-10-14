import MetalSprocketsPBR

/// Chooses which clip plays from named states and transitions, driving a ``GLTFAnimationController``: e.g. idle,
/// walk and run, switched by a `speed` parameter, cross-fading on each change.
///
/// A value type: set ``parameters``, call ``advance(by:in:)`` each frame, then ``pose(in:)``.
public struct GLTFAnimationStateMachine: Sendable {
    public struct State: Sendable {
        public var name: String
        public var animation: Int
        public var speed: Float
        public var loops: Bool

        public init(_ name: String, animation: Int, speed: Float = 1, loops: Bool = true) {
            self.name = name
            self.animation = animation
            self.speed = speed
            self.loops = loops
        }
    }

    /// What a transition's condition can look at.
    public struct Context: Sendable {
        public var parameters: [String: Float]
        /// How far through its clip the current state is, 0 ... 1 (above 1 once a non-looping clip has finished).
        public var normalizedTime: Float
        /// Seconds since the current state was entered.
        public var stateTime: Float
    }

    public struct Transition: Sendable {
        /// The state it leaves; nil leaves any state.
        public var from: String?
        public var to: String
        public var fadeDuration: Float
        public var condition: @Sendable (Context) -> Bool

        @preconcurrency
        public init(from: String?, to: String, fadeDuration: Float = 0.25, when condition: @escaping @Sendable (Context) -> Bool) {
            self.from = from
            self.to = to
            self.fadeDuration = fadeDuration
            self.condition = condition
        }
    }

    public let states: [String: State]
    public let transitions: [Transition]
    public var parameters: [String: Float] = [:]
    public private(set) var currentState: String
    public private(set) var stateTime: Float = 0
    /// The controller playing the states' clips; set its ``GLTFAnimationController/rootMotionNode`` or additive
    /// clips here.
    public var controller: GLTFAnimationController

    /// Starts in `initial`. Transitions are checked in order; the first whose condition holds is taken.
    public init(controller: GLTFAnimationController, states: [State], transitions: [Transition], initial: String) {
        precondition(states.contains { $0.name == initial }, "The initial state must be one of the states")
        self.states = Dictionary(states.map { ($0.name, $0) }) { first, _ in first }
        self.transitions = transitions
        self.controller = controller
        currentState = initial
        enter(initial, fadeDuration: 0)
    }

    public var context: Context {
        let state = states[currentState]
        let duration = state.map { controller.durations[$0.animation] } ?? 0
        let time = state.flatMap { state in controller.tracks.first { $0.animation == state.animation } }?.time ?? 0
        let normalized: Float
        if let state, !state.loops, duration > 0 {
            // A finished non-looping clip holds its last frame; report it past the end so "on finish" fires.
            normalized = stateTime * abs(state.speed) >= duration ? max(time / duration, 1) + 1e-6 : time / duration
        } else {
            normalized = duration > 0 ? time / duration : 0
        }
        return Context(parameters: parameters, normalizedTime: normalized, stateTime: stateTime)
    }

    /// Takes the first transition whose condition holds (at most one per call), then advances the controller.
    public mutating func advance(by seconds: Float, in asset: GLTFAsset) {
        let context = context
        if let transition = transitions.first(where: { ($0.from == nil || $0.from == currentState) && $0.to != currentState && states[$0.to] != nil && $0.condition(context) }) {
            enter(transition.to, fadeDuration: transition.fadeDuration)
        }
        stateTime += seconds
        controller.advance(by: seconds, in: asset)
    }

    public func pose(in asset: GLTFAsset) -> PBRPose {
        controller.pose(in: asset)
    }

    private mutating func enter(_ name: String, fadeDuration: Float) {
        guard let state = states[name] else { return }
        currentState = name
        stateTime = 0
        controller.play(state.animation, fadeDuration: fadeDuration, speed: state.speed, loops: state.loops, restarts: true)
    }
}
