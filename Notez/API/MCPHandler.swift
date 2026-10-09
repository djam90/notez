import Foundation

/// Model Context Protocol over Streamable HTTP (JSON responses, no SSE).
/// Tools map one-to-one onto `NotesAPI` operations.
final class MCPHandler {
    private let api: NotesAPI

    init(api: NotesAPI) {
        self.api = api
    }

    private static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]

    private static let instructions = """
    Notez is the user's personal notes app: nested pages (Notion-style), each with a title and a rich-text \
    body. Bodies are read and written as GitHub-flavoured markdown, including tables, task lists \
    (- [ ] / - [x]) and ==highlights==. Pages form a tree: use parentId to nest pages. Prefer \
    search_notes to find pages, and get_note before editing one. update_note with markdown replaces the \
    whole body, so to add to a page use appendMarkdown instead. Images appear as notez://asset/<id> URLs; \
    keep them as-is when rewriting a page.
    """

    /// Handles one JSON-RPC message or batch. Returns nil when nothing needs sending back (notifications).
    func handle(_ body: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return encode(error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = json as? [[String: Any]] {
            let responses = batch.compactMap(respond)
            return responses.isEmpty ? nil : encode(responses)
        }
        guard let message = json as? [String: Any] else {
            return encode(error(id: NSNull(), code: -32600, message: "Invalid request"))
        }
        return respond(to: message).map(encode)
    }

    private func respond(to message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        // Notifications (no id) get no response.
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return result(id: id, [
                "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "notez", "title": "Notez", "version": appVersion],
                "instructions": Self.instructions,
            ])
        case "ping":
            return result(id: id, [:])
        case "tools/list":
            return result(id: id, ["tools": Self.tools.map(\.definition)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = Self.tools.first(where: { $0.name == name }) else {
                return error(id: id, code: -32602, message: "Unknown tool")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let output = try tool.run(api, args)
                return result(id: id, [
                    "content": [["type": "text", "text": text(output)]],
                    "structuredContent": output,
                    "isError": false,
                ])
            } catch let failure as APIError {
                return result(id: id, ["content": [["type": "text", "text": failure.message]], "isError": true])
            } catch {
                return result(id: id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        default:
            return self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tools

    private struct Tool {
        let name: String
        let title: String
        let description: String
        let properties: [String: Any]
        let required: [String]
        var readOnly = false
        var destructive = false
        let run: (NotesAPI, NotesAPI.Args) throws -> Any

        var definition: [String: Any] {
            [
                "name": name,
                "title": title,
                "description": description,
                "inputSchema": ["type": "object", "properties": properties, "required": required],
                "annotations": [
                    "readOnlyHint": readOnly,
                    "destructiveHint": destructive,
                    "idempotentHint": readOnly,
                    "openWorldHint": false,
                ],
            ]
        }
    }

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static let idProp = prop("string", "Page id (UUID).")
    private static let parentID = prop("string", "Parent page id, or \"root\" for the top level.")

    private static let tools: [Tool] = [
        Tool(
            name: "list_notes", title: "List pages",
            description: "List pages with their ids, titles and paths. With no parentId, returns every page depth-first in sidebar order. With parentId, returns just that page's direct children (\"root\" for top-level pages).",
            properties: ["parentId": parentID], required: [], readOnly: true,
            run: { try $0.list($1) }
        ),
        Tool(
            name: "search_notes", title: "Search pages",
            description: "Search page titles and full text. Title matches come first. Returns pages with a snippet around the match. An empty query returns the most recently edited pages.",
            properties: [
                "query": prop("string", "Text to look for (case and accent insensitive substring)."),
                "limit": prop("integer", "Maximum results, default 20, max 100."),
            ],
            required: ["query"], readOnly: true,
            run: { try $0.search($1) }
        ),
        Tool(
            name: "get_note", title: "Read page",
            description: "Get a page's metadata, full body as markdown, and its direct children.",
            properties: ["id": idProp], required: ["id"], readOnly: true,
            run: { try $0.get($1) }
        ),
        Tool(
            name: "create_note", title: "Create page",
            description: "Create a page. It goes to the top of its level (top level unless parentId is given).",
            properties: [
                "title": prop("string", "Page title."),
                "markdown": prop("string", "Page body as markdown. Don't repeat the title as a heading."),
                "parentId": parentID,
                "icon": prop("string", "Optional single emoji shown in the sidebar."),
                "pinned": prop("boolean", "Pin the page in the sidebar."),
            ],
            required: ["title"],
            run: { try $0.create($1) }
        ),
        Tool(
            name: "update_note", title: "Update page",
            description: "Change a page. Only the fields you pass are changed. markdown replaces the whole body; appendMarkdown adds to the end of it. Passing parentId moves the page (\"root\" moves it to the top level).",
            properties: [
                "id": idProp,
                "title": prop("string", "New title."),
                "markdown": prop("string", "New body, replacing the existing one."),
                "appendMarkdown": prop("string", "Markdown to add to the end of the body."),
                "parentId": parentID,
                "icon": prop("string", "Single emoji, or \"\" to clear."),
                "pinned": prop("boolean", "Pin or unpin."),
            ],
            required: ["id"],
            run: { try $0.update($1) }
        ),
        Tool(
            name: "delete_note", title: "Delete page",
            description: "Permanently delete a page together with all its sub-pages and images. There is no undo.",
            properties: ["id": idProp], required: ["id"], destructive: true,
            run: { try $0.delete($1) }
        ),
    ]

    // MARK: - JSON-RPC

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    }

    private func text(_ object: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
