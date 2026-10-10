import SwiftUI

/// ⌘K: fuzzy-ish jump to any page by title or content, or create one.
struct QuickSwitcher: View {
    let store: NotesStore
    @State private var query = ""
    @State private var results: [Note] = []
    @State private var highlighted = 0

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var showCreate: Bool {
        !trimmed.isEmpty && !results.contains { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        PalettePanel(
            prompt: "Jump to or create a page…",
            query: $query,
            highlighted: $highlighted,
            rowCount: results.count + (showCreate ? 1 : 0),
            choose: choose,
            dismiss: { store.palette = nil }
        ) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle).lineLimit(1)
                    let path = note.location
                    if !path.isEmpty || !note.preview.isEmpty {
                        Text(path.isEmpty ? note.preview : path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .paletteRow(index, highlighted: $highlighted, choose: choose)
            }
            if showCreate {
                Label("Create “\(trimmed)”", systemImage: "plus")
                    .paletteRow(results.count, highlighted: $highlighted, choose: choose)
            }
        }
        .onAppear { results = store.search("") }
        .onChange(of: query) { results = store.search(query) }
    }

    private func choose() {
        store.palette = nil
        if highlighted < results.count {
            store.open(results[highlighted].id)
        } else if showCreate {
            store.newPage(title: trimmed)
        }
    }
}
