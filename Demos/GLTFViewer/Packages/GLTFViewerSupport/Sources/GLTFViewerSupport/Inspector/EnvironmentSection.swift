import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

/// The image-based lighting: which environment, how bright, and its rotation.
struct EnvironmentSection: View {
    @Environment(ViewerPreferences.self) private var preferences
    /// The model's scene has its own image-based light (EXT_lights_image_based).
    var hasFileEnvironment = false
    @State private var isChoosingFile = false
    private let library = EnvironmentLibrary.shared

    private var choices: [ViewerEnvironment] {
        var choices: [ViewerEnvironment] = [.model, .studio] + BundledHDRI.allCases.map { .hdri($0) } + [.gray]
        if case .file = preferences.settings.environment {
            choices.append(preferences.settings.environment)
        }
        return choices
    }

    var body: some View {
        @Bindable var preferences = preferences
        Section("Environment") {
            Picker("Environment", selection: $preferences.settings.environment) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice.name).tag(choice)
                }
            }
            .help("From Model uses the image-based light the model's file defines (EXT_lights_image_based), or the studio")
            if preferences.settings.environment == .model {
                Text(hasFileEnvironment ? "Using the model's image-based light." : "This model defines no environment; using the studio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Choose HDR File") {
                isChoosingFile = true
            }
            switch library.state(preferences.settings.environment) {
            case .loading:
                ProgressView("Preparing \(preferences.settings.environment.name)")
                    .controlSize(.small)

            case .failed(let message):
                Text("Cannot load \(preferences.settings.environment.name): \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)

            case .ready, nil:
                EmptyView()
            }
            LabeledContent("Intensity") {
                Slider(value: $preferences.settings.environmentIntensity, in: 0 ... 3)
                    .frame(width: 100)
                    .fixedSize()

                Text(preferences.settings.environmentIntensity, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 40)
                    .fixedSize()
            }
            LabeledContent("Rotation") {
                Slider(value: $preferences.settings.environmentRotation, in: -180 ... 180)
                    .frame(width: 100)
                    .fixedSize()

                Text("\(Int(preferences.settings.environmentRotation.rounded()))\u{00B0}")
                    .monospacedDigit()
                    .frame(width: 40)
                    .fixedSize()
            }
        }
        // Start building the chosen environment as soon as it is picked.
        .onChange(of: preferences.settings.environment, initial: true) {
            library.request(preferences.settings.environment)
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: EnvironmentLibrary.fileTypes) { result in
            if case .success(let url) = result {
                preferences.settings.environment = .file(url)
            }
        }
    }
}
