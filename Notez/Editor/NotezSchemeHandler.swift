import Foundation
import SwiftData
import WebKit

/// Serves everything the editor loads over a private `notez://` scheme:
///   notez://app/editor.html   -> the bundled editor
///   notez://asset/<uuid>      -> an embedded image from SwiftData
final class NotezSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "notez"
    static let editorURL = URL(string: "notez://app/editor.html")!
    static func assetURL(_ id: UUID) -> URL { URL(string: "notez://asset/\(id.uuidString)")! }

    private let context: ModelContext
    private let cache = NSCache<NSUUID, CachedAsset>()
    private lazy var editorHTML: Data? = Bundle.main
        .url(forResource: "editor", withExtension: "html")
        .flatMap { try? Data(contentsOf: $0) }

    init(context: ModelContext) {
        self.context = context
        cache.totalCostLimit = 200 * 1024 * 1024
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }

        switch url.host() {
        case "app":
            guard let data = editorHTML else { return fail(task) }
            respond(task, url: url, data: data, mime: "text/html")

        case "asset":
            guard let id = UUID(uuidString: url.lastPathComponent),
                  let asset = asset(id) else { return fail(task) }
            respond(task, url: url, data: asset.data, mime: asset.mime)

        default:
            fail(task)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func asset(_ id: UUID) -> CachedAsset? {
        if let hit = cache.object(forKey: id as NSUUID) { return hit }
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let asset = try? context.fetch(descriptor).first, let data = asset.data else { return nil }
        let entry = CachedAsset(data: data, mime: asset.mimeType)
        cache.setObject(entry, forKey: id as NSUUID, cost: data.count)
        return entry
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Cache-Control": "max-age=31536000, immutable",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask) {
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}

private final class CachedAsset {
    let data: Data
    let mime: String
    init(data: Data, mime: String) {
        self.data = data
        self.mime = mime
    }
}
