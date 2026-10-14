import SwiftUI
#if os(macOS)
import AppKit
#endif

/// What the sidebar has selected: a file the user opened, a built-in shape, or a sample model (by ID).
enum SidebarSelection: Hashable {
    case opened(URL)
    case showcase(ShowcaseScene)
    case shape(BasicShape)
    case sample(SampleModel.ID)
}

public struct SamplesView: View {
    @Environment(SampleLibrary.self) private var library
    @State private var selection: SidebarSelection?
    @State private var filter = ""
    /// Viewer settings, restored at launch and saved on every change.
    @State private var preferences = ViewerPreferences()
    /// Files opened this session, newest first; each keeps its sandbox access while listed.
    @State private var openedFiles: [OpenedFile] = []
    @State private var isImportingFile = false
    /// A .gltf whose external resources need the user to grant its folder.
    @State private var fileNeedingFolder: URL?
    /// Separate from `fileNeedingFolder`: SwiftUI clears isPresented before the importer's completion runs, which
    /// must still know the file.
    @State private var isChoosingFolder = false
    @State private var openError: String?
    @State private var isShowingOpenError = false

    public init() {}

    public var body: some View {
        browser
            .environment(preferences)
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: OpenedFile.contentTypes) { result in
                switch result {
                case .success(let url):
                    open(url)

                case .failure(let error):
                    showOpenError(error.localizedDescription)
                }
            }
            .background {
                // A second importer must live on another view; this one asks for the folder of a .gltf.
                Color.clear
                    .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                        if let file = fileNeedingFolder, case .success(let folder) = result {
                            open(file, folder: folder)
                        }
                        fileNeedingFolder = nil
                    }
                    .fileDialogMessage("\(fileNeedingFolder?.lastPathComponent ?? "This file") loads other files from its folder. Choose that folder to allow access.")
                    .fileDialogDefaultDirectory(fileNeedingFolder?.deletingLastPathComponent())
                    .fileDialogConfirmationLabel("Allow Access")
            }
            .alert("Cannot Open File", isPresented: $isShowingOpenError) {
                Button("OK") {}
            } message: {
                Text(openError ?? "")
            }
    }

    private func showOpenError(_ message: String) {
        openError = message
        isShowingOpenError = true
    }

    private var openButton: some View {
        Button("Open…", systemImage: "folder") {
            isImportingFile = true
        }
    }

    @ViewBuilder
    private func openedFileView(_ file: OpenedFile) -> some View {
        if file.needsFolderAccess {
            ContentUnavailableView {
                Label("Allow Access to the Folder", systemImage: "folder.badge.questionmark")
            } description: {
                Text("\(file.name) loads other files (buffers, images) from its folder. Choose that folder to allow access.")
            } actions: {
                Button("Choose Folder") {
                    fileNeedingFolder = file.url
                    isChoosingFolder = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ModelDetailView(title: file.name) { _ in file.url }
                .id(file.id)
        }
    }

    /// Opens a picked file directly, or asks for its folder when it references other files.
    private func open(_ url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            // Show it at once; a .gltf with external files asks for its folder from its detail view.
            show(OpenedFile(url: url, scopedURL: url, needsFolderAccess: try OpenedFile.needsFolderAccess(url)))
        } catch {
            showOpenError(error.localizedDescription)
        }
    }

    private func open(_ file: URL, folder: URL) {
        // Resolve symlinks: the file and folder may reach the same place by different paths.
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/") else {
            showOpenError("\(file.lastPathComponent) is not inside \(folder.lastPathComponent).")
            return
        }
        show(OpenedFile(url: file, scopedURL: folder))
    }

    /// Shows `url` selected in the Finder; disabled when there is nothing on disk yet (a sample not downloaded).
    @ViewBuilder
    private func revealButton(_ url: URL?) -> some View {
        #if os(macOS)
        Button("Show in Finder", systemImage: "folder") {
            if let url {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .disabled(url == nil)
        #endif
    }

    /// Adds `file` to the Opened Files section (replacing an earlier entry for the same file) and selects it.
    private func show(_ file: OpenedFile) {
        openedFiles.removeAll { $0.url == file.url }
        openedFiles.insert(file, at: 0)
        selection = .opened(file.url)
    }

    private func close(_ file: OpenedFile) {
        openedFiles.removeAll { $0.url == file.url }
        if selection == .opened(file.url) {
            selection = nil
        }
    }

    private var models: [SampleModel] {
        if case .loaded(let models) = library.state { models } else { [] }
    }

    /// Shown in the Sample Assets section until the index is downloaded, so the built-in shapes work offline.
    @ViewBuilder
    private var sampleIndexStatus: some View {
        switch library.state {
        case .downloading:
            ProgressView("Downloading sample index…")

        case .failed(let message):
            VStack(alignment: .leading) {
                Text("Download failed: \(message)")
                    .font(.caption)
                Button("Try Again") { Task { await library.downloadIndex() } }
            }

        case .notDownloaded:
            VStack(alignment: .leading) {
                Text("Khronos glTF sample models, downloaded when selected and cached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download Sample Index") { Task { await library.downloadIndex() } }
            }

        case .loaded:
            EmptyView()
        }
    }

    private var browser: some View {
        let shapes = BasicShape.allCases.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        let showcases = ShowcaseScene.allCases.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        let filtered = models.filter { $0.matches(filter) }
        return NavigationSplitView {
            List(selection: $selection) {
                if !openedFiles.isEmpty {
                    Section("Opened Files") {
                        ForEach(openedFiles, id: \.url) { file in
                            Label(file.name, systemImage: file.needsFolderAccess ? "doc.badge.ellipsis" : "doc")
                                .help(file.url.path)
                                .tag(SidebarSelection.opened(file.url))
                                .contextMenu {
                                    revealButton(file.url)
                                    Button("Close") { close(file) }
                                }
                        }
                    }
                }
                if !showcases.isEmpty {
                    Section("Showcase") {
                        ForEach(showcases) { scene in
                            Label(scene.name, systemImage: scene.systemImage)
                                .tag(SidebarSelection.showcase(scene))
                        }
                    }
                }
                if !shapes.isEmpty {
                    Section("Basic Shapes") {
                        ForEach(shapes) { shape in
                            Label(shape.name, systemImage: shape.systemImage)
                                .tag(SidebarSelection.shape(shape))
                        }
                    }
                }
                Section("Sample Assets") {
                    sampleIndexStatus
                    ForEach(filtered) { model in
                        SampleRow(model: model, isCached: library.isCached(model))
                            .tag(SidebarSelection.sample(model.id))
                            .contextMenu {
                                revealButton(library.downloadedLocation(of: model))
                            }
                    }
                }
            }
            .searchable(text: $filter, placement: .sidebar, prompt: "Filter by name or tag")
            .navigationTitle("Models")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .toolbar {
                openButton
            }
            // Clearing the cache (in Settings) unloads the index; drop a sample selection with it.
            .onChange(of: library.isLoaded) { _, isLoaded in
                if !isLoaded, case .sample = selection {
                    selection = nil
                }
            }
        } detail: {
            switch selection {
            case .opened(let url):
                if let file = openedFiles.first(where: { $0.url == url }) {
                    openedFileView(file)
                } else {
                    ContentUnavailableView("Select a Model", systemImage: "cube")
                }

            case .showcase(let scene):
                ModelDetailView(title: scene.name) { _ in
                    try scene.fileURL()
                }
                .id(selection)

            case .shape(let shape):
                ModelDetailView(title: shape.name) { _ in
                    guard let url = shape.fileURL else { throw CocoaError(.fileNoSuchFile) }
                    return url
                }
                .id(selection)

            case .sample(let id):
                if let model = models.first(where: { $0.id == id }) {
                    ModelDetailView(model: model, library: library)
                        .id(model.id)
                } else {
                    ContentUnavailableView("Select a Model", systemImage: "cube")
                }

            case nil:
                ContentUnavailableView("Select a Model", systemImage: "cube", description: Text("Pick a basic shape or a sample model, or open a glTF file."))
            }
        }
    }
}

struct SampleRow: View {
    var model: SampleModel
    var isCached: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.label)
                if let tags = model.tags, !tags.isEmpty {
                    Text(tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isCached {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Downloaded")
            }
        }
    }
}

#Preview {
    SamplesView()
        .environment(SampleLibrary())
}
