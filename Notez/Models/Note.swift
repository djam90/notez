import Foundation
import SwiftData

// All properties have defaults and all relationships are optional so the
// schema stays compatible with SwiftData's CloudKit sync.

/// Lightweight page metadata. Kept small on purpose: the sidebar queries every
/// note, so heavy content lives in `NoteBody` and is only faulted in on open.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = ""
    var preview: String = ""
    var isPinned: Bool = false
    var sortIndex: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var parent: Note?
    /// Only set on top-level pages. Sub-pages follow their root (`rootProject`).
    var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \Note.parent)
    var children: [Note]? = []

    @Relationship(deleteRule: .cascade, inverse: \NoteBody.note)
    var body: NoteBody?

    @Relationship(deleteRule: .cascade, inverse: \Asset.note)
    var assets: [Asset]? = []

    init(title: String = "", parent: Note? = nil, sortIndex: Double = 0) {
        self.title = title
        self.parent = parent
        self.sortIndex = sortIndex
    }

    var displayTitle: String { title.isEmpty ? "Untitled" : title }

    func setPreview(from text: String) {
        preview = String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }

    var sortedChildren: [Note] {
        (children ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Root-to-self chain, used for breadcrumbs.
    var ancestors: [Note] {
        var chain: [Note] = []
        var node = parent
        while let n = node {
            chain.insert(n, at: 0)
            node = n.parent
        }
        return chain
    }

    var rootProject: Project? { (ancestors.first ?? self).project }

    /// "Project / Parent / …" for subtitles. Excludes the page itself.
    var location: String {
        let chain = ancestors
        let project = (chain.first ?? self).project.map { [$0.displayName] } ?? []
        return (project + chain.map(\.displayTitle)).joined(separator: " / ")
    }

    func isDescendant(of other: Note) -> Bool {
        var node = parent
        while let n = node {
            if n.id == other.id { return true }
            node = n.parent
        }
        return false
    }
}

/// A named group of top-level pages, shown as its own sidebar section.
@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol name and a `ProjectStyle.colors` key ("" = default tint).
    var icon: String = "folder"
    var color: String = ""
    var sortIndex: Double = 0
    var createdAt: Date = Date()

    // Deleting a project keeps its pages, they drop back to the unfiled list.
    @Relationship(deleteRule: .nullify, inverse: \Note.project)
    var notes: [Note]? = []

    init(name: String, sortIndex: Double = 0) {
        self.name = name
        self.sortIndex = sortIndex
    }

    var displayName: String { name.isEmpty ? "Untitled Project" : name }
}

/// The editor document (TipTap JSON) plus plain text for search.
@Model
final class NoteBody {
    var doc: String = ""
    var plainText: String = ""
    /// Markdown awaiting conversion by the editor (seeded/imported notes).
    /// Cleared once the editor saves the converted document.
    var pendingMarkdown: String = ""
    var note: Note?

    init(markdown: String = "") {
        self.pendingMarkdown = markdown
        self.plainText = markdown
    }
}

/// An embedded image. Stored outside the SQLite file and served to the editor
/// via `notez://asset/<id>`.
@Model
final class Asset {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data?
    var mimeType: String = "image/png"
    var createdAt: Date = Date()
    var note: Note?

    init(data: Data, mimeType: String, note: Note?) {
        self.data = data
        self.mimeType = mimeType
        self.note = note
    }
}
