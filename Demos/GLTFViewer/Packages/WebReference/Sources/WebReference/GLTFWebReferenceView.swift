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
    public func makeNSView(context _: Context) -> WKWebView { reference.webView }
    public func updateNSView(_: WKWebView, context _: Context) {}
}
#else
extension GLTFWebReferenceView: UIViewRepresentable {
    public func makeUIView(context _: Context) -> WKWebView { reference.webView }
    public func updateUIView(_: WKWebView, context _: Context) {}
}
#endif
