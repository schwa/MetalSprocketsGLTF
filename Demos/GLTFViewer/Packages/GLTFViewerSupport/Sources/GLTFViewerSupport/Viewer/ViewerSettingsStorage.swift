import Foundation
import MetalSprocketsGLTF
import MetalSprocketsPBR
import WebReference

// ViewerSettings persist across launches as JSON in UserDefaults (SamplesView's @AppStorage). Each field decodes on
// its own and falls back to its default, so a value that no longer exists (a removed tab, debug view or HDRI, a sample
// count this GPU lacks) resets only itself.
extension ViewerSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case mode, webLighting, split, showsBackground, showsInspector, inspectorTab, debugView, showsWireframe
        case framebufferOnly, toneMapping, exposure, environment, environmentIntensity, environmentRotation, sampleCount
        case renderScale, extendedDynamicRange
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            try? container.decodeIfPresent(T.self, forKey: key)
        }
        mode = value(.mode).flatMap(ComparisonMode.init(rawValue:)) ?? mode
        webLighting = value(.webLighting).flatMap(GLTFWebReference.LightingMode.init(rawValue:)) ?? webLighting
        split = value(.split).map { min(max($0, 0), 1) } ?? split
        showsBackground = value(.showsBackground) ?? showsBackground
        showsInspector = value(.showsInspector) ?? showsInspector
        inspectorTab = value(.inspectorTab).flatMap(InspectorTab.init(rawValue:)) ?? inspectorTab
        debugView = value(.debugView).flatMap(PBRDebugView.init(rawValue:)) ?? debugView
        showsWireframe = value(.showsWireframe) ?? showsWireframe
        framebufferOnly = value(.framebufferOnly) ?? framebufferOnly
        toneMapping = value(.toneMapping).flatMap(PBRToneMapping.init(rawValue:)) ?? toneMapping
        exposure = value(.exposure).map { min(max($0, -4), 4) } ?? exposure
        environment = value(.environment).flatMap(ViewerEnvironment.init(storedValue:)) ?? environment
        environmentIntensity = value(.environmentIntensity) ?? environmentIntensity
        environmentRotation = value(.environmentRotation) ?? environmentRotation
        if let count: Int = value(.sampleCount), DisplayInspector.supportedSampleCounts.contains(count) {
            sampleCount = count
        }
        if let scale: Float = value(.renderScale), DisplayInspector.renderScales.contains(scale) {
            renderScale = scale
        }
        extendedDynamicRange = value(.extendedDynamicRange) ?? extendedDynamicRange
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode.rawValue, forKey: .mode)
        try container.encode(webLighting.rawValue, forKey: .webLighting)
        try container.encode(split, forKey: .split)
        try container.encode(showsBackground, forKey: .showsBackground)
        try container.encode(showsInspector, forKey: .showsInspector)
        try container.encode(inspectorTab.rawValue, forKey: .inspectorTab)
        try container.encode(debugView.rawValue, forKey: .debugView)
        try container.encode(showsWireframe, forKey: .showsWireframe)
        try container.encode(framebufferOnly, forKey: .framebufferOnly)
        try container.encode(toneMapping.rawValue, forKey: .toneMapping)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(environment.storedValue, forKey: .environment)
        try container.encode(environmentIntensity, forKey: .environmentIntensity)
        try container.encode(environmentRotation, forKey: .environmentRotation)
        try container.encode(sampleCount, forKey: .sampleCount)
        try container.encode(renderScale, forKey: .renderScale)
        try container.encode(extendedDynamicRange, forKey: .extendedDynamicRange)
    }

    /// The stored settings, or the defaults when there are none or they cannot be read.
    init(storedData: Data) {
        self = (try? JSONDecoder().decode(ViewerSettings.self, from: storedData)) ?? ViewerSettings()
    }

    var storedData: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

extension ViewerEnvironment {
    /// A stable string for storage. A picked file is stored as the studio: sandbox access to it does not survive a
    /// relaunch without a security-scoped bookmark.
    var storedValue: String {
        switch self {
        case .model: "model"
        case .studio, .file: "studio"
        case .gray: "gray"
        case .hdri(let hdri): "hdri:\(hdri.rawValue)"
        }
    }

    init?(storedValue: String) {
        switch storedValue {
        case "model": self = .model
        case "studio": self = .studio
        case "gray": self = .gray

        default:
            guard storedValue.hasPrefix("hdri:"), let hdri = BundledHDRI(rawValue: String(storedValue.dropFirst(5))) else { return nil }
            self = .hdri(hdri)
        }
    }
}
