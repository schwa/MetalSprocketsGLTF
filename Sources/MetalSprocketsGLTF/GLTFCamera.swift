import MetalSprocketsPBR
import simd
import SwiftGLTF

public extension PBRCamera {
    /// A glTF camera placed at `worldMatrix`. `aspectRatio` is used when the camera does not set one.
    init(_ camera: SwiftGLTF.Camera, worldMatrix: simd_float4x4, aspectRatio: Float) {
        let projectionMatrix: simd_float4x4
        if let perspective = camera.perspective {
            projectionMatrix = .perspective(fovY: perspective.yfov, aspectRatio: perspective.aspectRatio ?? aspectRatio, near: perspective.znear, far: perspective.zfar ?? 10_000)
        } else if let orthographic = camera.orthographic {
            projectionMatrix = .orthographic(halfWidth: orthographic.xmag, halfHeight: orthographic.ymag, near: orthographic.znear, far: orthographic.zfar)
        } else {
            projectionMatrix = .perspective(fovY: .pi / 4, aspectRatio: aspectRatio, near: 0.01, far: 1_000)
        }
        self.init(viewMatrix: worldMatrix.inverse, projectionMatrix: projectionMatrix)
    }
}
