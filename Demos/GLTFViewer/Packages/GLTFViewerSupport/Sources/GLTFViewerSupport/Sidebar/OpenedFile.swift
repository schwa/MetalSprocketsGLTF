import Foundation
import UniformTypeIdentifiers

/// A user-opened glTF file, holding sandbox access for as long as it is shown.
///
/// The App Sandbox grants access to the file the user picks, but a .gltf usually loads sibling .bin and image files
/// by relative URI. For those the user also picks the containing folder, and access comes from that folder instead.
@MainActor
final class OpenedFile {
    let url: URL
    /// The security-scoped URL access was started on: the file itself, or its folder.
    private let scopedURL: URL
    private let isAccessing: Bool
    /// A .gltf with external files, opened with access to the file only: it cannot load until its folder is granted.
    let needsFolderAccess: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, scopedURL: URL, needsFolderAccess: Bool = false) {
        self.url = url
        self.scopedURL = scopedURL
        self.needsFolderAccess = needsFolderAccess
        isAccessing = scopedURL.startAccessingSecurityScopedResource()
    }

    isolated deinit {
        if isAccessing {
            scopedURL.stopAccessingSecurityScopedResource()
        }
    }

    static let contentTypes: [UTType] = [
        UTType(filenameExtension: "glb") ?? .data,
        UTType(filenameExtension: "gltf") ?? .json
    ]

    /// Whether `url` references files outside itself (buffers or images that are not data URIs).
    ///
    /// .glb files are treated as self-contained; a .glb that references external files is rare and not handled.
    nonisolated static func needsFolderAccess(_ url: URL) throws -> Bool {
        guard url.pathExtension.lowercased() == "gltf" else {
            return false
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let resources = (json["buffers"] as? [[String: Any]] ?? []) + (json["images"] as? [[String: Any]] ?? [])
        return resources.contains { resource in
            guard let uri = resource["uri"] as? String else { return false }
            return !uri.hasPrefix("data:")
        }
    }
}
