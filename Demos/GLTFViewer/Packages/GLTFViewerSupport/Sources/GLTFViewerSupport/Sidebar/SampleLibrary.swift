import Foundation
import Observation

/// An entry in the Khronos glTF-Sample-Assets `model-index.json`.
public struct SampleModel: Codable, Hashable, Identifiable, Sendable {
    public var label: String
    public var name: String
    public var screenshot: String?
    public var tags: [String]?
    public var variants: [String: String]

    public var id: String { name }

    /// The variant to download: a single file when there is one, else the plain `glTF` with its external files.
    var preferredVariant: (folder: String, file: String)? {
        for folder in ["glTF-Binary", "glTF-Embedded", "glTF"] {
            if let file = variants[folder] {
                return (folder, file)
            }
        }
        return nil
    }

    public var isSupported: Bool { preferredVariant != nil }

    /// One downloadable file variant of a model (a folder in glTF-Sample-Assets).
    public struct VariantChoice: Hashable, Identifiable, Sendable {
        public var folder: String
        public var file: String
        /// False for variants that need extensions GLTFAsset cannot load (Draco #8). KTX2 and meshopt load through
        /// the MetalSprocketsGLTFBasisU and MetalSprocketsGLTFMeshopt targets.
        public var isSupported: Bool
        public var id: String { folder }
    }

    /// Every variant, the one ``preferredVariant`` picks first, then supported ones, then the rest by name.
    public var variantChoices: [VariantChoice] {
        let unsupportedMarkers = ["Draco"]
        let preferred = preferredVariant?.folder
        return variants.map { folder, file in
            VariantChoice(folder: folder, file: file, isSupported: !unsupportedMarkers.contains { folder.contains($0) })
        }.sorted { lhs, rhs in
            func rank(_ choice: VariantChoice) -> Int {
                choice.folder == preferred ? 0 : ["glTF-Binary", "glTF-Embedded", "glTF"].firstIndex(of: choice.folder).map { $0 + 1 } ?? (choice.isSupported ? 4 : 5)
            }
            return (rank(lhs), lhs.folder) < (rank(rhs), rhs.folder)
        }
    }

    public func matches(_ filter: String) -> Bool {
        filter.isEmpty
            || label.localizedCaseInsensitiveContains(filter)
            || name.localizedCaseInsensitiveContains(filter)
            || (tags ?? []).contains { $0.localizedCaseInsensitiveContains(filter) }
    }
}

/// Downloads the sample index and individual models on demand, caching both on disk.
@preconcurrency
@MainActor
@Observable
public final class SampleLibrary {
    public enum State {
        case notDownloaded
        case downloading
        case loaded([SampleModel])
        case failed(String)
    }

    public private(set) var state: State = .notDownloaded
    public private(set) var cachedModelNames: Set<String> = []

    static let baseURL = URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/")!
    let cacheDirectory: URL
    var indexURL: URL { cacheDirectory.appending(path: "model-index.json") }
    private var inFlight: [String: Task<URL, Error>] = [:]

    public init() {
        cacheDirectory = URL.cachesDirectory.appending(path: "GLTFSamples", directoryHint: .isDirectory)
        if let data = try? Data(contentsOf: indexURL), let models = try? Self.decode(data) {
            state = .loaded(models)
            cachedModelNames = Set(models.filter { model in
                model.preferredVariant.map { FileManager.default.fileExists(atPath: localURL(model, $0).path) } ?? false
            }.map(\.name))
        }
    }

    public func downloadIndex() async {
        state = .downloading
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.baseURL.appending(path: "model-index.json"))
            let models = try Self.decode(data)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: indexURL)
            state = .loaded(models)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        cachedModelNames = []
        state = .notDownloaded
    }

    var isLoaded: Bool {
        if case .loaded = state { true } else { false }
    }

    public func isCached(_ model: SampleModel) -> Bool {
        cachedModelNames.contains(model.name)
    }

    /// Returns the cached file, downloading it first if needed. Concurrent calls share one download. `variant` picks a
    /// file variant by folder; nil uses ``SampleModel/preferredVariant``.
    public func fileURL(for model: SampleModel, variant folder: String? = nil) async throws -> URL {
        guard let variant = folder.flatMap({ folder in model.variants[folder].map { (folder: folder, file: $0) } }) ?? model.preferredVariant else {
            throw URLError(.unsupportedURL)
        }
        let destination = localURL(model, variant)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let key = "\(model.name)/\(variant.folder)"
        if let task = inFlight[key] {
            return try await task.value
        }
        let folderURL = Self.baseURL.appending(path: "\(model.name)/\(variant.folder)/")
        let task = Task<URL, Error> {
            let temporary = try await Self.download(folderURL.appending(path: variant.file))
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // A multi-file .gltf brings its buffers and images. They download first and the .gltf moves into place last,
            // so a cached .gltf always has its files.
            if destination.pathExtension.lowercased() == "gltf" {
                for path in try Self.externalFiles(ofGLTF: Data(contentsOf: temporary)) {
                    let file = directory.appending(path: path)
                    guard !FileManager.default.fileExists(atPath: file.path) else { continue }
                    let downloaded = try await Self.download(folderURL.appending(path: path))
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: downloaded, to: file)
                }
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let url = try await task.value
        // The list's downloaded marker tracks the default variant.
        if variant.folder == model.preferredVariant?.folder {
            cachedModelNames.insert(model.name)
        }
        return url
    }

    nonisolated static func download(_ url: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return temporary
    }

    /// Relative paths of the buffer and image files a .gltf references. Data URIs, absolute paths and paths that
    /// leave the model's folder are skipped.
    nonisolated static func externalFiles(ofGLTF data: Data) throws -> [String] {
        struct Document: Decodable {
            struct Resource: Decodable { var uri: String? }
            var buffers: [Resource]?
            var images: [Resource]?
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        return ((document.buffers ?? []) + (document.images ?? [])).compactMap { resource in
            guard let uri = resource.uri, !uri.hasPrefix("data:"), let path = uri.removingPercentEncoding,
                  !path.hasPrefix("/"), !path.split(separator: "/").contains("..")
            else {
                return nil
            }
            return path
        }
    }

    /// Where `model` is downloaded: its default variant's file, else its folder if any variant is downloaded, else nil.
    public func downloadedLocation(of model: SampleModel) -> URL? {
        if let variant = model.preferredVariant {
            let file = localURL(model, variant)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        let folder = cacheDirectory.appending(path: model.name, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    private func localURL(_ model: SampleModel, _ variant: (folder: String, file: String)) -> URL {
        cacheDirectory.appending(path: "\(model.name)/\(variant.folder)/\(variant.file)")
    }

    nonisolated static func decode(_ data: Data) throws -> [SampleModel] {
        try JSONDecoder().decode([SampleModel].self, from: data)
            .filter(\.isSupported)
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
