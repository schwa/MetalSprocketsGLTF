import Foundation
@testable import GLTFViewerSupport
import MetalSprocketsGLTF
import Testing

// Each built-in scene is a valid glTF that loads without warnings, with the materials it advertises.
@Test(arguments: ShowcaseScene.allCases)
func showcaseSceneLoads(_ scene: ShowcaseScene) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).glb")
    try scene.glb().write(to: url)
    let asset = try GLTFAsset(url: url)
    #expect(asset.warnings.isEmpty, "\(asset.warnings)")
    switch scene {
    case .materialGrid:
        #expect(asset.materials.count == 25)
        #expect(asset.opaqueInstances.count == 25)
    case .showcase:
        #expect(asset.materials.count == 7)
        #expect(asset.hasTransmission)
        #expect(Set(asset.statistics.extensionsUsed).isSuperset(of: ["KHR_materials_transmission", "KHR_materials_clearcoat", "KHR_materials_sheen", "KHR_materials_iridescence", "KHR_materials_volume", "KHR_materials_ior"]))
        // The floor's checker texture (base color is the first texture slot).
        #expect(asset.materials[0].textureBindings[0].texture.width == 512)
    }
    // A copy to look at, when asked for.
    if let directory = ProcessInfo.processInfo.environment["WRITE_SHOWCASE_SCENES"] {
        try scene.glb().write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(scene.rawValue).glb"))
    }
}
