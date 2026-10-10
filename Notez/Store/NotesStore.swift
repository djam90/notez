import Foundation
import SwiftData
import SwiftUI

/// Per-window app state: selection, sidebar expansion and note mutations.
@Observable
final class NotesStore {
    let context: ModelContext
    let editor: EditorController

    var selectedID: UUID?
    enum Palette { case quickOpen, commands }
    /// The ⌘K / ⇧⌘K overlay showing, if any.
    var palette: Palette?
    var expanded: Set<UUID> {
        didSet { UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedKey) }
    }
    var collapsedProjects: Set<UUID> {
        didSet { UserDefaults.standard.set(collapsedProjects.map(\.uuidString), forKey: Self.collapsedProjectsKey) }
    }

    enum ProjectPrompt: Equatable {
        case new
        case rename(Project)
    }
    /// Drives the new/rename project alert. `projectName` is its text field.
    var projectPrompt: ProjectPrompt?
    var projectName = ""

    @ObservationIgnored private var pendingFocus: EditorController.Focus = .none
    private static let expandedKey = "sidebar.expanded"
    private static let collapsedProjectsKey = "sidebar.collapsedProjects"
    private static let lastOpenedKey = "lastOpened"
    /// Every open window, so changes made outside the editor (the local API) reach them.
    private static let windows = NSHashTable<NotesStore>.weakObjects()

    init(context: ModelContext) {
        self.context = context
        self.editor = EditorController(context: context)
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? []
        self.expanded = Set(saved.compactMap(UUID.init(uuidString:)))
        let collapsed = UserDefaults.standard.stringArray(forKey: Self.collapsedProjectsKey) ?? []
        self.collapsedProjects = Set(collapsed.compactMap(UUID.init(uuidString:)))
        editor.onOpenNote = { [weak self] id in self?.open(id) }
        Self.windows.add(self)

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
        if let project = note.rootProject { reveal(project) }
    }

    private func reveal(_ project: Project) {
        if collapsedProjects.contains(project.id) { collapsedProjects.remove(project.id) }
    }

    /// The shortcut for an open palette closes it, the other one swaps to it.
    func togglePalette(_ kind: Palette) {
        palette = palette == kind ? nil : kind
    }

    func collapseAll() {
        expanded = []
    }

    func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(id) },
            set: { open in
                if open { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        )
    }

    func isProjectExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !self.collapsedProjects.contains(id) },
            set: { open in
                if open { self.collapsedProjects.remove(id) } else { self.collapsedProjects.insert(id) }
            }
        )
    }

    // MARK: - Mutations

    /// Sub-pages ignore `project`, they belong to their root's project.
    @discardableResult
    func newNote(parent: Note? = nil, in project: Project? = nil, title: String = "") -> Note {
        // New pages go to the top of their level so quick dumps are easy to find.
        let top = context.siblings(of: parent).map(\.sortIndex).min() ?? 0
        let note = Note(title: title, parent: parent, sortIndex: top - 1)
        if parent == nil { note.project = project }
        context.insert(note)
        try? context.save()
        if let parent { expanded.insert(parent.id) }
        open(note.id, focus: title.isEmpty ? .title : .body)
        return note
    }

    /// A top-level page in the open page's project, like a new note in the current folder.
    func newPage(title: String = "") {
        newNote(in: selectedNote?.rootProject, title: title)
    }

    func newSubnote() {
        newNote(parent: selectedNote)
    }

    func delete(_ note: Note) {
        noteWillBeDeleted(note)
        context.delete(note)
        try? context.save()
    }

    /// Moves selection off `note` or its subtree before it is deleted.
    private func noteWillBeDeleted(_ note: Note) {
        if let selected = selectedNote, selected.id == note.id || selected.isDescendant(of: note) {
            selectedID = note.parent?.id
        }
    }

    func togglePin(_ note: Note) {
        note.isPinned.toggle()
    }

    /// Re-parent `note` under `newParent`, or to the top level of `project`
    /// (nil = unfiled) when `newParent` is nil. Refuses cycles.
    func move(_ note: Note, into newParent: Note?, project: Project? = nil) {
        guard context.move(note, into: newParent, project: project) else { return }
        if let newParent { expanded.insert(newParent.id) }
        if newParent == nil, let project { reveal(project) }
        try? context.save()
    }

    func move(id: UUID, into newParent: Note?, project: Project? = nil) {
        guard let note = fetchNote(id) else { return }
        move(note, into: newParent, project: project)
    }

    // MARK: - Projects

    func beginNewProject() {
        projectName = ""
        projectPrompt = .new
    }

    func beginRename(_ project: Project) {
        projectName = project.name
        projectPrompt = .rename(project)
    }

    /// Takes the prompt as captured by the alert, since dismissal may clear `projectPrompt` first.
    func commitProjectPrompt(_ prompt: ProjectPrompt) {
        projectPrompt = nil
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch prompt {
        case .new:
            let bottom = allProjects().last?.sortIndex ?? 0
            context.insert(Project(name: name, sortIndex: bottom + 1))
        case .rename(let project):
            project.name = name
        }
        try? context.save()
    }

    func setIcon(_ icon: String, for project: Project) {
        project.icon = icon
        try? context.save()
    }

    func setColor(_ color: String, for project: Project) {
        project.color = color
        try? context.save()
    }

    /// Places `project` just before `target`, or last when `target` is nil.
    func moveProject(_ project: Project, before target: Project?) {
        context.moveProject(project, before: target)
        try? context.save()
    }

    /// Swaps `project` with its neighbour (-1 = up, 1 = down).
    func moveProject(_ project: Project, by offset: Int) {
        var ordered = allProjects()
        guard let i = ordered.firstIndex(where: { $0.id == project.id }),
              ordered.indices.contains(i + offset) else { return }
        ordered.swapAt(i, i + offset)
        context.renumber(ordered)
        try? context.save()
    }

    func moveProject(id: UUID, before target: Project?) {
        guard let project = allProjects().first(where: { $0.id == id }) else { return }
        moveProject(project, before: target)
    }

    func delete(_ project: Project) {
        context.deleteProject(project)
        try? context.save()
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

    func fetchNote(_ id: UUID) -> Note? { context.note(id) }

    func search(_ query: String, limit: Int = 50) -> [Note] { context.searchNotes(query, limit: limit) }

    // MARK: - External changes

    /// Reloads `id` in any window that has it open, after its content changed outside the editor.
    static func reloadEverywhere(_ id: UUID) {
        for store in windows.allObjects where store.editor.currentNote?.id == id {
            store.editor.load(store.editor.currentNote)
        }
    }

    static func noteWillBeDeletedEverywhere(_ note: Note) {
        for store in windows.allObjects { store.noteWillBeDeleted(note) }
    }

    func allProjects() -> [Project] { context.projects() }
}

