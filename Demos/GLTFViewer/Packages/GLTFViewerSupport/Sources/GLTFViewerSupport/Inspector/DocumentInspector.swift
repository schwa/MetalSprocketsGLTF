import MetalSprocketsGLTF
import SwiftGLTF
import SwiftUI

/// The loaded glTF document as an outline (``DocumentOutline``) over the selected item's properties.
struct DocumentInspector: View {
    var asset: GLTFAsset
    @State private var items: [DocumentOutlineItem] = []
    @State private var selection: DocumentOutlineItem.ID?

    var body: some View {
        #if os(macOS)
        VSplitView {
            outline
            detail
        }
        #else
        VStack(spacing: 0) {
            outline
            Divider()
            detail
        }
        #endif
    }

    private var outline: some View {
        List(items, children: \.children, selection: $selection) { item in
            Label {
                VStack(alignment: .leading) {
                    Text(item.title)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: item.systemImage)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Empty Document", systemImage: "doc", description: Text("The file has no scenes, meshes or materials."))
            }
        }
        // Built once per asset, not on every body evaluation.
        .task(id: ObjectIdentifier(asset)) {
            items = DocumentOutline.items(for: asset)
            selection = nil
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let reference = selectedReference {
            Form {
                ForEach(DocumentOutline.properties(of: reference, in: asset.container.document)) { property in
                    LabeledContent(property.name) {
                        Text(property.value)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "list.bullet.indent", description: Text("Select an item to see its properties."))
        }
    }

    private var selectedReference: DocumentReference? {
        guard let selection else { return nil }
        func find(_ items: [DocumentOutlineItem]) -> DocumentReference? {
            for item in items {
                if item.id == selection {
                    return item.reference
                }
                if let found = find(item.children ?? []) {
                    return found
                }
            }
            return nil
        }
        return find(items)
    }
}
