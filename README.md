# Notez

Fast, native notes for macOS, iPadOS and iOS. Notion-style nested pages, proper tables, embedded images, quick capture.

## Architecture

```
Notez/                 SwiftUI app (one multiplatform target: Mac + iPhone + iPad)
  Models/              SwiftData models: Note (metadata), NoteBody (document), Asset (images)
  Store/               NotesStore: selection, tree ops, search. Seed: welcome page
  Views/               Sidebar tree, detail, ⌘K quick switcher
  Editor/              Persistent WKWebView + notez:// scheme handler + JS bridge
  Resources/editor.html  Built editor bundle (generated, committed)
editor/                TipTap editor (vanilla TS, Vite, single-file build)
scripts/               setup / build / run helpers
docs/                  Features and architecture docs
```

Why this shape:

- **Native shell** for everything you click (sidebar, switcher, menus, shortcuts), so navigation is instant.
- **One long-lived web view** for the editor. Switching notes is a JS call, not a page load. Native text views can't do good tables on iOS; TipTap/ProseMirror can.
- **SwiftData + CloudKit** for storage and free sync between Mac/iPhone/iPad. The sidebar only loads small `Note` rows; document JSON lives in `NoteBody` and is faulted in on open.
- **Images** are stored as SwiftData external blobs and served to the editor via `notez://asset/<id>`, never base64 in the document.

## Develop

```sh
open Notez.xcodeproj           # pick "My Mac" or an iOS simulator, ⌘R
# or
scripts/run-mac.sh             # build + launch on Mac
scripts/run-sim.sh             # build + launch on iPhone sim (SIM_NAME=... to change)
```

Editor changes:

```sh
scripts/setup.sh               # npm ci (once per clone/worktree)
cd editor && npm run dev       # iterate in a browser at /editor.html (mock host, localStorage)
scripts/build.sh editor        # writes Notez/Resources/editor.html - commit it with your change
```

Docs: [docs/FEATURES.md](docs/FEATURES.md) (every feature + how it's built), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (design, data model, bridge), [docs/API.md](docs/API.md) (local MCP/REST API), [CLAUDE.md](CLAUDE.md) (rules for agents).

In Debug builds the web view is inspectable from Safari > Develop. JS errors are forwarded to the Xcode console as `[editor] ...`.

## Enable iCloud sync

1. Target > Signing & Capabilities: pick your Team.
2. Add **iCloud** capability, tick **CloudKit**, add a container (e.g. `iCloud.io.github.djam90.notez`).
3. Add **Background Modes > Remote notifications** (iOS).

`ModelConfiguration(cloudKitDatabase: .automatic)` picks it up; no code changes. Without it, data is local only.

## Features

- Nested pages, drag to re-nest, pin, persisted expansion, reopens last page
- `/` command menu, markdown shortcuts, pasting markdown converts to rich text
- Tables: resizable columns, header toggle, merge/split, row/col controls
- Images: paste, drop, `⌘⇧I`, or `/image` (camera/photos on iOS), resizable
- Task lists, highlight, code blocks, quotes, links (⌘-click to open)
- `⌘N` new page, `⌘⇧N` sub-page, `⌘K` jump/create, `⌘⌥C` copy as Markdown
- MCP server + REST API on the Mac so Claude and other AI tools can manage notes (Settings > AI Access, see [docs/API.md](docs/API.md))

## Ideas next

- Global quick-capture hotkey / menu bar extra on Mac, Share Extension + widget on iOS
- `[[` page links (the `notez://note/<id>` route already opens notes)
- Orphaned image cleanup, trash/undo delete, markdown folder export
