import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftMesh

/// Simple models built into the viewer, so lighting, materials and debug views can be checked without downloading.
/// They ship as .glb files in the bundle (Resources/BasicShapes), generated from `mesh` and packed with gltfpack
/// (quantized and meshopt-compressed) by `just basic-shapes`, so they load like any other file.
public enum BasicShape: String, CaseIterable, Identifiable, Sendable {
    case sphere
    case cube
    case plane
    case cylinder
    case cone
    case torus

    public var id: Self { self }

    public var name: String { rawValue.capitalized }

    public var systemImage: String {
        switch self {
        case .sphere: "circle"
        case .cube: "cube"
        case .plane: "square"
        case .cylinder: "cylinder"
        case .cone: "cone"
        case .torus: "circle.circle"
        }
    }

    /// The shape's bundled .glb.
    public var fileURL: URL? {
        Bundle.module.url(forResource: name, withExtension: "glb", subdirectory: "BasicShapes")
    }

    /// Unit-sized (fits in -0.5...0.5), centred on the origin, counter-clockwise front faces.
    var mesh: ShapeMesh {
        switch self {
        case .sphere: .sphere(radius: 0.5, segments: 64, rings: 32)
        case .cube: .cube(size: 1)
        case .plane: .plane(size: 1)
        case .cylinder: .cylinder(radius: 0.5, height: 1, segments: 64)
        case .cone: .cone(radius: 0.5, height: 1, segments: 64)
        case .torus: .torus(radius: 0.35, tubeRadius: 0.15, segments: 64, tubeSegments: 32)
        }
    }
}

public extension BasicShape {
    /// The shape built directly as a ``PBRModel``, without glTF: the same mesh and neutral material as its .glb (before
    /// gltfpack), through ``PBRGeometryBuilder`` and ``PBRModelBuilder``.
    func model(device: MTLDevice) throws -> PBRModel {
        var geometry = PBRGeometryBuilder(device: device)
        try geometry.add(attributes: mesh.attributes, indices: mesh.indices, label: name)
        let primitive = try geometry.build()[0]
        let material = try PBRMaterial(name: "Neutral", uniforms: .defaults(baseColor: ShapeMesh.neutralColor, metallic: 0, roughness: 0.5), placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: [matrix_identity_float4x4]))
        builder.addInstance(primitive, material: material, node: 0)
        return try builder.build()
    }
}

struct ShapeMesh {
    static let neutralColor: SIMD4<Float> = [0.8, 0.8, 0.8, 1]

    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var texCoords: [SIMD2<Float>]
    var indices: [UInt32]

