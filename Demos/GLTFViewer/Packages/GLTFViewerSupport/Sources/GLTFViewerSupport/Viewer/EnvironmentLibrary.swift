import Foundation
import MetalSprocketsGLTF
import MetalSprocketsPBR
import Observation
import UniformTypeIdentifiers

/// A CC0 HDRI from Poly Haven, downloaded at 1K on first use and cached.
public enum BundledHDRI: String, CaseIterable, Identifiable, Sendable {
    case outdoor = "kloofendal_48d_partly_cloudy_puresky"
    case workshop = "aerodynamics_workshop"
    case sunset = "venice_sunset"
    case photoStudio = "brown_photostudio_02"

    public var id: Self { self }

    public var name: String {
        switch self {
        case .outdoor: "Outdoor"
        case .workshop: "Workshop"
        case .sunset: "Sunset"
        case .photoStudio: "Photo Studio"
        }
    }

    var downloadURL: URL {
        URL(string: "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/\(rawValue)_1k.hdr")!
    }
}

/// What lights the viewer's models.
public enum ViewerEnvironment: Hashable, Sendable {
    /// The image-based light the model's file defines (EXT_lights_image_based); the studio for models without one.
    /// Built by the asset, not the library.
    case model
    /// The procedural studio built into MetalSprocketsGLTF.
    case studio
    case hdri(BundledHDRI)
    /// A plain mid-gray environment.
    case gray
    /// An .hdr or .exr the user picked.
    case file(URL)

    var name: String {
        switch self {
        case .model: "From Model"
        case .studio: "Studio"
        case .hdri(let hdri): hdri.name
        case .gray: "Gray"
        case .file(let url): url.lastPathComponent
        }
    }
}

/// Builds and caches environments (prefiltering takes a moment), downloading HDRIs when needed.
@preconcurrency
@MainActor
@Observable
public final class EnvironmentLibrary {
    public static let shared = EnvironmentLibrary()

    public enum State {
        case loading
        case ready(PBREnvironment)
        case failed(String)
    }

    private(set) var states: [ViewerEnvironment: State] = [:]

    static let fileTypes: [UTType] = ["hdr", "exr"].compactMap { UTType(filenameExtension: $0) }

    /// The built environment, or nil until ``load(_:)`` has built it or after it failed (callers fall back to the
    /// studio). Safe to call while views update: it changes nothing.
    func environment(_ choice: ViewerEnvironment) -> PBREnvironment? {
        if choice == .studio || choice == .model {
            return .studio
        }
        if case .ready(let environment) = states[choice] {
            return environment
        }
        return nil
    }

    /// Starts building `choice` unless it is built, building or failed.
    func request(_ choice: ViewerEnvironment) {
        guard choice != .studio, choice != .model, states[choice] == nil else { return }
        load(choice)
    }

    func state(_ choice: ViewerEnvironment) -> State? {
        choice == .studio || choice == .model ? .ready(.studio) : states[choice]
    }

    private func load(_ choice: ViewerEnvironment) {
        states[choice] = .loading
        Task {
            do {
                let source = try await Self.source(for: choice)
                let environment = try await Task.detached(priority: .userInitiated) {
                    try Self.build(source, choice: choice)
                }.value
                states[choice] = .ready(environment)
            } catch {
                states[choice] = .failed(error.localizedDescription)
            }
        }
    }

    private static func source(for choice: ViewerEnvironment) async throws -> PBREnvironment.Source {
        switch choice {
        case .studio, .model:
            return .studio

        case .gray:
            return .uniform([0.5, 0.5, 0.5])

        case .file(let url):
            return .equirectangular(url)

        case .hdri(let hdri):
            let directory = URL.cachesDirectory.appending(path: "GLTFViewer/HDRIs", directoryHint: .isDirectory)
            let file = directory.appending(path: "\(hdri.rawValue)_1k.hdr")
            if !FileManager.default.fileExists(atPath: file.path) {
                let (downloaded, response) = try await URLSession.shared.download(from: hdri.downloadURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.moveItem(at: downloaded, to: file)
            }
            return .equirectangular(file)
        }
    }

    /// A user-picked file is security-scoped: access is held only while it is read.
    nonisolated private static func build(_ source: PBREnvironment.Source, choice: ViewerEnvironment) throws -> PBREnvironment {
        var scoped: URL?
        if case .file(let url) = choice, url.startAccessingSecurityScopedResource() {
            scoped = url
        }
        defer { scoped?.stopAccessingSecurityScopedResource() }
        return try PBREnvironment(source: source)
    }
}
