# MetalSprocketsGLTF

MetalSprocketsGLTF loads glTF 2.0 files for [MetalSprockets](https://github.com/schwa/MetalSprockets). The peer package [MetalSprocketsPBR](https://github.com/schwa/MetalSprocketsPBR) renders them. Import both modules: `MetalSprocketsGLTF` loads a `GLTFAsset`, and `MetalSprocketsPBR` renders the `PBRModel` of that asset.

The package requires macOS 26, iOS 26, or visionOS 26.

## Installation

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/schwa/MetalSprocketsGLTF", branch: "main"),
```

Then add the product to your target:

```swift
.product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
```

## Usage

Load a file. Then render the model of the asset with `PBRScene`. `PBRScene` is a MetalSprockets `Element`. You can use it in a `RenderView` or in an `OffscreenRenderer`.

```swift
import MetalSprocketsGLTF
import MetalSprocketsPBR

let asset = try GLTFAsset(url: url)

PBRScene(
    model: asset.model,
    viewMatrix: viewMatrix,
    projectionMatrix: projectionMatrix,
    lighting: PBRLighting(environment: .studio, toneMapping: .pbrNeutral),
    pose: asset.pose(animation: 0, time: time),
    viewportSize: viewportSize
)
```

- Load the asset one time. `GLTFAsset` is immutable and `Sendable`, so you can load it on a background task.
- To draw the rest pose, do not give a `pose:` argument.
- For the depth, camera, and lighting conventions, read the [MetalSprocketsPBR README](https://github.com/schwa/MetalSprocketsPBR).

## Products

- `MetalSprocketsGLTF`: the loader.
- `MetalSprocketsGLTFMeshopt`: meshopt decoding (`KHR_meshopt_compression`, `EXT_meshopt_compression`). To use it, add `GLTFMeshoptDecoder()` to `GLTFLoadOptions(bufferViewDecoders:)`.
- `MetalSprocketsGLTFBasisU`: KTX2 and Basis Universal textures (`KHR_texture_basisu`). To use it, add `GLTFBasisUTextureDecoder` to `GLTFLoadOptions(textureDecoders:)`.
The package also contains `ms-gltf-render`, a command-line tool for development. It renders glTF files and measures their performance. It is not a product.

`Demos/GLTFViewer` is a viewer app for macOS, iOS, and visionOS.

## glTF extension support

The tables below compare the package with the [glTF 2.0 extension registry](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0). Numbers such as #8 are issues in [`ISSUES.md`](ISSUES.md).

The glTF specification has a rule for the `extensionsRequired` list. If this list contains an unsupported extension, the file does not load. The loader then throws `GLTFUnsupportedExtensionsError`.

- To load the file with a warning, use `GLTFLoadOptions(loadsUnsupportedRequiredExtensions: true)`.
- A decoder that you add to `GLTFLoadOptions` adds its extensions to the supported set.

### Khronos

| Extension | Status |
|---|---|
| KHR_lights_punctual | Supported. Lights on animated nodes move with the pose. |
| KHR_materials_anisotropy | Supported |
| KHR_materials_clearcoat | Supported |
| KHR_materials_dispersion | Supported |
| KHR_materials_emissive_strength | Supported |
| KHR_materials_ior | Supported |
| KHR_materials_iridescence | Supported |
| KHR_materials_sheen | Supported |
| KHR_materials_specular | Supported |
| KHR_materials_transmission | Supported. The scene behind the material shows through it (`PBRTransmissionPass`). |
| KHR_materials_unlit | Supported |
| KHR_materials_volume | Supported |
| KHR_mesh_quantization | Supported |
| KHR_node_visibility | Supported. Animation of visibility is not supported. |
| KHR_texture_transform | Supported |
| KHR_animation_pointer | Partly supported: node transforms, morph weights, and material properties. Lights, cameras, and visibility: #89 |
| KHR_materials_variants | Supported. Load a variant with `GLTFAsset(url:variant:)`. To change the variant without a reload, use `asset.variant(_:)`. GLTFViewer has a variant picker in the Model tab. |
| KHR_draco_mesh_compression | Not supported: #8 |
| KHR_meshopt_compression | Supported by the optional `MetalSprocketsGLTFMeshopt` product. Add `GLTFMeshoptDecoder` to `GLTFLoadOptions.bufferViewDecoders`. |
| KHR_texture_basisu | Supported by the optional `MetalSprocketsGLTFBasisU` product. Add `GLTFBasisUTextureDecoder` to `GLTFLoadOptions`. |
| KHR_materials_diffuse_transmission | Supported |
| KHR_materials_retroreflection | Supported |
| KHR_materials_volume_scatter | Approximated. The multiscatter color tints the diffuse light that scatters back out. There is no scattering pass. The multiscatter texture and anisotropy have no effect. |
| KHR_gaussian_splatting | Not supported: #85 |
| KHR_interactivity, KHR_node_hoverability, KHR_node_selectability | Not supported. These extensions are for interaction, which is not a task of a renderer. |
| KHR_xmp_json_ld | Ignored (metadata) |

### Archived

| Extension | Status |
|---|---|
| KHR_materials_pbrSpecularGlossiness | Supported |
| KHR_techniques_webgl, KHR_xmp | Not supported (obsolete) |

### Vendor

| Extension | Status |
|---|---|
| EXT_texture_webp | Supported |
| EXT_meshopt_compression | Supported by the optional `MetalSprocketsGLTFMeshopt` product, the same as KHR_meshopt_compression |
| EXT_mesh_gpu_instancing | Supported (TRANSLATION, ROTATION, SCALE). The renderer draws skinned meshes one time only. |
| EXT_lights_image_based | Not supported: #86 |
| EXT_lights_ies | Not supported: #87 |
| EXT_texture_astc | Not supported: #88 |
| Others (ADOBE_, AGI_, CESIUM_, FB_, GODOT_, GRIFFEL_, MPEG_, MSFT_, NV_, other EXT_) | Not supported |

## Benchmarks

`just bench` builds `ms-gltf-render` in Release. Then it measures the frame time of a fixed set of sample scenes. Each scene uses a different draw path: static, many nodes, instanced, skinned, morphed and animated, blended, and transmissive.

The command compares the median CPU and GPU frame time of each scene with the baseline for this machine in `Benchmarks/<model>.json`. A scene fails when it is slower by more than 15% CPU or 50% GPU, and by more than 0.3 ms. If a scene fails, the command exits with status 1.

- Before you run the benchmarks, get the sample assets with `just download-sample-assets`.
- To run only some scenes, give their names: `just bench BrainStem Fox`.
- After an intended change, write a new baseline with `just bench-record`. A baseline is valid only on the machine that recorded it.

Each scene does 30 warm-up frames, then three rounds of 60 frames. The command keeps the fastest round. As a result, the CPU medians stay within a few percent from one run to the next.

## License

See [LICENSE](LICENSE).
