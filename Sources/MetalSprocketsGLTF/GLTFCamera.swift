import GeometryLite3D
import MetalSprocketsPBR
import simd
import SwiftGLTF

public extension PBRCamera {
    /// A glTF camera placed at `worldMatrix`. `aspectRatio` is used when the camera does not set one.
    init(_ camera: SwiftGLTF.Camera, worldMatrix: simd_float4x4, aspectRatio: Float) {
        let projectionMatrix: simd_float4x4
        if let perspective = camera.perspective {
            let projection = PerspectiveProjection(verticalAngleOfView: .radians(perspective.yfov), depthMode: .reversed(zClip: perspective.znear ... (perspective.zfar ?? 10_000)))
            projectionMatrix = projection.projectionMatrix(aspectRatio: perspective.aspectRatio ?? aspectRatio)
        } else if let orthographic = camera.orthographic {
            projectionMatrix = Self.reversedOrthographic(halfWidth: orthographic.xmag, halfHeight: orthographic.ymag, near: orthographic.znear, far: orthographic.zfar)
        } else {
            projectionMatrix = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.01 ... 1_000)).projectionMatrix(aspectRatio: aspectRatio)
        }
        self.init(viewMatrix: worldMatrix.inverse, projectionMatrix: projectionMatrix)
    }

    // GeometryLite3D's OrthographicProjection can't take independent xmag/ymag.
    private static func reversedOrthographic(halfWidth: Float, halfHeight: Float, near: Float, far: Float) -> simd_float4x4 {
        let depth = 1 / (far - near)
        return simd_float4x4(columns: ([1 / halfWidth, 0, 0, 0], [0, 1 / halfHeight, 0, 0], [0, 0, depth, 0], [0, 0, far * depth, 1]))
    }
}
