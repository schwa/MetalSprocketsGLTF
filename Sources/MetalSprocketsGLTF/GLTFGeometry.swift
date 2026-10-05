import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import simd
import SwiftGLTF
import SwiftMesh

enum GLTFGeometry {
    /// A glTF primitive's vertex attributes and index list, for ``PBRGeometryBuilder``.
    struct Primitive {
        var attributes: [MetalMesh.VertexAttributeData]
        var indices: [UInt32]
        var primitiveType: MTLPrimitiveType
        var morphTargets: MetalMesh.MorphTargets?
    }

    /// A glTF primitive's data. Strips, fans and loops become lists; normal-mapped primitives without tangents get
    /// MikkTSpace tangents. Nil when nothing would be drawn.
    /// `defaultWeights` are the mesh's morph weights (glTF mesh.weights); used when they match the targets.
    static func makePrimitive(_ primitive: SwiftGLTF.Mesh.Primitive, container: Container, defaultWeights: [Float]) throws -> Primitive? {
        let document = container.document
        func floats(_ semantic: SwiftGLTF.Mesh.Primitive.Semantic) throws -> (values: [Float], components: Int)? {
            guard let index = primitive.attributes[semantic] else { return nil }
            let accessor = try index.resolve(in: document)
            return (try container.floatComponents(for: accessor), accessor.type.componentCount)
        }

        guard let positions = try floats(.POSITION) else {
            throw PBRGeometryError.missingPositions
        }
        let vertexCount = positions.values.count / 3
        func vectors2(_ data: (values: [Float], components: Int)?) -> [SIMD2<Float>]? {
            data.map { data in (0 ..< vertexCount).map { SIMD2(data.values[$0 * 2], data.values[$0 * 2 + 1]) } }
        }
        func vectors3(_ values: [Float]) -> [SIMD3<Float>] {
            (0 ..< vertexCount).map { SIMD3(values[$0 * 3], values[$0 * 3 + 1], values[$0 * 3 + 2]) }
        }
        func vectors4(_ data: (values: [Float], components: Int)?) -> [SIMD4<Float>]? {
            data.map { data in
                (0 ..< vertexCount).map { index in
                    let base = index * data.components
                    return data.components == 4
                        ? SIMD4(data.values[base], data.values[base + 1], data.values[base + 2], data.values[base + 3])
                        : SIMD4(data.values[base], data.values[base + 1], data.values[base + 2], 1)
                }
            }
        }
        var positionValues = vectors3(positions.values)
        var normals = try floats(.NORMAL).map { vectors3($0.values) }
        var tangents = try vectors4(floats(.TANGENT))
        var texCoords0 = try vectors2(floats(.TEXCOORD_0))
        var texCoords1 = try vectors2(floats(.TEXCOORD_1))
        var colors = try vectors4(floats(.COLOR_0))
        // Missing attributes in a target contribute nothing.
        var morphTargets: [MetalMesh.MorphTargets.Target] = try primitive.targets.map { target in
            func offsets(_ semantic: SwiftGLTF.Mesh.Primitive.Semantic) throws -> [SIMD3<Float>]? {
                guard let index = target[semantic] else { return nil }
                let values = try container.floatComponents(for: index.resolve(in: document))
                guard values.count == vertexCount * 3 else {
                    throw GLTFError.invalidDocument("Morph target \(semantic.rawValue) count mismatch")
                }
                return vectors3(values)
            }
            return MetalMesh.MorphTargets.Target(positionOffsets: try offsets(.POSITION), normalOffsets: try offsets(.NORMAL), tangentOffsets: try offsets(.TANGENT))
        }
        var joints: [SIMD4<UInt16>]?
        var weights: [SIMD4<Float>]?
        if let jointData = try floats(.JOINTS_0), let weightData = try floats(.WEIGHTS_0), jointData.components == 4, weightData.components == 4 {
            joints = vectors4(jointData)?.map { SIMD4<UInt16>($0, rounding: .toNearestOrEven) }
            weights = vectors4(weightData)
        }

        var indices: [UInt32]
        if let indicesIndex = primitive.indices {
            indices = try readIndices(container.data(for: indicesIndex.resolve(in: document)), componentType: indicesIndex.resolve(in: document).componentType)
        } else {
            indices = (0 ..< UInt32(vertexCount)).map(\.self)
        }

        let primitiveType: MTLPrimitiveType
        switch primitive.mode {
        case .TRIANGLES:
            primitiveType = .triangle
            indices.removeLast(indices.count % 3)
        case .TRIANGLE_STRIP:
            primitiveType = .triangle
            indices = triangleList(fromStrip: indices)
        case .TRIANGLE_FAN:
            primitiveType = .triangle
            indices = triangleList(fromFan: indices)
        case .POINTS:
            primitiveType = .point
        case .LINES:
            primitiveType = .line
            indices.removeLast(indices.count % 2)
        case .LINE_STRIP:
            primitiveType = .line
            indices = lineList(fromStrip: indices, closed: false)
        case .LINE_LOOP:
            primitiveType = .line
            indices = lineList(fromStrip: indices, closed: true)
        }
        guard !indices.isEmpty else { return nil }

        // glTF requires flat normals when NORMAL is missing. The fragment shader derives them per pixel (hasNormals), so
        // vertices stay shared instead of being unwelded per triangle.

        // Normal-mapped primitives without TANGENT get MikkTSpace tangents, the space their normal maps are baked in.
        // Vertices are split where adjacent triangles need different tangents (UV seams, mirrored UVs).
        var hasTangents = tangents != nil
        let materialIndices = [primitive.material?.index].compactMap(\.self) + primitive.variantMaterials.values
        let normalMapTexCoord = materialIndices.lazy.compactMap { index in
            index < document.materials.count ? document.materials[index].normalTexture?.texCoord : nil
        }.first
        if !hasTangents, let normalValues = normals, primitiveType == .triangle, let normalMapTexCoord {
            let texCoords = (normalMapTexCoord == 1 ? texCoords1 : texCoords0) ?? Array(repeating: .zero, count: vertexCount)
            let cornerTangents = GLTFTangents.cornerTangents(
                positions: positionValues,
                normals: normalValues,
                // glTF's v runs down the image; MikkTSpace (as in Blender, where maps are baked) expects v up.
                texCoords: texCoords.map { SIMD2($0.x, 1 - $0.y) },
                indices: indices
            )
            let welded = GLTFTangents.weld(cornerTangents: cornerTangents, indices: indices)
            func remap<T>(_ values: [T]?) -> [T]? {
                values.map { values in welded.sources.map { values[$0] } }
            }
            positionValues = remap(positionValues)!
            normals = remap(normals)
            texCoords0 = remap(texCoords0)
            texCoords1 = remap(texCoords1)
            colors = remap(colors)
            joints = remap(joints)
            weights = remap(weights)
            morphTargets = morphTargets.map { target in
                MetalMesh.MorphTargets.Target(positionOffsets: remap(target.positionOffsets), normalOffsets: remap(target.normalOffsets), tangentOffsets: remap(target.tangentOffsets))
            }
            tangents = welded.tangents
            indices = welded.indices
            hasTangents = true
        }

        var attributes: [MetalMesh.VertexAttributeData] = [.positions(positionValues)]
        if let normals { attributes.append(.normals(normals)) }
        if let tangents { attributes.append(.tangents(tangents)) }
        if let texCoords0 { attributes.append(.textureCoordinates(texCoords0, set: 0)) }
        if let texCoords1 { attributes.append(.textureCoordinates(texCoords1, set: 1)) }
        if let colors { attributes.append(.colors(colors)) }
        if let joints, let weights {
            attributes.append(.jointIndices(joints))
            attributes.append(.jointWeights(weights))
        }
        return Primitive(
            attributes: attributes,
            indices: indices,
            primitiveType: primitiveType,
            morphTargets: morphTargets.isEmpty ? nil : MetalMesh.MorphTargets(targets: morphTargets, defaultWeights: defaultWeights.count == morphTargets.count ? defaultWeights : [])
        )
    }

