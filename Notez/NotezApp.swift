import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct NotezApp: App {
    let container: ModelContainer?
    let storeURL: URL
    let storeError: String?
    #if os(macOS)
    let server: APIServer?
    #endif

    init() {
        #if os(macOS)
        // Unit tests run inside this app. Keep it out of the Dock and from taking focus.
        if AppLaunch.isHostingUnitTests { NSApplication.shared.setActivationPolicy(.prohibited) }
        #endif
        // `.automatic` syncs via CloudKit once the iCloud capability is enabled
        // (see README); without it the store is purely local.
        let schema = Schema(versionedSchema: NotezSchema.self)
        let config = AppLaunch.isTesting
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        storeURL = config.url
        if !AppLaunch.isTesting { StoreBackup.backUpIfVersionChanged(storeURL: config.url) }
        do {
            container = try ModelContainer(
                for: schema, migrationPlan: NotezMigrationPlan.self, configurations: config
            )
            storeError = nil
        } catch {
            print("[store] failed to open: \(error)")
            container = nil
            storeError = String(describing: error)
        }
        #if os(macOS)
        server = AppLaunch.isTesting ? nil : container.map { APIServer(context: $0.mainContext) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView(context: container.mainContext)
                    .modelContainer(container)
            } else {
                StoreErrorView(message: storeError ?? "", backups: StoreBackup.folder(for: storeURL))
            }
        }
        #if DEBUG && os(macOS)
        // The dev build looks identical to the installed app in the Dock otherwise.
        .onChange(of: true, initial: true) { NSApp.dockTile.badgeLabel = "DEV" }
        #endif
        .commands { NotezCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif

        #if os(macOS)
        Settings {
            TabView {
                if let server {
                    APISettingsView(server: server)
                        .tabItem { Label("AI Access", systemImage: "sparkles") }
                }
            }
        }
        #endif
    }
}

/// Test runs share the dev app's bundle ID, so without this they would open
/// its store, change its settings and fight it for the API port.
enum AppLaunch {
    /// Hosting unit tests, or launched by a UI test (`-ui-testing`).
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.arguments.contains("-ui-testing")

    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        && !ProcessInfo.processInfo.arguments.contains("-ui-testing")

    /// Settings for window state and the welcome seed. Tests start from empty ones.
    static let defaults: UserDefaults = {
        guard isTesting, let suite = UserDefaults(suiteName: "notez.tests") else { return .standard }
        suite.removePersistentDomain(forName: "notez.tests")
        return suite
    }()
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
            Button("Quick Open…") { store?.togglePalette(.quickOpen) }
                .keyboardShortcut("k")
            Button("Command Palette…") { store?.togglePalette(.commands) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
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
