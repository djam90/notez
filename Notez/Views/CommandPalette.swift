import SwiftData
import SwiftUI

/// ⇧⌘K: run any app action by name. Commands that need a page only appear
/// while one is open.
struct CommandPalette: View {
    let store: NotesStore
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var query = ""
    @State private var highlighted = 0

    struct Command: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var shortcut = ""
        /// Extra words to match on, beyond the title.
        var keywords = ""
        var destructive = false
        let run: () -> Void
    }

    var body: some View {
        let matches = filtered(commands)
        PalettePanel(
            prompt: "Run a command…",
            query: $query,
            highlighted: $highlighted,
            rowCount: matches.count,
            choose: { choose(matches) },
            dismiss: { store.palette = nil }
        ) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                HStack {
                    Label(command.title, systemImage: command.symbol)
                        .foregroundStyle(command.destructive ? .red : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text(command.shortcut).foregroundStyle(.secondary)
                }
                .paletteRow(index, highlighted: $highlighted, choose: { choose(matches) })
            }
            if matches.isEmpty {
                Text("No matching commands").foregroundStyle(.secondary)
            }
        }
    }

    private func choose(_ matches: [Command]) {
        guard matches.indices.contains(highlighted) else { return }
        // Close first so commands that open other UI (⌘K, the project alert) aren't covered.
        store.palette = nil
        matches[highlighted].run()
    }

    /// Every query word must appear in the title or keywords. Titles that
    /// start with the query rank first.
    private func filtered(_ commands: [Command]) -> [Command] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        let words = q.split(separator: " ").map(String.init)
        let matching = commands.filter { command in
            let haystack = command.title + " " + command.keywords
            return words.allSatisfy { haystack.localizedStandardContains($0) }
        }
        let prefixed = matching.filter { $0.title.lowercased().hasPrefix(q.lowercased()) }
        return prefixed + matching.filter { !$0.title.lowercased().hasPrefix(q.lowercased()) }
    }

    private var commands: [Command] {
        var list: [Command] = [
            Command(id: "new", title: "New Page", symbol: "square.and.pencil", shortcut: "⌘N", keywords: "create add note") {
                store.newPage()
            },
        ]
        let note = store.selectedNote
        if let note {
            list.append(Command(id: "newSub", title: "New Sub-page", symbol: "plus", shortcut: "⇧⌘N", keywords: "create add child nested") {
                store.newSubnote()
            })
        }
        for project in projects {
            list.append(Command(id: "new-\(project.id)", title: "New Page in \(project.displayName)", symbol: project.icon, keywords: "create add project") {
                store.newNote(in: project)
            })
        }
        list += [
            Command(id: "newProject", title: "New Project…", symbol: "folder.badge.plus", shortcut: "⌥⌘N", keywords: "create add group folder") {
                store.beginNewProject()
            },
            Command(id: "open", title: "Quick Open…", symbol: "magnifyingglass", shortcut: "⌘K", keywords: "jump go search find switch") {
                store.palette = .quickOpen
            },
        ]

        if let note {
            list += [
                Command(id: "pin", title: note.isPinned ? "Unpin Page" : "Pin Page", symbol: note.isPinned ? "pin.slash" : "pin", shortcut: "⇧⌘D", keywords: "favourite favorite") {
                    store.togglePin(note)
                },
                Command(id: "image", title: "Insert Image…", symbol: "photo", shortcut: "⇧⌘I", keywords: "picture photo upload") {
                    store.editor.pickImage()
                },
                Command(id: "copy", title: "Copy Page as Markdown", symbol: "doc.on.doc", shortcut: "⌥⌘C", keywords: "export clipboard") {
                    Task { await store.copyMarkdown() }
                },
            ]
            if let parent = note.parent {
                list += [
                    Command(id: "parent", title: "Go to Parent Page", symbol: "arrow.turn.left.up", keywords: "up back \(parent.displayTitle)") {
                        store.open(parent.id)
                    },
                    Command(id: "topLevel", title: "Move to Top Level", symbol: "arrow.up.to.line", keywords: "unnest") {
                        store.move(note, into: nil, project: note.rootProject)
                    },
                ]
            }
            for project in projects where note.parent != nil || note.project?.id != project.id {
                list.append(Command(id: "move-\(project.id)", title: "Move to \(project.displayName)", symbol: "folder", keywords: "project file") {
                    store.move(note, into: nil, project: project)
                })
            }
            if note.parent == nil, note.project != nil {
                list.append(Command(id: "unfile", title: "Remove from Project", symbol: "doc.text", keywords: "no project unfile move") {
                    store.move(note, into: nil)
                })
            }
            if let project = note.rootProject {
                list.append(Command(id: "renameProject", title: "Rename Project “\(project.displayName)”…", symbol: "pencil") {
                    store.beginRename(project)
                })
            }
        }

        list.append(Command(id: "collapse", title: "Collapse All Pages", symbol: "list.bullet.indent", keywords: "sidebar fold tree") {
            store.collapseAll()
        })
        #if os(macOS)
        list.append(Command(id: "settings", title: "Settings…", symbol: "gear", shortcut: "⌘,", keywords: "preferences ai access api mcp") {
            openSettings()
        })
        #endif

        // Last, so it is never the default highlight.
        if let note {
            list.append(Command(id: "delete", title: "Delete Page", symbol: "trash", shortcut: "⇧⌘⌫", keywords: "remove trash", destructive: true) {
                store.delete(note)
            })
        }
        return list
    }
}
