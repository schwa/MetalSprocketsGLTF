default:
	just --list

# Benchmark sample scenes (Release) against this machine's baseline in Benchmarks/. Extra arguments go to `ms-gltf-render bench` (e.g. scene names, --record).
bench *args:
	xcb build -S MetalSprocketsGLTF/ms-gltf-render -c release
	.build/out/Products/Release/ms-gltf-render bench {{args}}

# Record this machine's benchmark baseline.
bench-record *args:
	just bench --record {{args}}

# Regenerate GLTFViewer's built-in shapes: write them from BasicShape, then pack them with gltfpack (quantized, meshopt).
basic-shapes:
	#!/usr/bin/env bash
	set -euo pipefail
	raw=$(mktemp -d)
	cd Demos/GLTFViewer/Packages/GLTFViewerSupport
	WRITE_BASIC_SHAPES="$raw" xcb test -S --raw -- --filter writeBasicShapes > /dev/null
	out=Sources/GLTFViewerSupport/Resources/BasicShapes
	mkdir -p "$out"
	for file in "$raw"/*.glb; do
		# -kv keeps TEXCOORD_0, which gltfpack otherwise drops because no texture uses it (the UV debug views do).
		# -vt 16: with the default 12 bits gltfpack undoes the UV scaling through KHR_texture_transform on textures;
		# these shapes have none, so their UVs would come out 16 times too small.
		npx --yes gltfpack -cc -kv -vt 16 -i "$file" -o "$out/$(basename "$file")"
	done
	ls -l "$out"

download-sample-assets:
	#!/usr/bin/env bash
	set -euo pipefail
	if [ ! -d .sample-assets ]; then
		git clone --depth 1 https://github.com/KhronosGroup/glTF-Sample-Assets.git .sample-assets
	else
		git -C .sample-assets pull --ff-only
	fi
