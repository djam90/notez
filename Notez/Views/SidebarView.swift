import SwiftData
import SwiftUI

struct SidebarView: View {
    @Bindable var store: NotesStore
    @Query(sort: \Note.sortIndex) private var notes: [Note]
    @Query(sort: \Project.sortIndex) private var projects: [Project]

    private var pinned: [Note] { notes.filter(\.isPinned) }

    var body: some View {
        let rootsByProject = Dictionary(grouping: notes.filter { $0.parent == nil }) { $0.project?.id }
        List(selection: $store.selectedID) {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { note in
                        NoteRow(note: note, store: store, projects: projects)
                    }
                }
            }
            ForEach(projects) { project in
                ProjectSection(project: project, roots: rootsByProject[project.id] ?? [], store: store, projects: projects)
            }
            Section {
                ForEach(rootsByProject[nil] ?? []) { note in
                    NoteTree(note: note, store: store, projects: projects)
                }
            } header: {
                Text("Pages")
                    .dropDestination(for: String.self) { items, _ in
                        for item in items {
                            if let id = projectID(item) {
                                store.moveProject(id: id, before: nil)
                            } else if let id = UUID(uuidString: item) {
                                store.move(id: id, into: nil)
                            }
                        }
                        return true
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("No pages yet", systemImage: "square.and.pencil")
                } actions: {
                    Button("New Page") { store.newPage() }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Quick Open", systemImage: "magnifyingglass") { store.showSwitcher = true }
            }
            ToolbarItem {
                Button("New Project", systemImage: "folder.badge.plus") { store.beginNewProject() }
            }
            ToolbarItem {
                Button("New Page", systemImage: "square.and.pencil") { store.newPage() }
            }
        }
        #if os(iOS)
        .navigationTitle("Notez")
        #endif
    }
}

/// Project drags carry this prefix so page drop targets (which parse a bare UUID) ignore them.
private let projectDragPrefix = "project:"

private func projectID(_ item: String) -> UUID? {
    guard item.hasPrefix(projectDragPrefix) else { return nil }
    return UUID(uuidString: String(item.dropFirst(projectDragPrefix.count)))
}

/// A collapsible section holding one project's top-level pages.
private struct ProjectSection: View {
    let project: Project
    let roots: [Note]
    @Bindable var store: NotesStore
    let projects: [Project]

    var body: some View {
        Section(isExpanded: store.isProjectExpanded(project.id)) {
            ForEach(roots) { note in
                NoteTree(note: note, store: store, projects: projects)
            }
            if roots.isEmpty {
                Button("New Page", systemImage: "plus") { store.newNote(in: project) }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        } header: {
            Label {
                Text(project.displayName)
            } icon: {
                Image(systemName: project.icon).foregroundStyle(ProjectStyle.color(project.color))
            }
            .draggable(projectDragPrefix + project.id.uuidString)
            // Dropping a project here places it above this one, dropping a page files it here.
            .dropDestination(for: String.self) { items, _ in
                for item in items {
                    if let id = projectID(item) {
                        store.moveProject(id: id, before: project)
                    } else if let id = UUID(uuidString: item) {
                        store.move(id: id, into: nil, project: project)
                    }
                }
                return true
            }
            .contextMenu {
                Button("New Page", systemImage: "plus") { store.newNote(in: project) }
                Button("Rename…", systemImage: "pencil") { store.beginRename(project) }
                ProjectStyleMenu(project: project, store: store)
                Divider()
                Button("Move Up", systemImage: "arrow.up") { store.moveProject(project, by: -1) }
                    .disabled(projects.first?.id == project.id)
                Button("Move Down", systemImage: "arrow.down") { store.moveProject(project, by: 1) }
                    .disabled(projects.last?.id == project.id)
                Divider()
                Button("Delete Project", systemImage: "trash", role: .destructive) { store.delete(project) }
            }
        }
    }
}

/// Recursive page tree with persisted expansion state.
private struct NoteTree: View {
    let note: Note
    @Bindable var store: NotesStore
    let projects: [Project]

    var body: some View {
        let children = note.sortedChildren
        if children.isEmpty {
            NoteRow(note: note, store: store, projects: projects)
        } else {
            DisclosureGroup(isExpanded: store.isExpanded(note.id)) {
                ForEach(children) { child in
                    NoteTree(note: child, store: store, projects: projects)
                }
            } label: {
                NoteRow(note: note, store: store, projects: projects)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let store: NotesStore
    let projects: [Project]

    var body: some View {
        Label {
            Text(note.displayTitle)
                .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        } icon: {
            if note.icon.isEmpty {
                Image(systemName: "doc.text")
            } else {
                Text(note.icon)
            }
        }
        .tag(note.id)
        .draggable(note.id.uuidString)
        .dropDestination(for: String.self) { ids, _ in
            ids.compactMap(UUID.init(uuidString:)).forEach { store.move(id: $0, into: note) }
            return true
        }
        .contextMenu {
            Button("New Sub-page", systemImage: "plus") { store.newNote(parent: note) }
            Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                store.togglePin(note)
            }
            if note.parent != nil {
                Button("Move to Top Level", systemImage: "arrow.up.to.line") {
                    store.move(note, into: nil, project: note.rootProject)
                }
            }
            MoveToProjectMenu(note: note, store: store, projects: projects)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
        }
    }
}
