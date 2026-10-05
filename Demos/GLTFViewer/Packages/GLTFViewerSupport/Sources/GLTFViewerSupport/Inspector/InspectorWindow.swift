#if os(visionOS)
import SwiftUI

/// Hands the model window's models to the inspector window (visionOS has no `.inspector`). Both windows observe the
/// same objects, so edits in either show in both.
@MainActor
@Observable
final class InspectorRelay {
    static let shared = InspectorRelay()

    /// The viewer of the model window that last appeared; nil when none is open.
    var viewer: ViewerModel?
    var preferences: ViewerPreferences?
    /// Whether the inspector window is open (it can also be closed with its own close control).
    var isWindowOpen = false
}

/// The inspector window: whatever ``InspectorRelay`` holds.
public struct InspectorWindow: Scene {
    public static let id = "Inspector"

    public init() {}

    public var body: some Scene {
        WindowGroup(id: Self.id) {
            InspectorWindowView()
                .frame(minWidth: 320, idealWidth: 380, minHeight: 480, idealHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 380, height: 640)
        // Beside the model window, which opened it.
        .defaultWindowPlacement { _, context in
            if let main = context.windows.first(where: { $0.id != Self.id }) {
                WindowPlacement(.trailing(main))
            } else {
                WindowPlacement()
            }
        }
    }
}

private struct InspectorWindowView: View {
    private let relay = InspectorRelay.shared

    var body: some View {
        Group {
            if let viewer = relay.viewer, let preferences = relay.preferences {
                ViewerInspector()
                    .environment(viewer)
                    .environment(preferences)
            } else {
                ContentUnavailableView("No Model", systemImage: "sidebar.trailing", description: Text("Open a model to inspect it."))
            }
        }
        .onAppear { relay.isWindowOpen = true }
        .onDisappear { relay.isWindowOpen = false }
    }
}

/// Opens or closes the inspector window.
struct InspectorWindowToggle: View {
    private let relay = InspectorRelay.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button(relay.isWindowOpen ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing") {
            if relay.isWindowOpen {
                dismissWindow(id: InspectorWindow.id)
            } else {
                openWindow(id: InspectorWindow.id)
            }
        }
    }
}
#endif
