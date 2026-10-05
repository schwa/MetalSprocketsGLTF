import CoreGraphics
import Foundation
import ImageIO
import simd
import UniformTypeIdentifiers

/// Built-in scenes that show what the renderer can do, made from the basic shapes. Written as .glb files on first use
/// (in Caches), so they load like any other file, including the three.js comparison.
public enum ShowcaseScene: String, CaseIterable, Identifiable, Sendable {
    /// Spheres stepping metallic (rows) and roughness (columns).
    case materialGrid
    /// The shapes on a checkered floor, each in a different material.
    case showcase

    public var id: Self { self }

    public var name: String {
        switch self {
        case .materialGrid: "Material Grid"
        case .showcase: "Showcase"
        }
    }

    public var systemImage: String {
        switch self {
        case .materialGrid: "circle.grid.3x3.fill"
        case .showcase: "sparkles"
        }
    }

    /// Bump when the generated content changes, so cached files are rewritten.
    static let version = 1

    /// The scene's .glb, written to Caches the first time.
    public func fileURL() throws -> URL {
        let directory = URL.cachesDirectory.appending(path: "GLTFViewer/Showcase", directoryHint: .isDirectory)
        let url = directory.appending(path: "\(rawValue)-v\(Self.version).glb")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try glb().write(to: url, options: .atomic)
        }
        return url
    }

    func glb() throws -> Data {
        var builder = GLBBuilder()
        switch self {
        case .materialGrid:
            let sphere = builder.addMesh(ShapeMesh.sphere(radius: 0.4, segments: 64, rings: 32))
            let steps = 5
            for row in 0 ..< steps {
                for column in 0 ..< steps {
                    let metallic = Float(row) / Float(steps - 1)
                    let roughness = max(Float(column) / Float(steps - 1), 0.04)
                    let material = builder.addMaterial([
                        "name": "metallic \(metallic) roughness \(roughness)",
                        "pbrMetallicRoughness": ["baseColorFactor": [0.95, 0.55, 0.25, 1], "metallicFactor": metallic, "roughnessFactor": roughness],
                    ])
                    builder.addNode(mesh: sphere, material: material, translation: [Float(column - steps / 2), Float(steps / 2 - row), 0])
                }
            }
        case .showcase:
            let checker = builder.addImage(try Self.checkerPNG())
            let floor = builder.addMaterial([
                "name": "Checkered Floor",
                "pbrMetallicRoughness": ["baseColorTexture": ["index": checker], "metallicFactor": 0, "roughnessFactor": 0.7],
            ])
            builder.addNode(mesh: builder.addMesh(.plane(size: 4.5)), material: floor, translation: [0, 0, 0])
            let pieces: [(mesh: ShapeMesh, material: [String: Any], rotation: simd_quatf?)] = [
                (.sphere(radius: 0.5, segments: 64, rings: 32), [
                    "name": "Gold",
                    "pbrMetallicRoughness": ["baseColorFactor": [1, 0.766, 0.336, 1], "metallicFactor": 1, "roughnessFactor": 0.18],
                ], nil),
                (.sphere(radius: 0.5, segments: 64, rings: 32), [
                    "name": "Glass",
                    "pbrMetallicRoughness": ["baseColorFactor": [0.95, 1, 0.97, 1], "metallicFactor": 0, "roughnessFactor": 0.03],
                    "extensions": ["KHR_materials_transmission": ["transmissionFactor": 1], "KHR_materials_ior": ["ior": 1.5], "KHR_materials_volume": ["thicknessFactor": 0.6, "attenuationColor": [0.85, 0.97, 0.9], "attenuationDistance": 1.5]],
                ], nil),
                (.torus(radius: 0.35, tubeRadius: 0.15, segments: 64, tubeSegments: 32), [
                    "name": "Car Paint",
                    "pbrMetallicRoughness": ["baseColorFactor": [0.55, 0.02, 0.03, 1], "metallicFactor": 0.4, "roughnessFactor": 0.45],
                    "extensions": ["KHR_materials_clearcoat": ["clearcoatFactor": 1, "clearcoatRoughnessFactor": 0.03]],
                ], simd_quatf(angle: .pi / 2, axis: [1, 0, 0])),
                (.cube(size: 0.9), [
                    "name": "Velvet",
                    "pbrMetallicRoughness": ["baseColorFactor": [0.18, 0.04, 0.25, 1], "metallicFactor": 0, "roughnessFactor": 0.9],
                    "extensions": ["KHR_materials_sheen": ["sheenColorFactor": [0.85, 0.5, 1], "sheenRoughnessFactor": 0.4]],
                ], simd_quatf(angle: .pi / 5, axis: [0, 1, 0])),
                (.cone(radius: 0.5, height: 1, segments: 64), [
                    "name": "Iridescent",
                    "pbrMetallicRoughness": ["baseColorFactor": [0.9, 0.9, 0.9, 1], "metallicFactor": 1, "roughnessFactor": 0.15],
                    "extensions": ["KHR_materials_iridescence": ["iridescenceFactor": 1, "iridescenceIor": 1.3, "iridescenceThicknessMinimum": 100, "iridescenceThicknessMaximum": 400]],
                ], nil),
                (.cylinder(radius: 0.4, height: 1, segments: 64), [
                    "name": "Satin Plastic",
                    "pbrMetallicRoughness": ["baseColorFactor": [0.1, 0.35, 0.85, 1], "metallicFactor": 0, "roughnessFactor": 0.35],
                ], nil),
            ]
            for (index, piece) in pieces.enumerated() {
                let column = Float(index % 3) - 1
                let row = Float(index / 3)
                builder.addNode(mesh: builder.addMesh(piece.mesh), material: builder.addMaterial(piece.material), translation: [column * 1.6, 0.5, row * 1.6 - 0.8], rotation: piece.rotation)
            }
        }
        return try builder.glb()
    }

    /// A 512 x 512 PNG of 16 x 16 light and mid gray squares.
    static func checkerPNG() throws -> Data {
        let size = 512
        let cell = size / 16
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let value: UInt8 = ((x / cell) + (y / cell)).isMultiple(of: 2) ? 200 : 90
                let index = (y * size + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}

/// Writes a binary glTF of shape meshes, materials (glTF material JSON), embedded images and nodes.
struct GLBBuilder {
    private var binary = Data()
    private var bufferViews: [[String: Any]] = []
    private var accessors: [[String: Any]] = []
    private var meshAccessors: [(positions: Int, normals: Int, texCoords: Int, indices: Int)] = []
    private var materials: [[String: Any]] = []
    private var images: [[String: Any]] = []
    private var meshes: [[String: Any]] = []
    private var meshKeys: [String: Int] = [:]
    private var nodes: [[String: Any]] = []
    private var extensionsUsed = Set<String>()

    private mutating func appendView(_ bytes: Data, target: Int?) -> Int {
        binary.append(contentsOf: [UInt8](repeating: 0, count: (4 - binary.count % 4) % 4))
        var view: [String: Any] = ["buffer": 0, "byteOffset": binary.count, "byteLength": bytes.count]
        if let target {
            view["target"] = target
        }
        binary.append(bytes)
        bufferViews.append(view)
        return bufferViews.count - 1
    }

    private mutating func appendAccessor(_ values: [Float], components: Int, type: String, bounds: (SIMD3<Float>, SIMD3<Float>)? = nil) -> Int {
        let view = appendView(values.withUnsafeBytes { Data($0) }, target: 34962)
        var accessor: [String: Any] = ["bufferView": view, "componentType": 5126, "count": values.count / components, "type": type]
        if let (minimum, maximum) = bounds {
            accessor["min"] = [minimum.x, minimum.y, minimum.z]
            accessor["max"] = [maximum.x, maximum.y, maximum.z]
        }
        accessors.append(accessor)
        return accessors.count - 1
    }

    /// Vertex data for `mesh`; returns a handle for ``addNode(mesh:material:translation:rotation:)``.
    mutating func addMesh(_ mesh: ShapeMesh) -> Int {
        let minimum = mesh.positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maximum = mesh.positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let positions = appendAccessor(mesh.positions.flatMap { [$0.x, $0.y, $0.z] }, components: 3, type: "VEC3", bounds: (minimum, maximum))
        let normals = appendAccessor(mesh.normals.flatMap { [$0.x, $0.y, $0.z] }, components: 3, type: "VEC3")
        let texCoords = appendAccessor(mesh.texCoords.flatMap { [$0.x, $0.y] }, components: 2, type: "VEC2")
        let indexView = appendView(mesh.indices.withUnsafeBytes { Data($0) }, target: 34963)
        accessors.append(["bufferView": indexView, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])
        meshAccessors.append((positions, normals, texCoords, accessors.count - 1))
        return meshAccessors.count - 1
    }

    /// A glTF material; extension names are added to extensionsUsed. Returns its index.
    mutating func addMaterial(_ material: [String: Any]) -> Int {
        if let extensions = material["extensions"] as? [String: Any] {
            extensionsUsed.formUnion(extensions.keys)
        }
        materials.append(material)
        return materials.count - 1
    }

    /// An embedded PNG as a texture (image, texture and default sampler); returns the texture index.
    mutating func addImage(_ png: Data) -> Int {
        let view = appendView(png, target: nil)
        images.append(["bufferView": view, "mimeType": "image/png"])
        return images.count - 1
    }

    /// A node drawing mesh handle `mesh` with material `material`.
    mutating func addNode(mesh: Int, material: Int, translation: SIMD3<Float>, rotation: simd_quatf? = nil) {
        let key = "\(mesh)-\(material)"
        let meshIndex: Int
        if let existing = meshKeys[key] {
            meshIndex = existing
        } else {
            let data = meshAccessors[mesh]
            meshes.append(["primitives": [["attributes": ["POSITION": data.positions, "NORMAL": data.normals, "TEXCOORD_0": data.texCoords], "indices": data.indices, "material": material]]])
            meshIndex = meshes.count - 1
            meshKeys[key] = meshIndex
        }
        var node: [String: Any] = ["mesh": meshIndex, "translation": [translation.x, translation.y, translation.z]]
        if let name = materials[material]["name"] {
            node["name"] = name
        }
        if let rotation {
            node["rotation"] = [rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real]
        }
        nodes.append(node)
    }

    func glb() throws -> Data {
        var binary = binary
        binary.append(contentsOf: [UInt8](repeating: 0, count: (4 - binary.count % 4) % 4))
        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "GLTFViewer ShowcaseScene"],
            "scene": 0,
            "scenes": [["nodes": Array(nodes.indices)]],
            "nodes": nodes,
            "meshes": meshes,
            "materials": materials,
            "accessors": accessors,
            "bufferViews": bufferViews,
            "buffers": [["byteLength": binary.count]],
        ]
        if !images.isEmpty {
            json["images"] = images
            json["textures"] = images.indices.map { ["source": $0, "sampler": 0] }
            json["samplers"] = [["magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497]]
        }
        if !extensionsUsed.isEmpty {
            json["extensionsUsed"] = extensionsUsed.sorted()
        }
        var jsonChunk = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        jsonChunk.append(contentsOf: [UInt8](repeating: 0x20, count: (4 - jsonChunk.count % 4) % 4))
        var glb = Data()
        func appendUInt32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { glb.append(contentsOf: $0) }
        }
        appendUInt32(0x4654_6C67) // "glTF"
        appendUInt32(2)
        appendUInt32(UInt32(12 + 8 + jsonChunk.count + 8 + binary.count))
        appendUInt32(UInt32(jsonChunk.count))
        appendUInt32(0x4E4F_534A) // "JSON"
        glb.append(jsonChunk)
        appendUInt32(UInt32(binary.count))
        appendUInt32(0x004E_4942) // "BIN\0"
        glb.append(binary)
        return glb
    }
}
