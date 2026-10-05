# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: No image-based lighting

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:rendering
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T17:16:18Z
closed: 2026-10-05T17:16:18Z
+++

Lighting is punctual lights plus a sky/ground hemisphere term. Metallic and glossy materials have nothing to reflect, so they look flat and dark compared to the Khronos reference renders (e.g. MetalRoughSpheres, DamagedHelmet).

- `2026-10-05T16:57:52Z`: Related to #28: matched-lighting comparisons differ mostly because of the ambient specular approximation that IBL would replace.
- `2026-10-05T17:16:18Z`: GLTFEnvironment: procedural studio, uniform, or equirectangular HDR source, GPU-prefiltered into irradiance + GGX specular cubes and a BRDF LUT; split-sum IBL in PBR.metal; GLTFLighting.environment (default: studio); optional GLTFEnvironmentBackground; three.js reference receives the same environment. CLI: --environment, --no-environment, --environment-intensity, --background. GLTFViewer: Background toggle.

---

## 2: Tangents are not generated when a primitive lacks TANGENT

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:rendering, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T17:53:25Z
closed: 2026-10-06T17:53:25Z
+++

Primitives without a TANGENT attribute fall back to a tangent frame built from screen-space derivatives in the fragment shader. This is per-pixel rather than smooth per-vertex, can show faceting/seams on low-poly or curved UV layouts, and does not match the MikkTSpace tangent space the glTF spec says normal maps are baked against.

- `2026-10-05T18:32:33Z`: Autonomous run: tried generating MikkTSpace tangents at load. Punting: there's no clean way to reach MikkTSpace. SwiftMesh's MikkTSpace C target isn't a product (importing it transitively compiles in SwiftPM but is an undeclared dependency); vendoring mikktspace.c again clashes with SwiftMesh's copy (target name and C symbols); Mesh.withTangents() needs a half-edge mesh, which can fail on non-manifold glTF index buffers. Unblocker: OK to add a 'MikkTSpace' library product to SwiftMesh and tag 0.0.5? Alternative without MikkTSpace: Lengyel-style per-vertex tangents (smooth, but not bit-compatible with baked normal maps).
- `2026-10-06T17:53:25Z`: Normal-mapped triangle primitives (default or any variant material) without TANGENT now get MikkTSpace tangents at load via SwiftMesh's SwiftMeshMikkTSpace product (GLTFTangents), fed (u, 1 - v) since glTF's v runs down while maps are baked v-up (without the flip NormalTangentTest fell 38 -> 26 dB vs three.js). Vertices are split only where corners get different tangents. Affects 30 sample models. Tests: TangentTests (u direction, mirrored UVs flip tangent and sign, seam welding). DamagedHelmet golden re-recorded (42 dB vs old, faint detail shading); reference PSNR re-recorded: within -0.3..+0.1 dB except SheenWoodLeatherSofa +2.1 (three.js itself uses derivative tangents). Release load: SheenWoodLeatherSofa 0.46 s.

---

## 3: normalTexture.scale and occlusionTexture.strength are ignored

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:rendering
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T19:18:37Z
closed: 2026-10-05T19:18:37Z
+++

Materials always use a normal scale of 1 and occlusion strength of 1. SwiftGLTF's TextureInfo does not expose `scale` / `strength`, so the values in the file are never read.

- `2026-10-05T16:57:51Z`: Blocked on SwiftGLTF #44 (TextureInfo lacks scale/strength).
- `2026-10-05T19:11:02Z`: SwiftGLTF's TextureInfo now has a scale field (see the current SwiftGLTF main). This may be unblocked: check whether occlusion strength is exposed too, and whether SwiftGLTF #44 can be closed.
- `2026-10-05T19:13:15Z`: Unblocked: SwiftGLTF main (pinned 91f5421b) TextureInfo exposes scale and strength (defaulting to 1).
- `2026-10-05T19:18:37Z`: Material uniforms now use TextureInfo.normalScale / occlusionStrength from SwiftGLTF (default 1). Test MaterialTests.readsNormalScaleAndOcclusionStrength fails before (both stayed 1) and passes after. Goldens unchanged.

---

## 4: Point and line primitives are not drawn

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:rendering
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T22:31:21Z
closed: 2026-10-05T22:31:21Z
+++

Primitives with mode POINTS, LINES, LINE_LOOP or LINE_STRIP are skipped with a warning when loading a GLTFAsset.

