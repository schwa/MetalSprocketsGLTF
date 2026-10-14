import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

struct CameraInspector: View {
    var asset: GLTFAsset
    @Environment(ViewerModel.self) private var viewer

    var body: some View {
        @Bindable var viewer = viewer
        let orbit = viewer.orbit
        Form {
            Section("View") {
                Picker("Camera", selection: $viewer.activeCamera) {
                    Text("Orbit").tag(Int?.none)
                    ForEach(asset.cameras.indices, id: \.self) { index in
                        Text(cameraName(index)).tag(Int?.some(index))
                    }
                }
                if let activeCamera = viewer.activeCamera, asset.cameras.indices.contains(activeCamera) {
                    LabeledContent("Projection", value: projectionDescription(activeCamera))
                    Text("Drag to orbit from this camera.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Orbit") {
                LabeledContent("Field of View") {
                    Slider(value: $viewer.fieldOfViewDegrees, in: 10 ... 120)
                        .frame(width: 100)
                        .fixedSize()
                    Text(viewer.fieldOfViewDegrees, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 40)
                        .fixedSize()
                }
                LabeledContent("Distance", value: orbit.distance, format: .number.precision(.significantDigits(3)))
                LabeledContent("Target", value: vectorDescription(orbit.target))
                LabeledContent("Position", value: vectorDescription(orbit.cameraWorldMatrix.columns.3.xyz))
                Button("Reset View") {
                    viewer.resetView()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func cameraName(_ index: Int) -> String {
        asset.cameras[index].camera.name ?? "Camera \(index)"
    }

    private func projectionDescription(_ index: Int) -> String {
        let camera = asset.cameras[index].camera
        if let perspective = camera.perspective {
            return "Perspective, \(Int((perspective.yfov * 180 / .pi).rounded()))° vertical"
        }
        if camera.orthographic != nil {
            return "Orthographic"
        }
        return "Unknown"
    }

    private func vectorDescription(_ vector: SIMD3<Float>) -> String {
        [vector.x, vector.y, vector.z].map { $0.formatted(.number.precision(.significantDigits(3))) }.joined(separator: ", ")
    }
}