// Shared by window stores and the local API, which runs without a window.
extension ModelContext {
    func note(_ id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func siblings(of parent: Note?) -> [Note] {
        if let parent { return parent.children ?? [] }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.parent == nil })
        return (try? fetch(descriptor)) ?? []
    }

    /// Re-parents `note` to the bottom of `newParent`, or to the top level of
    /// `project` (nil = unfiled) when `newParent` is nil. Sub-pages carry no
    /// project, they follow their root. Returns false for no-ops and cycles.
    @discardableResult
    func move(_ note: Note, into newParent: Note?, project: Project? = nil) -> Bool {
        if let newParent {
            guard newParent.id != note.id, !newParent.isDescendant(of: note) else { return false }
        }
        let newProject = newParent == nil ? project : nil
        guard note.parent?.id != newParent?.id || note.project?.id != newProject?.id else { return false }
        let bottom = siblings(of: newParent).map(\.sortIndex).max() ?? 0
        note.parent = newParent
        note.project = newProject
        note.sortIndex = bottom + 1
        return true
    }

    func projects() -> [Project] {
        (try? fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    /// Places `project` just before `target`, or last when `target` is nil.
    func moveProject(_ project: Project, before target: Project?) {
        guard project.id != target?.id else { return }
        var ordered = projects().filter { $0.id != project.id }
        let index = target.flatMap { t in ordered.firstIndex { $0.id == t.id } } ?? ordered.count
        ordered.insert(project, at: index)
        renumber(ordered)
    }

    func renumber(_ ordered: [Project]) {
        for (i, project) in ordered.enumerated() where project.sortIndex != Double(i) {
            project.sortIndex = Double(i)
        }
    }

    /// Keeps the project's pages, they become unfiled.
    func deleteProject(_ project: Project) {
        for note in project.notes ?? [] { note.project = nil }
        delete(project)
    }

    /// Title matches first, then full-text body matches.
    func searchNotes(_ query: String, limit: Int = 50) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            var recent = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            recent.fetchLimit = min(limit, 20)
            return (try? fetch(recent)) ?? []
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
        for note in (try? fetch(byTitle)) ?? [] where seen.insert(note.id).inserted {
            results.append(note)
        }
        for body in (try? fetch(byBody)) ?? [] {
            if let note = body.note, seen.insert(note.id).inserted { results.append(note) }
        }
        return Array(results.prefix(limit))
    }
}

extension FocusedValues {
    @Entry var store: NotesStore?
}
