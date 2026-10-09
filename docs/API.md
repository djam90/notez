# Local API and MCP server (macOS)

While Notez is running on a Mac, it can serve your notes to AI tools such as Claude: an MCP server at `/mcp` and a REST API under `/api`. Both run in the app process on top of the same SwiftData store the UI uses, so changes show up in the sidebar straight away.

## Turning it on

**Notez > Settings… > AI Access**, then tick **Allow AI tools to read and edit notes**. It is off by default.

- Listens on `127.0.0.1:6683` (configurable; Notez Dev defaults to 6684). The listener is restricted to the loopback interface, so other machines can't connect.
- Every request needs `Authorization: Bearer <token>`. The token is generated on first launch, shown in Settings and can be regenerated (old clients then get 401).
- Requests with an `Origin` header that isn't `localhost`/`127.0.0.1` are rejected with 403 (DNS rebinding guard, as the MCP spec requires).
- iOS and iPadOS don't run the server: there are no local AI tools there to talk to, and the app would be suspended in the background anyway.

Settings shows ready-to-copy snippets with your token filled in:

```sh
# Claude Code
claude mcp add --transport http notez http://127.0.0.1:6683/mcp --header "Authorization: Bearer <token>"
```

```json
// Claude Desktop (claude_desktop_config.json > mcpServers), bridged through mcp-remote
"notez": {
  "command": "npx",
  "args": ["-y", "mcp-remote", "http://127.0.0.1:6683/mcp", "--header", "Authorization: Bearer <token>"]
}
```

## Content format

Bodies go in and out as **GitHub-flavoured markdown**: headings, lists, task lists (`- [ ] ` / `- [x] `), tables, code blocks, quotes, `==highlight==`, links and images.

- **Reads** convert the stored TipTap JSON with `MarkdownExport` (Swift, mirrors `@tiptap/markdown`'s output so it parses back to the same document). Underline, image sizes and merged cells don't survive markdown.
- **Writes** go into `NoteBody.pendingMarkdown`, the same path seeded pages use. The editor converts it to TipTap JSON the next time the page is opened (rule 6: JSON stays the source of truth). `markdown` replaces the body (`doc` is cleared). `appendMarkdown` is added to `pendingMarkdown`, and the editor appends it to the existing document on open, so append is lossless. `plainText` and `preview` are updated immediately so search works before conversion.
- If a window has the page open, it is reloaded (`NotesStore.reloadEverywhere`). Otherwise the editor's next save would overwrite the API write with its stale copy. The API version wins over keystrokes typed in the last 300 ms.
- Images are referenced as `notez://asset/<uuid>`. Fetch the bytes with `GET /api/assets/<uuid>`. There is no image upload through the API yet.

## MCP

Streamable HTTP transport, JSON responses only (no SSE stream, no sessions). `GET /mcp` returns 405. Notifications get `202 Accepted`. Supports `initialize`, `ping`, `tools/list` and `tools/call`. The server sends `instructions` that explain the page model and markdown conventions.

| Tool | Arguments | Notes |
| --- | --- | --- |
| `list_notes` | `parentId?`, `projectId?` | No `parentId`: every page depth-first in sidebar order. `"root"`: top-level pages only. `projectId` limits either to one project (`"none"` = unfiled). |
| `list_projects` | | `{projects: [project], unfiledPageCount}` in sidebar order. |
| `create_project` | `name`, `icon?`, `color?` | Goes to the bottom of the sidebar. `icon`/`color` must be `ProjectStyle` values (the error lists them). |
| `search_notes` | `query`, `limit?` (20, max 100) | Title matches, then full text. Each result has a `snippet`. Empty query = recently edited. |
| `get_note` | `id` | Metadata + `markdown` + direct `children`. |
| `create_note` | `title`, `markdown?`, `parentId?`, `projectId?`, `icon?`, `pinned?` | New pages go to the top of their level. `projectId` files a new top-level page. |
| `update_note` | `id`, `title?`, `markdown?`, `appendMarkdown?`, `parentId?`, `projectId?`, `icon?`, `pinned?` | Only given fields change. `parentId` moves the page (`"root"` = top level, keeping its project). `projectId` moves it to the top level of that project (`"none"` = unfiled). Cycles and `parentId` + `projectId` together are rejected before anything changes. |
| `delete_note` | `id` | Deletes the page, its sub-pages and images. Marked `destructiveHint`. |

Tool results carry both `structuredContent` and the same JSON as text. Failures come back as `isError: true` results with a message.

## REST

All responses are JSON. Errors are `{"error": "message"}` with a 4xx/5xx status.

| Method and path | Body / query | Returns |
| --- | --- | --- |
| `GET /api/notes` | `?parentId=<id>\|root&projectId=<id>\|none` | `{notes: [summary]}` |
| `GET /api/projects` | | `{projects: [project], unfiledPageCount}` |
| `POST /api/projects` | `{name, icon?, color?}` | `201` project |
| `GET /api/search` | `?q=…&limit=…` | `{results: [summary + snippet]}` |
| `GET /api/notes/<id>` | | detail |
| `POST /api/notes` | `{title, markdown?, parentId?, projectId?, icon?, pinned?}` | `201` detail |
| `PATCH /api/notes/<id>` | `{title?, markdown?, appendMarkdown?, parentId?, projectId?, icon?, pinned?}` | detail |
| `DELETE /api/notes/<id>` | | `{deleted, pagesDeleted}` |
| `GET /api/assets/<id>` | | image bytes with their MIME type |

A **summary** is `id, title, icon, parentId, projectId, project` (the top-level page's project id and name, or null), `path` (ancestor titles joined with ` / `), `pinned, childCount, preview, createdAt, updatedAt` (ISO 8601). A **detail** adds `markdown` and `children: [{id, title}]`. A **project** is `id, name, icon, color, pageCount` (top-level pages).

**Projects.** Only top-level pages carry a project; sub-pages report their root's. That's why `parentId` and `projectId` can't be combined.

```sh
TOKEN=…   # from Settings
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:6683/api/search?q=groceries
curl -H "Authorization: Bearer $TOKEN" -X POST http://127.0.0.1:6683/api/notes \
  -d '{"title":"Ideas","markdown":"- [ ] write the API docs"}'
```

## Code

| File | Role |
| --- | --- |
| `Notez/API/NotesAPI.swift` | Operations shared by REST and MCP. Takes JSON dictionaries, returns JSON-ready dictionaries, throws `APIError(status, message)`. |
| `Notez/API/MCPHandler.swift` | JSON-RPC dispatch and tool definitions. |
| `Notez/API/APIServer.swift` | macOS only. `NWListener` on loopback, minimal HTTP/1.1 (`Content-Length` bodies, `Connection: close`), auth, Origin check, routing. `@Observable` settings persisted in `UserDefaults` (`api.enabled`, `api.port`, `api.token`). Created once in `NotezApp.init`, so it runs with no windows open. |
| `Notez/API/MarkdownExport.swift` | TipTap JSON to markdown. |
| `Notez/Views/APISettingsView.swift` | Settings > AI Access. |

Everything runs on the main actor against `container.mainContext`, the same context the windows use. The sandbox entitlement comes from `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES`.

## Limitations

- Projects can be listed, created and filed into, but not renamed, restyled, reordered or deleted through the API yet.
