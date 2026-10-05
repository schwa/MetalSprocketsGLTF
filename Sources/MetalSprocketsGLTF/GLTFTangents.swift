import simd
import SwiftMeshMikkTSpace

// glTF normal maps are baked against MikkTSpace tangents. When a normal-mapped primitive has no TANGENT attribute, the
// spec asks viewers to generate them with MikkTSpace.
enum GLTFTangents {
    /// MikkTSpace tangents (xyz, w = bitangent sign) for each corner of an indexed triangle list.
    static func cornerTangents(positions: [SIMD3<Float>], normals: [SIMD3<Float>], texCoords: [SIMD2<Float>], indices: [UInt32]) -> [SIMD4<Float>] {
        let input = Input(positions: positions, normals: normals, texCoords: texCoords, indices: indices)
        var interface = SMikkTSpaceInterface()
        interface.m_getNumFaces = { context in
            Int32(Input.from(context).indices.count / 3)
        }
        interface.m_getNumVerticesOfFace = { _, _ in 3 }
        interface.m_getPosition = { context, out, face, corner in
            let input = Input.from(context)
            let value = input.positions[input.vertex(face, corner)]
            out?[0] = value.x
            out?[1] = value.y
            out?[2] = value.z
        }
        interface.m_getNormal = { context, out, face, corner in
            let input = Input.from(context)
            let value = input.normals[input.vertex(face, corner)]
            out?[0] = value.x
            out?[1] = value.y
            out?[2] = value.z
        }
        interface.m_getTexCoord = { context, out, face, corner in
            let input = Input.from(context)
            let value = input.texCoords[input.vertex(face, corner)]
            out?[0] = value.x
            out?[1] = value.y
        }
        interface.m_setTSpaceBasic = { context, tangent, sign, face, corner in
            guard let tangent else { return }
            Input.from(context).tangents[Int(face) * 3 + Int(corner)] = SIMD4(tangent[0], tangent[1], tangent[2], sign)
        }
        withUnsafeMutablePointer(to: &interface) { interfacePointer in
            var context = SMikkTSpaceContext(m_pInterface: interfacePointer, m_pUserData: Unmanaged.passUnretained(input).toOpaque())
            _ = genTangSpaceDefault(&context)
        }
        return input.tangents
    }

    /// Splits vertices whose corners received different tangents, so each vertex has one tangent. Returns the new
    /// vertex order (indices into the old vertices), their tangents, and the remapped index list.
    static func weld(cornerTangents: [SIMD4<Float>], indices: [UInt32]) -> (sources: [Int], tangents: [SIMD4<Float>], indices: [UInt32]) {
        struct Key: Hashable {
            var vertex: UInt32
            var tangent: SIMD4<Float>
        }
        var lookup: [Key: UInt32] = [:]
        var sources: [Int] = []
        var tangents: [SIMD4<Float>] = []
        var newIndices: [UInt32] = []
        newIndices.reserveCapacity(indices.count)
        for (corner, vertex) in indices.enumerated() {
            let key = Key(vertex: vertex, tangent: cornerTangents[corner])
            if let existing = lookup[key] {
                newIndices.append(existing)
            } else {
                let index = UInt32(sources.count)
                lookup[key] = index
                sources.append(Int(vertex))
                tangents.append(key.tangent)
                newIndices.append(index)
            }
        }
        return (sources, tangents, newIndices)
    }

    private final class Input {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let texCoords: [SIMD2<Float>]
        let indices: [UInt32]
        var tangents: [SIMD4<Float>]

        init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], texCoords: [SIMD2<Float>], indices: [UInt32]) {
            self.positions = positions
            self.normals = normals
            self.texCoords = texCoords
            self.indices = indices
            tangents = Array(repeating: [1, 0, 0, 1], count: indices.count)
        }

        func vertex(_ face: Int32, _ corner: Int32) -> Int {
            Int(indices[Int(face) * 3 + Int(corner)])
        }

        static func from(_ context: UnsafePointer<SMikkTSpaceContext>?) -> Input {
            Unmanaged<Input>.fromOpaque(context!.pointee.m_pUserData).takeUnretainedValue()
        }
    }
}
