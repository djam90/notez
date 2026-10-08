import Foundation
import SwiftData
import SwiftUI

/// Per-window app state: selection, sidebar expansion and note mutations.
@Observable
final class NotesStore {
    let context: ModelContext
    let editor: EditorController

    var selectedID: UUID?
    var showSwitcher = false
    var expanded: Set<UUID> {
        didSet { UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedKey) }
    }

    @ObservationIgnored private var pendingFocus: EditorController.Focus = .none
    private static let expandedKey = "sidebar.expanded"
    private static let lastOpenedKey = "lastOpened"

    init(context: ModelContext) {
        self.context = context
        self.editor = EditorController(context: context)
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? []
        self.expanded = Set(saved.compactMap(UUID.init(uuidString:)))
        editor.onOpenNote = { [weak self] id in self?.open(id) }

        // Reopen where you left off (or the welcome page on first launch).
        let welcome = Seed.welcomeIfNeeded(in: context)
        let lastID = UserDefaults.standard.string(forKey: Self.lastOpenedKey).flatMap(UUID.init(uuidString:))
        if let id = welcome?.id ?? lastID, fetchNote(id) != nil {
            selectedID = id
            selectionChanged()
        }
    }

    var selectedNote: Note? {
        guard let selectedID else { return nil }
        if let current = editor.currentNote, current.id == selectedID { return current }
        return fetchNote(selectedID)
    }

    // MARK: - Navigation

    func open(_ id: UUID, focus: EditorController.Focus = .none) {
        pendingFocus = focus
        if selectedID == id {
            selectionChanged()
        } else {
            selectedID = id
        }
        revealInSidebar(id)
    }

    /// Called from the view whenever `selectedID` changes.
    func selectionChanged() {
        UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.lastOpenedKey)
        editor.load(selectedNote, focus: pendingFocus)
        pendingFocus = .none
    }

    func revealInSidebar(_ id: UUID) {
        guard let note = fetchNote(id) else { return }
        let ancestorIDs = note.ancestors.map(\.id)
        if !expanded.isSuperset(of: ancestorIDs) { expanded.formUnion(ancestorIDs) }
    }

    func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(id) },
            set: { open in
                if open { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        )
    }

    // MARK: - Mutations

    @discardableResult
    func newNote(parent: Note? = nil, title: String = "") -> Note {
        // New pages go to the top of their level so quick dumps are easy to find.
        let top = siblings(of: parent).map(\.sortIndex).min() ?? 0
        let note = Note(title: title, parent: parent, sortIndex: top - 1)
        context.insert(note)
        try? context.save()
        if let parent { expanded.insert(parent.id) }
        open(note.id, focus: title.isEmpty ? .title : .body)
        return note
    }

    func newSubnote() {
        newNote(parent: selectedNote)
    }

    func delete(_ note: Note) {
        if let selected = selectedNote, selected.id == note.id || selected.isDescendant(of: note) {
            selectedID = note.parent?.id
        }
        context.delete(note)
        try? context.save()
    }

    func togglePin(_ note: Note) {
        note.isPinned.toggle()
    }

    /// Re-parent `note` under `newParent` (nil = top level). Refuses cycles.
    func move(_ note: Note, into newParent: Note?) {
        if let newParent {
            guard newParent.id != note.id, !newParent.isDescendant(of: note) else { return }
        }
        guard note.parent?.id != newParent?.id else { return }
        let bottom = siblings(of: newParent).map(\.sortIndex).max() ?? 0
        note.parent = newParent
        note.sortIndex = bottom + 1
        if let newParent { expanded.insert(newParent.id) }
        try? context.save()
    }

    func move(id: UUID, into newParent: Note?) {
        guard let note = fetchNote(id) else { return }
        move(note, into: newParent)
    }

    func copyMarkdown() async {
        guard let markdown = await editor.markdown() else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
        #endif
    }

    // MARK: - Queries

    func fetchNote(_ id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func siblings(of parent: Note?) -> [Note] {
        if let parent { return parent.children ?? [] }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.parent == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Title matches first, then full-text body matches.
    func search(_ query: String, limit: Int = 50) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            var recent = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            recent.fetchLimit = 20
            return (try? context.fetch(recent)) ?? []
        }
        var byTitle = FetchDescriptor<Note>(
            predicate: #Predicate { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        byTitle.fetchLimit = limit
        var byBody = FetchDescriptor<NoteBody>(predicate: #Predicate { $0.plainText.localizedStandardContains(q) })
        byBody.fetchLimit = limit

        var seen = Set<UUID>()
        var results: [Note] = []
        for note in (try? context.fetch(byTitle)) ?? [] where seen.insert(note.id).inserted {
            results.append(note)
        }
        for body in (try? context.fetch(byBody)) ?? [] {
            if let note = body.note, seen.insert(note.id).inserted { results.append(note) }
        }
        return Array(results.prefix(limit))
    }
}

extension FocusedValues {
    @Entry var store: NotesStore?
}
