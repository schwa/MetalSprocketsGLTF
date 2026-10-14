import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

struct StatisticsSections: View {
    var statistics: GLTFAssetStatistics
    var warnings: [String]
    var file: FileInfo

    var body: some View {
        Section("File") {
            if let url = file.url {
                LabeledContent("Name", value: url.lastPathComponent)
                LabeledContent("Format", value: format(url))
            }
            if let size = file.sizeOnDisk(externalPaths: statistics.externalPaths) {
                LabeledContent("Size", value: size.formatted(.byteCount(style: .file)))
            }
            if let loadTime = file.loadTime {
                LabeledContent("Load Time", value: loadTime.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated, fractionalPart: .show(length: 0))))
            }
            LabeledContent("glTF Version", value: statistics.version)
            if let generator = statistics.generator {
                LabeledContent("Generator", value: generator)
            }
        }
        Section("Geometry") {
            count("Triangles", statistics.triangles)
            if statistics.lines > 0 { count("Lines", statistics.lines) }
            if statistics.points > 0 { count("Points", statistics.points) }
            count("Vertices", statistics.vertices)
            count("Nodes", statistics.nodes)
            count("Meshes", statistics.meshes)
            count("Primitives", statistics.primitives)
            count("Instances", statistics.instances)
            count("Draw Batches", statistics.batches)
        }
        Section("Materials") {
            count("Materials", statistics.materials)
            if statistics.materialVariants > 0 { count("Variants", statistics.materialVariants) }
            count("Textures", statistics.textures)
            LabeledContent("Texture Memory", value: statistics.textureBytes.formatted(.byteCount(style: .memory)))
            if let largest = statistics.largestTexture {
                LabeledContent("Largest Texture", value: "\(largest.width) × \(largest.height)")
            }
        }
        Section("Scene") {
            if statistics.scenes > 1 { count("Scenes", statistics.scenes) }
            count("Animations", statistics.animations)
            count("Skins", statistics.skins)
            if statistics.joints > 0 { count("Joints", statistics.joints) }
            count("Morph Targets", statistics.morphTargets)
            count("Lights", statistics.lights)
            count("Cameras", statistics.cameras)
        }
        if !warnings.isEmpty {
            Section("Warnings") {
                ForEach(warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                }
            }
        }
    }

    private func count(_ label: String, _ value: Int) -> some View {
        LabeledContent(label, value: value.formatted())
    }

    private func format(_ url: URL) -> String {
        url.pathExtension.lowercased() == "glb" ? "glTF Binary" : statistics.externalPaths.isEmpty ? "glTF (embedded)" : "glTF with external files"
    }
}
