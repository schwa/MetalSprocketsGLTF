import SwiftUI
import WebKit

/// Hosts a ``GLTFWebReference``'s web view. Drive the reference directly to load models and set the camera.
public struct GLTFWebReferenceView {
    public var reference: GLTFWebReference

    public init(reference: GLTFWebReference) {
        self.reference = reference
    }
}

#if os(macOS)
extension GLTFWebReferenceView: NSViewRepresentable {
    public func makeNSView(context: Context) -> WKWebView { reference.webView }
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
extension GLTFWebReferenceView: UIViewRepresentable {
    public func makeUIView(context: Context) -> WKWebView { reference.webView }
    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
