import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

/// The extensions the file uses, each with a toggle that reloads the model without it. Extensions the file requires,
/// and ones this app does not support, are listed without a toggle.
struct ExtensionsSection: View {
    var statistics: GLTFAssetStatistics
    @Environment(ViewerModel.self) private var viewer

    private static let supported = ViewerModel.loadOptions().supportedExtensions

    var body: some View {
        if !statistics.extensionsUsed.isEmpty {
            Section {
                ForEach(statistics.extensionsUsed, id: \.self) { name in
                    row(name)
                }
            } header: {
                Text("Extensions")
            } footer: {
                Text("Turning one off reloads the model as if the file did not use it.")
            }
        }
    }

    @ViewBuilder
    private func row(_ name: String) -> some View {
        if !Self.supported.contains(name) {
            LabeledContent(name, value: "Not supported")
        } else if statistics.extensionsRequired.contains(name) {
            LabeledContent(name, value: "Required")
        } else {
            @Bindable var viewer = viewer
            Toggle(name, isOn: $viewer.disabledExtensions[isEnabled: name])
        }
    }
}

extension Set<String> {
    /// For a set of disabled names: whether `name` is enabled (not in the set). Writable, so a toggle can bind to it
    /// by key path.
    subscript(isEnabled name: String) -> Bool {
        get { !contains(name) }
        set {
            if newValue {
                remove(name)
            } else {
                insert(name)
            }
        }
    }
}
