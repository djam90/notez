import SwiftUI

struct NoteDetailView: View {
    let store: NotesStore

    var body: some View {
        let note = store.selectedNote
        ZStack {
            // Always mounted so the editor is warm before the first note opens.
            EditorView(controller: store.editor)
                .opacity(note == nil ? 0 : 1)
                .ignoresSafeArea(.container, edges: .bottom)

            if note == nil {
                ContentUnavailableView {
                    Label("Nothing open", systemImage: "note.text")
                } description: {
                    Text("⌘N for a new page, ⌘K to jump to one.")
                } actions: {
                    Button("New Page") { store.newNote() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(note?.displayTitle ?? "")
        #if os(macOS)
        .navigationSubtitle(note.map { $0.ancestors.map(\.displayTitle).joined(separator: " / ") } ?? "")
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let note {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Insert Image", systemImage: "photo") { store.editor.pickImage() }
                    Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.fill" : "pin") {
                        store.togglePin(note)
                    }
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("New Sub-page", systemImage: "plus") { store.newNote(parent: note) }
                        Button("Copy as Markdown", systemImage: "doc.on.doc") {
                            Task { await store.copyMarkdown() }
                        }
                        Divider()
                        Button("Delete Page", systemImage: "trash", role: .destructive) { store.delete(note) }
                    }
                }
            }
        }
    }
}
