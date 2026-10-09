import SwiftUI

/// ⌘K: fuzzy-ish jump to any page by title or content, or create one.
/// An in-window overlay rather than a sheet: sheets animate in and out, and
/// jumping to a page has to feel instant.
struct QuickSwitcher: View {
    let store: NotesStore
    @State private var query = ""
    @State private var results: [Note] = []
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var showCreate: Bool {
        !trimmed.isEmpty && !results.contains { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
    private var rowCount: Int { results.count + (showCreate ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to or create a page…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(choose)
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                    #if os(iOS)
                    .submitLabel(.go)
                    #endif
            }
            .padding(14)

            Divider()

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                        row(index: index) {
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
                        }
                    }
                    if showCreate {
                        row(index: results.count) {
                            Label("Create “\(trimmed)”", systemImage: "plus")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
        }
        .frame(maxWidth: 560)
        .frame(height: 380)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // Click outside to dismiss.
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
        }
        .onAppear {
            results = store.search("")
            fieldFocused = true
        }
        .onChange(of: query) {
            results = store.search(query)
            highlighted = 0
        }
    }

    private func row(index: Int, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowBackground(index == highlighted ? Color.accentColor.opacity(0.18) : .clear)
            .id(index)
            .onTapGesture {
                highlighted = index
                choose()
            }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard rowCount > 0 else { return .handled }
        highlighted = (highlighted + delta + rowCount) % rowCount
        return .handled
    }

    private func dismiss() {
        store.showSwitcher = false
    }

    private func choose() {
        if highlighted < results.count {
            store.open(results[highlighted].id)
        } else if showCreate {
            store.newPage(title: trimmed)
        }
        dismiss()
    }
}