    static func readIndices(_ data: Data, componentType: Accessor.ComponentType) -> [UInt32] {
        data.withUnsafeBytes { raw in
            switch componentType {
            case .UNSIGNED_BYTE:
                return raw.map { UInt32($0) }
            case .UNSIGNED_SHORT:
                return (0 ..< raw.count / 2).map { UInt32(raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
            default:
                return (0 ..< raw.count / 4).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
            }
        }
    }

    /// Consecutive pairs of a line strip, plus the closing segment for a loop.
    static func lineList(fromStrip strip: [UInt32], closed: Bool) -> [UInt32] {
        guard strip.count >= 2 else { return [] }
        var lines = zip(strip, strip.dropFirst()).flatMap { [$0, $1] }
        if closed, strip.count > 2, let first = strip.first, let last = strip.last {
            lines += [last, first]
        }
        return lines
    }

    static func triangleList(fromStrip strip: [UInt32]) -> [UInt32] {
        guard strip.count >= 3 else { return [] }
        var result: [UInt32] = []
        for index in 0 ..< strip.count - 2 {
            if index.isMultiple(of: 2) {
                result += [strip[index], strip[index + 1], strip[index + 2]]
            } else {
                result += [strip[index + 1], strip[index], strip[index + 2]]
            }
        }
        return result
    }

    static func triangleList(fromFan fan: [UInt32]) -> [UInt32] {
        guard fan.count >= 3 else { return [] }
        return (1 ..< fan.count - 1).flatMap { [fan[0], fan[$0], fan[$0 + 1]] }
    }
}
