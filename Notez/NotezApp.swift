import SwiftData
import SwiftUI

@main
struct NotezApp: App {
    let container: ModelContainer

    init() {
        // `.automatic` syncs via CloudKit once the iCloud capability is enabled
        // (see README); without it the store is purely local.
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(for: Note.self, NoteBody.self, Asset.self, configurations: config)
        } catch {
            fatalError("Failed to open store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(context: container.mainContext)
        }
        .modelContainer(container)
        .commands { NotezCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}

struct NotezCommands: Commands {
    @FocusedValue(\.store) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Page") { store?.newNote() }
                .keyboardShortcut("n")
            Button("New Sub-page") { store?.newSubnote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store?.selectedNote == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Page as Markdown") { Task { await store?.copyMarkdown() } }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(store?.selectedNote == nil)
        }
        CommandMenu("Go") {
            Button("Quick Open…") { store?.showSwitcher = true }
                .keyboardShortcut("k")
        }
        CommandMenu("Page") {
            Button("Insert Image…") { store?.editor.pickImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(store?.selectedNote == nil)
            Button(store?.selectedNote?.isPinned == true ? "Unpin" : "Pin") {
                if let note = store?.selectedNote { store?.togglePin(note) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(store?.selectedNote == nil)
            Divider()
            Button("Delete Page", role: .destructive) {
                if let note = store?.selectedNote { store?.delete(note) }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(store?.selectedNote == nil)
        }
    }
}