    /// A SwiftMesh mesh flattened to indexed vertices. It must have normals and texture coordinates.
    init(_ mesh: Mesh) {
        let arrays = mesh.vertexArrays()
        func floats(_ attribute: MetalMesh.VertexAttributeData?) -> [Float] {
            guard let attribute else {
                fatalError("ShapeMesh needs positions, normals and texture coordinates from SwiftMesh")
            }
            return attribute.bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        let positions = floats(arrays.attributes.first { $0.semantic == .position })
        let normals = floats(arrays.attributes.first { $0.semantic == .normal })
        let texCoords = floats(arrays.attributes.first { $0.semantic == .texcoord(0) })
        self.positions = (0 ..< arrays.vertexCount).map { SIMD3(positions[$0 * 3], positions[$0 * 3 + 1], positions[$0 * 3 + 2]) }
        self.normals = (0 ..< arrays.vertexCount).map { SIMD3(normals[$0 * 3], normals[$0 * 3 + 1], normals[$0 * 3 + 2]) }
        self.texCoords = (0 ..< arrays.vertexCount).map { SIMD2(texCoords[$0 * 2], texCoords[$0 * 2 + 1]) }
        self.indices = arrays.submeshes.flatMap(\.indices)
    }

    private static let smooth: MeshAttributes = [.smoothNormals, .textureCoordinates]
    private static let flat: MeshAttributes = [.flatNormals, .textureCoordinates]

    static func sphere(radius: Float, segments: Int, rings: Int) -> Self {
        Self(.sphere(extents: SIMD3(repeating: radius * 2), latitudeSegments: rings, longitudeSegments: segments, attributes: smooth))
    }

    static func cube(size: Float) -> Self {
        Self(.box(extents: SIMD3(repeating: size), attributes: flat))
    }

    /// In the XZ plane, facing +Y, with the top of the texture toward -Z.
    static func plane(size: Float) -> Self {
        Self(Mesh.quad(extents: [size, size], attributes: flat).rotated(by: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])))
    }

    static func cylinder(radius: Float, height: Float, segments: Int) -> Self {
        Self(.cylinder(segments: segments, height: height, radius: radius, attributes: smooth))
    }

    static func cone(radius: Float, height: Float, segments: Int) -> Self {
        Self(.cone(segments: segments, height: height, radius: radius, attributes: smooth))
    }

    static func torus(radius: Float, tubeRadius: Float, segments: Int, tubeSegments: Int) -> Self {
        Self(.torus(majorSegments: segments, minorSegments: tubeSegments, majorRadius: radius, minorRadius: tubeRadius, attributes: smooth))
    }

    /// The mesh's vertex attributes, for ``PBRGeometryBuilder``: no tangents or vertex colors.
    var attributes: [MetalMesh.VertexAttributeData] {
        [.positions(positions), .normals(normals), .textureCoordinates(texCoords)]
    }

    /// A binary glTF with one mesh, one node and a neutral PBR material.
    func glb(name: String) throws -> Data {
        var binary = Data()
        func append<T>(_ values: [T]) -> (offset: Int, length: Int) {
            let offset = binary.count
            values.withUnsafeBytes { binary.append(contentsOf: $0) }
            return (offset, binary.count - offset)
        }
        // SIMD3<Float> is 16 bytes in memory; glTF wants packed 12-byte VEC3.
        func packed(_ vectors: [SIMD3<Float>]) -> [Float] { vectors.flatMap { [$0.x, $0.y, $0.z] } }
        let positions = append(packed(self.positions))
        let normals = append(packed(self.normals))
        let texCoords = append(self.texCoords.flatMap { [$0.x, $0.y] })
        let indices = append(self.indices)
        let minimum = self.positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let maximum = self.positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "GLTFViewer BasicShape"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0, "name": name]],
            "meshes": [["name": name, "primitives": [["attributes": ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2], "indices": 3, "material": 0]]]],
            "materials": [["name": "Neutral", "pbrMetallicRoughness": ["baseColorFactor": [Self.neutralColor.x, Self.neutralColor.y, Self.neutralColor.z, Self.neutralColor.w], "metallicFactor": 0, "roughnessFactor": 0.5]]],
            "buffers": [["byteLength": binary.count]],
            "bufferViews": [
                ["buffer": 0, "byteOffset": positions.offset, "byteLength": positions.length, "target": 34_962],
                ["buffer": 0, "byteOffset": normals.offset, "byteLength": normals.length, "target": 34_962],
                ["buffer": 0, "byteOffset": texCoords.offset, "byteLength": texCoords.length, "target": 34_962],
                ["buffer": 0, "byteOffset": indices.offset, "byteLength": indices.length, "target": 34_963]
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5_126, "count": self.positions.count, "type": "VEC3", "min": [minimum.x, minimum.y, minimum.z], "max": [maximum.x, maximum.y, maximum.z]],
                ["bufferView": 1, "componentType": 5_126, "count": self.normals.count, "type": "VEC3"],
                ["bufferView": 2, "componentType": 5_126, "count": self.texCoords.count, "type": "VEC2"],
                ["bufferView": 3, "componentType": 5_125, "count": self.indices.count, "type": "SCALAR"]
            ]
        ]
        var jsonChunk = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        jsonChunk.append(contentsOf: [UInt8](repeating: 0x20, count: (4 - jsonChunk.count % 4) % 4))
        binary.append(contentsOf: [UInt8](repeating: 0, count: (4 - binary.count % 4) % 4))

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
