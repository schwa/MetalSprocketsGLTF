import CoreGraphics
import Foundation
@testable import GLTFViewerSupport
import Testing

/// A 4 x 4 image filled with one sRGB gray.
private func gray(_ value: UInt8) throws -> CGImage {
    var pixels = [UInt8](repeating: value, count: 4 * 4 * 4)
    for index in stride(from: 3, to: pixels.count, by: 4) {
        pixels[index] = 255
    }
    return try #require(pixels.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    })
}

@Test func psnrOfIdenticalImagesIsInfinite() async throws {
    let psnr = await PSNR.between(try gray(100), try gray(100))
    #expect(psnr == .infinity)
}

// Every channel off by 10: MSE 100, so PSNR = 10 log10(255^2 / 100).
@Test func psnrOfAKnownDifference() async throws {
    let psnr = try #require(await PSNR.between(try gray(100), try gray(110)))
    #expect(abs(psnr - 10 * log10(255.0 * 255.0 / 100.0)) < 0.01)
}
