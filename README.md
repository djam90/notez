# Notez

Fast, native notes for macOS, iPadOS and iOS. Notion-style nested pages, proper tables, embedded images, quick capture.

## Architecture

```
Notez/                 SwiftUI app (one multiplatform target: Mac + iPhone + iPad)
  Models/              SwiftData models: Note (metadata), Project, NoteBody (document), Asset (images), versioned Schema
  Store/               NotesStore: selection, tree ops, search. Seed: welcome page
  Views/               Sidebar tree, detail, ⌘K quick switcher, ⌘⇧K command palette
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
scripts/run-mac.sh             # build + launch "Notez Dev" on Mac (separate data)
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

## Releasing (your everyday copy)

```sh
scripts/release-mac.sh 0.3.0
```

This bumps the version and build number, builds Release, quits the installed app, copies your data to `~/Notez-backups/<date>-before-v0.3.0/`, installs `/Applications/Notez.app`, commits "Release v0.3.0" and tags `v0.3.0`. The working tree must be clean.

- **Dev vs real data:** Debug builds are a separate app, "Notez Dev" (`io.github.djam90.notez.dev`), with their own data. Trying out a work-in-progress build never touches your real notes.
- **Data location:** `~/Library/Containers/io.github.djam90.notez/Data/Library/Application Support/` (`default.store*` plus `.default_SUPPORT/` for large images). It belongs to the bundle ID, so replacing the app keeps it.
- **Automatic backups:** on the first launch of a new version, the app copies its store to `Backups/` in that folder before opening it, and keeps the last 5.
- **If a version can't open your data**, it shows an error screen instead of starting. Nothing is changed. To restore, quit the app and copy a backup's files back over `default.store*`.
- **Signing prompt:** builds are ad-hoc signed, so after an update macOS may ask whether Notez can access data from other apps. Allow it. Setting a Team in Xcode stops this.

## Enable iCloud sync

1. Target > Signing & Capabilities: pick your Team.
2. Add **iCloud** capability, tick **CloudKit**, add a container (e.g. `iCloud.io.github.djam90.notez`).
3. Add **Background Modes > Remote notifications** (iOS).

`ModelConfiguration(cloudKitDatabase: .automatic)` picks it up; no code changes. Without it, data is local only.

## Features

This list must match the current build. Every commit that adds or changes a feature updates it (see CLAUDE.md). Details and verification status are in [docs/FEATURES.md](docs/FEATURES.md).

**Pages**
- Nested pages to any depth. Drag to re-nest, pin, delete (cascades to sub-pages, no trash yet)
- Sidebar expansion persists, and the app reopens the last page
- Welcome page on first launch

**Projects**
- Group top-level pages into projects, each a collapsible sidebar section. Unfiled pages live under **Pages**
- Each project has an icon and colour (right-click the header). Colours show in the sidebar and in menus
- Reorder by dragging headers or with Move Up/Down. File pages by dragging, or with **Move to Project** in the row menu or the page ⋯ menu
- New pages go into the open page's project. Deleting a project keeps its pages

**Navigation**
- `⌘K` palette: instant jump by title or full text, or create a page from the query
- `⌘⇧K` command palette: run any action by name (new page/project, pin, move to project, copy markdown, delete, settings…)
- Breadcrumb subtitle on Mac (Project / Parent / …)

**Editor**
- `/` command menu, markdown shortcuts, pasting markdown converts to rich text
- Formatting bubble (Mac/iPad pointer), links (⌘-click to open), task lists, highlight, code blocks, quotes
- Tables: resizable columns, header toggle, merge/split, row/col controls
- Images: paste, drop, `⌘⇧I`, or `/image` (camera/photos on iOS), resizable
- Autosave (300 ms debounce, flushed on switch/background). Copy page as Markdown

**AI access (Mac)**
- Local MCP server and REST API so Claude and other AI tools can list, search, read, create, edit, move and delete pages, and list, create, rename, restyle, reorder, delete and file into projects, while Notez runs. Off by default, loopback only, bearer token. Settings (`⌘,`) > AI Access. See [docs/API.md](docs/API.md)

**Data safety**
- Dev builds ("Notez Dev", red DEV Dock badge) have separate data from the installed app
- Versioned schema, a backup on each version upgrade, an error screen instead of a crash if data can't be opened
- `scripts/release-mac.sh` for versioned installs with a backup

**Shortcuts**

| Action | Keys |
| --- | --- |
| New page / sub-page / project | `⌘N` / `⌘⇧N` / `⌘⌥N` |
| Quick open | `⌘K` |
| Command palette | `⌘⇧K` |
| Insert image | `⌘⇧I` |
| Pin / unpin page | `⌘⇧D` |
| Delete page | `⌘⇧⌫` |
| Copy page as Markdown | `⌘⌥C` |

## Ideas next

- Image upload through the API
- Global quick-capture hotkey / menu bar extra on Mac, Share Extension + widget on iOS
- `[[` page links (the `notez://note/<id>` route already opens notes)
- Orphaned image cleanup, trash/undo delete, markdown folder export

## License

MIT, see [LICENSE](LICENSE).
