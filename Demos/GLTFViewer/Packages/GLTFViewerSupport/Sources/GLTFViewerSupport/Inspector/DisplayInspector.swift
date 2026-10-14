import Metal
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import SwiftUI
import WebReference

struct DisplayInspector: View {
    nonisolated static let renderScales: [Float] = [1, 0.75, 0.5]
    nonisolated static let supportsUpscaling = MTLCreateSystemDefaultDevice().map(PBRUpscaling.isSupported(device:)) ?? false

    /// MSAA sample counts this GPU can render with, 1 (off) first.
    nonisolated static let supportedSampleCounts: [Int] = {
        guard let device = MTLCreateSystemDefaultDevice() else { return [1] }
        return [1, 2, 4, 8].filter { device.supportsTextureSampleCount($0) }
    }()

    var hasFileEnvironment = false
    @Environment(ViewerPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Toggle("Environment Background", isOn: $preferences.settings.showsBackground)
                Picker("Antialiasing", selection: $preferences.settings.sampleCount) {
                    ForEach(Self.supportedSampleCounts, id: \.self) { count in
                        Text(count == 1 ? "Off" : "\(count)x MSAA").tag(count)
                    }
                }
                if Self.supportsUpscaling {
                    Picker("Render Scale", selection: $preferences.settings.renderScale) {
                        ForEach(Self.renderScales, id: \.self) { scale in
                            Text(scale == 1 ? "Full" : "\(Int(scale * 100))% + MetalFX").tag(scale)
                        }
                    }
                    .help("Draw at a lower resolution and upscale with MetalFX spatial scaling")
                }
                Picker("Shading", selection: $preferences.settings.debugView) {
                    ForEach(PBRDebugView.allCases) { view in
                        Text(view.name).tag(view)
                    }
                }
                .help("Show one shading input instead of the lit color")
                Toggle("Wireframe", isOn: $preferences.settings.showsWireframe)
                Toggle("Framebuffer Only", isOn: $preferences.settings.framebufferOnly)
                    .help("MTKView.framebufferOnly. Turn off if the view renders pink (Metal 4 / MetalSprockets workaround).")
                #if os(macOS)
                Toggle("Extended Dynamic Range", isOn: $preferences.settings.extendedDynamicRange)
                    .help("Float output for EDR displays. With Tone Mapping set to None (HDR), highlights brighter than white use the display's headroom.")
                #endif
                Picker("Tone Mapping", selection: $preferences.settings.toneMapping) {
                    ForEach(PBRToneMapping.allCases) { toneMapping in
                        Text(toneMapping.name).tag(toneMapping)
                    }
                }
                LabeledContent("Exposure") {
                    Slider(value: $preferences.settings.exposure, in: -4 ... 4)
                        .frame(width: 100)
                        .fixedSize()
                    Text(preferences.settings.exposure, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
                        .monospacedDigit()
                        .frame(width: 40)
                        .fixedSize()
                }
                .help("In stops: each step doubles or halves the light before tone mapping")
                .contextMenu {
                    Button("Reset") { preferences.settings.exposure = 0 }
                }
            }
            EnvironmentSection(hasFileEnvironment: hasFileEnvironment)
        }
        .formStyle(.grouped)
    }
}
