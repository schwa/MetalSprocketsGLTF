import simd

/// Where the immersive space puts models relative to the viewer.
enum ImmersivePlacement {
    static let distance: Float = 0.6
    static let belowEyes: Float = 0.1

    /// ``distance`` ahead of the head along its horizontal facing and ``belowEyes`` below eye height, upright and
    /// turned so the model's front (+Z) faces the viewer. `headTransform` is the head's (device's) transform in the
    /// space; it looks down its local -Z.
    static func inFront(of headTransform: simd_float4x4) -> simd_float4x4 {
        let head = SIMD3(headTransform.columns.3.x, headTransform.columns.3.y, headTransform.columns.3.z)
        var forward = -SIMD3(headTransform.columns.2.x, 0, headTransform.columns.2.z)
        forward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : [0, 0, -1]
        var matrix = simd_float4x4(simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0]))
        matrix.columns.3 = SIMD4(head + forward * distance + [0, -belowEyes, 0], 1)
        return matrix
    }
}