- `2026-10-05T22:31:21Z`: Primitives now carry an MTLPrimitiveType: POINTS draw as .point, LINES as .line, LINE_STRIP/LINE_LOOP are converted to line lists. Points and lines are drawn unlit in their base color (as three.js's GLTFLoader does with Points/LineBasicMaterial), unculled, and need no normals; the vertex shader writes point_size 1. Test: drawsPointsAndLines (all four modes; failed before with nothing loaded or drawn). Reference PSNR unchanged (no sample scene moved ≥0.3 dB).

---

## 5: Transparent primitives can sort incorrectly

+++
status: open
priority: low
kind: bug
labels: effort:m, area:rendering, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T21:30:34Z
+++

Blended primitives are sorted back to front by the centre of each primitive's world bounds. Large or intersecting transparent primitives can draw in the wrong order.

- `2026-10-05T22:34:01Z`: Looked at it during the auto-fix run. Punting: per-object sorting (ours by world-bounds centre distance, three.js by object depth) cannot order large or intersecting transparent primitives correctly; fixing it needs a design choice between per-triangle sorting (per-frame CPU/GPU cost) and order-independent transparency (e.g. weighted blended OIT: extra render targets, a composite pass, and a different look). three.js has the same limitation, so reference parity doesn't require either. Unblocker: decide whether to pursue OIT, per-triangle sorting, or accept the limitation (wontfix).
- `2026-10-06T21:30:34Z`: Deferred (user decision 2026-10-06), kept open. Options weighed: accept the limitation (matches three.js and the Khronos viewer), per-triangle sorting of blended primitives, weighted blended OIT as an opt-in, exact OIT (depth peeling / per-pixel lists). Leaning: accept for now; weighted blended OIT opt-in if a real model needs it. Cheap check still worth doing: whether instances of one blended mesh drawn in one instanced call are sorted among themselves.

---

## 6: Primitives without normals use extra memory

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:performance
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T17:35:07Z
closed: 2026-10-06T17:35:07Z
+++

When NORMAL is missing, every triangle is unwelded to produce flat normals, so vertex count becomes 3× the triangle count. Large models without normals use much more GPU memory.

- `2026-10-06T17:35:07Z`: Triangle primitives without NORMAL are no longer unwelded. GLTFAsset.Primitive.hasNormals is false for them and reaches the shader as GLTFMaterialUniforms.hasNormals (per-batch draws and merged records); the fragment shader then derives the flat face normal from cross(dfdx, dfdy) of the world position, turned to face the viewer and given the winding's sign so the existing back-face flip behaves as for real normals. Skinned and morphed primitives use the deformed position. Vertex count for such primitives drops from 3x the triangle count to the file's own. Test: primitivesWithoutNormalsKeepTheirVertices (indexed quad keeps 4 vertices, failed with 6; lit flat from +z). Goldens and reference unchanged, including normal-less scenes (Triangle, SimpleMeshes, SimpleMorph).

---

## 7: KTX2 and WebP textures are not loaded

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:extensions
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T18:45:26Z
closed: 2026-10-05T18:45:26Z
+++

Textures whose image comes from an extension (KHR_texture_basisu, EXT_texture_webp) have no `source` and are skipped with "Texture N has no source (extension images are not supported yet)". Seen on SheenWoodLeatherSofa.

- `2026-10-05T18:45:26Z`: EXT_texture_webp supported: textures without a source use the extension's image (ImageIO decodes WebP). Test loadsWebPTextures (SheenWoodLeatherSofa) fails before (texture warnings, no base color textures) and passes after. KTX2/KHR_texture_basisu split into a separate issue: it needs the Basis Universal transcoder and no binary sample model uses it. Unsupported KTX2 textures now warn explicitly.

---

## 8: Draco compressed meshes are not supported

+++
status: open
priority: low
kind: feature
labels: effort:l, area:extensions, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T18:31:35Z
+++

Primitives using KHR_draco_mesh_compression cannot be decoded; GLTFViewer lists glTF-Draco variants (about 20 sample models, none of them a default variant) as unsupported. Needs Google's Draco decoder (Apache-2.0, large C++), most likely in SwiftGLTF. Deferred: no default sample needs it. Meshopt split out to #104.

- `2026-10-05T18:45:49Z`: Autonomous run: surveyed usage — no default glTF-Binary sample uses either; they appear only in alternate variants (glTF-Draco for ~20 models; glTF-Meshopt / -Meshopt-EXT for BrainStem, DragonAttenuation, MeshoptCubeTest). Punting: both need a third-party C++ decoder (meshoptimizer, MIT, small; Draco, Apache-2.0, large), and both act at the buffer-view/accessor level, which belongs in SwiftGLTF rather than this renderer. Questions: (1) OK to add meshoptimizer's decoder to SwiftGLTF for EXT_/KHR_meshopt_compression? (2) For Draco, vendor Google's decoder into SwiftGLTF, or leave unsupported? Suggest splitting this issue into meshopt (effort:m) and Draco (effort:l).

---

## 9: KHR_materials_emissive_strength is ignored

+++
status: closed
priority: low
kind: feature
labels: effort:xs, area:extensions
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T20:13:44Z
closed: 2026-10-05T20:13:44Z
+++

The shader has an emissiveStrength uniform but it is always 1; the extension value is not read.

- `2026-10-05T20:13:44Z`: Material uniforms use SwiftGLTF's Material.emissiveStrength (default 1). Test readsEmissiveStrength fails before (stayed 1). Reference PSNR: CompareEmissiveStrength 29.3 → 33.6 dB, EmissiveStrengthTest 27.3 → 29.2.

---

## 10: PBR material extensions are not supported

+++
status: closed
priority: low
kind: feature
labels: effort:xl, area:extensions
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T19:12:12Z
closed: 2026-10-05T19:12:12Z
+++

No support for KHR_materials_clearcoat, transmission, sheen, specular, ior, volume, iridescence, anisotropy, dispersion, or KHR_materials_variants. Models using them render with base metallic-roughness only.

- `2026-10-05T16:57:52Z`: Very large; should be split into one issue per extension before work starts.
- `2026-10-05T19:12:12Z`: Split into one issue per extension: #46, #47, #48, #49, #50, #51, #52, #53, #54. Transmission + volume first (needed by ABeautifulGame).

---

## 11: KHR_mesh_quantization is unverified

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:extensions, area:testing, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T14:21:28Z
closed: 2026-10-06T14:21:28Z
+++

Quantized attributes go through Container.floatComponents and will probably work, but no quantized sample has been checked.

- `2026-10-06T14:21:28Z`: Verified: each glTF-Quantized sample loads without warnings and renders like its unquantized .glb (Avocado 55.6 dB, Lantern 47.4, Duck 42.3, AnimatedMorphCube 38.6 mid-animation with quantized morph targets; differences only at edges), with bounds within 1%. Test: SampleAssetsTests.quantizedMatchesUnquantized. The quantized Lantern combines its three meshes into one, so primitive counts are not compared. Meshopt variants that also use quantization need #8.

---

## 12: EXT_mesh_gpu_instancing is not supported

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:extensions, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T18:39:14Z
closed: 2026-10-06T18:39:14Z
+++

Nodes using EXT_mesh_gpu_instancing render a single instance.

- `2026-10-05T16:57:51Z`: Related to #17: both are about drawing repeated meshes with GPU instancing.
- `2026-10-06T18:32:52Z`: Priority by sample usage: 1 model; stays low.
- `2026-10-06T18:39:15Z`: Supported: EXT_mesh_gpu_instancing TRANSLATION/ROTATION/SCALE accessors become per-copy node-relative matrices (Resources.nodeInstanceMatrices, Instance.instanceMatrix, Batch/Record.instanceMatrices); every place that poses instances uses nodeWorld * instanceMatrix, so animated instanced nodes move their copies. Copies share one instanced batch (SimpleInstancing: 125 instances, 1 batch) and the merged path. Skinned meshes ignore instancing (they follow their joints). Custom _ attributes ignored. Test: gpuInstancingDrawsEveryCopy. Render matches the sample screenshot; reference PSNR 30.3 -> 30.9 (many small aliased edges).

---

## 13: Node animation is not supported

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:animation
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T18:53:58Z
closed: 2026-10-05T18:53:58Z
+++

glTF animations targeting node translation/rotation/scale are ignored; models render in their rest pose.

- `2026-10-05T18:53:58Z`: Node TRS animation: GLTFAsset.animations (clips decoded via SwiftGLTF keyframes; step/linear/cubic, slerp rotations), GLTFAsset.pose(animation:time:) → GLTFPose (world matrix per node), GLTFRenderer(pose:) uses per-frame instance transforms. CLI --animation/--time; web reference setAnimation (three AnimationMixer) so comparisons stay in step; GLTFViewer play/pause for the first clip. Tests: AnimationTests sample poses (incl. child inheritance, clamping) and render a pose; verified rendersPose fails when the pose is ignored. Visual check vs three.js: BoxAnimated, CesiumMilkTruck match. Not covered: morph weights (#15), skinning (#14), animated lights/cameras. Demo playback not run interactively.

---

## 14: Skinning is not supported

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:animation
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T19:01:44Z
closed: 2026-10-05T19:01:44Z
+++

JOINTS_0/WEIGHTS_0 and skins are ignored; skinned models render in bind pose.

- `2026-10-05T19:01:44Z`: Skinning: JOINTS_0/WEIGHTS_0 in a separate per-primitive vertex buffer (only skinned primitives pay for it); vertex_skinned blends up to 4 joint matrices (world(joint) × inverse bind, from the pose or the rest pose); the mesh node's transform is ignored per spec; skinned instances get their own (opaque/blended) pipelines and are not batched. Test SkinningTests fails before (triangle drawn at the mesh node) and passes after; the 5 skinned sample models now render (they were blank). Matches three.js mid-animation for Fox, CesiumMan, BrainStem, RiggedFigure. Limitations: normals use the blended skin matrix (assumes rigid joints); static vs skinned blended primitives sort separately.

---

## 15: Morph targets are not supported

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:animation
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T19:06:07Z
closed: 2026-10-05T19:06:07Z
+++

Primitive targets and mesh weights are ignored.

- `2026-10-05T19:06:07Z`: Morph targets on the GPU: per-primitive [target][vertex] position/normal deltas; both vertex functions apply weighted deltas (before skinning, per spec) using vertex_id; weights from node.weights, else mesh.weights, else zeros; animated 'weights' channels populate GLTFPose.morphWeights. Morphed instances aren't batched. Tests: MorphTargetTests (rest/mesh weights, node override, animated weights) — the override and animated cases failed before. Visual match vs three.js: AnimatedMorphCube, MorphStressTest. Not covered: TANGENT morph deltas.

---

## 16: KHR_animation_pointer is not supported

+++
status: closed
priority: low
kind: feature
labels: effort:l, area:animation, area:extensions
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T22:49:57Z
closed: 2026-10-05T22:49:57Z
+++

Animations targeting arbitrary properties via KHR_animation_pointer are ignored.

- `2026-10-05T22:49:57Z`: Implemented KHR_animation_pointer for nodes and materials. /nodes/N/{translation,rotation,scale,weights} become ordinary node channels. /materials/N/... supports the core and extension factors (base color, metallic/roughness, emissive + strength, alpha cutoff, normal scale, occlusion strength, IOR, transmission, volume, specular, iridescence, anisotropy, sheen, clearcoat, dispersion) and KHR_texture_transform offset/rotation/scale on every texture slot we bind; texture matrices are rebuilt from the file's unanimated parts plus the animated ones. GLTFPose.materialUniforms carries per-material overrides, which GLTFRenderer uses in place of static uniforms. Other targets (lights, cameras, node visibility, KHR_materials_diffuse_transmission, which isn't supported at all) are skipped and listed in GLTFAsset.warnings / GLTFAnimationClip.unsupportedPointers. Test: AnimationTests.animatesThroughPointers. Checked AnimationPointerUVs renders differently at t=0 and t=1.5 (31.6 dB apart).

---

## 17: Meshes shared by many nodes are drawn one call each

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:performance
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T18:40:39Z
closed: 2026-10-05T18:40:39Z
+++

Every node instance of a mesh produces its own draw call. Scenes with many repeated meshes (e.g. SimpleInstancing, scattered props) issue far more draws than needed.

- `2026-10-05T16:57:52Z`: Related to #12 (EXT_mesh_gpu_instancing).
- `2026-10-05T18:40:39Z`: Opaque instances sharing a primitive, material and winding become one instanced draw (GLTFAsset.opaqueBatches, static per-batch GLTFInstance buffers; the global model matrix is applied in the vertex shader). Blended primitives stay one per draw for sorting. Test instancesSharedMeshes: 3 nodes on one mesh give 1 batch of 3, all 3 rendered (verified it fails with instanceCount forced to 1). Goldens unchanged.

---

## 18: GLTFAsset loads textures serially

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:performance
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T18:35:03Z
closed: 2026-10-05T18:35:03Z
+++

Images are decoded and uploaded one at a time on the loading thread. Large texture-heavy models take a long time to load.

- `2026-10-05T18:35:03Z`: Images referenced by materials are preloaded in parallel (bytes read serially because Container's URI cache isn't thread-safe; decode + MTKTextureLoader upload via concurrentPerform). ABeautifulGame load: ~1.5s → ~0.88s (debug). No new test: performance-only; exact-match goldens and the 120-model sample suite verify identical output.

---

## 19: No frustum culling

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:performance
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T01:34:29Z
closed: 2026-10-06T01:34:29Z
+++

Every instance is drawn every frame regardless of visibility, even though world bounds are already computed per instance.

- `2026-10-05T19:13:47Z`: Related to #40: per-instance bounds are rest-pose only, so culling animated or skinned meshes needs #40 first.
- `2026-10-06T01:34:29Z`: Added GLTFFrustum (planes from the view-projection matrix, Metal clip space) and frustum culling in GLTFRenderer: per-batch draws are filtered by their (posed) world bounds, and merged records skip their Metal draw when outside the view (no extra elements). Test: frustumCullsBoundsOutsideTheView; goldens and reference PSNR unchanged. Measured with the scenes' own cameras: no gain on VirtualCity (~1.0 ms CPU either way) and NodePerformanceTest slightly slower (8.5 → 9.1 ms) because bounds tests for 10,000 records cost more than the draws they skip now that merged draws are cheap. Kept for large scenes with much off screen, where skipped draws and GPU work should outweigh the test cost.

---

## 20: No shadows

+++
status: open
priority: low
kind: feature
labels: effort:l, area:rendering, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-13T19:37:48Z
+++

GLTFRenderer does not cast or receive shadows from punctual lights.

- `2026-10-05T22:50:11Z`: Looked at it during the auto-fix run. Punting: shadows need design decisions the code can't settle, and glTF doesn't specify them. (1) Which lights cast (directional/spot: one shadow map each; point: cube maps)? (2) API: opt-in per renderer or per light, plus resolution, filtering (PCF?) and bias settings. (3) Most of our lighting is image-based and unshadowed, so punctual-only shadows may change little. (4) The three.js reference renders without shadows, so default-on shadows would lower reference PSNR for lit scenes unless the reference enables them too. Unblocker: pick the scope, e.g. 'opt-in shadow maps for directional and spot lights, PCF, off by default, reference unchanged'.
- `2026-10-07T15:23:55Z`: Skipped again in this auto-fix run: the scope question from the earlier comment is still open. Proposed default if you agree: opt-in shadow maps for directional and spot lights, 3x3 PCF, off by default, three.js reference unchanged.

---

## 21: Only one scene per GLTFAsset

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:api
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T00:31:22Z
closed: 2026-10-06T00:31:22Z
+++

GLTFAsset flattens a single scene at load time. Switching scenes in a multi-scene file requires loading the asset again.

- `2026-10-06T00:31:22Z`: GLTFAsset now separates scene-independent loading (materials, textures, meshes, skins, animations: GLTFAsset.Resources) from scene flattening. asset.scene(_:) builds another scene's asset from the same loaded data (same variant), without decoding meshes or textures again; GLTFAsset.sceneIndex, sceneCount and variant are exposed. Test: switchesScenes (checks shared vertex buffers and materials, and the out-of-range error). Uses the new API, so it could not run before.

---

## 22: No golden-image tests

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:testing
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T18:07:38Z
closed: 2026-10-05T18:07:38Z
+++

Rendering is only covered by a single-triangle test. Regressions in the PBR path (seen during development: material index crash, 24-bit PNG decode failure) were found by manually rendering the Khronos samples.

- `2026-10-05T18:07:38Z`: GoldenImageTests: 13 Khronos sample models rendered at 256×256 with default IBL, compared with GoldenImage (45 dB, ignoring edge AA halos). Goldens checked against the Khronos screenshots before recording. Failures save actual + 8× difference images. Verified: breaking KHR_texture_transform fails TextureTransformTest at 12.1 dB.

---

## 23: GLTFViewer demo is untested on visionOS

+++
status: closed
priority: low
kind: task
labels: effort:s, area:demo, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-07T02:32:09Z
closed: 2026-10-07T02:32:09Z
+++

The demo lists visionOS as a supported platform but has never been built or run there. Interaction3D does not declare visionOS.

- `2026-10-07T02:32:09Z`: Obsolete: the viewer has been run and tested on Vision Pro throughout #102/#140/#141.

---

## 24: GLTFViewer demo cannot build for the iOS Simulator

+++
status: closed
priority: low
kind: bug
labels: upstream, effort:xs, area:demo
created: 2026-10-05T16:00:03Z
updated: 2026-10-05T19:13:00Z
closed: 2026-10-05T19:13:00Z
+++

Building GLTFViewer for the iOS Simulator fails in MetalSupport and MetalSprockets:

```
MetalSupport/MTLDevice+Capabilities.swift:15:36: type 'MTLGPUFamily' has no member 'metal4'
MetalSprockets/Metal/GPUTimestampSampling.swift:24:23: cannot find type 'MTL4CounterHeap' in scope
```

macOS and iOS device builds succeed. Tracked upstream in MetalSprockets and MetalSupport.

- `2026-10-05T16:57:51Z`: Blocked on MetalSprockets #478 and MetalSupport #13.
- `2026-10-05T19:13:00Z`: Won't fix: iOS Simulator support is not needed.

---

## 25: GLTFViewer demo lacks viewing controls

+++
status: closed
priority: low
kind: enhancement
labels: effort:m, area:demo, deferred
created: 2026-10-05T16:00:03Z
updated: 2026-10-06T22:02:27Z
closed: 2026-10-06T22:02:27Z
+++

The demo has no controls for lighting/exposure, selecting a camera defined in the file, debug views (normals, UVs, material channels), or downloading all samples at once.

- `2026-10-05T19:13:47Z`: Related to #45 (animation picker and scrubber).
- `2026-10-06T14:31:01Z`: Related: #81 (document inspector), #82 (file variant picker), #90 (material variant picker).
- `2026-10-06T18:03:43Z`: Started: GLTFViewer now has an inspector (toolbar toggle; on visionOS a trailing ornament since inspectors are unavailable there) with tabs, tab 0 Camera: Orbit or a camera from the file (follows animated camera nodes; dragging continues orbiting from it), orbit field of view, distance/target/position readouts, Reset View. Lighting/exposure, debug views and download-all remain; they can become further tabs.
- `2026-10-06T19:08:55Z`: Debug views split out to #112.
- `2026-10-06T19:32:30Z`: Debug views done in #112 (Model tab Shading picker).
- `2026-10-06T22:02:27Z`: Closed: camera selection (Camera tab), debug views (#112), lighting (environment picker, intensity, rotation #130; tone mapping #127) and now exposure (Display tab slider, stops, persisted) are in. Download-all dropped as not needed (user).

---

## 26: GLTFViewer support package and Xcode project are not committed

+++
status: closed
priority: critical
kind: bug
labels: area:demo, area:vcs
created: 2026-10-05T16:00:19Z
updated: 2026-10-05T16:58:09Z
closed: 2026-10-05T16:14:52Z
+++

The root .gitignore (SwiftPM template) contains `Packages` and `*.xcodeproj`. As a result `Demos/GLTFViewer/Packages/GLTFViewerSupport/` (all of the demo code) and `Demos/GLTFViewer/GLTFViewer.xcodeproj` are untracked. Commits d4345435 and 236a8be9 ("GLTFViewer: use Interaction3D for camera controls", empty) are missing this work. A fresh checkout cannot build the demo.

- `2026-10-05T16:14:52Z`: Removed template Packages/*.xcodeproj ignores; demo support package and Xcode project now tracked.

---

## 27: GLTFViewer: compare against a web glTF renderer

+++
status: closed
priority: medium
kind: feature
labels: area:demo
created: 2026-10-05T16:21:59Z
updated: 2026-10-05T16:58:09Z
closed: 2026-10-05T16:33:03Z
+++

The demo app has no way to check our rendering against an established renderer.

Wanted:
- A toggle that also renders the selected model in a WebKit view using a standard web glTF renderer (e.g. three.js / <model-viewer> / Khronos glTF Sample Viewer), from the same camera.
- Two comparison layouts: side by side, and a single view with a draggable split slider that reveals one renderer on each side.

- `2026-10-05T16:33:03Z`: MetalSprocketsGLTFWebReference (three.js r186 in WebKit); CLI --web/--web-lighting writes -web.png and -compare.png; GLTFViewer has Metal/three.js/Side by Side/Split modes with matched or environment lighting.

---

## 28: Matched web lighting differs from GLTFRenderer for ambient specular

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:rendering, area:demo
created: 2026-10-05T16:42:33Z
updated: 2026-10-05T19:38:11Z
closed: 2026-10-05T19:38:11Z
+++

In GLTFViewer comparison modes and `ms-gltf-render --web --web-lighting matched`, the three.js reference is meant to use the same lighting as GLTFRenderer. It does not for ambient light:

- GLTFRenderer adds an ambient specular term (an analytic environment-BRDF approximation of the sky/ground colours).
- three.js HemisphereLight contributes diffuse only.

Metallic materials therefore always differ between the two renders, even where the direct-light BRDF agrees. Example: WaterBottle (Matched Lights) — our metal body is lighter and flatter with little visible roughness/normal detail; three.js is darker with visible scratches.

Related: #1.

- `2026-10-05T17:16:18Z`: With an environment (now the default) matched mode feeds three.js the same environment, so ambient specular matches. The mismatch remains only for the no-environment hemisphere fallback.
- `2026-10-05T18:25:54Z`: Autonomous run: reviewed after #1 — the mismatch now only exists for the no-environment hemisphere fallback. Punting: fixing it needs a design choice. Options: (a) drop the analytic ambient specular from the fallback so it matches three.js (metals go near-black without an environment); (b) patch three.js materials to emulate our analytic ambient; (c) remove the hemisphere fallback entirely and always use an environment (GLTFEnvironment .uniform for a cheap neutral one). Which do you want?
- `2026-10-05T19:33:13Z`: Decision: always use an environment. Remove the hemisphere fallback; when no environment is given, use a neutral one (e.g. GLTFEnvironment .uniform or the studio).
- `2026-10-05T19:38:11Z`: Always use an environment: GLTFLighting.environment is required (default GLTFEnvironment.studio, now non-optional); removed sky/ground colours, the .hemisphere preset, the shader's no-environment branches and analytic BRDF approximation, placeholder environment textures, the web reference's hemisphere light, and the CLI --no-environment flag. Matched web lighting now always uses the same environment, so the mismatch can no longer occur. No new failing-first test: the fix deletes the mismatched code path; WebReferenceTests now uses environmentIntensity 0 for its unlit check. Goldens bit-identical.

---

## 29: GLTFViewer: comparison mode resets when switching models

+++
status: closed
priority: low
kind: enhancement
labels: effort:xs, area:demo
created: 2026-10-05T16:44:36Z
updated: 2026-10-05T17:02:15Z
closed: 2026-10-05T17:02:15Z
+++

In GLTFViewer, the comparison settings (Metal / three.js / Side by Side / Split, the web lighting choice, and the split position) are stored per model view. Selecting another model in the sidebar resets them to Metal only, so comparing several models means re-selecting the mode every time.

Expected: the chosen comparison mode, web lighting and split position stay the same across model selections.

- `2026-10-05T17:02:15Z`: Comparison mode, web lighting and split position live in SamplesView and are passed to each model view as a binding.

---

## 30: 1×1 textures trigger a Metal validation failure

+++
status: closed
priority: high
kind: bug
labels: area:rendering
created: 2026-10-05T16:47:30Z
updated: 2026-10-05T16:58:09Z
closed: 2026-10-05T16:48:56Z
+++

Loading a model with 1×1 images (e.g. TextureEncodingTest) with Metal API validation enabled aborts:

```
-[MTLDebugBlitCommandEncoder generateMipmapsForTexture:]:1105: failed assertion `Generate Mipmaps For Texture Validation
[tex mipmapLevelCount](1) must be > 1.
```

GLTFViewer crashes when this model is selected while running from Xcode. Without validation (CLI, `xcb test`) the model renders normally.

- `2026-10-05T16:48:56Z`: Only request mipmaps for textures larger than 1×1. Verified: full sample suite passes with MTL_DEBUG_LAYER=1.

---

## 31: Tests do not run with Metal API validation

+++
status: closed
priority: high
kind: task
labels: area:testing
created: 2026-10-05T16:47:30Z
updated: 2026-10-05T16:58:09Z
closed: 2026-10-05T16:51:47Z
+++

The test suite (including the Khronos sample-model tests) runs without the Metal API validation layer. Invalid Metal usage is silently ignored, so tests pass even when the same code aborts under validation in GLTFViewer. Example: the 1×1 texture mipmap failure on TextureEncodingTest passed `loadsAndRenders`.

- `2026-10-05T16:51:47Z`: Added .metalValidation test trait: enables MTL_DEBUG_LAYER before the device exists and fails if the device is not MTLDebugDevice. Verified it catches #30 when the fix is reverted.

---

## 32: Spot lights render differently from the three.js reference

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, area:demo, effort:m
created: 2026-10-05T17:16:25Z
updated: 2026-10-05T18:30:42Z
closed: 2026-10-05T18:30:42Z
+++

LightVisibility (three KHR_lights_punctual spot lights, range 5, inner 0.65 / outer 0.8 rad) renders very differently in GLTFRenderer and the matched three.js reference, with or without an environment:

- three.js shows a red wash across most of the plane outside the red cone; GLTFRenderer does not.
- Cone sizes and falloff differ.
- With `--no-environment`, the plane outside the cones is grey in GLTFRenderer and black in three.js.

Repro: `ms-gltf-render LightVisibility.glb --web --no-environment`.

Unknown whether GLTFRenderer, the JS light conversion in the web reference, or both are wrong.

- `2026-10-05T18:30:42Z`: Cause: three.js GLTFLoader imports the file's KHR_lights_punctual lights into the scene, so the reference was lit by its own copy of the lights plus ours. The reference now removes loader-created lights. Regression test WebReferenceTests.ignoresLightsDefinedInTheFile fails before (unlit scene rendered with light) and passes after. Remaining plane brightness difference is #33 (rough metal under IBL).

---

## 33: Rough metals are darker than the three.js reference under IBL

+++
status: closed
priority: medium
kind: enhancement
labels: area:rendering, effort:m
created: 2026-10-05T17:16:25Z
updated: 2026-10-05T20:09:24Z
closed: 2026-10-05T20:09:24Z
+++

With image-based lighting, rough metallic materials (e.g. the rough end of MetalRoughSpheres) render slightly darker in GLTFRenderer than in three.js with the same environment. GLTFRenderer uses single-scattering GGX with the split-sum approximation, which loses energy at high roughness; three.js compensates for multiple scattering.

- `2026-10-05T18:24:28Z`: Related to #1 (IBL) — needs multiple-scattering energy compensation in the split-sum path.
- `2026-10-05T19:53:42Z`: Biggest cause of low PSNR against three.js (ReferencePSNR.json). These scenes have no material or omit metallicFactor, so glTF defaults make them fully rough metal, and ours renders much darker: SimpleInstancing 13.4 dB, BoxVertexColors 15.6, RecursiveSkeletons 15.7, MultiUVTest 15.9, NodePerformanceTest 16.4, BoxInterleaved 18.2, and the plane in LightVisibility 16.8. Raised to Medium.
- `2026-10-05T20:09:24Z`: Added multiple-scattering energy compensation to IBL (Fdez-Agüera 2019, as three.js and the Khronos viewer do): roughness-dependent single-scatter Fresnel, the lost energy (1 − Ess) returned scaled by average Fresnel, and diffuse reduced by the total specular reflectance. White-furnace test roughMetalConservesEnergy: 0.117 before, passes after (≥ 0.42 of 0.46). Reference PSNR re-recorded: 29 scenes improved (SimpleInstancing 13.4 → 27.0, LightVisibility 16.8 → 29.2, BoxVertexColors 15.6 → 26.5, MultiUVTest 15.9 → 25.9, RecursiveSkeletons 15.7 → 24.6, BoxInterleaved 18.2 → 25.5), 6 regressed (CompareRoughness 36.7 → 32.9, OrientationTest 27.3 → 26.3, CompareSpecular 26.6 → 25.7, CompareEmissiveStrength 30.2 → 29.3, WaterBottle 33.6 → 32.9, CommercialRefrigerator 25.6 → 25.1); total +99.5 dB. 12 goldens re-recorded after comparing old/new/three.js (new renders are closer to three.js; test patterns intact).

---

## 34: GLTFViewer: web view shows partial content while three.js loads

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:xs
created: 2026-10-05T17:16:40Z
updated: 2026-10-05T17:49:50Z
closed: 2026-10-05T17:49:50Z
+++

When a comparison mode is chosen, the three.js side takes a moment to become ready (CDN fetch, model load, environment upload). During that time the web view shows an incomplete page instead of a clean empty state.

Expected: a placeholder (or plain black) until the model is loaded and the first frame with the correct camera and lighting has been rendered.

- `2026-10-05T17:49:50Z`: Web view stays covered by a background-coloured placeholder (small spinner) until the first update with the view's camera, lighting and environment has completed.

---

## 35: KHR_node_visibility is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:s
created: 2026-10-05T18:30:47Z
updated: 2026-10-05T22:39:05Z
closed: 2026-10-05T22:39:05Z
+++

Nodes hidden with KHR_node_visibility (visible: false), and their descendants, are still drawn and their lights still contribute. Example: LightVisibility — the red light on InvisibleLight and its two children should be invisible, but GLTFRenderer adds three coincident red spot lights.

- `2026-10-05T22:39:05Z`: Implemented KHR_node_visibility: a node with visible false skips its mesh and all descendants' meshes at load (lights and cameras unaffected; animating visibility needs KHR_animation_pointer, #16). Extension type declared locally (KHRNodeVisibility.swift). Test: hidesInvisibleNodes (failed: hidden node's triangle still loaded). Reference PSNR dropped for CubeVisibility (39.1→19.2) and NodeVisibilityTest (48.8→15.5) because three.js 0.186's GLTFLoader doesn't support the extension: its NodeVisibilityTest render shows the 'extension is not supported' fallback, while ours matches the Khronos screenshot ('supported ✔ / handles defaults ✔'). Baselines re-recorded at the lower values.

---

## 36: KTX2 (KHR_texture_basisu) textures are not loaded

+++
status: closed
priority: medium
kind: feature
labels: area:extensions, effort:l, deferred
depends: 108, 125
created: 2026-10-05T18:45:26Z
updated: 2026-10-06T20:16:30Z
closed: 2026-10-06T20:16:30Z
+++

Textures whose only source is a KTX2 / Basis Universal image (KHR_texture_basisu) are skipped with "Texture N skipped: KTX2 (KHR_texture_basisu) is not supported". Loading them needs a Basis Universal transcoder. No glTF-Binary model in the Khronos sample set uses it; the glTF-KTX-BasisU variants of several models do. Split from #7.

- `2026-10-06T18:32:52Z`: Priority by sample usage: required by 6 models' KTX variants (ABeautifulGame, AnisotropyBarnLamp, CarConcept, ChronographWatch, FlightHelmet, StainedGlassLamp); no default variant.
- `2026-10-06T18:55:31Z`: Candidate decoder: ~/Projects/Scratch/BasisUniversalMetal (KTX2/Basis Universal -> MTLTexture via upstream's C transcoder API; ASTC/BC7/BC6H/RGBA targets, cubes, arrays, mips; tests pass). Before use: per-texture sRGB override (BasisUniversalMetal #1, needed), single-level files and mipmaps (#2), a remote to depend on (#3).
- `2026-10-06T20:16:30Z`: KTX2 / KHR_texture_basisu is supported through the optional MetalSprocketsGLTFBasisU product (#125), built on the texture decoder extension point (#123).

---

## 37: Morph targets ignore TANGENT offsets

+++
status: closed
priority: low
kind: bug
labels: area:animation, area:rendering, effort:s
created: 2026-10-05T19:10:20Z
updated: 2026-10-05T22:03:44Z
closed: 2026-10-05T22:03:44Z
+++

Morph target TANGENT deltas are not read or applied. Only POSITION and NORMAL offsets are morphed, so normal-mapped meshes with morph targets shade slightly wrong while morphed.

- `2026-10-05T22:03:44Z`: GLTFMorphDelta gains a tangent (xyz) field read from TANGENT morph targets; applyMorph offsets tangent.xyz (w untouched) before skinning. Test: MorphTargetTests.readsTangentDeltas (failed with tangent zeroed). Goldens and reference PSNR unchanged.

---

## 38: Animated lights and cameras do not move

+++
status: closed
priority: medium
kind: feature
labels: area:animation, effort:s
created: 2026-10-05T19:10:20Z
updated: 2026-10-05T22:00:44Z
closed: 2026-10-05T22:00:44Z
+++

Animation poses only affect mesh instances. Lights (KHR_lights_punctual) and cameras on animated nodes keep their rest transforms in GLTFAsset.lights and GLTFAsset.cameras.

- `2026-10-05T22:00:44Z`: Added GLTFAsset.lights(pose:) and cameras(pose:) (lights/cameras remember their node), and GLTFLighting(asset:pose:); GLTFRenderer's default lighting uses its pose. ms-gltf-render poses --camera and file lights with --animation/--time; GLTFViewer re-poses lights each frame. Test: AnimationTests.lightsAndCamerasFollowThePose (fixture gains a light and camera under the animated parent). The three.js reference still uses rest-pose lights in the demo comparison.

---

## 39: Face culling is wrong for animated negative scale

+++
status: closed
priority: low
kind: bug
labels: area:animation, area:rendering, effort:s
created: 2026-10-05T19:10:20Z
updated: 2026-10-05T22:07:52Z
closed: 2026-10-05T22:07:52Z
+++

Batch winding (isMirrored) is decided from the rest pose. When an animation gives a node a negative-determinant transform (or removes one), front and back faces are culled the wrong way for that instance.

- `2026-10-05T22:07:52Z`: With a pose, GLTFRenderer orders a batch's instances unmirrored-then-mirrored by the sign of each posed world matrix's determinant and issues up to two draws (baseInstance offset) with matching front-face winding. Skinned meshes are unchanged (placed by joints). Test: AnimationTests.mirroringAnimationKeepsFrontFaces (failed: triangle culled at time 1).

---

## 40: Bounds do not account for animation or skinning

+++
status: closed
priority: medium
kind: bug
labels: area:animation, area:api, effort:m
created: 2026-10-05T19:10:21Z
updated: 2026-10-05T19:21:03Z
closed: 2026-10-05T19:21:03Z
+++

GLTFAsset.bounds and per-instance world bounds come from the rest pose and the unskinned vertex positions. For skinned models the bind-space positions can be far from what is drawn, so GLTFCamera.framing can frame the wrong area, and blended-primitive sorting uses stale centres. Likely affects RecursiveSkeletons.

- `2026-10-05T19:13:47Z`: Related to #19: frustum culling needs bounds that follow animation and skinning.
- `2026-10-05T19:21:03Z`: Skinned bounds come from per-joint mesh-space boxes moved by the joint matrices (rest bounds at load, posed via asset.bounds(for:) / worldBounds(of:pose:)); morph targets grow primitive bounds conservatively (weights 0...1); animated nodes use the posed world matrix; blended sorting uses posed bounds when a pose is given. Test restBoundsFollowJoint failed before (centred at the mesh node, x = 10); new tests cover posed skinned, animated-node and morph bounds. Skinned samples (RecursiveSkeletons, BrainStem, Fox) frame correctly. Goldens unchanged.

---

## 41: Skinned normals are wrong for non-rigid joints

+++
status: closed
priority: low
kind: bug
labels: area:animation, area:rendering, effort:xs
created: 2026-10-05T19:10:21Z
updated: 2026-10-05T22:12:00Z
closed: 2026-10-05T22:12:00Z
+++

vertex_skinned transforms normals with the upper 3×3 of the blended skin matrix instead of its inverse transpose. Joints with non-uniform scale produce incorrectly shaded normals.

- `2026-10-05T22:12:00Z`: vertex_skinned now transforms normals by the skin matrix's cofactor matrix (inverse transpose up to scale, sign-corrected for mirroring) instead of the skin matrix itself. Test: SkinningTests.scaledJointNormalsUseInverseTranspose (lit triangle under a 4x-scaled joint; failed with green 121, passes after). Goldens and reference PSNR unchanged.

---

## 42: Skinned and static blended primitives are sorted separately

+++
status: closed
priority: low
kind: bug
labels: area:rendering, effort:s
created: 2026-10-05T19:10:21Z
updated: 2026-10-05T22:33:47Z
closed: 2026-10-05T22:33:47Z
+++

Blended primitives are drawn in two pipelines (static, then skinned), each sorted back to front on its own. Transparent skinned and static primitives that overlap can draw in the wrong order.

- `2026-10-05T22:33:47Z`: Blended primitives now keep a single back-to-front order; GLTFRenderer splits it into consecutive runs of static or skinned batches and draws each run with its own pipeline, in order. Test: SkinningTests.blendedSkinnedAndStaticShareOneSortOrder (far skinned red + near static green, half transparent; failed with red 178 / green 131 — the far triangle on top).

---

## 43: Cyclic node hierarchies recurse forever

+++
status: closed
priority: low
kind: bug
labels: area:api, effort:xs
created: 2026-10-05T19:10:21Z
updated: 2026-10-05T22:05:24Z
closed: 2026-10-05T22:05:24Z
+++

GLTFAsset's scene traversal and GLTFNodeHierarchy.pose follow node children without cycle detection. A malformed file whose nodes form a cycle overflows the stack instead of failing to load.

- `2026-10-05T22:05:24Z`: GLTFAsset's scene traversal tracks the current root-to-node path and throws GLTFError.invalidDocument when a node is its own ancestor; GLTFNodeHierarchy.pose only runs on loaded assets so never sees a cycle. Test: rejectsCyclicNodeHierarchy (GLTFAsset doesn't run SwiftGLTF's validator, so the new check is what throws). Not run failing-first: without the fix it overflows the stack and crashes the test process.

---

## 44: Web reference and its test require network access

+++
status: closed
priority: low
kind: task
labels: area:testing, area:demo, effort:s
created: 2026-10-05T19:10:21Z
updated: 2026-10-05T22:53:55Z
closed: 2026-10-05T22:53:55Z
+++

The three.js reference loads three.js from cdn.jsdelivr.net. Offline, GLTFWebReference fails after a 30 s timeout, the CLI --web option fails, and WebReferenceTests.ignoresLightsDefinedInTheFile fails rather than being skipped.

- `2026-10-05T22:53:55Z`: three.js is still fetched from jsdelivr (not vendored), but through the page's own gltfref://cdn/ scheme: the first request downloads each file and saves it under ~/Library/Caches/MetalSprocketsGLTFWebReference/, later runs serve it from there, so the reference, the CLI --web option and the tests work offline after one online run. GLTFWebReference.cdnBaseURL / cacheDirectory are configurable; GLTFWebReference.isAvailable (cached, or CDN reachable within 5 s) gates WebReferenceTests and ReferenceComparisonTests so they skip instead of failing when offline with an empty cache. Test: WebReferenceTests.worksOfflineFromTheCache (points the CDN at an invalid host after warming the cache; uses the new cdnBaseURL API, so it could not run before the change).

---

## 45: GLTFViewer can only play the first animation

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-05T19:11:01Z
updated: 2026-10-05T22:35:43Z
closed: 2026-10-05T22:35:43Z
+++

The demo play button always plays animations[0], looping. Models with several clips (e.g. Fox: Survey, Walk, Run) have no way to choose another clip, and there is no scrubber to set the time or step through a clip.

- `2026-10-05T19:13:47Z`: Related to #25 (demo viewing controls): an animation picker/scrubber is one of those controls.
- `2026-10-05T22:35:43Z`: GLTFViewer now has an Animation picker (when a model has more than one clip) and a scrubber slider with the current time; dragging the slider pauses at that time, choosing a clip restarts it from 0 keeping play/pause, and the three.js comparison follows the selected clip. No automated test: this is SwiftUI view state in the demo with no unit-testable logic; verified by building the demo and running GLTFViewerSupport's tests.

---

## 46: KHR_materials_transmission and KHR_materials_volume are not supported

+++
status: closed
priority: medium
kind: feature
labels: area:extensions, area:rendering, effort:l
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T19:30:26Z
closed: 2026-10-05T19:30:26Z
+++

Transmissive (glass-like) materials render as opaque surfaces in their base colour, and volume thickness/attenuation is ignored. Example: the pawn heads in ABeautifulGame (Pawn_Top_White / Pawn_Top_Black: transmissionFactor 1, thicknessFactor 0.22, attenuationColor 0.8) are opaque pastel spheres instead of tinted glass as in three.js. Also TransmissionTest, TransmissionRoughnessTest, DragonAttenuation. Split from #10.

- `2026-10-05T19:13:47Z`: Related to #47 (IOR) and #53 (dispersion, depends on this).
- `2026-10-05T19:30:26Z`: Transmission + volume using the environment fallback the spec allows: transmitted light is sampled from the IBL specular cube along the refracted ray (IOR 1.5; roughness adjusted for IOR), tinted by Beer-Lambert attenuation over thickness (thicknessFactor × texture.g × model scale), and replaces the diffuse lobe by transmissionFactor (× texture.r). Tests: readsTransmissionAndVolume, transmittedLightIsAttenuated (failed before: rendered opaque white). LightsPunctualLamp golden re-recorded (its shade uses transmission; checked against the Khronos screenshot — now translucent grey like the reference instead of opaque pink). ABeautifulGame pawns now render as dark glass. Limitation: the scene behind a transmissive surface is not visible (no screen-space transmission) — filed as a follow-up.

---

## 47: KHR_materials_ior is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:xs
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T20:21:56Z
closed: 2026-10-05T20:21:56Z
+++

The index of refraction is fixed at 1.5 (F0 = 0.04 for dielectrics). Materials that set KHR_materials_ior get the wrong Fresnel reflectance. Split from #10.

- `2026-10-05T19:13:47Z`: Related to #46: transmission refraction uses the IOR, so this is a cheap first step.
- `2026-10-05T20:21:56Z`: Material IOR (default 1.5) sets dielectric F0 = ((n-1)/(n+1))² and drives transmission refraction and roughness. Test indexOfRefractionSetsReflectance fails before (IOR not read; black IOR-1 dielectric reflected) and passes after. Reference PSNR: CompareDispersion +3.4, CompareIor +1.9, DragonDispersion +0.6, IORTestGrid +0.3; SunglassesKhronos -2.4 (its IOR-1 lenses lost their accidental 0.04 reflection; three.js shows them via iridescence, #51), TransmissionRoughnessTest -1.2 and DispersionTest -0.5 (environment transmission, #56). Goldens unchanged.

---

## 48: KHR_materials_specular is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:s
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T20:24:17Z
closed: 2026-10-05T20:24:17Z
+++

specularFactor, specularTexture, specularColorFactor and specularColorTexture are ignored, so dielectric specular strength and tint are always the default. Split from #10.

- `2026-10-05T20:24:17Z`: KHR_materials_specular: dielectric F0 = min(F0(IOR) × specularColor (factor × sRGB texture), 1); specular strength = specularFactor × texture alpha scales the dielectric specular lobes (direct and IBL), and diffuse keeps the remainder; metals unaffected. Test specularFactorScalesReflectance fails before (black dielectric with specularFactor 0 still reflected) and passes after. Reference PSNR: 8 scenes improved, none regressed (CompareSpecular +8.0, SpecularSilkPouf +6.9, SpecularTest +4.2, ChairDamaskPurplegold +2.4). Goldens unchanged.

---

## 49: KHR_materials_clearcoat is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:m
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T21:17:43Z
closed: 2026-10-05T21:17:43Z
+++

Clearcoat layers (car paint, varnish) are ignored; materials render without the second specular lobe. Example: ClearCoatTest, ClearcoatWicker, CarConcept. Split from #10.

- `2026-10-05T21:17:43Z`: Implemented KHR_materials_clearcoat as in three.js: F0 0.04 GGX layer (own roughness, clamped ≥0.0525; geometric normal unless clearcoatNormalTexture) for punctual lights and IBL (split-sum), AO-occluded, layered with color*(1 − clearcoat·Fcc). The three clearcoat textures share one sampler (Metal's 16-sampler limit). Tests: readsClearcoat, clearcoatDefaultsToOff. Reference PSNR: ClearcoatWicker +7.3, PotOfCoals +6.1, CompareClearcoat +5.3, ClearCoatCarPaint +5.2, PotOfCoalsAnimationPointer +3.9; no regressions.

---

## 50: KHR_materials_sheen is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:m
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T21:15:21Z
closed: 2026-10-05T21:15:21Z
+++

Sheen (cloth, velvet) is ignored. Examples: SheenChair, SheenWoodLeatherSofa, SheenCloth. Split from #10.

- `2026-10-05T21:15:21Z`: Implemented KHR_materials_sheen as in three.js: Charlie distribution + Neubelt visibility for punctual lights, fitted IBL sheen term (scaled for our irradiance/π map, occluded by AO), and albedo-scaling energy compensation (1 − 0.157·max(sheenColor)). Extension type declared locally. Tests: readsSheen, sheenDefaultsToOff. Reference PSNR: GlamVelvetSofa 24.4→37.0, ChairDamaskPurplegold 24.8→34.6, CompareSheen 30.6→37.1; no regressions.

---

## 51: KHR_materials_iridescence is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:m
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T20:55:43Z
closed: 2026-10-05T20:55:43Z
+++

Thin-film iridescence is ignored. Examples: IridescenceLamp, IridescentDishWithOlives. Split from #10.

- `2026-10-05T20:21:56Z`: SunglassesKhronos lenses (IOR 1, transmission + iridescence) render nearly black since #47 made IOR-1 dielectrics reflect nothing; three.js shows them as blue thin-film mirrors. Reference PSNR 21.1 dB.
- `2026-10-05T20:55:43Z`: Implemented KHR_materials_iridescence (thin-film Fresnel ported from three.js evalIridescence; mixes into punctual Fresnel and, via Schlick-to-F0, into IBL/multi-scatter). Extension type declared locally (KHRMaterialsIridescence.swift) since SwiftGLTF lacks it. Tests: readsIridescence, iridescenceDefaultsToOff. Reference PSNR: CompareIridescence 22.0→32.9, SunglassesKhronos 21.0→27.7, IridescenceSuzanne +2.6, IridescenceLamp +2.3; no regressions.

---

## 52: KHR_materials_anisotropy is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:m
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T20:59:02Z
closed: 2026-10-05T20:59:02Z
+++

Anisotropic specular highlights (brushed metal) are ignored. Examples: AnisotropyBarnLamp, AnisotropyDiscTest. Split from #10.

- `2026-10-05T19:53:42Z`: AnisotropyStrengthTest scores below 20 dB against three.js (ReferencePSNR.json); three.js renders anisotropic highlights, ours does not.
- `2026-10-05T20:59:02Z`: Implemented KHR_materials_anisotropy as in three.js: anisotropic GGX distribution + correlated visibility for punctual lights, bent normal for IBL; strength/rotation/texture (rg direction, b strength). Extension type declared locally (KHRMaterialsAnisotropy.swift). Tests: readsAnisotropy, anisotropyDefaultsToOff. Reference PSNR: AnisotropyBarnLamp 23.4→32.7, CompareAnisotropy 22.8→28.6, AnisotropyRotationTest +4.3, AnisotropyDiscTest +3.8, AnisotropyStrengthTest +1.3; no regressions.

---

## 53: KHR_materials_dispersion is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:s
depends: 46
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T21:20:27Z
closed: 2026-10-05T21:20:27Z
+++

Dispersion (wavelength-dependent refraction) is ignored. Depends on transmission support. Example: DispersionTest. Split from #10.

- `2026-10-05T21:20:27Z`: Implemented KHR_materials_dispersion as in three.js: with dispersion > 0 each color channel refracts with IOR ± (ior−1)·0.025·dispersion (scene or environment transmission). Test: readsDispersion. Reference PSNR unchanged (≤0.1 dB) for DragonDispersion/DispersionTest/CompareDispersion: at the suite's size the gap is dominated by three.js's geometry-roughness blur on the transmission, not dispersion.

---

## 54: KHR_materials_variants is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:s
created: 2026-10-05T19:12:12Z
updated: 2026-10-05T22:41:29Z
closed: 2026-10-05T22:41:29Z
+++

Material variants are ignored; the default material mapping is always used and there is no API to select a variant. Examples: MaterialsVariantsShoe, GlamVelvetSofa. Split from #10.

- `2026-10-05T22:41:29Z`: Implemented KHR_materials_variants: GLTFAsset.variantNames lists the document's variants, and GLTFAsset(url:variant:) / init(container:variant:) uses each primitive's mapped material for that variant (unmapped primitives keep their default). Primitive.variantMaterials holds the mappings. Extension types declared locally (KHRMaterialsVariants.swift). Test: appliesMaterialVariants (didn't compile before: no variant API). Limitation: switching variants means loading the asset again; ms-gltf-render and GLTFViewer don't expose a variant choice yet.

---

## 55: GLTFViewer: open arbitrary glTF/GLB files

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:m
created: 2026-10-05T19:12:45Z
updated: 2026-10-05T19:24:26Z
closed: 2026-10-05T19:24:26Z
+++

The demo can only show the Khronos sample models. There is no way to open a local .glb or .gltf file.

Wanted: a toolbar button that opens a file importer for .glb and .gltf.

Sandbox problem: a .gltf usually references sibling files (.bin buffers, textures) by relative URI. The file importer grants access only to the selected file, so those resources fail to load under the App Sandbox. .glb files and .gltf files with embedded data URIs work with single-file access.

Options to consider:
- Ask for the containing folder (folder picker) when a .gltf references external files, and use that security-scoped access for all resources.
- Let the user pick the folder up front and choose the .gltf inside it.
- Use NSFileCoordinator / related-items access (NSIsRelatedItemType) if it covers .bin/.png siblings.

- `2026-10-05T19:24:26Z`: Open… button (sidebar toolbar and the download prompt) with a .glb/.gltf importer. Self-contained files (.glb, or .gltf with only data URIs) open with single-file access; a .gltf referencing external buffers/images triggers a second folder importer (defaulting to the file's folder, with an explanation) and loads under the folder's security scope. Access is held while the file is shown (the three.js reference reads it later). Opened files use the same viewer (comparison, background, animation). Test: folderAccessOnlyForExternalResources. Not exercised interactively: the picker and sandbox flow (no UI driving).

---

## 56: Transmissive surfaces do not show the scene behind them

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, area:extensions, effort:l
created: 2026-10-05T19:30:26Z
updated: 2026-10-05T20:50:43Z
closed: 2026-10-05T20:50:43Z
+++

KHR_materials_transmission is implemented with the environment fallback: refracted rays sample the IBL environment, so objects behind a glass surface are not visible through it. three.js and the Khronos sample viewer render the opaque scene to a texture first and refract through it (e.g. the ABeautifulGame pawn heads show the board behind them). Doing that needs a separate opaque render pass before the main pass, which GLTFRenderer (an element placed inside a caller RenderPass) cannot currently set up. Follow-up to #46.

- `2026-10-05T19:53:42Z`: Low PSNR against three.js (ReferencePSNR.json) from transmission differences: GlassHurricaneCandleHolder 17.8 dB, GlassBrokenWindow 18.0, CompareTransmission 18.5, CompareVolume (< 20). three.js shows the scene behind the glass; ours shows the environment.
- `2026-10-05T20:50:43Z`: Added GLTFTransmissionTarget + GLTFTransmissionPass (renders non-transmissive primitives to a linear HDR rgba16Float target, then mipmaps it) and GLTFRenderer(transmissionTarget:), which samples it at the projected refracted exit point (LOD by roughness), falling back to environment refraction when nil. Wired into ms-gltf-render, the demo, and reference tests (only when asset.hasTransmission). Tests: MaterialTests.transmissionShowsSceneBehind / transmissionFallsBackToEnvironment. Reference PSNR: 23 glass scenes up (GlassHurricaneCandleHolder 17.9→26.8, AttenuationTest 24.1→33.7, USDShaderBall 23.8→33.0); 4 small drops ≤0.9 dB (ChronographWatch, ABeautifulGame, CommercialRefrigerator, IORTestGrid) accepted.

---

## 57: Compare renders against three.js reference images

+++
status: closed
priority: medium
kind: task
labels: area:testing, effort:m
created: 2026-10-05T19:33:13Z
updated: 2026-10-05T19:49:04Z
closed: 2026-10-05T19:49:04Z
+++

Golden-image tests only compare GLTFRenderer against its own earlier output. Nothing checks parity with an established renderer, so differences like #32 (spot lights), #33 (rough metals) or the pre-#1 ambient were found by eye.

Wanted: reference images rendered by three.js for the same models, camera, size and lighting, compared with GLTFRenderer output.

The CLI can already produce them: `ms-gltf-render <model> --web` writes `<name>-web.png` next to the Metal render using the same view, projection and GLTFLighting. GLTFWebReference can also render them inside a test.

Open points:
- The renderers legitimately differ (screen-space vs environment transmission #56, multi-scatter energy #33, tone mapping details), so an exact match is impossible. Needs a per-model PSNR threshold, or recorded scores that flag regressions.
- three.js comes from a CDN (#44), so tests or generation need network access, or the reference images are generated once and stored.

- `2026-10-05T19:49:04Z`: ReferenceComparisonTests renders every binary Khronos sample (128×128, auto-framed, default lighting) with GLTFRenderer and the three.js reference (matched lighting, same camera) and records the PSNR per scene in Tests/MetalSprocketsGLTFTests/ReferencePSNR.json (120 scenes). A scene fails if it drops more than 0.5 dB below its recorded value; RECORD_REFERENCE_PSNR=1 re-records. Needs network (three.js CDN, #44). Median 26.6 dB. Worst scenes to investigate: SimpleInstancing 13.4, BoxVertexColors 15.6, RecursiveSkeletons 15.7, MultiUVTest 15.9, NodePerformanceTest 16.4, LightVisibility 16.8 (#35), SpecGlossVsMetalRough 17.4, GlassHurricaneCandleHolder 17.8, GlassBrokenWindow 18.0, TextureLinearInterpolationTest 18.0, BoxInterleaved 18.2, CompareTransmission 18.5 (#56).

---

## 58: Some PNG textures render with the wrong colours

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:s
created: 2026-10-05T19:53:42Z
updated: 2026-10-05T20:03:55Z
closed: 2026-10-05T20:03:55Z
+++

Textures from PNGs that are not 8-bit RGBA render with wrong colours compared with three.js:

- BoxTextured and BoxTexturedNonPowerOfTwo (palette PNG, metallicFactor 0): the base colour texture looks washed out (lighter, less saturated) in GLTFRenderer.
- TextureLinearInterpolationTest (a 2×1 RGB PNG and a 512×256 grey + alpha PNG used as emissive / base colour): quads that are white in three.js render yellow in GLTFRenderer.

All three have low PSNR against three.js in ReferencePSNR.json (each below 20 dB). 8-bit RGBA PNGs (e.g. MultiUVTest, DamagedHelmet) look right.

Repro: ms-gltf-render .sample-assets/Models/BoxTextured/glTF-Binary/BoxTextured.glb --web, and compare the halves of BoxTextured-compare.png.

Cause not yet investigated. These formats go through MTKTextureLoader and, when it refuses them, the RGBA8 redraw fallback in GLTFTextureCache.

- `2026-10-05T20:03:55Z`: Yes, sRGB: MTKTextureLoader picks the texture format from the image, so palette PNGs (BoxTextured) came out rgba8Unorm (sRGB texels sampled as linear: washed out) and grey+alpha PNGs (TextureLinearInterpolationTest) came out rg8Unorm_srgb (grey in red, alpha in green: yellow). Now MTKTextureLoader's result is used only if it is four-channel with the requested color space; otherwise the image is redrawn to straight-alpha RGBA8 and uploaded with an explicit format, with blit-generated mipmaps. Test TextureDecodingTests fails before (wrong formats; texels off by 159 on average) and passes after. Reference PSNR re-recorded: BoxTextured 19.6 → 28.9 dB, TextureLinearInterpolationTest 18.0 → 33.1, 14 other scenes +0.6…+6.1, no regressions. Goldens unchanged.

---

## 59: KHR_materials_pbrSpecularGlossiness is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, area:rendering, effort:m
created: 2026-10-05T19:53:42Z
updated: 2026-10-05T22:44:14Z
closed: 2026-10-05T22:44:14Z
+++

Materials that use only the (archived) KHR_materials_pbrSpecularGlossiness extension fall back to the default metallic-roughness material. Example: the left bottle in SpecGlossVsMetalRough (17.4 dB against three.js in ReferencePSNR.json).

- `2026-10-05T22:44:14Z`: Implemented KHR_materials_pbrSpecularGlossiness by mapping it onto the existing model: diffuse(Factor/Texture) → base color with metallic 0; specularFactor / 0.04 → KHR_materials_specular's specularColor (texture → specularColor slot, sRGB); the shader derives roughness = 1 − glossinessFactor × specularGlossinessTexture.a when the material is spec-gloss. Extension type declared locally. Test: readsSpecularGlossiness (didn't compile before). Reference PSNR for SpecGlossVsMetalRough re-recorded 33 → 14: three.js removed spec-gloss support (r147) and renders the bottle white; ours matches the Khronos screenshot (spec-gloss bottle looks like the metal-rough one).

---

## 60: NodePerformanceTest scene is slow to load and render

+++
status: closed
priority: medium
kind: enhancement
labels: area:performance, effort:m
created: 2026-10-05T19:58:45Z
updated: 2026-10-06T01:25:38Z
closed: 2026-10-06T01:25:38Z
+++

NodePerformanceTest is a Khronos performance test: a flat hierarchy of 10,000 nodes, each referencing its own mesh with one primitive and its own material (10,000 nodes, meshes, primitives and materials; 39,993 accessors).

GLTFAsset builds 10,000 separate vertex/index buffers and material resources, and GLTFRenderer issues one draw call (with its own parameter bindings) per primitive, because no two instances share a primitive and material and so nothing can be batched (#17 only merges shared meshes). Load time and per-frame CPU encoding time scale with the node count.

Not yet measured: load time, CPU encode time per frame and GPU time per frame for this scene.

- `2026-10-06T00:34:29Z`: Measured (Release, M5 Max, 1024², ms-gltf-render --benchmark, MetalSprockets main + argument-buffer materials): load 0.7 s; per frame CPU 2010 ms, GPU 6.3 ms for 10,000 draws (~200 µs CPU per draw, almost all MetalSprockets element reconciliation and binding). The scene's 10,000 materials are all distinct (own baseColor texture, own roughness) and its 10,000 meshes are distinct, all with NORMAL/POSITION/TEXCOORD_0, so batching by mesh or material cannot reduce the draw count. Fix needs either far cheaper per-draw cost in MetalSprockets (#479/#476 there) or a GPU-driven path: merge static primitives into shared vertex/index buffers and draw them with few calls, each instance indexing its material's argument buffer.
- `2026-10-06T01:03:41Z`: Experiment: static opaque triangle primitives (not skinned, morphed, transmissive or blended) are merged at load into shared vertex/index/instance buffers, with per-record material uniforms and material argument buffers; at rest one Draw element issues one Metal draw per record, and the fragment shader looks up the record's material (vertex_merged / fragment_merged). Posed frames still draw batches individually. NodePerformanceTest CPU per frame 2010 → 8.2 ms (load 0.7 → 0.5 s); ABeautifulGame 5.8 → 2.8 ms; renders pixel-identical; all tests pass.
- `2026-10-06T01:25:38Z`: Fixed by drawing static opaque geometry from merged buffers (8023a6c3 plus this change): static, opaque, unskinned, unmorphed, non-transmissive triangle primitives share merged vertex/index/instance buffers, one Draw element issues a Metal draw per primitive, and the shader looks up each primitive's material. Posed frames supply per-frame instance matrices and animated material overrides to the merged path; a pose that mirrors an instance away from its rest winding falls back to per-batch drawing for that frame. NodePerformanceTest CPU per frame 2010 → ~8 ms; ABeautifulGame 5.8 → 2.8 ms. Tests: mergedGeometryFollowsThePose, mergedGeometryFallsBackWhenMirrored.

---

## 61: GLTFShaders.shared() races when first used from several threads

+++
status: closed
priority: high
kind: bug
labels: area:rendering, effort:xs
created: 2026-10-05T20:17:45Z
updated: 2026-10-05T20:20:32Z
closed: 2026-10-05T20:20:32Z
+++

GLTFShaders.shared() caches the shader functions and shared resources in a nonisolated(unsafe) static var without synchronisation. When two threads render a GLTFRenderer for the first time concurrently, both write the cache and one can copy a partially written value.

Seen in the test suite (parallel suites, RECORD_REFERENCE_PSNR=1 run): the test process died with SIGTRAP (EXC_BREAKPOINT) in swift_unknownObjectRetain, called from "outlined init with copy of GLTFShaders" in GLTFRenderer.content().

Any app that renders from more than one thread can hit it.

- `2026-10-05T20:20:32Z`: The cache is now a static let holding Result { try make() }, which Swift initialises once and thread-safely. No dedicated test: the race needs two threads to hit first use simultaneously and isn't reliably reproducible without Thread Sanitizer; the parallel test suite that crashed (RECORD_REFERENCE_PSNR=1 run) now passes, plus three normal runs.

---

## 62: Reference PSNR includes anti-aliasing differences

+++
status: closed
priority: medium
kind: bug
labels: area:testing, area:demo, effort:xs
created: 2026-10-05T20:37:04Z
updated: 2026-10-05T20:39:16Z
closed: 2026-10-05T20:39:16Z
+++

The three.js reference renders with WebGL antialiasing (multisampling) while GLTFRenderer output (OffscreenRenderer, the CLI, the demo by default) is single-sampled. Edges therefore differ in every scene, and the reference PSNR mixes edge aliasing into what is meant to measure shading parity. Busy scenes with many small objects are hit hardest: in MetalRoughSpheresNoTextures the sphere centres match within a few percent but the scene scores 22.9 dB.

- `2026-10-05T20:39:16Z`: GLTFWebReference(antialias:) defaults to false (page query ?antialias=), matching GLTFRenderer's single-sampled output. Reference PSNR re-recorded: median 27.8 → 32.1 dB, 94 scenes up, none down; NodePerformanceTest 16.3 → 39.9 (it was aliasing, not lighting), skinned/animated characters +12…+20 dB. The remaining low scenes are all unsupported extensions (transmission #56, iridescence #51, anisotropy #52, dispersion #53). No dedicated test: the reference suite itself shows the effect.

---

## 63: Reference PSNR includes texture-filtering differences

+++
status: closed
priority: medium
kind: bug
labels: area:testing, effort:xs
created: 2026-10-05T21:03:46Z
updated: 2026-10-05T21:04:34Z
closed: 2026-10-05T21:04:34Z
+++

GLTFRenderer samples mipmapped textures with 8x anisotropic filtering, but the three.js reference leaves GLTFLoader's default anisotropy of 1. At grazing angles three.js textures are blurrier than ours (fine 'brick' pattern on the LightsPunctualLamp shade, sharper brushed streaks on AnisotropyBarnLamp), so the reference PSNR counts a filtering-quality difference as a rendering error.

- `2026-10-05T21:04:35Z`: The three.js reference sets anisotropy 8 on mipmapped textures, matching GLTFRenderer's samplers. Reference PSNR re-recorded: median 32.85 → 33.45, 51 scenes up (CesiumMilkTruck +10.1, TextureLinearInterpolationTest +11.1), 3 small drops ≤0.9 dB.

---

## 64: Glass does not show the far side of double-sided transmissive objects

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:s
created: 2026-10-05T21:11:04Z
updated: 2026-10-05T21:11:09Z
closed: 2026-10-05T21:11:09Z
+++

The transmission pre-pass leaves out every transmissive primitive. three.js also renders the back faces of double-sided transmissive objects into its transmission target (seeing the opaque scene), so looking through a glass shade or bottle you see its lit inner wall. In LightsPunctualLamp the shade's inside, lit by the lamp's point lights, is missing: ours shows the bulb and stand glowing through instead (light-0-only comparison 25.5 dB).

- `2026-10-05T21:11:09Z`: GLTFTransmissionPass now copies the opaque result to a mipmapped backdrop, then renders back faces of double-sided transmissive primitives into the target (sampling the backdrop), then mipmaps, as three.js does. Test: MaterialTests.transmissionShowsTransmissiveBackFacesBehind (fails without the stage). LightsPunctualLamp light-0-only 25.5 → 28.3 dB, full scene at 512px 27.4 → 27.9; suite: TransmissionTest +0.6, no other changes ≥0.3 dB.

---

## 65: Reference comparison test intermittently fails with a WebKit JavaScript result error

+++
status: closed
priority: low
kind: bug
labels: area:testing, effort:s
created: 2026-10-05T21:15:25Z
updated: 2026-10-05T21:57:49Z
closed: 2026-10-05T21:57:49Z
+++

One RECORD_REFERENCE_PSNR=1 run of ReferenceComparisonTests failed 27 issues with 'Error Domain=WKErrorDomain Code=5 "JavaScript execution returned a result of an unsupported type"'. An immediate rerun with no code changes passed and recorded all 120 scenes. Seen once so far (after adding KHR_materials_sheen); cause unknown.

- `2026-10-05T21:57:49Z`: Cause: WebKit killed the reference page's WebContent process mid-suite (confirmed by a webViewWebContentProcessDidTerminate log in a failing run; the in-flight call surfaces as the misleading Code=5 error, then every later call fails). Likely trigger (unverified): the page never disposed old models' geometry/textures or replaced PMREM environments, so GPU memory grew across 120 models. Fixes: index.html disposes the previous model and environment; GLTFWebReference observes termination, reloads the page, restores fixed size/background, resends the environment, and exposes terminationCount; ReferenceComparisonTests retries a scene once after a termination. Test: WebReferenceTests.recoversFromContentProcessTermination (SIGKILLs the WebContent process via the _webProcessIdentifier SPI; _killWebContentProcess does not report terminations). 6 targeted runs before the fix: 1 failure; full suite passes after.

---

## 66: Specular aliasing differs from three.js on small or highly curved geometry

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:xs
created: 2026-10-05T21:22:39Z
updated: 2026-10-05T21:22:45Z
closed: 2026-10-05T21:22:45Z
+++

three.js raises every material's roughness by a geometry-roughness term (the screen-space change of the vertex normal) and uses a minimum roughness of 0.0525; GLTFRenderer uses the material roughness as-is (minimum 0.03). On small or dense meshes three.js reflections and transmission are softer: DragonDispersion's smooth dragon looks frosted in three.js but shows a sharp refracted checkerboard in ours (25.8 dB), and LightsPunctualLamp scores 23.0 dB.

- `2026-10-05T21:22:45Z`: Base and clearcoat roughness now = min(max(roughness, 0.0525) + geometryRoughness, 1) with geometryRoughness = max component of max(|dFdx(n)|, |dFdy(n)|), as in three.js. Reference PSNR: median 34.45 → 36.1, 66 scenes up (LightsPunctualLamp 23.0→35.2, PlaysetLightTest +15.7, SunglassesKhronos +9.6, DragonDispersion +8.3, DirectionalLight +7.8), 7 down (WaterBottle −2.2, CompareSheen −1.7, Avocado −1.1, others ≤0.8). Re-recorded 5 goldens (DamagedHelmet, LightsPunctualLamp, MetalRoughSpheres, NormalTangentMirrorTest, TextureEncodingTest); the change moves them toward three.js. No dedicated unit test: the effect is screen-space and covered by the reference suite and goldens.

---

## 67: Unlit materials skip exposure and tone mapping

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:xs
created: 2026-10-05T21:25:49Z
updated: 2026-10-05T21:25:54Z
closed: 2026-10-05T21:25:54Z
+++

KHR_materials_unlit primitives return their base color directly, without exposure or PBR Neutral tone mapping. three.js (and the Khronos sample viewer) tone map unlit materials like lit ones, so saturated unlit colors look more saturated and darker-edged in ours: UnlitTest scores 28.1 dB against three.js.

- `2026-10-05T21:25:54Z`: Unlit output now applies exposure and toneMapPBRNeutral (or stays linear in the transmission pre-pass). Test: unlitColorsAreToneMapped (failed with (255,0,0) before). rendersTriangle's green/blue bound relaxed 30→50 for tone-mapped red. Reference PSNR: UnlitTest 28.1→59.2, plus small gains elsewhere; no regressions. UnlitTest golden re-recorded.

---

## 68: Rough environment reflections differ from three.js

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:m, parked
created: 2026-10-05T21:27:45Z
updated: 2026-10-06T06:18:51Z
closed: 2026-10-06T06:18:51Z
+++

For fully rough materials our environment reflections are dimmer on faces pointing at bright parts of the environment than three.js's: BoxInterleaved (metallic 1, roughness 1) top face is (238,23,24) in ours vs (250,97,97) in three.js, scoring 25.8 dB. three.js bends the reflection vector toward the normal by roughness² and samples its own PMREM, whose blur per roughness differs from our GGX prefilter. Adopting only the bent reflection fixed the box (+13 dB) but made 62 other scenes worse (median −0.5 dB), so matching would need both the bend and three.js's PMREM roughness-to-blur mapping.

- `2026-10-05T21:34:46Z`: Trade-off: our GGX importance-sampled prefilter is the physically standard approach; three.js's PMREM blur plus reflection bending is a faster approximation. Matching it would make us more like three.js, not more correct — the first parity change that could make renders worse by an absolute standard. Parked: only worth doing if three.js parity is the explicit goal over correctness.
- `2026-10-06T06:18:51Z`: Won't fix: keeping our GGX importance-sampled prefilter rather than matching three.js's PMREM blur and reflection bending. The difference (rough surfaces facing bright parts of the environment, e.g. Box, OrientationTest) is an approximation gap in the reference, not an error here.

---

## 69: Rendering performance is poor in the GLTFViewer demo (ABeautifulGame / chess)

+++
status: closed
priority: high
kind: bug
labels: area:performance, effort:m
created: 2026-10-05T22:18:15Z
updated: 2026-10-05T23:56:32Z
closed: 2026-10-05T23:56:32Z
+++

User reports terrible rendering performance; GPU trace at /Users/schwa/Desktop/Chess.gputrace (5 frames, Apple M5 Max). The GPU is not the bottleneck: per frame the main pass takes ~0.86 ms and the transmission pre-pass ~0.55 ms (frag GLTFPBR::fragment_main dominates), ~1.4 ms total. The trace points at CPU-side overhead instead: ~1080 API calls per frame for 28 draws — every draw rebinds all textures and samplers (~350 setTexture, ~270 setSamplerState, ~160 setAddress per frame) even when consecutive draws share a material, and ~11 argument tables are created per frame (newArgumentTableWithDescriptor ×56 over 5 frames). Where the CPU frame time actually goes (element-tree rebuild, pose/joint/sort work, binding, argument-table allocation in MetalSprockets) has not been measured yet; needs a CPU profile.

- `2026-10-05T22:22:01Z`: Reference trace stays at /Users/schwa/Desktop/Chess.gputrace until this issue is resolved. See also #70 (no ResourceCollection). A Time Profiler capture from the user is coming.
- `2026-10-05T22:24:52Z`: Time Profiler (/Users/schwa/Desktop/Chess.trace, Release GLTFViewer, 7.7 s): ~74% of main-thread time is in MetalSprockets' isEqualStructurally / isEqualStoredProperty (Support/isEqual.swift), called from System.shouldUpdateNode during TreeReconciler.processElement. Self time is dominated by Swift runtime reflection (protocol-conformance lookups, tryCast, metadata demangling, Mirror). isEqual on a container element compares all stored properties, including its content subtree, by reflection; every container node does this, so cost grows roughly quadratically with nesting depth. GLTFRenderer wraps each of ~28 draws in a chain of ~45 nested .parameter modifiers, which is close to the worst case. MetalSprockets has no API to bind several parameters in one modifier. Root cause is in MetalSprockets reconciliation; mitigations here (fewer/shallower modifiers per draw, Equatable elements) are possible but secondary.
- `2026-10-05T22:25:17Z`: Filed upstream: MetalSprockets #479 (reconciliation compares whole subtrees by reflection — the 74% hotspot), #480 (no multi-parameter modifier). Existing MetalSprockets #476 covers per-draw argument-table rebinding.
- `2026-10-05T23:18:40Z`: Added ms-gltf-render --benchmark N (one reused OffscreenRenderer, element tree rebuilt each frame, 10 warm-up frames; prints frame/GPU/CPU median, mean, p95). Baseline with MetalSprockets main bf266f1, Release, M5 Max, ABeautifulGame 1024²: frame 29.6 ms, GPU 3.0 ms, CPU 26.6 ms median. Fox (animated) 1.6 ms CPU.
- `2026-10-05T23:24:40Z`: Material textures and samplers (17 + 17) now go through one argument buffer per material (GLTFMaterialResources, built at load), replacing 34 .parameter nodes per draw with one; the asset's ResourceCollection (#70) keeps the indirectly referenced textures resident. ABeautifulGame 1024² Release benchmark: CPU 26.6 → 7.4 ms, GPU 3.0 → 1.1 ms per frame. Goldens and reference PSNR unchanged. Experiment that motivated it: dropping 22 of ~47 per-draw parameter nodes alone cut CPU to 11.7 ms — reconciliation cost (StructuralIdentifier hashing, isEqual) scales with node count.
- `2026-10-05T23:32:01Z`: Unmorphed primitives now use vertex functions without morph arguments (new vertex_main_morphed / vertex_skinned_morphed variants for morphed ones, each in its own pipeline), so their draws no longer bind morph/morphDeltas/morphWeights; the index buffer's .useResource is dropped (the asset's ResourceCollection keeps it resident). Per-draw nodes ~13 → ~9. ABeautifulGame CPU 7.4 → 5.8 ms. Tried and reverted: Equatable batches (no measurable change) and a per-batch material uniform buffer chosen by an if/else per draw (slower, 7.0 → 8.4 ms).
- `2026-10-05T23:56:32Z`: Resolved: user reports GLTFViewer now renders the chess scene (ABeautifulGame) at 60 fps. Headless benchmark (Release, 1024²): CPU 26.6 → 5.8 ms, GPU 3.0 → ~1.1 ms per frame, via one argument buffer per material (dbb6bdc0, with a ResourceCollection, #70) and no morph bindings for unmorphed primitives (77583bb5), plus MetalSprockets main's performance work. Remaining cost is MetalSprockets reconciliation (MetalSprockets #479, #476, #480). The reference traces on the Desktop (Chess.gputrace, Chess.trace) are no longer needed.

---

## 70: Long-lived GPU resources are not in a ResourceCollection

+++
status: closed
priority: high
kind: bug
labels: area:performance, effort:s
created: 2026-10-05T22:22:01Z
updated: 2026-10-05T23:24:40Z
closed: 2026-10-05T23:24:40Z
+++

MetalSprockets' Metal 4 porting guide (Documentation/Porting-to-Metal4.md, checklist item 4) says resources that live longer than one frame must be registered in a ResourceCollection; with automatic residency each long-lived allocation is removed and re-added to the residency set every frame. Nothing in MetalSprocketsGLTF uses ResourceCollection or .useResourceCollection: mesh vertex/index buffers, instance and morph/skin buffers, material textures, environment maps, the BRDF LUT and the transmission target all rely on automatic residency. Related to #69. Reference trace: /Users/schwa/Desktop/Chess.gputrace (kept until #69 is resolved). It shows 18 useResidencySet calls over 5 frames but no addAllocation/removeAllocation calls, so the per-frame churn the guide describes is not confirmed by the capture (it may not record residency-set changes).

- `2026-10-05T23:24:40Z`: GLTFAsset now owns a ResourceCollection registering every long-lived allocation it draws with (mesh vertex/index buffers, skin and morph buffers, batch instance buffers, material textures and the new material argument buffers); GLTFRenderer attaches it with .useResourceCollection. Required now that material textures are only referenced through argument buffers (see #69). Environment textures are still bound directly and use automatic residency.

---

## 71: Web reference cannot load .gltf files with external buffers or images

+++
status: closed
priority: medium
kind: bug
labels: area:testing, area:demo, effort:s
created: 2026-10-06T01:36:22Z
updated: 2026-10-06T02:09:36Z
closed: 2026-10-06T02:09:36Z
+++

GLTFWebReference serves only the model file itself from gltfref://model/<uuid>/<name>. A .gltf that references separate .bin or image files (e.g. AnimatedCube, which has only a glTF variant) fails in three.js: those relative URLs resolve under gltfref://model/<uuid>/ and the scheme handler has no file for them, so the reference renders nothing. ms-gltf-render --web shows a black three.js image, and GLTFViewer's comparison side stays empty. Reference tests are unaffected because they only use .glb files, so these models have no reference PSNR.

- `2026-10-06T02:09:36Z`: GLTFWebReference's scheme handler now resolves gltfref://model/<id>/<path> beside the model file, so a .gltf's external buffers and images load (paths outside the model's directory are refused). Test: WebReferenceTests.loadsExternalResources (AnimatedTriangle's non-embedded .gltf; failed with nothing rendered). The reference suite now uses each model's .glb, else its plain .gltf: 120 → 150 scenes (AnimatedCube, Sponza, FlightHelmet, SciFiHelmet, Suzanne, MeshPrimitiveModes, …), baselines recorded; existing scenes unchanged.

---

## 72: Skinned meshes are slow to render

+++
status: closed
priority: high
kind: bug
labels: area:performance, effort:m
created: 2026-10-06T06:32:15Z
updated: 2026-10-06T06:38:02Z
closed: 2026-10-06T06:38:02Z
+++

Every skinned primitive is drawn by its own draw element and computes and binds its own joint matrices, so CPU time per frame grows with the skinned primitive count. In GLTFViewer BrainStem runs at ~40 fps and RecursiveSkeletons at ~30 fps on a 120 Hz display. Headless (ms-gltf-render --benchmark 60 --orbit --animation 0, Release, M5 Max): BrainStem 59 batches, 12.1 ms CPU / 0.4 ms GPU per frame; RecursiveSkeletons 84 batches, 13.5 ms CPU / 0.25 ms GPU.

- `2026-10-06T06:38:02Z`: Fixed: skinned opaque (unmorphed, non-transmissive) primitives are now merged like static ones: shared vertex, skin-vertex and index buffers, one Draw element, and one per-frame joint palette holding every skin's joint matrices with a per-record offset (vertex_skinned_merged). Headless (--benchmark 60 --orbit --animation 0): BrainStem 12.1 → 0.95 ms CPU, RecursiveSkeletons 13.5 → 1.1 ms. User confirms BrainStem now runs at 120 fps in GLTFViewer. Test: SkinningTests.mergedSkinnedMatchesPerBatchDrawing (an animated BrainStem frame renders the same merged and per-batch; GLTFRenderer.usesMergedGeometry turns merging off for it).

---

## 73: Scenes with transmission are slow to render

+++
status: closed
priority: medium
kind: bug
labels: area:performance, effort:m
created: 2026-10-06T06:32:15Z
updated: 2026-10-06T06:46:07Z
closed: 2026-10-06T06:46:07Z
+++

Transmissive primitives are never merged (each is its own draw element in the main pass and in the back-face pre-pass), and any transmissive material adds the transmission pre-passes, which rebuild the opaque scene's elements again. In GLTFViewer on a 120 Hz display: TransmissionTest ~72 fps, AttenuationTest ~80, DispersionTest ~90, CarConcept ~90 (1 transmissive material of 29), AnimationPointerUVs ~78 (9 transmissive). Headless (--benchmark 60 --orbit, Release): TransmissionTest 6.7 ms CPU, AttenuationTest 6.3, DispersionTest 5.7, CarConcept 5.3, AnimationPointerUVs 6.1 (animated); GPU under 1 ms for all.

- `2026-10-06T06:41:46Z`: Static transmissive opaque primitives are now merged into their own set: the main pass draws it, the opaque pre-pass leaves it out, and the back-face pre-pass draws its double-sided records with front faces culled. Headless (--benchmark 60 --orbit): TransmissionTest 6.7 → 3.6 ms CPU, AttenuationTest 6.3 → 3.6, DispersionTest 5.7 → 2.7, CarConcept 5.3 → 3.8, AnimationPointerUVs 6.1 → 4.8 (animated). Test: mergedTransmissionMatchesPerBatchDrawing. Left open pending a check in GLTFViewer; the remaining ~3 ms is the transmission pre-passes' fixed cost (three passes plus mipmapping), not yet profiled.
- `2026-10-06T06:46:07Z`: User-confirmed in GLTFViewer (Release, 120 Hz): TransmissionTest 72 → 120 fps, AttenuationTest 80 → 120, DispersionTest 90 → 120, CarConcept 90 → 110, AnimationPointerUVs 78 → 90. The remaining two are tracked in #75 (AnimationPointerUVs) and #76 (CarConcept).

---

## 74: NodePerformanceTest is slow to load and runs at ~10 fps in GLTFViewer

+++
status: closed
priority: medium
kind: bug
labels: area:performance, area:demo, effort:m
created: 2026-10-06T06:32:15Z
updated: 2026-10-06T06:46:50Z
closed: 2026-10-06T06:46:50Z
+++

In GLTFViewer, NodePerformanceTest (10,000 nodes, meshes and materials) takes a long time to load and then renders at ~10 fps. Headless the same scene loads in 0.5 s and takes ~9 ms CPU / ~1.5 ms GPU per frame (ms-gltf-render --benchmark 60 --orbit), so the extra cost is specific to the app. Cause not yet known; needs a profile of the app on this scene.

- `2026-10-06T06:46:50Z`: Debug-build artefact. ms-gltf-render on NodePerformanceTest: Debug loads in 1.74 s and takes ~83 ms CPU per frame (~12 fps, matching the ~10 fps seen in GLTFViewer); Release loads in 0.49 s at ~10 ms. Unoptimized Swift makes the per-record loops (10,000-record visibility check and draw loop, merging at load) much slower. User is happy to close.

---

## 75: AnimationPointerUVs runs at ~90 fps while animating

+++
status: open
priority: low
kind: bug
labels: area:performance, effort:m, deferred
created: 2026-10-06T06:46:07Z
updated: 2026-10-14T17:08:17Z
+++

In GLTFViewer (Release, 120 Hz display) AnimationPointerUVs runs at ~90 fps with its animation playing. Headless (ms-gltf-render --benchmark 60 --orbit --animation 0, Release, M5 Max): ~4.8 ms CPU, <1 ms GPU per frame. The scene has 132 primitives, 82 materials (9 transmissive, 3 blended) and animates material texture transforms through KHR_animation_pointer, so each frame also pays for the transmission pre-passes, per-batch drawing of the 3 blended primitives, and per-frame material uniform arrays for the merged sets. Not yet profiled.

- `2026-10-06T22:04:17Z`: Deferred. Bench now: AnimationPointerUVs 4.4 ms CPU per frame (Release, M5 Max), well within 120 Hz; re-measure in the app before working on it.
- `2026-10-14T17:08:17Z`: Related: #167 (material pointer strings parsed on every pose).

---

## 76: CarConcept runs at ~110 fps

+++
status: open
priority: low
kind: bug
labels: area:performance, effort:s, deferred
created: 2026-10-06T06:46:07Z
updated: 2026-10-06T22:04:17Z
+++

In GLTFViewer (Release, 120 Hz display) CarConcept runs at ~110 fps. Headless (ms-gltf-render --benchmark 60 --orbit, Release, M5 Max): ~3.8 ms CPU, <1 ms GPU per frame. 109 primitives, of which one has a transmissive material; that single material turns on the transmission pre-passes (opaque scene, back faces, mipmaps) for the whole scene. Likely the fixed cost of those passes; not yet profiled.

- `2026-10-06T22:04:17Z`: Deferred. Bench now: CarConcept 3.4 ms CPU per frame (Release, M5 Max), well within 120 Hz; re-measure in the app before working on it.

---

## 77: Animated scenes show different initial states in the Metal and three.js views

+++
status: closed
priority: low
kind: bug
labels: area:demo, area:animation, effort:xs
created: 2026-10-06T06:49:33Z
updated: 2026-10-06T18:57:57Z
closed: 2026-10-06T18:57:57Z
+++

In GLTFViewer's comparison modes, a scene with animations shows a different pose in the Metal and three.js views before playback starts. Probable cause (unconfirmed): the Metal side uses no pose (the file's rest node transforms) while the animation is stopped at time 0 (ModelDetailView.scene: 'animationStart == nil && heldAnimationTime == 0 ? nil : pose'), but the web side is always sent setAnimation(animationIndex, time: animationTime), so three.js shows the clip's first frame. A clip's first frame often differs from the rest pose.

- `2026-10-06T18:57:57Z`: Confirmed the cause in code: stopped at time 0 the Metal view drew the rest pose while three.js got setAnimation(index, time: 0). GLTFView now always draws the selected clip at the current time when the asset has animations, so before playback both show the clip's first frame (and switching clips shows the new clip's first frame). Not checked in the running app.

---

## 78: No multisample antialiasing

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, area:demo, effort:m
created: 2026-10-06T06:50:47Z
updated: 2026-10-06T19:35:32Z
closed: 2026-10-06T19:35:32Z
+++

GLTFRenderer renders single-sampled, so edges alias in GLTFViewer, ms-gltf-render and the transmission pre-pass. Nothing in the package enables MSAA, although MetalSprockets provides .msaa(sampleCount:) for render passes and RenderView's .metalSampleCount. Things it touches: pipelines must match the target's sample count; the transmission pre-pass and environment background render into the same passes; golden images and reference PSNR assume single-sampled output (the three.js reference has antialiasing off to match, #62).

- `2026-10-06T14:31:01Z`: Related: #79 (MetalFX spatial upscaling) depends on antialiased input.
- `2026-10-06T19:35:32Z`: GLTFScene.sampleCount (default 1) wraps the main pass in MetalSprockets' .msaa(sampleCount:) when rendering to a texture; pipelines take their sample count from the pass attachments, so no pipeline changes. The transmission pre-pass stays single-sampled. On screen, GLTFViewer sets RenderView's sample count (.metalSampleCount 4) from a new Antialiasing toggle in the Model tab (default on), and recreates the three.js reference with WebGL antialias to match (GLTFWebReference.antialias is now public). CLI: render --msaa N (also antialiases the --web render). Goldens and reference PSNR still single-sampled and unchanged. Tests: singleSampledEdgesAreHard / multisampledEdgesAreBlended (distinct edge values of an unlit triangle). Not checked in the running app.

---

## 79: No MetalFX spatial upscaling

+++
status: closed
priority: low
kind: feature
labels: area:rendering, area:demo, effort:m
created: 2026-10-06T06:50:47Z
updated: 2026-10-07T15:13:32Z
closed: 2026-10-07T15:13:32Z
+++

GLTFViewer always renders at the drawable's full resolution. There is no option to render at a lower internal resolution and upscale with MetalFX spatial scaling, which would cut fragment cost on large or high-DPI views (the PBR fragment shader is the main GPU cost). MetalSprockets provides a MetalFXSpatial element (input texture to output texture). It would need an offscreen render target at the reduced size, the upscale into the drawable, and a way to choose the scale; MetalFX expects antialiased input, so it interacts with MSAA (separate issue).

- `2026-10-06T14:31:01Z`: Related: #78 (MSAA) — MetalFX expects antialiased input.
- `2026-10-07T15:13:32Z`: PBRScene.upscaling (PBRUpscaling: scale, color/depth formats) draws the main pass into cached low-resolution targets (MSAA via sampleCount resolves there), upscales with MetalSprockets' MetalFXSpatial, and copies into the current target. Transmission target follows the low resolution. Viewer: Display > Render Scale (Full / 75% / 50% + MetalFX), persisted; when upscaling the view's sample count is 1 and the scene antialiases the low-res frame. CLI: --render-scale. UpscalingTests: half-scale upscaled frame matches full size (mean red diff ~3.9/255). Checked DamagedHelmet and TransmissionTest with background via the CLI. GPU savings not measured in the app.

---

## 80: Glass and liquid look pixelated in large views

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:s
created: 2026-10-06T06:58:19Z
updated: 2026-10-06T07:02:58Z
closed: 2026-10-06T07:02:58Z
+++

GLTFTransmissionTarget defaults to a fixed 1024x1024 texture whatever the view size. In a larger view (e.g. a Retina window, or ms-gltf-render at 2048x2048) transmissive surfaces sample a stretched, lower-resolution image of the scene behind them, so it looks blocky: in CompareVolume the checkerboard seen through the green liquid has stair-stepped edges. three.js sizes its transmission target to the drawing buffer and does not show this. With a 2048 target at 2048x2048 the edges are smooth.

- `2026-10-06T07:02:58Z`: GLTFTransmissionTarget(width:height:) sizes the target to the view (the square size: initializer remains). ms-gltf-render and the reference tests use their output size; GLTFViewer keeps a target matching the drawable size and recreates it when the size changes. Test: transmissionTargetMatchesViewSize. Reference PSNR re-recorded: 29 transmission scenes improved (DispersionTest 27.7 → 36.6, CompareVolume 30.5 → 37.1, CommercialRefrigerator 26.0 → 32.2, IridescenceLamp +5.9, GlassBrokenWindow +5.1), StainedGlassLamp −1.3.

---

## 81: GLTFViewer has no document inspector

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-10-06T07:03:10Z
updated: 2026-10-07T00:36:07Z
closed: 2026-10-07T00:36:07Z
+++

GLTFViewer shows only the rendered model plus a primitive and material count. There is no way to look inside the loaded glTF: its scenes and node hierarchy, meshes and primitives, materials and their extensions, textures and samplers, skins, animations, cameras and lights, the extensions used and required, and load warnings. A sidebar (inspector) listing the document's contents would help when checking why a model renders the way it does.

- `2026-10-06T14:31:01Z`: Related: #25 (GLTFViewer viewing controls) — both add UI around the render view.
- `2026-10-06T19:08:30Z`: Related: #111 (summary statistics in the Model tab).
- `2026-10-07T00:36:07Z`: GLTFViewer inspector has a Document tab: an outline (List with children) of the loaded file built by DocumentOutline: scenes (the shown one marked) with their node trees (mesh, skin, camera, light type, hidden by KHR_node_visibility; cycles and bad indices shown, not followed), meshes with primitives (mode, material, attributes, morph target count, extensions), materials (alpha mode, double-sided, extension names), textures (image, extensions, sampler), images (MIME type, embedded/URI), skins (joint count), animations with channels (path, target node, interpolation), cameras (projection, vertical FOV), lights (type, intensity, color). Empty sections are left out; rows are selectable text. Built once per asset in a task. Browsing only: selecting a node does not highlight it in the render. Viewer package now depends on SwiftGLTF directly. Tests: DocumentOutlineTests (basic shape outline; hierarchy, light and cycle handling, unique IDs). Not checked in the running app.

---

## 82: GLTFViewer sample browser cannot choose a model's file variant

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-06T14:22:48Z
updated: 2026-10-06T17:28:25Z
closed: 2026-10-06T17:28:25Z
+++

The Khronos sample index lists several file variants per model (glTF-Binary, glTF-Embedded, glTF, glTF-Quantized, glTF-Draco, glTF-Meshopt, glTF-KTX-BasisU, glTF-JPG-PNG, glTF-WEBP, ...). GLTFViewer's sample browser always picks one automatically (.glb, else embedded, else plain .gltf), so variants such as glTF-Quantized can only be viewed by downloading them by hand and using Open…. There is no way to pick a variant in the browser. Variants that need unsupported extensions (Draco and Meshopt, #8; KTX2, #36) would fail to load.

- `2026-10-06T17:28:25Z`: GLTFViewer's model view now has a Variant picker (toolbar, shown when a sample has more than one variant): it lists every file variant from the sample index, the default first, and marks those needing unsupported extensions (Draco, Meshopt: #8; KTX2: #36) as '(unsupported)' and unselectable. Choosing one downloads and caches that variant (multi-file .gltf variants with their buffers and images) and reloads the model. SampleLibrary.fileURL(for:variant:) takes the folder; the list's downloaded marker still tracks the default variant. Test: variantChoicesPutTheDefaultFirst. Not exercised in the running app (no UI driving); the download path is the one already used for multi-file models.

---

## 83: KHR_materials_diffuse_transmission is not supported

+++
status: closed
priority: high
kind: feature
labels: area:extensions, effort:m
created: 2026-10-06T14:24:50Z
updated: 2026-10-06T18:49:02Z
closed: 2026-10-06T18:49:02Z
+++

Materials using KHR_materials_diffuse_transmission (light scattering through thin, translucent surfaces such as leaves, paper or fabric) render as if the extension were absent: diffuseTransmissionFactor/Texture and diffuseTransmissionColorFactor/Texture are ignored. Sample assets: DiffuseTransmissionTest, DiffuseTransmissionPlant (and pointer targets in AnimationPointerUVs).

- `2026-10-06T18:32:52Z`: Priority by sample usage: 6 models, all default variants (AnimationPointerUVs, DiffuseTransmissionPlant, DiffuseTransmissionTeacup, DiffuseTransmissionTest, MandarinOrange, ScatteringSkull).
- `2026-10-06T18:49:02Z`: Supported per the spec's mix of diffuse BRDF and BTDF: per light, light from behind (dot(-N, L) > 0) adds diffuseTransmissionColor/pi * factor, Fresnel from the light mirrored to the front (Khronos sample viewer), and the front diffuse lobe is scaled by 1 - factor; IBL mixes in irradiance sampled at -N. Textures (factor in alpha, sRGB color), animation-pointer factors, metallic and specular transmission (which overrides it) handled; with KHR_materials_volume the transmitted color is attenuated over the thickness. Turned off for materials that also use KHR_materials_volume_scatter (ScatteringSkull went black without scattering; see #105). DiffuseTransmissionTest matches the Khronos screenshot row by row. Tests: DiffuseTransmissionTests (backlit quad dark without, red-tinted with, factor scales). three.js 0.186 lacks the extension, so reference PSNR re-recorded lower: AnimationPointerUVs 35.8->27, DiffuseTransmissionPlant 40.4->37, Teacup 38.9->23.8, Test 27.3->16.4, MandarinOrange 41.9->27.

---

## 84: KHR_materials_retroreflection is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:s
created: 2026-10-06T14:24:50Z
updated: 2026-10-07T14:24:46Z
closed: 2026-10-07T14:24:46Z
+++

Materials using KHR_materials_retroreflection (light reflected back toward its source, as on road signs) render as if the extension were absent.

- `2026-10-06T18:32:52Z`: Priority by sample usage: 1 model; stays low.
- `2026-10-07T14:24:46Z`: KHR_materials_retroreflection (Minimal Retroreflective Microfacet model, per the RC spec): weight w = retroreflectionFactor x texture R; for each light the metal/dielectric BRDF (diffuse Fresnel weighting and specular, including anisotropic and iridescent Fresnel) is also evaluated with the view reflected about the normal and blended by w; image-based specular blends toward the environment along the view direction (same split-sum terms, NdotV unchanged). Clearcoat, sheen and transmission unaffected. New uniforms retroreflectionFactor + texture slot (kPBRTextureRetroreflection), animatable factor via KHR_animation_pointer, registered as built-in. Checked on TrafficCone with only its camera-side point light: the retroreflective cone's bands glow, the control cone's do not. Tests: RetroreflectionTests (light at camera, oblique view: retro much brighter; TrafficCone loads factor and mask). three.js lacks it; TrafficCone's reference PSNR stays within tolerance under studio lighting.

---

## 85: KHR_gaussian_splatting is not supported

+++
status: open
priority: low
kind: feature
labels: area:extensions, effort:l, deferred
created: 2026-10-06T14:24:51Z
updated: 2026-10-06T18:41:39Z
+++

Primitives using KHR_gaussian_splatting (point primitives with Gaussian splat attributes) are not drawn as splats. Supporting it means a separate splat renderer (sorting, splat rasterisation), not a material change.

- `2026-10-06T14:27:42Z`: Use ../MetalSprocketsGaussianSplats (MetalSprockets-based splat framework with swappable renderers and PLY/SPLAT/SPZ/SOG loaders) for the splat rendering: decode the KHR_gaussian_splatting attributes into its splat representation and render them with one of its renderers alongside GLTFRenderer, rather than writing a splat renderer here.

---

## 86: EXT_lights_image_based is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:s
created: 2026-10-06T14:24:51Z
updated: 2026-10-07T00:07:40Z
closed: 2026-10-07T00:07:40Z
+++

Image-based lights defined by EXT_lights_image_based in a file are ignored; the renderer always uses its own GLTFEnvironment (studio, uniform or an HDR the caller supplies).

- `2026-10-06T18:32:52Z`: Priority by sample usage: 1 model; stays low.
- `2026-10-07T00:07:40Z`: EXT_lights_image_based: the scene's light is decoded at load (GLTFImageBasedLight; extension types EXTLightsImageBased / EXTLightsImageBasedScene): mip 0 of the specular cube, RGBD unpacked as Babylon writes it (rgb^2.2 / alpha; 3-channel = LDR sRGB), faces flipped vertically per the spec, resampled to a 4:2 linear equirect with the light's rotation (world direction d looks up q^-1 d) and intensity baked in. GLTFAsset.imageBasedLight / environment() (PBREnvironment built on first use, cached and shared across scene/variant copies); PBRLighting(asset:) uses it as the default environment, so the CLI and GLTFScene(asset:) pick it up. New PBREnvironment source .equirectangularPixels. The file's lower mips and SH irradiance coefficients are not used: our prefilter and convolution run on mip 0, keeping roughness mapping consistent with other environments. Checked on EnvironmentTest/glTF-IBL: upright, seamless at face edges and poles. Unverified: rotation direction (q vs q^-1); Babylon's reference screenshot differs too much in tone to tell. Viewer: Display tab 'Use File's Environment' toggle (on, persisted) shown when the model has one; the environment builds on first use on the main thread (a short stall). Tests: ImageBasedLightTests (faces on their axes, RGBD, rotation+intensity, default lighting, the sample). Not checked in the running app.

---

## 87: EXT_lights_ies is not supported

+++
status: open
priority: low
kind: feature
labels: area:extensions, effort:m, deferred
created: 2026-10-06T14:24:51Z
updated: 2026-10-07T14:10:07Z
+++

Photometric lights defined by EXT_lights_ies (IES light profiles) are ignored.

---

## 88: EXT_texture_astc is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:s
depends: 108
created: 2026-10-06T14:24:51Z
updated: 2026-10-07T14:34:52Z
closed: 2026-10-07T14:34:52Z
+++

Textures whose source is an ASTC-compressed image (EXT_texture_astc) are not loaded.

- `2026-10-06T18:59:24Z`: Plan: load the KTX2/ASTC images through BasisUniversalMetal (its issue #5, plain ASTC KTX2), as an optional extension target like KTX2/Basis (#108, #36). No sample uses this extension.
- `2026-10-06T18:59:28Z`: Correction: the BasisUniversalMetal issue is #9, not #5.
- `2026-10-07T14:34:52Z`: GLTFASTCTextureDecoder (EXT_texture_astc, in the optional MetalSprocketsGLTFBasisU target) loads the KTX2 image through BasisUniversalMetal's plain-ASTC path (its #9), with sRGB/linear chosen by material slot; registered in ms-gltf-render and GLTFViewer. Without the decoder, textures fall back to their regular source; files requiring the extension are rejected. Limitation: KTX2 files without a full mip chain get a generated chain stored uncompressed (Metal cannot generate mipmaps for ASTC), whether or not the sampler uses mipmaps; files with a full chain stay ASTC (BasisUniversalMetal's behavior, not covered by a test here since no fixture has ASTC mips). No sample model uses the extension; tests use BasisUniversalMetal's astc_6x6_srgb.ktx2: ASTCTests (loads with slot color space and mips, fallback without the decoder, required needs the decoder).
- `2026-10-07T14:41:51Z`: Verified the mip behavior with BasisUniversalMetal's fixtures through the decoder's call (colorSpace sRGB, generateMipmaps true): astc_8x8_srgb_zstd (9 levels) loads as astc_8x8_srgb with 9 levels, i.e. uploaded as-is, same block size, nothing re-encoded. Only single-level files are decoded (rgba8, generated mips), as astc_6x6_srgb (1 level) is; with generateMipmaps false it stays astc_6x6_srgb. Spec-conformant files (full chain for mipmapped samplers) therefore stay ASTC.

---

## 89: KHR_animation_pointer cannot animate lights, cameras or node visibility

+++
status: closed
priority: low
kind: enhancement
labels: area:animation, area:extensions, effort:m
created: 2026-10-06T14:24:51Z
updated: 2026-10-07T14:58:50Z
closed: 2026-10-07T14:58:50Z
+++

KHR_animation_pointer channels that target light properties (/extensions/KHR_lights_punctual/lights/N/...), camera properties (/cameras/N/...) or KHR_node_visibility (/nodes/N/extensions/KHR_node_visibility/visible) are skipped with a load warning. Only node transforms and weights and material properties animate.

- `2026-10-06T14:31:01Z`: Related: #35 (KHR_node_visibility) and #16 (KHR_animation_pointer, closed for nodes and materials).
- `2026-10-07T14:58:50Z`: KHR_animation_pointer now animates node visibility (/nodes/N/extensions/KHR_node_visibility/visible), KHR_lights_punctual light color, intensity, range and spot cone angles, and camera projection properties (perspective yfov/znear/zfar/aspectRatio, orthographic xmag/ymag/znear/zfar). PBRPose gains visibility (inherited down the hierarchy; empty when all visible), lights (posed, animated, without hidden ones) and cameraParameters. Visibility: when any clip animates it, nodes hidden at rest are loaded and the rest pose hides them; the renderer draws a hiding rest pose even without a pose, filters hidden instances in per-batch draws, collapses them in merged geometry, skips hidden skinned records; model bounds and pose bounds ignore hidden instances (keeps auto-framing and culling right). Fixed: lights on hidden nodes shone at rest. Cameras: GLTFAsset.cameras(pose:) applies animated parameters (patched copy of the SwiftGLTF camera). Fixed along the way: a batch with every instance hidden bound an empty instance array (emptyAllocation). Checked on CubeVisibility and LightVisibility (blue cube / blue light blink); no sample animates light or camera properties, so those are tested on synthetic files: PointerTargetTests (parsing, visibility load/rest/animation, render hidden vs shown, light intensity and color, camera yfov, hidden lights don't shine). Reference PSNR and goldens unchanged; bench in the usual range.

---

## 90: GLTFViewer has no KHR_materials_variants picker

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-06T14:24:51Z
updated: 2026-10-06T19:04:21Z
closed: 2026-10-06T19:04:21Z
+++

GLTFAsset supports KHR_materials_variants (variantNames, and the variant: load parameter), but GLTFViewer offers no way to choose a variant, so models such as MaterialsVariantsShoe always show their default materials.

- `2026-10-06T19:04:22Z`: GLTFViewer's Model inspector tab has a Material Variant picker (Default plus the file's variant names) when the file uses KHR_materials_variants. Switching uses the new GLTFAsset.variant(_:), which rebuilds the scene sharing the loaded meshes, materials and textures (no reload). three.js keeps the default materials (noted in the tab; follow-up filed). Test: switchesVariantWithoutReloading. Not checked in the running app; try MaterialsVariantsShoe.

---

## 91: Every caller assembles the scene by hand

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:m
created: 2026-10-06T14:30:17Z
updated: 2026-10-06T17:01:05Z
closed: 2026-10-06T17:01:05Z
+++

Drawing a model correctly needs GLTFTransmissionTarget, GLTFTransmissionPass, a RenderPass, GLTFEnvironmentBackground, GLTFRenderer and GLTFLighting(asset:pose:) wired together. Each caller (ms-gltf-render's scene(), GLTFViewer's ModelDetailView.scene(), ReferenceComparisonTests, MaterialTests) must create the transmission target only when asset.hasTransmission and at the view's size, run the pre-pass before the main pass with matching inputs, put the background in the same pass, and re-pose lights. The four copies have drifted, and getting it wrong is easy: the fixed 1024 target size of #80 was such a caller mistake. Dependencies are in-process; tests that hand-assemble pre-pass and pass would become tests of one scene element.

- `2026-10-06T14:31:01Z`: Related: #92 — a scene element would sit on top of the draw planning that #92 separates out.
- `2026-10-06T17:01:05Z`: Added GLTFScene: one element taking the asset, view/projection/model matrices, optional lighting (nil = the asset's lights, posed by the pose), pose, showsBackground and viewportSize. It keeps a transmission target matching the viewport across frames (@MSState cache), runs GLTFTransmissionPass only when the asset has transmission, and draws the background and GLTFRenderer in one RenderPass. ms-gltf-render, GLTFViewer and ReferenceComparisonTests now use it (GLTFViewer's own target cache and light posing are gone). Tests: sceneShowsWhatIsBehindGlass, transmissionTargetCacheFollowsViewportSize, sceneMatchesHandAssembly (TransmissionTest with background, identical to the hand-wired passes). Goldens, reference PSNR and benchmarks unchanged. The lower-level MaterialTests that compare merged vs per-batch transmission still assemble passes by hand on purpose.

---

## 92: GLTFRenderer mixes draw planning with element building

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:l
created: 2026-10-06T14:30:17Z
updated: 2026-10-06T17:13:30Z
closed: 2026-10-06T17:13:30Z
+++

GLTFRenderer.content() decides each frame which batches go through which merged set (static, transmissive, skinned) or per-batch pipeline, depending on the transmission pre-pass stage, the pose, the mirroring fallback, frustum culling and blend order, and builds the elements in the same function. The merged pipelines duplicate their draw loops, and GLTFTransmissionPass works by setting internal flags (prePassStage, usesMergedGeometry) on copies of the renderer. Path selection can only be tested indirectly by comparing rendered images (mergedSkinnedMatchesPerBatchDrawing, mergedTransmissionMatchesPerBatchDrawing). Dependencies are in-process.

- `2026-10-06T14:31:01Z`: Related: #91 (scene assembly) and #94 (asset initializer); GLTFTransmissionPass currently configures the renderer through internal flags.
- `2026-10-06T17:13:30Z`: Draw planning moved out of GLTFRenderer into GLTFDrawPlan: a pure value built from the asset, pose, transmission pre-pass stage, camera, model matrix and the merging switch. It holds the merged static, transmissive and skinned draws (posed instances, animated materials, per-record visibility, back-face mode, joint palette), the per-batch opaque groups by vertex variant, and the back-to-front blended runs. GLTFRenderer.content() now builds frame bindings and turns the plan into elements; the two merged pipelines share one draw loop (mergedDrawCalls). VertexVariant and BlendedRun moved with the plan. Tests: DrawPlanTests (merging and the merging switch, posed instances and the mirroring fallback, culling, transmission stage selection, blended run order). Goldens, reference PSNR, the merged-vs-per-batch image tests and benchmarks (ABeautifulGame 2.8 ms, TransmissionTest 3.6, BrainStem 1.0 CPU) unchanged. GLTFTransmissionPass still selects stages by setting prePassStage on renderer copies; that flag now feeds the plan.
- `2026-10-06T17:14:17Z`: Correction: benchmarks after this change measured ABeautifulGame 2.3 ms, TransmissionTest 3.2 ms, BrainStem 0.9 ms CPU (--benchmark 60 --orbit, Release), slightly faster than before (2.7, 3.6, 0.95), not unchanged.

---

## 93: A material feature is spread over many places

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:m
created: 2026-10-06T14:30:17Z
updated: 2026-10-06T17:09:11Z
closed: 2026-10-06T17:09:11Z
+++

Each material texture slot is listed separately in GLTFMaterialResource's binding code, its textureBindings and resource-buffer order (which must match GLTFMaterialTextureIndex in GLTFShaderTypes.h), the KHR_animation_pointer path list (textureSources) and set (texturePaths), the texture preload list, and the PBR shader's texture locals; factors are similarly split between the extension structs, the uniform struct and the animatable-factor table. Adding an extension touches six or seven places, and a mismatch fails silently as a wrong texture. Dependencies are in-process plus the CPU/GPU layout contract; the per-extension 'reads X' tests could become one table-driven consistency test.

- `2026-10-06T17:09:11Z`: Material textures are now described once, in GLTFMaterialTextureSlot.all (shader index, uniform slot, sRGB, every animation-pointer path that can supply it, and which source a glTF material uses, including the specular-glossiness substitutions). Binding, GLTFMaterialResource.textureBindings and the argument buffer's order, texture preloading, KHR_texture_transform registration and the animation-pointer texture paths are all derived from it; the 17 named Binding properties became textureBindings plus subscript(texture:). Adding a texture now means a shader enum case and one table entry. Tests: materialTextureSlotsMatchTheShaderLayout, materialResourceBufferFollowsTheSlots, specularGlossinessTexturesUseTheirSlots. Goldens and reference unchanged. Factors (non-texture uniforms) are still read inline in GLTFMaterialResource and listed separately in GLTFMaterialAnimation.animatableFactors; the shader's texture locals remain hand-written (GPU side).

---

## 94: GLTFAsset's initializer does everything

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:l
created: 2026-10-06T14:30:17Z
updated: 2026-10-06T17:19:29Z
closed: 2026-10-06T17:19:29Z
+++

GLTFAsset's initializers load the file (textures, materials, meshes, skins, animations), flatten the scene (with visibility, variants and cycle checks), compute bounds, build instance batches, build three merged geometry sets, and register residency, in one long code path that later features were added to (variants, scene switching, merging, culling bounds). Most tests have to load a whole asset to check one stage. Dependencies are in-process plus the Metal device (local).

- `2026-10-06T17:19:29Z`: GLTFAsset is now built from named stages (GLTFAssetLoading.swift): Resources.load(container:device:) loads textures, materials, meshes, skins and animations; GLTFSceneContents flattens one scene (instances with visibility, variants and cycle checks, lights and cameras with their nodes, roots, hierarchy, skinned bounds); makeBatches and GLTFMergedGeometry batch and merge; residencyAllocations lists each long-lived allocation once for the ResourceCollection. The initializers only compose these. Tests: AssetLoadingTests (root nodes without scenes, lights and cameras with their nodes, residency without duplicates and covering materials and instance buffers). Goldens and reference unchanged; NodePerformanceTest load time unchanged (0.51 s). Its per-frame CPU measured 10-12 ms across runs (earlier 9-10 ms); this change does not touch per-frame work, so likely noise or #92, not verified.

---

## 95: GLTFViewer crashes in the Metal Performance HUD when switching models

+++
status: closed
priority: medium
kind: bug
labels: area:demo, effort:s
created: 2026-10-06T16:34:27Z
updated: 2026-10-06T19:01:29Z
closed: 2026-10-06T19:01:29Z
+++

Switching between sample models in GLTFViewer (Debug build, Metal Performance HUD enabled) crashes with EXC_BAD_ACCESS at address 0x0 on the main thread, inside libMTLHud:

    frame #0: 0x0000000000000000
    frame #1: libMTLHud.dylib`__37-[HUDMTLLayerTracking safeAreaInsets]_block_invoke + 128
    frame #2: libdispatch.dylib`_dispatch_call_block_and_release + 32
    ... main queue drain / NSApplication run / SwiftUI runApp

Before the crash the console repeats, once per model switch:

    [libMTLHud] Metric com.apple.hud-stat.frame-interval already exist
    [libMTLHud] Metric com.apple.hud-stat.present-delay already exist
    [libMTLHud] Metric com.apple.hud-stat.fps already exist

along with 'Unable to obtain a task name port right for pid 618: (os/kern) failure (0x5)' and a benign ViewBridge 'NSViewBridgeErrorCanceled' message.

The crash is in Apple's HUD code: a block it dispatched to the main queue calls a null function pointer, apparently after the render view (MTKView / CAMetalLayer) it tracks has been torn down when the detail view switches models. Not yet known whether it reproduces with the HUD disabled, or whether GLTFViewer recreating the RenderView per model (rather than reusing it) is what triggers it.

- `2026-10-06T19:01:29Z`: Closed at the user's request.

---

## 96: CarConcept paint looks pixelated up close

+++
status: closed
priority: low
kind: bug
labels: area:rendering, effort:s
created: 2026-10-06T16:55:48Z
updated: 2026-10-06T16:56:07Z
closed: 2026-10-06T16:56:07Z
+++

Viewed up close in GLTFViewer, CarConcept's red body paint shows a coarse, blocky noise pattern: individual texels of the flake texture appear as hard-edged squares (screenshot: CleanShot 2026-10-06 09.55.11).

Finding: the paint materials ('Paint 1 Carmine', 'Paint 2 Carmine', 'Paint 1 Pearl') use normal texture 8, a flake normal map tiled 30x via KHR_texture_transform (normal scale 0.3/0.05), and texture 8 uses sampler 1, which the file sets to magFilter NEAREST (9728) and minFilter NEAREST_MIPMAP_LINEAR (9986). GLTFMaterialResource.makeSampler honours those filters, so magnified flakes are drawn as nearest-neighbour squares. This may be what the file asks for; still to check: how three.js renders the same close-up (it also honours glTF sampler filters), and whether anything else (normal scale, clearcoat, missing anisotropic filtering for non-linear samplers) makes ours look coarser.

- `2026-10-06T16:56:07Z`: Not a bug: three.js renders the same close-up identically. The file's flake normal map (texture 8, tiled 30x) uses a NEAREST magnification sampler, so magnified flakes are hard-edged squares by design.

---

## 97: No automated performance benchmark

+++
status: closed
priority: medium
kind: task
labels: area:performance, area:testing, effort:m
created: 2026-10-06T17:38:12Z
updated: 2026-10-06T19:17:23Z
closed: 2026-10-06T19:17:23Z
+++

Performance is measured by hand with ms-gltf-render --benchmark N [--orbit] [--animation 0], and the numbers live in issue comments. Nothing records baselines or notices a regression, and before/after comparisons are manual: e.g. NodePerformanceTest measured 10-12 ms CPU per frame after #94 against 9-10 ms earlier, and it is not known whether that is a regression or noise.

Wanted: a fixed set of scenes covering each draw path (static merged: ABeautifulGame; skinned: BrainStem, RecursiveSkeletons; transmission: TransmissionTest, CarConcept; blended; animated with material pointers: AnimationPointerUVs; many draws: NodePerformanceTest), recorded per-scene CPU and GPU frame times (median, p95), a check that fails when a scene gets slower than its baseline by more than a margin, and a way to re-record after intended changes, like ReferencePSNR.json.

Constraints: timings only mean something in Release builds and on the machine that recorded them, so it should run on demand (not as part of the regular Debug test run) and keep baselines per machine.

- `2026-10-06T17:38:46Z`: Related: the Buildkite pipeline issue — a self-hosted Mac agent is where benchmarks could run with stable baselines.
- `2026-10-06T19:17:23Z`: Added 'ms-gltf-render bench' (render is now the default subcommand, so existing usage still works) and 'just bench' / 'just bench-record'. Fixed scenes, one per draw path: ABeautifulGame, Sponza, NodePerformanceTest, SimpleInstancing, BrainStem, RecursiveSkeletons, Fox, AnimationPointerUVs (animated), AlphaBlendModeTest, TransmissionTest, CarConcept; orbiting, 1024x1024. Per-machine baselines in Benchmarks/<hw.model>.json (Codable median/mean/p95 for frame, CPU, GPU); compare exits 1 when a scene's median is slower by more than 15% CPU or 50% GPU and 0.3 ms. Noise: back-to-back single runs differed by up to 2x; loading all scenes first, then 3 round-robin rounds of 60 frames (30 warm-up) and keeping each scene's fastest brought CPU medians within about 2-3% between runs. Debug builds warn and refuse to record. Baseline recorded for Mac17,6 (M5 Max). Not done: running it in CI (#100).

---

## 98: No SwiftLint configuration

+++
status: closed
priority: low
kind: task
labels: area:testing, effort:s
created: 2026-10-06T17:38:45Z
updated: 2026-10-06T22:52:18Z
closed: 2026-10-06T22:52:18Z
+++

The package has no .swiftlint.yml and is never linted, so style and lint findings (force unwraps, long lines, unused code) go unchecked. The sibling MetalSprockets repository has a .swiftlint.yml that could serve as a starting point. Wanted: a configuration, a just recipe to run it, a first pass fixing or explicitly disabling what it reports, and running it in CI.

- `2026-10-06T22:52:18Z`: Root .swiftlint.yml (only_rules) with build/checkout directories excluded; disabled with reasons: trailing_comma, number_separator, unused_parameter, vertical_whitespace_between_cases, incompatible_concurrency_annotation. GLTFViewer's older separate config removed so the whole repo uses one. Findings fixed (mostly swiftlint --fix; one bad empty_count fix on a tuple reverted with disable:this). just lint (pass --fix to correct). Zero violations. Running it in CI is #99.

---

## 99: No GitHub Actions CI

+++
status: closed
priority: low
kind: task
labels: area:testing, effort:m
created: 2026-10-06T17:38:45Z
updated: 2026-10-07T17:06:49Z
closed: 2026-10-07T17:06:49Z
+++

There is no .github/workflows directory, so nothing builds or tests the package on push or pull request. MetalSprockets has swift.yml, xcode.yml and docc.yml workflows to start from. Constraints: the package needs macOS 26 and a Metal 4 GPU (hosted runners may lack one, so GPU tests may need to be skipped or run elsewhere); the sample-asset and reference (three.js, network) tests need .sample-assets and network access; golden images are exact and recorded on Apple silicon. Wanted at least: build the package, the CLI and GLTFViewer, run the tests that can run there, and lint (see the SwiftLint issue).

- `2026-10-07T15:27:52Z`: Punting: CI cannot resolve the package yet. (1) The repo has no git remote, so there is nowhere for Actions to run. (2) Package.swift depends on BasisUniversalMetal by local path (../../../Scratch/BasisUniversalMetal), which a runner cannot check out. (3) The MetalSprockets pin may point at unpushed commits. Unblocker: push this repo and BasisUniversalMetal to GitHub (and switch the dependency to its URL); then the workflow can follow MetalSprockets' swift.yml/xcode.yml (macos-26, Xcode 26.x, download MetalToolchain, skip plugin fingerprint validation), build package + CLI + GLTFViewer, run the non-GPU/non-network tests, and run swiftlint.

---

## 100: No Buildkite pipeline

+++
status: closed
priority: low
kind: task
labels: area:testing, effort:m
created: 2026-10-06T17:38:46Z
updated: 2026-10-07T17:06:53Z
closed: 2026-10-07T17:06:53Z
+++

There is no .buildkite/pipeline.yml, so the full test suite (GPU, sample assets, golden images, three.js reference) never runs automatically on real Apple-silicon hardware. MetalSprockets has a Buildkite pipeline to start from. Wanted: a pipeline on a self-hosted Mac agent that downloads or caches the sample assets, builds in Debug and Release, runs the whole test suite (including goldens and reference PSNR), and could later run the performance benchmark (#97) against per-machine baselines.

- `2026-10-07T15:28:03Z`: Punting, same blocker as #99: Buildkite checks out from a remote and this repo has none, and BasisUniversalMetal is a local path dependency. Once both are on GitHub, 'xcb ci generate --target buildkite' (as MetalSprockets did) gives a starting pipeline; add a step that fetches/caches .sample-assets and runs the full suite with MTL_DEBUG_LAYER=1, Debug and Release.

---

## 101: Glass is not visible through other glass

+++
status: open
priority: low
kind: enhancement
labels: area:rendering, effort:m, deferred
created: 2026-10-06T17:40:21Z
updated: 2026-10-07T03:55:13Z
+++

A transmissive surface shows the transmission pre-pass image, which holds only opaque primitives (plus back faces of double-sided transmissive ones). Other transmissive objects behind it are missing, so in CompareIOR the far glass ball cannot be seen through the near one. three.js and the Khronos sample viewer behave the same way, so this is beyond reference parity. Optional improvement: also draw transmissive primitives into the pre-pass (refracting only the environment, a one-bounce approximation), at the cost of an extra pass and a difference from three.js; correct multi-layer refraction would need repeated transmission passes or ray tracing.

- `2026-10-07T03:55:14Z`: Related: #145 (refraction in visionOS immersive mode).

---

## 102: No visionOS immersive rendering

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:l
created: 2026-10-06T17:53:49Z
updated: 2026-10-07T01:13:00Z
closed: 2026-10-07T01:13:00Z
+++

The package declares visionOS 26, but glTF scenes can only be shown in a window; there is no way to render a GLTFScene in an immersive space. MetalSprocketsUI already provides ImmersiveRenderContent / ImmersiveRenderPass (CompositorServices, stereo via vertex amplification).

What is missing: GLTFScene/GLTFRenderer take one view and projection matrix, while immersive rendering needs per-eye view and projection (amplified draws, per-view uniforms in the shaders); the transmission pre-pass and environment background assume one view and one render target size; frustum culling needs the union of both eyes' frusta; immersive uses reverse-Z depth and the device's own lighting/scale conventions (meters, model placement in the room). GLTFViewer would need a visionOS target with an immersive space to show a chosen sample model.

- `2026-10-07T01:00:20Z`: Implemented, not yet run on a device (immersive rendering is compiled out of MetalSprockets' runtime in the simulator). Shaders: per-view arrays (kGLTFMaxViewCount 2) for view-projection, camera position and background inverse view-projection; every vertex function reads [[amplification_id]] and passes the eye to the fragment stage. Mono (macOS/iOS) draws set no amplification and use entry 0: goldens and reference PSNR unchanged, bench in the session's usual range. PBRStereoViews (per-eye view, projection, viewport, reversed depth) on PBRRenderer and PBREnvironmentBackground: draws amplify per eye into a layered target, culling uses the union of the eyes' frusta, blending sorts from between the eyes, opaque depth test flips for reverse-Z. PBRImmersiveScene (visionOS): ImmersiveRenderPass + amplification count + one or more items (blended sorted across them); no transmission pre-pass (glass refracts the environment only). Verified on the Mac GPU: StereoTests renders two views at once into a two-slice target and each slice is byte-identical to rendering that view alone (matrices, camera positions, culling, background). GLTFViewer on visionOS: 'View Immersive' ornament opens GLTFImmersiveSpace (mixed immersion) showing the current model ~30 cm radius, 1 m ahead at 1.2 m height, playing its first animation, with the window's lighting and material variant; builds for visionOS. Untested: anything on device (placement/scale feel, reverse-Z, foveation, progressive immersion, performance).
- `2026-10-07T01:13:00Z`: Confirmed working on device by the user (after the multi-scene manifest fix, 5df11e8f).

---

## 103: GLTFViewer's three.js comparison shows no PSNR

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:m
created: 2026-10-06T18:26:05Z
updated: 2026-10-06T22:06:19Z
closed: 2026-10-06T22:06:19Z
+++

When comparing with three.js in GLTFViewer (three.js, Side by Side, Split), there is no number for how close the two renders are; judging parity means eyeballing, while the test suite measures PSNR against the same reference (ReferencePSNR.json).

Wanted: show the PSNR of the current Metal frame against the current three.js frame in the comparison modes (e.g. in the renderer labels or the stats overlay), updated when the camera, lighting or animation time settles, and ideally the recorded baseline for the model from ReferencePSNR.json next to it.

Notes: both renders must use the same size, camera and lighting at the moment of capture (GLTFWebReference already renders matching snapshots for the tests); capturing the Metal side means an offscreen render or reading back the view's drawable; computing PSNR every frame is unnecessary, so capture after interaction stops.

- `2026-10-06T22:06:19Z`: GLTFViewer shows 'PSNR nn.n dB' (bottom right) in the three.js comparison modes. Half a second after the view settles (camera, lighting, environment, exposure, tone mapping, antialiasing, variant), it takes the three.js snapshot and renders the Metal side offscreen at the snapshot's pixel size with the same camera, lighting, pose, background color and MSAA, then computes PSNR over sRGB RGB (PSNR.between). Hidden while anything changes, while an animation plays, and for debug views and wireframe (three.js draws neither). Not shown: the recorded ReferencePSNR baseline (it lives in the test target and uses fixed test framing, so it would not be comparable to an interactive view). Tests: psnrOfIdenticalImagesIsInfinite, psnrOfAKnownDifference. Not checked in the running app.

---

## 104: Meshopt compressed meshes are not supported

+++
status: closed
priority: medium
kind: feature
labels: area:extensions, effort:m
created: 2026-10-06T18:31:35Z
updated: 2026-10-06T20:43:32Z
closed: 2026-10-06T20:43:32Z
+++

Primitives using EXT_meshopt_compression or KHR_meshopt_compression (the same scheme under its vendor and Khronos names) cannot be loaded; GLTFViewer lists those variants as unsupported. Samples: BrainStem (glTF-Meshopt, glTF-Meshopt-EXT), DragonAttenuation, MeshoptCubeTest. Both extensions compress buffer views, so decoding belongs where buffer views are read (SwiftGLTF), using meshoptimizer's decoder (MIT, small C++). Split from #8; Draco stays there, deferred.

- `2026-10-06T18:32:52Z`: Priority by sample usage: required by 3 models' meshopt variants (BrainStem, DragonAttenuation, MeshoptCubeTest).
- `2026-10-06T18:56:37Z`: Related: #108 (extension points / optional extension targets).
- `2026-10-06T20:27:28Z`: Needs SwiftGLTF#64 (buffer view decoder hook in Container/AccessorReader). Plan here: GLTFLoadOptions.bufferViewDecoders passed to the Container, counted as supported extensions (#124), and an optional MetalSprocketsGLTFMeshopt target vendoring meshoptimizer's decoder (MIT) for EXT_/KHR_meshopt_compression incl. filters.
- `2026-10-06T20:43:32Z`: Added the optional MetalSprocketsGLTFMeshopt product: GLTFMeshoptDecoder (a SwiftGLTF BufferViewDecoder, SwiftGLTF#64) decodes EXT_ and KHR_meshopt_compression buffer views with meshoptimizer v1.3's decoder (vendored in Sources/CMeshoptimizer: vertexcodec, indexcodec, vertexfilter, header; MIT): ATTRIBUTES / TRIANGLES / INDICES modes and the OCTAHEDRAL, QUATERNION, EXPONENTIAL and COLOR filters. GLTFLoadOptions gains bufferViewDecoders (passed to the Container, counted as supported extensions); the built-in extension list now builds on SwiftGLTF's Document.supportedExtensions. ms-gltf-render and GLTFViewer opt in; the viewer's variant picker offers Meshopt variants. Tests (MetalSprocketsGLTFMeshoptTests): BrainStem's KHR and EXT variants are rejected without the decoder and load warning-free with it; BrainStem (both), DragonAttenuation (both) and MeshoptCubeTest render like their uncompressed variants above 30 dB with equal triangle counts (BrainStem mid-animation).

---

## 105: KHR_materials_volume_scatter is not supported

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:l
created: 2026-10-06T18:32:52Z
updated: 2026-10-07T15:27:34Z
closed: 2026-10-07T15:27:34Z
+++

Materials using KHR_materials_volume_scatter (subsurface scattering inside a volume: multiscatter color and scatter anisotropy, on top of KHR_materials_volume and KHR_materials_diffuse_transmission) render without scattering. Used by 1 sample: ScatteringSkull (optional extension, so it loads). Depends on #83 (diffuse transmission). Not in the README extension table yet.

- `2026-10-06T18:49:02Z`: When this is done, remove the workaround in GLTFMaterialResource that turns KHR_materials_diffuse_transmission off for volume-scatter materials (#83): with diffuse transmission 1 and a dense volume, ScatteringSkull renders black unless scattering returns light from the volume.
- `2026-10-07T15:27:34Z`: Approximated KHR_materials_volume_scatter without a scattering pass: multiscatterColorFactor tints the diffuse color, and for diffuse-transmitting materials half the transmitted share stays on the lit side (scattered light leaves both sides), the far-side half tinted too and attenuated by the volume. Removed the #83 workaround that turned diffuse transmission off for scatter materials. ScatteringSkull now renders teal like its Substance Stager screenshot. Not used: multiscatterColorTexture and scatterAnisotropy (noted in the README). VolumeScatterTests: a fully diffuse-transmitting dense volume returns ~nothing to a front light without scatter and teal with it (failed before: the material rendered white). Re-recorded ScatteringSkull's three.js PSNR (44.3 → 15.1 dB: three.js supports neither diffuse transmission nor volume scatter and draws it white); LightVisibility rose 35.3 → 36.3 from #89.

---

## 106: No way to turn individual glTF extensions on or off

+++
status: closed
priority: low
kind: feature
labels: area:extensions, effort:m
created: 2026-10-06T18:52:05Z
updated: 2026-10-06T21:47:05Z
closed: 2026-10-06T21:47:05Z
+++

Every supported extension is always applied. There is no way to load or render a model as if an extension were unsupported, which would help to:
- compare against three.js fairly where it lacks an extension (diffuse transmission, node visibility, spec-gloss): today those reference scores are re-recorded lower instead;
- debug or demonstrate an extension's effect (GLTFViewer toggle per extension, e.g. in the Model inspector tab);
- work around a broken or unwanted extension in a particular file;
- replace hard-coded fallbacks such as diffuse transmission being off for volume-scatter materials (#105).

Two levels, possibly both:
- Load time: an option set on GLTFAsset(url:...) naming the extensions to ignore. Material, node (visibility, instancing, lights) and geometry extensions are read while building the asset, so most would be handled there; extensions decoded in SwiftGLTF (texture_transform, specular, ior, transmission, volume, emissive_strength, unlit, lights_punctual, mesh_quantization, texture_webp) may need a hook in SwiftGLTF, or filtering of Document extensions before use. A required extension that is turned off should fail the load like an unsupported one.
- Render time: flags in the frame uniforms that the shader checks (cheap for material lobes such as sheen, clearcoat, iridescence, anisotropy, transmission, diffuse transmission, dispersion), so a viewer can toggle without reloading. Structural extensions (instancing, visibility, variants, quantization) only make sense at load time.

Open question: whether SwiftGLTF should offer a general 'ignore these extensions' option on Container/Document so other renderers get it too.

- `2026-10-06T18:52:20Z`: UI side: #107.
- `2026-10-06T18:56:37Z`: Related: #108 (extension points / optional extension targets).
- `2026-10-06T21:47:05Z`: GLTFLoadOptions.disabledExtensions: the document is filtered before loading (GLTFExtensionFilter re-encodes it and removes the names from every 'extensions' object at any depth, using SwiftGLTF's new Container.withDocument, SwiftGLTF b67e1f0), so materials, textures, nodes, primitives and document-level data (lights, variants) behave as if the file never used them. extensionsUsed/extensionsRequired are kept: statistics still list them, and disabling a required extension makes it unsupported (load fails unless loadsUnsupportedRequiredExtensions). CLI: render --disable-extension NAME (repeatable). Check: DiffuseTransmissionTest vs three.js 16.3 dB with diffuse transmission, 27.4 dB with it disabled (its pre-#83 score). Tests: DisabledExtensionsTests (3). Render-time toggling of material lobes without reload filed separately as #131.

---

## 107: GLTFViewer cannot toggle glTF extensions

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
depends: 106
created: 2026-10-06T18:52:20Z
updated: 2026-10-06T21:47:05Z
closed: 2026-10-06T21:47:05Z
+++

GLTFViewer gives no way to see a model with an extension turned off, so the effect of e.g. sheen, clearcoat or diffuse transmission cannot be compared on and off, and Metal cannot be compared fairly with three.js where three.js lacks an extension.

Wanted: an Extensions section (Model inspector tab, or its own tab) listing the extensions the loaded file uses, each with a toggle; render-time ones apply immediately, load-time ones reload the model. Unsupported extensions shown as such, required ones not toggleable. Depends on #106 (the library options).

- `2026-10-06T21:47:05Z`: GLTFViewer's Model tab lists the file's extensions with a toggle each; turning one off reloads the model without it (camera and view state kept: the current model stays on screen until the reload is ready). Required and unsupported extensions are listed without a toggle. Toggles reset when the file variant changes. Load-time only; instant material-lobe toggles are #131. Not checked in the running app.

---

## 108: Extensions cannot live in optional targets

+++
status: closed
priority: medium
kind: task
labels: area:extensions, area:architecture, effort:m
depends: 123, 124, 125
created: 2026-10-06T18:56:37Z
updated: 2026-10-06T20:45:34Z
closed: 2026-10-06T20:45:34Z
+++

Every extension is implemented inside the MetalSprocketsGLTF target and texture decoding is hard-wired in GLTFTextureCache, so an extension with a heavy dependency (KHR_texture_basisu via BasisUniversalMetal, #36; meshopt via meshoptimizer, #104; Draco, #8) would be compiled and linked into every client, whether it needs the extension or not.

Wanted: extension points in the core so an extension can ship as its own target and product, opted into at load time:
- a texture decoder protocol (e.g. GLTFTextureDecoder: the extension names it handles; given a glTF texture and document, choose the image and return an MTLTexture or nil); the built-in PNG/JPEG/WebP path stays the default;
- a matching hook for buffer view / geometry decoding (meshopt, Draco) later;
- registration through load options, e.g. GLTFAsset(url:options:) with options.textureDecoders;
- the required-extension check counts registered decoders' extension names as supported, so a file requiring an absent plugin fails clearly;
- first user: a MetalSprocketsGLTFBasisU target/product (core + BasisUniversalMetal) providing the KTX2 decoder, with its tests in a target that depends on it; GLTFViewer opts in.

Later we may move other extensions (material lobes, instancing, variants) into targets the same way, so the extension points should not be texture-specific only. Related: #106 (turning extensions on/off) could build on the same registry.

SwiftPM note: a separate product avoids building and linking the dependency, but SwiftPM still resolves and fetches it for every client of the package; package traits (Swift 6.1+) could make the dependency itself optional.

- `2026-10-06T19:36:11Z`: Related: #118 (separating the renderer from glTF); optional extension targets should fit the importer side of that split.
- `2026-10-06T20:16:36Z`: Done: texture decoder extension point (#123), required-extension check counting registered decoders (#124), first optional target MetalSprocketsGLTFBasisU (#125, closes #36). Remaining here: a matching hook for buffer view / geometry decoding (meshopt #104, Draco #8), and later moving other extensions into targets if wanted.
- `2026-10-06T20:27:28Z`: Geometry side depends on SwiftGLTF#64 (buffer view decoders).
- `2026-10-06T20:43:32Z`: Geometry side done for meshopt: SwiftGLTF#64 buffer view decoders + GLTFLoadOptions.bufferViewDecoders + MetalSprocketsGLTFMeshopt (#104). Draco (#8) would plug in the same way. Remaining: moving other extensions into targets, if ever wanted.
- `2026-10-06T20:45:34Z`: Done: texture decoders (#123), buffer view decoders (SwiftGLTF#64 + GLTFLoadOptions.bufferViewDecoders), required-extension check counting registered decoders (#124), and two optional targets: MetalSprocketsGLTFBasisU (#125) and MetalSprocketsGLTFMeshopt (#104). Draco (#8) would plug into the buffer view hook; moving other extensions into targets can get its own issue if wanted.

---

## 109: three.js reference cannot show material variants

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-06T19:04:21Z
updated: 2026-10-06T19:48:30Z
closed: 2026-10-06T19:48:30Z
+++

GLTFWebReference has no way to select a KHR_materials_variants variant (three.js's GLTFLoader does not support the extension; it points to a third-party plugin), so in GLTFViewer's comparison modes the three.js side always shows the default materials while the Metal side shows the chosen variant (the Model tab says so). Wanted: a setVariant(index) on GLTFWebReference that swaps materials in the web page, e.g. by reading the primitive mappings from parser.json and loading the mapped materials with parser.getDependency('material', index), or by vendoring the plugin.

- `2026-10-06T19:48:30Z`: Won't fix: not wanted.

---

## 110: GLTFViewer logs 'Conversion error!' messages of unknown origin

+++
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-06T19:04:47Z
updated: 2026-10-07T14:09:59Z
closed: 2026-10-07T14:09:59Z
+++

Running GLTFViewer logs lines like:

Conversion error! {{0, 1032}, {1376, 0}} was converted to {{428.94540148032337, 1855.0810263206054}, {1837.4181833148202, 0}}
Conversion error! {{0, 1032}, {1376, 0}} was converted to {{11857.882352941182, 8347.0588235294144}, {20882.823529411773, 0}}

Source unknown: no code in this repository prints them, so they come from a system framework. The rect has zero height and its width (1376) and y (1032) look like the window's width and height in points, so my guess (unverified) is a coordinate-space conversion of a zero-height rect at the bottom edge, e.g. keyboard or bottom bar geometry; the same log has 'Got a keyboard will change frame notification, but keyboard was not even present' and SFBarButtonGroup / keyboard messages, which suggests an iPad / iOS-on-Mac run. The other lines in that log ([libMTLHud] 'Metric ... already exist' repeated per view, 'cannot add handler to 0 from 0 - dropping', 'fopen failed for data file', AX Safe category, PointerUI port) look like system noise, but the libMTLHud ones repeat once per Metal view created, which may be worth checking too.

To find the source: set a symbolic breakpoint on os_log / _os_log_impl (or the CoreFoundation logging function) with a condition on the message, or search the frameworks' strings for 'Conversion error!'; note which action (opening the inspector, showing the scrubber, switching models, rotating) triggers it.

- `2026-10-07T14:09:59Z`: Closed by user: not worth chasing.

---

## 111: GLTFViewer shows no model statistics

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-06T19:08:30Z
updated: 2026-10-06T19:44:23Z
closed: 2026-10-06T19:44:23Z
+++

The only numbers GLTFViewer shows about a model are its primitive and material counts (bottom-left overlay). There is no file size, format, or geometry and texture totals, which makes it hard to judge a model's cost or compare file variants.

Wanted: a Statistics section in the Model inspector tab, e.g.
- file: format (glTF-Binary, glTF with external files, embedded), size on disk including external buffers and images, glTF generator and version (asset.generator);
- geometry: triangle, vertex and index counts (and points/lines when present), primitives, meshes, nodes, instances (including EXT_mesh_gpu_instancing copies), draw batches after merging;
- materials and textures: material count, texture count, total texture memory on the GPU, largest texture size;
- animation: clips, skins and joints, morph targets;
- extensions used and required;
- load time and load warnings.
Some of this needs GLTFAsset to expose counts it already has (vertex/index counts per primitive, texture memory). Related: #81 (browsing the full document structure).

- `2026-10-06T19:44:23Z`: Added GLTFAsset.statistics (GLTFAssetStatistics): version, generator, extensions used/required, external file paths; nodes, meshes, distinct primitives, instances (incl. instancing copies), draw batches; triangles/lines/points drawn and vertices stored; materials, variants, distinct textures (placeholders excluded), texture GPU memory, largest texture; animations, skins, joints, morph targets, lights, cameras, scenes. GLTFViewer's Model tab shows them in File / Geometry / Materials / Scene / Extensions / Warnings sections, with format, size on disk (including a .gltf's external buffers and images) and load time measured by the viewer. Tests: statisticsCountAQuad, statisticsCountInstancedCopies. Not checked in the running app.

---

## 112: No debug views of shading inputs

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, area:demo, effort:m
created: 2026-10-06T19:08:55Z
updated: 2026-10-06T19:32:30Z
closed: 2026-10-06T19:32:30Z
+++

There is no way to see what the PBR shader is working with (normals, tangents, UVs, material channels), so rendering problems such as wrong tangents (#2 work), flipped normals, bad UVs or texture slots are diagnosed by eye from the final image or with GPU captures.

MetalSprocketsAddOns has a DebugRenderPipeline (DebugShaders.h/.metal) with 27 modes: normal, tex coord, tangent, bitangent, world/local position, UV distortion, TBN matrix, vertex ID, face normal, UV derivatives, checkerboard, UV grid, depth, wireframe overlay, normal deviation, amplification/instance ID, quad thread, SIMD group, barycentrics, front facing, sample ID, point coord, distance to light/origin/camera. Its pipeline uses its own vertex layout and uniforms, so it cannot draw our skinned, morphed, instanced, merged glTF geometry directly.

Wanted: a debug view mode in our own shaders (a frame uniform, e.g. GLTFFrameUniforms.debugView) that replaces the lit color with one input, so every draw path (merged, skinned, morphed, instanced, transmission) gets it for free. Reuse AddOns' mode list and color mappings where they apply, plus glTF-specific ones: base color, metallic, roughness, occlusion, emissive, the shading normal after normal mapping, the geometric normal, tangent handedness, each texture slot's UVs (TEXCOORD_0/1 and KHR_texture_transform), alpha and alpha mode, and extension lobes on their own (clearcoat, sheen, transmission, diffuse transmission, iridescence, specular). Expose it on GLTFScene/GLTFRenderer and as a picker in GLTFViewer (an inspector tab or the Model tab). Related: #25 (lists debug views among missing viewer controls).

- `2026-10-06T19:32:30Z`: Added GLTFDebugView (public Swift enum mirroring the shader's kGLTFDebugView* values; test pins the order) and debugView on GLTFScene and GLTFRenderer. The PBR shade() function returns the chosen input just before lighting, so every draw path (per-batch, merged static/transmissive/skinned, morphed, instanced) gets it. Views: lit, base color, alpha, metallic, roughness, occlusion, emissive, shading normal, geometric normal, tangent, bitangent, tangent handedness, TEXCOORD_0/1, UV checker, front facing, specular F0, transmission, diffuse transmission, clearcoat, sheen, iridescence. Data views show their value (decoded for the sRGB target), color views the color; unlit materials show base color/alpha or dark gray. Debug views skip the transmission pre-pass. GLTFViewer: Shading picker in the Model tab (persists across models). CLI: render --debug-view <kebab-name>. Tests: debugViewsMatchTheShaderValues, debugViewsShowTheirInputs (base color, roughness gray, +z normal, front facing, metallic on a known quad). Not added from MetalSprocketsAddOns' list: vertex/instance/amplification IDs, SIMD group, quad thread, barycentrics, wireframe overlay, depth, distances; can follow if wanted.

---

## 113: Benchmark suite misses several draw paths

+++
status: open
priority: low
kind: task
labels: area:performance, area:testing, effort:s, deferred
created: 2026-10-06T19:18:26Z
updated: 2026-10-07T03:55:13Z
+++

The bench suite (ms-gltf-render bench, GLTFBenchCommand.scenes) has 11 scenes picked by hand. Paths with no scene, so their regressions go unnoticed:
- morph targets (e.g. AnimatedMorphCube, MorphStressTest, or a skinned+morphed character);
- diffuse transmission (DiffuseTransmissionPlant), sheen (SheenWoodLeatherSofa, GlamVelvetSofa), clearcoat, iridescence, anisotropy, dispersion: material lobes that add shader cost;
- KHR_materials_variants switching and node visibility;
- large texture sets / many materials (FlightHelmet, Sponza already partly);
- the environment background (--background) and the transmission pre-pass at larger sizes;
- point/line primitives (MeshPrimitiveModes);
- a scene with many lights (punctual lights loop), e.g. LightsPunctualLamp or PlaysetLightTest;
- load time, which is not measured at all (large files: Sponza, ABeautifulGame, CarConcept).
Also worth considering: a second resolution (GPU-bound at 4K) and scenes that are GPU-heavy rather than CPU-heavy. Adding scenes means re-recording each machine's baseline (just bench-record) and keeping the suite's run time reasonable (about a minute now).

---

## 114: Every frame churns MetalSprockets' residency set (upstream MetalSprockets#481)

+++
status: closed
priority: low
kind: bug
labels: area:performance, effort:xs
created: 2026-10-06T19:20:27Z
updated: 2026-10-06T19:55:36Z
closed: 2026-10-06T19:55:36Z
+++

A GPU capture of GLTFViewer shows, on every frame, removeAllocation for the environment specular and irradiance maps, the BRDF lookup and the transmission targets, a residency commit, then addAllocation of the same textures and another commit. The cause is in MetalSprockets (MetalContext retires the previous submission, dropping its allocations to zero uses, before acquiring the new frame's): filed upstream as MetalSprockets#481. Nothing to change here; cost unmeasured (MetalSprockets #436 found no GPU-time effect). Close when #481 is fixed and the MetalSprockets dependency is updated; then check a capture shows no per-frame add/remove and run just bench.

- `2026-10-06T19:55:03Z`: MetalSprockets updated to 9243779 (Defer residency release, upstream #481) in Package.resolved, GLTFViewerSupport and the GLTFViewer Xcode project. 96 tests pass; just bench passes with no measurable CPU change (medians -2%..+5% of baseline, within noise), so the churn was cheap. Remaining: confirm in a GPU capture that frames no longer remove/add the same allocations, then close.
- `2026-10-06T19:55:36Z`: Confirmed by the user in a GPU capture: frames no longer remove and re-add the same allocations. Fixed upstream (MetalSprockets#481, 9243779); no measurable time change, it was mainly a correctness issue.

---

## 115: Transmission backdrop texture is allocated even when unused

+++
status: closed
priority: medium
kind: bug
labels: area:performance, effort:s
created: 2026-10-06T19:21:55Z
updated: 2026-10-06T19:27:11Z
closed: 2026-10-06T19:27:11Z
+++

GLTFTransmissionTarget always allocates the 'GLTF Transmission Backdrop' texture (RGBA16Float, full mip chain, view-sized: 54.83 MiB at 2000x2570), but GLTFTransmissionPass only uses it when the scene has double-sided transmissive materials (hasBackFaces). A GPU capture of GLTFViewer showing ABeautifulGame, which has none, flags it as a Large Unused Resource. Every view showing a transmissive model pays for it.

Fix: allocate the backdrop only when it is needed (lazily on first use with back faces, or by passing whether the asset needs it), keeping it sized with the target. Test: a target used with an asset without double-sided transmissive materials has no backdrop texture; goldens and reference unchanged.

- `2026-10-06T19:27:11Z`: GLTFTransmissionTarget no longer allocates the backdrop up front: backdrop() makes it on first use (locked; the target is shared across frames), and GLTFTransmissionPass only asks for it when the scene has double-sided transmissive materials. Saves a view-sized RGBA16F mip chain (54.83 MiB at 2000x2570) for every other transmissive scene, e.g. ABeautifulGame. Test: transmissionShowsSceneBehind now also expects no backdrop (failed before: always allocated); transmissionShowsTransmissiveBackFacesBehind expects one. Goldens and reference unchanged (90 tests pass).

---

## 116: Check whether merged vertex buffers are really unused, and whether merging doubles geometry memory

+++
status: closed
priority: low
kind: task
labels: area:performance, effort:s
created: 2026-10-06T19:23:07Z
updated: 2026-10-06T19:57:21Z
closed: 2026-10-06T19:57:21Z
+++

Investigation. A GPU capture of GLTFViewer showing ABeautifulGame flags 'GLTF Merged Vertices' (31.64 MiB) as a Large Unused Resource. Probably a false positive: the static merged path draws the chess set (28 draw calls) and binds this buffer with .vertexBuffer, which MetalSprockets turns into an argument-table setAddress; my guess (unverified) is the debugger's 'never bound to a command encoder' check misses address-based binding.

Cannot tell yet because three merged geometries (static, transmissive, skinned) all label their buffers 'GLTF Merged Vertices'. Steps:
1. Give each merged geometry's buffers distinct labels (e.g. 'GLTF Merged Static Vertices').
2. In a capture, inspect a merged draw's bound resources: is the flagged buffer the one being read?
3. If one merged geometry really is unused, find why it is built.

Also measure: after merging, the original per-primitive vertex and index buffers stay allocated (needed for the per-batch fallback when a pose mirrors an instance), so merged geometry is stored twice. Report the extra memory for ABeautifulGame and Sponza; if large, file a fix (e.g. skip or free the originals when the fallback cannot happen, such as assets without animations). Split from #115.

- `2026-10-06T19:57:22Z`: Merged geometries now label their buffers by kind ('GLTF Merged Static Vertices', '... Transmissive ...', '... Skinned ...'), so a capture can tell which one the debugger flags; confirming that the flagged buffer is the one merged draws read is left to a capture (likely a false positive from address-based binding). Measured duplication: merging stores geometry twice (ABeautifulGame 37.4 + 40.2 MB, NodePerformanceTest 60.2 + 61.8, Sponza 17.0 + 18.6, BrainStem 4.2 + 4.6). Fix filed as #122 (shared geometry arena; the originals are still needed for variant/scene rebuilds and the mirrored-pose fallback).
- `2026-10-06T19:58:27Z`: User capture (ABeautifulGame) after the relabel: the flagged buffer is 'GLTF Merged Static Vertices'. The draw plan draws static batches from asset.merged whenever there is no mirroring pose (none here), so this is the buffer the merged draws read: a debugger false positive, most likely because Metal 4 argument-table binding by GPU address is not counted as use. The genuinely unread data in this scene is the per-primitive originals (#122).
- `2026-10-06T19:59:56Z`: Confirmed with gpudebug on the user's capture (GLTFViewer.gputrace, ABeautifulGame): the main pass's draws (commands/cb0/re2/draw0..14) use pipeline 'GLTF Opaque Merged' and bind 'GLTF Merged Static Vertices' (@buf61, 31.6 MiB) as vertex buffer 0 with 'GLTF Merged Static Indices' as the index buffer, so the Large Unused Resource insight is a false positive. Also seen: every chess piece mesh has two per-primitive buffers ('King_Shared[0] Vertices' and '... (2)'); that is the file, which defines black and white pieces as separate meshes with their own accessors, not double loading.

---

## 117: No controllable player character

+++
status: closed
priority: low
kind: feature
labels: area:demo, area:animation, effort:l
depends: 119
created: 2026-10-06T19:35:48Z
updated: 2026-10-06T19:37:11Z
closed: 2026-10-06T19:37:11Z
+++

GLTFViewer only orbits a camera around a static or self-animating model. There is no way to drive a character: move it around a scene and see its animations respond, which would exercise skinning, animation blending and the renderer in a game-like setting.

Wanted (to be refined): a demo mode where the user controls a skinned glTF character (e.g. Fox or CesiumMan from the samples) with the keyboard (WASD/arrows) or a game controller, in an environment (a ground plane, or a scene model such as Sponza). The character turns and moves; its clips switch with movement (idle, walk, run: Fox has Survey, Walk and Run) and ideally cross-fade; a follow camera keeps it in view.

Open questions:
- Where it lives: a mode of GLTFViewer, or a separate demo app.
- Which character and environment; whether to load them from the sample assets or ship them.
- Collision: none (flat ground), simple bounds, or ground-height queries against the scene.
- Animation blending: GLTFPose has no cross-fade between clips today; that may be its own library issue.
- Platforms: keyboard on macOS, touch/controller on iOS, visionOS later (#102).

- `2026-10-06T19:36:47Z`: Animation blending and clip switching: #119.
- `2026-10-06T19:37:12Z`: Closed at the user's request; the library side it needed (animation blending and clip switching) remains open as #119.

---

## 118: Rendering is tied to glTF

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:xl
created: 2026-10-06T19:36:10Z
updated: 2026-10-06T23:35:15Z
closed: 2026-10-06T23:35:15Z
+++

The PBR renderer (GLTFRenderer, GLTFScene, merged geometry, draw plans, transmission, environment, lighting, debug views) only accepts a GLTFAsset, which is built straight from a SwiftGLTF Document: 17 of the library's files import SwiftGLTF, including GLTFAsset, geometry, materials, animation and cameras. Another format cannot use the renderer without first being converted to glTF. For example, USD loaded through USDKit could be drawn with the same PBR pipeline, transmission and debug views if the renderer took a format-neutral scene.

Direction (a sketch, to be designed):
- A format-neutral render model in its own target: primitives (vertex/index/skin/morph buffers in the existing GLTFVertex layout), PBR materials (the existing uniforms + texture slots), instances and batches, skins, lights, cameras, environment, and poses (world matrices, morph weights, material overrides) produced by whatever drives animation.
- The renderer target depends only on that model (plus MetalSprockets), not on SwiftGLTF.
- Importers in their own targets build the model: MetalSprocketsGLTF (today's loading, animation sampling and glTF extensions) and later a USD importer via USDKit. Format-specific features map onto shared material features where they match (UsdPreviewSurface roughly maps onto metallic-roughness), or stay importer-only.
- Naming: the renderer's public types drop the GLTF prefix.

Things to watch: keep goldens, reference PSNR and the benchmark (just bench) unchanged through the split; the shader types (GLTFShaderTypes.h) are already format-neutral in practice; extension handling and #108 (extensions in optional targets) should fit the importer side; animation (GLTFAnimationClip, KHR_animation_pointer) is glTF-specific and would stay in the importer, producing poses.

Should be split into smaller issues (render model, renderer move, glTF importer, first second-format importer) before work starts.

- `2026-10-06T19:46:54Z`: Related: #121 (MetalSprocketsSceneGraph could become or feed the format-neutral render model).
- `2026-10-06T22:55:52Z`: Design (agreed 2026-10-06): bridge through data, not protocols. The renderer target (MetalSprocketsPBR, no SwiftGLTF) owns two types: PBRModel, immutable, built once, owns GPU buffers (primitives in the renderer's vertex layout with skin/morph data, PBRMaterial = uniforms + texture slots, instances by node index, skins as joint node indices + inverse binds, lights, bounds; merged buffers and batches computed inside); and PBRPose, per frame (world matrices by node, morph weights, material overrides, visibility). PBRModelBuilder takes vertices/indices/materials (MTLTextures)/nodes/lights and does the merging, so every producer gets batching. PBRScene (Element) takes models + pose + camera + lighting; environment, tone mapping, debug views, MSAA, transmission stay renderer-side. glTF importer keeps parsing, extensions, decoders, hierarchy evaluation, animation (clips and KHR_animation_pointer produce PBRPose), variants (become pose material overrides), file cameras, statistics; GLTFAsset wraps a PBRModel; GLTFScene stays as a convenience Element. Immutable model + pose chosen over a mutable model (keeps merged buffers, background loading and identity caching simple); structural change by composing several PBRModels per scene; scene graph (#121) becomes another producer via the builder. Split into sub-issues; each step must keep goldens, reference PSNR and bench unchanged.
- `2026-10-06T22:55:52Z`: Sub-issues: #132 render model types, #133 builder (merging/batching), #134 renderer as PBRScene, #135 variants as overrides, #136 several models per scene, #137 second producer.
- `2026-10-06T23:35:15Z`: Done through #132-#137: MetalSprocketsPBR (no SwiftGLTF) holds the render model (PBRModel, PBRPose, PBRMaterial, PBRLight), its builders (PBRGeometryBuilder, PBRModelBuilder) and the renderer (PBRRenderer, PBRScene with several models, transmission, environment, tone mapping, debug views); MetalSprocketsGLTF is an importer building PBRModels, with GLTF* typealiases and init(asset:) conveniences for existing callers. Variants are material overrides (no rebuild). A second producer (BasicShape) renders identically to its glTF form. Left: shader type/target names (#138); the scene graph (#121) can now be another producer.

---

## 119: No animation controller for blending and switching clips

+++
status: closed
priority: low
kind: feature
labels: area:animation, effort:m
created: 2026-10-06T19:36:47Z
updated: 2026-10-07T15:19:25Z
closed: 2026-10-07T15:19:25Z
+++

Animation is one clip at one time: asset.pose(animation:time:) samples a single clip into a GLTFPose. There is no way to play two clips at once, cross-fade from one to another, or drive clip choice from state, which a controllable character (#117) needs (idle -> walk -> run on Fox) and a viewer would use for smooth clip switching.

Wanted: an animation controller in the library, e.g. GLTFAnimationController (or a stateless function over layers):
- sample several clips and blend their node transforms (translation and scale lerp, rotation slerp/nlerp; morph weights lerp; KHR_animation_pointer material values lerp) by weight into one GLTFPose;
- cross-fade: start a clip and ramp its weight in over a duration while the previous ramps out;
- per-clip time, speed and looping; optionally sync walk/run cycles by normalised time so feet stay in phase;
- a blend parameter (e.g. speed 0...1 choosing between idle, walk and run weights), the basis of a simple blend tree;
- later: a small state machine (states with clips, transitions with durations and conditions), additive layers, root motion (extract the root node's movement so the controller moves the character instead of the clip).

Notes: blending happens on local node transforms before world matrices are computed (GLTFNodeHierarchy), so the sampling step needs to expose per-node local transforms rather than only finished poses. Tests can check: a 50/50 blend of two clips gives the halfway transforms; a finished cross-fade equals the target clip; weights always sum to 1.

- `2026-10-07T15:19:25Z`: Added GLTFAsset.pose(layers:) (weighted blend of clips: translation/scale/morph weights lerp, rotation nlerp with sign alignment, unanimated nodes blend with rest; materials/lights/cameras blended over layers that animate them; visibility by majority weight; one-layer fast path keeps the old single-clip result and cost) and GLTFAnimationController (play with cross-fade, per-clip speed and looping, 1D blend via blendWeights(parameter:count:) with phase sync). pose(animation:time:) now goes through layers. AnimationControllerTests (7): 50/50 halfway incl. 45° rotation, rest fill-in, single layer == clip, finished cross-fade == target clip, loop/clamp, weights sum to 1, phase sync. State machine, additive layers, root motion and viewer cross-fading moved to #150.

---

## 120: No wireframe overlay

+++
status: closed
priority: low
kind: feature
labels: area:rendering, area:demo, effort:s
created: 2026-10-06T19:46:26Z
updated: 2026-10-06T20:24:10Z
closed: 2026-10-06T20:24:10Z
+++

There is no way to see a model's triangles: the debug views (#112, GLTFDebugView) replace the shaded color with one input but none shows edges, so mesh density, topology, degenerate or stray triangles and LOD problems cannot be checked visually. MetalSprocketsAddOns' debug shaders have a wireframe overlay mode, but it cannot draw our skinned, morphed, instanced or merged geometry.

Wanted: a wireframe toggle independent of the shading view (so wireframe can sit over lit shading or over any debug view), on GLTFScene/GLTFRenderer (e.g. showsWireframe) and as a toggle in GLTFViewer's Display tab, plus a CLI flag.

Options: (1) barycentric edges in the existing fragment shader (Metal's [[barycentric_coord]] on Apple GPUs, with screen-space width from fwidth): one pass, works on every draw path, no extra geometry, anti-aliased lines; (2) a second pass with MTLTriangleFillMode.lines over the same draws: exact, but needs every pipeline variant again and gives aliased one-pixel lines. Option 1 looks best. Points and lines primitives are unaffected. Test: a quad with wireframe on has edge pixels in the wire color along its diagonal and border, and its centre unchanged.

- `2026-10-06T20:24:10Z`: Barycentric wireframe overlay: fragment_main and fragment_merged read [[barycentric_coord]] and blend a light cyan edge (width from fwidth, about a pixel, anti-aliased) over whatever shade() returns, so it works over lit shading and every debug view on all draw paths. Points/lines are skipped (GLTFMaterialUniforms.isPointOrLine); the transmission pre-pass never draws it. API: GLTFScene/GLTFRenderer.showsWireframe; GLTFViewer: Display tab toggle; CLI: render --wireframe. Test: wireframeDrawsTriangleEdgesOnly (quad diagonal turns cyan, interior unchanged). Checked visually on Box and DamagedHelmet; goldens unchanged (off by default).

---

## 121: MetalSprocketsSceneGraph is separate from this renderer

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:l
created: 2026-10-06T19:46:54Z
updated: 2026-10-13T19:47:08Z
closed: 2026-10-13T19:47:08Z
+++

../MetalSprocketsSceneGraph is a small (about 390 lines) scene graph for MetalSprockets: a SceneGraph of Nodes (a class tree with transform and optional mesh, light, camera content), a Material with a Blinn-Phong renderer (MetalSprocketsSceneGraphRenderer), and demo support; it builds on SwiftMesh and GeometryLite3D. It knows nothing of glTF, and this package's GLTFAsset has its own flattened node/instance model, so there are two scene models and two renderers, the scene graph's with far simpler shading (no PBR, IBL, skinning, morphs, transmission, batching or merging).

Wanted: decide how the two fit and integrate them, improving the scene graph where it falls short. Likely direction, overlapping #118 (render model independent of glTF):
- the scene graph (improved) becomes, or feeds, the format-neutral render model: nodes with transforms, mesh primitives, PBR materials, lights, cameras, skins, morph weights, instancing, visibility;
- glTF loads into a SceneGraph (and USD later), so apps can edit or build scenes in code and still render with this PBR pipeline, transmission and debug views;
- this renderer draws a SceneGraph (flattening it into instances and batches as GLTFAsset does now, ideally incrementally when only transforms change);
- the Blinn-Phong renderer either stays as a lightweight option or is replaced.

Improvements the scene graph would need: PBR materials (or a material protocol), per-node visibility, skins and joints, morph targets, instancing, animation targets (poses applied to nodes), bounds and change tracking for cheap re-flattening, and Sendable/value-semantics decisions (Node is a class today).

Should be split before work starts; coordinate with #118 and the scene graph's own ISSUES.md.

- `2026-10-07T15:28:14Z`: Punting: the issue itself says to split it before work starts, and it needs design decisions across two repos (does the scene graph become the render model or feed PBRModel; class vs value Node; material protocol vs PBR-only; keep or drop Blinn-Phong). Since #118 the format-neutral layer is MetalSprocketsPBR (PBRModel + PBRPose + PBRScene items), so the smallest useful first step is probably a SceneGraph → PBRModelBuilder adapter in MetalSprocketsSceneGraph. Unblocker: confirm that direction (or another), then split with the issue-splitting skill.
- `2026-10-13T19:47:08Z`: Closed: the work lives in MetalSprocketsSceneGraph (MSSG).

---

## 122: Merged geometry duplicates every merged primitive's vertex and index data

+++
status: closed
priority: medium
kind: enhancement
labels: area:performance, effort:m
created: 2026-10-06T19:57:21Z
updated: 2026-10-06T21:09:28Z
closed: 2026-10-06T21:09:28Z
+++

GLTFMergedGeometry copies each merged primitive's vertices and indices into its own buffers, and the per-primitive buffers stay allocated, so merged geometry is stored twice. Measured (MB, vertex + index + skin buffers): ABeautifulGame 37.4 originals + 40.2 merged; NodePerformanceTest 60.2 + 61.8; Sponza 17.0 + 18.6; BrainStem 4.2 + 4.6 (skinned). Roughly doubles geometry memory for every model that merges.

The originals cannot simply be freed: asset.variant(_:) and asset.scene(_:) rebuild merged geometry from them, non-merged batches draw from them, and the per-batch fallback (a pose mirroring an instance away from its rest winding) draws from them.

Fix idea: allocate all of an asset's primitives as ranges of one shared vertex buffer and one index buffer (an arena) at load. Per-batch draws bind the shared buffer at the primitive's offset (or use baseVertex/index offsets); merged draws use the same buffers with per-record baseVertex and index ranges, so merging builds only instance and record tables and copies no geometry. Rebuilding for a variant or scene then costs nothing extra. Watch: 16- vs 32-bit indices (merged uses 32-bit; per-primitive may be 16-bit), skin and morph buffers likewise, vertex counts beyond 32-bit index range, and that goldens, reference PSNR and just bench stay unchanged. From #116.

- `2026-10-06T21:09:28Z`: Every primitive of an asset now lives in one shared set of buffers (GLTFGeometryBuffers: GLTFVertex vertex buffer, 32-bit index buffer relative to each primitive's baseVertex, and a GLTFSkinVertex buffer parallel to the vertices when anything is skinned). Primitive drops its MetalMesh/indexType for id, geometry, baseVertex, vertexCount, indexStart, indexCount and isSkinned. Per-batch draws bind the shared buffers at the primitive's first vertex (vertex_id stays local for morph buffers) and draw its index range; merged geometry builds only instance/record/material tables and indexes the shared buffers by baseVertex, copying nothing; variant(_:) and scene(_:) share them too. Geometry memory: ABeautifulGame 77.6 -> 40.3 MB, NodePerformanceTest 122 -> 61.8 MB, Sponza 35.6 -> 18.6 MB, BrainStem 8.8 -> 4.6 MB (slightly above the old originals because indices are all 32-bit now). Bench: NodePerformanceTest CPU -34% (10.2 -> 6.7 ms), GPU -20% (10,000 vertex/index buffer pairs became one); small scenes +3..6% CPU (~0.05 ms, under the margin, cause not identified); baseline re-recorded. Goldens, reference PSNR, KTX2 and meshopt comparisons unchanged (108 tests).

---

## 123: No texture decoder extension point

+++
status: closed
priority: medium
kind: task
labels: area:extensions, area:architecture, effort:s
created: 2026-10-06T20:04:45Z
updated: 2026-10-06T20:08:56Z
closed: 2026-10-06T20:08:56Z
+++

GLTFTextureCache hard-wires image choice (texture.source, else EXT_texture_webp's source) and decoding (ImageIO / MTKTextureLoader). An extension that brings its own image format (KHR_texture_basisu, EXT_texture_astc) cannot plug in from another target. Wanted: a public GLTFTextureDecoder protocol (extension names it handles; given a glTF texture, the container and the sRGB flag, choose the image and return an MTLTexture or nil), consulted before the built-in path, with results cached per chosen image and color space and decoding kept parallel in preload. Registration through load options: GLTFAsset(url:options:) / init(container:options:) with options.textureDecoders, kept by variant(_:) and scene(_:). Tests with a test-only fake decoder: its texture is bound for a texture carrying its extension; without it the built-in path or a warning applies. Part of #108.

- `2026-10-06T20:08:56Z`: Added GLTFTextureDecoder (extensionNames; imageIndex(for:) chooses the image on the loading thread; makeTexture(data:sRGB:device:) decodes, called in parallel) and GLTFLoadOptions(textureDecoders:), taken by GLTFAsset(url:...options:) and init(container:...options:) and passed through Resources.load to GLTFTextureCache. The cache asks decoders in order before the built-in path (texture.source, then EXT_texture_webp), keeps per (image, color space) caching and parallel preload. variant(_:) and scene(_:) reuse the loaded textures. Tests (TextureDecoderTests, fake TEST_texture_fake extension): decoder's texture bound and asked with sRGB for base color; it wins over a fallback source; without it the fallback loads, or the texture is skipped with a warning. The decoder's extension names are not yet used for a required-extension check (#124).

---

## 124: Required glTF extensions are not checked

+++
status: closed
priority: medium
kind: bug
labels: area:extensions, effort:s
created: 2026-10-06T20:04:46Z
updated: 2026-10-06T20:11:38Z
closed: 2026-10-06T20:11:38Z
+++

GLTFAsset never looks at extensionsRequired: a file requiring an extension we do not support (e.g. KHR_texture_basisu without a fallback, KHR_draco_mesh_compression, meshopt) loads anyway and renders wrong or partly, with at most a texture warning. The spec says a loader must not load such a file. Wanted: a list of supported extensions (built-in plus registered decoders, #108), and on a required unsupported one either fail the load with an error naming it, or warn and continue. Decision needed: fail (spec-correct) or warn (forgiving, today's behavior), possibly an option. Before changing behavior, check every sample model's required extensions against the supported list. Part of #108.

- `2026-10-06T20:11:39Z`: A file whose extensionsRequired includes an extension outside GLTFLoadOptions.supportedExtensions (GLTFAsset.builtInExtensions plus registered decoders' names) now fails to load with GLTFUnsupportedExtensionsError (LocalizedError, names the extensions), as the spec requires; GLTFLoadOptions(loadsUnsupportedRequiredExtensions: true) loads it with a warning instead. Survey of glTF-Sample-Assets: every required extension is supported except Draco (18 variants), meshopt (5) and KTX2 (7), which now fail clearly instead of rendering wrong; no variant we load today (default binary/glTF, the reference and bench scenes) is rejected. Tests: unsupportedRequiredExtensionFailsTheLoad, unsupportedRequiredExtensionCanBeLoadedWithAWarning, registeredDecodersMakeTheirExtensionsSupported; 103 pass.

---

## 125: No KTX2 / Basis Universal texture target

+++
status: closed
priority: medium
kind: feature
labels: area:extensions, effort:s
depends: 123
created: 2026-10-06T20:04:46Z
updated: 2026-10-06T20:16:30Z
closed: 2026-10-06T20:16:30Z
+++

First real optional extension target for #108: MetalSprocketsGLTFBasisU (library product) depending on MetalSprocketsGLTF and BasisUniversalMetal, providing a GLTFTextureDecoder for KHR_texture_basisu (KTX2 via BasisUniversalMetal's BasisTextureLoader), with the slot's sRGB flag deciding the pixel format. GLTFViewer opts in; tests load the six KTX variants (ABeautifulGame, AnisotropyBarnLamp, CarConcept, ChronographWatch, FlightHelmet, StainedGlassLamp). Blocked by BasisUniversalMetal #1 (sRGB override) and #3 (no remote; a local path dependency works meanwhile). Implements #36.

- `2026-10-06T20:16:30Z`: Added the MetalSprocketsGLTFBasisU target/product (depends on MetalSprocketsGLTF, SwiftGLTF and BasisUniversalMetal, which already had the color-space override, mipmap generation and private storage). GLTFBasisUTextureDecoder handles KHR_texture_basisu: picks the extension's source image and transcodes with the material slot's sRGB/linear choice (not the file's flag), generating a mip chain for single-level files. Clients opt in with GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder()]); ms-gltf-render (render and bench) and GLTFViewer do, and the viewer's variant picker now offers KTX-BasisU variants (Draco/meshopt ones stay unsupported). Tests (MetalSprocketsGLTFBasisUTests): the KTX2 FlightHelmet is rejected without the decoder and loads warning-free with it; FlightHelmet, StainedGlassLamp, AnisotropyBarnLamp and ChronographWatch KTX2 renders match their PNG/JPEG variants above 30 dB. BasisUniversalMetal is a local path dependency until it has a remote (BasisUniversalMetal #3), so the package only resolves next to ~/Projects/Scratch/BasisUniversalMetal.

---

## 126: GLTFViewer has no built-in basic models

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-06T20:24:51Z
updated: 2026-10-06T20:53:21Z
closed: 2026-10-06T20:53:21Z
+++

GLTFViewer's sidebar is one flat list of glTF-Sample-Assets models, which must be downloaded first. There are no simple shapes available offline for quick checks of lighting, materials, debug views and the wireframe.

Wanted: sections in the sidebar, e.g. 'Basic Shapes' (built in) above 'Sample Assets' (the downloadable library), with a few built-in models: sphere (UV and/or icosphere), cube, plane, cylinder, cone, torus, perhaps a capsule and a Suzanne-like test head. Each with normals, tangents and UVs so normal maps and the UV checker work, and a neutral PBR material (with a few material presets, e.g. rough/smooth/metal, could come later).

Options for building them: generate them in code at launch (SwiftMesh already has shape generators; export to glTF or build GLTFAsset input directly) or ship small .glb files in the app bundle. Shipping .glb keeps them going through the normal loading path, which also makes them useful as loader tests. Selecting one should open it like any sample (inspector, variants hidden, comparison with three.js works if a file URL exists). Search should cover both sections.

- `2026-10-06T20:53:21Z`: GLTFViewer's sidebar now has sections: 'Basic Shapes' (sphere, cube, plane, cylinder, cone, torus; built in, available before and without the sample index) above 'Sample Assets' (the download prompt, progress or error now sits inside this section instead of replacing the whole window). Search filters both. Shapes are generated by BasicShape/ShapeMesh (unit size, normals, UVs, CCW fronts, neutral PBR material) and shipped as .glb resources packed with gltfpack (-cc -kv -vt 16: quantized + EXT_meshopt_compression, 2-18 KB each), so they load through the normal file path with the meshopt decoder and work with the three.js comparison. 'just basic-shapes' regenerates them. gltfpack notes: -kv keeps TEXCOORD_0 (otherwise dropped, no texture uses it); -vt 16 because 12-bit UVs rely on a texture transform these textureless shapes cannot carry (UVs came out 1/16 size). Tests: shapeGeometryIsConsistent (bounds, unit normals, winding agrees with normals), bundledShapeLoads (loads warning-free, triangle counts, UVs span 0...1). Not checked in the running app.

---

## 127: Tone mapping cannot be chosen

+++
status: closed
priority: low
kind: feature
labels: area:rendering, area:demo, effort:s
created: 2026-10-06T20:54:24Z
updated: 2026-10-06T21:13:47Z
closed: 2026-10-06T21:13:47Z
+++

Every lit, unlit and background output goes through Khronos PBR Neutral (toneMapPBRNeutral in GLTFShaderSupport.h, matches the spec), after exposure. There is no way to pick another operator, e.g. to compare with renderers or references that use ACES or AgX, to see clipped linear output, or to judge highlight handling.

Wanted: a tone mapping choice on GLTFLighting (next to exposure) or GLTFScene, passed in the frame uniforms: none (clamp), PBR Neutral (default), ACES filmic (e.g. the Hill / three.js ACESFilmic fit), AgX (Blender / three.js variant), maybe Reinhard. Applied in the PBR shader (lit and unlit paths) and the environment background alike; the transmission pre-pass stays linear. GLTFViewer: a picker in the Display tab; CLI: render --tone-mapping. The three.js reference already uses NeutralToneMapping; when a different operator is chosen, the web side should switch to its matching operator (three.js has ACESFilmic, AgX, Reinhard, Neutral, None) so comparisons stay fair. Goldens and reference PSNR stay on PBR Neutral.

- `2026-10-06T20:55:30Z`: Related: #128 (HDR / EDR output), which needs a tone mapping choice that can map to the display's headroom or not at all.
- `2026-10-06T21:13:47Z`: Added GLTFToneMapping (pbrNeutral default, linear/clamp, acesFilmic, agx, reinhard) on GLTFLighting.toneMapping, passed in the frame and background uniforms; one shader toneMap() applies it to lit, unlit and background output (the transmission pre-pass stays linear). ACES Filmic and AgX are ported from three.js r186's tonemapping_pars_fragment, Reinhard and Linear likewise. The three.js reference switches to the matching operator (GLTFWebReference.setLighting sends it). GLTFViewer: Tone Mapping picker in the Display tab (sent to both sides of the comparison). CLI: render --tone-mapping. Checks: DamagedHelmet Metal vs three.js PSNR per operator 34.1 (neutral) / 34.9 / 33.9 / 36.8 / 37.4 dB, so the ports match; tests toneMappingsMatchTheShaderValues and toneMappingAppliesTheChosenOperator (unlit 0.5 gray through linear, Reinhard, PBR Neutral). Goldens and reference unchanged.

---

## 128: No HDR / EDR output

+++
status: closed
priority: low
kind: feature
labels: area:rendering, area:demo, effort:m
created: 2026-10-06T20:55:30Z
updated: 2026-10-07T15:23:43Z
closed: 2026-10-07T15:23:43Z
+++

Rendering is HDR internally (rgba16Float environment maps and transmission target, unbounded linear lighting) but output is always SDR: the shader tone maps to 0...1 (PBR Neutral) and GLTFViewer's drawable is bgra8Unorm_srgb. On XDR displays the extra headroom is unused, and offscreen renders (OffscreenRenderer / ms-gltf-render) can only produce 8-bit PNGs.

Wanted:
- On screen (GLTFViewer, opt-in): a float drawable (rgba16Float) with wantsExtendedDynamicRangeContent and an extended linear color space on the CAMetalLayer (RenderView may need a MetalSprockets hook), and output that uses the display's headroom (NSScreen.maximumExtendedDynamicRangeColorComponentValue / its iOS equivalent) instead of compressing to 1.0: e.g. a tone mapper with a configurable white point above 1, or none.
- Offscreen: render into rgba16Float (pipelines take formats from the attachments, untested so far) and let the CLI write EXR or 16-bit float output, with or without tone mapping.
- Tests: a float-target render keeps values above 1 where the scene is brighter than white; SDR goldens unchanged.
Related: #127 (choosing the tone mapper).

- `2026-10-07T15:23:43Z`: Offscreen HDR done: PBRToneMapping.none (unclamped linear; three.js NoToneMapping), OffscreenRenderer.hdr(size:) (rgba16Float target), MTLTexture.float16Pixels()/hdrCGImage() and CGImage.writeEXR(to:). CLI writes OpenEXR when -o ends in .exr (works with --render-scale). Test floatTargetKeepsValuesAboveOne (unlit white × exposure 4 reads 4.0 from the float target; failed before). Checked DamagedHelmet EXR: max 10.4, 3.8% of components above 1. SDR goldens/PSNR unchanged. On-screen EDR needs a MetalSprockets RenderView hook: moved to #151. Note: a header-only shader change did not rebuild the metallib; touching the .metal files was needed.

---

## 129: GLTFViewer forgets its inspector state between launches

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:xs
created: 2026-10-06T20:58:07Z
updated: 2026-10-06T21:29:26Z
closed: 2026-10-06T21:29:26Z
+++

Whether the inspector is shown and which tab is selected live in ViewerSettings (@State in SamplesView), so they reset to closed / Camera on every launch. Wanted: persist them with @AppStorage (showsInspector as Bool, inspectorTab by its raw value). Worth considering for the other viewer settings too (display: background, antialiasing sample count, shading/debug view, wireframe; comparison mode and three.js lighting), each with a sensible default if the stored value is missing or no longer valid (e.g. a removed tab or debug view).

- `2026-10-06T21:29:26Z`: GLTFViewer's settings persist across launches: ViewerSettings is Codable and stored as JSON in @AppStorage("GLTFViewer.viewerSettings"), restored in SamplesView's init and saved on every change. Covers inspector shown/tab, comparison mode and split, three.js lighting, background, antialiasing sample count, shading/debug view, wireframe, framebuffer-only, tone mapping, environment (bundled HDRIs, gray, studio), intensity and rotation. Each field decodes on its own with its default as fallback (removed tabs, debug views, HDRIs, unsupported sample counts, out-of-range split). A picked .hdr/.exr is stored as Studio: its sandbox access would not survive a relaunch without a security-scoped bookmark. Tests: viewerSettingsRoundTrip, staleStoredValuesFallBackIndividually, pickedFilesAndUnreadableDataRestoreAsDefaults. Not checked in the running app.

---

## 130: GLTFViewer has no environment (IBL) picker

+++
status: closed
priority: low
kind: feature
labels: area:demo, area:rendering, effort:s
created: 2026-10-06T21:02:00Z
updated: 2026-10-06T21:19:26Z
closed: 2026-10-06T21:19:26Z
+++

GLTFViewer always lights models with the procedural studio environment. GLTFEnvironment already supports .studio, .uniform(color) and .equirectangular(URL) (.hdr/.exr), and the CLI has --environment and --environment-intensity, but the viewer offers no way to switch, so materials cannot be judged under different lighting (outdoor, interior, high-contrast) or against the environments other viewers use.

Wanted: an Environment section in the Display tab with a picker: Studio (procedural, default), a few bundled HDRIs (small, e.g. 1-2K CC0 equirectangulars from Poly Haven: outdoor sky, interior, neutral/overcast; size kept small or downloaded on demand like the samples), a uniform color, and 'Choose File...' for any .hdr/.exr (sandbox: user-selected file). Plus environment intensity and rotation sliders (rotation needs a frame uniform; it is also needed for EXT_lights_image_based, #86). Building an environment (prefiltering) takes time, so cache built GLTFEnvironments per source and build off the main thread with a progress indicator. The three.js comparison should get the same environment (GLTFWebReference already takes GLTFLighting; check it sends equirectangular sources, not only the studio). Persist the choice like other display settings (#129).

- `2026-10-06T21:19:26Z`: GLTFViewer's Display tab has an Environment section: Studio (procedural, default), four CC0 Poly Haven 1K HDRIs (Outdoor, Workshop, Sunset, Photo Studio; downloaded on first use to Caches/GLTFViewer/HDRIs), a plain Gray, and 'Choose HDR File' for any .hdr/.exr (sandbox scope held while it is read); intensity (0-3) and rotation (-180..180 degrees) sliders; progress and errors inline. EnvironmentLibrary builds environments off the main thread and caches them; the studio stands in until one is ready; the three.js side gets the same environment, intensity and rotation. Library: GLTFLighting.environmentRotation (yaw, radians) rotates every environment lookup (irradiance, specular, back irradiance, clearcoat, refraction fallback) and the background (frame/background uniform environmentRotation; zero matrix = identity); three.js gets scene.environmentRotation/backgroundRotation, and DamagedHelmet with Venice Sunset at 0 and 90 degrees matches three.js at 39.4 / 39.3 dB, so the conventions agree. CLI: --environment-rotation. Test: environmentRotationTurnsTheEnvironment. Not persisted across launches yet (#129). Not checked in the running app.

---

## 131: Material extensions cannot be toggled without reloading

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:s
created: 2026-10-06T21:47:05Z
updated: 2026-10-06T21:59:39Z
closed: 2026-10-06T21:59:39Z
+++

Extensions can be turned off at load time (GLTFLoadOptions.disabledExtensions, #106), and GLTFViewer reloads the model when one is toggled (#107). For material lobes (clearcoat, sheen, iridescence, anisotropy, transmission, diffuse transmission, dispersion, specular, volume) a render-time switch would be instant: a bitmask in the frame uniforms that the PBR shader checks before applying each lobe, so a viewer can flip them without reloading large models. Structural extensions (instancing, visibility, variants, compression, texture formats) stay load-time.

- `2026-10-06T21:59:39Z`: Won't fix: reloading on toggle is fine (user, 2026-10-06).

---

## 132: No format-neutral render model types

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:07:10Z
closed: 2026-10-06T23:07:10Z
+++

Part of #118. Add a MetalSprocketsPBR target (depends on MetalSprockets and the shader target, not SwiftGLTF) with PBRModel, PBRPose, PBRMaterial (today's GLTFMaterialResource: uniforms + texture slots) and PBRLight, and move the already format-neutral pieces into it: shader types, material uniforms, lighting, environment, tone mapping, debug views, bounds and camera framing. MetalSprocketsGLTF re-exports or typealiases the old names so callers keep compiling. Goldens, reference PSNR and bench unchanged.

- `2026-10-06T23:07:10Z`: Done: MetalSprocketsPBR target (product too; MetalSprocketsGLTF @_exported-imports it) with PBRBounds, PBRPose (public init), PBRMaterial (neutral init from uniforms + texture bindings, placeholder binding; glTF Material init is a convenience init in the importer), PBRLight (alias of the shader's GLTFLight), PBRGeometryBuffers, PBRLighting, PBREnvironment, PBRToneMapping, PBRDebugView, PBRFrustum, PBRCamera (glTF camera init stays in the importer). Old GLTF* names are typealiases in MetalSprocketsGLTF (PBRCompatibility.swift); the repo itself uses the new names (mechanical rename). PBRModel arrives with the builder (#133); PBREnvironmentBackground moves with the renderer (#134) since it uses the renderer's shader cache. Goldens, reference PSNR unchanged (114 tests pass).

---

## 133: Geometry merging and batching live in GLTFAsset

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:13:39Z
closed: 2026-10-06T23:13:39Z
+++

Part of #118, after #132. Move shared geometry buffers, merging (GLTFMergedGeometry) and batch building out of GLTFAsset into a PBRModelBuilder in MetalSprocketsPBR: it takes vertices in the renderer's layout, indices, skin and morph data, materials, nodes (instances by node index, instance matrices) and lights, and build() returns a PBRModel. GLTFAsset loading becomes builder calls. Tests: building a small model in code without glTF; goldens, PSNR, bench unchanged.

- `2026-10-06T23:13:39Z`: PBRModel (Primitive/Skin/Instance/Batch, opaque/blended batches, merged geometry, skins, lights, restPose stored once instead of recomputed per frame, bounds, resource collection, vertex descriptors) built by PBRModelBuilder (instances by node with optional explicit world matrix, skins, lights, resident extras; does skinned bounds, opaque/blended split, batching, merging, residency). Geometry goes through PBRGeometryBuilder (PrimitiveData in renderer layout -> primitives in shared buffers, with bounds, joint bounds, morph buffers). glTF loading is now builder calls (GLTFGeometry.makePrimitive returns PrimitiveData; GLTFSceneContents builds the model); GLTFAsset wraps model + glTF-only parts and forwards. Merging now also requires batches to share geometry buffers (always true for one glTF file). Test: PBRModelBuilderTests.buildsAModelWithoutGLTF. Goldens, PSNR unchanged; bench to be checked after #134.

---

## 134: Renderer depends on GLTFAsset

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:17:08Z
closed: 2026-10-06T23:17:08Z
+++

Part of #118, after #133. Move GLTFRenderer, draw plans, the transmission pass and environment background into MetalSprocketsPBR as PBRScene (Element) taking a PBRModel, a PBRPose, camera matrices and lighting; no SwiftGLTF import. GLTFScene stays as a convenience Element building a PBRScene from a GLTFAsset. Goldens, PSNR, bench unchanged.

- `2026-10-06T23:17:08Z`: PBRRenderer, PBRScene, PBRTransmissionPass/Target, PBRDrawPlan and PBREnvironmentBackground moved to MetalSprocketsPBR, taking a PBRModel; the target has no SwiftGLTF import. Default lighting there is the model's rest lights. MetalSprocketsGLTF keeps GLTFRenderer/GLTFScene/GLTFTransmissionPass/GLTFTransmissionTarget as typealiases with init(asset:...) convenience initializers (default lighting = the asset's lights placed by the pose, as before). Test: PBRModelBuilderTests.rendersAModelWithoutGLTF (code-built model through PBRScene). Goldens and reference PSNR unchanged (115 tests); bench within noise (CPU within +-4% on all scenes).

---

## 135: Material variants rebuild the asset

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:s
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:22:26Z
closed: 2026-10-06T23:22:26Z
+++

Part of #118, after #134. KHR_materials_variants currently builds a new asset (asset.variant(_:)). Express a variant as material overrides in PBRPose (or a per-scene material table) so switching is instant and the model stays shared. Check the variant goldens and viewer picker.

- `2026-10-06T23:22:26Z`: Material overrides: PBRModel.MaterialOverrides = [Primitive.Key: PBRMaterial] on PBRRenderer/PBRScene (not the pose: a pose forces the per-frame posed path even at rest). Per-batch draws use the override; merged geometry resolves it per record (uniforms, argument-buffer textures, double-sidedness) only when an override touches it, otherwise the prebuilt buffers. Overrides must keep the primitive's pass (PBRMaterial.canOverride: same alpha mode and transmission). GLTFAsset.materialOverrides(variant:) gives a variant's overrides relative to the materials the asset was built with, or nil when a swap would change passes (then use variant(_:), which remains). GLTFViewer switches variants through overrides (no rebuild), falling back to variant(_:) when needed; also dropped its Binding(get:set:) for an onChange. Tests: MaterialOverrideTests (overrides == rebuilt variant pixel-for-pixel on a synthetic file and every MaterialsVariantsShoe variant, merged and per batch; merged == per-batch with an override). Variant goldens unchanged. Not checked in the running app.

---

## 136: A scene can draw only one model

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:31:36Z
closed: 2026-10-06T23:31:36Z
+++

Part of #118, after #134. Let PBRScene draw several PBRModels, each with its own pose and model matrix, with merging per model; sorting of blended draws across models; one transmission pass for all. This is how scenes change structurally (add/remove a model) while models stay immutable. Test: two models in one scene match rendering each alone where they don't overlap.

- `2026-10-06T23:31:36Z`: PBRScene draws items: [PBRScene.Item] (model, pose, modelMatrix, materialOverrides); init(model:...) and the model/pose/modelMatrix/materialOverrides accessors keep one-model use unchanged. Several models: opaque drawn per item; blended batches of all items sorted back to front together (PBRScene.blendedRuns), drawn by one renderer per run of consecutive same-item batches (PBRRenderer.phase .opaque / .blended(ids)); one transmission pre-pass draws every item (PBRTransmissionPass.additionalRenderers), so glass sees other models. Known limits: the transmission pre-pass orders blended batches per model, not across models; default lighting is all items' lights untransformed by modelMatrix (as before for one model). Tests: MultiModelSceneTests (placement matches each model alone; blended order across models matches one combined model; glass sees another model). One-model element tree kept cheap: first renderer directly + ForEach over the rest (a conditional cost ~3% CPU, a ForEach of one ~5%). Bench: within ~2-3% of the previous commit measured in the same session, about the run-to-run noise here; GPU timings on the small scenes vary +-50% run to run in this session, also before this change.

---

## 137: No second producer of PBRModel

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T22:55:52Z
updated: 2026-10-06T23:35:15Z
closed: 2026-10-06T23:35:15Z
+++

Part of #118, after #133. Prove the model is format-neutral with a second producer: GLTFViewer's BasicShape built through PBRModelBuilder directly (no glTF round trip), and later the scene graph (#121) or USD. Rename leftover GLTF-prefixed renderer types once the split settles.

- `2026-10-06T23:35:15Z`: Second producer: BasicShape.model(device:) builds each viewer shape through PBRGeometryBuilder/PBRModelBuilder with no glTF; BasicShapeModelTests checks every shape renders pixel-identical to the same mesh written as .glb and loaded through MetalSprocketsGLTF. Added GLTFMaterialUniforms.defaults(baseColor:metallic:roughness:) and textureSlots in PBR (glTF/spec defaults; PBRModelBuilderTests.defaultUniformsMatchGLTF checks them field by field against a glTF material-less load), so code-built materials need no hand-filled uniforms. GLTFViewer still loads its shapes from the bundled .glb files (that keeps the three.js comparison and statistics). Renaming the remaining GLTF-prefixed shader types and target is #138.

---

## 138: Renderer still uses GLTF-prefixed shader types and target name

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-10-06T23:35:14Z
updated: 2026-10-07T07:52:16Z
closed: 2026-10-07T07:52:16Z
+++

After #118 the renderer lives in MetalSprocketsPBR, but its shader-facing types keep glTF names: the MetalSprocketsGLTFShaders target and the C/Metal types in GLTFShaderTypes.h (GLTFVertex, GLTFSkinVertex, GLTFMorphDelta, GLTFMaterialUniforms, GLTFTextureSlot, GLTFMaterialTextureIndex, GLTFLight, GLTFInstance, GLTFFrameUniforms, GLTFShaderToneMapping, GLTFShaderDebugView, ...), the GLTFPBR/GLTFIBL shader namespaces, and GPU labels ('GLTF Opaque', 'GLTF Vertices'). Code building a PBRModel without glTF writes GLTFVertex and GLTFMaterialUniforms. Wanted: rename to PBR* (target MetalSprocketsPBRShaders), keeping typealiases for the old Swift-visible names; goldens, PSNR and bench unchanged.

- `2026-10-07T07:52:17Z`: Renamed: target MetalSprocketsGLTFShaders -> MetalSprocketsPBRShaders (bundle, umbrella header, .mm), headers PBRShaderTypes.h / PBRShaderSupport.h, C/Metal types GLTF* -> PBR* (PBRVertex, PBRSkinVertex, PBRMorphDelta, PBRMaterialUniforms, PBRTextureSlot, PBRMaterialTextureIndex, PBRAlphaMode, PBRLight (replacing the PBRLight typealias), PBRLightType, PBRInstance, PBRViewUniforms, PBRFrameUniforms, PBRMorphUniforms, PBRMaterialResources, PBRPrefilterParameters, PBRBackgroundUniforms, PBRShaderToneMapping, PBRShaderDebugView), constants kGLTF* -> kPBR*, shader namespaces GLTFPBR/GLTFIBL/GLTFSupport -> PBR/PBRIBL/PBRSupport, GPU labels 'GLTF ...' -> 'PBR ...'. MetalSprocketsPBR re-exports MetalSprocketsPBRShaders; MetalSprocketsGLTF keeps typealiases for the old Swift-visible type names (constants are not aliased). Mechanical perl rename, then build, goldens and PSNR unchanged (129 + 19 tests).

---

## 139: GLTFViewer's built-in shapes look plain

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-07T00:01:03Z
updated: 2026-10-07T03:10:09Z
closed: 2026-10-07T03:10:09Z
+++

The Basic Shapes in GLTFViewer's sidebar (sphere, cube, plane, cylinder, cone, torus) are each one mesh with one flat gray material (0.8, metallic 0, roughness 0.5). They are useful for checking lighting and debug views but look dull as a first impression and show off none of the renderer. Ideas: a few material presets per shape (polished metal, glass, clearcoat car paint, velvet sheen, iridescent), a 'material spheres' grid (metallic x roughness), a showcase scene combining shapes on a ground plane, procedural textures (checker, normal map) to exercise texture paths. Built with PBRModelBuilder or written as .glb like today (BasicShape.glb / just basic-shapes).

- `2026-10-07T03:10:09Z`: GLTFViewer sidebar has a Showcase section with two generated scenes (written as .glb to Caches on first use by ShowcaseScene / GLBBuilder, so three.js comparison and the Document tab work): Material Grid (5x5 spheres, metallic by row, roughness by column) and Showcase (shapes on a checkered 4.5 m floor: gold, glass with volume tint, clearcoat car paint torus, velvet sheen cube, iridescent cone, satin plastic cylinder). Tests: ShowcaseSceneTests (both load without warnings, expected materials/extensions/texture). Not checked in the running app.

---

## 140: Transmissive glass is opaque in visionOS immersive mode

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:s
created: 2026-10-07T01:13:58Z
updated: 2026-10-07T02:29:10Z
closed: 2026-10-07T02:29:10Z
+++

In GLTFViewer's immersive space (PBRImmersiveScene) the CarConcept windows look opaque and mirrored, while alpha-blended glass in other samples shows the room through it. Stereo rendering has no transmission pre-pass, so KHR_materials_transmission surfaces refract the environment map and write alpha 1; the compositor never blends them with passthrough or with the model's own interior. Proposed fix: in stereo, draw transmissive materials in the blended pass with alpha ~ (1 - transmission) (premultiplied color), so the room and geometry behind show through, without refraction or tint. Longer term, a stereo transmission pre-pass (per-eye layered target) would restore refraction of the model itself.

- `2026-10-07T01:55:03Z`: Implemented (untested on device): in stereo (no transmission pre-pass) the renderer draws transmissive surfaces as coverage. GLTFFrameUniforms.transmissionAsCoverage: the shader skips environment refraction and writes premultiplied color with alpha = 1 - average(transmission x base color x volume attenuation x (1 - specular weight)); the draw plan moves transmissive opaque batches out of the opaque/merged paths into the back-to-front blended order as premultiplied runs (blend source factor one). So the model's own geometry and passthrough show through glass; color tint of what is behind is reduced to its average, no refraction. Also fixed: blended pipelines now use the renderer's depth function (reverse-Z everywhere since 03de3159). Mono rendering unchanged. Tests: TransmissionCoverageTests (stereo glass shows the red quad behind; over nothing it is mostly transparent; mono still refracts the environment).
- `2026-10-07T02:29:10Z`: Device follow-up: glass over passthrough was invisible (visible only where opaque geometry behind it had written depth), with sawtooth cuts along depth edges. Blended surfaces wrote no depth; the visionOS compositor showed our color only where depth was written. Fix: in stereo, blended pipelines write depth (writesBlendedDepth); they are drawn back to front. Confirmed fixed on device by the user. Foveation was not involved.

---

## 141: Immersive lighting does not use the real room (ARKit environment probes)

+++
status: closed
priority: low
kind: feature
labels: area:rendering, effort:m
created: 2026-10-07T01:13:58Z
updated: 2026-10-07T03:55:14Z
closed: 2026-10-07T03:55:14Z
+++

In GLTFViewer's immersive space models are lit by the chosen environment (studio, HDRI or the file's), not the room around the viewer, so reflections don't match passthrough. visionOS ARKit's EnvironmentLightEstimationProvider delivers EnvironmentProbeAnchor values with an HDR cube texture of the surroundings (apps cannot read the passthrough camera directly). Wanted: an option to light from it: convert the probe cube to a PBREnvironment source on the GPU and re-prefilter as it updates (throttled, e.g. every 1-2 s). To check: whether it needs world-sensing authorization, probe update rate and resolution, and prefilter cost per update.

- `2026-10-07T01:26:17Z`: Investigation (visionOS 27 SDK headers + Apple docs): ARKit EnvironmentLightEstimationProvider (visionOS 2+, isSupported, requiredAuthorizations known only at runtime - probably world sensing, which would need NSWorldSensingUsageDescription and session.requestAuthorization) delivers EnvironmentProbeAnchor updates. Each anchor has environmentTexture: a MTLTextureTypeCube of linear HDR RGB in Display P3, nil in poorly lit rooms, and only valid while the anchor lives (copy/convert it in the update handler); cameraScaleReference = camera brightness of an RGB 1 texel, for consistent brightness across updates; the anchor is always at the device's position. visionOS 27 adds a transform-correction variant of originFromAnchorTransform. Cost here (M5 Max): a full PBREnvironment rebuild from a 512x256 source is ~8 ms (specular 256 / irradiance 32), ~4 ms at 64/16, including the BRDF lookup which could be cached once; expect several times more on Vision Pro, fine every 1-2 s on a background queue. Plan: (1) PBREnvironment source from a cube texture: a GPU kernel to the equirect source with a P3-to-sRGB-linear matrix and a brightness scale; cache the BRDF lookup. (2) visionOS RoomLighting: ARKitSession + provider, throttled updates converting each probe into a PBREnvironment off the render loop, published to the immersive scene. (3) Viewer: 'Room' environment choice in the immersive space, falling back to the window's environment when the provider is unsupported, unauthorized, or the texture is nil. Device-only unknowns: authorization prompt, update rate, texture size, how cameraScaleReference maps to our intensity, behaviour in dim rooms.
- `2026-10-07T01:33:14Z`: Implemented, untested on device: PBREnvironment(cube:colorMatrix:scale:) (GPU cube-to-equirect kernel, PBREnvironment.displayP3ToLinearSRGB; BRDF lookup now built once per device), PBRRoomLighting (visionOS: ARKitSession + EnvironmentLightEstimationProvider, requests requiredAuthorizations, rebuilds at most once a second, keeps the last environment when the texture is nil, logs the probe's size/format/mips/cameraScaleReference and rebuild time under subsystem MetalSprocketsPBR category RoomLighting). GLTFViewer: runs it while the immersive space is open; 'Room Lighting' toggle in the bar (on, remembered) swaps the room's environment in; NSWorldSensingUsageDescription added. Test: CubeEnvironmentTests (faces on their axes, scale, P3 conversion keeps gray). Brightness uses scale 1 (cameraScaleReference not applied yet).
- `2026-10-07T01:37:33Z`: Device results (Vision Pro): requiredAuthorizations = [worldSensing] (granted via the prompt); probe texture 8x8 cube, rgba16Float, 4 mips; cameraScaleReference ~2742; rebuild 7-24 ms. At 8x8 the probe gives overall color and brightness and which side is brighter, no reflection detail, so the effect is subtle (best seen as brightness/color change, e.g. lamp on/off). Taking the headset off backgrounds the app and the rebuilds then failed (kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted); fixed by stopping room lighting outside the active scene phase. cameraScaleReference not applied (brightness looked plausible as-is).
- `2026-10-07T02:57:43Z`: Tried applying cameraScaleReference as a direct multiplier (values ~2000-2700): far too bright on device. Removed; the probe's radiance is used as-is.
- `2026-10-07T03:55:14Z`: Done: room lighting from ARKit environment probes is implemented (PBRRoomLighting, viewer Room Lighting toggle) and verified on Vision Pro (worldSensing authorization, 8x8 rgba16Float probe, rebuilds 7-24 ms). cameraScaleReference as a multiplier was tried and removed (far too bright). Remaining bug: #143 (sessions pile up after stop/restart).

---

## 142: GLTFViewer keeps rendering the window while immersive

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-07T02:17:57Z
updated: 2026-10-07T02:32:47Z
closed: 2026-10-07T02:32:47Z
+++

On visionOS, while GLTFViewer's immersive space is open (ImmersiveController.isOpen), the model window's RenderView keeps drawing the same model every frame, doubling GPU work for nothing the user is looking at. Wanted (demo only): stop the window's rendering while immersive is on, e.g. show a placeholder (ContentUnavailableView 'Viewing in Immersive Space', as MetalSprockets' VisionOSDemoView does) or pause the RenderView, and resume when the space closes. The inspector and toolbar stay usable.

- `2026-10-07T02:32:47Z`: While the immersive space is open, the model window shows a 'Viewing in Immersive Space' placeholder instead of its RenderView (visionOS only); toolbar, inspector window and immersive controls stay usable; rendering resumes on exit. Not checked on device.

---

## 143: Room lighting ARKit sessions pile up after stop and restart

+++
status: closed
priority: medium
kind: bug
labels: area:rendering, effort:s
created: 2026-10-07T03:06:32Z
updated: 2026-10-07T15:07:38Z
closed: 2026-10-07T15:07:38Z
+++

GLTFViewer on Vision Pro logs bursts of 5-9 'Room environment rebuilt' lines within a second, with rebuild time climbing from ~7 ms to ~40 ms, after the immersive space was closed and reopened or the headset taken off and on. PBRRoomLighting.run() only checks Task.isCancelled when an anchor update arrives and does not stop its ARKitSession on cancellation, so stopRoomLighting() leaves the old run going while a new one starts. Fix: stop the session in a task cancellation handler so anchorUpdates ends, and refuse a second concurrent run().

- `2026-10-07T15:07:39Z`: run() now stops its ARKitSession from a task cancellation handler (ends anchorUpdates immediately) and refuses a second concurrent run(). No unit test: ARKit environment probes exist only on a Vision Pro (unsupported in the simulator), so this is untested; verify on device that close/reopen no longer gives bursts of rebuilds.

---

## 144: GLTFViewer believes the immersive space is closed while it is open

+++
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-07T03:06:32Z
updated: 2026-10-07T17:34:05Z
closed: 2026-10-07T17:34:05Z
+++

On Vision Pro the log repeatedly shows 'Unable to present another Immersive Space when one is already requested or connected' when pressing View Immersive: ImmersiveController.isOpen was false while the space was still open. The fallback (dismiss, then open again) recovers, but restarts world tracking and room lighting. The triggering action is unknown (candidates: Digital Crown exit, system dismissal when the headset is removed). Wanted: track the space's real lifetime, e.g. from the immersive scene's phase or the render loop ending, instead of only the button.

- `2026-10-07T15:08:08Z`: Looked at tracking the space's real lifetime. The immersive scene's content is MetalSprockets' ImmersiveRenderContent (a CompositorLayer), which has no SwiftUI view to hang onAppear/onDisappear or scenePhase on, and exposes no signal when its render loop ends (layerRenderer .invalidated). Punting: a proper fix needs a MetalSprockets API change (e.g. ImmersiveRenderContent.onRenderLoopStart/End callbacks) plus a pin bump, and the triggering action is still unknown, so it can only be verified on device. Unblocker: OK to add those lifecycle callbacks to MetalSprockets and have ImmersiveController.isOpen follow them? A per-frame heartbeat in the viewer would work without MS changes but needs polling.
- `2026-10-07T17:34:05Z`: MetalSprockets af0e82c adds ImmersiveRenderContent.onRenderLoopChange (true when the render loop starts, false when it ends, however the space closed). GLTFImmersiveSpace forwards it to ImmersiveController.renderLoopChanged, which counts running loops (an old loop can end after a reopen's new one starts) and sets isOpen = count > 0, starting/stopping room lighting; it doesn't clear the shown model, so a reopen can't wipe it. No test: visionOS-only code needing a real immersive space. Needs checking on device: Digital Crown exit, headset off/on.

---

## 145: Glass does not refract in visionOS immersive mode

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:l
created: 2026-10-07T03:06:32Z
updated: 2026-10-07T17:56:31Z
closed: 2026-10-07T17:56:31Z
+++

In stereo (PBRImmersiveScene) there is no transmission pre-pass, so KHR_materials_transmission surfaces are drawn as coverage (#140): blended over what is behind them with an averaged tint, no refraction or roughness blur of the model's own geometry. Wanted: a stereo transmission pre-pass: per-eye opaque scene into a layered (two-slice) target with mips, sampled by eye in the PBR shader, like the mono PBRTransmissionPass.

- `2026-10-07T03:55:14Z`: Related: #101 (glass not visible through other glass): both need transmissive surfaces to see other transparent ones; a stereo transmission pre-pass should take #101 into account.
- `2026-10-07T17:56:31Z`: Stereo transmission pre-pass. PBRTransmissionTarget textures are now 2D arrays (viewCount slices; 1 in mono), the pass renders each eye into its slice with vertex amplification (full-target viewports), and the shader samples transmissionScene at the fragment's eye. PBRImmersiveScene adds the pre-pass (cached target sized to an eye's viewport) for models with transmission. In stereo, glass still blends as coverage so passthrough shows through; the target clears to alpha 0, and where it has geometry (alpha) the glass shows the refracted model instead; with a background (full immersion) that is everywhere. Mono unchanged: goldens and reference PSNR exact. StereoTests.stereoTransmissionMatchesSingleViewRenders: each eye of a two-view render equals a one-view render for that eye (fails when sampling slice 0 for both eyes), glass shows the red behind it, and differs from coverage-only. #101 (glass behind glass) not addressed. Not checked on device: look, GPU cost of the extra stereo pass at eye resolution, interaction with foveation.

---

## 146: Immersive rendering has no antialiasing

+++
status: open
priority: low
kind: enhancement
labels: area:rendering, effort:m, deferred
created: 2026-10-07T03:06:32Z
updated: 2026-10-13T19:15:30Z
+++

In GLTFViewer's immersive space, edges show stair-stepping, more visible toward the edges of the view where foveation lowers resolution. MetalSprockets' ImmersiveLayerConfiguration does not request multisampling, and PBRImmersiveScene renders at one sample. Wanted: MSAA (or another antialiasing) in the immersive path, checking that CompositorServices layered targets and foveation (rasterization rate maps) support it, and the GPU cost on Vision Pro.

- `2026-10-07T15:08:20Z`: Checked: MetalSprockets' immersive runtime has no multisample support at all (no sampleCount anywhere in MetalSprocketsUI/VisionOS). Punting: MSAA needs MetalSprockets changes (layered multisample color/depth textures matching the drawable, resolve into the CompositorServices textures, interaction with the rasterization rate map, every PBR pipeline built with the sample count) and the GPU cost can only be measured on a Vision Pro. Unblocker: OK to do this as a MetalSprockets issue first (ImmersiveRenderContent sampleCount option), then adopt it here and measure on device?

---

## 147: Immersive model is placed relative to where the space opened, not where the viewer looks

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-07T03:06:33Z
updated: 2026-10-07T05:34:03Z
closed: 2026-10-07T05:34:03Z
+++

GLTFImmersiveSpace places the model at a fixed position in the space's coordinates (0, 1.1, -0.6 m), i.e. relative to where the viewer stood when the space opened. If the viewer has turned or moved, the model appears off to the side or behind. Wanted: place it in front of the viewer's head when the space opens (or on request), using the device anchor (WorldTrackingProvider) at that time.

- `2026-10-07T05:34:03Z`: The immersive space now places models in front of the viewer: on the first frame with a device anchor after opening, ImmersivePlacement.inFront(of:) fixes a placement 0.6 m ahead along the head's horizontal facing, 10 cm below eye height, upright, front (+Z) facing the viewer. It stays fixed (walk around the model) and survives switching demos; reopening the space places it afresh. Before world tracking gives a head position, the old fixed spot is used. Tests: ImmersivePlacementTests. Not checked on device.

---

## 148: Dragging inspector sliders resizes the inspector

+++
status: closed
priority: medium
kind: bug
labels: area:demo, effort:s
created: 2026-10-07T15:13:44Z
updated: 2026-10-07T16:10:45Z
closed: 2026-10-07T16:10:45Z
+++

In GLTFViewer, dragging a slider in the inspector (e.g. exposure, environment intensity or rotation) makes the inspector change size while dragging. Expected: the inspector keeps its width. Cause not investigated yet; one suspect is a value label whose text width changes with the value.

- `2026-10-07T16:10:45Z`: Measured the Display inspector's fitting size across slider values (NSHostingView): width was constant, but the Rotation label (fixed 36 pt) wrapped to two lines from about -100° to -180°, growing the form by 16 pt, so the inspector re-laid out while dragging. Slider value labels are now SliderValueLabel, sized to their widest text, one line, fixed size. InspectorLayoutTests checks the size is identical across exposure/rotation/intensity values (604 vs 620 pt before). Not checked by dragging in the running app.
- `2026-10-07T16:15:31Z`: Still resized on every Exposure drag (reported). The Display form's ideal width is ~490 pt, past the inspector column's max of 420; inspector content now has a fixed ideal width (min 260, ideal 300). inspectorContentAsksForTheColumnWidth checks it (490 before). Also fixed: the first commit shipped a print-only throwaway test instead of InspectorLayoutTests' assertions. Not verified by dragging in the app.

---

## 149: Scene graph inspector tab has no selection or detail view

+++
status: closed
priority: medium
kind: enhancement
labels: area:demo, effort:m
created: 2026-10-07T15:13:48Z
updated: 2026-10-07T17:09:33Z
closed: 2026-10-07T17:09:33Z
+++

Split GLTFViewer's scene graph inspector tab vertically into two views: the node list on top, where a node can be selected, and a detail view below showing the selected node's properties.

- `2026-10-07T17:09:33Z`: Document tab is now the outline over a detail view (VSplitView on macOS, stacked on visionOS). Selecting an item shows its glTF JSON properties (index first, then sorted keys; nested values as compact JSON), via DocumentReference on each outline item and DocumentOutline.properties(of:in:). Test: itemsHaveReferencesAndProperties. Not checked in the running app.

---

## 150: Animation controller lacks state machine, additive layers, root motion; viewer doesn't cross-fade

+++
status: closed
priority: low
kind: feature
labels: area:animation, effort:m
created: 2026-10-07T15:19:25Z
updated: 2026-10-07T17:41:34Z
closed: 2026-10-07T17:41:34Z
+++

Follow-up to #119, which added GLTFAsset.pose(layers:) and GLTFAnimationController (cross-fade, speed, looping, 1D phase-synced blend). Still missing from #119's 'later' list: a small state machine (states with clips, transitions with durations and conditions), additive layers, and root motion. GLTFViewer also still switches clips with a cut; it could use the controller to cross-fade.

- `2026-10-07T17:41:35Z`: Library: GLTFAnimationLayer.Mode.additive (offsets from rest scaled by weight: translation/weights add, rotation/scale compose; nodes only); root motion via pose(layers:rootMotionNode:) (pins the node's x/z to rest), GLTFAsset.rootTranslation(layers:node:), and GLTFAnimationController.rootMotionNode/rootMotion measured in advance(by:in:) across loop wraps; controller additive tracks (setAdditive); GLTFAnimationStateMachine (named states with clip/speed/loops, ordered transitions with fade and condition on parameters, normalizedTime, stateTime). Viewer: switching clips cross-fades over 0.3 s (the old clip keeps playing while fading). Tests: additiveLayersAddOffsetsFromRest, extractsRootMotion (incl. wrap), stateMachineTransitions, viewer switchingClipsCrossFades. Viewer cross-fade not checked in the running app.

---

## 151: GLTFViewer has no EDR output on XDR displays

+++
status: closed
priority: low
kind: feature
labels: area:rendering, area:demo, effort:m
created: 2026-10-07T15:23:38Z
updated: 2026-10-07T17:28:38Z
closed: 2026-10-07T17:28:38Z
+++

Follow-up to #128 (which added PBRToneMapping.none and float offscreen/EXR output). On screen, GLTFViewer still draws into bgra8Unorm_srgb. Wanted (opt-in): an rgba16Float drawable with CAMetalLayer.wantsExtendedDynamicRangeContent and an extended linear sRGB color space, and a tone mapper whose white point follows the display headroom (NSScreen.maximumExtendedDynamicRangeColorComponentValue). Needs a MetalSprockets RenderView hook: it has metalColorPixelFormat and metalColorspace, but nothing sets wantsExtendedDynamicRangeContent.

- `2026-10-07T17:28:38Z`: MetalSprockets 96e0e87 adds RenderView.metalWantsExtendedDynamicRangeContent (pinned in all three Package.resolved). GLTFViewer Display tab (macOS): Extended Dynamic Range toggle, persisted: rgba16Float drawable, extendedLinearSRGB colorspace, wantsExtendedDynamicRangeContent; MetalFX targets follow the format; PSNR offscreen stays 8-bit. HDR highlights need Tone Mapping = None (HDR); the other tone mappers stay within 1. Not done: a tone mapper whose white point follows NSScreen.maximumExtendedDynamicRangeColorComponentValue. Tests: settings round trip + float formats; upscalesIntoFloatTargets (library). Not checked on an XDR display.

---

## 152: Verify on device that immersive no longer aborts on line and point primitives

+++
status: open
priority: medium
kind: task
labels: area:rendering, effort:xs, deferred
created: 2026-10-07T18:29:00Z
updated: 2026-10-14T17:08:17Z
+++

On Vision Pro, opening the model after the Showcase in the immersive space aborted with Metal validation: 'Only triangles may be drawn when using a rasterization rate map' (drawIndexedPrimitives). Fixed in e6f4bb6d: PBRImmersiveScene sets PBRRenderer.drawsTrianglesOnly, so point and line primitives are skipped in immersive (still drawn in windows); TrianglesOnlyTests covers it on macOS. To verify on device: open that model (and a points/lines sample such as MeshPrimitiveModes) in immersive with foveation on; no abort, triangles visible, lines and points absent.

---

## 153: Expose GLTFAnimationClip channels as public API

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:api
created: 2026-10-12T15:24:14Z
updated: 2026-10-13T19:45:54Z
closed: 2026-10-13T19:45:54Z
+++

GLTFAnimationClip.channels, Channel (target, keyframes) and Target are internal, so code outside this module cannot read glTF animations.

MetalSprocketsSceneGraph #16 loads a GLTFAsset into a SceneGraph (format-neutral nodes, TRS, morph weights, skins, animation clips). It needs, per channel: the target (node index + path translation/rotation/scale/weights; later material/light/camera/visibility pointers), the keyframe times, the flat values, and the interpolation (step/linear/cubic spline).

Want: make GLTFAnimationClip.channels, Channel and Target public (or add a public read-only view with those fields). Keyframe data should be reachable without importing SwiftGLTF types if possible.

- `2026-10-13T19:45:54Z`: GLTFAnimationClip.channels, Channel (target, times, values, componentsPerValue, interpolation, sample(at:)), Target, NodeProperty and Interpolation are public; no SwiftGLTF types in the API.

---

## 154: PBR geometry input uses its own format instead of MetalMesh

+++
status: closed
priority: medium
kind: task
created: 2026-10-13T00:52:56Z
updated: 2026-10-13T16:25:12Z
closed: 2026-10-13T16:25:12Z
+++

PBRGeometryBuilder takes PBRGeometryBuilder.PrimitiveData: [PBRVertex], [UInt32] indices, primitive type, [PBRSkinVertex]?, [[PBRMorphDelta]], hasTangents, hasNormals, materialIndex, variantMaterials and label. SwiftMesh's MetalMesh can now hold all the mesh data in this list: any vertex layout, several submeshes with primitive types, bounds per submesh, morph targets with default weights, and skin binding data (inverse bind matrices, joint names). So the PBR stack has a second mesh format that SwiftMesh users cannot feed in directly. For example, SwiftMesh shapes cannot be drawn with the PBR renderer.

materialIndex and variantMaterials are in PrimitiveData, but they are model data, not mesh data (see SwiftMesh #148).

- `2026-10-13T16:25:12Z`: Fixed: PBRGeometryBuilder.add(attributes:indices:primitiveType:morphTargets:label:) takes MetalMesh.VertexAttributeData and fills in missing attributes; build() returns primitives with MetalMesh views of the shared buffers; the glTF loader passes attribute arrays and keeps material indices on its side.

---

## 155: PBR shaders need all six vertex attributes at fixed indices

+++
status: closed
priority: medium
kind: task
created: 2026-10-13T00:52:57Z
updated: 2026-10-13T16:25:12Z
closed: 2026-10-13T16:25:12Z
+++

VertexIn in PBR.metal reads position, normal, tangent (float4), texCoord0, texCoord1 and color at attributes 0-5, and SkinnedVertexIn adds joints and weights at 6-7. A MetalMesh's VertexDescriptor contains only the attributes the caller gave, in the caller's order, and maps them to Metal attribute indexes by array position. A MetalMesh without (for example) colors or a second UV set does not match the pipeline. Today GLTFGeometry fills in the defaults (white color, zero tangent) when it builds PBRVertex values.

- `2026-10-13T16:25:12Z`: Fixed: PBRGeometryBuilder.add(attributes:indices:primitiveType:morphTargets:label:) takes MetalMesh.VertexAttributeData and fills in missing attributes; build() returns primitives with MetalMesh views of the shared buffers; the glTF loader passes attribute arrays and keeps material indices on its side.

---

## 156: Joint index formats differ between MetalMesh and PBR

+++
status: closed
priority: medium
kind: task
created: 2026-10-13T00:52:57Z
updated: 2026-10-13T00:54:38Z
closed: 2026-10-13T00:54:38Z
+++

MetalMesh stores joint indexes as SIMD4<UInt16> (.jointIndices). PBRSkinVertex.joints and SkinnedVertexIn.joints are float4. I have not checked whether Metal vertex fetch converts a ushort4 attribute to a float4 shader input. If it does not, skinned MetalMesh data cannot go to the PBR skinned pipeline unchanged.

- `2026-10-13T00:54:38Z`: Not a problem: a .ushort4 vertex attribute read as float4 in the shader gives exact values (tested [0,1,2,3] and [7,65535,300,42] through a stage_in vertex function, with Metal API validation on; pipeline creation accepted it). So MetalMesh's SIMD4<UInt16> joints work with PBR's SkinnedVertexIn as they are. Tested on this Mac's GPU only.

---

## 157: MetalMesh input to PBR would copy each primitive twice at load

+++
status: closed
priority: medium
kind: task
depends: 154
created: 2026-10-13T00:53:04Z
updated: 2026-10-13T16:25:12Z
closed: 2026-10-13T16:25:12Z
+++

PBRGeometryBuffers puts every primitive of an asset into one vertex buffer, one index buffer and one skin buffer (shared storage). Batched and merged draws (PBRMergedGeometry) depend on this. A MetalMesh made with the array init allocates its own MTLBuffers. If the loader makes a MetalMesh for each primitive and PBR then copies the data into its shared buffers, each primitive is allocated and copied twice at load, and the first set of buffers is thrown away. MetalMesh can point into shared buffers (vertexBufferOffsets, Submesh.indexBufferOffset), but nothing builds MetalMeshes that way now.

- `2026-10-13T16:15:28Z`: Partly done (MetalSprocketsPBR 534ead6f): PBRGeometryBuilder.build() now gives each PBRModel.Primitive a MetalMesh that views the shared buffers through offsets, with no copy. Still open: PBR takes PrimitiveData as input, not MetalMesh or attribute arrays (#154).
- `2026-10-13T16:25:12Z`: Fixed: PBRGeometryBuilder.add(attributes:indices:primitiveType:morphTargets:label:) takes MetalMesh.VertexAttributeData and fills in missing attributes; build() returns primitives with MetalMesh views of the shared buffers; the glTF loader passes attribute arrays and keeps material indices on its side.

---

## 158: glTF loader builds PBR PrimitiveData instead of MetalMesh

+++
status: closed
priority: medium
kind: task
depends: 154
created: 2026-10-13T00:53:04Z
updated: 2026-10-13T16:25:12Z
closed: 2026-10-13T16:25:12Z
+++

GLTFGeometry.makePrimitive turns each glTF primitive into PBRGeometryBuilder.PrimitiveData: it packs PBRVertex values, makes PBRSkinVertex values and [[PBRMorphDelta]], and stores the material and variant indexes in the data. glTF skins (inverse bind matrices) are handled apart from the primitive data. None of this makes a SwiftMesh MetalMesh, so glTF geometry cannot be used by MetalMesh-based code (and is limited to the PBR vertex layout).

- `2026-10-13T16:25:12Z`: Fixed: PBRGeometryBuilder.add(attributes:indices:primitiveType:morphTargets:label:) takes MetalMesh.VertexAttributeData and fills in missing attributes; build() returns primitives with MetalMesh views of the shared buffers; the glTF loader passes attribute arrays and keeps material indices on its side.

---

## 159: PBRGeometryBuilder is a separate geometry front end instead of taking MetalMesh

+++
status: closed
priority: medium
kind: task
created: 2026-10-13T16:36:18Z
updated: 2026-10-13T18:13:29Z
closed: 2026-10-13T18:13:29Z
+++

Question (schwa): do we need PBRGeometryBuilder, or can PBR just use a MetalMesh?

PBRGeometryBuilder now takes MetalMesh.VertexAttributeData arrays and gives back primitives with MetalMesh views. But callers that already have a MetalMesh cannot hand it to PBR. They must keep the attribute arrays and add them again. The builder now does three things:

1. It packs many primitives into one set of shared buffers (PBRGeometryBuffers), which batched and merged draws need. A MetalMesh is one mesh, and SwiftMesh has nothing that packs many meshes into shared buffers.
2. It converts to PBR's fixed vertex layout (PBRVertex, PBRSkinVertex), because the pipelines use one fixed vertex descriptor and not the descriptor of each mesh.
3. It makes PBR-specific data: bounds grown for morph targets, bounds for each joint, and the packed PBRMorphDelta buffer.

Item 3 does not need its own type. Items 1 and 2 are why PBR cannot take MetalMesh values as they are. Related: SwiftMesh #155 (no CPU path from Mesh to vertex arrays).

- `2026-10-13T17:09:01Z`: What actually needs sharing: merged draws (PBRRenderer.mergedDrawCalls) issue one Metal 4 drawIndexedPrimitives per record with an index buffer GPU address (indexBuffer.gpuAddress + indexStart * 4), so each record could use its own index buffer. There are no indirect or ICB draws that would need one buffer. The vertex buffer (and skin buffer) must be shared: the merged pipeline binds it once at index 0 and records reach their vertices by baseVertex, which is what keeps merged geometry to one element. One index buffer only saves allocations and residency entries. So taking MetalMesh values needs several meshes to share vertex buffers; index buffers can stay per submesh (see SwiftMesh #156).
- `2026-10-13T18:13:29Z`: PBRGeometryBuilder.add(_: MetalMesh) takes MetalMesh values (one primitive per submesh, attributes read back with vertexAttributeData()). PBR keeps its own shared-buffer packing: MetalMesh.packingVertexBuffers would add a copy for array input and does not cover the shared index and skin buffers.

---

## 160: Viewer's basic shapes repeat SwiftMesh's shape generators

+++
status: closed
priority: low
kind: task
created: 2026-10-13T16:56:27Z
updated: 2026-10-13T17:36:40Z
closed: 2026-10-13T17:36:40Z
+++

ShapeMesh in GLTFViewerSupport (Showcase/BasicShape.swift) has its own sphere, cube, plane, cylinder, cone and torus generators, and SwiftMesh's Mesh has generators for the same shapes. Positions, bounds and winding match (SwiftMesh's quad is in XY, ShapeMesh's plane is in XZ), but SwiftMesh cannot replace ShapeMesh yet:

- SwiftMesh #153: the generators' UV conventions differ (some mirrored); ShapeMesh uses glTF's v down.
- SwiftMesh #154: .smoothNormals smooths across hard edges (cylinder caps, cone apex); ShapeMesh keeps them hard.
- SwiftMesh #155: there is no CPU path from Mesh to the vertex arrays that PBRGeometryBuilder takes.

The shapes also make the .glb files in Resources/BasicShapes (just basic-shapes), so changing the generator changes those files and maybe golden images.

- `2026-10-13T17:36:40Z`: ShapeMesh is now built from SwiftMesh's generators via Mesh.vertexArrays(); bundled .glb files regenerated.

---

## 161: PBR primitive meshes have no morph targets

+++
status: closed
priority: low
kind: task
created: 2026-10-13T16:56:28Z
updated: 2026-10-13T18:13:29Z
closed: 2026-10-13T18:13:29Z
+++

PBRModel.Primitive.mesh (a MetalMesh view of the shared buffers) leaves morphTargets nil, even for primitives with morph targets. PBR keeps its own packed PBRMorphDelta buffer (morphBuffer) and morphTargetCount instead. Code that reads a primitive as a MetalMesh sees no morph targets. glTF default morph weights (mesh.weights) also do not reach the mesh.

MetalMesh.skin is empty too. In PBR a skin (joint nodes, inverse bind matrices) belongs to the model and is chosen per node, so it may not apply to one primitive.

- `2026-10-13T18:13:29Z`: Primitive meshes now carry morphTargets, with glTF mesh.weights as default weights. Skins stay model-level.

---

## 162: Centralize KHR_animation_pointer target handling

+++
status: closed
priority: low
kind: task
labels: area:architecture
created: 2026-10-14T15:57:17Z
updated: 2026-10-14T17:08:17Z
closed: 2026-10-14T17:05:38Z
+++

Pointer property strings are listed and applied in several unconnected places: GLTFAnimationClip.target(pointer:) with lightProperties/cameraProperties, PBRMaterial.canAnimate/animatableFactors/AnimatedState (GLTFMaterialAnimation.swift), GLTFMaterialTextureSlot.pointerPaths, GLTFAsset.lights(pose:properties:) (string switch), and Camera.applying(_:) (JSON round-trip). Parsing and applying can drift apart silently; adding a property needs 2-3 edits.

Goal: one internal module that parses a pointer once into a typed setter, used by both parse and apply. Boundary tests: pointer string + value -> posed light/camera/material uniforms.

Constraint: no public API break. Keep all existing public types, members and behavior; changes are internal, or additive with old API forwarding. GLTFAnimationClip.Target (public, string payloads) must stay as is.

---

## 163: Single descriptor per material extension

+++
status: closed
priority: low
kind: task
labels: area:architecture
created: 2026-10-14T15:57:17Z
updated: 2026-10-14T17:08:17Z
closed: 2026-10-14T17:05:38Z
+++

Adding a material extension touches ~5 places: the KHRMaterials*.swift Codable type, defaults in PBRMaterial.init(material:textures:), GLTFMaterialTextureSlot.all, PBRMaterial.animatableFactors, and GLTFAsset.builtInExtensions. Spec defaults, slots, pointer paths and support are kept in sync by hand.

Goal: an internal per-extension descriptor that supplies uniforms, texture slots and animatable paths, with the other lists derived from it. Table-driven boundary tests: material JSON -> uniforms, slots, animatable paths.

Constraint: no public API break. Keep all existing public types, members and behavior; changes are internal, or additive with old API forwarding. The public KHRMaterials* structs, their Material accessors and builtInExtensions contents must stay.

---

## 164: Unify scene graph walk for rest build and posing

+++
status: closed
priority: low
kind: task
labels: area:architecture
created: 2026-10-14T15:57:17Z
updated: 2026-10-14T17:08:18Z
closed: 2026-10-14T17:05:38Z
+++

The node hierarchy is walked twice with separate logic: GLTFSceneContents.visit (rest build, cycle and visibility checks) and GLTFNodeHierarchy.pose (posing). Visibility inheritance is implemented twice; Node.localMatrix and GLTFNodeHierarchy.Transform.localMatrix are duplicated; lights/cameras use parallel arrays (lightSources, cameras + cameraNodes).

Goal: one internal scene-graph type owning traversal, visibility and node->light/camera mapping, used for rest and posed results.

Constraint: no public API break. Keep all existing public types, members and behavior; changes are internal, or additive with old API forwarding. GLTFAsset's public surface (including pass-through properties, scene(_:), variant(_:), cameras tuple type) must stay.

---

## 165: Simplify GLTFTextureCache load paths

+++
status: closed
priority: low
kind: task
labels: area:architecture
created: 2026-10-14T15:57:17Z
updated: 2026-10-14T17:08:18Z
closed: 2026-10-14T17:05:38Z
+++

GLTFTextureCache has two load paths: preload (parallel) and binding(for:sRGB:) (serial fallback). Preload failures reach loadImage through a failures map, the "imageIndex-sRGB" string key is built in 3 places, and warnings pile up in a mutable array.

Goal: a typed cache key, one load path (preload results as the only source, or a lazy path that shares it), and warnings returned instead of mutated. Boundary tests: materials -> bindings + warnings.

Constraint: no public API break. Keep all existing public types, members and behavior; changes are internal, or additive with old API forwarding. The GLTFTextureDecoder protocol and GLTFLoadOptions must stay source-compatible.

---

## 166: GLTFTextureCache: return warnings, dedupe repeated image failures

+++
status: closed
priority: low
kind: task
labels: area:architecture, effort:s
created: 2026-10-14T17:07:18Z
updated: 2026-10-14T17:12:53Z
closed: 2026-10-14T17:12:53Z
+++

Follow-up to #165. GLTFTextureCache still collects warnings in a private(set) array that Resources.load reads afterwards, instead of returning them. Also, a failed image adds one 'Image N failed to load' warning for each material binding that uses it, so a shared broken texture gives duplicate warnings. Goal: report each failure once, and return warnings from the load instead of mutating cache state.

---

## 167: Parse material animation pointers once at load, not every pose

+++
status: closed
priority: low
kind: enhancement
labels: area:performance, effort:s
created: 2026-10-14T17:07:18Z
updated: 2026-10-14T17:11:00Z
closed: 2026-10-14T17:11:00Z
+++

PBRMaterial.AnimatedState.apply calls GLTFAnimationPointer.MaterialProperty(property) on every pose, which does dictionary lookups and builds suffix strings. The public GLTFAnimationClip.Target stores plain strings, so it cannot change. Option: keep an internal parsed MaterialProperty for each channel next to the public target, built in GLTFAnimationClip.init.

- `2026-10-14T17:08:17Z`: Related to #75 (AnimationPointerUVs slow while animating): re-parsing pointer strings on every pose may contribute.

---

## 168: Animated cameras go through a JSON round-trip on every cameras(pose:)

+++
status: closed
priority: low
kind: enhancement
labels: area:performance, effort:s
created: 2026-10-14T17:07:18Z
updated: 2026-10-14T17:32:42Z
closed: 2026-10-14T17:32:42Z
+++

GLTFAnimationPointer.apply(_:to: Camera) encodes the camera to JSON, patches it and decodes it again, because SwiftGLTF.Camera's properties are let constants. This runs on every cameras(pose:) call that has animated parameters. Fix: add mutable fields or a memberwise init to SwiftGLTF's Camera/Perspective/Orthographic, then set the fields directly.

- `2026-10-14T17:11:18Z`: Checked SwiftGLTF: Camera, Perspective and Orthographic have only let properties and no public memberwise init, so this repo cannot build a changed camera without JSON. Punting: the fix needs a change in the SwiftGLTF repo (public init or var fields), pushed to main before this package can use it. Unblocker: OK to change ~/Projects/Current/SwiftGLTF and push it?
- `2026-10-14T17:17:53Z`: Filed upstream as SwiftGLTF issue: 'Camera, Perspective and Orthographic cannot be built or changed by clients'.

---

## 169: Cache GLTFAsset.cameras instead of building it on each access

+++
status: closed
priority: low
kind: enhancement
labels: area:performance, effort:xs
created: 2026-10-14T17:07:18Z
updated: 2026-10-14T17:09:47Z
closed: 2026-10-14T17:09:47Z
+++

Since #164, GLTFAsset.cameras is computed from cameraSources and builds a new array on every access. The viewer (GLTFView, CameraInspector) reads it every frame. Store it once in init; the public type stays the same.

---

## 170: Use SwiftGLTF Document.removingExtensions in GLTFExtensionFilter

+++
status: closed
priority: low
kind: enhancement
labels: area:architecture, effort:xs
created: 2026-10-14T17:34:04Z
updated: 2026-10-14T17:39:04Z
closed: 2026-10-14T17:39:04Z
+++

GLTFExtensionFilter (GLTFLoadOptions.disabledExtensions) encodes the whole Document to JSON, strips extension keys and decodes it again. SwiftGLTF now has Document.removingExtensions(_:) (SwiftGLTF #67), but it also removes the names from extensionsUsed/extensionsRequired, which this package must keep (the required-extension check and GLTFAssetStatistics depend on them).

Blocked on SwiftGLTF #68 (an option to keep the declarations). Then replace GLTFExtensionFilter with the SwiftGLTF call; DisabledExtensionsTests must still pass unchanged.

---
