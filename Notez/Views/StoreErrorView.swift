import SwiftUI

/// Shown instead of the app when the store can't be opened, typically a schema
/// change without a migration. Better than crashing, and never touches the data.
struct StoreErrorView: View {
    let message: String
    let backups: URL

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open your notes", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Nothing was changed. Backups from previous versions are in:")
                Text(backups.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding()
    }
}
