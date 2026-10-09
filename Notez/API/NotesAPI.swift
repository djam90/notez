import Foundation
import SwiftData

struct APIError: Error {
    let status: Int
    let message: String

    static func badRequest(_ message: String) -> APIError { APIError(status: 400, message: message) }
    static func notFound(_ what: String) -> APIError { APIError(status: 404, message: "\(what) not found") }
}

/// Note operations for AI tools, shared by the REST routes and the MCP tools.
///
/// Content goes in and out as markdown. Writes are stored in
/// `NoteBody.pendingMarkdown`, the same path seeded pages use: the editor
/// converts it to TipTap JSON the next time the page is opened, so the API
/// works with no window (and no web view) at all.
final class NotesAPI {
    typealias Args = [String: Any]

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Reads

    /// All pages depth-first in sidebar order, or the children of `parentId` ("root" = top level).
    func list(_ args: Args) throws -> Any {
        let notes: [Note]
        if let parentID = args["parentId"] {
            let parent = try parentNote(parentID)
            notes = parent?.sortedChildren ?? context.siblings(of: nil).sorted { $0.sortIndex < $1.sortIndex }
        } else {
            func walk(_ nodes: [Note]) -> [Note] { nodes.flatMap { [$0] + walk($0.sortedChildren) } }
            notes = walk(context.siblings(of: nil).sorted { $0.sortIndex < $1.sortIndex })
        }
        return ["notes": notes.map(summary)]
    }

    func search(_ args: Args) throws -> Any {
        guard let query = args["query"] as? String else { throw APIError.badRequest("query is required") }
        let limit = max(1, min(int(args["limit"]) ?? 20, 100))
        let results = context.searchNotes(query, limit: limit).map { note in
            var item = summary(note)
            if let snippet = snippet(note.body?.plainText ?? "", around: query) { item["snippet"] = snippet }
            return item
        }
        return ["results": results]
    }

    func get(_ args: Args) throws -> Any {
        try detail(note(args))
    }

    // MARK: - Writes

    func create(_ args: Args) throws -> Any {
        let parent = try args["parentId"].flatMap(parentNote)
        let top = context.siblings(of: parent).map(\.sortIndex).min() ?? 0
        let note = Note(title: try string(args, "title") ?? "", parent: parent, sortIndex: top - 1)
        note.icon = try string(args, "icon") ?? ""
        note.isPinned = args["pinned"] as? Bool ?? false
        context.insert(note)
        setMarkdown(try string(args, "markdown") ?? "", on: note, append: false)
        try context.save()
        return try detail(note)
    }

    func update(_ args: Args) throws -> Any {
        let note = try note(args)
        // Validate the move before changing anything else.
        let newParent = try args["parentId"].map(parentNote)
        if let parent = newParent ?? nil, parent.id == note.id || parent.isDescendant(of: note) {
            throw APIError.badRequest("can't move a page into itself or one of its sub-pages")
        }
        var contentChanged = false
        if let title = try string(args, "title") {
            note.title = title
            contentChanged = true
        }
        if let markdown = try string(args, "markdown") {
            setMarkdown(markdown, on: note, append: false)
            contentChanged = true
        }
        if let markdown = try string(args, "appendMarkdown") {
            setMarkdown(markdown, on: note, append: true)
            contentChanged = true
        }
        if let icon = try string(args, "icon") { note.icon = icon }
        if let pinned = args["pinned"] as? Bool { note.isPinned = pinned }
        if let newParent { context.move(note, into: newParent) }
        if contentChanged { note.updatedAt = .now }
        try context.save()
        // An open editor would otherwise overwrite this with its stale copy on the next keystroke.
        if contentChanged { NotesStore.reloadEverywhere(note.id) }
        return try detail(note)
    }

    func delete(_ args: Args) throws -> Any {
        let note = try note(args)
        func count(_ n: Note) -> Int { 1 + (n.children ?? []).map(count).reduce(0, +) }
        let deleted = count(note)
        let id = note.id.uuidString
        NotesStore.noteWillBeDeletedEverywhere(note)
        context.delete(note)
        try context.save()
        return ["deleted": id, "pagesDeleted": deleted]
    }

    func asset(_ id: String) throws -> (data: Data, mimeType: String) {
        guard let uuid = UUID(uuidString: id) else { throw APIError.badRequest("invalid asset id") }
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        guard let asset = try? context.fetch(descriptor).first, let data = asset.data else {
            throw APIError.notFound("asset")
        }
        return (data, asset.mimeType)
    }

    // MARK: - Helpers

    private func setMarkdown(_ markdown: String, on note: Note, append: Bool) {
        let body = note.body ?? {
            let b = NoteBody()
            context.insert(b)
            note.body = b
            return b
        }()
        if append {
            guard !markdown.isEmpty else { return }
            body.pendingMarkdown = [body.pendingMarkdown, markdown].filter { !$0.isEmpty }.joined(separator: "\n\n")
            body.plainText = [body.plainText, markdown].filter { !$0.isEmpty }.joined(separator: "\n")
        } else {
            body.doc = ""
            body.pendingMarkdown = markdown
            body.plainText = markdown
        }
        note.setPreview(from: body.plainText)
    }

    private func note(_ args: Args) throws -> Note {
        guard let id = args["id"] as? String else { throw APIError.badRequest("id is required") }
        guard let uuid = UUID(uuidString: id) else { throw APIError.badRequest("invalid id \(id)") }
        guard let note = context.note(uuid) else { throw APIError.notFound("page \(id)") }
        return note
    }

    /// `null`, `""` or `"root"` mean the top level.
    private func parentNote(_ value: Any) throws -> Note? {
        if value is NSNull { return nil }
        guard let id = value as? String else { throw APIError.badRequest("parentId must be a string") }
        if id.isEmpty || id == "root" { return nil }
        return try note(["id": id])
    }

    private func string(_ args: Args, _ key: String) throws -> String? {
        guard let value = args[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw APIError.badRequest("\(key) must be a string") }
        return string
    }

    private func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? String).flatMap(Int.init)
    }

    private func summary(_ note: Note) -> [String: Any] {
        [
            "id": note.id.uuidString,
            "title": note.title,
            "icon": note.icon,
            "parentId": note.parent?.id.uuidString ?? NSNull(),
            "path": note.ancestors.map(\.displayTitle).joined(separator: " / "),
            "pinned": note.isPinned,
            "childCount": note.children?.count ?? 0,
            "preview": note.preview,
            "createdAt": note.createdAt.formatted(.iso8601),
            "updatedAt": note.updatedAt.formatted(.iso8601),
        ]
    }

    private func detail(_ note: Note) throws -> [String: Any] {
        var item = summary(note)
        item["markdown"] = MarkdownExport.markdown(for: note.body)
        item["children"] = note.sortedChildren.map { ["id": $0.id.uuidString, "title": $0.title] }
        return item
    }

    private func snippet(_ text: String, around query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let start = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}
