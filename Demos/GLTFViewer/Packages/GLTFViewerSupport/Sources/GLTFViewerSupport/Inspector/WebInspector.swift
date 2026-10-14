import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

struct WebInspector: View {
    @Environment(ViewerPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("three.js") {
                Picker("Lighting", selection: $preferences.settings.webLighting) {
                    Text("Matched Lights").tag(GLTFWebReference.LightingMode.matched)
                    Text("Environment").tag(GLTFWebReference.LightingMode.environment)
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }
}
