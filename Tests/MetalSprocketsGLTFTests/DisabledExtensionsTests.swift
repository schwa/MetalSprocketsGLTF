import Foundation
@testable import MetalSprocketsGLTF
import Testing

private func clearcoatFile(required: Bool = false) throws -> URL {
    let url = try makeExtensionMaterialFile(#"{"KHR_materials_clearcoat": {"clearcoatFactor": 1}}"#, extensionsUsed: ["KHR_materials_clearcoat"])
    guard required else { return url }
    let json = try String(contentsOf: url, encoding: .utf8)
        .replacingOccurrences(of: #""extensionsUsed": ["#, with: #""extensionsRequired": ["KHR_materials_clearcoat"], "extensionsUsed": ["#)
    try json.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// A disabled material extension is ignored; the file still reports using it.
@Test(.requiresMetal4, .requiresMetal4) func disabledMaterialExtensionIsIgnored() throws {
    let url = try clearcoatFile()
    #expect(try GLTFAsset(url: url).materials.first?.uniforms.clearcoatFactor == 1)
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(disabledExtensions: ["KHR_materials_clearcoat"]))
    #expect(asset.materials.first?.uniforms.clearcoatFactor == 0)
    #expect(asset.statistics.extensionsUsed.contains("KHR_materials_clearcoat"))
}

// Document-level extension data goes too: without KHR_materials_variants there are no variants.
@Test(.requiresMetal4, .requiresMetal4) func disabledDocumentExtensionIsIgnored() throws {
    let url = try makeVariantsTriangleFile()
    #expect(try GLTFAsset(url: url).variantNames == ["Blue", "Plain"])
    #expect(try GLTFAsset(url: url, options: GLTFLoadOptions(disabledExtensions: ["KHR_materials_variants"])).variantNames.isEmpty)
}

// Disabling an extension the file requires makes it unsupported: the load fails, or warns when allowed.
@Test(.requiresMetal4, .requiresMetal4) func disablingARequiredExtensionFailsTheLoad() throws {
    let url = try clearcoatFile(required: true)
    #expect(throws: GLTFUnsupportedExtensionsError.self) {
        try GLTFAsset(url: url, options: GLTFLoadOptions(disabledExtensions: ["KHR_materials_clearcoat"]))
    }
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(disabledExtensions: ["KHR_materials_clearcoat"], loadsUnsupportedRequiredExtensions: true))
    #expect(asset.materials.first?.uniforms.clearcoatFactor == 0)
    #expect(asset.warnings.contains { $0.contains("KHR_materials_clearcoat") })
}
