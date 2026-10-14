import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

/// The orbit camera's state. Comparing it against a snapshot tells whether the user has moved since picking a camera.
struct OrbitState: Equatable {
    var rotation: simd_quatf
    var distance: Float
    var target: SIMD3<Float>
    var fieldOfView: Float = .pi / 4

    /// Orbit state that looks from `worldMatrix` (a camera's placement) toward `center`'s depth along its view axis.
    init(cameraWorldMatrix worldMatrix: simd_float4x4, center: SIMD3<Float>, fieldOfView: Float) {
        let rotationMatrix = simd_float3x3(
            simd_normalize(worldMatrix.columns.0.xyz),
            simd_normalize(worldMatrix.columns.1.xyz),
            simd_normalize(worldMatrix.columns.2.xyz)
        )
        let position = worldMatrix.columns.3.xyz
        let forward = -rotationMatrix.columns.2
        let distance = max(simd_dot(center - position, forward), 1e-3)
        rotation = simd_normalize(simd_quatf(rotationMatrix))
        self.distance = distance
        target = position + forward * distance
        self.fieldOfView = fieldOfView
    }

    var cameraWorldMatrix: simd_float4x4 {
        var matrix = simd_float4x4(rotation)
        matrix.columns.3 = SIMD4(target - rotation.act([0, 0, -1]) * distance, 1)
        return matrix
    }
}
