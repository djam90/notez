import Foundation
import SwiftData
import WebKit
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
#endif

/// Owns the single, long-lived WKWebView that hosts the TipTap editor.
///
/// The web view is created once and reused for every note: switching notes is
/// just a `window.notez.load(...)` call, so there's no page load, no JS parse
/// and no layout thrash between notes.
final class EditorController: NSObject {
    let webView: WKWebView
    private let context: ModelContext
    private let schemeHandler: NotezSchemeHandler

    private var isReady = false
    private var pendingLoad: (() -> Void)?
    private(set) var currentNote: Note?

    /// Called when the editor wants to open an internal `notez://note/<id>` link.
    var onOpenNote: ((UUID) -> Void)?

    init(context: ModelContext) {
        self.context = context
        self.schemeHandler = NotezSchemeHandler(context: context)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: NotezSchemeHandler.scheme)
        config.suppressesIncrementalRendering = true
        #if os(iOS)
        config.dataDetectorTypes = []
        #endif

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakMessageHandler(self), name: "notez")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif

        webView.load(URLRequest(url: NotezSchemeHandler.editorURL))
    }

    // MARK: - Native -> JS

    enum Focus: String { case title, body, none }

    func load(_ note: Note?, focus: Focus = .none) {
        currentNote = note
        guard let note else { return }
        let payload: [String: Any] = [
            "id": note.id.uuidString,
            "title": note.title,
            "doc": note.body?.doc.isEmpty == false ? note.body!.doc : NSNull(),
            "markdown": note.body?.pendingMarkdown ?? "",
            "focus": focus.rawValue,
        ]
        run { [weak self] in self?.call("load", payload) }
    }

    func focusTitle() { run { [weak self] in self?.call("focusTitle") } }
    func pickImage() { run { [weak self] in self?.call("pickImage") } }
    func flush() { run { [weak self] in self?.call("flush") } }

    func markdown() async -> String? {
        try? await webView.evaluateJavaScript("window.notez.getMarkdown()") as? String
    }

    private func run(_ block: @escaping () -> Void) {
        if isReady { block() } else { pendingLoad = block }
    }

    private func call(_ method: String, _ args: Any...) {
        let json = args.map { arg -> String in
            guard let data = try? JSONSerialization.data(withJSONObject: arg, options: [.fragmentsAllowed]) else {
                return "null"
            }
            return String(decoding: data, as: UTF8.self)
        }
        webView.evaluateJavaScript("window.notez.\(method)(\(json.joined(separator: ",")))")
    }

    // MARK: - JS -> Native

    fileprivate func handle(_ body: Any) {
        guard let msg = body as? [String: Any], let type = msg["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            pendingLoad?()
            pendingLoad = nil

        case "change":
            guard let idString = msg["id"] as? String, let id = UUID(uuidString: idString),
                  let note = note(with: id) else { return }
            applyChange(
                to: note,
                title: msg["title"] as? String ?? "",
                doc: msg["doc"] as? String ?? "",
                text: msg["text"] as? String ?? ""
            )

        case "uploadImage":
            guard let requestId = msg["requestId"] as? String,
                  let base64 = msg["base64"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            let asset = Asset(data: data, mimeType: msg["mime"] as? String ?? "image/png", note: currentNote)
            context.insert(asset)
            try? context.save()
            call("resolveUpload", requestId, NotezSchemeHandler.assetURL(asset.id).absoluteString)

        case "openURL":
            guard let string = msg["url"] as? String, let url = URL(string: string) else { return }
            open(url)

        case "log":
            print("[editor]", msg["message"] as? String ?? "")

        default:
            break
        }
    }

    private func applyChange(to note: Note, title: String, doc: String, text: String) {
        let body = note.body ?? {
            let b = NoteBody()
            context.insert(b)
            note.body = b
            return b
        }()
        if note.title != title { note.title = title }
        body.doc = doc
        body.plainText = text
        body.pendingMarkdown = ""
        note.preview = String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
        note.updatedAt = .now
    }

    private func note(with id: UUID) -> Note? {
        if let currentNote, currentNote.id == id { return currentNote }
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func open(_ url: URL) {
        if url.scheme == NotezSchemeHandler.scheme, url.host() == "note",
           let id = UUID(uuidString: url.lastPathComponent) {
            onOpenNote?(id)
            return
        }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - WebKit delegates

extension EditorController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == NotezSchemeHandler.scheme { return .allow }
        // Never navigate the editor away; hand external links to the system.
        if action.navigationType == .linkActivated { open(url) }
        return .cancel
    }

    // target="_blank" / window.open
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url { open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        print("[editor] failed to load:", error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from a WebContent crash and reopen the current note.
        isReady = false
        let note = currentNote
        pendingLoad = { [weak self] in self?.load(note) }
        webView.load(URLRequest(url: NotezSchemeHandler.editorURL))
    }

    #if os(macOS)
    // <input type="file"> on macOS needs an explicit open panel.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : nil
    }
    #endif
}

/// Breaks the WKUserContentController -> handler retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?
    init(_ target: EditorController) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body)
    }
}
