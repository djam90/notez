import Foundation
import SwiftData
import Testing
@testable import Notez

/// The native half of the bridge. The async tests run the real bundled
/// editor (`Resources/editor.html`) in an off-screen web view, so they also
/// catch a stale or broken editor build.
@Suite struct EditorBridgeTests {
    let store: TestStore
    let editor: EditorController
    init() throws {
        store = try TestStore()
        editor = EditorController(context: store.context)
    }

    static let richMarkdown = """
    # Heading

    Some **bold**, *italic*, ~~strike~~, `code`, ==highlight== and a [link](https://example.com).

    - one
      - nested
    - two

    1. first
    2. second

    - [x] done
    - [ ] todo

    > quoted

    ```swift
    let x = 1
    ```

    | A | B |
    | --- | --- |
    | 1 | 2 |

    ---

    Groceries at the end
    """

    // MARK: - Messages from the editor

    @Test func changeMessagesSaveThePage() {
        let note = store.note("Old", updatedAt: .distantPast)
        note.body = NoteBody(markdown: "pending")
        editor.handle([
            "type": "change", "id": note.id.uuidString, "title": "New",
            "doc": #"{"type":"doc"}"#, "text": "hello\nworld",
        ])
        #expect(note.title == "New")
        #expect(note.body?.doc == #"{"type":"doc"}"#)
        #expect(note.body?.pendingMarkdown == "", "converted markdown must not be applied twice")
        #expect(note.body?.plainText == "hello\nworld")
        #expect(note.preview == "hello world")
        #expect(note.updatedAt > .distantPast)
    }

    @Test func changeCreatesAMissingBody() {
        let note = store.note("No body")
        editor.handle(["type": "change", "id": note.id.uuidString, "title": "No body", "doc": "{}", "text": "x"])
        #expect(note.body?.doc == "{}")
    }

    @Test func junkMessagesAreIgnored() {
        let note = store.note("Untouched")
        editor.handle(["type": "change", "id": UUID().uuidString, "title": "x", "doc": "{}", "text": ""])
        editor.handle(["type": "change", "id": "not-a-uuid"])
        editor.handle(["type": "nonsense"])
        editor.handle(["no": "type"])
        editor.handle("not a dictionary")
        #expect(note.title == "Untouched")
        #expect(store.count(NoteBody.self) == 0)
    }

    @Test func uploadsBecomeAssetsOfTheOpenPage() throws {
        let note = store.note("Page")
        editor.load(note)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        editor.handle(["type": "uploadImage", "requestId": "r1", "base64": png.base64EncodedString(), "mime": "image/jpeg"])
        let asset = try #require(try store.context.fetch(FetchDescriptor<Asset>()).first)
        #expect(asset.data == png)
        #expect(asset.mimeType == "image/jpeg")
        #expect(asset.note?.id == note.id)

        editor.handle(["type": "uploadImage", "requestId": "r2", "base64": "%%% not base64"])
        #expect(store.count(Asset.self) == 1)
    }

    // MARK: - The real editor

    @Test func bundledEditorStartsUp() async throws {
        try await waitUntil("the editor to send ready") { editor.isReady }
    }

    @Test func openingAPageConvertsItsPendingMarkdown() async throws {
        let note = try await openConverted(Self.richMarkdown)
        let doc = try #require(try JSONSerialization.jsonObject(with: Data(note.body!.doc.utf8)) as? [String: Any])
        let types = Set(nodeTypes(doc))
        for type in ["heading", "bulletList", "orderedList", "taskList", "blockquote", "codeBlock", "table", "horizontalRule"] {
            #expect(types.contains(type), "\(type) missing from \(types.sorted())")
        }
        #expect(note.body?.plainText.contains("Groceries at the end") == true)
        #expect(!note.body!.doc.contains("data:"), "images must never be inlined as base64")
    }

    /// The API reads pages through `MarkdownExport`, the editor through its own
    /// serializer. They must agree or AI edits would rewrite content.
    @Test func swiftAndEditorMarkdownAgree() async throws {
        let note = try await openConverted(Self.richMarkdown)
        let fromEditor = try #require(await editor.markdown())
        // The editor's export (Copy as Markdown) starts with the title, the API returns it separately.
        let title = "# \(note.title)\n\n"
        #expect(fromEditor.hasPrefix(title))
        let editorLines = normalized(String(fromEditor.dropFirst(title.count))).components(separatedBy: "\n")
        let swiftLines = normalized(MarkdownExport.markdown(for: note.body)).components(separatedBy: "\n")
        for i in 0..<max(editorLines.count, swiftLines.count) {
            let e = i < editorLines.count ? editorLines[i] : "<missing>"
            let s = i < swiftLines.count ? swiftLines[i] : "<missing>"
            #expect(s == e, "line \(i + 1): swift \(s.debugDescription), editor \(e.debugDescription)")
        }
    }

    /// What an AI tool does: read a page as markdown, write it back unchanged.
    /// The page must come out as the same document.
    @Test func apiMarkdownRoundTripsThroughTheEditor() async throws {
        let original = try await openConverted(Self.richMarkdown)
        let exported = MarkdownExport.markdown(for: original.body)
        let reimported = try await openConverted(exported)
        let before = try JSONSerialization.jsonObject(with: Data(original.body!.doc.utf8)) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: Data(reimported.body!.doc.utf8)) as? NSDictionary
        #expect(before != nil)
        #expect(before == after)
    }

    /// Whitespace-only differences: the editor pads table columns and puts
    /// extra blank lines around tables.
    private func normalized(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n")
            .map { $0.hasPrefix("|") ? $0.replacing(/\ {2,}/, with: " ") : $0 }
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openConverted(_ markdown: String) async throws -> Note {
        let note = store.note("Rich")
        note.body = NoteBody(markdown: markdown)
        editor.load(note)
        try await waitUntil("the editor to convert and save the markdown") {
            note.body?.pendingMarkdown.isEmpty == true && note.body?.doc.isEmpty == false
        }
        return note
    }

    private func nodeTypes(_ node: [String: Any]) -> [String] {
        let children = node["content"] as? [[String: Any]] ?? []
        return [node["type"] as? String ?? ""] + children.flatMap(nodeTypes)
    }
}
