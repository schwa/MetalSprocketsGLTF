import Foundation
import Metal
import MetalSupport
import Testing

// Copies of the helpers in Tests/MetalSprocketsGLTFTests at the repository root.

enum SampleAssets {
    // <repo>/Demos/GLTFViewer/Packages/WebReference/Tests/WebReferenceTests/TestSupport.swift -> <repo>
    static let modelsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: ".sample-assets/Models", directoryHint: .isDirectory)

    static var indexURL: URL { modelsDirectory.appending(path: "model-index.json") }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: indexURL.path) }

    struct Model: Decodable, CustomTestStringConvertible, Sendable {
        var name: String
        var variants: [String: String]
        var testDescription: String { name }

        /// The .glb, else the plain .gltf with its external files.
        var preferredURL: URL? {
            variants["glTF-Binary"].map { SampleAssets.modelsDirectory.appending(path: "\(name)/glTF-Binary/\($0)") }
                ?? variants["glTF"].map { SampleAssets.modelsDirectory.appending(path: "\(name)/glTF/\($0)") }
        }
    }

    static func preferredModels() -> [Model] {
        guard let data = try? Data(contentsOf: indexURL), let models = try? JSONDecoder().decode([Model].self, from: data) else {
            return []
        }
        return models.filter { $0.preferredURL != nil }.sorted { $0.name < $1.name }
    }
}

/// Runs a test with Metal API validation. See `MetalValidation.swift` in the root package tests.
struct MetalValidationTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try #require(MetalValidation.isEnabled, "Metal API validation is not active: the Metal device was created before MTL_DEBUG_LAYER was set.")
        try await function()
    }
}

extension Trait where Self == MetalValidationTrait {
    static var metalValidation: Self { Self() }
}

enum MetalValidation {
    static let isEnabled: Bool = {
        setenv("MTL_DEBUG_LAYER", "1", 1)
        let device = _MTLCreateSystemDefaultDevice()
        return String(describing: type(of: device)).contains("Debug")
    }()
}
