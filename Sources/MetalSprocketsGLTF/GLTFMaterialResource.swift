import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftGLTF

/// A glTF material resolved into shader uniforms, textures and samplers. Texture transforms are keyed by the
/// texture's path below `/materials/N/`, for KHR_animation_pointer.
extension PBRMaterial {
    convenience init(material: Material?, textures: GLTFTextureCache) throws {
        var uniforms = GLTFMaterialFeature.uniforms(for: material)

        func bind(_ info: TextureInfo?, sRGB: Bool, slot: inout PBRTextureSlot) -> Binding {
            slot.transform = matrix_identity_float3x3
            guard let info, let binding = textures.binding(for: info.index, sRGB: sRGB) else {
                slot.enabled = 0
                return textures.defaultBinding
            }
            slot.enabled = 1
            slot.texCoord = Int32(info.texCoord)
            if let transform = info.textureTransform {
                slot.transform = transform.matrix
                if let texCoord = transform.texCoord {
                    slot.texCoord = Int32(texCoord)
                }
            }
            return binding
        }

        // Bind every texture in GLTFMaterialTextureSlot.all.
        var bindings: [Binding] = []
        var textureTransforms: [String: TextureTransform] = [:]
        for slot in GLTFMaterialTextureSlot.all {
            let source = material.flatMap(slot.source)
            bindings.append(bind(source?.info, sRGB: slot.sRGB, slot: &uniforms[keyPath: slot.uniform]))
            if let source {
                let transform = source.info.textureTransform
                textureTransforms[source.path] = TextureTransform(slot: slot.uniform, offset: transform?.offset ?? .zero, rotation: transform?.rotation ?? 0, scale: transform?.scale ?? [1, 1])
            }
        }

        try self.init(name: material?.name, uniforms: uniforms, doubleSided: material?.doubleSided ?? false, textureBindings: bindings, device: textures.device)
        self.textureTransforms = textureTransforms
    }
}

extension KHRTextureTransform {
    /// uv' = T * R * S * uv, per KHR_texture_transform.
    var matrix: simd_float3x3 {
        let translation = simd_float3x3(columns: ([1, 0, 0], [0, 1, 0], [offset.x, offset.y, 1]))
        let rotation = simd_float3x3(columns: ([cos(self.rotation), -sin(self.rotation), 0], [sin(self.rotation), cos(self.rotation), 0], [0, 0, 1]))
        let scale = simd_float3x3(diagonal: [self.scale.x, self.scale.y, 1])
        return translation * rotation * scale
    }
}

/// Loads each (image, color space) and sampler once. `preload(_:)` decodes images in parallel; `binding(for:sRGB:)`
/// reads its results and loads anything it did not cover.
final class GLTFTextureCache {
    /// An image decoded for one color space.
    struct ImageKey: Hashable {
        var imageIndex: Int
        var sRGB: Bool
    }

    let container: Container
    let device: MTLDevice
    let loader: MTKTextureLoader
    /// Registered decoders (GLTFLoadOptions), asked before the built-in image path.
    let decoders: [any GLTFTextureDecoder]
    /// Every image loaded so far, or the error that stopped it.
    private var images: [ImageKey: Result<MTLTexture, Error>] = [:]
    private var samplers: [Int: MTLSamplerDescriptor] = [:]
    /// Textures a material asked for that have no loadable source, with the reason, by texture index.
    private var skippedTextures: [Int: String] = [:]
    /// Images a material asked for that failed to load, with the first error, by image index.
    private var failedImages: [Int: Error] = [:]

    /// What was skipped or failed, once per texture and image, whichever materials asked for it.
    var warnings: [String] {
        skippedTextures.sorted { $0.key < $1.key }.map { "Texture \($0.key) skipped: \($0.value)" }
            + failedImages.sorted { $0.key < $1.key }.map { "Image \($0.key) failed to load: \($0.value)" }
    }
    lazy var defaultBinding: PBRMaterial.Binding = makeBinding(texture: makeWhiteTexture(), samplerDescriptor: makeSamplerDescriptor(nil))

    init(container: Container, device: MTLDevice, decoders: [any GLTFTextureDecoder] = []) {
        self.container = container
        self.device = device
        self.loader = MTKTextureLoader(device: device)
        self.decoders = decoders
    }

    /// The image to load for `texture`, and the decoder that claimed it (nil for the built-in path).
    func source(of texture: Texture) -> (imageIndex: Int, decoder: (any GLTFTextureDecoder)?)? {
        for decoder in decoders {
            if let imageIndex = decoder.imageIndex(for: texture) {
                return (imageIndex, decoder)
            }
        }
        return Self.imageIndex(of: texture).map { ($0, nil) }
    }

