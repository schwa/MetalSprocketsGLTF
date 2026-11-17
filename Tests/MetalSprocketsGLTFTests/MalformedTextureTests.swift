import Foundation
@testable import MetalSprocketsGLTF
import Testing
import zlib

/// A triangle whose material uses texture `textureIndex` as its base color, with the given textures, images and
/// samplers. One 4-byte buffer view (index 1) follows the positions, for images that point at a buffer view.
func makeTexturedTriangleFile(textureIndex: Int = 0, textures: String, images: String = "[]", samplers: String = "[]") throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let buffer = (positions.withUnsafeBytes { Data($0) } + Data([1, 2, 3, 4])).base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": \(textureIndex)}}}],
      "textures": \(textures),
      "images": \(images),
      "samplers": \(samplers),
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 4}],
      "buffers": [{"byteLength": 40, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// A PNG with a valid signature and header claiming `width` × `height` pixels, and a tiny, truncated image body.
func makePNGHeader(width: UInt32, height: UInt32) -> Data {
    func chunk(_ type: String, _ body: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { data.append(contentsOf: $0) }
        let typed = Data(type.utf8) + body
        data.append(typed)
        let crc = typed.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(typed.count))) }
        withUnsafeBytes(of: crc.bigEndian) { data.append(contentsOf: $0) }
        return data
    }
    var header = Data()
    withUnsafeBytes(of: width.bigEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: height.bigEndian) { header.append(contentsOf: $0) }
    header.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit RGBA, no interlace.
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header) + chunk("IDAT", Data([0x78, 0x9C, 0x03, 0x00])) + chunk("IEND", Data())
}

// Bad texture data must give an error or a warning, never a crash. Each case is one malformed file.
@Suite(.requiresMetal4)
struct MalformedTextureTests {
    static let goodImage = #"[{"uri": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="}]"#

    static let cases: [(name: String, textureIndex: Int, textures: String, images: String, samplers: String)] = [
        ("negative texture index", -1, #"[{"source": 0}]"#, goodImage, "[]"),
        ("texture index out of range", 9, #"[{"source": 0}]"#, goodImage, "[]"),
        ("negative image index", 0, #"[{"source": -1}]"#, goodImage, "[]"),
        ("image index out of range", 0, #"[{"source": 9}]"#, goodImage, "[]"),
        ("negative sampler index", 0, #"[{"source": 0, "sampler": -1}]"#, goodImage, "[]"),
        ("sampler index out of range", 0, #"[{"source": 0, "sampler": 9}]"#, goodImage, "[]"),
        ("negative buffer view", 0, #"[{"source": 0}]"#, #"[{"bufferView": -1, "mimeType": "image/png"}]"#, "[]"),
        ("buffer view out of range", 0, #"[{"source": 0}]"#, #"[{"bufferView": 9, "mimeType": "image/png"}]"#, "[]"),
        ("bytes that are not an image", 0, #"[{"source": 0}]"#, #"[{"bufferView": 1, "mimeType": "image/png"}]"#, "[]"),
        ("empty data URI", 0, #"[{"source": 0}]"#, #"[{"uri": "data:image/png;base64,"}]"#, "[]"),
        ("missing file", 0, #"[{"source": 0}]"#, #"[{"uri": "does-not-exist.png"}]"#, "[]"),
        ("image without data", 0, #"[{"source": 0}]"#, #"[{}]"#, "[]"),
        ("bad sampler enums", 0, #"[{"source": 0, "sampler": 0}]"#, goodImage, #"[{"magFilter": 1, "minFilter": -5, "wrapS": 0, "wrapT": 99999}]"#)
    ]

    @Test(arguments: cases.indices)
    func loadsWithoutCrashing(_ index: Int) throws {
        let item = Self.cases[index]
        let url = try makeTexturedTriangleFile(textureIndex: item.textureIndex, textures: item.textures, images: item.images, samplers: item.samplers)
        // Throwing is fine; crashing is not. When it loads, the texture is skipped with a warning.
        if let asset = try? GLTFAsset(url: url) {
            #expect(!asset.warnings.isEmpty, "\(item.name)")
        }
    }

    // A PNG header that claims a huge image must not make the loader allocate for it.
    @Test func hugeDeclaredImageSize() throws {
        let png = makePNGHeader(width: 1 << 20, height: 1 << 20).base64EncodedString()
        let url = try makeTexturedTriangleFile(textures: #"[{"source": 0}]"#, images: #"[{"uri": "data:image/png;base64,\#(png)"}]"#)
        if let asset = try? GLTFAsset(url: url) {
            #expect(!asset.warnings.isEmpty)
        }
    }
}
