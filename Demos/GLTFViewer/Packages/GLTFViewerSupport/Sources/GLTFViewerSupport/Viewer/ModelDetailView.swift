import SwiftUI

/// Loads and shows one model, with its ``ViewerModel`` in the environment for the viewer and inspector.
struct ModelDetailView: View {
    @State private var viewer: ViewerModel

    init(title: String, fileURL: @escaping (String?) async throws -> URL) {
        _viewer = State(initialValue: ViewerModel(title: title, fileURL: fileURL))
    }

    init(model: SampleModel, library: SampleLibrary) {
        _viewer = State(initialValue: ViewerModel(model: model, library: library))
    }

    var body: some View {
        Group {
            switch viewer.phase {
            case .loading:
                ProgressView("Loading \(viewer.title)…")

            case .loaded(let model):
                GLTFView(model: model)

            case .failed(let message):
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    // The inspector isn't shown without a model, so offer the other variants here.
                    if viewer.fileVariants.count > 1 {
                        VariantPicker()
                            .fixedSize()
                    }
                }
            }
        }
        .navigationTitle(viewer.title)
        .environment(viewer)
        .task(id: viewer.loadKey) {
            await viewer.load()
        }
    }
}