    func binding(for index: Index<Texture>, sRGB: Bool) -> PBRMaterial.Binding? {
        let document = container.document
        guard index.index < document.textures.count else { return nil }
        let texture = document.textures[index.index]
        guard let (imageIndex, decoder) = source(of: texture) else {
            let reason = texture.extensions?["KHR_texture_basisu"] != nil ? "KTX2 (KHR_texture_basisu) is not supported" : "it has no source"
            skippedTextures[index.index] = reason
            return nil
        }
        let metalTexture: MTLTexture
        switch image(ImageKey(imageIndex: imageIndex, sRGB: sRGB), decoder: decoder) {
        case .success(let loaded):
            metalTexture = loaded

        case .failure(let error):
            if failedImages[imageIndex] == nil {
                failedImages[imageIndex] = error
            }
            return nil
        }
        let samplerIndex = texture.sampler?.index ?? -1
        let samplerDescriptor = samplers[samplerIndex] ?? {
            let samplerDescriptor = makeSamplerDescriptor(texture.sampler.flatMap { try? $0.resolve(in: document) })
            samplers[samplerIndex] = samplerDescriptor
            return samplerDescriptor
        }()
        return makeBinding(texture: metalTexture, samplerDescriptor: samplerDescriptor)
    }

    /// The image for `key`, loaded on first use.
    private func image(_ key: ImageKey, decoder: (any GLTFTextureDecoder)?) -> Result<MTLTexture, Error> {
        if let cached = images[key] {
            return cached
        }
        let result = Result { try Self.decode(imageData(key.imageIndex), key: key, label: label(key.imageIndex), decoder: decoder, loader: loader) }
        images[key] = result
        return result
    }

    /// Decodes and uploads every image the materials reference, in parallel, so `binding(for:sRGB:)` hits the cache.
    func preload(_ materials: [Material]) {
        let document = container.document
        var requests: [(key: ImageKey, decoder: (any GLTFTextureDecoder)?)] = []
        var seen = Set<ImageKey>()
        for material in materials {
            for slot in GLTFMaterialTextureSlot.all {
                guard let info = slot.source(material)?.info, info.index.index < document.textures.count, let (imageIndex, decoder) = source(of: document.textures[info.index.index]) else { continue }
                let key = ImageKey(imageIndex: imageIndex, sRGB: slot.sRGB)
                if images[key] == nil, seen.insert(key).inserted {
                    requests.append((key, decoder))
                }
            }
        }

        // Container's URI cache is not thread-safe, so read the bytes serially; decoding and upload run in parallel.
        let jobs: [(key: ImageKey, label: String, decoder: (any GLTFTextureDecoder)?, data: Result<Data, Error>)] = requests.map { request in
            (request.key, label(request.key.imageIndex), request.decoder, Result { try imageData(request.key.imageIndex) })
        }
        // Each iteration writes only its own slot.
        nonisolated(unsafe) let results = UnsafeMutableBufferPointer<Result<MTLTexture, Error>?>.allocate(capacity: jobs.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        let device = device
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = jobs[index]
            results[index] = Result { try Self.decode(job.data.get(), key: job.key, label: job.label, decoder: job.decoder, loader: MTKTextureLoader(device: device)) }
        }
        for (index, job) in jobs.enumerated() {
            images[job.key] = results[index]
        }
    }

    /// Decodes with `decoder`, or the built-in PNG / JPEG / WebP path when nil.
    static func decode(_ data: Data, key: ImageKey, label: String, decoder: (any GLTFTextureDecoder)?, loader: MTKTextureLoader) throws -> MTLTexture {
        let texture = try decoder?.makeTexture(data: data, sRGB: key.sRGB, device: loader.device) ?? makeTexture(data: data, sRGB: key.sRGB, loader: loader)
        texture.label = label
        return texture
    }

    func label(_ imageIndex: Int) -> String {
        let images = container.document.images
        return (images.indices.contains(imageIndex) ? images[imageIndex].name : nil) ?? "image\(imageIndex)"
    }

    /// The texture's image: its `source`, or an `EXT_texture_webp` source (ImageIO decodes WebP).
    static func imageIndex(of texture: Texture) -> Int? {
        if let source = texture.source {
            return source.index
        }
        return texture.webPSource?.index
    }

