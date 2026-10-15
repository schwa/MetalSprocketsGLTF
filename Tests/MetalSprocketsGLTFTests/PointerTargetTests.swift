import CoreGraphics
import Foundation
import GeometryLite3D
import MetalSprockets
@testable import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import SwiftGLTF
import Testing

/// A red unlit triangle (node 0, hidden at rest by KHR_node_visibility), a point light (node 1) and a camera (node 2),
/// animated over one second through KHR_animation_pointer: the triangle's visibility (hidden → shown, step), the
/// light's intensity (1 → 3) and color (red → blue), and the camera's yfov (0.5 → 1). With `animated` false, only the
/// rest state.
private func makePointerTargetFile(animated: Bool = true, lightHidden: Bool = false) throws -> URL {
    var data = Data()
    func append(_ values: [Float]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([-1, -1, 0, 1, -1, 0, 0, 1, 0]) // positions, 36 bytes at 0
    append([0, 1]) // times, 8 bytes at 36
    append([0, 1]) // visibility, 8 bytes at 44
    append([1, 3]) // intensities, 8 bytes at 52
    append([1, 0, 0, 0, 0, 1]) // colors, 24 bytes at 60
    append([0.5, 1]) // yfov, 8 bytes at 84
    func channel(_ sampler: Int, _ pointer: String) -> String {
        #"{"sampler": \#(sampler), "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "\#(pointer)"}}}}"#
    }
    let animations = !animated ? "[]" : """
    [{
      "channels": [
        \(channel(0, "/nodes/0/extensions/KHR_node_visibility/visible")),
        \(channel(1, "/extensions/KHR_lights_punctual/lights/0/intensity")),
        \(channel(2, "/extensions/KHR_lights_punctual/lights/0/color")),
        \(channel(3, "/cameras/0/perspective/yfov"))
      ],
      "samplers": [{"input": 1, "output": 2, "interpolation": "STEP"}, {"input": 1, "output": 3}, {"input": 1, "output": 4}, {"input": 1, "output": 5}]
    }]
    """
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_animation_pointer", "KHR_node_visibility", "KHR_lights_punctual", "KHR_materials_unlit"],
      "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "intensity": 1, "color": [1, 0, 0]}]}},
      "scene": 0, "scenes": [{"nodes": [0, 1, 2]}],
      "nodes": [
        {"mesh": 0, "extensions": {"KHR_node_visibility": {"visible": false}}},
        {"translation": [0, 2, 0], "extensions": {"KHR_lights_punctual": {"light": 0}\(lightHidden ? #", "KHR_node_visibility": {"visible": false}"# : "")}},
        {"camera": 0, "translation": [0, 0, 4]}
      ],
      "cameras": [{"type": "perspective", "perspective": {"yfov": 0.5, "znear": 0.1}}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "materials": [{"doubleSided": true, "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}, "extensions": {"KHR_materials_unlit": {}}}],
      "animations": \(animations),
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR"},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR"},
        {"bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3"},
        {"bufferView": 5, "componentType": 5126, "count": 2, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 8},
        {"buffer": 0, "byteOffset": 52, "byteLength": 8},
        {"buffer": 0, "byteOffset": 60, "byteLength": 24},
        {"buffer": 0, "byteOffset": 84, "byteLength": 8}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Suite(.requiresMetal4)
struct PointerTargetTests {
    // Visibility, light and camera pointers are parsed, not reported as unsupported.
    @Test func parsesTheNewTargets() {
        #expect(GLTFAnimationPointer.target("/nodes/3/extensions/KHR_node_visibility/visible") == .visibility(3))
        #expect(GLTFAnimationPointer.target("/extensions/KHR_lights_punctual/lights/2/spot/outerConeAngle") == .light(2, "spot/outerConeAngle"))
        #expect(GLTFAnimationPointer.target("/cameras/1/orthographic/xmag") == .camera(1, "orthographic/xmag"))
        #expect(GLTFAnimationPointer.target("/extensions/KHR_lights_punctual/lights/0/name") == nil)
        #expect(GLTFAnimationPointer.target("/cameras/0/type") == nil)
    }

    // Every light property a pointer can target is applied: parsing and applying share one table.
    @Test func appliesEveryLightProperty() {
        var light = PBRLight()
        GLTFAnimationPointer.apply([
            "color": [0, 1, 0], "intensity": [5], "range": [7],
            "spot/innerConeAngle": [0.1], "spot/outerConeAngle": [0.2]
        ], to: &light)
        #expect(light.color == [0, 1, 0])
        #expect(light.intensity == 5)
        #expect(light.range == 7)
        #expect(abs(light.innerConeCos - cos(0.1)) < 1e-6)
        #expect(abs(light.outerConeCos - cos(0.2)) < 1e-6)
        for property in GLTFAnimationPointer.lightSetters.keys {
            #expect(GLTFAnimationPointer.target("/extensions/KHR_lights_punctual/lights/0/\(property)") == .light(0, property))
        }
    }

    // Every camera property a pointer can target is applied.
    @Test func appliesEveryCameraProperty() throws {
        let perspective = try JSONDecoder().decode(SwiftGLTF.Camera.self, from: Data(#"{"type": "perspective", "perspective": {"yfov": 0.5, "znear": 0.1}}"#.utf8))
        let changed = GLTFAnimationPointer.apply(["perspective/yfov": 1, "perspective/znear": 0.2, "perspective/zfar": 50, "perspective/aspectRatio": 2], to: perspective)
        #expect(changed.perspective?.yfov == 1)
        #expect(changed.perspective?.znear == 0.2)
        #expect(changed.perspective?.zfar == 50)
        #expect(changed.perspective?.aspectRatio == 2)
        let orthographic = try JSONDecoder().decode(SwiftGLTF.Camera.self, from: Data(#"{"type": "orthographic", "orthographic": {"xmag": 1, "ymag": 1, "znear": 0.1, "zfar": 10}}"#.utf8))
        let changedOrthographic = GLTFAnimationPointer.apply(["orthographic/xmag": 2, "orthographic/ymag": 3, "orthographic/znear": 0.5, "orthographic/zfar": 20], to: orthographic)
        #expect(changedOrthographic.orthographic?.xmag == 2)
        #expect(changedOrthographic.orthographic?.ymag == 3)
        #expect(changedOrthographic.orthographic?.znear == 0.5)
        #expect(changedOrthographic.orthographic?.zfar == 20)
    }

    // Material factors and texture transform components parse into the property that applies them.
    @Test func parsesMaterialProperties() {
        for property in GLTFMaterialFeature.animatableFactors.keys {
            #expect(GLTFAnimationPointer.target("/materials/0/\(property)") == .material(0, property))
        }
        guard case let .textureTransform(path, component)? = GLTFAnimationPointer.MaterialProperty("normalTexture/extensions/KHR_texture_transform/rotation") else {
            Issue.record("texture transform not parsed")
            return
        }
        #expect(path == "normalTexture")
        #expect(component == .rotation)
        #expect(GLTFAnimationPointer.MaterialProperty("bogusTexture/extensions/KHR_texture_transform/rotation") == nil)
        #expect(GLTFAnimationPointer.MaterialProperty("name") == nil)
    }

    // A node hidden at rest is loaded when an animation can show it; the rest pose hides it, the animation shows it.
    @Test func animatesVisibility() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile())
        #expect(asset.warnings.isEmpty, "\(asset.warnings)")
        #expect(asset.opaqueInstances.map(\.nodeIndex) == [0])
        #expect(!asset.restPose.isVisible(0))
        #expect(!asset.pose(animation: 0, time: 0).isVisible(0))
        #expect(asset.pose(animation: 0, time: 1).isVisible(0))
    }

    // Without visibility animation, a hidden node contributes nothing.
    @Test func hiddenNodesWithoutAnimationAreNotLoaded() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile(animated: false))
        #expect(asset.opaqueInstances.isEmpty)
    }

    // Light intensity and color follow their pointers.
    @Test func animatesLightProperties() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile())
        let halfway = try #require(asset.lights(pose: asset.pose(animation: 0, time: 0.5)).first)
        #expect(abs(halfway.intensity - 2) < 1e-5)
        let end = try #require(asset.lights(pose: asset.pose(animation: 0, time: 1)).first)
        #expect(abs(end.intensity - 3) < 1e-5)
        #expect(simd_distance(end.color, [0, 0, 1]) < 1e-5)
    }

    // Camera projection properties follow their pointers.
    @Test func animatesCameraProperties() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile())
        let camera = try #require(asset.cameras(pose: asset.pose(animation: 0, time: 1)).first)
        #expect(abs((camera.camera.perspective?.yfov ?? 0) - 1) < 1e-5)
        #expect(abs((asset.cameras.first?.camera.perspective?.yfov ?? 0) - 0.5) < 1e-5)
    }

    // A light on a hidden node does not shine at rest.
    @Test func hiddenLightsDoNotShine() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile(animated: false, lightHidden: true))
        #expect(asset.lights.isEmpty)
    }

    // The renderer hides the rest pose's hidden instance even when no pose is given, and draws it once shown.
    @Test func rendersAnimatedVisibility() throws {
        let asset = try GLTFAsset(url: makePointerTargetFile())
        let view = LookAt(position: [0, 0, 4], target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)
        func centerRed(pose: PBRPose?) throws -> Int {
            let image = try OffscreenRenderer(size: CGSize(width: 32, height: 32), clearDepth: 0).render(
                try RenderPass { GLTFRenderer(asset: asset, viewMatrix: view, projectionMatrix: projection, pose: pose) }
            ).cgImage
            let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return Int(try #require(context.data).assumingMemoryBound(to: UInt8.self)[(16 * 32 + 16) * 4])
        }
        #expect(try centerRed(pose: nil) < 50)
        #expect(try centerRed(pose: asset.pose(animation: 0, time: 1)) > 200)
    }
}
