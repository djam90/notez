import Foundation
import Testing
@testable import Notez

/// TipTap JSON -> markdown for the API. EditorBridgeTests checks it against
/// the editor's own serializer; these pin each node type down precisely.
@Suite struct MarkdownExportTests {
    private func markdown(_ blocks: [[String: Any]], pending: String = "") throws -> String {
        let body = NoteBody(markdown: pending)
        let data = try JSONSerialization.data(withJSONObject: ["type": "doc", "content": blocks])
        body.doc = String(decoding: data, as: UTF8.self)
        return MarkdownExport.markdown(for: body)
    }

    private func text(_ text: String, _ marks: [[String: Any]] = []) -> [String: Any] {
        marks.isEmpty ? ["type": "text", "text": text] : ["type": "text", "text": text, "marks": marks]
    }

    private func paragraph(_ content: [String: Any]...) -> [String: Any] {
        ["type": "paragraph", "content": content]
    }

    private func item(_ blocks: [String: Any]..., type: String = "listItem", checked: Bool? = nil) -> [String: Any] {
        var node: [String: Any] = ["type": type, "content": blocks]
        if let checked { node["attrs"] = ["checked": checked] }
        return node
    }

    @Test func noBodyIsEmpty() {
        #expect(MarkdownExport.markdown(for: nil) == "")
        #expect(MarkdownExport.markdown(for: NoteBody()) == "")
    }

    @Test func pendingMarkdownFollowsTheDocument() throws {
        #expect(try markdown([paragraph(text("doc"))], pending: "pending") == "doc\n\npending")
        #expect(MarkdownExport.markdown(for: NoteBody(markdown: "only pending")) == "only pending")
    }

    @Test func inlineMarks() throws {
        let line = paragraph(
            text("b", [["type": "bold"]]), text(" "),
            text("i", [["type": "italic"]]), text(" "),
            text("s", [["type": "strike"]]), text(" "),
            text("c", [["type": "code"]]), text(" "),
            text("h", [["type": "highlight"]]), text(" "),
            text("link", [["type": "link", "attrs": ["href": "https://example.com"]]]), text(" "),
            text("both", [["type": "bold"], ["type": "italic"]])
        )
        #expect(try markdown([line]) == "**b** *i* ~~s~~ `c` ==h== [link](https://example.com) ***both***")
    }

    @Test func underlineIsDropped() throws {
        #expect(try markdown([paragraph(text("u", [["type": "underline"]]))]) == "u")
    }

    @Test func hardBreaksAndBlocksAreSeparated() throws {
        let doc: [[String: Any]] = [
            ["type": "heading", "attrs": ["level": 2], "content": [text("Title")]],
            paragraph(text("one"), ["type": "hardBreak"], text("two")),
            ["type": "horizontalRule"],
            ["type": "paragraph"],
        ]
        #expect(try markdown(doc) == "## Title\n\none\\\ntwo\n\n---")
    }

    @Test func codeBlocksKeepTheirLanguage() throws {
        let code: [String: Any] = ["type": "codeBlock", "attrs": ["language": "swift"], "content": [text("let a = 1\nlet b = 2")]]
        #expect(try markdown([code]) == "```swift\nlet a = 1\nlet b = 2\n```")
        let plain: [String: Any] = ["type": "codeBlock", "content": [text("x")]]
        #expect(try markdown([plain]) == "```\nx\n```")
    }

    @Test func quotesPrefixEveryLine() throws {
        let quote: [String: Any] = ["type": "blockquote", "content": [paragraph(text("a")), paragraph(text("b"))]]
        #expect(try markdown([quote]) == "> a\n>\n> b")
    }

    @Test func nestedListsIndentUnderTheirMarker() throws {
        let nested: [String: Any] = ["type": "bulletList", "content": [item(paragraph(text("inner")))]]
        let bullets: [String: Any] = ["type": "bulletList", "content": [
            item(paragraph(text("one")), nested),
            item(paragraph(text("two"))),
        ]]
        #expect(try markdown([bullets]) == "- one\n  - inner\n- two")
    }

    @Test func orderedListsCountFromTheirStart() throws {
        let list: [String: Any] = ["type": "orderedList", "attrs": ["start": 9], "content": [
            item(paragraph(text("nine")), paragraph(text("more"))),
            item(paragraph(text("ten"))),
        ]]
        #expect(try markdown([list]) == "9. nine\n   more\n10. ten")
    }

    @Test func taskLists() throws {
        let tasks: [String: Any] = ["type": "taskList", "content": [
            item(paragraph(text("done")), type: "taskItem", checked: true),
            item(paragraph(text("todo")), type: "taskItem", checked: false),
        ]]
        #expect(try markdown([tasks]) == "- [x] done\n- [ ] todo")
    }

    @Test func tablesAreSingleLinePipeTables() throws {
        func cell(_ type: String, _ paragraphs: [String: Any]...) -> [String: Any] { ["type": type, "content": paragraphs] }
        func row(_ cells: [String: Any]...) -> [String: Any] { ["type": "tableRow", "content": cells] }
        let table: [String: Any] = ["type": "table", "content": [
            row(cell("tableHeader", paragraph(text("A"))), cell("tableHeader", paragraph(text("B")))),
            row(cell("tableCell", paragraph(text("a|b"))), cell("tableCell", paragraph(text("1")), paragraph(text("2")))),
            row(cell("tableCell", paragraph(text("short")))),
        ]]
        #expect(try markdown([table]) == """
        | A | B |
        | --- | --- |
        | a\\|b | 1<br>2 |
        | short |  |
        """)
    }

    @Test func imagesKeepTheirAssetURL() throws {
        let image: [String: Any] = ["type": "image", "attrs": ["src": "notez://asset/abc", "alt": "cat", "width": 300]]
        #expect(try markdown([image]) == "![cat](notez://asset/abc)")
    }

    @Test func unknownNodesKeepTheirText() throws {
        let unknown: [String: Any] = ["type": "callout", "content": [paragraph(text("still here"))]]
        #expect(try markdown([unknown]) == "still here")
    }

    @Test func corruptDocumentsFallBackToPendingMarkdown() {
        let body = NoteBody(markdown: "pending")
        body.doc = "{not json"
        #expect(MarkdownExport.markdown(for: body) == "pending")
    }
}
