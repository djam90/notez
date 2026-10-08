import SwiftUI
import WebKit

/// Hosts the controller's persistent web view. SwiftUI may rebuild this view
/// (e.g. on iPhone when navigating back and forth) but the WKWebView itself is
/// never recreated.
#if os(macOS)
struct EditorView: NSViewRepresentable {
    let controller: EditorController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
struct EditorView: UIViewRepresentable {
    let controller: EditorController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
