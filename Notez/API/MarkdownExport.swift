import Foundation

/// TipTap JSON -> Markdown, for the local API (which runs without a web view).
/// Follows the conventions of `@tiptap/markdown` so text read through the API
/// parses back to the same document when written again. Lossy in the same
/// places markdown is: underline, image sizes, merged table cells.
enum MarkdownExport {
    /// The body of `note` as markdown, including any not-yet-converted pending markdown.
    static func markdown(for body: NoteBody?) -> String {
        guard let body else { return "" }
        let doc = (try? JSONSerialization.jsonObject(with: Data(body.doc.utf8))) as? [String: Any]
        let parts = [doc.map { blocks(children($0)) } ?? "", body.pendingMarkdown]
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private typealias Node = [String: Any]

    private static func children(_ node: Node) -> [Node] { node["content"] as? [Node] ?? [] }
    private static func attr<T>(_ node: Node, _ key: String) -> T? { (node["attrs"] as? Node)?[key] as? T }

    private static func blocks(_ nodes: [Node]) -> String {
        nodes.map(block).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func block(_ node: Node) -> String {
        switch node["type"] as? String {
        case "paragraph":
            return inline(children(node))
        case "heading":
            return String(repeating: "#", count: attr(node, "level") ?? 1) + " " + inline(children(node))
        case "blockquote":
            return prefixLines(blocks(children(node)), first: "> ", rest: "> ")
        case "codeBlock":
            let code = children(node).compactMap { $0["text"] as? String }.joined()
            return "```\(attr(node, "language") ?? "")\n\(code)\n```"
        case "horizontalRule":
            return "---"
        case "image":
            return image(node)
        case "bulletList":
            return children(node).map { listItem($0, marker: "- ") }.joined(separator: "\n")
        case "orderedList":
            let start: Int = attr(node, "start") ?? 1
            return children(node).enumerated().map { listItem($1, marker: "\(start + $0). ") }.joined(separator: "\n")
        case "taskList":
            return children(node).map { item in
                listItem(item, marker: "- [\((attr(item, "checked") ?? false) ? "x" : " ")] ")
            }.joined(separator: "\n")
        case "table":
            return table(node)
        default:
            // Unknown block: keep its text rather than dropping it.
            return node["content"] != nil ? blocks(children(node)) : inline([node])
        }
    }

    /// List items are tight: their blocks are joined by single newlines and
    /// continuation lines are indented to sit under the marker.
    private static func listItem(_ node: Node, marker: String) -> String {
        let body = children(node).map(block).filter { !$0.isEmpty }.joined(separator: "\n")
        let indent = String(repeating: " ", count: marker.hasPrefix("-") ? 2 : marker.count)
        return prefixLines(body, first: marker, rest: indent)
    }

    private static func prefixLines(_ text: String, first: String, rest: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { i, line in
            let prefix = i == 0 ? first : rest
            return line.isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + line
        }.joined(separator: "\n")
    }

    private static func table(_ node: Node) -> String {
        let rows = children(node).map { row in
            children(row).map { cell in
                // Cells are single-line in markdown.
                children(cell).map(block).joined(separator: "<br>")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
            }
        }
        guard let header = rows.first, !header.isEmpty else { return "" }
        let line = { (cells: [String]) in "| " + cells.joined(separator: " | ") + " |" }
        let width = header.count
        let pad = { (cells: [String]) in Array((cells + Array(repeating: "", count: width)).prefix(width)) }
        return ([line(header), line(Array(repeating: "---", count: width))] + rows.dropFirst().map { line(pad($0)) })
            .joined(separator: "\n")
    }

    private static func image(_ node: Node) -> String {
        let alt: String = attr(node, "alt") ?? ""
        let src: String = attr(node, "src") ?? ""
        return "![\(alt)](\(src))"
    }

    // MARK: - Inline

    private static func inline(_ nodes: [Node]) -> String {
        nodes.map { node -> String in
            switch node["type"] as? String {
            case "text":
                return marked(node["text"] as? String ?? "", marks: node["marks"] as? [Node] ?? [])
            case "hardBreak":
                return "\\\n"
            case "image":
                return image(node)
            default:
                return inline(children(node))
            }
        }.joined()
    }

    private static func marked(_ text: String, marks: [Node]) -> String {
        var out = text
        for mark in marks {
            switch mark["type"] as? String {
            case "bold": out = "**\(out)**"
            case "italic": out = "*\(out)*"
            case "strike": out = "~~\(out)~~"
            case "code": out = "`\(out)`"
            case "highlight": out = "==\(out)=="
            case "link": out = "[\(out)](\(attr(mark, "href") ?? ""))"
            default: break
            }
        }
        return out
    }
}
