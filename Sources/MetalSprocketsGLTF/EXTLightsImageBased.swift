import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSprocketsPBR
import simd
import SwiftGLTF

// EXT_lights_image_based: image-based lights defined in the file, one chosen per scene.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Vendor/EXT_lights_image_based
// SwiftGLTF has no typed version of this extension yet.

/// The document's image-based lights.
public struct EXTLightsImageBased: GLTFExtension {
    public static let extensionName = "EXT_lights_image_based"

    public struct Light: Decodable, Sendable {
        public var name: String?
        /// Quaternion (x, y, z, w) rotating the environment.
        public var rotation: SIMD4<Float>?
        public var intensity: Float?
        /// Spherical harmonics for irradiance, 9 x RGB.
        public var irradianceCoefficients: [[Float]]
        /// Image indices of the prefiltered specular cube map: per mip, the faces +X -X +Y -Y +Z -Z.
        public var specularImages: [[Int]]
        public var specularImageSize: Int
    }

    public let lights: [Light]
}

/// A scene's choice of image-based light.
public struct EXTLightsImageBasedScene: GLTFExtension {
    public static let extensionName = "EXT_lights_image_based"

    public let light: Int
}

/// An EXT_lights_image_based light decoded to linear equirectangular radiance, with its rotation and intensity
/// applied, ready to become a ``PBREnvironment``.
///
/// Only the sharpest mip of the file's specular cube map is used: it is the unblurred radiance, which the renderer
/// prefilters and convolves itself, so roughness maps to blur as for any other environment. The file's lower mips
/// and irradiance coefficients are not used.
public struct GLTFImageBasedLight: Sendable {
    public var name: String?
    public var width: Int
    public var height: Int
    /// Linear RGBA half floats, row 0 is +Y (``PBREnvironment/Source/equirectangularPixels(width:height:rgba:)``).
    public var rgba: [Float16]

    public func environment(device: MTLDevice? = nil) throws -> PBREnvironment {
        try PBREnvironment(source: .equirectangularPixels(width: width, height: height, rgba: rgba), device: device)
    }
}

extension GLTFImageBasedLight {
    /// The index of the light scene `sceneIndex` uses, if any.
    static func lightIndex(document: Document, sceneIndex: Int) -> Int? {
        guard document.scenes.indices.contains(sceneIndex) else { return nil }
        return (try? document.scenes[sceneIndex].extensionValue(EXTLightsImageBasedScene.self))?.light
    }

