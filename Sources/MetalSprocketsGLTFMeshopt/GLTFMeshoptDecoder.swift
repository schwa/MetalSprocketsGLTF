import CMeshoptimizer
import Foundation
import SwiftGLTF

/// EXT_meshopt_compression / KHR_meshopt_compression: a buffer view's bytes are meshoptimizer-compressed in another
/// buffer, and the view's own buffer may be a placeholder without data.
/// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Vendor/EXT_meshopt_compression
/// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_meshopt_compression
public struct MeshoptCompression: Decodable, Sendable {
    public enum Mode: String, Decodable, Sendable {
        case attributes = "ATTRIBUTES"
        case triangles = "TRIANGLES"
        case indices = "INDICES"
    }

    public enum Filter: String, Decodable, Sendable {
        case none = "NONE"
        case octahedral = "OCTAHEDRAL"
        case quaternion = "QUATERNION"
        case exponential = "EXPONENTIAL"
        /// KHR_meshopt_compression only.
        case color = "COLOR"
    }

    /// The buffer holding the compressed data, and where in it.
    public let buffer: Int
    public let byteOffset: Int
    public let byteLength: Int
    public let byteStride: Int
    public let count: Int
    public let mode: Mode
    public let filter: Filter

    enum CodingKeys: CodingKey {
        case buffer, byteOffset, byteLength, byteStride, count, mode, filter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buffer = try container.decode(Int.self, forKey: .buffer)
        byteOffset = try container.decodeIfPresent(Int.self, forKey: .byteOffset) ?? 0
        byteLength = try container.decode(Int.self, forKey: .byteLength)
        byteStride = try container.decode(Int.self, forKey: .byteStride)
        count = try container.decode(Int.self, forKey: .count)
        mode = try container.decode(Mode.self, forKey: .mode)
        filter = try container.decodeIfPresent(Filter.self, forKey: .filter) ?? .none
    }
}

private struct EXTMeshoptCompression: GLTFExtension {
    static let extensionName = "EXT_meshopt_compression"
    let compression: MeshoptCompression

    init(from decoder: Decoder) throws {
        compression = try MeshoptCompression(from: decoder)
    }
}

private struct KHRMeshoptCompression: GLTFExtension {
    static let extensionName = "KHR_meshopt_compression"
    let compression: MeshoptCompression

    init(from decoder: Decoder) throws {
        compression = try MeshoptCompression(from: decoder)
    }
}

public enum GLTFMeshoptError: Error, CustomStringConvertible {
    case sourceOutOfRange(buffer: Int)
    case decodingFailed(mode: MeshoptCompression.Mode, code: Int32)
    case unsupported(String)

    public var description: String {
        switch self {
        case .sourceOutOfRange(let buffer): "meshopt source range is outside buffer \(buffer)"
        case .decodingFailed(let mode, let code): "meshopt \(mode.rawValue) decoding failed (\(code))"
        case .unsupported(let message): "meshopt: \(message)"
        }
    }
}

/// Decompresses meshopt buffer views with meshoptimizer's decoder. Register it to load files using either extension:
///
/// ```swift
/// let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()]))
/// ```
public struct GLTFMeshoptDecoder: BufferViewDecoder {
    public let extensionNames: Set<String> = [EXTMeshoptCompression.extensionName, KHRMeshoptCompression.extensionName]

    public init() {}

    public func data(for bufferView: BufferView, in container: Container) throws -> Data? {
        guard let compression = try (bufferView.extensionValue(KHRMeshoptCompression.self)?.compression ?? bufferView.extensionValue(EXTMeshoptCompression.self)?.compression) else {
            return nil
        }
        return try Self.decode(compression, document: container.document) { try container.data(for: $0) }
    }

    /// The decoded bytes (`count * byteStride`), reading the compressed source through `bufferData`.
    static func decode(_ compression: MeshoptCompression, document: Document, bufferData: (Buffer) throws -> Data) throws -> Data {
        guard document.buffers.indices.contains(compression.buffer) else {
            throw GLTFMeshoptError.sourceOutOfRange(buffer: compression.buffer)
        }
        let buffer = try bufferData(document.buffers[compression.buffer])
        let range = compression.byteOffset ..< compression.byteOffset + compression.byteLength
        guard range.upperBound <= buffer.count else {
            throw GLTFMeshoptError.sourceOutOfRange(buffer: compression.buffer)
        }
        let source = buffer.subdata(in: range)
        var output = Data(count: compression.count * compression.byteStride)
        let code: Int32 = output.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { source in
                let input = source.bindMemory(to: UInt8.self)
                switch compression.mode {
                case .attributes:
                    return meshopt_decodeVertexBuffer(destination.baseAddress, compression.count, compression.byteStride, input.baseAddress, input.count)

                case .triangles:
                    return meshopt_decodeIndexBuffer(destination.baseAddress, compression.count, compression.byteStride, input.baseAddress, input.count)

                case .indices:
                    return meshopt_decodeIndexSequence(destination.baseAddress, compression.count, compression.byteStride, input.baseAddress, input.count)
                }
            }
        }
        guard code == 0 else {
            throw GLTFMeshoptError.decodingFailed(mode: compression.mode, code: code)
        }
        if compression.mode == .attributes {
            output.withUnsafeMutableBytes { bytes in
                switch compression.filter {
                case .none: break
                case .octahedral: meshopt_decodeFilterOct(bytes.baseAddress, compression.count, compression.byteStride)
                case .quaternion: meshopt_decodeFilterQuat(bytes.baseAddress, compression.count, compression.byteStride)
                case .exponential: meshopt_decodeFilterExp(bytes.baseAddress, compression.count, compression.byteStride)
                case .color: meshopt_decodeFilterColor(bytes.baseAddress, compression.count, compression.byteStride)
                }
            }
        }
        return output
    }
}
