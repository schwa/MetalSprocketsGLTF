import CoreGraphics
import MetalSprocketsPBR
import simd

// Old GLTF-prefixed names for the renderer types in MetalSprocketsPBR (#118).

public typealias GLTFBounds = PBRBounds
public typealias GLTFPose = PBRPose
public typealias GLTFMaterialResource = PBRMaterial
public typealias GLTFGeometryBuffers = PBRGeometryBuffers
public typealias GLTFLighting = PBRLighting
public typealias GLTFEnvironment = PBREnvironment
public typealias GLTFEnvironmentError = PBREnvironmentError
public typealias GLTFEnvironmentBackground = PBREnvironmentBackground
public typealias GLTFToneMapping = PBRToneMapping
public typealias GLTFDebugView = PBRDebugView
public typealias GLTFFrustum = PBRFrustum
public typealias GLTFCamera = PBRCamera
public typealias GLTFRenderer = PBRRenderer
public typealias GLTFScene = PBRScene
public typealias GLTFTransmissionPass = PBRTransmissionPass
public typealias GLTFTransmissionTarget = PBRTransmissionTarget

// Old names for the shader types: MetalSprocketsGLTFShaders is MetalSprocketsPBRShaders (#138), and kGLTF* constants are kPBR*.

public typealias GLTFVertex = PBRVertex
public typealias GLTFSkinVertex = PBRSkinVertex
public typealias GLTFMorphDelta = PBRMorphDelta
public typealias GLTFMaterialUniforms = PBRMaterialUniforms
public typealias GLTFTextureSlot = PBRTextureSlot
public typealias GLTFMaterialTextureIndex = PBRMaterialTextureIndex
public typealias GLTFAlphaMode = PBRAlphaMode
public typealias GLTFLight = PBRLight
public typealias GLTFLightType = PBRLightType
public typealias GLTFInstance = PBRInstance

// Drawing a GLTFAsset: its model, lit by default with its lights placed by the pose (lights on animated nodes move).

public extension PBRScene {
    init(asset: GLTFAsset, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, modelMatrix: simd_float4x4 = matrix_identity_float4x4, lighting: PBRLighting? = nil, pose: PBRPose? = nil, showsBackground: Bool = false, viewportSize: CGSize) {
        self.init(model: asset.model, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, lighting: lighting ?? PBRLighting(asset: asset, pose: pose), pose: pose, showsBackground: showsBackground, viewportSize: viewportSize)
    }
}

public extension PBRRenderer {
    init(asset: GLTFAsset, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, modelMatrix: simd_float4x4 = matrix_identity_float4x4, lighting: PBRLighting? = nil, pose: PBRPose? = nil, transmissionTarget: PBRTransmissionTarget? = nil) {
        self.init(model: asset.model, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, lighting: lighting ?? PBRLighting(asset: asset, pose: pose), pose: pose, transmissionTarget: transmissionTarget)
    }
}

public extension PBRTransmissionPass {
    init(asset: GLTFAsset, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, modelMatrix: simd_float4x4 = matrix_identity_float4x4, lighting: PBRLighting? = nil, pose: PBRPose? = nil, target: PBRTransmissionTarget, showsBackground: Bool = false) {
        self.init(model: asset.model, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, lighting: lighting ?? PBRLighting(asset: asset, pose: pose), pose: pose, target: target, showsBackground: showsBackground)
    }
}

public extension PBRLighting {
    /// The asset's lights, placed by `pose` when given, and its scene's image-based light (EXT_lights_image_based)
    /// as the environment, else the studio.
    init(asset: GLTFAsset, pose: PBRPose? = nil) {
        self.init(lights: pose.map { asset.lights(pose: $0) } ?? asset.lights, environment: (try? asset.environment()) ?? .studio)
    }
}
