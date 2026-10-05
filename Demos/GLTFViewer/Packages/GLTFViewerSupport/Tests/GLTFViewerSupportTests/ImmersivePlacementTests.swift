@testable import GLTFViewerSupport
import simd
import Testing

private func head(at position: SIMD3<Float>, yaw: Float, pitch: Float = 0) -> simd_float4x4 {
    var matrix = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0]))
    matrix.columns.3 = SIMD4(position, 1)
    return matrix
}

private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
    simd_distance(a, b) < 1e-4
}

// Ahead of the head along its facing, below eye height, with the model's front (+Z) toward the viewer.
@Test func placesInFrontOfTheHead() {
    // Facing -Z from (0, 1.6, 0): the model goes to (0, 1.5, -0.6), its front (+Z) toward the viewer.
    let straight = ImmersivePlacement.inFront(of: head(at: [0, 1.6, 0], yaw: 0))
    #expect(near(SIMD3(straight.columns.3.x, straight.columns.3.y, straight.columns.3.z), [0, 1.5, -0.6]))
    #expect(near(SIMD3(straight.columns.2.x, straight.columns.2.y, straight.columns.2.z), [0, 0, 1]))

    // Turned 90° left (facing -X) and standing elsewhere: ahead is -X, and the model's front faces +X.
    let turned = ImmersivePlacement.inFront(of: head(at: [2, 1.6, 3], yaw: .pi / 2))
    #expect(near(SIMD3(turned.columns.3.x, turned.columns.3.y, turned.columns.3.z), [1.4, 1.5, 3]))
    #expect(near(SIMD3(turned.columns.2.x, turned.columns.2.y, turned.columns.2.z), [1, 0, 0]))
}

// Looking down still places the model straight ahead by the same height rule, upright.
@Test func ignoresHeadPitch() {
    let placement = ImmersivePlacement.inFront(of: head(at: [0, 1.6, 0], yaw: 0, pitch: -0.5))
    #expect(near(SIMD3(placement.columns.3.x, placement.columns.3.y, placement.columns.3.z), [0, 1.5, -0.6]))
    #expect(near(SIMD3(placement.columns.1.x, placement.columns.1.y, placement.columns.1.z), [0, 1, 0]))
}
