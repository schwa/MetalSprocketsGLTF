import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case model = "Model"
    case document = "Document"
    case display = "Display"
    case web = "three.js"

    var id: Self { self }
}

/// Inspector content: a row of tabs over the selected tab. Reads ``ViewerModel`` and ``ViewerPreferences`` from the
/// environment.
struct ViewerInspector: View {
    @Environment(ViewerModel.self) private var viewer
    @Environment(ViewerPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        if let loaded = viewer.loaded {
            VStack(spacing: 0) {
                Picker("Inspector", selection: $preferences.settings.inspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
                Divider()
                switch preferences.settings.inspectorTab {
                case .camera:
                    CameraInspector(asset: loaded.asset)

                case .model:
                    ModelInspector(loaded: loaded)

                case .document:
                    DocumentInspector(asset: loaded.asset)

                case .display:
                    DisplayInspector(hasFileEnvironment: loaded.asset.imageBasedLight != nil)

                case .web:
                    WebInspector()
                }
            }
        } else {
            ContentUnavailableView("No Model", systemImage: "sidebar.trailing", description: Text("Open a model to inspect it."))
        }
    }
}
