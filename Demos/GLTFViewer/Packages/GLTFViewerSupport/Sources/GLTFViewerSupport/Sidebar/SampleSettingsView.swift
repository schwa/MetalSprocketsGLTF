import SwiftUI

/// Settings for the glTF-Sample-Assets library: refresh the model index and clear downloaded files.
public struct SampleSettingsView: View {
    @Environment(SampleLibrary.self) private var library

    public init() {}

    public var body: some View {
        Form {
            Section("Sample Assets") {
                LabeledContent("Model Index") {
                    Button("Refresh") {
                        Task { await library.downloadIndex() }
                    }
                }
                LabeledContent("Downloaded Models") {
                    Button("Clear Cache", role: .destructive) {
                        library.clearCache()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
