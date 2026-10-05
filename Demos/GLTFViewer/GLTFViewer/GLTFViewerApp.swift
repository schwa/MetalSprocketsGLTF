import GLTFViewerSupport
import SwiftUI

@main
struct GLTFViewerApp: App {
    @State private var library = SampleLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                // Room for the sidebar, the model and (on macOS) the inspector; smaller hides the controls.
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        #if os(macOS)
        Settings {
            SampleSettingsView()
                .environment(library)
        }
        #endif
        #if os(visionOS)
        InspectorWindow()
        GLTFImmersiveSpace()
        #endif
    }
}
