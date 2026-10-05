import Foundation
import Metal
import MetalSupport
import Testing

/// Runs a test with Metal API validation, so invalid Metal usage aborts instead of passing silently.
///
/// The validation layer is chosen when the device is created, and MetalSupport caches the system default device.
/// Every test that touches Metal must use this trait so validation is on before the first device exists.
struct MetalValidationTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
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
