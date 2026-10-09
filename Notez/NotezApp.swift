import SwiftData
import SwiftUI

@main
struct NotezApp: App {
    let container: ModelContainer
    #if os(macOS)
    let server: APIServer
    #endif

    init() {
        // `.automatic` syncs via CloudKit once the iCloud capability is enabled
        // (see README); without it the store is purely local.
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(for: Note.self, NoteBody.self, Asset.self, Project.self, configurations: config)
        } catch {
            fatalError("Failed to open store: \(error)")
        }
        #if os(macOS)
        server = APIServer(context: container.mainContext)
        #endif
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

        #if os(macOS)
        Settings {
            TabView {
                APISettingsView(server: server)
                    .tabItem { Label("AI Access", systemImage: "sparkles") }
            }
        }
        #endif
    }
}

struct NotezCommands: Commands {
    @FocusedValue(\.store) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Page") { store?.newPage() }
                .keyboardShortcut("n")
            Button("New Sub-page") { store?.newSubnote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store?.selectedNote == nil)
            Button("New Project…") { store?.beginNewProject() }
                .keyboardShortcut("n", modifiers: [.command, .option])
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
