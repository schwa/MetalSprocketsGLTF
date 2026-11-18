import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import MetalSprocketsGLTFMeshopt
import MetalSprocketsPBR
import MetalSprocketsUI
import simd
import SwiftUI

/// Viewing choices that persist while browsing different models.
public struct ViewerSettings: Equatable {
    var showsBackground = false
    var showsInspector = false
    var debugView: PBRDebugView = .lit
    var showsWireframe = false
    /// MTKView.framebufferOnly. Turning it off works around a Metal 4 / MetalSprockets problem where views render pink.
    var framebufferOnly = true
    var toneMapping: LightingToneMapping = .pbrNeutral
    /// In stops: the scene is scaled by 2^exposure before tone mapping.
    var exposure: Float = 0
    /// `.model` lights models that define an image-based light (EXT_lights_image_based) with it, others with the studio.
    var environment: ViewerEnvironment = .model
    var environmentIntensity: Float = 1
    /// Degrees about +Y.
    var environmentRotation: Float = 0
    /// MSAA samples per pixel (1 is off).
    var sampleCount = 4
    /// Fraction of the view's width and height drawn before MetalFX upscales to full size; 1 draws at full size.
    var renderScale: Float = 1
    /// Extended dynamic range on macOS: a float drawable in extended linear sRGB, so values above 1 (tone mapping
    /// None) use the display's headroom.
    var extendedDynamicRange = false
    /// The on-screen drawable's color format.
    var colorPixelFormat: MTLPixelFormat {
        extendedDynamicRange ? .rgba16Float : .bgra8Unorm_srgb
    }
    var upscaling: PBRUpscaling? {
        renderScale < 1 ? PBRUpscaling(scale: renderScale, colorPixelFormat: colorPixelFormat) : nil
    }
    var inspectorTab: InspectorTab = .camera

    public init() {}
}
