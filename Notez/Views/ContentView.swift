import SwiftData
import SwiftUI

struct ContentView: View {
    let context: ModelContext
    // Created once per window. (A `State(initialValue:)` in init would build a
    // throwaway store + web view every time SwiftUI re-inits this view.)
    @State private var store: NotesStore?

    var body: some View {
        Group {
            if let store {
                NotesWindow(store: store)
            } else {
                // Must be a real view: `onAppear` never fires on an empty Group.
                Color.clear
            }
        }
        .onAppear {
            if store == nil { store = NotesStore(context: context) }
        }
    }
}

private struct NotesWindow: View {
    @Bindable var store: NotesStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            NoteDetailView(store: store)
        }
        .onChange(of: store.selectedID) { store.selectionChanged() }
        .overlay {
            switch store.palette {
            case .quickOpen: QuickSwitcher(store: store)
            case .commands: CommandPalette(store: store)
            case nil: EmptyView()
            }
        }
        .alert(
            store.projectPrompt == .new ? "New Project" : "Rename Project",
            isPresented: Binding(
                get: { store.projectPrompt != nil },
                set: { if !$0 { store.projectPrompt = nil } }
            ),
            presenting: store.projectPrompt
        ) { prompt in
            TextField("Name", text: $store.projectName)
            Button("Cancel", role: .cancel) {}
            Button(prompt == .new ? "Create" : "Rename") { store.commitProjectPrompt(prompt) }
        }
        .focusedSceneValue(\.store, store)
    }
}
