import Metal
import MetalSprocketsGLTF
import simd
import SwiftUI
import WebReference

struct ModelInspector: View {
    var loaded: ViewerModel.LoadedAsset
    @Environment(ViewerModel.self) private var viewer

    var body: some View {
        @Bindable var viewer = viewer
        let asset = loaded.asset
        let materialVariantNames = asset.variantNames
        Form {
            if viewer.fileVariants.count > 1 {
                Section("Source") {
                    VariantPicker()
                }
            }
            if !materialVariantNames.isEmpty {
                Section {
                    Picker("Material Variant", selection: $viewer.materialVariant) {
                        Text("Default").tag(Int?.none)
                        ForEach(materialVariantNames.indices, id: \.self) { index in
                            Text(materialVariantNames[index]).tag(Int?.some(index))
                        }
                    }
                } header: {
                    Text("Materials")
                } footer: {
                    Text("three.js always shows the default materials.")
                }
            }
            ExtensionsSection(statistics: asset.statistics)
            StatisticsSections(statistics: asset.statistics, warnings: asset.warnings, file: FileInfo(url: loaded.url, loadTime: loaded.loadTime))
        }
        .formStyle(.grouped)
    }
}

/// Where a model was loaded from and how long it took.
struct FileInfo {
    var url: URL?
    var loadTime: Duration?

    /// The file plus a .gltf's external buffers and images.
    func sizeOnDisk(externalPaths: [String]) -> Int? {
        guard let url else { return nil }
        let directory = url.deletingLastPathComponent()
        let urls = [url] + externalPaths.map { directory.appending(path: $0) }
        let sizes = urls.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }
}

/// The glTF-Sample-Assets file variants of a model; unsupported ones are listed but can't be chosen.
struct VariantPicker: View {
    @Environment(ViewerModel.self) private var viewer

    var body: some View {
        @Bindable var viewer = viewer
        Picker("Variant", selection: $viewer.fileVariant) {
            ForEach(viewer.fileVariants) { choice in
                Text(choice.isSupported ? choice.folder : "\(choice.folder) (unsupported)")
                    .tag(Optional(choice.folder))
                    .selectionDisabled(!choice.isSupported)
            }
        }
        .pickerStyle(.menu)
        .help("File variant to load from glTF-Sample-Assets")
    }
}