    /// Decodes light `index` of the document's EXT_lights_image_based lights.
    init(container: Container, index: Int) throws {
        let document = container.document
        let lights = try document.extensionValue(EXTLightsImageBased.self)
        guard let lights, lights.lights.indices.contains(index) else {
            throw GLTFError.invalidDocument("EXT_lights_image_based light \(index) is out of range")
        }
        let light = lights.lights[index]
        guard let faces = light.specularImages.first, faces.count == 6 else {
            throw GLTFError.invalidDocument("EXT_lights_image_based light \(index) has no six-face mip 0")
        }
        let cube = try faces.map { try Self.decodeFace(container: container, imageIndex: $0) }
        let rotation = light.rotation.map { simd_quatf(vector: $0) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let size = cube[0].size
        self.init(name: light.name, cube: cube, size: size, rotation: rotation, intensity: light.intensity ?? 1)
    }

    /// One cube face: linear RGB, `size` x `size`, rows top-down.
    struct Face {
        var size: Int
        var pixels: [SIMD3<Float>]

        /// Bilinear, clamped to the face.
        func sample(u: Float, v: Float) -> SIMD3<Float> {
            let x = min(max(u * Float(size) - 0.5, 0), Float(size - 1))
            let y = min(max(v * Float(size) - 0.5, 0), Float(size - 1))
            let x0 = Int(x), y0 = Int(y)
            let x1 = min(x0 + 1, size - 1), y1 = min(y0 + 1, size - 1)
            let fx = x - Float(x0), fy = y - Float(y0)
            let top = simd_mix(pixels[y0 * size + x0], pixels[y0 * size + x1], SIMD3(repeating: fx))
            let bottom = simd_mix(pixels[y1 * size + x0], pixels[y1 * size + x1], SIMD3(repeating: fx))
            return simd_mix(top, bottom, SIMD3(repeating: fy))
        }
    }

    /// Resamples `cube` into a 4:2 equirectangular image of the same detail, looking each direction up through
    /// `rotation` and scaling by `intensity`.
    init(name: String?, cube: [Face], size: Int, rotation: simd_quatf, intensity: Float) {
        let width = size * 4
        let height = size * 2
        var rgba = [Float16](repeating: 0, count: width * height * 4)
        let inverse = rotation.inverse
        for row in 0 ..< height {
            for column in 0 ..< width {
                // As the shaders' equirectDirection.
                let phi = ((Float(column) + 0.5) / Float(width) - 0.5) * 2 * .pi
                let theta = (0.5 - (Float(row) + 0.5) / Float(height)) * .pi
                let direction = inverse.act(SIMD3(cos(theta) * cos(phi), sin(theta), cos(theta) * sin(phi)))
                let (face, u, v) = Self.cubeFace(direction)
                // The spec stores each face flipped vertically, to match glTF texture space.
                let color = cube[face].sample(u: u, v: 1 - v) * intensity
                let base = (row * width + column) * 4
                rgba[base] = Float16(color.x)
                rgba[base + 1] = Float16(color.y)
                rgba[base + 2] = Float16(color.z)
                rgba[base + 3] = 1
            }
        }
        self.init(name: name, width: width, height: height, rgba: rgba)
    }

    /// The face (+X -X +Y -Y +Z -Z) and texel position (0...1, v down) a direction looks up: the inverse of the
    /// shaders' cubeDirection.
    static func cubeFace(_ direction: SIMD3<Float>) -> (face: Int, u: Float, v: Float) {
        let absolute = simd_abs(direction)
        let face: Int
        let s: Float, t: Float, major: Float
        if absolute.x >= absolute.y, absolute.x >= absolute.z {
            face = direction.x > 0 ? 0 : 1
            (s, t, major) = (direction.x > 0 ? -direction.z : direction.z, -direction.y, absolute.x)
        } else if absolute.y >= absolute.z {
            face = direction.y > 0 ? 2 : 3
            (s, t, major) = (direction.x, direction.y > 0 ? direction.z : -direction.z, absolute.y)
        } else {
            face = direction.z > 0 ? 4 : 5
            (s, t, major) = (direction.z > 0 ? direction.x : -direction.x, -direction.y, absolute.z)
        }
        return (face, (s / major + 1) / 2, (t / major + 1) / 2)
    }

    /// A face image as linear RGB. Four-channel PNGs hold RGBD (as Babylon.js writes it: rgb in gamma 2.2 divided by
    /// alpha); others are LDR sRGB.
    static func decodeFace(container: Container, imageIndex: Int) throws -> Face {
        let document = container.document
        guard document.images.indices.contains(imageIndex) else {
            throw GLTFError.invalidDocument("EXT_lights_image_based image \(imageIndex) is out of range")
        }
        let image = document.images[imageIndex]
        let data: Data
        if let bufferView = image.bufferView {
            data = try container.data(for: bufferView.resolve(in: document))
        } else if let uri = image.uri {
            data = try container.data(for: uri)
        } else {
            throw GLTFError.invalidDocument("Image \(imageIndex) has neither a bufferView nor a uri")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil), cgImage.width == cgImage.height else {
            throw GLTFError.invalidDocument("EXT_lights_image_based image \(imageIndex) is not a square image")
        }
        let size = cgImage.width
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(cgImage.alphaInfo)
        // Draw unpremultiplied 8-bit RGBA so the alpha divisor survives intact: draw without alpha for RGB, and for
        // RGBD read the decoded bytes directly.
        var pixels = [SIMD3<Float>](repeating: .zero, count: size * size)
        if hasAlpha, cgImage.bitsPerComponent == 8, cgImage.bitsPerPixel == 32, [.last, .first].contains(cgImage.alphaInfo),
           let bytes = cgImage.dataProvider?.data, let pointer = CFDataGetBytePtr(bytes) {
            let alphaFirst = cgImage.alphaInfo == .first
            for row in 0 ..< size {
                for column in 0 ..< size {
                    let base = row * cgImage.bytesPerRow + column * 4
                    let channels = alphaFirst ? (pointer[base + 1], pointer[base + 2], pointer[base + 3], pointer[base]) : (pointer[base], pointer[base + 1], pointer[base + 2], pointer[base + 3])
                    let rgb = SIMD3<Float>(Float(channels.0), Float(channels.1), Float(channels.2)) / 255
                    let divisor = max(Float(channels.3) / 255, 1 / 255)
                    pixels[row * size + column] = SIMD3(pow(rgb.x, 2.2), pow(rgb.y, 2.2), pow(rgb.z, 2.2)) / divisor
                }
            }
            return Face(size: size, pixels: pixels)
        }
        if hasAlpha {
            throw GLTFError.invalidDocument("EXT_lights_image_based image \(imageIndex): unsupported RGBD pixel layout")
        }
        guard let space = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 32, bytesPerRow: size * 16, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let raw = context.data
        else {
            throw GLTFError.invalidDocument("EXT_lights_image_based image \(imageIndex) cannot be decoded")
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        let floats = raw.assumingMemoryBound(to: Float.self)
        for index in pixels.indices {
            pixels[index] = SIMD3(floats[index * 4], floats[index * 4 + 1], floats[index * 4 + 2])
        }
        return Face(size: size, pixels: pixels)
    }
}