    func imageData(_ imageIndex: Int) throws -> Data {
        let document = container.document
        guard document.images.indices.contains(imageIndex) else {
            throw GLTFError.invalidDocument("Image index \(imageIndex) is out of range")
        }
        let image = document.images[imageIndex]
        if let bufferView = image.bufferView {
            return try container.data(for: bufferView.resolve(in: document))
        }
        if let uri = image.uri {
            return try container.data(for: uri)
        }
        throw GLTFError.invalidDocument("Image \(imageIndex) has neither a bufferView nor a uri")
    }

    static func makeTexture(data: Data, sRGB: Bool, loader: MTKTextureLoader) throws -> MTLTexture {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GLTFError.unsupported("Undecodable image")
        }
        // A 1×1 texture has a single mip level; asking MTKTextureLoader to generate mipmaps for it fails validation.
        let hasMipmaps = max(cgImage.width, cgImage.height) > 1
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: sRGB,
            .generateMipmaps: hasMipmaps,
            .allocateMipmaps: hasMipmaps,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
        // MTKTextureLoader picks the format from the image: palette PNGs lose the sRGB format and grey + alpha PNGs
        // become two-channel textures. Only keep its result when it is four-channel with the requested color space.
        let expected: Set<MTLPixelFormat> = sRGB ? [.rgba8Unorm_srgb, .bgra8Unorm_srgb] : [.rgba8Unorm, .bgra8Unorm]
        if let texture = try? loader.newTexture(cgImage: cgImage, options: options), expected.contains(texture.pixelFormat) {
            return texture
        }
        return try uploadRGBA8(cgImage, sRGB: sRGB, mipmapped: hasMipmaps, device: loader.device)
    }

    /// Redraws `image` as straight-alpha RGBA8 and uploads it with an explicit pixel format.
    static func uploadRGBA8(_ image: CGImage, sRGB: Bool, mipmapped: Bool, device: MTLDevice) throws -> MTLTexture {
        let width = image.width
        let height = image.height
        // Indexed and grey images draw into RGB; keep RGB images in their own space so data textures are not converted.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GLTFError.unsupported("Cannot convert image to RGBA8")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext only draws premultiplied RGBA8; glTF textures use straight alpha.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha > 0, alpha < 255 {
                for channel in 0 ..< 3 {
                    pixels[index + channel] = UInt8(min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha))
                }
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sRGB ? .rgba8Unorm_srgb : .rgba8Unorm, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GLTFError.unsupported("Cannot create texture")
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        if mipmapped {
            guard let queue = device.makeCommandQueue(), let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw GLTFError.unsupported("Cannot generate mipmaps")
            }
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return texture
    }

    func makeBinding(texture: MTLTexture, samplerDescriptor: MTLSamplerDescriptor) -> PBRMaterial.Binding {
        // swiftlint:disable:next force_try
        try! PBRMaterial.Binding(texture: texture, samplerDescriptor: samplerDescriptor, device: device)
    }

    func makeSamplerDescriptor(_ sampler: Sampler?) -> MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.magFilter = sampler?.magFilter == .NEAREST ? .nearest : .linear
        switch sampler?.minFilter {
        case .NEAREST:
            descriptor.minFilter = .nearest

        case .NEAREST_MIPMAP_NEAREST:
            descriptor.minFilter = .nearest
            descriptor.mipFilter = .nearest

        case .LINEAR_MIPMAP_NEAREST:
            descriptor.minFilter = .linear
            descriptor.mipFilter = .nearest

        case .NEAREST_MIPMAP_LINEAR:
            descriptor.minFilter = .nearest
            descriptor.mipFilter = .linear

        case .LINEAR:
            descriptor.minFilter = .linear

        default:
            descriptor.minFilter = .linear
            descriptor.mipFilter = .linear
        }
        if descriptor.mipFilter == .linear, descriptor.minFilter == .linear, descriptor.magFilter == .linear {
            descriptor.maxAnisotropy = 8
        }
        func address(_ wrap: Sampler.Wrap?) -> MTLSamplerAddressMode {
            switch wrap {
            case .CLAMP_TO_EDGE: .clampToEdge
            case .MIRRORED_REPEAT: .mirrorRepeat
            default: .repeat
            }
        }
        descriptor.sAddressMode = address(sampler?.wrapS)
        descriptor.tAddressMode = address(sampler?.wrapT)
        return descriptor
    }

    func makeWhiteTexture() -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        let white: [UInt8] = [255, 255, 255, 255]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: white, bytesPerRow: 4)
        texture.label = "GLTF White"
        return texture
    }
}
