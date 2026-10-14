import Foundation
@testable import GLTFViewerSupport
import MetalSprocketsGLTF
import MetalSprocketsGLTFMeshopt
import SwiftGLTF
import Testing

private func section(_ items: [DocumentOutlineItem], _ id: String) -> DocumentOutlineItem? {
    items.first { $0.id == id }
}

// A basic shape: one scene with one mesh node, one mesh of one primitive, one material.
@Test func outlinesABasicShape() throws {
    let url = try #require(BasicShape.sphere.fileURL)
    let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()]))
    let items = DocumentOutline.items(for: asset)
    #expect(items.map(\.id) == ["scenes", "meshes", "materials"])
    let scene = try #require(section(items, "scenes")?.children?.first)
    #expect(scene.detail == "shown")
    let node = try #require(scene.children?.first)
    // gltfpack drops node names, so the node is listed by index.
    #expect(node.title == "Node 0")
    #expect(node.detail?.hasPrefix("mesh") == true)
    let primitive = try #require(section(items, "meshes")?.children?.first?.children?.first)
    #expect(primitive.detail?.contains("triangles") == true)
    #expect(primitive.detail?.contains("Neutral") == true)
    #expect(primitive.detail?.contains("NORMAL") == true)
    #expect(section(items, "materials")?.children?.first?.title == "Neutral")
}

// Node trees nest children, mark lights, and stop at cycles; every ID is unique.
@Test func outlinesHierarchiesLightsAndCycles() throws {
    let json = #"""
        {
        "asset": {"version": "2.0"},
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": {"KHR_lights_punctual": {"lights": [{"type": "spot", "intensity": 5, "spot": {}}]}},
        "scenes": [{"nodes": [0]}],
        "nodes": [
        {"name": "Root", "children": [1, 2]},
        {"name": "Lamp", "extensions": {"KHR_lights_punctual": {"light": 0}}},
        {"name": "Loop", "children": [0]}
        ]
        }
    """#
    // The loader rejects the cycle, so outline the document directly.
    let document = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    var path = Set<Int>()
    let root = DocumentOutline.node(document, 0, idPrefix: "scenes/0", path: &path)
    #expect(root.children?.map(\.title) == ["Lamp", "Loop"])
    #expect(root.children?.first?.detail == "spot light")
    #expect(root.children?.last?.children?.first?.detail == "cycle")
    func ids(_ item: DocumentOutlineItem) -> [String] { [item.id] + (item.children ?? []).flatMap(ids) }
    let all = ids(root)
    #expect(Set(all).count == all.count)
    #expect(DocumentOutline.lightDetail(document.punctualLights[0]).hasPrefix("spot · intensity 5"))
}

// Outline items refer to what they show, and the detail view lists its properties.
@Test func itemsHaveReferencesAndProperties() throws {
    let json = #"""
        {
        "asset": {"version": "2.0"},
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Root", "translation": [1, 2, 3], "children": [1]}, {"name": "Child"}],
        "materials": [{"name": "Red", "doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}}]
        }
    """#
    let document = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    var path = Set<Int>()
    let root = DocumentOutline.node(document, 0, idPrefix: "scenes/0", path: &path)
    #expect(root.reference == .node(0))
    #expect(root.children?.first?.reference == .node(1))
    #expect(DocumentOutline.materials(document).first?.reference == .material(0))

    let node = Dictionary(uniqueKeysWithValues: DocumentOutline.properties(of: .node(0), in: document).map { ($0.name, $0.value) })
    #expect(node["index"] == "0")
    #expect(node["name"] == "Root")
    #expect(node["translation"] == "[1,2,3]")
    #expect(node["children"] == "[1]")
    let material = Dictionary(uniqueKeysWithValues: DocumentOutline.properties(of: .material(0), in: document).map { ($0.name, $0.value) })
    #expect(material["doubleSided"] == "true")
    #expect(material["pbrMetallicRoughness"]?.contains("baseColorFactor") == true)
    #expect(DocumentOutline.properties(of: .node(9), in: document).isEmpty)
}
