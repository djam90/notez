#if os(macOS)
import AppKit
import SwiftUI

/// Settings > AI Access: turns the local API on and shows how to connect tools.
struct APISettingsView: View {
    @Bindable var server: APIServer
    @State private var showToken = false

    var body: some View {
        Form {
            Section {
                Toggle("Allow AI tools to read and edit notes", isOn: $server.isEnabled)
                TextField("Port", value: $server.port, format: .number.grouping(.never))
                LabeledContent("Status") { statusText }
            } footer: {
                Text("Serves an MCP server and REST API on this Mac only, while Notez is running.")
                    .foregroundStyle(.secondary)
            }

            Section("Access token") {
                HStack {
                    Text(showToken ? server.token : String(repeating: "•", count: 24))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                    Button("Copy") { copy(server.token) }
                    Button("Regenerate") { server.regenerateToken() }
                }
            }

            Section("Connect") {
                snippet("Claude Code", claudeCode)
                snippet("Claude Desktop (claude_desktop_config.json)", claudeDesktop)
                snippet("REST", rest)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var statusText: some View {
        switch server.status {
        case .running: Label("Running at \(server.baseURL)", systemImage: "circle.fill").foregroundStyle(.green)
        case .stopped: Text("Off").foregroundStyle(.secondary)
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    /// Shows the token only when revealed, but always copies the real one.
    private func snippet(_ title: String, _ text: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button("Copy") { copy(text(server.token)) }
            }
            Text(text(showToken ? server.token : "<token>"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(nil)
        }
    }

    private func claudeCode(_ token: String) -> String {
        "claude mcp add --transport http notez \(server.baseURL)/mcp --header \"Authorization: Bearer \(token)\""
    }

    private func claudeDesktop(_ token: String) -> String {
        """
        "notez": {
          "command": "npx",
          "args": ["-y", "mcp-remote", "\(server.baseURL)/mcp", "--header", "Authorization: Bearer \(token)"]
        }
        """
    }

    private func rest(_ token: String) -> String {
        "curl -H \"Authorization: Bearer \(token)\" \(server.baseURL)/api/notes"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif
