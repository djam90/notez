import SwiftData
import SwiftUI

struct SidebarView: View {
    @Bindable var store: NotesStore
    @Query(sort: \Note.sortIndex) private var notes: [Note]

    private var roots: [Note] { notes.filter { $0.parent == nil } }
    private var pinned: [Note] { notes.filter(\.isPinned) }

    var body: some View {
        List(selection: $store.selectedID) {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { note in
                        NoteRow(note: note, store: store)
                    }
                }
            }
            Section {
                ForEach(roots) { note in
                    NoteTree(note: note, store: store)
                }
            } header: {
                Text("Pages")
                    .dropDestination(for: String.self) { ids, _ in
                        ids.compactMap(UUID.init(uuidString:)).forEach { store.move(id: $0, into: nil) }
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
                    Button("New Page") { store.newNote() }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Quick Open", systemImage: "magnifyingglass") { store.showSwitcher = true }
            }
            ToolbarItem {
                Button("New Page", systemImage: "square.and.pencil") { store.newNote() }
            }
        }
        #if os(iOS)
        .navigationTitle("Notez")
        #endif
    }
}

/// Recursive page tree with persisted expansion state.
private struct NoteTree: View {
    let note: Note
    @Bindable var store: NotesStore

    var body: some View {
        let children = note.sortedChildren
        if children.isEmpty {
            NoteRow(note: note, store: store)
        } else {
            DisclosureGroup(isExpanded: store.isExpanded(note.id)) {
                ForEach(children) { child in
                    NoteTree(note: child, store: store)
                }
            } label: {
                NoteRow(note: note, store: store)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let store: NotesStore

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
                Button("Move to Top Level", systemImage: "arrow.up.to.line") { store.move(note, into: nil) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
        }
    }
}
