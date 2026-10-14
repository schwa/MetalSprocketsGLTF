import Foundation
@testable import GLTFViewerSupport
import Testing

// Single-file variants are preferred; models with only a multi-file glTF variant are kept and use it.
@Test func decodePrefersSingleFileVariantsSorted() throws {
    let json = """
    [
      {"label": "Zebra", "name": "Zebra", "tags": ["core"], "variants": {"glTF-Binary": "Zebra.glb", "glTF": "Zebra.gltf"}},
      {"label": "Apple", "name": "Apple", "variants": {"glTF-Embedded": "Apple.gltf"}},
      {"label": "Split", "name": "Split", "variants": {"glTF": "Split.gltf"}},
      {"label": "Draco", "name": "Draco", "variants": {"glTF-Draco": "Draco.gltf"}}
    ]
    """
    let models = try SampleLibrary.decode(Data(json.utf8))
    #expect(models.map(\.name) == ["Apple", "Split", "Zebra"])
    #expect(models[0].preferredVariant?.folder == "glTF-Embedded")
    #expect(models[1].preferredVariant?.folder == "glTF")
    #expect(models[2].preferredVariant?.folder == "glTF-Binary")
}

// Every file variant is offered, the default first; variants that need unsupported extensions are marked.
@Test func variantChoicesPutTheDefaultFirst() {
    let model = SampleModel(label: "Duck", name: "Duck", variants: [
        "glTF": "Duck.gltf", "glTF-Binary": "Duck.glb", "glTF-Draco": "Duck.gltf", "glTF-Quantized": "Duck.gltf",
        "glTF-Embedded": "Duck.gltf", "glTF-KTX-BasisU": "Duck.gltf", "glTF-Meshopt": "Duck.gltf",
        "glTF-KTX-BasisU-Draco": "Duck.gltf"
    ])
    let choices = model.variantChoices
    #expect(choices.first?.folder == "glTF-Binary")
    #expect(Set(choices.map(\.folder)) == Set(model.variants.keys))
    // KTX2 and meshopt load through their optional targets; Draco is not supported, alone or combined with KTX2.
    #expect(choices.filter(\.isSupported).map(\.folder) == ["glTF-Binary", "glTF-Embedded", "glTF", "glTF-KTX-BasisU", "glTF-Meshopt", "glTF-Quantized"])
    #expect(choices.filter { !$0.isSupported }.map(\.folder).sorted() == ["glTF-Draco", "glTF-KTX-BasisU-Draco"])
}

// A multi-file .gltf's buffers and images are downloaded beside it; data URIs and escaping paths are skipped.
@Test func externalFilesOfAGLTF() throws {
    let json = """
    {
      "buffers": [{"uri": "Mesh%20Data.bin", "byteLength": 4}, {"uri": "data:application/octet-stream;base64,AAAA", "byteLength": 3}],
      "images": [{"uri": "textures/Color.png"}, {"bufferView": 0, "mimeType": "image/png"}, {"uri": "../../secret.png"}, {"uri": "/etc/passwd"}]
    }
    """
    #expect(try SampleLibrary.externalFiles(ofGLTF: Data(json.utf8)) == ["Mesh Data.bin", "textures/Color.png"])
}

func writeTemporary(_ contents: String, extension pathExtension: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(pathExtension)")
    try Data(contents.utf8).write(to: url)
    return url
}

@Test func folderAccessOnlyForExternalResources() throws {
    let embedded = try writeTemporary(#"{"buffers": [{"uri": "data:application/octet-stream;base64,AAAA"}], "images": [{"bufferView": 0}]}"#, extension: "gltf")
    let externalBuffer = try writeTemporary(#"{"buffers": [{"uri": "model.bin"}]}"#, extension: "gltf")
    let externalImage = try writeTemporary(#"{"buffers": [], "images": [{"uri": "textures/albedo.png"}]}"#, extension: "gltf")
    let binary = try writeTemporary("not json", extension: "glb")
    #expect(try !OpenedFile.needsFolderAccess(embedded))
    #expect(try OpenedFile.needsFolderAccess(externalBuffer))
    #expect(try OpenedFile.needsFolderAccess(externalImage))
    #expect(try !OpenedFile.needsFolderAccess(binary))
}

@Test func filterMatchesNameLabelAndTags() {
    let model = SampleModel(label: "Damaged Helmet", name: "DamagedHelmet", tags: ["showcase", "pbr"], variants: ["glTF-Binary": "DamagedHelmet.glb"])
    #expect(model.matches(""))
    #expect(model.matches("helmet"))
    #expect(model.matches("PBR"))
    #expect(!model.matches("duck"))
}
