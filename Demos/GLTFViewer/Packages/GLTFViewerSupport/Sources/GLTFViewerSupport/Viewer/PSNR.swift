import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsGLTFMeshopt
import MetalSprocketsUI
import simd
import SwiftUI
import WebReference

/// Peak signal-to-noise ratio of two images in sRGB bytes, over RGB; infinity when they are identical. Images of
/// different sizes are compared at the first one's size.
enum PSNR {
    @concurrent
    static func between(_ lhs: CGImage, _ rhs: CGImage) async -> Double? {
        let width = lhs.width
        let height = lhs.height
        guard let a = rgba(lhs, width: width, height: height), let b = rgba(rhs, width: width, height: height) else { return nil }
        var sum = 0.0
        for index in 0 ..< width * height {
            for channel in 0 ..< 3 {
                let difference = Double(a[index * 4 + channel]) - Double(b[index * 4 + channel])
                sum += difference * difference
            }
        }
        let meanSquaredError = sum / Double(width * height * 3)
        return meanSquaredError == 0 ? .infinity : 10 * log10(255 * 255 / meanSquaredError)
    }

    private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
