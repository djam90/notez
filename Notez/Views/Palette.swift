import SwiftUI

/// The search field, result list, keyboard handling and floating panel shared
/// by ⌘K (QuickSwitcher) and ⇧⌘K (CommandPalette). An in-window overlay rather
/// than a sheet: sheets animate in and out, and these have to feel instant.
struct PalettePanel<Rows: View>: View {
    let prompt: String
    @Binding var query: String
    @Binding var highlighted: Int
    let rowCount: Int
    let choose: () -> Void
    let dismiss: () -> Void
    @ViewBuilder let rows: () -> Rows
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .accessibilityIdentifier("palette.query")
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
                List { rows() }
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
        .onAppear { fieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard rowCount > 0 else { return .handled }
        highlighted = (highlighted + delta + rowCount) % rowCount
        return .handled
    }
}

extension View {
    /// A clickable palette row at `index` that shows the keyboard highlight.
    func paletteRow(_ index: Int, highlighted: Binding<Int>, choose: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowBackground(index == highlighted.wrappedValue ? Color.accentColor.opacity(0.18) : .clear)
            .id(index)
            .onTapGesture {
                highlighted.wrappedValue = index
                choose()
            }
    }
}
