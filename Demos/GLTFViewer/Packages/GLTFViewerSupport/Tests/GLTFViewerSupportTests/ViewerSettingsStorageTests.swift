import Foundation
@testable import GLTFViewerSupport
import MetalSprocketsGLTF
import Testing

// Changed settings survive a save and restore.
@Test func viewerSettingsRoundTrip() {
    var settings = ViewerSettings()
    settings.showsInspector = true
    settings.inspectorTab = .display
    settings.debugView = .uvChecker
    settings.toneMapping = .agx
    settings.environment = .hdri(.sunset)
    settings.environmentRotation = 45
    settings.mode = .split
    settings.split = 0.3
    settings.framebufferOnly = false
    settings.extendedDynamicRange = true
    settings.renderScale = 0.5
    let restored = ViewerSettings(storedData: settings.storedData)
    #expect(restored == settings)
}

// EDR switches the drawable, and the upscaling targets with it, to half float.
@Test func extendedDynamicRangeUsesFloatTargets() {
    var settings = ViewerSettings()
    settings.renderScale = 0.5
    #expect(settings.colorPixelFormat == .bgra8Unorm_srgb)
    settings.extendedDynamicRange = true
    #expect(settings.colorPixelFormat == .rgba16Float)
    #expect(settings.upscaling?.colorPixelFormat == .rgba16Float)
}

// A value that no longer exists resets only itself; the rest is kept.
@Test func staleStoredValuesFallBackIndividually() {
    let json = #"{"showsInspector": true, "inspectorTab": "Removed Tab", "debugView": 999, "environment": "hdri:gone", "toneMapping": 3, "split": 7}"#
    let restored = ViewerSettings(storedData: Data(json.utf8))
    #expect(restored.showsInspector)
    #expect(restored.inspectorTab == ViewerSettings().inspectorTab)
    #expect(restored.debugView == .lit)
    #expect(restored.environment == ViewerSettings().environment)
    #expect(restored.toneMapping == .agx)
    #expect(restored.split == 1)
}

// A picked HDR file is not restored (its sandbox access would be gone); unreadable data gives the defaults.
@Test func pickedFilesAndUnreadableDataRestoreAsDefaults() {
    var settings = ViewerSettings()
    settings.environment = .file(URL(fileURLWithPath: "/tmp/sky.hdr"))
    #expect(ViewerSettings(storedData: settings.storedData).environment == .studio)
    #expect(ViewerSettings(storedData: Data("not json".utf8)) == ViewerSettings())
}
